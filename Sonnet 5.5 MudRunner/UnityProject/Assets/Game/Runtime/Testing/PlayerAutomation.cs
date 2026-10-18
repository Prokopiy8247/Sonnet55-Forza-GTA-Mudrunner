using System;
using System.IO;
using System.Text;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.UI;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Testing
{
    /// <summary>
    /// Command-line automation for the standalone player (used to verify builds without a human):
    /// <c>-mrworld wilderness|proving|arena [-mrvehicle scout|utility|hauler] [-mrdrive speed] [-mrshots dir] [-mrinterval s] [-mrquit s]</c>.
    /// Skips the main menu, starts the world, optionally drives straight ahead with the scripted bot, logs the vehicle state every
    /// second and writes screenshots (with the HUD) into the given folder.
    /// </summary>
    public static class PlayerAutomation
    {
        public static bool Active { get; private set; }
        public static WorldKind World = WorldKind.ProvingGround;
        public static string Vehicle = "utility";
        public static float DriveSpeed = -1f;
        public static string ShotsDir;
        public static float ShotInterval = 4f, QuitAfter = -1f;
        public static WorldKind? SwitchTo; public static float SwitchAt = 6f;
        public static int Scenario = -1;              // start this scenario (index into Scenarios.All) through the UI at SwitchAt seconds
        public static int Route = -1;                 // follow this wilderness route (index into WorldSites.routes) with the scripted bot
        public static bool NoTractionControl;         // full-throttle driver (what a careless player does)

        static string Arg(string[] a, string name)
        {
            for (int i = 0; i < a.Length - 1; i++) if (string.Equals(a[i], name, StringComparison.OrdinalIgnoreCase)) return a[i + 1];
            return null;
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Parse()
        {
            var a = Environment.GetCommandLineArgs();
            string w = Arg(a, "-mrworld");
            if (w == null) return;
            Active = true;
            switch (w.ToLowerInvariant())
            {
                case "wilderness": World = WorldKind.Wilderness; break;
                case "arena": World = WorldKind.Arena; break;
                default: World = WorldKind.ProvingGround; break;
            }
            string v = Arg(a, "-mrvehicle"); if (!string.IsNullOrEmpty(v)) Vehicle = v;
            if (float.TryParse(Arg(a, "-mrdrive"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var s)) DriveSpeed = s;
            ShotsDir = Arg(a, "-mrshots");
            if (float.TryParse(Arg(a, "-mrinterval"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var si)) ShotInterval = si;
            if (float.TryParse(Arg(a, "-mrquit"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var q)) QuitAfter = q;
            string sw = Arg(a, "-mrswitch");
            if (sw != null) SwitchTo = sw.ToLowerInvariant() == "wilderness" ? WorldKind.Wilderness : WorldKind.ProvingGround;
            if (float.TryParse(Arg(a, "-mrswitchat"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var sa)) SwitchAt = sa;
            if (int.TryParse(Arg(a, "-mrroute"), out var rt)) Route = rt;
            if (int.TryParse(Arg(a, "-mrscenario"), out var sc)) Scenario = sc;
            NoTractionControl = Arg(a, "-mrfull") != null;
            GameSession.ShowMainMenuOnStart = false;
            GameSession.ShowHelpOnStart = false;
        }

        /// <summary>Called by GameBootstrap after the world started.</summary>
        public static void Attach()
        {
            if (!Active) return;
            var go = new GameObject("PlayerAutomation");
            go.AddComponent<PlayerAutomationRunner>();
        }
    }

    sealed class PlayerAutomationRunner : MonoBehaviour
    {
        float t0, nextShot = 2f, nextLog;
        int shotIndex;
        Vehicle botFor; bool switched; float botReadyAt = 3f;

        void Start()
        {
            t0 = Time.realtimeSinceStartup;
            DontDestroyOnLoad(gameObject);
            if (!string.IsNullOrEmpty(PlayerAutomation.ShotsDir)) Directory.CreateDirectory(PlayerAutomation.ShotsDir);
        }

        void Update()
        {
            float t = Time.realtimeSinceStartup - t0;
            var gm = GameManager.Instance;
            if (!switched && PlayerAutomation.Scenario >= 0 && t >= PlayerAutomation.SwitchAt && UiRoot.Instance != null)
            {
                switched = true; botReadyAt = t + 6f;
                var sdef = MudRunner.Objectives.Scenarios.All[PlayerAutomation.Scenario];
                Debug.Log("[Automation] starting scenario '" + sdef.title + "' through the UI start routine");
                UiRoot.Instance.StartGame(sdef.world, sdef);
            }
            if (!switched && PlayerAutomation.SwitchTo.HasValue && t >= PlayerAutomation.SwitchAt && UiRoot.Instance != null)
            {
                switched = true; botReadyAt = t + 4f;
                Debug.Log("[Automation] switching world through the UI start routine");
                UiRoot.Instance.StartGame(PlayerAutomation.SwitchTo.Value, null);
            }
            if (gm != null && gm.Player != null && gm.Player != botFor && PlayerAutomation.DriveSpeed >= 0f && t > botReadyAt)
            {
                botFor = gm.Player;
                var inp = gm.Player.GetComponent<PlayerVehicleInput>(); if (inp != null) inp.enabled = false;
                var bot = gm.Player.gameObject.AddComponent<BotDriver>();
                bot.vehicle = gm.Player; bot.targetSpeed = PlayerAutomation.DriveSpeed; bot.tractionControl = !PlayerAutomation.NoTractionControl;
                var ws = MudRunner.WorldGen.WorldSites.Current;
                if (PlayerAutomation.Route >= 0 && ws != null && PlayerAutomation.Route < ws.routes.Count)
                {
                    var pts = ws.routes[PlayerAutomation.Route].points;
                    bot.useWaypoints = true; bot.waypointRadius = 6f;
                    // start with the first point ahead of the vehicle
                    int first = 0; float best = float.MaxValue;
                    for (int i = 0; i < pts.Length; i++) { float d = (pts[i] - gm.Player.transform.position).sqrMagnitude; if (d < best) { best = d; first = i; } }
                    for (int i = first; i < pts.Length; i += 3) bot.waypoints.Add(pts[i]);
                    Debug.Log("[Automation] following route '" + ws.routes[PlayerAutomation.Route].name + "' with " + bot.waypoints.Count + " waypoints");
                }
            }
            if (t >= nextLog)
            {
                nextLog = t + 1f;
                if (gm != null && gm.Player != null)
                {
                    var v = gm.Player; var p = v.transform.position;
                    float gh = gm.Ground != null ? gm.Ground.GroundHeight(p.x, p.z) : float.NaN;
                    var sb = new StringBuilder("[Automation] t=").Append(t.ToString("F1"));
                    sb.Append(" pos=").Append(p.ToString("F1")).Append(" groundH=").Append(gh.ToString("F2"));
                    sb.Append(" grounded=").Append(v.groundedWheels).Append(" speed=").Append(v.rb.linearVelocity.magnitude.ToString("F1"));
                    sb.Append(" kmh=").Append((v.forwardSpeed * 3.6f).ToString("F0"));
                    Debug.Log(sb.ToString());
                }
                else Debug.Log("[Automation] t=" + t.ToString("F1") + " no player yet");
            }
            if (!string.IsNullOrEmpty(PlayerAutomation.ShotsDir) && t >= nextShot)
            {
                nextShot = t + PlayerAutomation.ShotInterval;
                ScreenCapture.CaptureScreenshot(Path.Combine(PlayerAutomation.ShotsDir, "shot_" + (shotIndex++).ToString("D2") + ".png"));
            }
            if (PlayerAutomation.QuitAfter > 0f && t >= PlayerAutomation.QuitAfter) Application.Quit();
        }
    }
}
