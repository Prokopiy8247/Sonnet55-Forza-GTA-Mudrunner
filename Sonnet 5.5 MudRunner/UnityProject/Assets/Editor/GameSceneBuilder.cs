using System.IO;
using MudRunner.CameraSystem;
using MudRunner.Game;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Creates the project scenes from code (reproducible, no hand-edited YAML).
    ///   Unity.exe -batchmode -nographics -projectPath ... -executeMethod MudRunner.EditorTools.GameSceneBuilder.BuildAllFromCli -quit
    /// </summary>
    public static class GameSceneBuilder
    {
        public const string GameScenePath = "Assets/Scenes/Game.unity";

        [MenuItem("MudRunner/Build/Create Game Scene")]
        public static void BuildGameScene()
        {
            Directory.CreateDirectory("Assets/Scenes");
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            // camera
            var camGo = new GameObject("Main Camera");
            camGo.tag = "MainCamera";
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.Skybox;
            cam.nearClipPlane = 0.2f; cam.farClipPlane = 2500f; cam.fieldOfView = 60f;
            camGo.AddComponent<AudioListener>();
            camGo.AddComponent<CameraRig>();      // replaces SimpleChaseCamera; the HUD / menus / debug window are created at runtime by UiBootstrap
            camGo.transform.position = new Vector3(0, 6, -110);
            camGo.transform.rotation = Quaternion.Euler(15, 0, 0);

            // sun
            var sunGo = new GameObject("Sun");
            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.color = new Color(1f, 0.95f, 0.85f);
            sun.intensity = 1.6f;
            sun.shadows = LightShadows.Soft;
            sunGo.transform.rotation = Quaternion.Euler(42f, -35f, 0f);
            RenderSettings.sun = sun;
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.45f, 0.55f, 0.65f);
            RenderSettings.ambientEquatorColor = new Color(0.35f, 0.38f, 0.35f);
            RenderSettings.ambientGroundColor = new Color(0.15f, 0.13f, 0.1f);
            RenderSettings.fog = true; RenderSettings.fogMode = FogMode.ExponentialSquared; RenderSettings.fogDensity = 0.0012f;
            RenderSettings.fogColor = new Color(0.62f, 0.68f, 0.72f);

            // bootstrap
            var boot = new GameObject("GameBootstrap").AddComponent<GameBootstrap>();
            boot.world = WorldKind.ProvingGround; boot.vehicle = "utility"; boot.installUi = true; boot.showMainMenu = true;

            EditorSceneManager.SaveScene(scene, GameScenePath);
            SetBuildScenes();
            Debug.Log("[MudRunner] Game scene created at " + GameScenePath);
        }

        static void SetBuildScenes()
        {
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(GameScenePath, true) };
        }

        public static void BuildAllFromCli()
        {
            try
            {
                BuildGameScene();
                if (File.Exists("Assets/Scenes/SampleScene.unity")) { AssetDatabase.DeleteAsset("Assets/Scenes/SampleScene.unity"); }
                AssetDatabase.SaveAssets();
            }
            catch (System.Exception e) { Debug.LogError("[MudRunner] scene build failed: " + e); EditorApplication.Exit(1); }
        }
    }
}
