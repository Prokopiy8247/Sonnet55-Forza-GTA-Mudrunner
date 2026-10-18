using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Testing;
using MudRunner.Vehicles;
using MudRunner.WorldGen;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using Debug = UnityEngine.Debug;
using static MudRunner.WorldGen.PgLayout;

namespace MudRunner.Tests
{
    /// <summary>
    /// Tests of the procedural wilderness and proving ground (Docs/WORLD_SPEC.md): determinism, generation time, routes, spawn points,
    /// sites, hidden depth traps, fords, proving ground stations, props / structures, pre-carved ruts and the builders.
    /// The expensive full-world generation is done once (OneTimeSetUp); determinism / timing generate a second copy.
    /// </summary>
    public class WorldTests
    {
        static GeneratedWorld full;          // wilderness + proving ground strip (2049^2, props)
        static GeneratedWorld pg;            // proving ground only (cropped map)
        static double fullMs, memMb, peakMb;

        [OneTimeSetUp]
        public void Generate()
        {
            if (full != null) return;
            long before = GC.GetTotalMemory(true);
            var sw = Stopwatch.StartNew();
            full = WorldGenerator.Generate(new WorldGenConfig { full = true });
            fullMs = sw.Elapsed.TotalMilliseconds;
            long after = GC.GetTotalMemory(false);
            peakMb = (after - before) / (1024.0 * 1024.0);          // includes garbage not collected yet (rasters) = peak proxy
            long kept = GC.GetTotalMemory(true);
            memMb = (kept - before) / (1024.0 * 1024.0);
            pg = WorldGenerator.Generate(new WorldGenConfig { full = false });
            var t = new System.Text.StringBuilder("[MudRunner] WORLD gen " + fullMs.ToString("F0") + " ms, managed memory retained +" + memMb.ToString("F0") + " MB / peak +" + peakMb.ToString("F0") + " MB; stages:");
            foreach (var kv in full.timings) t.Append(' ').Append(kv.Key).Append('=').Append(kv.Value.ToString("F0"));
            Debug.Log(t.ToString());
            Debug.Log("[MudRunner] WORLD pg-only gen " + pg.timings["TOTAL"].ToString("F0") + " ms, map " + pg.map.size + "^2");
            foreach (var tr in full.tracks.tracks)
                Debug.Log("[MudRunner] ROUTE " + RouteStats.Compute(tr.name, full.sites.polylines[tr.name], full.map));
        }

        static void InRange(float v, float lo, float hi, string msg = "") { Assert.That(v, Is.InRange(lo, hi), msg + " (value " + v.ToString("F2") + ")"); }

        // ================================================================== determinism / budget

        [Test]
        public void Generation_IsDeterministic_AndFast()
        {
            var sw = Stopwatch.StartNew();
            var again = WorldGenerator.Generate(new WorldGenConfig { full = true });
            double ms = sw.Elapsed.TotalMilliseconds;
            ulong a = WorldHash.Compute(full), b = WorldHash.Compute(again);
            Debug.Log("[MudRunner] WORLD determinism: hash " + a.ToString("X16") + " vs " + b.ToString("X16") + ", second generation " + ms.ToString("F0") + " ms");
            Assert.AreEqual(a, b, "same seed -> same world");
            Assert.Less(ms, 8000.0, "generation (terrain, water, roads, props, structures) under 8 s");
            Assert.Less(fullMs, 8000.0, "first generation under 8 s");
            var other = WorldGenerator.Generate(new WorldGenConfig { full = false, seed = 99u });
            Assert.AreNotEqual(WorldHash.Compute(pg), WorldHash.Compute(other), "different seed -> different terrain");
        }

        [Test]
        public void Generation_MemoryBudget()
        {
            Debug.Log("[MudRunner] WORLD managed memory: retained +" + memMb.ToString("F0") + " MB, peak (incl. uncollected temporaries) +" + peakMb.ToString("F0") + " MB");
            Assert.Less(memMb, 400.0, "retained memory < 400 MB");
            Assert.Less(peakMb, 450.0, "peak memory");
        }

        [Test]
        public void Map_HasSpecGeometry()
        {
            var m = full.map;
            Assert.AreEqual(2049, m.size); Assert.AreEqual(1f, m.cell, 1e-6f);
            Assert.AreEqual(-1024f, m.origin.x, 1e-3f); Assert.AreEqual(-1024f, m.origin.y, 1e-3f);
            Assert.IsNotNull(m.water, "water map");
            Assert.AreEqual(m.size, m.water.size);
            // mountain ring: steep and high
            int steep = 0, n = 0; float maxRing = 0f;
            for (float x = -1000f; x <= 1000f; x += 20f)
                for (float z = -1000f; z <= 1000f; z += 20f)
                {
                    float d = Mathf.Max(Mathf.Abs(x), Mathf.Abs(z)) - 768f;
                    if (d < 15f || d > 80f) continue;
                    if (x > 790f && Mathf.Abs(z) < 320f) continue;      // proving ground valley
                    n++;
                    if (m.SampleSlopeDegrees(x, z) >= 30f) steep++;
                    maxRing = Mathf.Max(maxRing, m.SampleHeight(x, z));
                }
            float frac = steep / (float)Mathf.Max(1, n);
            Debug.Log("[MudRunner] WORLD ring: steep(>=30deg) fraction " + frac.ToString("F2") + ", max height " + maxRing.ToString("F0"));
            Assert.Greater(frac, 0.6f, "outer ring is mostly steep");
            Assert.Greater(maxRing, 70f, "mountains rise well above the playable area");
        }

        // ================================================================== routes

        static List<Vector3> Route(int id) { return new List<Vector3>(full.sites.Route(id).points); }

        [Test]
        public void Routes_ExistWithIncreasingLength()
        {
            Assert.AreEqual(3, full.sites.routes.Count);
            float l1 = full.sites.Route(1).length, l2 = full.sites.Route(2).length, l3 = full.sites.Route(3).length;
            Debug.Log("[MudRunner] WORLD route lengths: north " + l1.ToString("F0") + " m, central " + l2.ToString("F0") + " m, swamp " + l3.ToString("F0") + " m");
            Assert.Greater(l1, l2 + 200f, "north road is the long way");
            Assert.Greater(l2, l3 + 150f, "central track is the medium way");
            InRange(l1, 2400f, 3400f); InRange(l2, 1900f, 2700f); InRange(l3, 1550f, 2200f);
            var bc = full.sites.Get("BaseCamp").position; var cab = full.sites.Get("Cabin").position;
            foreach (var r in full.sites.routes)
            {
                Assert.Less(Vector2.Distance(new Vector2(r.points[0].x, r.points[0].z), new Vector2(bc.x, bc.z)), 45f, r.name + " starts at the base camp");
                var e = r.points[r.points.Length - 1];
                Assert.Less(Vector2.Distance(new Vector2(e.x, e.z), new Vector2(cab.x, cab.z)), 45f, r.name + " ends at the cabin island");
            }
        }

        static bool CellPassable(GroundMap m, float x, float z, bool bridgeOk, float maxWater, float maxExtra, bool allowBog)
        {
            if (!m.Contains(x, z)) return false;
            float g = m.SampleHeight(x, z);
            if (!bridgeOk && m.SampleSlopeDegrees(x, z) > 32f) return false;      // decks (and their ramps) do not care about the ground under them
            float wd = m.water != null ? m.water.Depth(x, z, g) : 0f;
            if (wd > maxWater && !bridgeOk) return false;
            if (m.SampleExtraDepth(x, z) > maxExtra && !bridgeOk) return false;
            if (!allowBog && !bridgeOk && m.DominantType(x, z) == SurfaceType.Bog) return false;
            return true;
        }

        static bool DeckNear(Track t, int i, float dist)
        {
            for (int k = i; k >= 0 && t.s[i] - t.s[k] <= dist; k--) if (t.kind[k] == (byte)TKind.Causeway || t.kind[k] == (byte)TKind.Bridge) return true;
            for (int k = i; k < t.n && t.s[k] - t.s[i] <= dist; k++) if (t.kind[k] == (byte)TKind.Causeway || t.kind[k] == (byte)TKind.Bridge) return true;
            return false;
        }

        [Test]
        public void Route1_NorthRoad_IsPassableEverywhere()
        {
            var t = full.tracks.Find("north");
            int bad = 0; string first = "";
            for (int i = 0; i < t.n; i++)
            {
                bool deck = DeckNear(t, i, 4f);       // the first metres before a deck are its ramp: ground there is the cut/fill lip, the vehicle drives on the deck
                if (!CellPassable(full.map, t.x[i], t.z[i], deck, 0.5f, 0.6f, false)) { bad++; if (first.Length == 0) first = "(" + t.x[i].ToString("F0") + "," + t.z[i].ToString("F0") + ")"; }
            }
            Assert.AreEqual(0, bad, "north road has impassable samples, first at " + first);
            var st = RouteStats.Compute("north", full.sites.Route(1).points, full.map);
            Debug.Log("[MudRunner] WORLD " + st);
            Assert.Less(st.maxSlopeDeg, 17f, "north road is gentle");
            float maxExtraOffDeck = 0f;      // the bog under the causeway deck is a trap only for those who leave the deck
            for (int i = 0; i < t.n; i++)
                if (t.kind[i] != (byte)TKind.Causeway && t.kind[i] != (byte)TKind.Bridge) maxExtraOffDeck = Mathf.Max(maxExtraOffDeck, full.map.SampleExtraDepth(t.x[i], t.z[i]));
            Assert.Less(maxExtraOffDeck, 0.6f, "no deep hidden traps on the safe road");
            Assert.Greater(st.surfaceLength[(int)SurfaceType.Gravel] + st.surfaceLength[(int)SurfaceType.FirmSoil], st.length * 0.6f, "mostly firm");
            Assert.Greater(st.surfaceLength[(int)SurfaceType.ShallowMud], 60f, "with a few muddy stretches");
        }

        [Test]
        public void Route1_ConnectsBaseCampToCabin_OnPassableCells()
        {
            // flood fill over passable cells in a 7 m corridor around the north route polyline
            var m = full.map; var t = full.tracks.Find("north");
            int n = m.size;
            var allowed = new bool[n * n];
            int R = 7;
            for (int i = 0; i < t.n; i++)
            {
                int cx = Mathf.RoundToInt(t.x[i] - m.origin.x), cz = Mathf.RoundToInt(t.z[i] - m.origin.y);
                bool deck = t.kind[i] == (byte)TKind.Causeway || t.kind[i] == (byte)TKind.Bridge;
                for (int dz = -R; dz <= R; dz++)
                    for (int dx = -R; dx <= R; dx++)
                    {
                        if (dx * dx + dz * dz > R * R) continue;
                        int ix = cx + dx, iz = cz + dz;
                        if (ix < 0 || iz < 0 || ix >= n || iz >= n) continue;
                        if (deck ? (Mathf.Abs(dx) + Mathf.Abs(dz) <= 2) : CellPassable(m, m.origin.x + ix, m.origin.y + iz, false, 0.5f, 0.6f, false)) allowed[iz * n + ix] = true;
                    }
            }
            int sx = Mathf.RoundToInt(t.x[0] - m.origin.x), sz = Mathf.RoundToInt(t.z[0] - m.origin.y);
            int ex = Mathf.RoundToInt(t.x[t.n - 1] - m.origin.x), ez = Mathf.RoundToInt(t.z[t.n - 1] - m.origin.y);
            Assert.IsTrue(allowed[sz * n + sx], "start cell passable"); Assert.IsTrue(allowed[ez * n + ex], "goal cell passable");
            var seen = new bool[n * n]; var q = new Queue<int>(); q.Enqueue(sz * n + sx); seen[sz * n + sx] = true;
            bool reached = false;
            while (q.Count > 0 && !reached)
            {
                int c = q.Dequeue(); int cx = c % n, cz = c / n;
                if (Mathf.Abs(cx - ex) <= 3 && Mathf.Abs(cz - ez) <= 3) { reached = true; break; }
                for (int k = 0; k < 4; k++)
                {
                    int nx = cx + (k == 0 ? 1 : k == 1 ? -1 : 0), nz = cz + (k == 2 ? 1 : k == 3 ? -1 : 0);
                    if (nx < 0 || nz < 0 || nx >= n || nz >= n) continue;
                    int ni = nz * n + nx;
                    if (seen[ni] || !allowed[ni]) continue;
                    seen[ni] = true; q.Enqueue(ni);
                }
            }
            Assert.IsTrue(reached, "a path of passable cells connects the base camp and the cabin along route 1");
        }

        [Test]
        public void Route2_Central_HasFordSteepClimbAndMud()
        {
            var st = RouteStats.Compute("central", full.sites.Route(2).points, full.map);
            Debug.Log("[MudRunner] WORLD " + st);
            InRange(st.maxWaterDepth, 0.6f, 1.0f, "ford F1 depth 0.7-0.9 m");
            Assert.Greater(st.maxSlopeDeg, 16f, "a steep short climb");
            Assert.Greater(st.steepLength15, 12f);
            Assert.Greater(st.surfaceLength[(int)SurfaceType.ShallowMud] + st.surfaceLength[(int)SurfaceType.DeepMud], 150f, "shallow and deep mud sections");
            Assert.Greater(st.surfaceLength[(int)SurfaceType.DeepMud], 20f, "deep mud");
            var f1 = full.sites.fords.Find(f => f.name.StartsWith("central"));
            Assert.AreEqual("central ford", f1.name);
            InRange(f1.current, 0.8f, 1.7f, "current about 1 m/s");
        }

        [Test]
        public void Route3_Swamp_HasWidowmakerDeepCrossingAndBog()
        {
            var st = RouteStats.Compute("swamp", full.sites.Route(3).points, full.map);
            Debug.Log("[MudRunner] WORLD " + st);
            Assert.GreaterOrEqual(st.maxSlopeDeg, 18f, "Widowmaker climb >= 18 deg"); Assert.LessOrEqual(st.maxSlopeDeg, 28f);
            Assert.Greater(st.steepLength22, 15f, "stretch of 22+ degrees");
            Assert.Greater(st.maxWaterDepth, 1.0f, "river deep crossing deeper than the utility truck can ford");
            Assert.Greater(st.maxExtra, 1.0f, "hidden depth around the cabin island");
            Assert.Greater(st.surfaceLength[(int)SurfaceType.Bog] + st.surfaceLength[(int)SurfaceType.DeepMud], 120f, "~200 m of bog / deep mud");
            // winch anchors along the route (every 40-80 m)
            int windows = 0, covered = 0;
            var pts = full.sites.Route(3).points;
            float acc = 0f, next = 40f;
            for (int i = 1; i < pts.Length; i++)
            {
                acc += Vector2.Distance(new Vector2(pts[i].x, pts[i].z), new Vector2(pts[i - 1].x, pts[i - 1].z));
                if (acc < next) continue;
                next += 100f;
                windows++;
                foreach (var a in full.sites.anchors) if (Vector2.Distance(new Vector2(a.position.x, a.position.z), new Vector2(pts[i].x, pts[i].z)) < 70f) { covered++; break; }
            }
            Debug.Log("[MudRunner] WORLD swamp route anchor coverage " + covered + "/" + windows);
            Assert.GreaterOrEqual(covered, (int)(windows * 0.8f), "anchors along the swamp route");
        }

        [Test]
        public void Routes_StayInsidePlayableArea()
        {
            foreach (var kv in full.sites.polylines)
                foreach (var p in kv.Value)
                    Assert.IsTrue(full.sites.InsidePlayable(p), kv.Key + " leaves the playable area at " + p);
        }

        // ================================================================== sites, spawn points

        [Test]
        public void ObjectiveSites_Resolve()
        {
            foreach (var n in new[] { "BaseCamp", "LoggingLanding", "Cabin" })
            {
                Assert.IsTrue(full.sites.Resolve(n, out var p, out var r), n);
                Assert.IsTrue(full.sites.InsidePlayable(p)); Assert.Greater(r, 5f);
            }
            Assert.IsTrue(full.sites.Resolve("Base camp", out var bc, out _), "names are matched ignoring case and spaces");
            // proving ground goals: end of the lane, plateau of the hill, far bank of the ford
            Assert.IsTrue(pg.sites.Resolve("Mud pits", out var pits, out _)); Assert.Greater(pits.z, PitZ0(PitCount - 1) + PitLen);
            Assert.IsTrue(pg.sites.Resolve("Mud hill", out var hill, out _)); Assert.Greater(hill.y - pg.map.SampleHeight(HillX, HillZ0 - 6f), HillHeight - 1f);
            Assert.IsTrue(pg.sites.Resolve("Ford", out var ford, out _)); Assert.Greater(ford.z, FordZ1);
            Assert.IsTrue(pg.sites.Resolve("Proving ground start", out _, out _));
            Assert.IsFalse(pg.sites.Resolve("Nowhere", out _, out _));
        }

        [Test]
        public void Sites_InsideBounds()
        {
            foreach (var kv in full.sites.sites)
            {
                var p = kv.Value.position;
                Assert.IsTrue(full.sites.InsidePlayable(p), kv.Key + " out of bounds " + p);
                Assert.IsTrue(full.map.Contains(p.x, p.z));
            }
            foreach (var n in new[] { "BaseCamp", "Garage", "FuelStation", "Cabin", "LoggingLanding", "Watchtower", "PumpStation", "Sawmill", "RadioMast" })
                Assert.IsTrue(full.sites.Has(n), "site " + n);
            Assert.IsTrue(full.sites.cargoSpawns.Count >= 3 && full.sites.trailerSpawns.Count >= 1);
            foreach (var s in full.sites.cargoSpawns) Assert.IsTrue(full.sites.InsidePlayable(s.position));
            // Wilderness / Cabin heights: cabin island above the swamp
            Assert.Greater(full.sites.Get("Cabin").position.y, 4.5f);
        }

        static void AssertSpawnOk(GeneratedWorld gw, WorldData w)
        {
            foreach (var p in w.points)
            {
                Assert.IsTrue(gw.map.Contains(p.position.x, p.position.z), p.name + " inside the map");
                float g = gw.map.SampleHeight(p.position.x, p.position.z);
                Assert.GreaterOrEqual(p.position.y, g - 0.02f, p.name + " not below the ground");
                Assert.LessOrEqual(p.position.y, g + 3f, p.name + " not floating");
                float wd = gw.map.water.Depth(p.position.x, p.position.z, g);
                Assert.Less(wd, 0.15f, p.name + " is on dry land (water depth " + wd.ToString("F2") + ")");
                var dom = gw.map.DominantType(p.position.x, p.position.z);
                Assert.AreNotEqual(SurfaceType.Bog, dom, p.name + " not on bog");
                Assert.Less(gw.map.SampleExtraDepth(p.position.x, p.position.z), 0.35f, p.name + " not on a hidden-depth patch");
            }
            Assert.IsTrue(gw.map.Contains(w.playerStart.x, w.playerStart.z));
            Assert.Less(gw.map.water.Depth(w.playerStart.x, w.playerStart.z, gw.map.SampleHeight(w.playerStart.x, w.playerStart.z)), 0.05f);
        }

        [Test]
        public void SpawnPoints_OnDryLandAboveGround()
        {
            WorldRegistration.EnsureRegistered();
            var data = WorldInstantiator.Instantiate(full, WorldKind.Wilderness, visuals: false);
            try
            {
                AssertSpawnOk(full, data);
                foreach (var name in new[] { "Base camp", "Cabin", "Ford F1", "Logging landing", "Proving ground gate" })
                    Assert.IsTrue(data.points.Exists(p => p.name == name), "teleport point " + name);
                Assert.IsNotNull(data.root);
                Assert.IsNotNull(WorldSites.Current);
                StringAssert.StartsWith("World_", data.root.name);
            }
            finally { UnityEngine.Object.DestroyImmediate(data.root); }
        }

        // ================================================================== hidden depth, fords, water

        [Test]
        public void HiddenDepthTraps_LookInnocent()
        {
            int real = 0;
            foreach (var t in full.sites.traps)
            {
                float ex = full.map.SampleExtraDepth(t.position.x, t.position.z);
                var dom = full.map.DominantType(t.position.x, t.position.z);
                if (t.decoy) { Assert.Less(ex, 0.05f, t.name + " decoy has no depth"); continue; }
                real++;
                Assert.GreaterOrEqual(ex, t.depth * 0.8f, t.name + " has its hidden depth");
                Assert.IsTrue(dom == SurfaceType.Grass || dom == SurfaceType.ShallowMud || dom == SurfaceType.FirmSoil || dom == SurfaceType.Bog, t.name + " looks like " + dom);
                if (t.depth <= 1.0f) Assert.AreNotEqual(SurfaceType.DeepMud, dom, t.name + " must not look like deep mud");
            }
            Assert.GreaterOrEqual(real, 8, "hidden traps exist");
            // grassy traps are wet (darker) so the careful player can read them
            foreach (var t in full.sites.traps) if (!t.decoy) Assert.Greater(full.map.SampleBaseWetness(t.position.x, t.position.z), 0.6f);
        }

        [Test]
        public void Fords_AndWater_InSpec()
        {
            var ws = full.sites;
            Debug.Log("[MudRunner] WORLD fords: " + string.Join(" | ", ws.fords.ConvertAll(f => f.name + " depth " + f.depth.ToString("F2") + " len " + f.length.ToString("F0") + " cur " + f.current.ToString("F2"))));
            var f1 = ws.fords.Find(f => f.name == "central ford");
            var f2 = ws.fords.Find(f => f.name == "mid_link ford");
            var deep = ws.fords.FindAll(f => f.name == "swamp ford");
            InRange(f1.depth, 0.6f, 1.0f); InRange(f2.depth, 0.5f, 1.0f);
            Assert.GreaterOrEqual(deep.Count, 2);
            float dmax = 0f; foreach (var d in deep) dmax = Mathf.Max(dmax, d.depth);
            InRange(dmax, 1.0f, 1.3f, "deep crossing 1.0-1.3 m (hauler only)");
            // river: banks above the water, deep sections deeper than 1.8 m somewhere
            var w = full.map.water;
            float maxDepth = 0f; int wetCells = 0;
            for (int i = 0; i < w.level.Length; i += 3)
            {
                if (float.IsNegativeInfinity(w.level[i])) continue;
                wetCells++;
                float d = w.level[i] - full.map.height[i];
                if (d > maxDepth) maxDepth = d;
            }
            Debug.Log("[MudRunner] WORLD water: max depth " + maxDepth.ToString("F2") + " m, wet cells (1/3 sample) " + wetCells);
            Assert.Greater(maxDepth, 1.8f, "river deeper than 1.8 m (impassable) somewhere");
            Assert.Greater(wetCells, 15000, "rivers, ponds and swamp pools exist");
            // current speeds along the main river within 0.8..1.6 m/s in the middle of deep reaches
            int ok = 0, total = 0;
            var river = full.rivers[0];
            for (int i = 20; i < river.n - 20; i += 8)
            {
                float x = river.x[i], z = river.z[i];
                if (!w.Sample(x, z, out _, out var fl)) continue;
                total++; if (fl.magnitude >= 0.7f && fl.magnitude <= 1.8f) ok++;
            }
            Assert.Greater(ok, total * 0.8f, "flow 0.8-1.6 m/s along the river centre");
            // the river flows toward +x on average
            Vector2 sum = Vector2.zero;
            for (int i = 20; i < river.n - 20; i += 8) if (w.Sample(river.x[i], river.z[i], out _, out var fl)) sum += fl;
            Assert.Greater(sum.x, 0f, "river flows toward +x");
        }

        // ================================================================== proving ground

        [Test]
        public void ProvingGround_MudPits_AreStaged()
        {
            var m = pg.map;
            float floor = m.SampleHeight(SpineX + 8f, PitZ0(0) - 12f);
            for (int k = 0; k < PitCount; k++)
            {
                float zc = PitZ0(k) + PitLen * 0.5f;
                var dom = m.DominantType(SpineX, zc);
                Assert.AreEqual(PitSurface[k], dom, "pit " + (k + 1) + " surface");
                Assert.AreEqual(PitExtra[k], m.SampleExtraDepth(SpineX, zc), 0.06f, "pit " + (k + 1) + " hidden depth");
                float dish = m.SampleHeight(SpineX + 11f, zc) - m.SampleHeight(SpineX, zc);
                Assert.Greater(dish, 0.2f, "pit " + (k + 1) + " is dished");
                if (k < PitCount - 1)
                {
                    float zg = PitZ0(k) + PitLen + PitGap * 0.5f;
                    Assert.AreEqual(SurfaceType.Gravel, m.DominantType(SpineX, zg), "causeway after pit " + (k + 1) + " is firm");
                    Assert.AreEqual(floor, m.SampleHeight(SpineX, zg), 0.15f, "causeway at floor level");
                }
                Assert.AreEqual(PitLen, 18f); Assert.AreEqual(12f, PitHalfW * 2f);
            }
            Assert.AreEqual(8f, PitGap);
        }

        [Test]
        public void ProvingGround_SteepMudHill_HasThreeSteps()
        {
            var m = pg.map;
            float[] expect = { 12f, 20f, 28f };
            for (int s = 0; s < 3; s++)
            {
                float za = HillZ(s) + 3f, zb = HillZ(s + 1) - 3f;
                float ha = m.SampleHeight(HillX, za), hb = m.SampleHeight(HillX, zb);
                float deg = Mathf.Atan2(hb - ha, zb - za) * Mathf.Rad2Deg;
                Debug.Log("[MudRunner] WORLD hill step " + (s + 1) + ": " + deg.ToString("F1") + " deg (target " + expect[s] + ")");
                Assert.AreEqual(expect[s], deg, 1.6f, "step " + (s + 1));
                Assert.AreEqual(SurfaceType.ShallowMud, m.DominantType(HillX, (za + zb) * 0.5f), "wet mud surface on step " + (s + 1));
                Assert.Greater(m.SampleBaseWetness(HillX, (za + zb) * 0.5f), 0.8f);
            }
            float top = m.SampleHeight(HillX, HillZ(4) - 5f), bottom = m.SampleHeight(HillX, HillZ0 - 6f);
            Assert.AreEqual(HillHeight, top - bottom, 0.8f, "70 m climb rises ~24 m");
            float ztot = 0f; for (int i = 0; i < 3; i++) ztot += StepLen[i]; Assert.AreEqual(70f, ztot);
            // firm return slope
            float zr = (HillZ(4) + HillZ(5)) * 0.5f;
            Assert.AreNotEqual(SurfaceType.ShallowMud, m.DominantType(HillX, zr), "return slope is not mud");
            Assert.AreEqual(ReturnDeg, Mathf.Atan2(m.SampleHeight(HillX, zr - 5f) - m.SampleHeight(HillX, zr + 5f), 10f) * Mathf.Rad2Deg, 1.6f);
            // winch anchor trees at the top
            int near = 0;
            foreach (var a in pg.sites.anchors) if (Vector2.Distance(new Vector2(a.position.x, a.position.z), new Vector2(HillX, HillZ(4) - 10f)) < 25f) near++;
            Assert.GreaterOrEqual(near, 4, "anchors at the top of the hill");
        }

        [Test]
        public void ProvingGround_SideSlope_Articulation_Ford_Pad()
        {
            var m = pg.map;
            // side slope: 40 m, 14-18 deg sideways, mud
            for (float x = SideX0 + 6f; x <= SideX1 - 6f; x += 8f)
            {
                float tilt = Mathf.Atan2(m.SampleHeight(x, SideZ + 4f) - m.SampleHeight(x, SideZ - 4f), 8f) * Mathf.Rad2Deg;
                InRange(tilt, 12.5f, 19.5f, "cross slope at x=" + x);
                Assert.IsTrue(m.DominantType(x, SideZ) == SurfaceType.ShallowMud, "side slope is mud");
            }
            Assert.AreEqual(40f, SideX1 - SideX0);
            // articulation course: 9 boulders + 9 holes, 0.4 m deep, 45 m
            int boulders = 0, holes = 0;
            foreach (var s in pg.props.structures) if (s.tag == "artboulder") boulders++;
            for (int i = 0; i < ArtStations; i++)
            {
                ArtItems(i, out _, out Vector2 hole);
                float depth = m.SampleHeight(SpineX + (hole.x > SpineX ? 3.2f : -3.2f), hole.y) - m.SampleHeight(hole.x, hole.y);
                if (depth > 0.3f) holes++;
            }
            Assert.AreEqual(ArtStations, boulders); Assert.AreEqual(ArtStations, holes, "every station has a 0.4 m deep hole");
            Assert.AreEqual(45f, ArtZ1 - ArtZ0);
            // ford: 36 m, profile 0.4 -> 0.8 -> 1.2 -> 1.6 -> back, current 1.5 m/s
            var w = m.water;
            Assert.AreEqual(36f, FordZ1 - FordZ0);
            float[] zs = { FordZ0 + 1.5f, FordZ0 + 8f, FordZ0 + 14f, (FordZ0 + FordZ1) * 0.5f, FordZ1 - 14f, FordZ1 - 8f, FordZ1 - 1.5f };
            float prev = -1f; float maxD = 0f;
            var depths = new List<float>();
            foreach (float z in zs)
            {
                float d = w.Depth(SpineX, z, m.SampleHeight(SpineX, z));
                depths.Add(d); maxD = Mathf.Max(maxD, d);
            }
            Debug.Log("[MudRunner] WORLD PG ford depths: " + string.Join(", ", depths.ConvertAll(d => d.ToString("F2"))));
            InRange(maxD, 1.5f, 1.75f, "deepest point 1.6 m");
            Assert.Less(depths[0], 0.6f); Assert.Greater(depths[1], depths[0]); Assert.Greater(depths[2], depths[1]); Assert.Greater(depths[3], depths[2]);
            Assert.Greater(depths[3], depths[4]); Assert.Greater(depths[4], depths[5]); Assert.Greater(depths[5], depths[6]);
            Assert.IsTrue(w.Sample(SpineX, (FordZ0 + FordZ1) * 0.5f, out float lvl, out Vector2 fl));
            Assert.AreEqual(FordCurrent, fl.magnitude, 0.2f, "current 1.5 m/s");
            Assert.AreEqual(FordWl, lvl, 0.01f, "constant water surface");
            // bypass bridge
            Assert.IsTrue(pg.sites.bridges.Exists(b => b.name == "PG ford bridge"));
            // measuring pad flat, cones, log pile, stumps, sandbox
            float h0 = m.SampleHeight(MeasCenter.x, MeasCenter.y);
            for (float x = MeasX0 + 3f; x < MeasX1; x += 10f) for (float z = MeasZ0 + 3f; z < MeasZ1; z += 10f) Assert.AreEqual(h0, m.SampleHeight(x, z), 0.1f, "measuring pad is flat");
            int cones = 0, logs = 0, stumps = 0, trees = 0;
            foreach (var s in pg.props.structures)
            {
                if (s.id == "cone") cones++;
                if (s.id == "log_long" && s.dynamic && Vector2.Distance(new Vector2(s.pos.x, s.pos.z), LogPile) < 6f) logs++;
                if (s.tag == "pgstump") stumps++;
                if (s.tag == "anchor:tree" && Vector2.Distance(new Vector2(s.pos.x, s.pos.z), LogPile) < 40f) trees++;
            }
            Assert.AreEqual(25, cones); Assert.AreEqual(20, logs, "20 dynamic logs"); Assert.AreEqual(6, stumps); Assert.GreaterOrEqual(trees, 4);
            Assert.AreEqual(SurfaceType.Sand, m.DominantType((SandX0 + SandX1) * 0.5f, (SandZ0 + SandZ1) * 0.5f));
            // straight with distance poles every 10 m
            int poles = 0; foreach (var s in pg.props.structures) if (s.tag == "distancepole") poles++;
            Assert.AreEqual(11, poles);
            Assert.AreEqual(100f, StraightZ1 - StraightZ0);
            foreach (var f in new[] { "PGStart", "PGMudPits", "PGMudHill", "PGSideSlope", "PGArticulation", "PGFord", "PGLogPile", "PGMeasuring" }) Assert.IsTrue(pg.sites.Has(f), f);
            Assert.GreaterOrEqual(pg.sites.provingGroundFeatures.Count, 9);
        }

        [Test]
        public void ProvingGround_IsInsideStripAndConnectedToWilderness()
        {
            // the same features exist in the shared map, and the service road reaches the proving ground across the ridge
            var m = full.map;
            Assert.AreEqual(pg.map.SampleHeight(SpineX, -100f), m.SampleHeight(SpineX, -100f), 0.05f, "same terrain in both maps");
            Assert.AreEqual(PgLayout.PitSurface[2], m.DominantType(SpineX, PitZ0(2) + 9f));
            var svc = full.tracks.Find("service");
            Assert.IsNotNull(svc);
            var end = svc.Point(svc.n - 1);
            Assert.Greater(end.x, 805f); Assert.Less(end.x, 830f);
            Assert.Less(Mathf.Abs(end.y - Floor), 3f, "service road meets the valley floor");
            var st = RouteStats.Compute("service", full.sites.polylines["service"], m);
            Debug.Log("[MudRunner] WORLD " + st);
            Assert.Less(st.maxSlopeDeg, 20f, "service road drivable up to the pass");
            Assert.IsTrue(full.sites.fords.Exists(f => f.name == "pg_ford ford"));
            Assert.IsTrue(full.sites.polylines.ContainsKey("ProvingGroundLoop"));
            float loopLen = WorldSites.PolylineLength(full.sites.polylines["ProvingGroundLoop"]);
            Debug.Log("[MudRunner] WORLD proving ground loop length " + loopLen.ToString("F0") + " m");
            InRange(loopLen, 450f, 1300f);
        }

        // ================================================================== props / structures

        [Test]
        public void Props_Placed_AwayFromRoadsAndWater()
        {
            var set = full.props; var m = full.map;
            var cnt = set.CountPerType();
            Debug.Log("[MudRunner] WORLD props: " + string.Join(", ", System.Linq.Enumerable.Select(System.Linq.Enumerable.Range(0, cnt.Length), i => set.typeIds[i] + "=" + cnt[i])) + " total " + set.Count + ", structures " + set.structures.Count);
            Assert.Greater(set.Count, 60000, "dense forest");
            int inWater = 0, onRoad = 0, treesChecked = 0;
            var wtmp = new float[8];
            for (int i = 0; i < set.insts.Length; i += 3)
            {
                var p = set.insts[i];
                if (m.water.Depth(p.x, p.z, m.SampleHeight(p.x, p.z)) > 0.2f) inWater++;
                if (p.type <= PropPlacement.Birch)
                {
                    treesChecked++;
                    m.SampleWeights(p.x, p.z, wtmp);
                    if (wtmp[(int)SurfaceType.Gravel] > 0.6f) onRoad++;
                }
            }
            Assert.AreEqual(0, inWater, "no props in the water");
            Assert.Less(onRoad, Mathf.Max(5, treesChecked / 500), "(almost) no trees on gravel");
            Assert.Greater(cnt[PropPlacement.Reed], 1000, "reeds in the swamp");
            Assert.Greater(cnt[PropPlacement.Rock_M] + cnt[PropPlacement.Rock_L], 300, "boulders");
            Assert.Greater(cnt[PropPlacement.DeadTree], 100, "dead trees in the bog");
        }

        [Test]
        public void Structures_AnchorsBridgesAndBuildings()
        {
            var set = full.props;
            int anchors = 0; foreach (var s in set.structures) if (s.anchor) anchors++;
            Assert.GreaterOrEqual(anchors, 80, "winch anchors");
            Assert.AreEqual(anchors, full.sites.anchors.Count, "anchor list matches");
            bool garage = false, cabin = false, tower = false, fuel = false, broken = false;
            foreach (var s in set.structures)
            {
                if (s.tag == "garage") garage = true; if (s.tag == "cabin") cabin = true; if (s.tag == "watchtower") tower = true; if (s.tag == "fuel") fuel = true;
                if (s.id.StartsWith("bridge_broken")) broken = true;
            }
            Assert.IsTrue(garage && cabin && tower && fuel && broken, "garage, fuel station, cabin, watchtower, broken bridge");
            Assert.GreaterOrEqual(full.sites.bridges.Count, 5);
            var b1 = full.sites.bridges.Find(b => b.name == "Old bridge B1");
            Assert.Greater(b1.length, 14f); Assert.IsTrue(b1.fragile); Assert.Less(b1.maxLoadKg, 4000f);
            Assert.Greater(full.sites.garageZones.Count, 0);
            Assert.GreaterOrEqual(full.sites.cargoSpawns.Count, 3);
        }

        [Test]
        public void PropLibrary_ProvidesAllSpecIds()
        {
            string[] ids = { "spruce_a", "spruce_b", "spruce_c", "birch", "deadtree", "rock_s", "rock_m", "rock_l", "rock_slab", "log_long", "log_short", "stump", "reed", "bush", "cabin", "garage", "fuel_station",
                             "watchtower", "bridge_intact", "bridge_broken", "sign_arrow", "sign_warn", "post_anchor", "barrel", "crate", "tent", "fence" };
            var lib = PropLibraries.Current;
            foreach (var id in ids)
            {
                var d = lib.Get(id);
                Assert.IsNotNull(d, id); Assert.IsNotNull(d.lods[0], id + " mesh"); Assert.Greater(d.lods[0].vertexCount, 8, id);
                Assert.IsNotNull(d.materials); Assert.GreaterOrEqual(d.materials.Length, d.lods[0].subMeshCount, id + " materials");
            }
            Assert.Greater(lib.Get("log_long").mass, 0f, "logs are dynamic");
            Assert.AreEqual(lib.Get("bridge_intact:24").bounds.size.z, 24f, 0.5f, "parametrised bridge length");
            Assert.Greater(lib.Get("garage").colliders.Length, 3, "buildings carry colliders");
        }

        // ================================================================== ruts (MudField.PrecarveTrack)

        [Test]
        public void PrecarveTrack_WritesRutsAndBerms_InAnyState()
        {
            var poly = new List<Vector2>();
            for (float x = -40f; x <= 40f; x += 2f) poly.Add(new Vector2(x, 5f + 0.1f * x));
            // before the window exists: goes to the sparse store
            var f1 = new MudField(0.25f);
            f1.PrecarveTrack(poly, 1.8f, 0.2f, 0.5f, 0.08f, 0.3f, 0.4f, 0f);
            Assert.Greater(f1.StoredTiles, 0, "ruts written into the tile store");
            f1.Recenter(new Vector3(0f, 0f, 5f), true);
            // rut centre lines are at +-0.9 m from the polyline
            Vector2 c = new Vector2(0f, 5f); Vector2 n = new Vector2(-0.1f, 1f).normalized;
            f1.Sample(c.x + n.x * 0.9f, c.y + n.y * 0.9f, out float dhL, out float churnL, out float compL);
            f1.Sample(c.x - n.x * 0.9f, c.y - n.y * 0.9f, out float dhR, out _, out _);
            f1.Sample(c.x, c.y, out float dhM, out _, out _);
            Debug.Log("[MudRunner] WORLD precarve: left " + dhL.ToString("F3") + " right " + dhR.ToString("F3") + " middle " + dhM.ToString("F3") + " churn " + churnL.ToString("F2"));
            Assert.Less(dhL, -0.12f); Assert.Less(dhR, -0.12f); Assert.Greater(dhM, dhL + 0.1f, "ridge between the ruts");
            Assert.Greater(churnL, 0.1f); Assert.Greater(compL, 0.1f);
            f1.Sample(c.x + n.x * 1.5f, c.y + n.y * 1.5f, out float dhB, out _, out _);
            Assert.Greater(dhB, 0.0f, "berm beside the rut");
            // after the window exists: written directly
            var f2 = new MudField(0.25f);
            f2.Recenter(new Vector3(0f, 0f, 5f), true);
            f2.PrecarveTrack(poly, 1.8f, 0.2f, 0.5f, 0.08f, 0.3f, 0.4f, 0f);
            f2.Sample(c.x + n.x * 0.9f, c.y + n.y * 0.9f, out float dh2, out _, out _);
            Assert.AreEqual(dhL, dh2, 0.02f, "same result before / after the window exists");
            // far away tiles (outside the 256 m window) end up in the store and are restored when the window moves there
            var far = new List<Vector2> { new Vector2(600f, 600f), new Vector2(640f, 600f), new Vector2(680f, 600f) };
            f2.PrecarveTrack(far, 1.8f, 0.2f);
            Assert.Greater(f2.StoredTiles, 0);
            f2.Recenter(new Vector3(640f, 0f, 600f), true);
            f2.Sample(640f, 600.9f, out float dhFar, out _, out _);
            Assert.Less(dhFar, -0.1f, "pre-carved ruts survive the window scrolling");
        }

        [Test]
        public void WorldRuts_ApplyToTheMudField()
        {
            var map = TestArena.Flat(SurfaceType.FirmSoil, 100f);
            var gs = TestArena.Install(map, Vector3.zero);
            try
            {
                int calls = WorldRuts.Apply(gs.Field, full);   // tracks lie far outside this little map: must not throw, only store
                Assert.Greater(calls, 20, "rut runs applied");
                var t = full.tracks.Find("central");
                int i = t.n / 2;
                for (int k = 0; k < t.n; k++) if (t.ruts[k] && t.carve[k]) { i = k; break; }
                gs.Field.Recenter(new Vector3(t.x[i], 0f, t.z[i]), true);
                float min = 0f;
                for (float dz = -4f; dz <= 4f; dz += 0.25f) for (float dx = -4f; dx <= 4f; dx += 0.25f) min = Mathf.Min(min, gs.Field.SampleDh(t.x[i] + dx, t.z[i] + dz));
                Assert.Less(min, -0.04f, "a rut exists along the central track");
            }
            finally { UnityEngine.Object.DestroyImmediate(gs.gameObject); }
        }

        // ================================================================== builders (GameObjects)

        [UnityTest]
        public IEnumerator Builders_AreRegistered_AndBuildBothWorlds()
        {
            WorldRegistration.EnsureRegistered();
            Assert.IsTrue(WorldBuilders.Registry.ContainsKey(WorldKind.Wilderness));
            Assert.IsTrue(WorldBuilders.Registry.ContainsKey(WorldKind.ProvingGround));
            var sw = Stopwatch.StartNew();
            var wp = WorldBuilders.Build(WorldKind.ProvingGround);
            double pgMs = sw.Elapsed.TotalMilliseconds;
            yield return null;
            try
            {
                Assert.AreEqual(WorldKind.ProvingGround, wp.kind);
                Assert.IsNotNull(wp.map.water);
                foreach (var name in new[] { "Proving ground start", "Mud pits", "Mud hill", "Side slope", "Articulation", "Ford", "Log pile" })
                    Assert.IsTrue(wp.points.Exists(p => p.name == name), "teleport point '" + name + "'");
                AssertSpawnOk(pg, wp);
                var h = wp.root.GetComponent<WorldHandle>();
                Assert.Greater(h.structureCount, 100, "structures instantiated");
                Assert.IsNotNull(h.groundCollider);
                int rb = wp.root.GetComponentsInChildren<Rigidbody>().Length;
                Assert.GreaterOrEqual(rb, 30, "dynamic logs / barrels / crates");
                int anchors = wp.root.GetComponentsInChildren<WinchAnchor>().Length;
                Assert.GreaterOrEqual(anchors, 12, "winch anchors in the proving ground");
                Debug.Log("[MudRunner] WORLD ProvingGround builder " + pgMs.ToString("F0") + " ms, structures " + h.structureCount + ", rigidbodies " + rb + ", anchors " + anchors);
                // ground height / collider agree
                Physics.SyncTransforms();
                float gy = wp.map.SampleHeight(SpineX, -170f);
                Assert.IsTrue(Physics.Raycast(new Vector3(SpineX, gy + 50f, -170f), Vector3.down, out var hit, 100f, 1 << GameLayers.Terrain), "terrain collider under the straight");
                Assert.AreEqual(gy, hit.point.y, 0.35f);
            }
            finally { UnityEngine.Object.Destroy(wp.root); wp.onTeardown?.Invoke(wp); }
            yield return null;

            sw.Restart();
            var ww = WorldBuilders.Build(WorldKind.Wilderness);
            double wMs = sw.Elapsed.TotalMilliseconds;
            yield return null;
            try
            {
                Assert.AreEqual(WorldKind.Wilderness, ww.kind);
                Assert.AreEqual(2049, ww.map.size);
                var h = ww.root.GetComponent<WorldHandle>();
                Assert.IsNotNull(h.sites); Assert.AreSame(h.sites, WorldSites.Current);
                Assert.IsTrue(ww.points.Exists(p => p.name == "Base camp"));
                Assert.Greater(h.waterQuads, 1000, "water surface mesh");
                Assert.IsNotNull(h.props); Assert.IsNotNull(h.colliders);
                AssertSpawnOk(h.world, ww);
                Debug.Log("[MudRunner] WORLD Wilderness builder total " + wMs.ToString("F0") + " ms (gen " + h.generateMs.ToString("F0") + " ms), structures " + h.structureCount + ", water quads " + h.waterQuads + ", props " + h.world.props.Count);
                Assert.Less(wMs, 12000.0, "whole build incl. collider, water mesh, structures");
                // collider pool follows the player position
                h.colliders.Refresh(ww.playerStart, true);
                Assert.Greater(h.colliders.ActiveCount, 20, "tree colliders near the base camp");
                Assert.LessOrEqual(h.colliders.ActiveCount, h.colliders.maxActive);
            }
            finally { UnityEngine.Object.Destroy(ww.root); ww.onTeardown?.Invoke(ww); }
            yield return null;
        }

        [UnityTest]
        public IEnumerator FragileBridge_CollapsesUnderOverload()
        {
            var go = new GameObject("TestBridge");
            go.transform.position = new Vector3(5000f, 0f, 5000f);
            var col = go.AddComponent<BoxCollider>(); col.size = new Vector3(4f, 0.3f, 20f);
            var fb = go.AddComponent<FragileBridge>(); fb.maxLoadKg = 3500f; fb.length = 20f; fb.width = 4f; fb.bridgeName = "test";
            yield return new WaitForFixedUpdate();
            Assert.IsFalse(fb.collapsed);
            // a heavy fake "vehicle" cannot be spawned without a ground; collapse directly and check the state change
            fb.Collapse();
            Assert.IsTrue(fb.collapsed); Assert.IsFalse(col.enabled);
            yield return new WaitForSeconds(0.2f);
            UnityEngine.Object.Destroy(go);
        }
    }
}
