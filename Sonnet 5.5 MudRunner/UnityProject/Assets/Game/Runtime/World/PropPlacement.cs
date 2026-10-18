using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>Deterministic placement of the instanced vegetation / rocks and the structure list for a generated world.</summary>
    public static class PropPlacement
    {
        public const int Spruce_A = 0, Spruce_B = 1, Spruce_C = 2, Birch = 3, DeadTree = 4, Rock_S = 5, Rock_M = 6, Rock_L = 7, Rock_Slab = 8,
                         Stump = 9, Reed = 10, Bush = 11, Moss = 12, LogLong = 13, LogShort = 14;
        public static readonly string[] TypeIds = { "spruce_a", "spruce_b", "spruce_c", "birch", "deadtree", "rock_s", "rock_m", "rock_l", "rock_slab", "stump", "reed", "bush", "moss", "log_long", "log_short" };
        static readonly bool[] Solid = { true, true, true, true, true, true, true, true, true, true, false, false, false, true, true };

        struct Env
        {
            public float h, slope, wet, S, roadEdge, padEdge, pgSdf;
            public bool water;
            public float wRock, wFirm, wGrass, wGravel, wShallow, wDeep, wBog, wSand;
        }

        sealed class Ctx
        {
            public GeneratedWorld gw; public GroundMap map; public WorldNoise noise; public int size; public float ox, oz;
            public byte[] swamp; public float[] roadEdge; public WaterMap water; public List<PadDef> pads;
        }

        static bool Fetch(Ctx c, float x, float z, out Env e)
        {
            e = default;
            int ix = Mathf.RoundToInt(x - c.ox), iz = Mathf.RoundToInt(z - c.oz);
            if (ix < 3 || iz < 3 || ix >= c.size - 3 || iz >= c.size - 3) return false;
            int idx = iz * c.size + ix;
            var m = c.map;
            e.h = m.height[idx];
            float gx = (m.height[idx + 2] - m.height[idx - 2]) * 0.25f, gz = (m.height[idx + 2 * c.size] - m.height[idx - 2 * c.size]) * 0.25f;
            e.slope = Mathf.Atan(Mathf.Sqrt(gx * gx + gz * gz)) * Mathf.Rad2Deg;
            e.wet = m.baseWet[idx] * (1f / 255f);
            e.S = c.swamp[idx] * (1f / 255f);
            e.roadEdge = c.roadEdge != null ? c.roadEdge[idx] : float.MaxValue;
            e.water = c.water != null && c.water.level[idx] > e.h - 0.1f;
            int o = idx * 8; const float k = 1f / 255f;
            e.wRock = m.weights[o] * k; e.wFirm = m.weights[o + 1] * k; e.wGrass = m.weights[o + 2] * k; e.wGravel = m.weights[o + 3] * k;
            e.wShallow = m.weights[o + 4] * k; e.wDeep = m.weights[o + 5] * k; e.wBog = m.weights[o + 6] * k; e.wSand = m.weights[o + 7] * k;
            float pe = float.MaxValue;
            for (int i = 0; i < c.pads.Count; i++)
            {
                var p = c.pads[i];
                float mx = Mathf.Max(p.rx, p.rz) + 14f;
                if (Mathf.Abs(x - p.x) > mx || Mathf.Abs(z - p.z) > mx) continue;
                TerrainGenerator.PadWeight(p, x, z, out float ed);
                if (p.name == "CabinIsland") ed += 14f;      // trees may grow on the outer ring of the island
                if (ed < pe) pe = ed;
            }
            e.padEdge = pe;
            e.pgSdf = x > 780f ? PgLayout.RectSdf(x, z, PgLayout.BowlX0, PgLayout.BowlX1, PgLayout.BowlZ0, PgLayout.BowlZ1) : 99f;
            return true;
        }

        delegate void CellFn(Ctx c, int gi, int gj, float x, float z, List<PropInst> o);

        static void Grid(Ctx c, float g, uint salt, List<PropInst> dst, CellFn fn)
        {
            int n = Mathf.FloorToInt((c.size - 8) / g);
            var rows = new List<PropInst>[n];
            Parallel.For(0, n, gj =>
            {
                var l = new List<PropInst>(64);
                for (int gi = 0; gi < n; gi++)
                {
                    float jx = WorldNoise.Hash01(gi, gj, salt), jz = WorldNoise.Hash01(gi, gj, salt + 1000003u);
                    float x = c.ox + 4f + (gi + jx) * g, z = c.oz + 4f + (gj + jz) * g;
                    fn(c, gi, gj, x, z, l);
                }
                rows[gj] = l;
            });
            for (int j = 0; j < n; j++) dst.AddRange(rows[j]);
        }

        static PropInst Make(int type, float x, float z, float yaw, float scale, Env e, float sink = 0.05f)
        {
            return new PropInst { type = (ushort)type, x = x, y = e.h - sink, z = z, yaw = yaw, scale = scale };
        }

        // ------------------------------------------------------------------ the placement

        public static PropSet Place(GeneratedWorld gw)
        {
            var map = gw.map;
            var c = new Ctx { gw = gw, map = map, noise = gw.noise, size = map.size, ox = map.origin.x, oz = map.origin.y, swamp = gw.swamp, roadEdge = gw.roadEdge, water = gw.water, pads = gw.pads };
            var list = new List<PropInst>(200000);
            uint seed = gw.cfg.seed;
            var noise = gw.noise;

            // ---- trees (spruce / birch / dead trees)
            Grid(c, 5.0f, seed + 11u, list, (cc, gi, gj, x, z, o) =>
            {
                if (!Fetch(cc, x, z, out var e)) return;
                float forest = noise.Fbm(x * 0.0075f + 5f, z * 0.0075f - 3f, 3);
                float dens = WorldNoise.Smooth(-0.65f, -0.05f, forest);
                float surf = e.wGrass * 0.95f + e.wFirm * 0.75f + e.wRock * 0.10f + e.wShallow * 0.10f + e.wDeep * 0.01f + e.wSand * 0.02f;
                dens *= surf;
                dens *= 1f - WorldNoise.Smooth(40f, 54f, e.slope);
                dens *= 1f - WorldNoise.Smooth(88f, 108f, e.h);
                if (e.water) dens = 0f;
                if (e.roadEdge < 1.9f) dens = 0f; else if (e.roadEdge < 8f) dens *= Mathf.Pow(WorldNoise.Smooth(1.9f, 8f, e.roadEdge), 0.8f);
                if (e.pgSdf < 3f) dens = 0f;
                if (e.padEdge < 5f) dens = 0f; else if (e.padEdge < 20f) dens *= WorldNoise.Smooth(5f, 20f, e.padEdge);
                float r0 = WorldNoise.Hash01(gi, gj, seed + 21u);
                // dead trees in the swamp
                if (e.S > 0.2f && !e.water && r0 < 0.045f * WorldNoise.Smooth(0.2f, 0.6f, e.S) && e.wBog > 0.2f)
                {
                    o.Add(Make(DeadTree, x, z, WorldNoise.Hash01(gi, gj, seed + 22u) * 360f, 0.8f + 0.5f * WorldNoise.Hash01(gi, gj, seed + 23u), e));
                    return;
                }
                if (r0 > dens) return;
                float r1 = WorldNoise.Hash01(gi, gj, seed + 24u), r2 = WorldNoise.Hash01(gi, gj, seed + 25u), r3 = WorldNoise.Hash01(gi, gj, seed + 26u);
                float birchP = Mathf.Min(0.38f, 0.03f + 0.4f * WorldNoise.Smooth(0.3f, 0.75f, e.wet));
                int type; float scale;
                if (r1 < birchP) { type = Birch; scale = 0.8f + 0.45f * r3; }
                else
                {
                    float edge = 1f - WorldNoise.Smooth(0.2f, 0.75f, dens);
                    float youngP = 0.10f + 0.5f * edge;
                    if (r2 < youngP) { type = Spruce_C; scale = 0.8f + 0.7f * r3; }
                    else if (r2 < youngP + 0.38f) { type = Spruce_B; scale = 0.82f + 0.4f * r3; }
                    else { type = Spruce_A; scale = 0.8f + 0.45f * r3; }
                }
                o.Add(Make(type, x, z, WorldNoise.Hash01(gi, gj, seed + 27u) * 360f, scale, e));
            });
            int nTrees = list.Count;

            // ---- reeds (swamp, pond / river shores, trap rims)
            Grid(c, 2.7f, seed + 31u, list, (cc, gi, gj, x, z, o) =>
            {
                if (!Fetch(cc, x, z, out var e)) return;
                if (e.water || e.pgSdf < 3f) return;
                float clump = noise.Fbm(x * 0.07f + 9f, z * 0.07f + 2f, 2);
                float p = WorldNoise.Smooth(0.78f, 0.97f, e.wet) * (0.12f + 0.55f * e.S) * WorldNoise.Smooth(-0.15f, 0.35f, clump);
                p *= 1f - WorldNoise.Smooth(7f, 16f, e.slope);
                if (e.roadEdge < 1.5f) p = 0f;
                if (e.padEdge < 2f) p = 0f;
                if (p <= 0f) return;
                if (WorldNoise.Hash01(gi, gj, seed + 32u) > p) return;
                o.Add(Make(Reed, x, z, WorldNoise.Hash01(gi, gj, seed + 33u) * 360f, 0.8f + 0.7f * WorldNoise.Hash01(gi, gj, seed + 34u), e, 0.02f));
            });
            // trap rim reeds: the subtle cue that something is wrong with the ground
            foreach (var tp in gw.traps)
            {
                if (tp.decoy && (tp.x * 7 + tp.z) % 2 < 1) continue;
                var rg = new Rng((uint)(tp.x * 31 + tp.z * 17 + 5));
                int n = Mathf.RoundToInt(tp.r * 1.6f);
                for (int i = 0; i < n; i++)
                {
                    float a = i / (float)n * Mathf.PI * 2f + rg.Next01() * 0.4f, rr = tp.r * (0.95f + 0.55f * rg.Next01());
                    float x = tp.x + Mathf.Cos(a) * rr, z = tp.z + Mathf.Sin(a) * rr;
                    if (!Fetch(c, x, z, out var e) || e.water) continue;
                    list.Add(Make(Reed, x, z, rg.Next01() * 360f, 0.9f + 0.6f * rg.Next01(), e, 0.02f));
                }
            }

            // ---- bushes
            Grid(c, 6.2f, seed + 41u, list, (cc, gi, gj, x, z, o) =>
            {
                if (!Fetch(cc, x, z, out var e)) return;
                if (e.water || e.pgSdf < 3f) return;
                float p = (0.03f + 0.22f * (1f - WorldNoise.Smooth(3.5f, 16f, e.roadEdge)) * (e.roadEdge > 3.2f ? 1f : 0f)) * (e.wGrass + e.wFirm * 0.7f);
                p *= 1f - WorldNoise.Smooth(25f, 38f, e.slope);
                if (e.padEdge < 3f) p = 0f;
                if (WorldNoise.Hash01(gi, gj, seed + 42u) > p) return;
                o.Add(Make(Bush, x, z, WorldNoise.Hash01(gi, gj, seed + 43u) * 360f, 0.7f + 0.7f * WorldNoise.Hash01(gi, gj, seed + 44u), e, 0.05f));
            });

            // ---- rocks and boulders
            Grid(c, 11f, seed + 51u, list, (cc, gi, gj, x, z, o) =>
            {
                if (!Fetch(cc, x, z, out var e)) return;
                if (e.water || e.roadEdge < 1.2f || e.padEdge < 2f || e.pgSdf < 3f) return;
                float outcrop = noise.Fbm(x * 0.03f - 10f, z * 0.03f + 4f, 2);
                float p = Mathf.Clamp01(e.wRock * 1.1f) * 0.85f + 0.10f * WorldNoise.Smooth(0.35f, 0.7f, outcrop) * WorldNoise.Smooth(5f, 14f, e.slope) + 0.015f;
                p *= 1f - 0.9f * e.S;
                if (WorldNoise.Hash01(gi, gj, seed + 52u) > p) return;
                int count = 1 + (WorldNoise.Hash01(gi, gj, seed + 53u) < 0.55f * e.wRock ? 2 : 0);
                for (int k = 0; k < count; k++)
                {
                    float ox = (WorldNoise.Hash01(gi, gj, seed + 54u + (uint)k) - 0.5f) * 8f, oz = (WorldNoise.Hash01(gi, gj, seed + 60u + (uint)k) - 0.5f) * 8f;
                    float xx = x + ox, zz = z + oz;
                    if (!Fetch(cc, xx, zz, out var e2) || e2.water || e2.roadEdge < 1.0f || e2.pgSdf < 3f) continue;
                    float r = WorldNoise.Hash01(gi + k, gj, seed + 55u);
                    float steep = WorldNoise.Smooth(15f, 35f, e2.slope);
                    int t = r < 0.42f - 0.15f * steep ? Rock_S : r < 0.74f - 0.1f * steep ? Rock_M : r < 0.92f ? Rock_L : Rock_Slab;
                    float sc = 0.75f + 0.6f * WorldNoise.Hash01(gi + k, gj, seed + 56u);
                    o.Add(Make(t, xx, zz, WorldNoise.Hash01(gi + k, gj, seed + 57u) * 360f, sc, e2, 0.15f * sc));
                }
            });

            // ---- stumps along the roads and scattered in the woods
            Grid(c, 8.5f, seed + 61u, list, (cc, gi, gj, x, z, o) =>
            {
                if (!Fetch(cc, x, z, out var e)) return;
                if (e.water || e.roadEdge < 2.3f || e.padEdge < 1f || e.pgSdf < 3f) return;
                float near = 1f - WorldNoise.Smooth(3f, 16f, e.roadEdge);
                float landing = 1f - WorldNoise.Smooth(0f, 30f, e.padEdge);
                float p = (0.012f + 0.16f * near + 0.2f * landing) * (e.wGrass + e.wFirm) * (1f - WorldNoise.Smooth(20f, 35f, e.slope));
                if (WorldNoise.Hash01(gi, gj, seed + 62u) > p) return;
                o.Add(Make(Stump, x, z, WorldNoise.Hash01(gi, gj, seed + 63u) * 360f, 0.8f + 0.5f * WorldNoise.Hash01(gi, gj, seed + 64u), e, 0.05f));
            });

            // ---- fallen logs (decor with colliders)
            Grid(c, 14f, seed + 71u, list, (cc, gi, gj, x, z, o) =>
            {
                if (!Fetch(cc, x, z, out var e)) return;
                if (e.water || e.roadEdge < 4f || e.padEdge < 3f || e.pgSdf < 3f) return;
                float forest = noise.Fbm(x * 0.0075f + 5f, z * 0.0075f - 3f, 3);
                float p = 0.05f * (e.wGrass + e.wFirm) * WorldNoise.Smooth(-0.4f, 0.1f, forest) * (1f - WorldNoise.Smooth(18f, 30f, e.slope)) * (1f - e.S);
                if (WorldNoise.Hash01(gi, gj, seed + 72u) > p) return;
                bool lng = WorldNoise.Hash01(gi, gj, seed + 73u) < 0.55f;
                var inst = Make(lng ? LogLong : LogShort, x, z, WorldNoise.Hash01(gi, gj, seed + 74u) * 360f, 0.85f + 0.3f * WorldNoise.Hash01(gi, gj, seed + 75u), e, lng ? -0.25f : -0.22f);
                o.Add(inst);
            });

            // ---- moss patches on the forest floor
            Grid(c, 5.8f, seed + 81u, list, (cc, gi, gj, x, z, o) =>
            {
                if (!Fetch(cc, x, z, out var e)) return;
                if (e.water || e.roadEdge < 2f || e.pgSdf < 3f) return;
                float p = 0.10f * WorldNoise.Smooth(0.25f, 0.6f, e.wet) * e.wGrass * (1f - WorldNoise.Smooth(14f, 26f, e.slope)) * (1f - e.wBog);
                if (WorldNoise.Hash01(gi, gj, seed + 82u) > p) return;
                o.Add(Make(Moss, x, z, WorldNoise.Hash01(gi, gj, seed + 83u) * 360f, 0.7f + 0.8f * WorldNoise.Hash01(gi, gj, seed + 84u), e, 0.0f));
            });

            var set = new PropSet();
            set.Build(list, TypeIds, Solid, map.origin, map.WorldSize, 32f);
            StructurePlacer.Build(gw, set);
            return set;
        }
    }
}
