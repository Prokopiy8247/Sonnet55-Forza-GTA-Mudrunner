using System;
using System.Collections.Generic;
using System.Text;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>Measured statistics of a route polyline on the generated map (used by the tests and the preview log).</summary>
    public sealed class RouteStats
    {
        public string name;
        public float length;
        public float minY, maxY, climb;
        public float maxSlopeDeg, meanSlopeDeg, steepLength15, steepLength22;
        public Vector3 maxSlopeAt;
        public float maxExtra, hiddenLength, maxWaterDepth, waterLength, deepWaterLength;
        public readonly float[] surfaceLength = new float[8];
        public float mudLength => surfaceLength[(int)SurfaceType.ShallowMud] + surfaceLength[(int)SurfaceType.DeepMud] + surfaceLength[(int)SurfaceType.Bog];
        public int impassableSamples;      // samples that are deep water (> 1.8 m), too steep (> 32 deg) or have extra depth > 1.5 and are not covered by a bridge
        public float maxWetBase;

        public static RouteStats Compute(string name, IList<Vector3> pts, GroundMap map, float step = 2f)
        {
            var st = new RouteStats { name = name, minY = float.MaxValue, maxY = float.MinValue };
            if (pts == null || pts.Count < 2) return st;
            float acc = 0f, next = 0f; float prevY = float.NaN; Vector3 prev = pts[0];
            double slopeSum = 0; int slopeN = 0;
            var tmp = new float[8];
            for (int i = 1; i < pts.Count; i++)
            {
                Vector3 a = pts[i - 1], b = pts[i];
                float seg = Vector3.Distance(new Vector3(a.x, 0, a.z), new Vector3(b.x, 0, b.z));
                st.length += seg;
            }
            // resample at fixed step
            float L = 0f;
            Vector3 p0 = pts[0];
            var samples = new List<Vector3>();
            samples.Add(p0);
            for (int i = 1; i < pts.Count; i++)
            {
                Vector3 a = pts[i - 1], b = pts[i];
                float seg = Vector2.Distance(new Vector2(a.x, a.z), new Vector2(b.x, b.z));
                if (seg < 1e-4f) continue;
                while (next + step <= L + seg)
                {
                    next += step;
                    float u = (next - L) / seg;
                    samples.Add(Vector3.Lerp(a, b, u));
                }
                L += seg;
            }
            samples.Add(pts[pts.Count - 1]);
            for (int i = 0; i < samples.Count; i++)
            {
                var p = samples[i];
                float g = map.SampleHeight(p.x, p.z);
                float py = p.y;
                if (py < st.minY) st.minY = py;
                if (py > st.maxY) st.maxY = py;
                if (!float.IsNaN(prevY) && py > prevY) st.climb += py - prevY;
                prevY = py;
                // slope along the path over ~8 m
                int j0 = Mathf.Max(0, i - 2), j1 = Mathf.Min(samples.Count - 1, i + 2);
                float run = Vector2.Distance(new Vector2(samples[j0].x, samples[j0].z), new Vector2(samples[j1].x, samples[j1].z));
                float dy = samples[j1].y - samples[j0].y;
                float sd = Mathf.Atan2(Mathf.Abs(dy), Mathf.Max(0.1f, run)) * Mathf.Rad2Deg;
                if (sd > st.maxSlopeDeg) { st.maxSlopeDeg = sd; st.maxSlopeAt = p; }
                slopeSum += sd; slopeN++;
                if (sd > 15f) st.steepLength15 += step;
                if (sd > 22f) st.steepLength22 += step;
                // surface
                map.SampleWeights(p.x, p.z, tmp);
                int best = 0; float bw = -1f; for (int k = 0; k < 8; k++) if (tmp[k] > bw) { bw = tmp[k]; best = k; }
                st.surfaceLength[best] += step;
                float ex = map.SampleExtraDepth(p.x, p.z);
                if (ex > st.maxExtra) st.maxExtra = ex;
                if (ex > 0.3f) st.hiddenLength += step;
                float wet = map.SampleBaseWetness(p.x, p.z);
                if (wet > st.maxWetBase) st.maxWetBase = wet;
                float wd = map.water != null ? map.water.Depth(p.x, p.z, g) : 0f;
                if (wd > st.maxWaterDepth) st.maxWaterDepth = wd;
                if (wd > 0.05f) st.waterLength += step;
                if (wd > 0.9f) st.deepWaterLength += step;
            }
            st.meanSlopeDeg = slopeN > 0 ? (float)(slopeSum / slopeN) : 0f;
            return st;
        }

        public override string ToString()
        {
            var sb = new StringBuilder();
            sb.Append(name).Append(": len=").Append(length.ToString("F0")).Append("m climb=").Append(climb.ToString("F0")).Append("m Y[").Append(minY.ToString("F1")).Append("..").Append(maxY.ToString("F1"))
              .Append("] slope max/mean=").Append(maxSlopeDeg.ToString("F1")).Append("@(").Append(maxSlopeAt.x.ToString("F0")).Append(",").Append(maxSlopeAt.z.ToString("F0")).Append(")/").Append(meanSlopeDeg.ToString("F1")).Append(" steep>15=").Append(steepLength15.ToString("F0")).Append("m >22=").Append(steepLength22.ToString("F0"))
              .Append("m extra max=").Append(maxExtra.ToString("F2")).Append(" hidden(>0.3)=").Append(hiddenLength.ToString("F0")).Append("m water max=").Append(maxWaterDepth.ToString("F2")).Append(" len=").Append(waterLength.ToString("F0"))
              .Append("m surf[");
            string[] n = { "rock", "firm", "grass", "grav", "shMud", "dpMud", "bog", "sand" };
            for (int k = 0; k < 8; k++) if (surfaceLength[k] > 1f) sb.Append(n[k]).Append('=').Append(surfaceLength[k].ToString("F0")).Append(' ');
            sb.Append(']');
            return sb.ToString();
        }
    }

    /// <summary>Deterministic 64-bit FNV-1a fingerprint of everything a world generation produced (ground, water, props, sites).</summary>
    public static class WorldHash
    {
        const ulong Offset = 14695981039346656037UL, Prime = 1099511628211UL;

        static ulong Bytes(ulong h, ReadOnlySpan<byte> b)
        {
            for (int i = 0; i < b.Length; i++) { h ^= b[i]; h *= Prime; }
            return h;
        }

        static ulong Int(ulong h, int v) { for (int i = 0; i < 4; i++) { h ^= (byte)(v >> (8 * i)); h *= Prime; } return h; }
        static ulong Flt(ulong h, float v) { return Int(h, BitConverter.SingleToInt32Bits(v)); }

        public static ulong Compute(GeneratedWorld gw)
        {
            ulong h = Offset;
            var map = gw.map;
            h = Bytes(h, System.Runtime.InteropServices.MemoryMarshal.AsBytes(new ReadOnlySpan<float>(map.height)));
            h = Bytes(h, map.weights); h = Bytes(h, map.extraDepth); h = Bytes(h, map.baseWet);
            if (map.water != null)
            {
                h = Bytes(h, System.Runtime.InteropServices.MemoryMarshal.AsBytes(new ReadOnlySpan<float>(map.water.level)));
                h = Bytes(h, System.Runtime.InteropServices.MemoryMarshal.AsBytes(new ReadOnlySpan<sbyte>(map.water.flowX)));
                h = Bytes(h, System.Runtime.InteropServices.MemoryMarshal.AsBytes(new ReadOnlySpan<sbyte>(map.water.flowZ)));
            }
            if (gw.props != null)
            {
                h = Int(h, gw.props.Count); h = Int(h, gw.props.structures.Count);
                for (int i = 0; i < gw.props.insts.Length; i += 7) { var p = gw.props.insts[i]; h = Flt(h, p.x); h = Flt(h, p.z); h = Int(h, p.type); }
                foreach (var st in gw.props.structures) { h = Flt(h, st.pos.x); h = Flt(h, st.pos.z); }
            }
            foreach (var kv in gw.sites.sites) { h = Flt(h, kv.Value.position.x); h = Flt(h, kv.Value.position.z); }
            foreach (var r in gw.sites.routes) h = Flt(h, r.length);
            return h;
        }
    }
}
