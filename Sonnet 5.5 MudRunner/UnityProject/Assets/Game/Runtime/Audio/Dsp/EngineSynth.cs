using System;
using System.Runtime.CompilerServices;

namespace MudRunner.Audio.Dsp
{
    /// <summary>
    /// Static description of one engine's sound. The synth is a "firing-pulse wavetable through exhaust resonances" model:
    ///  * one 720-degree (4-stroke) cycle of combustion pressure pulses, baked into two band-limited wavetables (soft = idle,
    ///    sharp = load) with the per-cylinder amplitude pattern of the firing order (uneven bank pairing = V8 burble);
    ///  * the table is read at rpm/120 Hz, so the dominant partial is the firing frequency rpm/60*cylinders/2;
    ///  * the pulse train excites fixed-frequency exhaust/body resonances (so timbre moves with rpm like a real pipe),
    ///    then a load-controlled low-pass; intake roar, diesel knock, valvetrain and turbo are added around it.
    /// </summary>
    public sealed class EngineProfile
    {
        public string name = "engine";
        public int cylinders = 4;
        public float idleRpm = 850f, redlineRpm = 5200f, stallRpm = 400f;
        public bool diesel;

        // pulse shapes in crank degrees: rise and decay time constants (soft table = idle, sharp table = load)
        public float riseSoft = 3f, decaySoft = 22f, riseSharp = 1f, decaySharp = 9f;
        public float[] fireAmp = { 1f, 1f, 1f, 1f };         // per firing pulse (baked into the tables)

        // exhaust / body resonances: parallel band-passes added to the dry pulse signal
        public float[] fmFreq = { 420f, 950f, 2300f };
        public float[] fmQ = { 2.2f, 3f, 3.5f };
        public float[] fmGain = { 1.6f, 1.8f, 1.2f };

        public float cutIdle = 1800f, cutLoad = 5200f;       // low-pass cutoff (Hz) at idle/no load and at full load/rpm
        public float hpHz = 35f;
        public float knock;                                   // combustion knock (diesel clatter) amount
        public float knockHz = 2200f;
        public float intake;                                  // intake roar amount
        public float intakeHz = 700f;
        public float mech;                                    // valvetrain / gear noise amount
        public float rough = 0.08f;                           // random per-firing amplitude variation (idle)
        public float turbo;                                   // turbo whistle amount (0 = none)
        public bool exhaustBrake;

        public float crankRpm = 170f, crankTime = 0.8f, ringTeeth = 120f;
        public float gain = 0.2f;                             // overall engine level

        /// <summary>Firing frequency (Hz) at a given rpm: rpm/60 * cylinders/2.</summary>
        public float FiringHz(float rpm) { return rpm / 60f * cylinders * 0.5f; }

        // ------------------------------------------------------------------ the three vehicles

        /// <summary>Small buzzy inline-4 petrol: even firing, thin sharp pulses, bright mid/upper resonances, strong intake howl.</summary>
        public static EngineProfile Scout()
        {
            return new EngineProfile
            {
                name = "scout", cylinders = 4, idleRpm = 850f, redlineRpm = 5200f, stallRpm = 400f, diesel = false,
                riseSoft = 1.5f, decaySoft = 9f, riseSharp = 0.4f, decaySharp = 3.5f,
                fireAmp = new[] { 1.00f, 0.93f, 1.06f, 0.97f },
                fmFreq = new[] { 450f, 1100f, 2600f }, fmQ = new[] { 2.2f, 3.0f, 3.5f }, fmGain = new[] { 1.2f, 1.6f, 1.4f },
                cutIdle = 3000f, cutLoad = 7500f, hpHz = 45f,
                knock = 0.06f, knockHz = 3200f, intake = 0.55f, intakeHz = 900f, mech = 0.30f, rough = 0.07f,
                turbo = 0f, exhaustBrake = false,
                crankRpm = 190f, crankTime = 0.75f, ringTeeth = 112f, gain = 0.22f,
            };
        }

        /// <summary>V8 diesel pick-up: cross-plane style bank pairing gives the lumpy burble, deep body resonances, moderate knock.</summary>
        public static EngineProfile Utility()
        {
            return new EngineProfile
            {
                name = "utility", cylinders = 8, idleRpm = 750f, redlineRpm = 4000f, stallRpm = 350f, diesel = true,
                riseSoft = 2f, decaySoft = 14f, riseSharp = 0.6f, decaySharp = 6f,
                fireAmp = BankPattern(new[] { 0, 1, 1, 0, 1, 0, 0, 1 }, 1.24f, 1.0f, 0.78f),
                fmFreq = new[] { 85f, 170f, 520f }, fmQ = new[] { 1.8f, 2.0f, 2.2f }, fmGain = new[] { 2.2f, 1.9f, 1.1f },
                cutIdle = 1300f, cutLoad = 3800f, hpHz = 30f,
                knock = 0.55f, knockHz = 1900f, intake = 0.22f, intakeHz = 420f, mech = 0.14f, rough = 0.14f,
                turbo = 0f, exhaustBrake = false,
                crankRpm = 170f, crankTime = 1.0f, ringTeeth = 132f, gain = 0.25f,
            };
        }

        /// <summary>Big inline-6 turbo diesel: heavy low drone, loud clatter at idle, turbo whistle/blow-off, exhaust brake.</summary>
        public static EngineProfile Hauler()
        {
            return new EngineProfile
            {
                name = "hauler", cylinders = 6, idleRpm = 650f, redlineRpm = 2800f, stallRpm = 300f, diesel = true,
                riseSoft = 2f, decaySoft = 12f, riseSharp = 0.5f, decaySharp = 5f,
                fireAmp = new[] { 1.00f, 0.95f, 1.05f, 0.98f, 1.03f, 0.96f },
                fmFreq = new[] { 62f, 125f, 330f }, fmQ = new[] { 1.5f, 1.9f, 2.2f }, fmGain = new[] { 2.4f, 2.0f, 1.2f },
                cutIdle = 1800f, cutLoad = 4500f, hpHz = 24f,
                knock = 0.85f, knockHz = 2000f, intake = 0.42f, intakeHz = 380f, mech = 0.18f, rough = 0.10f,
                turbo = 1f, exhaustBrake = true,
                crankRpm = 200f, crankTime = 1.35f, ringTeeth = 150f, gain = 0.23f,
            };
        }

        public static EngineProfile ForKey(string key)
        {
            switch ((key ?? "").ToLowerInvariant())
            {
                case "scout": return Scout();
                case "hauler": return Hauler();
                default: return Utility();
            }
        }

        /// <summary>Pick the closest of the three timbres from vehicle numbers and fit the rpm limits.</summary>
        public static EngineProfile ForVehicle(string vehicleName, float massKg, float idleRpm, float redlineRpm, float stallRpm)
        {
            string n = (vehicleName ?? "").ToLowerInvariant();
            EngineProfile p;
            if (n.Contains("scout") || n.Contains("pathfinder")) p = Scout();
            else if (n.Contains("hauler") || n.Contains("mammoth")) p = Hauler();
            else if (n.Contains("utility") || n.Contains("bruiser")) p = Utility();
            else p = massKg < 3000f ? Scout() : (massKg < 7000f ? Utility() : Hauler());
            if (idleRpm > 100f) p.idleRpm = idleRpm;
            if (redlineRpm > p.idleRpm + 500f) p.redlineRpm = redlineRpm;
            if (stallRpm > 50f) p.stallRpm = stallRpm;
            return p;
        }

        /// <summary>Per-firing amplitude from bank pairing: a firing that follows its own bank closely (short gap) is reinforced.</summary>
        public static float[] BankPattern(int[] bankOfFiring, float shortGain, float midGain, float longGain)
        {
            int n = bankOfFiring.Length;
            var a = new float[n];
            for (int i = 0; i < n; i++)
            {
                int gap = 1;
                while (gap < n && bankOfFiring[((i - gap) % n + n) % n] != bankOfFiring[i]) gap++;
                a[i] = gap == 1 ? shortGain : (gap == 2 ? midGain : longGain);
            }
            return a;
        }
    }

    /// <summary>Builds (and caches per profile instance) the two wavetables.</summary>
    public static class EngineTables
    {
        public const int Size = 4096;

        public static CycleTable Build(EngineProfile p, bool sharp)
        {
            var t = new CycleTable(Size);
            float rise = sharp ? p.riseSharp : p.riseSoft;
            float decay = sharp ? p.decaySharp : p.decaySoft;
            int cyl = p.cylinders;
            float degPerSample = 720f / Size;
            for (int i = 0; i < cyl; i++)
            {
                float a0 = i * 720f / cyl;
                float amp = p.fireAmp[i % p.fireAmp.Length];
                for (int j = 0; j < Size; j++)
                {
                    float d = j * degPerSample - a0;
                    if (d < 0f) d += 720f;
                    if (d > decay * 8f) continue;
                    t.data[j] += amp * (1f - MathF.Exp(-d / rise)) * MathF.Exp(-d / decay);
                }
            }
            // zero mean, fixed RMS so the sharp table is "more peaky" rather than louder
            double mean = 0;
            for (int j = 0; j < Size; j++) mean += t.data[j];
            mean /= Size;
            double e = 0;
            for (int j = 0; j < Size; j++) { t.data[j] -= (float)mean; e += (double)t.data[j] * t.data[j]; }
            float g = 0.3f / (float)Math.Sqrt(e / Size);
            for (int j = 0; j < Size; j++) t.data[j] *= g;
            t.Finish();
            return t;
        }
    }

    /// <summary>
    /// Real-time engine voice. Runs in chunks of up to 128 frames; per chunk it updates a small state machine
    /// (off / cranking / failed start / running / dying), smooths its controls and recomputes filter coefficients, then runs
    /// a tight per-sample loop with every filter state hoisted into locals (this matters a lot on the Mono JIT).
    /// Secondary layers (diesel knock, turbo, blow-off, starter whine) are added in separate short passes only while they are
    /// audible. No allocation after construction.
    /// </summary>
    public sealed class EngineSynth
    {
        const int Chunk = 128;
        const int StOff = 0, StCrank = 1, StFail = 2, StRun = 3, StDying = 4;

        public readonly EngineProfile profile;
        readonly float sr, invSr;
        readonly Rng rng;
        readonly CycleTable soft, sharp;
        readonly int nSeg;
        readonly float[] nz = new float[Chunk], scratch = new float[Chunk];

        // oscillator
        float phase, incCur, dInc;
        int lastSeg = -1;
        float gA = 1f, gB = 1f;

        // state
        int state = StOff;
        float stateT, catchT = 1f;
        bool init, stallMode;
        int seenStart, seenFail, seenStall;
        float rpmS, thrS, loadS, strainS, floodS, fire, comp, missP, boost, exB, rough, thrPrev, whineEnv, jitter, t;
        float whinePh;

        // filters / envelopes (states live in fields, hoisted into locals inside the loops)
        struct BqBp
        {
            public float b0, b2, a1, a2, z1, z2;
            /// <summary>RBJ constant-0-dB-peak band-pass (b1 = 0) with the formant gain folded in; direct form II transposed.</summary>
            public void Set(float fc, float q, float gain, float sr)
            {
                float w = DspMath.TwoPi * fc / sr, cw = MathF.Cos(w), al = MathF.Sin(w) / (2f * q), inv = 1f / (1f + al);
                b0 = gain * al * inv; b2 = -b0; a1 = -2f * cw * inv; a2 = (1f - al) * inv;
            }
        }
        BqBp bq0, bq1, bq2;
        Svf turboBp;
        readonly GrainMixer knockMixer = new GrainMixer();
        readonly float[][] knockGrains = new float[8][];
        float dcX1, dcY1, lp1, lp2, lp1s, lp2s, inLo, inHi, mechZ, jitterZ;
        float blowV, blowK;
        float turboPh, blowPh;

        public EngineSynth(EngineProfile profile, float sampleRate, uint seed = 12345u)
        {
            this.profile = profile; sr = sampleRate; invSr = 1f / sampleRate; rng = new Rng(seed);
            soft = EngineTables.Build(profile, false); sharp = EngineTables.Build(profile, true);
            nSeg = profile.cylinders;
            bq0.Set(profile.fmFreq[0], profile.fmQ[0], profile.fmGain[0], sr);
            bq1.Set(profile.fmFreq[1], profile.fmQ[1], profile.fmGain[1], sr);
            bq2.Set(profile.fmFreq[2], profile.fmQ[2], profile.fmGain[2], sr);
            turboBp.Set(6000f, 0.8f, sr);
            BuildKnockGrains();
            incCur = profile.idleRpm / 120f * invSr;
            rpmS = profile.idleRpm;
        }

        /// <summary>Pre-render the combustion-knock grains: band-passed noise with a fast exponential decay (diesel clatter / petrol tick).</summary>
        void BuildKnockGrains()
        {
            var r = new Rng(0xC10C4u + (uint)profile.cylinders * 77u);
            float tau = profile.diesel ? 0.0040f : 0.0016f;
            int len = (int)(tau * 6f * sr);
            var bp = new Svf(); bp.Set(profile.knockHz, 0.6f, sr);
            for (int v = 0; v < knockGrains.Length; v++)
            {
                var g = new float[len];
                bp.Reset();
                for (int j = 0; j < len; j++)
                {
                    float env = MathF.Exp(-j / (tau * sr));
                    g[j] = bp.Tick(r.Signed()) * bp.k * env * 1.8f;
                }
                knockGrains[v] = g;
            }
        }

        public bool IsSilent { get { return state == StOff && fire < 0.001f && rpmS < 25f && knockMixer.Active == 0 && boost < 0.01f; } }
        public int State { get { return state; } }

        public void Render(VehicleSignals s, float[] dst, int offset, int count)
        {
            if (!s.hasEngine) return;
            while (count > 0)
            {
                int n = count > Chunk ? Chunk : count;
                RenderChunk(s, dst, offset, n);
                offset += n; count -= n;
            }
        }

        float DrawGain()
        {
            if (fire > 0.999f || rng.Next01() < fire)
            {
                float g = 1f + rough * rng.Gauss();
                if (g < 0.15f) g = 0.15f;
                if (missP > 0f && rng.Next01() < missP) g = 0.1f;
                return g;
            }
            return comp;
        }

        void RenderChunk(VehicleSignals s, float[] dst, int off, int n)
        {
            var p = profile;
            float dt = n * invSr;
            t += dt;
            // self-heal: a poisoned state (NaN from a bad input in an earlier build / external misuse) must never stay in the oscillator or the smoothers
            if (!(rpmS >= 0f && rpmS < 50000f)) rpmS = p.idleRpm;
            if (!(thrS >= 0f && thrS <= 1.5f)) thrS = 0f;
            if (!(loadS >= 0f && loadS <= 1.5f)) loadS = 0f;
            if (!(strainS >= 0f && strainS <= 1.5f)) strainS = 0f;
            if (!(floodS >= 0f && floodS <= 1.5f)) floodS = 0f;
            if (!(boost >= 0f && boost <= 1.5f)) boost = 0f;
            if (!(exB >= 0f && exB <= 1.5f)) exB = 0f;
            if (!(fire >= 0f && fire <= 1.5f)) fire = 0f;
            if (!(comp >= 0f && comp <= 1.5f)) comp = 0f;
            if (!(phase >= 0f && phase < 1f)) phase = 0f;
            if (!(incCur >= 0f && incCur < 0.25f)) incCur = rpmS / 120f * invSr;
            if (!init)
            {
                seenStart = s.startCount; seenFail = s.failCount; seenStall = s.stallCount;
                state = s.engineOn ? StRun : StOff; fire = s.engineOn ? 1f : 0f; rpmS = s.rpm; init = true; catchT = 1f;
                incCur = rpmS / 120f * invSr;
            }

            // ---------------------------------------------------------------- state machine
            if (s.startCount != seenStart) { seenStart = s.startCount; state = StCrank; stateT = 0f; stallMode = false; }
            if (s.failCount != seenFail) { seenFail = s.failCount; state = StFail; stateT = 0f; }
            if (s.stallCount != seenStall) { seenStall = s.stallCount; stallMode = true; }
            bool on = s.engineOn;
            stateT += dt;
            switch (state)
            {
                case StOff: if (on) { state = StRun; stateT = 0f; catchT = 1f; fire = 1f; } break;
                case StCrank: if (stateT >= p.crankTime) { if (on) { state = StRun; stateT = 0f; catchT = 0f; } else state = StOff; } break;
                case StFail: if (stateT >= p.crankTime * 1.7f) state = StOff; break;
                case StRun: catchT += dt; if (!on) { state = StDying; stateT = 0f; } break;
                case StDying: if (on) { state = StRun; stateT = 0f; stallMode = false; catchT = 1f; } else if (stateT > 3f && rpmS < 40f) state = StOff; break;
            }
            bool cranking = state == StCrank || state == StFail;

            // ---------------------------------------------------------------- targets
            float rpmT = cranking ? p.crankRpm : s.rpm;
            float rpmTc = cranking ? 0.05f : (state == StRun && catchT < 0.4f ? 0.16f : 0.045f);
            rpmS += (rpmT - rpmS) * (1f - MathF.Exp(-dt / rpmTc));
            if (rpmS < 0f) rpmS = 0f;

            float fireT, fireTc, compT;
            switch (state)
            {
                case StRun: fireT = 1f; fireTc = catchT < 0.45f ? 0.30f : 0.04f; compT = 0f; break;
                case StCrank: fireT = 0f; fireTc = 0.02f; compT = 0.55f; break;
                case StFail: fireT = s.flood > 0.3f ? 0.14f : 0f; fireTc = 0.02f; compT = 0.5f; break;
                case StDying: fireT = 0f; fireTc = stallMode ? 0.55f : 0.07f; compT = 0.28f * DspMath.Clamp01(rpmS / Math.Max(1f, p.idleRpm)); break;
                default: fireT = 0f; fireTc = 0.05f; compT = 0.28f * DspMath.Clamp01(rpmS / Math.Max(1f, p.idleRpm)); break;
            }
            fire += (fireT - fire) * (1f - MathF.Exp(-dt / fireTc));
            comp += (compT - comp) * (1f - MathF.Exp(-dt / 0.03f));

            float aFast = 1f - MathF.Exp(-dt / 0.06f);
            thrS += (s.throttle - thrS) * aFast;
            loadS += (s.load - loadS) * (1f - MathF.Exp(-dt / 0.10f));
            strainS += (s.strain - strainS) * (1f - MathF.Exp(-dt / 0.25f));
            floodS += (s.flood - floodS) * (1f - MathF.Exp(-dt / 0.2f));
            float running = state == StRun ? 1f : 0f;

            float rpm01 = DspMath.Clamp01((rpmS - p.idleRpm) / Math.Max(1f, p.redlineRpm - p.idleRpm));
            float rpmFrac = DspMath.Clamp01(rpmS / Math.Max(1f, p.redlineRpm));

            // turbo spool: slow attack, slightly quicker release
            float boostT = p.turbo > 0f && state == StRun ? DspMath.Clamp01(loadS * 1.15f) * DspMath.SmoothStep(p.idleRpm * 1.1f, p.redlineRpm * 0.7f, rpmS) : 0f;
            boost += (boostT - boost) * (1f - MathF.Exp(-dt / (boostT > boost ? 0.55f : 0.40f)));
            if (p.turbo > 0f && thrPrev >= 0.5f && thrS < 0.5f && boost > 0.35f) { float a0 = boost * 0.9f; if (a0 > blowV) blowV = a0; blowK = MathF.Exp(-1f / (0.32f * sr)); }
            thrPrev = thrS;

            // exhaust brake (closed throttle, rolling, in gear)
            float exT = p.exhaustBrake && s.exhaustBrakeOk && s.throttle < 0.05f && rpmS > p.idleRpm * 1.5f && s.speed > 2f && state == StRun ? 1f : 0f;
            exB += (exT - exB) * (1f - MathF.Exp(-dt / 0.22f));

            // roughness / misfire
            rough = p.rough * (0.35f + 0.65f * (1f - rpm01) * (1f - rpm01)) + 0.12f * strainS + 0.35f * floodS;
            missP = 0.004f + 0.5f * floodS + (state == StRun && catchT < 0.45f ? 0.5f * (1f - catchT / 0.45f) : 0f);

            float whineT = (state == StCrank || state == StFail) ? 1f : 0f;
            if (state == StCrank && stateT > p.crankTime - 0.12f) whineT = 0f;
            whineEnv += (whineT - whineEnv) * (1f - MathF.Exp(-dt / (whineT > whineEnv ? 0.06f : 0.04f)));

            if (state == StOff && rpmS < 25f && fire < 0.001f && comp < 0.001f && knockMixer.Active == 0 && boost < 0.01f && blowV < 1e-4f && whineEnv < 1e-3f) { incCur = 0f; return; }

            // ---------------------------------------------------------------- jitter / hunting, cycle frequency ramp
            jitterZ += 0.02f * (rng.Signed() - jitterZ);
            jitter = jitterZ * 0.0045f * (0.5f + rough * 6f);
            float hunt = 1f + 0.012f * strainS * SinTable.Sin(t * 3.7f) + jitter;
            float fc = rpmS * hunt / 120f * s.doppler * invSr;
            if (incCur == 0f) incCur = fc;
            dInc = (fc - incCur) / n;

            // ---------------------------------------------------------------- per-chunk coefficients
            float lowLoad = Math.Max(loadS, 0.6f * thrS);
            float cut = DspMath.Lerp(p.cutIdle, p.cutLoad, DspMath.Clamp01(0.55f * lowLoad + 0.45f * rpm01 + 0.35f * exB));
            float aLp = DspMath.TptG(cut / 0.64f, sr);                                      // two cascaded TPT one-poles ~ 12 dB/oct, -3 dB at 'cut'
            float aInHi = 1f - MathF.Exp(-DspMath.TwoPi * (p.intakeHz * 1.4f + 0.5f * rpmS) * invSr);
            float aInLo = 1f - MathF.Exp(-DspMath.TwoPi * (p.intakeHz * 0.25f) * invSr);
            float mix = DspMath.Clamp01(0.10f + 0.80f * loadS + 0.35f * strainS + 0.9f * exB);
            float pulseAmp = 1f + 0.25f * strainS + 1.0f * exB;
            float intLvl = p.intake * 0.5f * (0.08f + 0.92f * thrS) * (0.1f + 0.9f * rpmFrac) * (0.4f + 0.6f * rpmFrac) * 2.2f;
            float knockAmp = p.knock * 0.9f * (1.1f - 0.7f * loadS) * (1.1f - 0.5f * rpm01);
            float mechLvl = p.mech * 0.05f * rpmFrac * rpmFrac * (0.3f + 0.7f * running);
            float mechA = 1f - MathF.Exp(-DspMath.TwoPi * 3500f * invSr);
            float lvl = p.gain * (0.50f + 0.50f * rpm01) * (0.55f + 0.45f * lowLoad) * (1f + 0.15f * strainS);
            if (cranking) lvl = Math.Max(lvl, p.gain * 0.8f);
            float dcR = 1f - DspMath.TwoPi * p.hpHz * invSr;

            // ---------------------------------------------------------------- the main per-sample loop (hoisted state)
            Block.Noise(rng, nz, n);
            var tS = soft.data; var tH = sharp.data;
            float b0a = bq0.b0, b2a = bq0.b2, a1a = bq0.a1, a2a = bq0.a2, z1a = bq0.z1, z2a = bq0.z2;
            float b0b = bq1.b0, b2b = bq1.b2, a1b = bq1.a1, a2b = bq1.a2, z1b = bq1.z1, z2b = bq1.z2;
            float b0c = bq2.b0, b2c = bq2.b2, a1c = bq2.a1, a2c = bq2.a2, z1c = bq2.z1, z2c = bq2.z2;
            float dcx1 = dcX1, dcy1 = dcY1, lpA = lp1s, lpB = lp2s;
            float inc = incCur, ph = phase, ga = gA, gb = gB;
            int seg = lastSeg;
            bool useSharp = mix > 0.001f, exOn = exB > 0.01f, crankMod = cranking;
            float exK = exB * 0.55f, nSegF = nSeg;
            var grains = knockGrains;

            for (int i = 0; i < n; i++)
            {
                float ii = inc;
                if (crankMod) ii *= 1f + 0.30f * SinTable.Cos(ph * nSegF);
                ph += ii; if (ph >= 1f) ph -= 1f;
                inc += dInc;

                float sf = ph * nSegF; int sg = (int)sf; float u = sf - sg;
                if (sg != seg)
                {
                    seg = sg; ga = gb; gb = DrawGain();
                    if (ga > 0.45f)
                    {
                        float a = knockAmp * ga * (0.6f + 0.4f * rng.Next01());
                        if (a > 0.003f) knockMixer.Add(grains[(int)(rng.NextU() & 7u)], i, a * lvl);
                    }
                }
                float g = ga + (gb - ga) * u;

                float xi = ph * 4096f; int ix = (int)xi; float fr = xi - ix;
                float x = tS[ix] + (tS[ix + 1] - tS[ix]) * fr;
                if (useSharp) { float ps = tH[ix] + (tH[ix + 1] - tH[ix]) * fr; x += (ps - x) * mix; }
                float w = nz[i];
                x *= g * pulseAmp;
                if (exOn) x += exK * w * (x < 0f ? -x : x);

                float dcy = x - dcx1 + dcR * dcy1; dcx1 = x; dcy1 = dcy; x = dcy;

                // three exhaust / body resonances (parallel band-passes, formant gain folded into the coefficients)
                float ya = b0a * x + z1a; z1a = z2a - a1a * ya; z2a = b2a * x - a2a * ya;
                float yb = b0b * x + z1b; z1b = z2b - a1b * yb; z2b = b2b * x - a2b * yb;
                float yc = b0c * x + z1c; z1c = z2c - a1c * yc; z2c = b2c * x - a2c * yc;
                float y = x + ya + yb + yc;

                float q1 = (y - lpA) * aLp; float yl1 = q1 + lpA; lpA = yl1 + q1;
                float q2 = (yl1 - lpB) * aLp; float yl2 = q2 + lpB; lpB = yl2 + q2;
                dst[off + i] += yl2 * lvl;
            }
            bq0.z1 = z1a; bq0.z2 = z2a; bq1.z1 = z1b; bq1.z2 = z2b; bq2.z1 = z1c; bq2.z2 = z2c;
            dcX1 = dcx1; dcY1 = dcy1; lp1s = lpA; lp2s = lpB;
            phase = ph; lastSeg = seg; gA = ga; gB = gb; incCur = inc;
            // self-heal: if a bad input ever poisoned the oscillator or the filters, restart them instead of staying silent forever
            float chk = lpA + lpB + z1a + z2a + z1b + z2b + z1c + z2c + dcx1 + dcy1 + ph + inc;
            if (!(chk > -1e6f && chk < 1e6f) || !(ph >= 0f && ph < 1f))
            {
                bq0.z1 = bq0.z2 = bq1.z1 = bq1.z2 = bq2.z1 = bq2.z2 = 0f; dcX1 = dcY1 = lp1s = lp2s = 0f; phase = 0f; lastSeg = -1; incCur = rpmS > 0f && rpmS < 50000f ? rpmS / 120f * invSr : 0f;
                if (!(rpmS >= 0f && rpmS < 50000f)) rpmS = p.idleRpm;
                gA = gB = 1f;
            }

            // ---------------------------------------------------------------- intake roar and valvetrain hiss (only while audible)
            if (intLvl > 0.003f)
            {
                float ihi = inHi, ilo = inLo, ig = intLvl * lvl;
                for (int i = 0; i < n; i++)
                {
                    float w = nz[i];
                    ihi += aInHi * (w - ihi); ilo += aInLo * (w - ilo);
                    dst[off + i] += (ihi - ilo) * ig;
                }
                inHi = ihi; inLo = ilo;
            }
            if (mechLvl > 0.0015f)
            {
                float mz = mechZ, mg = mechLvl * 6f * lvl;
                for (int i = 0; i < n; i++)
                {
                    float w = nz[(i + 53) & 127];
                    mz += mechA * (w - mz);
                    dst[off + i] += (w - mz) * mg;
                }
                mechZ = mz;
            }

            // ---------------------------------------------------------------- combustion knock grains
            knockMixer.Mix(dst, off, n);

            // ---------------------------------------------------------------- turbo whistle
            float turboA = p.turbo * 0.09f * boost * boost * MathF.Sqrt(boost);
            if (turboA > 1e-5f)
            {
                float f1 = (1500f + 3200f * boost) * invSr * s.doppler;
                float p1 = turboPh;
                var tt = HarmonicTables.Turbo;
                float tg = turboA * lvl;
                for (int i = 0; i < n; i++)
                {
                    p1 += f1; p1 -= (int)p1;
                    float x1 = p1 * 4096f; int i1 = (int)x1; float s1 = tt[i1] + (tt[i1 + 1] - tt[i1]) * (x1 - i1);
                    dst[off + i] += tg * s1 * (0.8f + 0.2f * nz[i]);
                }
                turboPh = p1;
            }

            // ---------------------------------------------------------------- turbo blow-off flutter
            if (blowV > 1e-4f)
            {
                float bv = blowV, bk = blowK, bph = blowPh, binc = 14f * invSr;
                var tab = SinTable.t;
                for (int i = 0; i < n; i++)
                {
                    bph += binc; bph -= (int)bph;
                    float xb = bph * 4096f; int ib = (int)xb; float sb = tab[ib] + (tab[ib + 1] - tab[ib]) * (xb - ib);
                    scratch[i] = bv * (0.55f + 0.45f * sb);
                    bv *= bk;
                }
                blowPh = bph; blowV = bv;
                Block.BandpassAddEnv(ref turboBp, nz, scratch, dst, off, n, 0.10f * lvl);
            }

            // ---------------------------------------------------------------- starter motor / ring-gear whine
            float whineA = 0.060f * whineEnv;
            if (whineA > 1e-5f)
            {
                float wi = rpmS / 60f * p.ringTeeth * invSr, wp = whinePh;
                var st = HarmonicTables.Starter;
                float cm = (0.75f + 0.25f * SinTable.Cos(ph * nSegF)) * whineA;
                for (int i = 0; i < n; i++)
                {
                    wp += wi; wp -= (int)wp;
                    float xw = wp * 4096f; int iw = (int)xw; float s1 = st[iw] + (st[iw + 1] - st[iw]) * (xw - iw);
                    dst[off + i] += cm * (s1 + 0.18f * nz[i]);
                }
                whinePh = wp;
            }
        }

        public void Reset()
        {
            phase = 0f; lastSeg = -1; gA = gB = 1f; init = false; state = StOff; fire = 0f; comp = 0f; boost = 0f; exB = 0f;
            bq0.z1 = bq0.z2 = bq1.z1 = bq1.z2 = bq2.z1 = bq2.z2 = 0f; turboBp.Reset();
            blowV = 0f; dcX1 = dcY1 = lp1 = lp2 = lp1s = lp2s = inLo = inHi = mechZ = jitterZ = 0f;
        }
    }
}
