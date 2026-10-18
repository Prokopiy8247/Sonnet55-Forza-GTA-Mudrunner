using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using MudRunner.Ground;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace MudRunner.WorldGen
{
    public sealed class WorldGenConfig
    {
        public uint seed = 20260611u;
        /// <summary>false = only the compact proving ground map (cropped), true = the full 2048 m map (wilderness + proving ground strip).</summary>
        public bool full = true;
        public bool props = true;
        /// <summary>Cropped proving-ground-only map extents (square, 1 m cells).</summary>
        public Vector2 pgOrigin = new Vector2(585f, -320f);
        public int pgSize = 641;
    }

    public struct PondInfo { public PondDef def; public float level; }

    public sealed class GeneratedWorld
    {
        public WorldGenConfig cfg;
        public GroundMap map;
        public WaterMap water;
        public WorldNoise noise;
        public List<River> rivers = new List<River>();
        public List<PondInfo> ponds = new List<PondInfo>();
        public TrackSet tracks = new TrackSet();
        public byte[] swamp;
        /// <summary>Distance from the nearest road edge in metres (float.MaxValue beyond ~14 m). Released after prop placement.</summary>
        public float[] roadEdge;
        public List<PadDef> pads;
        public List<TrapDef> traps;
        public WorldSites sites = new WorldSites();
        public PropSet props;
        public readonly Dictionary<string, double> timings = new Dictionary<string, double>();
        public float swampWaterLevel = TerrainGenerator.SwampWl;
        public bool IsFull => cfg.full;
    }

    /// <summary>
    /// Deterministic terrain pipeline: base hills + swamp + pads + river valleys + ponds + mountain ring (stage A), road profiles and
    /// road carving (B, C), surfaces / wetness / hidden depth / water (D). All per-cell stages run in parallel and are order independent.
    /// </summary>
    public sealed partial class TerrainGenerator
    {
        public const float SwampWl = 3.85f;
        const float BogBase = 3.98f;

        readonly WorldGenConfig cfg;
        readonly GeneratedWorld gw = new GeneratedWorld();
        WorldNoise noise;
        GroundMap map;
        int size; float cell = 1f; Vector2 origin;
        float[] rDist, rT, cDist, cT, tDist, tT;
        River river, creek;
        List<PadDef> pads; List<float> padY = new List<float>();
        List<PondInfo> ponds = new List<PondInfo>();
        List<TrapDef> traps;
        byte[] swamp;
        TrackSet tset;
        readonly Stopwatch sw = new Stopwatch();

        public TerrainGenerator(WorldGenConfig cfg) { this.cfg = cfg; gw.cfg = cfg; }

        void Mark(string name)
        {
            gw.timings[name] = sw.Elapsed.TotalMilliseconds;
            sw.Restart();
        }

        // ================================================================== entry

        public GeneratedWorld Generate()
        {
            sw.Restart();
            noise = new WorldNoise(cfg.seed);
            gw.noise = noise;
            if (cfg.full) { size = 2049; origin = new Vector2(-1024f, -1024f); }
            else { size = cfg.pgSize; origin = cfg.pgOrigin; }
            map = new GroundMap(size, cell, origin);
            gw.map = map;
            swamp = new byte[size * size];
            gw.swamp = swamp;
            pads = cfg.full ? WorldLayout.BuildPads() : new List<PadDef>();
            traps = cfg.full ? WorldLayout.BuildTraps() : new List<TrapDef>();
            gw.pads = pads; gw.traps = traps;
            Mark("alloc");

            BuildRivers();
            Mark("rivers");
            InitPadsAndPonds();
            Mark("pads");
            StageA();
            Mark("stageA_height");
            BuildTracks();
            Mark("tracks_profile");
            StageC();
            Mark("stageC_roads");
            StageD();
            Mark("stageD_surface");
            PostPg();
            map.Finalize_();
            Mark("finalize");
            rDist = rT = cDist = cT = tDist = tT = null;
            gw.tracks = tset;
            return gw;
        }

        // ================================================================== features setup

        void BuildRivers()
        {
            if (!cfg.full) return;
            var defs = WorldLayout.BuildRivers();
            river = River.Build(defs[0], noise, 0f, 1);
            Vector2 cEnd = new Vector2(defs[1].nodes[defs[1].nodes.Count - 1].x, defs[1].nodes[defs[1].nodes.Count - 1].z);
            float endWl = river.WlAtPoint(cEnd.x, cEnd.y);
            creek = River.Build(defs[1], noise, endWl, 2);
            gw.rivers.Add(river); gw.rivers.Add(creek);
            rDist = new float[size * size]; rT = new float[size * size];
            cDist = new float[size * size]; cT = new float[size * size];
            Fill(rDist, float.MaxValue); Fill(cDist, float.MaxValue);
            RasterRiver(river, rDist, rT);
            RasterRiver(creek, cDist, cT);
        }

        static void Fill(float[] a, float v) { for (int i = 0; i < a.Length; i++) a[i] = v; }

        void RasterRiver(River r, float[] dist, float[] t)
        {
            var link = new bool[r.n];
            for (int i = 0; i < r.n - 1; i++) link[i] = true;
            var rad = new float[r.n];
            for (int i = 0; i < r.n; i++) rad[i] = r.influence[Mathf.Min(r.n - 1, i + 1)];
            SegmentRaster.Rasterize(size, cell, origin, r.x, r.z, link, rad, dist, t);
        }

        void InitPadsAndPonds()
        {
            foreach (var p in pads)
            {
                float y = p.y;
                if (float.IsNaN(y)) y = BaseHeightPoint(p.x, p.z, false);
                padY.Add(y);
            }
            if (!cfg.full) return;
            foreach (var pd in WorldLayout.BuildPonds())
            {
                float lvl = pd.level;
                if (float.IsNaN(lvl)) lvl = BaseHeightPoint(pd.x, pd.z, true) - 0.45f;
                ponds.Add(new PondInfo { def = pd, level = lvl });
            }
            gw.ponds = ponds;
        }

        /// <summary>Height at a point without ponds/mountains (brute force river distances) - used to place pads and ponds.</summary>
        float BaseHeightPoint(float x, float z, bool withPadsAndRivers)
        {
            float h = Interior(x, z);
            float S = SwampMask(x, z);
            if (S > 0.001f) h = Mathf.Lerp(h, SwampHeight(x, z), S);
            if (!withPadsAndRivers) return h;
            h = ApplyPads(x, z, h);
            if (river != null)
            {
                river.Nearest(x, z, out float d, out float t);
                if (d < river.influence[Mathf.Clamp((int)t, 0, river.n - 1)]) h = RiverHeight(river, d, t, x, z, h, out _);
                creek.Nearest(x, z, out d, out t);
                if (d < creek.influence[Mathf.Clamp((int)t, 0, creek.n - 1)]) h = RiverHeight(creek, d, t, x, z, h, out _);
            }
            return h;
        }

        float RiverHeight(River r, float d, float t, float x, float z, float hIn, out float wl)
        {
            var sm = new River.Sample();
            r.Eval(t, ref sm);
            return River.CellHeight(r, sm, d, x, z, hIn, noise, out wl, out _);
        }

        // ================================================================== base terrain functions

        static float G(float x, float z, float cx, float cz, float sx, float sz)
        {
            float dx = (x - cx) / sx, dz = (z - cz) / sz;
            return Mathf.Exp(-0.5f * (dx * dx + dz * dz));
        }

        static float Sm(float a, float b, float x) { return WorldNoise.Smooth(a, b, x); }

        /// <summary>Rolling hills plus authored landforms (no rivers, no mountains).</summary>
        public float Interior(float x, float z)
        {
            float h = 17f;
            h += 13f * noise.Fbm(x * 0.0020f + 3.1f, z * 0.0020f - 1.7f, 3);
            h += 4.4f * noise.Fbm(x * 0.0085f + 9.3f, z * 0.0085f + 4.4f, 3);
            h += 1.1f * noise.Fbm(x * 0.030f - 5.2f, z * 0.030f + 2.9f, 3);
            h += 0.30f * noise.Fbm(x * 0.13f + 1.1f, z * 0.13f - 7.7f, 2);
            float sh = Sm(-90f, -340f, z);
            if (sh > 0f) h += sh * (8f + 13f * noise.Ridged(x * 0.0030f + 5.5f, z * 0.0030f - 2.2f, 3));
            h += 40f * G(x, z, -470f, 380f, 240f, 240f);
            h += 34f * G(x, z, -450f, 480f, 60f, 60f);
            h += 24f * G(x, z, 100f, 600f, 65f, 65f);
            h += 46f * G(x, z, 350f, -310f, 80f, 60f);
            h += 14f * G(x, z, 600f, -330f, 120f, 100f);
            float nr = Mathf.Exp(-((z - 668f) / 85f) * ((z - 668f) / 85f)) * Sm(-740f, -470f, x) * (1f - 0.92f * Sm(240f, 520f, x));
            h += 30f * nr;
            float ex = Sm(-520f, -250f, x) * (1f - Sm(-60f, 120f, x));
            if (ex > 0f) h += 9f * Sm(80f, 190f, z + 14f * noise.Fbm(x * 0.012f, z * 0.012f, 2)) * (1f - Sm(260f, 520f, z)) * ex;
            h += 27f * G(x, z, -372f, 205f, 42f, 38f);       // steep knoll the central track climbs over
            return h;
        }

        /// <summary>0..1 swamp basin mask (NE).</summary>
        public float SwampMask(float x, float z)
        {
            var c = WorldLayout.SwampCenter; var r = WorldLayout.SwampRadii;
            float dx = (x - c.x) / r.x, dz = (z - c.y) / r.y;
            float q = Mathf.Sqrt(dx * dx + dz * dz);
            if (q > 1.7f) return 0f;
            q *= 1f + 0.2f * noise.Fbm(x * 0.011f + 40f, z * 0.011f - 25f, 3);
            return 1f - Sm(0.55f, 1.12f, q);
        }

        public float SwampHeight(float x, float z)
        {
            float pools = noise.Fbm(x * 0.026f + 12f, z * 0.026f - 8f, 3);
            float pm = Sm(-0.02f, 0.30f, pools);
            float hump = 0.5f * noise.Fbm(x * 0.11f, z * 0.11f, 2);
            float bog = BogBase + 0.14f * hump + 0.10f * noise.Fbm(x * 0.017f, z * 0.017f, 2);
            float bed = SwampWl - 0.12f - 0.55f * pm;
            return Mathf.Lerp(bog, bed, pm);
        }

        float OutsideDistance(float x, float z)
        {
            float ax = Mathf.Abs(x) - WorldLayout.Play, az = Mathf.Abs(z) - WorldLayout.Play;
            if (ax > 0f && az > 0f) return Mathf.Sqrt(ax * ax + az * az);
            return Mathf.Max(0f, Mathf.Max(ax, az));
        }

        /// <summary>Mountain ring added on top of the interior terrain (and a gentle rise inside the border).</summary>
        public float Mountain(float x, float z)
        {
            float ax = Mathf.Abs(x) - WorldLayout.Play, az = Mathf.Abs(z) - WorldLayout.Play;
            float m = Mathf.Max(ax, az);                 // signed distance-ish (negative inside)
            float inside = 0f;
            if (m < 0f) inside = 18f * Sm(-110f, 0f, m);
            float passM = PgPass(x, z);
            if (passM > 0f) inside *= 1f - 0.93f * passM;
            float dOut = OutsideDistance(x, z);
            if (dOut <= 0f) return inside;
            float dn = dOut + 12f * noise.Fbm(x * 0.0075f + 2f, z * 0.0075f - 5f, 2);
            dn = Mathf.Max(0f, dn);
            float lin = 0.84f * dn;
            const float cap = 70f, k = 14f;
            float hmin = 0.5f * (lin + cap - Mathf.Sqrt((lin - cap) * (lin - cap) + k * k) );   // smooth minimum
            float ridged = noise.Ridged(x * 0.0065f + 8f, z * 0.0065f + 3f, 4) - 0.45f;
            float detail = 26f * ridged * Sm(8f, 80f, dOut);
            float tot = 18f + hmin + detail;
            if (passM > 0f) tot *= 1f - 0.93f * passM;
            return tot;
        }

        // ------------------------------------------------------------------ pads

        public static float PadWeight(in PadDef p, float x, float z, out float edgeDist)
        {
            float cs = Mathf.Cos(p.yawDeg * Mathf.Deg2Rad), sn = Mathf.Sin(p.yawDeg * Mathf.Deg2Rad);
            float dx = x - p.x, dz = z - p.z;
            float u = dx * cs + dz * sn, v = -dx * sn + dz * cs;
            if (p.round)
            {
                float q = Mathf.Sqrt((u / p.rx) * (u / p.rx) + (v / p.rz) * (v / p.rz));
                edgeDist = (q - 1f) * 0.5f * (p.rx + p.rz);
            }
            else
            {
                float ex = Mathf.Max(Mathf.Abs(u) - p.rx, 0f), ez = Mathf.Max(Mathf.Abs(v) - p.rz, 0f);
                edgeDist = Mathf.Sqrt(ex * ex + ez * ez);
                if (ex <= 0f && ez <= 0f) edgeDist = Mathf.Max(Mathf.Abs(u) - p.rx, Mathf.Abs(v) - p.rz);
            }
            return 1f - Sm(0f, p.blend, edgeDist);
        }

        float ApplyPads(float x, float z, float h)
        {
            for (int i = 0; i < pads.Count; i++)
            {
                var p = pads[i];
                float m = Mathf.Max(p.rx, p.rz) + p.blend + 4f;
                if (Mathf.Abs(x - p.x) > m || Mathf.Abs(z - p.z) > m) continue;
                float w = PadWeight(p, x, z, out _);
                if (w > 0f) h = Mathf.Lerp(h, padY[i], w);
            }
            return h;
        }

        // ------------------------------------------------------------------ ponds

        float PondHeight(in PondInfo pi, float x, float z, float hIn, out float wl)
        {
            wl = WaterMap.NoWater;
            var p = pi.def;
            float dx = x - p.x, dz = z - p.z;
            float rn = p.r * (1f + 0.22f * noise.Fbm(x * 0.05f + 3f, z * 0.05f + 9f, 2));
            float q = Mathf.Sqrt(dx * dx + dz * dz) / rn;
            if (q >= 1.9f) return hIn;
            if (q < 1f)
            {
                float bed = pi.level - p.depth * (1f - q * q * q);
                wl = pi.level;
                return Mathf.Min(hIn, bed);
            }
            float u = Sm(1f, 1.9f, q);
            float lip = Mathf.Max(hIn, pi.level + 0.25f);
            float edge = Mathf.Lerp(pi.level - 0.02f, lip, u);
            return Mathf.Lerp(Mathf.Min(hIn, edge), hIn, u * u);
        }

        // ================================================================== stage A

        void StageA()
        {
            var po = new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount };
            var height = map.height;
            Parallel.For(0, size, po, iz =>
            {
                float z = origin.y + iz * cell;
                int rowBase = iz * size;
                for (int ix = 0; ix < size; ix++)
                {
                    float x = origin.x + ix * cell;
                    int idx = rowBase + ix;
                    float h = Interior(x, z);
                    float S = SwampMask(x, z);
                    swamp[idx] = (byte)Mathf.Clamp(Mathf.RoundToInt(S * 255f), 0, 255);
                    if (S > 0.001f) h = Mathf.Lerp(h, SwampHeight(x, z), S);
                    h = ApplyPads(x, z, h);
                    if (rDist != null)
                    {
                        float d = rDist[idx];
                        if (d < float.MaxValue) h = RiverHeight(river, d, rT[idx], x, z, h, out _);
                        d = cDist[idx];
                        if (d < float.MaxValue)
                        {
                            float hc = RiverHeight(creek, d, cT[idx], x, z, h, out _);
                            // inside the main channel the creek may only deepen the ground, never raise it
                            if (rDist[idx] < float.MaxValue)
                            {
                                var smr = new River.Sample(); river.Eval(rT[idx], ref smr);
                                if (rDist[idx] < smr.w + smr.bankRun + 8f) hc = Mathf.Min(hc, h);
                            }
                            h = hc;
                        }
                        for (int p = 0; p < ponds.Count; p++)
                        {
                            var pd = ponds[p].def;
                            float dx = x - pd.x, dz = z - pd.z;
                            if (dx * dx + dz * dz > pd.r * pd.r * 6f) continue;
                            h = PondHeight(ponds[p], x, z, h, out _);
                        }
                    }
                    h += Mountain(x, z);
                    h = PgHeight(x, z, h);
                    height[idx] = h;
                }
            });
        }

        // ================================================================== tracks (stage B)

        float SampleHeight(float x, float z) { return map.SampleHeight(x, z); }

        void BuildTracks()
        {
            tset = new TrackSet();
            var defs = new List<TrackDef>();
            if (cfg.full) defs.AddRange(WorldLayout.BuildTracks());
            defs.AddRange(PgTracks());
            // order: parents first
            var done = new HashSet<string>();
            var pending = new List<TrackDef>(defs);
            int guard = 0;
            while (pending.Count > 0 && guard++ < 20)
            {
                for (int i = 0; i < pending.Count; i++)
                {
                    var d = pending[i];
                    bool ok = (string.IsNullOrEmpty(d.parent) || done.Contains(d.parent) || !Exists(defs, d.parent)) &&
                              (string.IsNullOrEmpty(d.endParent) || done.Contains(d.endParent) || !Exists(defs, d.endParent));
                    if (!ok) continue;
                    var t = TrackBuilder.Build(d, tset.tracks.Count, noise);
                    TrackBuilder.SolveProfile(t, SampleHeight, string.IsNullOrEmpty(d.parent) ? null : tset.Find(d.parent),
                        string.IsNullOrEmpty(d.endParent) ? null : tset.Find(d.endParent), RoadFloor);
                    tset.tracks.Add(t);
                    done.Add(d.name);
                    pending.RemoveAt(i); i--;
                }
            }
            tset.Finish();
        }

        /// <summary>Roads in the swamp stay above the standing water.</summary>
        float RoadFloor(float x, float z) { return SwampMask(x, z) > 0.12f ? SwampWl + 0.2f : -1000f; }

        static bool Exists(List<TrackDef> defs, string name) { foreach (var d in defs) if (d.name == name) return true; return false; }

        // ================================================================== stage C: carve the roads

        void StageC()
        {
            int n = tset.count;
            tDist = new float[size * size]; tT = new float[size * size];
            Fill(tDist, float.MaxValue);
            gw.roadEdge = new float[size * size];
            Fill(gw.roadEdge, float.MaxValue);
            if (n < 2) return;
            var rad = new float[n];
            for (int i = 0; i < n; i++) rad[i] = tset.ghw[i] + 31f;
            SegmentRaster.Rasterize(size, cell, origin, tset.gx, tset.gz, tset.glink, rad, tDist, tT);
            var po = new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount };
            var height = map.height;
            Parallel.For(0, size, po, iz =>
            {
                int rowBase = iz * size;
                for (int ix = 0; ix < size; ix++)
                {
                    int idx = rowBase + ix;
                    float td = tDist[idx];
                    if (td >= float.MaxValue) continue;
                    float t = tT[idx];
                    int j = (int)t; float u = t - j;
                    int jj = j + 1;
                    if (jj >= n || !tset.glink[j]) continue;
                    float hw = Mathf.Lerp(tset.ghw[j], tset.ghw[jj], u);
                    gw.roadEdge[idx] = td - hw;
                    if (!tset.gcarve[j] || !tset.gcarve[jj]) continue;
                    float Y = Mathf.Lerp(tset.gy[j], tset.gy[jj], u);
                    float hCur = height[idx];
                    float diff = hCur - Y;
                    float sh = Mathf.Clamp(4f + 3.2f * Mathf.Abs(diff), 4f, 30f);
                    if (td > hw + sh) continue;
                    float wRoad = 1f - Sm(hw * 0.9f, hw + sh, td);
                    float camber = 0.09f * Sm(0.3f, 1f, Mathf.Min(1f, td / hw));
                    float yc = Y - camber;
                    height[idx] = hCur + (yc - hCur) * wRoad;
                }
            });
        }

        // ================================================================== stage D: surfaces, wetness, hidden depth, water

        static void RoadVec(SurfaceType t, float[] o)
        {
            for (int k = 0; k < 8; k++) o[k] = 0f;
            switch (t)
            {
                case SurfaceType.Gravel: o[(int)SurfaceType.Gravel] = 0.82f; o[(int)SurfaceType.FirmSoil] = 0.12f; o[(int)SurfaceType.Rock] = 0.06f; break;
                case SurfaceType.FirmSoil: o[(int)SurfaceType.FirmSoil] = 0.78f; o[(int)SurfaceType.Gravel] = 0.12f; o[(int)SurfaceType.Grass] = 0.10f; break;
                case SurfaceType.ShallowMud: o[(int)SurfaceType.ShallowMud] = 0.82f; o[(int)SurfaceType.FirmSoil] = 0.10f; o[(int)SurfaceType.Grass] = 0.08f; break;
                case SurfaceType.DeepMud: o[(int)SurfaceType.DeepMud] = 0.84f; o[(int)SurfaceType.ShallowMud] = 0.16f; break;
                case SurfaceType.Bog: o[(int)SurfaceType.Bog] = 0.82f; o[(int)SurfaceType.DeepMud] = 0.18f; break;
                case SurfaceType.Rock: o[(int)SurfaceType.Rock] = 0.7f; o[(int)SurfaceType.Gravel] = 0.3f; break;
                default: o[(int)t] = 1f; break;
            }
        }

        void StageD()
        {
            var po = new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount };
            var height = map.height;
            var water = new WaterMap(size, cell, origin);
            gw.water = water; map.water = water;
            int tn = tset.count;
            var pads2 = pads;
            // slowly varying noise fields on a 4 m grid (bilinear lookup in the per-cell loop)
            const int cstep = 4;
            int cs = (size - 1) / cstep + 2;
            var cN0 = new float[cs * cs]; var cN1 = new float[cs * cs]; var cRidge = new float[cs * cs]; var cRock = new float[cs * cs]; var cGrav = new float[cs * cs];
            Parallel.For(0, cs, po, j =>
            {
                float zz = origin.y + j * cstep;
                for (int i = 0; i < cs; i++)
                {
                    float xx = origin.x + i * cstep; int k = j * cs + i;
                    cN0[k] = noise.Fbm(xx * 0.0042f + 70f, zz * 0.0042f - 33f, 3);
                    cN1[k] = noise.Fbm(xx * 0.014f + 21f, zz * 0.014f - 4f, 3);
                    cRidge[k] = noise.Ridged(xx * 0.012f + 40f, zz * 0.012f - 15f, 3);
                    cRock[k] = noise.Fbm(xx * 0.021f - 50f, zz * 0.021f + 70f, 3);
                    cGrav[k] = noise.Fbm(xx * 0.035f + 13f, zz * 0.035f - 21f, 2);
                }
            });
            Parallel.For(0, size, po, iz =>
            {
                var w = new float[8];
                var v1 = new float[8];
                var v2 = new float[8];
                float z = origin.y + iz * cell;
                int rowBase = iz * size;
                for (int ix = 0; ix < size; ix++)
                {
                    float x = origin.x + ix * cell;
                    int idx = rowBase + ix;
                    float h = height[idx];

                    // ---- slope
                    int il = ix > 0 ? idx - 1 : idx, ir = ix < size - 1 ? idx + 1 : idx;
                    int idn = iz > 0 ? idx - size : idx, iu = iz < size - 1 ? idx + size : idx;
                    float gx = (height[ir] - height[il]) / ((ir - il) * cell);
                    float gz = (height[iu] - height[idn]) / (((iu - idn) / size) * cell);
                    float slope = Mathf.Atan(Mathf.Sqrt(gx * gx + gz * gz)) * Mathf.Rad2Deg;

                    float S = swamp[idx] * (1f / 255f);
                    float cgx = ix * (1f / cstep), cgz = iz * (1f / cstep);
                    float n1 = Bil(cN1, cs, cgx, cgz);
                    float n2 = noise.Fbm(x * 0.055f + 31f, z * 0.055f - 12f, 2);
                    float n3 = noise.Perlin(x * 0.17f + 7f, z * 0.17f + 3f);

                    // ---- water proximity
                    float waterLevel = WaterMap.NoWater;
                    Vector2 flow = Vector2.zero;
                    float riverProx = 0f, shoreD = 999f, ford = 0f;
                    bool inRiver = false, inCreek = false;
                    float rWeff = 0f, rBar = 0f, floodH = 99f;
                    if (rDist != null)
                    {
                        EvalRiverCell(river, rDist[idx], rT[idx], x, z, h, ref waterLevel, ref flow, ref shoreD, ref ford, ref inRiver, ref rWeff, ref rBar, ref floodH);
                        float sd2 = 999f, f2 = 0f, weff2 = 0f, bar2 = 0f; bool inC = false;
                        float wl2 = WaterMap.NoWater; Vector2 flow2 = Vector2.zero;
                        EvalRiverCell(creek, cDist[idx], cT[idx], x, z, h, ref wl2, ref flow2, ref sd2, ref f2, ref inC, ref weff2, ref bar2, ref floodH);
                        if (inC && (!inRiver || wl2 > waterLevel - 0.3f)) { if (!inRiver) { waterLevel = wl2; flow = flow2; } inCreek = true; }
                        if (sd2 < shoreD) { shoreD = sd2; ford = f2; rBar = bar2; }
                    }
                    // ponds
                    float pondShore = 999f; bool inPond = false;
                    for (int p = 0; p < ponds.Count; p++)
                    {
                        var pd = ponds[p].def;
                        float dx = x - pd.x, dz = z - pd.z;
                        float d2 = dx * dx + dz * dz;
                        float lim = pd.r * 3f + 60f;
                        if (d2 > lim * lim) continue;
                        float dist = Mathf.Sqrt(d2), dd;
                        if (dist > pd.r * 2f) dd = dist - pd.r;
                        else
                        {
                            float rn = pd.r * (1f + 0.22f * noise.Fbm(x * 0.05f + 3f, z * 0.05f + 9f, 2));
                            dd = dist - rn;
                            if (dd < 0f && h < ponds[p].level - 0.02f) { inPond = true; waterLevel = ponds[p].level; flow = Vector2.zero; }
                        }
                        if (dd < pondShore) pondShore = dd;
                    }
                    // swamp pools
                    if (S > 0.25f && h < SwampWl - 0.02f && !inRiver && !inCreek && !inPond) { waterLevel = SwampWl; flow = Vector2.zero; }

                    // ---- wetness
                    float shore = Mathf.Min(shoreD, pondShore);
                    float n0 = Bil(cN0, cs, cgx, cgz);     // ~250 m: dry / moist regions
                    float wet = 0.2f + 0.14f * n1 + 0.05f * n2 - 0.10f * Mathf.Clamp(n0, -0.5f, 0.5f);
                    if (shore < 200f) wet += 0.55f * Mathf.Exp(-Mathf.Max(0f, shore) / 15f);
                    if (floodH < 5f) wet += 0.16f * (1f - Sm(0.4f, 5f, floodH));
                    wet += 1.0f * S;
                    wet *= 1f - 0.65f * Sm(12f, 28f, slope);
                    wet = Mathf.Clamp01(wet);

                    // ---- natural surface mixture
                    float wetc = Mathf.Clamp01((wet - 0.2f) * 2.0f);
                    float dryAmt = Sm(-0.02f, 0.30f, n0 + 0.35f * n1) * (1f - Sm(0.35f, 0.6f, wet));
                    float ridge = Bil(cRidge, cs, cgx, cgz);
                    float rock = Sm(34f, 48f, slope + 8f * n2) + 0.35f * Sm(0.40f, 0.62f, Bil(cRock, cs, cgx, cgz)) * Sm(8f, 18f, slope) * (1f - S);
                    rock += 0.6f * Sm(0.62f, 0.84f, ridge) * Sm(3f, 11f, slope) * (1f - wetc) * (1f - S);
                    rock = Mathf.Clamp01(rock);
                    float bog = Sm(0.30f, 0.62f, S + 0.30f * (0.7f * n2 + 0.3f * n3));
                    float deep = Sm(0.80f, 0.97f, wet + 0.12f * n3 + 0.10f * n2) * (1f - rock);
                    float mud = Sm(0.56f, 0.80f, wet + 0.16f * n3) * (1f - rock);
                    float sand = 0f;
                    if (shore < 6f) sand = (1f - Sm(0.2f, 4.5f, Mathf.Max(0f, shore))) * (0.35f + 0.5f * Mathf.Max(0f, rBar) + 0.25f * (n3 * 0.5f + 0.5f));
                    sand = Mathf.Clamp01(sand);
                    float gravelAmt = 0.45f * Sm(0.42f, 0.70f, Bil(cGrav, cs, cgx, cgz)) * dryAmt * (1f - Sm(8f, 18f, slope)) * (1f - S);
                    float rem = (1f - rock) * (1f - bog) * (1f - 0.9f * deep) * (1f - 0.85f * mud) * (1f - sand);
                    float grassShare = Mathf.Clamp01(0.85f - 0.6f * dryAmt + 0.3f * wetc + 0.12f * n2 - 0.1f * Sm(20f, 36f, slope));
                    for (int k = 0; k < 8; k++) w[k] = 0f;
                    w[(int)SurfaceType.Rock] = rock;
                    w[(int)SurfaceType.Bog] = bog * (1f - rock);
                    w[(int)SurfaceType.DeepMud] = deep * (1f - bog);
                    w[(int)SurfaceType.ShallowMud] = mud * (1f - bog) * (1f - deep);
                    w[(int)SurfaceType.Sand] = sand * (1f - bog);
                    w[(int)SurfaceType.Gravel] = rem * gravelAmt;
                    w[(int)SurfaceType.Grass] = rem * (1f - gravelAmt) * grassShare;
                    w[(int)SurfaceType.FirmSoil] = rem * (1f - gravelAmt) * (1f - grassShare);

                    float extra = 0f;
                    if (S > 0.2f) extra = Mathf.Max(extra, S * (0.25f + 0.65f * Sm(-0.2f, 0.5f, n2)) * bog);
                    extra = Mathf.Max(extra, 0.3f * deep * (0.5f + 0.5f * (n2 * 0.5f + 0.5f)));

                    PgBase(x, z, slope, w, ref wet, ref extra);

                    // ---- channels (river bed / ponds): override with bed material
                    if (rDist != null)
                    {
                        float chA = 0f; float fordF = 0f;
                        if (inRiver || shoreD < 1.8f) { chA = 1f - Sm(-0.3f, 1.8f, shoreD); fordF = ford; }
                        if (chA > 0f)
                        {
                            for (int k = 0; k < 8; k++) v1[k] = 0f;
                            v1[(int)SurfaceType.Gravel] = 0.15f + 0.5f * fordF; v1[(int)SurfaceType.Sand] = 0.5f - 0.25f * fordF; v1[(int)SurfaceType.ShallowMud] = 0.35f * (1f - fordF); v1[(int)SurfaceType.Rock] = 0.12f * fordF;
                            Lerp8(w, v1, chA);
                            wet = Mathf.Lerp(wet, 1f, chA); extra *= 1f - chA;
                        }
                        float pA = 0f;
                        if (pondShore < 1.5f) pA = 1f - Sm(-0.3f, 1.5f, pondShore);
                        if (pA > 0f)
                        {
                            for (int k = 0; k < 8; k++) v1[k] = 0f;
                            v1[(int)SurfaceType.Sand] = 0.35f; v1[(int)SurfaceType.ShallowMud] = 0.4f; v1[(int)SurfaceType.DeepMud] = 0.25f;
                            Lerp8(w, v1, pA);
                            wet = Mathf.Lerp(wet, 1f, pA); extra *= 1f - pA;
                        }
                    }

                    // ---- roads
                    float td = tDist[idx];
                    if (td < float.MaxValue && tn > 1)
                    {
                        float t = tT[idx];
                        int j = (int)t; float u = t - j; int jj = Mathf.Min(j + 1, tn - 1);
                        if (j < tn - 1 && tset.glink[j] && tset.gcarve[j] && tset.gcarve[jj])
                        {
                            var tr = tset.gtrack[j]; int lj = tset.glocal[j], lk = tset.glocal[jj];
                            float hw = Mathf.Lerp(tr.halfW[lj], tr.halfW[lk], u);
                            float edge = td + 0.28f * n3 * (0.5f + 0.5f * n2);
                            float roadA = 1f - Sm(hw * 0.78f, hw + 1.1f, edge);
                            if (roadA > 0.002f)
                            {
                                var sA = (SurfaceType)tr.surfA[lj]; var sB = (SurfaceType)tr.surfB[lj];
                                RoadVec(sA, v1);
                                float mx = Mathf.Lerp(tr.mix[lj], tr.mix[lk], u);
                                if (mx > 0.01f && tr.surfB[lj] != tr.surfA[lj]) { RoadVec(sB, v2); for (int k = 0; k < 8; k++) v1[k] = Mathf.Lerp(v1[k], v2[k], mx); }
                                bool rut = tr.ruts[lj];
                                if (rut && (sA == SurfaceType.FirmSoil || sA == SurfaceType.Gravel))
                                {
                                    float lane = 1f - Sm(0.15f, 0.6f, Mathf.Abs(td - 0.95f));
                                    v1[(int)SurfaceType.ShallowMud] += 0.55f * lane;
                                    float mid = 1f - Sm(0.2f, 0.8f, td);
                                    v1[(int)SurfaceType.Grass] += 0.35f * mid; v1[(int)SurfaceType.FirmSoil] += 0.0f;
                                }
                                Lerp8(w, v1, roadA);
                                float rw = Mathf.Lerp(tr.wet[lj], tr.wet[lk], u);
                                wet = Mathf.Lerp(wet, rw, roadA);
                                float rex = Mathf.Lerp(tr.extra[lj], tr.extra[lk], u);
                                extra = Mathf.Lerp(extra, rex, roadA);
                            }
                        }
                    }

                    // ---- pads
                    for (int p = 0; p < pads2.Count; p++)
                    {
                        var pd = pads2[p];
                        float m = Mathf.Max(pd.rx, pd.rz) + 8f;
                        if (Mathf.Abs(x - pd.x) > m || Mathf.Abs(z - pd.z) > m) continue;
                        PadWeight(pd, x, z, out float ed);
                        float pa = 1f - Sm(0f, 5f, ed + 0.4f * n3);
                        if (pa > 0.002f)
                        {
                            RoadVec(pd.surf, v1);
                            if (pd.surf == SurfaceType.FirmSoil) { v1[(int)SurfaceType.Grass] += 0.12f * (n2 * 0.5f + 0.5f); }
                            Lerp8(w, v1, pa);
                            wet = Mathf.Lerp(wet, pd.wet, pa); extra *= 1f - pa;
                        }
                    }

                    // ---- hidden depth traps (look like ordinary wet grass / mud)
                    for (int p = 0; p < traps.Count; p++)
                    {
                        var tp = traps[p];
                        float dx = x - tp.x, dz = z - tp.z;
                        float rr = tp.r * (1f + 0.25f * noise.Fbm(x * 0.07f + p * 7f, z * 0.07f - p * 3f, 2));
                        if (Mathf.Abs(dx) > rr * 1.3f || Mathf.Abs(dz) > rr * 1.3f) continue;
                        float dd = Mathf.Sqrt(dx * dx + dz * dz);
                        float a = 1f - Sm(0.45f * rr, rr, dd);
                        if (a <= 0f) continue;
                        if (tp.depth > 0f) extra = Mathf.Max(extra, tp.depth * a);
                        wet = Mathf.Max(wet, 0.86f * a);
                        for (int k = 0; k < 8; k++) v1[k] = 0f;
                        if (tp.mudLook) { v1[(int)SurfaceType.ShallowMud] = 0.62f; v1[(int)SurfaceType.DeepMud] = 0.2f; v1[(int)SurfaceType.Grass] = 0.18f; }
                        else { v1[(int)SurfaceType.Grass] = 0.8f; v1[(int)SurfaceType.ShallowMud] = 0.2f; }
                        Lerp8(w, v1, 0.75f * a);
                    }

                    // ---- proving ground override
                    PgSurface(x, z, h, slope, w, ref wet, ref extra);

                    map.SetWeights(ix, iz, new ReadOnlySpan<float>(w));
                    map.baseWet[idx] = (byte)Mathf.Clamp(Mathf.RoundToInt(wet * 255f), 0, 255);
                    map.extraDepth[idx] = (byte)Mathf.Clamp(Mathf.RoundToInt(extra / GroundMap.MaxExtraDepth * 255f), 0, 255);

                    if (waterLevel > float.NegativeInfinity)
                    {
                        water.level[idx] = waterLevel;
                        if (flow.sqrMagnitude > 1e-4f)
                        {
                            water.flowX[idx] = (sbyte)Mathf.Clamp(Mathf.RoundToInt(flow.x * 10f), -127, 127);
                            water.flowZ[idx] = (sbyte)Mathf.Clamp(Mathf.RoundToInt(flow.y * 10f), -127, 127);
                        }
                    }
                }
            });
            PgWater(water);
        }

        static float Bil(float[] a, int cs, float gx, float gz)
        {
            int i0 = (int)gx, j0 = (int)gz;
            if (i0 >= cs - 1) i0 = cs - 2; if (j0 >= cs - 1) j0 = cs - 2;
            float fx = gx - i0, fz = gz - j0;
            int k = j0 * cs + i0;
            float a0 = a[k] + (a[k + 1] - a[k]) * fx, a1 = a[k + cs] + (a[k + cs + 1] - a[k + cs]) * fx;
            return a0 + (a1 - a0) * fz;
        }

        static void Lerp8(float[] a, float[] b, float t)
        {
            float sa = 0f, sb = 0f;
            for (int k = 0; k < 8; k++) { sa += a[k]; sb += b[k]; }
            if (sb < 1e-5f) return;
            float inv = sa > 1e-5f ? sa / sb : 1f;     // keep the total comparable
            for (int k = 0; k < 8; k++) a[k] = Mathf.Lerp(a[k], b[k] * inv, t);
        }

        /// <summary>River / creek per-cell water + shore information.</summary>
        void EvalRiverCell(River r, float d, float t, float x, float z, float h, ref float waterLevel, ref Vector2 flow,
                           ref float shoreD, ref float ford, ref bool inChannel, ref float wEffOut, ref float bar, ref float floodH)
        {
            if (d >= float.MaxValue) return;
            var sm = new River.Sample(); r.Eval(t, ref sm);
            float fh = h - sm.wl;
            if (fh < floodH) floodH = fh;
            float bn = noise.Fbm(x * 0.055f + 17f, z * 0.055f - 9f, 2);
            float wEff = Mathf.Max(0.8f, sm.w * (1f + 0.17f * bn));
            float cross = sm.tx * (z - sm.pz) - sm.tz * (x - sm.px);
            float side = cross >= 0f ? 1f : -1f;
            bar = Mathf.Clamp(sm.curv * 60f, -1f, 1f) * side;
            shoreD = d - wEff;
            ford = sm.ford;
            wEffOut = wEff;
            if (d <= wEff && h < sm.wl - 0.02f)
            {
                inChannel = true;
                waterLevel = sm.wl;
                float dn = Mathf.Clamp01(d / wEff);
                float sp = sm.speed * (0.45f + 0.55f * (1f - dn * dn));
                flow = new Vector2(sm.tx, sm.tz) * sp;
            }
        }

        // ================================================================== proving ground hooks (TerrainGenerator.PG.cs)
    }
}
