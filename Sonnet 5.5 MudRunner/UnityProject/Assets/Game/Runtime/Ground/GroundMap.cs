using System;
using UnityEngine;

namespace MudRunner.Ground
{
    /// <summary>
    /// Static, compact description of the world ground: macro height field plus per-cell surface data.
    /// Everything is flat arrays (no per-object nodes). The physical terrain collider, the visual ground
    /// renderer and the wheel-soil model are all built from / query this one data set.
    ///
    /// Grid: <see cref="size"/> x <see cref="size"/> samples, spacing <see cref="cell"/> metres, world XZ of
    /// sample (0,0) is <see cref="origin"/>. Index = z * size + x.
    /// </summary>
    public sealed class GroundMap
    {
        public const int LayerCount = (int)SurfaceType.Count;     // 8 surface layers
        public const float MaxExtraDepth = 2.0f;                  // byte 255 in extraDepth => +2 m of soft layer
        public const float MaxRelax = 0.1f;                       // byte 255 in fluidity => 0.1 1/s

        public readonly int size;
        public readonly float cell;
        public readonly Vector2 origin;

        public readonly float[] height;       // metres
        public readonly byte[] weights;       // size*size*8 surface layer weights (0..255), expected to sum ~255
        public readonly byte[] extraDepth;    // hidden extra soft-layer depth painted by the designer
        public readonly byte[] baseWet;       // base wetness 0..1 (wet ground, standing water margin)
        public readonly byte[] fluidity;      // derived: how fast ruts relax (see SurfaceParams.rutRelaxRate)

        /// <summary>Optional water layer (rivers, ponds, swamp water). Null when the map has no water.</summary>
        public WaterMap water;

        public float minHeight { get; private set; }
        public float maxHeight { get; private set; }

        public float WorldSize => (size - 1) * cell;
        public Vector2 Min => origin;
        public Vector2 Max => origin + new Vector2(WorldSize, WorldSize);
        public Vector2 Center => origin + new Vector2(WorldSize * 0.5f, WorldSize * 0.5f);

        public GroundMap(int size, float cell, Vector2 origin)
        {
            if (size < 3) throw new ArgumentException("size");
            this.size = size;
            this.cell = cell;
            this.origin = origin;
            int n = size * size;
            height = new float[n];
            weights = new byte[n * LayerCount];
            extraDepth = new byte[n];
            baseWet = new byte[n];
            fluidity = new byte[n];
            // default: firm soil everywhere
            for (int i = 0; i < n; i++) weights[i * LayerCount + (int)SurfaceType.FirmSoil] = 255;
        }

        public bool Contains(float x, float z)
        {
            return x >= origin.x && z >= origin.y && x <= origin.x + WorldSize && z <= origin.y + WorldSize;
        }

        // ------------------------------------------------------------------ construction helpers

        public int Index(int ix, int iz) => iz * size + ix;

        public void WorldToGrid(float x, float z, out float gx, out float gz)
        {
            gx = (x - origin.x) / cell;
            gz = (z - origin.y) / cell;
        }

        public Vector2 GridToWorld(int ix, int iz) => new Vector2(origin.x + ix * cell, origin.y + iz * cell);

        public void SetWeights(int ix, int iz, SurfaceType dominant)
        {
            int o = Index(ix, iz) * LayerCount;
            for (int k = 0; k < LayerCount; k++) weights[o + k] = 0;
            weights[o + (int)dominant] = 255;
        }

        /// <summary>Set weights from a float array of 8 values (normalised internally).</summary>
        public void SetWeights(int ix, int iz, ReadOnlySpan<float> w)
        {
            float sum = 0f;
            for (int k = 0; k < LayerCount; k++) sum += Mathf.Max(0f, w[k]);
            if (sum < 1e-5f) { SetWeights(ix, iz, SurfaceType.FirmSoil); return; }
            int o = Index(ix, iz) * LayerCount;
            float inv = 255f / sum;
            int total = 0;
            int best = 0; float bestW = -1f;
            for (int k = 0; k < LayerCount; k++)
            {
                float v = Mathf.Max(0f, w[k]);
                if (v > bestW) { bestW = v; best = k; }
                int b = Mathf.Clamp(Mathf.RoundToInt(v * inv), 0, 255);
                weights[o + k] = (byte)b; total += b;
            }
            // fix rounding so the dominant layer carries the remainder
            int fix = 255 - total;
            weights[o + best] = (byte)Mathf.Clamp(weights[o + best] + fix, 0, 255);
        }

        /// <summary>Call once after filling height/weights: computes min/max height and derived per-cell data.</summary>
        public void Finalize_()
        {
            float mn = float.MaxValue, mx = float.MinValue;
            for (int i = 0; i < height.Length; i++)
            {
                float h = height[i];
                if (h < mn) mn = h;
                if (h > mx) mx = h;
            }
            minHeight = mn; maxHeight = mx;
            RebuildFluidity();
        }

        public void RebuildFluidity()
        {
            Span<float> relax = stackalloc float[LayerCount];
            for (int k = 0; k < LayerCount; k++) relax[k] = SurfaceDatabase.Table[k].rutRelaxRate;
            int n = size * size;
            for (int i = 0; i < n; i++)
            {
                float r = 0f; int o = i * LayerCount;
                for (int k = 0; k < LayerCount; k++) r += weights[o + k] * relax[k];
                r = r / 255f / MaxRelax;
                fluidity[i] = (byte)Mathf.Clamp(Mathf.RoundToInt(r * 255f), 0, 255);
            }
        }

        // ------------------------------------------------------------------ height queries

        public float SampleHeight(float x, float z)
        {
            WorldToGrid(x, z, out float gx, out float gz);
            gx = Mathf.Clamp(gx, 0f, size - 1.001f);
            gz = Mathf.Clamp(gz, 0f, size - 1.001f);
            int ix = (int)gx, iz = (int)gz;
            float fx = gx - ix, fz = gz - iz;
            int i00 = iz * size + ix;
            float h00 = height[i00], h10 = height[i00 + 1], h01 = height[i00 + size], h11 = height[i00 + size + 1];
            return Mathf.Lerp(Mathf.Lerp(h00, h10, fx), Mathf.Lerp(h01, h11, fx), fz);
        }

        public Vector3 SampleNormal(float x, float z)
        {
            float e = cell * 0.75f;
            float hl = SampleHeight(x - e, z), hr = SampleHeight(x + e, z);
            float hd = SampleHeight(x, z - e), hu = SampleHeight(x, z + e);
            var n = new Vector3(hl - hr, 2f * e, hd - hu);
            return n.normalized;
        }

        /// <summary>Slope in degrees at a position.</summary>
        public float SampleSlopeDegrees(float x, float z)
        {
            return Mathf.Acos(Mathf.Clamp01(SampleNormal(x, z).y)) * Mathf.Rad2Deg;
        }

        // ------------------------------------------------------------------ surface queries

        /// <summary>Bilinear surface layer weights (sum to ~1) into <paramref name="w"/> (length 8).</summary>
        public void SampleWeights(float x, float z, Span<float> w)
        {
            WorldToGrid(x, z, out float gx, out float gz);
            gx = Mathf.Clamp(gx, 0f, size - 1.001f);
            gz = Mathf.Clamp(gz, 0f, size - 1.001f);
            int ix = (int)gx, iz = (int)gz;
            float fx = gx - ix, fz = gz - iz;
            float w00 = (1 - fx) * (1 - fz), w10 = fx * (1 - fz), w01 = (1 - fx) * fz, w11 = fx * fz;
            int i00 = (iz * size + ix) * LayerCount;
            int i10 = i00 + LayerCount, i01 = i00 + size * LayerCount, i11 = i01 + LayerCount;
            const float inv = 1f / 255f;
            for (int k = 0; k < LayerCount; k++)
                w[k] = (weights[i00 + k] * w00 + weights[i10 + k] * w10 + weights[i01 + k] * w01 + weights[i11 + k] * w11) * inv;
        }

        public SurfaceType DominantType(float x, float z)
        {
            Span<float> w = stackalloc float[LayerCount];
            SampleWeights(x, z, w);
            int best = 0; float bw = -1f;
            for (int k = 0; k < LayerCount; k++) if (w[k] > bw) { bw = w[k]; best = k; }
            return (SurfaceType)best;
        }

        public float SampleByte(byte[] data, float x, float z)
        {
            WorldToGrid(x, z, out float gx, out float gz);
            gx = Mathf.Clamp(gx, 0f, size - 1.001f);
            gz = Mathf.Clamp(gz, 0f, size - 1.001f);
            int ix = (int)gx, iz = (int)gz;
            float fx = gx - ix, fz = gz - iz;
            int i00 = iz * size + ix;
            float a = Mathf.Lerp(data[i00], data[i00 + 1], fx);
            float b = Mathf.Lerp(data[i00 + size], data[i00 + size + 1], fx);
            return Mathf.Lerp(a, b, fz) * (1f / 255f);
        }

        public float SampleExtraDepth(float x, float z) => SampleByte(extraDepth, x, z) * MaxExtraDepth;
        public float SampleBaseWetness(float x, float z) => SampleByte(baseWet, x, z);
        public float SampleFluidity(float x, float z) => SampleByte(fluidity, x, z) * MaxRelax;

        /// <summary>Blend the surface table with the local layer weights. No wetness/global scaling applied here.</summary>
        public void SampleSoil(float x, float z, out SurfaceParams p)
        {
            Span<float> w = stackalloc float[LayerCount];
            SampleWeights(x, z, w);
            Blend(w, out p);
        }

        public static void Blend(ReadOnlySpan<float> w, out SurfaceParams p)
        {
            float sum = 0f;
            for (int k = 0; k < LayerCount; k++) sum += w[k];
            if (sum < 1e-4f) { p = SurfaceDatabase.Table[(int)SurfaceType.FirmSoil]; return; }
            float inv = 1f / sum;
            p = default;
            float r = 0, g = 0, b = 0;
            float kc = 0, kphi = 0, n = 0, c = 0, phi = 0, sk = 0, sd = 0, vi = 0, rr = 0, cg = 0, dr = 0, uw = 0, bf = 0, ws = 0, hg = 0;
            for (int k = 0; k < LayerCount; k++)
            {
                float a = w[k] * inv;
                if (a <= 0f) continue;
                ref readonly SurfaceParams s = ref SurfaceDatabase.Table[k];
                kc += s.kc * a; kphi += s.kphi * a; n += s.n * a; c += s.cohesion * a; phi += s.frictionAngle * a;
                sk += s.shearK * a; sd += s.softDepth * a; vi += s.viscosity * a; rr += s.rutRelaxRate * a;
                cg += s.compactionGain * a; dr += s.digRate * a; uw += s.unitWeight * a; bf += s.bulldozeFactor * a;
                ws += s.wetnessSensitivity * a; hg += s.hardGrip * a;
                r += s.tint.r * a; g += s.tint.g * a; b += s.tint.b * a;
            }
            p.name = "blend"; p.tint = new Color(r, g, b);
            p.kc = kc; p.kphi = kphi; p.n = n; p.cohesion = c; p.frictionAngle = phi; p.shearK = sk; p.softDepth = sd;
            p.viscosity = vi; p.rutRelaxRate = rr; p.compactionGain = cg; p.digRate = dr; p.unitWeight = uw;
            p.bulldozeFactor = bf; p.wetnessSensitivity = ws; p.hardGrip = hg;
        }

        // ------------------------------------------------------------------ authoring helpers (tests / generators)

        /// <summary>Fill every cell by a delegate returning height and fill weights from a surface delegate.</summary>
        public void Fill(Func<float, float, float> heightFn, Func<float, float, SurfaceType> surfaceFn = null)
        {
            for (int iz = 0; iz < size; iz++)
                for (int ix = 0; ix < size; ix++)
                {
                    float x = origin.x + ix * cell, z = origin.y + iz * cell;
                    height[iz * size + ix] = heightFn(x, z);
                    if (surfaceFn != null) SetWeights(ix, iz, surfaceFn(x, z));
                }
        }

        public void SetExtraDepth(int ix, int iz, float metres)
        {
            extraDepth[Index(ix, iz)] = (byte)Mathf.Clamp(Mathf.RoundToInt(metres / MaxExtraDepth * 255f), 0, 255);
        }

        public void SetBaseWetness(int ix, int iz, float wet01)
        {
            baseWet[Index(ix, iz)] = (byte)Mathf.Clamp(Mathf.RoundToInt(wet01 * 255f), 0, 255);
        }
    }
}
