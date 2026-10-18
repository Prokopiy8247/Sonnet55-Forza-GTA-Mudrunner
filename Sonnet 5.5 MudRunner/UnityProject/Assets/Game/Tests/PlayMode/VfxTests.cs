using System.Collections;
using System.IO;
using MudRunner.Atmosphere;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Rendering;
using MudRunner.Testing;
using MudRunner.Vehicles;
using MudRunner.Vfx;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace MudRunner.Tests
{
    /// <summary>VFX layer: installs, emits bounded mud spray from a spinning wheel, rain, sky; the Game scene gets it automatically. Writes Captures/vfx_mud_spin.png.</summary>
    public class VfxTests
    {
        [SetUp] public void SetUp() { Time.captureFramerate = 60; }

        [TearDown]
        public void TearDown()
        {
            Time.captureFramerate = 0;
            if (VfxDirector.Instance != null) Object.Destroy(VfxDirector.Instance.gameObject);
            if (GroundService.Instance != null) Object.Destroy(GroundService.Instance.gameObject);
        }

        [UnityTest]
        public IEnumerator Director_MudSpray_Rain_Bounded()
        {
            var map = TestArena.Flat(SurfaceType.DeepMud, 200f);
            var gs = TestArena.Install(map, Vector3.zero, 0.7f);
            var cam = new GameObject("Main Camera") { tag = "MainCamera" }.AddComponent<Camera>();
            cam.allowHDR = true; cam.clearFlags = CameraClearFlags.Skybox; cam.farClipPlane = 800f;
            GroundRenderer.Create(map, cam, false);
            var dir = VfxDirector.Install();
            var at = AtmosphereController.Instance;
            at.SetTime(18.3f); at.SetRain(0.8f);
            var def = GameManager.GetDefinition("utility");
            var a = def.axles[0];
            var v = VehicleFactory.Create(def, new Vector3(0f, gs.GroundHeight(0, 0) + (a.tire.radius - a.hubY) + 0.15f, 0f), Quaternion.identity);
            gs.focus = v.transform;
            int maxTotal = 0; long allocSum = 0; int allocN = 0; int maxBlobs = 0;
            for (int f = 0; f < 420; f++)
            {
                var i = v.input; i.throttle = 1f; i.handbrake = false; v.input = i;
                var p = v.transform.position;
                cam.transform.position = p + v.transform.right * 3.2f - v.transform.forward * 4.6f + Vector3.up * 1.5f;
                cam.transform.rotation = Quaternion.LookRotation((p + new Vector3(0, 0.5f, -1.6f)) - cam.transform.position, Vector3.up);
                yield return null;
                maxTotal = Mathf.Max(maxTotal, dir.Hub.TotalCount);
                maxBlobs = Mathf.Max(maxBlobs, dir.Hub.Count(Fx.MudBlob));
                if (f > 240) { allocSum += dir.LastTickAllocBytes; allocN++; }
            }
            Debug.Log("[MudRunner] VFX mud test: max live particles " + maxTotal + " (cap " + dir.Hub.TotalCap + "), mud blobs max " + maxBlobs + ", tick " + dir.LastTickMs.ToString("F3") +
                      " ms, avg tick alloc " + (allocN > 0 ? allocSum / allocN : 0) + " B, wheel mud intensity " + v.GetComponent<WheelVfx>().MudIntensity.ToString("F2") +
                      ", rain " + dir.Weather.Intensity.ToString("F2") + ", splashes/frame " + dir.Weather.SplashesThisFrame);
            Assert.Greater(maxBlobs, 5, "mud blobs were emitted");
            Assert.LessOrEqual(dir.Hub.Count(Fx.MudBlob), dir.Hub.Cap(Fx.MudBlob), "pool bounded");
            Assert.IsNotNull(RenderSettings.skybox, "skybox set");
            Assert.IsFalse(float.IsNaN(v.transform.position.x));
            var rt = new RenderTexture(1600, 900, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB); rt.Create();
            cam.targetTexture = rt; cam.Render(); cam.targetTexture = null;
            var prev = RenderTexture.active; RenderTexture.active = rt;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false); tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0); tex.Apply();
            RenderTexture.active = prev;
            string dirPath = Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Captures"); Directory.CreateDirectory(dirPath);
            File.WriteAllBytes(Path.Combine(dirPath, "vfx_mud_spin.png"), tex.EncodeToPNG());
            Object.Destroy(tex); rt.Release(); Object.Destroy(rt);
        }

        [UnityTest]
        public IEnumerator GameScene_InstallsVfx_Automatically()
        {
            var op = SceneManager.LoadSceneAsync("Game");
            while (!op.isDone) yield return null;
            for (int i = 0; i < 90; i++) yield return null;
            Assert.IsNotNull(VfxDirector.Instance, "VfxDirector installed by GameBootstrap");
            Assert.IsNotNull(AtmosphereController.Instance, "AtmosphereController exists");
            Assert.IsNotNull(RenderSettings.skybox, "skybox assigned");
            var gm = GameManager.Instance;
            Assert.IsNotNull(gm.Player.GetComponent<WheelVfx>(), "player vehicle has WheelVfx");
            Debug.Log("[MudRunner] VFX game scene: active vehicles " + VfxDirector.Instance.ActiveVehicles + ", water chunks " +
                      (VfxDirector.Instance.Water != null ? VfxDirector.Instance.Water.ChunkCount : 0) + ", tick " + VfxDirector.Instance.LastTickMs.ToString("F3") + " ms");
        }
    }
}
