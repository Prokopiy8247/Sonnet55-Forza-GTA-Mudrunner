using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.Vehicles
{
    /// <summary>
    /// A drivable vehicle: Rigidbody + project-owned wheels (suspension, tyre, soil) + drivetrain.
    /// All numbers come from a <see cref="VehicleDefinition"/>. Forces are applied in FixedUpdate.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    [DefaultExecutionOrder(-10)]
    public sealed class Vehicle : MonoBehaviour
    {
        public static readonly List<Vehicle> All = new List<Vehicle>();

        public VehicleDefinition def;
        public VehicleInput input;
        public bool useProps = true;
        [Range(0f, 1f)] public float tractionHeightBlend = 0.55f;

        public Rigidbody rb { get; private set; }
        public Wheel[] wheels { get; private set; }
        public Drivetrain drivetrain { get; private set; }
        public Winch winch { get; private set; }
        public VehicleWater water { get; private set; }
        public float fuel;
        public float damage01;

        /// <summary>Optional visual transforms, same order as <see cref="wheels"/> (axle-major, left then right).</summary>
        public Transform[] wheelVisuals;
        /// <summary>Optional lights/other visual children.</summary>
        public Transform visualRoot;

        // ---- telemetry
        public float forwardSpeed, speed, speedKmh;
        public float steerSmoothed;
        public float stuckTime;
        public bool isStuck;
        public int groundedWheels;
        public float maxSinkage, meanSlipAbs, meanSlipSpeed;
        public float bellyContact;       // 0..1 how much the belly is resting on the mud
        public float throttleEff, brakeEff;
        public float waterDepthAtVehicle;

        Vector3[] bodyLocal;
        float[] bodyRadius;
        float steerWheelbase = 3f;
        float totalSteerDeg;
        bool initialised;
        float[] supportScratch;

        // ------------------------------------------------------------------ setup

        public void Initialize(VehicleDefinition d)
        {
            def = d;
            rb = GetComponent<Rigidbody>();
            rb.mass = d.mass;
            rb.centerOfMass = d.centerOfMass;
            Vector3 s = d.bodySize;
            float m = d.mass;
            rb.inertiaTensor = new Vector3(m / 12f * (s.y * s.y + s.z * s.z), m / 12f * (s.x * s.x + s.z * s.z), m / 12f * (s.x * s.x + s.y * s.y)) * 1.15f;
            rb.inertiaTensorRotation = Quaternion.identity;
            rb.linearDamping = 0f; rb.angularDamping = 0.15f;
            rb.interpolation = RigidbodyInterpolation.Interpolate;
            rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            rb.sleepThreshold = 0f;
            rb.maxAngularVelocity = 12f;
            rb.maxDepenetrationVelocity = 3f;
            rb.solverIterations = 12; rb.solverVelocityIterations = 4;

            // body collider (if the prefab has none)
            if (GetComponentInChildren<Collider>() == null)
            {
                var col = gameObject.AddComponent<BoxCollider>();
                col.size = d.bodySize; col.center = d.bodyCenter;
                var pm = new PhysicsMaterial("VehicleBody") { dynamicFriction = 0.1f, staticFriction = 0.1f, frictionCombine = PhysicsMaterialCombine.Minimum, bounciness = 0f, bounceCombine = PhysicsMaterialCombine.Minimum };
                col.sharedMaterial = pm;
            }
            SetLayerRecursive(gameObject, GameLayers.VehicleBody);

            // wheels
            int n = d.axles.Length * 2;
            wheels = new Wheel[n];
            float W = d.mass * 9.81f;
            float zbar = 0f; foreach (var a in d.axles) zbar += a.z; zbar /= d.axles.Length;
            float var_ = 0f; foreach (var a in d.axles) var_ += (a.z - zbar) * (a.z - zbar); var_ /= d.axles.Length;
            float[] axleLoad = new float[d.axles.Length];
            float sum = 0f;
            for (int i = 0; i < axleLoad.Length; i++)
            {
                float f = W / axleLoad.Length;
                if (var_ > 1e-4f) f *= 1f + (d.centerOfMass.z - zbar) * (d.axles[i].z - zbar) / var_;
                axleLoad[i] = Mathf.Max(0.08f * W / axleLoad.Length, f); sum += axleLoad[i];
            }
            for (int i = 0; i < axleLoad.Length; i++) axleLoad[i] *= W / sum;

            for (int ai = 0; ai < d.axles.Length; ai++)
            {
                var a = d.axles[ai];
                for (int side = 0; side < 2; side++)
                {
                    bool left = side == 0;
                    float x = (left ? -0.5f : 0.5f) * a.track;
                    var anchor = new Vector3(x, a.hubY + a.restLength, a.z);
                    float strut = Mathf.Max(0.2f * axleLoad[ai] * 0.5f, axleLoad[ai] * 0.5f - a.unsprungMass * 9.81f);
                    var w = new Wheel();
                    w.Configure(this, a, ai, left, anchor, strut);
                    wheels[ai * 2 + side] = w;
                }
            }
            drivetrain = new Drivetrain(d, wheels);
            supportScratch = new float[n];

            // steering geometry: wheelbase from steered axle to the mean of fixed axles
            float zs = 0f; int ns = 0, nf = 0; float zf = 0f;
            foreach (var a in d.axles) { if (Mathf.Abs(a.steerFactor) > 0.01f) { zs += a.z; ns++; } else { zf += a.z; nf++; } }
            if (ns > 0 && nf > 0) steerWheelbase = Mathf.Max(1.5f, Mathf.Abs(zs / ns - zf / nf));

            bodyLocal = new Vector3[d.bodyPoints.Length]; bodyRadius = new float[d.bodyPoints.Length];
            for (int i = 0; i < bodyLocal.Length; i++) { var p = d.bodyPoints[i]; bodyLocal[i] = new Vector3(p.x, p.y, p.z); bodyRadius[i] = p.w; }

            fuel = d.fuelCapacity * 0.9f;
            if (d.isTrailer) { drivetrain.engineOn = false; fuel = 0f; drivetrain.gear = 0; }
            water = GetComponent<VehicleWater>() ?? gameObject.AddComponent<VehicleWater>(); water.vehicle = this;
            if (d.hasWinch) { winch = GetComponent<Winch>() ?? gameObject.AddComponent<Winch>(); winch.Setup(this); }
            initialised = true;
        }

        static void SetLayerRecursive(GameObject go, int layer)
        {
            go.layer = layer;
            foreach (Transform c in go.transform) SetLayerRecursive(c.gameObject, layer);
        }

        void OnEnable() { All.Add(this); }
        void OnDisable() { All.Remove(this); }

        // ------------------------------------------------------------------ controls (called by input providers)

        public void ToggleAwd() { if (def.hasAwdSwitch) drivetrain.awd = !drivetrain.awd; }
        public void ToggleLowRange() { if (def.hasLowRange) drivetrain.lowRange = !drivetrain.lowRange; }
        public void ToggleAxleLock(int axle) { if (axle >= 0 && axle < drivetrain.axleLock.Length && def.axles[axle].canLockDiff) drivetrain.axleLock[axle] = !drivetrain.axleLock[axle]; }
        public void ToggleCentreLock() { if (def.hasCentreDiffLock) drivetrain.centreLock = !drivetrain.centreLock; }
        public Vector3? intakeOverrideLocal;      // from the model's Intake empty
        public Vector3? hitchOverrideLocal;       // from the model's Anchor_Hitch empty
        public float FordingRating => VehicleDefinition.ComputeFordingRating(def, intakeOverrideLocal);
        public Vector3 IntakeLocal => intakeOverrideLocal ?? def.intakeLocal;
        public Vector3 HitchLocal => hitchOverrideLocal ?? def.hitchLocal;
        public Vehicle towedTrailer;
        public Vehicle towingVehicle;

        public void ToggleEngine() { if (def.isTrailer) return; if (water != null && water.engineFlooded && !drivetrain.engineOn) return; drivetrain.StartStop(fuel); }
        public void ToggleGearMode() { drivetrain.ToggleMode(); }

        public void Refuel() { fuel = def.fuelCapacity; }
        public void Repair() { damage01 = 0f; }

        public void ResetUpright(Vector3? position = null)
        {
            Vector3 p = position ?? transform.position + Vector3.up * 1.5f;
            float yaw = transform.eulerAngles.y;
            rb.linearVelocity = Vector3.zero; rb.angularVelocity = Vector3.zero;
            transform.SetPositionAndRotation(p, Quaternion.Euler(0f, yaw, 0f));
            rb.position = p; rb.rotation = Quaternion.Euler(0f, yaw, 0f);
            foreach (var w in wheels) { w.omega = 0f; w.length = w.prevLength = w.restLength; }
        }

        // ------------------------------------------------------------------ physics step

        // ---- cost telemetry (vehicle physics only)
        static long fixedTicks; static long fixedCalls;
        public static void ResetFixedStats() { fixedTicks = 0; fixedCalls = 0; }
        /// <summary>Average milliseconds one vehicle's FixedUpdate takes (soil model, suspension, drivetrain, field writes).</summary>
        public static float FixedMsPerCall => fixedCalls > 0 ? (float)(fixedTicks * 1000.0 / System.Diagnostics.Stopwatch.Frequency / fixedCalls) : 0f;
        public static float FixedMsPerStep => FixedMsPerCall * Mathf.Max(1, All.Count);

        void FixedUpdate()
        {
            if (!initialised) return;
            var gs = GroundService.Instance;
            if (gs == null || gs.Map == null) return;
            long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
            Step(gs);
            fixedTicks += System.Diagnostics.Stopwatch.GetTimestamp() - t0; fixedCalls++;
        }

        void Step(GroundService gs)
        {
            float dt = Time.fixedDeltaTime;
            var map = gs.Map; var field = gs.Field;

            Vector3 vel = rb.linearVelocity;
            forwardSpeed = Vector3.Dot(vel, transform.forward);
            speed = vel.magnitude; speedKmh = speed * 3.6f;

            // ---- gear shifting events
            if (input.shiftUp || input.shiftDown) { drivetrain.ManualShift(input.shiftUp, input.shiftDown); input.shiftUp = input.shiftDown = false; }

            // ---- pedals, steering
            drivetrain.ResolvePedals(input, forwardSpeed, out throttleEff, out brakeEff);
            UpdateSteering(dt);
            for (int i = 0; i < wheels.Length; i++)
            {
                var w = wheels[i];
                w.brakeTorque = brakeEff * w.axle.brakeTorque + (input.handbrake ? w.axle.handbrakeTorque : 0f);
            }

            // ---- contacts + suspension
            for (int i = 0; i < wheels.Length; i++)
            {
                wheels[i].SolveContact(map, field, dt);
                supportScratch[i] = wheels[i].SuspensionForce(dt);
            }
            // anti-roll bars
            for (int a = 0; a < def.axles.Length; a++)
            {
                var L = wheels[a * 2]; var R = wheels[a * 2 + 1];
                float arb = def.axles[a].antiRoll * (L.compressionDelta - R.compressionDelta);
                if (L.grounded || R.grounded) { supportScratch[a * 2] += arb; supportScratch[a * 2 + 1] -= arb; }
            }

            // ---- tyre + soil forces, apply to rigid body
            groundedWheels = 0; maxSinkage = 0f; meanSlipAbs = 0f; meanSlipSpeed = 0f;
            for (int i = 0; i < wheels.Length; i++)
            {
                var w = wheels[i];
                float sup = Mathf.Max(0f, supportScratch[i]);
                Vector3 tyreF = w.ComputeTyreForces(gs, sup, dt, rb);
                if (w.grounded)
                {
                    groundedWheels++;
                    Vector3 anchorW = transform.TransformPoint(w.anchorLocal);
                    rb.AddForceAtPosition(w.contactNormal * sup, anchorW, ForceMode.Force);
                    rb.AddForceAtPosition(tyreF, w.TractionPoint(tractionHeightBlend), ForceMode.Force);
                    maxSinkage = Mathf.Max(maxSinkage, w.sinkage);
                    meanSlipAbs += Mathf.Abs(w.slipRatio); meanSlipSpeed += Mathf.Abs(w.slipVelocity);
                }
            }
            if (groundedWheels > 0) { meanSlipAbs /= groundedWheels; meanSlipSpeed /= groundedWheels; }

            // ---- drivetrain (wheel omegas, engine, fuel)
            drivetrain.Step(dt, throttleEff, forwardSpeed, ref fuel);

            // ---- body contact, aero
            ApplyBodyContacts(gs, dt);
            if (speed > 0.01f) rb.AddForce(-0.6125f * def.dragCdA * speed * vel, ForceMode.Force);

            UpdateStuck(dt);
        }

        void UpdateSteering(float dt)
        {
            float target = Mathf.Clamp(input.steer, -1f, 1f);
            float rate = Mathf.Abs(target) > Mathf.Abs(steerSmoothed) ? 2.4f : 4.0f;
            steerSmoothed = Mathf.MoveTowards(steerSmoothed, target, rate * dt);
            float maxDeg = Mathf.Lerp(34f, 8f, Mathf.Clamp01(Mathf.Abs(forwardSpeed) / 20f));
            float delta = steerSmoothed * maxDeg * Mathf.Deg2Rad;
            totalSteerDeg = delta * Mathf.Rad2Deg;
            float absTan = Mathf.Tan(Mathf.Abs(delta));
            for (int i = 0; i < wheels.Length; i++)
            {
                var w = wheels[i];
                float f = w.steerFactor;
                if (Mathf.Abs(f) < 0.01f || Mathf.Abs(delta) < 1e-4f) { w.steerAngle = 0f; continue; }
                float t = w.axle.track;
                float inner = Mathf.Atan(steerWheelbase / Mathf.Max(0.01f, steerWheelbase / Mathf.Max(1e-4f, absTan) - t * 0.5f));
                float outer = Mathf.Atan(steerWheelbase / (steerWheelbase / Mathf.Max(1e-4f, absTan) + t * 0.5f));
                bool turningLeft = delta < 0f;                     // negative steer = left
                bool isInner = turningLeft == w.isLeft;
                float ang = (isInner ? inner : outer) * Mathf.Sign(delta);
                w.steerAngle = ang * Mathf.Rad2Deg * f;
            }
        }

        void ApplyBodyContacts(GroundService gs, float dt)
        {
            bellyContact = 0f;
            if (bodyLocal.Length == 0) return;
            Vector3 c = transform.position;
            SoilSample soil = gs.SampleSoil(c.x, c.z);
            float mPt = rb.mass / bodyLocal.Length;
            float kb = rb.mass * 9.81f * 2.5f / 0.08f / bodyLocal.Length;
            float cb = 1.4f * Mathf.Sqrt(kb * mPt);
            float mu = Mathf.Max(0.35f, soil.tanPhi * 1.3f);
            float cohesionPa = soil.cohesion * 1000f;
            int touching = 0;
            for (int i = 0; i < bodyLocal.Length; i++)
            {
                Vector3 p = transform.TransformPoint(bodyLocal[i]);
                float h = gs.SurfaceHeight(p.x, p.z);
                float pen = h - (p.y - bodyRadius[i]);
                if (pen <= 0f) continue;
                touching++;
                Vector3 v = rb.GetPointVelocity(p);
                Vector3 n = gs.Map.SampleNormal(p.x, p.z);
                float vn = Vector3.Dot(v, n);
                // spring + damping (damping only while sinking into the surface)
                float fn = kb * pen + (vn < 0f ? -cb * vn : 0f);
                fn = Mathf.Min(fn, rb.mass * 9.81f * 6f / bodyLocal.Length);
                rb.AddForceAtPosition(n * fn, p, ForceMode.Force);
                Vector3 vt = v - n * vn;
                float vtm = vt.magnitude;
                if (vtm > 0.01f)
                {
                    float cap = mu * fn + cohesionPa * 0.5f * Mathf.Min(pen, 0.5f);
                    float ft = Mathf.Min(cap, mPt * vtm / dt);
                    rb.AddForceAtPosition(-vt / vtm * ft, p, ForceMode.Force);
                }
            }
            bellyContact = (float)touching / bodyLocal.Length;
        }

        void UpdateStuck(float dt)
        {
            bool trying = throttleEff > 0.3f && speed < 0.5f && drivetrain.engineOn;
            if (trying) stuckTime += dt; else stuckTime = Mathf.Max(0f, stuckTime - dt * 2f);
            isStuck = stuckTime > 2.5f;
        }

        // ------------------------------------------------------------------ visuals

        void Update()
        {
            if (!initialised) return;
            float dt = Time.deltaTime;
            for (int i = 0; i < wheels.Length; i++)
            {
                var w = wheels[i];
                w.spinAngle += w.omega * dt;
                w.visualLength = Mathf.Lerp(w.visualLength, w.length, 1f - Mathf.Exp(-dt / 0.03f));
            }
            if (wheelVisuals == null) return;
            Transform body = transform;
            for (int i = 0; i < wheels.Length && i < wheelVisuals.Length; i++)
            {
                var vis = wheelVisuals[i]; if (vis == null) continue;
                var w = wheels[i];
                Vector3 hub = body.TransformPoint(w.anchorLocal) - body.up * w.visualLength;
                vis.position = hub;
                vis.rotation = body.rotation * Quaternion.Euler(0f, w.steerAngle, 0f) * Quaternion.Euler(w.spinAngle * Mathf.Rad2Deg, 0f, 0f);
            }
        }

        // ------------------------------------------------------------------ helpers

        public float TotalMass => rb != null ? rb.mass : def.mass;
        public float SteerAngleDeg => totalSteerDeg;

        void OnDrawGizmosSelected()
        {
            if (wheels == null) return;
            foreach (var w in wheels)
            {
                if (!w.grounded) continue;
                Gizmos.color = Color.green; Gizmos.DrawLine(w.patchCenter, w.patchCenter + w.contactNormal);
                Gizmos.color = Color.red; Gizmos.DrawSphere(w.patchCenter, 0.05f);
            }
        }
    }
}
