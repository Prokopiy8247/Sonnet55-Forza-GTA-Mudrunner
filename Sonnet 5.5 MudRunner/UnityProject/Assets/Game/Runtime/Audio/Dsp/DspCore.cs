using System;
using System.Runtime.CompilerServices;

namespace MudRunner.Audio.Dsp
{
    // =====================================================================================================================
    //  Pure DSP building blocks. No UnityEngine dependency, no allocation after construction, no thread affinity:
    //  everything here can run on the audio thread, on a worker thread (clip pre-rendering) or in a batch-mode test.
    // =====================================================================================================================

    /// <summary>Small float math helpers (all inlined, no allocation).</summary>
    public static class DspMath
    {
        public const float Pi = 3.14159265358979f;
        public const float TwoPi = 6.28318530717959f;
        const MethodImplOptions Inl = MethodImplOptions.AggressiveInlining;

        [MethodImpl(Inl)] public static float Clamp(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
        [MethodImpl(Inl)] public static float Clamp01(float v) { return v < 0f ? 0f : (v > 1f ? 1f : v); }
        [MethodImpl(Inl)] public static float Lerp(float a, float b, float t) { return a + (b - a) * t; }
        [MethodImpl(Inl)] public static float Abs(float v) { return v < 0f ? -v : v; }
        [MethodImpl(Inl)] public static float Max(float a, float b) { return a > b ? a : b; }
        [MethodImpl(Inl)] public static float Min(float a, float b) { return a < b ? a : b; }

        /// <summary>0 below e0, 1 above e1, smooth Hermite in between.</summary>
        [MethodImpl(Inl)]
        public static float SmoothStep(float e0, float e1, float x)
        {
            float t = (x - e0) / (e1 - e0);
            t = t < 0f ? 0f : (t > 1f ? 1f : t);
            return t * t * (3f - 2f * t);
        }

        /// <summary>Remap x from [a,b] to [0,1], clamped.</summary>
        [MethodImpl(Inl)] public static float InvLerp01(float a, float b, float x) { return Clamp01((x - a) / (b - a)); }

        public static float DbToLin(float db) { return MathF.Pow(10f, db * 0.05f); }
        public static float LinToDb(float lin) { return 20f * MathF.Log10(lin < 1e-9f ? 1e-9f : lin); }

        /// <summary>Coefficient G for a zero-delay-feedback (TPT / bilinear) one-pole: v=(x-s)*G; y=v+s; s=y+v. Exact at high cut-offs, zero gain at Nyquist.</summary>
        public static float TptG(float fc, float sampleRate)
        {
            if (fc > sampleRate * 0.45f) fc = sampleRate * 0.45f;
            float g = MathF.Tan(Pi * fc / sampleRate);
            return g / (1f + g);
        }

        /// <summary>One-pole smoothing coefficient for a time constant (s): y += (x-y)*coef per sample.</summary>
        public static float SmoothCoef(float seconds, float sampleRate)
        {
            if (seconds <= 1e-6f) return 1f;
            return 1f - MathF.Exp(-1f / (seconds * sampleRate));
        }

        /// <summary>tanh-like soft limiter, unity small-signal gain, output limited to [-1,1].</summary>
        [MethodImpl(Inl)]
        public static float SoftLimit(float x)
        {
            if (x > 3f) return 1f;
            if (x < -3f) return -1f;
            float x2 = x * x;
            return x * (27f + x2) / (27f + 9f * x2);
        }

        /// <summary>Per-voice soft-knee limiter: identity for |x| &lt;= 0.75, then a smooth saturation towards 0.97 (slope-continuous, never reaches full scale).</summary>
        [MethodImpl(Inl)]
        public static float SoftKnee(float x)
        {
            float a = x < 0f ? -x : x;
            if (a <= 0.75f) return x;
            float y = 0.75f + 0.22f * SoftLimit((a - 0.75f) * (1f / 0.22f));
            return x < 0f ? -y : y;
        }

        /// <summary>Master-bus soft-knee limiter: identity for |x| &lt;= 0.8, saturating towards 1.0.</summary>
        [MethodImpl(Inl)]
        public static float MasterKnee(float x)
        {
            float a = x < 0f ? -x : x;
            if (a <= 0.8f) return x;
            float y = 0.8f + 0.2f * SoftLimit((a - 0.8f) * 5f);
            return x < 0f ? -y : y;
        }

        /// <summary>True for NaN or +-Infinity.</summary>
        [MethodImpl(Inl)] public static bool IsBad(float x) { return float.IsNaN(x) || float.IsInfinity(x); }
    }

    /// <summary>Shared sine lookup (4096 points + guard, linear interpolation: error &lt; 3e-7). Phase is in cycles.</summary>
    public static class SinTable
    {
        const int N = 4096;
        public static readonly float[] t = Build();

        static float[] Build()
        {
            var a = new float[N + 2];
            for (int i = 0; i < a.Length; i++) a[i] = (float)Math.Sin(2.0 * Math.PI * i / N);
            return a;
        }

        /// <summary>sin(2*pi*phase) for any finite phase (cycles).</summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static float Sin(float phase)
        {
            phase -= (int)phase;
            if (phase < 0f) phase += 1f;
            float x = phase * N;
            int i = (int)x;
            float f = x - i;
            return t[i] + (t[i + 1] - t[i]) * f;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static float Cos(float phase) { return Sin(phase + 0.25f); }
    }

    /// <summary>xorshift32 PRNG. Deterministic, allocation-free, good enough for audio noise.</summary>
    public sealed class Rng
    {
        public uint s;                 // public so hot loops can inline the xorshift on a local copy
        public Rng(uint seed) { s = seed == 0u ? 0x9E3779B9u : seed; }
        public void Seed(uint seed) { s = seed == 0u ? 0x9E3779B9u : seed; }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public uint NextU() { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s; }
        /// <summary>[0,1)</summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Next01() { return (int)(NextU() >> 8) * (1f / 16777216f); }
        /// <summary>[-1,1)</summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Signed() { return (int)(NextU() >> 8) * (2f / 16777216f) - 1f; }
        public float Range(float a, float b) { return a + (b - a) * Next01(); }
        /// <summary>Approximately Gaussian, unit variance (sum of 4 uniforms).</summary>
        public float Gauss() { return (Next01() + Next01() + Next01() + Next01() - 2f) * 1.7320508f; }
        /// <summary>Exponential variate with the given mean.</summary>
        public float Exp(float mean) { return -mean * MathF.Log(1f - Next01() * 0.999999f); }
        public int Int(int n) { return (int)(NextU() % (uint)n); }
    }

    /// <summary>
    /// Zero-delay-feedback state variable filter (Zavalishin/Cytomic TPT). Stable under per-sample modulation, so it is the
    /// workhorse for every swept/resonant filter in the project. Outputs after <see cref="Tick"/>: lp, bp (peak gain Q), hp.
    /// </summary>
    public struct Svf
    {
        public float a1, a2, a3, ic1, ic2;      // coefficients / integrator states (public so hot loops can hoist them into locals)
        public float k;                 // 1/Q
        public float lp, bp, hp;

        public void Set(float fc, float q, float sampleRate)
        {
            float nyq = sampleRate * 0.45f;
            if (fc > nyq) fc = nyq;
            if (fc < 5f) fc = 5f;
            if (q < 0.1f) q = 0.1f;
            float g = MathF.Tan(DspMath.Pi * fc / sampleRate);
            k = 1f / q;
            a1 = 1f / (1f + g * (g + k));
            a2 = g * a1;
            a3 = g * a2;
        }

        public void Reset() { ic1 = ic2 = 0f; lp = bp = hp = 0f; }

        /// <summary>Advance one sample; returns the raw band-pass v1 (peak gain Q). Use k*return for unity-gain band-pass.</summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Tick(float x)
        {
            float v3 = x - ic2;
            float v1 = a1 * ic1 + a2 * v3;
            float v2 = ic2 + a2 * ic1 + a3 * v3;
            ic1 = 2f * v1 - ic1;
            ic2 = 2f * v2 - ic2;
            lp = v2; bp = v1; hp = x - k * v1 - v2;
            return v1;
        }
    }

    /// <summary>One-pole low-pass / high-pass.</summary>
    public struct OnePole
    {
        public float z;
        public static float CoefForCutoff(float fc, float sampleRate) { return 1f - MathF.Exp(-DspMath.TwoPi * fc / sampleRate); }
        [MethodImpl(MethodImplOptions.AggressiveInlining)] public float Lp(float x, float a) { z += a * (x - z); return z; }
        [MethodImpl(MethodImplOptions.AggressiveInlining)] public float Hp(float x, float a) { z += a * (x - z); return x - z; }
    }

    /// <summary>RBJ-cookbook biquad (direct form II transposed). For fixed filters and for filter-response tests.</summary>
    public sealed class Biquad
    {
        float b0 = 1, b1, b2, a1, a2, z1, z2;

        void Norm(float nb0, float nb1, float nb2, float na0, float na1, float na2)
        {
            float inv = 1f / na0;
            b0 = nb0 * inv; b1 = nb1 * inv; b2 = nb2 * inv; a1 = na1 * inv; a2 = na2 * inv;
        }

        static void Pre(float fc, float q, float sr, out float cw, out float alpha, out float sw)
        {
            if (fc > sr * 0.45f) fc = sr * 0.45f;
            if (fc < 1f) fc = 1f;
            float w = DspMath.TwoPi * fc / sr;
            cw = MathF.Cos(w); sw = MathF.Sin(w);
            alpha = sw / (2f * Math.Max(0.05f, q));
        }

        public Biquad Lowpass(float fc, float q, float sr)
        {
            Pre(fc, q, sr, out float cw, out float al, out _);
            Norm((1f - cw) * 0.5f, 1f - cw, (1f - cw) * 0.5f, 1f + al, -2f * cw, 1f - al); return this;
        }
        public Biquad Highpass(float fc, float q, float sr)
        {
            Pre(fc, q, sr, out float cw, out float al, out _);
            Norm((1f + cw) * 0.5f, -(1f + cw), (1f + cw) * 0.5f, 1f + al, -2f * cw, 1f - al); return this;
        }
        /// <summary>Band-pass with constant 0 dB peak gain.</summary>
        public Biquad Bandpass(float fc, float q, float sr)
        {
            Pre(fc, q, sr, out float cw, out float al, out _);
            Norm(al, 0f, -al, 1f + al, -2f * cw, 1f - al); return this;
        }
        public Biquad Notch(float fc, float q, float sr)
        {
            Pre(fc, q, sr, out float cw, out float al, out _);
            Norm(1f, -2f * cw, 1f, 1f + al, -2f * cw, 1f - al); return this;
        }
        public Biquad Peaking(float fc, float q, float gainDb, float sr)
        {
            Pre(fc, q, sr, out float cw, out float al, out _);
            float A = MathF.Pow(10f, gainDb / 40f);
            Norm(1f + al * A, -2f * cw, 1f - al * A, 1f + al / A, -2f * cw, 1f - al / A); return this;
        }

        public void Reset() { z1 = z2 = 0f; }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Process(float x)
        {
            float y = b0 * x + z1;
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            return y;
        }
    }


    /// <summary>
    /// Mixes short pre-rendered grains (shared immutable arrays) at sample-accurate offsets: used for combustion knock, drops and
    /// other sparse events where a per-sample filter would be wasted work.
    /// </summary>
    public sealed class GrainMixer
    {
        const int Slots = 24;
        readonly float[][] data = new float[Slots][];
        readonly int[] pos = new int[Slots], delay = new int[Slots];
        readonly float[] gain = new float[Slots];
        int count;

        public int Active { get { return count; } }

        public void Add(float[] grain, int delaySamples, float g)
        {
            if (count == Slots)                     // drop the oldest
            {
                for (int i = 1; i < Slots; i++) { data[i - 1] = data[i]; pos[i - 1] = pos[i]; delay[i - 1] = delay[i]; gain[i - 1] = gain[i]; }
                count--;
            }
            data[count] = grain; pos[count] = 0; delay[count] = delaySamples; gain[count] = g; count++;
        }

        /// <summary>Add the next n samples of every active grain into dst[off..off+n).</summary>
        public void Mix(float[] dst, int off, int n)
        {
            int w = 0;
            for (int s = 0; s < count; s++)
            {
                var d = data[s]; int p = pos[s], dl = delay[s]; float g = gain[s];
                if (dl >= n)
                {
                    delay[s] = dl - n;
                }
                else
                {
                    int m = n - dl, len = d.Length - p;
                    if (m > len) m = len;
                    int o = off + dl;
                    for (int j = 0; j < m; j++) dst[o + j] += d[p + j] * g;
                    p += m; delay[s] = 0; pos[s] = p;
                    if (p >= d.Length) continue;      // finished: not kept
                }
                if (w != s) { data[w] = data[s]; pos[w] = pos[s]; delay[w] = delay[s]; gain[w] = gain[s]; }
                w++;
            }
            for (int s = w; s < count; s++) data[s] = null;
            count = w;
        }
    }

    /// <summary>Fixed-weight harmonic wavetables (a sum of sines baked into one 4096-point cycle): one lookup per sample instead of one per partial.</summary>
    public static class HarmonicTables
    {
        public const int Size = 4096;
        public static readonly float[] Hum = Make(new[] { 1f, 0.55f, 0.35f, 0f, 0.2f });          // winch motor: harmonics 1,2,3,5
        public static readonly float[] Whine = Make(new[] { 1f, 0.4f });                           // gear-mesh whine: 1,2
        public static readonly float[] Turbo = Make(new[] { 1f, 0.35f });                          // turbo whistle: 1,2
        public static readonly float[] Starter = Make(new[] { 1f, 0.5f, 0.3f });                   // starter / ring-gear whine: 1,2,3
        public static readonly float[] Tread = Make(new[] { 0.6f, 0.25f });                        // tyre tread tone: 1,2

        /// <summary>weights[k-1] = amplitude of harmonic k.</summary>
        static float[] Make(float[] weights)
        {
            var t = new float[Size + 2];
            for (int i = 0; i < t.Length; i++)
            {
                double v = 0;
                for (int k = 0; k < weights.Length; k++) if (weights[k] != 0f) v += weights[k] * Math.Sin(2.0 * Math.PI * (k + 1) * i / Size);
                t[i] = (float)v;
            }
            return t;
        }
    }

    /// <summary>Shared white-noise table (64k samples + 256 guard samples). Slices at random offsets are statistically white.</summary>
    public static class NoiseTable
    {
        public const int Size = 1 << 16;
        public static readonly float[] Data = Build();

        static float[] Build()
        {
            var d = new float[Size + 256];
            uint s = 0x2545F491u;
            double mean = 0;
            for (int i = 0; i < Size; i++)
            {
                s ^= s << 13; s ^= s >> 17; s ^= s << 5;
                d[i] = (int)(s >> 8) * (2f / 16777216f) - 1f;
                mean += d[i];
            }
            float m = (float)(mean / Size);
            for (int i = 0; i < Size; i++) d[i] -= m;
            for (int i = 0; i < 256; i++) d[Size + i] = d[i];
            return d;
        }
    }

    /// <summary>
    /// Block-oriented helpers. They hoist all filter/PRNG state into locals for the duration of the loop, which makes a large
    /// difference on the Mono JIT used by the editor (field access through 'this' and tiny method calls are not optimised away).
    /// </summary>
    public static class Block
    {
        /// <summary>Fill buf[0..n) (n &lt;= 256) with white noise in [-1,1): a random slice of a shared pre-generated table (a memcpy).</summary>
        public static void Noise(Rng rng, float[] buf, int n)
        {
            int start = (int)(rng.NextU() >> 16) & (NoiseTable.Size - 1);
            Array.Copy(NoiseTable.Data, start, buf, 0, n);
        }

        /// <summary>dst[off+i] += gain * unity-gain band-pass(src[i]).</summary>
        public static void BandpassAdd(ref Svf f, float[] src, float[] dst, int off, int n, float gain)
        {
            float a1 = f.a1, a2 = f.a2, a3 = f.a3, ic1 = f.ic1, ic2 = f.ic2, g = gain * f.k;
            for (int i = 0; i < n; i++)
            {
                float v3 = src[i] - ic2;
                float v1 = a1 * ic1 + a2 * v3;
                float v2 = ic2 + a2 * ic1 + a3 * v3;
                ic1 = 2f * v1 - ic1; ic2 = 2f * v2 - ic2;
                dst[off + i] += v1 * g;
            }
            f.ic1 = ic1; f.ic2 = ic2;
        }

        /// <summary>dst[off+i] += gain * env[i] * unity-gain band-pass(src[i]).</summary>
        public static void BandpassAddEnv(ref Svf f, float[] src, float[] env, float[] dst, int off, int n, float gain)
        {
            float a1 = f.a1, a2 = f.a2, a3 = f.a3, ic1 = f.ic1, ic2 = f.ic2, g = gain * f.k;
            for (int i = 0; i < n; i++)
            {
                float v3 = src[i] - ic2;
                float v1 = a1 * ic1 + a2 * v3;
                float v2 = ic2 + a2 * ic1 + a3 * v3;
                ic1 = 2f * v1 - ic1; ic2 = 2f * v2 - ic2;
                dst[off + i] += v1 * g * env[i];
            }
            f.ic1 = ic1; f.ic2 = ic2;
        }

        /// <summary>dst[off+i] += gain * low-pass(src[i]).</summary>
        public static void LowpassAdd(ref Svf f, float[] src, float[] dst, int off, int n, float gain)
        {
            float a1 = f.a1, a2 = f.a2, a3 = f.a3, ic1 = f.ic1, ic2 = f.ic2;
            for (int i = 0; i < n; i++)
            {
                float v3 = src[i] - ic2;
                float v1 = a1 * ic1 + a2 * v3;
                float v2 = ic2 + a2 * ic1 + a3 * v3;
                ic1 = 2f * v1 - ic1; ic2 = 2f * v2 - ic2;
                dst[off + i] += v2 * gain;
            }
            f.ic1 = ic1; f.ic2 = ic2;
        }

        /// <summary>
        /// Linear-interpolating 2x upsample-and-add of a half-rate buffer: dst[off+j] += value at half-rate time j/2 (delayed by one half-rate
        /// sample so no look-ahead is needed). 'prev' carries the last half-rate sample across chunks. Textures below ~4 kHz can be
        /// synthesised at half rate with this at 40-45 % of the cost; the interpolation images land above 20 kHz.
        /// </summary>
        public static void UpsampleAdd(float[] half, int m, float[] dst, int off, int n, ref float prev)
        {
            float hp = prev;
            for (int k = 0; k < m; k++)
            {
                float h = half[k]; int j = off + 2 * k;
                dst[j] += 0.5f * (hp + h);
                if (2 * k + 1 < n) dst[j + 1] += h;
                hp = h;
            }
            prev = hp;
        }

        /// <summary>One-pole low-pass of src into outBuf[0..n) (state kept in z).</summary>
        public static void OnePoleLp(ref float z, float a, float[] src, float[] outBuf, int n)
        {
            float zz = z;
            for (int i = 0; i < n; i++) { zz += a * (src[i] - zz); outBuf[i] = zz; }
            z = zz;
        }
    }

    /// <summary>Paul Kellet's economy pink-noise filter (about -3 dB/octave, +-0.5 dB from 10 Hz).</summary>
    public struct PinkFilter
    {
        float b0, b1, b2;
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Process(float white)
        {
            b0 = 0.99765f * b0 + white * 0.0990460f;
            b1 = 0.96300f * b1 + white * 0.2965164f;
            b2 = 0.57000f * b2 + white * 1.0526913f;
            return (b0 + b1 + b2 + white * 0.1848f) * 0.25f;
        }
    }

    /// <summary>DC blocker (one-pole high-pass).</summary>
    public struct DcBlocker
    {
        float x1, y1;
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Process(float x, float r) { float y = x - x1 + r * y1; x1 = x; y1 = y; return y; }
    }

    /// <summary>Exponential decay envelope: Trigger(amp, tau) then Tick() each sample.</summary>
    public struct Decay
    {
        public float v, k;
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public void Trigger(float amp, float tauSeconds, float sampleRate)
        {
            if (amp > v) v = amp;
            k = MathF.Exp(-1f / (Math.Max(1e-4f, tauSeconds) * sampleRate));
        }
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Tick() { float r = v; v *= k; if (v < 1e-7f) v = 0f; return r; }
    }

    /// <summary>
    /// Small cloud of Minnaert-style bubbles: each is a sine with exponentially decaying amplitude and a slightly rising
    /// frequency. Used for mud suction pops, water gurgle, drops and splash tails. Processed per block (voice-major loops).
    /// </summary>
    public sealed class BubbleBank
    {
        const int Max = 10;
        readonly float[] phase = new float[Max], freq = new float[Max], dfreq = new float[Max], amp = new float[Max], decay = new float[Max];
        readonly int[] delay = new int[Max];
        readonly float invSr;
        int next;
        bool any;

        public BubbleBank(float sampleRate) { invSr = 1f / sampleRate; }

        public void Reset() { for (int i = 0; i < Max; i++) amp[i] = 0f; any = false; }

        /// <param name="f0">start frequency (Hz)</param>
        /// <param name="tau">amplitude decay time constant (s)</param>
        /// <param name="rise">relative frequency rise per second (0.1*decay rate is the physical value)</param>
        /// <param name="delaySamples">start offset inside the next block</param>
        public void Trigger(float f0, float tau, float amplitude, float rise, int delaySamples = 0)
        {
            int i = next; next = (next + 1) % Max;
            phase[i] = 0f;
            freq[i] = f0 * invSr;
            dfreq[i] = f0 * rise * invSr * invSr;
            amp[i] = amplitude;
            decay[i] = MathF.Exp(-invSr / Math.Max(1e-4f, tau));
            delay[i] = delaySamples;
            any = true;
        }

        public bool Active { get { return any; } }

        /// <summary>Single-sample tick (tests). Do not mix with <see cref="AddBlock"/> on the same bank.</summary>
        public float Tick()
        {
            if (!any) return 0f;
            float s = 0f; bool alive = false;
            for (int i = 0; i < Max; i++)
            {
                float a = amp[i];
                if (a < 2.5e-3f) continue;
                alive = true;
                if (delay[i] > 0) { delay[i]--; continue; }
                float ph = phase[i];
                s += a * SinTable.Sin(ph);
                ph += freq[i];
                phase[i] = ph - (int)ph;
                freq[i] += dfreq[i];
                amp[i] = a * decay[i];
            }
            any = alive;
            return s;
        }

        /// <summary>Add the bubbles for the next n samples into dst[off..off+n) (voice-major loops with locals).</summary>
        public void AddBlock(float[] dst, int off, int n, float gain = 1f)
        {
            if (!any) return;
            var tab = SinTable.t;
            bool alive = false;
            for (int v = 0; v < Max; v++)
            {
                float a = amp[v];
                if (a < 1.2e-3f) continue;
                int d = delay[v];
                if (d >= n) { delay[v] = d - n; alive = true; continue; }
                float ph = phase[v], fr = freq[v], dfr = dfreq[v], dec = decay[v];
                float ag = a * gain;
                for (int i = d; i < n; i++)
                {
                    float x = ph * 4096f; int ix = (int)x; float f = x - ix;
                    dst[off + i] += ag * (tab[ix] + (tab[ix + 1] - tab[ix]) * f);
                    ph += fr; if (ph >= 1f) ph -= 1f;
                    fr += dfr; ag *= dec;
                }
                delay[v] = 0; phase[v] = ph; freq[v] = fr;
                float na = gain > 0f ? ag / gain : 0f;
                if (na >= 2.5e-3f) { amp[v] = na; alive = true; } else amp[v] = 0f;
            }
            any = alive;
        }
    }

    /// <summary>Single-cycle wavetable with a wrap-around guard sample and linear interpolation.</summary>
    public sealed class CycleTable
    {
        public readonly int n;
        public readonly float[] data;
        public CycleTable(int size) { n = size; data = new float[size + 1]; }

        public void Finish()
        {
            data[n] = data[0];
        }

        /// <summary>Remove the mean and scale so max |x| = peak.</summary>
        public void NormalizeZeroMean(float peak)
        {
            double mean = 0;
            for (int i = 0; i < n; i++) mean += data[i];
            mean /= n;
            float mx = 1e-9f;
            for (int i = 0; i < n; i++) { data[i] -= (float)mean; mx = Math.Max(mx, Math.Abs(data[i])); }
            float g = peak / mx;
            for (int i = 0; i < n; i++) data[i] *= g;
            Finish();
        }

        /// <summary>phase in [0,1)</summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public float Read(float phase)
        {
            float x = phase * n;
            int i = (int)x;
            float f = x - i;
            return data[i] + (data[i + 1] - data[i]) * f;
        }
    }


    /// <summary>
    /// Inhomogeneous Poisson event clock: call <see cref="Tick"/> once per sample with the current rate (events per sample).
    /// Exact for time-varying rates, one subtraction per sample.
    /// </summary>
    public struct PoissonClock
    {
        public float acc;
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public bool Tick(float ratePerSample, Rng rng)
        {
            if (acc <= 0f) acc = rng.Exp(1f);
            acc -= ratePerSample;
            if (acc > 0f) return false;
            acc = rng.Exp(1f);
            return true;
        }
    }

    /// <summary>Lock-free single-producer/single-consumer event queue (main thread pushes, audio thread pops). No allocation.</summary>
    public struct VoiceEvent
    {
        public int kind;       // see Sfx / event conventions of the consumer
        public int variant;
        public float gain;
        public float pitch;
    }

    public sealed class EventQueue
    {
        const int Cap = 64;               // power of two
        readonly VoiceEvent[] buf = new VoiceEvent[Cap];
        int head;                          // written by producer
        int tail;                          // written by consumer

        public bool Push(in VoiceEvent e)
        {
            int h = System.Threading.Volatile.Read(ref head);
            int t = System.Threading.Volatile.Read(ref tail);
            if (h - t >= Cap) return false;
            buf[h & (Cap - 1)] = e;
            System.Threading.Volatile.Write(ref head, h + 1);
            return true;
        }

        public bool TryPop(out VoiceEvent e)
        {
            int t = System.Threading.Volatile.Read(ref tail);
            int h = System.Threading.Volatile.Read(ref head);
            if (t == h) { e = default; return false; }
            e = buf[t & (Cap - 1)];
            System.Threading.Volatile.Write(ref tail, t + 1);
            return true;
        }

        public int Count { get { return System.Threading.Volatile.Read(ref head) - System.Threading.Volatile.Read(ref tail); } }
        public void Clear() { while (TryPop(out _)) { } }
    }
}
