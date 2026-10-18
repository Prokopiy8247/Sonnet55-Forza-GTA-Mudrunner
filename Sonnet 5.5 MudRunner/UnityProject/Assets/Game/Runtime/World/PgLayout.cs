using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;
using static MudRunner.Ground.SurfaceType;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Geometry of the compact proving ground (east strip x 800..1010, z -300..300). Everything is analytic so the terrain, surfaces,
    /// structures and tests all read the same numbers. Stations from the entrance (west pass at z = -196):
    /// start/measure pad -> 100 m straight -> six mud pits -> articulation course -> [spur north: river ford, log pile, measuring area]
    /// and the east loop: steep mud hill (12/20/28 deg) -> firm return slope -> 40 m side-slope track -> back to the spine.
    /// </summary>
    public static class PgLayout
    {
        public const float Floor = 28f;                       // elevation of the valley floor
        public const float BowlX0 = 815f, BowlX1 = 998f, BowlZ0 = -288f, BowlZ1 = 290f;

        public const float PadX0 = 830f, PadX1 = 870f, PadZ0 = -265f, PadZ1 = -225f;
        public const float SpineX = 850f;
        public const float StraightZ0 = -225f, StraightZ1 = -125f;

        public const int PitCount = 6;
        public const float PitLen = 18f, PitGap = 8f, PitHalfW = 6f, PitDepth = 0.35f;
        public static float PitZ0(int k) { return -105f + (PitLen + PitGap) * k; }
        public static readonly string[] PitNames = { "shallow mud", "shallow mud + 0.3 m hidden depth", "deep mud", "deep mud + 0.5 m hidden depth", "bog", "bog + 0.8 m hidden depth" };
        public static readonly SurfaceType[] PitSurface = { ShallowMud, ShallowMud, DeepMud, DeepMud, Bog, Bog };
        public static readonly float[] PitExtra = { 0f, 0.3f, 0f, 0.5f, 0f, 0.8f };

        // hill
        public const float HillX = 940f, HillZ0 = -112f, HillHalfTop = 11f, HillSide = 0.62f;
        public static readonly float[] StepDeg = { 12f, 20f, 28f };
        public static readonly float[] StepLen = { 20f, 25f, 25f };
        public const float PlateauLen = 30f, ReturnDeg = 10f;
        public static float HillZ(int boundary)   // 0 = base, 1..3 = end of step 1..3, 4 = end of plateau, 5 = end of return slope
        {
            float z = HillZ0;
            for (int i = 0; i < 3 && i < boundary; i++) z += StepLen[i] * Mathf.Cos(StepDeg[i] * Mathf.Deg2Rad);
            if (boundary >= 4) z += PlateauLen;
            if (boundary >= 5) z += HillHeight / Mathf.Tan(ReturnDeg * Mathf.Deg2Rad);
            return z;
        }
        public static float HillHeight
        {
            get { float h = 0f; for (int i = 0; i < 3; i++) h += StepLen[i] * Mathf.Sin(StepDeg[i] * Mathf.Deg2Rad); return h; }
        }

        public static float HillRaw(float z)
        {
            float z1 = HillZ(1), z2 = HillZ(2), z3 = HillZ(3), z4 = HillZ(4), z5 = HillZ(5);
            float r1 = StepLen[0] * Mathf.Sin(StepDeg[0] * Mathf.Deg2Rad), r2 = StepLen[1] * Mathf.Sin(StepDeg[1] * Mathf.Deg2Rad), H = HillHeight;
            if (z < HillZ0) return 0f;
            if (z < z1) return (z - HillZ0) * Mathf.Tan(StepDeg[0] * Mathf.Deg2Rad);
            if (z < z2) return r1 + (z - z1) * Mathf.Tan(StepDeg[1] * Mathf.Deg2Rad);
            if (z < z3) return r1 + r2 + (z - z2) * Mathf.Tan(StepDeg[2] * Mathf.Deg2Rad);
            if (z < z4) return H;
            if (z < z5) return H - (z - z4) * Mathf.Tan(ReturnDeg * Mathf.Deg2Rad);
            return 0f;
        }

        /// <summary>Height of the hill axis above the floor, with the slope breaks rounded over about 3 m.</summary>
        public static float HillProfile(float z) { return 0.25f * HillRaw(z - 1.5f) + 0.5f * HillRaw(z) + 0.25f * HillRaw(z + 1.5f); }

        // side slope track (runs along +x, tilted towards -z)
        public const float SideX0 = 868f, SideX1 = 908f, SideZ = 140f, SideHalf = 8f, SideBench = 2.6f;
        public static float SideTiltDeg(float x) { return 14f + 4f * Mathf.Clamp01((x - SideX0) / (SideX1 - SideX0)); }

        // articulation course
        public const float ArtZ0 = 62f, ArtZ1 = 107f;
        public static int ArtStations => 9;
        public static float ArtStationZ(int i) { return ArtZ0 + 2f + i * 5.2f; }

        // ford
        public const float FordZ0 = 190f, FordZ1 = 226f, FordWl = Floor - 0.25f, FordX0 = 820f, FordX1 = 996f, FordCurrent = 1.5f;
        static readonly float[] FordT = { 0f, 0.04f, 0.22f, 0.38f, 0.5f, 0.62f, 0.78f, 0.96f, 1f };
        static readonly float[] FordD = { 0f, 0.4f, 0.8f, 1.2f, 1.6f, 1.2f, 0.8f, 0.4f, 0f };
        public static float FordDepth(float z)
        {
            float t = (z - FordZ0) / (FordZ1 - FordZ0);
            if (t <= 0f || t >= 1f) return 0f;
            for (int i = 0; i + 1 < FordT.Length; i++)
                if (t <= FordT[i + 1]) return Mathf.Lerp(FordD[i], FordD[i + 1], (t - FordT[i]) / (FordT[i + 1] - FordT[i]));
            return 0f;
        }

        public static readonly Vector2 LogPile = new Vector2(835f, 262f);
        public const float SandX0 = 853f, SandX1 = 874f, SandZ0 = 250f, SandZ1 = 266f;
        public const float MeasX0 = 917f, MeasX1 = 973f, MeasZ0 = 236f, MeasZ1 = 292f;
        public static readonly Vector2 MeasCenter = new Vector2(945f, 264f);

        public static readonly Vector2 Start = new Vector2(845f, -238f);
        public const float StartYaw = 0f;

        public static float RectSdf(float x, float z, float x0, float x1, float z0, float z1)
        {
            float cx = (x0 + x1) * 0.5f, cz = (z0 + z1) * 0.5f, hx = (x1 - x0) * 0.5f, hz = (z1 - z0) * 0.5f;
            float dx = Mathf.Abs(x - cx) - hx, dz = Mathf.Abs(z - cz) - hz;
            float ox = Mathf.Max(dx, 0f), oz = Mathf.Max(dz, 0f);
            return Mathf.Sqrt(ox * ox + oz * oz) + Mathf.Min(Mathf.Max(dx, dz), 0f);
        }

        /// <summary>Boulder / hole stations of the articulation course: (x, z, boulderOnLeft).</summary>
        public static void ArtItems(int i, out Vector2 boulder, out Vector2 hole)
        {
            float z = ArtStationZ(i);
            bool left = i % 2 == 0;
            boulder = new Vector2(SpineX + (left ? -0.95f : 0.95f), z);
            hole = new Vector2(SpineX + (left ? 0.95f : -0.95f), z);
        }

        public static bool InBox(float x, float z, float margin = 70f)
        {
            return x > 760f - margin * 0f && x < 1040f && z > -340f && z < 340f;
        }

        // ------------------------------------------------------------------ track definitions

        public static List<TrackDef> Tracks(bool full)
        {
            var l = new List<TrackDef>();
            TNode N(float x, float z, TKind kind = TKind.Road, float w = 4f, SurfaceType surf = Gravel) { return WorldLayout.N(x, z, surf, w, 0.15f, 0f, kind, false, float.NaN, 0.1f); }
            if (!full)
            {
                var ap = WorldLayout.T("pg_approach", "Proving ground approach", 0, N(600f, -250f), N(660f, -232f), N(725f, -205f), N(770f, -192f), N(800f, -194f), N(815f, -198f));
                ap.wiggle = 3f; l.Add(ap);
            }
            var entry = WorldLayout.T("pg_entry", "Proving ground entrance", 0, N(815f, -198f), N(830f, -208f), N(850f, -224f)); entry.wiggle = 0f; l.Add(entry);
            var spine = WorldLayout.T("pg_spine", "Spine: straight, mud pits, articulation", 0,
                N(850f, -224f, TKind.Road, 6f), N(850f, -126f, TKind.Free, 6f), N(850f, 60f, TKind.Free), N(850f, 108f, TKind.Road), N(850f, 134f));
            spine.wiggle = 0f; l.Add(spine);
            float hz5 = HillZ(5);
            var east = WorldLayout.T("pg_east", "East loop: hill and side slope", 0,
                N(850f, -122f), N(895f, -114f), N(940f, -112f, TKind.Free, 6f), N(940f, hz5 + 4f, TKind.Road, 6f), N(940f, 134f), N(918f, 142f), N(908f, 140f, TKind.Free), N(868f, 140f, TKind.Road), N(850f, 136f));
            east.wiggle = 0f; l.Add(east);
            var ford = WorldLayout.T("pg_ford", "Ford spur", 0, N(850f, 134f), N(850f, 186f), N(850f, FordZ0, TKind.Ford), N(850f, FordZ1 + 2f), N(850f, 246f));
            ford.wiggle = 0f; l.Add(ford);
            var bridge = WorldLayout.T("pg_bridge", "Ford bypass bridge", 0, N(940f, 134f), N(975f, 150f), N(985f, 172f), N(985f, 186f, TKind.Bridge, 3f), N(985f, 230f), N(975f, 250f), N(960f, 262f));
            bridge.wiggle = 0f; l.Add(bridge);
            var north = WorldLayout.T("pg_north", "North area road", 0, N(850f, 246f), N(880f, 258f), N(915f, 264f), N(945f, 264f));
            north.wiggle = 0f; l.Add(north);
            var logs = WorldLayout.T("pg_logs", "Log pile spur", 0, N(850f, 246f), N(838f, 258f), N(832f, 272f));
            logs.wiggle = 0f; l.Add(logs);
            return l;
        }
    }
}
