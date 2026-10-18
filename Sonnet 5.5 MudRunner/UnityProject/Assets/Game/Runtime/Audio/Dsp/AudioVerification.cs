using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace MudRunner.Audio.Dsp
{
    /// <summary>One verified scenario: statistics plus the sanity verdict.</summary>
    public sealed class ScenarioReport
    {
        public string name;
        public AudioStats stats;
        public bool pass;
        public string issue = "";
        public double renderMs;
        public float seconds;
        public float envCv;          // coefficient of variation of the 20 ms RMS envelope (non-stationarity)
    }

    /// <summary>
    /// Numerical checks that stand in for listening: sanity of every scenario, engine fundamental / harmonic series versus the
    /// firing frequency, timbre separation, level ordering, and the CPU cost of the real-time voices. Used by the editor tool
    /// (prints + WAV) and by the tests (asserts); needs no audio device.
    /// </summary>
    public static class AudioVerification
    {
        // ------------------------------------------------------------------ scenario sanity

        /// <summary>Generic acceptance rules for a rendered buffer.</summary>
        public static string CheckSanity(string name, AudioStats st)
        {
            if (st.badCount > 0) return "NaN/Inf samples: " + st.badCount;
            if (st.clipCount > 0 || st.peak >= 0.999f) return "clipping (peak " + st.peak.ToString("F3") + ")";
            if (Math.Abs(st.dc) > 0.01f || Math.Abs(st.dc) > 0.05f * st.rms) return "DC offset " + st.dc.ToString("E1");
            if (st.rmsDb < -62f) return "too quiet (" + st.rmsDb.ToString("F1") + " dBFS)";
            if (st.rmsDb > -8f) return "too loud (" + st.rmsDb.ToString("F1") + " dBFS)";
            return "";
        }

        public static ScenarioReport RunScenario(string name, int sr, out RenderedAudio audio)
        {
            var sw = Stopwatch.StartNew();
            audio = AudioScenarios.Render(name, sr);
            sw.Stop();
            int skip = sr / 4;
            var rep = new ScenarioReport { name = name, renderMs = sw.Elapsed.TotalMilliseconds, seconds = audio.left.Length / (float)sr };
            var sl = AudioAnalysis.Analyze(audio.left, skip, audio.left.Length - skip, sr);
            rep.stats = sl;
            string issue = CheckSanity(name, sl);
            if (issue.Length == 0 && audio.right != null)
            {
                var sRight = AudioAnalysis.Analyze(audio.right, skip, audio.right.Length - skip, sr);
                issue = CheckSanity(name, sRight);
            }
            rep.issue = issue; rep.pass = issue.Length == 0;
            var env = AudioAnalysis.RmsCurve(audio.left, skip, audio.left.Length - skip, sr / 50);
            double m = 0, m2 = 0; foreach (var e in env) { m += e; m2 += (double)e * e; }
            m /= env.Length; double var_ = Math.Max(0, m2 / env.Length - m * m);
            rep.envCv = m > 1e-9 ? (float)(Math.Sqrt(var_) / m) : 0f;
            return rep;
        }

        // ------------------------------------------------------------------ engine firing frequency

        public sealed class EngineRow
        {
            public string engine; public float rpm, f0, peakNear, dbFund, dbH2, dbH3, dbHalf, floorDb, centroid, rmsDb; public bool pass;
        }

        static float Db(float power) { return 10f * (float)Math.Log10(power + 1e-14f); }

        public static EngineRow MeasureEngine(EngineProfile p, float rpm, float throttle, float load, int sr, uint seed = 777u)
        {
            var x = AudioScenarios.RenderVehicle(p, 4f, AudioScenarios.Steady(rpm, throttle, load), sr, seed, 512, false);
            int skip = sr / 2;
            int fft = 32768;
            var psd = AudioAnalysis.PowerSpectrum(x, skip, x.Length - skip, fft);
            float f0 = p.FiringHz(rpm);
            var row = new EngineRow { engine = p.name, rpm = rpm, f0 = f0 };
            float pf = AudioAnalysis.PowerNear(psd, fft, sr, f0, 0.012f);
            float p2 = AudioAnalysis.PowerNear(psd, fft, sr, f0 * 2f, 0.012f);
            float p3 = AudioAnalysis.PowerNear(psd, fft, sr, f0 * 3f, 0.012f);
            float half = AudioAnalysis.PowerNear(psd, fft, sr, f0 * 0.5f, 0.012f);
            float med = AudioAnalysis.MedianPower(psd, fft, sr, f0 * 0.6f, f0 * 6f);
            row.dbFund = Db(pf); row.dbH2 = Db(p2); row.dbH3 = Db(p3); row.dbHalf = Db(half); row.floorDb = Db(med);
            AudioAnalysis.PeakFrequency(psd, fft, sr, f0 * 0.85f, f0 * 1.15f, out float pk);
            row.peakNear = AudioAnalysis.PeakFrequency(psd, fft, sr, f0 * 0.85f, f0 * 1.15f, out _);
            var st = AudioAnalysis.Analyze(x, skip, x.Length - skip, sr);
            row.centroid = st.centroidHz; row.rmsDb = st.rmsDb;
            // fundamental and the next two partials must rise clearly above the broadband floor and the peak must sit at f0
            row.pass = (row.dbFund - row.floorDb) > 10f && (row.dbH2 - row.floorDb) > 6f && Math.Abs(row.peakNear - f0) / f0 < 0.02f;
            return row;
        }

        // ------------------------------------------------------------------ level ordering, timbre, CPU

        /// <summary>Octave-band levels (dB) of a signal, used as a coarse spectral fingerprint.</summary>
        public static float[] OctaveFingerprint(float[] x, int start, int count, int sr)
        {
            int fft = 16384;
            var psd = AudioAnalysis.PowerSpectrum(x, start, count, fft);
            float[] centers = { 63f, 125f, 250f, 500f, 1000f, 2000f, 4000f, 8000f };
            var fp = new float[centers.Length];
            float total = 0f;
            for (int i = 0; i < centers.Length; i++) { fp[i] = AudioAnalysis.BandPower(psd, fft, sr, centers[i] / 1.4142f, centers[i] * 1.4142f); total += fp[i]; }
            for (int i = 0; i < fp.Length; i++) fp[i] = Db(fp[i] / Math.Max(1e-14f, total));
            return fp;
        }

        public static float FingerprintDistance(float[] a, float[] b)
        {
            double s = 0; for (int i = 0; i < a.Length; i++) { double d = Math.Max(-60, a[i]) - Math.Max(-60, b[i]); s += d * d; }
            return (float)Math.Sqrt(s / a.Length);
        }

        /// <summary>CPU cost of one audio callback, in milliseconds per block.</summary>
        public sealed class CpuReport
        {
            public double typicalMedian, typicalP95;      // three vehicles driving in mud (engine + tyres + creak; one also wading / gravel, one winching)
            public double extremeMedian, extremeP95;      // every layer of every vehicle active at once
            public double ambienceMedian;                 // global ambience (rain + wind + night insects + frogs) + river voice
            public int vehicles, blockFrames;
        }

        static void Drive(VehicleSignals s, EngineProfile p, float t, int i, bool extreme)
        {
            s.engineOn = true; s.rpm = p.idleRpm * (2f + 0.5f * (float)Math.Sin(t * 0.8 + i)); s.throttle = 0.7f; s.load = 0.7f; s.strain = 0.3f; s.speed = 5f;
            s.wheelRev = 1.5f; s.mudRoll = 0.6f; s.mudSlip = 0.4f; s.suction = 0.5f; s.wetness = 0.6f; s.creak = 0.6f; s.creakSpeed = 0.4f;
            if (extreme) { s.gravel = 0.3f; s.grass = 0.2f; s.hard = 0.2f; s.wading = 0.5f; s.winchMotor = 1f; s.winchLoad = 0.5f; }
            else
            {
                s.gravel = i == 1 ? 0.3f : 0f; s.wading = i == 1 ? 0.5f : 0f; s.winchMotor = i == 2 ? 1f : 0f; s.winchLoad = i == 2 ? 0.5f : 0f;
                if (i == 1) { s.mudSlip = 0.1f; s.suction = 0.2f; }
            }
        }

        static void TimeVehicles(int vehicles, int blockFrames, int blocks, int sr, bool extreme, out double median, out double p95)
        {
            var bank = AudioScenarios.Bank(sr);
            var profiles = new[] { EngineProfile.Utility(), EngineProfile.Scout(), EngineProfile.Hauler(), EngineProfile.Utility() };
            var sigs = new VehicleSignals[vehicles];
            var syn = new VehicleSynth[vehicles];
            for (int i = 0; i < vehicles; i++)
            {
                sigs[i] = new VehicleSignals();
                syn[i] = new VehicleSynth(profiles[i % profiles.Length], sr, sigs[i], bank, (uint)i + 1u);
            }
            var buf = new float[blockFrames];
            var times = new double[blocks];
            double freq = Stopwatch.Frequency;
            for (int b = -60; b < blocks; b++)         // warm-up blocks (JIT)
            {
                long t0 = Stopwatch.GetTimestamp();
                for (int i = 0; i < vehicles; i++)
                {
                    float t = b * blockFrames / (float)sr;
                    Drive(sigs[i], profiles[i % profiles.Length], t, i, extreme);
                    if (b % 12 == 0) sigs[i].PushSfx(Sfx.BumpThump, 0.5f);
                    syn[i].Render(buf, 0, blockFrames);
                }
                long t1 = Stopwatch.GetTimestamp();
                if (b >= 0) times[b] = (t1 - t0) * 1000.0 / freq;
            }
            Array.Sort(times);
            median = times[blocks / 2]; p95 = times[(int)(blocks * 0.95)];
        }

        /// <summary>
        /// Time to synthesize one audio callback for N vehicles ("typical" heavy driving and the "extreme" case with every layer on)
        /// plus the global ambience worst case (heavy rain + wind + night insects + frogs + roof) and the river voice.
        /// </summary>
        public static CpuReport MeasureCpu(int vehicles, int blockFrames, int blocks, int sr, int repeats = 3)
        {
            // CPU contention (other processes) can only inflate a measurement, so keep the best of a few repeats
            CpuReport best = null;
            for (int k = 0; k < Math.Max(1, repeats); k++)
            {
                var c = MeasureCpuOnce(vehicles, blockFrames, blocks, sr);
                if (best == null) { best = c; continue; }
                best.typicalMedian = Math.Min(best.typicalMedian, c.typicalMedian); best.typicalP95 = Math.Min(best.typicalP95, c.typicalP95);
                best.extremeMedian = Math.Min(best.extremeMedian, c.extremeMedian); best.extremeP95 = Math.Min(best.extremeP95, c.extremeP95);
                best.ambienceMedian = Math.Min(best.ambienceMedian, c.ambienceMedian);
            }
            return best;
        }

        static CpuReport MeasureCpuOnce(int vehicles, int blockFrames, int blocks, int sr)
        {
            var r = new CpuReport { vehicles = vehicles, blockFrames = blockFrames };
            TimeVehicles(vehicles, blockFrames, blocks, sr, false, out r.typicalMedian, out r.typicalP95);
            TimeVehicles(vehicles, blockFrames, blocks, sr, true, out r.extremeMedian, out r.extremeP95);

            var amb = new AmbienceSynth(sr, 5u); var river = new RiverSynth(sr);
            var ap = new AmbienceParams { rain = 0.8f, wind = 0.6f, night = 1f, swamp = 0.8f, forest = 0.5f, roof = 0.5f, wetGround = 0.8f, day = 0.3f };
            var l = new float[blockFrames]; var rr = new float[blockFrames]; var m = new float[blockFrames];
            var at = new double[blocks];
            double freq = Stopwatch.Frequency;
            for (int b = -60; b < blocks; b++)
            {
                long t0 = Stopwatch.GetTimestamp();
                amb.Render(ap, l, rr, 0, blockFrames);
                river.Render(0.8f, 1.5f, m, 0, blockFrames);
                long t1 = Stopwatch.GetTimestamp();
                if (b >= 0) at[b] = (t1 - t0) * 1000.0 / freq;
            }
            Array.Sort(at); r.ambienceMedian = at[blocks / 2];
            return r;
        }
    }
}
