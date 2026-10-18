using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.Atmosphere
{
    /// <summary>
    /// Time of day + weather. Minimal functional core (sun, ambient, fog, rain -> ground wetness); the atmosphere worker
    /// extends it with sky, clouds, rain particles, lights and polish. Public API is stable: other systems only use it.
    /// </summary>
    public sealed class AtmosphereController : MonoBehaviour
    {
        public static AtmosphereController Instance { get; private set; }

        [Range(0f, 24f)] public float hour = 15.5f;
        [Tooltip("Game minutes advanced per real second (0 = frozen).")]
        public float minutesPerSecond = 0f;
        [Tooltip("Rain intensity 0..1 (target). Rain raises ground wetness, drying lowers it.")]
        [Range(0f, 1f)] public float rain;
        [Range(0f, 1f)] public float overcast = 0.35f;
        public float rainWetnessRate = 0.012f;      // wetness/s at full rain
        public float dryingRate = 0.0006f;          // wetness/s
        public Light sun;
        /// <summary>Set by SkyController: it then owns sun / ambient / fog (this component keeps time, rain and wetness).</summary>
        public bool externalLighting;

        public bool IsNight => hour < 5.5f || hour > 20.5f;
        public float SunHeight01 => Mathf.Clamp01(Mathf.Sin((hour - 6f) / 12f * Mathf.PI));

        void Awake() { Instance = this; }
        void OnDestroy() { if (Instance == this) Instance = null; }

        public void SetTime(float h) { hour = Mathf.Repeat(h, 24f); Apply(); }
        public void SetRain(float intensity) { rain = Mathf.Clamp01(intensity); }
        public void SetRainOn(bool on) { rain = on ? 0.85f : 0f; }

        void Start() { if (sun == null) sun = RenderSettings.sun; Apply(); }

        void Update()
        {
            if (minutesPerSecond > 0f) hour = Mathf.Repeat(hour + minutesPerSecond / 60f * Time.deltaTime, 24f);
            var gs = GroundService.Instance;
            if (gs != null)
            {
                float w = gs.wetness;
                w += rain * rainWetnessRate * Time.deltaTime;
                w -= (1f - rain) * dryingRate * Time.deltaTime;
                gs.wetness = Mathf.Clamp01(w);
            }
            Apply();
        }

        void Apply()
        {
            if (externalLighting || sun == null) return;
            float day = SunHeight01;
            sun.transform.rotation = Quaternion.Euler(Mathf.Lerp(-6f, 62f, day) * (hour >= 6f && hour <= 18f ? 1f : -1f), (hour - 12f) * 15f - 35f, 0f);
            sun.intensity = Mathf.Lerp(0f, 1.7f, Mathf.Pow(day, 0.6f)) * Mathf.Lerp(1f, 0.45f, Mathf.Max(overcast, rain));
            sun.color = Color.Lerp(new Color(1f, 0.55f, 0.3f), new Color(1f, 0.96f, 0.88f), Mathf.Clamp01(day * 2f));
            RenderSettings.ambientIntensity = Mathf.Lerp(0.15f, 1f, day);
            float fog = 0.0009f + 0.0016f * Mathf.Max(overcast, rain) + (IsNight ? 0.0006f : 0f);
            RenderSettings.fogDensity = fog;
            RenderSettings.fogColor = Color.Lerp(new Color(0.03f, 0.04f, 0.06f), Color.Lerp(new Color(0.65f, 0.72f, 0.78f), new Color(0.45f, 0.5f, 0.54f), Mathf.Max(overcast, rain)), day);
        }
    }
}
