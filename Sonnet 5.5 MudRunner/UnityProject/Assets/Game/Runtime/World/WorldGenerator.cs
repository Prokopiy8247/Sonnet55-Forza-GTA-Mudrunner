using System;
using System.Collections.Generic;
using System.Diagnostics;
using MudRunner.Ground;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Pure-data world generation (no GameObjects): terrain + water + roads, named sites and routes, and the prop placement lists.
    /// <see cref="WildernessBuilder"/> / <see cref="ProvingGroundBuilder"/> instantiate the result into the scene.
    /// </summary>
    public static class WorldGenerator
    {
        public static GeneratedWorld Generate(WorldGenConfig cfg = null)
        {
            cfg = cfg ?? new WorldGenConfig();
            var total = Stopwatch.StartNew();
            var gen = new TerrainGenerator(cfg);
            var gw = gen.Generate();
            var sw = Stopwatch.StartNew();
            FillSites(gw);
            gw.timings["sites"] = sw.Elapsed.TotalMilliseconds; sw.Restart();
            if (cfg.props)
            {
                gw.props = PropPlacement.Place(gw);
                gw.timings["props"] = sw.Elapsed.TotalMilliseconds;
            }
            gw.roadEdge = null;
            gw.timings["TOTAL"] = total.Elapsed.TotalMilliseconds;
            return gw;
        }

        static Vector3 OnGround(GroundMap map, float x, float z) { return new Vector3(x, map.SampleHeight(x, z), z); }

        static void FillSites(GeneratedWorld gw)
        {
            var map = gw.map; var ws = gw.sites;
            if (gw.cfg.full)
            {
                foreach (var s in WorldLayout.BuildSites()) ws.Add(s.name, OnGround(map, s.x, s.z), s.r);
                var ps = WorldLayout.PlayerStart;
                ws.playerStart = OnGround(map, ps.x, ps.z); ws.playerYaw = WorldLayout.PlayerYaw;
            }
            foreach (var t in gw.tracks.tracks)
            {
                var pts = new Vector3[t.n];
                for (int i = 0; i < t.n; i++) pts[i] = new Vector3(t.x[i], t.y[i], t.z[i]);
                ws.polylines[t.name] = pts;
            }
            var routeNames = new[] { "", "Route 1: North road", "Route 2: Central track", "Route 3: Swamp shortcut" };
            var risk = new[] { "", "low risk, long", "medium risk, ford and mud", "high risk, short: steep mud, deep crossing, bog" };
            var colors = new[] { Color.white, new Color(0.15f, 0.5f, 1f), new Color(1f, 0.9f, 0.1f), new Color(1f, 0.2f, 0.2f) };
            foreach (var t in gw.tracks.tracks)
            {
                int id = t.def.routeId;
                if (id < 1 || id > 3) continue;
                var pts = ws.polylines[t.name];
                ws.routes.Add(new WorldSites.RouteInfo { id = id, name = routeNames[id], risk = risk[id], points = pts, length = WorldSites.PolylineLength(pts), color = colors[id], description = t.def.display });
            }
            foreach (var tp in gw.traps) ws.traps.Add(new WorldSites.TrapInfo { name = tp.name, position = OnGround(map, tp.x, tp.z), radius = tp.r, depth = tp.depth, decoy = tp.decoy });
            // fords + bridges from the track kinds
            foreach (var t in gw.tracks.tracks)
            {
                foreach (var run in TrackBuilder.Runs(t, TKind.Ford))
                {
                    int m = (run.a + run.b) / 2;
                    float len = t.s[run.b] - t.s[run.a];
                    float depth = 0f; float cur = 0f;
                    for (int i = run.a; i <= run.b; i++)
                    {
                        if (map.water != null)
                        {
                            float wd = map.water.Depth(t.x[i], t.z[i], map.SampleHeight(t.x[i], t.z[i]));
                            if (wd > depth) depth = wd;
                            if (map.water.Sample(t.x[i], t.z[i], out _, out var fl)) cur = Mathf.Max(cur, fl.magnitude);
                        }
                    }
                    ws.fords.Add(new WorldSites.FordInfo { name = t.name + " ford", center = new Vector3(t.x[m], map.SampleHeight(t.x[m], t.z[m]), t.z[m]), yaw = t.Yaw(m), depth = depth, length = len, current = cur });
                }
                foreach (var run in TrackBuilder.Runs(t, TKind.Bridge))
                {
                    int a = run.a, b = Mathf.Min(t.n - 1, run.b + 1);
                    Vector3 pa = t.Point(a), pb = t.Point(b);
                    Vector3 c = (pa + pb) * 0.5f;
                    float len = Vector2.Distance(new Vector2(pa.x, pa.z), new Vector2(pb.x, pb.z));
                    if (t.name != "pg_bridge") len += 10f;                     // overshoot the soft banks by 5 m on each side
                    float yaw = Mathf.Atan2(pb.x - pa.x, pb.z - pa.z) * Mathf.Rad2Deg;
                    string nm = t.name == "old_road" ? "Old bridge B1" : t.name == "swamp_bridge" ? "Bridge B2" : t.name + " bridge";
                    float load = t.name == "old_road" ? 3500f : 5500f;
                    ws.bridges.Add(new WorldSites.BridgeInfo { name = nm, center = c, yaw = yaw, length = len, width = 4f, maxLoadKg = load, fragile = true });
                }
                foreach (var run in TrackBuilder.Runs(t, TKind.Causeway))
                {
                    int a = run.a, b = Mathf.Min(t.n - 1, run.b + 1);
                    Vector3 pa = t.Point(a), pb = t.Point(b);
                    ws.bridges.Add(new WorldSites.BridgeInfo { name = "Swamp causeway", center = (pa + pb) * 0.5f, yaw = Mathf.Atan2(pb.x - pa.x, pb.z - pa.z) * Mathf.Rad2Deg,
                        length = Vector2.Distance(new Vector2(pa.x, pa.z), new Vector2(pb.x, pb.z)), width = 3.6f, maxLoadKg = 6500f, fragile = true });
                }
            }
        }
    }
}
