using System;
using System.Collections;
using System.Collections.Generic;
using MudRunner.CameraSystem;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Testing;
using MudRunner.UI;
using MudRunner.Vehicles;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace MudRunner.Tests
{
    /// <summary>
    /// UI + camera verification. Functional tests assert behaviour (HUD built, camera modes, debug actions, menus).
    /// <see cref="Capture_AllViews"/> additionally writes Captures/ui_*.png for human review (needs graphics: GFX=1 Tools/rt.sh ui1 UiTests).
    /// </summary>
    public class UiTests
    {
        readonly List<string> logErrors = new List<string>();

        [SetUp]
        public void SetUp()
        {
            Time.captureFramerate = 60;
            GameSession.ShowMainMenuOnStart = false;
            GameSession.ShowHelpOnStart = false;
            GameSession.Selected = null;
            logErrors.Clear();
            Application.logMessageReceived += OnLog;
        }

        [TearDown]
        public void TearDown()
        {
            Application.logMessageReceived -= OnLog;
            Time.captureFramerate = 0;
            Time.timeScale = 1f; Time.fixedDeltaTime = 0.01f; AudioListener.pause = false;
            LogAssert.ignoreFailingMessages = false;
            GameSession.ShowMainMenuOnStart = true; GameSession.ShowHelpOnStart = true;
        }

        void OnLog(string msg, string stack, LogType type)
        {
            if (type == LogType.Exception || type == LogType.Error || type == LogType.Assert) logErrors.Add(type + ": " + msg);
        }

        // ------------------------------------------------------------------ helpers

        static IEnumerator LoadGame()
        {
            var op = SceneManager.LoadSceneAsync("Game");
            while (!op.isDone) yield return null;
            yield return null; yield return null;
            yield return Wait(0.3f);
        }

        static IEnumerator Wait(float seconds)
        {
            float t0 = Time.unscaledTime;
            while (Time.unscaledTime - t0 < seconds) yield return null;
        }

        static IEnumerator WaitGame(float seconds)
        {
            float t0 = Time.time;
            while (Time.time - t0 < seconds) yield return null;
        }

        static IEnumerator StartFreeDrive(WorldKind kind)
        {
            UiRoot.Instance.StartGame(kind, null);
            float t0 = Time.unscaledTime;
            while ((UiState.LoadingWorld || UiState.MainMenuOpen) && Time.unscaledTime - t0 < 30f) yield return null;
            yield return Wait(0.5f);
        }

        static BotDriver Drive(Vehicle v, float speed)
        {
            var b = v.GetComponent<BotDriver>(); if (b == null) b = v.gameObject.AddComponent<BotDriver>();
            b.vehicle = v; b.targetSpeed = speed; b.tractionControl = true; b.holdBrake = false; b.useWaypoints = false;
            return b;
        }

        static bool HasGraphics => SystemInfo.graphicsDeviceType != GraphicsDeviceType.Null;

        // ------------------------------------------------------------------ diagnostics

        [UnityTest, Timeout(300000)]
        public IEnumerator Diag_MaskDeactivation_Report()
        {
            LogAssert.ignoreFailingMessages = true;
            var cases = new[]
            {
                (n: "rect_image", rect: true, lines: false, arc: false, img: true, first: false),
                (n: "rect_lines", rect: true, lines: true, arc: false, img: false, first: false),
                (n: "rect_arc", rect: true, lines: false, arc: true, img: false, first: false),
                (n: "rect_all_inactive_first", rect: true, lines: true, arc: true, img: true, first: true),
                (n: "stencil_all", rect: false, lines: true, arc: true, img: true, first: false),
            };
            foreach (var c in cases)
            {
                logErrors.Clear();
                UiDiag.BuildMaskCase(c.n, c.rect, c.lines, c.arc, c.img, c.first, out GameObject go);
                yield return null; yield return null;
                go.SetActive(false); yield return null; go.SetActive(true); yield return null; go.SetActive(false); yield return null;
                Debug.Log("[MudRunner] DIAG mask case " + c.n + ": " + logErrors.Count + " error log(s)" + (logErrors.Count > 0 ? " first: " + logErrors[0].Substring(0, Mathf.Min(140, logErrors[0].Length)) : ""));
                UnityEngine.Object.Destroy(go.transform.parent.gameObject);
            }
            logErrors.Clear();
            LogAssert.ignoreFailingMessages = false;
        }

        // ------------------------------------------------------------------ boot + HUD

        [UnityTest, Timeout(300000)]
        public IEnumerator Boot_InstallsRigAndUi_AndMainMenuIsOptional()
        {
            GameSession.ShowMainMenuOnStart = true;
            yield return LoadGame();
            Assert.IsNotNull(UiRoot.Instance, "UiRoot");
            Assert.IsNotNull(Hud.Instance, "Hud");
            Assert.IsNotNull(CameraRig.Instance, "CameraRig");
            Assert.IsNotNull(DebugMenu.Instance, "DebugMenu");
            Assert.IsNull(Camera.main.GetComponent<SimpleChaseCamera>(), "SimpleChaseCamera must have been replaced");
            Assert.IsTrue(UiState.MainMenuOpen, "main menu opens at boot");
            Assert.AreEqual(CameraMode.Showcase, CameraRig.Instance.Mode, "showcase camera behind the menu");
            Assert.IsNotNull(GameManager.Instance.Player, "the world runs behind the menu");
            Assert.IsFalse(GameManager.Instance.PlayerInput != null && GameManager.Instance.PlayerInput.inputEnabled, "no driving behind the menu");
            Assert.Greater(Hud.Instance.CountGraphics(), 200, "HUD + menus build a few hundred uGUI graphics");
            // start a free drive from the menu
            yield return StartFreeDrive(WorldKind.ProvingGround);
            Assert.IsFalse(UiState.MainMenuOpen);
            Assert.AreEqual(CameraMode.Chase, CameraRig.Instance.Mode);
            Assert.IsTrue(GameManager.Instance.PlayerInput.inputEnabled, "driving enabled after starting");
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        [UnityTest, Timeout(300000)]
        public IEnumerator Hud_ElementsExist_AndTrackTheVehicle()
        {
            yield return LoadGame();
            var hud = Hud.Instance;
            Assert.IsNotNull(hud.Gauges); Assert.IsNotNull(hud.Status); Assert.IsNotNull(hud.Compass); Assert.IsNotNull(hud.Minimap); Assert.IsNotNull(hud.FullMap);
            Assert.IsNotNull(hud.Objective); Assert.IsNotNull(hud.Toasts); Assert.IsNotNull(hud.Help); Assert.IsNotNull(hud.Stuck); Assert.IsNotNull(hud.Winch);
            Assert.IsNotNull(hud.Physics); Assert.IsNotNull(hud.Gizmos); Assert.IsNotNull(hud.Stats); Assert.IsNotNull(hud.Prompt);
            var v = GameManager.Instance.Player;
            Assert.IsNotNull(v);
            Drive(v, 7f);
            yield return WaitGame(5f);
            Assert.IsTrue(hud.Visible, "HUD visible with a vehicle");
            Assert.IsFalse(string.IsNullOrEmpty(hud.Gauges.SpeedString));
            Assert.Greater(int.Parse(hud.Gauges.SpeedString), 3, "speedometer shows the speed (" + hud.Gauges.SpeedString + ", vehicle " + v.speedKmh.ToString("F1") + ")");
            Assert.Greater(int.Parse(hud.Gauges.RpmString), 300, "rpm read-out");
            Assert.IsTrue(hud.Gauges.GearString.Length > 0, "gear text");
            Assert.IsTrue(hud.Compass.HeadingString.EndsWith("°"), "compass heading " + hud.Compass.HeadingString);
            Assert.IsTrue(hud.Status.FuelString.EndsWith("L"), "fuel text " + hud.Status.FuelString);
            Assert.IsTrue(hud.Status.SurfaceString.Length > 0, "surface read-out");
            // notifications
            Hud.Notify("Test toast", 2f);
            yield return null; yield return null;
            Assert.GreaterOrEqual(hud.Toasts.ActiveCount, 1);
            Assert.AreEqual("Test toast", hud.Toasts.NewestText);
            // map texture builds in the background
            float t0 = Time.unscaledTime;
            while (!hud.Minimap.HasTexture && Time.unscaledTime - t0 < 10f) yield return null;
            Assert.IsTrue(hud.Minimap.HasTexture, "minimap texture generated");
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        [UnityTest, Timeout(300000)]
        public IEnumerator Hud_ControlHelp_And_MapToggle_And_Waypoint()
        {
            yield return LoadGame();
            var hud = Hud.Instance; var ui = UiRoot.Instance;
            hud.ShowHelpTemporarily(0.6f);
            yield return null;
            Assert.IsTrue(hud.Help.IsOpen, "help shows");
            yield return Wait(1.2f);
            Assert.IsFalse(hud.Help.IsOpen, "help hides itself");
            ui.Perform(UiAction.Help); yield return null;
            Assert.IsTrue(hud.Help.IsOpen); ui.Perform(UiAction.Help); Assert.IsFalse(hud.Help.IsOpen);

            ui.Perform(UiAction.Map); yield return null; yield return null;
            Assert.IsTrue(hud.FullMap.IsOpen); Assert.IsTrue(UiState.MapOpen); Assert.IsTrue(UiState.CursorFree);
            float t0 = Time.unscaledTime;
            while (!hud.FullMap.HasTexture && Time.unscaledTime - t0 < 10f) yield return null;
            Assert.IsTrue(hud.FullMap.HasTexture, "full map texture");
            var p = GameManager.Instance.Player.transform.position;
            MapMarkers.SetUserWaypoint(p + new Vector3(60f, 0f, 90f));
            yield return null; yield return null;
            Assert.IsNotNull(MapMarkers.UserWaypoint);
            ui.Perform(UiAction.Pause);       // Esc closes the map first
            Assert.IsFalse(hud.FullMap.IsOpen); Assert.IsFalse(UiState.PauseOpen, "Esc only closed the map");
            MapMarkers.SetUserWaypoint(null);
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        // ------------------------------------------------------------------ camera

        [UnityTest, Timeout(300000)]
        public IEnumerator Camera_ModesSwitch_WithBlend_AndStayInRange()
        {
            yield return LoadGame();
            var rig = CameraRig.Instance; var v = GameManager.Instance.Player;
            Assert.AreEqual(CameraMode.Chase, rig.Mode, "default chase");
            Drive(v, 5f);
            yield return WaitGame(2f);
            var cam = rig.Cam;
            float d = Vector3.Distance(cam.transform.position, v.transform.position);
            Assert.That(d, Is.InRange(4f, 20f), "chase distance " + d);
            Assert.That(cam.fieldOfView, Is.InRange(58f, 76f), "chase fov");

            rig.CycleMode(); Assert.AreEqual(CameraMode.Cockpit, rig.Mode);
            Assert.IsTrue(rig.IsBlending, "transition blends");
            yield return Wait(0.7f);
            Assert.IsFalse(rig.IsBlending, "blend done after 0.7 s");
            d = Vector3.Distance(cam.transform.position, v.transform.position);
            Assert.Less(d, 3.0f, "cockpit camera inside the vehicle footprint, d=" + d);
            Assert.That(cam.fieldOfView, Is.InRange(60f, 80f));

            rig.CycleMode(); Assert.AreEqual(CameraMode.Wheel, rig.Mode);
            yield return Wait(0.8f);
            var w = v.wheels[rig.SelectedWheel];
            d = Vector3.Distance(cam.transform.position, w.hubWorld);
            Assert.That(d, Is.InRange(1.4f, 4.8f), "wheel close-up distance to the hub " + d);
            int first = rig.SelectedWheel; rig.SelectWheel(1); Assert.AreNotEqual(first, rig.SelectedWheel, "wheel selection");
            rig.SetWheel(v.wheels.Length - 1); Assert.AreEqual(v.wheels.Length - 1, rig.SelectedWheel);
            yield return Wait(0.8f);
            d = Vector3.Distance(cam.transform.position, v.wheels[rig.SelectedWheel].hubWorld);
            Assert.That(d, Is.InRange(1.4f, 4.8f), "another wheel framed " + d);

            rig.CycleMode(); Assert.AreEqual(CameraMode.Top, rig.Mode);
            yield return Wait(0.8f);
            d = Vector3.Distance(cam.transform.position, v.transform.position);
            Assert.Greater(d, 14f, "top camera is far, d=" + d);
            Assert.Greater(cam.transform.position.y, v.transform.position.y + 10f, "top camera above the vehicle");

            rig.CycleMode(); Assert.AreEqual(CameraMode.Chase, rig.Mode, "cycle wraps");

            // free camera blocks the vehicle input and returns to the previous mode
            DebugActions.SetFreeCamera(true);
            yield return Wait(0.3f);
            Assert.AreEqual(CameraMode.Free, rig.Mode); Assert.IsTrue(UiState.FreeCamera);
            Assert.IsFalse(GameManager.Instance.PlayerInput.inputEnabled, "vehicle input paused in free camera");
            DebugActions.SetFreeCamera(false);
            yield return Wait(0.3f);
            Assert.AreEqual(CameraMode.Chase, rig.Mode); Assert.IsFalse(UiState.FreeCamera);
            Assert.IsTrue(GameManager.Instance.PlayerInput.inputEnabled);

            // chase zoom clamps to 4..20 m
            rig.SetZoom(100f); Assert.AreEqual(20f, rig.ChaseDistance, 0.01f);
            rig.SetZoom(0.5f); Assert.AreEqual(4f, rig.ChaseDistance, 0.01f);
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        [UnityTest, Timeout(300000)]
        public IEnumerator Camera_ChaseStaysAboveGround_AndFollowsTeleport()
        {
            yield return LoadGame();
            var rig = CameraRig.Instance; var gm = GameManager.Instance; var gs = GroundService.Instance;
            rig.SetZoom(6f);
            gm.TeleportPlayer(new Vector3(80f, 0f, 0f), 90f);     // onto the demo mud hill
            rig.Snap();
            yield return WaitGame(1.5f);
            var p = rig.transform.position;
            Assert.GreaterOrEqual(p.y, gs.SurfaceHeight(p.x, p.z) + 0.4f, "camera above the terrain");
            Assert.Less(Vector3.Distance(p, gm.Player.transform.position), 21f, "camera followed the teleport");
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        // ------------------------------------------------------------------ debug menu actions

        [UnityTest, Timeout(300000)]
        public IEnumerator DebugActions_ChangeTheExpectedValues()
        {
            yield return LoadGame();
            var gm = GameManager.Instance; var gs = GroundService.Instance;
            var v = gm.Player;

            DebugActions.SetMudDepth(2f); Assert.AreEqual(2f, gs.mudDepthScale, 1e-4f);
            DebugActions.SetMudDepth(9f); Assert.AreEqual(3f, gs.mudDepthScale, 1e-4f, "mud depth clamps to 3");
            DebugActions.SetMudDepth(0.01f); Assert.AreEqual(0.2f, gs.mudDepthScale, 1e-4f, "mud depth clamps to 0.2");
            DebugActions.SetSoftness(2.5f); Assert.AreEqual(2.5f, gs.softnessScale, 1e-4f);
            DebugActions.SetRutRelax(3f); Assert.AreEqual(3f, gs.rutRelaxScale, 1e-4f);
            DebugActions.SetWetness(0.8f); Assert.AreEqual(0.8f, gs.wetness, 1e-4f);
            DebugActions.ResetGroundTuning(); Assert.AreEqual(1f, gs.mudDepthScale);

            DebugActions.SetRain(true); Assert.Greater(DebugActions.Atmosphere().rain, 0.5f);
            DebugActions.SetRain(false); Assert.AreEqual(0f, DebugActions.Atmosphere().rain, 1e-4f);
            DebugActions.SetRainIntensity(0.4f); Assert.AreEqual(0.4f, DebugActions.Atmosphere().rain, 1e-4f);
            DebugActions.SetTimeOfDay(7.5f); Assert.AreEqual(7.5f, DebugActions.Atmosphere().hour, 1e-3f);
            DebugActions.SetTimeLapse(30f); Assert.AreEqual(30f, DebugActions.Atmosphere().minutesPerSecond, 1e-3f);
            DebugActions.SetTimeLapse(0f);

            float baseDt = UiState.BaseFixedDeltaTime;
            DebugActions.SetSlowMotion(0.25f);
            Assert.AreEqual(0.25f, Time.timeScale, 1e-4f); Assert.AreEqual(baseDt * 0.25f, Time.fixedDeltaTime, 1e-5f, "fixedDeltaTime follows timeScale");
            DebugActions.SetSlowMotion(0.1f); Assert.AreEqual(baseDt * 0.1f, Time.fixedDeltaTime, 1e-5f);
            DebugActions.SetSlowMotion(1f); Assert.AreEqual(1f, Time.timeScale); Assert.AreEqual(baseDt, Time.fixedDeltaTime, 1e-5f);

            // vehicle switching / spawning
            int vehiclesBefore = gm.Vehicles.Count;
            var hauler = DebugActions.SwitchVehicle("hauler");
            Assert.AreSame(hauler, gm.Player); Assert.AreEqual(GameManager.GetDefinition("hauler").displayName, gm.Player.def.displayName);
            yield return null; yield return null;
            Assert.AreEqual(vehiclesBefore, gm.Vehicles.Count, "switch replaces, does not add");
            var extra = DebugActions.SpawnVehicle("scout");
            Assert.IsNotNull(extra); Assert.AreEqual(vehiclesBefore + 1, gm.Vehicles.Count);
            Assert.AreNotSame(extra, gm.Player);
            Assert.AreEqual(1, DebugActions.RemoveOtherVehicles());
            DebugActions.SwitchVehicle("utility");
            yield return null; yield return null;
            v = gm.Player;

            // teleport
            Assert.IsTrue(DebugActions.TeleportToSpawn());
            yield return null;
            Assert.Less(Vector2.Distance(new Vector2(v.transform.position.x, v.transform.position.z), new Vector2(gm.World.playerStart.x, gm.World.playerStart.z)), 2f);
            var pt = gm.World.points[gm.World.points.Count - 1];
            Assert.IsTrue(DebugActions.TeleportToPoint(pt));
            yield return null;
            Assert.Less(Vector2.Distance(new Vector2(v.transform.position.x, v.transform.position.z), new Vector2(pt.position.x, pt.position.z)), 2f, "teleported to " + pt.name);

            // service
            v.fuel = 1f; v.damage01 = 0.6f;
            DebugActions.Refuel(); Assert.AreEqual(v.def.fuelCapacity, v.fuel, 1e-3f);
            DebugActions.Repair(); Assert.AreEqual(0f, v.damage01, 1e-6f);
            v.transform.rotation = Quaternion.Euler(0f, 0f, 170f); v.rb.rotation = v.transform.rotation;
            DebugActions.FlipReset();
            Assert.Greater(Vector3.Dot(v.transform.up, Vector3.up), 0.95f, "flip reset puts the vehicle upright");

            // drivetrain toggles
            bool awd = v.drivetrain.awd; DebugActions.ToggleAwd(); Assert.AreNotEqual(awd, v.drivetrain.awd);
            bool low = v.drivetrain.lowRange; DebugActions.ToggleLowRange(); Assert.AreNotEqual(low, v.drivetrain.lowRange);
            DebugActions.ToggleFrontLock(); Assert.IsTrue(v.drivetrain.axleLock[0]);
            DebugActions.ToggleRearLock(); Assert.IsTrue(v.drivetrain.axleLock[1]);
            DebugActions.ToggleCentreLock(); Assert.IsTrue(v.drivetrain.centreLock);
            bool eng = v.drivetrain.engineOn; DebugActions.ToggleEngine(); Assert.AreNotEqual(eng, v.drivetrain.engineOn); DebugActions.ToggleEngine();
            bool anchored = DebugActions.WinchAutoAnchor();
            Assert.AreEqual(anchored, v.winch.Attached, "auto-anchor result matches the winch state");
            DebugActions.WinchDetach(); Assert.IsFalse(v.winch.Attached);

            // trailer / cargo (real TrailerSystem) and the physics suite entry point
            Assert.IsTrue(DebugActions.SpawnTrailer(), "trailer attaches to the utility truck");
            yield return null; yield return null;
            Assert.IsNotNull(MudRunner.Cargo.TrailerSystem.Instance); Assert.IsTrue(MudRunner.Cargo.TrailerSystem.Instance.HasTrailer);
            Assert.IsTrue(DebugActions.LoadCargo("logs")); Assert.Greater(MudRunner.Cargo.TrailerSystem.Instance.CargoCount, 0, "logs loaded");
            DebugActions.ClearCargo(); Assert.AreEqual(0, MudRunner.Cargo.TrailerSystem.Instance.CargoCount);
            Assert.IsTrue(DebugActions.DetachTrailer()); yield return null; Assert.IsNull(MudRunner.Cargo.TrailerSystem.Instance.Hitch, "hitch released"); Assert.IsNull(v.towedTrailer, "vehicle no longer tows");
            Assert.IsNotNull(DebugActions.SuiteStatus(), "suite status string is available (the suite itself is not started here: it swaps the world)");

            // ground debug view
            DebugActions.SetGroundDebugView(1); Assert.AreEqual(1f, Shader.GetGlobalFloat("_MR_DebugMode"), 1e-4f);
            DebugActions.SetGroundDebugView(0); Assert.AreEqual(0f, Shader.GetGlobalFloat("_MR_DebugMode"), 1e-4f);

            // overlays
            Hud.Instance.SetPhysicsOverlay(true); yield return null; yield return null; Assert.IsTrue(UiState.PhysicsOverlay);
            UiState.ForceGizmos = true; yield return null; yield return null;
            Hud.Instance.SetPhysicsOverlay(false); UiState.ForceGizmos = false;
            LogAssert.ignoreFailingMessages = true;       // RunPhysicsSuite may legitimately log while missing
            Assert.IsEmpty(logErrors.FindAll(e => e.Contains("Exception")), string.Join("\n", logErrors));
        }

        [UnityTest, Timeout(300000)]
        public IEnumerator DebugMenu_TextFocusPausesVehicleInput_AndBenchmarkRuns()
        {
            yield return LoadGame();
            var dm = DebugMenu.Instance; var gm = GameManager.Instance;
            dm.SetOpen(true);
            yield return null; yield return null;
            Assert.IsTrue(UiState.DebugOpen); Assert.IsTrue(UiState.CursorFree);
            Assert.IsTrue(gm.PlayerInput.inputEnabled, "driving still possible with the window open");
            UiState.TextFieldFocus = true;                     // what OnGUI sets while a text field has focus
            yield return null; yield return null;
            Assert.IsFalse(gm.PlayerInput.inputEnabled, "vehicle input paused while typing");
            UiState.TextFieldFocus = false;
            yield return null; yield return null;
            Assert.IsTrue(gm.PlayerInput.inputEnabled);
            dm.Toggle(); Assert.IsFalse(UiState.DebugOpen);

            dm.benchmark.Start(1.0f, true);
            Assert.IsTrue(dm.benchmark.Running);
            yield return Wait(1.6f);
            Assert.IsFalse(dm.benchmark.Running); Assert.IsTrue(dm.benchmark.HasResult);
            Assert.Greater(dm.benchmark.Frames, 10); Assert.Greater(dm.benchmark.Avg, 1f); Assert.GreaterOrEqual(dm.benchmark.Avg, dm.benchmark.Low1);
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        // ------------------------------------------------------------------ menus

        [UnityTest, Timeout(300000)]
        public IEnumerator PauseMenu_FreezesTime_AndRestores()
        {
            yield return LoadGame();
            var ui = UiRoot.Instance; var gm = GameManager.Instance;
            ui.Perform(UiAction.Pause);
            Assert.IsTrue(UiState.PauseOpen); Assert.AreEqual(0f, Time.timeScale); Assert.IsTrue(gm.paused); Assert.IsTrue(UiState.CursorFree);
            yield return Wait(0.2f);
            Assert.IsFalse(gm.PlayerInput.inputEnabled);
            ui.Pause.ShowControlsPage(true);
            ui.Perform(UiAction.Pause);                         // closes the controls page first
            Assert.IsTrue(ui.Pause.IsOpen, "Esc leaves the controls page, not the menu");
            ui.Perform(UiAction.Pause);
            Assert.IsFalse(UiState.PauseOpen); Assert.AreEqual(1f, Time.timeScale); Assert.IsFalse(gm.paused);
            // slow motion survives a pause
            DebugActions.SetSlowMotion(0.5f); ui.Perform(UiAction.Pause); Assert.AreEqual(0f, Time.timeScale); ui.Perform(UiAction.Pause);
            Assert.AreEqual(0.5f, Time.timeScale, 1e-4f); DebugActions.SetSlowMotion(1f);
            // quality presets and volume do not throw
            foreach (QualityPreset q in Enum.GetValues(typeof(QualityPreset))) { UiQuality.Apply(q); Assert.AreEqual(q, UiQuality.Current); }
            UiQuality.Apply(QualityPreset.High);
            float vol = AudioListener.volume; AudioListener.volume = 0.5f; Assert.AreEqual(0.5f, AudioListener.volume, 1e-3f); AudioListener.volume = vol;
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        [UnityTest, Timeout(300000)]
        public IEnumerator GarageMenu_SwitchRefuelRepair()
        {
            yield return LoadGame();
            var ui = UiRoot.Instance; var gm = GameManager.Instance;
            Assert.Greater(GarageZone.All.Count, 0, "a garage zone exists (fallback at the start if the world has none)");
            var zone = GarageZone.All[0];
            gm.TeleportPlayer(zone.transform.position, 0f);
            yield return WaitGame(0.5f);
            var v = gm.Player; v.fuel = 5f; v.damage01 = 0.4f;
            ui.Perform(UiAction.Garage);
            Assert.IsTrue(UiState.GarageOpen, "Enter opens the garage inside the zone"); Assert.AreEqual(0f, Time.timeScale);
            ui.Garage.Refuel(); Assert.AreEqual(v.def.fuelCapacity, v.fuel, 1e-3f);
            ui.Garage.Repair(); Assert.AreEqual(0f, v.damage01, 1e-6f);
            ui.Garage.Switch("scout"); yield return Wait(0.1f);
            Assert.AreEqual(GameManager.GetDefinition("scout").displayName, gm.Player.def.displayName);
            ui.Perform(UiAction.Pause);                          // Esc closes the garage
            Assert.IsFalse(UiState.GarageOpen); Assert.AreEqual(1f, Time.timeScale);
            // outside the zone Enter does nothing
            gm.TeleportPlayer(zone.transform.position + new Vector3(zone.radius + 120f, 0f, 0f), 0f);
            yield return WaitGame(0.3f);
            if (GarageZone.Find(gm.Player.transform.position) == null) { ui.Perform(UiAction.Garage); Assert.IsFalse(UiState.GarageOpen); }
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        [Test]
        public void ScenarioCatalog_HasThreeEntries_WithValidVehicles()
        {
            Assert.GreaterOrEqual(ScenarioCatalog.All.Count, 3);
            foreach (var s in ScenarioCatalog.All)
            {
                Assert.IsFalse(string.IsNullOrEmpty(s.title)); Assert.IsFalse(string.IsNullOrEmpty(s.description));
                Assert.Contains(s.vehicle, GameManager.VehicleKeys, "vehicle key of " + s.title);
                Assert.IsNotNull(ScenarioCatalog.Find(s.id));
            }
            foreach (var k in GameManager.VehicleKeys)
            {
                var st = VehicleStats.From(k);
                Assert.Greater(st.mass, 500f); Assert.Greater(st.powerKw, 20f); Assert.Greater(st.tyreRadius, 0.2f); Assert.IsNotEmpty(st.Drive);
            }
        }

        [UnityTest, Timeout(300000)]
        public IEnumerator StuckWarning_FlashesWhenTheVehicleIsStuck_WithHints()
        {
            yield return LoadGame();
            var gm = GameManager.Instance; var v = gm.Player;
            UiState.ScriptedDriving = true; yield return null; yield return null;                  // keyboard driver off (a Keyboard device may exist in a graphics batch run)
            var i = v.input; i.throttle = 1f; i.handbrake = true; i.brake = 1f; v.input = i;      // both pedals + parking brake = "trying but not moving"
            float t0 = Time.time;
            while (!v.isStuck && Time.time - t0 < 8f) yield return null;
            Assert.IsTrue(v.isStuck, "vehicle reports stuck");
            yield return Wait(0.3f);
            Assert.IsTrue(Hud.Instance.Stuck.IsShowing, "stuck banner visible");
            i = v.input; i.throttle = 0f; i.handbrake = false; v.input = i;
            Assert.IsEmpty(logErrors, string.Join("\n", logErrors));
        }

        // ------------------------------------------------------------------ screenshots for human review

        [UnityTest, Timeout(600000)]
        public IEnumerator Capture_AllViews()
        {
            if (!HasGraphics) Assert.Ignore("needs a graphics device (run with GFX=1)");
            LogAssert.ignoreFailingMessages = true;            // keep going; errors are collected and asserted at the end
            GameSession.ShowMainMenuOnStart = true;
            yield return LoadGame();
            var ui = UiRoot.Instance; var hud = Hud.Instance; var rig = CameraRig.Instance;
            Debug.Log("[MudRunner] UI fonts: " + UiAssets.FontReport + "  screen " + Screen.width + "x" + Screen.height + " dpi " + Screen.dpi + " canvasScale " + ui.Canvas.scaleFactor
                + " kb=" + (UnityEngine.InputSystem.Keyboard.current != null) + " mouse=" + (UnityEngine.InputSystem.Mouse.current != null) + " gpu=" + SystemInfo.graphicsDeviceName);

            // ---- menus over the live world
            UiScreenshot.Trace("capture test start");
            yield return Wait(2.0f);
            UiScreenshot.Trace("step main_menu");
            yield return UiScreenshot.Capture("main_menu");
            ui.Main.ShowPage(MainMenu.Page.Vehicles); yield return Wait(0.3f);
            UiScreenshot.Trace("step main_menu_vehicle");
            yield return UiScreenshot.Capture("main_menu_vehicle");
            ui.Main.ShowPage(MainMenu.Page.Scenarios); yield return Wait(0.3f);
            UiScreenshot.Trace("step main_menu_scenarios");
            yield return UiScreenshot.Capture("main_menu_scenarios");
            ui.Main.ShowPage(MainMenu.Page.Home);

            // ---- drive
            yield return StartFreeDrive(WorldKind.ProvingGround);
            var gm = GameManager.Instance; var v = gm.Player;
            hud.ShowHelpTemporarily(0.1f);
            Drive(v, 7f);
            yield return WaitGame(7f);
            UiScreenshot.Trace("step hud_chase");
            yield return UiScreenshot.Capture("hud_chase");

            rig.SetMode(CameraMode.Cockpit); yield return Wait(1.0f);
            UiScreenshot.Trace("step cockpit");
            yield return UiScreenshot.Capture("cockpit");
            rig.SetMode(CameraMode.Wheel); rig.SetWheel(0); yield return Wait(1.0f);
            UiScreenshot.Trace("step wheel_closeup");
            yield return UiScreenshot.Capture("wheel_closeup");
            rig.SetWheel(3); yield return Wait(1.0f);
            UiScreenshot.Trace("step wheel_closeup_rear");
            yield return UiScreenshot.Capture("wheel_closeup_rear");
            rig.SetMode(CameraMode.Top); yield return Wait(1.0f);
            UiScreenshot.Trace("step top");
            yield return UiScreenshot.Capture("top");
            rig.SetMode(CameraMode.Chase); yield return Wait(1.0f);

            hud.SetPhysicsOverlay(true); yield return Wait(0.5f);
            UiScreenshot.Trace("step physics_overlay");
            yield return UiScreenshot.Capture("physics_overlay");
            UiState.ForceGizmos = true; yield return Wait(0.3f);
            UiScreenshot.Trace("step force_gizmos");
            yield return UiScreenshot.Capture("force_gizmos");
            hud.SetPhysicsOverlay(false); UiState.ForceGizmos = false;

            hud.SetMapOpen(true);
            float t0 = Time.unscaledTime;
            while (!hud.FullMap.HasTexture && Time.unscaledTime - t0 < 20f) yield return null;
            MapMarkers.SetUserWaypoint(v.transform.position + new Vector3(-70f, 0f, 120f));
            yield return Wait(0.6f);
            UiScreenshot.Trace("step full_map");
            yield return UiScreenshot.Capture("full_map");
            hud.SetMapOpen(false); MapMarkers.SetUserWaypoint(null);

            hud.Help.Open(true); yield return Wait(0.3f);
            UiScreenshot.Trace("step help");
            yield return UiScreenshot.Capture("help");
            hud.Help.Open(false);

            // ---- night + rain + headlights
            DebugActions.SetTimeOfDay(19.9f); DebugActions.SetRain(true); DebugActions.Atmosphere().overcast = 0.8f;
            UiRoot.ToggleHeadlights(v); Hud.Notify("Headlights test toast: night + rain", 6f);
            yield return Wait(2.0f);
            UiScreenshot.Trace("step hud_night_rain");
            yield return UiScreenshot.Capture("hud_night_rain");
            DebugActions.SetTimeOfDay(15.5f); DebugActions.SetRain(false); DebugActions.Atmosphere().overcast = 0.35f; UiRoot.ToggleHeadlights(v);

            // ---- winch card
            Destroy(v.GetComponent<BotDriver>());
            var ia = v.input; ia.throttle = 0f; ia.handbrake = true; v.input = ia;
            var post = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            post.name = "TestAnchor"; post.transform.localScale = new Vector3(0.5f, 1.2f, 0.5f);
            post.transform.position = v.transform.position + v.transform.forward * 11f + Vector3.up * 0.2f;
            post.AddComponent<WinchAnchor>();
            yield return Wait(0.6f);
            if (v.winch != null) v.winch.TryAutoAttach();
            if (v.winch != null) v.winch.input = 0f;
            yield return Wait(0.8f);
            UiScreenshot.Trace("step winch");
            yield return UiScreenshot.Capture("winch");
            if (v.winch != null) v.winch.Detach();
            Destroy(post);

            // ---- stuck: floor it against the handbrake
            UiState.ScriptedDriving = true; yield return null; yield return null;
            var is2 = v.input; is2.throttle = 1f; is2.brake = 1f; is2.handbrake = true; v.input = is2;
            t0 = Time.time;
            while (!v.isStuck && Time.time - t0 < 8f) yield return null;
            yield return Wait(0.5f);
            UiScreenshot.Trace("step stuck_warning");
            yield return UiScreenshot.Capture("stuck_warning");
            is2 = v.input; is2.throttle = 0f; is2.brake = 0f; is2.handbrake = false; v.input = is2; UiState.ScriptedDriving = false;

            // ---- low fuel + damage
            v.fuel = v.def.fuelCapacity * 0.07f; v.damage01 = 0.35f;
            yield return Wait(1.0f);
            UiScreenshot.Trace("step hud_lowfuel");
            yield return UiScreenshot.Capture("hud_lowfuel");
            v.fuel = v.def.fuelCapacity * 0.8f; v.damage01 = 0f;

            // ---- pause + controls
            ui.Perform(UiAction.Pause); yield return Wait(0.5f);
            UiScreenshot.Trace("step pause_menu");
            yield return UiScreenshot.Capture("pause_menu");
            ui.Pause.ShowControlsPage(true); yield return Wait(0.3f);
            UiScreenshot.Trace("step pause_controls");
            yield return UiScreenshot.Capture("pause_controls");
            ui.Perform(UiAction.Pause); ui.Perform(UiAction.Pause);

            // ---- garage
            if (GarageZone.All.Count > 0) gm.TeleportPlayer(GarageZone.All[0].transform.position, 0f);
            yield return WaitGame(1.0f);
            ui.Perform(UiAction.Garage); yield return Wait(0.5f);
            UiScreenshot.Trace("step garage");
            yield return UiScreenshot.Capture("garage");
            ui.Perform(UiAction.Pause);

            // ---- the other two vehicles in the chase view (HUD adapts: 6x6 gauges etc.)
            DebugActions.SwitchVehicle("hauler"); yield return WaitGame(2.5f);
            UiScreenshot.Trace("step hud_hauler");
            yield return UiScreenshot.Capture("hud_hauler");
            DebugActions.SwitchVehicle("scout"); yield return WaitGame(2.5f);
            UiScreenshot.Trace("step hud_scout");
            yield return UiScreenshot.Capture("hud_scout");

            // ---- IMGUI debug window: real back buffer (640x480 in batch mode), two scroll positions
            UiScreenshot.Trace("debug menu");
            UiState.ShowFps = true; UiState.ShowCoords = true;
            DebugMenu.Instance.SetOpen(true); yield return Wait(0.8f);
            yield return UiScreenshot.Capture("debug_menu", true);
            DebugMenu.Instance.scroll = new Vector2(0f, 420f); yield return Wait(0.3f);
            yield return UiScreenshot.Capture("debug_menu_2", true);
            DebugMenu.Instance.SetOpen(false); UiState.ShowFps = false; UiState.ShowCoords = false;

            Debug.Log("[MudRunner] UI capture finished; " + logErrors.Count + " error log(s)");
            foreach (var e in logErrors) Debug.Log("[MudRunner] UI capture error log: " + e);
            LogAssert.ignoreFailingMessages = false;
            Assert.IsEmpty(logErrors.FindAll(e => e.StartsWith("Exception") || e.Contains("NullReference")), string.Join("\n", logErrors));
        }

        static void Destroy(UnityEngine.Object o) { if (o != null) UnityEngine.Object.Destroy(o); }
    }
}
