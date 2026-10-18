using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Ground;
using UnityEngine;
using static MudRunner.WorldGen.PgLayout;

namespace MudRunner.WorldGen
{
    /// <summary>Structures, signs, anchors, dynamic props and named sites of the proving ground.</summary>
    public static class ProvingGroundPlacer
    {
        sealed class B
        {
            public GeneratedWorld gw; public GroundMap map; public PropSet set; public WorldSites ws;
            public float Gy(float x, float z) { return map.SampleHeight(x, z); }

            public void Add(string id, float x, float z, float yaw, bool dynamic = false, string text = null, string tag = null, float lift = 0f, float scale = 1f)
            {
                set.structures.Add(new StructureDef { id = id, pos = new Vector3(x, Gy(x, z) + lift, z), rot = Quaternion.Euler(0f, yaw, 0f), scale = scale, dynamic = dynamic, text = text, tag = tag });
            }
            public void Post(float x, float z, float yaw)
            {
                set.structures.Add(new StructureDef { id = "post_anchor", pos = new Vector3(x, Gy(x, z), z), rot = Quaternion.Euler(0f, yaw, 0f), scale = 1f, anchor = true, anchorPull = 120000f, anchorLocal = new Vector3(0f, 1.0f, 0.22f), tag = "anchor:post" });
                ws.anchors.Add(new WorldSites.AnchorInfo { position = new Vector3(x, Gy(x, z) + 1f, z), kind = "post" });
            }
            public void Tree(float x, float z, float yaw)
            {
                set.structures.Add(new StructureDef { id = "spruce_b", pos = new Vector3(x, Gy(x, z) - 0.05f, z), rot = Quaternion.Euler(0f, yaw, 0f), scale = 1.05f, anchor = true, anchorPull = 0f, anchorLocal = new Vector3(0f, 0.9f, 0.18f), tag = "anchor:tree" });
                ws.anchors.Add(new WorldSites.AnchorInfo { position = new Vector3(x, Gy(x, z) + 0.9f, z), kind = "tree" });
            }
        }

        public static void Build(GeneratedWorld gw, PropSet set, WorldSites ws)
        {
            var b = new B { gw = gw, map = gw.map, set = set, ws = ws };
            var map = gw.map;
            if (!map.Contains(SpineX, 0f)) return;

            // ---- sites
            Vector3 P(float x, float z) { return new Vector3(x, map.SampleHeight(x, z), z); }
            ws.Add("PGStart", P(850f, -245f), 22f, 0f);
            ws.Add("PGStraight", P(850f, -175f), 55f, 0f);
            ws.Add("PGMudPits", P(850f, -30f), 85f, 0f);
            ws.Add("PGMudHill", P(HillX, HillZ0 - 12f), 40f, 0f);
            ws.Add("PGSideSlope", P((SideX0 + SideX1) * 0.5f, SideZ), 28f, 90f);
            ws.Add("PGArticulation", P(850f, (ArtZ0 + ArtZ1) * 0.5f), 30f, 0f);
            ws.Add("PGFord", P(850f, (FordZ0 + FordZ1) * 0.5f), 30f, 0f);
            ws.Add("PGLogPile", P(LogPile.x, LogPile.y), 24f, 0f);
            ws.Add("PGMeasuring", P(MeasCenter.x, MeasCenter.y), 34f, 0f);
            ws.Add("PGGarage", P(897f, -248f), 16f, 270f);
            foreach (var f in new[] { "start/measure pad with painted grid", "100 m straight with distance poles", "6 mud pits (shallow to bog with hidden depth)", "steep mud hill 12/20/28 deg",
                                       "side-slope track 14-18 deg", "axle articulation course", "river ford 36 m (0.4-1.6 m deep, 1.5 m/s)", "log pile and sandbox", "measuring area with marker cones" })
                ws.provingGroundFeatures.Add(f);
            if (!gw.cfg.full)
            {
                ws.AddGoal("Proving ground start", P(850f, -245f), 22f);
                ws.AddGoal("Mud pits", P(SpineX, PitZ0(PitCount - 1) + PitLen + PitGap * 0.5f + 4f), 22f);                  // end of the lane, past pit 6
                ws.AddGoal("Mud hill", P(HillX, 0.5f * (HillZ(3) + HillZ(4))), 22f);                                            // plateau on top of the three steps
                ws.AddGoal("Side slope", P(0.5f * (SideX0 + SideX1), SideZ), 22f);
                ws.AddGoal("Articulation", P(SpineX, ArtZ1 + 6f), 20f);
                ws.AddGoal("Ford", P(SpineX, FordZ1 + 12f), 22f);                                                                // far bank of the 36 m crossing
                ws.AddGoal("Log pile", P(LogPile.x, LogPile.y), 22f);
                ws.AddGoal("Measuring area", P(MeasCenter.x, MeasCenter.y), 30f);
            }
            ws.garageZones.Add(new WorldSites.GarageZoneInfo { name = "Proving ground garage", position = P(880f, -248f), radius = 24f });
            if (!gw.cfg.full)
            {
                ws.playerStart = P(Start.x, Start.y); ws.playerYaw = StartYaw;
            }
            ws.provingGroundBounds = new Rect(750f, -300f, 260f, 600f);                                       // strip incl. the pass the service road crosses
            ws.cargoSpawns.Add(new WorldSites.SpawnPoint { name = "pgcargo1", position = P(838f, -240f), yaw = 0f });
            ws.cargoSpawns.Add(new WorldSites.SpawnPoint { name = "pgcargo2", position = P(842f, -236f), yaw = 0f });
            ws.trailerSpawns.Add(new WorldSites.SpawnPoint { name = "pgtrailer", position = P(858f, -240f), yaw = 0f });

            // loop polyline for the map / tests
            var loop = new List<Vector3>();
            foreach (var n in new[] { "pg_entry", "pg_spine", "pg_east" })
            {
                var t = gw.tracks.Find(n);
                if (t == null) continue;
                for (int i = 0; i < t.n; i += 2) loop.Add(new Vector3(t.x[i], t.y[i], t.z[i]));
            }
            if (loop.Count > 0) ws.polylines["ProvingGroundLoop"] = loop.ToArray();

            // ---- start area
            b.Add("garage", 897f, -248f, 270f, tag: "garage");
            b.Add("fuel_station", 850f, -279f, 0f, tag: "fuel");
            string[] col = { "Red", "Blue", "Green", "Orange" };
            for (int i = 0; i < 4; i++) b.Add("barrel:" + col[i], 877f + (i % 2) * 0.7f, -268f - (i / 2) * 0.7f, i * 20f, dynamic: true);
            for (int i = 0; i < 3; i++) b.Add("crate", 882f, -268f + i * 0.0f, i * 11f, dynamic: true, lift: i * 0.92f);
            b.Add("sign_arrow", 820f, -204f, 30f, text: "PROVING GROUND", tag: "pgsign");
            b.Add("sign_arrow", 834f, -222f, 20f, text: "START / MEASURE AREA", tag: "pgsign");
            b.Post(828f, -262f, 0f); b.Post(872f, -262f, 0f); b.Post(828f, -228f, 0f); b.Post(872f, -228f, 0f);
            // distance poles (10 m) along the straight
            for (int k = 0; k <= 10; k++)
                b.Add("distance_pole", SpineX + 7.5f, StraightZ0 + 10f * k, 0f, text: (k * 10) + " m", tag: "distancepole");
            b.Add("sign_arrow", SpineX - 9f, StraightZ0 + 40f, 90f, text: "100 m STRAIGHT (0-100 m)", tag: "pgsign");

            // ---- mud pits
            for (int k = 0; k < PitCount; k++)
            {
                float z0 = PitZ0(k);
                b.Add("sign_warn", SpineX - 9.5f, z0 + 1.5f, 90f, text: "PIT " + (k + 1) + ": " + PitNames[k].ToUpperInvariant(), tag: "pgsign");
                for (int s = -1; s <= 1; s += 2)
                {
                    b.Add("depth_pole", SpineX + s * (PitHalfW + 0.8f), z0 + 3f, 0f, tag: "depthpole");
                    b.Add("depth_pole", SpineX + s * (PitHalfW + 0.8f), z0 + PitLen - 3f, 0f, tag: "depthpole");
                }
            }
            b.Post(SpineX - 9f, PitZ0(0) - 3f, 90f); b.Post(SpineX + 9f, PitZ0(0) - 3f, 270f);
            b.Post(SpineX - 9f, PitZ0(2) + PitLen + 4f, 90f); b.Post(SpineX + 9f, PitZ0(2) + PitLen + 4f, 270f);
            b.Post(SpineX - 9f, PitZ0(4) + PitLen + 4f, 90f); b.Post(SpineX + 9f, PitZ0(4) + PitLen + 4f, 270f);
            b.Post(SpineX - 9f, PitZ0(5) + PitLen + 5f, 90f); b.Post(SpineX + 9f, PitZ0(5) + PitLen + 5f, 270f);
            b.Tree(SpineX - 14f, PitZ0(3), 0f); b.Tree(SpineX + 14f, PitZ0(4), 0f);

            // ---- steep mud hill
            b.Add("sign_warn", HillX - 14f, HillZ0 - 6f, 90f, text: "STEEP MUD HILL 12 / 20 / 28 deg", tag: "pgsign");
            b.Add("sign_arrow", 890f, -108f, 0f, text: "MUD HILL >>", tag: "pgsign");
            float zt = HillZ(4) - 12f;
            b.Tree(HillX - 14.5f, zt, 10f); b.Tree(HillX + 14.5f, zt, 70f); b.Tree(HillX - 14.5f, zt + 10f, 130f); b.Tree(HillX + 14.5f, zt + 10f, 190f);
            b.Post(HillX - 5f, HillZ(4) - 4f, 0f); b.Post(HillX + 5f, HillZ(4) - 4f, 0f);
            b.Add("marker_post:White", HillX - 6f, HillZ(1), 0f); b.Add("marker_post:Yellow", HillX - 6f, HillZ(2), 0f); b.Add("marker_post:Red", HillX - 6f, HillZ(3), 0f);

            // ---- side slope
            b.Add("sign_warn", SideX0 - 10f, SideZ - 3f, 90f, text: "SIDE SLOPE 14-18 deg (40 m)", tag: "pgsign");
            b.Post(SideX0 - 2f, SideZ + 14f, 180f); b.Post(SideX1 + 2f, SideZ + 14f, 180f);
            b.Post(SideX0 + 20f, SideZ - 14f, 0f);

            // ---- articulation course: boulders alternate left/right, holes opposite
            b.Add("sign_warn", SpineX - 8f, ArtZ0 - 4f, 90f, text: "ARTICULATION COURSE 45 m", tag: "pgsign");
            for (int i = 0; i < ArtStations; i++)
            {
                ArtItems(i, out Vector2 boulder, out Vector2 hole);
                b.Add(i % 3 == 1 ? "rock_s" : "rock_m", boulder.x, boulder.y, i * 47f, scale: 0.95f + 0.05f * (i % 2), tag: "artboulder");
            }
            b.Post(SpineX - 7f, ArtZ1 + 4f, 90f);

            // ---- ford
            b.Add("sign_warn", SpineX - 8f, FordZ0 - 6f, 90f, text: "FORD 36 m  MAX 1.6 m  CURRENT 1.5 m/s", tag: "pgsign");
            b.Add("sign_warn", SpineX + 6f, FordZ1 + 6f, 270f, text: "FORD 36 m", tag: "pgsign");
            for (int i = 0; i < 6; i++)
            {
                float z = FordZ0 + 3f + i * 6f;
                b.Add("depth_pole", SpineX + 10.5f, z, 0f, tag: "depthpole");
            }
            b.Add("sign_arrow", 940f, 150f, -30f, text: "FORD BYPASS BRIDGE >>", tag: "pgsign");
            if (gw.map.Contains(985f, 208f))
            {
                float deckY = map.SampleHeight(985f, 180f) + 0.02f;
                set.structures.Add(new StructureDef { id = "bridge_intact:44", pos = new Vector3(985f, deckY, 208f), rot = Quaternion.identity, scale = 1f, tag = "bridge:PG ford bridge|12000" });
                ws.bridges.Add(new WorldSites.BridgeInfo { name = "PG ford bridge", center = new Vector3(985f, deckY, 208f), yaw = 0f, length = 44f, width = 4.2f, maxLoadKg = 12000f, fragile = false });
            }

            // ---- log pile and sandbox
            float lx = LogPile.x, lz = LogPile.y;
            {
                float gy = b.Gy(lx, lz);
                int[] rows = { 6, 5, 4, 3, 2 };
                for (int r = 0; r < rows.Length; r++)
                    for (int k = 0; k < rows[r]; k++)
                    {
                        Vector3 pos = new Vector3(lx + (-(rows[r] - 1) * 0.5f + k) * 0.64f, gy + 0.33f + r * 0.55f + 0.03f, lz + ((k + r) % 2 == 0 ? 0f : 0.3f));
                        set.structures.Add(new StructureDef { id = "log_long", pos = pos, rot = Quaternion.identity, scale = 1f, dynamic = true, tag = "log" });
                    }
            }
            float[,] st = { { 851, 244 }, { 858, 270 }, { 845, 284 }, { 822, 246 }, { 868, 278 }, { 815, 274 } };
            for (int i = 0; i < st.GetLength(0); i++) b.Add("stump", st[i, 0], st[i, 1], i * 60f, tag: "pgstump");
            b.Tree(826f, 278f, 0f); b.Tree(846f, 255f, 60f); b.Tree(864f, 243f, 120f); b.Tree(862f, 277f, 180f);
            b.Post(820f, 254f, 0f); b.Post(850f, 276f, 0f);
            for (int i = 0; i < 4; i++) b.Add("barrel:" + col[i], 842f + i * 0.8f, 248f, 0f, dynamic: true);
            for (int i = 0; i < 4; i++) b.Add("crate", 846f + (i % 2) * 1.0f, 252f + (i / 2) * 1.0f, i * 17f, dynamic: true);
            b.Add("sign_arrow", 842f, 244f, 90f, text: "LOG PILE / SANDBOX", tag: "pgsign");
            b.Add("sign_warn", (SandX0 + SandX1) * 0.5f, SandZ0 - 3f, 180f, text: "SANDBOX", tag: "pgsign");

            // ---- measuring area: grid of cones
            for (int i = 0; i < 5; i++)
                for (int j = 0; j < 5; j++)
                    b.Add("cone", MeasX0 + 4f + i * 12f, MeasZ0 + 4f + j * 12f, 0f, tag: "cone");
            b.Add("sign_arrow", MeasX0 - 2f, MeasZ0 - 3f, 90f, text: "MEASURING AREA (turning circle)", tag: "pgsign");
            b.Post(MeasX0 - 3f, MeasZ1 - 4f, 90f); b.Post(MeasX1 + 3f, MeasZ1 - 4f, 270f);
        }

        public static void AddPoints(GeneratedWorld gw, WorldData data)
        {
            var ws = gw.sites; var map = gw.map;
            if (!map.Contains(SpineX, 0f)) return;
            void Add(string name, float x, float z, float yaw) { data.points.Add(new WorldPoint(name, new Vector3(x, map.SampleHeight(x, z), z), yaw)); }
            Add("Proving ground start", Start.x, Start.y, StartYaw);
            Add("Mud pits", SpineX, PitZ0(0) - 14f, 0f);
            Add("Mud hill", HillX, HillZ0 - 14f, 0f);
            Add("Side slope", SideX0 - 12f, SideZ, 90f);
            Add("Articulation", SpineX, ArtZ0 - 10f, 0f);
            Add("Ford", SpineX, FordZ0 - 10f, 0f);
            Add("Log pile", LogPile.x + 5f, LogPile.y - 14f, 0f);
            Add("Measuring area", MeasCenter.x, MeasCenter.y - 20f, 0f);
        }
    }
}
