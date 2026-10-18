using System;
using System.Collections;
using MudRunner.Atmosphere;
using MudRunner.Cargo;
using MudRunner.CameraSystem;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Testing;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>
    /// Every action of the debug / benchmark menu as a plain static function (the IMGUI window only calls these), so the
    /// behaviour is testable without drawing anything. All of them are null-safe against missing systems.
    /// </summary>
    public static class DebugActions
    {
        static GameManager GM => GameManager.Instance;
        static Vehicle Player => GM != null ? GM.Player : null;

        // ------------------------------------------------------------------ teleport / vehicles

        public static bool Teleport(Vector3 position, float yaw)
        {
            if (GM == null || Player == null) return false;
            GM.TeleportPlayer(position, yaw);
            CameraRig.Instance?.Snap();
            return true;
        }

        public static bool TeleportToPoint(WorldPoint p) { return Teleport(p.position, p.yaw); }

        public static bool TeleportToSpawn()
        {
            if (GM == null || GM.World == null) return false;
            return Teleport(GM.World.playerStart, GM.World.playerYaw);
        }

        public static Vehicle SwitchVehicle(string key)
        {
            if (GM == null || GM.World == null) return null;
            var v = GM.SwitchPlayerVehicle(key);
            GameSession.VehicleKey = key;
            CameraRig.Instance?.Snap();
            Hud.Notify("Vehicle: " + v.def.displayName, 2.5f);
            return v;
        }

        /// <summary>Spawns an extra (AI-less) vehicle 7 m to the side of the player: winch target, convoy, traffic.</summary>
        public static Vehicle SpawnVehicle(string key)
        {
            var p = Player; if (GM == null || p == null) return null;
            Vector3 pos = p.transform.position + p.transform.right * 7f + p.transform.forward * 2f;
            var v = GM.SpawnVehicle(key, pos, p.transform.eulerAngles.y, false);
            if (v != null) { var i = v.input; i.handbrake = true; v.input = i; }
            Hud.Notify("Spawned " + v.def.displayName, 2f);
            return v;
        }

        public static int RemoveOtherVehicles()
        {
            if (GM == null) return 0;
            int n = 0;
            for (int i = GM.Vehicles.Count - 1; i >= 0; i--)
            {
                var v = GM.Vehicles[i];
                if (v == null || v == GM.Player) continue;
                GM.Vehicles.RemoveAt(i); UnityEngine.Object.Destroy(v.gameObject); n++;
            }
            return n;
        }

        // ------------------------------------------------------------------ trailer / cargo (null-safe)

        public static bool SpawnTrailer()
        {
            if (Player == null) return false;
            bool ok = TrailerSystem.EnsureInstance().SpawnTrailerBehindPlayer();
            Hud.Notify(ok ? "Trailer attached" : "Cannot attach a trailer to this vehicle", 2.5f, ok ? NoteKind.Good : NoteKind.Warn);
            return ok;
        }

        public static bool DetachTrailer()
        {
            var t = TrailerSystem.Instance;
            if (t == null || !t.HasTrailer) { Hud.Notify("No trailer attached", 2f, NoteKind.Warn); return false; }
            t.DetachTrailer();
            Hud.Notify("Trailer detached", 2f);
            return true;
        }

        public static bool LoadCargo(string kind)
        {
            if (Player == null) return false;
            var t = TrailerSystem.EnsureInstance();
            t.LoadCargo(kind);
            Hud.Notify(t.HasTrailer ? "Loaded " + t.CargoDescription : "No trailer to load", 2.5f, t.HasTrailer ? NoteKind.Good : NoteKind.Warn);
            return t.HasTrailer;
        }

        public static void ClearCargo() { var t = TrailerSystem.Instance; if (t != null) t.ClearCargo(); }

        // ------------------------------------------------------------------ vehicle service

        public static void Refuel() { var p = Player; if (p != null) { p.Refuel(); Hud.Notify("Refuelled", 1.5f, NoteKind.Good); } }
        public static void Repair() { var p = Player; if (p != null) { p.Repair(); Hud.Notify("Repaired", 1.5f, NoteKind.Good); } }
        public static void FlipReset() { var p = Player; if (p != null) { p.ResetUpright(); CameraRig.Instance?.Snap(); } }
        public static bool Recover() { return GM != null && GM.RecoverPlayer(); }

        // ------------------------------------------------------------------ camera

        public static void SetFreeCamera(bool on)
        {
            var rig = CameraRig.Instance; if (rig == null) return;
            if (on) rig.SetMode(CameraMode.Free); else rig.ExitFree();
        }

        // ------------------------------------------------------------------ ground tuning

        public static GroundService Ground => GroundService.Instance;
        public static void SetMudDepth(float v) { if (Ground != null) Ground.mudDepthScale = Mathf.Clamp(v, 0.2f, 3f); }
        public static void SetSoftness(float v) { if (Ground != null) Ground.softnessScale = Mathf.Clamp(v, 0.3f, 3f); }
        public static void SetRutRelax(float v) { if (Ground != null) Ground.rutRelaxScale = Mathf.Clamp(v, 0f, 6f); }
        public static void SetWetness(float v) { if (Ground != null) Ground.SetWetness(v); }
        public static void ResetGroundTuning() { if (Ground != null) { Ground.mudDepthScale = 1f; Ground.softnessScale = 1f; Ground.rutRelaxScale = 1f; Ground.wetness = 0.3f; } }

        /// <summary>0 off, 1 surface type, 2 dh, 3 churn (see Ground shader _MR_DebugMode).</summary>
        public static void SetGroundDebugView(int mode) { Shader.SetGlobalFloat("_MR_DebugMode", mode); GroundDebugMode = mode; }
        public static int GroundDebugMode { get; private set; }

        // ------------------------------------------------------------------ weather / time

        public static AtmosphereController Atmosphere(bool create = true)
        {
            var a = AtmosphereController.Instance;
            if (a == null && create) { var go = new GameObject("Atmosphere"); a = go.AddComponent<AtmosphereController>(); }
            return a;
        }

        public static void SetRain(bool on) { Atmosphere()?.SetRainOn(on); }
        public static void SetRainIntensity(float v) { Atmosphere()?.SetRain(v); }
        public static void SetTimeOfDay(float hour) { Atmosphere()?.SetTime(hour); }
        public static void SetTimeLapse(float minutesPerSecond) { var a = Atmosphere(); if (a != null) a.minutesPerSecond = Mathf.Max(0f, minutesPerSecond); }

        // ------------------------------------------------------------------ time

        public static void SetSlowMotion(float scale)
        {
            UiState.SlowMotion = Mathf.Clamp(scale, 0.02f, 1f);
            UiTime.Refresh();
        }

        // ------------------------------------------------------------------ drivetrain / winch

        public static void ToggleAwd() { Player?.ToggleAwd(); }
        public static void ToggleLowRange() { Player?.ToggleLowRange(); }
        public static void ToggleFrontLock() { Player?.ToggleAxleLock(0); }
        public static void ToggleRearLock() { var p = Player; if (p == null) return; for (int a = 1; a < p.def.axles.Length; a++) p.ToggleAxleLock(a); }
        public static void ToggleCentreLock() { Player?.ToggleCentreLock(); }
        public static void ToggleEngine() { Player?.ToggleEngine(); }
        public static void ToggleGearMode() { Player?.ToggleGearMode(); }
        public static bool WinchAutoAnchor() { var p = Player; if (p == null || p.winch == null) return false; bool ok = p.winch.TryAutoAttach(); Hud.Notify(ok ? "Winch auto-anchored" : "No anchor in range", 2f, ok ? NoteKind.Good : NoteKind.Warn); return ok; }
        public static void WinchDetach() { var p = Player; if (p != null && p.winch != null) p.winch.Detach(); }

        // ------------------------------------------------------------------ test suite (reflection: the class is added later by the lead)

        public static string LastSuiteResult { get; private set; } = "";

        /// <summary>Starts the in-game physics test suite (MudRunner.Testing.RuntimePhysicsSuite). The suite swaps the world for test arenas and restores it afterwards.</summary>
        public static bool RunPhysicsSuite(bool quick = false)
        {
            try
            {
                var suite = RuntimePhysicsSuite.Run(quick);
                LastSuiteResult = suite != null && suite.Running ? "physics suite running..." : "physics suite started";
                Hud.Notify("Physics test suite started" + (quick ? " (quick)" : ""), 3f, NoteKind.Good);
                return suite != null;
            }
            catch (Exception ex)
            {
                LastSuiteResult = "Suite failed to start: " + ex.Message; Debug.LogException(ex);
                Hud.Notify(LastSuiteResult, 4f, NoteKind.Bad);
                return false;
            }
        }

        /// <summary>One-line status of the suite for the debug window.</summary>
        public static string SuiteStatus()
        {
            var s = RuntimePhysicsSuite.Instance;
            if (s == null) return LastSuiteResult;
            if (s.Running) return "running " + Mathf.RoundToInt(s.Progress * 100f) + "%  " + s.Status;
            if (s.Lines.Count > 0) return "done: " + s.Passed + " passed, " + s.Failed + " failed   (" + RuntimePhysicsSuite.ReportPath + ")";
            return LastSuiteResult;
        }
    }

    /// <summary>Frame-time benchmark: records N seconds of frame times and reports average / 1% low / 0.1% low / worst / hitches.</summary>
    public sealed class Benchmark
    {
        public bool Running { get; private set; }
        public float Duration = 20f;
        public float Elapsed { get; private set; }
        public bool HasResult { get; private set; }
        public float Avg, Min, Max, Low1, Low01, AvgMs, WorstMs; public int Frames, Hitches; public long GcDelta;
        System.Collections.Generic.List<float> samples = new System.Collections.Generic.List<float>(4096);
        long gc0; BotDriver bot;

        public void Start(float seconds, bool autoDrive)
        {
            Duration = seconds; Elapsed = 0f; samples.Clear(); Running = true; HasResult = false;
            gc0 = GC.GetTotalMemory(false);
            var p = GameManager.Instance != null ? GameManager.Instance.Player : null;
            if (autoDrive && p != null)
            {
                bot = p.GetComponent<BotDriver>(); if (bot == null) bot = p.gameObject.AddComponent<BotDriver>();
                bot.vehicle = p; bot.targetSpeed = 7f; bot.useWaypoints = false; bot.tractionControl = true;
            }
        }

        public void Stop(bool finish)
        {
            if (!Running) return;
            Running = false;
            if (bot != null) { UnityEngine.Object.Destroy(bot); bot = null; }
            if (finish) Compute();
        }

        public void Tick(float dt)
        {
            if (!Running) return;
            samples.Add(dt); Elapsed += dt;
            if (Elapsed >= Duration) Stop(true);
        }

        void Compute()
        {
            Frames = samples.Count; if (Frames == 0) return;
            var a = samples.ToArray(); Array.Sort(a);
            float sum = 0f; Hitches = 0;
            foreach (var s in a) { sum += s; if (s > 0.0334f) Hitches++; }
            AvgMs = sum / Frames * 1000f; Avg = Frames / sum; Min = 1f / a[Frames - 1]; Max = 1f / a[0]; WorstMs = a[Frames - 1] * 1000f;
            int k1 = Mathf.Max(1, Mathf.CeilToInt(Frames * 0.01f)), k01 = Mathf.Max(1, Mathf.CeilToInt(Frames * 0.001f));
            float s1 = 0f, s01 = 0f;
            for (int i = 0; i < k1; i++) s1 += a[Frames - 1 - i];
            for (int i = 0; i < k01; i++) s01 += a[Frames - 1 - i];
            Low1 = k1 / s1; Low01 = k01 / s01;
            GcDelta = GC.GetTotalMemory(false) - gc0;
            HasResult = true;
            Debug.Log("[MudRunner] BENCH " + Frames + " frames in " + Elapsed.ToString("F1") + " s: avg " + Avg.ToString("F1") + " fps (" + AvgMs.ToString("F2") + " ms), 1% low " + Low1.ToString("F1")
                + ", 0.1% low " + Low01.ToString("F1") + ", worst " + WorstMs.ToString("F1") + " ms, hitches>33ms " + Hitches + ", gc delta " + (GcDelta / 1024) + " KB, res " + Screen.width + "x" + Screen.height);
        }

        public string Summary()
        {
            if (Running) return "running " + Elapsed.ToString("0.0") + " / " + Duration.ToString("0") + " s   (" + samples.Count + " frames)";
            if (!HasResult) return "no result yet";
            return "avg " + Avg.ToString("0.0") + " fps (" + AvgMs.ToString("0.00") + " ms)\n1% low " + Low1.ToString("0.0") + "   0.1% low " + Low01.ToString("0.0") + "\nmin " + Min.ToString("0.0") + "  max " + Max.ToString("0.0") + "  worst " + WorstMs.ToString("0.0") + " ms\nhitches (>33 ms): " + Hitches + "   GC delta: " + (GcDelta / 1024) + " KB";
        }
    }
}
