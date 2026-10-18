using System;
using System.Diagnostics;
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace MudRunner.Rendering
{
    /// <summary>
    /// Procedural texture set of the ground shader. Everything is generated in code (Burst jobs, tileable):
    ///  * <see cref="Albedo"/>  Texture2DArray, 8 slices (Rock, FirmSoil, Grass, Gravel, ShallowMud, DeepMud, Bog, Sand), RGBA32 sRGB:
    ///    rgb = albedo, a = smoothness. Mipmaps on, aniso 8.
    ///  * <see cref="Normal"/>  Texture2DArray, 8 slices, RGBA32 linear: rg = tangent-space normal xy (0.5 + 0.5*n), b = height (for height-blend), a = 1.
    ///    Tangent space = world (u = +X, v = +Z) for the top-down projection.
    ///  * <see cref="Macro"/>   tileable 4-channel low-frequency variation (RGBA32 linear).
    ///  * <see cref="DetailNormal"/> tileable fine-grain normal map (rg).
    /// </summary>
    public sealed class GroundTextures : IDisposable
    {
        public const int LayerCount = 8;
        public const int DefaultSize = 1024;
        public const int MacroSize = 512;
        public const int DetailSize = 512;

        /// <summary>Per-layer normal-map relief (height gradient per texel -> slope). Tuned by eye.</summary>
        static readonly float[] ReliefTable = { 52f, 38f, 34f, 62f, 26f, 22f, 16f, 28f };

        public Texture2DArray Albedo { get; private set; }
        public Texture2DArray Normal { get; private set; }
        public Texture2D Macro { get; private set; }
        public Texture2D DetailNormal { get; private set; }
        public int Size { get; private set; }
        public float GenerationMs { get; private set; }

        /// <summary>Debug only: keep CPU copies of the generated textures (texture atlas dumps). Set before the first use of <see cref="Shared"/>.</summary>
        public static bool DebugKeepReadable;

        static GroundTextures shared;
        /// <summary>Lazily generated shared instance (1024^2 x 8). Survives GroundRenderer rebuilds.</summary>
        public static GroundTextures Shared
        {
            get
            {
                if (shared == null || shared.Albedo == null) shared = Generate(DefaultSize, DebugKeepReadable);
                return shared;
            }
        }

        // ------------------------------------------------------------------ jobs

        [BurstCompile(CompileSynchronously = true, FloatMode = FloatMode.Fast, FloatPrecision = FloatPrecision.Standard)]
        struct LayerJob : IJobParallelFor
        {
            public int layer;
            public int size;
            [NativeDisableParallelForRestriction] public NativeArray<float4> albedoSm;
            [NativeDisableParallelForRestriction] public NativeArray<float> height;

            public void Execute(int y)
            {
                float inv = 1f / size;
                int row = y * size;
                for (int x = 0; x < size; x++)
                {
                    float2 uv = new float2((x + 0.5f) * inv, (y + 0.5f) * inv);
                    float3 c; float sm, h;
                    switch (layer)
                    {
                        case 0: GroundPatterns.Rock(uv, out c, out sm, out h); break;
                        case 1: GroundPatterns.FirmSoil(uv, out c, out sm, out h); break;
                        case 2: GroundPatterns.Grass(uv, out c, out sm, out h); break;
                        case 3: GroundPatterns.Gravel(uv, out c, out sm, out h); break;
                        case 4: GroundPatterns.ShallowMud(uv, out c, out sm, out h); break;
                        case 5: GroundPatterns.DeepMud(uv, out c, out sm, out h); break;
                        case 6: GroundPatterns.Bog(uv, out c, out sm, out h); break;
                        default: GroundPatterns.Sand(uv, out c, out sm, out h); break;
                    }
                    albedoSm[row + x] = new float4(math.saturate(c), math.saturate(sm));
                    height[row + x] = h;
                }
            }
        }

        [BurstCompile(CompileSynchronously = true, FloatMode = FloatMode.Fast)]
        struct PackJob : IJobParallelFor
        {
            public int size;
            public float relief;
            [ReadOnly] public NativeArray<float4> albedoSm;
            [ReadOnly] public NativeArray<float> height;
            [NativeDisableParallelForRestriction] public NativeArray<byte> albedoOut;   // RGBA32
            [NativeDisableParallelForRestriction] public NativeArray<byte> normalOut;   // RGBA32

            public void Execute(int y)
            {
                int mask = size - 1;
                int ym = ((y - 1) & mask) * size, yp = ((y + 1) & mask) * size, row = y * size;
                for (int x = 0; x < size; x++)
                {
                    int xm = (x - 1) & mask, xp = (x + 1) & mask;
                    float dx = (height[row + xp] - height[row + xm]) * 0.5f;
                    float dy = (height[yp + x] - height[ym + x]) * 0.5f;
                    float3 n = math.normalize(new float3(-dx * relief, -dy * relief, 1f));
                    int i = (row + x) * 4;
                    float4 a = albedoSm[row + x];
                    albedoOut[i + 0] = (byte)(a.x * 255f + 0.5f);
                    albedoOut[i + 1] = (byte)(a.y * 255f + 0.5f);
                    albedoOut[i + 2] = (byte)(a.z * 255f + 0.5f);
                    albedoOut[i + 3] = (byte)(a.w * 255f + 0.5f);
                    normalOut[i + 0] = (byte)(math.saturate(n.x * 0.5f + 0.5f) * 255f + 0.5f);
                    normalOut[i + 1] = (byte)(math.saturate(n.y * 0.5f + 0.5f) * 255f + 0.5f);
                    normalOut[i + 2] = (byte)(math.saturate(height[row + x]) * 255f + 0.5f);
                    normalOut[i + 3] = 255;
                }
            }
        }

        [BurstCompile(CompileSynchronously = true, FloatMode = FloatMode.Fast)]
        struct MacroJob : IJobParallelFor
        {
            public int size;
            [NativeDisableParallelForRestriction] public NativeArray<byte> output;
            public void Execute(int y)
            {
                float inv = 1f / size;
                for (int x = 0; x < size; x++)
                {
                    float4 m = GroundPatterns.Macro(new float2((x + 0.5f) * inv, (y + 0.5f) * inv));
                    int i = (y * size + x) * 4;
                    output[i + 0] = (byte)(m.x * 255f + 0.5f);
                    output[i + 1] = (byte)(m.y * 255f + 0.5f);
                    output[i + 2] = (byte)(m.z * 255f + 0.5f);
                    output[i + 3] = (byte)(m.w * 255f + 0.5f);
                }
            }
        }

        [BurstCompile(CompileSynchronously = true, FloatMode = FloatMode.Fast)]
        struct DetailHeightJob : IJobParallelFor
        {
            public int size;
            [NativeDisableParallelForRestriction] public NativeArray<float> height;
            public void Execute(int y)
            {
                float inv = 1f / size;
                for (int x = 0; x < size; x++)
                    height[y * size + x] = GroundPatterns.DetailHeight(new float2((x + 0.5f) * inv, (y + 0.5f) * inv));
            }
        }

        [BurstCompile(CompileSynchronously = true, FloatMode = FloatMode.Fast)]
        struct DetailNormalJob : IJobParallelFor
        {
            public int size;
            [ReadOnly] public NativeArray<float> height;
            [NativeDisableParallelForRestriction] public NativeArray<byte> output;
            public void Execute(int y)
            {
                int mask = size - 1;
                int ym = ((y - 1) & mask) * size, yp = ((y + 1) & mask) * size, row = y * size;
                for (int x = 0; x < size; x++)
                {
                    int xm = (x - 1) & mask, xp = (x + 1) & mask;
                    float dx = (height[row + xp] - height[row + xm]) * 0.5f;
                    float dy = (height[yp + x] - height[ym + x]) * 0.5f;
                    float3 n = math.normalize(new float3(-dx * 14f, -dy * 14f, 1f));
                    int i = (row + x) * 4;
                    output[i + 0] = (byte)(math.saturate(n.x * 0.5f + 0.5f) * 255f + 0.5f);
                    output[i + 1] = (byte)(math.saturate(n.y * 0.5f + 0.5f) * 255f + 0.5f);
                    output[i + 2] = 255;
                    output[i + 3] = 255;
                }
            }
        }

        // ------------------------------------------------------------------ generation

        /// <summary>Generate all textures. <paramref name="keepReadable"/> keeps CPU copies (debug dumps only).</summary>
        public static GroundTextures Generate(int size = DefaultSize, bool keepReadable = false)
        {
            var sw = Stopwatch.StartNew();
            var t = new GroundTextures { Size = size };
            int n = size * size;

            t.Albedo = new Texture2DArray(size, size, LayerCount, TextureFormat.RGBA32, true, false)
            {
                name = "MR_Ground_AlbedoSmooth", wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 8,
            };
            t.Normal = new Texture2DArray(size, size, LayerCount, TextureFormat.RGBA32, true, true)
            {
                name = "MR_Ground_NormalHeight", wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 8,
            };

            var albedoSm = new NativeArray<float4>(n, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            var height = new NativeArray<float>(n, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            var albedoBytes = new NativeArray<byte>(n * 4, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            var normalBytes = new NativeArray<byte>(n * 4, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            try
            {
                for (int layer = 0; layer < LayerCount; layer++)
                {
                    var job = new LayerJob { layer = layer, size = size, albedoSm = albedoSm, height = height };
                    job.Schedule(size, 4).Complete();
                    var pack = new PackJob
                    {
                        size = size, relief = ReliefTable[layer] * (size / 1024f),
                        albedoSm = albedoSm, height = height, albedoOut = albedoBytes, normalOut = normalBytes,
                    };
                    pack.Schedule(size, 8).Complete();
                    t.Albedo.SetPixelData(albedoBytes, 0, layer);
                    t.Normal.SetPixelData(normalBytes, 0, layer);
                }
            }
            finally
            {
                albedoSm.Dispose(); height.Dispose(); albedoBytes.Dispose(); normalBytes.Dispose();
            }
            t.Albedo.Apply(true, !keepReadable);
            t.Normal.Apply(true, !keepReadable);

            // macro variation
            var macroBytes = new NativeArray<byte>(MacroSize * MacroSize * 4, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            new MacroJob { size = MacroSize, output = macroBytes }.Schedule(MacroSize, 8).Complete();
            t.Macro = new Texture2D(MacroSize, MacroSize, TextureFormat.RGBA32, true, true)
            {
                name = "MR_Ground_Macro", wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 2,
            };
            t.Macro.SetPixelData(macroBytes, 0);
            t.Macro.Apply(true, !keepReadable);
            macroBytes.Dispose();

            // detail normal
            var dh = new NativeArray<float>(DetailSize * DetailSize, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            var dn = new NativeArray<byte>(DetailSize * DetailSize * 4, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            new DetailHeightJob { size = DetailSize, height = dh }.Schedule(DetailSize, 8).Complete();
            new DetailNormalJob { size = DetailSize, height = dh, output = dn }.Schedule(DetailSize, 8).Complete();
            t.DetailNormal = new Texture2D(DetailSize, DetailSize, TextureFormat.RGBA32, true, true)
            {
                name = "MR_Ground_DetailNormal", wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 4,
            };
            t.DetailNormal.SetPixelData(dn, 0);
            t.DetailNormal.Apply(true, !keepReadable);
            dh.Dispose(); dn.Dispose();

            sw.Stop();
            t.GenerationMs = (float)sw.Elapsed.TotalMilliseconds;
            Debug.Log("[MudRunner] GroundTextures generated: " + size + "x" + size + " x" + LayerCount + " layers in " + t.GenerationMs.ToString("F0") + " ms");
            return t;
        }

        public void Dispose()
        {
            DestroyTex(Albedo); DestroyTex(Normal); DestroyTex(Macro); DestroyTex(DetailNormal);
            Albedo = null; Normal = null; Macro = null; DetailNormal = null;
            if (shared == this) shared = null;
        }

        static void DestroyTex(UnityEngine.Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) UnityEngine.Object.Destroy(o); else UnityEngine.Object.DestroyImmediate(o);
        }
    }
}
