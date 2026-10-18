using MudRunner.Audio.Dsp;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Audio
{
    /// <summary>
    /// Per-vehicle bridge between the simulation and its procedural voice. Lives on the vehicle's GameObject:
    ///  * FixedUpdate (after Vehicle / VehicleWater / Winch): reads wheels (slip, sinkage, load, suspension velocity, bump stops,
    ///    surface blend, water depth), detects discrete happenings (bump-stop thump, mud splash, water entry, rock hit, winch twang)
    ///    and accumulates the continuous drives for the tyres, creak and water synths;
    ///  * Update: engine telemetry (rpm, throttle, load, strain, flood), start / stall / shift / handbrake events, spatial values
    ///    from the <see cref="AudioDirector"/> (Doppler, distance, cabin), and publishes everything into <see cref="VehicleSignals"/>;
    ///  * OnCollisionEnter: body impacts classified by what was hit.
    /// The audio thread only ever reads the signals object and pops the event queue.
    /// </summary>
    [DefaultExecutionOrder(30)]
    public sealed class VehicleAudioDriver : MonoBehaviour
    {
        public Vehicle vehicle;
        public VehicleSignals signals;
        public VehicleSynth synth;
        public EngineProfile profile;
        public VehicleVoice voice;
        public AudioSource source;
        public Transform voiceTransform;
        public bool isPlayer;

        // spatial state (director writes)
        public float distanceToListener;
        public bool voiceActive = true;

        // ---- wheel bookkeeping
        float[] prevBump, prevSink, prevMudW, cooldown, airTime;
        bool[] prevWater, prevOnProp, prevGrounded;
        readonly float[] wbuf = new float[GroundMap.LayerCount];

        // ---- continuous drives gathered in FixedUpdate (smoothed here), consumed in Update
        float tMudRoll, tMudSlip, tSuction, tGravel, tGrass, tHard, tSand, tSkid, tBelly, tRev, tCreak, tCreakSpeed;
        float cMudRoll, cMudSlip, cSuction, cGravel, cGrass, cHard, cSand, cSkid, cBelly, cCreak, cCreakSpeed, cWading;

        // ---- engine / event state
        bool initialised, prevEngineOn, prevHandbrake, prevWinchAttached, prevStuck;
        int prevGear;
        float prevRpm, prevBrake, prevTension, splashCooldown, shiftCooldown, twangCooldown, impactCooldown, lowFuelTimer, stuckTimer;
        float flood01, strain01, load01;
        readonly Rng rng = new Rng(0xBEEFu);
        bool airBrakes;
        static int driverCounter;
        int faultCount;

        public void Init(Vehicle v, VehicleSignals sig, VehicleSynth syn, EngineProfile prof, VehicleVoice vv, AudioSource src, Transform vt)
        {
            vehicle = v; signals = sig; synth = syn; profile = prof; voice = vv; source = src; voiceTransform = vt;
            int n = v.wheels != null ? v.wheels.Length : 0;
            prevBump = new float[n]; prevSink = new float[n]; prevMudW = new float[n]; cooldown = new float[n];
            prevWater = new bool[n]; prevOnProp = new bool[n]; prevGrounded = new bool[n]; airTime = new float[n];
            airBrakes = prof != null && prof.name == "hauler";
            rng.Seed(0x9E3779B9u * (uint)(++driverCounter) + 17u);
        }

        static float Smooth01(float x) { x = Mathf.Clamp01(x); return x * x * (3f - 2f * x); }

        // ====================================================================== physics-rate analysis

        void FixedUpdate()
        {
            var v = vehicle;
            if (v == null || v.def == null || v.wheels == null || signals == null) return;
            var gs = GroundService.Instance;
            var map = gs != null ? gs.Map : null;
            var water = map != null ? map.water : null;
            float dt = Mathf.Max(1e-4f, Time.fixedDeltaTime);
            var wheels = v.wheels;
            int n = wheels.Length;
            float vBody = v.speed;

            float sMudRoll = 0, sMudSlip = 0, sSuction = 0, sGravel = 0, sGrass = 0, sHard = 0, sSand = 0, sSkid = 0, sRev = 0;
            float creak = 0f, speedAcc = 0f;
            int splashesThisStep = 0;

            for (int i = 0; i < n; i++)
            {
                var w = wheels[i];
                cooldown[i] -= dt;
                sRev += Mathf.Abs(w.omega) / (2f * Mathf.PI);
                float compV = (w.prevLength - w.length) / dt;         // + when compressing
                // the strut length jumps from full droop to the contact value when a wheel touches down: that is not a damper speed
                bool wasGrounded = prevGrounded[i];
                if (!wasGrounded) compV = 0f;
                compV = Mathf.Clamp(compV, -6f, 6f);
                float aV = Mathf.Abs(compV);

                if (w.grounded)
                {
                    // touch-down after being airborne: a thump scaled by the vertical speed of the body
                    if (!wasGrounded && airTime[i] > 0.12f && cooldown[i] <= 0f)
                    {
                        float vy = Mathf.Max(0f, -v.rb.linearVelocity.y);
                        signals.PushSfx(vy > 2.5f ? Sfx.BumpThump : Sfx.SuspClonk, Mathf.Clamp(0.25f + vy / 6f + airTime[i], 0.25f, 1f), rng.Range(0.9f, 1.1f));
                        cooldown[i] = 0.25f;
                    }
                    airTime[i] = 0f;
                    // ---------------- surface blend at the contact patch
                    Vector3 pc = w.patchCenter;
                    float wMud, wGravel, wGrass, wHard, wSand, wFirm, wRock;
                    if (map != null)
                    {
                        map.SampleWeights(pc.x, pc.z, wbuf);
                        wMud = wbuf[(int)SurfaceType.ShallowMud] * 0.75f + wbuf[(int)SurfaceType.DeepMud] + wbuf[(int)SurfaceType.Bog];
                        wGravel = wbuf[(int)SurfaceType.Gravel]; wGrass = wbuf[(int)SurfaceType.Grass];
                        wSand = wbuf[(int)SurfaceType.Sand]; wFirm = wbuf[(int)SurfaceType.FirmSoil]; wRock = wbuf[(int)SurfaceType.Rock];
                    }
                    else { wMud = wGravel = wGrass = wSand = 0f; wFirm = 1f; wRock = 0f; }
                    if (w.onProp) { wMud *= 0.3f; wRock = Mathf.Max(wRock, 0.7f); }
                    float wet = Mathf.Clamp01(w.soil.wet);
                    wHard = wRock + wFirm * (1f - 0.6f * wet);

                    float sinkNorm = Mathf.Clamp01(w.sinkage / 0.30f);
                    float slip = Mathf.Abs(w.slipVelocity);
                    float wm = Mathf.Clamp01(wMud + 0.25f * wet * wFirm + 0.35f * wet * wGrass);   // how "squishy" the ground feels
                    float depthTerm = 0.3f + 0.7f * sinkNorm;
                    float churnT = 0.65f + 0.7f * Mathf.Clamp01(w.churn);          // churned, liquefied mud squelches harder than virgin ground
                    float loadF = Smooth01(w.load / Mathf.Max(500f, w.staticLoad * 0.6f));

                    float rollT = Smooth01(vBody / 5f), slipT = Smooth01(slip / 5f);
                    sMudRoll += wm * depthTerm * rollT * loadF * churnT;
                    sMudSlip += wm * depthTerm * slipT * loadF * churnT;
                    sSuction += Mathf.Clamp01(wm * sinkNorm * churnT * (0.6f * Smooth01(vBody / 3f) + 0.8f * slipT));
                    sGravel += wGravel * Smooth01((vBody + 0.5f * slip) / 8f) * loadF;
                    sGrass += wGrass * (1f - 0.5f * wet) * Smooth01((vBody + 0.5f * slip) / 6f) * loadF;
                    sHard += wHard * Smooth01(vBody / 8f) * loadF;
                    sSand += wSand * Smooth01((vBody + 0.5f * slip) / 5f) * loadF;
                    sSkid += (wRock + 0.6f * wGravel + 0.5f * wFirm) * Smooth01((slip - 1.5f) / 5f) * loadF;

                    // ---------------- discrete events: mud splash on entering soft ground at speed
                    float sinkRate = (w.sinkage - prevSink[i]) / dt;
                    bool enteredMud = wm > 0.5f && prevMudW[i] <= 0.3f && vBody > 2.5f;
                    bool plunged = wm > 0.4f && sinkRate > 0.7f && vBody > 1f;
                    if ((enteredMud || plunged) && cooldown[i] <= 0f && splashesThisStep < 2)
                    {
                        float inten = Mathf.Clamp01(vBody / 11f + sinkRate * 0.25f);
                        bool big = inten > 0.55f && v.def.mass > 3000f || inten > 0.8f;
                        signals.PushSfx(big ? Sfx.MudSplashBig : Sfx.MudSplashSmall, 0.25f + 0.75f * inten, rng.Range(0.92f, 1.08f));
                        cooldown[i] = 0.35f; splashesThisStep++;
                    }
                    prevMudW[i] = wm; prevSink[i] = w.sinkage;

                    // ---------------- water at the patch: entry splash
                    bool inWater = false; float wDepth = 0f;
                    if (water != null && water.Sample(pc.x, pc.z, out float lvl, out _)) { wDepth = lvl - pc.y; inWater = wDepth > 0.06f; }
                    if (inWater && !prevWater[i] && vBody > 1.5f && splashCooldown <= 0f)
                    {
                        float inten = Mathf.Clamp01(vBody / 9f) * Mathf.Clamp01(0.35f + wDepth / 0.5f);
                        signals.PushSfx(inten > 0.55f ? Sfx.WaterSplashBig : Sfx.WaterSplashSmall, 0.25f + 0.75f * inten, rng.Range(0.92f, 1.08f));
                        splashCooldown = 0.18f;
                    }
                    prevWater[i] = inWater;

                    // ---------------- suspension: bump stop, damper clonk, rock strike
                    if (w.bumpPenetration > 0.008f && prevBump[i] <= 0.008f && cooldown[i] <= 0.1f)
                    {
                        float g = Mathf.Clamp(0.25f + w.bumpPenetration * 5f + compV * 0.2f, 0.2f, 1f);
                        signals.PushSfx(Sfx.BumpThump, g, rng.Range(0.9f, 1.1f));
                        cooldown[i] = Mathf.Max(cooldown[i], 0.18f);
                    }
                    else if (compV > 1.5f && cooldown[i] <= 0f)
                    {
                        signals.PushSfx(Sfx.SuspClonk, Mathf.Clamp01((compV - 1.2f) / 2.5f) * 0.7f + 0.2f, rng.Range(0.9f, 1.1f));
                        cooldown[i] = 0.2f;
                    }
                    if (w.onProp && !prevOnProp[i] && vBody > 1.5f && cooldown[i] <= 0f)
                    {
                        signals.PushSfx(Sfx.RockThud, Mathf.Clamp01(0.25f + vBody / 9f), rng.Range(0.9f, 1.1f));
                        cooldown[i] = 0.25f;
                    }
                    prevBump[i] = w.bumpPenetration; prevOnProp[i] = w.onProp;

                    // creak: articulation / slow-to-moderate strut motion under load
                    float hump = Smooth01(aV / 0.35f) * (1f - Smooth01((aV - 0.9f) / 1.5f));
                    creak += hump * loadF; speedAcc += aV;
                }
                else
                {
                    prevMudW[i] = 0f; prevSink[i] = 0f; prevBump[i] = 0f; prevWater[i] = false; prevOnProp[i] = false;
                    airTime[i] += dt;
                }
                prevGrounded[i] = w.grounded;
            }
            splashCooldown -= dt; shiftCooldown -= dt; twangCooldown -= dt; impactCooldown -= dt;

            // axle articulation (left vs right strut travel moving in opposite directions)
            for (int a = 0; a + 1 < n; a += 2)
            {
                var L = wheels[a]; var R = wheels[a + 1];
                float artic = Mathf.Abs((L.length - R.length) - (L.prevLength - R.prevLength)) / dt;
                if (L.grounded && R.grounded) creak += 0.8f * Smooth01(artic / 0.5f) * (1f - Smooth01((artic - 1.2f) / 1.5f));
            }

            float inv = n > 0 ? 1f / n : 0f;
            float norm = 1.25f * inv * (1f + 0.05f * Mathf.Max(0, n - 4));
            tMudRoll = Mathf.Clamp01(sMudRoll * norm); tMudSlip = Mathf.Clamp01(sMudSlip * norm); tSuction = Mathf.Clamp01(sSuction * norm);
            tGravel = Mathf.Clamp01(sGravel * norm); tGrass = Mathf.Clamp01(sGrass * norm); tHard = Mathf.Clamp01(sHard * norm);
            tSand = Mathf.Clamp01(sSand * norm); tSkid = Mathf.Clamp01(sSkid * norm);
            tBelly = Mathf.Clamp01(v.bellyContact * 1.5f) * Smooth01(vBody / 1.5f);
            tRev = sRev * inv;
            tCreak = Mathf.Clamp01(creak * 1.2f * inv * 2f);
            tCreakSpeed = Mathf.Clamp01(speedAcc * inv / 1.0f);

            // ---------------- winch hardware events
            var wn = v.winch;
            if (wn != null)
            {
                bool att = wn.Attached;
                if (att && !prevWinchAttached) signals.PushSfx(Sfx.HookClunk, 0.85f, rng.Range(0.95f, 1.05f));
                if (!att && prevWinchAttached) signals.PushSfx(Sfx.HookRelease, 0.75f, rng.Range(0.95f, 1.05f));
                float rated = Mathf.Max(1f, wn.ratedPull);
                float ten = wn.Tension / rated;
                float rate = (ten - prevTension) / dt;
                if (att && twangCooldown <= 0f && ((ten > 0.12f && prevTension < 0.03f) || rate > 2.5f) )
                {
                    signals.PushSfx(Sfx.RopeTwang, Mathf.Clamp(0.25f + ten * 1.2f, 0.3f, 1f), rng.Range(0.9f, 1.1f));
                    twangCooldown = 0.6f;
                }
                prevWinchAttached = att; prevTension = ten;
            }
        }

        // ====================================================================== frame-rate publishing

        void Update()
        {
            var v = vehicle;
            if (v == null || v.def == null || signals == null || v.drivetrain == null) return;
            float dt = Mathf.Max(1e-4f, Time.unscaledDeltaTime);
            var dr = v.drivetrain;
            var s = signals;
            var def = v.def;
            var wn = v.winch;
            var vw = v.water;

            bool trailer = def.isTrailer;
            s.hasEngine = !trailer;
            bool engineOn = dr.engineOn && v.fuel > 0f && !trailer;
            float rpm = dr.rpm;
            float rpmFrac = Mathf.Clamp01((rpm - def.idleRpm) / Mathf.Max(1f, def.redlineRpm - def.idleRpm));

            // ---------------- load / strain (lugging in mud) / flood
            float thr = v.throttleEff;
            float loadT = engineOn ? Mathf.Clamp01(Mathf.Max(thr * 0.9f, dr.loadFraction * 1.4f)) : 0f;
            float lowRpm = 1f - Smooth01((rpmFrac - 0.08f) / 0.30f);
            float st1 = Mathf.Clamp01((thr - 0.55f) / 0.45f) * lowRpm;
            float st2 = dr.clutchSlipping && thr > 0.5f ? Mathf.Clamp01(1f - v.speed / 4f) : 0f;
            float st3 = thr > 0.6f && v.meanSlipAbs > 0.45f ? Mathf.Clamp01((v.meanSlipAbs - 0.45f) * 2f) * (1f - Smooth01(v.speed / 8f)) : 0f;
            float strainT = engineOn ? Mathf.Clamp01(Mathf.Max(st1 * 0.9f, Mathf.Max(st2, st3 * 0.8f))) : 0f;
            float floodT = 0f;
            if (vw != null) floodT = vw.engineFlooded ? 1f : Mathf.Clamp01(vw.floodTimer / 0.6f);
            float a = 1f - Mathf.Exp(-dt / 0.08f);
            load01 += (loadT - load01) * a; strain01 += (strainT - strain01) * a; flood01 += (floodT - flood01) * a;

            // ---------------- transitions
            if (!initialised)
            {
                initialised = true;
                prevEngineOn = engineOn; prevGear = dr.gear; prevHandbrake = v.input.handbrake; prevRpm = rpm; prevBrake = v.brakeEff;
                prevStuck = v.isStuck;
            }
            if (engineOn && !prevEngineOn)
            {
                s.startCount++;
                s.PushSfx(Sfx.StarterClunk, 0.55f, rng.Range(0.95f, 1.05f));
            }
            else if (!engineOn && prevEngineOn)
            {
                bool stalled = v.fuel <= 0f || (vw != null && vw.engineFlooded) || (prevRpm < def.stallRpm * 1.8f && dr.engagement > 0.02f) || dr.stallTimer > 0f;
                if (stalled) s.stallCount++;
            }
            prevEngineOn = engineOn;
            // a failed key-turn: the player presses the ignition key while the engine cannot start
            if (isPlayer && !engineOn && !trailer && IgnitionPressed() && (v.fuel <= 0f || (vw != null && vw.engineFlooded))) s.failCount++;

            if (dr.gear != prevGear && !trailer)
            {
                OnGearChanged(prevGear, dr.gear);
                prevGear = dr.gear;
            }
            bool hb = v.input.handbrake;
            if (hb != prevHandbrake)
            {
                if (airBrakes) s.PushSfx(hb ? Sfx.AirPsstOn : Sfx.AirPsstOff, hb ? 0.75f : 0.6f, rng.Range(0.95f, 1.05f));
                else s.PushSfx(Sfx.HandbrakeRatchet, hb ? 0.6f : 0.35f, hb ? 1f : 1.25f);
                prevHandbrake = hb;
            }
            if (airBrakes && prevBrake > 0.45f && v.brakeEff < 0.05f && v.speed < 4f) s.PushSfx(Sfx.AirPsstOff, 0.5f, rng.Range(0.9f, 1.1f));
            prevBrake = v.brakeEff; prevRpm = rpm;

            // ---------------- continuous signals
            s.engineOn = engineOn; s.rpm = rpm; s.throttle = thr; s.load = load01; s.strain = strain01; s.flood = flood01;
            s.speed = v.speed; s.brake = v.brakeEff; s.handbrake = hb;
            s.exhaustBrakeOk = dr.gear > 0 && v.forwardSpeed > 1f;

            float ga = 1f - Mathf.Exp(-dt / 0.06f), gr = 1f - Mathf.Exp(-dt / 0.35f);
            cMudRoll += (tMudRoll - cMudRoll) * ga; cMudSlip += (tMudSlip - cMudSlip) * ga; cSuction += (tSuction - cSuction) * ga;
            cGravel += (tGravel - cGravel) * ga; cGrass += (tGrass - cGrass) * ga; cHard += (tHard - cHard) * ga;
            cSand += (tSand - cSand) * ga; cSkid += (tSkid - cSkid) * ga; cBelly += (tBelly - cBelly) * ga;
            cCreak += (tCreak - cCreak) * (tCreak > cCreak ? ga : gr); cCreakSpeed += (tCreakSpeed - cCreakSpeed) * ga;
            s.mudRoll = cMudRoll; s.mudSlip = cMudSlip; s.suction = cSuction; s.gravel = cGravel; s.grass = cGrass; s.hard = cHard;
            s.sand = cSand; s.skid = cSkid; s.belly = cBelly; s.wheelRev = tRev;
            s.creak = cCreak; s.creakSpeed = cCreakSpeed;
            var gs = GroundService.Instance;
            s.wetness = gs != null ? gs.wetness : 0f;

            // wading
            float wadeT = 0f, flow = 0f;
            if (vw != null)
            {
                float depth = Mathf.Max(vw.maxWaterDepthAtWheels, v.waterDepthAtVehicle);
                wadeT = Mathf.Clamp01(depth / 0.45f) * (0.25f + 0.75f * Smooth01(v.speed / 4f));
                flow = vw.currentSpeed;
            }
            cWading += (wadeT - cWading) * ga;
            s.wading = cWading; s.waterFlow = flow;

            // winch
            if (wn != null)
            {
                bool run = wn.Attached && Mathf.Abs(wn.input) > 0.01f;
                s.winchMotor = run ? 1f : 0f;
                s.winchLoad = Mathf.Clamp01(wn.Tension / Mathf.Max(1f, wn.ratedPull));
                s.winchDir = wn.input >= 0f ? 1f : -1f;
            }
            else { s.winchMotor = 0f; s.winchLoad = 0f; }

            s.Sanitize();

            // the audio thread parks a voice after an exception; rebuild its synth here (allocation is fine on the main thread)
            if (voice != null && voice.faulted && faultCount < 3)
            {
                faultCount++;
                var dir = AudioDirector.Instance;
                Debug.LogWarning("[MudRunner] audio voice of " + name + " raised an exception and was rebuilt (" + faultCount + ")");
                synth = new VehicleSynth(profile, dir != null ? dir.SampleRate : 48000, signals, dir != null ? dir.Bank : null, (uint)(1000 + faultCount));
                voice.synth = synth; voice.faulted = false;
            }
        }

        static bool IgnitionPressed()
        {
            var kb = UnityEngine.InputSystem.Keyboard.current;
            return kb != null && kb.iKey.wasPressedThisFrame;
        }

        void OnGearChanged(int from, int to)
        {
            var v = vehicle; var dr = v.drivetrain; var s = signals; var def = v.def;
            if (shiftCooldown > 0f || to == 0 || from == 0) { return; }
            shiftCooldown = 0.15f;
            bool heavy = def.mass > 3000f;
            float g = Mathf.Clamp(0.35f + 0.6f * load01, 0.35f, 1f);
            // grinding: manual shift with a large engine/wheel speed mismatch, or reverse engaged while rolling
            float mismatch = 0f;
            if (dr.mode == GearMode.Manual)
            {
                float wIn = 0f; int cnt = 0;
                for (int i = 0; i < v.wheels.Length; i++) if (dr.AxleDriven(v.wheels[i].axleIndex)) { wIn += Mathf.Abs(v.wheels[i].omega); cnt++; }
                if (cnt > 0)
                {
                    float eq = wIn / cnt * Mathf.Abs(dr.TotalRatio(to)) * 9.5493f;
                    mismatch = Mathf.Abs(dr.rpm - eq) / Mathf.Max(dr.rpm, def.idleRpm);
                }
            }
            bool dirChange = (from < 0) != (to < 0) && Mathf.Abs(v.forwardSpeed) > 2.5f;
            float grind = Mathf.Max(Mathf.Clamp01((mismatch - 0.30f) / 0.6f) * (v.input.throttle > 0.15f ? 1f : 0.5f), dirChange ? 0.8f : 0f);
            if (grind > 0.1f) s.PushSfx(Sfx.GearGrind, 0.35f + 0.6f * grind, rng.Range(0.9f, 1.1f));
            s.PushSfx(heavy ? Sfx.ShiftClunkHeavy : Sfx.ShiftClunkLight, g * (heavy ? 0.85f : 0.7f), rng.Range(0.94f, 1.06f));
        }

        // ====================================================================== collisions

        void OnCollisionEnter(Collision c)
        {
            var v = vehicle;
            if (v == null || v.rb == null || signals == null || impactCooldown > 0f) return;
            float j = c.impulse.magnitude / Mathf.Max(1f, v.rb.mass);     // velocity change of the vehicle (m/s)
            float rv = c.relativeVelocity.magnitude;
            float inten = Mathf.Clamp01((Mathf.Max(j, rv * 0.6f) - 0.25f) / 6f);
            if (inten < 0.03f) return;
            Sfx id = ClassifyImpact(c.collider, inten);
            impactCooldown = 0.08f;
            signals.PushSfx(id, 0.2f + 0.8f * inten, rng.Range(0.92f, 1.08f));
            if (inten > 0.7f && id != Sfx.VehicleCrunch) signals.PushSfx(Sfx.VehicleCrunch, 0.5f * inten, rng.Range(0.95f, 1.05f));
        }

        /// <summary>Pick the impact sound from what was hit (layer first, then object name hints).</summary>
        public static Sfx ClassifyImpact(Collider other, float inten)
        {
            if (other == null) return Sfx.MetalThud;
            int layer = other.gameObject.layer;
            string name = other.gameObject.name;
            if (layer == GameLayers.VehicleBody) return inten > 0.45f ? Sfx.VehicleCrunch : Sfx.MetalThud;
            if (Has(name, "rock") || Has(name, "stone") || Has(name, "boulder") || Has(name, "cliff")) return Sfx.RockThud;
            if (Has(name, "log") || Has(name, "tree") || Has(name, "trunk") || Has(name, "wood") || Has(name, "crate") || Has(name, "plank")) return Sfx.WoodThunk;
            if (layer == GameLayers.DynamicProps) return Sfx.CargoClank;
            if (layer == GameLayers.Debris) return Sfx.PlasticThud;
            if (Has(name, "bush") || Has(name, "plastic") || Has(name, "cone")) return Sfx.PlasticThud;
            return Sfx.MetalThud;
        }

        static bool Has(string s, string what) { return s != null && s.IndexOf(what, System.StringComparison.OrdinalIgnoreCase) >= 0; }
    }
}
