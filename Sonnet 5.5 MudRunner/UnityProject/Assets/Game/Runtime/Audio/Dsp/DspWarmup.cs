using System;

namespace MudRunner.Audio.Dsp
{
    /// <summary>
    /// Keeps first-use costs off the audio thread: static lookup tables are built on the calling (main) thread, and
    /// <see cref="JitWarm"/> exercises every synth path on throw-away instances so the Mono JIT has compiled all of it before
    /// the first real audio callback (a lazily compiled 500-line method would otherwise glitch the first buffers).
    /// </summary>
    public static class DspWarmup
    {
        /// <summary>Force the static tables (sine, noise, harmonic wavetables) to be built now.</summary>
        public static void Touch()
        {
            if (SinTable.t.Length == 0 || NoiseTable.Data.Length == 0 || HarmonicTables.Hum.Length == 0 || HarmonicTables.Whine.Length == 0
                || HarmonicTables.Turbo.Length == 0 || HarmonicTables.Starter.Length == 0 || HarmonicTables.Tread.Length == 0)
                throw new InvalidOperationException("DSP tables failed to initialise");
        }

        /// <summary>Run all voices through a short scripted workout (safe on any thread; allocates, so never call it from the audio callback).</summary>
        public static void JitWarm(int sampleRate)
        {
            Touch();
            var bank = SfxBank.Tiny(sampleRate);
            var buf = new float[256];
            foreach (var prof in new[] { EngineProfile.Hauler(), EngineProfile.Scout(), EngineProfile.Utility() })
            {
                var sig = new VehicleSignals();
                var syn = new VehicleSynth(prof, sampleRate, sig, bank, 7);
                for (int b = 0; b < 24; b++)
                {
                    sig.engineOn = b != 10 && b != 11; sig.rpm = prof.idleRpm * (1.2f + 0.05f * b); sig.throttle = (b & 4) != 0 ? 0f : 1f; sig.load = 0.8f; sig.strain = 0.5f;
                    sig.flood = b > 18 ? 0.8f : 0f; sig.speed = 6f; sig.exhaustBrakeOk = true; sig.doppler = 1.05f; sig.distance01 = b > 20 ? 0.7f : 0.1f; sig.cabin = b > 16 ? 0.6f : 0f;
                    sig.mudRoll = 0.6f; sig.mudSlip = 0.5f; sig.suction = 0.5f; sig.gravel = 0.5f; sig.grass = 0.4f; sig.hard = 0.4f; sig.sand = 0.4f; sig.skid = 0.4f; sig.belly = 0.4f;
                    sig.wheelRev = 2f; sig.wetness = 0.5f; sig.creak = 0.7f; sig.creakSpeed = 0.5f; sig.wading = 0.6f; sig.waterFlow = 1f;
                    sig.winchMotor = 1f; sig.winchLoad = 0.7f;
                    if (b == 2) sig.startCount++;
                    if (b == 9) sig.stallCount++;
                    if (b == 14) sig.failCount++;
                    for (int k = 0; k < (int)Sfx.Count; k += 5) sig.PushSfx((Sfx)k, 0.5f, 1f, 0);
                    syn.Render(buf, 0, buf.Length);
                }
            }
            var amb = new AmbienceSynth(sampleRate, 3u);
            var ap = new AmbienceParams { wind = 0.6f, speedWind = 0.3f, rain = 0.7f, roof = 0.6f, wetGround = 0.7f, day = 1f, night = 1f, forest = 0.8f, swamp = 0.8f, cabin = 0.5f };
            var l = new float[256]; var r = new float[256];
            for (int b = 0; b < 140; b++) amb.Render(ap, l, r, 0, 256);           // long enough for birds / crickets / frogs to start phrases
            var river = new RiverSynth(sampleRate);
            for (int b = 0; b < 8; b++) river.Render(0.8f, 1.5f, buf, 0, 256);
        }
    }
}
