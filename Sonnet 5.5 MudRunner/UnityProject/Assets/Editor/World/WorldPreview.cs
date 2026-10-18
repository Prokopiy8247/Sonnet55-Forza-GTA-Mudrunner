using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using MudRunner.Ground;
using MudRunner.WorldGen;
using UnityEditor;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Review tooling for the generated world.
    ///   Tools/ub.sh worldmap MudRunner.EditorTools.WorldPreview.Map          (no graphics needed)  -> Captures/world_*.png + route statistics
    ///   GFX=1 Tools/ub.sh worldgfx MudRunner.EditorTools.WorldPreview.Run                          -> + perspective renders
    /// Env: WORLD_CROP="x0,z0,size[,name]" renders an extra 1:1..4:1 crop of the surface map.
    /// </summary>
    public static class WorldPreview
    {
        static string CaptureDir => Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Captures");

        /// <summary>Full preview: maps + perspective renders (needs graphics: GFX=1).</summary>
        [MenuItem("MudRunner/World/Capture perspective views")]
        public static void Run() { WorldPreviewGfx.Run(); }

        [MenuItem("MudRunner/World/Generate and capture maps")]
        public static void Map()
        {
            try { MapInternal(); }
            catch (Exception e)
            {
                Debug.LogError("[MudRunner] WorldPreview.Map FAILED: " + e);
                if (Application.isBatchMode) EditorApplication.Exit(1);
            }
        }

        public static void LogTimings(GeneratedWorld gw)
        {
            var sb = new StringBuilder("[MudRunner] World generation ms:");
            foreach (var kv in gw.timings) sb.Append(' ').Append(kv.Key).Append('=').Append(kv.Value.ToString("F0"));
            Debug.Log(sb.ToString());
        }

        public static void LogRouteStats(GeneratedWorld gw)
        {
            foreach (var t in gw.tracks.tracks)
            {
                var pts = gw.sites.polylines[t.name];
                var st = RouteStats.Compute(t.name, pts, gw.map);
                Debug.Log("[MudRunner] ROUTE " + st);
                var prof = Environment.GetEnvironmentVariable("WORLD_PROFILE");
                if (!string.IsNullOrEmpty(prof) && prof.Contains(t.name))
                {
                    var sb = new StringBuilder("[MudRunner] PROFILE " + t.name + ":");
                    for (int i = 0; i < t.n; i += 20)
                    {
                        float g = i + 5 < t.n ? (t.y[i + 5] - t.y[i]) / Mathf.Max(0.1f, t.s[i + 5] - t.s[i]) : 0f;
                        sb.Append("\n  s=").Append(t.s[i].ToString("F0")).Append(" (").Append(t.x[i].ToString("F0")).Append(",").Append(t.z[i].ToString("F0")).Append(") y=").Append(t.y[i].ToString("F1"))
                          .Append(" grade=").Append((g * 100f).ToString("F0")).Append("% kind=").Append((TKind)t.kind[i]).Append(" surf=").Append((SurfaceType)t.surfA[i]);
                    }
                    Debug.Log(sb.ToString());
                }
            }
        }

        static void MapInternal()
        {
            Directory.CreateDirectory(CaptureDir);
            var cfg = new WorldGenConfig();
            var sw = Stopwatch.StartNew();
            var gw = WorldGenerator.Generate(cfg);
            Debug.Log("[MudRunner] Generate(full) wall time " + sw.ElapsedMilliseconds + " ms; map " + gw.map.size + "^2, height " + gw.map.minHeight.ToString("F1") + ".." + gw.map.maxHeight.ToString("F1"));
            LogTimings(gw);
            LogRouteStats(gw);
            WriteMaps(gw, "world");
            var crop = Environment.GetEnvironmentVariable("WORLD_CROP");
            if (!string.IsNullOrEmpty(crop))
            {
                foreach (var spec in crop.Split(';'))
                {
                    var p = spec.Split(',');
                    if (p.Length < 3) continue;
                    float cx = float.Parse(p[0]), cz = float.Parse(p[1]), size = float.Parse(p[2]);
                    string name = p.Length > 3 ? p[3] : "crop";
                    WriteCrop(gw, cx, cz, size, name);
                }
            }
            Debug.Log("[MudRunner] WorldPreview.Map finished OK");
        }

        public static void WriteMaps(GeneratedWorld gw, string prefix)
        {
            var map = gw.map;
            int s = map.size;
            // surface + routes
            var surf = WorldMapImages.RenderBase(map, 0, 0, s, s, 1, 0);
            var bare = (Color32[])surf.Clone();
            WorldMapImages.Overlay(surf, s, s, map.origin.x, map.origin.y, 1f, gw, true, 3);
            var legend = new List<string>();
            WorldMapImages.DrawSites(surf, s, s, map.origin.x, map.origin.y, 1f, gw, legend, 2);
            WorldMapImages.Save(Path.Combine(CaptureDir, prefix + "_surface.png"), surf, s, s);
            WorldMapImages.Save(Path.Combine(CaptureDir, prefix + "_surface_clean.png"), bare, s, s);
            var relief = WorldMapImages.RenderBase(map, 0, 0, s, s, 1, 1);
            WorldMapImages.Overlay(relief, s, s, map.origin.x, map.origin.y, 1f, gw, false, 2);
            WorldMapImages.Save(Path.Combine(CaptureDir, prefix + "_relief.png"), relief, s, s);
            var slope = WorldMapImages.RenderBase(map, 0, 0, s, s, 1, 2);
            WorldMapImages.Overlay(slope, s, s, map.origin.x, map.origin.y, 1f, gw, false, 2);
            WorldMapImages.Save(Path.Combine(CaptureDir, prefix + "_slope.png"), slope, s, s);
            Debug.Log("[MudRunner] MAP legend: " + string.Join(" | ", legend));
        }

        public static void WriteCrop(GeneratedWorld gw, float cx, float cz, float size, string name)
        {
            var map = gw.map;
            int px = 1536;
            float scale = px / size;
            // sample the map at 1 m but upscale by nearest: render at map resolution then enlarge
            int n = Mathf.Max(16, Mathf.CeilToInt(size));
            int x0 = Mathf.RoundToInt(cx - size * 0.5f - map.origin.x), z0 = Mathf.RoundToInt(cz - size * 0.5f - map.origin.y);
            var small = WorldMapImages.RenderBase(map, x0, z0, n, n, 1, 0);
            var big = new Color32[px * px];
            for (int j = 0; j < px; j++)
                for (int i = 0; i < px; i++)
                    big[j * px + i] = small[Mathf.Min(n - 1, (int)(j / scale)) * n + Mathf.Min(n - 1, (int)(i / scale))];
            WorldMapImages.Overlay(big, px, px, cx - size * 0.5f, cz - size * 0.5f, scale, gw, true, Mathf.Max(2, Mathf.RoundToInt(scale * 3)));
            WorldMapImages.Save(Path.Combine(CaptureDir, "world_" + name + ".png"), big, px, px);
            var rel = WorldMapImages.RenderBase(map, x0, z0, n, n, 1, 1);
            var bigR = new Color32[px * px];
            for (int j = 0; j < px; j++)
                for (int i = 0; i < px; i++)
                    bigR[j * px + i] = rel[Mathf.Min(n - 1, (int)(j / scale)) * n + Mathf.Min(n - 1, (int)(i / scale))];
            WorldMapImages.Save(Path.Combine(CaptureDir, "world_" + name + "_relief.png"), bigR, px, px);
        }
    }
}
