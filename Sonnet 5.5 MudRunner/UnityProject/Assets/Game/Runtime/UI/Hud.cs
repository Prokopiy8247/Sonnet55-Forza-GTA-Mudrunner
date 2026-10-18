using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>
    /// The gameplay HUD (code-built uGUI): instrument cluster, status card, compass, minimap + full map, objective card, winch card,
    /// stuck warning, toasts, control help, physics overlay and force gizmos. Only visible while a player vehicle exists.
    /// </summary>
    [DefaultExecutionOrder(200)]
    public sealed class Hud : MonoBehaviour
    {
        public static Hud Instance { get; private set; }

        public Canvas Canvas { get; private set; }
        public readonly HudContext Ctx = new HudContext();
        public RectTransform HudLayer { get; private set; }

        public HudGauges Gauges { get; private set; }
        public HudStatus Status { get; private set; }
        public HudCompass Compass { get; private set; }
        public HudMinimap Minimap { get; private set; }
        public HudFullMap FullMap { get; private set; }
        public HudObjective Objective { get; private set; }
        public HudToasts Toasts { get; private set; }
        public HudHelp Help { get; private set; }
        public HudStuck Stuck { get; private set; }
        public HudWinch Winch { get; private set; }
        public HudPrompt Prompt { get; private set; }
        public HudStats Stats { get; private set; }
        public HudPhysicsOverlay Physics { get; private set; }
        public HudGizmos Gizmos { get; private set; }

        readonly List<HudWidget> hudWidgets = new List<HudWidget>();
        CanvasGroup hudGroup;
        Canvas hudCanvas;
        float alpha;
        bool built;
        Vehicle lastVehicle;
        float sessionStart = -1f, helpShownAt = -1f;
        bool helpShownOnce;

        // event watchers
        bool wasLowFuel, wasStuck, wasFlooded, wasEngineOn = true, wasWinch, wasLights;
        float lastRecoverCount = -1f, lastObjectiveState;
        bool lastCompleted, lastFailed;
        GarageZone lastGarage;

        public bool Visible => alpha > 0.02f;
        public int GraphicCount { get; private set; }

        static readonly List<(string, float, NoteKind)> pendingNotes = new List<(string, float, NoteKind)>();

        // ------------------------------------------------------------------ static API

        public static void Notify(string message, float seconds = 3.5f) { Notify(message, seconds, NoteKind.Info); }

        public static void Notify(string message, float seconds, NoteKind kind)
        {
            if (string.IsNullOrEmpty(message)) return;
            if (Instance != null && Instance.Toasts != null) Instance.Toasts.Post(message, seconds, kind);
            else if (pendingNotes.Count < 16) pendingNotes.Add((message, seconds, kind));
        }

        // ------------------------------------------------------------------ build

        void Awake() { Instance = this; }
        void OnDestroy() { if (Instance == this) Instance = null; }

        public void Build(Canvas canvas, RectTransform root)
        {
            if (built) return;
            built = true;
            Canvas = canvas;
            Ctx.canvas = canvas; Ctx.root = root; Ctx.gm = GameManager.Instance;

            HudLayer = UiFactory.NewRect("HudLayer", root);
            UiFactory.Fill(HudLayer);
            hudCanvas = HudLayer.gameObject.AddComponent<Canvas>();       // nested canvases isolate rebuilds: the dials do not re-batch the menus
            hudGroup = HudLayer.gameObject.AddComponent<CanvasGroup>();
            hudGroup.blocksRaycasts = false; hudGroup.interactable = false;

            Gizmos = Add(new HudGizmos());
            Physics = Add(new HudPhysicsOverlay());
            Minimap = Add(new HudMinimap());
            Status = Add(new HudStatus());
            Gauges = Add(new HudGauges());
            Compass = Add(new HudCompass());
            Objective = Add(new HudObjective());
            Winch = Add(new HudWinch());
            Prompt = Add(new HudPrompt());
            Stuck = Add(new HudStuck());
            Stats = Add(new HudStats());

            FullMap = new HudFullMap(); FullMap.Build(Ctx, root); Isolate(FullMap);
            Help = new HudHelp(); Help.Build(Ctx, root); Isolate(Help);
            Toasts = new HudToasts(); Toasts.Build(Ctx, root); Isolate(Toasts);
            foreach (var (m, s, k) in pendingNotes) Toasts.Post(m, s, k);
            pendingNotes.Clear();
            hudGroup.alpha = 0f;
        }

        T Add<T>(T w) where T : HudWidget
        {
            w.Build(Ctx, HudLayer);
            Isolate(w);
            hudWidgets.Add(w);
            return w;
        }

        static void Isolate(HudWidget w)
        {
            if (w.root != null && w.root.GetComponent<Canvas>() == null) w.root.gameObject.AddComponent<Canvas>();
        }

        // ------------------------------------------------------------------ public controls

        public void SetMapOpen(bool open) { FullMap.SetOpen(open); }
        public void ToggleMap() { FullMap.SetOpen(!FullMap.IsOpen); }
        public void ToggleHelp() { Help.Toggle(); }
        public void SetPhysicsOverlay(bool on) { Physics.SetOpen(on); }
        public void TogglePhysicsOverlay() { Physics.SetOpen(!UiState.PhysicsOverlay); }
        public void SetHudHidden(bool hidden) { UiState.HudHidden = hidden; }

        /// <summary>Shows the key help for a while (e.g. at the start of a drive).</summary>
        public void ShowHelpTemporarily(float seconds = 10f) { Help.Open(true, seconds); helpShownOnce = true; }

        // ------------------------------------------------------------------ update

        void LateUpdate()
        {
            if (!built) return;
            var gm = GameManager.Instance;
            Ctx.gm = gm;
            Ctx.v = gm != null ? gm.Player : null;
            Ctx.cam = Camera.main;
            Ctx.dt = Time.unscaledDeltaTime;
            Ctx.time = Time.unscaledTime;
            bool want = Ctx.v != null && !UiState.HudHidden && !UiState.MainMenuOpen && !UiState.LoadingWorld;
            float target = want ? 1f : 0f;
            alpha = Mathf.MoveTowards(alpha, target, Ctx.dt * 4f);
            hudGroup.alpha = alpha;
            bool active = alpha > 0.005f;
            if (hudCanvas.enabled != active) hudCanvas.enabled = active;

            if (Ctx.v != lastVehicle)
            {
                lastVehicle = Ctx.v;
                if (Ctx.v != null)
                {
                    foreach (var w in hudWidgets) w.OnVehicleChanged(Ctx);
                    lastRecoverCount = gm != null ? gm.totalRecovers : 0f;
                    wasLowFuel = false; wasStuck = false; wasFlooded = false; wasEngineOn = true; wasWinch = false;
                    MapTrail.Clear();
                    if (!UiState.MainMenuOpen && Ctx.v != null && sessionStart < 0f) sessionStart = Ctx.time;
                }
            }
            if (Ctx.v == null || Ctx.cam == null) { Ctx.cam = Camera.main; if (FullMap.IsOpen) FullMap.SetOpen(false); SafeTick(Help); SafeTick(Toasts); return; }

            MapTrail.Add(Ctx.v.transform.position);
            if (active)
            {
                SafeTick(Stats);
                Toasts.topOffset = Stats.Visible ? Stats.Height : 0f;
                for (int i = 0; i < hudWidgets.Count; i++) if (hudWidgets[i] != Stats) SafeTick(hudWidgets[i]);
            }
            SafeTick(FullMap);
            SafeTick(Help);
            SafeTick(Toasts);
            WatchEvents();

            // first drive: show the control help for a few seconds once the main menu is gone
            if (!helpShownOnce && !UiState.MainMenuOpen && !UiState.LoadingWorld && Ctx.v != null && GameSession.ShowHelpOnStart)
            {
                if (helpShownAt < 0f) helpShownAt = Ctx.time + 0.6f;
                else if (Ctx.time >= helpShownAt) { ShowHelpTemporarily(10f); }
            }
        }

        readonly HashSet<HudWidget> failed = new HashSet<HudWidget>();

        /// <summary>A failing widget must not take the whole HUD down: log once per widget and keep ticking the others.</summary>
        void SafeTick(HudWidget w)
        {
            try { w.Tick(Ctx); }
            catch (System.Exception e)
            {
                if (failed.Add(w)) Debug.LogError("[MudRunner] HUD widget " + w.GetType().Name + " failed: " + e);
            }
        }

        void WatchEvents()
        {
            var v = Ctx.v; if (v == null || v.def == null) return;
            // fuel
            float frac = v.fuel / Mathf.Max(1f, v.def.fuelCapacity);
            if (frac < 0.15f && !wasLowFuel && v.def.fuelCapacity > 1f) { wasLowFuel = true; Notify("Low fuel — " + Mathf.CeilToInt(v.fuel) + " L left", 4f, NoteKind.Warn); }
            else if (frac > 0.2f) wasLowFuel = false;
            // stuck
            if (v.isStuck && !wasStuck) Notify("Vehicle stuck: try low range, diff locks or the winch", 4f, NoteKind.Warn);
            wasStuck = v.isStuck;
            // engine
            bool flooded = v.water != null && v.water.engineFlooded;
            if (flooded && !wasFlooded) Notify("Engine flooded! Get out of the water and wait", 4.5f, NoteKind.Bad);
            wasFlooded = flooded;
            bool on = v.drivetrain != null && v.drivetrain.engineOn;
            if (wasEngineOn && !on && !flooded && v.fuel > 0.05f && !v.def.isTrailer && Time.timeScale > 0f && UiState.VehicleInputBlocked == false)
                Notify("Engine stopped — press I to restart", 3f, NoteKind.Warn);
            if (wasEngineOn && !on && v.fuel <= 0.05f && !v.def.isTrailer) Notify("Out of fuel!", 4f, NoteKind.Bad);
            wasEngineOn = on;
            // winch
            bool winch = v.winch != null && v.winch.Attached;
            if (winch && !wasWinch) Notify("Winch attached" + (v.winch.AnchorName.Length > 0 ? ": " + v.winch.AnchorName : ""), 2.5f, NoteKind.Good);
            else if (!winch && wasWinch) Notify("Winch released", 2f, NoteKind.Info);
            wasWinch = winch;
            // headlights
            var hl = v.GetComponent<VehicleHeadlights>();
            bool lights = hl != null && hl.On;
            if (lights != wasLights) { wasLights = lights; Notify(lights ? "Headlights on" : "Headlights off", 1.6f, NoteKind.Info); }
            // recover
            var gm = Ctx.gm;
            if (gm != null)
            {
                if (lastRecoverCount >= 0f && gm.totalRecovers > lastRecoverCount)
                    Notify("Vehicle recovered (−" + gm.recoverFuelCost.ToString("0") + " L fuel, +" + gm.recoverTimePenalty.ToString("0") + " s penalty)", 4f, NoteKind.Warn);
                lastRecoverCount = gm.totalRecovers;
            }
            // objective
            var om = ObjectiveManager.Instance;
            if (om != null)
            {
                if (om.completed && !lastCompleted) Notify(string.IsNullOrEmpty(om.resultText) ? "Objective complete!" : om.resultText, 6f, NoteKind.Good);
                if (om.failed && !lastFailed) Notify(string.IsNullOrEmpty(om.resultText) ? "Objective failed" : om.resultText, 6f, NoteKind.Bad);
                lastCompleted = om.completed; lastFailed = om.failed;
            }
            // garage
            var gz = GarageZone.Find(v.transform.position);
            if (gz != lastGarage) { lastGarage = gz; }
        }

        /// <summary>Number of active uGUI graphics (tests use this to prove the HUD was built).</summary>
        public int CountGraphics()
        {
            int n = 0;
            if (Canvas == null) return 0;
            var gs = Canvas.GetComponentsInChildren<Graphic>(true);
            n = gs.Length;
            GraphicCount = n;
            return n;
        }
    }
}
