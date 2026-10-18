using System;
using System.Collections.Generic;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Named places, routes and gameplay data of the generated world (read by objectives, HUD, map, tests).
    /// Plain data, no scene dependencies; <see cref="Current"/> points at the active world's instance.
    /// </summary>
    public sealed class WorldSites
    {
        public static WorldSites Current;

        public struct Site { public string name; public Vector3 position; public float radius; public float yaw; }
        public struct SpawnPoint { public string name; public Vector3 position; public float yaw; }
        public sealed class RouteInfo
        {
            public int id; public string name; public string risk; public string description;
            public Vector3[] points; public float length;
            public Color color;
        }
        public struct BridgeInfo { public string name; public Vector3 center; public float yaw; public float length; public float width; public float maxLoadKg; public bool fragile; public bool broken; }
        public struct FordInfo { public string name; public Vector3 center; public float yaw; public float depth; public float length; public float current; }
        public struct TrapInfo { public string name; public Vector3 position; public float radius; public float depth; public bool decoy; }
        public struct AnchorInfo { public Vector3 position; public string kind; }

        public readonly Dictionary<string, Site> sites = new Dictionary<string, Site>();
        public readonly List<RouteInfo> routes = new List<RouteInfo>();
        public readonly List<SpawnPoint> cargoSpawns = new List<SpawnPoint>();
        public readonly List<SpawnPoint> trailerSpawns = new List<SpawnPoint>();
        public readonly List<BridgeInfo> bridges = new List<BridgeInfo>();
        public readonly List<FordInfo> fords = new List<FordInfo>();
        public readonly List<TrapInfo> traps = new List<TrapInfo>();
        public readonly List<AnchorInfo> anchors = new List<AnchorInfo>();
        public readonly Dictionary<string, Vector3[]> polylines = new Dictionary<string, Vector3[]>();   // all tracks + proving ground loop
        public readonly List<string> provingGroundFeatures = new List<string>();
        public struct GarageZoneInfo { public string name; public Vector3 position; public float radius; }
        public readonly List<GarageZoneInfo> garageZones = new List<GarageZoneInfo>();

        public Vector3 playerStart; public float playerYaw;
        public Rect playableBounds = new Rect(-768f, -768f, 1536f, 1536f);
        public Rect provingGroundBounds = new Rect(750f, -300f, 260f, 600f);

        /// <summary>Goal positions for objectives (named like the scenarios do: "Mud pits" = the end of the lane, "Mud hill" = the plateau, "Ford" = the far bank ...).</summary>
        public readonly Dictionary<string, (Vector3 pos, float radius)> goals = new Dictionary<string, (Vector3, float)>();

        public static string Norm(string n)
        {
            if (string.IsNullOrEmpty(n)) return "";
            var sb = new System.Text.StringBuilder(n.Length);
            foreach (char c in n) if (char.IsLetterOrDigit(c)) sb.Append(char.ToLowerInvariant(c));
            return sb.ToString();
        }

        public void AddGoal(string name, Vector3 pos, float radius) { goals[Norm(name)] = (pos, radius); }

        /// <summary>Resolve a scenario site name (goals first, then the named sites). Used by ObjectiveManager.SiteResolver.</summary>
        public bool Resolve(string name, out Vector3 pos, out float radius)
        {
            string k = Norm(name);
            if (goals.TryGetValue(k, out var g)) { pos = g.pos; radius = g.radius; return true; }
            foreach (var kv in sites) if (Norm(kv.Key) == k) { pos = kv.Value.position; radius = kv.Value.radius; return true; }
            pos = Vector3.zero; radius = 14f; return false;
        }

        public bool TryGet(string name, out Site s) { return sites.TryGetValue(name, out s); }
        public Site Get(string name) { return sites[name]; }
        public bool Has(string name) { return sites.ContainsKey(name); }

        public RouteInfo Route(int id) { foreach (var r in routes) if (r.id == id) return r; return null; }
        public RouteInfo Route(string name) { foreach (var r in routes) if (string.Equals(r.name, name, StringComparison.OrdinalIgnoreCase)) return r; return null; }

        public void Add(string name, Vector3 pos, float radius, float yaw = 0f)
        {
            sites[name] = new Site { name = name, position = pos, radius = radius, yaw = yaw };
        }

        public static float PolylineLength(IList<Vector3> p)
        {
            float l = 0f;
            for (int i = 1; i < p.Count; i++) l += Vector3.Distance(p[i - 1], p[i]);
            return l;
        }

        /// <summary>True when the position lies in the wilderness playable square or the proving ground strip.</summary>
        public bool InsidePlayable(Vector3 p)
        {
            return playableBounds.Contains(new Vector2(p.x, p.z)) || provingGroundBounds.Contains(new Vector2(p.x, p.z));
        }
    }
}
