using System.Collections.Generic;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>Colour palette and constants shared by every piece of UI (dark translucent panels, amber accent).</summary>
    public static class UiTheme
    {
        public static readonly Color Bg = new Color(0.045f, 0.052f, 0.062f, 0.78f);
        public static readonly Color BgDeep = new Color(0.030f, 0.036f, 0.044f, 0.88f);
        public static readonly Color BgSolid = new Color(0.040f, 0.046f, 0.054f, 0.97f);
        public static readonly Color Row = new Color(1f, 1f, 1f, 0.045f);
        public static readonly Color Border = new Color(1f, 1f, 1f, 0.11f);
        public static readonly Color Accent = new Color32(255, 176, 32, 255);
        public static readonly Color AccentDim = new Color32(150, 100, 20, 255);
        public static readonly Color AccentSoft = new Color(1f, 0.69f, 0.125f, 0.18f);
        public static readonly Color Text = new Color(0.94f, 0.95f, 0.96f, 1f);
        public static readonly Color TextDim = new Color(0.62f, 0.67f, 0.72f, 1f);
        public static readonly Color TextFaint = new Color(0.42f, 0.46f, 0.50f, 1f);
        public static readonly Color Good = new Color32(104, 218, 118, 255);
        public static readonly Color Warn = new Color32(255, 204, 48, 255);
        public static readonly Color Bad = new Color32(255, 84, 66, 255);
        public static readonly Color Info = new Color32(84, 196, 255, 255);
        public static readonly Color LampOff = new Color(1f, 1f, 1f, 0.16f);
        public static readonly Color Track = new Color(1f, 1f, 1f, 0.10f);

        public static Color WithAlpha(Color c, float a) { c.a = a; return c; }

        /// <summary>Green (0) - yellow (0.6) - red (1+) ramp used by usage bars.</summary>
        public static Color UsageColor(float t)
        {
            t = Mathf.Clamp(t, 0f, 1.25f);
            if (t < 0.6f) return Color.Lerp(Good, Warn, t / 0.6f);
            return Color.Lerp(Warn, Bad, Mathf.Clamp01((t - 0.6f) / 0.4f));
        }

        /// <summary>Red (0) to green (1) health ramp.</summary>
        public static Color HealthColor(float t)
        {
            t = Mathf.Clamp01(t);
            if (t < 0.5f) return Color.Lerp(Bad, Warn, t * 2f);
            return Color.Lerp(Warn, Good, (t - 0.5f) * 2f);
        }

        public const int RefWidth = 1920, RefHeight = 1080;
        public const float Margin = 36f;
    }

    /// <summary>Player-facing UI preferences (persisted with PlayerPrefs).</summary>
    public static class UiSettings
    {
        static int imperial = -1;
        public static bool Imperial
        {
            get { if (imperial < 0) imperial = UnityEngine.PlayerPrefs.GetInt("mr_imperial", 0); return imperial == 1; }
            set { imperial = value ? 1 : 0; UnityEngine.PlayerPrefs.SetInt("mr_imperial", imperial); }
        }
    }

    /// <summary>Process-wide UI state read by the camera, input gate and widgets.</summary>
    public static class UiState
    {
        public static bool MainMenuOpen, PauseOpen, GarageOpen, DebugOpen, MapOpen, HelpOpen, PhysicsOverlay, ForceGizmos, ShowFps, ShowCoords;
        public static bool HudHidden;
        public static bool TextFieldFocus;
        public static bool FreeCamera;
        public static bool LoadingWorld;
        /// <summary>Set by tests / scripted demos that write Vehicle.input themselves: the keyboard/gamepad driver is switched off.</summary>
        public static bool ScriptedDriving;

        /// <summary>A modal UI layer is open (game logic should not receive input).</summary>
        public static bool ModalOpen => MainMenuOpen || PauseOpen || GarageOpen || LoadingWorld;

        /// <summary>The mouse cursor must be visible and free (menus, map, debug window).</summary>
        public static bool CursorFree => ModalOpen || MapOpen || DebugOpen;

        public static bool VehicleInputBlocked => ModalOpen || TextFieldFocus || FreeCamera || ScriptedDriving;

        public static float BaseFixedDeltaTime = 0.01f;
        public static float SlowMotion = 1f;

        public static void ResetAll()
        {
            MainMenuOpen = PauseOpen = GarageOpen = DebugOpen = MapOpen = HelpOpen = PhysicsOverlay = ForceGizmos = ShowFps = ShowCoords = false;
            HudHidden = TextFieldFocus = FreeCamera = LoadingWorld = ScriptedDriving = false;
            SlowMotion = 1f;
        }
    }

    /// <summary>Named world locations drawn on the compass / minimap / full map. Worlds and gameplay code register their sites here.</summary>
    public static class MapMarkers
    {
        public enum Kind { Site, Garage, Fuel, Objective, Waypoint, Danger, Camp }

        public sealed class Marker
        {
            public string name; public Vector3 position; public Kind kind; public float radius; public bool showOnCompass = true;
            public Marker(string n, Vector3 p, Kind k, float r = 0f) { name = n; position = p; kind = k; radius = r; }
        }

        public sealed class Route
        {
            public string name; public Vector3[] points; public Color color;
            public Route(string n, Vector3[] p, Color c) { name = n; points = p; color = c; }
        }

        static readonly List<Marker> markers = new List<Marker>();
        static readonly List<Route> routes = new List<Route>();
        public static IReadOnlyList<Marker> Markers => markers;
        public static IReadOnlyList<Route> Routes => routes;
        public static Marker UserWaypoint { get; private set; }
        public static int Version { get; private set; }

        public static Marker Add(string name, Vector3 pos, Kind kind = Kind.Site, float radius = 0f)
        {
            var m = new Marker(name, pos, kind, radius); markers.Add(m); Version++; return m;
        }
        public static void Remove(Marker m) { if (markers.Remove(m)) Version++; }
        /// <summary>Adds a route polyline for the maps (a route with the same name is replaced).</summary>
        public static Route AddRoute(string name, Vector3[] pts, Color color)
        {
            var r = new Route(name, pts, color);
            for (int i = 0; i < routes.Count; i++) if (routes[i].name == name) { routes[i] = r; Version++; return r; }
            routes.Add(r); Version++; return r;
        }
        public static void RemoveRoute(Route r) { if (routes.Remove(r)) Version++; }
        public static void Clear() { markers.Clear(); routes.Clear(); UserWaypoint = null; Version++; }
        public static void SetUserWaypoint(Vector3? p)
        {
            UserWaypoint = p.HasValue ? new Marker("Waypoint", p.Value, Kind.Waypoint) : null; Version++;
        }
    }
}

namespace MudRunner.UI
{
    /// <summary>Tiny diagnostic used by the UI tests: builds throw-away canvases to check how the uGUI masks behave when deactivated.</summary>
    public static class UiDiag
    {
        public static void BuildMaskCase(string name, bool rectMask, bool withLines, bool withArc, bool withImage, bool inactiveFirst, out UnityEngine.GameObject root)
        {
            var cgo = new UnityEngine.GameObject("diag_" + name, typeof(UnityEngine.RectTransform));
            var canvas = cgo.AddComponent<UnityEngine.Canvas>(); canvas.renderMode = UnityEngine.RenderMode.ScreenSpaceOverlay;
            var clip = UiFactory.NewRect("Clip", cgo.transform);
            clip.sizeDelta = new UnityEngine.Vector2(200, 200);
            if (inactiveFirst) clip.gameObject.SetActive(false);
            if (rectMask) clip.gameObject.AddComponent<UnityEngine.UI.RectMask2D>();
            else { var im = clip.gameObject.AddComponent<UnityEngine.UI.Image>(); im.sprite = UiAssets.White; clip.gameObject.AddComponent<UnityEngine.UI.Mask>().showMaskGraphic = false; }
            if (withLines) { var l = UiFactory.NewRect("Lines", clip); var ul = l.gameObject.AddComponent<UiLines>(); ul.Add(UnityEngine.Vector2.zero, new UnityEngine.Vector2(50, 50), 3f, UnityEngine.Color.white); ul.Apply(); }
            if (withArc) { var a = UiFactory.NewRect("Arc", clip); var ua = a.gameObject.AddComponent<UiArc>(); ua.Configure(50, 8, -135, 270); }
            if (withImage) UiFactory.Img(clip, "Img", UiAssets.Circle, UnityEngine.Color.white);
            UiFactory.Label(clip, "txt", 14, UnityEngine.Color.white);
            root = clip.gameObject;
        }
    }
}
