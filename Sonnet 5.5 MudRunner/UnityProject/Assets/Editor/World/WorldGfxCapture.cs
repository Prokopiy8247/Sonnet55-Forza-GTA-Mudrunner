using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using MudRunner.Ground;
using MudRunner.Rendering;
using MudRunner.Testing;
using MudRunner.WorldGen;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Debug = UnityEngine.Debug;

namespace MudRunner.EditorTools
{
    public static partial class WorldPreviewGfx
    {
        const int Wpx = 1600, Hpx = 900;
        static string CaptureDir => Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Captures");

        struct V
        {
            public string name; public Vector3 pos; public Vector3 look; public float fov, sunEl, sunAz, wet, far;
            public V(string n, float px, float pz, float ph, float lx, float lz, float lh, float fov = 62f, float sunEl = 32f, float sunAz = 215f, float wet = 0.35f, float far = 2500f)
            { name = n; pos = new Vector3(px, ph, pz); look = new Vector3(lx, lh, lz); this.fov = fov; this.sunEl = sunEl; this.sunAz = sunAz; this.wet = wet; this.far = far; }
        }

        static Camera cam; static Light sun; static GroundService gs; static WorldHandle handle; static GeneratedWorld gw; static GroundRenderer gr;

        public static void Run()
        {
            try { RunInternal(); }
            catch (Exception e)
            {
                Debug.LogError("[MudRunner] WorldPreviewGfx FAILED: " + e);
                if (Application.isBatchMode) EditorApplication.Exit(1);
            }
        }

        static void SelectPcQuality()
        {
            string[] names = QualitySettings.names;
            for (int i = 0; i < names.Length; i++) if (names[i] == "PC") { QualitySettings.SetQualityLevel(i, true); return; }
        }

        static void RunInternal()
        {
            Directory.CreateDirectory(CaptureDir);
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            SelectPcQuality();
            Debug.Log("[MudRunner] SystemInfo: " + SystemInfo.graphicsDeviceName + " / " + SystemInfo.graphicsDeviceType);
            WorldRegistration.EnsureRegistered();
            GroundTextures.DebugKeepReadable = false;

            var sw = Stopwatch.StartNew();
            var cfg = new WorldGenConfig { full = true };
            gw = WorldGenerator.Generate(cfg);
            WorldPreview.LogTimings(gw);
            WorldPreview.LogRouteStats(gw);
            WorldPreview.WriteMaps(gw, "world");
            var data = WorldInstantiator.Instantiate(gw, MudRunner.Game.WorldKind.Wilderness);
            handle = data.root.GetComponent<WorldHandle>();
            Debug.Log("[MudRunner] world generate+instantiate " + sw.ElapsedMilliseconds + " ms");

            gs = TestArena.Install(gw.map, data.playerStart, 0.35f);
            gr = handle.groundRenderer;
            cam = MakeCamera(); sun = MakeSun(32f, 215f); MakeSky(sun); MakeVolume();
            if (gr != null) { gr.buildFromGroundService = false; gr.targetCamera = cam; var s2 = Stopwatch.StartNew(); gr.Build(gw.map); Debug.Log("[MudRunner] GroundRenderer.Build " + s2.ElapsedMilliseconds + " ms, chunks " + gr.ChunkCount); }
            if (handle.props != null) handle.props.targetCamera = cam;
            int ruts = WorldRuts.Apply(gs.Field, gw);
            gs.Field.SyncGpu(5000);
            Debug.Log("[MudRunner] ruts applied: calls=" + ruts + " storedTiles=" + gs.Field.StoredTiles + " resident=" + gs.Field.ResidentActiveTiles);

            var only = Environment.GetEnvironmentVariable("WG_ONLY");
            foreach (var v in Views())
            {
                if (!string.IsNullOrEmpty(only) && !Matches(only, v.name)) continue;
                Shoot(v);
            }
            Debug.Log("[MudRunner] WorldPreviewGfx finished OK");
        }

        static bool Matches(string filter, string name)
        {
            foreach (var tok in filter.Split(new[] { ' ', ',', ';' }, StringSplitOptions.RemoveEmptyEntries)) if (name.Contains(tok)) return true;
            return false;
        }

        // ------------------------------------------------------------------ views

        static V Along(string track, float s, float back, float h, float ahead, float lookH, float fov = 62f, float wet = 0.35f, float sunEl = 32f, float sunAz = 215f)
        {
            var t = gw.tracks.Find(track);
            Vector3 p = t.AtLength(s), q = t.AtLength(s + ahead), b = t.AtLength(Mathf.Max(0f, s - back));
            Vector3 dir = (q - p); dir.y = 0f; dir = dir.normalized;
            Vector3 cp = p - dir * back;
            return new V(track + "_" + (int)s, cp.x, cp.z, h, q.x, q.z, lookH, fov, sunEl, sunAz, wet);
        }

        static V AlongAt(string name, string track, float wx, float wz, float back, float h, float ahead, float lookH, float fov = 62f, float wet = 0.35f)
        {
            var t = gw.tracks.Find(track);
            int i = t.NearestIndex(wx, wz);
            var v = Along(track, t.s[i], back, h, ahead, lookH, fov, wet);
            v.name = name;
            return v;
        }

        static List<V> Views()
        {
            var l = new List<V>();
            // overviews
            l.Add(new V("w_overview_sw", -330f, -820f, 230f, -250f, -200f, 0f, 60f));
            l.Add(new V("w_overview_ne", 120f, 120f, 420f, 520f, 420f, 0f, 62f, 28f, 200f));
            l.Add(new V("w_base_camp", -560f, -520f, 7f, -615f, -575f, 2.5f, 64f));
            l.Add(new V("w_base_camp_high", -520f, -480f, 40f, -610f, -565f, 0f, 62f));
            l.Add(AlongAt("w_central_forest", "central", -440f, -390f, 14f, 3.2f, 40f, 1.5f));
            l.Add(AlongAt("w_central_mud", "central", 245f, 455f, 16f, 3.4f, 40f, 0.5f));
            l.Add(AlongAt("w_north_gravel", "north", -710f, -300f, 14f, 3.0f, 40f, 1.5f));
            l.Add(AlongAt("w_ford_f1", "central", -262f, -40f, 24f, 4.0f, 40f, 0.2f, 60f));
            l.Add(AlongAt("w_ford_f2", "mid_link", 182f, -100f, 24f, 4.0f, 40f, 0.2f, 60f));
            l.Add(AlongAt("w_creek_ford", "swamp", -65f, -472f, 24f, 4.0f, 40f, 0.5f, 60f));
            l.Add(AlongAt("w_old_bridge", "old_road", -15f, 26f, 28f, 5f, 40f, 0.5f, 60f));
            l.Add(AlongAt("w_bridge_b2", "swamp_bridge", 290f, -60f, 28f, 5f, 40f, 0.5f, 60f));
            l.Add(AlongAt("w_deep_crossing", "swamp", 412f, -50f, 26f, 4.5f, 40f, 0.2f, 60f));
            l.Add(AlongAt("w_widowmaker", "swamp", 336f, -388f, 40f, 6f, 80f, 14f, 64f, 0.6f));
            l.Add(AlongAt("w_widowmaker_top", "swamp", 352f, -270f, 12f, 3.5f, 40f, -3f, 62f, 0.6f));
            l.Add(AlongAt("w_bog_approach", "swamp", 531f, 345f, 20f, 3.5f, 40f, 0.3f, 62f, 0.8f));
            l.Add(AlongAt("w_central_swamp_edge", "central", 440f, 468f, 18f, 3.3f, 40f, 0.3f, 62f, 0.8f));
            l.Add(AlongAt("w_causeway", "north", 540f, 586f, 20f, 4f, 40f, 0.5f, 62f, 0.5f));
            l.Add(new V("w_cabin_aerial", 505f, 440f, 30f, 552f, 488f, 5f, 55f));
            l.Add(new V("w_cabin_ground", 550f, 440f, 3f, 552f, 488f, 4f, 62f));
            l.Add(new V("w_swamp_overview", 300f, 280f, 70f, 565f, 430f, 3f, 60f));
            l.Add(new V("w_watchtower", -520f, 430f, 12f, -450f, 480f, 20f, 60f));
            l.Add(new V("w_radio_mast", 40f, 560f, 8f, 100f, 600f, 25f, 60f));
            l.Add(new V("w_sawmill", -330f, -225f, 4f, -300f, -200f, 2f, 64f));
            l.Add(new V("w_logging_landing", -120f, 390f, 5f, -150f, 420f, 1.5f, 64f));
            l.Add(new V("w_pump_station", 575f, -225f, 5f, 598f, -250f, 2f, 64f));
            l.Add(new V("w_river_valley", -120f, -190f, 25f, -60f, -40f, 8f, 62f));
            // proving ground (look heights are metres above the ground at the target)
            l.Add(new V("pg_overview", 880f, -296f, 45f, 905f, 20f, 2f, 70f));
            l.Add(new V("pg_start", 880f, -258f, 3.2f, 850f, -215f, 2f, 66f));
            l.Add(new V("pg_straight", 850f, -232f, 2.6f, 850f, -140f, 1f, 62f));
            l.Add(new V("pg_pits", 838f, -126f, 4.5f, 850f, -50f, 0.5f, 62f));
            l.Add(new V("pg_pits_side", 826f, -45f, 5f, 850f, -45f, 0.3f, 66f));
            l.Add(new V("pg_hill", 928f, -138f, 4f, 940f, -60f, 14f, 62f));
            l.Add(new V("pg_hill_side", 905f, -78f, 9f, 940f, -66f, 9f, 66f));
            l.Add(new V("pg_hill_top", 940f, -50f, 3.5f, 940f, 30f, 1f, 66f));
            l.Add(new V("pg_sideslope", 886f, 118f, 4f, 888f, 140f, 1f, 62f));
            l.Add(new V("pg_articulation", 850f, 50f, 3.2f, 850f, 90f, 0.5f, 60f));
            l.Add(new V("pg_ford", 846f, 170f, 3.2f, 850f, 208f, 0f, 62f));
            l.Add(new V("pg_logpile", 858f, 238f, 3.5f, 835f, 262f, 1.5f, 64f));
            l.Add(new V("pg_measure", 925f, 232f, 5f, 945f, 264f, 0f, 66f));
            return l;
        }

        // ------------------------------------------------------------------ scene setup

        static Camera MakeCamera()
        {
            var go = new GameObject("Main Camera") { tag = "MainCamera" };
            var c = go.AddComponent<Camera>();
            c.allowHDR = true; c.clearFlags = CameraClearFlags.Skybox; c.nearClipPlane = 0.1f; c.farClipPlane = 2500f; c.fieldOfView = 60f;
            var data = c.GetUniversalAdditionalCameraData();
            data.renderPostProcessing = true; data.antialiasing = AntialiasingMode.SubpixelMorphologicalAntiAliasing; data.antialiasingQuality = AntialiasingQuality.High;
            data.renderShadows = true; data.volumeLayerMask = ~0;
            return c;
        }

        static Light MakeSun(float el, float az)
        {
            var go = new GameObject("Sun");
            var l = go.AddComponent<Light>();
            l.type = LightType.Directional; l.color = new Color(1f, 0.93f, 0.82f); l.intensity = 2.6f; l.shadows = LightShadows.Soft; l.shadowStrength = 1f;
            l.transform.rotation = Quaternion.Euler(el, az, 0f);
            return l;
        }

        static void MakeSky(Light s)
        {
            var sky = new Material(Shader.Find("Skybox/Procedural"));
            sky.SetFloat("_SunSize", 0.045f); sky.SetFloat("_SunSizeConvergence", 5f); sky.SetFloat("_AtmosphereThickness", 1.05f);
            sky.SetColor("_SkyTint", new Color(0.5f, 0.5f, 0.5f)); sky.SetColor("_GroundColor", new Color(0.52f, 0.56f, 0.60f)); sky.SetFloat("_Exposure", 1.25f);
            RenderSettings.skybox = sky; RenderSettings.sun = s;
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.62f, 0.70f, 0.82f); RenderSettings.ambientEquatorColor = new Color(0.55f, 0.53f, 0.49f); RenderSettings.ambientGroundColor = new Color(0.30f, 0.27f, 0.23f);
            RenderSettings.ambientIntensity = 1f; RenderSettings.defaultReflectionMode = DefaultReflectionMode.Skybox; RenderSettings.reflectionIntensity = 1f;
            RenderSettings.fog = true; RenderSettings.fogMode = FogMode.ExponentialSquared; RenderSettings.fogDensity = 0.0009f; RenderSettings.fogColor = new Color(0.62f, 0.68f, 0.76f);
        }

        static void MakeVolume()
        {
            var go = new GameObject("PostFX");
            var vol = go.AddComponent<Volume>(); vol.isGlobal = true; vol.priority = 10;
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();
            var tm = profile.Add<Tonemapping>(true); tm.mode.Override(TonemappingMode.ACES);
            var bloom = profile.Add<Bloom>(true); bloom.intensity.Override(0.18f); bloom.threshold.Override(1.0f); bloom.scatter.Override(0.6f);
            var ca = profile.Add<ColorAdjustments>(true); ca.postExposure.Override(0.2f); ca.contrast.Override(6f); ca.saturation.Override(8f);
            var vig = profile.Add<Vignette>(true); vig.intensity.Override(0.18f);
            vol.sharedProfile = profile;
        }

        static void WaitShaders()
        {
            int guard = 0;
            while (ShaderUtil.anythingCompiling && guard++ < 60) System.Threading.Thread.Sleep(100);   // capped: the flag can stay true in batch mode
        }

        static Vector3 OnGround(Vector3 p)
        {
            float y = gw.map.SampleHeight(p.x, p.z) + gs.Field.SampleDh(p.x, p.z);
            return new Vector3(p.x, y + p.y, p.z);
        }

        static void Shoot(V v)
        {
            gs.wetness = v.wet;
            Shader.SetGlobalFloat("_MR_Wetness", v.wet);
            sun.transform.rotation = Quaternion.Euler(v.sunEl, v.sunAz, 0f);
            cam.fieldOfView = v.fov; cam.farClipPlane = v.far;
            cam.transform.position = OnGround(v.pos);
            Vector3 target = OnGround(v.look);
            cam.transform.rotation = Quaternion.LookRotation((target - cam.transform.position).normalized, Vector3.up);
            gs.Field.Recenter(cam.transform.position, true);
            gs.Field.SyncGpu(5000);
            WorldRuts.Apply(gs.Field, gw);      // re-apply after a recenter (stored tiles are idempotent: strongest wins)
            gs.Field.SyncGpu(5000);
            GroundRenderer.SetDebugMode(0);
            if (gr != null) gr.UpdateLod(true);
            var rt = new RenderTexture(Wpx, Hpx, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB) { antiAliasing = 1, name = "WorldCaptureRT" };
            rt.Create();
            cam.targetTexture = rt;
            Render(); Render();
            Render();
            string path = Path.Combine(CaptureDir, v.name + ".png");
            SavePng(rt, path);
            cam.targetTexture = null; rt.Release(); UnityEngine.Object.DestroyImmediate(rt);
            Debug.Log("[MudRunner] captured " + v.name + ".png cam=" + cam.transform.position.ToString("F0") + " props drawn=" + (handle.props != null ? handle.props.LastDrawnInstances : 0) + " calls=" + (handle.props != null ? handle.props.LastDrawCalls : 0) +
                      (gr != null ? " groundTris=" + gr.VisibleTriangleCount : ""));
        }

        static void Render()
        {
            if (handle.props != null) handle.props.Render(cam, true);
            cam.Render();
        }

        static void SavePng(RenderTexture rt, string path)
        {
            var prev = RenderTexture.active;
            RenderTexture.active = rt;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            tex.Apply();
            RenderTexture.active = prev;
            File.WriteAllBytes(path, tex.EncodeToPNG());
            UnityEngine.Object.DestroyImmediate(tex);
        }
    }
}
