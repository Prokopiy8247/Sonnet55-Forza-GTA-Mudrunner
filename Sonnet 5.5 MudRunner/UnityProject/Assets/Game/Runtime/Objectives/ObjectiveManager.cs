using System;
using System.Collections.Generic;
using MudRunner.Cargo;
using MudRunner.Game;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Objectives
{
    public enum StageKind { Reach, LoadCargo, Deliver }

    [Serializable]
    public class ObjectiveStage
    {
        public StageKind kind;
        public string site;                // named site (WorldSites) or "pos:x,z"
        public string label;
        public float radius = 14f;
        public string cargoKind = "logs";  // for LoadCargo / Deliver
        public int minCargo = 3;           // for Deliver: minimum cargo items that must arrive
    }

    /// <summary>One scenario: start conditions plus an ordered list of stages. Free drive = no scenario.</summary>
    [Serializable]
    public class ScenarioDef
    {
        public string id;
        public string title;
        [TextArea] public string description;
        public int difficulty;                 // 1 easy .. 3 hard
        public WorldKind world = WorldKind.Wilderness;
        public string vehicle = "utility";
        public bool withTrailer;
        public string startSite = "BaseCamp";
        public float startFuelFraction = 0.9f;
        public float timeLimitSeconds = -1f;   // < 0: none
        public float fuelLimitLitres = -1f;    // > 0: start fuel is clamped to this and running out fails the scenario
        public List<ObjectiveStage> stages = new List<ObjectiveStage>();
    }

    /// <summary>
    /// Objective/scenario runner. Keeps its HUD-facing fields (title, detail, target, timers) current; the HUD only reads them.
    /// Sites are resolved by <see cref="SiteResolver"/> (the world builder registers named sites there).
    /// </summary>
    public sealed class ObjectiveManager : MonoBehaviour
    {
        public static ObjectiveManager Instance { get; private set; }

        // ---- HUD-facing
        public string title = "Free drive";
        public string detail = "Explore the map. No objectives.";
        public bool hasTarget;
        public Vector3 targetPosition;
        public float targetRadius = 12f;
        public float timeLeft = -1f;           // < 0 = no timer
        public float fuelLimit = -1f;          // < 0 = no fuel limit
        public string cargoStatus = "";
        public bool completed, failed;
        public string resultText = "";

        // ---- state
        public ScenarioDef Active { get; private set; }
        public int StageIndex { get; private set; }
        public float Elapsed { get; private set; }
        public float fuelAtStart;
        public int stuckEvents, winchUses;
        public static Action<string> Message;                 // HUD toast hook (UI worker subscribes)
        public static event Action<ScenarioDef> ScenarioStarted;
        public static event Action<bool, string> ScenarioFinished;

        /// <summary>Resolve a named site to (position, radius). Set by the world builder / WorldSites.</summary>
        public static Func<string, (bool found, Vector3 pos, float radius)> SiteResolver;

        float stuckPrev;

        void Awake() { Instance = this; }
        void OnDestroy() { if (Instance == this) Instance = null; }

        public static ObjectiveManager EnsureInstance()
        {
            if (Instance != null) return Instance;
            var go = new GameObject("ObjectiveManager");
            var gm = GameManager.Instance; if (gm != null) go.transform.SetParent(gm.transform, false);
            return go.AddComponent<ObjectiveManager>();
        }

        public float DistanceToTarget(Vector3 from) { return hasTarget ? Vector3.Distance(new Vector3(from.x, 0, from.z), new Vector3(targetPosition.x, 0, targetPosition.z)) : 0f; }

        static bool ResolveSite(string site, out Vector3 pos, out float radius)
        {
            pos = Vector3.zero; radius = 14f;
            if (string.IsNullOrEmpty(site)) return false;
            if (site.StartsWith("pos:"))
            {
                var p = site.Substring(4).Split(',');
                if (p.Length == 2 && float.TryParse(p[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float x) &&
                    float.TryParse(p[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float z))
                { pos = new Vector3(x, 0, z); return true; }
                return false;
            }
            if (SiteResolver != null) { var r = SiteResolver(site); if (r.found) { pos = r.pos; radius = r.radius; return true; } }
            var gm = GameManager.Instance;
            if (gm != null && gm.World != null)
                foreach (var wp in gm.World.points) if (string.Equals(wp.name, site, StringComparison.OrdinalIgnoreCase)) { pos = wp.position; return true; }
            return false;
        }

        // ------------------------------------------------------------------ scenario control

        public void StartFreeDrive()
        {
            Active = null; completed = failed = false; hasTarget = false; timeLeft = -1f; fuelLimit = -1f; cargoStatus = "";
            title = "Free drive"; detail = "Explore the map. No objectives."; resultText = "";
        }

        public bool StartScenario(ScenarioDef def)
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.Player == null) return false;
            Active = def; StageIndex = 0; Elapsed = 0f; completed = failed = false; resultText = ""; stuckEvents = winchUses = 0;
            title = def.title; timeLeft = def.timeLimitSeconds; fuelLimit = def.fuelLimitLitres;
            var v = gm.Player;
            if (def.fuelLimitLitres > 0f) v.fuel = Mathf.Min(def.fuelLimitLitres, v.def.fuelCapacity);
            else v.fuel = v.def.fuelCapacity * def.startFuelFraction;
            fuelAtStart = v.fuel;
            gm.totalPenaltySeconds = 0f; gm.totalRecovers = 0;
            if (def.withTrailer) { var ts = TrailerSystem.EnsureInstance(); ts.Attach(v); }
            EnterStage();
            ScenarioStarted?.Invoke(def);
            return true;
        }

        public void RestoreProgress(int stage, float elapsed)
        {
            if (Active == null) return;
            StageIndex = Mathf.Clamp(stage, 0, Active.stages.Count); Elapsed = elapsed;
            EnterStage();
        }

        void EnterStage()
        {
            if (Active == null) return;
            if (StageIndex >= Active.stages.Count) { Finish(true, "All objectives complete."); return; }
            var st = Active.stages[StageIndex];
            hasTarget = ResolveSite(st.site, out targetPosition, out float r);
            targetRadius = st.radius > 0 ? st.radius : r;
            string label = string.IsNullOrEmpty(st.label) ? st.kind + " " + st.site : st.label;
            detail = "[" + (StageIndex + 1) + "/" + Active.stages.Count + "] " + label;
            Message?.Invoke(detail);
        }

        void Finish(bool success, string text)
        {
            completed = success; failed = !success; hasTarget = false;
            var gm = GameManager.Instance;
            float fuelUsed = gm != null && gm.Player != null ? Mathf.Max(0f, fuelAtStart - gm.Player.fuel) : 0f;
            float score = Elapsed + (gm != null ? gm.totalPenaltySeconds : 0f);
            resultText = (success ? "COMPLETE" : "FAILED") + " - " + text + "\ntime " + FormatTime(Elapsed) + " (+" + (gm != null ? gm.totalPenaltySeconds : 0f).ToString("F0") + " s recover penalties)  fuel used " + fuelUsed.ToString("F1") + " L  recoveries " + (gm != null ? gm.totalRecovers : 0) + "  stuck events " + stuckEvents + "  winch uses " + winchUses;
            detail = resultText;
            Message?.Invoke(resultText);
            ScenarioFinished?.Invoke(success, resultText);
        }

        public static string FormatTime(float s) { int m = (int)(s / 60f); return m + ":" + ((int)s % 60).ToString("00"); }

        // ------------------------------------------------------------------ update

        void Update()
        {
            var gm = GameManager.Instance;
            if (Active == null || completed || failed || gm == null || gm.Player == null) return;
            var v = gm.Player;
            Elapsed += Time.deltaTime;
            if (Active.timeLimitSeconds > 0f)
            {
                timeLeft = Active.timeLimitSeconds - Elapsed - gm.totalPenaltySeconds;
                if (timeLeft <= 0f) { Finish(false, "Out of time."); return; }
            }
            if (Active.fuelLimitLitres > 0f && v.fuel <= 0.01f && v.speed < 0.5f) { Finish(false, "Out of fuel."); return; }
            if (v.isStuck && stuckPrev <= 0.5f) stuckEvents++;
            stuckPrev = v.isStuck ? 1f : 0f;
            if (v.winch != null && v.winch.Attached && Mathf.Abs(v.winch.input) > 0.1f && v.winch.IsTaut && Time.frameCount % 120 == 0) winchUses++;

            var ts = TrailerSystem.Instance;
            cargoStatus = ts != null && ts.CargoCount > 0 ? ts.CargoDescription + ": " + ts.CargoOnDeck + "/" + ts.CargoCount + " (" + ts.CargoMass.ToString("F0") + " kg)" : "";

            if (StageIndex >= Active.stages.Count) return;
            var st = Active.stages[StageIndex];
            if (!hasTarget) { hasTarget = ResolveSite(st.site, out targetPosition, out _); if (!hasTarget) return; }
            Vector3 p = v.transform.position;
            bool inside = DistanceToTarget(p) < targetRadius;
            if (!inside) return;
            switch (st.kind)
            {
                case StageKind.Reach: Advance("Reached " + st.site); break;
                case StageKind.LoadCargo:
                    {
                        var t = TrailerSystem.EnsureInstance();
                        if (!t.HasTrailer) t.Attach(v);
                        t.LoadCargo(st.cargoKind);
                        Advance("Cargo loaded: " + t.CargoDescription);
                        break;
                    }
                case StageKind.Deliver:
                    {
                        if (ts == null || !ts.HasTrailer) { detail = "You need the trailer with cargo."; break; }
                        if (ts.CargoOnDeck >= st.minCargo) Advance("Delivered " + ts.CargoOnDeck + "/" + ts.CargoCount + " items");
                        else detail = "Not enough cargo left on the trailer (" + ts.CargoOnDeck + "/" + st.minCargo + ").";
                        break;
                    }
            }
        }

        void Advance(string msg)
        {
            Message?.Invoke(msg);
            StageIndex++;
            if (StageIndex >= Active.stages.Count) Finish(true, msg); else EnterStage();
        }
    }

    /// <summary>Built-in scenario list.</summary>
    public static class Scenarios
    {
        public static readonly List<ScenarioDef> All = Build();

        static List<ScenarioDef> Build()
        {
            var list = new List<ScenarioDef>();
            list.Add(new ScenarioDef
            {
                id = "firm_route", title = "Scouting the Landing", difficulty = 1, world = WorldKind.Wilderness, vehicle = "scout",
                description = "Take the light scout from base camp to the Logging Landing. The north road is long but firm; the shortcuts will bog a light vehicle.",
                timeLimitSeconds = 1500f, startFuelFraction = 0.9f,
                stages = { new ObjectiveStage { kind = StageKind.Reach, site = "LoggingLanding", label = "Drive to the Logging Landing", radius = 16f } },
            });
            list.Add(new ScenarioDef
            {
                id = "timber_run", title = "Timber Run", difficulty = 2, world = WorldKind.Wilderness, vehicle = "hauler", withTrailer = true,
                description = "Take the 6x6 and its trailer to the Logging Landing, load timber, and haul at least 3 of 5 logs back to base camp across the bog.",
                timeLimitSeconds = 2700f, startFuelFraction = 0.8f,
                stages =
                {
                    new ObjectiveStage { kind = StageKind.Reach, site = "LoggingLanding", label = "Drive to the Logging Landing", radius = 16f },
                    new ObjectiveStage { kind = StageKind.LoadCargo, site = "LoggingLanding", label = "Load the timber", radius = 16f, cargoKind = "logs" },
                    new ObjectiveStage { kind = StageKind.Deliver, site = "BaseCamp", label = "Deliver the timber to base camp", radius = 18f, cargoKind = "logs", minCargo = 3 },
                },
            });
            list.Add(new ScenarioDef
            {
                id = "last_gallon", title = "Last Gallon", difficulty = 3, world = WorldKind.Wilderness, vehicle = "utility",
                description = "Reach the cabin in the swamp before the tank runs dry. 40 litres only: the short route through the bog saves fuel if it works.",
                fuelLimitLitres = 40f, timeLimitSeconds = 3000f,
                stages = { new ObjectiveStage { kind = StageKind.Reach, site = "Cabin", label = "Reach the cabin", radius = 16f } },
            });
            list.Add(new ScenarioDef
            {
                id = "proving_gauntlet", title = "Proving Ground Gauntlet", difficulty = 2, world = WorldKind.ProvingGround, vehicle = "utility", startSite = "Proving ground start",
                description = "Run the mud pits, the steep mud hill and the river ford in order.",
                timeLimitSeconds = 1200f,
                stages =
                {
                    new ObjectiveStage { kind = StageKind.Reach, site = "Mud pits", label = "Cross the mud-pit lane", radius = 25f },
                    new ObjectiveStage { kind = StageKind.Reach, site = "Mud hill", label = "Climb the mud hill", radius = 25f },
                    new ObjectiveStage { kind = StageKind.Reach, site = "Ford", label = "Ford the river", radius = 25f },
                },
            });
            return list;
        }
    }
}
