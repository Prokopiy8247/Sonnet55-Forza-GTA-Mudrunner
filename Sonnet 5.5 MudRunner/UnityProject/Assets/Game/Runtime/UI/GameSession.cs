using System;
using System.Collections.Generic;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Game
{
    /// <summary>
    /// The scenarios shown in the main menu. This is a thin facade over the objectives system's own list
    /// (<see cref="Scenarios.All"/>, ScenarioDef with stages): every menu entry really runs through
    /// <c>ObjectiveManager.EnsureInstance().StartScenario(def)</c>.
    /// </summary>
    public static class ScenarioCatalog
    {
        public static List<ScenarioDef> All { get { return Scenarios.All; } }

        public static ScenarioDef Find(string id)
        {
            var l = All;
            for (int i = 0; i < l.Count; i++) if (l[i].id == id) return l[i];
            return null;
        }

        public static string DifficultyName(ScenarioDef d) { return d.difficulty >= 3 ? "Hard" : d.difficulty == 2 ? "Medium" : "Easy"; }
    }

    /// <summary>
    /// Choices made in the menus. <see cref="Selected"/> is the scenario the player started (null = free drive); the objectives
    /// worker subscribes to <see cref="ScenarioStarted"/> / reads <see cref="Selected"/> after the world has been created.
    /// </summary>
    public static class GameSession
    {
        public static ScenarioDef Selected;     // MudRunner.Objectives.ScenarioDef chosen in the menu (null = free drive)
        public static string VehicleKey = "utility";
        public static WorldKind World = WorldKind.ProvingGround;
        /// <summary>Set to false (before the Game scene boots) to skip the main menu, e.g. in automated tests.</summary>
        public static bool ShowMainMenuOnStart = true;
        /// <summary>Show the control help for the first seconds of a drive.</summary>
        public static bool ShowHelpOnStart = true;

        /// <summary>Raised after a world + vehicle were created from the menu (Selected is null for free drive).</summary>
        public static event Action<ScenarioDef> ScenarioStarted;
        public static void RaiseStarted() { ScenarioStarted?.Invoke(Selected); }
    }

    /// <summary>Marks a garage: stand inside <see cref="radius"/> and press Enter to switch vehicle, refuel and repair. Worlds add one per garage building.</summary>
    public sealed class GarageZone : MonoBehaviour
    {
        public static readonly List<GarageZone> All = new List<GarageZone>();
        public string displayName = "Garage";
        public float radius = 18f;
        public bool allowVehicleSwitch = true, allowRefuel = true, allowRepair = true;

        void OnEnable() { All.Add(this); }
        void OnDisable() { All.Remove(this); }

        public bool Contains(Vector3 p)
        {
            Vector3 d = p - transform.position; d.y = 0f;
            return d.sqrMagnitude <= radius * radius;
        }

        public static GarageZone Find(Vector3 p)
        {
            GarageZone best = null; float bd = float.MaxValue;
            for (int i = 0; i < All.Count; i++)
            {
                var g = All[i]; if (g == null || !g.isActiveAndEnabled) continue;
                Vector3 d = p - g.transform.position; d.y = 0f;
                float sq = d.sqrMagnitude;
                if (sq <= g.radius * g.radius && sq < bd) { bd = sq; best = g; }
            }
            return best;
        }

        void OnDrawGizmosSelected() { Gizmos.color = Color.green; Gizmos.DrawWireSphere(transform.position, radius); }
    }

    /// <summary>Headlights: two spot lights on the vehicle, toggled with L. Added to the player vehicle by the UI bootstrap.</summary>
    public sealed class VehicleHeadlights : MonoBehaviour
    {
        public bool On { get; private set; }
        public float intensity = 250f, range = 70f, spotAngle = 62f;
        Light left, right;

        public void Toggle() { Set(!On); }

        public void Set(bool on)
        {
            On = on;
            EnsureLights();
            if (left != null) left.enabled = on;
            if (right != null) right.enabled = on;
        }

        void EnsureLights()
        {
            if (left != null) return;
            var v = GetComponent<Vehicle>();
            Vector3 size = v != null && v.def != null ? v.def.bodySize : new Vector3(2f, 1f, 4.5f);
            Vector3 center = v != null && v.def != null ? v.def.bodyCenter : new Vector3(0f, 1f, 0f);
            float z = center.z + size.z * 0.5f - 0.1f, y = center.y - size.y * 0.15f, x = size.x * 0.32f;
            left = Make("HeadlightL", new Vector3(-x, y, z));
            right = Make("HeadlightR", new Vector3(x, y, z));
        }

        Light Make(string n, Vector3 local)
        {
            var go = new GameObject(n);
            go.transform.SetParent(transform, false);
            go.transform.localPosition = local;
            go.transform.localRotation = Quaternion.Euler(4f, 0f, 0f);
            var l = go.AddComponent<Light>();
            l.type = LightType.Spot; l.range = range; l.spotAngle = spotAngle; l.innerSpotAngle = spotAngle * 0.55f;
            l.color = new Color(1f, 0.95f, 0.82f); l.intensity = intensity;
            l.shadows = LightShadows.None;
            l.enabled = false;
            return l;
        }
    }
}
