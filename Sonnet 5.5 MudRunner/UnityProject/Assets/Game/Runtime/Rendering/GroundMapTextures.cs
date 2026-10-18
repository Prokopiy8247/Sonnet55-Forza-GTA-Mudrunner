using System;
using System.Runtime.InteropServices;
using Unity.Burst;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;
using MudRunner.Ground;

namespace MudRunner.Rendering
{
    /// <summary>GPU copies of a <see cref="GroundMap"/>: height (R32F), macro normal (RGHalf), 2 control maps (RGBA8), params (RG8).</summary>
    public sealed class GroundMapTextures : IDisposable
    {
        public Texture2D Height { get; private set; }
        public Texture2D NormalMap { get; private set; }
        public Texture2D Control0 { get; private set; }
        public Texture2D Control1 { get; private set; }
        public Texture2D Params { get; private set; }

        [BurstCompile(CompileSynchronously = true, FloatMode = FloatMode.Fast)]
        struct NormalJob : IJobParallelFor
        {
            public int size;
            public float invCell;
            [ReadOnly] public NativeArray<float> height;
            [NativeDisableParallelForRestriction] public NativeArray<ushort> output;   // RGHalf: nx, nz

            float H(int x, int z)
            {
                x = math.clamp(x, 0, size - 1); z = math.clamp(z, 0, size - 1);
                return height[z * size + x];
            }

            public void Execute(int z)
            {
                for (int x = 0; x < size; x++)
                {
                    // 3x3 Sobel: smooth, avoids 1 m facets when the map is sampled bilinearly
                    float gx = 0f, gz = 0f;
                    for (int j = -1; j <= 1; j++)
                    {
                        float wj = j == 0 ? 2f : 1f;
                        gx += wj * (H(x + 1, z + j) - H(x - 1, z + j));
                        gz += wj * (H(x + j, z + 1) - H(x + j, z - 1));
                    }
                    gx *= 0.125f * invCell;     // / (4 weights * 2 cells)
                    gz *= 0.125f * invCell;
                    float3 n = math.normalize(new float3(-gx, 1f, -gz));
                    int o = (z * size + x) * 2;
                    output[o] = (ushort)math.f32tof16(n.x);
                    output[o + 1] = (ushort)math.f32tof16(n.z);
                }
            }
        }

        public static GroundMapTextures Create(GroundMap map)
        {
            var t = new GroundMapTextures();
            int size = map.size;
            int n = size * size;

            // height
            t.Height = new Texture2D(size, size, TextureFormat.RFloat, false, true)
            {
                name = "MR_Ground_Height", wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear,
            };
            t.Height.SetPixelData(map.height, 0);
            t.Height.Apply(false, true);

            // macro normal
            var hNative = new NativeArray<float>(map.height, Allocator.TempJob);
            var nOut = new NativeArray<ushort>(n * 2, Allocator.TempJob, NativeArrayOptions.UninitializedMemory);
            new NormalJob { size = size, invCell = 1f / map.cell, height = hNative, output = nOut }.Schedule(size, 4).Complete();
            t.NormalMap = new Texture2D(size, size, TextureFormat.RGHalf, false, true)
            {
                name = "MR_Ground_MacroNormal", wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear,
            };
            t.NormalMap.SetPixelData(nOut, 0);
            t.NormalMap.Apply(false, true);
            hNative.Dispose(); nOut.Dispose();

            // control maps: layers 0..3 and 4..7 are interleaved bytes, 8 bytes per cell == 2 uints per cell
            var c0 = new uint[n];
            var c1 = new uint[n];
            ReadOnlySpan<uint> w = MemoryMarshal.Cast<byte, uint>(map.weights.AsSpan());
            for (int i = 0; i < n; i++) { c0[i] = w[2 * i]; c1[i] = w[2 * i + 1]; }
            t.Control0 = MakeTex(size, TextureFormat.RGBA32, "MR_Ground_Control0");
            t.Control0.SetPixelData(c0, 0); t.Control0.Apply(false, true);
            t.Control1 = MakeTex(size, TextureFormat.RGBA32, "MR_Ground_Control1");
            t.Control1.SetPixelData(c1, 0); t.Control1.Apply(false, true);

            // params: R = extraDepth, G = baseWet
            var pr = new ushort[n];
            for (int i = 0; i < n; i++) pr[i] = (ushort)(map.extraDepth[i] | (map.baseWet[i] << 8));
            t.Params = MakeTex(size, TextureFormat.RG16, "MR_Ground_Params");
            t.Params.SetPixelData(pr, 0); t.Params.Apply(false, true);
            return t;
        }

        static Texture2D MakeTex(int size, TextureFormat fmt, string name)
        {
            return new Texture2D(size, size, fmt, false, true)
            {
                name = name, wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear,
            };
        }

        public void Dispose()
        {
            Kill(Height); Kill(NormalMap); Kill(Control0); Kill(Control1); Kill(Params);
            Height = NormalMap = Control0 = Control1 = Params = null;
        }

        static void Kill(UnityEngine.Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) UnityEngine.Object.Destroy(o); else UnityEngine.Object.DestroyImmediate(o);
        }
    }
}
