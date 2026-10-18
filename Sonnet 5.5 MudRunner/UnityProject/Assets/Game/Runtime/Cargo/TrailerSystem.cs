using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Cargo
{
    /// <summary>
    /// Trailer + cargo for the player's vehicle. A trailer is a normal <see cref="Vehicle"/> (own wheels, suspension, soil model,
    /// brakes, no engine) coupled to the towing vehicle with a ConfigurableJoint ball hitch (limits: yaw 75, pitch 20, roll 15 deg).
    /// Cargo items are loose rigid bodies resting on the deck: their weight reaches the trailer suspension through contact,
    /// so load raises sinkage, shifts the centre of mass and can tip or spill (cargo further than 8 m from the deck counts as lost).
    /// </summary>
    public sealed class TrailerSystem : MonoBehaviour
    {
        public static TrailerSystem Instance { get; private set; }

        public Vehicle Trailer { get; private set; }
        public Vehicle Tow { get; private set; }
        public ConfigurableJoint Hitch { get; private set; }
        public readonly List<Rigidbody> Cargo = new List<Rigidbody>();
        public readonly List<float> CargoValue = new List<float>();
        public bool HasTrailer => Trailer != null;
        public string CargoDescription { get; private set; } = "";
        public float CargoMass { get; private set; }
        public int CargoCount => Cargo.Count;
        public int CargoLostCount { get; private set; }
        public int CargoOnDeck { get; private set; }
        public float hitchYaw = 75f, hitchPitch = 20f, hitchRoll = 15f;

        static VehicleDefinition trailerDef;
        static PhysicsMaterial cargoMat;

        void Awake() { Instance = this; }
        void OnDestroy() { if (Instance == this) Instance = null; }

        public static TrailerSystem EnsureInstance()
        {
            if (Instance != null) return Instance;
            var go = new GameObject("TrailerSystem");
            var gm = GameManager.Instance;
            if (gm != null) go.transform.SetParent(gm.transform, false);
            return go.AddComponent<TrailerSystem>();
        }

        // ------------------------------------------------------------------ trailer

        public bool SpawnTrailerBehindPlayer()
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.Player == null) return false;
            return Attach(gm.Player);
        }

        public bool Attach(Vehicle tow)
        {
            if (tow == null || tow.def.isTrailer) return false;
            DetachTrailer(true);
            if (trailerDef == null) trailerDef = VehicleDefinition.CreateLogTrailer();
            Tow = tow;
            Vector3 hitchW = tow.transform.TransformPoint(tow.HitchLocal);
            Quaternion rot = tow.transform.rotation;
            Vector3 pos = hitchW - rot * trailerDef.drawbarLocal;
            var gs = Ground.GroundService.Instance;
            if (gs != null)
            {
                // place so the trailer wheels start just above ground
                float gy = gs.GroundHeight(pos.x, pos.z - 2f);
                pos.y = Mathf.Max(pos.y, gy + trailerDef.axles[0].tire.radius - trailerDef.axles[0].hubY + 0.2f);
            }
            var t = VehicleFactory.Create(trailerDef, pos, rot);
            t.towingVehicle = tow; tow.towedTrailer = t;
            Trailer = t;
            var rb = t.rb;
            // keep the hitch joint stable: more solver iterations on both bodies
            rb.solverIterations = 14; rb.solverVelocityIterations = 4;
            tow.rb.solverIterations = Mathf.Max(tow.rb.solverIterations, 14); tow.rb.solverVelocityIterations = Mathf.Max(tow.rb.solverVelocityIterations, 4);
            // physics layers: trailer collides with tow? no - they share a joint; ignore collisions between them
            foreach (var a in tow.GetComponentsInChildren<Collider>())
                foreach (var b in t.GetComponentsInChildren<Collider>()) Physics.IgnoreCollision(a, b, true);

            var j = t.gameObject.AddComponent<ConfigurableJoint>();
            j.connectedBody = tow.rb;
            j.autoConfigureConnectedAnchor = false;
            j.anchor = trailerDef.drawbarLocal;
            j.connectedAnchor = tow.HitchLocal;
            j.xMotion = j.yMotion = j.zMotion = ConfigurableJointMotion.Locked;
            j.angularXMotion = ConfigurableJointMotion.Limited;   // pitch
            j.angularYMotion = ConfigurableJointMotion.Limited;   // yaw
            j.angularZMotion = ConfigurableJointMotion.Limited;   // roll
            j.lowAngularXLimit = new SoftJointLimit { limit = -hitchPitch };
            j.highAngularXLimit = new SoftJointLimit { limit = hitchPitch };
            j.angularYLimit = new SoftJointLimit { limit = hitchYaw };
            j.angularZLimit = new SoftJointLimit { limit = hitchRoll };
            j.enableCollision = false;
            j.projectionMode = JointProjectionMode.PositionAndRotation;
            j.projectionDistance = 0.05f; j.projectionAngle = 5f;
            Hitch = j;
            EnsureDeck(t);
            return true;
        }

        Vector3 deckLocal;          // centre of the deck surface (trailer-local)
        bool deckFromModel;

        /// <summary>Blender trailers ship collision for the frame only; the deck, bunk stakes and an anti-roll lip are added here so cargo stays on.</summary>
        void EnsureDeck(Vehicle t)
        {
            var anchors = t.GetComponent<VehicleAnchors>();
            deckFromModel = anchors != null && anchors.cargo != null;
            deckLocal = deckFromModel ? t.transform.InverseTransformPoint(anchors.cargo.position)
                                      : new Vector3(0f, t.def.bodyCenter.y + t.def.bodySize.y * 0.5f, t.def.bodyCenter.z);
            if (!deckFromModel) return;    // primitive trailers already have deck + stakes
            var pm = new PhysicsMaterial("TrailerDeck") { dynamicFriction = 0.6f, staticFriction = 0.7f, frictionCombine = PhysicsMaterialCombine.Average };
            var go = new GameObject("DeckColliders"); go.transform.SetParent(t.transform, false); go.layer = GameLayers.VehicleBody;
            var deck = go.AddComponent<BoxCollider>(); deck.center = deckLocal - Vector3.up * 0.1f; deck.size = new Vector3(2.2f, 0.2f, 5.9f); deck.sharedMaterial = pm;
            foreach (float z in new[] { -2.7f, -0.8f, 1.1f, 2.6f })
                foreach (float sx in new[] { -1f, 1f })
                {
                    var st = go.AddComponent<BoxCollider>(); st.size = new Vector3(0.12f, 1.05f, 0.12f);
                    st.center = new Vector3(sx * 1.14f, deckLocal.y + 0.52f, deckLocal.z + z * 0.5f + (z > 0 ? 0.2f : 0f)); st.sharedMaterial = pm;
                }
        }

        public void DetachTrailer() { DetachTrailer(false); }

        public void DetachTrailer(bool destroy)
        {
            if (Hitch != null) Destroy(Hitch);
            Hitch = null;
            if (Tow != null) Tow.towedTrailer = null;
            if (Trailer != null)
            {
                Trailer.towingVehicle = null;
                if (destroy) { ClearCargo(); Destroy(Trailer.gameObject); }
            }
            if (destroy) Trailer = null;
        }

        void FixedUpdate()
        {
            if (Trailer == null) return;
            // surge brakes: trailer brakes with the tow vehicle's service brake and handbrake
            if (Tow != null)
            {
                var ti = Trailer.input;
                ti.brake = Mathf.Clamp01(Tow.brakeEff * 0.8f);
                ti.handbrake = Tow.input.handbrake;
                Trailer.input = ti;
            }
            UpdateCargoStats();
        }

        // ------------------------------------------------------------------ cargo

        public void ClearCargo()
        {
            foreach (var c in Cargo) if (c != null) Destroy(c.gameObject);
            Cargo.Clear(); CargoValue.Clear(); CargoMass = 0f; CargoLostCount = 0; CargoDescription = "";
        }

        public void LoadCargo(string kind)
        {
            if (Trailer == null && !SpawnTrailerBehindPlayer()) return;
            ClearCargo();
            var t = Trailer.transform;
            if (cargoMat == null) cargoMat = new PhysicsMaterial("Cargo") { dynamicFriction = 0.7f, staticFriction = 0.8f, bounciness = 0.02f, frictionCombine = PhysicsMaterialCombine.Average };
            float deckY = deckLocal.y; float deckZ = deckFromModel ? deckLocal.z : Trailer.def.bodyCenter.z;
            kind = kind.ToLowerInvariant();
            if (kind.StartsWith("log"))
            {
                // two layers of 5 m logs along the trailer, resting on the deck
                float r = 0.22f, len = 5.0f;
                float[] xs = { -0.62f, 0f, 0.62f };
                int n = 0;
                for (int layer = 0; layer < 2; layer++)
                {
                    int cnt = layer == 0 ? 3 : 2;
                    for (int i = 0; i < cnt; i++)
                    {
                        float x = layer == 0 ? xs[i] : (i == 0 ? -0.31f : 0.31f);
                        float y = deckY + r + 0.02f + layer * (r * 1.75f);
                        AddLog(t, new Vector3(x, y, deckZ), r, len, 530f + 25f * n); n++;
                    }
                }
                CargoDescription = "Timber logs";
            }
            else if (kind.StartsWith("barrel"))
            {
                int n = 0;
                for (int row = 0; row < 2; row++) for (int col = 0; col < 3; col++) for (int k = 0; k < 2; k++)
                    { AddBarrel(t, new Vector3(-0.7f + col * 0.7f, deckY + 0.46f + k * 0.92f, deckZ - 2.0f + row * 1.4f)); n++; }
                CargoDescription = "Fuel barrels";
            }
            else
            {
                for (int row = 0; row < 3; row++) for (int col = 0; col < 2; col++) for (int k = 0; k < 2; k++)
                    AddCrate(t, new Vector3(-0.55f + col * 1.1f, deckY + 0.4f + k * 0.8f, deckZ - 2.4f + row * 1.2f));
                CargoDescription = "Supply crates";
            }
            UpdateCargoStats();
        }

        void AddLog(Transform trailer, Vector3 localCenter, float radius, float length, float mass)
        {
            var go = new GameObject("CargoLog");
            go.layer = GameLayers.DynamicProps;
            go.transform.SetPositionAndRotation(trailer.TransformPoint(localCenter), trailer.rotation);
            var vis = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            Destroy(vis.GetComponent<Collider>());
            vis.transform.SetParent(go.transform, false);
            vis.transform.localRotation = Quaternion.Euler(90f, 0f, 0f);
            vis.transform.localScale = new Vector3(radius * 2f, length * 0.5f, radius * 2f);
            Tint(vis, new Color(0.3f, 0.2f, 0.12f));
            var cap = go.AddComponent<CapsuleCollider>();
            cap.direction = 2; cap.radius = radius; cap.height = length; cap.sharedMaterial = cargoMat;
            Register(go, mass);
        }

        void AddBarrel(Transform trailer, Vector3 local)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            go.name = "CargoBarrel"; go.layer = GameLayers.DynamicProps;
            go.transform.SetPositionAndRotation(trailer.TransformPoint(local), trailer.rotation);
            go.transform.localScale = new Vector3(0.58f, 0.46f, 0.58f);
            Destroy(go.GetComponent<Collider>());
            var c = go.AddComponent<CapsuleCollider>(); c.radius = 0.5f; c.height = 2f; c.direction = 1; c.sharedMaterial = cargoMat;
            Tint(go, new Color(0.15f, 0.3f, 0.55f));
            Register(go, 200f);
        }

        void AddCrate(Transform trailer, Vector3 local)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "CargoCrate"; go.layer = GameLayers.DynamicProps;
            go.transform.SetPositionAndRotation(trailer.TransformPoint(local), trailer.rotation);
            go.transform.localScale = new Vector3(0.9f, 0.7f, 1.0f);
            go.GetComponent<Collider>().sharedMaterial = cargoMat;
            Tint(go, new Color(0.45f, 0.33f, 0.18f));
            Register(go, 150f);
        }

        void Register(GameObject go, float mass)
        {
            var rb = go.AddComponent<Rigidbody>();
            rb.mass = mass; rb.interpolation = RigidbodyInterpolation.Interpolate; rb.linearDamping = 0.02f; rb.angularDamping = 0.2f;
            rb.sleepThreshold = 0.02f; rb.solverIterations = 10; rb.maxDepenetrationVelocity = 2f;
            Cargo.Add(rb); CargoValue.Add(100f);
            go.transform.SetParent(transform, true);
        }

        static void Tint(GameObject go, Color c)
        {
            var r = go.GetComponent<Renderer>(); var sh = Shader.Find("Universal Render Pipeline/Lit");
            if (r == null || sh == null) return;
            var m = new Material(sh); m.SetColor("_BaseColor", c); r.sharedMaterial = m;
        }

        void UpdateCargoStats()
        {
            float m = 0f; int deck = 0, lost = 0;
            Vector3 dc = Trailer != null ? Trailer.transform.TransformPoint(Trailer.def.bodyCenter) : Vector3.zero;
            foreach (var c in Cargo)
            {
                if (c == null) { lost++; continue; }
                m += c.mass;
                bool onDeck = Trailer != null && (c.position - dc).sqrMagnitude < 8f * 8f;
                if (onDeck) deck++; else lost++;
            }
            CargoMass = m; CargoOnDeck = deck; CargoLostCount = lost;
        }

        public float TotalTowedMass => (Trailer != null ? Trailer.rb.mass : 0f) + CargoMass;
    }
}
