using System;
using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Builds the list of structures (buildings, bridges, signs, winch anchors, dynamic logs/barrels ...) of the wilderness.
    /// Positions come from <see cref="WorldLayout"/> and the generated tracks; heights are snapped to the generated ground.
    /// </summary>
    public static class StructurePlacer
    {
        sealed class B
        {
            public GeneratedWorld gw; public GroundMap map; public PropSet set; public WorldSites ws; public uint seed;
            public List<StructureDef> list => set.structures;

            public float Gy(float x, float z) { return map.SampleHeight(x, z); }

            public void Add(string id, float x, float z, float yaw, float scale = 1f, bool dynamic = false, string text = null, string tag = null, float lift = 0f)
            {
                list.Add(new StructureDef { id = id, pos = new Vector3(x, Gy(x, z) + lift, z), rot = Quaternion.Euler(0f, yaw, 0f), scale = scale, dynamic = dynamic, text = text, tag = tag });
            }

            public void AddAnchorPost(float x, float z, float yaw)
            {
                list.Add(new StructureDef { id = "post_anchor", pos = new Vector3(x, Gy(x, z), z), rot = Quaternion.Euler(0f, yaw, 0f), scale = 1f, anchor = true, anchorPull = 120000f, anchorLocal = new Vector3(0f, 1.0f, 0.22f), tag = "anchor:post" });
                ws.anchors.Add(new WorldSites.AnchorInfo { position = new Vector3(x, Gy(x, z) + 1f, z), kind = "post" });
            }

            public void AddAnchorTree(float x, float z, float yaw)
            {
                list.Add(new StructureDef { id = "spruce_b", pos = new Vector3(x, Gy(x, z) - 0.05f, z), rot = Quaternion.Euler(0f, yaw, 0f), scale = 1.05f, anchor = true, anchorPull = 0f, anchorLocal = new Vector3(0f, 0.9f, 0.18f), tag = "anchor:tree" });
                ws.anchors.Add(new WorldSites.AnchorInfo { position = new Vector3(x, Gy(x, z) + 0.9f, z), kind = "tree" });
            }

            public void LogPile(float x, float z, float yaw, int rows, string id = "log_long")
            {
                float gy = Gy(x, z);
                Quaternion q = Quaternion.Euler(0f, yaw, 0f);
                for (int r = 0; r < rows; r++)
                {
                    int cnt = rows - r + 1;
                    for (int k = 0; k < cnt; k++)
                    {
                        Vector3 loc = new Vector3((-(cnt - 1) * 0.5f + k) * 0.64f, 0.33f + r * 0.55f + 0.03f, ((k + r) % 2 == 0 ? 0f : 0.25f));
                        list.Add(new StructureDef { id = id, pos = new Vector3(x, gy, z) + q * loc, rot = q, scale = 1f, dynamic = true, tag = "log" });
                    }
                }
            }
        }

        static float Hash(int a, int b, uint s) { return WorldNoise.Hash01(a, b, s); }

        public static void Build(GeneratedWorld gw, PropSet set)
        {
            var b = new B { gw = gw, map = gw.map, set = set, ws = gw.sites, seed = gw.cfg.seed };
            if (gw.cfg.full) WildernessStructures(b);
            ProvingGroundPlacer.Build(gw, set, b.ws);
        }

        static void WildernessStructures(B b)
        {
            var gw = b.gw; var ws = gw.sites; var map = gw.map;

            // ---------------------------------------------------------------- base camp
            Vector2 bc = WorldLayout.BaseCamp;
            b.Add("garage", -622f, -577f, 0f, tag: "garage");
            b.Add("fuel_station", -571f, -580f, 90f, tag: "fuel");
            b.Add("tent", -628f, -541f, 20f); b.Add("tent", -631f, -531f, -30f); b.Add("tent", -622f, -526f, 80f);
            for (int i = 0; i < 4; i++) b.Add("crate", -611.5f + (i % 2) * 1.02f, -578f - (i / 2) * 1.02f, i * 11f, dynamic: true);
            string[] bcol = { "Red", "Blue", "Green", "Red", "Orange", "Blue" };
            for (int i = 0; i < 6; i++) b.Add("barrel:" + bcol[i], -557f + (i % 3) * 0.7f, -551f - (i / 3) * 0.75f, i * 23f, dynamic: true);
            b.Add("barrel:Red", -631f, -565f, 0f, dynamic: true); b.Add("barrel:Blue", -632f, -566f, 0f, dynamic: true);
            for (int i = 0; i < 5; i++) b.Add("fence", -590f + i * 3.1f, -592f, 0f);
            for (int i = 0; i < 3; i++) b.Add("fence", -637f, -551f + i * 3.1f, 90f);
            b.AddAnchorPost(-606f, -536f, 20f); b.AddAnchorPost(-584f, -567f, -40f); b.AddAnchorPost(-643f, -562f, 100f); b.AddAnchorPost(-596f, -586f, 160f);
            ws.Add("GarageEntrance", new Vector3(-622f, b.Gy(-622f, -566f), -566f), 6f, 0f);
            ws.garageZones.Add(new WorldSites.GarageZoneInfo { name = "Base camp garage", position = new Vector3(-618f, b.Gy(-618f, -566f), -566f), radius = 22f });
            ws.cargoSpawns.Add(new WorldSites.SpawnPoint { name = "cargo1", position = new Vector3(-612f, b.Gy(-612f, -553f), -553f), yaw = 0f });
            ws.cargoSpawns.Add(new WorldSites.SpawnPoint { name = "cargo2", position = new Vector3(-606f, b.Gy(-606f, -549f), -549f), yaw = 0f });
            ws.cargoSpawns.Add(new WorldSites.SpawnPoint { name = "cargo3", position = new Vector3(-600f, b.Gy(-600f, -545f), -545f), yaw = 0f });
            ws.trailerSpawns.Add(new WorldSites.SpawnPoint { name = "trailer1", position = new Vector3(-598f, b.Gy(-598f, -562f), -562f), yaw = 0f });
            ws.trailerSpawns.Add(new WorldSites.SpawnPoint { name = "trailer2", position = new Vector3(-585f, b.Gy(-585f, -580f), -580f), yaw = 90f });

            // route signs at the camp exits
            foreach (var r in ws.routes)
            {
                string key = r.id == 1 ? "NORTH ROAD" : r.id == 2 ? "CENTRAL TRACK" : "SWAMP SHORTCUT";
                var pts = r.points;
                Vector3 p = pts[Mathf.Min(pts.Length - 1, 14)];
                Vector3 q = pts[Mathf.Min(pts.Length - 1, 20)];
                float yaw = Mathf.Atan2(q.x - p.x, q.z - p.z) * Mathf.Rad2Deg;
                Vector3 side = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * 6f;
                b.Add("sign_arrow", p.x + side.x, p.z + side.z, yaw - 90f, text: key + "  " + (r.length / 1000f).ToString("F1") + " km", tag: "routesign:" + r.id);
            }
            b.Add("sign_arrow", -592f, -540f, 90f, text: "PROVING GROUND >>", tag: "pgsign");
            foreach (var s in WorldLayout.BuildSigns()) b.Add(s.id, s.x, s.z, s.yaw, text: s.text);

            // ---------------------------------------------------------------- cabin island
            b.Add("cabin", 552f, 488f, 0f, tag: "cabin");
            b.Add("woodpile", 568f, 478f, 90f); b.Add("crate", 538f, 472f, 12f, dynamic: true); b.Add("crate", 538.9f, 472.4f, 40f, dynamic: true); b.Add("barrel:Green", 574f, 492f, 0f, dynamic: true);
            float[,] ip = { { 530, 468 }, { 572, 466 }, { 528, 497 }, { 576, 500 }, { 551, 459 }, { 562, 468 }, { 540, 507 }, { 566, 509 } };
            for (int i = 0; i < ip.GetLength(0); i++) b.AddAnchorPost(ip[i, 0], ip[i, 1], i * 33f);
            float[,] it = { { 524, 484 }, { 580, 482 }, { 546, 450 }, { 560, 512 } };
            for (int i = 0; i < it.GetLength(0); i++) b.AddAnchorTree(it[i, 0], it[i, 1], i * 70f);

            // ---------------------------------------------------------------- logging landing
            b.LogPile(-166f, 406f, 15f, 4); b.LogPile(-134f, 402f, 12f, 4); b.LogPile(-150f, 436f, 98f, 3);
            b.Add("woodpile", -178f, 428f, 90f); b.Add("woodpile", -122f, 430f, 20f);
            b.Add("barrel:Orange", -141f, 421f, 0f, dynamic: true); b.Add("barrel:Red", -140f, 420f, 0f, dynamic: true); b.Add("barrel:Blue", -141.6f, 419.5f, 0f, dynamic: true);
            b.Add("crate", -156f, 421f, 10f, dynamic: true); b.Add("crate", -156f, 422.1f, 30f, dynamic: true);
            b.AddAnchorPost(-170f, 424f, 0f); b.AddAnchorPost(-129f, 413f, 90f); b.AddAnchorTree(-148f, 453f, 30f);

            // ---------------------------------------------------------------- sawmill ruin
            b.Add("sawmill", -300f, -200f, 20f, tag: "sawmill");
            for (int i = 0; i < 6; i++) b.Add(i % 2 == 0 ? "log_long" : "log_short", -278f + i * 1.3f, -186f + (i % 3) * 3.2f, 70f + i * 14f, dynamic: true, lift: 0.4f);
            b.AddAnchorPost(-322f, -178f, 0f); b.AddAnchorPost(-278f, -216f, 40f);

            // ---------------------------------------------------------------- pump station
            b.Add("pump_house", 598f, -252f, 90f, tag: "pump");
            for (int i = 0; i < 4; i++) b.Add("barrel:" + (i % 2 == 0 ? "Blue" : "Red"), 586f + (i % 2) * 0.7f, -240f - (i / 2) * 0.7f, i * 20f, dynamic: true);
            for (int i = 0; i < 4; i++) b.Add("fence", 580f + i * 3.1f, -233f, 0f);
            b.AddAnchorPost(612f, -236f, 0f); b.AddAnchorPost(583f, -264f, 90f);

            // ---------------------------------------------------------------- watchtower / radio mast
            b.Add("watchtower", -450f, 480f, 0f, tag: "watchtower");
            for (int i = 0; i < 3; i++) b.Add("fence", -441f + i * 3.1f, 470f, 0f);
            b.AddAnchorPost(-460f, 470f, 0f);
            b.Add("radio_mast", 100f, 600f, 0f, tag: "radiomast");
            for (int i = 0; i < 3; i++) b.Add("fence", 110f, 590f + i * 3.1f, 90f);
            b.Add("barrel:Red", 92f, 594f, 0f, dynamic: true);

            // ---------------------------------------------------------------- bridges + causeway
            foreach (var br in ws.bridges)
            {
                bool cause = br.name.Contains("causeway");
                string id = cause ? "causeway:" + br.length.ToString("F1", System.Globalization.CultureInfo.InvariantCulture)
                                  : "bridge_intact:" + br.length.ToString("F1", System.Globalization.CultureInfo.InvariantCulture) + (br.name.Contains("B1") ? ":old" : "");
                var sd = new StructureDef { id = id, pos = br.center + Vector3.up * 0.02f, rot = Quaternion.Euler(0f, br.yaw, 0f), scale = 1f, tag = "bridge:" + br.name + "|" + br.maxLoadKg.ToString("F0") };
                list(b).Add(sd);
            }
            // broken planked bridge next to the south creek ford
            {
                float x = -66f, z = -492f;
                float hy = 0.5f * (b.Gy(x - 9f, z) + b.Gy(x + 9f, z));
                list(b).Add(new StructureDef { id = "bridge_broken:15", pos = new Vector3(x, hy + 0.02f, z), rot = Quaternion.Euler(0f, 90f, 0f), scale = 1f, tag = "bridge:Broken bridge|0" });
                ws.bridges.Add(new WorldSites.BridgeInfo { name = "Broken bridge", center = new Vector3(x, hy, z), yaw = 90f, length = 15f, width = 4.2f, maxLoadKg = 0f, fragile = true, broken = true });
                b.Add("sign_warn", -74f, -486f, 90f, text: "BRIDGE OUT");
            }

            // ---------------------------------------------------------------- fords: depth poles
            foreach (var f in ws.fords)
            {
                Vector3 side = Quaternion.Euler(0, f.yaw + 90f, 0) * Vector3.forward;
                float off = 3.4f;
                b.Add("depth_pole", f.center.x + side.x * off, f.center.z + side.z * off, 0f, tag: "depthpole");
                b.Add("depth_pole", f.center.x - side.x * off, f.center.z - side.z * off, 0f, tag: "depthpole");
            }

            // ---------------------------------------------------------------- junction signs + route markers
            foreach (var t in gw.tracks.tracks)
            {
                if (!string.IsNullOrEmpty(t.def.parent))
                {
                    var parent = gw.tracks.Find(t.def.parent);
                    if (parent != null)
                    {
                        int j = Mathf.Min(t.n - 1, 4);
                        float yaw = Mathf.Atan2(t.x[j] - t.x[0], t.z[j] - t.z[0]) * Mathf.Rad2Deg;
                        Vector3 side = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * (t.halfW[0] + 3.5f);
                        b.Add("sign_arrow", t.x[0] + side.x, t.z[0] + side.z, yaw - 90f, text: t.def.display, tag: "junction:" + t.name);
                    }
                }
                if (t.name == "service")
                {
                    // signposted gravel track to the proving ground
                    for (float s = 220f; s < t.Length - 60f; s += 260f)
                    {
                        int i = Mathf.Clamp(Mathf.RoundToInt(s / TrackBuilder.Spacing), 2, t.n - 3);
                        if (t.kind[i] != 0) continue;
                        float yaw = Mathf.Atan2(t.x[i + 1] - t.x[i - 1], t.z[i + 1] - t.z[i - 1]) * Mathf.Rad2Deg;
                        Vector3 side = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * (t.halfW[i] + 3f);
                        b.Add("sign_arrow", t.x[i] + side.x, t.z[i] + side.z, yaw - 90f, text: "PROVING GROUND >> " + ((t.Length - s) / 1000f).ToString("F1") + " km", tag: "pgsign");
                    }
                }
                if (t.def.routeId >= 1 || t.name == "service")
                {
                    string col = t.def.routeId == 1 ? "Blue" : t.def.routeId == 2 ? "Yellow" : t.def.routeId == 3 ? "Red" : "White";
                    int k = 0;
                    for (float s = 70f; s < t.Length - 20f; s += 130f, k++)
                    {
                        int i = Mathf.Clamp(Mathf.RoundToInt(s / TrackBuilder.Spacing), 1, t.n - 2);
                        if (t.kind[i] != 0) continue;
                        float yaw = Mathf.Atan2(t.x[i + 1] - t.x[i - 1], t.z[i + 1] - t.z[i - 1]) * Mathf.Rad2Deg;
                        float sd = (k % 2 == 0 ? 1f : -1f) * (t.halfW[i] + 1.6f);
                        Vector3 side = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * sd;
                        b.Add("marker_post:" + col, t.x[i] + side.x, t.z[i] + side.z, 0f, tag: "marker:" + t.name);
                    }
                }
            }

            // ---------------------------------------------------------------- winch anchors along the harder routes + loose logs
            foreach (var t in gw.tracks.tracks)
            {
                bool dense = t.name == "central" || t.name == "swamp" || t.name == "mid_link" || t.name == "old_road";
                bool sparse = t.name == "north" || t.name == "swamp_bridge" || t.name == "service" || t.name == "logging_link";
                if (!dense && !sparse) continue;
                float step = dense ? 52f : 150f;
                int ai = 0;
                for (float s = 35f; s < t.Length - 15f; s += step * (0.75f + 0.5f * Hash(ai, t.index, b.seed + 7u)), ai++)
                {
                    int i = Mathf.Clamp(Mathf.RoundToInt(s / TrackBuilder.Spacing), 2, t.n - 3);
                    if (t.kind[i] != 0 || t.kind[i - 2] != 0 || t.kind[i + 2] != 0) continue;
                    var surfA = (SurfaceType)t.surfA[i];
                    bool mud = surfA == SurfaceType.ShallowMud || surfA == SurfaceType.DeepMud || surfA == SurfaceType.Bog;
                    if (sparse && !mud && ai % 3 != 0) continue;
                    float yaw = Mathf.Atan2(t.x[i + 1] - t.x[i - 1], t.z[i + 1] - t.z[i - 1]) * Mathf.Rad2Deg;
                    float side = (ai % 2 == 0 ? 1f : -1f) * (t.halfW[i] + 2.4f + 1.4f * Hash(ai, i, b.seed + 8u));
                    Vector3 off = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * side;
                    float x = t.x[i] + off.x, z = t.z[i] + off.z;
                    float wl = gw.water != null ? gw.water.level[map.Index(Mathf.RoundToInt(x - map.origin.x), Mathf.RoundToInt(z - map.origin.y))] : float.NegativeInfinity;
                    if (wl > b.Gy(x, z) - 0.2f) continue;
                    if (map.SampleSlopeDegrees(x, z) > 28f) continue;
                    if (mud && Hash(ai, i, b.seed + 9u) < 0.55f) b.AddAnchorPost(x, z, yaw + 90f);
                    else b.AddAnchorTree(x, z, Hash(ai, i, b.seed + 10u) * 360f);
                }
                // loose logs and stumps by the road
                if (dense || t.name == "north")
                {
                    int cnt = dense ? 9 : 6;
                    for (int k = 0; k < cnt; k++)
                    {
                        float s = (k + 0.5f + 0.4f * Hash(k, t.index, b.seed + 12u)) / cnt * t.Length;
                        int i = Mathf.Clamp(Mathf.RoundToInt(s / TrackBuilder.Spacing), 2, t.n - 3);
                        if (t.kind[i] != 0) continue;
                        float yaw = Mathf.Atan2(t.x[i + 1] - t.x[i - 1], t.z[i + 1] - t.z[i - 1]) * Mathf.Rad2Deg;
                        float sd = (Hash(k, i, b.seed + 13u) < 0.5f ? 1f : -1f) * (t.halfW[i] + 1.9f + 1.5f * Hash(k, i, b.seed + 14u));
                        Vector3 off = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * sd;
                        float x = t.x[i] + off.x, z = t.z[i] + off.z;
                        if (map.SampleSlopeDegrees(x, z) > 20f) continue;
                        b.Add(Hash(k, i, b.seed + 15u) < 0.45f ? "log_long" : "log_short", x, z, yaw + (Hash(k, i, b.seed + 16u) < 0.5f ? 0f : 90f) + (Hash(k, i, b.seed + 17u) - 0.5f) * 30f, dynamic: true, lift: 0.45f);
                    }
                }
            }

            // bog approach posts: the final stretch of the swamp route and the central track (easy hooks for recovery)
            var sw = gw.tracks.Find("swamp");
            if (sw != null)
            {
                for (float s = sw.Length - 210f; s < sw.Length - 12f; s += 26f)
                {
                    int i = Mathf.Clamp(Mathf.RoundToInt(s / TrackBuilder.Spacing), 2, sw.n - 3);
                    float yaw = Mathf.Atan2(sw.x[i + 1] - sw.x[i - 1], sw.z[i + 1] - sw.z[i - 1]) * Mathf.Rad2Deg;
                    float sd = (((int)(s / 26f)) % 2 == 0 ? 1f : -1f) * (sw.halfW[i] + 2.6f);
                    Vector3 off = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * sd;
                    b.AddAnchorPost(sw.x[i] + off.x, sw.z[i] + off.z, yaw + 90f);
                }
            }
            var ce = gw.tracks.Find("central");
            if (ce != null)
            {
                for (float s = ce.Length - 130f; s < ce.Length - 10f; s += 26f)
                {
                    int i = Mathf.Clamp(Mathf.RoundToInt(s / TrackBuilder.Spacing), 2, ce.n - 3);
                    float yaw = Mathf.Atan2(ce.x[i + 1] - ce.x[i - 1], ce.z[i + 1] - ce.z[i - 1]) * Mathf.Rad2Deg;
                    float sd = (((int)(s / 26f)) % 2 == 0 ? 1f : -1f) * (ce.halfW[i] + 2.6f);
                    Vector3 off = Quaternion.Euler(0, yaw + 90f, 0) * Vector3.forward * sd;
                    b.AddAnchorPost(ce.x[i] + off.x, ce.z[i] + off.z, yaw + 90f);
                }
            }
        }

        static List<StructureDef> list(B b) { return b.set.structures; }
    }
}
