using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;
using static MudRunner.Ground.SurfaceType;

namespace MudRunner.WorldGen
{
    public enum TKind : byte { Road = 0, Ford = 1, Bridge = 2, Causeway = 3, Free = 4 }

    /// <summary>One authored node of a track. Surface/kind/ruts describe the segment that STARTS at this node; the other values are
    /// interpolated between nodes.</summary>
    public struct TNode
    {
        public float x, z;
        public float y;            // NaN = automatic (follows the terrain with a grade limit), otherwise a pinned road height
        public SurfaceType surf;
        public float halfW;        // half width of the road bed
        public float extra;        // hidden extra soft depth (m)
        public float wet;          // base wetness 0..1
        public float grade;        // maximum grade (rise/run) of the automatic profile
        public TKind kind;
        public bool ruts;
    }

    public sealed class TrackDef
    {
        public string name;
        public string display;
        public string parent;                 // spur: start joins this track (profile locked to the parent there)
        public string endParent;              // optional: end joins this track
        public int routeId = -1;              // 1 north, 2 central, 3 swamp, 0 = other
        public float wiggle = 6f;             // lateral meander amplitude (m)
        public float ruDepth = 0.14f;         // depth of pre-carved ruts
        public List<TNode> nodes = new List<TNode>();
    }

    public struct RiverNode { public float x, z, halfW, depth, ford; }

    public sealed class RiverDef
    {
        public string name;
        public List<RiverNode> nodes = new List<RiverNode>();
        public float wlStart, wlEnd;          // water surface elevation at start / end
        public bool endsInWater;              // creek: the last node lies on another river (its WL is taken from there)
        public float slope = 0.0065f;         // creek: water surface drop per metre of length
        public float speedBase = 1.1f;
    }

    public struct PondDef { public string name; public float x, z, r, depth; public float level; }   // level NaN = surface - 0.35
    public struct PadDef
    {
        public string name; public float x, z, rx, rz, yawDeg, blend; public float y; public SurfaceType surf; public float wet; public bool round;
    }
    public struct TrapDef { public string name; public float x, z, r, depth; public bool decoy; public bool mudLook; }
    public struct SiteDef { public string name; public float x, z, r; }
    public struct SignDef { public string id; public float x, z, yaw; public string text; }

    /// <summary>
    /// The authored geography of the Wilderness (all coordinates in metres, X east, Z north). Terrain, tracks and objects are
    /// generated around this data by <see cref="WorldGenerator"/>. Edit here to move things; nothing else hard-codes positions.
    /// </summary>
    public static class WorldLayout
    {
        public const float Half = 1024f;           // map half size
        public const float Play = 768f;            // playable half size

        public static readonly Vector2 BaseCamp = new Vector2(-600f, -560f);
        public static readonly Vector3 PlayerStart = new Vector3(-585f, 0f, -545f);
        public const float PlayerYaw = 45f;

        public static readonly Vector2 SwampCenter = new Vector2(565f, 445f);
        public static readonly Vector2 SwampRadii = new Vector2(215f, 185f);
        public static readonly Vector2 CabinPos = new Vector2(550f, 480f);

        // ------------------------------------------------------------------ helpers for authoring tracks

        public static TNode N(float x, float z, SurfaceType surf = Gravel, float w = 3f, float wet = 0.2f, float extra = 0f,
                       TKind kind = TKind.Road, bool ruts = false, float y = float.NaN, float grade = 0.16f)
        {
            return new TNode { x = x, z = z, y = y, surf = surf, halfW = w, wet = wet, extra = extra, kind = kind, ruts = ruts, grade = grade };
        }

        public static TrackDef T(string name, string display, int route, params TNode[] nodes)
        {
            var t = new TrackDef { name = name, display = display, routeId = route };
            t.nodes.AddRange(nodes);
            return t;
        }

        // ------------------------------------------------------------------ rivers

        public static List<RiverDef> BuildRivers()
        {
            var main = new RiverDef { name = "Silverrun", wlStart = 15.2f, wlEnd = 4.2f, speedBase = 1.15f };
            void R(float x, float z, float hw, float d, float ford = 0f) { main.nodes.Add(new RiverNode { x = x, z = z, halfW = hw, depth = d, ford = ford }); }
            R(-632, -52, 2.5f, 0.9f); R(-585, -78, 4.0f, 1.3f); R(-520, -48, 5.0f, 1.7f); R(-455, -62, 6.0f, 2.0f);
            R(-395, -100, 6.5f, 2.2f); R(-335, -75, 7.0f, 2.3f); R(-298, -34, 8.5f, 1.4f);
            R(-262, -18, 11f, 0.8f, 0.8f);                       // F1
            R(-222, -26, 10f, 1.2f); R(-180, -65, 8f, 2.0f); R(-130, -100, 7.5f, 2.2f); R(-85, -62, 7f, 2.2f);
            R(-50, -5, 6.5f, 2.4f); R(-20, 40, 5.5f, 2.6f);      // B1 pinch
            R(30, 35, 6.5f, 2.4f); R(75, -5, 7.5f, 2.2f); R(125, -55, 8f, 2.0f);
            R(182, -92, 12f, 0.7f, 0.7f);                        // F2
            R(235, -70, 9f, 1.8f);
            R(290, -45, 5f, 2.8f);                               // B2 pinch
            R(340, -75, 7.5f, 2.4f); R(385, -60, 10f, 2.0f);
            R(428, -28, 12.5f, 1.1f, 1.1f);                      // deep crossing (hauler only)
            R(475, -18, 11f, 1.8f); R(525, 10, 10f, 1.9f); R(568, 62, 10f, 1.6f); R(594, 130, 11f, 1.4f);
            R(600, 208, 12f, 1.0f); R(588, 275, 14f, 0.8f); R(572, 318, 18f, 0.55f); R(556, 352, 24f, 0.3f);

            var creek = new RiverDef { name = "Mossbeck", endsInWater = true, wlStart = 0f, wlEnd = 0f, speedBase = 0.9f, slope = 0.027f };
            void K(float x, float z, float hw, float d, float ford = 0f) { creek.nodes.Add(new RiverNode { x = x, z = z, halfW = hw, depth = d, ford = ford }); }
            K(-90, -700, 1.5f, 0.5f); K(-70, -640, 2.0f, 0.7f); K(-82, -575, 2.4f, 0.8f); K(-66, -520, 2.8f, 0.9f);
            K(-64, -472, 3.5f, 0.45f, 0.45f);                    // south creek ford
            K(-45, -420, 3f, 1.0f); K(-25, -350, 3f, 1.1f); K(-32, -270, 3.3f, 1.2f); K(-20, -190, 3.5f, 1.3f);
            K(-45, -120, 4f, 1.5f); K(-72, -78, 5f, 1.6f); K(-85, -62, 7f, 2.2f);
            return new List<RiverDef> { main, creek };
        }

        public static List<PondDef> BuildPonds()
        {
            float nan = float.NaN;
            return new List<PondDef>
            {
                new PondDef { name = "Spring", x = -660, z = -38, r = 24, depth = 1.6f, level = 15.4f },
                new PondDef { name = "Oxbow W", x = -472, z = 14, r = 17, depth = 1.2f, level = nan },
                new PondDef { name = "Oxbow M", x = -118, z = -150, r = 15, depth = 1.2f, level = nan },
                new PondDef { name = "Oxbow E", x = 150, z = 8, r = 13, depth = 1.0f, level = nan },
                new PondDef { name = "Fish pond", x = 352, z = -2, r = 18, depth = 1.4f, level = nan },
                new PondDef { name = "Pump pond", x = 660, z = -326, r = 26, depth = 1.8f, level = nan },
                new PondDef { name = "Logging pond", x = -80, z = 380, r = 22, depth = 1.2f, level = nan },
                new PondDef { name = "Mere", x = -330, z = 520, r = 26, depth = 1.5f, level = nan },
            };
        }

        public static List<PadDef> BuildPads()
        {
            float nan = float.NaN;
            return new List<PadDef>
            {
                new PadDef { name = "BaseCamp", x = -600, z = -560, rx = 36, rz = 36, yawDeg = 0, blend = 26, y = nan, surf = Gravel, wet = 0.1f },
                new PadDef { name = "Sawmill", x = -300, z = -200, rx = 30, rz = 26, yawDeg = 20, blend = 20, y = nan, surf = FirmSoil, wet = 0.35f, round = true },
                new PadDef { name = "LoggingLanding", x = -150, z = 420, rx = 38, rz = 30, yawDeg = 15, blend = 22, y = nan, surf = FirmSoil, wet = 0.3f, round = true },
                new PadDef { name = "Watchtower", x = -450, z = 480, rx = 15, rz = 15, yawDeg = 0, blend = 18, y = nan, surf = Rock, wet = 0.05f, round = true },
                new PadDef { name = "RadioMast", x = 100, z = 600, rx = 15, rz = 15, yawDeg = 0, blend = 18, y = nan, surf = Rock, wet = 0.05f, round = true },
                new PadDef { name = "PumpStation", x = 598, z = -250, rx = 24, rz = 20, yawDeg = 0, blend = 16, y = nan, surf = Gravel, wet = 0.15f, round = true },
                new PadDef { name = "CabinIsland", x = CabinPos.x, z = CabinPos.y, rx = 34, rz = 30, yawDeg = 10, blend = 26, y = 5.35f, surf = Grass, wet = 0.3f, round = true },
            };
        }

        public static List<TrapDef> BuildTraps()
        {
            return new List<TrapDef>
            {
                new TrapDef { name = "Central bypass A", x = 75, z = 472, r = 12, depth = 0.9f },
                new TrapDef { name = "Central bypass B", x = 228, z = 436, r = 9, depth = 0.65f, mudLook = true },
                new TrapDef { name = "Central decoy", x = 118, z = 476, r = 9, depth = 0f, decoy = true },
                new TrapDef { name = "North soft spot", x = -352, z = 622, r = 7, depth = 0.4f },
                new TrapDef { name = "Swamp meadow", x = 478, z = 205, r = 13, depth = 0.95f },
                new TrapDef { name = "Swamp decoy", x = 520, z = 225, r = 10, depth = 0f, decoy = true },
                new TrapDef { name = "Island west carpet", x = 503, z = 496, r = 11, depth = 1.5f },
                new TrapDef { name = "Island east carpet", x = 592, z = 472, r = 11, depth = 1.8f },
                new TrapDef { name = "Island south pit", x = 548, z = 438, r = 12, depth = 1.3f, mudLook = true },
                new TrapDef { name = "Ford F1 soft bank", x = -283, z = -62, r = 8, depth = 0.7f },
                new TrapDef { name = "Widowmaker foot", x = 310, z = -395, r = 10, depth = 0.7f, mudLook = true },
                new TrapDef { name = "Creek meadow", x = -30, z = -440, r = 9, depth = 0.6f },
            };
        }

        public static List<SiteDef> BuildSites()
        {
            return new List<SiteDef>
            {
                new SiteDef { name = "BaseCamp", x = -600, z = -560, r = 45 },
                new SiteDef { name = "Garage", x = -622, z = -578, r = 16 },
                new SiteDef { name = "FuelStation", x = -566, z = -588, r = 14 },
                new SiteDef { name = "Sawmill", x = -300, z = -200, r = 30 },
                new SiteDef { name = "LoggingLanding", x = -150, z = 420, r = 36 },
                new SiteDef { name = "Watchtower", x = -450, z = 480, r = 16 },
                new SiteDef { name = "RadioMast", x = 100, z = 600, r = 16 },
                new SiteDef { name = "PumpStation", x = 598, z = -250, r = 24 },
                new SiteDef { name = "Cabin", x = CabinPos.x, z = CabinPos.y, r = 22 },
                new SiteDef { name = "FordF1", x = -262, z = -18, r = 25 },
                new SiteDef { name = "FordF2", x = 182, z = -92, r = 25 },
                new SiteDef { name = "OldBridgeB1", x = -20, z = 40, r = 18 },
                new SiteDef { name = "BridgeB2", x = 290, z = -45, r = 16 },
                new SiteDef { name = "DeepCrossing", x = 420, z = -42, r = 28 },
                new SiteDef { name = "CreekFord", x = -64, z = -472, r = 18 },
                new SiteDef { name = "Widowmaker", x = 350, z = -340, r = 40 },
                new SiteDef { name = "SwampEntrance", x = 515, z = 275, r = 30 },
                new SiteDef { name = "ProvingGroundGate", x = 805, z = -196, r = 20 },
            };
        }

        // ------------------------------------------------------------------ tracks

        public static List<TrackDef> BuildTracks()
        {
            var list = new List<TrackDef>();

            // ---- Route 1: NORTH ROAD (long, mostly firm gravel, a few muddy stretches, fragile causeway at the end)
            var north = T("north", "North road", 1,
                N(-598, -548, Gravel, 3.4f), N(-640, -512, Gravel, 3.4f), N(-680, -456, Gravel, 3.3f), N(-702, -386, Gravel, 3.3f),
                N(-716, -300, Gravel, 3.3f), N(-722, -210, FirmSoil, 3.2f, 0.25f), N(-726, -150, ShallowMud, 3.2f, 0.55f, 0.05f, ruts: true),
                N(-728, -92, ShallowMud, 3.2f, 0.6f, 0.05f, ruts: true), N(-727, -40, Gravel, 3.3f), N(-725, 20, Gravel, 3.3f),
                N(-722, 85, Gravel, 3.3f), N(-716, 150, FirmSoil, 3.2f), N(-722, 225, Gravel, 3.3f), N(-702, 300, Gravel, 3.3f),
                N(-640, 340, FirmSoil, 3.2f, 0.3f), N(-615, 410, Gravel, 3.3f), N(-650, 470, Gravel, 3.3f), N(-600, 525, FirmSoil, 3.2f),
                N(-560, 524, Gravel, 3.3f), N(-520, 530, Gravel, 3.3f), N(-480, 560, Gravel, 3.3f), N(-440, 592, ShallowMud, 3.2f, 0.55f, 0.04f, ruts: true),
                N(-395, 625, ShallowMud, 3.2f, 0.5f, 0.2f, ruts: true),
                N(-330, 652, Gravel, 3.3f), N(-250, 662, Gravel, 3.4f), N(-160, 668, Gravel, 3.4f), N(-80, 664, Gravel, 3.4f),
                N(0, 658, Gravel, 3.4f), N(100, 658, Gravel, 3.4f), N(200, 650, FirmSoil, 3.2f), N(262, 646, ShallowMud, 3.2f, 0.5f, 0f, ruts: true),
                N(325, 648, ShallowMud, 3.2f, 0.45f, 0f, ruts: true), N(385, 660, Gravel, 3.3f), N(450, 655, Gravel, 3.3f, grade: 0.18f),
                N(505, 625, Gravel, 3.3f, grade: 0.18f), N(535, 600, FirmSoil, 3.2f, 0.35f, kind: TKind.Causeway),
                N(547, 548, Bog, 2.6f, 0.9f, kind: TKind.Causeway), N(551, 512, FirmSoil, 3f, 0.3f));
            north.wiggle = 14f; north.ruDepth = 0.11f;
            list.Add(north);

            // ---- Route 2: CENTRAL TRACK (medium, forest dirt, ruts, ford F1, steep climb, mud at the swamp edge)
            var central = T("central", "Central track", 2,
                N(-585, -548, Gravel, 3f), N(-545, -505, Gravel, 3f), N(-495, -445, FirmSoil, 2.7f, 0.3f, ruts: true), N(-440, -390, FirmSoil, 2.6f, 0.3f, ruts: true),
                N(-385, -335, FirmSoil, 2.6f, 0.35f, ruts: true), N(-345, -280, ShallowMud, 2.6f, 0.55f, 0.05f, ruts: true), N(-318, -235, FirmSoil, 2.7f, 0.3f),
                N(-292, -192, Gravel, 3f), N(-278, -130, FirmSoil, 2.7f, 0.4f, ruts: true), N(-270, -78, ShallowMud, 2.7f, 0.65f, 0.05f, ruts: true),
                N(-264, -52, ShallowMud, 2.7f, 0.7f, 0.1f, kind: TKind.Ford), N(-258, 14, Gravel, 3f, 0.4f),
                N(-262, 62, ShallowMud, 2.7f, 0.6f, ruts: true), N(-292, 112, FirmSoil, 2.7f, 0.3f, grade: 0.3f), N(-340, 158, FirmSoil, 2.7f, 0.3f, grade: 0.44f),
                N(-380, 212, ShallowMud, 2.6f, 0.55f, 0.1f, ruts: true, grade: 0.46f), N(-410, 275, FirmSoil, 2.7f, 0.3f, ruts: true, grade: 0.3f),
                N(-386, 345, FirmSoil, 2.6f, 0.3f, ruts: true), N(-322, 395, FirmSoil, 2.7f, 0.3f), N(-246, 428, FirmSoil, 2.7f, 0.3f, ruts: true),
                N(-190, 424, Gravel, 3.2f, 0.2f), N(-150, 410, Gravel, 3.2f, 0.2f), N(-104, 470, Gravel, 3.2f), N(-30, 522, FirmSoil, 2.7f, 0.3f, ruts: true),
                N(50, 538, ShallowMud, 2.7f, 0.65f, 0.1f, ruts: true), N(125, 500, ShallowMud, 2.7f, 0.6f, ruts: true), N(185, 472, DeepMud, 2.7f, 0.8f, 0.25f, ruts: true),
                N(245, 455, DeepMud, 2.7f, 0.85f, 0.35f, ruts: true), N(300, 452, ShallowMud, 2.7f, 0.6f, ruts: true), N(350, 476, FirmSoil, 2.7f, 0.4f, ruts: true),
                N(397, 471, ShallowMud, 2.7f, 0.7f, 0.1f, ruts: true, grade: 0.2f), N(440, 468, DeepMud, 2.6f, 0.9f, 0.45f, ruts: true, grade: 0.2f),
                N(480, 477, DeepMud, 2.6f, 0.95f, 0.9f, ruts: true), N(512, 481, FirmSoil, 2.6f, 0.5f));
            central.wiggle = 13f; central.ruDepth = 0.17f;
            list.Add(central);

            // ---- Route 3: SWAMP SHORTCUT (short; Widowmaker climb, river deep crossing, 200 m of bog at the end)
            var swamp = T("swamp", "Swamp shortcut", 3,
                N(-583, -552, Gravel, 3f), N(-540, -540, Gravel, 3f), N(-480, -525, Gravel, 3f), N(-410, -508, FirmSoil, 2.8f, 0.25f),
                N(-330, -498, FirmSoil, 2.7f, 0.25f), N(-250, -492, FirmSoil, 2.7f, 0.3f), N(-170, -488, FirmSoil, 2.7f, 0.35f, ruts: true),
                N(-118, -481, ShallowMud, 2.7f, 0.6f, 0.05f, ruts: true), N(-88, -475, ShallowMud, 2.7f, 0.6f, 0.05f, kind: TKind.Ford),
                N(-42, -468, Gravel, 3f, 0.3f), N(2, -455, FirmSoil, 2.8f), N(80, -441, FirmSoil, 2.7f, 0.3f), N(160, -426, FirmSoil, 2.7f, 0.3f),
                N(240, -413, FirmSoil, 2.7f, 0.3f), N(300, -407, ShallowMud, 2.7f, 0.5f, ruts: true, grade: 0.3f), N(336, -388, ShallowMud, 2.6f, 0.75f, 0.12f, ruts: true, grade: 0.46f),
                N(350, -345, DeepMud, 2.6f, 0.9f, 0.2f, ruts: true, grade: 0.47f), N(354, -307, ShallowMud, 2.6f, 0.8f, 0.1f, ruts: true, grade: 0.46f),
                N(352, -270, FirmSoil, 2.7f, 0.35f, grade: 0.3f), N(346, -224, FirmSoil, 2.7f, 0.3f, ruts: true), N(336, -176, FirmSoil, 2.7f, 0.3f),
                N(322, -126, ShallowMud, 2.7f, 0.5f, ruts: true), N(368, -106, ShallowMud, 2.7f, 0.6f), N(412, -76, ShallowMud, 2.6f, 0.6f, 0.1f, kind: TKind.Ford),
                N(437, 2, FirmSoil, 2.7f, 0.5f), N(447, 44, FirmSoil, 2.7f, 0.4f), N(458, 86, ShallowMud, 2.6f, 0.5f, ruts: true), N(471, 130, FirmSoil, 2.6f, 0.3f, ruts: true),
                N(485, 178, FirmSoil, 2.6f, 0.35f, ruts: true), N(499, 226, ShallowMud, 2.6f, 0.55f, 0.1f, ruts: true), N(512, 268, DeepMud, 2.6f, 0.8f, 0.3f, ruts: true, grade: 0.2f),
                N(522, 306, Bog, 2.5f, 0.9f, 0.6f, ruts: true, grade: 0.2f), N(531, 345, Bog, 2.5f, 0.95f, 0.9f, ruts: true), N(540, 385, Bog, 2.5f, 0.95f, 1.2f, ruts: true),
                N(546, 421, Bog, 2.5f, 0.95f, 1.4f, ruts: true), N(549, 452, FirmSoil, 2.5f, 0.5f));
            swamp.wiggle = 8f; swamp.ruDepth = 0.2f;
            list.Add(swamp);

            // bridge detour of the swamp route (B2, load limited) - leaves and rejoins the main line
            var detour = T("swamp_bridge", "Bridge B2 detour", 0,
                N(322, -126, FirmSoil, 2.7f, 0.4f, grade: 0.27f), N(300, -92, FirmSoil, 2.7f, 0.3f, grade: 0.27f), N(290, -57, Gravel, 3f, 0.2f, kind: TKind.Bridge),
                N(290, -33, Gravel, 3f, 0.2f), N(304, 14, FirmSoil, 2.7f, 0.3f), N(356, 66, FirmSoil, 2.7f, 0.3f), N(412, 90, FirmSoil, 2.7f, 0.3f), N(458, 86, FirmSoil, 2.7f, 0.35f));
            detour.parent = "swamp"; detour.endParent = "swamp"; detour.wiggle = 4f;
            list.Add(detour);

            // ---- service road to the proving ground (branches off the swamp route after the creek ford)
            var service = T("service", "Service road", 0,
                N(-42, -468, Gravel, 3.2f), N(30, -482, Gravel, 3.3f), N(130, -503, Gravel, 3.3f), N(230, -507, Gravel, 3.3f), N(330, -494, FirmSoil, 3.2f, 0.25f),
                N(420, -466, Gravel, 3.3f), N(500, -415, Gravel, 3.3f), N(560, -352, FirmSoil, 3.2f, 0.25f), N(594, -300, Gravel, 3.3f), N(606, -262, Gravel, 3.3f),
                N(660, -232, Gravel, 3.3f), N(725, -205, Gravel, 3.3f), N(770, -192, Gravel, 3.3f, grade: 0.14f), N(800, -194, Gravel, 3.4f), N(815, -198, Gravel, 4f));
            service.parent = "swamp"; service.wiggle = 6f;
            list.Add(service);

            // ---- mid link: swamp stem -> ford F2 -> central track east of the logging landing
            var mid = T("mid_link", "Mid link (Ford F2)", 0,
                N(160, -426, FirmSoil, 2.7f, 0.3f), N(148, -350, FirmSoil, 2.7f, 0.3f), N(150, -270, FirmSoil, 2.6f, 0.3f, ruts: true), N(162, -196, FirmSoil, 2.6f, 0.35f),
                N(174, -140, ShallowMud, 2.6f, 0.55f, 0.05f, ruts: true), N(182, -112, ShallowMud, 2.6f, 0.6f, 0.05f, kind: TKind.Ford),
                N(186, -62, Gravel, 3f, 0.3f), N(192, -10, FirmSoil, 2.7f, 0.3f), N(197, 60, FirmSoil, 2.6f, 0.3f), N(200, 150, FirmSoil, 2.6f, 0.3f, ruts: true),
                N(204, 250, ShallowMud, 2.6f, 0.5f, ruts: true), N(209, 345, FirmSoil, 2.6f, 0.35f), N(206, 430, FirmSoil, 2.6f, 0.4f), N(190, 468, FirmSoil, 2.7f, 0.5f));
            mid.parent = "swamp"; mid.endParent = "central"; mid.wiggle = 7f;
            list.Add(mid);

            // ---- old bridge road: swamp stem -> old bridge B1 (fragile) -> logging landing
            var oldRoad = T("old_road", "Old bridge road (B1)", 0,
                N(2, -455, Gravel, 2.8f), N(12, -390, FirmSoil, 2.6f, 0.3f), N(8, -310, FirmSoil, 2.6f, 0.3f, ruts: true), N(0, -230, FirmSoil, 2.6f, 0.3f),
                N(-4, -150, ShallowMud, 2.6f, 0.5f, ruts: true), N(-8, -72, FirmSoil, 2.6f, 0.4f), N(-11, -6, Gravel, 2.8f, 0.3f), N(-15, 30, Gravel, 2.8f, 0.2f, kind: TKind.Bridge),
                N(-25, 50, Gravel, 2.8f, 0.2f), N(-42, 120, FirmSoil, 2.6f, 0.3f), N(-72, 200, FirmSoil, 2.6f, 0.3f, ruts: true), N(-104, 290, ShallowMud, 2.6f, 0.5f, ruts: true),
                N(-128, 365, FirmSoil, 2.6f, 0.3f), N(-150, 410, Gravel, 3f));
            oldRoad.parent = "swamp"; oldRoad.endParent = "central"; oldRoad.wiggle = 6f;
            list.Add(oldRoad);

            // ---- spurs
            var tower = T("watchtower", "Watchtower track", 0,
                N(-520, 530, Gravel, 2.6f), N(-494, 512, FirmSoil, 2.4f, grade: 0.2f), N(-468, 494, FirmSoil, 2.4f, grade: 0.22f), N(-452, 482, Gravel, 3f, grade: 0.2f));
            tower.parent = "north"; tower.wiggle = 2f;
            list.Add(tower);

            var radio = T("radio_mast", "Radio mast track", 0,
                N(100, 658, Gravel, 2.6f), N(104, 632, FirmSoil, 2.4f, grade: 0.2f), N(100, 606, Gravel, 3f, grade: 0.2f));
            radio.parent = "north"; radio.wiggle = 2f;
            list.Add(radio);

            var link = T("logging_link", "Logging haul road", 0,
                N(-150, 420, Gravel, 3.2f), N(-168, 500, Gravel, 3.2f), N(-190, 590, FirmSoil, 3f, 0.3f), N(-200, 660, Gravel, 3.3f));
            link.parent = "central"; link.endParent = "north"; link.wiggle = 6f;
            list.Add(link);

            return list;
        }

        // ------------------------------------------------------------------ extra hand placed signs (junction signs are derived)

        public static List<SignDef> BuildSigns()
        {
            return new List<SignDef>
            {
                new SignDef { id = "sign_arrow", x = -578, z = -532, yaw = 40f, text = "ROUTES" },
                new SignDef { id = "sign_warn", x = -256, z = -86, yaw = 180f, text = "FORD 0.8m" },
                new SignDef { id = "sign_warn", x = 410, z = -112, yaw = 180f, text = "DEEP 1.1m" },
                new SignDef { id = "sign_warn", x = 505, z = 252, yaw = 180f, text = "BOG" },
                new SignDef { id = "sign_warn", x = 440, z = 478, yaw = 90f, text = "SOFT" },
                new SignDef { id = "sign_warn", x = -22, z = 12, yaw = 0f, text = "WEAK BRIDGE 3.5t" },
                new SignDef { id = "sign_warn", x = 288, z = -100, yaw = 0f, text = "BRIDGE 5.5t" },
                new SignDef { id = "sign_warn", x = 355, z = -430, yaw = 180f, text = "STEEP MUD" },
                new SignDef { id = "sign_warn", x = 540, z = 568, yaw = 0f, text = "WEAK CAUSEWAY 6.5t" },
            };
        }
    }
}
