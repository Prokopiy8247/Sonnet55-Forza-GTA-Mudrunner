using System;
using UnityEngine;

namespace MudRunner.Ground
{
    /// <summary>
    /// Water as compact raster data (no per-object nodes): world-space water surface height per cell and the horizontal
    /// current velocity. Rivers, ponds and the swamp are rasterised into it by the world builder; the water renderer builds
    /// its mesh from it and the vehicle physics (buoyancy, drag, fording) reads it.
    /// </summary>
    public sealed class WaterMap
    {
        public readonly int size;
        public readonly float cell;
        public readonly Vector2 origin;
        public readonly float[] level;     // world Y of the surface; float.NegativeInfinity = no water here
        public readonly sbyte[] flowX;     // current in 0.1 m/s units (+x)
        public readonly sbyte[] flowZ;     // current in 0.1 m/s units (+z)

        public const float NoWater = float.NegativeInfinity;

        public WaterMap(int size, float cell, Vector2 origin)
        {
            this.size = size; this.cell = cell; this.origin = origin;
            level = new float[size * size];
            flowX = new sbyte[size * size]; flowZ = new sbyte[size * size];
            for (int i = 0; i < level.Length; i++) level[i] = NoWater;
        }

        public float WorldSize => (size - 1) * cell;
        public int Index(int ix, int iz) => iz * size + ix;

        public void Set(int ix, int iz, float surfaceY, Vector2 flow)
        {
            int i = Index(ix, iz);
            level[i] = surfaceY;
            flowX[i] = (sbyte)Mathf.Clamp(Mathf.RoundToInt(flow.x * 10f), -127, 127);
            flowZ[i] = (sbyte)Mathf.Clamp(Mathf.RoundToInt(flow.y * 10f), -127, 127);
        }

        /// <summary>Water surface and current at a world position. Returns false when there is no water.</summary>
        public bool Sample(float x, float z, out float surfaceY, out Vector2 flow)
        {
            float gx = (x - origin.x) / cell, gz = (z - origin.y) / cell;
            surfaceY = NoWater; flow = Vector2.zero;
            if (gx < 0f || gz < 0f || gx > size - 1.001f || gz > size - 1.001f) return false;
            int ix = (int)gx, iz = (int)gz; float fx = gx - ix, fz = gz - iz;
            int i00 = iz * size + ix;
            float a = level[i00], b = level[i00 + 1], c = level[i00 + size], d = level[i00 + size + 1];
            bool va = !float.IsNegativeInfinity(a), vb = !float.IsNegativeInfinity(b), vc = !float.IsNegativeInfinity(c), vd = !float.IsNegativeInfinity(d);
            if (!(va || vb || vc || vd)) return false;
            if (va && vb && vc && vd)
                surfaceY = Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fz);
            else
            {
                // edge cell: nearest valid corner
                float best = float.MaxValue; int bi = -1;
                for (int k = 0; k < 4; k++)
                {
                    bool v = k == 0 ? va : k == 1 ? vb : k == 2 ? vc : vd;
                    if (!v) continue;
                    float dx = (k & 1) - fx, dz = (k >> 1) - fz; float dd = dx * dx + dz * dz;
                    if (dd < best) { best = dd; bi = k; }
                }
                surfaceY = bi == 0 ? a : bi == 1 ? b : bi == 2 ? c : d;
            }
            int near = i00 + (fx > 0.5f ? 1 : 0) + (fz > 0.5f ? size : 0);
            flow = new Vector2(flowX[near], flowZ[near]) * 0.1f;
            return true;
        }

        /// <summary>Water depth over the given ground height (0 when dry).</summary>
        public float Depth(float x, float z, float groundY)
        {
            return Sample(x, z, out float lvl, out _) ? Mathf.Max(0f, lvl - groundY) : 0f;
        }
    }
}
