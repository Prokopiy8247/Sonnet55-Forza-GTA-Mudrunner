using System.Collections;
using System.Collections.Generic;
using MudRunner.CameraSystem;
using MudRunner.Game;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

namespace MudRunner.UI
{
    public enum UiAction { Pause, Map, Help, Physics, Fps, Debug, HideHud, Garage, Headlights, MinimapIn, MinimapOut }

    /// <summary>
    /// Owner of the whole UI layer: canvas + event system, HUD, menus, debug window. Maps hotkeys to <see cref="UiAction"/>s, gates the
    /// player's vehicle input while a modal UI is open, manages the cursor and the time scale.
    ///
    /// Keys: Esc pause/back, Tab map, H help, C camera, [ ] wheel, F1 or ` debug menu, F2 physics overlay, F3 FPS, F10 hide HUD (F5/F9 = quick save/load, SaveSystem),
    /// Enter garage, L headlights, - / = minimap zoom.
    /// </summary>
    [DefaultExecutionOrder(-60)]
    public sealed class UiRoot : MonoBehaviour
    {
        public static UiRoot Instance { get; private set; }

        public Canvas Canvas { get; private set; }
        public RectTransform Root { get; private set; }
        public Hud Hud { get; private set; }
        public MainMenu Main { get; private set; }
        public PauseMenu Pause { get; private set; }
        public GarageMenu Garage { get; private set; }
        public LoadingOverlay Loading { get; private set; }
        public DebugMenu DebugUi { get; private set; }
        public bool Built { get; private set; }

        readonly List<UiMenu> menus = new List<UiMenu>();
        bool wasBlocked, lastCursorFree = true, cursorInit;
        bool subscribed;
        GameManager subscribedTo;

        void Awake()
        {
            Instance = this;
            UiState.ResetAll();
            if (Mathf.Approximately(Time.timeScale, 1f)) UiState.BaseFixedDeltaTime = Time.fixedDeltaTime;
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
            if (subscribedTo != null) subscribedTo.WorldLoaded -= OnWorldLoaded;
            ObjectiveBridge.Unhook();
            UiTime.Reset();
            Cursor.visible = true; Cursor.lockState = CursorLockMode.None;
            UiState.ResetAll();
            WorldMapTexture.Release();
        }

        // ------------------------------------------------------------------ build

        public void Build()
        {
            if (Built) return;
            Built = true;
            UiAssets.Get(UiFont.Body);
            var cgo = new GameObject("UI Canvas", typeof(RectTransform));
            cgo.layer = 5;
            cgo.transform.SetParent(transform, false);
            Canvas = cgo.AddComponent<Canvas>();
            Canvas.renderMode = RenderMode.ScreenSpaceOverlay; Canvas.sortingOrder = 50; Canvas.pixelPerfect = false;
            var scaler = cgo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(UiTheme.RefWidth, UiTheme.RefHeight);
            scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight; scaler.matchWidthOrHeight = 0.5f;
            cgo.AddComponent<GraphicRaycaster>();
            Root = UiFactory.NewRect("Root", cgo.transform);
            UiFactory.Fill(Root);

            EnsureEventSystem();

            Hud = gameObject.AddComponent<Hud>();
            Hud.Build(Canvas, Root);

            Main = new MainMenu(); Main.Build(Root); menus.Add(Main);
            Garage = new GarageMenu(); Garage.Build(Root); menus.Add(Garage);
            Pause = new PauseMenu(); Pause.Build(Root); menus.Add(Pause);
            Loading = new LoadingOverlay(); Loading.Build(Root); menus.Add(Loading);

            Main.onStart = (kind, sc) => StartGame(kind, sc);
            Main.onPreviewVehicle = PreviewVehicle;
            Pause.onReturnToMain = OpenMainMenu;

            DebugUi = gameObject.AddComponent<DebugMenu>();
            Main.RefreshVehicle();
            ObjectiveBridge.HookMessages();
        }

        static void EnsureEventSystem()
        {
            var es = EventSystem.current != null ? EventSystem.current : Object.FindAnyObjectByType<EventSystem>();
            if (es == null)
            {
                var go = new GameObject("EventSystem");
                es = go.AddComponent<EventSystem>();
            }
            var module = es.GetComponent<InputSystemUIInputModule>();
            if (module == null)
            {
                var old = es.GetComponent<StandaloneInputModule>();
                if (old != null) Object.Destroy(old);
                module = es.gameObject.AddComponent<InputSystemUIInputModule>();
            }
            // keyboard / gamepad navigation would fight the gameplay keys (WASD, Space, Enter, Esc): pointer only.
            module.move = null; module.submit = null; module.cancel = null;
        }

        // ------------------------------------------------------------------ per frame

        void Update()
        {
            FpsCounter.Tick();
            PollGameManager();
            HandleKeys();
            ApplyInputGate();
            ApplyCursor();
            float dt = Time.unscaledDeltaTime;
            for (int i = 0; i < menus.Count; i++) { menus[i].TickFade(dt); menus[i].Tick(dt); }
        }

        void PollGameManager()
        {
            var gm = GameManager.Instance;
            if (gm == subscribedTo) return;
            if (subscribedTo != null) subscribedTo.WorldLoaded -= OnWorldLoaded;
            subscribedTo = gm;
            if (gm != null)
            {
                gm.WorldLoaded += OnWorldLoaded;
                ObjectiveManager.EnsureInstance();      // free-drive objective card + objective toasts
                SaveSystem.EnsureInstance();            // F5 / F9 quick save / load
                if (gm.World != null) OnWorldLoaded(gm.World);
            }
        }

        void OnWorldLoaded(WorldData w)
        {
            MapTrail.Clear();
            EnsureGarageZone(w);
        }

        /// <summary>If the world builder did not create any garage zone, add one at the player start so the garage is usable.</summary>
        void EnsureGarageZone(WorldData w)
        {
            if (w == null || GarageZone.All.Count > 0) return;
            var go = new GameObject("Garage (fallback)");
            if (w.root != null) go.transform.SetParent(w.root.transform, true);
            go.transform.position = w.playerStart;
            var z = go.AddComponent<GarageZone>();
            z.displayName = "Start garage"; z.radius = 22f;
        }

        // ------------------------------------------------------------------ hotkeys

        void HandleKeys()
        {
            var kb = Keyboard.current; var pad = Gamepad.current;
            if (kb == null && pad == null) return;
            if (UiState.LoadingWorld) return;
            bool typing = UiState.TextFieldFocus;
            if (kb != null)
            {
                if (kb.f1Key.wasPressedThisFrame || (!typing && kb.backquoteKey.wasPressedThisFrame)) Perform(UiAction.Debug);
                if (typing) return;
                if (kb.escapeKey.wasPressedThisFrame) Perform(UiAction.Pause);
                if (kb.f10Key.wasPressedThisFrame) Perform(UiAction.HideHud);
                if (kb.f3Key.wasPressedThisFrame) Perform(UiAction.Fps);
                if (UiState.ModalOpen) return;
                if (kb.tabKey.wasPressedThisFrame) Perform(UiAction.Map);
                if (kb.hKey.wasPressedThisFrame) Perform(UiAction.Help);
                if (kb.f2Key.wasPressedThisFrame) Perform(UiAction.Physics);
                if (kb.enterKey.wasPressedThisFrame || kb.numpadEnterKey.wasPressedThisFrame) Perform(UiAction.Garage);
                if (kb.lKey.wasPressedThisFrame) Perform(UiAction.Headlights);
                if (kb.minusKey.wasPressedThisFrame || kb.numpadMinusKey.wasPressedThisFrame) Perform(UiAction.MinimapOut);
                if (kb.equalsKey.wasPressedThisFrame || kb.numpadPlusKey.wasPressedThisFrame) Perform(UiAction.MinimapIn);
            }
            if (pad != null && !typing)
            {
                if (pad.startButton.wasPressedThisFrame) Perform(UiAction.Pause);
                if (!UiState.ModalOpen && pad.selectButton.wasPressedThisFrame) Perform(UiAction.Map);
            }
        }

        /// <summary>Executes a UI hotkey action (also used by tests and the pause menu buttons).</summary>
        public void Perform(UiAction a)
        {
            if (!Built) return;
            var gm = GameManager.Instance;
            switch (a)
            {
                case UiAction.Pause:
                    if (UiState.LoadingWorld) return;
                    if (Main.IsOpen) { Main.OnBack(); return; }
                    if (Garage.IsOpen) { CloseGarage(); return; }
                    if (Hud.FullMap.IsOpen) { Hud.SetMapOpen(false); return; }
                    if (Hud.Help.IsOpen) { Hud.Help.Open(false); return; }
                    if (Pause.IsOpen) { if (!Pause.OnBack()) { Pause.Close(); ReleaseHandbrake(gm != null ? gm.Player : null); } return; }
                    if (gm != null && gm.Player != null) { ZeroVehicleInput(gm.Player, true); Pause.Open(); }
                    break;
                case UiAction.Map:
                    if (UiState.ModalOpen || gm == null || gm.Player == null) return;
                    Hud.ToggleMap(); break;
                case UiAction.Help:
                    if (UiState.ModalOpen) return;
                    Hud.ToggleHelp(); break;
                case UiAction.Physics: Hud.TogglePhysicsOverlay(); break;
                case UiAction.Fps: UiState.ShowFps = !UiState.ShowFps; break;
                case UiAction.Debug: DebugUi.Toggle(); break;
                case UiAction.HideHud: UiState.HudHidden = !UiState.HudHidden; break;
                case UiAction.Garage:
                    if (UiState.ModalOpen || gm == null || gm.Player == null) return;
                    var z = GarageZone.Find(gm.Player.transform.position);
                    if (z != null) OpenGarage(z);
                    break;
                case UiAction.Headlights:
                    if (gm == null || gm.Player == null) return;
                    ToggleHeadlights(gm.Player); break;
                case UiAction.MinimapIn: Hud.Minimap.ZoomStep(-1); break;
                case UiAction.MinimapOut: Hud.Minimap.ZoomStep(+1); break;
            }
        }

        public static VehicleHeadlights ToggleHeadlights(Vehicle v)
        {
            if (v == null) return null;
            var h = v.GetComponent<VehicleHeadlights>(); if (h == null) h = v.gameObject.AddComponent<VehicleHeadlights>();
            h.Toggle();
            return h;
        }

        // ------------------------------------------------------------------ input gate + cursor

        void ApplyInputGate()
        {
            var gm = GameManager.Instance; if (gm == null) return;
            bool block = UiState.VehicleInputBlocked;
            var pi = gm.PlayerInput;
            if (pi != null && pi.inputEnabled == block) pi.inputEnabled = !block;
            if (block != wasBlocked)
            {
                wasBlocked = block;
                if (block && gm.Player != null) ZeroVehicleInput(gm.Player, UiState.ModalOpen);
            }
        }

        static void ReleaseHandbrake(Vehicle v) { if (v == null) return; var i = v.input; i.handbrake = false; v.input = i; }

        public static void ZeroVehicleInput(Vehicle v, bool holdBrake)
        {
            if (v == null) return;
            var i = v.input; i.throttle = 0f; i.brake = 0f; i.steer = 0f; i.handbrake = holdBrake; v.input = i;
        }

        void ApplyCursor()
        {
            bool free = UiState.CursorFree;
            if (!cursorInit || free != lastCursorFree)
            {
                cursorInit = true; lastCursorFree = free;
                Cursor.visible = free;
                Cursor.lockState = free ? CursorLockMode.None : CursorLockMode.Locked;
            }
        }

        // ------------------------------------------------------------------ menus / flows

        public void OpenMainMenu()
        {
            var gm = GameManager.Instance;
            if (Pause.IsOpen) Pause.Close();
            if (Garage.IsOpen) Garage.Close();
            Hud.SetMapOpen(false); Hud.Help.Open(false);
            if (gm != null && gm.Player != null) ZeroVehicleInput(gm.Player, true);
            Main.Open();
            CameraRig.Instance?.SetMode(CameraMode.Showcase);
        }

        public void CloseMainMenu()
        {
            Main.Close();
            var rig = CameraRig.Instance;
            if (rig != null) { rig.SetMode(CameraMode.Chase, true); rig.Snap(); }
            var gm = GameManager.Instance;
            if (gm != null && gm.Player != null) { var i = gm.Player.input; i.handbrake = false; gm.Player.input = i; }
        }

        public void OpenGarage(GarageZone z)
        {
            var gm = GameManager.Instance;
            if (gm != null && gm.Player != null) ZeroVehicleInput(gm.Player, true);
            Hud.SetMapOpen(false);
            Garage.Open(z);
        }

        public void CloseGarage()
        {
            Garage.Close();
            var gm = GameManager.Instance;
            if (gm != null && gm.Player != null) { var i = gm.Player.input; i.handbrake = false; gm.Player.input = i; }
        }

        void PreviewVehicle(string key)
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.World == null) return;
            if (gm.Player != null && gm.Player.def == GameManager.GetDefinition(key)) return;
            gm.SwitchPlayerVehicle(key);
            ZeroVehicleInput(gm.Player, true);
            CameraRig.Instance?.Snap();
        }

        public Coroutine StartGame(WorldKind kind, ScenarioDef scenario)
        {
            return StartCoroutine(StartGameRoutine(kind, scenario));
        }

        IEnumerator StartGameRoutine(WorldKind kind, ScenarioDef sc)
        {
            var gm = GameManager.Instance;
            if (gm == null) yield break;
            string key = sc != null ? sc.vehicle : GameSession.VehicleKey;
            GameSession.Selected = sc; GameSession.World = kind; GameSession.VehicleKey = key;
            bool needWorld = gm.World == null || gm.World.kind != kind || sc != null;
            if (needWorld)
            {
                Loading.Show((sc != null ? sc.title.ToUpperInvariant() : kind == WorldKind.Wilderness ? "WILDERNESS" : "PROVING GROUND"));
                yield return null; yield return null;
                MapMarkers.Clear(); MapTrail.Clear(); GarageZone.All.RemoveAll(g => g == null);
                gm.StartWorld(kind, key);
                yield return null;
            }
            else if (gm.Player == null || gm.Player.def != GameManager.GetDefinition(key)) gm.SwitchPlayerVehicle(key);
            EnsureGarageZone(gm.World);
            if (sc != null && gm.World != null && gm.Player != null && ObjectiveBridge.TryResolveSite(sc.startSite, out Vector3 startPos, out float startYaw)
                && (new Vector2(startPos.x - gm.Player.transform.position.x, startPos.z - gm.Player.transform.position.z)).magnitude > 40f)
                gm.TeleportPlayer(startPos, startYaw);
            if (sc != null) { if (!ObjectiveBridge.StartScenario(sc)) Debug.LogWarning("[MudRunner] could not start scenario " + sc.id); }
            else ObjectiveBridge.StartFreeDrive();
            Loading.Hide();
            CloseMainMenu();
            GameSession.RaiseStarted();
            Hud.Notify(sc != null ? "Scenario: " + sc.title : "Free drive — " + (kind == WorldKind.Wilderness ? "Wilderness" : "Proving ground"), 3.5f);
            Hud.ShowHelpTemporarily(10f);
        }

        public static void QuitGame()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }
    }

    /// <summary>Entry point used by <see cref="GameBootstrap"/> and the scene builder: installs the camera rig and the UI.</summary>
    public static class UiBootstrap
    {
        /// <summary>Idempotent. Installs <see cref="CameraRig"/> on the main camera (removing SimpleChaseCamera) and creates the UI.</summary>
        public static UiRoot Install()
        {
            if (UiRoot.Instance != null) return UiRoot.Instance;
            var cam = Camera.main;
            if (cam == null)
            {
                var cgo = new GameObject("Main Camera") { tag = "MainCamera" };
                cam = cgo.AddComponent<Camera>(); cgo.AddComponent<AudioListener>();
                cam.nearClipPlane = 0.25f; cam.farClipPlane = 2500f;
            }
            InstallCameraRig(cam);
            var go = new GameObject("UI");
            var ui = go.AddComponent<UiRoot>();
            ui.Build();
            return ui;
        }

        public static CameraRig InstallCameraRig(Camera cam)
        {
            var old = cam.GetComponent<SimpleChaseCamera>();
            if (old != null) { old.enabled = false; Object.Destroy(old); }
            var rig = cam.GetComponent<CameraRig>();
            if (rig == null) rig = cam.gameObject.AddComponent<CameraRig>();
            return rig;
        }
    }
}
