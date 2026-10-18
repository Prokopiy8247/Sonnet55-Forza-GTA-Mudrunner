using MudRunner.Game;
using MudRunner.Objectives;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>Glue between the UI and the objectives system: start a scenario / free drive, forward objective toasts to the HUD, resolve start sites.</summary>
    public static class ObjectiveBridge
    {
        static bool hooked;

        /// <summary>Starts <paramref name="def"/> on the running world (player vehicle must exist). Returns false on failure.</summary>
        public static bool StartScenario(ScenarioDef def)
        {
            if (def == null) return false;
            var om = ObjectiveManager.EnsureInstance();
            return om.StartScenario(def);
        }

        public static void StartFreeDrive()
        {
            var om = ObjectiveManager.Instance;
            if (om != null) om.StartFreeDrive();
        }

        /// <summary>World position of a scenario start site (objective site resolver first, then the world's teleport points by name).</summary>
        public static bool TryResolveSite(string site, out Vector3 pos, out float yaw)
        {
            pos = Vector3.zero; yaw = 0f;
            if (string.IsNullOrEmpty(site)) return false;
            var gm = GameManager.Instance;
            string want = Norm(site);
            if (gm != null && gm.World != null)
                foreach (var p in gm.World.points)
                    if (Norm(p.name) == want) { pos = p.position; yaw = p.yaw; return true; }
            if (ObjectiveManager.SiteResolver != null)
            {
                var r = ObjectiveManager.SiteResolver(site);
                if (r.found) { pos = r.pos; yaw = gm != null && gm.World != null ? gm.World.playerYaw : 0f; return true; }
            }
            return false;
        }

        static string Norm(string s) { return s == null ? "" : s.Replace(" ", "").Replace("_", "").ToLowerInvariant(); }

        /// <summary>Subscribes the HUD toast to ObjectiveManager.Message (also used by the save system).</summary>
        public static void HookMessages()
        {
            if (hooked) return;
            ObjectiveManager.Message += OnMessage;
            hooked = true;
        }

        public static void Unhook()
        {
            if (!hooked) return;
            ObjectiveManager.Message -= OnMessage;
            hooked = false;
        }

        static void OnMessage(string msg)
        {
            if (string.IsNullOrEmpty(msg)) return;
            // the final "COMPLETE / FAILED ..." text is announced by the HUD's own objective watcher
            if (msg.StartsWith("COMPLETE") || msg.StartsWith("FAILED")) return;
            Hud.Notify(msg, 4.5f, NoteKind.Info);
        }
    }
}
