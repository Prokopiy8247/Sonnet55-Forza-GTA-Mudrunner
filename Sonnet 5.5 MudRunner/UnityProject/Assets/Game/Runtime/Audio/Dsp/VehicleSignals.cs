namespace MudRunner.Audio.Dsp
{
    /// <summary>
    /// Everything the per-vehicle synthesizer needs to know, as plain fields. The main thread (VehicleAudioDriver, or an
    /// offline scenario script) writes them, the audio thread reads them at the start of each render chunk. 32-bit field
    /// writes are atomic, so no locking is needed; one-shot happenings go through <see cref="events"/> or the *Count fields.
    /// </summary>
    public sealed class VehicleSignals
    {
        // ------------------------------------------------------------------ engine
        public bool hasEngine = true;
        public bool engineOn = true;             // drivetrain.engineOn && fuel > 0
        public float rpm = 800f;
        public float throttle;                   // 0..1 driver demand reaching the engine
        public float load;                       // 0..1 torque / available torque (drives pulse sharpness and brightness)
        public float strain;                     // 0..1 lugging: high load at low rpm / clutch slipping in mud
        public float flood;                      // 0..1 water entering the intake (splutter)
        public float speed;                      // m/s of the body
        public float brake;                      // 0..1 service brake
        public bool handbrake;
        public bool exhaustBrakeOk = true;       // moving forward in gear (hauler engine brake)
        public int startCount, failCount, stallCount;   // incremented by the main thread on each start / failed start / stall

        // ------------------------------------------------------------------ tyres / ground (aggregated over the wheels, 0..1)
        public float mudRoll, mudSlip, suction, gravel, grass, hard, sand, skid, belly;
        public float wheelRev;                   // mean wheel revolution rate (Hz)
        public float wetness;                    // 0..1 ground wetness

        // ------------------------------------------------------------------ suspension
        public float creak;                      // 0..1 how much creaking is wanted
        public float creakSpeed;                 // 0..1 normalised articulation speed (pitch / stick-slip rate)

        // ------------------------------------------------------------------ water
        public float wading;                     // 0..1
        public float waterFlow;                  // m/s current

        // ------------------------------------------------------------------ winch
        public float winchMotor;                 // 0..1 motor running
        public float winchLoad;                  // 0..1 tension / rated pull
        public float winchDir = 1f;              // +1 reel in, -1 reel out

        // ------------------------------------------------------------------ spatial (set by the director)
        public float doppler = 1f;               // frequency ratio heard (1 = no shift)
        public float distance01;                 // 0 near .. 1 far (air absorption low-pass)
        public float cabin;                      // 0 outside .. 1 in the cockpit (muffling)

        // ------------------------------------------------------------------ mix
        public float busEngine = 1f, busSurface = 1f, busFx = 1f, master = 1f;

        /// <summary>One-shot sample events (impacts, splashes, shifts...) for the in-voice sample player.</summary>
        public readonly EventQueue events = new EventQueue();

        static float F(float v, float lo, float hi) { if (float.IsNaN(v)) return lo; return v < lo ? lo : (v > hi ? hi : v); }

        /// <summary>Replace NaN/Infinity and clamp every field to its sane range (in place).</summary>
        public void Sanitize() { CopySanitizedTo(this); }

        /// <summary>
        /// Copy every value field into <paramref name="d"/> with NaN/Infinity removed and the range clamped. The synth renders from such a private
        /// copy, so a bad number from the game thread can never poison an oscillator phase or a filter state on the audio thread.
        /// </summary>
        public void CopySanitizedTo(VehicleSignals d)
        {
            d.hasEngine = hasEngine; d.engineOn = engineOn; d.handbrake = handbrake; d.exhaustBrakeOk = exhaustBrakeOk;
            d.startCount = startCount; d.failCount = failCount; d.stallCount = stallCount;
            d.rpm = F(rpm, 0f, 20000f); d.throttle = F(throttle, 0f, 1f); d.load = F(load, 0f, 1f); d.strain = F(strain, 0f, 1f); d.flood = F(flood, 0f, 1f);
            d.speed = F(speed, 0f, 300f); d.brake = F(brake, 0f, 1f);
            d.mudRoll = F(mudRoll, 0f, 1f); d.mudSlip = F(mudSlip, 0f, 1f); d.suction = F(suction, 0f, 1f); d.gravel = F(gravel, 0f, 1f); d.grass = F(grass, 0f, 1f);
            d.hard = F(hard, 0f, 1f); d.sand = F(sand, 0f, 1f); d.skid = F(skid, 0f, 1f); d.belly = F(belly, 0f, 1f); d.wheelRev = F(wheelRev, 0f, 200f); d.wetness = F(wetness, 0f, 1f);
            d.creak = F(creak, 0f, 1f); d.creakSpeed = F(creakSpeed, 0f, 1f); d.wading = F(wading, 0f, 1f); d.waterFlow = F(waterFlow, 0f, 30f);
            d.winchMotor = F(winchMotor, 0f, 1f); d.winchLoad = F(winchLoad, 0f, 1f); d.winchDir = float.IsNaN(winchDir) ? 1f : F(winchDir, -1f, 1f);
            d.doppler = float.IsNaN(doppler) ? 1f : F(doppler, 0.5f, 2f); d.distance01 = F(distance01, 0f, 1f); d.cabin = F(cabin, 0f, 1f);
            d.busEngine = F(busEngine, 0f, 4f); d.busSurface = F(busSurface, 0f, 4f); d.busFx = F(busFx, 0f, 4f); d.master = F(master, 0f, 4f);
        }

        public void PushSfx(Sfx id, float gain, float pitch = 1f, int variant = -1)
        {
            var e = new VoiceEvent { kind = (int)id, variant = variant, gain = gain, pitch = pitch };
            events.Push(e);
        }
    }
}
