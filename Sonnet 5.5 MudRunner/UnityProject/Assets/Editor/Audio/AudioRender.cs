using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using MudRunner.Audio.Dsp;
using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Offline audio verification: renders every voice type through the real synthesizers (no audio device needed), writes
    /// Captures/audio_*.wav and prints numerical sanity statistics (peak, RMS, DC, spectral centroid, NaN/Inf, clipping) plus
    /// the engine firing-frequency check, timbre separation, level ordering and the CPU cost of the real-time voices.
    ///   Tools/ub.sh audio MudRunner.EditorTools.AudioRender.Run
    /// </summary>
    public static class AudioRender
    {
        const int SampleRate = 48000;

        [MenuItem("MudRunner/Audio/Render Audio Captures")]
        public static void MenuRun() { Run(); }

        /// <summary>Batch entry point. Exit code 1 when any check failed.</summary>
        public static void Run()
        {
            int failures = RunAll(true);
            if (Application.isBatchMode) EditorApplication.Exit(failures > 0 ? 1 : 0);
        }

        /// <summary>Renders everything; returns the number of failed checks.</summary>
        public static int RunAll(bool writeWav)
        {
            int failures = 0;
            string dir = Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Captures");
            Directory.CreateDirectory(dir);
            var all = new StringBuilder();

            // ---------------------------------------------------------------- every scenario
            Log("== scenarios (48 kHz, stats skip the first 0.25 s)");
            foreach (var name in AudioScenarios.Names())
            {
                var rep = AudioVerification.RunScenario(name, SampleRate, out var audio);
                var st = rep.stats;
                string line = string.Format("AUDIO {0,-28} {1,5:F1}s render {2,5:F0}ms | peak {3:F3} rms {4,6:F1} dBFS dc {5,9:E1} centroid {6,5:F0} Hz rolloff85 {7,5:F0} Hz crest {8,4:F1} cv {9:F2} nan/inf {10} clip {11} | {12}",
                    name, rep.seconds, rep.renderMs, st.peak, st.rmsDb, st.dc, st.centroidHz, st.rolloff85Hz, st.crest, rep.envCv, st.badCount, st.clipCount, rep.pass ? "OK" : "FAIL: " + rep.issue);
                Log(line);
                if (!rep.pass) failures++;
                if (writeWav) WavFile.Write(Path.Combine(dir, "audio_" + name + ".wav"), audio.left, audio.right, SampleRate);
            }

            // ---------------------------------------------------------------- engine firing frequency
            Log("== engine fundamental = rpm/60*cylinders/2 (strongest partial near f0, harmonic series above the noise floor)");
            foreach (var p in new[] { EngineProfile.Scout(), EngineProfile.Utility(), EngineProfile.Hauler() })
            {
                foreach (float mult in new[] { 1.5f, 3.0f, 4.6f })
                {
                    float rpm = Mathf.Min(p.idleRpm * mult, p.redlineRpm * 0.9f);
                    var r = AudioVerification.MeasureEngine(p, rpm, 0.4f, 0.4f, SampleRate);
                    Log(string.Format("AUDIO ENGINE {0,-8} {1,2}cyl rpm {2,5:F0} f0 {3,6:F1} Hz  peak@ {4,6:F1} Hz | fundamental {5,6:F1} h2 {6,6:F1} h3 {7,6:F1} floor {8,6:F1} dB | centroid {9,5:F0} Hz rms {10,5:F1} dBFS | {11}",
                        r.engine, p.cylinders, r.rpm, r.f0, r.peakNear, r.dbFund, r.dbH2, r.dbH3, r.floorDb, r.centroid, r.rmsDb, r.pass ? "PASS" : "FAIL"));
                    if (!r.pass) failures++;
                }
            }

            // ---------------------------------------------------------------- timbre distinctness
            var names = new[] { "scout", "utility", "hauler" };
            var fps = new List<float[]>();
            var cents = new List<float>();
            foreach (var n in names)
            {
                var p = EngineProfile.ForKey(n);
                float rpm = p.idleRpm + (p.redlineRpm - p.idleRpm) * 0.4f;
                var x = AudioScenarios.RenderVehicle(p, 4f, AudioScenarios.Steady(rpm, 0.5f, 0.5f), SampleRate, 3, 512, false);
                fps.Add(AudioVerification.OctaveFingerprint(x, SampleRate / 2, x.Length - SampleRate / 2, SampleRate));
                cents.Add(AudioAnalysis.Analyze(x, SampleRate / 2, x.Length - SampleRate / 2, SampleRate).centroidHz);
            }
            Log(string.Format("AUDIO TIMBRE octave-fingerprint distance scout/utility {0:F1} dB, scout/hauler {1:F1} dB, utility/hauler {2:F1} dB; centroids {3:F0}/{4:F0}/{5:F0} Hz",
                AudioVerification.FingerprintDistance(fps[0], fps[1]), AudioVerification.FingerprintDistance(fps[0], fps[2]), AudioVerification.FingerprintDistance(fps[1], fps[2]), cents[0], cents[1], cents[2]));

            // ---------------------------------------------------------------- level ordering
            AudioScenarios.ReferenceLevels(SampleRate, out float e, out float t, out float a);
            float ed = DspMath.LinToDb(e), td = DspMath.LinToDb(t), ad = DspMath.LinToDb(a);
            bool order = ed > td && td > ad;
            Log(string.Format("AUDIO LEVELS engine {0:F1} dBFS > tyres {1:F1} dBFS > ambience {2:F1} dBFS : {3}", ed, td, ad, order ? "PASS" : "FAIL"));
            if (!order) failures++;

            // ---------------------------------------------------------------- CPU
            var cpu = AudioVerification.MeasureCpu(3, 1024, 400, SampleRate);
            bool cpuOk = cpu.typicalMedian < 1.5 && cpu.ambienceMedian < 1.0;
            Log(string.Format("AUDIO CPU per 1024-frame callback (editor Mono JIT, budget 1.5 ms): 3 vehicles driving in mud median {0:F3} ms p95 {1:F3} ms | every layer of every vehicle on median {2:F3} ms p95 {3:F3} ms | ambience worst case + river {4:F3} ms : {5}",
                cpu.typicalMedian, cpu.typicalP95, cpu.extremeMedian, cpu.extremeP95, cpu.ambienceMedian, cpuOk ? "PASS" : "FAIL"));
            if (!cpuOk) failures++;

            Log("AUDIO SUMMARY failures=" + failures + (writeWav ? " wav files in " + dir : ""));
            return failures;
        }

        static void Log(string s) { Debug.Log("[MudRunner] " + s); }
    }
}
