using System;
using System.Collections.Generic;
using MudRunner.Ground;
using MudRunner.Testing;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Game
{
    public enum WorldKind { Arena = 0, ProvingGround = 1, Wilderness = 2 }

    /// <summary>A named place the debug menu / map can teleport to.</summary>
    public struct WorldPoint
    {
        public string name; public Vector3 position; public float yaw;
        public WorldPoint(string n, Vector3 p, float y) { name = n; position = p; yaw = y; }
    }

    /// <summary>Everything a world builder returns to the game.</summary>
    public sealed class WorldData
    {
        public WorldKind kind;
        public GroundMap map;
        public Vector3 playerStart; public float playerYaw;
        public List<WorldPoint> points = new List<WorldPoint>();
        public Action<WorldData> onTeardown;
        public GameObject root;
    }

    /// <summary>
    /// Central coordinator: owns the active world, the ground service and the player vehicle, and is the facade the
    /// UI, debug menu, objectives and save system talk to. World content is produced by <see cref="WorldBuilders"/>.
    /// </summary>
    [DefaultExecutionOrder(-200)]
    public sealed class GameManager : MonoBehaviour
    {
        public static GameManager Instance { get; private set; }

        public WorldData World { get; private set; }
        public GroundService Ground { get; private set; }
        public Vehicle Player { get; private set; }
        public PlayerVehicleInput PlayerInput { get; private set; }
        public readonly List<Vehicle> Vehicles = new List<Vehicle>();

        public event Action<WorldData> WorldLoaded;
        public event Action<Vehicle> PlayerChanged;
        public event Action<Vehicle> VehicleSpawned;

        public static readonly string[] VehicleKeys = { "scout", "utility", "hauler" };
        static readonly Dictionary<string, VehicleDefinition> defCache = new Dictionary<string, VehicleDefinition>();

        public bool paused;
        public float recoverFuelCost = 3f, recoverTimePenalty = 20f;
        public float totalPenaltySeconds, totalRecovers;

        void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
        }

        void OnDestroy() { if (Instance == this) Instance = null; }

        public static VehicleDefinition GetDefinition(string key)
        {
            if (defCache.TryGetValue(key, out var d) && d != null) return d;
            var loaded = Resources.Load<VehicleDefinition>("Vehicles/" + key);
            if (loaded == null)
            {
                switch (key)
                {
                    case "scout": loaded = VehicleDefinition.CreateScout(); break;
                    case "utility": loaded = VehicleDefinition.CreateUtility(); break;
                    default: loaded = VehicleDefinition.CreateHauler(); break;
                }
            }
            defCache[key] = loaded;
            return loaded;
        }

        // ------------------------------------------------------------------ worlds

        public WorldData StartWorld(WorldKind kind, string vehicleKey = "utility")
        {
            Teardown();
            World = WorldBuilders.Build(kind);
            // ground service + physics ground
            var gsObj = new GameObject("GroundService");
            gsObj.transform.SetParent(transform, false);
            Ground = gsObj.AddComponent<GroundService>();
            Ground.Initialize(World.map, 0.25f, World.playerStart);
            WorldLoaded?.Invoke(World);
            var v = SpawnVehicle(vehicleKey, World.playerStart, World.playerYaw, true);
            return World;
        }

        public void Teardown()
        {
            foreach (var v in Vehicles) if (v != null) Destroy(v.gameObject);
            Vehicles.Clear();
            Player = null;
            if (World != null) { World.onTeardown?.Invoke(World); if (World.root != null) Destroy(World.root); }
            if (Ground != null) { Ground.Retire(); Destroy(Ground.gameObject); Ground = null; }
            World = null;
        }

        // ------------------------------------------------------------------ vehicles

        public Vehicle SpawnVehicle(string key, Vector3 position, float yawDeg, bool makePlayer)
        {
            var def = GetDefinition(key);
            // ground-level spawn height
            float gy = Ground != null ? Ground.GroundHeight(position.x, position.z) : position.y;
            var a = def.axles[0];
            position.y = gy + (a.tire.radius - a.hubY) + 0.15f;
            var v = VehicleFactory.Create(def, position, Quaternion.Euler(0f, yawDeg, 0f));
            Vehicles.Add(v);
            if (Ground != null) Ground.AddFocus(v.transform);
            VehicleSpawned?.Invoke(v);
            if (makePlayer) SetPlayer(v);
            return v;
        }

        public void SetPlayer(Vehicle v)
        {
            if (Player != null)
            {
                var old = Player.GetComponent<PlayerVehicleInput>();
                if (old != null) Destroy(old);
                var oi = Player.input; oi.throttle = 0; oi.brake = 0; oi.steer = 0; oi.handbrake = true; Player.input = oi;
            }
            Player = v;
            if (v != null)
            {
                PlayerInput = v.GetComponent<PlayerVehicleInput>() ?? v.gameObject.AddComponent<PlayerVehicleInput>();
                PlayerInput.vehicle = v;
                var i = v.input; i.handbrake = false; v.input = i;
                if (Ground != null) Ground.focus = v.transform;
            }
            PlayerChanged?.Invoke(v);
        }

        public Vehicle SwitchPlayerVehicle(string key)
        {
            Vector3 pos = Player != null ? Player.transform.position + Player.transform.forward * 0f : World.playerStart;
            float yaw = Player != null ? Player.transform.eulerAngles.y : World.playerYaw;
            if (Player != null) { Vehicles.Remove(Player); Destroy(Player.gameObject); Player = null; }
            return SpawnVehicle(key, pos, yaw, true);
        }

        public void TeleportPlayer(Vector3 pos, float yawDeg)
        {
            if (Player == null) return;
            if (Ground != null) Ground.Field.Recenter(pos, true);
            float gy = Ground != null ? Ground.GroundHeight(pos.x, pos.z) : pos.y;
            var a = Player.def.axles[0];
            pos.y = gy + (a.tire.radius - a.hubY) + 0.2f;
            Player.transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, yawDeg, 0f));
            Player.rb.position = pos; Player.rb.rotation = Quaternion.Euler(0f, yawDeg, 0f);
            Player.rb.linearVelocity = Vector3.zero; Player.rb.angularVelocity = Vector3.zero;
            foreach (var w in Player.wheels) { w.omega = 0f; w.length = w.prevLength = w.restLength; }
        }

        /// <summary>Limited vehicle recovery with a visible cost (fuel + time penalty).</summary>
        public bool RecoverPlayer()
        {
            if (Player == null) return false;
            Player.fuel = Mathf.Max(0f, Player.fuel - recoverFuelCost);
            totalPenaltySeconds += recoverTimePenalty; totalRecovers++;
            var p = Player.transform.position;
            Player.ResetUpright(p + Vector3.up * 1.2f);
            return true;
        }

        void Update()
        {
            if (Player != null && PlayerInput != null && PlayerInput.wantsRecover) RecoverPlayer();
        }
    }

    /// <summary>Factory table for the available world builders. Other modules register theirs here.</summary>
    public static class WorldBuilders
    {
        public static readonly Dictionary<WorldKind, Func<WorldData>> Registry = new Dictionary<WorldKind, Func<WorldData>>();

        public static WorldData Build(WorldKind kind)
        {
            if (Registry.TryGetValue(kind, out var f)) return f();
            return DemoArena.Build(kind);
        }
    }

    /// <summary>Code-built fallback world: firm field with shallow/deep mud strips, a bog pit and a mud hill. Used for tests and as default until the real world builders register.</summary>
    public static class DemoArena
    {
        public static WorldData Build(WorldKind kind)
        {
            const float size = 400f;
            var map = TestArena.CreateMap(size, 1f,
                (x, z) =>
                {
                    float h = 0f;
                    // mud hill at x in [60,100], z in [-40, 40]: ramp 14 deg then plateau
                    float dx = x - 80f, dz = z;
                    if (Mathf.Abs(dz) < 25f) { float t = Mathf.Clamp01((x - 40f) / 40f); h += Mathf.SmoothStep(0, 1, t) * 9f * Mathf.Clamp01(1f - (x - 120f) / 30f); }
                    // gentle rolling
                    h += Mathf.Sin(x * 0.03f) * Mathf.Cos(z * 0.025f) * 0.6f;
                    return h;
                },
                (x, z) =>
                {
                    if (x > -150f && x < -110f && z > -60f && z < -20f) return SurfaceType.ShallowMud;
                    if (x > -150f && x < -110f && z > -20f && z < 20f) return SurfaceType.DeepMud;
                    if (x > -150f && x < -110f && z > 20f && z < 60f) return SurfaceType.Bog;
                    if (x > 40f && x < 130f && Mathf.Abs(z) < 25f) return SurfaceType.ShallowMud;
                    if (z > 80f && z < 160f && x > -60f && x < 60f) return SurfaceType.Grass;
                    if (Mathf.Abs(x) < 6f && z < -60f) return SurfaceType.Gravel;
                    return SurfaceType.FirmSoil;
                });
            var w = new WorldData { kind = kind, map = map, playerStart = new Vector3(0, 0, -100), playerYaw = 0f };
            w.points.Add(new WorldPoint("Start", w.playerStart, 0f));
            w.points.Add(new WorldPoint("Mud pits", new Vector3(-90, 0, 0), 270f));
            w.points.Add(new WorldPoint("Mud hill", new Vector3(10, 0, 0), 90f));
            return w;
        }
    }
}
