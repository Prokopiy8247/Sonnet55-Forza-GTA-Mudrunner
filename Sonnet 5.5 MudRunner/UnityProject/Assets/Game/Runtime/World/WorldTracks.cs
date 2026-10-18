using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>A track resampled to dense points (2 m) with its vertical profile solved.</summary>
    public sealed class Track
    {
        public TrackDef def;
        public string name;
        public int index;
        public int n;
        public float[] x, z, y, s;
        public float[] halfW, extra, wet, grade;
        public byte[] kind;
        public bool[] ruts, carve, locked;
        public byte[] surfA, surfB;
        public float[] mix;                    // weight of surfB
        public float[] nodeF;                  // node index + fraction
        public float[] nodeS;                  // arclength of every authored node
        public int globalOffset;
        public float Length => n > 0 ? s[n - 1] : 0f;

        public Vector3 Point(int i) { return new Vector3(x[i], y[i], z[i]); }

        public int NearestIndex(float px, float pz)
        {
            int best = 0; float bd = float.MaxValue;
            for (int i = 0; i < n; i++)
            {
                float dx = x[i] - px, dz = z[i] - pz;
                float d = dx * dx + dz * dz;
                if (d < bd) { bd = d; best = i; }
            }
            return best;
        }

        /// <summary>Position/height at arclength.</summary>
        public Vector3 AtLength(float len)
        {
            if (len <= 0f) return Point(0);
            if (len >= Length) return Point(n - 1);
            int lo = 0, hi = n - 1;
            while (hi - lo > 1) { int m = (lo + hi) >> 1; if (s[m] <= len) lo = m; else hi = m; }
            float u = (len - s[lo]) / Mathf.Max(1e-4f, s[hi] - s[lo]);
            return Vector3.Lerp(Point(lo), Point(hi), u);
        }

        public float Yaw(int i)
        {
            int a = Mathf.Max(0, i - 1), b = Mathf.Min(n - 1, i + 1);
            return Mathf.Atan2(x[b] - x[a], z[b] - z[a]) * Mathf.Rad2Deg;
        }
    }

    /// <summary>All dense tracks concatenated in global arrays for rasterisation.</summary>
    public sealed class TrackSet
    {
        public readonly List<Track> tracks = new List<Track>();
        public float[] gx, gz, gy, ghw;
        public bool[] glink, gcarve;
        public Track[] gtrack;
        public int[] glocal;
        public int count;

        public Track Find(string name) { foreach (var t in tracks) if (t.name == name) return t; return null; }

        public void Finish()
        {
            count = 0;
            foreach (var t in tracks) { t.globalOffset = count; count += t.n; }
            gx = new float[count]; gz = new float[count]; gy = new float[count]; ghw = new float[count];
            glink = new bool[count]; gcarve = new bool[count]; gtrack = new Track[count]; glocal = new int[count];
            foreach (var t in tracks)
                for (int i = 0; i < t.n; i++)
                {
                    int g = t.globalOffset + i;
                    gx[g] = t.x[i]; gz[g] = t.z[i]; gy[g] = t.y[i]; ghw[g] = t.halfW[i];
                    glink[g] = i < t.n - 1; gcarve[g] = t.carve[i];
                    gtrack[g] = t; glocal[g] = i;
                }
        }
    }

    public static class TrackBuilder
    {
        public const float Spacing = 2f;

        // ------------------------------------------------------------------ spline resampling

        static Vector2 CR(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, float t)
        {
            float t2 = t * t, t3 = t2 * t;
            return 0.5f * (2f * p1 + (-p0 + p2) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 + (-p0 + 3f * p1 - 3f * p2 + p3) * t3);
        }

        /// <summary>Dense Catmull-Rom resample through the points at the given spacing. nodeF = node index + fraction.</summary>
        public static void Resample(IList<Vector2> pts, float spacing, out List<Vector2> dense, out List<float> nodeF)
        {
            int n = pts.Count;
            const int sub = 24;
            var fp = new List<Vector2>((n - 1) * sub + 1);
            var ff = new List<float>(fp.Capacity);
            for (int i = 0; i < n - 1; i++)
            {
                Vector2 p0 = pts[Mathf.Max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Mathf.Min(n - 1, i + 2)];
                for (int k = 0; k < sub; k++)
                {
                    float t = k / (float)sub;
                    fp.Add(CR(p0, p1, p2, p3, t)); ff.Add(i + t);
                }
            }
            fp.Add(pts[n - 1]); ff.Add(n - 1);
            var cum = new float[fp.Count];
            for (int i = 1; i < fp.Count; i++) cum[i] = cum[i - 1] + Vector2.Distance(fp[i - 1], fp[i]);
            float total = cum[cum.Length - 1];
            int cnt = Mathf.Max(2, Mathf.RoundToInt(total / spacing) + 1);
            dense = new List<Vector2>(cnt); nodeF = new List<float>(cnt);
            int j = 0;
            for (int k = 0; k < cnt; k++)
            {
                float L = total * k / (cnt - 1);
                while (j < cum.Length - 2 && cum[j + 1] < L) j++;
                float u = (L - cum[j]) / Mathf.Max(1e-5f, cum[j + 1] - cum[j]);
                dense.Add(Vector2.Lerp(fp[j], fp[j + 1], u));
                nodeF.Add(Mathf.Lerp(ff[j], ff[j + 1], u));
            }
        }

        // ------------------------------------------------------------------ build one dense track

        public static Track Build(TrackDef def, int index, WorldNoise noise)
        {
            var nodes = def.nodes;
            int nn = nodes.Count;
            var pts = new List<Vector2>(nn);
            for (int i = 0; i < nn; i++) pts.Add(new Vector2(nodes[i].x, nodes[i].z));
            Resample(pts, Spacing, out var dense, out var nodeF);
            int n = dense.Count;

            var t = new Track
            {
                def = def, name = def.name, index = index, n = n,
                x = new float[n], z = new float[n], y = new float[n], s = new float[n],
                halfW = new float[n], extra = new float[n], wet = new float[n], grade = new float[n],
                kind = new byte[n], ruts = new bool[n], carve = new bool[n], locked = new bool[n],
                surfA = new byte[n], surfB = new byte[n], mix = new float[n], nodeF = nodeF.ToArray(), nodeS = new float[nn],
            };

            // attributes by node fraction
            for (int i = 0; i < n; i++)
            {
                float f = t.nodeF[i];
                int a = Mathf.Min((int)f, nn - 2); float u = f - a;
                if (a < 0) a = 0;
                var A = nodes[a]; var B = nodes[Mathf.Min(nn - 1, a + 1)];
                t.halfW[i] = Mathf.Lerp(A.halfW, B.halfW, u);
                t.extra[i] = Mathf.Lerp(A.extra, B.extra, u);
                t.wet[i] = Mathf.Lerp(A.wet, B.wet, u);
                t.grade[i] = Mathf.Lerp(A.grade, B.grade, u);
                t.kind[i] = (byte)A.kind;
                t.ruts[i] = A.ruts;
                t.surfA[i] = (byte)A.surf;
                t.surfB[i] = (byte)A.surf;
                t.x[i] = dense[i].x; t.z[i] = dense[i].y;
            }

            // lateral meander (not near special segments nor the ends)
            if (def.wiggle > 0.01f)
            {
                var special = new float[n];
                for (int i = 0; i < n; i++) special[i] = t.kind[i] != (byte)TKind.Road ? 0f : float.MaxValue;
                // distance (in samples) to the nearest special sample
                float last = float.MaxValue;
                for (int i = 0; i < n; i++) { if (t.kind[i] != 0) last = 0f; else if (last < float.MaxValue) last += Spacing; special[i] = Mathf.Min(special[i], last); }
                last = float.MaxValue;
                for (int i = n - 1; i >= 0; i--) { if (t.kind[i] != 0) last = 0f; else if (last < float.MaxValue) last += Spacing; special[i] = Mathf.Min(special[i], last); }
                float seedZ = 11.3f * (index + 1);
                var ox = new float[n]; var oz = new float[n];
                float acc = 0f;
                var arc = new float[n];
                for (int i = 1; i < n; i++) { acc += Vector2.Distance(dense[i], dense[i - 1]); arc[i] = acc; }
                float total = acc;
                for (int i = 0; i < n; i++)
                {
                    int ia = Mathf.Max(0, i - 1), ib = Mathf.Min(n - 1, i + 1);
                    Vector2 tan = (dense[ib] - dense[ia]).normalized;
                    Vector2 nor = new Vector2(-tan.y, tan.x);
                    float edge = Mathf.Min(arc[i], total - arc[i]);
                    float fEdge = WorldNoise.Smooth(0f, 40f, edge);
                    float fSpec = WorldNoise.Smooth(14f, 40f, special[i]);
                    float off = def.wiggle * 1.7f * noise.Fbm(arc[i] / 85f, seedZ, 2) * fEdge * fSpec;
                    ox[i] = nor.x * off; oz[i] = nor.y * off;
                }
                for (int i = 0; i < n; i++) { t.x[i] += ox[i]; t.z[i] += oz[i]; }
            }

            // arclength
            for (int i = 1; i < n; i++) t.s[i] = t.s[i - 1] + Mathf.Sqrt((t.x[i] - t.x[i - 1]) * (t.x[i] - t.x[i - 1]) + (t.z[i] - t.z[i - 1]) * (t.z[i] - t.z[i - 1]));
            for (int k = 0; k < nn; k++)
            {
                // arclength of node k: interpolate nodeF
                int lo = 0, hi = n - 1;
                while (hi - lo > 1) { int m = (lo + hi) >> 1; if (t.nodeF[m] <= k) lo = m; else hi = m; }
                float u = (k - t.nodeF[lo]) / Mathf.Max(1e-5f, t.nodeF[hi] - t.nodeF[lo]);
                t.nodeS[k] = Mathf.Lerp(t.s[lo], t.s[hi], Mathf.Clamp01(u));
            }

            // surface transitions between consecutive segments (6 m blend)
            const float tr = 6f;
            for (int i = 0; i < n; i++)
            {
                int seg = Mathf.Clamp((int)t.nodeF[i], 0, nn - 2);
                float dStart = t.s[i] - t.nodeS[seg], dEnd = t.nodeS[seg + 1] - t.s[i];
                if (dStart < tr && seg > 0) { t.surfB[i] = (byte)nodes[seg - 1].surf; t.mix[i] = 0.5f * (1f - dStart / tr); }
                else if (dEnd < tr && seg < nn - 2) { t.surfB[i] = (byte)nodes[seg + 1].surf; t.mix[i] = 0.5f * (1f - dEnd / tr); }
            }

            for (int i = 0; i < n; i++) t.carve[i] = t.kind[i] == (byte)TKind.Road;
            return t;
        }

        // ------------------------------------------------------------------ vertical profile

        public static void SolveProfile(Track t, Func<float, float, float> heightAt, Track parentStart, Track parentEnd, Func<float, float, float> minY = null)
        {
            int n = t.n;
            var raw = new float[n];
            for (int i = 0; i < n; i++)
            {
                raw[i] = heightAt(t.x[i], t.z[i]);
                if (minY != null && t.kind[i] != (byte)TKind.Ford && t.kind[i] != (byte)TKind.Free && t.kind[i] != (byte)TKind.Bridge) raw[i] = Mathf.Max(raw[i], minY(t.x[i], t.z[i]));
            }
            var Y = new float[n];
            var lockd = t.locked;
            for (int i = 0; i < n; i++)
            {
                Y[i] = raw[i];
                if (t.kind[i] == (byte)TKind.Ford || t.kind[i] == (byte)TKind.Free) { lockd[i] = true; t.carve[i] = false; }
                else if (t.kind[i] == (byte)TKind.Causeway) { Y[i] = raw[i] + 0.55f; t.carve[i] = false; }
                else if (t.kind[i] == (byte)TKind.Bridge) { t.carve[i] = false; }
            }

            // pinned nodes
            var pinS = new List<float>(); var pinY = new List<float>();
            for (int k = 0; k < t.def.nodes.Count; k++)
                if (!float.IsNaN(t.def.nodes[k].y)) { pinS.Add(t.nodeS[k]); pinY.Add(t.def.nodes[k].y); }
            for (int p = 0; p + 1 < pinS.Count; p++)
                for (int i = 0; i < n; i++)
                    if (t.s[i] >= pinS[p] && t.s[i] <= pinS[p + 1])
                    {
                        Y[i] = Mathf.Lerp(pinY[p], pinY[p + 1], (t.s[i] - pinS[p]) / Mathf.Max(1e-3f, pinS[p + 1] - pinS[p]));
                        lockd[i] = true;
                    }

            // near a junction the free profile is blended toward the parent's height (the parent road is already cut / filled there)
            if (parentStart != null && n > 0)
            {
                float y0 = parentStart.y[parentStart.NearestIndex(t.x[0], t.z[0])];
                for (int i = 0; i < n && t.s[i] < 70f; i++) if (!lockd[i]) Y[i] = Mathf.Lerp(y0, Y[i], WorldNoise.Smooth(0f, 70f, t.s[i]));
            }
            if (parentEnd != null && n > 0)
            {
                float y1 = parentEnd.y[parentEnd.NearestIndex(t.x[n - 1], t.z[n - 1])];
                for (int i = n - 1; i >= 0 && t.s[n - 1] - t.s[i] < 70f; i--) if (!lockd[i]) Y[i] = Mathf.Lerp(y1, Y[i], WorldNoise.Smooth(0f, 70f, t.s[n - 1] - t.s[i]));
            }

            // parent locks
            if (parentStart != null && n > 0)
            {
                int j = parentStart.NearestIndex(t.x[0], t.z[0]);
                Y[0] = parentStart.y[j]; lockd[0] = true;
                if (n > 2) { Y[1] = parentStart.y[j]; lockd[1] = true; }
            }
            if (parentEnd != null && n > 0)
            {
                int j = parentEnd.NearestIndex(t.x[n - 1], t.z[n - 1]);
                Y[n - 1] = parentEnd.y[j]; lockd[n - 1] = true;
                if (n > 2) { Y[n - 2] = parentEnd.y[j]; lockd[n - 2] = true; }
            }

            // bridges: raw interpolated between the ends
            FixBridges(t, Y);

            // gaussian smoothing of the free points (10 m sigma), locked points stay
            const int R = 12; // samples
            var w = new float[2 * R + 1];
            float sig = 5f, ws = 0f;
            for (int k = -R; k <= R; k++) { w[k + R] = Mathf.Exp(-(k * k) / (2f * sig * sig)); ws += w[k + R]; }
            for (int k = 0; k < w.Length; k++) w[k] /= ws;
            for (int pass = 0; pass < 2; pass++)
            {
                var S = (float[])Y.Clone();
                for (int i = 0; i < n; i++)
                {
                    if (lockd[i] || t.kind[i] == (byte)TKind.Bridge) continue;
                    float acc = 0f;
                    for (int k = -R; k <= R; k++)
                    {
                        int j = Mathf.Clamp(i + k, 0, n - 1);
                        acc += w[k + R] * Y[j];
                    }
                    S[i] = acc;
                }
                Y = S;
                FixBridges(t, Y);
            }

            // grade limiting (forward/backward), locked points are fixed
            for (int it = 0; it < 3; it++)
            {
                for (int i = 1; i < n; i++)
                {
                    if (lockd[i] || t.kind[i] == (byte)TKind.Bridge) continue;
                    float g = Mathf.Max(0.02f, t.grade[i]) * Spacing;
                    Y[i] = Mathf.Clamp(Y[i], Y[i - 1] - g, Y[i - 1] + g);
                }
                for (int i = n - 2; i >= 0; i--)
                {
                    if (lockd[i] || t.kind[i] == (byte)TKind.Bridge) continue;
                    float g = Mathf.Max(0.02f, t.grade[i]) * Spacing;
                    Y[i] = Mathf.Clamp(Y[i], Y[i + 1] - g, Y[i + 1] + g);
                }
                FixBridges(t, Y);
            }
            for (int i = 0; i < n; i++) t.y[i] = Y[i];
        }

        static void FixBridges(Track t, float[] Y)
        {
            int n = t.n;
            int i = 0;
            while (i < n)
            {
                if (t.kind[i] != (byte)TKind.Bridge) { i++; continue; }
                int a = i;
                while (i < n && t.kind[i] == (byte)TKind.Bridge) i++;
                int b = i - 1;
                int ia = Mathf.Max(0, a - 1), ib = Mathf.Min(n - 1, b + 1);
                for (int k = a; k <= b; k++)
                {
                    float u = (t.s[k] - t.s[ia]) / Mathf.Max(1e-3f, t.s[ib] - t.s[ia]);
                    Y[k] = Mathf.Lerp(Y[ia], Y[ib], u);
                }
            }
        }

        // ------------------------------------------------------------------ route polyline helpers

        /// <summary>Contiguous index ranges [a, b] of dense points with the given kind.</summary>
        public static List<(int a, int b)> Runs(Track t, TKind kind)
        {
            var list = new List<(int, int)>();
            int i = 0;
            while (i < t.n)
            {
                if (t.kind[i] != (byte)kind) { i++; continue; }
                int a = i;
                while (i < t.n && t.kind[i] == (byte)kind) i++;
                list.Add((a, i - 1));
            }
            return list;
        }
    }

    /// <summary>Rasterises a set of line segments into per-cell distance + segment parameter (index + fraction), in parallel and deterministically.</summary>
    public static class SegmentRaster
    {
        public static void Rasterize(int size, float cell, Vector2 origin, float[] px, float[] pz, bool[] link, float[] radius,
                                     float[] dist, float[] tpar)
        {
            int nseg = px.Length;
            var rowStart = new int[size + 1];
            var z0i = new int[nseg]; var z1i = new int[nseg];
            for (int i = 0; i < nseg; i++)
            {
                z0i[i] = 1; z1i[i] = 0;
                if (!link[i] || i + 1 >= nseg) continue;
                float r = radius[i];
                float zmin = Mathf.Min(pz[i], pz[i + 1]) - r, zmax = Mathf.Max(pz[i], pz[i + 1]) + r;
                int a = Mathf.Max(0, Mathf.FloorToInt((zmin - origin.y) / cell));
                int b = Mathf.Min(size - 1, Mathf.CeilToInt((zmax - origin.y) / cell));
                if (b < a) continue;
                z0i[i] = a; z1i[i] = b;
                for (int r2 = a; r2 <= b; r2++) rowStart[r2 + 1]++;
            }
            for (int i = 0; i < size; i++) rowStart[i + 1] += rowStart[i];
            var fill = new int[size];
            var rowSegs = new int[rowStart[size]];
            for (int i = 0; i < nseg; i++)
                for (int r2 = z0i[i]; r2 <= z1i[i]; r2++) rowSegs[rowStart[r2] + fill[r2]++] = i;

            Parallel.For(0, size, iz =>
            {
                float wz = origin.y + iz * cell;
                int rowBase = iz * size;
                for (int k = rowStart[iz]; k < rowStart[iz + 1]; k++)
                {
                    int sgi = rowSegs[k];
                    float ax = px[sgi], az = pz[sgi], bx = px[sgi + 1], bz = pz[sgi + 1];
                    float r = radius[sgi];
                    float xmin = Mathf.Min(ax, bx) - r, xmax = Mathf.Max(ax, bx) + r;
                    int x0 = Mathf.Max(0, Mathf.FloorToInt((xmin - origin.x) / cell));
                    int x1 = Mathf.Min(size - 1, Mathf.CeilToInt((xmax - origin.x) / cell));
                    float dx = bx - ax, dz = bz - az;
                    float len2 = dx * dx + dz * dz;
                    float inv = len2 > 1e-8f ? 1f / len2 : 0f;
                    float r2 = r * r;
                    for (int ix = x0; ix <= x1; ix++)
                    {
                        float wx = origin.x + ix * cell;
                        float u = ((wx - ax) * dx + (wz - az) * dz) * inv;
                        u = u < 0f ? 0f : (u > 1f ? 1f : u);
                        float cx = ax + dx * u - wx, cz = az + dz * u - wz;
                        float d2 = cx * cx + cz * cz;
                        if (d2 > r2) continue;
                        int idx = rowBase + ix;
                        float d = Mathf.Sqrt(d2);
                        if (d < dist[idx]) { dist[idx] = d; tpar[idx] = sgi + u; }
                    }
                }
            });
        }
    }
}
