using UnityEngine;

namespace MudRunner.Vehicles
{
    /// <summary>Builds drivable vehicles. Primitive stand-ins are used for tests and until a Blender-authored prefab exists.</summary>
    public static class VehicleFactory
    {
        /// <summary>
        /// Create a vehicle: uses the Blender-authored prefab Resources/VehiclePrefabs/&lt;definition name&gt; when it exists
        /// (built by the editor tool VehiclePrefabBuilder), otherwise a primitive stand-in with identical physics.
        /// </summary>
        public static Vehicle Create(VehicleDefinition def, Vector3 position, Quaternion rotation)
        {
            var prefab = Resources.Load<GameObject>("VehiclePrefabs/" + def.name);
            if (prefab == null) return CreatePrimitive(def, position, rotation);
            var go = Object.Instantiate(prefab, position, rotation);
            go.name = def.displayName;
            if (go.GetComponent<Rigidbody>() == null) go.AddComponent<Rigidbody>();
            var veh = go.GetComponent<Vehicle>() ?? go.AddComponent<Vehicle>();
            veh.Initialize(def);
            var binder = go.GetComponent<VehicleVisualBinder>();
            if (binder != null) binder.Bind(veh);
            return veh;
        }

        /// <summary>Box body + cylinder wheels (visual only). Fully functional physics.</summary>
        public static Vehicle CreatePrimitive(VehicleDefinition def, Vector3 position, Quaternion rotation, bool withVisuals = true)
        {
            var go = new GameObject(def.displayName + " (primitive)");
            go.transform.SetPositionAndRotation(position, rotation);
            var rb = go.AddComponent<Rigidbody>();
            var veh = go.AddComponent<Vehicle>();

            var col = go.AddComponent<BoxCollider>();
            col.size = def.bodySize; col.center = def.bodyCenter;
            col.sharedMaterial = new PhysicsMaterial("VehicleBody") { dynamicFriction = 0.1f, staticFriction = 0.1f, frictionCombine = PhysicsMaterialCombine.Minimum, bounciness = 0f };

            if (def.isTrailer)
            {
                // log stakes along both sides of the deck
                float deckTop = def.bodyCenter.y + def.bodySize.y * 0.5f;
                foreach (float z in new[] { -3.1f, -1.2f, 0.7f, 2.2f })
                    foreach (float sx in new[] { -1f, 1f })
                    {
                        var st = go.AddComponent<BoxCollider>();
                        st.size = new Vector3(0.12f, 1.0f, 0.12f); st.center = new Vector3(sx * 1.14f, deckTop + 0.5f, z);
                        st.sharedMaterial = col.sharedMaterial;
                        if (withVisuals)
                        {
                            var vis0 = GameObject.CreatePrimitive(PrimitiveType.Cube); Object.Destroy(vis0.GetComponent<Collider>());
                            vis0.transform.SetParent(go.transform, false); vis0.transform.localPosition = st.center; vis0.transform.localScale = st.size;
                            SetColor(vis0, new Color(0.35f, 0.25f, 0.12f));
                        }
                    }
            }

            Transform[] vis = null;
            if (withVisuals)
            {
                var body = GameObject.CreatePrimitive(PrimitiveType.Cube);
                body.name = "BodyVisual";
                Object.Destroy(body.GetComponent<Collider>());
                body.transform.SetParent(go.transform, false);
                body.transform.localPosition = def.bodyCenter;
                body.transform.localScale = def.bodySize;
                SetColor(body, new Color(0.75f, 0.45f, 0.1f));

                vis = new Transform[def.axles.Length * 2];
                for (int a = 0; a < def.axles.Length; a++)
                    for (int s = 0; s < 2; s++)
                    {
                        var ax = def.axles[a];
                        var pivot = new GameObject("Wheel_" + ax.name + (s == 0 ? "_L" : "_R")).transform;
                        pivot.SetParent(go.transform, false);
                        var cyl = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                        Object.Destroy(cyl.GetComponent<Collider>());
                        cyl.transform.SetParent(pivot, false);
                        cyl.transform.localRotation = Quaternion.Euler(0f, 0f, 90f);
                        cyl.transform.localScale = new Vector3(ax.tire.radius * 2f, ax.tire.width * 0.5f, ax.tire.radius * 2f);
                        SetColor(cyl, new Color(0.08f, 0.08f, 0.08f));
                        vis[a * 2 + s] = pivot;
                    }
            }
            veh.Initialize(def);
            veh.wheelVisuals = vis;
            if (vis != null)
                for (int i = 0; i < vis.Length; i++) vis[i].position = go.transform.TransformPoint(veh.wheels[i].anchorLocal) - go.transform.up * veh.wheels[i].restLength;
            return veh;
        }

        static void SetColor(GameObject go, Color c)
        {
            var r = go.GetComponent<Renderer>();
            if (r == null) return;
            var sh = Shader.Find("Universal Render Pipeline/Lit");
            if (sh == null) return;
            var m = new Material(sh);
            m.SetColor("_BaseColor", c);
            r.sharedMaterial = m;
        }
    }
}
