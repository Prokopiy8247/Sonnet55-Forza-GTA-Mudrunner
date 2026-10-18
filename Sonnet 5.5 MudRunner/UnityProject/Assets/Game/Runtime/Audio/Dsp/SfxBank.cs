using System;

namespace MudRunner.Audio.Dsp
{
    /// <summary>
    /// Offline (non real-time) recipes that render the one-shot sounds: impacts, splashes, shifts, winch hardware, UI.
    /// Every recipe is a handful of damped modes (struck metal / wood), filtered noise bursts and Minnaert bubble clouds.
    /// Pure functions of (sound, variant, sample rate): deterministic, thread-safe, safe to run on a worker thread.
    /// </summary>
    public static class SfxRecipes
    {
        // ------------------------------------------------------------------ toolkit

        /// <summary>Damped sine starting at t0; optional initial downward pitch glide (relative, decays with dropTau).</summary>
        public static void Modal(float[] b, int sr, float t0, float f, float tau, float amp, float glide = 0f, float dropTau = 0.03f)
        {
            int i0 = (int)(t0 * sr);
            if (i0 >= b.Length) return;
            int len = Math.Min(b.Length - i0, (int)(tau * 7f * sr));
            double ph = 0, dec = Math.Exp(-1.0 / (tau * sr)), env = amp;
            double dd = Math.Exp(-1.0 / (dropTau * sr)), gl = glide;
            for (int k = 0; k < len; k++)
            {
                b[i0 + k] += (float)(env * Math.Sin(ph));
                ph += 2.0 * Math.PI * f * (1.0 + gl) / sr;
                env *= dec; gl *= dd;
            }
        }

        /// <summary>Filtered noise burst: linear attack, exponential decay. mode 0 = band-pass, 1 = high-pass, 2 = low-pass. Frequency sweeps f0 -> f1 over 'tau*3'.</summary>
        public static void NoiseBurst(float[] b, int sr, Rng rng, float t0, float attack, float tau, float amp, int mode, float f0, float f1, float q)
        {
            int i0 = (int)(t0 * sr);
            if (i0 >= b.Length) return;
            int len = Math.Min(b.Length - i0, (int)((attack + tau * 7f) * sr));
            var f = new Svf();
            float sweepLen = Math.Max(1f, tau * 3f * sr);
            for (int k = 0; k < len; k++)
            {
                if ((k & 31) == 0)
                {
                    float u = Math.Min(1f, k / sweepLen);
                    f.Set(f0 * (float)Math.Pow(f1 / f0, u), q, sr);
                }
                float t = k / (float)sr;
                float env = t < attack ? t / attack : (float)Math.Exp(-(t - attack) / tau);
                float w = rng.Signed();
                float y = f.Tick(w);
                float o = mode == 0 ? y * f.k : (mode == 1 ? f.hp : f.lp);
                b[i0 + k] += o * env * amp;
            }
        }

        /// <summary>Cloud of bubbles scattered over [t0, t0+dur], earlier ones more likely.</summary>
        public static void Bubbles(float[] b, int sr, Rng rng, float t0, float dur, int count, float fLo, float fHi, float tauLo, float tauHi, float amp)
        {
            for (int n = 0; n < count; n++)
            {
                float u = rng.Next01(); u = u * u;
                float t = t0 + dur * u;
                float f = fLo * (float)Math.Pow(fHi / fLo, rng.Next01());
                float tau = rng.Range(tauLo, tauHi);
                float a = amp * rng.Range(0.3f, 1f) * (1f - 0.6f * u);
                Modal(b, sr, t, f, tau, a, 0f);
                // bubble pitch rises: emulate with a small positive glide by adding a slightly higher partial that decays faster
                Modal(b, sr, t, f * 1.12f, tau * 0.5f, a * 0.35f, 0f);
            }
        }

        public static void Click(float[] b, int sr, Rng rng, float t0, float amp, float cutoffHz = 3500f)
        {
            NoiseBurst(b, sr, rng, t0, 0.0002f, 0.0009f, amp, 1, cutoffHz, cutoffHz, 0.7f);
        }

        public static void Normalize(float[] b, float peak)
        {
            float m = 1e-9f;
            for (int i = 0; i < b.Length; i++) { float a = Math.Abs(b[i]); if (a > m) m = a; }
            float g = peak / m;
            for (int i = 0; i < b.Length; i++) b[i] *= g;
        }

        /// <summary>Remove DC and fade the last 'ms' to avoid a click at the end; also a 0.5 ms fade-in.</summary>
        public static void Finish(float[] b, int sr, float fadeOutMs = 25f)
        {
            double mean = 0; for (int i = 0; i < b.Length; i++) mean += b[i]; mean /= Math.Max(1, b.Length);
            for (int i = 0; i < b.Length; i++) b[i] -= (float)mean;
            int fo = Math.Min(b.Length, (int)(fadeOutMs * 0.001f * sr));
            for (int i = 0; i < fo; i++) b[b.Length - 1 - i] *= (float)i / fo;
            int fi = Math.Min(b.Length, (int)(0.0005f * sr));
            for (int i = 0; i < fi; i++) b[i] *= (float)i / fi;
        }

        static float[] Buf(float seconds, int sr) { return new float[Math.Max(16, (int)(seconds * sr))]; }

        // ------------------------------------------------------------------ catalogue

        public static int VariantCount(Sfx id)
        {
            switch (id)
            {
                case Sfx.BumpThump: case Sfx.MetalThud: case Sfx.CargoClank: case Sfx.RockThud:
                case Sfx.MudSplashSmall: case Sfx.MudSplashBig: case Sfx.WaterSplashSmall: case Sfx.WaterSplashBig: return 3;
                case Sfx.SuspClonk: case Sfx.PlasticThud: case Sfx.WoodThunk: case Sfx.VehicleCrunch:
                case Sfx.ShiftClunkLight: case Sfx.ShiftClunkHeavy: case Sfx.GearGrind: case Sfx.RopeTwang: return 2;
                default: return 1;
            }
        }

        /// <summary>Render one variant of a sound at the given sample rate (peak-normalised to 0.9; the player applies the gain).</summary>
        public static float[] Render(Sfx id, int variant, int sr)
        {
            var rng = new Rng((uint)(0x1F3D5B79 + (int)id * 7919 + variant * 104729));
            float[] b;
            float v = variant;
            switch (id)
            {
                case Sfx.BumpThump:
                {
                    b = Buf(0.55f, sr);
                    Modal(b, sr, 0f, 46f + 6f * v, 0.09f, 1f, 0.9f, 0.05f);
                    Modal(b, sr, 0f, 92f + 10f * v, 0.05f, 0.5f, 0.5f, 0.03f);
                    NoiseBurst(b, sr, rng, 0f, 0.001f, 0.03f, 0.6f, 2, 380f, 220f, 0.7f);
                    Modal(b, sr, 0.004f, 175f + 25f * v, 0.07f, 0.22f);          // chassis rattle
                    Modal(b, sr, 0.012f, 430f + 60f * v, 0.05f, 0.1f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.SuspClonk:
                {
                    b = Buf(0.45f, sr);
                    Click(b, sr, rng, 0f, 0.9f, 2500f);
                    float f = 360f + 60f * v;
                    Modal(b, sr, 0f, f, 0.10f, 0.7f); Modal(b, sr, 0f, f * 2.41f, 0.07f, 0.5f); Modal(b, sr, 0f, f * 4.3f, 0.05f, 0.35f); Modal(b, sr, 0f, f * 6.9f, 0.03f, 0.2f);
                    Modal(b, sr, 0f, 78f, 0.06f, 0.6f, 0.5f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.MetalThud:
                {
                    b = Buf(0.8f, sr);
                    float f = 205f + 35f * v;
                    Modal(b, sr, 0f, 80f - 8f * v, 0.07f, 1f, 0.7f, 0.04f);
                    Modal(b, sr, 0f, f, 0.22f, 0.55f); Modal(b, sr, 0f, f * 2.32f, 0.16f, 0.4f); Modal(b, sr, 0f, f * 4.1f, 0.10f, 0.28f);
                    Modal(b, sr, 0f, f * 6.7f, 0.07f, 0.2f); Modal(b, sr, 0f, f * 9.3f, 0.04f, 0.12f);
                    NoiseBurst(b, sr, rng, 0f, 0.0004f, 0.012f, 0.8f, 1, 1800f, 1800f, 0.7f);
                    Finish(b, sr, 40f); Normalize(b, 0.9f); return b;
                }
                case Sfx.PlasticThud:
                {
                    b = Buf(0.32f, sr);
                    Modal(b, sr, 0f, 105f + 15f * v, 0.04f, 1f, 0.5f, 0.03f);
                    Modal(b, sr, 0f, 310f + 40f * v, 0.035f, 0.5f); Modal(b, sr, 0f, 620f, 0.02f, 0.25f);
                    NoiseBurst(b, sr, rng, 0f, 0.0005f, 0.02f, 0.7f, 2, 1800f, 700f, 0.7f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.CargoClank:
                {
                    b = Buf(1.0f, sr);
                    int hits = 3 + variant;
                    float t = 0f;
                    for (int h = 0; h < hits; h++)
                    {
                        float f = rng.Range(280f, 640f), a = rng.Range(0.5f, 1f) * (1f - 0.12f * h);
                        Click(b, sr, rng, t, a * 0.8f, 2800f);
                        Modal(b, sr, t, f, 0.16f, a * 0.6f); Modal(b, sr, t, f * 2.76f, 0.11f, a * 0.45f); Modal(b, sr, t, f * 5.4f, 0.07f, a * 0.3f); Modal(b, sr, t, f * 8.9f, 0.04f, a * 0.18f);
                        Modal(b, sr, t, 90f, 0.05f, a * 0.5f, 0.4f);
                        t += rng.Range(0.045f, 0.12f);
                    }
                    Finish(b, sr, 60f); Normalize(b, 0.9f); return b;
                }
                case Sfx.RockThud:
                {
                    b = Buf(0.6f, sr);
                    Modal(b, sr, 0f, 52f + 6f * v, 0.10f, 1f, 0.9f, 0.05f);
                    Modal(b, sr, 0f, 130f + 20f * v, 0.05f, 0.4f, 0.3f);
                    NoiseBurst(b, sr, rng, 0f, 0.001f, 0.05f, 0.9f, 0, 700f, 300f, 0.6f);
                    NoiseBurst(b, sr, rng, 0f, 0.0004f, 0.008f, 0.7f, 1, 2500f, 2500f, 0.7f);
                    Finish(b, sr, 40f); Normalize(b, 0.9f); return b;
                }
                case Sfx.WoodThunk:
                {
                    b = Buf(0.45f, sr);
                    float f = 150f + 20f * v;
                    Modal(b, sr, 0f, f, 0.06f, 1f, 0.3f); Modal(b, sr, 0f, f * 2.1f, 0.045f, 0.6f); Modal(b, sr, 0f, f * 3.7f, 0.03f, 0.35f);
                    NoiseBurst(b, sr, rng, 0f, 0.0005f, 0.02f, 0.5f, 2, 1200f, 500f, 0.7f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.VehicleCrunch:
                {
                    b = Buf(1.3f, sr);
                    Modal(b, sr, 0f, 60f, 0.12f, 1f, 0.8f, 0.05f);
                    for (int m = 0; m < 9; m++) Modal(b, sr, rng.Range(0f, 0.12f), rng.Range(250f, 3800f), rng.Range(0.05f, 0.3f), rng.Range(0.15f, 0.6f));
                    NoiseBurst(b, sr, rng, 0f, 0.001f, 0.06f, 0.9f, 0, 1500f, 600f, 0.5f);
                    for (int c = 0; c < 8; c++) Click(b, sr, rng, rng.Range(0.02f, 0.6f), rng.Range(0.2f, 0.6f), 2500f);
                    Finish(b, sr, 80f); Normalize(b, 0.9f); return b;
                }
                case Sfx.MudSplashSmall:
                {
                    b = Buf(0.55f, sr);
                    NoiseBurst(b, sr, rng, 0f, 0.003f, 0.05f, 0.7f, 0, 1800f, 500f, 0.7f);
                    NoiseBurst(b, sr, rng, 0.01f, 0.004f, 0.09f, 0.35f, 2, 700f, 250f, 0.7f);
                    Bubbles(b, sr, rng, 0.015f, 0.28f, 7 + 2 * variant, 110f, 520f, 0.02f, 0.05f, 0.55f);
                    Finish(b, sr, 50f); Normalize(b, 0.9f); return b;
                }
                case Sfx.MudSplashBig:
                {
                    b = Buf(1.0f, sr);
                    NoiseBurst(b, sr, rng, 0f, 0.004f, 0.11f, 0.8f, 0, 2800f, 380f, 0.6f);
                    NoiseBurst(b, sr, rng, 0.01f, 0.008f, 0.2f, 0.5f, 2, 600f, 180f, 0.7f);
                    Modal(b, sr, 0.005f, 78f + 8f * v, 0.12f, 0.8f, 0.6f, 0.05f);
                    Bubbles(b, sr, rng, 0.02f, 0.6f, 16 + 3 * variant, 85f, 420f, 0.03f, 0.07f, 0.5f);
                    Finish(b, sr, 80f); Normalize(b, 0.9f); return b;
                }
                case Sfx.WaterSplashSmall:
                {
                    b = Buf(0.6f, sr);
                    NoiseBurst(b, sr, rng, 0f, 0.002f, 0.07f, 0.7f, 1, 1400f, 3200f, 0.7f);
                    NoiseBurst(b, sr, rng, 0.004f, 0.003f, 0.12f, 0.35f, 0, 2600f, 1200f, 0.6f);
                    Bubbles(b, sr, rng, 0.01f, 0.4f, 12 + 3 * variant, 520f, 2600f, 0.008f, 0.025f, 0.45f);
                    Finish(b, sr, 60f); Normalize(b, 0.9f); return b;
                }
                case Sfx.WaterSplashBig:
                {
                    b = Buf(1.3f, sr);
                    NoiseBurst(b, sr, rng, 0f, 0.003f, 0.2f, 0.8f, 1, 900f, 2800f, 0.6f);
                    NoiseBurst(b, sr, rng, 0.005f, 0.006f, 0.32f, 0.45f, 0, 1800f, 500f, 0.5f);
                    Modal(b, sr, 0.01f, 140f, 0.14f, 0.55f, 0.7f, 0.08f);
                    Bubbles(b, sr, rng, 0.015f, 0.9f, 30 + 4 * variant, 300f, 2600f, 0.01f, 0.04f, 0.4f);
                    Finish(b, sr, 100f); Normalize(b, 0.9f); return b;
                }
                case Sfx.ShiftClunkLight:
                {
                    b = Buf(0.3f, sr);
                    Modal(b, sr, 0f, 98f + 10f * v, 0.045f, 1f, 0.5f, 0.03f);
                    Click(b, sr, rng, 0f, 0.7f, 3000f);
                    Modal(b, sr, 0.002f, 1250f + 100f * v, 0.03f, 0.25f); Modal(b, sr, 0.002f, 2900f, 0.02f, 0.12f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.ShiftClunkHeavy:
                {
                    b = Buf(0.5f, sr);
                    Modal(b, sr, 0f, 62f + 6f * v, 0.08f, 1f, 0.6f, 0.04f);
                    Modal(b, sr, 0f, 150f, 0.05f, 0.4f);
                    Click(b, sr, rng, 0f, 0.8f, 2500f);
                    Modal(b, sr, 0.003f, 640f + 60f * v, 0.08f, 0.35f); Modal(b, sr, 0.003f, 1900f, 0.04f, 0.2f);
                    Modal(b, sr, 0.05f, 62f, 0.06f, 0.3f);
                    Finish(b, sr, 40f); Normalize(b, 0.9f); return b;
                }
                case Sfx.GearGrind:
                {
                    b = Buf(0.42f, sr);
                    var r1 = new Svf(); var r2 = new Svf(); r1.Set(2600f, 5f, sr); r2.Set(4100f, 6f, sr);
                    float period = sr / (92f + 14f * v); float next = 0;
                    for (int i = 0; i < b.Length; i++)
                    {
                        float t = i / (float)sr;
                        float env = DspMath.SmoothStep(0f, 0.04f, t) * (1f - DspMath.SmoothStep(0.26f, 0.40f, t));
                        float imp = 0f;
                        if (i >= next) { imp = rng.Range(0.4f, 1f) * (rng.Next01() < 0.5f ? -1f : 1f) * 6f; next += period * rng.Range(0.8f, 1.25f); }
                        float n = rng.Signed();
                        b[i] += (r1.Tick(imp + n * 0.15f) * r1.k + 0.7f * r2.Tick(imp + n * 0.15f) * r2.k) * env * 0.5f;
                    }
                    Modal(b, sr, 0f, 95f + 14f * v, 0.2f, 0.25f);
                    Finish(b, sr, 50f); Normalize(b, 0.9f); return b;
                }
                case Sfx.HandbrakeRatchet:
                {
                    b = Buf(0.8f, sr);
                    float t = 0f, gap = 0.045f;
                    for (int c = 0; c < 7; c++)
                    {
                        Click(b, sr, rng, t, 0.8f, 3200f);
                        Modal(b, sr, t, 2350f, 0.012f, 0.45f); Modal(b, sr, t, 900f, 0.02f, 0.35f);
                        t += gap; gap *= 1.16f;
                    }
                    Modal(b, sr, t, 110f, 0.05f, 0.5f, 0.4f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.AirPsstOn:
                {
                    b = Buf(0.9f, sr);
                    Modal(b, sr, 0f, 75f, 0.04f, 0.45f, 0.5f);
                    NoiseBurst(b, sr, rng, 0f, 0.006f, 0.22f, 0.85f, 1, 3000f, 3000f, 0.7f);
                    NoiseBurst(b, sr, rng, 0.0f, 0.01f, 0.30f, 0.45f, 0, 7500f, 5200f, 0.5f);
                    Finish(b, sr, 80f); Normalize(b, 0.9f); return b;
                }
                case Sfx.AirPsstOff:
                {
                    b = Buf(0.5f, sr);
                    NoiseBurst(b, sr, rng, 0f, 0.004f, 0.10f, 0.85f, 1, 3600f, 3600f, 0.7f);
                    NoiseBurst(b, sr, rng, 0f, 0.006f, 0.15f, 0.35f, 0, 6500f, 4200f, 0.6f);
                    Click(b, sr, rng, 0f, 0.5f, 2200f); Modal(b, sr, 0.01f, 120f, 0.04f, 0.3f);
                    Finish(b, sr, 50f); Normalize(b, 0.9f); return b;
                }
                case Sfx.TurboBlowOff:
                {
                    b = Buf(0.9f, sr);
                    var f = new Svf(); f.Set(4600f, 0.9f, sr);
                    var f2 = new Svf(); f2.Set(2100f, 1.2f, sr);
                    for (int i = 0; i < b.Length; i++)
                    {
                        float t = i / (float)sr;
                        float env = DspMath.SmoothStep(0f, 0.01f, t) * (float)Math.Exp(-t / 0.28f);
                        float am = 0.55f + 0.45f * (float)Math.Sin(2 * Math.PI * (15f - 8f * t) * t);
                        float w = rng.Signed();
                        b[i] += (f.Tick(w) * f.k + 0.5f * f2.Tick(w) * f2.k) * env * am;
                    }
                    Finish(b, sr, 80f); Normalize(b, 0.9f); return b;
                }
                case Sfx.HookClunk:
                {
                    b = Buf(0.7f, sr);
                    Click(b, sr, rng, 0f, 0.9f, 3000f);
                    Modal(b, sr, 0f, 480f, 0.07f, 0.55f); Modal(b, sr, 0f, 1270f, 0.05f, 0.4f); Modal(b, sr, 0f, 3100f, 0.03f, 0.22f);
                    Click(b, sr, rng, 0.065f, 1f, 2200f);
                    Modal(b, sr, 0.065f, 145f, 0.07f, 0.9f, 0.6f, 0.04f); Modal(b, sr, 0.065f, 690f, 0.09f, 0.35f); Modal(b, sr, 0.065f, 1750f, 0.05f, 0.25f);
                    Finish(b, sr, 50f); Normalize(b, 0.9f); return b;
                }
                case Sfx.HookRelease:
                {
                    b = Buf(0.5f, sr);
                    Click(b, sr, rng, 0f, 0.7f, 3500f);
                    Modal(b, sr, 0f, 880f, 0.05f, 0.5f); Modal(b, sr, 0f, 2250f, 0.035f, 0.35f);
                    Click(b, sr, rng, 0.11f, 0.5f, 3000f); Modal(b, sr, 0.11f, 1320f, 0.04f, 0.3f);
                    Modal(b, sr, 0.0f, 210f, 0.04f, 0.3f, 0.3f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.RopeTwang:
                {
                    b = Buf(1.3f, sr);
                    float f0 = 96f + 28f * v;
                    for (int k = 1; k <= 12; k++)
                    {
                        float tau = 0.62f / (float)Math.Pow(k, 0.75);
                        Modal(b, sr, 0f, f0 * k * (1f + 0.0006f * k * k), tau, 1f / (float)Math.Pow(k, 1.05), 0.035f, 0.08f);
                    }
                    NoiseBurst(b, sr, rng, 0f, 0.0003f, 0.01f, 0.55f, 1, 2000f, 2000f, 0.7f);
                    Finish(b, sr, 120f); Normalize(b, 0.9f); return b;
                }
                case Sfx.StarterClunk:
                {
                    b = Buf(0.25f, sr);
                    Click(b, sr, rng, 0f, 0.9f, 2800f);
                    Modal(b, sr, 0f, 215f, 0.045f, 0.9f, 0.4f); Modal(b, sr, 0f, 1500f, 0.03f, 0.35f);
                    Modal(b, sr, 0.03f, 2200f, 0.02f, 0.2f);
                    Finish(b, sr); Normalize(b, 0.9f); return b;
                }
                case Sfx.UiNotify: return Tones(0.7f, sr, new[] { 659.25f, 987.77f }, new[] { 0f, 0.11f }, 0.16f, 0.35f, false);
                case Sfx.UiWarn: return Tones(0.55f, sr, new[] { 1000f, 1000f }, new[] { 0f, 0.2f }, 0.07f, 0.32f, true);
                case Sfx.UiStuck: return Tones(1.0f, sr, new[] { 740f, 520f, 740f, 520f, 740f, 520f }, new[] { 0f, 0.14f, 0.28f, 0.42f, 0.56f, 0.70f }, 0.07f, 0.32f, true);
                case Sfx.UiFuel: return Tones(0.9f, sr, new[] { 880f, 660f, 440f }, new[] { 0f, 0.2f, 0.4f }, 0.10f, 0.32f, true);
                case Sfx.UiClick:
                {
                    b = Buf(0.07f, sr);
                    Modal(b, sr, 0f, 2600f, 0.008f, 0.8f); Modal(b, sr, 0f, 5200f, 0.005f, 0.3f);
                    Finish(b, sr, 10f); Normalize(b, 0.5f); return b;
                }
                case Sfx.UiSuccess: return Tones(1.1f, sr, new[] { 523.25f, 659.25f, 783.99f, 1046.5f }, new[] { 0f, 0.1f, 0.2f, 0.3f }, 0.18f, 0.35f, false);
            }
            return new float[16];
        }

        static float[] Tones(float seconds, int sr, float[] freqs, float[] starts, float tau, float peak, bool squareish)
        {
            var b = Buf(seconds, sr);
            for (int i = 0; i < freqs.Length; i++)
            {
                int i0 = (int)(starts[i] * sr);
                int len = Math.Min(b.Length - i0, (int)(tau * 6f * sr));
                double ph = 0;
                for (int k = 0; k < len; k++)
                {
                    float t = k / (float)sr;
                    float att = Math.Min(1f, t / 0.004f);
                    float env = squareish ? att * (t < tau ? 1f : (float)Math.Exp(-(t - tau) / 0.02f)) : att * (float)Math.Exp(-t / tau);
                    double s;
                    if (squareish) s = Math.Sin(ph) + Math.Sin(3 * ph) / 3.0 + Math.Sin(5 * ph) / 5.0;
                    else s = Math.Sin(ph) + 0.3 * Math.Sin(2 * ph) + 0.12 * Math.Sin(3 * ph);
                    b[i0 + k] += (float)(s * env);
                    ph += 2.0 * Math.PI * freqs[i] / sr;
                }
            }
            Finish(b, sr, 20f); Normalize(b, peak);
            return b;
        }
    }

    /// <summary>All pre-rendered one-shots for one sample rate. Immutable after <see cref="Build"/>, so the audio thread may read it freely.</summary>
    public sealed class SfxBank
    {
        public readonly int sampleRate;
        readonly float[][][] clips;

        SfxBank(int sr, float[][][] c) { sampleRate = sr; clips = c; }

        /// <summary>Minimal bank (tiny silent-ish clips) used to exercise the sample player paths during JIT warm-up.</summary>
        public static SfxBank Tiny(int sampleRate)
        {
            int n = (int)Sfx.Count;
            var all = new float[n][][];
            for (int i = 0; i < n; i++)
            {
                int vc = SfxRecipes.VariantCount((Sfx)i);
                all[i] = new float[vc][];
                for (int v = 0; v < vc; v++) { var c = new float[96]; for (int k = 0; k < c.Length; k++) c[k] = 0.001f * (c.Length - k); all[i][v] = c; }
            }
            return new SfxBank(sampleRate, all);
        }

        public static SfxBank Build(int sampleRate)
        {
            int n = (int)Sfx.Count;
            var all = new float[n][][];
            for (int i = 0; i < n; i++)
            {
                var id = (Sfx)i;
                int vc = SfxRecipes.VariantCount(id);
                all[i] = new float[vc][];
                for (int v = 0; v < vc; v++) all[i][v] = SfxRecipes.Render(id, v, sampleRate);
            }
            return new SfxBank(sampleRate, all);
        }

        public int VariantCount(Sfx id) { return clips[(int)id].Length; }

        public float[] Get(Sfx id, int variant)
        {
            var v = clips[(int)id];
            if (variant < 0 || variant >= v.Length) variant = ((variant % v.Length) + v.Length) % v.Length;
            return v[variant];
        }
    }

    /// <summary>Small polyphonic one-shot sample player living inside a voice. No allocation; reads shared immutable clips.</summary>
    public sealed class SamplePlayer
    {
        const int Slots = 8;
        readonly float[][] data = new float[Slots][];
        readonly float[] pos = new float[Slots];
        readonly float[] step = new float[Slots];
        readonly float[] gain = new float[Slots];
        readonly Rng rng = new Rng(8675309u);
        public volatile SfxBank bank;

        public void Play(Sfx id, int variant, float g, float pitch)
        {
            var bk = bank;
            if (bk == null) return;
            if (variant < 0) variant = rng.Int(bk.VariantCount(id));
            int slot = -1; float furthest = -1f;
            for (int i = 0; i < Slots; i++)
            {
                if (data[i] == null) { slot = i; break; }
                float prog = pos[i] / data[i].Length;
                if (prog > furthest) { furthest = prog; slot = i; }
            }
            data[slot] = bk.Get(id, variant); pos[slot] = 0f; step[slot] = pitch; gain[slot] = g;
        }

        public bool Active { get { for (int i = 0; i < Slots; i++) if (data[i] != null) return true; return false; } }

        public void Mix(float[] dst, int off, int n)
        {
            for (int s = 0; s < Slots; s++)
            {
                var d = data[s];
                if (d == null) continue;
                float p = pos[s], st = step[s], g = gain[s];
                int len = d.Length - 2;
                int i = 0;
                for (; i < n; i++)
                {
                    if (p >= len) { data[s] = null; break; }
                    int ip = (int)p; float f = p - ip;
                    dst[off + i] += (d[ip] + (d[ip + 1] - d[ip]) * f) * g;
                    p += st;
                }
                pos[s] = p;
                if (i == n && p >= len) data[s] = null;
            }
        }
    }
}
