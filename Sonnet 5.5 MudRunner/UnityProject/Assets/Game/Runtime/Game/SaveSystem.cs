using System;
using System.Collections.Generic;
using System.IO;
using MudRunner.Atmosphere;
using MudRunner.Ground;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.InputSystem;

namespace MudRunner.Game
{
    [Serializable]
    public class SaveData
    {
        public int version = 1;
        public string world;
        public string vehicle;
        public Vector3 position;
        public Quaternion rotation;
        public float fuel, damage;
        public float hour, wetness, rain;
        public float mudDepthScale = 1f, softnessScale = 1f;
        public string scenarioId;
        public int stageIndex;
        public float elapsed, penaltySeconds;
        public int recovers;
        public float masterVolume = 1f;
        public int quality;
        public bool lowRange, awd, centreLock;
        public bool[] axleLock;
        public bool hasMud;
        public string savedAt;
    }

    /// <summary>
    /// Persists: current vehicle (+ fuel/damage/driveline state), position, time of day, weather/wetness, objective progress, settings,
    /// and (stretch) the mud-field snapshot so ruts survive a reload. JSON in persistentDataPath/saves, mud snapshot as a compact binary file.
    /// F5 quick-save, F9 quick-load. Loading re-creates the world when needed.
    /// </summary>
    public sealed class SaveSystem : MonoBehaviour
    {
        public static SaveSystem Instance { get; private set; }
        public static string SaveDir => Path.Combine(Application.persistentDataPath, "saves");
        public static string Path_(string slot) => Path.Combine(SaveDir, slot + ".json");
        static string MudPath(string slot) => Path.Combine(SaveDir, slot + ".mud");

        void Awake() { Instance = this; }
        void OnDestroy() { if (Instance == this) Instance = null; }

        public static SaveSystem EnsureInstance()
        {
            if (Instance != null) return Instance;
            var go = new GameObject("SaveSystem");
            var gm = GameManager.Instance; if (gm != null) go.transform.SetParent(gm.transform, false);
            return go.AddComponent<SaveSystem>();
        }

        void Update()
        {
            var kb = Keyboard.current; if (kb == null) return;
            if (kb.f5Key.wasPressedThisFrame) { Save("quick"); Hud_Notify("Game saved"); }
            if (kb.f9Key.wasPressedThisFrame) { if (Load("quick")) Hud_Notify("Game loaded"); else Hud_Notify("No quick-save found"); }
        }

        static void Hud_Notify(string s) { ObjectiveManager.Message?.Invoke(s); }

        // ------------------------------------------------------------------ save

        public bool Save(string slot = "quick")
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.Player == null || gm.World == null) return false;
            var v = gm.Player;
            var d = new SaveData
            {
                world = gm.World.kind.ToString(), vehicle = KeyOf(v.def), position = v.transform.position, rotation = v.transform.rotation,
                fuel = v.fuel, damage = v.damage01, lowRange = v.drivetrain.lowRange, awd = v.drivetrain.awd, centreLock = v.drivetrain.centreLock,
                axleLock = (bool[])v.drivetrain.axleLock.Clone(), masterVolume = AudioListener.volume, quality = QualitySettings.GetQualityLevel(),
                savedAt = DateTime.Now.ToString("s"),
            };
            var gs = gm.Ground;
            if (gs != null) { d.wetness = gs.wetness; d.mudDepthScale = gs.mudDepthScale; d.softnessScale = gs.softnessScale; }
            var at = AtmosphereController.Instance; if (at != null) { d.hour = at.hour; d.rain = at.rain; }
            var om = ObjectiveManager.Instance;
            if (om != null && om.Active != null) { d.scenarioId = om.Active.id; d.stageIndex = om.StageIndex; d.elapsed = om.Elapsed; }
            d.penaltySeconds = gm.totalPenaltySeconds; d.recovers = (int)gm.totalRecovers;
            Directory.CreateDirectory(SaveDir);
            if (gs != null && gs.Field != null) { d.hasMud = WriteMud(gs.Field, MudPath(slot)); }
            File.WriteAllText(Path_(slot), JsonUtility.ToJson(d, true));
            Debug.Log("[MudRunner] saved " + Path_(slot));
            return true;
        }

        static string KeyOf(VehicleDefinition def)
        {
            string n = def.name.ToLowerInvariant();
            foreach (var k in GameManager.VehicleKeys) if (n.Contains(k)) return k;
            return "utility";
        }

        // ------------------------------------------------------------------ load

        public bool Load(string slot = "quick")
        {
            var gm = GameManager.Instance;
            if (gm == null || !File.Exists(Path_(slot))) return false;
            var d = JsonUtility.FromJson<SaveData>(File.ReadAllText(Path_(slot)));
            if (d == null) return false;
            if (!Enum.TryParse(d.world, out WorldKind kind)) kind = WorldKind.ProvingGround;
            if (gm.World == null || gm.World.kind != kind) gm.StartWorld(kind, d.vehicle);
            else if (gm.Player == null || KeyOf(gm.Player.def) != d.vehicle) gm.SwitchPlayerVehicle(d.vehicle);
            var v = gm.Player; if (v == null) return false;
            v.transform.SetPositionAndRotation(d.position, d.rotation);
            v.rb.position = d.position; v.rb.rotation = d.rotation;
            v.rb.linearVelocity = Vector3.zero; v.rb.angularVelocity = Vector3.zero;
            foreach (var w in v.wheels) { w.omega = 0f; w.length = w.prevLength = w.restLength; }
            v.fuel = d.fuel; v.damage01 = d.damage;
            v.drivetrain.lowRange = d.lowRange; v.drivetrain.awd = d.awd; v.drivetrain.centreLock = d.centreLock;
            if (d.axleLock != null) for (int i = 0; i < Mathf.Min(d.axleLock.Length, v.drivetrain.axleLock.Length); i++) v.drivetrain.axleLock[i] = d.axleLock[i];
            var gs = gm.Ground;
            if (gs != null)
            {
                gs.wetness = d.wetness; gs.mudDepthScale = d.mudDepthScale; gs.softnessScale = d.softnessScale;
                gs.Field.Recenter(d.position, true);
                if (d.hasMud && File.Exists(MudPath(slot))) ReadMud(gs.Field, MudPath(slot));
            }
            var at = AtmosphereController.Instance; if (at != null) { at.SetTime(d.hour); at.rain = d.rain; }
            gm.totalPenaltySeconds = d.penaltySeconds; gm.totalRecovers = d.recovers;
            AudioListener.volume = d.masterVolume;
            if (!string.IsNullOrEmpty(d.scenarioId))
            {
                var om = ObjectiveManager.EnsureInstance();
                var def = Scenarios.All.Find(s => s.id == d.scenarioId);
                if (def != null) { om.StartScenario(def); om.RestoreProgress(d.stageIndex, d.elapsed); v.fuel = d.fuel; }
            }
            Debug.Log("[MudRunner] loaded " + Path_(slot));
            return true;
        }

        // ------------------------------------------------------------------ mud snapshot (binary, quantised)

        static bool WriteMud(MudField field, string path)
        {
            var tiles = field.Snapshot();
            using (var bw = new BinaryWriter(File.Create(path)))
            {
                bw.Write(0x4D554431); bw.Write(tiles.Count);
                foreach (var t in tiles)
                {
                    bw.Write(t.wtx); bw.Write(t.wtz);
                    for (int i = 0; i < t.data.Length; i++)
                    {
                        bw.Write((short)Mathf.Clamp(Mathf.RoundToInt(t.data[i].dh * 1000f), short.MinValue, short.MaxValue));
                        bw.Write((byte)Mathf.Clamp(Mathf.RoundToInt(t.data[i].churn * 255f), 0, 255));
                        bw.Write((byte)Mathf.Clamp(Mathf.RoundToInt(t.data[i].compact * 255f), 0, 255));
                    }
                }
            }
            return tiles.Count > 0;
        }

        static void ReadMud(MudField field, string path)
        {
            var list = new List<(int, int, MudCell[])>();
            using (var br = new BinaryReader(File.OpenRead(path)))
            {
                if (br.ReadInt32() != 0x4D554431) return;
                int n = br.ReadInt32();
                for (int k = 0; k < n; k++)
                {
                    int wtx = br.ReadInt32(), wtz = br.ReadInt32();
                    var arr = new MudCell[MudField.TileSize * MudField.TileSize];
                    for (int i = 0; i < arr.Length; i++)
                    {
                        arr[i].dh = br.ReadInt16() / 1000f;
                        arr[i].churn = br.ReadByte() / 255f;
                        arr[i].compact = br.ReadByte() / 255f;
                    }
                    list.Add((wtx, wtz, arr));
                }
            }
            field.Restore(list);
        }
    }
}
