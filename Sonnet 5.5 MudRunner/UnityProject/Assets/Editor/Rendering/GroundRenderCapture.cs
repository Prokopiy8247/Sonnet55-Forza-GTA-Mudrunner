using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using MudRunner.Ground;
using MudRunner.Rendering;
using MudRunner.Testing;
using Debug = UnityEngine.Debug;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Batch-mode capture + measurement harness for the ground renderer.
    ///   GFX=1 Tools/ub.sh groundcap MudRunner.EditorTools.GroundRenderCapture.Run
    /// Builds the showcase map, carves synthetic wheel tracks into the mud field, renders PNGs into Captures/ and prints
    /// [MudRunner] lines with timings (CPU ms of Camera.Render, GPU-synchronised ms, chunk / triangle counts, GC, LOD update cost).
    /// </summary>
    public static class GroundRenderCapture
    {
        const int Wpx = 1920, Hpx = 1080;
        const string MaterialAssetPath = "Assets/Game/Runtime/Rendering/Resources/MudRunner/GroundMaterial.mat";

        static string CaptureDir => Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Captures");

        // depth (m) a loaded wheel sinks on each surface type in the synthetic tracks (Rock .. Sand)
        static readonly float[] TrackDepth = { 0f, 0.05f, 0.07f, 0.03f, 0.17f, 0.30f, 0.40f, 0.10f };

        [MenuItem("MudRunner/Rendering/Run Ground Capture")]
        public static void Run()
        {
            try { RunInternal(); }
            catch (Exception e)
            {
                Debug.LogError("[MudRunner] GroundRenderCapture FAILED: " + e);
                if (Application.isBatchMode) EditorApplication.Exit(1);
            }
        }

        // ================================================================== main

        static void RunInternal()
        {
            Directory.CreateDirectory(CaptureDir);
            EnsureMaterialAsset();
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            SelectPcQuality();
            Debug.Log("[MudRunner] SystemInfo: " + SystemInfo.graphicsDeviceName + " / " + SystemInfo.graphicsDeviceType + " / pipeline=" + (GraphicsSettings.currentRenderPipeline != null ? GraphicsSettings.currentRenderPipeline.name : "none"));

            GroundTextures.DebugKeepReadable = true;

            // ---- world
            Debug.Log("[MudRunner] step: building showcase map");
            var map = TestArena.RenderShowcase(400f, 1f);
            var gs = TestArena.Install(map, new Vector3(0f, 0f, 0f), 0.3f);
            var rgo = new GameObject("GroundRenderer");
            var gr = rgo.AddComponent<GroundRenderer>();
            gr.buildFromGroundService = false;

            Debug.Log("[MudRunner] step: scene objects");
            var cam = MakeCamera();
            var sun = MakeSun(22f, 205f);
            MakeSky(sun);
            MakeVolume();
            var probe = MakeReflectionProbe();
            Debug.Log("[MudRunner] step: scene objects done, building renderer");
            gr.targetCamera = cam;

            var sw = Stopwatch.StartNew();
            gr.Build(map);
            Debug.Log("[MudRunner] GroundRenderer.Build(400x400 m, " + map.size + "^2 samples): " + sw.ElapsedMilliseconds + " ms, chunks=" + gr.ChunkCount);

            CarveTracks(gs.Field, map);
            gs.Field.SyncGpu(1000);
            Debug.Log("[MudRunner] Field: residentTiles=" + gs.Field.ResidentActiveTiles + " minDh=" + gs.Field.MinDh().ToString("F3") + " volume=" + gs.Field.ResidentVolume().ToString("F2") + " m3");

            DumpTextureAtlas();
            RenderProbe(probe);

            // ---- the captures
            var views = new View[]
            {
                // name, camera position (relative to ground) / target, sun elevation/azimuth, fov, wetness, debug
                new View { name = "dbg_overview_noshadow", pos = new Vector3(0f, 170f, -230f), look = new Vector3(15f, 0f, 20f), fov = 52f, sunEl = 30f, sunAz = 140f, wet = 0.3f, far = 3000f, noShadow = true },
                new View { name = "dbg_overview_normals", pos = new Vector3(0f, 170f, -230f), look = new Vector3(15f, 0f, 20f), fov = 52f, sunEl = 30f, sunAz = 140f, wet = 0.3f, far = 3000f, debug = 5 },
                new View { name = "ground_bands",      pos = new Vector3(0f, 48f, -78f),      look = new Vector3(0f, 0f, 0f),          fov = 50f, sunEl = 30f, sunAz = 140f, wet = 0.3f },
                new View { name = "ground_close_rut",  pos = new Vector3(2.0f, 1.5f, -4.0f),  look = new Vector3(15f, -0.35f, -4.0f), fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f },
                new View { name = "ground_wide",       pos = new Vector3(-30f, 7.0f, -30f),   look = new Vector3(20f, -1.2f, -2f),     fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f },
                new View { name = "ground_overview",   pos = new Vector3(0f, 170f, -230f),    look = new Vector3(15f, 0f, 20f),        fov = 52f, sunEl = 30f, sunAz = 140f, wet = 0.3f, far = 3000f },
                new View { name = "ground_lowsun",     pos = new Vector3(2.0f, 1.8f, -3.6f),  look = new Vector3(18f, -0.4f, -4.0f),   fov = 62f, sunEl = 6.5f, sunAz = 125f, wet = 0.3f },
                new View { name = "ground_puddles",    pos = new Vector3(3.0f, 1.6f, -4.0f),  look = new Vector3(18f, -0.4f, -4.0f),   fov = 62f, sunEl = 22f, sunAz = 140f, wet = 1.0f },
                new View { name = "ground_puddles_wide", pos = new Vector3(-26f, 6.0f, -26f), look = new Vector3(22f, -1.2f, 2f),     fov = 62f, sunEl = 22f, sunAz = 140f, wet = 1.0f },
                new View { name = "ground_spinhole",   pos = new Vector3(21.5f, 1.5f, -20.0f), look = new Vector3(24f, -1.4f, -14f),    fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f },
                new View { name = "ground_steep",      pos = new Vector3(95f, 3f, -20f),      look = new Vector3(140f, 6f, -8f),      fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f },
                new View { name = "ground_horizon",    pos = new Vector3(-20f, 2.2f, 0f),     look = new Vector3(200f, 8f, 20f),       fov = 70f, sunEl = 24f, sunAz = 140f, wet = 0.3f, far = 3000f },
                new View { name = "ground_debug_surface", pos = new Vector3(-30f, 14f, -50f), look = new Vector3(10f, -1f, 0f),        fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f, debug = 1 },
                new View { name = "ground_debug_dh",   pos = new Vector3(-8f, 9f, -10f),      look = new Vector3(18f, -1.2f, -5f),     fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f, debug = 2 },
                new View { name = "ground_debug_churn", pos = new Vector3(-8f, 9f, -10f),     look = new Vector3(18f, -1.2f, -5f),     fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f, debug = 3 },
                new View { name = "ground_debug_lod",  pos = new Vector3(-30f, 7.0f, -30f),   look = new Vector3(60f, -1.2f, 10f),     fov = 62f, sunEl = 24f, sunAz = 140f, wet = 0.3f, debug = 4, far = 3000f },
                new View { name = "ground_lodseam",    pos = new Vector3(-12f, 3.2f, -34f),   look = new Vector3(25f, -1.2f, 10f),     fov = 55f, sunEl = 20f, sunAz = 140f, wet = 0.3f },
            };

            // GR_ONLY="name1 name2" renders only matching views ("all" = every view, "perf" = measurements only). Default = core set.
            var only = Environment.GetEnvironmentVariable("GR_ONLY");
            string coreSet = "ground_bands ground_close_rut ground_wide ground_overview ground_lowsun ground_puddles ground_steep ground_debug_surface ground_debug_dh";
            string viewFilter = string.IsNullOrEmpty(only) ? coreSet : only;
            bool all = viewFilter.Contains("all");
            foreach (var v in views)
            {
                if (!all && !MatchesFilter(viewFilter, v.name)) continue;
                Shoot(v, cam, sun, gr, map, gs);
                if (!srpReported) { srpReported = true; ReportSrpBatcher(); }     // shader is compiled now
            }
            GroundRenderer.SetDebugMode(0);

            if (!string.IsNullOrEmpty(only) && only.Contains("perf"))
            {
                Measure(cam, sun, gr, map, gs);
                Stress2km(cam, sun);
            }
            Debug.Log("[MudRunner] GroundRenderCapture finished OK");
        }

        static bool MatchesFilter(string filter, string name)
        {
            foreach (var tok in filter.Split(new[] { ' ', ',', ';' }, StringSplitOptions.RemoveEmptyEntries))
                if (name.Contains(tok)) return true;
            return false;
        }

        // ================================================================== scene helpers

        struct View
        {
            public string name;
            public Vector3 pos;     // x,z world; y = metres above the (deformed) ground
            public Vector3 look;    // x,z world; y = metres above the ground at that spot
            public float fov, sunEl, sunAz, wet, far;
            public int debug;
            public bool noShadow;
        }

        static bool srpReported;

        static void ReportSrpBatcher()
        {
            try
            {
                var shader = AssetDatabase.LoadAssetAtPath<Shader>("Assets/Game/Shaders/Ground.shader");
                var t = typeof(ShaderUtil);
                var mCode = t.GetMethod("GetSRPBatcherCompatibilityCode", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
                var mWhy = t.GetMethod("GetSRPBatcherCompatibilityIssueReason", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
                if (mCode == null) { Debug.Log("[MudRunner] SRP Batcher check: API not found"); return; }
                var ps = mCode.GetParameters();
                string sig = "";
                foreach (var pi in ps) sig += pi.ParameterType.Name + " " + pi.Name + ", ";
                Debug.Log("[MudRunner] SRP Batcher API: GetSRPBatcherCompatibilityCode(" + sig + ")");
                if (ps.Length == 2)
                {
                    int code = (int)mCode.Invoke(null, new object[] { shader, 0 });
                    Debug.Log("[MudRunner] SRP Batcher compatibility code for Ground.shader subshader 0 (after compile): " + code + " (0 = compatible)");
                }
            }
            catch (Exception e) { Debug.Log("[MudRunner] SRP Batcher check failed: " + e.Message); }
        }

        static void SelectPcQuality()
        {
            string[] names = QualitySettings.names;
            for (int i = 0; i < names.Length; i++)
                if (names[i] == "PC") { QualitySettings.SetQualityLevel(i, true); return; }
        }

        static Camera MakeCamera()
        {
            var go = new GameObject("Main Camera") { tag = "MainCamera" };
            var cam = go.AddComponent<Camera>();
            cam.allowHDR = true;
            cam.clearFlags = CameraClearFlags.Skybox;
            cam.nearClipPlane = 0.1f;
            cam.farClipPlane = 1500f;
            cam.fieldOfView = 60f;
            var data = cam.GetUniversalAdditionalCameraData();
            data.renderPostProcessing = true;
            data.antialiasing = AntialiasingMode.SubpixelMorphologicalAntiAliasing;
            data.antialiasingQuality = AntialiasingQuality.High;
            data.renderShadows = true;
            data.volumeLayerMask = ~0;
            return cam;
        }

        static Light MakeSun(float elevation, float azimuth)
        {
            var go = new GameObject("Sun");
            var l = go.AddComponent<Light>();
            l.type = LightType.Directional;
            l.color = new Color(1f, 0.93f, 0.82f);
            l.intensity = 2.6f;
            l.shadows = LightShadows.Soft;
            l.shadowStrength = 1f;
            l.transform.rotation = Quaternion.Euler(elevation, azimuth, 0f);
            return l;
        }

        static void MakeSky(Light sun)
        {
            var sky = new Material(Shader.Find("Skybox/Procedural"));
            sky.SetFloat("_SunSize", 0.045f);
            sky.SetFloat("_SunSizeConvergence", 5f);
            sky.SetFloat("_AtmosphereThickness", 1.05f);
            sky.SetColor("_SkyTint", new Color(0.5f, 0.5f, 0.5f));
            sky.SetColor("_GroundColor", new Color(0.52f, 0.56f, 0.60f));
            sky.SetFloat("_Exposure", 1.25f);
            RenderSettings.skybox = sky;
            RenderSettings.sun = sun;
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.62f, 0.70f, 0.82f);
            RenderSettings.ambientEquatorColor = new Color(0.55f, 0.53f, 0.49f);
            RenderSettings.ambientGroundColor = new Color(0.30f, 0.27f, 0.23f);
            RenderSettings.ambientIntensity = 1f;
            RenderSettings.defaultReflectionMode = DefaultReflectionMode.Skybox;
            RenderSettings.reflectionIntensity = 1f;
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogDensity = 0.0009f;
            RenderSettings.fogColor = new Color(0.62f, 0.68f, 0.76f);
            DynamicGI.UpdateEnvironment();
        }

        static void MakeVolume()
        {
            var go = new GameObject("PostFX");
            var vol = go.AddComponent<Volume>();
            vol.isGlobal = true;
            vol.priority = 10;
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();
            var tm = profile.Add<Tonemapping>(true);
            tm.mode.Override(TonemappingMode.ACES);
            var bloom = profile.Add<Bloom>(true);
            bloom.intensity.Override(0.18f);
            bloom.threshold.Override(1.0f);
            bloom.scatter.Override(0.6f);
            var ca = profile.Add<ColorAdjustments>(true);
            ca.postExposure.Override(0.2f);
            ca.contrast.Override(6f);
            ca.saturation.Override(8f);
            var vig = profile.Add<Vignette>(true);
            vig.intensity.Override(0.18f);
            vol.sharedProfile = profile;
        }

        static ReflectionProbe MakeReflectionProbe()
        {
            var go = new GameObject("ReflectionProbe");
            go.transform.position = new Vector3(0f, 12f, 0f);
            var p = go.AddComponent<ReflectionProbe>();
            p.mode = ReflectionProbeMode.Realtime;
            p.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
            p.timeSlicingMode = ReflectionProbeTimeSlicingMode.NoTimeSlicing;
            p.resolution = 128;
            p.size = new Vector3(900f, 200f, 900f);
            p.boxProjection = false;
            p.hdr = true;
            p.cullingMask = 0;           // sky only
            p.clearFlags = ReflectionProbeClearFlags.Skybox;
            p.intensity = 1f;
            return p;
        }

        static void RenderProbe(ReflectionProbe p)
        {
            try { p.RenderProbe(); }
            catch (Exception e) { Debug.LogWarning("[MudRunner] reflection probe render failed: " + e.Message); }
        }

        static void EnsureMaterialAsset()
        {
            if (AssetDatabase.LoadAssetAtPath<Material>(MaterialAssetPath) != null) return;
            var shader = AssetDatabase.LoadAssetAtPath<Shader>("Assets/Game/Shaders/Ground.shader");
            if (shader == null) { Debug.LogError("[MudRunner] Ground.shader not imported"); return; }
            string dir = Path.GetDirectoryName(MaterialAssetPath);
            Directory.CreateDirectory(dir);
            AssetDatabase.Refresh();
            var mat = new Material(shader) { name = "GroundMaterial" };
            AssetDatabase.CreateAsset(mat, MaterialAssetPath);
            AssetDatabase.SaveAssets();
            Debug.Log("[MudRunner] created " + MaterialAssetPath);
        }

        // ================================================================== track carving

        static float TrackDepthAt(GroundMap map, float x, float z)
        {
            Span<float> w = stackalloc float[8];
            map.SampleWeights(x, z, w);
            float d = 0f;
            for (int k = 0; k < 8; k++) d += w[k] * TrackDepth[k];
            return d;
        }

        static void CarveWheelPath(MudField f, GroundMap map, IList<Vector2> pts, float lateral, float depthScale, float churn, float compact, float bermFrac, float stepLen = 0.11f, float rampLen = 2.5f, float halfWidth = 0.19f)
        {
            // resample polyline
            float acc = 0f; float total = 0f;
            for (int i = 1; i < pts.Count; i++) total += (pts[i] - pts[i - 1]).magnitude;
            float walked = 0f;
            for (int i = 1; i < pts.Count; i++)
            {
                Vector2 a = pts[i - 1], b = pts[i];
                float seg = (b - a).magnitude;
                if (seg < 1e-4f) continue;
                Vector2 dir = (b - a) / seg;
                Vector2 lat = new Vector2(-dir.y, dir.x);
                for (float s = 0f; s < seg; s += stepLen)
                {
                    Vector2 p = a + dir * s + lat * lateral;
                    float t = walked + s;
                    float ramp = Mathf.SmoothStep(0f, 1f, Mathf.Min(t / rampLen, (total - t) / rampLen));
                    float depth = TrackDepthAt(map, p.x, p.y) * depthScale * ramp;
                    if (depth < 0.004f && churn <= 0f) continue;
                    var op = new PatchOp
                    {
                        cx = p.x, cz = p.y, fx = dir.x, fz = dir.y,
                        halfWidth = halfWidth, halfLength = 0.26f,
                        depth = depth, moveSign = 1f, bermFrac = bermFrac, frontFrac = 0.12f, maxBerm = 0.30f,
                        churn = depth > 0.02f ? churn : 0f, compact = depth > 0.02f ? compact : 0f,
                    };
                    f.CarvePatch(op);
                }
                walked += seg;
            }
            acc += total;
        }

        static void CarveTracks(MudField f, GroundMap map)
        {
            const float track = 1.8f;
            // A: straight pair of ruts through all 8 surface bands
            var a = new List<Vector2> { new Vector2(-62f, -4f), new Vector2(62f, -4f) };
            CarveWheelPath(f, map, a, +track * 0.5f, 1f, 0.07f, 0.05f, 0.55f);
            CarveWheelPath(f, map, a, -track * 0.5f, 1f, 0.07f, 0.05f, 0.55f);

            // B: S-curve across the deep / shallow mud
            var b = new List<Vector2>();
            for (float z = -38f; z <= 38f; z += 1f) b.Add(new Vector2(20f + 9f * Mathf.Sin(z * 0.09f + 0.4f), z));
            CarveWheelPath(f, map, b, +track * 0.5f, 1.15f, 0.10f, 0.06f, 0.6f);
            CarveWheelPath(f, map, b, -track * 0.5f, 1.15f, 0.10f, 0.06f, 0.6f);

            // C: figure 8 of churned mud (3 laps, loosening, shallower)
            var c = new List<Vector2>();
            for (int lap = 0; lap < 3; lap++)
                for (float t = 0f; t <= Mathf.PI * 2f; t += 0.03f)
                    c.Add(new Vector2(25f + 12f * Mathf.Sin(t) + lap * 0.15f, 22f + 7f * Mathf.Sin(2f * t) + lap * 0.1f));
            CarveWheelPath(f, map, c, +track * 0.5f, 0.55f, 0.16f, -0.04f, 0.45f, 0.15f, 0.0f, 0.2f);
            CarveWheelPath(f, map, c, -track * 0.5f, 0.55f, 0.16f, -0.04f, 0.45f, 0.15f, 0.0f, 0.2f);

            // D: spun-out hole in the deep mud: four wheels dig in place, deeper every iteration
            Vector2 centre = new Vector2(24f, -14f);
            Vector2[] wheels = { new Vector2(-0.9f, -1.5f), new Vector2(0.9f, -1.5f), new Vector2(-0.9f, 1.5f), new Vector2(0.9f, 1.5f) };
            var rng = new System.Random(7);
            for (int it = 0; it < 60; it++)
            {
                float depth = Mathf.Lerp(0.08f, 0.62f, it / 59f);
                for (int wi = 0; wi < 4; wi++)
                {
                    float ang = it * 0.9f + wi;
                    Vector2 jitter = new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * 0.08f;
                    Vector2 p = centre + wheels[wi] + jitter;
                    f.CarvePatch(new PatchOp
                    {
                        cx = p.x, cz = p.y, fx = 1f, fz = 0f, halfWidth = 0.24f, halfLength = 0.36f,
                        depth = depth, moveSign = (it & 1) == 0 ? 1f : -1f, bermFrac = 0.65f, frontFrac = 0.2f, maxBerm = 0.34f,
                        churn = 0.10f, compact = -0.02f,
                    });
                }
            }

            // E: a short pair of ruts across grass / firm soil next to the basin (visible but shallow)
            var e = new List<Vector2> { new Vector2(-62f, 30f), new Vector2(-30f, 26f), new Vector2(-5f, 34f) };
            CarveWheelPath(f, map, e, +track * 0.5f, 1f, 0.04f, 0.05f, 0.5f);
            CarveWheelPath(f, map, e, -track * 0.5f, 1f, 0.04f, 0.05f, 0.5f);
        }

        // ================================================================== rendering

        static Vector3 OnGround(GroundMap map, MudField field, Vector3 p)
        {
            float y = map.SampleHeight(p.x, p.z) + field.SampleDh(p.x, p.z);
            return new Vector3(p.x, y + p.y, p.z);
        }

        static void WaitShaders()
        {
            // bounded: other editor activity (asset imports of other workers) can keep 'anythingCompiling' true for minutes
            int guard = 0;
            while (ShaderUtil.anythingCompiling && guard++ < 40) System.Threading.Thread.Sleep(100);
        }

        static void Shoot(View v, Camera cam, Light sun, GroundRenderer gr, GroundMap map, GroundService gs)
        {
            gs.wetness = v.wet;
            Shader.SetGlobalFloat("_MR_Wetness", v.wet);
            sun.transform.rotation = Quaternion.Euler(v.sunEl, v.sunAz, 0f);
            DynamicGI.UpdateEnvironment();
            cam.fieldOfView = v.fov;
            cam.farClipPlane = v.far > 0f ? v.far : 1500f;
            cam.transform.position = OnGround(map, gs.Field, v.pos);
            Vector3 target = OnGround(map, gs.Field, v.look);
            cam.transform.rotation = Quaternion.LookRotation((target - cam.transform.position).normalized, Vector3.up);
            GroundRenderer.SetDebugMode(v.debug);
            sun.shadows = v.noShadow ? LightShadows.None : LightShadows.Soft;
            gr.UpdateLod(true);

            var rt = new RenderTexture(Wpx, Hpx, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB) { antiAliasing = 1, name = "GroundCaptureRT" };
            rt.Create();
            cam.targetTexture = rt;
            // render a few times so async shader compilation / SSAO / probes settle
            WaitShaders();
            cam.Render();
            cam.Render();
            string path = Path.Combine(CaptureDir, v.name + ".png");
            SavePng(rt, path);
            cam.targetTexture = null;
            rt.Release(); UnityEngine.Object.DestroyImmediate(rt);
            Debug.Log("[MudRunner] captured " + v.name + ".png  chunks visible=" + gr.VisibleChunkCount + "/" + gr.ChunkCount + " tris=" + gr.VisibleTriangleCount +
                      " lod counts=" + gr.GetLodChunkCount(0) + "," + gr.GetLodChunkCount(1) + "," + gr.GetLodChunkCount(2) + "," + gr.GetLodChunkCount(3) + "," + gr.GetLodChunkCount(4) + " off=" + gr.GetLodChunkCount(5) +
                      " cam=" + cam.transform.position.ToString("F1") + " euler=" + cam.transform.eulerAngles.ToString("F1") + " groundAtCam=" + map.SampleHeight(cam.transform.position.x, cam.transform.position.z).ToString("F2"));
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

        // ================================================================== measurements

        static double TimeRenders(Camera cam, RenderTexture rt, int count, out double cpuMs)
        {
            var tex = new Texture2D(1, 1, TextureFormat.RGBA32, false);
            for (int w = 0; w < 6; w++) cam.Render();          // warm-up (GPU clocks, caches)
            RenderTexture.active = rt; tex.ReadPixels(new Rect(0, 0, 1, 1), 0, 0); RenderTexture.active = null;
            double cpuTotal = 0;
            var total = Stopwatch.StartNew();
            for (int i = 0; i < count; i++)
            {
                var s = Stopwatch.StartNew();
                cam.Render();
                s.Stop();
                cpuTotal += s.Elapsed.TotalMilliseconds;
            }
            // force GPU completion
            RenderTexture.active = rt;
            tex.ReadPixels(new Rect(0, 0, 1, 1), 0, 0);
            RenderTexture.active = null;
            total.Stop();
            UnityEngine.Object.DestroyImmediate(tex);
            cpuMs = cpuTotal / count;
            return total.Elapsed.TotalMilliseconds / count;
        }

        static void Measure(Camera cam, Light sun, GroundRenderer gr, GroundMap map, GroundService gs)
        {
            gs.wetness = 0.3f;
            Shader.SetGlobalFloat("_MR_Wetness", 0.3f);
            GroundRenderer.SetDebugMode(0);
            var rt = new RenderTexture(1920, 1080, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB) { antiAliasing = 1 };
            rt.Create();
            cam.targetTexture = rt;
            var views = new (string name, Vector3 pos, Vector3 look, float far)[]
            {
                ("close", new Vector3(2f, 1.5f, -4f), new Vector3(15f, -0.35f, -4f), 1500f),
                ("overview", new Vector3(0f, 170f, -230f), new Vector3(15f, 0f, 20f), 3000f),
            };
            foreach (var v in views)
            {
                cam.farClipPlane = v.far;
                cam.transform.position = OnGround(map, gs.Field, v.pos);
                cam.transform.rotation = Quaternion.LookRotation((OnGround(map, gs.Field, v.look) - cam.transform.position).normalized, Vector3.up);
                gr.UpdateLod(true);
                WaitShaders(); for (int i = 0; i < 3; i++) cam.Render();
                int tris = gr.VisibleTriangleCount, chunks = gr.VisibleChunkCount;

                // with ground
                double withCpu; double withWall = TimeRenders(cam, rt, 20, out withCpu);
                // ground chunks off (sky + nothing)
                SetChunks(gr, false);
                double offCpu; double offWall = TimeRenders(cam, rt, 20, out offCpu);
                SetChunks(gr, true);
                gr.UpdateLod(true);
                // shadows off
                var prevShadows = sun.shadows; sun.shadows = LightShadows.None;
                double nsCpu; double nsWall = TimeRenders(cam, rt, 20, out nsCpu);
                sun.shadows = prevShadows;
                Debug.Log("[MudRunner] PERF " + v.name + " @1080p: Camera.Render CPU " + withCpu.ToString("F2") + " ms, wall(GPU-synced) " + withWall.ToString("F2") +
                          " ms | without ground: CPU " + offCpu.ToString("F2") + " / wall " + offWall.ToString("F2") + " ms | no sun shadows: wall " + nsWall.ToString("F2") +
                          " ms | ground GPU cost ~ " + (withWall - offWall).ToString("F2") + " ms | chunks=" + chunks + " tris=" + tris);
            }

            // ---- GPU-bound measurement at 4K: the frame is GPU limited there, so the with/without-ground difference is real GPU cost
            cam.targetTexture = null;
            rt.Release(); UnityEngine.Object.DestroyImmediate(rt);
            var rt4 = new RenderTexture(3840, 2160, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB) { antiAliasing = 1 };
            rt4.Create();
            cam.targetTexture = rt4;
            foreach (var v in views)
            {
                cam.farClipPlane = v.far;
                cam.transform.position = OnGround(map, gs.Field, v.pos);
                cam.transform.rotation = Quaternion.LookRotation((OnGround(map, gs.Field, v.look) - cam.transform.position).normalized, Vector3.up);
                gr.UpdateLod(true);
                WaitShaders(); for (int i = 0; i < 2; i++) cam.Render();
                double c1; double with4k = TimeRenders(cam, rt4, 12, out c1);
                SetChunks(gr, false);
                double c2; double off4k = TimeRenders(cam, rt4, 12, out c2);
                SetChunks(gr, true);
                var prevSh = sun.shadows; sun.shadows = LightShadows.None;
                double c3; double nos4k = TimeRenders(cam, rt4, 12, out c3);
                sun.shadows = prevSh;
                Debug.Log("[MudRunner] PERF-4K " + v.name + " 3840x2160 (GPU-bound): frame with ground " + with4k.ToString("F2") + " ms, without ground " + off4k.ToString("F2") + " ms, with ground but sun shadows off " + nos4k.ToString("F2") +
                          " ms => ground cost ~ " + (with4k - off4k).ToString("F2") + " ms at 4K = ~" + ((with4k - off4k) / 4.0).ToString("F2") + " ms at 1080p (pixel-bound estimate)");
            }
            rt = new RenderTexture(1920, 1080, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB) { antiAliasing = 1 };
            rt.Create();
            cam.targetTexture = rt;

            // LOD update cost + GC
            cam.farClipPlane = 1500f;
            cam.transform.position = OnGround(map, gs.Field, new Vector3(0, 3, 0));
            gr.UpdateLod(true);
            var sw = Stopwatch.StartNew();
            int iters = 1000;
            long gc0 = GC.GetAllocatedBytesForCurrentThread();
            for (int i = 0; i < iters; i++)
            {
                cam.transform.position += new Vector3(0.05f, 0f, 0.02f);       // creep so LODs actually change sometimes
                gr.UpdateLod(false);
            }
            long gc1 = GC.GetAllocatedBytesForCurrentThread();
            sw.Stop();
            Debug.Log("[MudRunner] PERF UpdateLod(false) x" + iters + " (chunk budget/call ~" + Mathf.Max(32, 0) + "): avg " + (sw.Elapsed.TotalMilliseconds / iters * 1000.0).ToString("F1") + " us/call, GC alloc " + (gc1 - gc0) + " bytes");
            cam.targetTexture = null;
            rt.Release(); UnityEngine.Object.DestroyImmediate(rt);
        }

        static void SetChunks(GroundRenderer gr, bool on)
        {
            foreach (var mr in gr.GetComponentsInChildren<MeshRenderer>(true)) if (!on) mr.forceRenderingOff = true; else mr.forceRenderingOff = false;
        }

        /// <summary>2 km x 2 km map to validate chunk counts / LOD sweep cost at the maximum map size.</summary>
        static void Stress2km(Camera cam, Light sun)
        {
            var sw = Stopwatch.StartNew();
            var map = TestArena.CreateMap(2000f, 1f,
                (x, z) => 8f * Mathf.Sin(x * 0.004f) * Mathf.Cos(z * 0.005f) + 1.5f * Mathf.Sin(x * 0.03f + z * 0.02f),
                (x, z) => (SurfaceType)(Mathf.FloorToInt(Mathf.PerlinNoise(x * 0.01f + 50f, z * 0.01f + 50f) * 8f) & 7));
            long tMap = sw.ElapsedMilliseconds;
            var go = new GameObject("GroundRenderer2km");
            var gr = go.AddComponent<GroundRenderer>();
            gr.buildFromGroundService = false;
            gr.targetCamera = cam;
            cam.farClipPlane = 3000f;
            cam.transform.position = new Vector3(0f, 60f, 0f);
            cam.transform.rotation = Quaternion.Euler(20f, 30f, 0f);
            sw.Restart();
            gr.Build(map);
            long tBuild = sw.ElapsedMilliseconds;
            sw.Restart();
            for (int i = 0; i < 50; i++) gr.UpdateLod(true);
            double full = sw.Elapsed.TotalMilliseconds / 50.0;
            // time-sliced sweep: at 60 fps with 5 sweeps/s => n*dt*5 chunks per frame
            Debug.Log("[MudRunner] 2km map: map gen " + tMap + " ms, GroundRenderer.Build " + tBuild + " ms, chunks=" + gr.ChunkCount + ", visible=" + gr.VisibleChunkCount + ", tris=" + gr.VisibleTriangleCount +
                      "; full LOD sweep " + full.ToString("F3") + " ms => average per frame at 60 fps/5 Hz sweeps ~ " + (full / 12.0).ToString("F4") + " ms");
            var collSw = Stopwatch.StartNew();
            var terrain = GroundColliderBuilder.Create(map);
            Debug.Log("[MudRunner] GroundColliderBuilder.Create(2km): " + collSw.ElapsedMilliseconds + " ms, resolution=" + terrain.terrainData.heightmapResolution);
            GroundColliderBuilder.Destroy(terrain);
            UnityEngine.Object.DestroyImmediate(go);
        }

        // ================================================================== texture atlas dump

        static void DumpTextureAtlas()
        {
            var tex = GroundTextures.Shared;
            Debug.Log("[MudRunner] GroundTextures: " + tex.GenerationMs.ToString("F0") + " ms for " + tex.Size + "^2 x 8 (+macro, detail)");
            try
            {
                int tile = 512; int mip = 1;     // 1024 -> 512
                var alb = new Texture2D(tile * 4, tile * 2, TextureFormat.RGBA32, false);
                var nrm = new Texture2D(tile * 4, tile * 2, TextureFormat.RGBA32, false);
                for (int i = 0; i < 8; i++)
                {
                    var a = tex.Albedo.GetPixelData<Color32>(mip, i);
                    var n = tex.Normal.GetPixelData<Color32>(mip, i);
                    int ox = (i % 4) * tile, oy = (1 - i / 4) * tile;
                    var ac = new Color32[tile * tile];
                    var nc = new Color32[tile * tile];
                    for (int k = 0; k < tile * tile; k++)
                    {
                        ac[k] = new Color32(a[k].r, a[k].g, a[k].b, 255);
                        nc[k] = new Color32(n[k].r, n[k].g, 255, 255);
                    }
                    alb.SetPixels32(ox, oy, tile, tile, ac);
                    nrm.SetPixels32(ox, oy, tile, tile, nc);
                }
                File.WriteAllBytes(Path.Combine(CaptureDir, "ground_textures_albedo.png"), alb.EncodeToPNG());
                File.WriteAllBytes(Path.Combine(CaptureDir, "ground_textures_normal.png"), nrm.EncodeToPNG());
                // smoothness + height strips
                var sm = new Texture2D(tile * 4, tile * 2, TextureFormat.RGBA32, false);
                for (int i = 0; i < 8; i++)
                {
                    var a = tex.Albedo.GetPixelData<Color32>(mip, i);
                    var n = tex.Normal.GetPixelData<Color32>(mip, i);
                    int ox = (i % 4) * tile, oy = (1 - i / 4) * tile;
                    var sc = new Color32[tile * tile];
                    for (int k = 0; k < tile * tile; k++) sc[k] = new Color32(a[k].a, a[k].a, n[k].b, 255);   // R=G=smoothness, B=height
                    sm.SetPixels32(ox, oy, tile, tile, sc);
                }
                File.WriteAllBytes(Path.Combine(CaptureDir, "ground_textures_smooth_height.png"), sm.EncodeToPNG());
                // 2x2 tiling check of two layers (grass + gravel) at mip 1
                var tiling = new Texture2D(tile * 4, tile * 2, TextureFormat.RGBA32, false);
                int[] pick = { 2, 3 };
                for (int j = 0; j < 2; j++)
                {
                    var a = tex.Albedo.GetPixelData<Color32>(mip, pick[j]);
                    for (int ty = 0; ty < 2; ty++)
                        for (int tx = 0; tx < 2; tx++)
                        {
                            var ac = new Color32[tile * tile];
                            for (int k = 0; k < tile * tile; k++) ac[k] = new Color32(a[k].r, a[k].g, a[k].b, 255);
                            tiling.SetPixels32(j * tile * 2 + tx * tile, ty * tile, tile, tile, ac);
                        }
                }
                File.WriteAllBytes(Path.Combine(CaptureDir, "ground_textures_tiling.png"), tiling.EncodeToPNG());
                UnityEngine.Object.DestroyImmediate(alb); UnityEngine.Object.DestroyImmediate(nrm); UnityEngine.Object.DestroyImmediate(sm); UnityEngine.Object.DestroyImmediate(tiling);
            }
            catch (Exception e)
            {
                Debug.LogWarning("[MudRunner] texture atlas dump failed: " + e.Message);
            }
        }
    }
}
