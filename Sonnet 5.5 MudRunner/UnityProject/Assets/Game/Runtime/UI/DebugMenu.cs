using System.Collections.Generic;
using MudRunner.Atmosphere;
using MudRunner.CameraSystem;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Testing;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>
    /// IMGUI debug + benchmark window (F1 or backtick). Grouped, collapsible sections; every control calls <see cref="DebugActions"/>.
    /// While a text field has focus the vehicle input is paused (<see cref="UiState.TextFieldFocus"/>).
    /// </summary>
    public sealed class DebugMenu : MonoBehaviour
    {
        public static DebugMenu Instance { get; private set; }
        public bool IsOpen { get; private set; }
        public readonly Benchmark benchmark = new Benchmark();

        public Vector2 scroll;
        readonly Dictionary<string, bool> folds = new Dictionary<string, bool>
        {
            { "Teleport", true }, { "Vehicle", true }, { "Camera", false }, { "Terrain & mud", true }, { "Weather & time", true },
            { "Drivetrain & winch", false }, { "Overlays & diagnostics", true }, { "Soil under the vehicle", false }, { "Tests & benchmark", true },
        };
        readonly Dictionary<string, string> buffers = new Dictionary<string, string>();
        string tpX = "0", tpZ = "0";
        float benchSeconds = 20f; bool benchAutoDrive = true;
        float lapse;
        GUIStyle sWindow, sHeader, sHeaderOpen, sButton, sButtonOn, sLabel, sDim, sField, sToggle, sMono, sTitle;
        Texture2D texBg, texHeader, texBtn, texBtnHover, texBtnOn, texField;
        bool stylesReady;

        public const float WindowWidth = 440f;

        void Awake() { Instance = this; }
        void OnDestroy() { if (Instance == this) Instance = null; UiState.DebugOpen = false; UiState.TextFieldFocus = false; }

        public void SetOpen(bool open)
        {
            IsOpen = open; UiState.DebugOpen = open;
            if (!open) { UiState.TextFieldFocus = false; GUIUtility.keyboardControl = 0; }
        }

        public void Toggle() { SetOpen(!IsOpen); }

        void Update() { benchmark.Tick(Time.unscaledDeltaTime); }

        // ------------------------------------------------------------------ styles

        static Texture2D Tex(Color c)
        {
            var t = new Texture2D(1, 1, TextureFormat.RGBA32, false) { hideFlags = HideFlags.HideAndDontSave, filterMode = FilterMode.Point };
            t.SetPixel(0, 0, c); t.Apply();
            return t;
        }

        void EnsureStyles()
        {
            if (stylesReady) return;
            stylesReady = true;
            texBg = Tex(new Color(0.04f, 0.047f, 0.056f, 0.94f)); texHeader = Tex(new Color(1f, 0.69f, 0.125f, 0.14f));
            texBtn = Tex(new Color(1f, 1f, 1f, 0.09f)); texBtnHover = Tex(new Color(1f, 1f, 1f, 0.18f)); texBtnOn = Tex(new Color(1f, 0.69f, 0.125f, 0.92f)); texField = Tex(new Color(0f, 0f, 0f, 0.55f));
            var body = UiAssets.Get(UiFont.Body); var bold = UiAssets.Get(UiFont.Bold); var mono = UiAssets.Get(UiFont.Mono); var disp = UiAssets.Get(UiFont.Display);
            sWindow = new GUIStyle(GUI.skin.box) { normal = { background = texBg }, padding = new RectOffset(10, 10, 10, 10), border = new RectOffset(0, 0, 0, 0) };
            sHeader = new GUIStyle(GUI.skin.button) { font = bold, fontSize = 14, alignment = TextAnchor.MiddleLeft, padding = new RectOffset(10, 4, 5, 5), fixedHeight = 28, fontStyle = bold == body ? FontStyle.Bold : FontStyle.Normal };
            sHeader.normal.background = texHeader; sHeader.hover.background = texBtnHover; sHeader.active.background = texBtnHover;
            sHeader.normal.textColor = new Color(1f, 0.74f, 0.25f); sHeader.hover.textColor = Color.white; sHeader.active.textColor = Color.white;
            sHeaderOpen = new GUIStyle(sHeader);
            sButton = new GUIStyle(GUI.skin.button) { font = body, fontSize = 13, alignment = TextAnchor.MiddleCenter, padding = new RectOffset(6, 6, 4, 4), margin = new RectOffset(2, 2, 2, 2) };
            sButton.normal.background = texBtn; sButton.hover.background = texBtnHover; sButton.active.background = texBtnOn; sButton.focused.background = texBtn;
            sButton.normal.textColor = new Color(0.93f, 0.95f, 0.96f); sButton.hover.textColor = Color.white; sButton.active.textColor = Color.black; sButton.focused.textColor = Color.white;
            sButtonOn = new GUIStyle(sButton);
            sButtonOn.normal.background = texBtnOn; sButtonOn.hover.background = texBtnOn; sButtonOn.focused.background = texBtnOn;
            sButtonOn.normal.textColor = Color.black; sButtonOn.hover.textColor = Color.black; sButtonOn.focused.textColor = Color.black;
            sLabel = new GUIStyle(GUI.skin.label) { font = body, fontSize = 13, wordWrap = true, normal = { textColor = new Color(0.93f, 0.95f, 0.96f) }, padding = new RectOffset(2, 2, 1, 1) };
            sDim = new GUIStyle(sLabel) { normal = { textColor = new Color(0.62f, 0.67f, 0.72f) } };
            sMono = new GUIStyle(sLabel) { font = mono, fontSize = 12, wordWrap = false };
            sTitle = new GUIStyle(sLabel) { font = disp, fontSize = 22, normal = { textColor = new Color(1f, 0.69f, 0.125f) } };
            sField = new GUIStyle(GUI.skin.textField) { font = mono, fontSize = 12, alignment = TextAnchor.MiddleRight, padding = new RectOffset(4, 4, 3, 3) };
            sField.normal.background = texField; sField.focused.background = texField; sField.hover.background = texField;
            sField.normal.textColor = Color.white; sField.focused.textColor = new Color(1f, 0.74f, 0.25f);
            sToggle = new GUIStyle(sButton);
        }

        // ------------------------------------------------------------------ drawing helpers

        bool Fold(string name)
        {
            bool open = folds[name];
            if (GUILayout.Button((open ? "▾  " : "▸  ") + name.ToUpperInvariant(), sHeader)) { open = !open; folds[name] = open; }
            return open;
        }

        bool Toggle(string label, bool value)
        {
            bool nv = GUILayout.Toggle(value, label, value ? sButtonOn : sButton, GUILayout.MinHeight(26));
            return nv;
        }

        bool Btn(string label, bool on = false, params GUILayoutOption[] opts)
        {
            return GUILayout.Button(label, on ? sButtonOn : sButton, opts);
        }

        /// <summary>Label + slider + editable number. Returns the new value.</summary>
        float Slider(string label, float value, float min, float max, string fmt = "0.00")
        {
            string name = "tf_" + label;
            GUILayout.BeginHorizontal();
            GUILayout.Label(label, sLabel, GUILayout.Width(128));
            float nv = GUILayout.HorizontalSlider(value, min, max, GUILayout.ExpandWidth(true), GUILayout.Height(18));
            GUI.SetNextControlName(name);
            string cur = value.ToString(fmt, System.Globalization.CultureInfo.InvariantCulture);
            bool focused = GUI.GetNameOfFocusedControl() == name;
            if (!buffers.TryGetValue(name, out string buf) || !focused) buf = cur;
            string edited = GUILayout.TextField(buf, 8, sField, GUILayout.Width(58));
            if (edited != buf || focused) buffers[name] = edited;
            if (focused && edited != cur && float.TryParse(edited, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float parsed))
                nv = Mathf.Clamp(parsed, min, max);
            GUILayout.EndHorizontal();
            return nv;
        }

        void Space(float h = 4f) { GUILayout.Space(h); }

        // ------------------------------------------------------------------ OnGUI

        void OnGUI()
        {
            if (!IsOpen) { return; }
            EnsureStyles();
            float s = Mathf.Max(1f, Screen.height / 1080f);
            var gm = GameManager.Instance;

            var e = Event.current;
            if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape && GUIUtility.keyboardControl != 0) { GUI.FocusControl(null); GUIUtility.keyboardControl = 0; e.Use(); }
            if (e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) && GUI.GetNameOfFocusedControl().StartsWith("tf_")) { GUI.FocusControl(null); }

            GUI.matrix = Matrix4x4.Scale(new Vector3(s, s, 1f));
            float sh = Screen.height / s;
            var rect = new Rect(16, 16, WindowWidth, Mathf.Min(sh - 32, 1000));
            GUILayout.BeginArea(rect, sWindow);
            GUILayout.BeginHorizontal();
            GUILayout.Label("DEBUG / BENCHMARK", sTitle);
            GUILayout.FlexibleSpace();
            GUILayout.Label("F1 / `  close", sDim, GUILayout.Width(90));
            GUILayout.EndHorizontal();
            if (gm == null || gm.World == null || gm.Player == null)
            {
                GUILayout.Label("No world / vehicle running." + (RuntimePhysicsSuite.Instance != null && RuntimePhysicsSuite.Instance.Running ? "  Physics suite is running: " + DebugActions.SuiteStatus() : ""), sDim);
                GUILayout.EndArea();
                UiState.TextFieldFocus = false;
                return;
            }
            scroll = GUILayout.BeginScrollView(scroll, false, false, GUILayout.ExpandHeight(true));
            DrawTeleport(gm); DrawVehicle(gm); DrawCamera(); DrawTerrain(); DrawWeather(); DrawDrivetrain(gm); DrawOverlays(gm); DrawSoil(gm); DrawTests();
            GUILayout.EndScrollView();
            GUILayout.EndArea();

            if (e.type == EventType.Repaint || e.type == EventType.Layout)
                UiState.TextFieldFocus = GUI.GetNameOfFocusedControl().StartsWith("tf_");
        }

        // ------------------------------------------------------------------ sections

        void DrawTeleport(GameManager gm)
        {
            if (!Fold("Teleport")) return;
            var pts = gm.World.points;
            if (Btn("Spawn point")) DebugActions.TeleportToSpawn();
            int col = 0;
            GUILayout.BeginHorizontal();
            for (int i = 0; i < pts.Count; i++)
            {
                if (Btn(pts[i].name, false, GUILayout.MinWidth(130))) DebugActions.TeleportToPoint(pts[i]);
                col++;
                if (col == 3 && i < pts.Count - 1) { col = 0; GUILayout.EndHorizontal(); GUILayout.BeginHorizontal(); }
            }
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            GUILayout.Label("X", sDim, GUILayout.Width(14)); GUI.SetNextControlName("tf_tpx"); tpX = GUILayout.TextField(tpX, 8, sField, GUILayout.Width(70));
            GUILayout.Label("Z", sDim, GUILayout.Width(14)); GUI.SetNextControlName("tf_tpz"); tpZ = GUILayout.TextField(tpZ, 8, sField, GUILayout.Width(70));
            if (Btn("Go"))
            {
                if (float.TryParse(tpX, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float x) && float.TryParse(tpZ, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float z))
                    DebugActions.Teleport(new Vector3(x, 0f, z), gm.Player.transform.eulerAngles.y);
            }
            if (Btn("Here")) { var p = gm.Player.transform.position; tpX = p.x.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture); tpZ = p.z.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture); }
            GUILayout.EndHorizontal();
            Space();
        }

        void DrawVehicle(GameManager gm)
        {
            if (!Fold("Vehicle")) return;
            var v = gm.Player;
            GUILayout.Label("Driving: " + v.def.displayName + "   fuel " + v.fuel.ToString("0") + "/" + v.def.fuelCapacity.ToString("0") + " L   hull " + Mathf.RoundToInt((1f - v.damage01) * 100f) + "%", sDim);
            GUILayout.Label("Switch to", sDim);
            GUILayout.BeginHorizontal();
            foreach (var k in GameManager.VehicleKeys)
                if (Btn(k, v.def == GameManager.GetDefinition(k))) DebugActions.SwitchVehicle(k);
            GUILayout.EndHorizontal();
            GUILayout.Label("Spawn extra vehicle beside you", sDim);
            GUILayout.BeginHorizontal();
            foreach (var k in GameManager.VehicleKeys) if (Btn(k)) DebugActions.SpawnVehicle(k);
            if (Btn("Remove extras")) DebugActions.RemoveOtherVehicles();
            GUILayout.EndHorizontal();
            GUILayout.Label("Trailer / cargo", sDim);
            GUILayout.BeginHorizontal();
            if (Btn("Spawn trailer")) DebugActions.SpawnTrailer();
            if (Btn("Detach")) DebugActions.DetachTrailer();
            if (Btn("Logs")) DebugActions.LoadCargo("logs");
            if (Btn("Crates")) DebugActions.LoadCargo("crates");
            if (Btn("Barrels")) DebugActions.LoadCargo("barrels");
            if (Btn("Clear")) DebugActions.ClearCargo();
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            if (Btn("Refuel")) DebugActions.Refuel();
            if (Btn("Repair")) DebugActions.Repair();
            if (Btn("Flip reset")) DebugActions.FlipReset();
            if (Btn("Recover")) DebugActions.Recover();
            GUILayout.EndHorizontal();
            Space();
        }

        void DrawCamera()
        {
            if (!Fold("Camera")) return;
            var rig = CameraRig.Instance; if (rig == null) { GUILayout.Label("No CameraRig", sDim); return; }
            bool free = rig.Mode == CameraMode.Free;
            if (Toggle("Free camera  (WASD  Q/E  Shift = fast  RMB = look)", free) != free) DebugActions.SetFreeCamera(!free);
            GUILayout.BeginHorizontal();
            if (Btn("Chase", rig.Mode == CameraMode.Chase)) rig.SetMode(CameraMode.Chase);
            if (Btn("Cockpit", rig.Mode == CameraMode.Cockpit)) rig.SetMode(CameraMode.Cockpit);
            if (Btn("Wheel", rig.Mode == CameraMode.Wheel)) rig.SetMode(CameraMode.Wheel);
            if (Btn("Top", rig.Mode == CameraMode.Top)) rig.SetMode(CameraMode.Top);
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            GUILayout.Label("Wheel " + rig.SelectedWheel, sDim, GUILayout.Width(70));
            if (Btn("<")) rig.SelectWheel(-1);
            if (Btn(">")) rig.SelectWheel(+1);
            rig.shakeEnabled = Toggle("Shake", rig.shakeEnabled);
            GUILayout.EndHorizontal();
            Space();
        }

        void DrawTerrain()
        {
            if (!Fold("Terrain & mud")) return;
            var g = GroundService.Instance; if (g == null) { GUILayout.Label("No GroundService", sDim); return; }
            float v;
            v = Slider("Mud depth x", g.mudDepthScale, 0.2f, 3f); if (!Mathf.Approximately(v, g.mudDepthScale)) DebugActions.SetMudDepth(v);
            v = Slider("Softness x", g.softnessScale, 0.3f, 3f); if (!Mathf.Approximately(v, g.softnessScale)) DebugActions.SetSoftness(v);
            v = Slider("Rut relax x", g.rutRelaxScale, 0f, 6f); if (!Mathf.Approximately(v, g.rutRelaxScale)) DebugActions.SetRutRelax(v);
            v = Slider("Wetness", g.wetness, 0f, 1f); if (!Mathf.Approximately(v, g.wetness)) DebugActions.SetWetness(v);
            GUILayout.BeginHorizontal();
            GUILayout.Label("Ground view", sDim, GUILayout.Width(80));
            int gm = DebugActions.GroundDebugMode;
            if (Btn("Off", gm == 0)) DebugActions.SetGroundDebugView(0);
            if (Btn("Surface", gm == 1)) DebugActions.SetGroundDebugView(1);
            if (Btn("dh", gm == 2)) DebugActions.SetGroundDebugView(2);
            if (Btn("Churn", gm == 3)) DebugActions.SetGroundDebugView(3);
            GUILayout.EndHorizontal();
            if (Btn("Reset tuning")) DebugActions.ResetGroundTuning();
            Space();
        }

        void DrawWeather()
        {
            if (!Fold("Weather & time")) return;
            var a = AtmosphereController.Instance;
            float rain = a != null ? a.rain : 0f;
            GUILayout.BeginHorizontal();
            if (Btn("Rain on", rain > 0.05f)) DebugActions.SetRain(true);
            if (Btn("Rain off", rain <= 0.05f)) DebugActions.SetRain(false);
            GUILayout.EndHorizontal();
            float nr = Slider("Rain intensity", rain, 0f, 1f); if (!Mathf.Approximately(nr, rain)) DebugActions.SetRainIntensity(nr);
            float hour = a != null ? a.hour : 15.5f;
            float nh = Slider("Time of day (h)", hour, 0f, 24f, "0.0"); if (!Mathf.Approximately(nh, hour)) DebugActions.SetTimeOfDay(nh);
            lapse = a != null ? a.minutesPerSecond : lapse;
            float nl = Slider("Time-lapse (min/s)", lapse, 0f, 120f, "0"); if (!Mathf.Approximately(nl, lapse)) { lapse = nl; DebugActions.SetTimeLapse(nl); }
            GUILayout.BeginHorizontal();
            if (Btn("06:00")) DebugActions.SetTimeOfDay(6f);
            if (Btn("12:00")) DebugActions.SetTimeOfDay(12f);
            if (Btn("18:30")) DebugActions.SetTimeOfDay(18.5f);
            if (Btn("23:00")) DebugActions.SetTimeOfDay(23f);
            GUILayout.EndHorizontal();
            Space();
        }

        void DrawDrivetrain(GameManager gm)
        {
            if (!Fold("Drivetrain & winch")) return;
            var v = gm.Player; var d = v.drivetrain;
            GUILayout.BeginHorizontal();
            if (Toggle("AWD", d.awd) != d.awd) DebugActions.ToggleAwd();
            if (Toggle("Low range", d.lowRange) != d.lowRange) DebugActions.ToggleLowRange();
            if (Toggle("Engine", d.engineOn) != d.engineOn) DebugActions.ToggleEngine();
            GUILayout.EndHorizontal();
            bool rear = false; for (int i = 1; i < d.axleLock.Length; i++) rear |= d.axleLock[i];
            GUILayout.BeginHorizontal();
            if (Toggle("Front lock", d.axleLock.Length > 0 && d.axleLock[0]) != (d.axleLock.Length > 0 && d.axleLock[0])) DebugActions.ToggleFrontLock();
            if (Toggle("Rear lock", rear) != rear) DebugActions.ToggleRearLock();
            if (Toggle("Centre lock", d.centreLock) != d.centreLock) DebugActions.ToggleCentreLock();
            GUILayout.EndHorizontal();
            bool manual = d.mode == GearMode.Manual;
            if (Toggle("Manual gearbox", manual) != manual) DebugActions.ToggleGearMode();
            if (v.winch != null)
            {
                GUILayout.BeginHorizontal();
                if (Btn("Winch: auto-anchor", v.winch.Attached)) DebugActions.WinchAutoAnchor();
                if (Btn("Release winch")) DebugActions.WinchDetach();
                GUILayout.EndHorizontal();
                if (v.winch.Attached) GUILayout.Label("rope " + v.winch.RopeLength.ToString("0.0") + " m   tension " + (v.winch.Tension / 1000f).ToString("0.0") + " kN   " + v.winch.AnchorName, sDim);
            }
            else GUILayout.Label("This vehicle has no winch.", sDim);
            Space();
        }

        void DrawOverlays(GameManager gm)
        {
            if (!Fold("Overlays & diagnostics")) return;
            GUILayout.BeginHorizontal();
            bool phys = UiState.PhysicsOverlay;
            if (Toggle("Physics overlay (F2)", phys) != phys) Hud.Instance?.TogglePhysicsOverlay();
            UiState.ForceGizmos = Toggle("Force / collider gizmos", UiState.ForceGizmos);
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            UiState.ShowFps = Toggle("Show FPS (F3)", UiState.ShowFps);
            UiState.ShowCoords = Toggle("Coordinates", UiState.ShowCoords);
            GUILayout.EndHorizontal();
            GUILayout.Label("Slow motion  (timeScale " + Time.timeScale.ToString("0.00") + ", fixed dt " + (Time.fixedDeltaTime * 1000f).ToString("0.00") + " ms)", sDim);
            GUILayout.BeginHorizontal();
            foreach (float f in new[] { 0.1f, 0.25f, 0.5f, 1f })
                if (Btn(f == 1f ? "1x" : f + "x", Mathf.Approximately(UiState.SlowMotion, f))) DebugActions.SetSlowMotion(f);
            GUILayout.EndHorizontal();
            GUILayout.Label("FPS " + FpsCounter.Fps.ToString("0") + "  (" + FpsCounter.FrameMs.ToString("0.0") + " ms)   1% low " + FpsCounter.Low1.ToString("0") + "   0.1% low " + FpsCounter.Low01.ToString("0") + "   worst " + FpsCounter.WorstMs.ToString("0.0") + " ms", sMono);
            var p = gm.Player.transform.position;
            GUILayout.Label("pos " + p.x.ToString("0.0") + ", " + p.y.ToString("0.0") + ", " + p.z.ToString("0.0") + "   speed " + gm.Player.speedKmh.ToString("0.0") + " km/h", sMono);
            Space();
        }

        void DrawSoil(GameManager gm)
        {
            if (!Fold("Soil under the vehicle")) return;
            var g = GroundService.Instance; if (g == null || g.Map == null) return;
            var p = gm.Player.transform.position;
            var s = g.SampleSoil(p.x, p.z);
            var tbl = SurfaceDatabase.Table[(int)s.dominant];
            var sb = new System.Text.StringBuilder();
            sb.Append("surface   ").Append(tbl.name).Append('\n');
            sb.Append("kc ").Append(s.kc.ToString("0.0")).Append("  kphi ").Append(s.kphi.ToString("0")).Append("  n ").Append(s.n.ToString("0.00")).Append('\n');
            sb.Append("cohesion ").Append(s.cohesion.ToString("0.0")).Append(" kPa   phi ").Append(s.phiDeg.ToString("0.0")).Append(" deg\n");
            sb.Append("shear K ").Append(s.shearK.ToString("0.000")).Append(" m   viscosity ").Append(s.viscosity.ToString("0.00")).Append('\n');
            sb.Append("soft depth ").Append(s.softDepth.ToString("0.00")).Append(" m   wet ").Append(s.wet.ToString("0.00")).Append('\n');
            sb.Append("fluidity ").Append(s.fluidity.ToString("0.000")).Append("  slope ").Append(g.Map.SampleSlopeDegrees(p.x, p.z).ToString("0.0")).Append(" deg\n");
            if (g.Field != null && g.Field.IsResidentWorld(p.x, p.z)) { g.Field.Sample(p.x, p.z, out float dh, out float churn, out float comp); sb.Append("field dh ").Append((dh * 100f).ToString("0.0")).Append(" cm  churn ").Append(churn.ToString("0.00")).Append("  compact ").Append(comp.ToString("0.00")); }
            GUILayout.Label(sb.ToString(), sMono);
            var ws = gm.Player.wheels;
            for (int i = 0; i < ws.Length; i++)
                GUILayout.Label(ws[i].name.PadRight(9) + " load " + (ws[i].load / 1000f).ToString("0.0").PadLeft(5) + " kN  sink " + (ws[i].sinkage * 100f).ToString("0.0").PadLeft(5) + " cm  slip " + ws[i].slipRatio.ToString("0.00").PadLeft(5), sMono);
            Space();
        }

        void DrawTests()
        {
            if (!Fold("Tests & benchmark")) return;
            GUILayout.BeginHorizontal();
            if (Btn("Run physics test suite")) DebugActions.RunPhysicsSuite(false);
            if (Btn("Quick", false, GUILayout.Width(60))) DebugActions.RunPhysicsSuite(true);
            GUILayout.EndHorizontal();
            string suiteStatus = DebugActions.SuiteStatus();
            if (!string.IsNullOrEmpty(suiteStatus)) GUILayout.Label(suiteStatus, sDim);
            GUILayout.Space(4);
            GUILayout.BeginHorizontal();
            GUILayout.Label("Benchmark", sDim, GUILayout.Width(70));
            GUI.SetNextControlName("tf_bench");
            string bs = GUILayout.TextField(benchSeconds.ToString("0"), 4, sField, GUILayout.Width(44));
            if (float.TryParse(bs, out float bsv)) benchSeconds = Mathf.Clamp(bsv, 3f, 300f);
            GUILayout.Label("s", sDim, GUILayout.Width(14));
            benchAutoDrive = Toggle("auto-drive", benchAutoDrive);
            if (!benchmark.Running) { if (Btn("Start")) benchmark.Start(benchSeconds, benchAutoDrive); }
            else if (Btn("Stop")) benchmark.Stop(true);
            GUILayout.EndHorizontal();
            GUILayout.Label(benchmark.Summary(), sMono);
            Space();
        }
    }
}
