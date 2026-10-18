using System;
using System.Collections.Generic;
using System.Diagnostics;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Rendering;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace MudRunner.WorldGen
{
    /// <summary>Component on the world root giving access to the generated data (tests, objectives, tools).</summary>
    public sealed class WorldHandle : MonoBehaviour
    {
        public GeneratedWorld world;
        public WorldSites sites => world != null ? world.sites : null;
        public InstancedPropRenderer props;
        public PropColliderPool colliders;
        public GroundRenderer groundRenderer;
        public Terrain groundCollider;
        public GameObject water;
        public int structureCount, waterQuads;
        public double buildMs, generateMs;
    }

    /// <summary>Registers the world builders with <see cref="WorldBuilders"/> (no scene wiring needed).</summary>
    public static class WorldRegistration
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Register()
        {
            WorldBuilders.Registry[WorldKind.Wilderness] = WildernessBuilder.Build;
            WorldBuilders.Registry[WorldKind.ProvingGround] = ProvingGroundBuilder.Build;
        }

        /// <summary>For tests / editor tools running before the runtime initialiser.</summary>
        public static void EnsureRegistered()
        {
            if (!WorldBuilders.Registry.ContainsKey(WorldKind.Wilderness)) WorldBuilders.Registry[WorldKind.Wilderness] = WildernessBuilder.Build;
            if (!WorldBuilders.Registry.ContainsKey(WorldKind.ProvingGround)) WorldBuilders.Registry[WorldKind.ProvingGround] = ProvingGroundBuilder.Build;
        }
    }

    /// <summary>The 2 km wilderness: forest, river Silverrun, swamp, three routes (see Docs/WORLD_SPEC.md).</summary>
    public static class WildernessBuilder
    {
        public static WorldData Build() { return Build(new WorldGenConfig { full = true }); }

        public static WorldData Build(WorldGenConfig cfg)
        {
            cfg.full = true;
            var gw = WorldGenerator.Generate(cfg);
            return WorldInstantiator.Instantiate(gw, WorldKind.Wilderness);
        }
    }

    /// <summary>The compact proving ground (mud pits, hill, side slope, articulation, ford, log pile, measuring area).</summary>
    public static class ProvingGroundBuilder
    {
        public static WorldData Build() { return Build(new WorldGenConfig { full = false }); }

        public static WorldData Build(WorldGenConfig cfg)
        {
            cfg.full = false;
            var gw = WorldGenerator.Generate(cfg);
            return WorldInstantiator.Instantiate(gw, WorldKind.ProvingGround);
        }
    }

    /// <summary>Turns a <see cref="GeneratedWorld"/> into GameObjects + a <see cref="WorldData"/>.</summary>
    public static class WorldInstantiator
    {
        public static WorldData Instantiate(GeneratedWorld gw, WorldKind kind, bool visuals = true)
        {
            var sw = Stopwatch.StartNew();
            var map = gw.map;
            var data = new WorldData { kind = kind, map = map };
            var root = new GameObject(kind == WorldKind.Wilderness ? "World_Wilderness" : "World_ProvingGround");
            data.root = root;
            var handle = root.AddComponent<WorldHandle>();
            handle.world = gw;
            WorldSites.Current = gw.sites;

            data.playerStart = gw.sites.playerStart;
            data.playerYaw = gw.sites.playerYaw;
            BuildPoints(gw, data);

            var lib = PropLibraries.Current;
            // physical ground (terrain collider only, never drawn)
            handle.groundCollider = GroundColliderBuilder.Create(map, root.transform);
            handle.generateMs = gw.timings.TryGetValue("TOTAL", out var tms) ? tms : 0;
            double tCollider = sw.Elapsed.TotalMilliseconds;

            if (visuals)
            {
                // ground renderer: builds itself from the GroundService map on Start (GameManager creates the service right after us)
                handle.groundRenderer = EnsureGroundRenderer(root.transform);
                if (Application.isPlaying) EnsureAtmosphere();
                if (gw.water != null)
                {
                    handle.water = WaterSurfaceMesh.Build(gw.water, map, root.transform, WaterSurfaceMesh.CreateMaterial(), out handle.waterQuads);
                }
                if (gw.props != null && gw.props.Count > 0)
                {
                    var pr = new GameObject("InstancedProps");
                    pr.transform.SetParent(root.transform, false);
                    var ipr = pr.AddComponent<InstancedPropRenderer>();
                    ipr.Init(gw.props, lib);
                    handle.props = ipr;
                    var cp = new GameObject("PropColliders");
                    cp.transform.SetParent(root.transform, false);
                    var pool = cp.AddComponent<PropColliderPool>();
                    pool.Init(gw.props, lib);
                    handle.colliders = pool;
                }
            }
            if (gw.props != null)
            {
                var st = new GameObject("Structures");
                st.transform.SetParent(root.transform, false);
                handle.structureCount = WorldObjects.SpawnAll(st.transform, gw.props, lib);
            }
            var guard = root.AddComponent<WorldBoundaryGuard>();
            guard.map = map; guard.safePoint = data.playerStart; guard.safeYaw = data.playerYaw;
            guard.kind = kind;

            WorldUiBridge.Register(gw, data);

            // scenario sites for the objective system
            var ws = gw.sites;
            if (gw.cfg.full)
            {
                if (ws.TryGet("FordF1", out var f1)) ws.AddGoal("Ford", f1.position, 26f);
                if (ws.TryGet("BaseCamp", out var bcs)) ws.AddGoal("Base camp", bcs.position, 26f);
            }
            System.Func<string, (bool, Vector3, float)> resolver = name =>
            {
                if (ws.Resolve(name, out var p, out var r)) return (true, p, r);
                foreach (var wp in data.points) if (string.Equals(wp.name, name, System.StringComparison.OrdinalIgnoreCase)) return (true, wp.position, 16f);
                return (false, Vector3.zero, 14f);
            };
            MudRunner.Objectives.ObjectiveManager.SiteResolver = resolver;

            // pre-carved ruts need the mud field, which GameManager creates after the builder returns
            var gm = GameManager.Instance;
            if (gm != null)
            {
                Action<WorldData> onLoaded = null;
                onLoaded = w =>
                {
                    if (w != data) return;
                    gm.WorldLoaded -= onLoaded;
                    if (gm.Ground != null && gm.Ground.Field != null) WorldRuts.Apply(gm.Ground.Field, gw);
                };
                gm.WorldLoaded += onLoaded;
            }
            data.onTeardown = d =>
            {
                if (WorldSites.Current == gw.sites) WorldSites.Current = null;
                if (MudRunner.Objectives.ObjectiveManager.SiteResolver == resolver) MudRunner.Objectives.ObjectiveManager.SiteResolver = null;
                WorldUiBridge.Unregister(gw);
            };
            handle.buildMs = sw.Elapsed.TotalMilliseconds + handle.generateMs;
            Debug.Log("[MudRunner] World '" + root.name + "' built: generation " + handle.generateMs.ToString("F0") + " ms, instantiate " + sw.ElapsedMilliseconds + " ms (collider " + tCollider.ToString("F0") +
                      " ms), structures " + handle.structureCount + ", water quads " + handle.waterQuads + ", prop instances " + (gw.props != null ? gw.props.Count : 0));
            return data;
        }

        /// <summary>
        /// One live GroundRenderer per world. Renderers of earlier worlds (children of a WorldHandle root that may still be
        /// pending its deferred Destroy this frame) are retired explicitly, so a world restart in the same frame always gets
        /// a fresh renderer. A renderer that is not part of a world (placed in the scene by someone else) is reused.
        /// </summary>
        static GroundRenderer EnsureGroundRenderer(Transform worldRoot)
        {
            GroundRenderer reuse = null;
            foreach (var old in UnityEngine.Object.FindObjectsByType<GroundRenderer>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (old == null) continue;
                if (old.GetComponentInParent<WorldHandle>(true) != null)
                {
                    old.gameObject.SetActive(false);                    // hidden at once, destroyed with (or instead of) the old world root
                    if (Application.isPlaying) UnityEngine.Object.Destroy(old.gameObject); else UnityEngine.Object.DestroyImmediate(old.gameObject);
                }
                else if (reuse == null && old.gameObject.activeInHierarchy) reuse = old;
            }
            if (reuse != null) return reuse;
            var gr = new GameObject("GroundRenderer");
            gr.transform.SetParent(worldRoot, false);
            var r = gr.AddComponent<GroundRenderer>();
            r.buildFromGroundService = true;                            // builds itself from the GroundService map GameManager creates next
            return r;
        }

        /// <summary>Time of day / weather controller (persists across worlds) plus a sun if the scene has none.</summary>
        static void EnsureAtmosphere()
        {
            if (RenderSettings.sun == null)
            {
                Light dir = null;
                foreach (var l in UnityEngine.Object.FindObjectsByType<Light>(FindObjectsSortMode.None))
                    if (l != null && l.type == LightType.Directional) { dir = l; break; }
                if (dir == null)
                {
                    var sg = new GameObject("Sun");
                    dir = sg.AddComponent<Light>();
                    dir.type = LightType.Directional; dir.intensity = 1.6f; dir.color = new Color(1f, 0.96f, 0.88f);
                    dir.shadows = LightShadows.Soft;
                    sg.transform.rotation = Quaternion.Euler(52f, -35f, 0f);
                }
                RenderSettings.sun = dir;
            }
            var at = MudRunner.Atmosphere.AtmosphereController.Instance;
            if (at == null) at = UnityEngine.Object.FindFirstObjectByType<MudRunner.Atmosphere.AtmosphereController>();
            if (at == null)
            {
                var ag = new GameObject("Atmosphere");
                at = ag.AddComponent<MudRunner.Atmosphere.AtmosphereController>();
            }
            if (at.sun == null) at.sun = RenderSettings.sun;
        }

        static void BuildPoints(GeneratedWorld gw, WorldData data)
        {
            var ws = gw.sites; var map = gw.map;
            // teleport point on the track a few metres BEFORE the site (so fords, bridges and buildings are never spawned inside)
            void AddTrack(string name, string siteKey, float back)
            {
                if (!ws.TryGet(siteKey, out var s)) return;
                Track best = null; int bi = 0; float bd = float.MaxValue;
                foreach (var t in gw.tracks.tracks)
                {
                    int i = t.NearestIndex(s.position.x, s.position.z);
                    float d = (new Vector2(t.x[i], t.z[i]) - new Vector2(s.position.x, s.position.z)).sqrMagnitude;
                    if (d < bd) { bd = d; best = t; bi = i; }
                }
                if (best == null || bd > 80f * 80f) { data.points.Add(new WorldPoint(name, s.position, 0f)); return; }
                float len = Mathf.Max(0f, best.s[bi] - back);
                Vector3 p = best.AtLength(len);
                int j = best.NearestIndex(p.x, p.z);
                data.points.Add(new WorldPoint(name, new Vector3(p.x, map.SampleHeight(p.x, p.z), p.z), best.Yaw(j)));
            }
            if (gw.cfg.full)
            {
                data.points.Add(new WorldPoint("Base camp", data.playerStart, data.playerYaw));
                if (ws.TryGet("GarageEntrance", out var ge)) data.points.Add(new WorldPoint("Garage", ge.position, 0f));
                AddTrack("Sawmill", "Sawmill", 22f); AddTrack("Ford F1", "FordF1", 55f); AddTrack("Old bridge B1", "OldBridgeB1", 35f); AddTrack("Ford F2", "FordF2", 45f);
                AddTrack("Bridge B2", "BridgeB2", 35f); AddTrack("Creek ford", "CreekFord", 40f); AddTrack("Widowmaker mud hill", "Widowmaker", 60f); AddTrack("Deep crossing", "DeepCrossing", 45f);
                AddTrack("Logging landing", "LoggingLanding", 25f); AddTrack("Watchtower", "Watchtower", 20f); AddTrack("Radio mast", "RadioMast", 16f); AddTrack("Pump station", "PumpStation", 22f);
                AddTrack("Swamp entrance", "SwampEntrance", 45f); AddTrack("Proving ground gate", "ProvingGroundGate", 0f);
                if (ws.TryGet("Cabin", out var cb)) data.points.Add(new WorldPoint("Cabin", new Vector3(cb.position.x - 2f, map.SampleHeight(cb.position.x - 2f, cb.position.z + 18f), cb.position.z + 18f), 180f));
            }
            ProvingGroundPlacer.AddPoints(gw, data);
        }

        public static float NearestTrackYaw(GeneratedWorld gw, Vector3 p)
        {
            float best = float.MaxValue; float yaw = 0f;
            foreach (var t in gw.tracks.tracks)
            {
                int i = t.NearestIndex(p.x, p.z);
                float d = (new Vector2(t.x[i], t.z[i]) - new Vector2(p.x, p.z)).sqrMagnitude;
                if (d < best) { best = d; yaw = t.Yaw(i); }
            }
            return best < 60f * 60f ? yaw : 0f;
        }
    }

    /// <summary>Safety net: puts the player back at a safe point when it leaves the world (or falls through).</summary>
    public sealed class WorldBoundaryGuard : MonoBehaviour
    {
        public GroundMap map;
        public Vector3 safePoint; public float safeYaw;
        public WorldKind kind;
        float timer;

        void Update()
        {
            timer -= Time.unscaledDeltaTime;
            if (timer > 0f) return;
            timer = 0.5f;
            var gm = GameManager.Instance;
            if (gm == null || gm.Player == null || map == null) return;
            Vector3 p = gm.Player.transform.position;
            float lim = map.WorldSize * 0.5f - 12f;
            Vector2 c = map.Center;
            bool outside = Mathf.Abs(p.x - c.x) > lim || Mathf.Abs(p.z - c.y) > lim;
            bool below = map.Contains(p.x, p.z) && p.y < map.SampleHeight(p.x, p.z) - 40f;
            if (outside || below) gm.TeleportPlayer(safePoint, safeYaw);
        }
    }
}
