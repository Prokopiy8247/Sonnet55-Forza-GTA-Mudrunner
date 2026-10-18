using System.Collections;
using System.IO;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Rendering;
using MudRunner.Testing;
using MudRunner.Vehicles;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace MudRunner.Tests
{
    /// <summary>
    /// Visual QA of the Blender-authored vehicles inside Unity (run with graphics: GFX=1 Tools/rt.sh veh1 VehicleShowcase).
    /// Drives each vehicle through mud and over rocks and writes Captures/veh_*.png so wheel pivots, materials and the
    /// articulating suspension parts can be inspected.
    /// </summary>
    public class VehicleShowcaseTests
    {
        Camera cam; Light sun; GroundRenderer gr; GameObject rocks;

        [SetUp] public void SetUp() { Time.captureFramerate = 30; }

        [TearDown]
        public void TearDown()
        {
            Time.captureFramerate = 0;
            foreach (var v in Vehicle.All.ToArray()) if (v != null) Object.Destroy(v.gameObject);
            if (gr != null) Object.Destroy(gr.gameObject);
            if (cam != null) Object.Destroy(cam.gameObject);
            if (sun != null) Object.Destroy(sun.gameObject);
            if (rocks != null) Object.Destroy(rocks);
            if (GroundService.Instance != null) Object.Destroy(GroundService.Instance.gameObject);
        }

        static readonly string[] Keys = { "scout", "utility", "hauler" };

        void Capture(string name, int w = 1280, int h = 720)
        {
            Directory.CreateDirectory("Captures");
            var rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32) { antiAliasing = 4 };
            var prev = cam.targetTexture; cam.targetTexture = rt; cam.Render(); cam.targetTexture = prev;
            var prevActive = RenderTexture.active; RenderTexture.active = rt;
            var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, w, h), 0, 0); tex.Apply();
            RenderTexture.active = prevActive;
            File.WriteAllBytes("Captures/" + name + ".png", tex.EncodeToPNG());
            Object.Destroy(tex); rt.Release(); Object.Destroy(rt);
            Debug.Log("[MudRunner] captured " + name + ".png");
        }

        void Place(Vector3 target, Vector3 offset, float fov = 45f)
        {
            cam.fieldOfView = fov;
            cam.transform.position = target + offset;
            cam.transform.rotation = Quaternion.LookRotation(target - cam.transform.position);
        }

        [UnityTest]
        public IEnumerator VehicleShowcase_Capture([ValueSource(nameof(Keys))] string key)
        {
            // world: firm start, shallow-mud field, rock course afterwards
            var map = TestArena.Strips((15f, 60f, SurfaceType.ShallowMud, 0f), (60f, 95f, SurfaceType.DeepMud, 0f));
            var gs = TestArena.Install(map, new Vector3(0, 0, -8f), 0.6f);
            var camGo = new GameObject("ShowcaseCam"); camGo.tag = "MainCamera"; cam = camGo.AddComponent<Camera>(); cam.farClipPlane = 800f; cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0.55f, 0.7f, 0.85f);
            var sunGo = new GameObject("ShowcaseSun"); sun = sunGo.AddComponent<Light>(); sun.type = LightType.Directional; sun.intensity = 1.8f; sun.shadows = LightShadows.Soft; sunGo.transform.rotation = Quaternion.Euler(38f, -50f, 0f);
            RenderSettings.sun = sun; RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.55f, 0.65f, 0.8f); RenderSettings.ambientEquatorColor = new Color(0.4f, 0.42f, 0.4f); RenderSettings.ambientGroundColor = new Color(0.2f, 0.17f, 0.12f);
            gr = GroundRenderer.Create(map, cam, withCollider: false);

            // rocks beside the mud field for the articulation shot
            rocks = new GameObject("Rocks");
            for (int i = 0; i < 6; i++)
            {
                var rk = GameObject.CreatePrimitive(PrimitiveType.Cube); rk.transform.SetParent(rocks.transform);
                float side = i % 2 == 0 ? -1f : 1f; rk.layer = GameLayers.Props;
                rk.transform.position = new Vector3(side * 0.8f, 0.1f, 100f + i * 4f); rk.transform.localScale = new Vector3(1.0f, 0.3f, 1.3f); rk.transform.rotation = Quaternion.Euler(0f, 15f * side, 0f);
            }

            var def = GameManager.GetDefinition(key);
            Vector3 start = new Vector3(0, 0, -8f);
            float gy = gs.GroundHeight(start.x, start.z);
            start.y = gy + 0.1f;
            var v = VehicleFactory.Create(def, start, Quaternion.identity);
            gs.focus = v.transform;
            var bot = v.gameObject.AddComponent<BotDriver>(); bot.vehicle = v;
            bot.holdBrake = true;
            yield return new WaitForSeconds(1.5f);
            yield return null;
            Vector3 p = v.transform.position;
            float len = def.bodySize.z;
            // 1. rest, three-quarter front / side
            Place(p + Vector3.up * 0.9f, new Vector3(-len * 0.95f, len * 0.28f, len * 0.95f)); Capture("veh_" + key + "_front34");
            Place(p + Vector3.up * 0.6f, new Vector3(-len * 1.25f, len * 0.12f, 0.2f), 40f); Capture("veh_" + key + "_side");
            Place(p + Vector3.up * 0.5f, new Vector3(len * 0.5f, -0.1f + 0.4f, -len * 0.85f), 55f); Capture("veh_" + key + "_rear34");

            // 2. drive through the shallow mud: ruts + sinking wheels
            bot.holdBrake = false; bot.targetSpeed = 3.0f; bot.tractionControl = true; veh = v;
            float t0 = Time.time;
            while (Time.time - t0 < 40f && v.transform.position.z < 45f) yield return null;
            p = v.transform.position;
            Place(p + Vector3.up * 0.5f, new Vector3(-len * 1.2f, len * 0.16f, -0.5f), 42f); Capture("veh_" + key + "_mud_side");
            Place(p + Vector3.up * 0.4f, new Vector3(-len * 0.6f, 0.9f, -len * 1.1f), 50f); Capture("veh_" + key + "_mud_rear34");
            // ruts left behind
            Place(new Vector3(p.x, 0f, p.z - len * 1.4f), new Vector3(-2.0f, 2.2f, -len * 0.9f), 55f); Capture("veh_" + key + "_ruts");

            // 3. rock course articulation
            bot.targetSpeed = 2.2f;
            t0 = Time.time;
            while (Time.time - t0 < 60f && v.transform.position.z < 103f) yield return null;
            // wait until a wheel is clearly compressed relative to its opposite wheel, then shoot
            float best = 0f; int tries = 0;
            while (tries < 140)
            {
                yield return null; tries++;
                float diff = 0f;
                for (int a = 0; a < def.axles.Length; a++) diff = Mathf.Max(diff, Mathf.Abs(v.wheels[a * 2].length - v.wheels[a * 2 + 1].length));
                if (diff > best) best = diff;
                if (diff > 0.12f && v.transform.position.z > 100f) break;
            }
            p = v.transform.position;
            Place(p + Vector3.up * 0.4f, new Vector3(-len * 0.1f, 0.35f, len * 1.15f), 52f); Capture("veh_" + key + "_articulation_front");
            Place(p + Vector3.up * 0.6f, new Vector3(-len * 1.1f, len * 0.1f, 0.5f), 45f); Capture("veh_" + key + "_articulation_side");
            Debug.Log("[MudRunner] SHOWCASE " + key + " max strut difference " + best.ToString("F2") + " m, final z=" + v.transform.position.z.ToString("F1"));
            Assert.Greater(v.transform.position.z, key == "hauler" ? 90f : 55f);   // scout / utility are expected to bog down in the deep-mud field
        }

        Vehicle veh;
    }
}
