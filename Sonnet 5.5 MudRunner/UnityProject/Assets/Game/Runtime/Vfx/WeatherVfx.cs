using MudRunner.Atmosphere;
using MudRunner.Ground;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.Vfx
{
    /// <summary>
    /// Rain: two GPU streak layers (a static mesh of camera facing quads animated entirely in the vertex shader of MudRunner/Rain, so no per-frame CPU work,
    /// near box 16 m + far box 60 m, thinned by intensity, slanted by the wind) plus pooled ground splashes / water rings around the camera
    /// emitted into the shared <see cref="ParticleHub"/>. Intensity follows <see cref="SkyController.Rain"/> (smoothed AtmosphereController.rain).
    /// </summary>
    public sealed class WeatherVfx : MonoBehaviour
    {
        const int Streaks = 2600;

        VfxDirector director;
        GameObject nearGo, farGo;
        Material nearMat, farMat;
        Mesh mesh;
        Vector3 prevCam, camVel;
        float accSplash;
        bool hasPrev;
        static readonly int IdCamVel = Shader.PropertyToID("_MR_CamVel");

        public float Intensity { get; private set; }
        public int SplashesThisFrame { get; private set; }

        public void Setup(VfxDirector d)
        {
            director = d;
            var sh = VfxResources.RainShader;
            if (sh == null) return;
            mesh = BuildMesh();
            nearMat = VfxResources.NewMaterial(sh, "VFX_RainNear");
            nearMat.SetVector("_Box", new Vector4(16f, 12f, 16f, 0f)); nearMat.SetVector("_Fall", new Vector4(9.5f, 0.6f, 0.011f, 0.30f));
            farMat = VfxResources.NewMaterial(sh, "VFX_RainFar");
            farMat.SetVector("_Box", new Vector4(60f, 28f, 60f, 0f)); farMat.SetVector("_Fall", new Vector4(10.5f, 1.6f, 0.03f, 0.16f));
            nearGo = MakeLayer("RainNear", nearMat);
            farGo = MakeLayer("RainFar", farMat);
        }

        GameObject MakeLayer(string name, Material m)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = m;
            mr.shadowCastingMode = ShadowCastingMode.Off; mr.receiveShadows = false;
            mr.lightProbeUsage = LightProbeUsage.Off; mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            mr.motionVectorGenerationMode = MotionVectorGenerationMode.ForceNoMotion;
            go.SetActive(false);
            return go;
        }

        static Mesh BuildMesh()
        {
            var rng = new System.Random(1234);
            var verts = new Vector3[Streaks * 4]; var cols = new Color32[Streaks * 4]; var uvs = new Vector2[Streaks * 4]; var tris = new int[Streaks * 6];
            for (int i = 0; i < Streaks; i++)
            {
                var seed = new Vector3((float)rng.NextDouble(), (float)rng.NextDouble(), (float)rng.NextDouble());
                var c = new Color32((byte)rng.Next(256), (byte)rng.Next(256), (byte)rng.Next(256), (byte)rng.Next(256));
                for (int k = 0; k < 4; k++)
                {
                    verts[i * 4 + k] = seed; cols[i * 4 + k] = c;
                    uvs[i * 4 + k] = new Vector2(k == 1 || k == 2 ? 1f : 0f, k >= 2 ? 1f : 0f);
                }
                int vi = i * 4, ti = i * 6;
                tris[ti] = vi; tris[ti + 1] = vi + 1; tris[ti + 2] = vi + 2; tris[ti + 3] = vi; tris[ti + 4] = vi + 2; tris[ti + 5] = vi + 3;
            }
            var m = new Mesh { name = "RainStreaks", hideFlags = HideFlags.DontSave };
            m.vertices = verts; m.colors32 = cols; m.uv = uvs; m.triangles = tris;
            m.bounds = new Bounds(Vector3.zero, Vector3.one * 100000f);
            return m;
        }

        public void Tick(float dt, Camera cam)
        {
            SplashesThisFrame = 0;
            var sky = director != null ? director.Sky : null;
            float target = sky != null ? sky.Rain : (AtmosphereController.Instance != null ? AtmosphereController.Instance.rain : 0f);
            Intensity = target;
            bool on = VfxDirector.Enabled && Intensity > 0.01f && cam != null;
            if (nearGo != null && nearGo.activeSelf != on) nearGo.SetActive(on);
            bool farOn = on && VfxDirector.Quality != VfxQuality.Low;
            if (farGo != null && farGo.activeSelf != farOn) farGo.SetActive(farOn);
            if (cam == null) { hasPrev = false; return; }

            Vector3 cp = cam.transform.position;
            if (hasPrev && dt > 1e-4f) camVel = Vector3.Lerp(camVel, (cp - prevCam) / dt, 0.2f);
            prevCam = cp; hasPrev = true;
            Shader.SetGlobalVector(IdCamVel, new Vector4(camVel.x, camVel.y, camVel.z, 0f));
            if (!on) return;

            // ground splashes / water rings around the camera focus
            var gs = GroundService.Instance;
            var hub = director.Hub;
            if (gs == null || gs.Map == null || hub == null) return;
            var water = gs.Map.water;
            float rate = Intensity * 150f * VfxDirector.Scale;
            accSplash += rate * dt;
            int n = Mathf.Min((int)accSplash, 12);
            accSplash -= (int)accSplash;
            Vector3 focus = cp + cam.transform.forward * 5f;
            for (int i = 0; i < n; i++)
            {
                Vector2 r = Random.insideUnitCircle * 12f;
                float x = focus.x + r.x, z = focus.z + r.y;
                float gy = gs.SurfaceHeight(x, z);
                float wl;
                if (water != null && water.Sample(x, z, out wl, out _) && wl > gy)
                {
                    hub.Emit(Fx.Ripple, new Vector3(x, wl + 0.02f, z), Vector3.zero, new Color32(235, 242, 246, 110), Random.Range(0.25f, 0.5f), Random.Range(0.6f, 1.0f));
                }
                else
                {
                    hub.Emit(Fx.SplashPuff, new Vector3(x, gy + 0.03f, z), Vector3.up * 0.4f, new Color32(215, 220, 226, 140), Random.Range(0.09f, 0.17f), Random.Range(0.25f, 0.4f));
                    for (int k = 0; k < 2; k++)
                        hub.Emit(Fx.Droplet, new Vector3(x, gy + 0.03f, z), new Vector3(Random.Range(-0.5f, 0.5f), Random.Range(1.2f, 2.4f), Random.Range(-0.5f, 0.5f)), new Color32(235, 242, 246, 255), Random.Range(0.012f, 0.026f), 0.35f);
                }
                SplashesThisFrame++;
            }
        }

        void OnDestroy()
        {
            if (nearMat != null) Destroy(nearMat);
            if (farMat != null) Destroy(farMat);
            if (mesh != null) Destroy(mesh);
        }
    }
}
