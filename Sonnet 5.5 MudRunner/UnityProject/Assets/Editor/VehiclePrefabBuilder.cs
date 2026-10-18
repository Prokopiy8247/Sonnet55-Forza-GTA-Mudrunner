using System.Collections.Generic;
using System.IO;
using MudRunner.Vehicles;
using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Bakes the VehicleDefinition assets (Assets/Resources/Vehicles) and builds drivable prefabs (Assets/Resources/VehiclePrefabs)
    /// from the Blender FBX files described in Docs/ART_SPEC.md:  physics root + Rigidbody + Vehicle + binder, wheels found BY NAME,
    /// COL_* proxies turned into BoxColliders, tyre/axle numbers measured from the model, LODGroup from *_LOD1/_LOD2 nodes.
    ///   Unity.exe -batchmode -nographics -projectPath ... -executeMethod MudRunner.EditorTools.VehiclePrefabBuilder.BuildAllFromCli -quit
    /// </summary>
    public static class VehiclePrefabBuilder
    {
        const string DefFolder = "Assets/Resources/Vehicles";
        const string PrefabFolder = "Assets/Resources/VehiclePrefabs";

        struct Entry { public string key, name, fbx; public System.Func<VehicleDefinition> factory; }

        static readonly Entry[] Entries =
        {
            new Entry { key = "scout", name = "Scout", fbx = "Assets/Game/Art/Vehicles/Scout/Scout.fbx", factory = VehicleDefinition.CreateScout },
            new Entry { key = "utility", name = "Utility", fbx = "Assets/Game/Art/Vehicles/Utility/Utility.fbx", factory = VehicleDefinition.CreateUtility },
            new Entry { key = "hauler", name = "Hauler", fbx = "Assets/Game/Art/Vehicles/Hauler/Hauler.fbx", factory = VehicleDefinition.CreateHauler },
            new Entry { key = "logtrailer", name = "LogTrailer", fbx = "Assets/Game/Art/Trailers/LogTrailer/LogTrailer.fbx", factory = VehicleDefinition.CreateLogTrailer },
        };

        [MenuItem("MudRunner/Build/Vehicle Definitions + Prefabs")]
        public static void BuildAll()
        {
            Directory.CreateDirectory(DefFolder); Directory.CreateDirectory(PrefabFolder);
            MaterialLibrary.BuildAll();
            foreach (var e in Entries)
                if (File.Exists(e.fbx)) AssetDatabase.ImportAsset(e.fbx, ImportAssetOptions.ForceUpdate | ImportAssetOptions.ForceSynchronousImport);   // re-run ModelPostprocessor now that the MR_* library exists
            foreach (var e in Entries)
            {
                var def = BakeDefinition(e);
                if (!File.Exists(e.fbx)) { Debug.Log("[MudRunner] prefab skipped (no FBX yet): " + e.fbx); continue; }
                try { BuildPrefab(e, def); }
                catch (System.Exception ex) { Debug.LogError("[MudRunner] prefab build failed for " + e.name + ": " + ex); }
            }
            AssetDatabase.SaveAssets(); AssetDatabase.Refresh();
        }

        public static void BuildAllFromCli() { BuildAll(); }

        static VehicleDefinition BakeDefinition(Entry e)
        {
            string path = DefFolder + "/" + e.key + ".asset";
            var existing = AssetDatabase.LoadAssetAtPath<VehicleDefinition>(path);
            var fresh = e.factory();
            if (existing == null) { AssetDatabase.CreateAsset(fresh, path); existing = fresh; }
            else { EditorUtility.CopySerialized(fresh, existing); Object.DestroyImmediate(fresh); }
            existing.name = e.name;
            EditorUtility.SetDirty(existing);
            return existing;
        }

        // ------------------------------------------------------------------ prefab

        static GameObject BuildPrefab(Entry e, VehicleDefinition def)
        {
            var fbx = AssetDatabase.LoadAssetAtPath<GameObject>(e.fbx);
            var root = new GameObject(e.name);
            var model = (GameObject)PrefabUtility.InstantiatePrefab(fbx);
            model.transform.SetParent(root.transform, false);
            model.name = "Model";
            var all = new Dictionary<string, Transform>();
            foreach (var t in model.GetComponentsInChildren<Transform>(true)) all[ModelNames.Norm(t.name)] = t;

            // ---- wheels by name -> axle-major, left then right
            var visuals = new List<Transform>();
            int axles = def.axles.Length;
            for (int a = 0; a < axles; a++)
            {
                string ax = a == 0 ? "F" : (a == axles - 1 ? "R" : "M");
                foreach (string side in new[] { "L", "R" })
                {
                    string wn = "Wheel_" + ax + side;
                    if (!all.TryGetValue(wn, out var w)) { Debug.LogWarning("[MudRunner] " + e.name + ": missing " + wn); visuals.Add(null); continue; }
                    visuals.Add(w);
                }
            }
            MeasureWheels(root.transform, visuals, def);

            // LOD wheel meshes ride with their wheel pivot
            for (int i = 0; i < visuals.Count; i++)
            {
                if (visuals[i] == null) continue;
                foreach (var suffix in new[] { "_LOD1", "_LOD2" })
                    if (all.TryGetValue(ModelNames.Norm(visuals[i].name) + suffix, out var lod)) lod.SetParent(visuals[i], true);
            }
            // leaf packs / hub pieces named Hub_* stay where they are; the runtime SuspensionVisuals moves them

            // ---- per-vehicle paint (Docs/ART_SPEC.md: Unity overrides the MR_Paint colour per vehicle)
            ApplyPaint(model, e.name);

            // ---- collision proxies
            var colRoot = new GameObject("Collision"); colRoot.transform.SetParent(root.transform, false); colRoot.layer = GameLayers.VehicleBody;
            var pm = AssetDatabase.LoadAssetAtPath<PhysicsMaterial>("Assets/Game/Materials/VehicleBody.physicMaterial");
            if (pm == null)
            {
                pm = new PhysicsMaterial("VehicleBody") { dynamicFriction = 0.1f, staticFriction = 0.1f, frictionCombine = PhysicsMaterialCombine.Minimum, bounciness = 0f };
                AssetDatabase.CreateAsset(pm, "Assets/Game/Materials/VehicleBody.physicMaterial");
            }
            Bounds union = new Bounds(); bool any = false;
            var cols = new List<Transform>();
            foreach (var kv in all) if (kv.Key.StartsWith("COL_")) cols.Add(kv.Value);
            foreach (var c in cols)
            {
                var mf = c.GetComponent<MeshFilter>();
                if (mf == null || mf.sharedMesh == null) continue;
                var b = LocalBounds(root.transform, c, mf.sharedMesh.bounds);
                var go = new GameObject(c.name); go.transform.SetParent(colRoot.transform, false); go.layer = GameLayers.VehicleBody;
                var bc = go.AddComponent<BoxCollider>(); bc.center = b.center; bc.size = b.size; bc.sharedMaterial = pm;
                if (!any) { union = b; any = true; } else union.Encapsulate(b);
                Object.DestroyImmediate(c.gameObject);
            }
            if (any)
            {
                def.bodySize = union.size; def.bodyCenter = union.center;
                def.bodyPoints = BodyPointsFrom(union, def);
            }
            else Debug.LogWarning("[MudRunner] " + e.name + ": no COL_ proxies, using definition box");

            // ---- engine intake (snorkel) -> intake height and rated fording depth come from the model
            if (all.TryGetValue("Intake", out var intakeT))
            {
                def.intakeLocal = root.transform.InverseTransformPoint(intakeT.position);
                def.fordingDepth = VehicleDefinition.ComputeFordingRating(def);
            }
            if (all.TryGetValue("Anchor_Hitch", out var hitchT)) def.hitchLocal = root.transform.InverseTransformPoint(hitchT.position);

            // ---- LODs
            BuildLodGroup(model);

            // ---- components
            foreach (var t in root.GetComponentsInChildren<Transform>(true)) if (t.gameObject.layer == 0) t.gameObject.layer = GameLayers.VehicleBody;
            var rb = root.AddComponent<Rigidbody>(); rb.mass = def.mass;
            var veh = root.AddComponent<Vehicle>(); veh.def = def;
            var binder = root.AddComponent<VehicleVisualBinder>(); binder.wheelVisuals = visuals.ToArray();

            EditorUtility.SetDirty(def);
            string path = PrefabFolder + "/" + e.name + ".prefab";
            var prefab = PrefabUtility.SaveAsPrefabAsset(root, path);
            Object.DestroyImmediate(root);
            Debug.Log("[MudRunner] prefab built: " + path + " (wheels " + visuals.Count + ", collision boxes " + cols.Count + ", body " + def.bodySize + ")");
            return prefab;
        }

        static readonly Dictionary<string, (Color primary, Color secondary)> PaintColors = new Dictionary<string, (Color, Color)>
        {
            { "Scout", (new Color(0.30f, 0.34f, 0.15f), new Color(0.07f, 0.07f, 0.07f)) },      // olive / black
            { "Utility", (new Color(0.62f, 0.24f, 0.08f), new Color(0.12f, 0.12f, 0.13f)) },    // rust orange / charcoal
            { "Hauler", (new Color(0.10f, 0.26f, 0.14f), new Color(0.72f, 0.58f, 0.05f)) },     // dark green / hazard yellow
            { "LogTrailer", (new Color(0.30f, 0.20f, 0.12f), new Color(0.10f, 0.10f, 0.11f)) },
        };

        static void ApplyPaint(GameObject model, string vehicleName)
        {
            if (!PaintColors.TryGetValue(vehicleName, out var col)) return;
            System.IO.Directory.CreateDirectory(MaterialLibrary.Folder + "/Vehicles");
            Material Variant(string baseName, Color c)
            {
                string path = MaterialLibrary.Folder + "/Vehicles/" + vehicleName + "_" + baseName + ".mat";
                var m = AssetDatabase.LoadAssetAtPath<Material>(path);
                var src = AssetDatabase.LoadAssetAtPath<Material>(MaterialLibrary.Folder + "/" + baseName + ".mat");
                if (src == null) return null;
                if (m == null) { m = new Material(src); AssetDatabase.CreateAsset(m, path); }
                else { m.shader = src.shader; m.CopyPropertiesFromMaterial(src); }
                m.SetColor("_BaseColor", c);
                EditorUtility.SetDirty(m);
                return m;
            }
            var prim = Variant("MR_Paint", col.primary); var sec = Variant("MR_PaintSecondary", col.secondary);
            foreach (var r in model.GetComponentsInChildren<Renderer>(true))
            {
                var mats = r.sharedMaterials; bool ch = false;
                for (int i = 0; i < mats.Length; i++)
                {
                    if (mats[i] == null) continue;
                    if (mats[i].name == "MR_Paint" && prim != null) { mats[i] = prim; ch = true; }
                    else if (mats[i].name == "MR_PaintSecondary" && sec != null) { mats[i] = sec; ch = true; }
                }
                if (ch) r.sharedMaterials = mats;
            }
        }

        static Bounds LocalBounds(Transform root, Transform t, Bounds meshBounds)
        {
            var c = meshBounds.center; var ex = meshBounds.extents;
            Vector3 mn = Vector3.one * float.MaxValue, mx = Vector3.one * float.MinValue;
            for (int i = 0; i < 8; i++)
            {
                var corner = c + new Vector3((i & 1) == 0 ? -ex.x : ex.x, (i & 2) == 0 ? -ex.y : ex.y, (i & 4) == 0 ? -ex.z : ex.z);
                var p = root.InverseTransformPoint(t.TransformPoint(corner));
                mn = Vector3.Min(mn, p); mx = Vector3.Max(mx, p);
            }
            var b = new Bounds(); b.SetMinMax(mn, mx); return b;
        }

        /// <summary>Hub position / tyre size taken from the model (data from the model wins over the factory numbers).</summary>
        static void MeasureWheels(Transform root, List<Transform> visuals, VehicleDefinition def)
        {
            for (int a = 0; a < def.axles.Length; a++)
            {
                var L = visuals[a * 2]; var R = visuals[a * 2 + 1];
                if (L == null || R == null) continue;
                var axle = def.axles[a];
                Vector3 pl = root.InverseTransformPoint(L.position), pr = root.InverseTransformPoint(R.position);
                axle.z = 0.5f * (pl.z + pr.z);
                axle.hubY = 0.5f * (pl.y + pr.y);
                axle.track = Mathf.Abs(pr.x - pl.x);
                var mf = L.GetComponent<MeshFilter>();
                if (mf != null && mf.sharedMesh != null)
                {
                    var b = LocalBounds(root, L, mf.sharedMesh.bounds);
                    axle.tire.radius = Mathf.Max(0.2f, 0.5f * Mathf.Max(b.size.y, b.size.z));
                    axle.tire.width = Mathf.Clamp(b.size.x, 0.15f, 1.0f);
                }
                axle.restLength = Mathf.Max(axle.restLength, 0.3f);
            }
        }

        static Vector4[] BodyPointsFrom(Bounds b, VehicleDefinition def)
        {
            var list = new List<Vector4>();
            Vector3 c = b.center, e = b.extents; float r = 0.12f;
            for (int ix = -1; ix <= 1; ix += 2)
                for (int iz = -1; iz <= 1; iz += 2)
                {
                    list.Add(new Vector4(c.x + ix * e.x, c.y - e.y, c.z + iz * e.z, r));
                    list.Add(new Vector4(c.x + ix * e.x, c.y + e.y, c.z + iz * e.z, r));
                }
            list.Add(new Vector4(c.x, c.y - e.y, c.z, r));
            list.Add(new Vector4(c.x, c.y - e.y, c.z + e.z * 0.5f, r));
            list.Add(new Vector4(c.x, c.y - e.y, c.z - e.z * 0.5f, r));
            return list.ToArray();
        }

        static void BuildLodGroup(GameObject model)
        {
            var lod0 = new List<Renderer>(); var lod1 = new List<Renderer>(); var lod2 = new List<Renderer>();
            foreach (var r in model.GetComponentsInChildren<Renderer>(true))
            {
                string n = ModelNames.Norm(r.name);
                if (n.EndsWith("_LOD1")) lod1.Add(r); else if (n.EndsWith("_LOD2")) lod2.Add(r);
                else if (n.EndsWith("_Billboard")) r.enabled = false;
                else lod0.Add(r);
            }
            if (lod1.Count == 0 && lod2.Count == 0) return;
            var g = model.AddComponent<LODGroup>();
            var lods = new List<LOD> { new LOD(0.28f, lod0.ToArray()) };
            if (lod1.Count > 0) lods.Add(new LOD(0.09f, lod1.ToArray()));
            if (lod2.Count > 0) lods.Add(new LOD(0.02f, lod2.ToArray()));
            g.SetLODs(lods.ToArray());
            g.RecalculateBounds();
        }
    }
}
