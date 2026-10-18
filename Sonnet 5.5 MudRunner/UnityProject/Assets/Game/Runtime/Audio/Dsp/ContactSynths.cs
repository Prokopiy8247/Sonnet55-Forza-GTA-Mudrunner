using System;

namespace MudRunner.Audio.Dsp
{
    /// <summary>
    /// Tyre / ground noise of one vehicle (all wheels aggregated by the driver into a few 0..1 drives).
    /// Mud = filtered "slurp" noise + Minnaert suction pops + flung-mud spray; gravel = Poisson grain clicks into two stone
    /// resonances; grass = soft swish; hard ground = tyre hum + tread tone; sand = hiss; skid = stick-slip scrub; belly drag.
    /// Each component only runs while its drive is non-negligible, as a short pass over a 128-sample chunk (state in locals).
    /// </summary>
    public sealed class SurfaceSynth
    {
        const int Chunk = 128;
        readonly float sr, invSr;
        readonly Rng rng;
        readonly float[] noise = new float[Chunk], noise2 = new float[Chunk], env = new float[Chunk], tmp = new float[Chunk], hb = new float[Chunk / 2 + 1];
        readonly int[] evPos = new int[24];
        readonly float[] evAmp = new float[24];

        float mRoll, mSlip, suc, grv, grs, hrd, snd, skd, bel, rev, wet;
        Svf mudBp, sucBp, sprayBp, gravA, gravB, grassBp, hardBp, sandBp, skidBp, bellyBp;
        readonly BubbleBank pops;
        float slurpZ, grassZ, hardLoZ, sprayV, sprayK, slurpLast;
        float popAcc, sprayAcc, gravAcc, halfPrev;
        float sucPh, lugPh, lugPh2, skidPh, grassPh;
        int gravHot;

        public SurfaceSynth(float sampleRate, uint seed = 4242u)
        {
            sr = sampleRate; invSr = 1f / sampleRate; rng = new Rng(seed);
            pops = new BubbleBank(sampleRate);
            gravA.Set(2300f, 3.2f, sr); gravB.Set(4600f, 3.8f, sr);
            sucBp.Set(120f, 1.1f, sr * 0.5f);
            hardBp.Set(650f, 0.9f, sr);
            grassBp.Set(1900f, 0.55f, sr);
            sandBp.Set(2200f, 0.45f, sr);
            skidBp.Set(1400f, 2.2f, sr);
            bellyBp.Set(230f, 0.7f, sr);
            sprayBp.Set(1500f, 1.3f, sr);
            mudBp.Set(300f, 0.9f, sr * 0.5f);
            sprayK = MathF.Exp(-1f / (0.03f * sr));
        }

        public void Render(VehicleSignals s, float[] dst, int offset, int count)
        {
            while (count > 0)
            {
                int n = count > Chunk ? Chunk : count;
                RenderChunk(s, dst, offset, n);
                offset += n; count -= n;
            }
        }

        public bool IsQuiet { get { return mRoll + mSlip + suc + grv + grs + hrd + snd + skd + bel < 0.003f; } }

        /// <summary>Poisson events inside a chunk using the integrated-rate method; positions are written ascending.</summary>
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

        void RenderChunk(VehicleSignals s, float[] dst, int off, int n)
        {
            float dt = n * invSr;
            float a = 1f - MathF.Exp(-dt / 0.07f);
            mRoll += (s.mudRoll - mRoll) * a; mSlip += (s.mudSlip - mSlip) * a; suc += (s.suction - suc) * a;
            grv += (s.gravel - grv) * a; grs += (s.grass - grs) * a; hrd += (s.hard - hrd) * a; snd += (s.sand - snd) * a;
            skd += (s.skid - skd) * a; bel += (s.belly - bel) * a; rev += (s.wheelRev - rev) * a; wet += (s.wetness - wet) * a;
            if (mRoll + mSlip + suc + grv + grs + hrd + snd + skd + bel < 0.002f) return;

            float lugHz = DspMath.Clamp(rev * 22f, 25f, 420f);
            Block.Noise(rng, noise, n); Block.Noise(rng, noise2, n);
            var tab = SinTable.t;

            // ------------------------------------------------------------- mud: slurp body + suction + pops + spray
            float mudDrive = DspMath.Clamp01(mRoll * 0.75f + mSlip);
            if (mudDrive > 0.004f || suc > 0.004f)
            {
                // the slurp body and the sub-bass suction are low-frequency textures: synthesised at half rate, then interpolated
                float lvl = 0.33f * MathF.Pow(mudDrive, 0.85f);
                int m = (n + 1) >> 1;
                float srH = sr * 0.5f;
                bool wrote = false;
                if (lvl > 1e-4f)
                {
                    float slA = 1f - MathF.Exp(-DspMath.TwoPi * 12f / srH);
                    float z = slurpZ;
                    for (int k = 0; k < m; k++)
                    {
                        z += slA * (noise2[k] - z);
                        float e = 0.5f + 20f * z; e = e < 0.05f ? 0.05f : (e > 1.4f ? 1.4f : e);
                        env[k] = e;
                    }
                    slurpZ = z; slurpLast = DspMath.Clamp01(env[m - 1] * 0.7f);
                    mudBp.Set(210f + 420f * slurpLast + 120f * wet, 0.9f, srH);
                    for (int k = 0; k < m; k++) hb[k] = 0f;
                    wrote = true;
                    Block.BandpassAddEnv(ref mudBp, noise, env, hb, 0, m, lvl);
                }
                else slurpLast *= 0.98f;

                // sub "whump" of the suction (modulated at the wheel revolution rate)
                float sucLvl = 0.55f * MathF.Pow(suc, 0.9f);
                if (sucLvl > 0.002f)
                {
                    if (!wrote) { for (int k = 0; k < m; k++) hb[k] = 0f; wrote = true; }
                    // slow LFO (wheel revolution rate): evaluated at both ends of the chunk and ramped in between
                    float rv = Math.Max(0.4f, rev) * invSr * n;
                    float ph1 = sucPh + rv; ph1 -= (int)ph1;
                    float l0 = 0.5f + 0.5f * SinTable.Sin(sucPh), l1 = 0.5f + 0.5f * SinTable.Sin(ph1), dl = (l1 - l0) / m;
                    for (int k = 0; k < m; k++) { tmp[k] = l0 * l0; l0 += dl; }
                    sucPh = ph1;
                    sucBp.Set(95f + 110f * slurpLast, 1.1f, srH);
                    Block.BandpassAddEnv(ref sucBp, noise2, tmp, hb, 0, m, sucLvl * 1.6f);
                }
                if (wrote) Block.UpsampleAdd(hb, m, dst, off, n, ref halfPrev);

                // suction pops (Minnaert bubbles)
                float popRate = (1.5f + 15f * suc + 10f * mSlip + 4f * mRoll) * invSr;
                float popAmp = 0.2f * (0.35f + MathF.Max(mudDrive, suc));
                int ne = Events(ref popAcc, popRate, n, 6);
                for (int e = 0; e < ne; e++)
                {
                    float tau = rng.Range(0.018f, 0.05f);
                    pops.Trigger(rng.Range(85f, 330f), tau, popAmp * rng.Range(0.35f, 1f), rng.Range(0.08f, 0.2f) / tau, evPos[e]);
                }
                pops.AddBlock(dst, off, n);

                // flung-mud spray: band-passed noise bursts at random centre frequencies
                float sprayAmp = 0.30f * mSlip;
                if (sprayAmp > 0.005f || sprayV > 1e-4f)
                {
                    int ns = sprayAmp > 0.005f ? Events(ref sprayAcc, (4f + 55f * mSlip * mSlip) * invSr, n, 6) : 0;
                    for (int e = 0; e < ns; e++) evAmp[e] = sprayAmp * rng.Range(0.4f, 1f);
                    if (ns > 0) sprayBp.Set(rng.Range(700f, 2800f), 1.3f, sr);
                    float v = sprayV, k = sprayK; int ei = 0;
                    for (int i = 0; i < n; i++)
                    {
                        while (ei < ns && evPos[ei] == i) { if (evAmp[ei] > v) v = evAmp[ei]; ei++; }
                        env[i] = v; v *= k;
                    }
                    sprayV = v < 1e-5f ? 0f : v;
                    Block.BandpassAddEnv(ref sprayBp, noise, env, dst, off, n, 1.2f);
                }
            }

            // ------------------------------------------------------------- gravel crunch
            if (grv > 0.004f)
            {
                float amp = 0.78f * MathF.Pow(grv, 0.8f);
                int ng = Events(ref gravAcc, (110f + 1500f * grv) * invSr, n, 20);
                if (ng > 0 || gravHot > 0)
                {
                    for (int i = 0; i < n; i++) tmp[i] = 0f;
                    for (int e = 0; e < ng; e++) { float r = rng.Next01(); tmp[evPos[e]] += r * r * 9f * (rng.Next01() < 0.5f ? -1f : 1f); }
                    Block.BandpassAdd(ref gravA, tmp, dst, off, n, 0.35f * amp);
                    Block.BandpassAdd(ref gravB, tmp, dst, off, n, 0.245f * amp);
                    gravHot = ng > 0 ? 3 : gravHot - 1;
                }
                float bed = 0.02f * amp;
                for (int i = 0; i < n; i++) dst[off + i] += noise[i] * bed;
            }

            // ------------------------------------------------------------- grass swish
            if (grs > 0.004f)
            {
                float lvl = 0.35f * MathF.Pow(grs, 0.85f);
                float ra = 1f - MathF.Exp(-DspMath.TwoPi * 6f * invSr);
                float rv = Math.Max(0.4f, rev) * invSr * 2.5f, ph = grassPh, z = grassZ;
                for (int i = 0; i < n; i++)
                {
                    ph += rv; ph -= (int)ph;
                    z += ra * (noise2[i] - z);
                    float x = ph * 4096f; int ix = (int)x;
                    float am = 0.65f + 0.35f * (tab[ix] + (tab[ix + 1] - tab[ix]) * (x - ix)) + 14f * z;
                    env[i] = am < 0.1f ? 0.1f : (am > 1.4f ? 1.4f : am);
                }
                grassPh = ph; grassZ = z;
                Block.BandpassAddEnv(ref grassBp, noise, env, dst, off, n, lvl * 1.15f);
            }

            // ------------------------------------------------------------- hard ground: tyre hum + tread tone
            if (hrd > 0.004f)
            {
                float lvl = 0.42f * MathF.Pow(hrd, 0.9f);
                float lr = lugHz * invSr, p1 = lugPh;
                float loA = 1f - MathF.Exp(-DspMath.TwoPi * 150f * invSr), lz = hardLoZ;
                var tread = HarmonicTables.Tread;
                float tg = 0.12f * lvl, lg = 1.5f * lvl;
                for (int i = 0; i < n; i++)
                {
                    p1 += lr; p1 -= (int)p1;
                    float x1 = p1 * 4096f; int i1 = (int)x1; float s1 = tread[i1] + (tread[i1 + 1] - tread[i1]) * (x1 - i1);
                    lz += loA * (noise2[i] - lz);
                    dst[off + i] += s1 * tg + lz * lg;
                }
                lugPh = p1; hardLoZ = lz;
                Block.BandpassAdd(ref hardBp, noise, dst, off, n, 0.8f * lvl);
            }

            // ------------------------------------------------------------- sand hiss
            if (snd > 0.004f) Block.BandpassAdd(ref sandBp, noise, dst, off, n, 0.2f * MathF.Pow(snd, 0.9f));

            // ------------------------------------------------------------- skid / scrub (stick-slip)
            if (skd > 0.004f)
            {
                float lvl = 0.5f * MathF.Pow(skd, 0.9f);
                float inc = 41f * invSr, ph = skidPh;
                for (int i = 0; i < n; i++)
                {
                    ph += inc; ph -= (int)ph;
                    float x = ph * 4096f; int ix = (int)x; float sn = tab[ix] + (tab[ix + 1] - tab[ix]) * (x - ix);
                    env[i] = 0.45f + 0.55f * (sn > 0f ? sn : 0f);
                }
                skidPh = ph;
                Block.BandpassAddEnv(ref skidBp, noise, env, dst, off, n, lvl);
            }

            // ------------------------------------------------------------- belly drag
            if (bel > 0.004f) Block.BandpassAdd(ref bellyBp, noise, dst, off, n, 0.5f * MathF.Pow(bel, 0.85f) * (0.5f + 0.5f * slurpLast));
        }
    }

    /// <summary>
    /// Stick-slip creak / groan: a saw-tooth "slip" oscillator (rate follows articulation speed) excites three high-Q body
    /// modes whose frequencies glide with speed; a slow random gate makes groans come and go. Used for suspension and rope.
    /// </summary>
    public sealed class CreakSynth
    {
        const int Chunk = 128;
        readonly float sr, invSr;
        readonly Rng rng;
        readonly float[] baseF, baseQ, weight;
        readonly float[] exc = new float[Chunk], gateBuf = new float[Chunk], nA = new float[Chunk], nB = new float[Chunk], hb = new float[Chunk / 2 + 1];
        Svf m0, m1, m2;
        float slipPh, level, speed, gateZ, wobbleZ, halfPrev;

        public CreakSynth(float sampleRate, uint seed, float[] modeFreqs, float[] modeQs, float[] modeWeights)
        {
            sr = sampleRate; invSr = 1f / sampleRate; rng = new Rng(seed);
            baseF = modeFreqs; baseQ = modeQs; weight = modeWeights;
        }

        public static CreakSynth Suspension(float sr, uint seed = 99u)
        {
            return new CreakSynth(sr, seed, new[] { 330f, 760f, 1550f }, new[] { 13f, 17f, 22f }, new[] { 1f, 0.7f, 0.4f });
        }

        public static CreakSynth Rope(float sr, uint seed = 77u)
        {
            return new CreakSynth(sr, seed, new[] { 620f, 1350f, 2800f }, new[] { 18f, 22f, 26f }, new[] { 0.8f, 0.8f, 0.5f });
        }

        public bool IsQuiet { get { return level < 0.002f; } }

        public void Render(float levelTarget, float speedTarget, float[] dst, int offset, int count)
        {
            while (count > 0)
            {
                int n = count > Chunk ? Chunk : count;
                RenderChunk(levelTarget, speedTarget, dst, offset, n);
                offset += n; count -= n;
            }
        }

        void RenderChunk(float levelT, float speedT, float[] dst, int off, int n)
        {
            float dt = n * invSr;
            level += (levelT - level) * (1f - MathF.Exp(-dt / 0.05f));
            speed += (speedT - speed) * (1f - MathF.Exp(-dt / 0.08f));
            if (level < 0.002f) return;

            wobbleZ += 0.3f * (rng.Signed() - wobbleZ);
            float wobble = wobbleZ * 3f;                                  // slow mode wander (once per chunk)
            float sp = DspMath.Clamp01(speed);
            float glide = 0.82f + 0.45f * sp + 0.10f * wobble;
            // the whole creak lives below ~4 kHz: run it at half rate and interpolate (m half-rate samples cover the n output samples)
            float srH = sr * 0.5f, invH = 1f / srH;
            int mm = (n + 1) >> 1;
            m0.Set(baseF[0] * glide, baseQ[0], srH);
            m1.Set(baseF[1] * glide * (1f + 0.04f * wobble), baseQ[1], srH);
            m2.Set(baseF[2] * glide * (1f - 0.03f * wobble), baseQ[2], srH);
            float k0 = m0.k * weight[0], k1 = m1.k * weight[1], k2 = m2.k * weight[2];
            float slipInc = (28f + 190f * sp) * (1f + 0.12f * wobble) * invH;
            float gateA = 1f - MathF.Exp(-DspMath.TwoPi * 2.2f * invH);
            float open0 = 0.75f - 0.5f * DspMath.Clamp01(level * 1.2f);          // groan probability grows with the drive
            float inv = 1f / 0.18f;

            // excitation (saw with slip-stick shaping + a little noise) and the groan gate
            Block.Noise(rng, nA, mm); Block.Noise(rng, nB, mm);
            float ph = slipPh, gz = gateZ;
            for (int i = 0; i < mm; i++)
            {
                float n1 = nA[i], n2 = nB[i];
                ph += slipInc; ph -= (int)ph;
                float saw = ph * 2f - 1f;
                saw = saw * (0.35f + 0.65f * (saw < 0f ? -saw : saw));
                exc[i] = saw + 0.45f * n1;
                gz += gateA * (n2 - gz);
                float tg = ((0.5f + 40f * gz) - open0) * inv; tg = tg < 0f ? 0f : (tg > 1f ? 1f : tg);
                gateBuf[i] = tg * tg * (3f - 2f * tg) * level * 0.5f;
            }
            slipPh = ph; gateZ = gz;

            // three resonant body modes, fused
            float a1_0 = m0.a1, a2_0 = m0.a2, a3_0 = m0.a3, c1_0 = m0.ic1, c2_0 = m0.ic2;
            float a1_1 = m1.a1, a2_1 = m1.a2, a3_1 = m1.a3, c1_1 = m1.ic1, c2_1 = m1.ic2;
            float a1_2 = m2.a1, a2_2 = m2.a2, a3_2 = m2.a3, c1_2 = m2.ic1, c2_2 = m2.ic2;
            for (int i = 0; i < mm; i++)
            {
                float x = exc[i];
                float v3 = x - c2_0; float v1 = a1_0 * c1_0 + a2_0 * v3; float v2 = c2_0 + a2_0 * c1_0 + a3_0 * v3; c1_0 = 2f * v1 - c1_0; c2_0 = 2f * v2 - c2_0;
                float o = v1 * k0;
                v3 = x - c2_1; v1 = a1_1 * c1_1 + a2_1 * v3; v2 = c2_1 + a2_1 * c1_1 + a3_1 * v3; c1_1 = 2f * v1 - c1_1; c2_1 = 2f * v2 - c2_1;
                o += v1 * k1;
                v3 = x - c2_2; v1 = a1_2 * c1_2 + a2_2 * v3; v2 = c2_2 + a2_2 * c1_2 + a3_2 * v3; c1_2 = 2f * v1 - c1_2; c2_2 = 2f * v2 - c2_2;
                o += v1 * k2;
                hb[i] = o * gateBuf[i];
            }
            m0.ic1 = c1_0; m0.ic2 = c2_0; m1.ic1 = c1_1; m1.ic2 = c2_1; m2.ic1 = c1_2; m2.ic2 = c2_2;
            Block.UpsampleAdd(hb, mm, dst, off, n, ref halfPrev);
        }
    }

    /// <summary>Wading: water wash hiss with lapping, plus gurgling bubble clouds.</summary>
    public sealed class WaterSynth
    {
        const int Chunk = 128;
        readonly float sr, invSr;
        readonly Rng rng;
        readonly float[] noise = new float[Chunk], noise2 = new float[Chunk], env = new float[Chunk];
        readonly int[] evPos = new int[12];
        Svf washBp;
        readonly BubbleBank bubbles;
        float level, flow, lapPh, lapZ, hissZ, lowZ, bubAcc;

        public WaterSynth(float sampleRate, uint seed = 31337u)
        {
            sr = sampleRate; invSr = 1f / sampleRate; rng = new Rng(seed);
            bubbles = new BubbleBank(sampleRate);
            washBp.Set(900f, 0.5f, sr);
        }

        public bool IsQuiet { get { return level < 0.002f; } }

        public void Render(VehicleSignals s, float[] dst, int offset, int count)
        {
            while (count > 0)
            {
                int n = count > Chunk ? Chunk : count;
                RenderChunk(s, dst, offset, n);
                offset += n; count -= n;
            }
        }

        void RenderChunk(VehicleSignals s, float[] dst, int off, int n)
        {
            float dt = n * invSr;
            level += (s.wading - level) * (1f - MathF.Exp(-dt / 0.12f));
            flow += (s.waterFlow - flow) * (1f - MathF.Exp(-dt / 0.3f));
            if (level < 0.002f) return;
            Block.Noise(rng, noise, n); Block.Noise(rng, noise2, n);
            var tab = SinTable.t;

            float lvl = 0.5f * MathF.Pow(level, 0.8f);
            washBp.Set(700f + 900f * level, 0.5f, sr);
            float lapA = 1f - MathF.Exp(-DspMath.TwoPi * 2.5f * invSr);
            float lapInc = (0.6f + 1.4f * level) * invSr;
            float hiA = 1f - MathF.Exp(-DspMath.TwoPi * (2600f + 1800f * level) * invSr);     // high-pass corner via one-pole subtraction
            float loA = 1f - MathF.Exp(-DspMath.TwoPi * 180f * invSr);
            float ph = lapPh, lz = lapZ, hz = hissZ, oz = lowZ;
            for (int i = 0; i < n; i++)
            {
                ph += lapInc; ph -= (int)ph;
                lz += lapA * (noise2[i] - lz);
                float x = ph * 4096f; int ix = (int)x;
                float lap = 0.55f + 0.30f * (tab[ix] + (tab[ix + 1] - tab[ix]) * (x - ix)) + 25f * lz;
                lap = lap < 0.15f ? 0.15f : (lap > 1.3f ? 1.3f : lap);
                float w = noise[i];
                hz += hiA * (w - hz); oz += loA * (w - oz);
                env[i] = lap;
                // hiss (high-passed) and rumble (low-passed) share the lap envelope; the wash is the band-pass pass below
                dst[off + i] += ((w - hz) * 0.2f + oz * 0.29f) * lap * lvl;
            }
            lapPh = ph; lapZ = lz; hissZ = hz; lowZ = oz;
            Block.BandpassAddEnv(ref washBp, noise, env, dst, off, n, 0.55f * lvl);

            // gurgling bubbles
            float rate = (6f + 70f * level) * invSr;
            float bubAmp = 0.22f * lvl;
            float total = rate * n, left = total; int cnt = 0;
            if (bubAcc <= 0f) bubAcc = rng.Exp(1f);
            while (bubAcc <= left && cnt < 12)
            {
                left -= bubAcc;
                int pos = (int)((total - left) / total * n); evPos[cnt++] = pos >= n ? n - 1 : pos;
                bubAcc = rng.Exp(1f);
            }
            bubAcc -= left;
            for (int e = 0; e < cnt; e++)
            {
                float tau = rng.Range(0.010f, 0.035f);
                bubbles.Trigger(rng.Range(280f, 1500f), tau, bubAmp * rng.Range(0.3f, 1f), rng.Range(0.1f, 0.3f) / tau, evPos[e]);
            }
            bubbles.AddBlock(dst, off, n);
        }
    }

    /// <summary>Winch motor: harmonic hum + gear-mesh whine (pitch drops with load), brush noise, load growl, rope groan.</summary>
    public sealed class WinchSynth
    {
        const int Chunk = 128;
        readonly float sr, invSr;
        readonly Rng rng;
        readonly CreakSynth rope;
        readonly float[] noise = new float[Chunk];
        Svf brushBp;
        float motor, load, hum, whine, growlPh, jitZ;

        public WinchSynth(float sampleRate, uint seed = 2024u)
        {
            sr = sampleRate; invSr = 1f / sampleRate; rng = new Rng(seed);
            rope = CreakSynth.Rope(sr, seed + 3u);
            brushBp.Set(3300f, 1.2f, sr);
        }

        public bool IsQuiet { get { return motor < 0.002f && load < 0.02f && rope.IsQuiet; } }

        public void Render(VehicleSignals s, float[] dst, int offset, int count)
        {
            while (count > 0)
            {
                int n = count > Chunk ? Chunk : count;
                RenderChunk(s, dst, offset, n);
                offset += n; count -= n;
            }
        }

        void RenderChunk(VehicleSignals s, float[] dst, int off, int n)
        {
            float dt = n * invSr;
            motor += (s.winchMotor - motor) * (1f - MathF.Exp(-dt / (s.winchMotor > motor ? 0.08f : 0.15f)));
            load += (s.winchLoad - load) * (1f - MathF.Exp(-dt / 0.15f));

            // rope groan: tension dependent, mostly while it is being hauled
            float ropeLvl = DspMath.SmoothStep(0.12f, 0.8f, load) * (0.35f + 0.65f * motor);
            if (ropeLvl > 0.002f || !rope.IsQuiet) rope.Render(ropeLvl * 0.9f, 0.25f + 0.5f * load, dst, off, n);
            if (motor < 0.003f) return;

            jitZ += 0.2f * (rng.Signed() - jitZ);
            float dir = s.winchDir >= 0f ? 1f : 1.12f;
            float fHum = (92f + 38f * (1f - 0.6f * load)) * dir * (1f + jitZ * 0.02f);
            float incH = fHum * invSr, incW = fHum * 5.35f * invSr;
            float lvl = 0.35f * motor * (0.55f + 0.45f * load);
            float growl = 0.30f * load;
            float growlInc = (6f + 6f * load) * invSr;
            Block.Noise(rng, noise, n);
            Block.BandpassAdd(ref brushBp, noise, dst, off, n, 0.05f * lvl);

            var humT = HarmonicTables.Hum; var whineT = HarmonicTables.Whine;
            float h = hum, w = whine;
            float gp = growlPh + growlInc * n; gp -= (int)gp;
            float amA = 1f - growl * (0.5f + 0.5f * SinTable.Sin(growlPh)), amB = 1f - growl * (0.5f + 0.5f * SinTable.Sin(gp));
            float am = amA, dam = (amB - amA) / n;
            float gH = 0.16f * lvl, gW = 0.075f * lvl;
            for (int i = 0; i < n; i++)
            {
                h += incH; h -= (int)h; w += incW; w -= (int)w;
                float x1 = h * 4096f; int i1 = (int)x1; float hv = humT[i1] + (humT[i1 + 1] - humT[i1]) * (x1 - i1);
                float y1 = w * 4096f; int j1 = (int)y1; float wv = whineT[j1] + (whineT[j1 + 1] - whineT[j1]) * (y1 - j1);
                dst[off + i] += (hv * gH + wv * gW) * am;
                am += dam;
            }
            hum = h; whine = w; growlPh = gp;
        }
    }
}
