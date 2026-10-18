using System;
using System.IO;

namespace MudRunner.Audio.Dsp
{
    /// <summary>Numerical sanity statistics of a rendered buffer (used by the offline renderer and the tests).</summary>
    public struct AudioStats
    {
        public int frames;
        public float peak;           // max |x|
        public float rms;            // linear RMS
        public float rmsDb;          // dBFS
        public float dc;             // mean
        public float centroidHz;     // spectral centroid (20 Hz .. Nyquist), power weighted
        public float rolloff85Hz;    // frequency below which 85 % of the power lies
        public float crest;          // peak / rms
        public int badCount;         // NaN or Inf samples
        public int clipCount;        // samples with |x| >= 0.999
        public float sampleRate;

        public override string ToString()
        {
            return "peak=" + peak.ToString("F3") + " rms=" + rms.ToString("F4") + " (" + rmsDb.ToString("F1") + " dBFS) dc=" + dc.ToString("E1")
                 + " centroid=" + centroidHz.ToString("F0") + "Hz roll85=" + rolloff85Hz.ToString("F0") + "Hz crest=" + crest.ToString("F1")
                 + " nan/inf=" + badCount + " clip=" + clipCount;
        }
    }

    /// <summary>FFT, Welch power spectrum and the derived measures used to verify synthesized audio without listening to it.</summary>
    public static class AudioAnalysis
    {
        /// <summary>In-place radix-2 complex FFT (length must be a power of two).</summary>
        public static void Fft(float[] re, float[] im)
        {
            int n = re.Length;
            // bit reversal
            for (int i = 1, j = 0; i < n; i++)
            {
                int bit = n >> 1;
                for (; (j & bit) != 0; bit >>= 1) j ^= bit;
                j ^= bit;
                if (i < j) { float tr = re[i]; re[i] = re[j]; re[j] = tr; float ti = im[i]; im[i] = im[j]; im[j] = ti; }
            }
            for (int len = 2; len <= n; len <<= 1)
            {
                double ang = -2.0 * Math.PI / len;
                float wr = (float)Math.Cos(ang), wi = (float)Math.Sin(ang);
                int half = len >> 1;
                for (int i = 0; i < n; i += len)
                {
                    double cr = 1.0, ci = 0.0;
                    for (int k = 0; k < half; k++)
                    {
                        int a = i + k, b = a + half;
                        float xr = (float)(re[b] * cr - im[b] * ci), xi = (float)(re[b] * ci + im[b] * cr);
                        re[b] = re[a] - xr; im[b] = im[a] - xi;
                        re[a] += xr; im[a] += xi;
                        double ncr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = ncr;
                    }
                }
            }
        }

        /// <summary>
        /// Welch-averaged power spectrum (Hann window, 50 % overlap) of x[start .. start+count). Returns fftSize/2+1 bins of
        /// mean |X|^2 normalised so a full-scale sine of amplitude A gives about A^2/4 * fftSize^2 * window gain in its bin.
        /// </summary>
        public static float[] PowerSpectrum(float[] x, int start, int count, int fftSize)
        {
            var psd = new float[fftSize / 2 + 1];
            var re = new float[fftSize]; var im = new float[fftSize];
            var win = new float[fftSize];
            double wsum = 0;
            for (int i = 0; i < fftSize; i++) { win[i] = 0.5f - 0.5f * (float)Math.Cos(2.0 * Math.PI * i / fftSize); wsum += win[i]; }
            int hop = fftSize / 2;
            int segs = 0;
            for (int s = start; s == start || s + fftSize <= start + count; s += hop)
            {
                for (int i = 0; i < fftSize; i++)
                {
                    int idx = s + i;
                    re[i] = (idx < start + count && idx < x.Length) ? x[idx] * win[i] : 0f;
                    im[i] = 0f;
                }
                Fft(re, im);
                for (int k = 0; k <= fftSize / 2; k++) psd[k] += re[k] * re[k] + im[k] * im[k];
                segs++;
                if (s + fftSize > start + count) break;
            }
            float norm = 1f / (segs * (float)(wsum * wsum));
            for (int k = 0; k < psd.Length; k++) psd[k] *= norm;       // |X|^2 / (sum w)^2 : sine of amplitude A -> A^2/4
            return psd;
        }

        public static AudioStats Analyze(float[] x, int sampleRate) { return Analyze(x, 0, x.Length, sampleRate); }

        public static AudioStats Analyze(float[] x, int start, int count, int sampleRate)
        {
            var st = new AudioStats { frames = count, sampleRate = sampleRate };
            double sum = 0, sum2 = 0; float pk = 0;
            for (int i = start; i < start + count; i++)
            {
                float v = x[i];
                if (DspMath.IsBad(v)) { st.badCount++; continue; }
                float a = Math.Abs(v);
                if (a > pk) pk = a;
                if (a >= 0.999f) st.clipCount++;
                sum += v; sum2 += (double)v * v;
            }
            int good = Math.Max(1, count - st.badCount);
            st.peak = pk;
            st.dc = (float)(sum / good);
            st.rms = (float)Math.Sqrt(sum2 / good);
            st.rmsDb = DspMath.LinToDb(st.rms);
            st.crest = st.rms > 1e-9f ? st.peak / st.rms : 0f;
            if (st.badCount == 0 && count >= 256)
            {
                int fft = 4096; while (fft > count) fft >>= 1;
                var psd = PowerSpectrum(x, start, count, fft);
                float binHz = sampleRate / (float)fft;
                double tot = 0, wsum = 0;
                for (int k = 1; k < psd.Length; k++)
                {
                    float f = k * binHz; if (f < 20f) continue;
                    tot += psd[k]; wsum += psd[k] * f;
                }
                st.centroidHz = tot > 0 ? (float)(wsum / tot) : 0f;
                double acc = 0; st.rolloff85Hz = 0;
                for (int k = 1; k < psd.Length; k++)
                {
                    float f = k * binHz; if (f < 20f) continue;
                    acc += psd[k];
                    if (acc >= 0.85 * tot) { st.rolloff85Hz = f; break; }
                }
            }
            return st;
        }

        /// <summary>Total power (sum of the PSD bins) between f1 and f2.</summary>
        public static float BandPower(float[] psd, int fftSize, float sampleRate, float f1, float f2)
        {
            float binHz = sampleRate / fftSize;
            int k1 = Math.Max(1, (int)Math.Floor(f1 / binHz)), k2 = Math.Min(psd.Length - 1, (int)Math.Ceiling(f2 / binHz));
            double s = 0;
            for (int k = k1; k <= k2; k++) s += psd[k];
            return (float)s;
        }

        /// <summary>RMS (linear amplitude) contained in the band, from the PSD (Parseval-consistent up to the window gain).</summary>
        public static float BandRms(float[] x, int start, int count, int sampleRate, float f1, float f2, int fftSize = 8192)
        {
            int fft = fftSize; while (fft > count) fft >>= 1;
            var psd = PowerSpectrum(x, start, count, fft);
            // Hann window: a sine of amplitude A puts 3*A^2/8 of summed PSD into its bins, and its mean square is A^2/2
            return (float)Math.Sqrt(BandPower(psd, fft, sampleRate, f1, f2) * (4f / 3f));
        }

        /// <summary>Frequency of the largest PSD bin in [f1,f2] with parabolic refinement.</summary>
        public static float PeakFrequency(float[] psd, int fftSize, float sampleRate, float f1, float f2, out float peakPower)
        {
            float binHz = sampleRate / fftSize;
            int k1 = Math.Max(1, (int)Math.Floor(f1 / binHz)), k2 = Math.Min(psd.Length - 2, (int)Math.Ceiling(f2 / binHz));
            int best = k1; float bp = -1;
            for (int k = k1; k <= k2; k++) if (psd[k] > bp) { bp = psd[k]; best = k; }
            peakPower = bp;
            float a = psd[Math.Max(1, best - 1)], b = psd[best], c = psd[Math.Min(psd.Length - 1, best + 1)];
            float den = a - 2f * b + c;
            float off = Math.Abs(den) > 1e-20f ? 0.5f * (a - c) / den : 0f;
            return (best + Math.Max(-1f, Math.Min(1f, off))) * binHz;
        }

        /// <summary>Largest PSD value within +-tolerance (fraction) of f. Handy for harmonic-series checks.</summary>
        public static float PowerNear(float[] psd, int fftSize, float sampleRate, float f, float tolFrac)
        {
            float binHz = sampleRate / fftSize;
            int k1 = Math.Max(1, (int)Math.Floor(f * (1f - tolFrac) / binHz)), k2 = Math.Min(psd.Length - 1, (int)Math.Ceiling(f * (1f + tolFrac) / binHz));
            float m = 0;
            for (int k = k1; k <= k2; k++) if (psd[k] > m) m = psd[k];
            return m;
        }

        /// <summary>Median PSD in [f1,f2] (noise-floor estimate).</summary>
        public static float MedianPower(float[] psd, int fftSize, float sampleRate, float f1, float f2)
        {
            float binHz = sampleRate / fftSize;
            int k1 = Math.Max(1, (int)Math.Floor(f1 / binHz)), k2 = Math.Min(psd.Length - 1, (int)Math.Ceiling(f2 / binHz));
            int n = Math.Max(1, k2 - k1 + 1);
            var tmp = new float[n];
            Array.Copy(psd, k1, tmp, 0, n);
            Array.Sort(tmp);
            return tmp[n / 2];
        }

        /// <summary>Short-time RMS curve (one value per hop).</summary>
        public static float[] RmsCurve(float[] x, int start, int count, int hop)
        {
            int n = Math.Max(1, count / hop);
            var r = new float[n];
            for (int i = 0; i < n; i++)
            {
                double s = 0; int c = 0;
                for (int j = 0; j < hop && start + i * hop + j < x.Length; j++) { float v = x[start + i * hop + j]; s += (double)v * v; c++; }
                r[i] = c > 0 ? (float)Math.Sqrt(s / c) : 0f;
            }
            return r;
        }
    }

    /// <summary>Minimal RIFF/WAVE writer (16-bit PCM, mono or stereo).</summary>
    public static class WavFile
    {
        public static void WriteMono(string path, float[] x, int sampleRate) { Write(path, x, null, sampleRate); }

        public static void Write(string path, float[] left, float[] right, int sampleRate)
        {
            int ch = right == null ? 1 : 2;
            int n = left.Length;
            string dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write))
            using (var w = new BinaryWriter(fs))
            {
                int dataBytes = n * ch * 2;
                w.Write(new[] { (byte)'R', (byte)'I', (byte)'F', (byte)'F' });
                w.Write(36 + dataBytes);
                w.Write(new[] { (byte)'W', (byte)'A', (byte)'V', (byte)'E', (byte)'f', (byte)'m', (byte)'t', (byte)' ' });
                w.Write(16); w.Write((short)1); w.Write((short)ch); w.Write(sampleRate);
                w.Write(sampleRate * ch * 2); w.Write((short)(ch * 2)); w.Write((short)16);
                w.Write(new[] { (byte)'d', (byte)'a', (byte)'t', (byte)'a' });
                w.Write(dataBytes);
                for (int i = 0; i < n; i++)
                {
                    w.Write(ToPcm(left[i]));
                    if (ch == 2) w.Write(ToPcm(right[i]));
                }
            }
        }

        static short ToPcm(float v)
        {
            if (DspMath.IsBad(v)) return 0;
            int s = (int)Math.Round(v * 32767.0);
            return (short)(s > 32767 ? 32767 : (s < -32768 ? -32768 : s));
        }
    }
}
