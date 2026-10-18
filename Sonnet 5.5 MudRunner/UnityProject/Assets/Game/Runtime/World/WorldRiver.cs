using System;
using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// A river / creek: dense centreline with per-point channel parameters (half width, depth, bank height, ford factor,
    /// water level, current speed). The channel carve itself is evaluated per terrain cell from the rasterised distance.
    /// </summary>
    public sealed class River
    {
        public RiverDef def;
        public string name;
        public int n;
        public float length;
        public float[] x, z, s, w, depth, bankH, bankRun, plainW, wallW, wl, ford, fordDepth, speed, curv, tanX, tanZ, influence, fade;
        public List<(float s, float depth, Vector2 pos, float halfW)> fords = new List<(float, float, Vector2, float)>();

        public const float Spacing = 4f;
        public float planeA, planeB, planeC;      // water level plane (least squares) used for the far valley floor
        public float meanBank = 1.6f;

        public struct Sample
        {
            public float w, depth, bankH, bankRun, plainW, wallW, wl, ford, fordDepth, speed, curv, tx, tz, px, pz, fade, s;
        }

        public static River Build(RiverDef def, WorldNoise noise, float endWl, int salt)
        {
            var pts = new List<Vector2>();
            foreach (var nd in def.nodes) pts.Add(new Vector2(nd.x, nd.z));
            TrackBuilder.Resample(pts, Spacing, out var dense, out var nodeF);
            int n = dense.Count;
            var r = new River { def = def, name = def.name, n = n };
            r.x = new float[n]; r.z = new float[n]; r.s = new float[n]; r.w = new float[n]; r.depth = new float[n];
            r.bankH = new float[n]; r.bankRun = new float[n]; r.plainW = new float[n]; r.wallW = new float[n]; r.wl = new float[n];
            r.ford = new float[n]; r.fordDepth = new float[n]; r.speed = new float[n]; r.curv = new float[n];
            r.tanX = new float[n]; r.tanZ = new float[n]; r.influence = new float[n]; r.fade = new float[n];
            for (int i = 0; i < n; i++)
            {
                r.x[i] = dense[i].x; r.z[i] = dense[i].y;
                if (i > 0) r.s[i] = r.s[i - 1] + Vector2.Distance(dense[i], dense[i - 1]);
            }
            r.length = r.s[n - 1];
            int nn = def.nodes.Count;
            var nodeS = new float[nn];
            for (int k = 0; k < nn; k++)
            {
                int lo = 0, hi = n - 1;
                while (hi - lo > 1) { int m = (lo + hi) >> 1; if (nodeF[m] <= k) lo = m; else hi = m; }
                float u = (k - nodeF[lo]) / Mathf.Max(1e-5f, nodeF[hi] - nodeF[lo]);
                nodeS[k] = Mathf.Lerp(r.s[lo], r.s[hi], Mathf.Clamp01(u));
                if (def.nodes[k].ford > 0f) r.fords.Add((nodeS[k], def.nodes[k].ford, new Vector2(def.nodes[k].x, def.nodes[k].z), def.nodes[k].halfW));
            }
            // tangents + curvature
            for (int i = 0; i < n; i++)
            {
                int a = Mathf.Max(0, i - 1), b = Mathf.Min(n - 1, i + 1);
                Vector2 t = new Vector2(r.x[b] - r.x[a], r.z[b] - r.z[a]).normalized;
                r.tanX[i] = t.x; r.tanZ[i] = t.y;
            }
            for (int i = 0; i < n; i++)
            {
                int a = Mathf.Max(0, i - 6), b = Mathf.Min(n - 1, i + 6);
                float a0 = Mathf.Atan2(r.tanZ[a], r.tanX[a]), a1 = Mathf.Atan2(r.tanZ[b], r.tanX[b]);
                float da = Mathf.DeltaAngle(a0 * Mathf.Rad2Deg, a1 * Mathf.Rad2Deg) * Mathf.Deg2Rad;
                r.curv[i] = da / Mathf.Max(1f, r.s[b] - r.s[a]);
            }

            float wlStart = def.wlStart, wlEnd = def.endsInWater ? endWl : def.wlEnd;
            if (def.endsInWater) wlStart = wlEnd + def.slope * r.length;
            for (int i = 0; i < n; i++)
            {
                float f = nodeF[i];
                int a = Mathf.Clamp((int)f, 0, nn - 2); float u = f - a;
                var A = def.nodes[a]; var B = def.nodes[a + 1];
                float w = Mathf.Lerp(A.halfW, B.halfW, u);
                float d = Mathf.Lerp(A.depth, B.depth, u);
                float wlLin = Mathf.Lerp(wlStart, wlEnd, r.s[i] / r.length);
                // ford factor
                float fo = 0f, fd = d, fwF = w, fwl = wlLin;
                foreach (var fz in r.fords)
                {
                    float dist = Mathf.Abs(r.s[i] - fz.s);
                    float fac = 1f - WorldNoise.Smooth(24f, 72f, dist);
                    if (fac > fo)
                    {
                        fo = fac; fd = fz.depth; fwF = fz.halfW;
                        float wlF = Mathf.Lerp(wlStart, wlEnd, fz.s / r.length);
                        fwl = Mathf.Lerp(wlLin, wlF, 1f - WorldNoise.Smooth(44f, 110f, dist));
                    }
                }
                r.wl[i] = fwl;
                r.ford[i] = fo;
                r.fordDepth[i] = fd;
                r.depth[i] = Mathf.Lerp(d, fd, fo);
                r.w[i] = Mathf.Lerp(w, Mathf.Max(w, fwF), fo);
                float deepBank = 0.85f + 0.55f * r.depth[i];
                float fordBank = 0.35f + 0.3f * r.depth[i];
                r.bankH[i] = Mathf.Max(0.4f, Mathf.Lerp(deepBank, fordBank, fo));
                r.bankRun[i] = r.bankH[i] * Mathf.Lerp(1.35f, 7.5f, fo);
                float ns = noise.Fbm(r.s[i] / 150f + 3.7f * salt, 5.1f * salt, 2);
                r.plainW[i] = (13f + 24f * (0.5f + 0.5f * ns)) * (def.endsInWater ? 0.55f : 1f) + 10f * fo;
                r.wallW[i] = (46f + 40f * (0.5f + 0.5f * noise.Fbm(r.s[i] / 210f + 7f, 9f * salt, 2))) * (def.endsInWater ? 1.7f : 1f);
                float sp = def.speedBase * (1f + 0.22f * fo) + 0.28f * noise.Fbm(r.s[i] / 60f, 2.2f * salt, 2);
                r.speed[i] = Mathf.Clamp(sp, 0.8f, 1.6f);
                float fadeIn = WorldNoise.Smooth(0f, 45f, r.s[i]);
                float fadeOut = def.endsInWater ? 1f : 1f - WorldNoise.Smooth(r.length - 120f, r.length - 25f, r.s[i]);
                r.fade[i] = fadeIn * fadeOut;
                r.influence[i] = r.w[i] + r.bankRun[i] + r.plainW[i] + r.wallW[i] + 6f;
            }
            r.FitPlane();
            return r;
        }

        void FitPlane()
        {
            // wl ~ a*x + b*z + c (normal equations)
            double sxx = 0, sxz = 0, szz = 0, sx = 0, sz = 0, sw = 0, sxw = 0, szw = 0; int m = n;
            for (int i = 0; i < n; i++)
            {
                double x = this.x[i], z = this.z[i], w = wl[i];
                sxx += x * x; sxz += x * z; szz += z * z; sx += x; sz += z; sw += w; sxw += x * w; szw += z * w;
            }
            double[,] A = { { sxx, sxz, sx }, { sxz, szz, sz }, { sx, sz, m } };
            double[] bb = { sxw, szw, sw };
            // gaussian elimination
            for (int c = 0; c < 3; c++)
            {
                int piv = c; for (int r = c + 1; r < 3; r++) if (Math.Abs(A[r, c]) > Math.Abs(A[piv, c])) piv = r;
                if (Math.Abs(A[piv, c]) < 1e-9) { planeA = planeB = 0; planeC = wl[0]; return; }
                if (piv != c) { for (int k = 0; k < 3; k++) { var t = A[c, k]; A[c, k] = A[piv, k]; A[piv, k] = t; } var tb = bb[c]; bb[c] = bb[piv]; bb[piv] = tb; }
                for (int r = c + 1; r < 3; r++) { double f = A[r, c] / A[c, c]; for (int k = c; k < 3; k++) A[r, k] -= f * A[c, k]; bb[r] -= f * bb[c]; }
            }
            double[] sol = new double[3];
            for (int r = 2; r >= 0; r--) { double acc = bb[r]; for (int k = r + 1; k < 3; k++) acc -= A[r, k] * sol[k]; sol[r] = acc / A[r, r]; }
            planeA = (float)sol[0]; planeB = (float)sol[1]; planeC = (float)sol[2];
            float sb = 0f; for (int i = 0; i < n; i++) sb += bankH[i]; meanBank = sb / n;
        }

        public float WlAtPoint(float px, float pz)
        {
            int best = 0; float bd = float.MaxValue;
            for (int i = 0; i < n; i++) { float dx = x[i] - px, dz = z[i] - pz; float d = dx * dx + dz * dz; if (d < bd) { bd = d; best = i; } }
            return wl[best];
        }

        public void Nearest(float px, float pz, out float dist, out float t)
        {
            float bd = float.MaxValue; t = 0f;
            for (int i = 0; i < n - 1; i++)
            {
                float ax = x[i], az = z[i], dx = x[i + 1] - ax, dz = z[i + 1] - az;
                float l2 = dx * dx + dz * dz;
                float u = l2 > 1e-6f ? Mathf.Clamp01(((px - ax) * dx + (pz - az) * dz) / l2) : 0f;
                float cx = ax + dx * u - px, cz = az + dz * u - pz;
                float d2 = cx * cx + cz * cz;
                if (d2 < bd) { bd = d2; t = i + u; }
            }
            dist = Mathf.Sqrt(bd);
        }

        public void Eval(float t, ref Sample o)
        {
            int j = Mathf.Clamp((int)t, 0, n - 2);
            float u = Mathf.Clamp01(t - j);
            int k = j + 1;
            o.w = Mathf.Lerp(w[j], w[k], u); o.depth = Mathf.Lerp(depth[j], depth[k], u);
            o.bankH = Mathf.Lerp(bankH[j], bankH[k], u); o.bankRun = Mathf.Lerp(bankRun[j], bankRun[k], u);
            o.plainW = Mathf.Lerp(plainW[j], plainW[k], u); o.wallW = Mathf.Lerp(wallW[j], wallW[k], u);
            o.wl = Mathf.Lerp(wl[j], wl[k], u); o.ford = Mathf.Lerp(ford[j], ford[k], u);
            o.fordDepth = Mathf.Lerp(fordDepth[j], fordDepth[k], u); o.speed = Mathf.Lerp(speed[j], speed[k], u);
            o.curv = Mathf.Lerp(curv[j], curv[k], u); o.fade = Mathf.Lerp(fade[j], fade[k], u);
            o.tx = Mathf.Lerp(tanX[j], tanX[k], u); o.tz = Mathf.Lerp(tanZ[j], tanZ[k], u);
            o.px = Mathf.Lerp(x[j], x[k], u); o.pz = Mathf.Lerp(z[j], z[k], u);
            o.s = Mathf.Lerp(s[j], s[k], u);
        }

        /// <summary>Channel shaped height for one cell. d = distance to the centreline. Returns the new height; wl = water surface or NoWater.</summary>
        public static float CellHeight(River r, in Sample sm, float d, float cx, float cz, float hIn, WorldNoise noise, out float waterLevel, out float wEff)
        {
            float bn = noise.Fbm(cx * 0.055f + 17f, cz * 0.055f - 9f, 2);
            wEff = Mathf.Max(0.8f, sm.w * (1f + 0.17f * bn));
            float cross = sm.tx * (cz - sm.pz) - sm.tz * (cx - sm.px);
            float side = cross >= 0f ? 1f : -1f;
            float g = Mathf.Clamp(sm.curv * 60f, -1f, 1f) * side;     // > 0: inside of the bend (gentle point bar)
            float bankH = sm.bankH * (g > 0f ? 1f - 0.35f * g : 1f - 0.15f * g);
            float bankRun = sm.bankRun * (g > 0f ? 1f + 1.4f * g : 1f + 0.35f * g);
            float micro = 0.22f * noise.Fbm(cx * 0.03f, cz * 0.03f, 2) * (1f - sm.ford * 0.7f);
            float fp = sm.wl + bankH + micro;
            float top = Mathf.Lerp(hIn, fp, sm.fade);
            waterLevel = WaterMap.NoWater;
            if (d <= wEff)
            {
                float q = d / wEff;
                float ex = Mathf.Lerp(2.2f, 3.6f, sm.ford);
                float bed = sm.wl - sm.depth * (1f - Mathf.Pow(q, ex));
                bed += 0.05f * noise.Perlin(cx * 0.45f, cz * 0.45f) * (0.4f + sm.ford);
                if (bed > sm.wl) bed = sm.wl;
                waterLevel = sm.wl;
                return bed;
            }
            if (d <= wEff + bankRun)
            {
                float u = (d - wEff) / bankRun;
                float sc = u * u * (3f - 2f * u);
                return sm.wl + (top - sm.wl) * sc;
            }
            float dOut = d - wEff - bankRun;
            float blend = 1f - WorldNoise.Smooth(sm.plainW, sm.plainW + sm.wallW, dOut);
            // far from the banks the floodplain level follows a smooth plane instead of the nearest river sample (no seams at meander medial axes)
            float farW = WorldNoise.Smooth(0.1f * sm.plainW, 0.8f * sm.plainW, dOut);
            float wlFar = r.planeA * cx + r.planeB * cz + r.planeC;
            float fpOut = Mathf.Lerp(sm.wl + bankH, wlFar + r.meanBank, farW) + micro;
            float topOut = Mathf.Lerp(hIn, fpOut, sm.fade);
            return Mathf.Lerp(hIn, topOut, blend);
        }
    }
}
