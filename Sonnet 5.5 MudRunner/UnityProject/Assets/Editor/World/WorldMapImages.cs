using System;
using System.Collections.Generic;
using System.IO;
using MudRunner.Ground;
using MudRunner.WorldGen;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>CPU renderer of top-down maps (surface colours + hillshade + water + routes/sites overlay) for human review.</summary>
    public static class WorldMapImages
    {
        public struct Marker { public string label; public Vector3 pos; public Color32 color; public int style; }

        static readonly string[] Digits = {
            "111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
            "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111" };

        static void Put(Color32[] px, int w, int h, int x, int y, Color32 c)
        {
            if (x < 0 || y < 0 || x >= w || y >= h) return;
            px[y * w + x] = c;
        }

        static void Disc(Color32[] px, int w, int h, int cx, int cy, int r, Color32 c)
        {
            for (int dy = -r; dy <= r; dy++)
                for (int dx = -r; dx <= r; dx++)
                    if (dx * dx + dy * dy <= r * r + 1) Put(px, w, h, cx + dx, cy + dy, c);
        }

        static void Line(Color32[] px, int w, int h, float x0, float y0, float x1, float y1, int r, Color32 c)
        {
            float len = Mathf.Max(Mathf.Abs(x1 - x0), Mathf.Abs(y1 - y0));
            int n = Mathf.Max(1, Mathf.CeilToInt(len));
            for (int i = 0; i <= n; i++)
            {
                float u = i / (float)n;
                Disc(px, w, h, Mathf.RoundToInt(Mathf.Lerp(x0, x1, u)), Mathf.RoundToInt(Mathf.Lerp(y0, y1, u)), r, c);
            }
        }

        static void Number(Color32[] px, int w, int h, int x, int y, int num, int scale, Color32 fg, Color32 bg)
        {
            string s = num.ToString();
            int tw = s.Length * 4 * scale + scale;
            for (int yy = -scale; yy < 5 * scale + scale; yy++) for (int xx = -scale; xx < tw; xx++) Put(px, w, h, x + xx, y + yy, bg);
            for (int i = 0; i < s.Length; i++)
            {
                string g = Digits[s[i] - '0'];
                for (int gy = 0; gy < 5; gy++)
                    for (int gx = 0; gx < 3; gx++)
                        if (g[gy * 3 + gx] == '1')
                            for (int sy = 0; sy < scale; sy++) for (int sx = 0; sx < scale; sx++)
                                Put(px, w, h, x + (i * 4 + gx) * scale + sx, y + (4 - gy) * scale + sy, fg);
            }
        }

        public static Color32[] RenderBase(GroundMap map, int x0, int z0, int nx, int nz, int step, int mode)
        {
            var px = new Color32[nx * nz];
            var tmp = new float[8];
            var tint = new Color[8];
            for (int k = 0; k < 8; k++) tint[k] = SurfaceDatabase.Table[k].tint;
            // make layers more distinguishable for the map
            tint[(int)SurfaceType.Grass] = new Color(0.22f, 0.40f, 0.14f);
            tint[(int)SurfaceType.FirmSoil] = new Color(0.50f, 0.40f, 0.26f);
            tint[(int)SurfaceType.Gravel] = new Color(0.78f, 0.72f, 0.58f);
            tint[(int)SurfaceType.ShallowMud] = new Color(0.45f, 0.28f, 0.14f);
            tint[(int)SurfaceType.DeepMud] = new Color(0.26f, 0.15f, 0.08f);
            tint[(int)SurfaceType.Bog] = new Color(0.16f, 0.24f, 0.11f);
            tint[(int)SurfaceType.Sand] = new Color(0.86f, 0.78f, 0.52f);
            tint[(int)SurfaceType.Rock] = new Color(0.50f, 0.50f, 0.52f);
            int s = map.size;
            Vector3 L = new Vector3(-0.55f, 0.62f, 0.55f).normalized;
            for (int j = 0; j < nz; j++)
                for (int i = 0; i < nx; i++)
                {
                    int ix = Mathf.Clamp(x0 + i * step, 0, s - 1), iz = Mathf.Clamp(z0 + j * step, 0, s - 1);
                    int idx = iz * s + ix;
                    float h = map.height[idx];
                    int il = Mathf.Max(0, ix - 1), ir = Mathf.Min(s - 1, ix + 1), id = Mathf.Max(0, iz - 1), iu = Mathf.Min(s - 1, iz + 1);
                    float gx = (map.height[iz * s + ir] - map.height[iz * s + il]) / (ir - il);
                    float gz = (map.height[iu * s + ix] - map.height[id * s + ix]) / (iu - id);
                    var n = new Vector3(-gx * 1.6f, 1f, -gz * 1.6f).normalized;
                    float shade = Mathf.Clamp(0.58f + 0.62f * (Vector3.Dot(n, L) - 0.7f), 0.25f, 1.25f);
                    Color c;
                    if (mode == 0)
                    {
                        int o = idx * 8;
                        float r = 0, g = 0, b = 0;
                        for (int k = 0; k < 8; k++) { float w = map.weights[o + k] * (1f / 255f); r += tint[k].r * w; g += tint[k].g * w; b += tint[k].b * w; }
                        // extra depth hint (very subtle) so that traps can be spotted in the debug map
                        c = new Color(r, g, b);
                    }
                    else if (mode == 1)
                    {
                        float t = Mathf.Clamp01((h - 0f) / 90f);
                        c = Color.Lerp(new Color(0.15f, 0.35f, 0.2f), Color.Lerp(new Color(0.7f, 0.65f, 0.35f), Color.white, Mathf.Clamp01((t - 0.5f) * 2f)), t);
                    }
                    else
                    {
                        float sl = Mathf.Atan(Mathf.Sqrt(gx * gx + gz * gz)) * Mathf.Rad2Deg;
                        c = sl < 8f ? new Color(0.25f, 0.6f, 0.25f) : sl < 15f ? new Color(0.8f, 0.8f, 0.2f) : sl < 22f ? new Color(0.95f, 0.55f, 0.1f) : sl < 30f ? new Color(0.9f, 0.15f, 0.1f) : new Color(0.4f, 0.1f, 0.4f);
                    }
                    c *= shade;
                    if (map.water != null)
                    {
                        float lv = map.water.level[idx];
                        if (lv > float.NegativeInfinity && lv > h)
                        {
                            float d = Mathf.Clamp01((lv - h) / 2.2f);
                            var wc = Color.Lerp(new Color(0.20f, 0.55f, 0.85f), new Color(0.04f, 0.18f, 0.45f), d);
                            c = Color.Lerp(c, wc * Mathf.Clamp(shade, 0.8f, 1.1f), 0.6f + 0.35f * d);
                        }
                    }
                    c.a = 1f;
                    px[j * nx + i] = c;
                }
            return px;
        }

        public static void Save(string path, Color32[] px, int w, int h)
        {
            var tex = new Texture2D(w, h, TextureFormat.RGBA32, false);
            tex.SetPixels32(px);
            tex.Apply();
            File.WriteAllBytes(path, tex.EncodeToPNG());
            UnityEngine.Object.DestroyImmediate(tex);
        }

        /// <summary>Overlay routes + markers. origin of the image is world (x0, z0) at pixel (0,0), scale = pixels per metre.</summary>
        public static void Overlay(Color32[] px, int w, int h, float wx0, float wz0, float scale, GeneratedWorld gw, bool markers, int lineR)
        {
            foreach (var t in gw.tracks.tracks)
            {
                Color32 col = new Color32(235, 235, 235, 255);
                float lw = 0.6f * lineR;
                if (t.def.routeId == 1) { col = new Color32(40, 120, 255, 255); lw = lineR; }
                else if (t.def.routeId == 2) { col = new Color32(255, 235, 30, 255); lw = lineR; }
                else if (t.def.routeId == 3) { col = new Color32(255, 40, 40, 255); lw = lineR; }
                for (int i = 1; i < t.n; i++)
                {
                    float x0 = (t.x[i - 1] - wx0) * scale, y0 = (t.z[i - 1] - wz0) * scale, x1 = (t.x[i] - wx0) * scale, y1 = (t.z[i] - wz0) * scale;
                    Color32 c = col;
                    if (t.kind[i] == (byte)TKind.Ford) c = new Color32(0, 255, 255, 255);
                    else if (t.kind[i] == (byte)TKind.Bridge) c = new Color32(255, 140, 0, 255);
                    else if (t.kind[i] == (byte)TKind.Causeway) c = new Color32(255, 140, 220, 255);
                    Line(px, w, h, x0, y0, x1, y1, Mathf.Max(0, Mathf.RoundToInt(lw * 0.5f)), c);
                }
            }
            if (!markers) return;
            foreach (var tp in gw.traps)
            {
                int cx = Mathf.RoundToInt((tp.x - wx0) * scale), cy = Mathf.RoundToInt((tp.z - wz0) * scale);
                Color32 c = tp.decoy ? new Color32(120, 255, 120, 255) : new Color32(255, 0, 255, 255);
                for (int a = 0; a < 24; a++)
                {
                    float an = a / 24f * Mathf.PI * 2f;
                    Put(px, w, h, cx + Mathf.RoundToInt(Mathf.Cos(an) * tp.r * scale), cy + Mathf.RoundToInt(Mathf.Sin(an) * tp.r * scale), c);
                }
            }
        }

        public static void DrawSites(Color32[] px, int w, int h, float wx0, float wz0, float scale, GeneratedWorld gw, List<string> legend, int numScale)
        {
            int idx = 1;
            foreach (var kv in gw.sites.sites)
            {
                var s = kv.Value;
                int cx = Mathf.RoundToInt((s.position.x - wx0) * scale), cy = Mathf.RoundToInt((s.position.z - wz0) * scale);
                if (cx < -20 || cy < -20 || cx > w + 20 || cy > h + 20) { idx++; continue; }
                Disc(px, w, h, cx, cy, 3 * numScale, new Color32(0, 0, 0, 255));
                Disc(px, w, h, cx, cy, 2 * numScale, new Color32(255, 255, 255, 255));
                Number(px, w, h, cx + 4 * numScale, cy + 2 * numScale, idx, numScale, new Color32(0, 0, 0, 255), new Color32(255, 255, 255, 235));
                legend?.Add(idx + " " + s.name + " (" + s.position.x.ToString("F0") + "," + s.position.z.ToString("F0") + ")");
                idx++;
            }
        }
    }
}
