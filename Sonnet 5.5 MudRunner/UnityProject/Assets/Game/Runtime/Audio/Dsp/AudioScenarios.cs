using System;
using System.Collections.Generic;

namespace MudRunner.Audio.Dsp
{
    /// <summary>A rendered scenario (mono when right == null).</summary>
    public sealed class RenderedAudio
    {
        public string name;
        public int sampleRate;
        public float[] left, right;
        public string note;
        public bool Stereo { get { return right != null; } }
    }

    /// <summary>
    /// Offline scenarios: drive the very same synthesizers the game uses with scripted control signals and capture the output.
    /// Shared by the editor tool (WAV + statistics) and by the tests (numerical assertions); no audio device is needed.
    /// </summary>
    public static class AudioScenarios
    {
        public const int DefaultRate = 48000;
        public delegate void Script(float t, VehicleSignals s);

        static SfxBank cachedBank;
        static int cachedRate;
        public static SfxBank Bank(int sr)
        {
            if (cachedBank == null || cachedRate != sr) { cachedBank = SfxBank.Build(sr); cachedRate = sr; }
            return cachedBank;
        }

        // ------------------------------------------------------------------ generic renderers

        public static float[] RenderVehicle(EngineProfile profile, float seconds, Script script, int sr = DefaultRate, uint seed = 1u, int block = 512, bool withBank = true)
        {
            var sig = new VehicleSignals { speed = 5f };
            var syn = new VehicleSynth(profile, sr, sig, withBank ? Bank(sr) : null, seed);
            int n = (int)(seconds * sr);
            var buf = new float[n];
            for (int o = 0; o < n; o += block)
            {
                int c = Math.Min(block, n - o);
                script?.Invoke(o / (float)sr, sig);
                syn.Render(buf, o, c);
            }
            return buf;
        }

        public static void RenderAmbience(float seconds, Action<float, AmbienceParams> script, out float[] left, out float[] right, int sr = DefaultRate, int block = 512)
        {
            var p = new AmbienceParams();
            var syn = new AmbienceSynth(sr, 99u);
            int n = (int)(seconds * sr);
            left = new float[n]; right = new float[n];
            for (int o = 0; o < n; o += block)
            {
                int c = Math.Min(block, n - o);
                script?.Invoke(o / (float)sr, p);
                syn.Render(p, left, right, o, c);
            }
        }

        public static float[] RenderRiver(float seconds, float level, float flow, int sr = DefaultRate)
        {
            var syn = new RiverSynth(sr);
            int n = (int)(seconds * sr);
            var buf = new float[n];
            for (int o = 0; o < n; o += 512) syn.Render(level, flow, buf, o, Math.Min(512, n - o));
            return buf;
        }

        static float[] Concat(int sr, float gapSeconds, params float[][] parts)
        {
            int gap = (int)(gapSeconds * sr);
            int total = 0; foreach (var p in parts) total += p.Length + gap;
            var r = new float[total]; int o = 0;
            foreach (var p in parts) { Array.Copy(p, 0, r, o, p.Length); o += p.Length + gap; }
            return r;
        }

        // ------------------------------------------------------------------ vehicle scripts

        /// <summary>Steady state: constant rpm / throttle / load.</summary>
        public static Script Steady(float rpm, float throttle, float load, float strain = 0f, float speed = 5f)
        {
            return (t, s) => { s.engineOn = true; s.rpm = rpm; s.throttle = throttle; s.load = load; s.strain = strain; s.speed = speed; };
        }

        /// <summary>Rev up from idle to 95 % of redline and back down over the given duration.</summary>
        public static Script Sweep(EngineProfile p, float seconds)
        {
            return (t, s) =>
            {
                float u = t / seconds;
                float tri = u < 0.5f ? u * 2f : (1f - u) * 2f;               // 0..1..0
                float rpm01 = Math.Min(1f, tri * 1.05f);
                s.engineOn = true;
                s.rpm = p.idleRpm + (p.redlineRpm * 0.95f - p.idleRpm) * rpm01;
                s.throttle = u < 0.5f ? 0.15f + 0.85f * rpm01 : 0.02f;
                s.load = u < 0.5f ? 0.25f + 0.65f * rpm01 : 0.08f;
                s.speed = 3f + 12f * rpm01; s.exhaustBrakeOk = true;
            };
        }

        public static Script StartStall(EngineProfile p)
        {
            // 0.0-0.5 off | 0.5 start | ~2.2 running | 5.0 stall | 7.0 restart | 9.0 key-off
            float rpmNow = 0f;
            return (t, s) =>
            {
                s.speed = 0f; s.throttle = 0f; s.load = 0.1f;
                if (t < 0.5f) { s.engineOn = false; rpmNow = 0f; s.rpm = 0f; }
                else if (t < 5.0f)
                {
                    if (!s.engineOn) { s.engineOn = true; s.startCount++; rpmNow = p.idleRpm * 0.6f; }
                    rpmNow += (p.idleRpm * (t > 3.5f ? 1.35f : 1f) - rpmNow) * 0.02f; s.rpm = rpmNow;
                    s.throttle = t > 3.5f && t < 4.2f ? 0.5f : 0f; s.load = s.throttle > 0f ? 0.5f : 0.1f;
                }
                else if (t < 7.0f)
                {
                    if (s.engineOn) { s.engineOn = false; s.stallCount++; }
                    rpmNow *= 0.985f; s.rpm = rpmNow;
                }
                else if (t < 9.0f)
                {
                    if (!s.engineOn) { s.engineOn = true; s.startCount++; rpmNow = p.idleRpm * 0.6f; }
                    rpmNow += (p.idleRpm - rpmNow) * 0.02f; s.rpm = rpmNow;
                }
                else { s.engineOn = false; rpmNow *= 0.97f; s.rpm = rpmNow; }
            };
        }

        public static Script Lugging(EngineProfile p)
        {
            return (t, s) =>
            {
                float u = Math.Min(1f, t / 4f);
                s.engineOn = true; s.rpm = p.idleRpm * (1.55f - 0.25f * u); s.throttle = 1f; s.load = 1f; s.strain = u; s.speed = 0.8f;
            };
        }

        public static Script Flooding(EngineProfile p)
        {
            return (t, s) =>
            {
                s.rpm = p.idleRpm; s.throttle = 0.1f; s.load = 0.1f; s.speed = 1f;
                s.flood = Math.Min(1f, t / 3f);
                if (t < 4f) s.engineOn = true; else { if (s.engineOn) { s.stallCount++; s.engineOn = false; } s.rpm = p.idleRpm * 0.3f; s.flood = 1f; if (t > 5.5f && t < 5.6f) s.failCount++; }
            };
        }

        public static Script ExhaustBrake(EngineProfile p)
        {
            return (t, s) =>
            {
                s.engineOn = true; s.speed = 9f; s.exhaustBrakeOk = true;
                if (t < 3.5f) { s.rpm = p.idleRpm * 2.6f; s.throttle = 0f; s.load = 0f; }
                else { s.rpm = p.idleRpm * 2.6f; s.throttle = 1f; s.load = 0.85f; }
            };
        }

        static Script Ground(Action<VehicleSignals> set, float speed = 5f)
        {
            return (t, s) =>
            {
                s.engineOn = false; s.hasEngine = false;
                s.speed = speed; s.wheelRev = speed / (2f * 3.14159f * 0.54f);
                set(s);
            };
        }


        // ------------------------------------------------------------------ scripted one-shot events

        public struct Ev { public float t; public Sfx id; public float gain, pitch; public int variant; }
        static Ev E(float t, Sfx id, float gain, float pitch, int variant) { return new Ev { t = t, id = id, gain = gain, pitch = pitch, variant = variant }; }
        static void NoEngine(float t, VehicleSignals s) { s.engineOn = false; s.hasEngine = false; }

        /// <summary>Wrap a script so that each listed sample event is pushed exactly once when the clock passes its time.</summary>
        static Script Events(Script baseScript, params Ev[] evs)
        {
            var fired = new bool[evs.Length];
            return (t, s) =>
            {
                baseScript?.Invoke(t, s);
                for (int i = 0; i < evs.Length; i++)
                    if (!fired[i] && t >= evs[i].t) { fired[i] = true; s.PushSfx(evs[i].id, evs[i].gain, evs[i].pitch, evs[i].variant); }
            };
        }

        // ------------------------------------------------------------------ named scenarios

        public static readonly string[] EngineKeys = { "scout", "utility", "hauler" };

        public static IEnumerable<string> Names()
        {
            foreach (var k in EngineKeys)
            {
                yield return "engine_" + k + "_idle";
                yield return "engine_" + k + "_sweep";
                yield return "engine_" + k + "_lug";
                yield return "engine_" + k + "_startstall";
            }
            yield return "engine_utility_flooded";
            yield return "engine_hauler_exhaustbrake";
            yield return "mud_roll";
            yield return "mud_squelch_spin";
            yield return "gravel";
            yield return "grass";
            yield return "hard_ground";
            yield return "sand";
            yield return "wading";
            yield return "splash_mud";
            yield return "splash_water";
            yield return "creak";
            yield return "bump_thumps";
            yield return "impacts";
            yield return "gear_shift";
            yield return "winch";
            yield return "winch_hook";
            yield return "rain_light";
            yield return "rain_heavy";
            yield return "rain_roof";
            yield return "wind";
            yield return "ambience_day_forest";
            yield return "ambience_night_swamp";
            yield return "river_fast";
            yield return "river_still";
            yield return "ui";
            yield return "mix_drive_mud";
        }

        public static RenderedAudio Render(string name, int sr = DefaultRate)
        {
            var r = new RenderedAudio { name = name, sampleRate = sr };
            string[] part = name.Split('_');
            if (name.StartsWith("engine_"))
            {
                var p = EngineProfile.ForKey(part[1]);
                string kind = part[2];
                switch (kind)
                {
                    case "idle": r.left = RenderVehicle(p, 5f, (t, s) => { s.engineOn = true; s.rpm = p.idleRpm * (1f + 0.01f * (float)Math.Sin(t * 2.1)); s.throttle = 0f; s.load = 0.05f; s.speed = 0f; }, sr); break;
                    case "sweep": r.left = RenderVehicle(p, 10f, Sweep(p, 10f), sr); break;
                    case "lug": r.left = RenderVehicle(p, 6f, Lugging(p), sr); break;
                    case "startstall": r.left = RenderVehicle(p, 10.5f, StartStall(p), sr); break;
                    case "flooded": r.left = RenderVehicle(p, 7f, Flooding(p), sr); break;
                    case "exhaustbrake": r.left = RenderVehicle(p, 7f, ExhaustBrake(p), sr); break;
                }
                return r;
            }
            var ut = EngineProfile.Utility();
            switch (name)
            {
                case "mud_roll": r.left = RenderVehicle(ut, 6f, Ground(s => { s.mudRoll = 0.55f; s.suction = 0.25f; s.mudSlip = 0.1f; s.wetness = 0.5f; }), sr); break;
                case "mud_squelch_spin":
                    r.left = RenderVehicle(ut, 8f, (t, s) =>
                    {
                        s.engineOn = false; s.hasEngine = false; s.speed = 1.5f; s.wheelRev = 2.5f;
                        float u = Math.Min(1f, t / 3f);
                        s.mudRoll = 0.5f; s.mudSlip = 0.2f + 0.7f * u; s.suction = 0.3f + 0.6f * u; s.wetness = 0.7f; s.belly = u > 0.8f ? 0.5f : 0f;
                    }, sr); break;
                case "gravel": r.left = RenderVehicle(ut, 6f, Ground(s => { s.gravel = 0.7f; }, 9f), sr); break;
                case "grass": r.left = RenderVehicle(ut, 6f, Ground(s => { s.grass = 0.7f; }, 7f), sr); break;
                case "hard_ground": r.left = RenderVehicle(ut, 6f, Ground(s => { s.hard = 0.7f; s.skid = 0.1f; }, 10f), sr); break;
                case "sand": r.left = RenderVehicle(ut, 6f, Ground(s => { s.sand = 0.7f; }, 6f), sr); break;
                case "wading": r.left = RenderVehicle(ut, 6f, (t, s) => { s.engineOn = false; s.hasEngine = false; s.wading = Math.Min(1f, t / 1.5f) * 0.8f; s.waterFlow = 1f; s.speed = 3f; }, sr); break;
                case "splash_mud":
                    r.left = RenderVehicle(ut, 6f, Events(NoEngine, E(0.2f, Sfx.MudSplashSmall, 0.7f, 1f, 0), E(1.5f, Sfx.MudSplashSmall, 1f, 1f, 1), E(3.0f, Sfx.MudSplashBig, 1f, 1f, 0), E(4.5f, Sfx.MudSplashBig, 1f, 0.85f, 2)), sr); break;
                case "splash_water":
                    r.left = RenderVehicle(ut, 6f, Events(NoEngine, E(0.2f, Sfx.WaterSplashSmall, 0.8f, 1f, 0), E(1.5f, Sfx.WaterSplashSmall, 1f, 1.1f, 2), E(3.0f, Sfx.WaterSplashBig, 1f, 1f, 0), E(4.5f, Sfx.WaterSplashBig, 1f, 0.9f, 1)), sr); break;
                case "creak":
                    r.left = RenderVehicle(ut, 8f, (t, s) =>
                    {
                        s.engineOn = false; s.hasEngine = false;
                        float u = t / 8f;
                        s.creak = t < 4f ? 0.8f : 0.6f; s.creakSpeed = t < 4f ? 0.2f + 0.2f * u : 0.7f;
                    }, sr); break;
                case "bump_thumps":
                    r.left = RenderVehicle(ut, 5f, Events(NoEngine, E(0.1f, Sfx.BumpThump, 0.5f, 1f, 0), E(1.0f, Sfx.BumpThump, 0.8f, 1f, 1), E(1.9f, Sfx.SuspClonk, 0.7f, 1f, 0),
                        E(2.8f, Sfx.BumpThump, 1f, 1f, 2), E(3.7f, Sfx.SuspClonk, 1f, 1f, 1)), sr); break;
                case "impacts":
                    r.left = RenderVehicle(ut, 8f, Events(NoEngine, E(0.1f, Sfx.MetalThud, 0.9f, 1f, 0), E(1.3f, Sfx.PlasticThud, 0.9f, 1f, 0), E(2.5f, Sfx.CargoClank, 0.9f, 1f, 0),
                        E(3.8f, Sfx.RockThud, 0.9f, 1f, 0), E(5.0f, Sfx.WoodThunk, 0.9f, 1f, 0), E(6.2f, Sfx.VehicleCrunch, 0.9f, 1f, 0)), sr); break;
                case "gear_shift":
                    r.left = RenderVehicle(EngineProfile.Hauler(), 6f, Events((t, s) => { s.engineOn = true; s.rpm = 1500f; s.throttle = 0.5f; s.load = 0.5f; s.speed = 6f; },
                        E(0.5f, Sfx.ShiftClunkHeavy, 0.9f, 1f, 0), E(2.0f, Sfx.GearGrind, 0.8f, 1f, 0), E(2.0f, Sfx.ShiftClunkHeavy, 0.9f, 1f, 1),
                        E(3.5f, Sfx.AirPsstOn, 0.8f, 1f, 0), E(4.8f, Sfx.AirPsstOff, 0.8f, 1f, 0)), sr); break;
                case "winch":
                    r.left = RenderVehicle(ut, 9f, Events((t, s) =>
                    {
                        s.engineOn = false; s.hasEngine = false;
                        float u = Math.Min(1f, t / 7f);
                        s.winchMotor = t > 0.6f && t < 8.2f ? 1f : 0f; s.winchLoad = t < 1.2f ? 0.02f : 0.1f + 0.85f * u; s.winchDir = 1f;
                    }, E(1.2f, Sfx.RopeTwang, 0.8f, 1f, 0), E(6.0f, Sfx.RopeTwang, 1f, 1.1f, 1)), sr); break;
                case "winch_hook":
                    r.left = RenderVehicle(ut, 3f, Events(NoEngine, E(0.2f, Sfx.HookClunk, 1f, 1f, 0), E(1.6f, Sfx.HookRelease, 1f, 1f, 0)), sr); break;
                case "rain_light": RenderAmbience(8f, (t, p) => { p.rain = 0.25f; p.wetGround = 0.4f; p.master = 1f; }, out r.left, out r.right, sr); break;
                case "rain_heavy": RenderAmbience(8f, (t, p) => { p.rain = 0.9f; p.wetGround = 0.9f; p.wind = 0.3f; }, out r.left, out r.right, sr); break;
                case "rain_roof": RenderAmbience(8f, (t, p) => { p.rain = 0.7f; p.roof = 1f; p.cabin = 1f; p.wetGround = 0.6f; }, out r.left, out r.right, sr); break;
                case "wind": RenderAmbience(12f, (t, p) => { p.wind = 0.7f; p.forest = 0.4f; }, out r.left, out r.right, sr); break;
                case "ambience_day_forest": RenderAmbience(20f, (t, p) => { p.day = 1f; p.forest = 0.9f; p.wind = 0.2f; }, out r.left, out r.right, sr); break;
                case "ambience_night_swamp": RenderAmbience(16f, (t, p) => { p.night = 1f; p.swamp = 0.9f; p.forest = 0.4f; p.wind = 0.1f; }, out r.left, out r.right, sr); break;
                case "river_fast": r.left = RenderRiver(8f, 1f, 2.5f, sr); break;
                case "river_still": r.left = RenderRiver(8f, 0.8f, 0.05f, sr); break;
                case "ui":
                {
                    var bank = Bank(sr);
                    r.left = Concat(sr, 0.25f, bank.Get(Sfx.UiNotify, 0), bank.Get(Sfx.UiWarn, 0), bank.Get(Sfx.UiStuck, 0), bank.Get(Sfx.UiFuel, 0), bank.Get(Sfx.UiClick, 0), bank.Get(Sfx.UiSuccess, 0));
                    break;
                }
                case "mix_drive_mud":
                    r.left = RenderVehicle(ut, 10f, DriveMud(ut), sr); break;
            }
            return r;
        }

        /// <summary>Reference "driving through mud" signal set: used for the mix scenario and for the level-ordering checks.</summary>
        public static Script DriveMud(EngineProfile p)
        {
            return (t, s) =>
            {
                s.engineOn = true; s.hasEngine = true;
                s.rpm = p.idleRpm * 2.0f + 250f * (float)Math.Sin(t * 0.7); s.throttle = 0.6f; s.load = 0.6f; s.strain = 0.25f; s.speed = 4.5f;
                s.wheelRev = 1.4f; s.mudRoll = 0.6f; s.mudSlip = 0.3f; s.suction = 0.35f; s.wetness = 0.6f;
                s.creak = 0.25f; s.creakSpeed = 0.3f;
            };
        }

        /// <summary>Reference levels (linear RMS) used to assert engine &gt; tyres &gt; ambience.</summary>
        public static void ReferenceLevels(int sr, out float engineRms, out float tyreRms, out float ambienceRms)
        {
            var ut = EngineProfile.Utility();
            var eng = RenderVehicle(ut, 3f, (t, s) => { s.engineOn = true; s.rpm = 1800f; s.throttle = 0.5f; s.load = 0.5f; s.speed = 5f; }, sr);
            var tyr = RenderVehicle(ut, 3f, (t, s) => { s.engineOn = false; s.hasEngine = false; s.speed = 4.5f; s.wheelRev = 1.4f; s.mudRoll = 0.6f; s.mudSlip = 0.3f; s.suction = 0.35f; s.wetness = 0.6f; }, sr);
            RenderAmbience(24f, (t, p) => { p.day = 1f; p.forest = 0.7f; p.wind = 0.25f; }, out var l, out var r, sr);
            engineRms = AudioAnalysis.Analyze(eng, sr / 2, eng.Length - sr / 2, sr).rms;
            tyreRms = AudioAnalysis.Analyze(tyr, sr / 2, tyr.Length - sr / 2, sr).rms;
            ambienceRms = AudioAnalysis.Analyze(l, sr, l.Length - sr, sr).rms;
        }
    }
}
