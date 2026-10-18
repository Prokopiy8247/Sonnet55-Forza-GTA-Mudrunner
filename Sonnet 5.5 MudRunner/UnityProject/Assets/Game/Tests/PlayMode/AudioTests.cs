using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using MudRunner.Audio;
using MudRunner.Audio.Dsp;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Testing;
using MudRunner.Vehicles;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace MudRunner.Tests
{
    /// <summary>
    /// Audio verification without listening and without an audio device: the pure DSP classes are rendered offline and
    /// asserted numerically (levels, spectra, firing-frequency physics, no NaN/clipping, allocation-free, CPU budget), plus a
    /// director integration smoke test with real vehicles. All numbers are logged with the [MudRunner] prefix.
    /// </summary>
    public class AudioTests
    {
        const int SR = 48000;

        static void Log(string s) { Debug.Log("[MudRunner] AUDIO " + s); }

        // ------------------------------------------------------------------ DSP primitives

        [Test]
        public void Rng_IsUniformAndDeterministic()
        {
            var a = new Rng(42); var b = new Rng(42);
            double sum = 0, sum2 = 0; int n = 200000;
            for (int i = 0; i < n; i++)
            {
                float x = a.Next01(); Assert.AreEqual(x, b.Next01());
                Assert.GreaterOrEqual(x, 0f); Assert.Less(x, 1f);
                sum += x; sum2 += x * x;
            }
            Assert.AreEqual(0.5, sum / n, 0.01);
            Assert.AreEqual(1.0 / 12.0, sum2 / n - (sum / n) * (sum / n), 0.005);
        }

        [Test]
        public void Svf_Lowpass_HasExpectedCornerAndSlope()
        {
            float fc = 1000f;
            Assert.AreEqual(-3f, ToneGainDb(fc, f => { var s = new Svf(); s.Set(fc, 0.7071f, SR); return (x) => { s.Tick(x); return s.lp; }; }), 0.6f, "-3 dB at the corner");
            float g2 = ToneGainDb(fc * 4f, f => { var s = new Svf(); s.Set(fc, 0.7071f, SR); return (x) => { s.Tick(x); return s.lp; }; });
            float g1 = ToneGainDb(fc * 2f, f => { var s = new Svf(); s.Set(fc, 0.7071f, SR); return (x) => { s.Tick(x); return s.lp; }; });
            Assert.AreEqual(-12f, g2 - g1, 1.5f, "12 dB/octave");
            Assert.AreEqual(0f, ToneGainDb(100f, f => { var s = new Svf(); s.Set(fc, 0.7071f, SR); return (x) => { s.Tick(x); return s.lp; }; }), 0.3f, "flat in the passband");
        }

        [Test]
        public void Svf_Bandpass_PeaksAtCentre()
        {
            Func<float, Func<float, float>> mk = f => { var s = new Svf(); s.Set(800f, 8f, SR); return (x) => s.Tick(x) * s.k; };
            float at = ToneGainDb(800f, mk), off = ToneGainDb(3200f, mk);
            Assert.AreEqual(0f, at, 0.5f);
            Assert.Less(off, -20f);
        }

        [Test]
        public void Biquad_Responses()
        {
            var lp = new Biquad().Lowpass(2000f, 0.7071f, SR);
            Assert.AreEqual(-3f, ToneGainDb(2000f, f => lp.Process), 0.6f);
            var bp = new Biquad().Bandpass(1000f, 4f, SR);
            Assert.AreEqual(0f, ToneGainDb(1000f, f => bp.Process), 0.5f);
            var notch = new Biquad().Notch(1000f, 6f, SR);
            Assert.Less(ToneGainDb(1000f, f => notch.Process), -30f);
        }

        /// <summary>Gain (dB) of a filter for a sine of frequency f, measured after the transient.</summary>
        static float ToneGainDb(float f, Func<float, Func<float, float>> make)
        {
            var proc = make(f);
            int n = SR; double in2 = 0, out2 = 0;
            for (int i = 0; i < n; i++)
            {
                float x = (float)Math.Sin(2 * Math.PI * f * i / SR) * 0.5f;
                float y = proc(x);
                if (i > n / 2) { in2 += x * x; out2 += y * y; }
            }
            return 10f * (float)Math.Log10(out2 / in2);
        }

        [Test]
        public void Fft_FindsSinePeak_AndParsevalHolds()
        {
            var x = new float[SR];
            for (int i = 0; i < x.Length; i++) x[i] = 0.5f * (float)Math.Sin(2 * Math.PI * 1234.0 * i / SR);
            int fft = 16384;
            var psd = AudioAnalysis.PowerSpectrum(x, 0, x.Length, fft);
            float f = AudioAnalysis.PeakFrequency(psd, fft, SR, 100f, 5000f, out _);
            Assert.AreEqual(1234f, f, 3f);
            float rms = AudioAnalysis.BandRms(x, 0, x.Length, SR, 1000f, 1500f, fft);
            Assert.AreEqual(0.5f / Mathf.Sqrt(2f), rms, 0.01f, "band RMS of a sine");
        }

        [Test]
        public void PinkNoise_FallsAboutThreeDbPerOctave()
        {
            var rng = new Rng(7); var pink = new PinkFilter();
            var x = new float[SR * 4];
            for (int i = 0; i < x.Length; i++) x[i] = pink.Process(rng.Signed());
            int fft = 16384;
            var psd = AudioAnalysis.PowerSpectrum(x, 0, x.Length, fft);
            float p1 = AudioAnalysis.BandPower(psd, fft, SR, 200f, 400f);      // one octave
            float p2 = AudioAnalysis.BandPower(psd, fft, SR, 400f, 800f);
            float p3 = AudioAnalysis.BandPower(psd, fft, SR, 3200f, 6400f);
            Assert.AreEqual(0f, 10f * Mathf.Log10(p2 / p1), 1.2f, "equal power per octave for pink noise");
            Assert.AreEqual(0f, 10f * Mathf.Log10(p3 / p1), 2.0f);
        }

        [Test]
        public void BubbleBank_RingsAtRequestedFrequency_AndDecays()
        {
            var b = new BubbleBank(SR);
            b.Trigger(800f, 0.03f, 1f, 0f);
            var x = new float[SR / 4];
            for (int i = 0; i < x.Length; i++) x[i] = b.Tick();
            var psd = AudioAnalysis.PowerSpectrum(x, 0, 4096, 4096);
            Assert.AreEqual(800f, AudioAnalysis.PeakFrequency(psd, 4096, SR, 100f, 4000f, out _), 40f);
            Assert.Less(Mathf.Abs(x[x.Length - 1]), 1e-3f, "decayed");
        }

        [Test]
        public void EventQueue_IsFifoAndBounded()
        {
            var q = new EventQueue();
            for (int i = 0; i < 100; i++) q.Push(new VoiceEvent { kind = i });
            int popped = 0;
            while (q.TryPop(out var e)) { Assert.AreEqual(popped, e.kind); popped++; }
            Assert.AreEqual(64, popped, "fixed capacity, overflow dropped");
        }

        [Test]
        public void SmallDspUtilities_BehaveAsDocumented()
        {
            // one-pole: step reaches 1-1/e after one time constant
            var op = new OnePole(); float a = OnePole.CoefForCutoff(100f, SR); float y = 0f;
            for (int i = 0; i < (int)(SR / (2f * Mathf.PI * 100f)); i++) y = op.Lp(1f, a);
            Assert.AreEqual(0.632f, y, 0.03f);
            // DC blocker removes an offset
            var dc = new DcBlocker(); float o = 0f; for (int i = 0; i < SR; i++) o = dc.Process(0.5f, 0.9985f);
            Assert.Less(Mathf.Abs(o), 0.01f);
            // exponential decay envelope
            var d = new Decay(); d.Trigger(1f, 0.05f, SR); float v = 0f; for (int i = 0; i < (int)(0.05f * SR); i++) v = d.Tick();
            Assert.AreEqual(0.368f, v, 0.01f);
            // inhomogeneous Poisson clock: event count follows the rate (200 /s for 20 s)
            var pc = new PoissonClock(); var r = new Rng(3); int n = 0; float rate = 200f / SR;
            for (int i = 0; i < SR * 20; i++) if (pc.Tick(rate, r)) n++;
            Assert.AreEqual(4000f, n, 4000f * 0.06f);
            // soft limiters: identity below the knee, monotonic, bounded
            float prev = -2f;
            for (float x = -3f; x <= 3f; x += 0.01f) { float k = DspMath.SoftKnee(x); Assert.GreaterOrEqual(k, prev - 1e-6f); Assert.LessOrEqual(Mathf.Abs(k), 0.9701f); prev = k; }
            Assert.AreEqual(0.5f, DspMath.SoftKnee(0.5f), 1e-6f); Assert.AreEqual(0.7f, DspMath.MasterKnee(0.7f), 1e-6f); Assert.LessOrEqual(DspMath.MasterKnee(5f), 1f);
            // TPT one-pole coefficient gives the textbook -3 dB point
            float g = DspMath.TptG(1000f, SR); float s = 0f, e1 = 0f, e2 = 0f;
            for (int i = 0; i < SR; i++)
            {
                float x = Mathf.Sin(2f * Mathf.PI * 1000f * i / SR);
                float q = (x - s) * g; float yy = q + s; s = yy + q;
                if (i > SR / 2) { e1 += x * x; e2 += yy * yy; }
            }
            Assert.AreEqual(-3f, 10f * Mathf.Log10(e2 / e1), 0.4f);
        }

        [Test]
        public void NoiseTable_SlicesAreWhite_AndGrainMixerIsSampleAccurate()
        {
            var rng = new Rng(11); var buf = new float[128]; var all = new float[SR * 2];
            for (int o = 0; o + 128 <= all.Length; o += 128) { Block.Noise(rng, buf, 128); System.Array.Copy(buf, 0, all, o, 128); }
            int fft = 8192; var psd = AudioAnalysis.PowerSpectrum(all, 0, all.Length, fft);
            float lo = AudioAnalysis.BandPower(psd, fft, SR, 200f, 2000f) / 1800f, hi = AudioAnalysis.BandPower(psd, fft, SR, 12000f, 14000f) / 2000f;
            Assert.AreEqual(0f, 10f * Mathf.Log10(lo / hi), 1.0f, "flat spectrum");
            var st = AudioAnalysis.Analyze(all, SR);
            Assert.Less(Mathf.Abs(st.dc), 0.01f); Assert.AreEqual(0.577f, st.rms, 0.03f);

            var gm = new GrainMixer(); var grain = new float[] { 1f, 2f, 3f, 4f, 5f };
            var dst = new float[16];
            gm.Add(grain, 3, 0.5f);
            gm.Mix(dst, 0, 6);                       // starts at index 3: 0.5, 1, 1.5 inside the first block
            gm.Mix(dst, 6, 6);                       // continues: 2, 2.5 then done
            Assert.AreEqual(0f, dst[2]); Assert.AreEqual(0.5f, dst[3]); Assert.AreEqual(1.5f, dst[5]); Assert.AreEqual(2f, dst[6]); Assert.AreEqual(2.5f, dst[7]); Assert.AreEqual(0f, dst[8]);
            Assert.AreEqual(0, gm.Active);
        }

        [Test]
        public void HarmonicTables_HaveTheirPartials()
        {
            // rectangular-window DFT of exactly one table cycle: bin k holds harmonic k with no leakage
            var re = new float[4096]; var im = new float[4096];
            System.Array.Copy(HarmonicTables.Hum, re, 4096);
            AudioAnalysis.Fft(re, im);
            float Amp(int k) { return 2f * Mathf.Sqrt(re[k] * re[k] + im[k] * im[k]) / 4096f; }
            Assert.AreEqual(1f, Amp(1), 0.01f); Assert.AreEqual(0.55f, Amp(2), 0.01f); Assert.AreEqual(0.35f, Amp(3), 0.01f);
            Assert.Less(Amp(4), 0.01f); Assert.AreEqual(0.2f, Amp(5), 0.01f); Assert.Less(Amp(6), 0.01f);
        }

        [Test]
        public void Signals_Sanitize_ReplacesNaNAndClamps()
        {
            var s = new VehicleSignals { rpm = float.NaN, mudRoll = 5f, doppler = float.NaN, speed = -3f, wading = float.PositiveInfinity, master = -1f };
            s.Sanitize();
            Assert.AreEqual(0f, s.rpm); Assert.AreEqual(1f, s.mudRoll); Assert.AreEqual(1f, s.doppler); Assert.AreEqual(0f, s.speed); Assert.AreEqual(1f, s.wading); Assert.AreEqual(0f, s.master);
        }

        [Test]
        public void VehicleVoice_Process_FillsEveryChannel_AndSurvivesBadSignals()
        {
            var go = new GameObject("TestVoice"); spawned.Add(go);
            var voice = go.AddComponent<VehicleVoice>();
            var sig = new VehicleSignals { engineOn = true, rpm = 2000f, throttle = 0.5f, load = 0.5f, speed = 5f };
            voice.synth = new VehicleSynth(EngineProfile.Utility(), SR, sig, null, 1);
            foreach (int ch in new[] { 1, 2, 6 })
            {
                var data = new float[ch * 1500];
                voice.Process(data, ch); voice.Process(data, ch);
                double e = 0;
                for (int f = 0; f < 1500; f++)
                    for (int c = 1; c < ch; c++) Assert.AreEqual(data[f * ch], data[f * ch + c], "mono voice replicated into channel " + c);
                for (int f = 0; f < 1500; f++) e += data[f * ch] * data[f * ch];
                Assert.Greater(e, 1e-3, "audible output with " + ch + " channels");
            }
            // a NaN rpm must neither throw out of the callback nor leak NaN into the output
            sig.rpm = float.NaN;
            var bad = new float[2 * 1024];
            for (int i = 0; i < 4; i++) { voice.Process(bad, 2); foreach (var v in bad) Assert.IsFalse(float.IsNaN(v) || float.IsInfinity(v)); }
            Log("voice after NaN rpm: faulted=" + voice.faulted);
        }

        // ------------------------------------------------------------------ engines

        static readonly string[] Keys = { "scout", "utility", "hauler" };

        [Test]
        public void Engine_FundamentalIsFiringFrequency([ValueSource(nameof(Keys))] string key)
        {
            var p = EngineProfile.ForKey(key);
            var sb = new StringBuilder();
            foreach (float mult in new[] { 1.5f, 3.0f, 4.6f })
            {
                float rpm = Mathf.Min(p.idleRpm * mult, p.redlineRpm * 0.9f);
                var r = AudioVerification.MeasureEngine(p, rpm, 0.4f, 0.4f, SR);
                sb.Append(string.Format("{0} rpm {1:F0}: f0={2:F1}Hz peak@{3:F1} fund={4:F1}dB h2={5:F1} h3={6:F1} floor={7:F1} cent={8:F0}Hz rms={9:F1}dBFS | ", key, r.rpm, r.f0, r.peakNear, r.dbFund, r.dbH2, r.dbH3, r.floorDb, r.centroid, r.rmsDb));
                Assert.AreEqual(r.f0, r.peakNear, r.f0 * 0.02f, key + " strongest partial near rpm/60*cyl/2 at " + rpm);
                Assert.Greater(r.dbFund - r.floorDb, 10f, "fundamental clearly above the noise floor");
                Assert.Greater(r.dbH2 - r.floorDb, 6f, "second harmonic present");
                Assert.Greater(r.dbH3 - r.floorDb, 4f, "third harmonic present");
            }
            Log(sb.ToString());
        }

        [Test]
        public void Engine_PitchScalesWithRpm()
        {
            var p = EngineProfile.Utility();
            float Peak(float rpm)
            {
                var x = AudioScenarios.RenderVehicle(p, 3f, AudioScenarios.Steady(rpm, 0.4f, 0.4f), SR, 5, 512, false);
                int fft = 32768; var psd = AudioAnalysis.PowerSpectrum(x, SR / 2, x.Length - SR / 2, fft);
                float f0 = p.FiringHz(rpm);
                return AudioAnalysis.PeakFrequency(psd, fft, SR, f0 * 0.8f, f0 * 1.2f, out _);
            }
            float a = Peak(1000f), b = Peak(2000f), c = Peak(3000f);
            Assert.AreEqual(2f, b / a, 0.04f); Assert.AreEqual(3f, c / a, 0.06f);
        }

        [Test]
        public void Engine_ThreeTimbresAreDistinct()
        {
            var fps = new List<float[]>(); var cents = new List<float>();
            foreach (var k in Keys)
            {
                var p = EngineProfile.ForKey(k);
                float rpm = p.idleRpm + (p.redlineRpm - p.idleRpm) * 0.4f;
                var x = AudioScenarios.RenderVehicle(p, 4f, AudioScenarios.Steady(rpm, 0.5f, 0.5f), SR, 3, 512, false);
                fps.Add(AudioVerification.OctaveFingerprint(x, SR / 2, x.Length - SR / 2, SR));
                cents.Add(AudioAnalysis.Analyze(x, SR / 2, x.Length - SR / 2, SR).centroidHz);
            }
            float d01 = AudioVerification.FingerprintDistance(fps[0], fps[1]), d02 = AudioVerification.FingerprintDistance(fps[0], fps[2]), d12 = AudioVerification.FingerprintDistance(fps[1], fps[2]);
            Log(string.Format("timbre distances scout-utility {0:F1} scout-hauler {1:F1} utility-hauler {2:F1} dB; centroids {3:F0}/{4:F0}/{5:F0} Hz", d01, d02, d12, cents[0], cents[1], cents[2]));
            Assert.Greater(d01, 3f); Assert.Greater(d02, 3f); Assert.Greater(d12, 3f);
            Assert.Greater(cents[0], cents[1] * 1.5f, "scout is the buzzy bright one");
            Assert.Greater(cents[0], cents[2] * 1.5f);
        }

        [Test]
        public void Engine_LoadMakesItLouderAndBrighter([ValueSource(nameof(Keys))] string key)
        {
            var p = EngineProfile.ForKey(key);
            float rpm = p.idleRpm * 2.5f;
            var lo = AudioScenarios.RenderVehicle(p, 3f, AudioScenarios.Steady(rpm, 0.05f, 0.05f), SR, 9, 512, false);
            var hi = AudioScenarios.RenderVehicle(p, 3f, AudioScenarios.Steady(rpm, 1f, 0.9f), SR, 9, 512, false);
            var a = AudioAnalysis.Analyze(lo, SR / 2, lo.Length - SR / 2, SR); var b = AudioAnalysis.Analyze(hi, SR / 2, hi.Length - SR / 2, SR);
            Log(key + " load: " + a.rmsDb.ToString("F1") + " dB / " + a.centroidHz.ToString("F0") + " Hz -> " + b.rmsDb.ToString("F1") + " dB / " + b.centroidHz.ToString("F0") + " Hz");
            Assert.Greater(b.rmsDb, a.rmsDb + 2f); Assert.Greater(b.centroidHz, a.centroidHz);
        }

        [Test]
        public void Engine_RevSweepGetsLouderWithRpm([ValueSource(nameof(Keys))] string key)
        {
            var p = EngineProfile.ForKey(key);
            float LevelAt(float rpm)
            {
                var x = AudioScenarios.RenderVehicle(p, 2.5f, AudioScenarios.Steady(rpm, 0.5f, 0.5f), SR, 11, 512, false);
                return AudioAnalysis.Analyze(x, SR / 2, x.Length - SR / 2, SR).rmsDb;
            }
            float idle = LevelAt(p.idleRpm), mid = LevelAt((p.idleRpm + p.redlineRpm) * 0.5f), high = LevelAt(p.redlineRpm * 0.92f);
            Assert.Greater(mid, idle); Assert.Greater(high, mid - 0.5f);
        }

        [Test]
        public void Engine_StartCrankStallRestart_HasThePhases()
        {
            var p = EngineProfile.Utility();
            var x = AudioScenarios.RenderVehicle(p, 10.5f, AudioScenarios.StartStall(p), SR, 3, 512, false);
            var env = AudioAnalysis.RmsCurve(x, 0, x.Length, SR / 10);          // 100 ms
            float Db(int i) { return 20f * Mathf.Log10(env[i] + 1e-9f); }
            Assert.Less(Db(2), -80f, "silent before the key is turned");
            Assert.Greater(Db(8), -50f, "cranking is audible (starter + compression chug)");
            float running = Db(35);
            Assert.Greater(running, -40f, "engine running");
            Assert.Less(Db(65), running - 25f, "stalled: engine dies away");
            Assert.Greater(Db(78), -50f, "restart cranking");
            Assert.Less(Db(104), running - 25f, "key off at the end");
            Log("start/stall envelope dB per 0.1s: crank " + Db(8).ToString("F1") + " run " + running.ToString("F1") + " stalled " + Db(65).ToString("F1") + " off " + Db(104).ToString("F1"));
        }

        [Test]
        public void Engine_StrainAndFlood_AreAudiblyDifferent()
        {
            var p = EngineProfile.Utility();
            float rpm = p.idleRpm * 1.8f;
            var calm = AudioScenarios.RenderVehicle(p, 4f, AudioScenarios.Steady(rpm, 0.8f, 0.8f, 0f), SR, 3, 512, false);
            var strained = AudioScenarios.RenderVehicle(p, 4f, AudioScenarios.Steady(rpm, 0.8f, 0.8f, 1f), SR, 3, 512, false);
            var a = AudioAnalysis.Analyze(calm, SR, calm.Length - SR, SR); var b = AudioAnalysis.Analyze(strained, SR, strained.Length - SR, SR);
            Assert.Greater(b.rmsDb, a.rmsDb + 0.5f, "lugging engine is louder");
            // flooded engine splutters: strong amplitude irregularity compared to a healthy idle
            var healthy = AudioScenarios.RenderVehicle(p, 5f, AudioScenarios.Steady(p.idleRpm, 0.1f, 0.1f), SR, 3, 512, false);
            var flood = AudioScenarios.RenderVehicle(p, 5f, (t, s) => { s.engineOn = true; s.rpm = p.idleRpm; s.throttle = 0.1f; s.load = 0.1f; s.flood = 1f; }, SR, 3, 512, false);
            float cvH = Cv(healthy, SR), cvF = Cv(flood, SR);
            Log("flood irregularity CV healthy " + cvH.ToString("F2") + " flooded " + cvF.ToString("F2"));
            Assert.Greater(cvF, cvH * 1.15f);
        }

        static float Cv(float[] x, int sr)
        {
            var env = AudioAnalysis.RmsCurve(x, sr, x.Length - sr, sr / 25);     // 40 ms windows (about one firing at idle)
            double m = 0, m2 = 0; foreach (var e in env) { m += e; m2 += e * e; }
            m /= env.Length; return (float)(Math.Sqrt(Math.Max(0, m2 / env.Length - m * m)) / m);
        }

        [Test]
        public void Engine_HaulerHasTurboAndExhaustBrake()
        {
            var p = EngineProfile.Hauler();
            // turbo whistle: spools up under load -> narrow high line that is absent at idle
            var idle = AudioScenarios.RenderVehicle(p, 4f, (t, s) => { s.engineOn = true; s.rpm = 1500f; s.throttle = 0f; s.load = 0f; s.speed = 5f; s.exhaustBrakeOk = false; }, SR, 3, 512, false);
            var boost = AudioScenarios.RenderVehicle(p, 6f, AudioScenarios.Steady(1900f, 1f, 1f), SR, 3, 512, false);
            int fft = 16384;
            var pi = AudioAnalysis.PowerSpectrum(idle, SR * 2, SR * 2, fft); var pb = AudioAnalysis.PowerSpectrum(boost, SR * 4, SR * 2, fft);
            float hi0 = AudioAnalysis.BandPower(pi, fft, SR, 3000f, 5000f), hi1 = AudioAnalysis.BandPower(pb, fft, SR, 3000f, 5000f);
            Log("turbo band 3-5 kHz: idle " + (10 * Mathf.Log10(hi0 + 1e-14f)).ToString("F1") + " dB, boosted " + (10 * Mathf.Log10(hi1 + 1e-14f)).ToString("F1") + " dB");
            Assert.Greater(hi1, hi0 * 4f, "turbo whistle / intake roar appears with boost");
            // exhaust brake: lift-off while rolling is much louder than the same rpm without it
            var noBrake = AudioScenarios.RenderVehicle(p, 5f, (t, s) => { s.engineOn = true; s.rpm = 1700f; s.throttle = 0f; s.load = 0f; s.speed = 0.5f; s.exhaustBrakeOk = false; }, SR, 3, 512, false);
            var brake = AudioScenarios.RenderVehicle(p, 5f, (t, s) => { s.engineOn = true; s.rpm = 1700f; s.throttle = 0f; s.load = 0f; s.speed = 9f; s.exhaustBrakeOk = true; }, SR, 3, 512, false);
            var a = AudioAnalysis.Analyze(noBrake, SR * 2, SR * 3, SR); var b = AudioAnalysis.Analyze(brake, SR * 2, SR * 3, SR);
            Log("exhaust brake: " + a.rmsDb.ToString("F1") + " -> " + b.rmsDb.ToString("F1") + " dBFS");
            Assert.Greater(b.rmsDb, a.rmsDb + 3f);
        }

        // ------------------------------------------------------------------ ground / water / suspension / winch

        static float[] Ground(Action<VehicleSignals> set, float seconds = 4f, float speed = 5f)
        {
            return AudioScenarios.RenderVehicle(EngineProfile.Utility(), seconds, (t, s) => { s.hasEngine = false; s.engineOn = false; s.speed = speed; s.wheelRev = speed / 3.4f; set(s); }, SR, 21, 512, true);
        }

        static float Band(float[] x, float f1, float f2) { return AudioAnalysis.BandRms(x, SR / 2, x.Length - SR / 2, SR, f1, f2); }

        [Test]
        public void Mud_IsLowMidAndIrregular_AndGrowsWithSlip()
        {
            var roll = Ground(s => { s.mudRoll = 0.5f; s.suction = 0.25f; s.wetness = 0.5f; });
            var spin = Ground(s => { s.mudRoll = 0.5f; s.mudSlip = 0.9f; s.suction = 0.8f; s.wetness = 0.7f; }, 5f, 1.5f);
            var sr = AudioAnalysis.Analyze(roll, SR / 2, roll.Length - SR / 2, SR); var ss = AudioAnalysis.Analyze(spin, SR / 2, spin.Length - SR / 2, SR);
            Log("mud roll " + sr.rmsDb.ToString("F1") + " dB cent " + sr.centroidHz.ToString("F0") + " | spin " + ss.rmsDb.ToString("F1") + " dB cent " + ss.centroidHz.ToString("F0"));
            Assert.Greater(ss.rmsDb, sr.rmsDb + 4f, "wheelspin squelch is much louder than rolling");
            Assert.Greater(Band(spin, 120f, 1200f), 3f * Band(spin, 4000f, 12000f), "squelch energy is low-mid, not hiss");
            Assert.Less(ss.centroidHz, 1500f);
            Assert.Greater(Cv(spin, SR), 0.18f, "squelch is bursty (non-stationary)");
        }

        [Test]
        public void Surfaces_HaveTheirSpectralCharacter()
        {
            var mud = Ground(s => { s.mudRoll = 0.6f; s.suction = 0.3f; });
            var gravel = Ground(s => s.gravel = 0.7f, 4f, 9f);
            var grass = Ground(s => s.grass = 0.7f, 4f, 7f);
            var hard = Ground(s => s.hard = 0.7f, 4f, 10f);
            float cm = AudioAnalysis.Analyze(mud, SR / 2, mud.Length - SR / 2, SR).centroidHz;
            float cg = AudioAnalysis.Analyze(gravel, SR / 2, gravel.Length - SR / 2, SR).centroidHz;
            float cs = AudioAnalysis.Analyze(grass, SR / 2, grass.Length - SR / 2, SR).centroidHz;
            float ch = AudioAnalysis.Analyze(hard, SR / 2, hard.Length - SR / 2, SR).centroidHz;
            Log(string.Format("centroids mud {0:F0} hard {1:F0} grass {2:F0} gravel {3:F0} Hz", cm, ch, cs, cg));
            Assert.Less(cm, ch); Assert.Less(ch, cs); Assert.Less(cs, cg + 400f);
            Assert.Greater(cg, 2500f, "gravel crunch is bright");
            // gravel is impulsive (grains), mud is not as peaky relative to rms
            float crestG = AudioAnalysis.Analyze(gravel, SR / 2, gravel.Length - SR / 2, SR).crest;
            Assert.Greater(crestG, 5f);
        }

        [Test]
        public void Water_WadingIsBroadbandAndSplashesAreWellFormed()
        {
            var wade = AudioScenarios.Render("wading", SR).left;
            var st = AudioAnalysis.Analyze(wade, SR / 2, wade.Length - SR / 2, SR);
            Assert.Greater(st.centroidHz, 1500f, "water wash is bright compared to mud");
            Assert.Greater(Cv(wade, SR), 0.1f);
            var bank = AudioScenarios.Bank(SR);
            for (int v = 0; v < 3; v++)
            {
                var big = bank.Get(Sfx.WaterSplashBig, v); var small = bank.Get(Sfx.WaterSplashSmall, v);
                Assert.Greater(big.Length, small.Length, "big splash lasts longer");
                // tail energy must have decayed: last 100 ms vs first 100 ms
                var head = AudioAnalysis.Analyze(big, 0, SR / 10, SR); var tail = AudioAnalysis.Analyze(big, big.Length - SR / 10, SR / 10, SR);
                Assert.Less(tail.rms, head.rms * 0.15f, "splash decays");
            }
        }

        [Test]
        public void Creak_IsResonantBandLimitedAndIntermittent()
        {
            var cr = AudioScenarios.Render("creak", SR).left;
            var st = AudioAnalysis.Analyze(cr, SR / 2, cr.Length - SR / 2, SR);
            Log("creak " + st);
            Assert.Greater(Band(cr, 250f, 2000f), 4f * Band(cr, 5000f, 15000f), "creak lives in the body-mode band");
            Assert.Greater(Cv(cr, SR), 0.5f, "groans come and go");
            var quiet = Ground(s => { s.creak = 0f; });
            Assert.Less(AudioAnalysis.Analyze(quiet, SR / 2, quiet.Length - SR / 2, SR).rms, 1e-4f, "no creak without articulation");
        }

        [Test]
        public void Winch_WhinePitchDropsWithLoad()
        {
            float Pitch(float load)
            {
                var x = AudioScenarios.RenderVehicle(EngineProfile.Utility(), 3f, (t, s) => { s.hasEngine = false; s.engineOn = false; s.winchMotor = 1f; s.winchLoad = load; s.winchDir = 1f; }, SR, 3, 512, false);
                int fft = 32768; var psd = AudioAnalysis.PowerSpectrum(x, SR, SR * 2 - 1, fft);
                return AudioAnalysis.PeakFrequency(psd, fft, SR, 300f, 1200f, out _);
            }
            float light = Pitch(0.05f), heavy = Pitch(0.95f);
            Log("winch whine " + light.ToString("F0") + " Hz (light) -> " + heavy.ToString("F0") + " Hz (heavy)");
            Assert.Less(heavy, light * 0.88f);
            // rope tension creak only when loaded
            var slack = AudioScenarios.RenderVehicle(EngineProfile.Utility(), 3f, (t, s) => { s.hasEngine = false; s.engineOn = false; s.winchMotor = 0f; s.winchLoad = 0.02f; }, SR, 3, 512, false);
            var taut = AudioScenarios.RenderVehicle(EngineProfile.Utility(), 3f, (t, s) => { s.hasEngine = false; s.engineOn = false; s.winchMotor = 0f; s.winchLoad = 0.9f; }, SR, 3, 512, false);
            Assert.Greater(AudioAnalysis.Analyze(taut, SR, SR * 2 - 1, SR).rms, 5f * AudioAnalysis.Analyze(slack, SR, SR * 2 - 1, SR).rms + 1e-6f);
        }

        // ------------------------------------------------------------------ weather / ambience

        [Test]
        public void Rain_ScalesWithIntensity_AndIsBrighterThanWind()
        {
            float L(float rain)
            {
                AudioScenarios.RenderAmbience(4f, (t, p) => { p.rain = rain; }, out var l, out var r, SR);
                return AudioAnalysis.Analyze(l, SR, l.Length - SR, SR).rmsDb;
            }
            float a = L(0.2f), b = L(0.5f), c = L(0.9f);
            Log("rain rms " + a.ToString("F1") + " / " + b.ToString("F1") + " / " + c.ToString("F1") + " dBFS");
            Assert.Greater(b, a + 2f); Assert.Greater(c, b + 2f);
            AudioScenarios.RenderAmbience(6f, (t, p) => { p.rain = 0.7f; }, out var rl, out _, SR);
            AudioScenarios.RenderAmbience(6f, (t, p) => { p.wind = 0.7f; }, out var wl, out _, SR);
            float cr = AudioAnalysis.Analyze(rl, SR, rl.Length - SR, SR).centroidHz, cw = AudioAnalysis.Analyze(wl, SR, wl.Length - SR, SR).centroidHz;
            Log("centroids rain " + cr.ToString("F0") + " wind " + cw.ToString("F0") + " Hz");
            Assert.Greater(cr, cw * 3f);
            // roof drumming adds a mid-band component in cockpit mode
            AudioScenarios.RenderAmbience(6f, (t, p) => { p.rain = 0.6f; }, out var open, out _, SR);
            AudioScenarios.RenderAmbience(6f, (t, p) => { p.rain = 0.6f; p.roof = 1f; p.cabin = 0f; }, out var roof, out _, SR);
            Assert.Greater(AudioAnalysis.BandRms(roof, SR, roof.Length - SR, SR, 700f, 3000f), AudioAnalysis.BandRms(open, SR, open.Length - SR, SR, 700f, 3000f) * 1.2f);
        }

        [Test]
        public void Wind_GustsAndGrowsWithSpeed()
        {
            AudioScenarios.RenderAmbience(12f, (t, p) => { p.wind = 0.6f; }, out var l, out var r, SR);
            Assert.Greater(Cv(l, SR), 0.2f, "wind gusts");
            AudioScenarios.RenderAmbience(4f, (t, p) => { p.speedWind = 0.2f; }, out var slow, out _, SR);
            AudioScenarios.RenderAmbience(4f, (t, p) => { p.speedWind = 0.8f; }, out var fast, out _, SR);
            Assert.Greater(AudioAnalysis.Analyze(fast, SR, fast.Length - SR, SR).rmsDb, AudioAnalysis.Analyze(slow, SR, slow.Length - SR, SR).rmsDb + 6f);
            // stereo: channels are decorrelated (independent noise per ear)
            double dot = 0, ll = 0, rr = 0;
            for (int i = SR; i < l.Length; i++) { dot += l[i] * r[i]; ll += l[i] * l[i]; rr += r[i] * r[i]; }
            Assert.Less(Math.Abs(dot / Math.Sqrt(ll * rr)), 0.5, "wind stereo decorrelated");
        }

        [Test]
        public void Ambience_DayBirds_NightInsectsAndFrogs()
        {
            AudioScenarios.RenderAmbience(20f, (t, p) => { p.day = 1f; p.forest = 0.9f; }, out var day, out _, SR);
            AudioScenarios.RenderAmbience(20f, (t, p) => { p.night = 1f; p.swamp = 0.9f; p.forest = 0.4f; }, out var night, out _, SR);
            AudioScenarios.RenderAmbience(10f, (t, p) => { p.day = 0f; p.night = 0f; }, out var none, out _, SR);
            AudioScenarios.RenderAmbience(12f, (t, p) => { p.night = 0.04f; p.swamp = 0.9f; }, out var dusk, out _, SR);
            float dayBirds = AudioAnalysis.BandRms(day, SR, day.Length - SR, SR, 1800f, 6500f);
            float crickets = AudioAnalysis.BandRms(night, SR, night.Length - SR, SR, 3700f, 5500f);
            float totalNight = AudioAnalysis.Analyze(night, SR, night.Length - SR, SR).rms;
            float frogs = AudioAnalysis.BandRms(night, SR, night.Length - SR, SR, 300f, 2500f);
            Log(string.Format("birds(day) {0:E1} crickets-band(night) {1:E1} of total {2:E1}, frogs-band(night) {3:E1}, dusk rms {4:E1}, no-drive rms {5:E1}", dayBirds, crickets, totalNight, frogs,
                AudioAnalysis.Analyze(dusk, SR, dusk.Length - SR, SR).rms, AudioAnalysis.Analyze(none, SR, none.Length - SR, SR).rms));
            Assert.Greater(dayBirds, 3e-3f, "daytime forest has bird song");
            Assert.Greater(crickets, 5e-3f, "crickets chirp at night");
            Assert.Greater(crickets, 0.5f * totalNight, "the night bed is dominated by the 4-5 kHz insect band");
            Assert.Greater(frogs, 1e-3f, "swamp night has frogs");
            Assert.Less(AudioAnalysis.Analyze(dusk, SR, dusk.Length - SR, SR).rms, 1e-4f, "below the darkness threshold the insects and frogs stay silent");
            Assert.Less(AudioAnalysis.Analyze(none, SR, none.Length - SR, SR).rms, 1e-4f, "no ambience without drive values");
            // bird phrases are tonal chirps: strongest line well above the neighbouring noise
            int fft = 8192; var psd = AudioAnalysis.PowerSpectrum(day, SR, SR * 3, fft);
            float peak = AudioAnalysis.PeakFrequency(psd, fft, SR, 1500f, 7000f, out float pp);
            Assert.Greater(peak, 1500f);
        }

        [Test]
        public void River_FastIsLouderAndBrighterThanStill()
        {
            var fast = AudioScenarios.RenderRiver(5f, 1f, 2.5f, SR); var still = AudioScenarios.RenderRiver(5f, 1f, 0.05f, SR);
            var a = AudioAnalysis.Analyze(fast, SR, fast.Length - SR, SR); var b = AudioAnalysis.Analyze(still, SR, still.Length - SR, SR);
            Assert.Greater(a.rmsDb, b.rmsDb + 10f); Assert.Greater(a.centroidHz, b.centroidHz * 2f);
            var away = AudioScenarios.RenderRiver(4f, 0f, 2.5f, SR);
            Assert.Less(AudioAnalysis.Analyze(away, SR, away.Length - SR, SR).rms, 1e-4f, "silent when no water is near");
        }

        // ------------------------------------------------------------------ one-shot bank

        [Test]
        public void SfxBank_AllClipsAreValid()
        {
            var bank = AudioScenarios.Bank(SR);
            var sb = new StringBuilder();
            for (int i = 0; i < (int)Sfx.Count; i++)
            {
                var id = (Sfx)i;
                Assert.GreaterOrEqual(bank.VariantCount(id), 1);
                for (int v = 0; v < bank.VariantCount(id); v++)
                {
                    var c = bank.Get(id, v);
                    var st = AudioAnalysis.Analyze(c, SR);
                    Assert.AreEqual(0, st.badCount, id + " NaN/Inf");
                    Assert.LessOrEqual(st.peak, 0.95f, id + " peak"); Assert.Greater(st.peak, 0.2f, id + " not silent");
                    Assert.Less(Mathf.Abs(st.dc), 0.01f, id + " dc");
                    Assert.Greater(c.Length, SR / 25, id + " length"); Assert.Less(c.Length, SR * 2, id + " not too long");
                    var tail = AudioAnalysis.Analyze(c, c.Length - SR / 50, SR / 50, SR);
                    Assert.Less(tail.peak, 0.05f, id + " ends quietly (no click)");
                    if (v == 0) sb.Append(id).Append(' ').Append((c.Length / (float)SR).ToString("F2")).Append("s pk").Append(st.peak.ToString("F2")).Append(" c").Append(st.centroidHz.ToString("F0")).Append(" | ");
                }
            }
            Log("bank: " + sb);
        }

        [Test]
        public void Impacts_MetalHasRingWoodIsDuller_MudSplashIsLowerThanWater()
        {
            var bank = AudioScenarios.Bank(SR);
            float cMetal = AudioAnalysis.Analyze(bank.Get(Sfx.MetalThud, 0), SR).centroidHz, cWood = AudioAnalysis.Analyze(bank.Get(Sfx.WoodThunk, 0), SR).centroidHz;
            float cMud = AudioAnalysis.Analyze(bank.Get(Sfx.MudSplashBig, 0), SR).centroidHz, cWater = AudioAnalysis.Analyze(bank.Get(Sfx.WaterSplashBig, 0), SR).centroidHz;
            Log(string.Format("centroids metal {0:F0} wood {1:F0} mud splash {2:F0} water splash {3:F0}", cMetal, cWood, cMud, cWater));
            Assert.Greater(cMetal, cWood); Assert.Greater(cWater, cMud * 2f);
        }

        // ------------------------------------------------------------------ whole-pipeline checks

        [Test]
        public void AllScenarios_PassSanity()
        {
            var failures = new List<string>(); var sb = new StringBuilder();
            foreach (var name in AudioScenarios.Names())
            {
                var rep = AudioVerification.RunScenario(name, SR, out _);
                sb.Append(string.Format("{0}: peak {1:F2} rms {2:F1}dB dc {3:E0} cent {4:F0} | ", name, rep.stats.peak, rep.stats.rmsDb, rep.stats.dc, rep.stats.centroidHz));
                if (!rep.pass) failures.Add(name + ": " + rep.issue);
            }
            Log(sb.ToString());
            Assert.IsEmpty(failures, string.Join("; ", failures));
        }

        [Test]
        public void Levels_EngineAboveTyresAboveAmbience()
        {
            AudioScenarios.ReferenceLevels(SR, out float e, out float t, out float a);
            float ed = DspMath.LinToDb(e), td = DspMath.LinToDb(t), ad = DspMath.LinToDb(a);
            Log(string.Format("levels engine {0:F1} dBFS > tyres {1:F1} dBFS > ambience {2:F1} dBFS", ed, td, ad));
            Assert.Greater(ed, td + 1f); Assert.Greater(td, ad + 2f);
        }

        [Test]
        public void Synth_NoNaNOrClipping_UnderExtremeSignals([ValueSource(nameof(Keys))] string key)
        {
            var p = EngineProfile.ForKey(key);
            var sig = new VehicleSignals();
            var syn = new VehicleSynth(p, SR, sig, AudioScenarios.Bank(SR), 3);
            var rng = new Rng(99);
            var buf = new float[512];
            int bad = 0; float peak = 0f;
            for (int blk = 0; blk < 800; blk++)
            {
                sig.engineOn = rng.Next01() > 0.1f; sig.rpm = rng.Range(0f, p.redlineRpm * 1.4f); sig.throttle = rng.Next01(); sig.load = rng.Next01(); sig.strain = rng.Next01(); sig.flood = rng.Next01() > 0.8f ? 1f : 0f;
                sig.speed = rng.Range(0f, 40f); sig.brake = rng.Next01(); sig.exhaustBrakeOk = rng.Next01() > 0.5f;
                sig.mudRoll = rng.Next01(); sig.mudSlip = rng.Next01(); sig.suction = rng.Next01(); sig.gravel = rng.Next01(); sig.grass = rng.Next01(); sig.hard = rng.Next01(); sig.sand = rng.Next01(); sig.skid = rng.Next01(); sig.belly = rng.Next01();
                sig.wheelRev = rng.Range(0f, 20f); sig.creak = rng.Next01(); sig.creakSpeed = rng.Next01(); sig.wading = rng.Next01(); sig.waterFlow = rng.Range(0f, 4f);
                sig.winchMotor = rng.Next01() > 0.5f ? 1f : 0f; sig.winchLoad = rng.Next01(); sig.doppler = rng.Range(0.8f, 1.25f); sig.distance01 = rng.Next01(); sig.cabin = rng.Next01();
                if (rng.Next01() > 0.97f) sig.startCount++; if (rng.Next01() > 0.99f) sig.stallCount++; if (rng.Next01() > 0.99f) sig.failCount++;
                if (rng.Next01() > 0.8f) sig.PushSfx((Sfx)rng.Int((int)Sfx.Count), rng.Next01() * 2f, rng.Range(0.5f, 2f));
                syn.Render(buf, 0, buf.Length);
                for (int i = 0; i < buf.Length; i++) { float v = buf[i]; if (float.IsNaN(v) || float.IsInfinity(v)) bad++; peak = Mathf.Max(peak, Mathf.Abs(v)); }
            }
            Assert.AreEqual(0, bad, "NaN/Inf");
            Assert.LessOrEqual(peak, 1.0f, "soft limiter keeps |x| <= 1");
            var amb = new AmbienceSynth(SR, 3); var ap = new AmbienceParams();
            var l = new float[512]; var r = new float[512];
            for (int blk = 0; blk < 600; blk++)
            {
                ap.rain = rng.Next01(); ap.wind = rng.Next01(); ap.speedWind = rng.Next01(); ap.roof = rng.Next01(); ap.day = rng.Next01(); ap.night = rng.Next01(); ap.forest = rng.Next01(); ap.swamp = rng.Next01(); ap.cabin = rng.Next01(); ap.wetGround = rng.Next01();
                amb.Render(ap, l, r, 0, 512);
                for (int i = 0; i < 512; i++) { Assert.IsFalse(float.IsNaN(l[i]) || float.IsInfinity(l[i]) || float.IsNaN(r[i]) || float.IsInfinity(r[i])); Assert.LessOrEqual(Mathf.Abs(l[i]), 1f); }
            }
        }

        [Test]
        public void Synth_RenderDoesNotAllocate()
        {
            var sig = new VehicleSignals { engineOn = true, rpm = 2000, throttle = 0.6f, load = 0.6f, speed = 6f, wheelRev = 2f, mudRoll = 0.5f, mudSlip = 0.4f, suction = 0.4f, gravel = 0.2f, grass = 0.2f, creak = 0.5f, creakSpeed = 0.4f, wading = 0.4f, winchMotor = 1f, winchLoad = 0.5f };
            var syn = new VehicleSynth(EngineProfile.Hauler(), SR, sig, AudioScenarios.Bank(SR), 1);
            var amb = new AmbienceSynth(SR, 1); var ap = new AmbienceParams { rain = 0.6f, wind = 0.5f, day = 1f, night = 0.5f, forest = 0.6f, swamp = 0.5f };
            var buf = new float[1024]; var l = new float[1024]; var r = new float[1024];
            for (int i = 0; i < 60; i++) { syn.Render(buf, 0, 1024); amb.Render(ap, l, r, 0, 1024); }     // warm up (JIT, lazy statics)
            long before = AllocBytes();
            long monoBefore = UnityEngine.Profiling.Profiler.GetMonoUsedSizeLong();
            int gcBefore = GC.CollectionCount(0);
            for (int i = 0; i < 400; i++)
            {
                if (i % 20 == 0) sig.PushSfx(Sfx.MetalThud, 0.5f);
                syn.Render(buf, 0, 1024); amb.Render(ap, l, r, 0, 1024);
            }
            long after = AllocBytes();
            long monoAfter = UnityEngine.Profiling.Profiler.GetMonoUsedSizeLong();
            int gcs = GC.CollectionCount(0) - gcBefore;
            Log("allocation check: GetAllocatedBytes delta " + (after - before) + " B, mono heap delta " + (monoAfter - monoBefore) + " B, gen0 collections " + gcs + " over 400 callbacks");
            Assert.AreEqual(0, gcs, "no GC collections while rendering");
            Assert.LessOrEqual(monoAfter - monoBefore, 16384, "no managed allocation in the render path");
            if (before > 0) Assert.LessOrEqual(after - before, 16384, "no managed allocation in the render path (thread counter)");
        }

        static long AllocBytes()
        {
            try { return GC.GetAllocatedBytesForCurrentThread(); } catch { return -1; }
        }

        [Test]
        public void Cpu_ThreeVehiclesFitTheAudioCallbackBudget()
        {
            var c = AudioVerification.MeasureCpu(3, 1024, 300, SR, 5);
            Log(string.Format("cpu per 1024-frame callback (editor Mono JIT): 3 vehicles driving in mud median {0:F3} ms p95 {1:F3} ms | every layer of every vehicle on: median {2:F3} ms p95 {3:F3} ms | ambience worst case + river {4:F3} ms (budget 1.5 ms)",
                c.typicalMedian, c.typicalP95, c.extremeMedian, c.extremeP95, c.ambienceMedian));
            Assert.Less(c.typicalMedian, 1.5, "median callback time for three vehicles driving in mud");
            Assert.Less(c.extremeMedian, 3.0, "even with every layer of every vehicle on the callback stays far below the 21 ms buffer");
            Assert.Less(c.ambienceMedian, 1.0, "ambience + river worst case");
        }

        // ------------------------------------------------------------------ engine profile bookkeeping

        [Test]
        public void Profiles_FitTheVehicleDefinitions()
        {
            var sc = VehicleDefinition.CreateScout(); var ut = VehicleDefinition.CreateUtility(); var ha = VehicleDefinition.CreateHauler();
            var ps = EngineProfile.ForVehicle(sc.name, sc.mass, sc.idleRpm, sc.redlineRpm, sc.stallRpm);
            var pu = EngineProfile.ForVehicle(ut.name, ut.mass, ut.idleRpm, ut.redlineRpm, ut.stallRpm);
            var ph = EngineProfile.ForVehicle(ha.name, ha.mass, ha.idleRpm, ha.redlineRpm, ha.stallRpm);
            Assert.AreEqual("scout", ps.name); Assert.AreEqual(4, ps.cylinders);
            Assert.AreEqual("utility", pu.name); Assert.AreEqual(8, pu.cylinders);
            Assert.AreEqual("hauler", ph.name); Assert.AreEqual(6, ph.cylinders); Assert.IsTrue(ph.exhaustBrake);
            Assert.AreEqual(sc.redlineRpm, ps.redlineRpm); Assert.AreEqual(ha.idleRpm, ph.idleRpm);
            Assert.AreEqual(rpmHz(ut.idleRpm, 8), pu.FiringHz(ut.idleRpm), 0.01f);
            UnityEngine.Object.DestroyImmediate(sc); UnityEngine.Object.DestroyImmediate(ut); UnityEngine.Object.DestroyImmediate(ha);
        }

        static float rpmHz(float rpm, int cyl) { return rpm / 60f * cyl / 2f; }

        // ------------------------------------------------------------------ Unity-side integration

        GroundService gs;
        readonly List<GameObject> spawned = new List<GameObject>();

        [TearDown]
        public void TearDown()
        {
            foreach (var go in spawned) if (go != null) UnityEngine.Object.Destroy(go);
            spawned.Clear();
            if (AudioDirector.Instance != null) UnityEngine.Object.DestroyImmediate(AudioDirector.Instance.gameObject);
            if (GroundService.Instance != null) UnityEngine.Object.DestroyImmediate(GroundService.Instance.gameObject);
            AudioListener.volume = 1f;
            Time.captureFramerate = 0;
        }

        Vehicle Spawn(string key, Vector3 pos)
        {
            var d = key == "scout" ? VehicleDefinition.CreateScout() : key == "utility" ? VehicleDefinition.CreateUtility() : VehicleDefinition.CreateHauler();
            var a = d.axles[0];
            pos.y = gs.GroundHeight(pos.x, pos.z) + (a.tire.radius - a.hubY) + 0.06f;
            var v = VehicleFactory.CreatePrimitive(d, pos, Quaternion.identity, withVisuals: false);
            spawned.Add(v.gameObject);
            return v;
        }

        [UnityTest]
        public IEnumerator Director_AttachesVoices_FollowsSignals_AndMasterVolumeWorks()
        {
            Time.captureFramerate = 60;
            gs = TestArena.Install(TestArena.Flat(SurfaceType.ShallowMud), Vector3.zero, 0.5f);
            var scout = Spawn("scout", Vector3.zero);
            var hauler = Spawn("hauler", new Vector3(14f, 0f, 0f));
            var dir = AudioDirector.Install();
            Assert.IsNotNull(dir); Assert.AreSame(dir, AudioDirector.Install(), "Install is idempotent");
            AudioDirector.MasterVolume = 0.37f;
            Assert.AreEqual(0.37f, AudioListener.volume, 1e-4f, "MasterVolume is AudioListener.volume");
            AudioDirector.MasterVolume = 1f;
            Assert.IsNotNull(UnityEngine.Object.FindAnyObjectByType<AudioListener>(), "a listener exists");

            var inp = scout.input; inp.throttle = 1f; scout.input = inp;
            float t0 = Time.time; while (Time.time - t0 < 2.5f) yield return null;

            var ds = dir.GetDriver(scout); var dh = dir.GetDriver(hauler);
            Assert.IsNotNull(ds, "scout got a driver"); Assert.IsNotNull(dh, "hauler got a driver");
            Assert.IsNotNull(ds.voice); Assert.IsNotNull(ds.source); Assert.IsNotNull(ds.voice.synth);
            Assert.AreEqual("scout", ds.profile.name); Assert.AreEqual("hauler", dh.profile.name);
            Assert.Greater(ds.signals.rpm, scout.def.idleRpm * 1.05f, "rpm reaches the synth");
            Assert.Greater(ds.signals.throttle, 0.5f);
            Assert.Greater(ds.signals.mudRoll + ds.signals.mudSlip, 0.02f, "driving in mud drives the squelch");
            Assert.IsTrue(ds.signals.engineOn);
            Assert.Less(dh.signals.rpm, 1200f, "parked hauler idles");
            Assert.IsNotNull(dir.AmbienceVoice); Assert.IsNotNull(dir.RiverVoice);
            Log("director: " + dir.DebugSummary() + " | scout rpm " + ds.signals.rpm.ToString("F0") + " mudRoll " + ds.signals.mudRoll.ToString("F2") + " mudSlip " + ds.signals.mudSlip.ToString("F2") + " suction " + ds.signals.suction.ToString("F2") + " creak " + ds.signals.creak.ToString("F2"));

            // the voice synthesizes real audio from those signals (same path as OnAudioFilterRead, driven manually)
            var buf = new float[4096];
            for (int i = 0; i < 6; i++) ds.synth.Render(buf, 0, buf.Length);
            var st = AudioAnalysis.Analyze(buf, SR);
            Assert.AreEqual(0, st.badCount); Assert.Greater(st.rms, 1e-3f, "audible output");

            // engine key-off then start: counters and events reach the synth
            int starts = ds.signals.startCount;
            scout.drivetrain.engineOn = false; yield return null; yield return null;
            scout.drivetrain.engineOn = true; yield return null; yield return null; yield return null;
            Assert.Greater(ds.signals.startCount, starts, "restart detected (starter cranking)");

            // impact classification
            var rock = new GameObject("BigRock"); rock.layer = GameLayers.Props; var bc = rock.AddComponent<BoxCollider>(); spawned.Add(rock);
            Assert.AreEqual(Sfx.RockThud, VehicleAudioDriver.ClassifyImpact(bc, 0.5f));
            var log = new GameObject("LogPile"); log.layer = GameLayers.DynamicProps; var bc2 = log.AddComponent<BoxCollider>(); spawned.Add(log);
            Assert.AreEqual(Sfx.WoodThunk, VehicleAudioDriver.ClassifyImpact(bc2, 0.5f));
            var other = new GameObject("Wall"); other.layer = GameLayers.Props; var bc3 = other.AddComponent<BoxCollider>(); spawned.Add(other);
            Assert.AreEqual(Sfx.MetalThud, VehicleAudioDriver.ClassifyImpact(bc3, 0.2f));

            // far / unused voices are paused, destroying a vehicle removes its driver
            UnityEngine.Object.Destroy(hauler.gameObject);
            float t1 = Time.time; while (Time.time - t1 < 0.8f) yield return null;
            Assert.IsNull(dir.GetDriver(hauler));
        }

        [UnityTest]
        public IEnumerator Director_AutoInstallsOnlyWhenAllowed_AndIsDormantWithoutGameManager()
        {
            if (AudioDirector.Instance != null) UnityEngine.Object.DestroyImmediate(AudioDirector.Instance.gameObject);    // an interactive editor run may have auto-created one
            Assert.IsNull(AudioDirector.Instance);
            var go = new GameObject("TestDirector");
            spawned.Add(go);
            var d = go.AddComponent<AudioDirector>();
            d.dormant = true;
            yield return null; yield return null;
            Assert.IsFalse(d.Activated, "stays dormant until a GameManager exists");
            var gmGo = new GameObject("GameManager"); var gm = gmGo.AddComponent<GameManager>(); spawned.Add(gmGo);
            yield return null; yield return null;
            Assert.IsTrue(d.Activated, "activates once the GameManager exists");
            Assert.IsNotNull(d.AmbienceVoice);
            // UI sounds before the bank exists must not throw
            AudioDirector.PlayUi(Sfx.UiNotify); AudioDirector.Notify(); AudioDirector.Warn();
            float t0 = Time.realtimeSinceStartup; while (d.Bank == null && Time.realtimeSinceStartup - t0 < 15f) yield return null;
            Assert.IsNotNull(d.Bank, "one-shot bank is rendered on a worker thread");
            AudioDirector.PlayUi(Sfx.UiNotify); AudioDirector.PlayAt(Sfx.MetalThud, Vector3.up, 0.5f);
            yield return null;
        }
    }
}
