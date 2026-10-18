using MudRunner.Vfx;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.Atmosphere
{
    /// <summary>
    /// Sky + lighting polish driven by <see cref="AtmosphereController"/> (hour / overcast / rain; its API is unchanged, it just stops writing the lighting
    /// when this component is present). Owns: the skybox material (shader MudRunner/Sky: gradient, haze, sun disc + glow, moon, stars, scrolling clouds),
    /// the key light (sun by day, moon by night, with palette-driven colour / intensity / direction), trilight ambient + fog colour curves, and publishes the
    /// globals the VFX shaders use (_MR_VfxSunColor/_MR_VfxSunDir/_MR_VfxAmbient, _MR_Weather = rain, wind xz, overcast).
    /// Sunrise 05:30, sunset 20:30, solar noon 13:00.
    /// </summary>
    [DefaultExecutionOrder(60)]
    public sealed class SkyController : MonoBehaviour
    {
        public static SkyController Instance { get; private set; }

        public Material SkyMaterial { get; private set; }
        public float Rain { get; private set; }            // smoothed rain 0..1
        public float Overcast { get; private set; }        // smoothed overcast incl. rain
        public float SunElevation { get; private set; }    // degrees
        public bool drivesLighting = true;

        static readonly float[] Key = { -18f, -8f, -2f, 3f, 10f, 25f, 60f };
        static readonly Color[] Zenith =
        {
            new Color(0.003f, 0.005f, 0.016f), new Color(0.014f, 0.024f, 0.07f), new Color(0.05f, 0.07f, 0.19f), new Color(0.10f, 0.16f, 0.38f),
            new Color(0.08f, 0.19f, 0.50f), new Color(0.07f, 0.20f, 0.58f), new Color(0.06f, 0.20f, 0.62f)
        };
        static readonly Color[] Horizon =
        {
            new Color(0.012f, 0.014f, 0.03f), new Color(0.06f, 0.05f, 0.09f), new Color(0.60f, 0.24f, 0.12f), new Color(0.75f, 0.45f, 0.30f),
            new Color(0.55f, 0.58f, 0.65f), new Color(0.50f, 0.62f, 0.80f), new Color(0.48f, 0.62f, 0.85f)
        };

        AtmosphereController at;
        Light sun;
        float giTimer, lastGiElev = -999f, lastGiOvercast = -1f;
        bool first = true;

        static readonly int IdZenith = Shader.PropertyToID("_ZenithColor"), IdHorizon = Shader.PropertyToID("_HorizonColor"), IdGround = Shader.PropertyToID("_GroundColor"),
            IdGlow = Shader.PropertyToID("_GlowColor"), IdSunColor = Shader.PropertyToID("_SunColor"), IdMoonColor = Shader.PropertyToID("_MoonColor"),
            IdSunDir = Shader.PropertyToID("_SunDir"), IdMoonDir = Shader.PropertyToID("_MoonDir"), IdP0 = Shader.PropertyToID("_P0"), IdP1 = Shader.PropertyToID("_P1"),
            IdWind = Shader.PropertyToID("_Wind"), IdCloudLit = Shader.PropertyToID("_CloudLit"), IdCloudShade = Shader.PropertyToID("_CloudShade"), IdSunVis = Shader.PropertyToID("_SunVis"),
            GSunColor = Shader.PropertyToID("_MR_VfxSunColor"), GSunDir = Shader.PropertyToID("_MR_VfxSunDir"), GAmbient = Shader.PropertyToID("_MR_VfxAmbient"),
            GWeather = Shader.PropertyToID("_MR_Weather");

        void Awake()
        {
            Instance = this;
            var sh = VfxResources.SkyShader;
            if (sh != null)
            {
                SkyMaterial = VfxResources.NewMaterial(sh, "VFX_Sky");
                SkyMaterial.SetTexture("_CloudTex", VfxTextures.Cloud);
                RenderSettings.skybox = SkyMaterial;
            }
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.defaultReflectionMode = DefaultReflectionMode.Skybox;
            RenderSettings.reflectionIntensity = 1f;
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            // defaults for the VFX shaders until the first Update
            Shader.SetGlobalVector(GSunColor, new Vector4(1.6f, 1.5f, 1.3f, 1f));
            Shader.SetGlobalVector(GSunDir, new Vector4(0.3f, 0.8f, 0.3f, 0f));
            Shader.SetGlobalVector(GAmbient, new Vector4(0.45f, 0.5f, 0.6f, 1f));
            Shader.SetGlobalVector(GWeather, Vector4.zero);
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
            if (SkyMaterial != null) { if (RenderSettings.skybox == SkyMaterial) RenderSettings.skybox = null; Destroy(SkyMaterial); }
        }

        static float Smooth(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3f - 2f * t); }

        static Color Palette(Color[] arr, float elev)
        {
            if (elev <= Key[0]) return arr[0];
            for (int i = 1; i < Key.Length; i++)
                if (elev <= Key[i]) return Color.Lerp(arr[i - 1], arr[i], (elev - Key[i - 1]) / (Key[i] - Key[i - 1]));
            return arr[arr.Length - 1];
        }

        static Vector3 Dir(float elevDeg, float azDeg)
        {
            float e = elevDeg * Mathf.Deg2Rad, a = azDeg * Mathf.Deg2Rad;
            return new Vector3(Mathf.Cos(e) * Mathf.Sin(a), Mathf.Sin(e), Mathf.Cos(e) * Mathf.Cos(a));
        }

        void LateUpdate()
        {
            if (at == null) at = AtmosphereController.Instance;
            if (at == null) return;
            if (drivesLighting) at.externalLighting = true;
            if (sun == null) sun = at.sun != null ? at.sun : RenderSettings.sun;
            float dt = Time.deltaTime;
            if (first) { Rain = at.rain; first = false; } else Rain = Mathf.MoveTowards(Rain, at.rain, dt * 0.3f);
            float targetOc = Mathf.Max(at.overcast, Rain * 0.95f);
            Overcast = Mathf.Lerp(Overcast, targetOc, 1f - Mathf.Exp(-dt * 0.8f));
            if (Time.frameCount < 3) Overcast = targetOc;
            float oc = Overcast;

            // ---- sun / moon
            float t = (at.hour - 5.5f) / 15f;
            float elev = 58f * Mathf.Sin(t * Mathf.PI);
            float az = Mathf.Lerp(80f, 280f, t);
            SunElevation = elev;
            Vector3 sunDir = Dir(elev, az);
            Vector3 moonDir = -sunDir;
            float dayK = Smooth(-8f, 22f, elev);

            Color zenith = Palette(Zenith, elev), horizon = Palette(Horizon, elev);
            Color grey = new Color(0.34f, 0.36f, 0.40f) * Mathf.Lerp(0.04f, 1f, dayK) * Mathf.Lerp(1f, 0.62f, Rain);
            zenith = Color.Lerp(zenith, grey * 0.85f, oc * 0.85f);
            horizon = Color.Lerp(horizon, grey * 1.1f, oc * 0.8f);
            Color sunCol = Color.Lerp(new Color(1f, 0.52f, 0.26f), new Color(1f, 0.95f, 0.85f), Smooth(0f, 22f, elev));
            Color glow = Color.Lerp(new Color(1f, 0.5f, 0.2f), new Color(1f, 0.85f, 0.6f), Smooth(2f, 30f, elev)) * (1f - oc * 0.85f);
            float lowSun = 1f - Smooth(4f, 28f, elev);

            // ---- key light (sun by day, moon by night)
            float sunI = 2.3f * Smooth(-2f, 12f, elev) * (1f - 0.62f * oc);
            float moonUp = Smooth(0.05f, 0.35f, moonDir.y);
            float moonI = 0.20f * moonUp * (1f - 0.55f * oc) * (elev < -2f ? 1f : 0f);
            Color keyCol; float keyI; Vector3 keyDir;
            if (elev > -2f) { keyCol = sunCol; keyI = sunI; keyDir = sunDir; }
            else { keyCol = new Color(0.55f, 0.66f, 1f); keyI = moonI; keyDir = moonDir.y > 0f ? moonDir : sunDir; }
            if (drivesLighting && sun != null)
            {
                sun.transform.rotation = Quaternion.LookRotation(-keyDir, Vector3.up);
                sun.color = keyCol; sun.intensity = keyI;
                sun.enabled = keyI > 0.001f;
            }

            // ---- ambient + fog
            Color ambSky = Color.Lerp(zenith, horizon, 0.35f) * Mathf.Lerp(1.0f, 0.9f, oc) + new Color(0.010f, 0.014f, 0.03f);
            Color ambEq = horizon * 0.85f + new Color(0.010f, 0.012f, 0.022f);
            Color ambGr = new Color(0.12f, 0.10f, 0.08f) * Mathf.Lerp(0.05f, 1f, dayK) * Mathf.Lerp(1f, 0.6f, oc) + new Color(0.006f, 0.006f, 0.008f);
            if (drivesLighting)
            {
                RenderSettings.ambientMode = AmbientMode.Trilight;
                RenderSettings.ambientSkyColor = ambSky; RenderSettings.ambientEquatorColor = ambEq; RenderSettings.ambientGroundColor = ambGr;
                RenderSettings.ambientIntensity = 1f;
                RenderSettings.fog = true; RenderSettings.fogMode = FogMode.ExponentialSquared;
                RenderSettings.fogColor = horizon * 0.92f;
                RenderSettings.fogDensity = 0.0009f + 0.0017f * Mathf.Max(oc, Rain) + (1f - dayK) * 0.0004f;
            }

            // ---- sky material
            if (SkyMaterial != null)
            {
                Vector3 wind = VfxDirector.Instance != null ? VfxDirector.Instance.Wind : Vector3.zero;
                SkyMaterial.SetColor(IdZenith, zenith); SkyMaterial.SetColor(IdHorizon, horizon);
                SkyMaterial.SetColor(IdGround, Color.Lerp(horizon * 0.55f, ambGr * 2f, 0.4f));
                SkyMaterial.SetColor(IdGlow, glow);
                SkyMaterial.SetColor(IdSunColor, sunCol * 28f * (1f - oc * 0.92f));
                SkyMaterial.SetColor(IdMoonColor, new Color(1.2f, 1.3f, 1.6f));
                SkyMaterial.SetVector(IdSunDir, sunDir); SkyMaterial.SetVector(IdMoonDir, moonDir);
                SkyMaterial.SetVector(IdP0, new Vector4(0.0105f, Mathf.Lerp(1f, 0.5f, oc), 0.45f, 7f));
                float stars = Smooth(-4f, -16f, elev) * (1f - oc);
                float cover = Mathf.Clamp01(0.30f + 0.62f * oc + 0.1f * Rain);
                SkyMaterial.SetVector(IdP1, new Vector4(stars, cover, Mathf.Lerp(0.88f, 1f, oc), 1.1f));
                SkyMaterial.SetVector(IdWind, new Vector4(0.004f + wind.x * 0.0012f, 0.0015f + wind.z * 0.0012f, 0f, 0f));
                Color cloudLit = Color.Lerp(Color.white, new Color(1f, 0.62f, 0.38f), lowSun) * Mathf.Lerp(0.08f, 1f, dayK) * Mathf.Lerp(1f, 0.55f, oc);
                cloudLit += new Color(0.02f, 0.025f, 0.04f) * (1f - dayK);
                Color cloudShade = Color.Lerp(new Color(0.55f, 0.60f, 0.72f), new Color(0.38f, 0.26f, 0.32f), lowSun) * Mathf.Lerp(0.06f, 1f, dayK) * Mathf.Lerp(1f, 0.55f, oc);
                cloudShade += new Color(0.012f, 0.015f, 0.03f) * (1f - dayK);
                SkyMaterial.SetColor(IdCloudLit, cloudLit); SkyMaterial.SetColor(IdCloudShade, cloudShade);
                SkyMaterial.SetVector(IdSunVis, new Vector4(1f, Smooth(-2f, -10f, elev) * (1f - 0.85f * oc), 1f, 0f));
            }

            // ---- globals for the VFX shaders
            Vector3 w2 = VfxDirector.Instance != null ? VfxDirector.Instance.Wind : Vector3.zero;
            Color lightLin = keyCol * keyI;
            Shader.SetGlobalVector(GSunColor, new Vector4(lightLin.r, lightLin.g, lightLin.b, 1f));
            Shader.SetGlobalVector(GSunDir, new Vector4(keyDir.x, keyDir.y, keyDir.z, 0f));
            Color amb = ambSky * 0.65f + ambEq * 0.35f;
            Shader.SetGlobalVector(GAmbient, new Vector4(amb.r, amb.g, amb.b, 1f));
            Shader.SetGlobalVector(GWeather, new Vector4(Rain, w2.x, w2.z, oc));

            // ---- reflection / GI refresh (expensive: only on real changes, at most every 3 s)
            giTimer -= dt;
            if (first || giTimer <= 0f && (Mathf.Abs(elev - lastGiElev) > 1.5f || Mathf.Abs(oc - lastGiOvercast) > 0.12f) || lastGiElev < -900f)
            {
                lastGiElev = elev; lastGiOvercast = oc; giTimer = 3f;
                DynamicGI.UpdateEnvironment();
            }
        }
    }
}
