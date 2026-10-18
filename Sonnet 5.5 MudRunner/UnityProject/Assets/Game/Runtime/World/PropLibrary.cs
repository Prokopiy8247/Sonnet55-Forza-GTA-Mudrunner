using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.WorldGen
{
    public enum ColShape : byte { None = 0, Box, Capsule, Sphere }

    /// <summary>Collider description in prop-local space. Box: size = full size. Capsule: size.x = radius, size.y = height, axis 0/1/2 = X/Y/Z. Sphere: size.x = radius.</summary>
    public struct ColRecipe
    {
        public ColShape shape; public Vector3 center; public Vector3 size; public int axis;
        public static ColRecipe Box(Vector3 center, Vector3 size) { return new ColRecipe { shape = ColShape.Box, center = center, size = size }; }
        public static ColRecipe Capsule(Vector3 center, float radius, float height, int axis = 1) { return new ColRecipe { shape = ColShape.Capsule, center = center, size = new Vector3(radius, height, 0), axis = axis }; }
        public static ColRecipe Sphere(Vector3 center, float radius) { return new ColRecipe { shape = ColShape.Sphere, center = center, size = new Vector3(radius, 0, 0) }; }
    }

    /// <summary>Everything the world needs to draw / collide one kind of prop: meshes (LOD0..2), materials per submesh, collider recipe.</summary>
    public sealed class PropDef
    {
        public string id;
        public Mesh[] lods = new Mesh[3];
        public float lod0Dist = 60f, lod1Dist = 160f, maxDist = 520f;
        public Material[] materials;
        public ColRecipe[] colliders = new ColRecipe[0];
        public float mass;                  // > 0: dynamic rigid body when spawned as a GameObject
        public bool castShadows = true;
        public Bounds bounds;
        public float height = 1f;           // nominal height (for anchors / placement)
        public GameObject prefab;           // set by art libraries: instantiate this instead of building from mesh
        public int SubMeshCount => lods[0] != null ? lods[0].subMeshCount : 1;
    }

    /// <summary>
    /// Source of prop meshes. <c>Get(id)</c> understands optional parameters after a colon, e.g. "bridge_intact:24" (span length in metres).
    /// Swapping to Blender-authored art is a one-file change: assign <see cref="PropLibraries.Current"/> (see <see cref="ArtPropLibrary"/>).
    /// </summary>
    public interface IPropLibrary
    {
        PropDef Get(string id);
    }

    public static class PropLibraries
    {
        static IPropLibrary current;

        /// <summary>The active library: art props where they exist, procedural stand-ins otherwise.</summary>
        public static IPropLibrary Current
        {
            get { if (current == null) current = new ArtPropLibrary(new ProceduralPropLibrary()); return current; }
            set { current = value; }
        }
    }

    // ====================================================================== materials

    /// <summary>Flat-colour URP/Lit materials for the stand-in props (art libraries bring their own).</summary>
    public static class PropMaterials
    {
        static readonly Dictionary<string, Material> cache = new Dictionary<string, Material>();

        struct Spec { public Color c; public float smooth, metal; public bool cullOff; public Color emit; }
        static Spec S(float r, float g, float b, float sm = 0.15f, float me = 0f, bool cullOff = false) { return new Spec { c = new Color(r, g, b), smooth = sm, metal = me, cullOff = cullOff }; }

        static readonly Dictionary<string, Spec> specs = new Dictionary<string, Spec>
        {
            { "Bark", S(0.16f, 0.105f, 0.07f, 0.1f) }, { "Foliage", S(0.075f, 0.23f, 0.09f, 0.1f, 0f, true) }, { "FoliageB", S(0.095f, 0.26f, 0.10f, 0.1f, 0f, true) },
            { "FoliageC", S(0.065f, 0.20f, 0.09f, 0.1f, 0f, true) }, { "Birch", S(0.62f, 0.60f, 0.55f, 0.15f) }, { "BirchLeaf", S(0.22f, 0.40f, 0.10f, 0.1f, 0f, true) },
            { "Dead", S(0.30f, 0.27f, 0.23f, 0.05f) }, { "Rock", S(0.33f, 0.32f, 0.30f, 0.25f) }, { "RockDark", S(0.22f, 0.22f, 0.21f, 0.25f) },
            { "Wood", S(0.38f, 0.26f, 0.14f, 0.1f) }, { "WoodDark", S(0.22f, 0.15f, 0.09f, 0.1f) }, { "WoodGrey", S(0.34f, 0.31f, 0.27f, 0.05f) },
            { "LogEnd", S(0.55f, 0.40f, 0.22f, 0.1f) }, { "Metal", S(0.45f, 0.46f, 0.48f, 0.55f, 0.8f) }, { "MetalDark", S(0.10f, 0.10f, 0.11f, 0.45f, 0.7f) },
            { "Rust", S(0.35f, 0.16f, 0.07f, 0.2f, 0.4f) }, { "Roof", S(0.27f, 0.15f, 0.11f, 0.35f, 0.4f) }, { "RoofGreen", S(0.12f, 0.25f, 0.18f, 0.35f, 0.4f) },
            { "Concrete", S(0.48f, 0.48f, 0.46f, 0.1f) }, { "Canvas", S(0.35f, 0.38f, 0.22f, 0.05f) }, { "CanvasOrange", S(0.65f, 0.32f, 0.08f, 0.05f) },
            { "Hazard", S(0.85f, 0.65f, 0.05f, 0.3f) }, { "Black", S(0.03f, 0.03f, 0.03f, 0.3f) }, { "White", S(0.85f, 0.85f, 0.82f, 0.25f) },
            { "Red", S(0.62f, 0.07f, 0.06f, 0.4f) }, { "Green", S(0.12f, 0.35f, 0.16f, 0.35f) }, { "Orange", S(0.85f, 0.35f, 0.05f, 0.4f) },
            { "Blue", S(0.10f, 0.25f, 0.62f, 0.4f) }, { "Yellow", S(0.9f, 0.78f, 0.1f, 0.35f) }, { "Reed", S(0.35f, 0.42f, 0.16f, 0.1f, 0f, true) },
            { "Moss", S(0.09f, 0.16f, 0.05f, 0.02f) }, { "Bush", S(0.10f, 0.26f, 0.09f, 0.1f, 0f, true) }, { "Glass", S(0.16f, 0.22f, 0.26f, 0.8f) },
            { "Stone", S(0.40f, 0.39f, 0.36f, 0.2f) }, { "Planks", S(0.45f, 0.33f, 0.19f, 0.1f) }, { "PlanksOld", S(0.33f, 0.27f, 0.20f, 0.05f) },
            { "Door", S(0.12f, 0.10f, 0.09f, 0.1f) },
        };

        public static Material Get(string key)
        {
            if (cache.TryGetValue(key, out var m) && m != null) return m;
            if (!specs.TryGetValue(key, out var sp)) sp = S(0.5f, 0.5f, 0.5f);
            Shader sh = Shader.Find("Universal Render Pipeline/Lit");
            if (sh == null) sh = Shader.Find("Standard");
            if (sh == null) sh = Shader.Find("Sprites/Default");
            m = new Material(sh) { name = "MR_Prop_" + key, enableInstancing = true, hideFlags = HideFlags.DontSave };
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", sp.c);
            if (m.HasProperty("_Color")) m.SetColor("_Color", sp.c);
            if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", sp.smooth);
            if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", sp.metal);
            if (sp.cullOff && m.HasProperty("_Cull")) m.SetFloat("_Cull", 0f);
            cache[key] = m;
            return m;
        }

        public static Material[] Get(params string[] keys)
        {
            var arr = new Material[keys.Length];
            for (int i = 0; i < keys.Length; i++) arr[i] = Get(keys[i]);
            return arr;
        }
    }

    // ====================================================================== art library wrapper

    /// <summary>
    /// Uses Blender-authored models (Assets/Game/Art/Props_*, Resources "Props/&lt;id&gt;") where they exist and falls back to the
    /// procedural stand-ins otherwise. This is the single place that decides where props come from.
    /// </summary>
    public sealed class ArtPropLibrary : IPropLibrary
    {
        readonly IPropLibrary fallback;
        readonly Dictionary<string, PropDef> cache = new Dictionary<string, PropDef>();
        public static readonly Dictionary<string, string[]> NameHints = new Dictionary<string, string[]>
        {
            { "spruce_a", new[] { "Nat_Spruce_A", "Nat_Spruce_Tall", "Nat_Spruce" } }, { "spruce_b", new[] { "Nat_Spruce_B", "Nat_Spruce_Medium" } }, { "spruce_c", new[] { "Nat_Spruce_C", "Nat_Spruce_Young" } },
            { "birch", new[] { "Nat_Birch" } }, { "deadtree", new[] { "Nat_DeadTree", "Nat_Dead" } },
            { "rock_s", new[] { "Nat_Rock_S", "Nat_Rock_01", "Nat_RockSmall" } }, { "rock_m", new[] { "Nat_Rock_M", "Nat_Rock_02", "Nat_RockMedium" } },
            { "rock_l", new[] { "Nat_Rock_L", "Nat_Rock_03", "Nat_RockLarge" } }, { "rock_slab", new[] { "Nat_Rock_Slab", "Nat_Rock_04" } },
            { "log_long", new[] { "Nat_Log_Long", "Nat_LogLong" } }, { "log_short", new[] { "Nat_Log_Short", "Nat_LogShort" } }, { "stump", new[] { "Nat_Stump" } },
            { "reed", new[] { "Nat_Reed" } }, { "bush", new[] { "Nat_Bush" } },
            { "cabin", new[] { "Str_Cabin" } }, { "garage", new[] { "Str_Garage", "Str_Workshop" } }, { "fuel_station", new[] { "Str_FuelStation", "Str_Fuel" } },
            { "watchtower", new[] { "Str_Watchtower" } }, { "bridge_intact", new[] { "Str_Bridge_Intact", "Str_Bridge" } }, { "bridge_broken", new[] { "Str_Bridge_Broken" } },
            { "sign_arrow", new[] { "Str_Sign_Arrow" } }, { "sign_warn", new[] { "Str_Sign_Warn" } }, { "post_anchor", new[] { "Str_Post_Anchor", "Str_AnchorPost" } },
            { "barrel", new[] { "Str_Barrel" } }, { "crate", new[] { "Str_Crate" } }, { "tent", new[] { "Str_Tent" } }, { "fence", new[] { "Str_Fence" } },
        };

        public ArtPropLibrary(IPropLibrary fallback) { this.fallback = fallback; }

        public PropDef Get(string id)
        {
            if (cache.TryGetValue(id, out var d) && d != null && d.lods[0] != null) return d;
            d = TryArt(id) ?? fallback.Get(id);
            cache[id] = d;
            return d;
        }

        PropDef TryArt(string id)
        {
            string key = id; int colon = id.IndexOf(':'); if (colon >= 0) return null;   // parametrised props (bridges) stay procedural
            GameObject prefab = Resources.Load<GameObject>("Props/" + key);
#if UNITY_EDITOR
            if (prefab == null && NameHints.TryGetValue(key, out var hints))
            {
                foreach (var h in hints)
                {
                    var guids = UnityEditor.AssetDatabase.FindAssets(h + " t:Model", new[] { "Assets/Game/Art" });
                    foreach (var g in guids)
                    {
                        string path = UnityEditor.AssetDatabase.GUIDToAssetPath(g);
                        if (!path.Contains("/" + h + "/") && !System.IO.Path.GetFileNameWithoutExtension(path).Equals(h, StringComparison.OrdinalIgnoreCase)) continue;
                        prefab = UnityEditor.AssetDatabase.LoadAssetAtPath<GameObject>(path);
                        if (prefab != null) break;
                    }
                    if (prefab != null) break;
                }
            }
#endif
            if (prefab == null) return null;
            var mf = prefab.GetComponentInChildren<MeshFilter>();
            var mr = prefab.GetComponentInChildren<MeshRenderer>();
            if (mf == null || mr == null || mf.sharedMesh == null) return null;
            var fb = fallback.Get(id);
            var def = new PropDef
            {
                id = id, lods = new[] { mf.sharedMesh, mf.sharedMesh, mf.sharedMesh }, materials = mr.sharedMaterials,
                colliders = fb.colliders, mass = fb.mass, castShadows = fb.castShadows, bounds = mf.sharedMesh.bounds, height = fb.height,
                lod0Dist = fb.lod0Dist, lod1Dist = fb.lod1Dist, maxDist = fb.maxDist, prefab = prefab,
            };
            // look for LOD meshes by name (<Mesh>_LOD1/_LOD2) next to the main mesh
            foreach (var m in prefab.GetComponentsInChildren<MeshFilter>(true))
            {
                if (m.sharedMesh == null) continue;
                if (m.name.EndsWith("_LOD1")) def.lods[1] = m.sharedMesh;
                else if (m.name.EndsWith("_LOD2")) def.lods[2] = m.sharedMesh;
            }
            return def;
        }
    }
}
