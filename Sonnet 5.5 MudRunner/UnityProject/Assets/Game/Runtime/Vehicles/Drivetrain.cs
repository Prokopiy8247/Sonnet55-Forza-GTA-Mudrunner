using System;
using UnityEngine;

namespace MudRunner.Vehicles
{
    public enum GearMode { Automatic, Manual }

    /// <summary>Per-frame driver commands.</summary>
    public struct VehicleInput
    {
        public float throttle;     // 0..1
        public float brake;        // 0..1 (service brake / reverse pedal in automatic mode)
        public float steer;        // -1..1
        public bool handbrake;
        public bool shiftUp, shiftDown;   // edge flags, consumed by the vehicle each fixed step
    }

    /// <summary>
    /// Engine + clutch/converter + gearbox + transfer case + differentials.
    ///
    /// Engine and driven wheels are coupled by an *implicit lock solve*: given the torques the tyres put on the wheels
    /// (computed beforehand) we compute the clutch torque that would make engine and wheels agree at the end of the step,
    /// then clamp it to the clutch capacity (slip). This stays stable even when the wheels spin freely in mud.
    /// Locked differentials / centre lock are impulse couplings applied after the wheel speeds were updated.
    /// </summary>
    public sealed class Drivetrain
    {
        readonly VehicleDefinition def;
        readonly Wheel[] wheels;
        readonly int axleCount;

        // ---- selectable state
        public bool engineOn = true;
        public GearMode mode = GearMode.Automatic;
        public int gear = 1;                 // -1 reverse, 0 neutral, 1..N
        public bool lowRange;
        public bool awd = true;
        public bool centreLock;
        public bool[] axleLock;              // per axle differential lock

        // ---- readouts
        public float engineOmega;            // rad/s
        public float rpm => engineOmega * 9.5492966f;
        public float engineTorque, clutchTorque, wheelTorqueTotal, loadFraction;
        public float shiftTimer;
        public float lockStress;             // |lock torque| accumulated metric (Nm), decays
        public float fuelRateLitresPerHour;
        public float stallTimer;
        public float currentRatio;
        public bool clutchSlipping;
        public float engagement;

        readonly float peakTorque, peakPower;
        readonly bool[] drivenAxle;
        readonly float[] share;              // torque share per wheel (sum over driven wheels = 1)

        public Drivetrain(VehicleDefinition d, Wheel[] w)
        {
            def = d; wheels = w;
            axleCount = d.axles.Length;
            axleLock = new bool[axleCount];
            drivenAxle = new bool[axleCount];
            share = new float[w.Length];
            float pt = 0f, pp = 0f;
            for (float r = d.idleRpm; r <= d.redlineRpm; r += 50f)
            {
                float t = d.torqueCurve.Evaluate(r);
                pt = Mathf.Max(pt, t);
                pp = Mathf.Max(pp, t * r * 0.10472f);
            }
            peakTorque = Mathf.Max(10f, pt); peakPower = Mathf.Max(1000f, pp);
            engineOmega = d.idleRpm / 9.5492966f;
        }

        public int GearCount => def.gearbox.forwardRatios.Length;
        public string GearLabel => gear < 0 ? "R" : gear == 0 ? "N" : gear.ToString();
        public bool AxleDriven(int i) => drivenAxle[i];

        // ------------------------------------------------------------------ gear / range logic

        public float GearRatio(int g)
        {
            if (g == 0) return 0f;
            if (g < 0) return -def.gearbox.reverseRatio;
            return def.gearbox.forwardRatios[Mathf.Clamp(g, 1, GearCount) - 1];
        }

        public float TotalRatio(int g)
        {
            float r = GearRatio(g) * def.gearbox.finalDrive;
            if (lowRange && def.hasLowRange) r *= def.gearbox.lowRangeRatio;
            return r;
        }

        /// <summary>Translate pedals to effective throttle / service brake according to gear logic. Returns drive throttle.</summary>
        public void ResolvePedals(in VehicleInput inp, float forwardSpeed, out float driveThrottle, out float serviceBrake)
        {
            driveThrottle = inp.throttle; serviceBrake = inp.brake;
            if (mode == GearMode.Automatic)
            {
                if (gear < 0)
                {
                    // reverse engaged: S is the throttle, W is the brake
                    driveThrottle = inp.brake; serviceBrake = inp.throttle;
                    if (inp.throttle > 0.05f && forwardSpeed > -0.7f && inp.brake < 0.05f) { gear = 1; driveThrottle = inp.throttle; serviceBrake = 0f; }
                }
                else
                {
                    if (inp.throttle > 0.05f && gear == 0) gear = 1;
                    if (inp.brake > 0.05f && inp.throttle < 0.05f && forwardSpeed < 0.7f && engineOn)
                    {
                        gear = -1; driveThrottle = inp.brake; serviceBrake = 0f;
                    }
                }
            }
        }

        /// <summary>Engine rpm the vehicle's GROUND speed would impose with the clutch locked in gear g (wheel spin does not fool the shift logic).</summary>
        float GroundEquivalentRpm(int g, float forwardSpeed)
        {
            float r = 0f; int n = 0;
            for (int i = 0; i < wheels.Length; i++) if (share[i] > 0f) { r += wheels[i].tire.radius; n++; }
            r = n > 0 ? r / n : 0.5f;
            return Mathf.Abs(forwardSpeed) / Mathf.Max(0.1f, r) * Mathf.Abs(TotalRatio(g)) * 9.5492966f;
        }

        void AutoShift(float dt, float throttle, float forwardSpeed)
        {
            if (shiftTimer > 0f) { shiftTimer -= dt; return; }
            if (mode != GearMode.Automatic || gear <= 0) return;
            float eq = GroundEquivalentRpm(gear, forwardSpeed);
            float upRpm = def.gearbox.upshiftRpm * (0.75f + 0.25f * throttle);
            float downRpm = def.gearbox.downshiftRpm * (0.9f + 0.4f * throttle);
            float kick = downRpm * 1.5f;                       // kick-down threshold under heavy throttle
            // upshift only when the NEXT gear would still sit comfortably above the kick-down / down-shift thresholds (no hunting)
            bool canUp = gear < GearCount && eq > upRpm && GroundEquivalentRpm(gear + 1, forwardSpeed) > Mathf.Max(kick, def.gearbox.downshiftRpm * 1.25f) * 1.08f;
            if (canUp && forwardSpeed > 0.8f) { gear++; shiftTimer = def.gearbox.shiftTime; }
            else if (gear > 1 && eq < downRpm) { gear--; shiftTimer = def.gearbox.shiftTime * 0.5f; }
            else if (gear > 1 && throttle > 0.85f && eq < kick && GroundEquivalentRpm(gear - 1, forwardSpeed) < def.redlineRpm * 0.85f) { gear--; shiftTimer = def.gearbox.shiftTime * 0.5f; }
        }

        public void ManualShift(bool up, bool down)
        {
            if (mode != GearMode.Manual) return;
            if (shiftTimer > 0f) return;
            if (up && gear < GearCount) { gear++; shiftTimer = def.gearbox.shiftTime; }
            else if (down && gear > -1) { gear--; shiftTimer = def.gearbox.shiftTime; }
        }

        public void ToggleMode() { mode = mode == GearMode.Automatic ? GearMode.Manual : GearMode.Automatic; if (mode == GearMode.Automatic && gear == 0) gear = 1; }

        public void SetLowRange(bool v) { if (def.hasLowRange) lowRange = v; }

        public void StartStop(float fuel)
        {
            if (engineOn) { engineOn = false; }
            else if (fuel > 0f) { engineOn = true; engineOmega = Mathf.Max(engineOmega, def.idleRpm * 0.6f / 9.5492966f); stallTimer = 0f; }
        }

        // ------------------------------------------------------------------ step

        /// <summary>Compute torque shares for the currently driven axles.</summary>
        void UpdateShares()
        {
            int driven = 0;
            for (int a = 0; a < axleCount; a++)
            {
                var m = def.axles[a].drive;
                drivenAxle[a] = m == DriveMode.Always || (m == DriveMode.AwdOnly && awd);
                if (drivenAxle[a]) driven++;
            }
            Array.Clear(share, 0, share.Length);
            if (driven == 0) return;
            for (int a = 0; a < axleCount; a++)
            {
                if (!drivenAxle[a]) continue;
                float axleShare;
                if (driven == 1) axleShare = 1f;
                else if (axleCount == 2) axleShare = a == 0 ? def.frontTorqueShare : 1f - def.frontTorqueShare;
                else axleShare = AxleShareMulti(a, driven);
                for (int i = 0; i < wheels.Length; i++) if (wheels[i].axleIndex == a) share[i] = axleShare * 0.5f;
            }
        }

        float AxleShareMulti(int a, int driven)
        {
            // multi-axle: front gets the configured share, the remaining driven axles split the rest evenly
            if (a == 0) return def.frontTorqueShare;
            int rest = driven - (drivenAxle[0] ? 1 : 0);
            float remain = drivenAxle[0] ? 1f - def.frontTorqueShare : 1f;
            return rest > 0 ? remain / rest : 0f;
        }

        /// <summary>
        /// Advance engine + gearbox and set per-wheel drive torque (wheel.driveTorque). Wheel ground torques must already be computed.
        /// Updates wheel omegas (drive + ground torque, then brakes), then applies diff-lock couplings.
        /// </summary>
        public void Step(float dt, float driveThrottle, float forwardSpeed, ref float fuel)
        {
            UpdateShares();
            AutoShift(dt, driveThrottle, forwardSpeed);

            bool run = engineOn && fuel > 0f;
            float r = rpm;
            float throttle = run ? Mathf.Clamp01(driveThrottle) : 0f;

            // ---- engine torque
            float tCurve = def.torqueCurve.Evaluate(Mathf.Clamp(r, def.idleRpm * 0.5f, def.redlineRpm)) * throttle;
            if (r > def.redlineRpm) tCurve = 0f;
            if (run && throttle < 0.02f && r < def.idleRpm) tCurve = Mathf.Max(tCurve, def.torqueCurve.Evaluate(def.idleRpm) * Mathf.Clamp01((def.idleRpm - r) / 200f) * 0.5f + 5f);   // idle governor
            float friction = def.engineFriction + def.engineBrakingPerKrpm * r * 0.001f;
            float tFric = run ? friction * (1f - 0.85f * throttle) : friction + 40f;
            engineTorque = tCurve - tFric;

            float ratio = TotalRatio(gear) * (1f);
            currentRatio = ratio;

            // ---- clutch / converter
            engagement = 0f;
            if (run && ratio != 0f && shiftTimer <= 0f)
                engagement = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(def.idleRpm + 30f, def.idleRpm + 900f, r));
            float tcMax = engagement * peakTorque * 1.8f;

            float Ie = def.engineInertia;
            float tc = 0f;
            float eta = def.gearbox.efficiency;

            if (ratio != 0f && engagement > 0f)
            {
                // implicit lock: A = sum(s_i^2/I_i), B = sum(s_i*Tg_i/I_i), omega_in = ratio * sum(s_i*omega_i)
                float A = 0f, B = 0f, wIn = 0f;
                for (int i = 0; i < wheels.Length; i++)
                {
                    float s = share[i]; if (s <= 0f) continue;
                    float I = Mathf.Max(0.5f, wheels[i].tire.inertia);
                    A += s * s / I;
                    B += s * (wheels[i].groundTorque) / I;
                    wIn += s * wheels[i].omega;
                }
                wIn *= ratio;
                float denom = dt * (1f / Ie + ratio * ratio * eta * A);
                float lockTc = (engineOmega - wIn + dt * engineTorque / Ie - dt * ratio * B) / Mathf.Max(1e-6f, denom);
                tc = Mathf.Clamp(lockTc, -tcMax, tcMax);
                clutchSlipping = Mathf.Abs(lockTc) > tcMax;
            }
            else clutchSlipping = false;
            clutchTorque = tc;

            // ---- engine integration
            engineOmega += dt * (engineTorque - tc) / Ie;
            if (engineOmega < 0f) engineOmega = 0f;
            float maxOmega = def.redlineRpm * 1.15f / 9.5492966f;
            if (engineOmega > maxOmega) engineOmega = maxOmega;

            // stall
            if (engineOn)
            {
                if (rpm < def.stallRpm && engagement > 0.05f) stallTimer += dt; else stallTimer = Mathf.Max(0f, stallTimer - dt);
                if (stallTimer > 0.5f) { engineOn = false; stallTimer = 0f; }
                if (fuel <= 0f) engineOn = false;
            }

            // ---- wheel torques & omega update
            float wheelTorque = tc * ratio * eta;
            wheelTorqueTotal = wheelTorque;
            for (int i = 0; i < wheels.Length; i++)
            {
                var w = wheels[i];
                w.driveTorque = wheelTorque * share[i];
                float I = Mathf.Max(0.5f, w.tire.inertia);
                float om = w.omega + dt * (w.driveTorque + w.groundTorque) / I;
                // brakes: impulse limited, cannot reverse the wheel
                float bt = w.brakeTorque;
                if (bt > 0f)
                {
                    float d = bt * dt / I;
                    if (Mathf.Abs(om) <= d) om = 0f; else om -= Mathf.Sign(om) * d;
                }
                w.omega = om;
            }

            ApplyCouplings(dt);

            // ---- fuel
            if (run)
            {
                float load = Mathf.Clamp01(Mathf.Max(0f, tCurve * engineOmega) / peakPower);
                loadFraction = load;
                fuelRateLitresPerHour = def.idleFuelRate + (def.fullLoadFuelRate - def.idleFuelRate) * load * (0.35f + 0.65f * throttle);
                fuel = Mathf.Max(0f, fuel - fuelRateLitresPerHour * dt / 3600f);
            }
            else { fuelRateLitresPerHour = 0f; loadFraction = 0f; }

            lockStress = Mathf.Max(0f, lockStress - 400f * dt);
        }

        // ------------------------------------------------------------------ diff locks

        void ApplyCouplings(float dt)
        {
            // axle diff locks: equalise left/right wheel speeds
            for (int a = 0; a < axleCount; a++)
            {
                if (!axleLock[a] || !def.axles[a].canLockDiff) continue;
                Wheel L = null, R = null;
                for (int i = 0; i < wheels.Length; i++) if (wheels[i].axleIndex == a) { if (wheels[i].isLeft) L = wheels[i]; else R = wheels[i]; }
                if (L == null || R == null) continue;
                float IL = Mathf.Max(0.5f, L.tire.inertia), IR = Mathf.Max(0.5f, R.tire.inertia);
                float Ir = IL * IR / (IL + IR);
                float T = (R.omega - L.omega) * Ir / dt;
                L.omega += T * dt / IL; R.omega -= T * dt / IR;
                lockStress += Mathf.Abs(T) * 0.02f;
            }
            // centre lock: equalise linear speed of the front group and the rest of the driven axles
            if (centreLock && def.hasCentreDiffLock)
            {
                double iF = 0, iR = 0, uF = 0, uR = 0; int nF = 0, nR = 0;
                for (int i = 0; i < wheels.Length; i++)
                {
                    var w = wheels[i];
                    if (!drivenAxle[w.axleIndex]) continue;
                    float r = w.tire.radius;
                    float iu = w.tire.inertia / (r * r);
                    if (w.axleIndex == 0) { iF += iu; uF += w.omega * r; nF++; } else { iR += iu; uR += w.omega * r; nR++; }
                }
                if (nF > 0 && nR > 0)
                {
                    uF /= nF; uR /= nR;
                    double Ir = iF * iR / (iF + iR);
                    double F = (uR - uF) * Ir / dt;   // force-like
                    double dUF = F * dt / iF, dUR = -F * dt / iR;
                    for (int i = 0; i < wheels.Length; i++)
                    {
                        var w = wheels[i];
                        if (!drivenAxle[w.axleIndex]) continue;
                        float r = w.tire.radius;
                        w.omega += (float)((w.axleIndex == 0 ? dUF : dUR) / r);
                    }
                    lockStress += (float)Math.Abs(F) * 0.01f;
                }
            }
        }
    }
}
