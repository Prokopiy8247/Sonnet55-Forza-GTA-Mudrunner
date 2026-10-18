using System;

namespace MudRunner.Audio.Dsp
{
    /// <summary>Environment description for the global stereo ambience voice (written by the director ~5x per second).</summary>
    public sealed class AmbienceParams
    {
        public float wind;          // 0..1 weather wind
        public float speedWind;     // 0..1 wind noise from the player's own speed
        public float rain;          // 0..1 intensity
        public float roof;          // 0..1 rain drumming on the cabin roof (cockpit view)
        public float wetGround;     // 0..1 puddles / drips
        public float day;           // 0..1 daylight (bird activity)
        public float night;         // 0..1 darkness (insects, frogs)
        public float forest;        // 0..1 tree cover
        public float swamp;         // 0..1 swamp / water margin
        public float cabin;         // 0..1 muffling when in the cockpit
        public float master = 1f;

        static float F(float v, float lo, float hi) { if (float.IsNaN(v)) return lo; return v < lo ? lo : (v > hi ? hi : v); }

        /// <summary>Copy with NaN/Infinity removed and every value clamped to 0..1 (master 0..4).</summary>
        public void CopySanitizedTo(AmbienceParams d)
        {
            d.wind = F(wind, 0f, 1f); d.speedWind = F(speedWind, 0f, 1f); d.rain = F(rain, 0f, 1f); d.roof = F(roof, 0f, 1f); d.wetGround = F(wetGround, 0f, 1f);
            d.day = F(day, 0f, 1f); d.night = F(night, 0f, 1f); d.forest = F(forest, 0f, 1f); d.swamp = F(swamp, 0f, 1f); d.cabin = F(cabin, 0f, 1f);
            d.master = F(master, 0f, 4f);
        }
    }

    /// <summary>
    /// Global stereo ambience bed: wind (gusting filtered noise with a whistling resonance), rain (hiss + droplet patter + puddle
    /// bubbles + roof drumming), forest birds (frequency-contour chirp phrases), crickets (pulse-gated 4-5 kHz tones), frogs
    /// (pulsed saw through two formants, peepers) and wind in the trees. Every component sleeps when its drive is ~0, and all
    /// loops are block passes with hoisted state (cheap on the Mono JIT).
    /// </summary>
    public sealed class AmbienceSynth
    {
        const int Chunk = 128;
        readonly float sr, invSr;
        readonly Rng rng;
        readonly AmbienceParams clean = new AmbienceParams();
        readonly float[] nL = new float[Chunk], nR = new float[Chunk], tmp = new float[Chunk], tmp2 = new float[Chunk], env = new float[Chunk];
        readonly int[] evPos = new int[24];
        readonly float[] evAmp = new float[24];

        // smoothed environment
        float wind, speedWind, rain, roof, wetGround, day, night, forest, swamp, cabin, master = 1f;
        float t, gustNoise, gust;

        // wind state
        float pkL0, pkL1, pkL2, pkR0, pkR1, pkR2;
        float bodyL1, bodyL2, bodyR1, bodyR2, rumbleL, rumbleR;
        Svf whistleL, whistleR;
        // rain state
        float hpL, hpR, rl1, rl2, rr1, rr2, roarL, roarR;
        Svf dropL, dropR, roofA, roofB;
        float dropEnvL, dropEnvR, dropAccL, dropAccR, roofAcc, roofEnvA, roofEnvB, puddleAcc;
        readonly BubbleBank puddles;
        // trees
        Svf treeBp; float treeZ;
        // cabin muffle
        float cabL1, cabL2, cabR1, cabR2;

        // ---- birds
        struct Bird
        {
            public bool active, inGap;
            public int species, notesLeft, notesTotal;
            public float noteT, noteDur, gapT, gapDur, f0, f1, f2, amp, pan, fmRate, fmDepth, amRate, ph, vibPh, baseF;
        }
        readonly Bird[] birds = new Bird[4];
        float birdTimer = 1.5f;

        // ---- crickets
        struct Cricket
        {
            public float carrier, ph, pulseRate, pulsePh, onDur, offDur, tPhase, amp, pan, gate, thr;
            public bool on;
        }
        readonly Cricket[] crickets = new Cricket[5];

        // ---- frogs
        struct Frog
        {
            public bool peeper;
            public float saw, sawInc, pulsePh, pulseRate, croakT, croakDur, gapT, amp, pan, base1, ph2, tone, thr;
            public Svf f1, f2;
        }
        readonly Frog[] frogs = new Frog[3];

        public AmbienceSynth(float sampleRate, uint seed = 555u)
        {
            sr = sampleRate; invSr = 1f / sampleRate; rng = new Rng(seed);
            DspWarmup.Touch();
            puddles = new BubbleBank(sampleRate);
            treeBp.Set(1100f, 0.5f, sr);
            dropL.Set(3000f, 4f, sr); dropR.Set(3500f, 4f, sr);
            roofA.Set(980f, 6f, sr); roofB.Set(2350f, 7f, sr);
            whistleL.Set(600f, 3.5f, sr); whistleR.Set(640f, 3.5f, sr);
            for (int i = 0; i < crickets.Length; i++)
            {
                crickets[i].carrier = rng.Range(3800f, 5300f); crickets[i].pulseRate = rng.Range(26f, 40f);
                crickets[i].onDur = rng.Range(0.12f, 0.35f); crickets[i].offDur = rng.Range(0.3f, 1.1f); crickets[i].tPhase = rng.Range(0f, 1f);
                crickets[i].amp = rng.Range(0.5f, 1f); crickets[i].pan = rng.Range(-0.95f, 0.95f); crickets[i].thr = 0.08f + 0.17f * i;
            }
            for (int i = 0; i < frogs.Length; i++)
            {
                frogs[i].peeper = i == 2;
                frogs[i].sawInc = rng.Range(85f, 140f) * invSr; frogs[i].pulseRate = rng.Range(18f, 27f);
                frogs[i].croakDur = rng.Range(0.35f, 0.7f); frogs[i].gapT = rng.Range(0.5f, 3f); frogs[i].croakT = 99f;
                frogs[i].amp = rng.Range(0.6f, 1f); frogs[i].pan = rng.Range(-0.9f, 0.9f); frogs[i].base1 = rng.Range(2400f, 3200f);
                frogs[i].f1.Set(520f + 60f * i, 4f, sr); frogs[i].f2.Set(1650f + 150f * i, 4f, sr);
                frogs[i].thr = 0.05f + 0.2f * i;
            }
        }

        public void Render(AmbienceParams p, float[] left, float[] right, int offset, int count)
        {
            while (count > 0)
            {
                int n = count > Chunk ? Chunk : count;
                RenderChunk(p, left, right, offset, n);
                offset += n; count -= n;
            }
        }

        static void Smooth(ref float cur, float target, float a) { cur += (target - cur) * a; }

        /// <summary>Poisson events in a chunk (integrated-rate method); returns the count, positions in evPos.</summary>
        int Events(ref float acc, float ratePerSample, int n, int max)
        {
            float total = ratePerSample * n, left = total;
            int cnt = 0;
            if (!(total > 1e-9f)) return 0;
            if (acc <= 0f) acc = rng.Exp(1f);
            while (acc <= left && cnt < max)
            {
                left -= acc;
                int pos = (int)((total - left) / total * n);
                evPos[cnt++] = pos >= n ? n - 1 : pos;
                acc = rng.Exp(1f);
            }
            acc -= left;
            return cnt;
        }

        void RenderChunk(AmbienceParams raw, float[] L, float[] R, int off, int n)
        {
            raw.CopySanitizedTo(clean);
            var p = clean;
            float dt = n * invSr;
            t += dt;
            float a = 1f - MathF.Exp(-dt / 0.6f);
            Smooth(ref wind, p.wind, a); Smooth(ref speedWind, p.speedWind, 1f - MathF.Exp(-dt / 0.15f));
            Smooth(ref rain, p.rain, a); Smooth(ref roof, p.roof, a); Smooth(ref wetGround, p.wetGround, a);
            Smooth(ref day, p.day, a); Smooth(ref night, p.night, a); Smooth(ref forest, p.forest, a); Smooth(ref swamp, p.swamp, a);
            Smooth(ref cabin, p.cabin, 1f - MathF.Exp(-dt / 0.2f));
            float masterPrev = master;
            Smooth(ref master, p.master, 1f - MathF.Exp(-dt / 0.1f));

            Array.Clear(L, off, n); Array.Clear(R, off, n);
            Block.Noise(rng, nL, n); Block.Noise(rng, nR, n);

            // gust: sum of slow sines + low-pass noise (once per chunk)
            gustNoise += 0.012f * (rng.Signed() - gustNoise);
            gust = DspMath.Clamp01(0.5f + 0.28f * SinTable.Sin(t * 0.11f) + 0.17f * SinTable.Sin(t * 0.27f + 0.3f) + 0.1f * SinTable.Sin(t * 0.61f + 0.7f) + 3.2f * gustNoise);

            RenderWind(L, R, off, n);
            if (rain > 0.004f || roof > 0.004f) RenderRain(L, R, off, n);
            if (day * (0.15f + forest) > 0.01f && rain < 0.9f) RenderBirds(L, R, off, n, dt);
            if (night > 0.05f) { RenderCrickets(L, R, off, n); if (swamp > 0.05f || rain > 0.2f) RenderFrogs(L, R, off, n); }
            if (forest * (wind + 0.5f * speedWind) > 0.005f) RenderTrees(L, R, off, n);

            // cabin muffling (cockpit view): two cascaded one-poles per ear
            if (cabin > 0.02f)
            {
                float cut = (20000f - 17500f * cabin) / 0.64f;
                float ca = 1f - MathF.Exp(-DspMath.TwoPi * cut * invSr);
                float gl = 1f - 0.25f * cabin;
                float l1 = cabL1, l2 = cabL2, r1 = cabR1, r2 = cabR2;
                for (int i = 0; i < n; i++)
                {
                    l1 += ca * (L[off + i] - l1); l2 += ca * (l1 - l2); L[off + i] = l2 * gl;
                    r1 += ca * (R[off + i] - r1); r2 += ca * (r1 - r2); R[off + i] = r2 * gl;
                }
                cabL1 = l1; cabL2 = l2; cabR1 = r1; cabR2 = r2;
            }

            // master gain ramp + soft knee limiter (linear below 0.8)
            float mg = masterPrev, dmg = (master - masterPrev) / n;
            for (int i = 0; i < n; i++)
            {
                mg += dmg;
                float l = L[off + i] * mg, r = R[off + i] * mg;
                if (l > 0.75f || l < -0.75f) l = DspMath.SoftKnee(l);
                if (r > 0.75f || r < -0.75f) r = DspMath.SoftKnee(r);
                L[off + i] = l; R[off + i] = r;
            }
        }

        // ------------------------------------------------------------------ wind
        void RenderWind(float[] L, float[] R, int off, int n)
        {
            float w = DspMath.Clamp01(wind * (0.45f + 0.9f * gust) + speedWind);
            if (w < 0.01f) return;
            float lvl = 0.13f * MathF.Pow(w, 1.35f);
            float bodyFc = 150f + 1000f * w;
            float ba = 1f - MathF.Exp(-DspMath.TwoPi * (bodyFc / 0.64f) * invSr);
            float baR = 1f - MathF.Exp(-DspMath.TwoPi * (bodyFc * 1.03f / 0.64f) * invSr);
            float wf = 380f + 900f * w + 160f * SinTable.Sin(t * 0.17f);
            whistleL.Set(wf, 3.5f, sr); whistleR.Set(wf * 1.06f, 3.5f, sr);
            float whistleLvl = 0.55f * w * w * lvl;
            float rumbleA = 1f - MathF.Exp(-DspMath.TwoPi * 110f * invSr);
            float rumbleLvl = 1.5f * w * w * lvl;
            float bodyG = 2.4f * lvl;

            // left ear
            {
                float b0 = pkL0, b1 = pkL1, b2 = pkL2, y1 = bodyL1, y2 = bodyL2, rz = rumbleL;
                for (int i = 0; i < n; i++)
                {
                    float wn = nL[i];
                    b0 = 0.99765f * b0 + wn * 0.0990460f; b1 = 0.96300f * b1 + wn * 0.2965164f; b2 = 0.57000f * b2 + wn * 1.0526913f;
                    float pk = (b0 + b1 + b2 + wn * 0.1848f) * 0.25f;
                    tmp[i] = pk;
                    y1 += ba * (pk - y1); y2 += ba * (y1 - y2);
                    rz += rumbleA * (wn - rz);
                    L[off + i] += y2 * bodyG + rz * rumbleLvl;
                }
                pkL0 = b0; pkL1 = b1; pkL2 = b2; bodyL1 = y1; bodyL2 = y2; rumbleL = rz;
                Block.BandpassAdd(ref whistleL, tmp, L, off, n, whistleLvl);
            }
            // right ear
            {
                float b0 = pkR0, b1 = pkR1, b2 = pkR2, y1 = bodyR1, y2 = bodyR2, rz = rumbleR;
                for (int i = 0; i < n; i++)
                {
                    float wn = nR[i];
                    b0 = 0.99765f * b0 + wn * 0.0990460f; b1 = 0.96300f * b1 + wn * 0.2965164f; b2 = 0.57000f * b2 + wn * 1.0526913f;
                    float pk = (b0 + b1 + b2 + wn * 0.1848f) * 0.25f;
                    tmp[i] = pk;
                    y1 += baR * (pk - y1); y2 += baR * (y1 - y2);
                    rz += rumbleA * (wn - rz);
                    R[off + i] += y2 * bodyG + rz * rumbleLvl;
                }
                pkR0 = b0; pkR1 = b1; pkR2 = b2; bodyR1 = y1; bodyR2 = y2; rumbleR = rz;
                Block.BandpassAdd(ref whistleR, tmp, R, off, n, whistleLvl);
            }
        }

        // ------------------------------------------------------------------ rain
        void FillDropEnv(ref float acc, ref float v, float rate, float amp, int n)
        {
            int ne = Events(ref acc, rate, n, 20);
            for (int e = 0; e < ne; e++) evAmp[e] = amp * rng.Range(0.3f, 1f);
            float k = MathF.Exp(-1f / (0.004f * sr)), vv = v; int ei = 0;
            for (int i = 0; i < n; i++)
            {
                while (ei < ne && evPos[ei] == i) { if (evAmp[ei] > vv) vv = evAmp[ei]; ei++; }
                env[i] = vv; vv *= k;
            }
            v = vv < 1e-5f ? 0f : vv;
        }

        void RenderRain(float[] L, float[] R, int off, int n)
        {
            float r = rain;
            if (r > 0.004f)
            {
                float hissLvl = 0.121f * MathF.Pow(r, 0.72f) * 1.6f;
                float roarLvl = 0.3f * r * r * 1.5f;
                float aHp = 1f - MathF.Exp(-DspMath.TwoPi * 1300f * invSr);
                float aLp = DspMath.TptG((9000f - 2500f * (1f - r)) / 0.64f, sr);
                float aRoar = 1f - MathF.Exp(-DspMath.TwoPi * 520f * invSr);
                float dropRate = (30f + 1500f * r) * invSr;
                float dropAmp = 0.32f * MathF.Pow(r, 0.7f);

                // left ear: hiss (high-pass then 12 dB/oct low-pass), roar, droplet patter
                {
                    float hp = hpL, s1 = rl1, s2 = rl2, rz = roarL;
                    for (int i = 0; i < n; i++)
                    {
                        float w = nL[i];
                        hp += aHp * (w - hp); float h = w - hp;
                        float q1 = (h - s1) * aLp; float y1 = q1 + s1; s1 = y1 + q1;
                        float q2 = (y1 - s2) * aLp; float y2 = q2 + s2; s2 = y2 + q2;
                        rz += aRoar * (w - rz);
                        L[off + i] += y2 * hissLvl + rz * roarLvl;
                    }
                    hpL = hp; rl1 = s1; rl2 = s2; roarL = rz;
                    FillDropEnv(ref dropAccL, ref dropEnvL, dropRate, dropAmp, n);
                    dropL.Set(rng.Range(1500f, 6500f), 4f, sr);
                    Block.BandpassAddEnv(ref dropL, nL, env, L, off, n, 1f);
                }
                {
                    float hp = hpR, s1 = rr1, s2 = rr2, rz = roarR;
                    for (int i = 0; i < n; i++)
                    {
                        float w = nR[i];
                        hp += aHp * (w - hp); float h = w - hp;
                        float q1 = (h - s1) * aLp; float y1 = q1 + s1; s1 = y1 + q1;
                        float q2 = (y1 - s2) * aLp; float y2 = q2 + s2; s2 = y2 + q2;
                        rz += aRoar * (w - rz);
                        R[off + i] += y2 * hissLvl + rz * roarLvl;
                    }
                    hpR = hp; rr1 = s1; rr2 = s2; roarR = rz;
                    FillDropEnv(ref dropAccR, ref dropEnvR, dropRate, dropAmp, n);
                    dropR.Set(rng.Range(1500f, 6500f), 4f, sr);
                    Block.BandpassAddEnv(ref dropR, nR, env, R, off, n, 1f);
                }

                // puddle plinks
                float pr = wetGround * r * 55f * invSr;
                if (pr > 0f)
                {
                    int ne = Events(ref puddleAcc, pr, n, 4);
                    for (int e = 0; e < ne; e++)
                    {
                        float tau = rng.Range(0.006f, 0.02f);
                        puddles.Trigger(rng.Range(600f, 2800f), tau, 0.18f * rng.Range(0.3f, 1f), rng.Range(0.1f, 0.35f) / tau, evPos[e]);
                    }
                }
                if (puddles.Active)
                {
                    for (int i = 0; i < n; i++) tmp[i] = 0f;
                    puddles.AddBlock(tmp, 0, n);
                    for (int i = 0; i < n; i++) { L[off + i] += tmp[i] * 0.8f; R[off + i] += tmp[i] * 0.6f; }
                }
            }
            if (roof > 0.004f)
            {
                // heavier drops on the sheet-metal roof: two resonant modes, a few dozen per second
                float rr = (14f + 110f * Math.Max(rain, 0.05f)) * invSr;
                float amp = 1.5f * roof * MathF.Sqrt(Math.Max(rain, 0.02f));
                int ne = Events(ref roofAcc, rr, n, 8);
                for (int e = 0; e < ne; e++) evAmp[e] = rng.Range(0.3f, 1f) * amp;
                float ka = MathF.Exp(-1f / (0.012f * sr)), kb = MathF.Exp(-1f / (0.007f * sr));
                float va = roofEnvA, vb = roofEnvB; int ei = 0;
                for (int i = 0; i < n; i++)
                {
                    while (ei < ne && evPos[ei] == i) { if (evAmp[ei] > va) va = evAmp[ei]; if (evAmp[ei] * 0.6f > vb) vb = evAmp[ei] * 0.6f; ei++; }
                    env[i] = va; tmp2[i] = vb; va *= ka; vb *= kb;
                }
                roofEnvA = va < 1e-5f ? 0f : va; roofEnvB = vb < 1e-5f ? 0f : vb;
                for (int i = 0; i < n; i++) tmp[i] = 0f;
                Block.BandpassAddEnv(ref roofA, nL, env, tmp, 0, n, 1f);
                Block.BandpassAddEnv(ref roofB, nR, tmp2, tmp, 0, n, 1f);
                for (int i = 0; i < n; i++) { L[off + i] += tmp[i]; R[off + i] += tmp[i]; }
            }
        }

        // ------------------------------------------------------------------ trees rustle
        void RenderTrees(float[] L, float[] R, int off, int n)
        {
            float w = DspMath.Clamp01(wind * (0.4f + gust) + speedWind * 0.6f);
            float lvl = 0.16f * forest * MathF.Pow(w, 1.2f);
            if (lvl < 0.001f) return;
            float am = 1f - MathF.Exp(-DspMath.TwoPi * 5f * invSr);
            treeBp.Set(1000f + 900f * w, 0.5f, sr);
            float z = treeZ;
            for (int i = 0; i < n; i++)
            {
                z += am * (nR[(i + 37) & 127] - z);
                float e = 0.5f + 30f * z; e = e < 0.1f ? 0.1f : (e > 1.5f ? 1.5f : e);
                env[i] = e;
            }
            treeZ = z;
            for (int i = 0; i < n; i++) tmp[i] = 0f;
            Block.BandpassAddEnv(ref treeBp, nL, env, tmp, 0, n, lvl);
            for (int i = 0; i < n; i++) { L[off + i] += tmp[i]; R[off + i] += tmp[i] * 0.9f; }
        }

        // ------------------------------------------------------------------ birds
        void StartPhrase(ref Bird b)
        {
            float r = rng.Next01();
            b.species = r < 0.30f ? 0 : (r < 0.50f ? 1 : (r < 0.64f ? 2 : (r < 0.74f ? 3 : 4)));
            b.active = true; b.inGap = false; b.gapT = 0f;
            b.amp = rng.Range(0.07f, 0.34f) * (0.5f + 0.5f * forest); b.pan = rng.Range(-0.9f, 0.9f);
            switch (b.species)
            {
                case 0: b.notesTotal = 3 + rng.Int(4); b.baseF = rng.Range(3000f, 4200f); break;
                case 1: b.notesTotal = 2 + rng.Int(2); b.baseF = rng.Range(1800f, 2600f); break;
                case 2: b.notesTotal = 1; b.baseF = rng.Range(2800f, 3600f); break;
                case 3: b.notesTotal = 2; b.baseF = rng.Range(560f, 800f); break;
                default: b.notesTotal = 8 + rng.Int(7); b.baseF = rng.Range(3000f, 4400f); break;
            }
            b.notesLeft = b.notesTotal;
            StartNote(ref b);
        }

        void StartNote(ref Bird b)
        {
            int idx = b.notesTotal - b.notesLeft;
            b.noteT = 0f; b.inGap = false; b.fmRate = 0f; b.fmDepth = 0f; b.amRate = 0f; b.vibPh = 0f; b.ph = 0f;
            switch (b.species)
            {
                case 0:
                    b.noteDur = rng.Range(0.07f, 0.11f); b.gapDur = rng.Range(0.05f, 0.09f);
                    b.f0 = b.baseF * rng.Range(0.88f, 0.94f); b.f1 = b.baseF * rng.Range(1.18f, 1.3f); b.f2 = b.baseF * rng.Range(0.95f, 1.05f); break;
                case 1:
                {
                    bool rising = (idx & 1) == 0 ? rng.Next01() < 0.6f : rng.Next01() < 0.3f;
                    b.noteDur = rng.Range(0.22f, 0.4f); b.gapDur = rng.Range(0.1f, 0.16f);
                    float a = b.baseF * 0.8f, c = b.baseF * 1.2f;
                    b.f0 = rising ? a : c; b.f2 = rising ? c : a; b.f1 = 0.5f * (a + c) * rng.Range(0.97f, 1.04f);
                    b.fmRate = 6f; b.fmDepth = 0.012f; break;
                }
                case 2:
                    b.noteDur = rng.Range(0.45f, 0.9f); b.gapDur = 0f;
                    b.f0 = b.baseF * 0.97f; b.f1 = b.baseF * 1.03f; b.f2 = b.baseF; b.fmRate = rng.Range(24f, 32f); b.fmDepth = 0.11f; b.amRate = b.fmRate; break;
                case 3:
                    b.noteDur = 0.25f; b.gapDur = 0.2f;
                    b.f0 = b.baseF * (idx == 0 ? 1f : 0.93f); b.f1 = b.f0 * 0.92f; b.f2 = b.f0 * 0.78f; break;
                default:
                    b.noteDur = rng.Range(0.04f, 0.07f); b.gapDur = rng.Range(0.025f, 0.05f);
                    { float bf = b.baseF * rng.Range(0.75f, 1.3f); b.f0 = bf * 0.9f; b.f1 = bf * 1.1f; b.f2 = bf * 1.2f; } break;
            }
        }

        void RenderBirds(float[] L, float[] R, int off, int n, float dt)
        {
            float rate = 0.5f * day * (0.15f + forest) * (1f - 0.9f * rain) * (1f - 0.5f * wind);
            birdTimer -= dt;
            if (birdTimer <= 0f)
            {
                birdTimer = rng.Exp(1f / Math.Max(0.02f, rate));
                for (int i = 0; i < birds.Length; i++)
                    if (!birds[i].active) { StartPhrase(ref birds[i]); break; }
            }
            var tab = SinTable.t;
            for (int bi = 0; bi < birds.Length; bi++)
            {
                if (!birds[bi].active) continue;
                ref Bird b = ref birds[bi];
                float gl = MathF.Sqrt(0.5f * (1f - b.pan)), gr = MathF.Sqrt(0.5f * (1f + b.pan));
                int i = 0;
                while (i < n && b.active)
                {
                    if (b.inGap)
                    {
                        float remain = b.gapDur - b.gapT;
                        int gs = (int)(remain * sr);
                        if (gs > n - i) { b.gapT += (n - i) * invSr; i = n; break; }
                        i += Math.Max(gs, 0); b.gapT = b.gapDur;
                        b.notesLeft--; if (b.notesLeft <= 0) { b.active = false; break; }
                        StartNote(ref b);
                        continue;
                    }
                    // render the note (or the part that fits into this chunk)
                    int noteLeft = (int)((b.noteDur - b.noteT) * sr);
                    int m = Math.Min(n - i, Math.Max(noteLeft, 0));
                    float invDur = 1f / b.noteDur;
                    float ph = b.ph, vp = b.vibPh, nt = b.noteT;
                    float fmInc = b.fmRate * invSr, fmD = b.fmDepth, amp = b.amp;
                    bool fm = fmD > 0f, am = b.amRate > 0f, coo = b.species == 3;
                    for (int j = 0; j < m; j++)
                    {
                        float u = nt * invDur;
                        float f = u < 0.5f ? b.f0 + (b.f1 - b.f0) * (u * 2f) : b.f1 + (b.f2 - b.f1) * ((u - 0.5f) * 2f);
                        if (fm) { vp += fmInc; vp -= (int)vp; float xv = vp * 4096f; int iv = (int)xv; f *= 1f + fmD * (tab[iv] + (tab[iv + 1] - tab[iv]) * (xv - iv)); }
                        ph += f * invSr; ph -= (int)ph;
                        float xe = u * 2048f; int ie = (int)xe; float e = tab[ie] + (tab[ie + 1] - tab[ie]) * (xe - ie);       // sin(pi*u)
                        e = coo ? e * e : e * MathF.Sqrt(e < 0f ? 0f : e);
                        if (am) { float xa = (vp + 0.25f) * 4096f; xa -= 4096f * (int)(xa * (1f / 4096f)); int ia = (int)xa; e *= 0.65f + 0.35f * (tab[ia] + (tab[ia + 1] - tab[ia]) * (xa - ia)); }
                        float xs = ph * 4096f; int isn = (int)xs; float sfr = xs - isn;
                        float s1 = tab[isn] + (tab[isn + 1] - tab[isn]) * sfr;
                        int i2 = (isn * 2) & 4095; float s2 = tab[i2];
                        float o = (s1 + 0.18f * s2) * e * amp;
                        L[off + i + j] += o * gl; R[off + i + j] += o * gr;
                        nt += invSr;
                    }
                    b.ph = ph; b.vibPh = vp; b.noteT = nt;
                    i += m;
                    if (nt >= b.noteDur - invSr)
                    {
                        if (b.gapDur <= 0f) { b.notesLeft--; if (b.notesLeft <= 0) { b.active = false; break; } StartNote(ref b); }
                        else { b.inGap = true; b.gapT = 0f; }
                    }
                    else if (m == 0) { b.noteT = b.noteDur; }
                }
            }
        }

        // ------------------------------------------------------------------ crickets
        void RenderCrickets(float[] L, float[] R, int off, int n)
        {
            var tab = SinTable.t;
            for (int ci = 0; ci < crickets.Length; ci++)
            {
                ref Cricket c = ref crickets[ci];
                if (night < c.thr) { c.gate = 0f; continue; }
                float lvl = 0.07f * c.amp * DspMath.SmoothStep(c.thr, c.thr + 0.3f, night) * (1f - 0.8f * rain);
                // on/off chirp groups advance once per chunk
                c.tPhase += n * invSr;
                float lim = c.on ? c.onDur : c.offDur;
                if (c.tPhase >= lim) { c.tPhase = 0f; c.on = !c.on; if (c.on) { c.onDur = rng.Range(0.12f, 0.35f); c.offDur = rng.Range(0.3f, 1.1f); c.pulsePh = 0f; } }
                float g0 = c.gate, gT = c.on ? 1f : 0f;
                float g1 = g0 + (gT - g0) * 0.35f;
                c.gate = g1;
                if (lvl < 1e-4f || (g0 < 0.002f && g1 < 0.002f)) continue;
                float gl = MathF.Sqrt(0.5f * (1f - c.pan)), gr = MathF.Sqrt(0.5f * (1f + c.pan));
                float carInc = c.carrier * invSr, pulInc = c.pulseRate * invSr;
                float ph = c.ph, pp = c.pulsePh, g = g0, dg = (g1 - g0) / n;
                for (int i = 0; i < n; i++)
                {
                    ph += carInc; ph -= (int)ph; pp += pulInc; pp -= (int)pp;
                    // pulse envelope: sin^2 of the first half of the cycle, silent in the second half
                    float pe = pp < 0.5f ? 4f * pp * (1f - 2f * pp) * 2f : 0f;      // parabola 0..1..0 over the first half
                    float x = ph * 4096f; int ix = (int)x;
                    float o = (tab[ix] + (tab[ix + 1] - tab[ix]) * (x - ix)) * pe * g * lvl;
                    L[off + i] += o * gl; R[off + i] += o * gr;
                    g += dg;
                }
                c.ph = ph; c.pulsePh = pp;
            }
        }

        // ------------------------------------------------------------------ frogs
        void RenderFrogs(float[] L, float[] R, int off, int n)
        {
            var tab = SinTable.t;
            float act = DspMath.Clamp01(night * swamp + 0.5f * rain * swamp + 0.15f * night);
            for (int fi = 0; fi < frogs.Length; fi++)
            {
                ref Frog f = ref frogs[fi];
                if (act < f.thr) continue;
                float lvl = 0.2f * f.amp * DspMath.SmoothStep(f.thr, f.thr + 0.3f, act);
                float gl = MathF.Sqrt(0.5f * (1f - f.pan)), gr = MathF.Sqrt(0.5f * (1f + f.pan));
                int i = 0;
                while (i < n)
                {
                    if (f.croakT > f.croakDur)
                    {
                        // resting: count the gap down and maybe start the next croak
                        f.gapT -= (n - i) * invSr;
                        if (f.gapT > 0f) break;
                        f.croakT = 0f; f.gapT = rng.Range(0.6f, 3.2f) / Math.Max(0.3f, act);
                        f.croakDur = f.peeper ? rng.Range(0.07f, 0.11f) : rng.Range(0.3f, 0.7f);
                        f.sawInc = (f.peeper ? 0f : rng.Range(80f, 145f)) * invSr; f.pulseRate = rng.Range(18f, 27f); f.pulsePh = 0f; f.tone = rng.Range(0.95f, 1.1f);
                        continue;
                    }
                    int m = Math.Min(n - i, Math.Max(1, (int)((f.croakDur - f.croakT) * sr)));
                    float invDur = 1f / f.croakDur, ct = f.croakT;
                    if (f.peeper)
                    {
                        float ph = f.ph2, bi = f.base1 * f.tone * invSr;
                        for (int j = 0; j < m; j++)
                        {
                            float u = ct * invDur;
                            ph += bi * (0.9f + 0.25f * u); ph -= (int)ph;
                            float x = ph * 4096f; int ix = (int)x; float s = tab[ix] + (tab[ix + 1] - tab[ix]) * (x - ix);
                            float xe = u * 2048f; int ie = (int)xe; float e = tab[ie] + (tab[ie + 1] - tab[ie]) * (xe - ie);
                            float o = s * e * 0.5f * lvl;
                            L[off + i + j] += o * gl; R[off + i + j] += o * gr;
                            ct += invSr;
                        }
                        f.ph2 = ph;
                    }
                    else
                    {
                        float sw = f.saw, pp = f.pulsePh, sInc = f.sawInc, pInc = f.pulseRate * invSr;
                        float a1 = f.f1.a1, a2 = f.f1.a2, a3 = f.f1.a3, c1 = f.f1.ic1, c2 = f.f1.ic2, k1 = f.f1.k * 0.8f;
                        float b1 = f.f2.a1, b2 = f.f2.a2, b3 = f.f2.a3, d1 = f.f2.ic1, d2 = f.f2.ic2, k2 = f.f2.k * 0.45f;
                        for (int j = 0; j < m; j++)
                        {
                            float u = ct * invDur;
                            sw += sInc * (1f - 0.12f * u); sw -= (int)sw;
                            pp += pInc; pp -= (int)pp;
                            float pe = pp < 0.5f ? 2f * pp : 2f - 2f * pp;                // triangle pulses
                            float x = (sw * 2f - 1f) * pe;
                            float v3 = x - c2; float v1 = a1 * c1 + a2 * v3; float v2 = c2 + a2 * c1 + a3 * v3; c1 = 2f * v1 - c1; c2 = 2f * v2 - c2;
                            float o = v1 * k1;
                            v3 = x - d2; v1 = b1 * d1 + b2 * v3; v2 = d2 + b2 * d1 + b3 * v3; d1 = 2f * v1 - d1; d2 = 2f * v2 - d2;
                            o += v1 * k2;
                            float xe = u * 2048f; int ie = (int)xe; float e = tab[ie] + (tab[ie + 1] - tab[ie]) * (xe - ie);
                            o *= e * 1.2f * lvl;
                            L[off + i + j] += o * gl; R[off + i + j] += o * gr;
                            ct += invSr;
                        }
                        f.saw = sw; f.pulsePh = pp; f.f1.ic1 = c1; f.f1.ic2 = c2; f.f2.ic1 = d1; f.f2.ic2 = d2;
                    }
                    f.croakT = ct + 0f;
                    if (f.croakT >= f.croakDur) f.croakT = f.croakDur + 1e-4f;
                    i += m;
                }
            }
        }
    }

    /// <summary>Mono flowing-water bed (river / stream / swamp lapping) rendered at the nearest water position.</summary>
    public sealed class RiverSynth
    {
        const int Chunk = 128;
        readonly float sr, invSr;
        readonly Rng rng;
        readonly float[] noise = new float[Chunk], noise2 = new float[Chunk], pinkBuf = new float[Chunk], env = new float[Chunk], tmp = new float[Chunk];
        readonly int[] evPos = new int[16];
        Svf rush;
        readonly BubbleBank bubbles;
        float pk0, pk1, pk2, turbZ, hissZ, lowZ, bubAcc, dcX, dcY;
        float level, flow, t;

        public RiverSynth(float sampleRate, uint seed = 2718u)
        {
            sr = sampleRate; invSr = 1f / sampleRate; rng = new Rng(seed);
            DspWarmup.Touch();
            bubbles = new BubbleBank(sampleRate);
            rush.Set(500f, 0.55f, sr);
        }

        /// <param name="levelT">0..1 loudness (proximity)</param>
        /// <param name="flowT">current speed in m/s (0 = still swamp water)</param>
        public void Render(float levelT, float flowT, float[] dst, int offset, int count)
        {
            while (count > 0)
            {
                int n = count > Chunk ? Chunk : count;
                RenderChunk(levelT, flowT, dst, offset, n);
                offset += n; count -= n;
            }
        }

        void RenderChunk(float levelT, float flowT, float[] dst, int off, int n)
        {
            if (!(levelT >= 0f && levelT <= 4f)) levelT = 0f;
            if (!(flowT >= 0f && flowT <= 30f)) flowT = 0f;
            float dt = n * invSr; t += dt;
            level += (levelT - level) * (1f - MathF.Exp(-dt / 0.4f));
            flow += (flowT - flow) * (1f - MathF.Exp(-dt / 0.8f));
            if (level < 0.003f) { Array.Clear(dst, off, n); return; }
            float fn = DspMath.Clamp01(flow / 2.5f);
            float lvl = 0.30f * level * (0.2f + 0.8f * fn);
            Block.Noise(rng, noise, n); Block.Noise(rng, noise2, n);
            rush.Set(260f + 700f * fn, 0.55f, sr);
            float turbA = 1f - MathF.Exp(-DspMath.TwoPi * 1.3f * invSr);
            float hiA = 1f - MathF.Exp(-DspMath.TwoPi * (3500f + 1500f * fn) * invSr);
            float loA = 1f - MathF.Exp(-DspMath.TwoPi * 130f * invSr);
            float hissG = 0.22f * fn * fn;

            float b0 = pk0, b1 = pk1, b2 = pk2, tz = turbZ, hz = hissZ, lz = lowZ;
            for (int i = 0; i < n; i++)
            {
                float w = noise[i];
                b0 = 0.99765f * b0 + w * 0.0990460f; b1 = 0.96300f * b1 + w * 0.2965164f; b2 = 0.57000f * b2 + w * 1.0526913f;
                float pk = (b0 + b1 + b2 + w * 0.1848f) * 0.25f;
                pinkBuf[i] = pk;
                tz += turbA * (noise2[i] - tz);
                float turb = 0.65f + 45f * tz; turb = turb < 0.2f ? 0.2f : (turb > 1.4f ? 1.4f : turb);
                env[i] = turb;
                hz += hiA * (w - hz); lz += loA * (pk - lz);
                // hiss (high-passed white) and low rumble share the turbulence envelope; the rush is added by the band-pass pass
                dst[off + i] = ((w - hz) * hissG + lz * 0.35f * 2.2f) * turb * lvl;
            }
            pk0 = b0; pk1 = b1; pk2 = b2; turbZ = tz; hissZ = hz; lowZ = lz;
            Block.BandpassAddEnv(ref rush, pinkBuf, env, dst, off, n, 0.7f * lvl);

            // bubbling
            float rate = (8f + 260f * fn * fn + 40f * level) * invSr;
            float total = rate * n, left = total; int cnt = 0;
            if (bubAcc <= 0f) bubAcc = rng.Exp(1f);
            while (bubAcc <= left && cnt < 16)
            {
                left -= bubAcc;
                int pos = (int)((total - left) / total * n); evPos[cnt++] = pos >= n ? n - 1 : pos;
                bubAcc = rng.Exp(1f);
            }
            bubAcc -= left;
            for (int e = 0; e < cnt; e++)
            {
                float tau = rng.Range(0.006f, 0.03f);
                bubbles.Trigger(rng.Range(350f, 3200f), tau, 0.25f * rng.Range(0.3f, 1f), rng.Range(0.1f, 0.3f) / tau, evPos[e]);
            }
            bubbles.AddBlock(dst, off, n, fn * lvl);

            // remove sub-audible drift of the pink noise
            float x1 = dcX, y1 = dcY;
            for (int i = 0; i < n; i++) { float x = dst[off + i]; float y = x - x1 + 0.9985f * y1; x1 = x; y1 = y; dst[off + i] = y; }
            dcX = x1; dcY = y1;
        }
    }
}
