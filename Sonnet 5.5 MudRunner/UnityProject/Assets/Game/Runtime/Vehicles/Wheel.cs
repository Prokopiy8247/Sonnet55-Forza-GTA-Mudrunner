using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.Vehicles
{
    /// <summary>
    /// One simulated wheel: project-owned suspension + tyre + soil model (no WheelCollider).
    ///
    /// Per fixed step:
    ///  1. SolveContact: find the hub position at which the wheel circle just touches the *deformed* ground
    ///     (macro height + mud-field offset, plus physics props), limited by suspension travel.
    ///  2. Spring / damper / bump-stop force along the contact normal -> wheel load.
    ///  3. Soil: Bekker sinkage target from the load; the wheel digs the field down toward it (viscosity limited),
    ///     spinning wheels dig deeper; resistances and shear caps from the soil state.
    ///  4. Tyre forces (traction, side force) with Janosi-Hanamoto shear curve and impulse-limited stability.
    ///  5. Carve the contact patch into the mud field (ruts, berms, churn, compaction).
    /// </summary>
    public sealed class Wheel
    {
        // ---------------- configuration
        public Vehicle vehicle;
        public AxleDef axle;
        public int axleIndex;
        public bool isLeft;
        public string name;
        public TireSpec tire;
        public Vector3 anchorLocal;
        public float restLength, minLength, maxLength, freeLength, springRate;
        public float staticLoad;
        public float steerFactor;

        // ---------------- state
        public float length, prevLength, visualLength;
        public float omega;
        public float spinAngle;
        public float steerAngle;       // degrees
        public bool grounded;
        public bool onProp;
        public Vector3 hubWorld, patchCenter, contactNormal = Vector3.up;
        public float supportForce;     // N along contact normal
        public float load;             // N the soil sees
        public float slipVelocity, slipRatio, lateralSlip;
        public float sinkage;          // m below the original surface at the patch centre (after this step)
        public float targetSinkage;
        public float churn, compact;
        public SoilSample soil;
        public SoilContact soilContact;
        public float driveTorque, brakeTorque, groundTorque;
        public float fTrac, fLat, fResist, tractionUsage;
        public float lastDigPerStep, lastExcess;   // diagnostics for the spin-digging term
        public float compressionDelta;   // compression relative to free length (for anti-roll)
        public float bumpPenetration;
        public Vector3 lastForceLocalDebug;

        // working
        Vector3 fwdSteered, rightSteered, fwdHoriz, rightHoriz;
        float rEff;
        float digAccumulated;

        public void Configure(Vehicle v, AxleDef a, int idx, bool left, Vector3 anchorLocalPos, float staticLoadN)
        {
            vehicle = v; axle = a; axleIndex = idx; isLeft = left;
            name = a.name + (left ? "_L" : "_R");
            tire = a.tire;
            steerFactor = a.steerFactor;
            springRate = a.springRate;
            restLength = a.restLength;
            minLength = Mathf.Max(0.05f, a.restLength - a.travelUp);
            maxLength = a.restLength + a.travelDown;
            staticLoad = staticLoadN;
            freeLength = a.restLength + staticLoadN / Mathf.Max(1f, a.springRate);
            anchorLocal = anchorLocalPos;
            length = prevLength = visualLength = lengthFiltered = lengthFilteredPrev = a.restLength;
            rEff = tire.radius * 0.97f;
        }

        // ------------------------------------------------------------------ contact

        static readonly float[] ArcFrac = { -0.85f, -0.55f, -0.27f, 0f, 0.27f, 0.55f, 0.85f };
        static readonly float[] penScratch = new float[32];
        static readonly Vector3[] ptScratch = new Vector3[32];
        float lengthFiltered, lengthFilteredPrev;

        /// <summary>Effective (deformed) surface height.</summary>
        static float Surf(GroundMap map, MudField field, float x, float z)
        {
            float h = map.SampleHeight(x, z);
            return field != null ? h + field.SampleDh(x, z) : h;
        }

        public void SolveContact(GroundMap map, MudField field, float dt)
        {
            Transform t = vehicle.transform;
            Vector3 up = t.up;
            Vector3 anchorW = t.TransformPoint(anchorLocal);

            Quaternion steerRot = Quaternion.AngleAxis(steerAngle, up);
            fwdSteered = steerRot * t.forward;
            rightSteered = steerRot * t.right;
            fwdHoriz = new Vector3(fwdSteered.x, 0f, fwdSteered.z); float fh = fwdHoriz.magnitude;
            fwdHoriz = fh > 1e-4f ? fwdHoriz / fh : Vector3.forward;
            rightHoriz = new Vector3(fwdHoriz.z, 0f, -fwdHoriz.x);

            float R = tire.radius;
            float halfB = tire.width * 0.45f;
            float upY = Mathf.Max(0.3f, up.y);

            prevLength = length;
            float L = maxLength;
            float bestPen = float.MinValue; Vector3 bestPt = anchorW;
            bool touching = false;
            const float beta = 45f;      // softmax sharpness (1/m): compliant tyre/soil averages over nearly-touching samples
            for (int iter = 0; iter < 4; iter++)
            {
                Vector3 H = anchorW - up * L;
                float maxPen = float.MinValue;
                int n = 0;
                for (int k = 0; k < ArcFrac.Length; k++)
                {
                    float d = ArcFrac[k] * R;
                    float drop = Mathf.Sqrt(Mathf.Max(0f, R * R - d * d));
                    Vector3 Pc = H + fwdSteered * d - up * drop;
                    for (int s = -1; s <= 1; s++)
                    {
                        Vector3 P = Pc + rightSteered * (s * halfB);
                        float h = Surf(map, field, P.x, P.z);
                        float pen = h - P.y;
                        penScratch[n] = pen; ptScratch[n] = new Vector3(P.x, h, P.z); n++;
                        if (pen > maxPen) { maxPen = pen; bestPt = ptScratch[n - 1]; }
                    }
                }
                if (iter == 0 && maxPen <= 0f) { touching = false; break; }
                touching = true;
                // softmax-weighted penetration (smooth, close to the max)
                float num = 0f, den = 0f;
                for (int i = 0; i < n; i++) { float w = Mathf.Exp(beta * (penScratch[i] - maxPen)); num += w * penScratch[i]; den += w; }
                bestPen = num / den;
                L = Mathf.Clamp(L - bestPen / upY, 0.0f, maxLength);
                if (Mathf.Abs(bestPen) < 0.0008f) break;
            }

            grounded = touching;
            onProp = false;

            // props (rocks, logs, bridges, stumps): same wheel-circle solve as for the terrain, but against physics colliders.
            // Only runs when a prop is near the wheel (cheap overlap test), so open ground costs nothing.
            if (vehicle.useProps)
            {
                float Lp = grounded ? L : maxLength;
                if (SolveProps(anchorW, up, upY, ref Lp, out Vector3 pn, out Vector3 pp) && (Lp < L - 1e-4f || !grounded))
                {
                    L = Lp; grounded = true; onProp = true;
                    bestPt = pp; contactNormal = pn;
                }
            }

            if (!grounded)
            {
                length = maxLength;
                bumpPenetration = 0f;
                supportForce = 0f; load = 0f;
                patchCenter = anchorW - up * length - up * R;
                contactNormal = up;
                hubWorld = anchorW - up * length;
                return;
            }

            bumpPenetration = Mathf.Max(0f, minLength - L);
            length = Mathf.Max(L, minLength);
            hubWorld = anchorW - up * length;

            if (!onProp)
            {
                // surface gradient over the tyre footprint -> contact normal
                float dq = Mathf.Max(0.3f, R * 0.5f), dw = Mathf.Max(0.2f, tire.width * 0.55f);
                float hF = Surf(map, field, bestPt.x + fwdHoriz.x * dq, bestPt.z + fwdHoriz.z * dq);
                float hB = Surf(map, field, bestPt.x - fwdHoriz.x * dq, bestPt.z - fwdHoriz.z * dq);
                float hR = Surf(map, field, bestPt.x + rightHoriz.x * dw, bestPt.z + rightHoriz.z * dw);
                float hL = Surf(map, field, bestPt.x - rightHoriz.x * dw, bestPt.z - rightHoriz.z * dw);
                float a = (hF - hB) / (2f * dq), b = (hR - hL) / (2f * dw);
                Vector3 g = fwdHoriz * a + rightHoriz * b;
                contactNormal = (Vector3.up - g).normalized;
            }
            patchCenter = hubWorld - contactNormal * R;
        }

        static readonly int PropMask = (1 << GameLayers.Props) | (1 << GameLayers.DynamicProps);

        /// <summary>Raise the hub (shorten the strut) until the wheel circle clears physics colliders. Returns true if props touch the wheel.</summary>
        bool SolveProps(Vector3 anchorW, Vector3 up, float upY, ref float L, out Vector3 normal, out Vector3 point)
        {
            normal = up; point = Vector3.zero;
            float R = tire.radius;
            Vector3 h0 = anchorW - up * L;
            if (!Physics.CheckSphere(h0 - up * (R * 0.3f), R + 0.45f, PropMask, QueryTriggerInteraction.Ignore)) return false;
            float halfB = tire.width * 0.45f;
            float lift = R * 0.9f;                       // rays start this far above each wheel-circle sample
            bool any = false;
            for (int iter = 0; iter < 4; iter++)
            {
                Vector3 H = anchorW - up * L;
                float maxPen = float.MinValue; Vector3 bestN = up, bestP = H;
                for (int k = 0; k < ArcFrac.Length; k++)
                {
                    float d = ArcFrac[k] * R;
                    float drop = Mathf.Sqrt(Mathf.Max(0f, R * R - d * d));
                    Vector3 Pc = H + fwdSteered * d - up * drop;
                    for (int sIdx = -1; sIdx <= 1; sIdx++)
                    {
                        Vector3 P = Pc + rightSteered * (sIdx * halfB);
                        if (Physics.Raycast(P + up * lift, -up, out RaycastHit hit, lift + 0.5f, PropMask, QueryTriggerInteraction.Ignore))
                        {
                            float pen = lift - hit.distance;           // > 0: collider surface is above the wheel sample
                            if (pen > maxPen) { maxPen = pen; bestN = hit.normal; bestP = hit.point; }
                        }
                    }
                }
                if (maxPen <= 0.0008f) break;
                L = Mathf.Clamp(L - maxPen / upY, 0f, maxLength);
                any = true; normal = bestN.y > 0.3f ? bestN : up; point = bestP;
            }
            return any;
        }

        // ------------------------------------------------------------------ suspension

        /// <summary>Spring + damper + bump stop (N, along contact normal). Anti-roll is added by the vehicle.</summary>
        public float SuspensionForce(float dt)
        {
            if (!grounded) { compressionDelta = freeLength - maxLength; return 0f; }
            float x = freeLength - length + bumpPenetration * 0f;
            compressionDelta = x;
            float fs = Mathf.Max(0f, springRate * x);
            lengthFilteredPrev = lengthFiltered;
            lengthFiltered += (length - lengthFiltered) * (1f - Mathf.Exp(-dt / 0.03f));
            float v = (lengthFilteredPrev - lengthFiltered) / Mathf.Max(1e-4f, dt);   // + when compressing (low-passed: no jitter -> no damper noise)
            float fd = v >= 0f ? axle.bumpDamping * v : axle.reboundDamping * v;
            float fb = 0f;
            if (bumpPenetration > 0f) fb = springRate * 12f * bumpPenetration + axle.bumpDamping * 2f * Mathf.Max(0f, v);
            return fs + fd + fb;
        }

        // ------------------------------------------------------------------ soil + tyre

        public struct TireOutput { public Vector3 forceAtPatch; }

        /// <summary>
        /// Evaluate soil + tyre with the wheel's current spin and drive/brake torque.
        /// supportRaw = strut + anti-roll force along the contact normal (already clamped &gt;= 0).
        /// </summary>
        public Vector3 ComputeTyreForces(GroundService ground, float supportN, float dt, Rigidbody rb)
        {
            supportForce = supportN;
            fTrac = fLat = fResist = 0f;
            tractionUsage = 0f;
            if (!grounded)
            {
                load = 0f; sinkage = 0f; slipVelocity = 0f;
                return Vector3.zero;
            }

            var map = ground.Map; var field = ground.Field;
            float g = 9.81f;
            load = supportN + axle.unsprungMass * g * Mathf.Max(0f, contactNormal.y);

            Vector3 n = contactNormal;
            Vector3 fT = fwdSteered - n * Vector3.Dot(fwdSteered, n);
            fT = fT.sqrMagnitude > 1e-6f ? fT.normalized : fwdHoriz;
            Vector3 lT = Vector3.Cross(n, fT);

            Vector3 vC = rb.GetPointVelocity(patchCenter);
            float vx = Vector3.Dot(vC, fT), vy = Vector3.Dot(vC, lT);

            // ---- soil at the patch
            float px = patchCenter.x, pz = patchCenter.z;
            soil = ground.SampleSoil(px, pz);
            float dhC = 0f; churn = 0f; compact = 0f;
            float dhFront = 0f;
            bool fieldOk = field != null && field.IsResidentWorld(px, pz);
            float halfL0 = 0.5f * TireSoilModel.ContactLength(tire.radius, TireSoilModel.Deflection(tire, load) + 0.02f);
            float travelSign = vx >= 0f ? 1f : -1f;
            float shallowest = 0f;
            if (fieldOk)
            {
                field.Sample(px, pz, out dhC, out churn, out compact);
                dhFront = field.SampleDh(px + fT.x * halfL0 * travelSign, pz + fT.z * halfL0 * travelSign);
                var probe = new PatchOp { cx = px, cz = pz, fx = fwdHoriz.x, fz = fwdHoriz.z, halfWidth = Mathf.Max(tire.width * 0.45f, 0.1f), halfLength = Mathf.Max(halfL0, 0.12f) };
                if (!field.PatchDepthRange(probe, out shallowest, out _)) shallowest = -dhC;
            }
            bool onSoft = !onProp && soil.softDepth > 0.02f;
            float stiffScale = Mathf.Max(0.25f, (1f + soil.compactionGain * compact) * (1f - 0.45f * churn));

            float dCur = fieldOk ? shallowest : -dhC;  // depth of the SUPPORT surface (shallowest cell under the patch) below the original surface
            float dEq = 0f; bool bottomed = false;
            if (onSoft)
                dEq = TireSoilModel.SolveSinkage(tire, load, soil, stiffScale, soil.softDepth, out bottomed);
            float dTarget = Mathf.Max(dCur, dEq);
            targetSinkage = dTarget;

            // geometry for contact area uses the larger of the current and target depth
            float zGeom = Mathf.Max(0f, Mathf.Max(dCur, dTarget));
            soilContact = TireSoilModel.Evaluate(tire, load, zGeom, soil, stiffScale, bottomed);
            float zRes = Mathf.Max(0f, dTarget + dhFront);     // depth still to be pressed in at the leading edge
            float rComp, rBull;
            ResistanceAt(tire, soil, stiffScale, zRes, out rComp, out rBull);
            soilContact.compactionResistance = rComp;
            soilContact.bulldozeResistance = rBull;

            // ---- slip
            float wheelSpeed = omega * rEff;
            slipVelocity = wheelSpeed - vx;
            float denom = Mathf.Max(Mathf.Max(Mathf.Abs(wheelSpeed), Mathf.Abs(vx)), 0.25f);
            slipRatio = Mathf.Clamp(slipVelocity / denom, -1f, 1f);
            lateralSlip = Mathf.Clamp(vy / denom, -1.5f, 1.5f);

            float mShare = Mathf.Max(load / g + axle.unsprungMass, 0.15f * vehicle.rb.mass / Mathf.Max(1, vehicle.wheels.Length));
            float mEffLong = 1f / (1f / mShare + rEff * rEff / Mathf.Max(0.5f, tire.inertia));

            float capX = Mathf.Max(1f, soilContact.thrustCap), capY = Mathf.Max(1f, soilContact.lateralCap);
            float frac = TireSoilModel.ThrustFraction(slipRatio, soilContact.contactLength, soil.shearK);
            float fx = Mathf.Sign(slipRatio) * capX * frac;
            fx = Mathf.Sign(fx) * Mathf.Min(Mathf.Abs(fx), mEffLong * Mathf.Abs(slipVelocity) / dt);
            float fracY = TireSoilModel.ThrustFraction(lateralSlip, soilContact.contactLength, soil.shearK);
            float fy = -Mathf.Sign(vy) * capY * fracY;
            fy = Mathf.Sign(fy) * Mathf.Min(Mathf.Abs(fy), mShare * Mathf.Abs(vy) / dt);

            // friction ellipse
            float ex = Mathf.Abs(fx) / capX, ey = Mathf.Abs(fy) / capY;
            float es = Mathf.Sqrt(ex * ex + ey * ey);
            if (es > 1f) { fx /= es; fy /= es; }
            tractionUsage = Mathf.Min(1.5f, es);

            // resistances oppose the rolling direction (smooth around standstill so a parked vehicle is not pushed)
            float rTotal = rComp + rBull + tire.rollingResistance * load * (onSoft ? 0.5f : 1f);
            float res = -rTotal * (float)System.Math.Tanh(vx / 0.12f);

            fTrac = fx; fLat = fy; fResist = res;

            // ---- ground torque on the wheel (shear traction only; resistances act on the vehicle)
            groundTorque = -fx * rEff;

            // ---- soil deformation: sink toward the target, spinning wheels dig
            if (fieldOk && !onProp)
            {
                float tau = 0.04f + soil.viscosity * 0.5f;
                float newDepth = dCur;
                if (dTarget > dCur) newDepth = dCur + (dTarget - dCur) * Mathf.Min(1f, dt / tau);

                // spin digging: wheel slipping hard relative to ground speed throws soil rearwards
                lastDigPerStep = 0f; lastExcess = 0f;
                float excess = Mathf.Abs(slipVelocity) - 0.12f * Mathf.Abs(vx) - 0.08f;
                if (excess > 0f && onSoft && load > 500f)
                {
                    float room = Mathf.Clamp01(1f - newDepth / Mathf.Max(0.05f, soil.softDepth + 0.05f));
                    float loadFactor = Mathf.Clamp01(load / Mathf.Max(1f, staticLoad));
                    float dig = soil.digRate * excess * dt * room * room * (0.4f + 0.6f * loadFactor) * (0.5f + churn);
                    newDepth += dig; lastDigPerStep = dig; lastExcess = excess;
                }
                newDepth = Mathf.Min(newDepth, soil.softDepth + 0.08f);

                float slipAmount = Mathf.Clamp01((Mathf.Abs(slipVelocity) - 0.3f) / 3f);
                var op = new PatchOp
                {
                    cx = px, cz = pz, fx = fwdHoriz.x, fz = fwdHoriz.z,
                    halfWidth = Mathf.Max(0.5f * tire.width * 0.9f, 0.1f),
                    halfLength = Mathf.Max(0.5f * soilContact.contactLength, 0.12f),
                    depth = newDepth, moveSign = travelSign,
                    bermFrac = 0.55f, frontFrac = onSoft ? 0.2f + 0.2f * slipAmount : 0f,
                    maxBerm = 0.35f,
                    churn = onSoft ? (0.04f + 0.5f * slipAmount) * dt * 60f * 0.05f : 0f,
                    compact = onSoft ? (slipAmount < 0.3f ? 0.02f : -0.03f) * dt * 60f * Mathf.Clamp01(load / Mathf.Max(1f, staticLoad)) : 0f,
                };
                if (newDepth > 0.002f || op.churn > 0f) field.CarvePatch(op);
                field.Sample(px, pz, out float dhAfter, out _, out _);
                sinkage = Mathf.Max(0f, -dhAfter);
            }
            else sinkage = Mathf.Max(0f, dCur);

            Vector3 force = fT * (fx + res) + lT * fy;
            return force;
        }

        /// <summary>Compaction + bulldozing resistance at sinkage z (N).</summary>
        public static void ResistanceAt(in TireSpec tire, in SoilSample soil, float stiffScale, float z, out float rComp, out float rBull)
        {
            if (z <= 1e-5f) { rComp = rBull = 0f; return; }
            float n = Mathf.Max(0.3f, soil.n);
            float k = TireSoilModel.Modulus(soil, tire.width, stiffScale);
            rComp = tire.width * k * Mathf.Pow(z, n + 1f) / (n + 1f);
            float cPa = soil.cohesion * 1000f;
            rBull = soil.bulldozeFactor * tire.width * z * (cPa * 1.2f + 0.5f * soil.unitWeight * 1000f * z * 1.0f * (1f + soil.tanPhi));
        }

        /// <summary>World position where the traction force acts (between contact patch and hub).</summary>
        public Vector3 TractionPoint(float blend)
        {
            return patchCenter + contactNormal * (blend * tire.radius);
        }
    }
}
