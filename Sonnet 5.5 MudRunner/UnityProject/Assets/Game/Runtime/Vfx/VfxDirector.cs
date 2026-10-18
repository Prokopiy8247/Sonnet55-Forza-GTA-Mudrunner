using System.Collections.Generic;
using MudRunner.Atmosphere;
using MudRunner.Ground;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Vfx
{
    public enum VfxQuality { Low = 0, Medium = 1, High = 2 }

    /// <summary>
    /// Entry point of the VFX layer. <see cref="Install"/> (called by GameBootstrap) creates: the pooled <see cref="ParticleHub"/>, the
    /// <see cref="AtmosphereController"/> (if missing), the <see cref="SkyController"/> (skybox, sun / moon, ambient, fog), the <see cref="WeatherVfx"/>
    /// (GPU rain + ground splashes) and keeps a <see cref="WheelVfx"/> + <see cref="BodyVfx"/> on every <see cref="Vehicle"/> (incl. trailers) and a
    /// <see cref="WaterRenderer"/> on every map that has water. Effects only run for vehicles near the camera.
    /// Global toggles for the debug menu: <see cref="Enabled"/>, <see cref="Quality"/>.
    /// </summary>
    [DefaultExecutionOrder(100)]
    public sealed class VfxDirector : MonoBehaviour
    {
        public static VfxDirector Instance { get; private set; }

        static bool enabledFlag = true;
        static VfxQuality quality = VfxQuality.High;

        /// <summary>Global on / off for particles, rain and splashes (water surface and sky stay).</summary>
        public static bool Enabled
        {
            get { return enabledFlag; }
            set { enabledFlag = value; if (Instance != null && Instance.Hub != null) Instance.Hub.SetVisible(value); }
        }

        public static VfxQuality Quality
        {
            get { return quality; }
            set { quality = value; if (Instance != null && Instance.Hub != null) Instance.Hub.SetQuality(value); }
        }

        public static float ScaleFor(VfxQuality q) { return q == VfxQuality.Low ? 0.35f : q == VfxQuality.Medium ? 0.65f : 1f; }
        public static float Scale { get { return ScaleFor(quality); } }
        public static float ViewDistance { get { return quality == VfxQuality.Low ? 70f : quality == VfxQuality.Medium ? 110f : 160f; } }

        public ParticleHub Hub { get; private set; }
        public WeatherVfx Weather { get; private set; }
        public SkyController Sky { get; private set; }
        public WaterRenderer Water { get; private set; }
        public Vector3 Wind { get; private set; }
        public Camera Cam { get; private set; }

        // telemetry
        public float LastTickMs { get; private set; }
        public long LastTickAllocBytes { get; private set; }
        public int ActiveVehicles { get; private set; }

        sealed class Entry { public Vehicle v; public WheelVfx wheel; public BodyVfx body; }
        readonly Dictionary<Vehicle, Entry> entries = new Dictionary<Vehicle, Entry>();
        readonly List<Vehicle> stale = new List<Vehicle>();
        float waterTimer;

        public static VfxDirector Install()
        {
            if (Instance != null) return Instance;
            var existing = FindFirstObjectByType<VfxDirector>();
            if (existing != null) return existing;
            var go = new GameObject("VfxDirector");
            return go.AddComponent<VfxDirector>();
        }

        void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
            Hub = ParticleHub.Create(transform, quality);
            Hub.SetVisible(enabledFlag);

            // atmosphere (+ a sun if the scene has none)
            var at = AtmosphereController.Instance;
            if (at == null) at = FindFirstObjectByType<AtmosphereController>();
            if (at == null) at = new GameObject("Atmosphere").AddComponent<AtmosphereController>();
            if (RenderSettings.sun == null)
            {
                Light dir = null;
                foreach (var l in FindObjectsByType<Light>(FindObjectsSortMode.None)) if (l != null && l.type == LightType.Directional) { dir = l; break; }
                if (dir == null)
                {
                    dir = new GameObject("Sun").AddComponent<Light>();
                    dir.type = LightType.Directional; dir.shadows = LightShadows.Soft; dir.intensity = 1.6f;
                }
                RenderSettings.sun = dir;
            }
            if (at.sun == null) at.sun = RenderSettings.sun;
            Sky = at.GetComponent<SkyController>();
            if (Sky == null) Sky = at.gameObject.AddComponent<SkyController>();

            var wgo = new GameObject("Weather");
            wgo.transform.SetParent(transform, false);
            Weather = wgo.AddComponent<WeatherVfx>();
            Weather.Setup(this);
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        void LateUpdate()
        {
            long a0 = System.GC.GetAllocatedBytesForCurrentThread();
            long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
            float dt = Mathf.Min(Time.deltaTime, 0.05f);
            Cam = Camera.main;
            if (Hub == null) return;
            Hub.BeginFrame();
            UpdateWind();
            EnsureWater(dt);

            // vehicles
            stale.Clear();
            foreach (var kv in entries) if (kv.Key == null) stale.Add(kv.Key);
            for (int i = 0; i < stale.Count; i++) entries.Remove(stale[i]);
            Vector3 camPos = Cam != null ? Cam.transform.position : Vector3.zero;
            float maxD = ViewDistance, maxD2 = maxD * maxD;
            int active = 0;
            var all = Vehicle.All;
            for (int i = 0; i < all.Count; i++)
            {
                var v = all[i];
                if (v == null || v.wheels == null || v.def == null) continue;
                if (!entries.TryGetValue(v, out var e)) e = Attach(v);
                if (!enabledFlag) continue;
                if (Cam != null && (v.transform.position - camPos).sqrMagnitude > maxD2) continue;
                active++;
                e.wheel.Tick(dt);
                e.body.Tick(dt);
            }
            ActiveVehicles = active;
            if (Weather != null) Weather.Tick(dt, Cam);

            LastTickMs = (float)((System.Diagnostics.Stopwatch.GetTimestamp() - t0) * 1000.0 / System.Diagnostics.Stopwatch.Frequency);
            LastTickAllocBytes = System.GC.GetAllocatedBytesForCurrentThread() - a0;
        }

        Entry Attach(Vehicle v)
        {
            var e = new Entry { v = v };
            e.wheel = v.GetComponent<WheelVfx>(); if (e.wheel == null) e.wheel = v.gameObject.AddComponent<WheelVfx>();
            e.body = v.GetComponent<BodyVfx>(); if (e.body == null) e.body = v.gameObject.AddComponent<BodyVfx>();
            e.wheel.Setup(v, this);
            e.body.Setup(v, this);
            // headlights: softer, wider falloff (VehicleLights creates the spots, we only polish them)
            foreach (var l in v.GetComponentsInChildren<Light>(true))
            {
                if (l.type != LightType.Spot) continue;
                l.innerSpotAngle = l.spotAngle * 0.28f;
                l.range = Mathf.Max(l.range, 55f);
                l.intensity = Mathf.Max(l.intensity, 220f);
                l.shadows = LightShadows.None;
            }
            entries[v] = e;
            return e;
        }

        void UpdateWind()
        {
            float t = Time.time;
            float rain = Sky != null ? Sky.Rain : 0f;
            float ang = Mathf.PerlinNoise(t * 0.02f, 0.37f) * Mathf.PI * 2f;
            float spd = 0.8f + 3.5f * rain + 2.0f * Mathf.PerlinNoise(t * 0.15f, 7.1f) * (0.4f + rain);
            Wind = new Vector3(Mathf.Cos(ang), 0f, Mathf.Sin(ang)) * spd;
        }

        void EnsureWater(float dt)
        {
            waterTimer -= dt;
            if (waterTimer > 0f) return;
            waterTimer = 0.5f;
            var gs = GroundService.Instance;
            if (gs == null || gs.Map == null || gs.Map.water == null) { Water = null; return; }
            if (Water != null && Water.Map == gs.Map) return;
            foreach (var wr in FindObjectsByType<WaterRenderer>(FindObjectsSortMode.None))
                if (wr != null && wr.Map == gs.Map) { Water = wr; return; }
            Water = WaterRenderer.Create(gs.Map.water, gs.Map, null);
        }
    }
}
