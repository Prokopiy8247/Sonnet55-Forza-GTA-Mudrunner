using System;
using System.Collections.Generic;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Code-generated stand-in props (low poly, flat colours) behind <see cref="IPropLibrary"/>. Origin is at the base centre on the
    /// ground, front of buildings faces local +Z. Ids: see WORLD_SPEC section 4 plus a few extras (pump_house, radio_mast, sawmill,
    /// causeway, marker_post, depth_pole, distance_pole, cone, tank, woodpile, moss). Parametrised ids: "bridge_intact:24", "bridge_broken:14",
    /// "bridge_intact:22:old", "causeway:90", "marker_post:blue".
    /// </summary>
    public sealed class ProceduralPropLibrary : IPropLibrary
    {
        readonly Dictionary<string, PropDef> cache = new Dictionary<string, PropDef>();

        public PropDef Get(string id)
        {
            if (cache.TryGetValue(id, out var d) && d != null && d.lods[0] != null) return d;
            d = Build(id);
            cache[id] = d;
            return d;
        }

        // ------------------------------------------------------------------ helpers

        static PropDef Finish(string id, MeshBuilder lod0, MeshBuilder lod1, MeshBuilder lod2, string[] mats, ColRecipe[] cols, float mass = 0f,
                              float height = 1f, float lod0Dist = 60f, float lod1Dist = 160f, float maxDist = 520f, bool shadows = true)
        {
            var def = new PropDef { id = id, materials = PropMaterials.Get(mats), colliders = cols ?? new ColRecipe[0], mass = mass, height = height, castShadows = shadows,
                                    lod0Dist = lod0Dist, lod1Dist = lod1Dist, maxDist = maxDist };
            def.lods[0] = lod0.ToMesh(id + "_LOD0");
            def.lods[1] = lod1 != null ? lod1.ToMesh(id + "_LOD1") : def.lods[0];
            def.lods[2] = lod2 != null ? lod2.ToMesh(id + "_LOD2") : def.lods[1];
            def.bounds = def.lods[0].bounds;
            // make sure the material array covers every submesh
            if (def.materials.Length < def.lods[0].subMeshCount)
            {
                var m = new Material[def.lods[0].subMeshCount];
                for (int i = 0; i < m.Length; i++) m[i] = def.materials[Mathf.Min(i, def.materials.Length - 1)];
                def.materials = m;
            }
            return def;
        }

        static string[] M(params string[] k) { return k; }
        static ColRecipe[] C(params ColRecipe[] c) { return c; }

        PropDef Build(string full)
        {
            string id = full; var args = new string[0];
            int colon = full.IndexOf(':');
            if (colon >= 0) { id = full.Substring(0, colon); args = full.Substring(colon + 1).Split(':'); }
            switch (id)
            {
                case "spruce_a": return Spruce(full, 0);
                case "spruce_b": return Spruce(full, 1);
                case "spruce_c": return Spruce(full, 2);
                case "birch": return Birch(full);
                case "deadtree": return DeadTree(full);
                case "rock_s": return Rock(full, 0.45f, 0.34f, 0.40f, 6, 4, 0.28f, 11u, 0.35f);
                case "rock_m": return Rock(full, 1.0f, 0.78f, 0.9f, 7, 4, 0.26f, 23u, 0.9f);
                case "rock_l": return Rock(full, 2.0f, 1.5f, 1.8f, 8, 5, 0.22f, 37u, 1.8f);
                case "rock_slab": return Rock(full, 2.4f, 0.4f, 1.6f, 8, 3, 0.18f, 53u, 1.5f);
                case "log_long": return Log(full, 6f, 0.32f, 1100f);
                case "log_short": return Log(full, 2.2f, 0.28f, 320f);
                case "stump": return Stump(full);
                case "reed": return Reed(full);
                case "bush": return Bush(full);
                case "moss": return Moss(full);
                case "cabin": return Cabin(full);
                case "garage": return Garage(full);
                case "fuel_station": return FuelStation(full);
                case "watchtower": return Watchtower(full);
                case "radio_mast": return RadioMast(full);
                case "sawmill": return Sawmill(full);
                case "pump_house": return PumpHouse(full);
                case "bridge_intact": return Bridge(full, args, false);
                case "bridge_broken": return Bridge(full, args, true);
                case "causeway": return Causeway(full, args);
                case "sign_arrow": return SignArrow(full);
                case "sign_warn": return SignWarn(full);
                case "post_anchor": return PostAnchor(full);
                case "barrel": return Barrel(full, args.Length > 0 ? args[0] : "Red");
                case "crate": return Crate(full);
                case "tent": return Tent(full);
                case "fence": return Fence(full);
                case "marker_post": return MarkerPost(full, args.Length > 0 ? args[0] : "White");
                case "depth_pole": return DepthPole(full);
                case "distance_pole": return DistancePole(full);
                case "cone": return Cone(full);
                case "tank": return Tank(full);
                case "woodpile": return WoodPile(full);
                default:
                    {
                        var mb = new MeshBuilder();
                        mb.Box(new Vector3(0, 0.5f, 0), Vector3.one);
                        return Finish(full, mb, null, null, M("Red"), C(ColRecipe.Box(new Vector3(0, 0.5f, 0), Vector3.one)));
                    }
            }
        }

        // ================================================================== nature

        static MeshBuilder SpruceMesh(int variant, int lod, uint seed)
        {
            float H = variant == 0 ? 14f : variant == 1 ? 10.5f : 5.2f;
            float Rmax = variant == 0 ? 2.8f : variant == 1 ? 2.3f : 1.35f;
            int nT = variant == 0 ? 10 : variant == 1 ? 8 : 5;
            if (lod == 1) nT = Mathf.Max(4, nT - 3);
            if (lod == 2) nT = 3;
            int seg = lod == 0 ? 10 : lod == 1 ? 7 : 5;
            var mb = new MeshBuilder();
            mb.sub = 0;
            mb.Cylinder(Vector3.zero, 0.12f + 0.016f * H, 0.04f, H * 0.96f, lod == 0 ? 7 : 5, false, false);
            mb.sub = 1;
            var rng = new Rng(seed);
            float yStart = H * 0.13f, span = H * 0.80f;
            for (int i = 0; i < nT; i++)
            {
                float f = nT > 1 ? i / (float)(nT - 1) : 0f;
                float y = yStart + f * span;
                float R = Mathf.Lerp(Rmax, 0.3f, Mathf.Pow(f, 0.85f));
                float hT = span / nT * 2.3f;
                var ringB = new Vector3[seg];
                var ringA = new Vector3[seg];
                float rot = i * 0.77f + rng.Next01();
                for (int s = 0; s < seg; s++)
                {
                    float a = rot + s / (float)seg * Mathf.PI * 2f;
                    float rr = R * (0.86f + 0.28f * rng.Next01());
                    ringB[s] = new Vector3(Mathf.Cos(a) * rr, y - 0.10f * hT * (rr / R), Mathf.Sin(a) * rr);
                    ringA[s] = new Vector3(Mathf.Cos(a + 0.2f) * rr * 0.58f, y + 0.46f * hT, Mathf.Sin(a + 0.2f) * rr * 0.58f);
                }
                Vector3 apex = new Vector3(0f, y + hT, 0f);
                for (int s = 0; s < seg; s++)
                {
                    int s1 = (s + 1) % seg;
                    if (lod == 0)
                    {
                        mb.Tri(apex, ringA[s1], ringA[s]);
                        mb.Tri(ringA[s], ringA[s1], ringB[s1]);
                        mb.Tri(ringA[s], ringB[s1], ringB[s]);
                    }
                    else mb.Tri(apex, ringB[s1], ringB[s]);
                }
            }
            return mb;
        }

        PropDef Spruce(string id, int variant)
        {
            uint seed = 101u + (uint)variant * 17u;
            float H = variant == 0 ? 14f : variant == 1 ? 10.5f : 5.2f;
            string foliage = variant == 0 ? "Foliage" : variant == 1 ? "FoliageB" : "FoliageC";
            float r = 0.13f + 0.016f * H;
            return Finish(id, SpruceMesh(variant, 0, seed), SpruceMesh(variant, 1, seed), SpruceMesh(variant, 2, seed), M("Bark", foliage),
                C(ColRecipe.Capsule(new Vector3(0, Mathf.Min(2.2f, H * 0.3f), 0), r * 0.85f, Mathf.Min(4.4f, H * 0.6f))),
                0f, H, 55f, 150f, 950f);
        }

        PropDef Birch(string id)
        {
            MeshBuilder Mk(int lod)
            {
                var mb = new MeshBuilder();
                mb.sub = 0;
                mb.Cylinder(Vector3.zero, 0.16f, 0.05f, 8.2f, lod == 0 ? 7 : 5, false, false);
                if (lod == 0)
                {
                    mb.Beam(new Vector3(0, 4.2f, 0), new Vector3(1.0f, 6.2f, 0.4f), 0.07f, 0.07f);
                    mb.Beam(new Vector3(0, 5.0f, 0), new Vector3(-0.9f, 6.8f, -0.5f), 0.06f, 0.06f);
                }
                mb.sub = 1;
                if (lod == 0)
                {
                    mb.Blob(new Vector3(0.1f, 6.9f, 0f), new Vector3(1.7f, 1.5f, 1.6f), 8, 4, 0.25f, 5u);
                    mb.Blob(new Vector3(1.0f, 5.9f, 0.5f), new Vector3(1.2f, 1.0f, 1.1f), 7, 3, 0.25f, 6u);
                    mb.Blob(new Vector3(-0.9f, 6.3f, -0.5f), new Vector3(1.3f, 1.1f, 1.2f), 7, 3, 0.25f, 7u);
                    mb.Blob(new Vector3(0f, 8.0f, 0f), new Vector3(1.0f, 0.9f, 1.0f), 7, 3, 0.25f, 8u);
                }
                else mb.Blob(new Vector3(0f, 6.6f, 0f), new Vector3(2.0f, 2.2f, 2.0f), 6, 3, 0.2f, 5u);
                return mb;
            }
            return Finish(id, Mk(0), Mk(1), Mk(1), M("Birch", "BirchLeaf"), C(ColRecipe.Capsule(new Vector3(0, 1.8f, 0), 0.14f, 3.6f)), 0f, 8.2f, 50f, 130f, 750f);
        }

        PropDef DeadTree(string id)
        {
            MeshBuilder Mk(int lod)
            {
                var mb = new MeshBuilder();
                mb.Cylinder(Vector3.zero, 0.26f, 0.05f, 6.8f, lod == 0 ? 6 : 4, false, false);
                if (lod == 0)
                {
                    var rng = new Rng(77u);
                    for (int i = 0; i < 6; i++)
                    {
                        float y = 2.2f + i * 0.7f; float a = rng.Next01() * Mathf.PI * 2f;
                        Vector3 s0 = new Vector3(0, y, 0);
                        Vector3 e = s0 + new Vector3(Mathf.Cos(a) * (1.1f + rng.Next01() * 0.8f), 0.6f + rng.Next01() * 0.8f, Mathf.Sin(a) * (1.1f + rng.Next01() * 0.8f));
                        mb.Beam(s0, e, 0.09f, 0.09f);
                        mb.Beam(Vector3.Lerp(s0, e, 0.6f), Vector3.Lerp(s0, e, 0.6f) + new Vector3(-Mathf.Sin(a) * 0.5f, 0.5f, Mathf.Cos(a) * 0.5f), 0.05f, 0.05f);
                    }
                }
                return mb;
            }
            return Finish(id, Mk(0), Mk(1), Mk(1), M("Dead"), C(ColRecipe.Capsule(new Vector3(0, 1.6f, 0), 0.22f, 3.2f)), 0f, 6.8f, 50f, 130f, 650f);
        }

        PropDef Rock(string id, float rx, float ry, float rz, int seg, int rings, float rough, uint seed, float colR)
        {
            MeshBuilder Mk(int lod)
            {
                var mb = new MeshBuilder();
                mb.Blob(new Vector3(0, ry * 0.55f, 0), new Vector3(rx, ry, rz), lod == 0 ? seg : Mathf.Max(5, seg - 2), lod == 0 ? rings : Mathf.Max(3, rings - 1), rough, seed, -0.7f);
                return mb;
            }
            ColRecipe col = id == "rock_slab" ? ColRecipe.Box(new Vector3(0, ry * 0.5f, 0), new Vector3(rx * 1.7f, ry * 1.2f, rz * 1.7f))
                                              : ColRecipe.Sphere(new Vector3(0, ry * 0.6f, 0), colR * 0.85f);
            return Finish(id, Mk(0), Mk(1), Mk(1), M("Rock"), C(col), 0f, ry * 1.5f, 80f, 200f, id == "rock_s" ? 220f : 420f);
        }

        PropDef Log(string id, float len, float r, float mass)
        {
            var mb = new MeshBuilder();
            mb.sub = 0;
            mb.CylinderAxis(Vector3.zero, Vector3.forward, len, r, r * 0.9f, 9, true, 1);
            var lo = new MeshBuilder();
            lo.CylinderAxis(Vector3.zero, Vector3.forward, len, r, r * 0.9f, 6, true, 1);
            return Finish(id, mb, lo, lo, M("Bark", "LogEnd"), C(ColRecipe.Capsule(Vector3.zero, r * 0.95f, len, 2)), mass, r * 2f, 60f, 140f, 300f);
        }

        PropDef Stump(string id)
        {
            var mb = new MeshBuilder();
            mb.Cylinder(Vector3.zero, 0.52f, 0.34f, 0.28f, 8, false, false);
            mb.Cylinder(new Vector3(0, 0.28f, 0), 0.34f, 0.31f, 0.55f, 8, false, false);
            mb.sub = 1;
            mb.Cylinder(new Vector3(0, 0.83f, 0), 0.31f, 0.30f, 0.01f, 8, true, false);
            var lo = new MeshBuilder();
            lo.Cylinder(Vector3.zero, 0.42f, 0.31f, 0.84f, 6, true, false);
            return Finish(id, mb, lo, lo, M("Bark", "LogEnd"), C(ColRecipe.Capsule(new Vector3(0, 0.42f, 0), 0.36f, 0.85f)), 0f, 0.85f, 50f, 120f, 220f);
        }

        PropDef Reed(string id)
        {
            var mb = new MeshBuilder();
            var rng = new Rng(901u);
            for (int i = 0; i < 11; i++)
            {
                float a = rng.Next01() * Mathf.PI * 2f, rr = rng.Next01() * 0.35f;
                float h = 1.0f + rng.Next01() * 0.8f;
                Vector3 b = new Vector3(Mathf.Cos(a) * rr, 0f, Mathf.Sin(a) * rr);
                Vector3 lean = new Vector3(Mathf.Cos(a) * 0.35f, 0f, Mathf.Sin(a) * 0.35f) * (0.4f + rng.Next01() * 0.6f);
                Vector3 side = new Vector3(-Mathf.Sin(a), 0f, Mathf.Cos(a)) * 0.045f;
                Vector3 mid = b + lean * 0.35f + Vector3.up * h * 0.55f;
                Vector3 top = b + lean + Vector3.up * h;
                mb.QuadDouble(b - side, b + side, mid + side * 0.7f, mid - side * 0.7f);
                mb.Tri(mid - side * 0.7f, mid + side * 0.7f, top);
                mb.Tri(top, mid + side * 0.7f, mid - side * 0.7f);
            }
            return Finish(id, mb, null, null, M("Reed"), null, 0f, 1.6f, 60f, 70f, 120f, false);
        }

        PropDef Bush(string id)
        {
            var mb = new MeshBuilder();
            mb.Blob(new Vector3(0, 0.55f, 0), new Vector3(0.95f, 0.75f, 0.9f), 7, 4, 0.3f, 31u, -0.5f);
            mb.Blob(new Vector3(0.55f, 0.4f, 0.3f), new Vector3(0.6f, 0.5f, 0.6f), 6, 3, 0.3f, 32u, -0.5f);
            var lo = new MeshBuilder();
            lo.Blob(new Vector3(0, 0.55f, 0), new Vector3(1.0f, 0.75f, 1.0f), 5, 3, 0.2f, 31u, -0.5f);
            return Finish(id, mb, lo, lo, M("Bush"), null, 0f, 1.2f, 40f, 80f, 130f, false);
        }

        PropDef Moss(string id)
        {
            var mb = new MeshBuilder();
            mb.Blob(new Vector3(0, 0.02f, 0), new Vector3(1.5f, 0.08f, 1.1f), 8, 3, 0.35f, 61u, -0.2f);
            return Finish(id, mb, null, null, M("Moss"), null, 0f, 0.1f, 35f, 40f, 60f, false);
        }

        // ================================================================== buildings and structures

        PropDef Cabin(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 2; mb.Box(new Vector3(0, 0.15f, 0), new Vector3(7.4f, 0.3f, 5.6f));
            mb.sub = 0;
            for (int i = 0; i < 9; i++)
            {
                float y = 0.3f + i * 0.27f + 0.135f;
                float ov = (i % 2 == 0) ? 0.35f : 0.1f;
                mb.CylinderAxis(new Vector3(0, y, 2.55f), Vector3.right, 7.1f + ov, 0.14f, 0.14f, 6, true);
                mb.CylinderAxis(new Vector3(0, y, -2.55f), Vector3.right, 7.1f + ov, 0.14f, 0.14f, 6, true);
                mb.CylinderAxis(new Vector3(3.45f, y, 0), Vector3.forward, 5.2f + (0.45f - ov), 0.14f, 0.14f, 6, true);
                mb.CylinderAxis(new Vector3(-3.45f, y, 0), Vector3.forward, 5.2f + (0.45f - ov), 0.14f, 0.14f, 6, true);
            }
            mb.sub = 3;
            mb.Box(new Vector3(-1.2f, 1.25f, 2.72f), new Vector3(1.0f, 1.95f, 0.1f));      // door
            mb.Box(new Vector3(1.6f, 1.55f, 2.72f), new Vector3(1.0f, 0.8f, 0.08f));       // windows
            mb.Box(new Vector3(-3.62f, 1.55f, 0.4f), new Vector3(0.08f, 0.8f, 1.0f));
            mb.sub = 1;
            float eave = 0.8f;
            Vector3 a = new Vector3(-4.1f, 2.76f, 3.35f), b = new Vector3(4.1f, 2.76f, 3.35f), c = new Vector3(4.1f, 4.5f, 0f), d = new Vector3(-4.1f, 4.5f, 0f);
            mb.QuadDouble(a, b, c, d);
            mb.QuadDouble(new Vector3(4.1f, 2.76f, -3.35f), new Vector3(-4.1f, 2.76f, -3.35f), d, c);
            mb.sub = 0;
            mb.Tri(new Vector3(3.5f, 2.73f, 2.7f), new Vector3(3.5f, 4.45f, 0f), new Vector3(3.5f, 2.73f, -2.7f));
            mb.Tri(new Vector3(-3.5f, 2.73f, -2.7f), new Vector3(-3.5f, 4.45f, 0f), new Vector3(-3.5f, 2.73f, 2.7f));
            // porch
            mb.sub = 0; mb.Box(new Vector3(0, 0.22f, 3.7f), new Vector3(6.4f, 0.14f, 1.9f));
            mb.Box(new Vector3(-2.9f, 1.3f, 4.55f), new Vector3(0.18f, 2.2f, 0.18f)); mb.Box(new Vector3(2.9f, 1.3f, 4.55f), new Vector3(0.18f, 2.2f, 0.18f));
            mb.sub = 1; mb.QuadDouble(new Vector3(-3.2f, 2.45f, 4.75f), new Vector3(3.2f, 2.45f, 4.75f), new Vector3(3.2f, 2.95f, 2.6f), new Vector3(-3.2f, 2.95f, 2.6f));
            mb.sub = 2; mb.Box(new Vector3(2.4f, 2.6f, -2.95f), new Vector3(0.9f, 5.3f, 0.9f)); mb.Box(new Vector3(2.4f, 5.4f, -2.95f), new Vector3(1.05f, 0.2f, 1.05f));
            return Finish(id, mb, null, null, M("Wood", "Roof", "Stone", "Door"),
                C(ColRecipe.Box(new Vector3(0, 1.5f, 0), new Vector3(7.2f, 3.0f, 5.4f)), ColRecipe.Box(new Vector3(0, 3.6f, 0), new Vector3(7.2f, 1.6f, 4.0f)),
                  ColRecipe.Box(new Vector3(0, 0.25f, 3.7f), new Vector3(6.4f, 0.4f, 1.9f)), ColRecipe.Box(new Vector3(2.4f, 2.6f, -2.95f), new Vector3(0.9f, 5.2f, 0.9f))),
                0f, 5f, 400f, 600f, 900f);
        }

        PropDef Garage(string id)
        {
            var mb = new MeshBuilder();
            float W = 14f, D = 10f, H = 4.6f, T = 0.3f;
            mb.sub = 2; mb.Box(new Vector3(0, 0.05f, 0), new Vector3(W, 0.1f, D));      // floor (dark concrete)
            mb.sub = 0;
            mb.Box(new Vector3(0, H * 0.5f, -D * 0.5f + T * 0.5f), new Vector3(W, H, T));
            mb.Box(new Vector3(-W * 0.5f + T * 0.5f, H * 0.5f, 0), new Vector3(T, H, D));
            mb.Box(new Vector3(W * 0.5f - T * 0.5f, H * 0.5f, 0), new Vector3(T, H, D));
            float openW = 6.4f, openH = 4.0f;
            float sideW = (W - openW) * 0.5f;
            mb.Box(new Vector3(-(openW * 0.5f + sideW * 0.5f), H * 0.5f, D * 0.5f - T * 0.5f), new Vector3(sideW, H, T));
            mb.Box(new Vector3((openW * 0.5f + sideW * 0.5f), H * 0.5f, D * 0.5f - T * 0.5f), new Vector3(sideW, H, T));
            mb.Box(new Vector3(0, openH + (H - openH) * 0.5f, D * 0.5f - T * 0.5f), new Vector3(openW, H - openH, T));
            // rolled up door
            mb.sub = 3; mb.Box(new Vector3(0, openH + 0.12f, D * 0.5f - 0.5f), new Vector3(openW, 0.3f, 0.35f));
            // hazard trim around the opening
            mb.Box(new Vector3(-openW * 0.5f - 0.1f, openH * 0.5f, D * 0.5f + 0.02f), new Vector3(0.22f, openH, 0.06f));
            mb.Box(new Vector3(openW * 0.5f + 0.1f, openH * 0.5f, D * 0.5f + 0.02f), new Vector3(0.22f, openH, 0.06f));
            mb.Box(new Vector3(0, openH + 0.1f, D * 0.5f + 0.02f), new Vector3(openW + 0.42f, 0.22f, 0.06f));
            // sign board above the door
            mb.Box(new Vector3(0, H - 0.35f, D * 0.5f + 0.08f), new Vector3(5f, 0.7f, 0.08f));
            // roof (low gable along x)
            mb.sub = 1;
            float rise = 1.1f, ov = 0.5f;
            Vector3 f0 = new Vector3(-W * 0.5f - ov, H, D * 0.5f + ov), f1 = new Vector3(W * 0.5f + ov, H, D * 0.5f + ov);
            Vector3 b0 = new Vector3(-W * 0.5f - ov, H, -D * 0.5f - ov), b1 = new Vector3(W * 0.5f + ov, H, -D * 0.5f - ov);
            Vector3 r0 = new Vector3(-W * 0.5f - ov, H + rise, 0), r1 = new Vector3(W * 0.5f + ov, H + rise, 0);
            mb.QuadDouble(f0, f1, r1, r0); mb.QuadDouble(b1, b0, r0, r1);
            mb.sub = 0;
            mb.Tri(new Vector3(-W * 0.5f, H, D * 0.5f), new Vector3(-W * 0.5f, H + rise, 0), new Vector3(-W * 0.5f, H, -D * 0.5f));
            mb.Tri(new Vector3(W * 0.5f, H, -D * 0.5f), new Vector3(W * 0.5f, H + rise, 0), new Vector3(W * 0.5f, H, D * 0.5f));
            // workbench + shelves inside
            mb.sub = 1; mb.Box(new Vector3(-5.2f, 0.55f, -3.8f), new Vector3(2.4f, 1.1f, 0.9f)); mb.Box(new Vector3(5.4f, 1.0f, -4.5f), new Vector3(1.5f, 2.0f, 0.5f));
            return Finish(id, mb, null, null, M("Metal", "RoofGreen", "Concrete", "Yellow"),
                C(ColRecipe.Box(new Vector3(0, H * 0.5f, -D * 0.5f + T * 0.5f), new Vector3(W, H, T)), ColRecipe.Box(new Vector3(-W * 0.5f + T * 0.5f, H * 0.5f, 0), new Vector3(T, H, D)),
                  ColRecipe.Box(new Vector3(W * 0.5f - T * 0.5f, H * 0.5f, 0), new Vector3(T, H, D)),
                  ColRecipe.Box(new Vector3(-(openW * 0.5f + sideW * 0.5f), H * 0.5f, D * 0.5f - T * 0.5f), new Vector3(sideW, H, T)),
                  ColRecipe.Box(new Vector3((openW * 0.5f + sideW * 0.5f), H * 0.5f, D * 0.5f - T * 0.5f), new Vector3(sideW, H, T)),
                  ColRecipe.Box(new Vector3(0, openH + (H - openH) * 0.5f + 0.4f, D * 0.5f - T * 0.5f), new Vector3(openW, H - openH + 0.8f, T)),
                  ColRecipe.Box(new Vector3(0, H + 0.6f, 0), new Vector3(W, 1.2f, D))),
                0f, 6f, 500f, 800f, 1100f);
        }

        PropDef FuelStation(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0;
            float px = 3.4f, pz = 1.9f, ph = 4.3f;
            foreach (var sx in new[] { -1f, 1f }) foreach (var sz in new[] { -1f, 1f }) mb.Box(new Vector3(sx * px, ph * 0.5f, sz * pz), new Vector3(0.28f, ph, 0.28f));
            mb.sub = 1; mb.Box(new Vector3(0, ph + 0.2f, 0), new Vector3(9.2f, 0.4f, 5.6f));
            mb.sub = 2; mb.Box(new Vector3(0, ph + 0.2f, 2.85f), new Vector3(9.2f, 0.42f, 0.06f)); mb.Box(new Vector3(0, ph - 0.1f, 0), new Vector3(8.9f, 0.12f, 5.3f));
            mb.sub = 3; mb.Box(new Vector3(0, 0.12f, 0), new Vector3(5.2f, 0.24f, 1.3f));
            for (int i = 0; i < 2; i++)
            {
                float x = (i == 0 ? -1.4f : 1.4f);
                mb.sub = 1; mb.Box(new Vector3(x, 0.24f + 0.78f, 0), new Vector3(0.62f, 1.5f, 0.48f));
                mb.sub = 0; mb.Box(new Vector3(x, 1.65f, 0.26f), new Vector3(0.44f, 0.3f, 0.06f));
                mb.Beam(new Vector3(x + 0.34f, 1.1f, 0), new Vector3(x + 0.6f, 0.75f, 0.3f), 0.06f, 0.06f);
            }
            // storage tank
            mb.sub = 2;
            mb.CylinderAxis(new Vector3(7.4f, 1.45f, -1.5f), Vector3.forward, 5.5f, 1.1f, 1.1f, 12, true);
            mb.sub = 0; mb.Box(new Vector3(7.4f, 0.2f, -0.4f), new Vector3(1.6f, 0.4f, 0.35f)); mb.Box(new Vector3(7.4f, 0.2f, -2.8f), new Vector3(1.6f, 0.4f, 0.35f));
            return Finish(id, mb, null, null, M("Metal", "Red", "White", "Concrete"),
                C(ColRecipe.Box(new Vector3(-1.4f, 1.0f, 0), new Vector3(0.7f, 2f, 0.6f)), ColRecipe.Box(new Vector3(1.4f, 1.0f, 0), new Vector3(0.7f, 2f, 0.6f)),
                  ColRecipe.Box(new Vector3(-px, ph * 0.5f, -pz), new Vector3(0.4f, ph, 0.4f)), ColRecipe.Box(new Vector3(px, ph * 0.5f, -pz), new Vector3(0.4f, ph, 0.4f)),
                  ColRecipe.Box(new Vector3(-px, ph * 0.5f, pz), new Vector3(0.4f, ph, 0.4f)), ColRecipe.Box(new Vector3(px, ph * 0.5f, pz), new Vector3(0.4f, ph, 0.4f)),
                  ColRecipe.Capsule(new Vector3(7.4f, 1.45f, -1.5f), 1.1f, 5.5f, 2)),
                0f, 5f, 300f, 500f, 800f);
        }

        PropDef Watchtower(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0;
            float h = 8.2f;
            Vector3[] foot = { new Vector3(-1.9f, 0, -1.9f), new Vector3(1.9f, 0, -1.9f), new Vector3(1.9f, 0, 1.9f), new Vector3(-1.9f, 0, 1.9f) };
            Vector3[] top = new Vector3[4];
            for (int i = 0; i < 4; i++) { top[i] = new Vector3(foot[i].x * 0.62f, h, foot[i].z * 0.62f); mb.Beam(foot[i], top[i], 0.28f, 0.28f); }
            for (int lv = 0; lv < 3; lv++)
            {
                float f0 = lv / 3f, f1 = (lv + 1) / 3f;
                for (int i = 0; i < 4; i++)
                {
                    int j = (i + 1) % 4;
                    Vector3 a0 = Vector3.Lerp(foot[i], top[i], f0), a1 = Vector3.Lerp(foot[i], top[i], f1), b0 = Vector3.Lerp(foot[j], top[j], f0), b1 = Vector3.Lerp(foot[j], top[j], f1);
                    mb.Beam(a0, b0, 0.16f, 0.16f);
                    mb.Beam(a0, b1, 0.12f, 0.12f); mb.Beam(b0, a1, 0.12f, 0.12f);
                }
            }
            mb.sub = 1;
            mb.Box(new Vector3(0, h + 0.1f, 0), new Vector3(3.6f, 0.22f, 3.6f));
            for (int i = 0; i < 4; i++)
            {
                float a = i * 90f * Mathf.Deg2Rad;
                Vector3 n = new Vector3(Mathf.Sin(a), 0, Mathf.Cos(a));
                Vector3 side = new Vector3(n.z, 0, -n.x);
                mb.Box(new Vector3(0, h + 0.7f, 0) + n * 1.78f, new Vector3(Mathf.Abs(side.x) * 3.6f + 0.1f, 0.08f, Mathf.Abs(side.z) * 3.6f + 0.1f));
                mb.Box(new Vector3(0, h + 1.15f, 0) + n * 1.78f, new Vector3(Mathf.Abs(side.x) * 3.6f + 0.1f, 0.08f, Mathf.Abs(side.z) * 3.6f + 0.1f));
            }
            mb.sub = 0;
            for (int r = 0; r < 8; r++) { float y = 0.7f + r * 0.95f; mb.Box(new Vector3(0.4f, y, 1.9f - r * 0.07f), new Vector3(0.7f, 0.05f, 0.05f)); }
            mb.Beam(new Vector3(0.05f, 0.2f, 1.95f), new Vector3(0.05f, h + 0.2f, 1.45f), 0.06f, 0.06f); mb.Beam(new Vector3(0.75f, 0.2f, 1.95f), new Vector3(0.75f, h + 0.2f, 1.45f), 0.06f, 0.06f);
            // hut
            mb.sub = 0; mb.Box(new Vector3(0, h + 1.35f, -0.2f), new Vector3(2.4f, 2.1f, 2.2f));
            mb.sub = 3; mb.Box(new Vector3(0, h + 1.55f, 0.92f), new Vector3(1.8f, 0.8f, 0.05f));
            mb.sub = 2;
            Vector3 q0 = new Vector3(-1.5f, h + 2.4f, 1.1f), q1 = new Vector3(1.5f, h + 2.4f, 1.1f), q2 = new Vector3(1.5f, h + 3.3f, -0.2f), q3 = new Vector3(-1.5f, h + 3.3f, -0.2f);
            mb.QuadDouble(q0, q1, q2, q3);
            mb.QuadDouble(new Vector3(1.5f, h + 2.4f, -1.5f), new Vector3(-1.5f, h + 2.4f, -1.5f), q3, q2);
            return Finish(id, mb, null, null, M("WoodDark", "Planks", "Roof", "Glass"),
                C(ColRecipe.Box(new Vector3(-1.5f, 2f, -1.5f), new Vector3(0.5f, 4f, 0.5f)), ColRecipe.Box(new Vector3(1.5f, 2f, -1.5f), new Vector3(0.5f, 4f, 0.5f)),
                  ColRecipe.Box(new Vector3(-1.5f, 2f, 1.5f), new Vector3(0.5f, 4f, 0.5f)), ColRecipe.Box(new Vector3(1.5f, 2f, 1.5f), new Vector3(0.5f, 4f, 0.5f)),
                  ColRecipe.Box(new Vector3(0, h + 1.2f, 0), new Vector3(3.6f, 2.8f, 3.6f))),
                0f, 12f, 500f, 800f, 1200f);
        }

        PropDef RadioMast(string id)
        {
            var mb = new MeshBuilder();
            float H = 28f; int bands = 7;
            Vector3[] foot = new Vector3[3], top = new Vector3[3];
            for (int i = 0; i < 3; i++)
            {
                float a = i * 120f * Mathf.Deg2Rad + 0.3f;
                foot[i] = new Vector3(Mathf.Cos(a) * 1.5f, 0, Mathf.Sin(a) * 1.5f); top[i] = new Vector3(Mathf.Cos(a) * 0.22f, H, Mathf.Sin(a) * 0.22f);
            }
            for (int b = 0; b < bands; b++)
            {
                float f0 = b / (float)bands, f1 = (b + 1) / (float)bands;
                mb.sub = (b % 2 == 0) ? 1 : 2;
                for (int i = 0; i < 3; i++)
                {
                    Vector3 a0 = Vector3.Lerp(foot[i], top[i], f0) + Vector3.up * (f0 * H), a1 = Vector3.Lerp(foot[i], top[i], f1) + Vector3.up * (f1 * H);
                    a0.y = f0 * H; a1.y = f1 * H;
                    mb.Beam(a0, a1, 0.14f, 0.14f);
                }
                mb.sub = 0;
                for (int i = 0; i < 3; i++)
                {
                    int j = (i + 1) % 3;
                    Vector3 a0 = Vector3.Lerp(foot[i], top[i], f1); a0.y = f1 * H; Vector3 b0 = Vector3.Lerp(foot[j], top[j], f1); b0.y = f1 * H;
                    Vector3 a00 = Vector3.Lerp(foot[i], top[i], f0); a00.y = f0 * H;
                    mb.Beam(a0, b0, 0.07f, 0.07f); mb.Beam(a00, b0, 0.05f, 0.05f);
                }
            }
            mb.sub = 0; mb.Beam(new Vector3(0, H, 0), new Vector3(0, H + 4f, 0), 0.06f, 0.06f);
            mb.sub = 3; mb.Box(new Vector3(3.8f, 1.2f, 0), new Vector3(3f, 2.4f, 2.6f));
            mb.sub = 0; mb.Box(new Vector3(3.8f, 2.5f, 0), new Vector3(3.3f, 0.2f, 2.9f));
            return Finish(id, mb, null, null, M("MetalDark", "Red", "White", "Concrete"),
                C(ColRecipe.Capsule(new Vector3(0, 1.8f, 0), 1.3f, 3.6f), ColRecipe.Box(new Vector3(3.8f, 1.2f, 0), new Vector3(3f, 2.4f, 2.6f))), 0f, 32f, 1500f, 2000f, 2400f);
        }

        PropDef Sawmill(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0;
            var rng = new Rng(404u);
            float[] hs = { 4.6f, 4.6f, 3.1f, 4.4f, 2.0f, 4.5f };
            for (int i = 0; i < 6; i++)
            {
                float x = (i % 3 - 1) * 5f, z = (i / 3 - 0.5f) * 7f;
                mb.Box(new Vector3(x, hs[i] * 0.5f, z), new Vector3(0.34f, hs[i], 0.34f));
            }
            mb.Beam(new Vector3(-5f, 4.6f, -3.5f), new Vector3(0f, 4.6f, -3.5f), 0.3f, 0.3f);
            mb.Beam(new Vector3(0f, 4.4f, 3.5f), new Vector3(5f, 4.5f, 3.5f), 0.3f, 0.3f);
            mb.Beam(new Vector3(-5f, 4.6f, -3.5f), new Vector3(-5f, 4.2f, 3.5f), 0.3f, 0.3f);
            mb.sub = 1;
            mb.QuadDouble(new Vector3(-5.5f, 4.4f, -3.8f), new Vector3(0.5f, 4.4f, -3.8f), new Vector3(0.5f, 2.6f, -1.2f), new Vector3(-5.5f, 2.6f, -1.2f));
            mb.QuadDouble(new Vector3(0.5f, 0.9f, 1.5f), new Vector3(5.5f, 0.7f, 1.5f), new Vector3(5.5f, 1.4f, 4.4f), new Vector3(0.5f, 1.6f, 4.4f));
            mb.sub = 2;
            mb.CylinderAxis(new Vector3(-2f, 1.4f, 0.3f), Vector3.right, 1.6f, 1.2f, 1.2f, 14, true);
            mb.Box(new Vector3(-2f, 0.6f, 0.3f), new Vector3(0.3f, 1.2f, 2.4f)); mb.Box(new Vector3(-2.9f, 0.6f, 0.3f), new Vector3(0.3f, 1.2f, 2.4f));
            mb.CylinderAxis(new Vector3(4.2f, 1.1f, -1.6f), Vector3.forward, 4.6f, 0.95f, 0.95f, 12, true);
            for (int i = 0; i < 2; i++) mb.Beam(new Vector3(-6f + i * 0.5f, 0.3f, -5f), new Vector3(8f + i * 0.5f, 0.3f, -5f), 0.14f, 0.14f);
            mb.sub = 3;
            for (int i = 0; i < 14; i++) mb.CylinderAxis(new Vector3(-6.5f + (i % 4) * 0.55f, 0.3f + (i / 4) * 0.5f, 6f), Vector3.right, 3.4f, 0.24f, 0.24f, 6, true);
            return Finish(id, mb, null, null, M("WoodGrey", "Roof", "Rust", "Wood"),
                C(ColRecipe.Box(new Vector3(-5f, 2.3f, -3.5f), new Vector3(0.5f, 4.6f, 0.5f)), ColRecipe.Box(new Vector3(5f, 2.2f, 3.5f), new Vector3(0.5f, 4.4f, 0.5f)),
                  ColRecipe.Capsule(new Vector3(4.2f, 1.1f, -1.6f), 0.95f, 4.6f, 2), ColRecipe.Box(new Vector3(-2.4f, 1.2f, 0.3f), new Vector3(2.0f, 2.4f, 2.6f)),
                  ColRecipe.Box(new Vector3(-5f, 0.9f, 6f), new Vector3(3.4f, 1.8f, 1.6f))),
                0f, 5f, 300f, 500f, 800f);
        }

        PropDef PumpHouse(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0; mb.Box(new Vector3(0, 1.6f, 0), new Vector3(6f, 3.2f, 4.5f));
            mb.sub = 1; mb.Box(new Vector3(0, 3.35f, 0), new Vector3(6.6f, 0.3f, 5.1f));
            mb.sub = 2; mb.Box(new Vector3(0, 1.1f, 2.28f), new Vector3(1.4f, 2.2f, 0.08f));
            mb.sub = 3;
            mb.Cylinder(new Vector3(5f, 0, 1.5f), 1.4f, 1.4f, 4.2f, 14, true, false); mb.Cylinder(new Vector3(5f, 0, -1.5f), 1.4f, 1.4f, 3.6f, 14, true, false);
            mb.CylinderAxis(new Vector3(2.5f, 0.5f, 1.5f), Vector3.right, 4f, 0.14f, 0.14f, 6, true);
            mb.CylinderAxis(new Vector3(2.5f, 0.5f, -1.5f), Vector3.right, 4f, 0.14f, 0.14f, 6, true);
            return Finish(id, mb, null, null, M("Concrete", "Roof", "Door", "Metal"),
                C(ColRecipe.Box(new Vector3(0, 1.8f, 0), new Vector3(6f, 3.6f, 4.5f)), ColRecipe.Capsule(new Vector3(5f, 2.1f, 1.5f), 1.4f, 4.2f), ColRecipe.Capsule(new Vector3(5f, 1.8f, -1.5f), 1.4f, 3.6f)), 0f, 4.2f, 300f, 500f, 800f);
        }

        // ------------------------------------------------------------------ bridges

        PropDef Bridge(string id, string[] args, bool broken)
        {
            float L = 10f; bool old = false;
            if (args.Length > 0) float.TryParse(args[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out L);
            if (args.Length > 1 && args[1] == "old") old = true;
            float W = 4.2f;
            var mb = new MeshBuilder();
            mb.sub = 0;
            int n = Mathf.Max(4, Mathf.RoundToInt(L / 0.26f));
            float pl = L / n;
            var cols = new List<ColRecipe>();
            // missing plank zones for the broken bridge
            float g0 = L * 0.30f, g1 = L * 0.58f, g2 = L * 0.74f, g3 = L * 0.80f;
            for (int i = 0; i < n; i++)
            {
                float z = -L * 0.5f + (i + 0.5f) * pl;
                float t = z + L * 0.5f;
                bool missing = broken && ((t > g0 && t < g1) || (t > g2 && t < g3) || (i % 7 == 3 && t > g1));
                if (missing) continue;
                float jitter = old ? ((i * 37 % 11) - 5) * 0.004f : 0f;
                mb.Box(new Vector3(0, -0.06f + jitter, z), new Vector3(W, 0.12f, pl * 0.92f));
            }
            if (!broken) cols.Add(ColRecipe.Box(new Vector3(0, -0.15f, 0), new Vector3(W, 0.3f, L)));
            else
            {
                cols.Add(ColRecipe.Box(new Vector3(0, -0.15f, -L * 0.5f + g0 * 0.5f), new Vector3(W, 0.3f, g0)));
                cols.Add(ColRecipe.Box(new Vector3(0, -0.15f, -L * 0.5f + (g1 + g2) * 0.5f), new Vector3(W * 0.5f, 0.3f, g2 - g1)));
                cols.Add(ColRecipe.Box(new Vector3(0, -0.15f, -L * 0.5f + (g3 + L) * 0.5f), new Vector3(W, 0.3f, L - g3)));
            }
            mb.sub = 1;
            for (int s = -1; s <= 1; s += 2) mb.Box(new Vector3(s * 1.5f, -0.42f, 0), new Vector3(0.28f, 0.42f, L));
            mb.Box(new Vector3(0, -0.42f, 0), new Vector3(0.28f, 0.42f, L));
            int bents = Mathf.Max(2, Mathf.RoundToInt(L / 6f) + 1);
            for (int b = 0; b < bents; b++)
            {
                float z = -L * 0.5f + 0.5f + b * (L - 1f) / (bents - 1);
                for (int s = -1; s <= 1; s += 2) mb.Box(new Vector3(s * 1.7f, -2.0f, z), new Vector3(0.34f, 3.4f, 0.34f));
                mb.Box(new Vector3(0, -0.75f, z), new Vector3(3.9f, 0.22f, 0.26f));
                mb.Beam(new Vector3(-1.7f, -2.6f, z), new Vector3(1.7f, -0.9f, z), 0.14f, 0.14f);
            }
            int posts = Mathf.Max(3, Mathf.RoundToInt(L / 2.4f) + 1);
            for (int p = 0; p < posts; p++)
            {
                float z = -L * 0.5f + p * L / (posts - 1);
                float t = z + L * 0.5f;
                bool gone = broken && (t > g0 - 0.5f && t < g1 + 0.5f) && (p % 2 == 0);
                for (int s = -1; s <= 1; s += 2)
                {
                    if (gone && s > 0) continue;
                    mb.Box(new Vector3(s * (W * 0.5f - 0.1f), 0.5f, z), new Vector3(0.14f, 1.1f, 0.14f));
                }
            }
            for (int s = -1; s <= 1; s += 2)
            {
                float x = s * (W * 0.5f - 0.1f);
                if (!broken) { mb.Box(new Vector3(x, 1.05f, 0), new Vector3(0.1f, 0.12f, L)); mb.Box(new Vector3(x, 0.6f, 0), new Vector3(0.08f, 0.1f, L)); }
                else
                {
                    mb.Box(new Vector3(x, 1.05f, -L * 0.5f + g0 * 0.5f), new Vector3(0.1f, 0.12f, g0)); mb.Box(new Vector3(x, 1.05f, -L * 0.5f + (g3 + L) * 0.5f), new Vector3(0.1f, 0.12f, L - g3));
                    if (s < 0) mb.Beam(new Vector3(x, 1.05f, -L * 0.5f + g0), new Vector3(x - 0.2f, 0.15f, -L * 0.5f + g0 + 2.4f), 0.1f, 0.12f);
                }
            }
            return Finish(id, mb, null, null, M(old || broken ? "PlanksOld" : "Planks", "WoodDark"), cols.ToArray(), 0f, 1.1f, 400f, 600f, 900f);
        }

        PropDef Causeway(string id, string[] args)
        {
            float L = 60f;
            if (args.Length > 0) float.TryParse(args[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out L);
            float W = 3.7f;
            var mb = new MeshBuilder();
            mb.sub = 0;
            int n = Mathf.Max(4, Mathf.RoundToInt(L / 0.28f));
            float pl = L / n;
            for (int i = 0; i < n; i++) mb.Box(new Vector3(0, -0.06f, -L * 0.5f + (i + 0.5f) * pl), new Vector3(W, 0.12f, pl * 0.9f));
            mb.sub = 1;
            for (int s = -1; s <= 1; s += 2) mb.Box(new Vector3(s * 1.2f, -0.4f, 0), new Vector3(0.3f, 0.4f, L));
            int piles = Mathf.Max(2, Mathf.RoundToInt(L / 3.2f) + 1);
            for (int p = 0; p < piles; p++)
            {
                float z = -L * 0.5f + p * L / (piles - 1);
                for (int s = -1; s <= 1; s += 2) mb.Box(new Vector3(s * 1.75f, -1.7f, z), new Vector3(0.32f, 3.0f, 0.32f));
                mb.Box(new Vector3(0, -0.7f, z), new Vector3(3.6f, 0.2f, 0.24f));
                for (int s = -1; s <= 1; s += 2) mb.Box(new Vector3(s * (W * 0.5f - 0.08f), 0.4f, z), new Vector3(0.12f, 0.9f, 0.12f));
            }
            for (int s = -1; s <= 1; s += 2) mb.Box(new Vector3(s * (W * 0.5f - 0.08f), 0.82f, 0), new Vector3(0.09f, 0.1f, L));
            return Finish(id, mb, null, null, M("PlanksOld", "WoodDark"), C(ColRecipe.Box(new Vector3(0, -0.15f, 0), new Vector3(W, 0.3f, L))), 0f, 1f, 400f, 600f, 900f);
        }

        // ------------------------------------------------------------------ small props

        PropDef SignArrow(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0; mb.Box(new Vector3(0, 1.15f, 0), new Vector3(0.14f, 2.3f, 0.14f));
            mb.sub = 1;
            mb.Box(new Vector3(-0.15f, 1.9f, 0.09f), new Vector3(1.3f, 0.42f, 0.05f));
            mb.Tri(new Vector3(0.5f, 2.18f, 0.09f), new Vector3(0.5f, 1.62f, 0.09f), new Vector3(1.0f, 1.9f, 0.09f));
            mb.Tri(new Vector3(1.0f, 1.9f, 0.065f), new Vector3(0.5f, 1.62f, 0.065f), new Vector3(0.5f, 2.18f, 0.065f));
            mb.sub = 2; mb.Box(new Vector3(-0.15f, 1.9f, 0.125f), new Vector3(1.1f, 0.06f, 0.02f));
            mb.Box(new Vector3(-0.15f, 1.9f, 0.065f), new Vector3(1.3f, 0.42f, 0.02f));
            return Finish(id, mb, null, null, M("WoodDark", "Yellow", "Black"), C(ColRecipe.Box(new Vector3(0, 1.15f, 0), new Vector3(0.2f, 2.3f, 0.2f))), 0f, 2.3f, 200f, 300f, 450f);
        }

        PropDef SignWarn(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0; mb.Box(new Vector3(0, 1.1f, 0), new Vector3(0.12f, 2.2f, 0.12f));
            mb.sub = 1;
            var save = mb.xf;
            mb.xf = Matrix4x4.TRS(new Vector3(0, 2.0f, 0.09f), Quaternion.Euler(0, 0, 45f), Vector3.one);
            mb.Box(Vector3.zero, new Vector3(0.92f, 0.92f, 0.05f));
            mb.sub = 2;
            mb.Box(new Vector3(0, 0, 0.03f), new Vector3(0.72f, 0.72f, 0.02f));
            mb.sub = 1;
            mb.Box(new Vector3(0, 0, 0.045f), new Vector3(0.62f, 0.62f, 0.02f));
            mb.sub = 2;
            mb.xf = save * Matrix4x4.TRS(new Vector3(0, 2.0f, 0.09f), Quaternion.identity, Vector3.one);
            mb.Box(new Vector3(0, 0.08f, 0.06f), new Vector3(0.09f, 0.34f, 0.02f)); mb.Box(new Vector3(0, -0.2f, 0.06f), new Vector3(0.09f, 0.09f, 0.02f));
            mb.xf = save;
            return Finish(id, mb, null, null, M("WoodDark", "Yellow", "Black"), C(ColRecipe.Box(new Vector3(0, 1.1f, 0), new Vector3(0.2f, 2.2f, 0.2f))), 0f, 2.5f, 200f, 300f, 450f);
        }

        PropDef PostAnchor(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0; mb.Box(new Vector3(0, 0.55f, 0), new Vector3(0.36f, 1.9f, 0.36f));
            mb.Box(new Vector3(0, 1.52f, 0), new Vector3(0.46f, 0.08f, 0.46f));
            mb.sub = 1;
            for (int i = 0; i < 10; i++)
            {
                float a = i / 10f * Mathf.PI * 2f;
                mb.Box(new Vector3(Mathf.Cos(a) * 0.15f, 1.0f + Mathf.Sin(a) * 0.15f, 0.2f), new Vector3(0.07f, 0.07f, 0.07f));
            }
            return Finish(id, mb, null, null, M("Wood", "MetalDark"), C(ColRecipe.Box(new Vector3(0, 0.75f, 0), new Vector3(0.4f, 1.6f, 0.4f))), 0f, 1.5f, 200f, 300f, 450f);
        }

        PropDef Barrel(string id, string color)
        {
            var mb = new MeshBuilder();
            mb.Cylinder(Vector3.zero, 0.29f, 0.29f, 0.88f, 10, true, true);
            mb.sub = 1; mb.Cylinder(new Vector3(0, 0.22f, 0), 0.3f, 0.3f, 0.05f, 10, false, false); mb.Cylinder(new Vector3(0, 0.6f, 0), 0.3f, 0.3f, 0.05f, 10, false, false);
            return Finish(id, mb, null, null, M(color, "MetalDark"), C(ColRecipe.Capsule(new Vector3(0, 0.44f, 0), 0.29f, 0.88f)), 90f, 0.9f, 120f, 200f, 300f);
        }

        PropDef Crate(string id)
        {
            var mb = new MeshBuilder();
            mb.Box(new Vector3(0, 0.45f, 0), new Vector3(0.9f, 0.9f, 0.9f));
            mb.sub = 1;
            foreach (var sx in new[] { -1f, 1f }) foreach (var sz in new[] { -1f, 1f }) mb.Box(new Vector3(sx * 0.43f, 0.45f, sz * 0.43f), new Vector3(0.1f, 0.92f, 0.1f));
            mb.Box(new Vector3(0, 0.88f, 0), new Vector3(0.92f, 0.06f, 0.92f)); mb.Box(new Vector3(0, 0.02f, 0), new Vector3(0.92f, 0.06f, 0.92f));
            return Finish(id, mb, null, null, M("Planks", "WoodDark"), C(ColRecipe.Box(new Vector3(0, 0.45f, 0), new Vector3(0.9f, 0.9f, 0.9f))), 60f, 0.9f, 120f, 200f, 300f);
        }

        PropDef Tent(string id)
        {
            var mb = new MeshBuilder();
            float w = 1.5f, d = 1.6f, h = 1.7f;
            mb.QuadDouble(new Vector3(-w, 0, d), new Vector3(0, h, d), new Vector3(0, h, -d), new Vector3(-w, 0, -d));
            mb.QuadDouble(new Vector3(0, h, d), new Vector3(w, 0, d), new Vector3(w, 0, -d), new Vector3(0, h, -d));
            mb.Tri(new Vector3(-w, 0, d), new Vector3(w, 0, d), new Vector3(0, h, d)); mb.Tri(new Vector3(0, h, -d), new Vector3(w, 0, -d), new Vector3(-w, 0, -d));
            mb.sub = 1; mb.Box(new Vector3(0, 0.02f, 0), new Vector3(2.9f, 0.04f, 3.1f));
            return Finish(id, mb, null, null, M("Canvas", "Black"), C(ColRecipe.Box(new Vector3(0, 0.8f, 0), new Vector3(2.6f, 1.6f, 3f))), 0f, 1.7f, 200f, 300f, 450f);
        }

        PropDef Fence(string id)
        {
            var mb = new MeshBuilder();
            for (int i = 0; i < 2; i++) mb.Box(new Vector3(-1.5f + i * 3f, 0.6f, 0), new Vector3(0.14f, 1.2f, 0.14f));
            mb.Box(new Vector3(0, 0.95f, 0), new Vector3(3.1f, 0.1f, 0.06f)); mb.Box(new Vector3(0, 0.55f, 0), new Vector3(3.1f, 0.1f, 0.06f));
            return Finish(id, mb, null, null, M("Wood"), C(ColRecipe.Box(new Vector3(0, 0.6f, 0), new Vector3(3.1f, 1.2f, 0.18f))), 0f, 1.2f, 150f, 250f, 400f);
        }

        PropDef MarkerPost(string id, string color)
        {
            var mb = new MeshBuilder();
            mb.Box(new Vector3(0, 0.9f, 0), new Vector3(0.12f, 1.8f, 0.12f));
            mb.sub = 1; mb.Box(new Vector3(0, 1.82f, 0), new Vector3(0.18f, 0.22f, 0.18f));
            return Finish(id, mb, null, null, M("WoodDark", color), C(ColRecipe.Box(new Vector3(0, 0.9f, 0), new Vector3(0.16f, 1.8f, 0.16f))), 0f, 1.9f, 120f, 200f, 300f);
        }

        PropDef DepthPole(string id)
        {
            var mb = new MeshBuilder();
            for (int i = 0; i < 8; i++)
            {
                mb.sub = i % 2;
                mb.Cylinder(new Vector3(0, i * 0.25f, 0), 0.05f, 0.05f, 0.25f, 6, i == 7, false);
            }
            mb.sub = 1; mb.Box(new Vector3(0, 0.03f, 0), new Vector3(0.4f, 0.06f, 0.4f));
            return Finish(id, mb, null, null, M("White", "Red"), C(ColRecipe.Capsule(new Vector3(0, 1f, 0), 0.06f, 2f)), 0f, 2f, 120f, 200f, 300f);
        }

        PropDef DistancePole(string id)
        {
            var mb = new MeshBuilder();
            mb.Cylinder(Vector3.zero, 0.05f, 0.05f, 1.3f, 6, false, false);
            mb.sub = 1; mb.Cylinder(new Vector3(0, 1.3f, 0), 0.055f, 0.055f, 0.2f, 6, true, false); mb.Cylinder(new Vector3(0, 0.9f, 0), 0.055f, 0.055f, 0.1f, 6, false, false);
            return Finish(id, mb, null, null, M("White", "Black"), C(ColRecipe.Capsule(new Vector3(0, 0.75f, 0), 0.06f, 1.5f)), 0f, 1.5f, 120f, 200f, 300f);
        }

        PropDef Cone(string id)
        {
            var mb = new MeshBuilder();
            mb.Cylinder(Vector3.zero, 0.21f, 0.04f, 0.58f, 8, false, false);
            mb.sub = 1; mb.Cylinder(new Vector3(0, 0.22f, 0), 0.14f, 0.1f, 0.14f, 8, false, false); mb.Box(new Vector3(0, 0.015f, 0), new Vector3(0.42f, 0.03f, 0.42f));
            return Finish(id, mb, null, null, M("Orange", "White"), C(ColRecipe.Capsule(new Vector3(0, 0.3f, 0), 0.2f, 0.6f)), 4f, 0.6f, 100f, 160f, 250f);
        }

        PropDef Tank(string id)
        {
            var mb = new MeshBuilder();
            mb.CylinderAxis(new Vector3(0, 1.3f, 0), Vector3.forward, 6f, 1.15f, 1.15f, 12, true);
            mb.sub = 1; mb.Box(new Vector3(0, 0.2f, 1.8f), new Vector3(1.8f, 0.4f, 0.4f)); mb.Box(new Vector3(0, 0.2f, -1.8f), new Vector3(1.8f, 0.4f, 0.4f));
            return Finish(id, mb, null, null, M("Green", "Metal"), C(ColRecipe.Capsule(new Vector3(0, 1.3f, 0), 1.15f, 6f, 2)), 0f, 2.5f, 300f, 450f, 700f);
        }

        PropDef WoodPile(string id)
        {
            var mb = new MeshBuilder();
            mb.sub = 0;
            for (int row = 0; row < 4; row++)
                for (int i = 0; i < 6 - row; i++)
                    mb.CylinderAxis(new Vector3(-1.2f + i * 0.42f + row * 0.21f, 0.2f + row * 0.36f, 0), Vector3.forward, 2.2f, 0.19f, 0.19f, 6, true, 1);
            return Finish(id, mb, null, null, M("Bark", "LogEnd"), C(ColRecipe.Box(new Vector3(0, 0.7f, 0), new Vector3(2.6f, 1.4f, 2.2f))), 0f, 1.4f, 100f, 180f, 280f);
        }
    }
}
