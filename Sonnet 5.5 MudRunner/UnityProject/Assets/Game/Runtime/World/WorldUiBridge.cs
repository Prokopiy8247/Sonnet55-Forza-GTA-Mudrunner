using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.UI;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Hands the world's named places to the HUD: map markers (sites, garage, fuel, hazards), the route polylines for the map, and the
    /// garage zone(s) where the vehicle can be switched / refuelled. Kept in one small file so the coupling to the UI layer stays obvious.
    /// </summary>
    public static class WorldUiBridge
    {
        static readonly List<MapMarkers.Marker> mine = new List<MapMarkers.Marker>();

        public static void Register(GeneratedWorld gw, WorldData data)
        {
            Unregister(null);
            var ws = gw.sites;
            foreach (var kv in ws.sites)
            {
                var s = kv.Value;
                MapMarkers.Kind kind = MapMarkers.Kind.Site;
                string label = Pretty(s.name);
                switch (s.name)
                {
                    case "BaseCamp": kind = MapMarkers.Kind.Camp; label = "Base camp"; break;
                    case "Garage": kind = MapMarkers.Kind.Garage; label = "Garage"; break;
                    case "FuelStation": kind = MapMarkers.Kind.Fuel; label = "Fuel station"; break;
                    case "GarageEntrance": continue;
                    case "PlayerStart": continue;
                    case "DeepCrossing": case "SwampEntrance": case "OldBridgeB1": case "BridgeB2": kind = MapMarkers.Kind.Danger; break;
                    case "Widowmaker": label = "Widowmaker hill"; kind = MapMarkers.Kind.Danger; break;
                }
                mine.Add(MapMarkers.Add(label, s.position, kind, s.radius));
            }
            foreach (var r in ws.routes)
                MapMarkers.AddRoute(r.name, Decimate(r.points, 6), r.color);
            // garage zone(s)
            if (data.root != null)
            {
                foreach (var zone in ws.garageZones)
                {
                    var go = new GameObject("GarageZone " + zone.name);
                    go.transform.SetParent(data.root.transform, false);
                    go.transform.position = zone.position;
                    var gz = go.AddComponent<GarageZone>();
                    gz.displayName = zone.name; gz.radius = zone.radius;
                }
            }
        }

        public static void Unregister(GeneratedWorld gw)
        {
            for (int i = 0; i < mine.Count; i++) MapMarkers.Remove(mine[i]);
            mine.Clear();
        }

        static Vector3[] Decimate(Vector3[] p, int step)
        {
            var l = new List<Vector3>(p.Length / step + 2);
            for (int i = 0; i < p.Length; i += step) l.Add(p[i]);
            if ((p.Length - 1) % step != 0) l.Add(p[p.Length - 1]);
            return l.ToArray();
        }

        static string Pretty(string s)
        {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < s.Length; i++)
            {
                if (i > 0 && char.IsUpper(s[i]) && !char.IsUpper(s[i - 1])) sb.Append(' ');
                sb.Append(s[i]);
            }
            return sb.ToString();
        }
    }
}
