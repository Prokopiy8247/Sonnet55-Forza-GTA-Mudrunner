using System;

namespace MudRunner.Audio.Dsp
{
    /// <summary>
    /// One vehicle's complete mono voice: engine, tyres/ground, suspension creak, wading water, winch hardware and a small
    /// one-shot sample player (impacts, splashes, shifts), mixed with per-bus gains, distance/cabin low-pass and a soft limiter.
    /// Pure DSP: render it from OnAudioFilterRead, from a test, or offline into a WAV.
    /// </summary>
    public sealed class VehicleSynth
    {
        const int Block = 256;

        public readonly VehicleSignals sig;
        readonly VehicleSignals work = new VehicleSignals();     // sanitized private copy the voices actually read
        public readonly EngineSynth engine;
        public readonly SurfaceSynth surface;
        public readonly CreakSynth creak;
        public readonly WaterSynth water;
        public readonly WinchSynth winch;
        public readonly SamplePlayer player = new SamplePlayer();
        public readonly float sampleRate;

        readonly float[] bufEng = new float[Block], bufSrf = new float[Block], bufFx = new float[Block];
        Svf outLp;
        float dcX, dcY;
        float cutCur = 20000f;
        float busE = 1f, busS = 1f, busF = 1f, master = 1f;

        public VehicleSynth(EngineProfile profile, float sampleRate, VehicleSignals signals, SfxBank bank, uint seed = 1u)
        {
            this.sampleRate = sampleRate;
            DspWarmup.Touch();
            sig = signals ?? new VehicleSignals();
            engine = new EngineSynth(profile ?? EngineProfile.Utility(), sampleRate, 1000u + seed * 17u);
            surface = new SurfaceSynth(sampleRate, 4000u + seed * 31u);
            creak = CreakSynth.Suspension(sampleRate, 99u + seed * 13u);
            water = new WaterSynth(sampleRate, 31337u + seed * 7u);
            winch = new WinchSynth(sampleRate, 2024u + seed * 5u);
            player.bank = bank;
            outLp.Set(20000f, 0.7f, sampleRate);
        }

        /// <summary>Renders <paramref name="count"/> mono frames into dst[offset..] (overwrites).</summary>
        public void Render(float[] dst, int offset, int count)
        {
            while (count > 0)
            {
                int n = count > Block ? Block : count;
                RenderBlock(dst, offset, n);
                offset += n; count -= n;
            }
        }

        void RenderBlock(float[] dst, int off, int n)
        {
            VoiceEvent e;
            int guard = 0;
            while (guard++ < 16 && sig.events.TryPop(out e)) player.Play((Sfx)e.kind, e.variant, e.gain, e.pitch > 0.05f && e.pitch < 8f ? e.pitch : 1f);
            sig.CopySanitizedTo(work);
            var s = work;

            Array.Clear(bufEng, 0, n); Array.Clear(bufSrf, 0, n); Array.Clear(bufFx, 0, n);
            // level of detail: far-away vehicles drop their inaudible layers (distance01 is 0 near .. 1 at ~200 m)
            float lod = s.distance01;
            engine.Render(s, bufEng, 0, n);
            if (lod < 0.9f) surface.Render(s, bufSrf, 0, n);
            if (lod < 0.6f)
            {
                water.Render(s, bufSrf, 0, n);
                creak.Render(s.creak, s.creakSpeed, bufFx, 0, n);
                winch.Render(s, bufFx, 0, n);
            }
            if (player.Active) player.Mix(bufFx, 0, n);

            // low-pass for distance (air absorption) and cabin muffling
            float cabin = DspMath.Clamp01(s.cabin);
            float far = DspMath.Clamp01(s.distance01);
            float cutFar = 1800f + 20000f * (1f - far) * (1f - far);
            float cutCab = 20000f - 17000f * cabin;
            float cut = cutFar < cutCab ? cutFar : cutCab;
            bool filt = cut < 17000f || cutCur < 17000f;
            if (filt)
            {
                cutCur += (cut - cutCur) * 0.4f;
                outLp.Set(cutCur, 0.7f, sampleRate);
            }

            float tE = s.busEngine * (1f + 0.35f * cabin), tS = s.busSurface * (1f - 0.35f * cabin), tF = s.busFx * (1f - 0.15f * cabin), tM = s.master;
            float inv = 1f / n;
            float dE = (tE - busE) * inv, dS = (tS - busS) * inv, dF = (tF - busF) * inv, dM = (tM - master) * inv;
            float bE = busE, bS = busS, bF = busF, bM = master;
            float x1 = dcX, y1 = dcY;
            float a1 = outLp.a1, a2 = outLp.a2, a3 = outLp.a3, ic1 = outLp.ic1, ic2 = outLp.ic2;
            for (int i = 0; i < n; i++)
            {
                bE += dE; bS += dS; bF += dF; bM += dM;
                float x = bufEng[i] * bE + bufSrf[i] * bS + bufFx[i] * bF;
                if ((x - x) != 0f) x = 0f;                                    // NaN / Infinity can never reach the filter state or the device
                if (filt)
                {
                    float v3 = x - ic2; float v1 = a1 * ic1 + a2 * v3; float v2 = ic2 + a2 * ic1 + a3 * v3;
                    ic1 = 2f * v1 - ic1; ic2 = 2f * v2 - ic2; x = v2;
                }
                x *= bM;
                float y = x - x1 + 0.9985f * y1; x1 = x; y1 = y;              // DC blocker
                if (y > 0.75f || y < -0.75f) y = DspMath.SoftKnee(y);         // soft knee (identity below 0.75, ceiling 0.97)
                dst[off + i] = y;
            }
            outLp.ic1 = ic1; outLp.ic2 = ic2; dcX = x1; dcY = y1;
            busE = tE; busS = tS; busF = tF; master = tM;
        }
    }
}
