using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using MudRunner.Atmosphere;
using MudRunner.Audio.Dsp;
using MudRunner.Cargo;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Audio
{
    /// <summary>
    /// Owns all procedural audio of the game. Everything audible is synthesized in code (see MudRunner.Audio.Dsp): there are no
    /// audio assets. The director
    ///  * follows the AudioListener (creates one if the scene has none) and tracks its velocity for Doppler;
    ///  * attaches a <see cref="VehicleAudioDriver"/> + 3D voice to every <see cref="Vehicle"/> (engine, tyres, suspension, water,
    ///    winch, impacts) and keeps only the nearest voices running;
    ///  * runs the global stereo ambience voice (wind, rain, birds, insects, frogs), a positional river voice that sits toward the
    ///    nearest <see cref="WaterMap"/> cells, UI sounds and a soft-knee master limiter.
    /// Integration: call <see cref="Install"/> once (GameBootstrap / GameManager); it is also created automatically after the
    /// first scene load and stays dormant until a GameManager exists. Master volume is AudioListener.volume
    /// (<see cref="MasterVolume"/> is the same value).
    /// </summary>
    [DefaultExecutionOrder(50)]
    public sealed class AudioDirector : MonoBehaviour
    {
        public static AudioDirector Instance { get; private set; }

        // ---------------------------------------------------------------- public settings (static so UI / settings code needs no reference)

        /// <summary>Master volume 0..1 (is AudioListener.volume, so the pause-menu slider and the save system share it).</summary>
        public static float MasterVolume
        {
            get { return AudioListener.volume; }
            set { AudioListener.volume = Mathf.Clamp01(value); }
        }
        public static float EngineVolume = 1f, SurfaceVolume = 1f, EffectsVolume = 1f, AmbienceVolume = 1f, UiVolume = 1f;
        /// <summary>Tree cover 0..1 used for birds / rustle. Negative = derive from the world kind and the local ground.</summary>
        public static float ForestDensity = -1f;
        /// <summary>-1 automatic (listener inside the player's cab), 0 force outside, 1 force cockpit muffling.</summary>
        public static int CockpitOverride = -1;
        /// <summary>The auto-created director is skipped in batch mode (tests call Install explicitly).</summary>
        public static bool AutoInstallInBatchMode = false;
        public static int MaxVehicleVoices = 6;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics()
        {
            Instance = null;
            EngineVolume = SurfaceVolume = EffectsVolume = AmbienceVolume = UiVolume = 1f;
            ForestDensity = -1f; CockpitOverride = -1; MaxVehicleVoices = 6;
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void AutoCreate()
        {
            if (Instance != null) return;
            if (Application.isBatchMode && !AutoInstallInBatchMode) return;
            Create(true);
        }

        /// <summary>Create (or return) the director and activate it immediately.</summary>
        public static AudioDirector Install()
        {
            if (Instance == null) Create(false);
            Instance.Activate();
            return Instance;
        }

        static AudioDirector Create(bool dormant)
        {
            var go = new GameObject("AudioDirector");
            DontDestroyOnLoad(go);
            var d = go.AddComponent<AudioDirector>();
            d.dormant = dormant;
            return d;
        }

        // ---------------------------------------------------------------- state

        public bool dormant;
        public bool Activated { get; private set; }
        public int SampleRate { get; private set; } = 48000;
        public SfxBank Bank { get { return bank; } }
        volatile SfxBank bank;
        volatile bool dspReady;
        Task bankTask;
        readonly List<AudioSource> pendingPlay = new List<AudioSource>();

        readonly List<VehicleAudioDriver> drivers = new List<VehicleAudioDriver>();
        public IReadOnlyList<VehicleAudioDriver> Drivers { get { return drivers; } }
        public AmbienceVoice AmbienceVoice { get; private set; }
        public RiverVoice RiverVoice { get; private set; }
        public AmbienceParams AmbienceParams { get; private set; }

        // listener
        AudioListener listener;
        Transform listenerT;
        Vector3 lastListenerPos, listenerVel;
        bool haveListenerPos;
        float listenerSearchTimer;

        // timers
        float scanTimer, envTimer, riverTimer;
        float cabinSmooth;

        // river
        Transform riverT;
        Vector3 riverTarget;
        bool riverFound;
        float riverLevelT, riverFlowT;

        // one-shots and UI
        AudioSource[] pool;
        AudioClip[][] clipCache;
        int poolNext;
        AudioSource uiSource;
        Transform poolRoot;
        readonly List<Transform> poolFollow = new List<Transform>();

        // UI watchers
        bool prevStuck, prevObjDone, prevObjFail, prevFlooding;
        float lowFuelTimer, stuckTimer;
        float cargoScanTimer;

        readonly float[] wbuf = new float[GroundMap.LayerCount];
        uint seedCounter;

        void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        // ================================================================== activation

        void Activate()
        {
            if (Activated) return;
            Activated = true; dormant = false;
            SampleRate = AudioSettings.outputSampleRate > 0 ? AudioSettings.outputSampleRate : 48000;
            int sr = SampleRate;
            // all one-shot clips are rendered on a worker thread (pure DSP, no Unity API) so the first frame does not hitch
            // (the same worker first JIT-compiles every synth path so the first real audio callback does not stall)
            bankTask = Task.Run(() =>
            {
                try { DspWarmup.JitWarm(sr); }
                catch (System.Exception e) { Debug.LogWarning("[MudRunner] audio warm-up failed: " + e.Message); }
                finally { dspReady = true; }
                try { bank = SfxBank.Build(sr); }
                catch (System.Exception e) { Debug.LogWarning("[MudRunner] audio bank build failed: " + e.Message); }
            });

            EnsureListener();
            CreateAmbience();
            CreateRiver();
            CreatePool();
        }

        /// <summary>Voices start playing only after the DSP warm-up finished (otherwise the first buffers would wait for JIT compilation).</summary>
        void StartVoice(AudioSource src)
        {
            if (src == null) return;
            if (dspReady) src.Play(); else pendingPlay.Add(src);
        }

        void EnsureListener()
        {
            if (listener != null && listener.isActiveAndEnabled) return;
            listener = FindAnyObjectByType<AudioListener>();
            if (listener == null)
            {
                var cam = Camera.main;
                listener = cam != null ? cam.gameObject.AddComponent<AudioListener>() : gameObject.AddComponent<AudioListener>();
            }
            listenerT = listener.transform;
            if (listener.GetComponent<MasterLimiter>() == null) listener.gameObject.AddComponent<MasterLimiter>();
            haveListenerPos = false;
        }

        void CreateAmbience()
        {
            var go = new GameObject("AmbienceVoice");
            go.transform.SetParent(transform, false);
            var src = AudioVoiceUtil.AddSource(go, false);
            src.priority = 40;
            var v = go.AddComponent<AmbienceVoice>();
            AmbienceParams = new AmbienceParams();
            v.parameters = AmbienceParams;
            v.synth = new AmbienceSynth(SampleRate, 777u);
            v.source = src;
            AmbienceVoice = v;
            StartVoice(src);
        }

        void CreateRiver()
        {
            var go = new GameObject("RiverVoice");
            go.transform.SetParent(transform, false);
            var src = AudioVoiceUtil.AddSource(go, true, 150f);
            src.minDistance = 6f;
            var v = go.AddComponent<RiverVoice>();
            v.synth = new RiverSynth(SampleRate, 1717u);
            v.source = src;
            RiverVoice = v; riverT = go.transform;
            StartVoice(src);
        }

        void CreatePool()
        {
            poolRoot = new GameObject("OneShots").transform;
            poolRoot.SetParent(transform, false);
            pool = new AudioSource[14];
            for (int i = 0; i < pool.Length; i++)
            {
                var go = new GameObject("OneShot" + i);
                go.transform.SetParent(poolRoot, false);
                var s = go.AddComponent<AudioSource>();
                s.playOnAwake = false; s.loop = false; s.spatialBlend = 1f; s.dopplerLevel = 0.4f;
                s.rolloffMode = AudioRolloffMode.Custom; s.minDistance = 5f; s.maxDistance = 140f;
                s.SetCustomCurve(AudioSourceCurveType.CustomRolloff, AudioVoiceUtil.RolloffCurve(140f));
                pool[i] = s; poolFollow.Add(null);
            }
            var ui = new GameObject("UiVoice");
            ui.transform.SetParent(transform, false);
            uiSource = ui.AddComponent<AudioSource>();
            uiSource.playOnAwake = false; uiSource.spatialBlend = 0f; uiSource.priority = 32; uiSource.ignoreListenerPause = true;   // menu sounds also play while the game is paused
            clipCache = new AudioClip[(int)Sfx.Count][];
        }

        // ================================================================== one-shots / UI API

        AudioClip GetClip(Sfx id, int variant)
        {
            var b = bank;
            if (b == null) return null;
            int vc = b.VariantCount(id);
            variant = ((variant % vc) + vc) % vc;
            var arr = clipCache[(int)id] ?? (clipCache[(int)id] = new AudioClip[vc]);
            if (arr[variant] == null)
            {
                var data = b.Get(id, variant);
                var clip = AudioClip.Create(id + "_" + variant, data.Length, 1, b.sampleRate, false);
                clip.SetData(data, 0);
                arr[variant] = clip;
            }
            return arr[variant];
        }

        /// <summary>Play a UI sound (2D). Safe to call before activation (ignored).</summary>
        public static void PlayUi(Sfx id, float gain = 1f)
        {
            var d = Instance;
            if (d == null || !d.Activated || d.uiSource == null) return;
            var clip = d.GetClip(id, 0);
            if (clip == null) return;
            d.uiSource.PlayOneShot(clip, gain * UiVolume);
        }

        public static void Notify() { PlayUi(Sfx.UiNotify); }
        public static void Warn() { PlayUi(Sfx.UiWarn); }
        public static void Click() { PlayUi(Sfx.UiClick, 0.8f); }

        /// <summary>Play a one-shot at a world position (optionally following a transform, e.g. a vehicle).</summary>
        public static void PlayAt(Sfx id, Vector3 position, float gain = 1f, float pitch = 1f, Transform follow = null)
        {
            var d = Instance;
            if (d == null || !d.Activated || d.pool == null) return;
            var b = d.bank;
            if (b == null) return;
            var clip = d.GetClip(id, Random.Range(0, b.VariantCount(id)));
            if (clip == null) return;
            int idx = -1;
            for (int k = 0; k < d.pool.Length; k++) { int j = (d.poolNext + k) % d.pool.Length; if (!d.pool[j].isPlaying) { idx = j; break; } }
            if (idx < 0) idx = d.poolNext;
            d.poolNext = (idx + 1) % d.pool.Length;
            var s = d.pool[idx];
            s.Stop();
            s.transform.SetParent(follow != null ? follow : d.poolRoot, true);
            s.transform.position = position;
            d.poolFollow[idx] = follow;
            s.clip = clip; s.volume = Mathf.Clamp01(gain) * EffectsVolume; s.pitch = pitch;
            s.Play();
        }

        // ================================================================== frame update

        void Update()
        {
            if (!Activated)
            {
                if (GameManager.Instance != null) Activate();
                else return;
            }
            float dt = Mathf.Max(1e-4f, Time.unscaledDeltaTime);
            listenerSearchTimer -= dt;
            if (listenerSearchTimer <= 0f)
            {
                listenerSearchTimer = 0.5f;
                // the director's own fallback listener is replaced as soon as a real camera exists
                if (listener != null && listener.gameObject == gameObject && Camera.main != null && Camera.main.GetComponent<AudioListener>() == null)
                {
                    Destroy(listener); listener = null; listenerT = null; listenerSearchTimer = 0.05f;
                }
                else if (listener == null || !listener.isActiveAndEnabled) EnsureListener();
            }
            UpdateListener(dt);

            if (dspReady && pendingPlay.Count > 0)
            {
                for (int i = 0; i < pendingPlay.Count; i++) if (pendingPlay[i] != null) pendingPlay[i].Play();
                pendingPlay.Clear();
            }
            // late-bound sample bank (built on a worker thread)
            var b = bank;
            scanTimer -= dt;
            if (scanTimer <= 0f) { scanTimer = 0.25f; ScanVehicles(); }
            if (b != null) for (int i = 0; i < drivers.Count; i++) { var dr = drivers[i]; if (dr != null && dr.synth != null && dr.synth.player.bank == null) dr.synth.player.bank = b; }

            UpdateDrivers(dt);
            envTimer -= dt;
            if (envTimer <= 0f) { envTimer = 0.2f; UpdateEnvironment(); }
            UpdateRiver(dt);
            UpdatePool();
            // recover voices that raised an exception on the audio thread
            if (AmbienceVoice != null && AmbienceVoice.faulted) { AmbienceVoice.synth = new AmbienceSynth(SampleRate, 778u); AmbienceVoice.faulted = false; }
            if (RiverVoice != null && RiverVoice.faulted) { RiverVoice.synth = new RiverSynth(SampleRate, 1718u); RiverVoice.faulted = false; }
            UpdateUiWatchers(dt);
            cargoScanTimer -= dt;
            if (cargoScanTimer <= 0f) { cargoScanTimer = 1f; ScanCargo(); }
        }

        void UpdateListener(float dt)
        {
            if (listenerT == null) return;
            Vector3 p = listenerT.position;
            if (!haveListenerPos) { lastListenerPos = p; haveListenerPos = true; listenerVel = Vector3.zero; }
            Vector3 v = (p - lastListenerPos) / dt;
            if (v.sqrMagnitude > 80f * 80f) v = Vector3.zero;                     // teleport
            listenerVel = Vector3.Lerp(listenerVel, v, 1f - Mathf.Exp(-dt / 0.08f));
            lastListenerPos = p;
            transform.position = p;                                               // the director follows the listener
        }

        // ---------------------------------------------------------------- vehicles

        void ScanVehicles()
        {
            var all = Vehicle.All;
            for (int i = 0; i < all.Count; i++)
            {
                var v = all[i];
                if (v == null || v.def == null || v.wheels == null || v.drivetrain == null) continue;
                var existing = v.GetComponent<VehicleAudioDriver>();
                if (existing != null)
                {
                    // a driver left behind by an earlier director: adopt it while its voice is alive, otherwise rebuild it
                    if (existing.voice != null && existing.synth != null) { if (!drivers.Contains(existing)) drivers.Add(existing); continue; }
                    Destroy(existing);
                }
                CreateDriver(v);
            }
            for (int j = drivers.Count - 1; j >= 0; j--) if (drivers[j] == null || drivers[j].vehicle == null) drivers.RemoveAt(j);
        }

        VehicleAudioDriver CreateDriver(Vehicle v)
        {
            var def = v.def;
            var profile = EngineProfile.ForVehicle(def.name, def.mass, def.idleRpm, def.redlineRpm, def.stallRpm);
            var sig = new VehicleSignals();
            sig.engineOn = v.drivetrain.engineOn; sig.rpm = v.drivetrain.rpm; sig.hasEngine = !def.isTrailer;
            var synth = new VehicleSynth(profile, SampleRate, sig, bank, ++seedCounter);

            var go = new GameObject("VehicleAudio");
            go.transform.SetParent(v.transform, false);
            go.transform.localPosition = def.bodyCenter + new Vector3(0f, 0.1f, def.bodySize.z * 0.3f);
            var src = AudioVoiceUtil.AddSource(go, true);
            var voice = go.AddComponent<VehicleVoice>();
            voice.synth = synth; voice.source = src;

            var driver = v.gameObject.AddComponent<VehicleAudioDriver>();
            driver.Init(v, sig, synth, profile, voice, src, go.transform);
            drivers.Add(driver);
            StartVoice(src);
            return driver;
        }

        public VehicleAudioDriver GetDriver(Vehicle v)
        {
            for (int i = 0; i < drivers.Count; i++) if (drivers[i] != null && drivers[i].vehicle == v) return drivers[i];
            return null;
        }

        void UpdateDrivers(float dt)
        {
            var gm = GameManager.Instance;
            var player = gm != null ? gm.Player : null;
            Vector3 lp = lastListenerPos;
            const float C = 343f;
            int n = drivers.Count;

            // distance + ranking (only the nearest MaxVehicleVoices stay active)
            for (int i = 0; i < n; i++)
            {
                var d = drivers[i]; if (d == null || d.voiceTransform == null) continue;
                d.distanceToListener = Vector3.Distance(lp, d.voiceTransform.position);
            }
            bool anyCabin = false;
            for (int i = 0; i < n; i++)
            {
                var d = drivers[i]; if (d == null || d.voiceTransform == null || d.vehicle == null) continue;
                int rank = 0;
                for (int k = 0; k < n; k++) if (k != i && drivers[k] != null && drivers[k].distanceToListener < d.distanceToListener) rank++;
                bool want = d.distanceToListener < 230f && rank < MaxVehicleVoices;
                if (want != d.voiceActive)
                {
                    d.voiceActive = want;
                    if (want) d.source.UnPause(); else d.source.Pause();
                }
                d.isPlayer = d.vehicle == player;
                d.source.spatialBlend = d.isPlayer ? 0.75f : 1f;
                var sig = d.signals;

                // Doppler (the synthesized signal is not resampled by Unity, so the synth applies the frequency ratio itself)
                Vector3 toSrc = d.voiceTransform.position - lp;
                float dist = Mathf.Max(0.5f, toSrc.magnitude);
                Vector3 u = toSrc / dist;
                Vector3 vs = d.vehicle.rb != null ? d.vehicle.rb.linearVelocity : Vector3.zero;
                float ratio = (C + Vector3.Dot(listenerVel, u)) / (C + Vector3.Dot(vs, u));
                ratio = Mathf.Clamp(ratio, 0.8f, 1.25f);
                if (d.isPlayer) ratio = 1f + (ratio - 1f) * 0.3f;
                sig.doppler += (ratio - sig.doppler) * (1f - Mathf.Exp(-dt / 0.07f));
                sig.distance01 = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(25f, 200f, dist));

                // cockpit muffling
                float cabin = 0f;
                if (d.isPlayer)
                {
                    if (CockpitOverride >= 0) cabin = CockpitOverride > 0 ? 1f : 0f;
                    else
                    {
                        var def = d.vehicle.def;
                        Vector3 head = d.vehicle.transform.TransformPoint(def.bodyCenter);
                        float r = Mathf.Max(def.bodySize.x, def.bodySize.y) * 0.8f + 0.4f;
                        cabin = 1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(r * 0.9f, r * 1.4f, Vector3.Distance(lp, head)));
                    }
                    cabinSmooth += (cabin - cabinSmooth) * (1f - Mathf.Exp(-dt / 0.25f));
                    anyCabin = true;
                }
                sig.cabin = d.isPlayer ? cabinSmooth : 0f;
                sig.busEngine = EngineVolume; sig.busSurface = SurfaceVolume; sig.busFx = EffectsVolume; sig.master = 1f;
                sig.Sanitize();
            }
            if (!anyCabin) cabinSmooth += (0f - cabinSmooth) * (1f - Mathf.Exp(-dt / 0.25f));
        }

        // ---------------------------------------------------------------- environment

        void UpdateEnvironment()
        {
            var p = AmbienceParams;
            if (p == null) return;
            var atm = AtmosphereController.Instance;
            var gs = GroundService.Instance;
            var gm = GameManager.Instance;
            var map = gs != null ? gs.Map : null;

            float rain = atm != null ? atm.rain : 0f;
            float overcast = atm != null ? atm.overcast : 0.3f;
            float sun = atm != null ? atm.SunHeight01 : 0.8f;
            p.rain = rain;
            p.day = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0.06f, 0.35f, sun)) * (1f - 0.35f * overcast);
            p.night = 1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0f, 0.22f, sun));
            p.wind = Mathf.Clamp01(0.10f + 0.6f * overcast + 0.3f * rain);
            p.wetGround = gs != null ? gs.wetness : 0.3f;
            p.cabin = cabinSmooth;
            p.roof = cabinSmooth * rain;
            p.master = AmbienceVolume;

            float playerSpeed = gm != null && gm.Player != null ? gm.Player.speed : 0f;
            p.speedWind = 0.8f * Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(4f, 28f, playerSpeed)) * (1f - 0.55f * cabinSmooth);

            // local ground: grass => forest, bog / deep mud => swamp
            float grass = 0f, swampG = 0f;
            Vector3 lp = lastListenerPos;
            if (map != null && map.Contains(lp.x, lp.z))
            {
                map.SampleWeights(lp.x, lp.z, wbuf);
                grass = wbuf[(int)SurfaceType.Grass];
                swampG = wbuf[(int)SurfaceType.Bog] + wbuf[(int)SurfaceType.DeepMud] * 0.8f + wbuf[(int)SurfaceType.ShallowMud] * 0.35f;
            }
            float baseForest = 0.4f;
            if (gm != null && gm.World != null)
                baseForest = gm.World.kind == WorldKind.Wilderness ? 0.8f : (gm.World.kind == WorldKind.ProvingGround ? 0.35f : 0.15f);
            p.forest = ForestDensity >= 0f ? Mathf.Clamp01(ForestDensity) : Mathf.Clamp01(baseForest * (0.45f + 0.9f * grass));

            // water proximity: scan the water map around the listener
            ScanWater(lp, map != null ? map.water : null, out float waterNear);
            p.swamp = Mathf.Clamp01(swampG + 0.7f * waterNear * (1f - 0.5f * Mathf.Clamp01(riverFlowT / 1.5f)));
        }

        void ScanWater(Vector3 lp, WaterMap water, out float nearness)
        {
            nearness = 0f;
            riverFound = false;
            if (water == null) { riverLevelT = 0f; return; }
            const float R = 72f, step = 6f;
            float bestD = float.MaxValue, sx = 0f, sz = 0f, sw = 0f, flow = 0f;
            for (float dx = -R; dx <= R; dx += step)
                for (float dz = -R; dz <= R; dz += step)
                {
                    float d2 = dx * dx + dz * dz;
                    if (d2 > R * R) continue;
                    if (!water.Sample(lp.x + dx, lp.z + dz, out float lvl, out Vector2 fl)) continue;
                    float d = Mathf.Sqrt(d2);
                    if (d < bestD) bestD = d;
                    float w = 1f / (1f + d2 * 0.004f);
                    sx += (lp.x + dx) * w; sz += (lp.z + dz) * w; sw += w; flow += fl.magnitude * w;
                }
            if (sw <= 0f) { riverLevelT = 0f; return; }
            riverFound = true;
            riverTarget = new Vector3(sx / sw, lp.y, sz / sw);
            riverFlowT = flow / sw;
            riverLevelT = Mathf.SmoothStep(0f, 1f, 1f - Mathf.Clamp01(bestD / R));
            nearness = Mathf.Clamp01(1f - bestD / 40f);
        }

        void UpdateRiver(float dt)
        {
            if (RiverVoice == null || riverT == null) return;
            if (riverFound) riverT.position = Vector3.Lerp(riverT.position, riverTarget, 1f - Mathf.Exp(-dt / 0.4f));
            RiverVoice.level = riverLevelT * AmbienceVolume;
            RiverVoice.flow = riverFlowT;
        }

        // ---------------------------------------------------------------- one-shot housekeeping

        void UpdatePool()
        {
            if (pool == null) return;
            for (int i = 0; i < pool.Length; i++)
            {
                if (poolFollow[i] != null && !pool[i].isPlaying) { pool[i].transform.SetParent(poolRoot, true); poolFollow[i] = null; }
            }
        }

        void ScanCargo()
        {
            var ts = TrailerSystem.Instance;
            if (ts == null) return;
            for (int i = 0; i < ts.Cargo.Count; i++)
            {
                var rb = ts.Cargo[i];
                if (rb != null && rb.GetComponent<CargoAudioProbe>() == null) rb.gameObject.AddComponent<CargoAudioProbe>();
            }
        }

        // ---------------------------------------------------------------- UI watchers

        void UpdateUiWatchers(float dt)
        {
            var gm = GameManager.Instance;
            var v = gm != null ? gm.Player : null;
            if (v != null && v.def != null)
            {
                if (v.isStuck && !prevStuck) { PlayUi(Sfx.UiStuck); stuckTimer = 12f; }
                else if (v.isStuck) { stuckTimer -= dt; if (stuckTimer <= 0f) { PlayUi(Sfx.UiStuck, 0.8f); stuckTimer = 12f; } }
                prevStuck = v.isStuck;

                float cap = Mathf.Max(1f, v.def.fuelCapacity);
                float frac = v.fuel / cap;
                if (!v.def.isTrailer && frac < 0.15f && v.fuel > 0f && v.drivetrain != null && v.drivetrain.engineOn)
                {
                    lowFuelTimer -= dt;
                    if (lowFuelTimer <= 0f) { PlayUi(Sfx.UiFuel); lowFuelTimer = frac < 0.05f ? 15f : 45f; }
                }
                else lowFuelTimer = Mathf.Min(lowFuelTimer, 0f);

                bool flooding = v.water != null && v.water.floodTimer > 0.2f && v.drivetrain != null && v.drivetrain.engineOn;
                if (flooding && !prevFlooding) PlayUi(Sfx.UiWarn);
                prevFlooding = flooding;
            }
            var om = ObjectiveManager.Instance;
            if (om != null)
            {
                if (om.completed && !prevObjDone) PlayUi(Sfx.UiSuccess);
                if (om.failed && !prevObjFail) PlayUi(Sfx.UiWarn);
                prevObjDone = om.completed; prevObjFail = om.failed;
            }
        }

        // ================================================================== diagnostics

        public string DebugSummary()
        {
            var sb = new StringBuilder();
            sb.Append("Audio: sr=").Append(SampleRate).Append(" bank=").Append(bank != null ? "ready" : "building").Append(" vehicles=").Append(drivers.Count)
              .Append(" master=").Append(AudioListener.volume.ToString("F2"));
            if (AmbienceParams != null)
                sb.Append(" | rain=").Append(AmbienceParams.rain.ToString("F2")).Append(" wind=").Append(AmbienceParams.wind.ToString("F2"))
                  .Append(" day=").Append(AmbienceParams.day.ToString("F2")).Append(" night=").Append(AmbienceParams.night.ToString("F2"))
                  .Append(" forest=").Append(AmbienceParams.forest.ToString("F2")).Append(" swamp=").Append(AmbienceParams.swamp.ToString("F2"));
            return sb.ToString();
        }
    }

    /// <summary>Added to loose cargo bodies: plays a clank / thunk at the contact point when they knock into something.</summary>
    [AddComponentMenu("")]
    public sealed class CargoAudioProbe : MonoBehaviour
    {
        float cooldown;
        Rigidbody rb;

        void Awake() { rb = GetComponent<Rigidbody>(); }
        void Update() { cooldown -= Time.deltaTime; }

        void OnCollisionEnter(Collision c)
        {
            if (cooldown > 0f) return;
            float mass = rb != null ? Mathf.Max(1f, rb.mass) : 100f;
            float j = c.impulse.magnitude / mass;
            float inten = Mathf.Clamp01((j - 0.2f) / 4f);
            if (inten < 0.04f) return;
            cooldown = 0.09f;
            string n = gameObject.name;
            Sfx id = n.IndexOf("Log", System.StringComparison.OrdinalIgnoreCase) >= 0 || n.IndexOf("Crate", System.StringComparison.OrdinalIgnoreCase) >= 0 ? Sfx.WoodThunk : Sfx.CargoClank;
            Vector3 p = c.contactCount > 0 ? c.GetContact(0).point : transform.position;
            AudioDirector.PlayAt(id, p, 0.2f + 0.8f * inten, Random.Range(0.92f, 1.08f));
        }
    }
}
