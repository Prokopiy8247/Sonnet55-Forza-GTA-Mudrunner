using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using MudRunner.Cargo;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Testing
{
    /// <summary>
    /// In-game automated physics validation (debug menu: "Run physics test suite"; also callable from batch mode).
    /// Builds isolated test arenas, drives scripted bots (<see cref="BotDriver"/>) and reports numbers for:
    /// surface crossing per vehicle, spin-vs-controlled throttle, diff-lock/low-range hill climbs, winch recovery,
    /// water fording, rock-course suspension stability/articulation, trailer haul, and frame time with deforming vehicles.
    /// The previous world is restored when the suite ends. Usage: <c>RuntimePhysicsSuite.Run()</c>.
    /// </summary>
    public sealed class RuntimePhysicsSuite : MonoBehaviour
    {
        public static RuntimePhysicsSuite Instance { get; private set; }
        public bool Running { get; private set; }
        public float Progress { get; private set; }
        public string Status { get; private set; } = "";
        public readonly List<string> Lines = new List<string>();
        public string Report => string.Join("\n", Lines);
        public int Passed, Failed;
        public float timeScale = 3f;
        public static string ReportPath => Path.Combine(Application.persistentDataPath, "physics_suite_report.txt");

        GroundService gs; Vehicle veh; BotDriver bot;

        public static RuntimePhysicsSuite Run(bool quick = false)
        {
            if (Instance == null)
            {
                var go = new GameObject("RuntimePhysicsSuite");
                Instance = go.AddComponent<RuntimePhysicsSuite>();
            }
            if (!Instance.Running) Instance.StartCoroutine(Instance.Routine(quick));
            return Instance;
        }

        void Log(string s, bool pass = true, bool isResult = false)
        {
            Lines.Add(s);
            if (isResult) { if (pass) Passed++; else Failed++; }
            Debug.Log("[MudRunner] SUITE " + s);
        }

        // ------------------------------------------------------------------ helpers

        static VehicleDefinition Def(string key) { return GameManager.GetDefinition(key); }

        void Install(GroundMap map, Vector3 focus, float wet)
        {
            gs = TestArena.Install(map, focus, wet);
        }

        Vehicle Spawn(string key, Vector3 pos, float yaw = 0f)
        {
            var d = Def(key);
            float gy = gs.GroundHeight(pos.x, pos.z);
            pos.y = gy + (d.axles[0].tire.radius - d.axles[0].hubY) + 0.08f;
            var v = VehicleFactory.Create(d, pos, Quaternion.Euler(0f, yaw, 0f));
            gs.focus = v.transform;
            var b = v.GetComponent<BotDriver>() ?? v.gameObject.AddComponent<BotDriver>(); b.vehicle = v;
            veh = v; bot = b;
            return v;
        }

        void Cleanup()
        {
            if (veh != null) Destroy(veh.gameObject);
            veh = null; bot = null;
            if (TrailerSystem.Instance != null) { TrailerSystem.Instance.DetachTrailer(true); Destroy(TrailerSystem.Instance.gameObject); }
            if (GroundService.Instance != null) { DestroyImmediate(GroundService.Instance.gameObject); }
            foreach (var go in GameObject.FindObjectsByType<WinchAnchor>(FindObjectsSortMode.None)) Destroy(go.gameObject);
        }

        IEnumerator Wait(float sec) { float t = Time.time; while (Time.time - t < sec) yield return new WaitForFixedUpdate(); }

        struct Strat
        {
            public string label; public bool awd, locks, low, tc; public float speed;
            public static Strat Open => new Strat { label = "open", awd = true, speed = 4f };
            public static Strat Locked => new Strat { label = "locked+low", awd = true, locks = true, low = true, speed = 2.5f, tc = true };
        }

        class StripRes { public bool passed; public float time, sink, slip, stopZ; }

        IEnumerator Strip(string key, SurfaceType surf, Strat st, StripRes r, float length = 40f, float limit = 80f)
        {
            Install(TestArena.Strips((0f, length, surf, 0f)), new Vector3(0, 0, -60f), 0.4f);
            Spawn(key, new Vector3(0, 0, -60f));
            var dt = veh.drivetrain; dt.awd = st.awd; dt.lowRange = st.low; dt.centreLock = st.locks;
            for (int i = 0; i < dt.axleLock.Length; i++) dt.axleLock[i] = st.locks;
            bot.targetSpeed = st.speed; bot.tractionControl = st.tc;
            float t0 = Time.time, tEnter = -1f; r.sink = r.slip = 0f; r.passed = false;
            while (Time.time - t0 < limit)
            {
                yield return new WaitForFixedUpdate();
                float z = veh.transform.position.z;
                if (z > 0f && tEnter < 0f) tEnter = Time.time;
                if (z > 0f && z < length) { r.sink = Mathf.Max(r.sink, veh.maxSinkage); r.slip = Mathf.Max(r.slip, veh.meanSlipAbs); }
                if (z > length + 2f) { r.passed = true; break; }
                if (tEnter > 0f && Time.time - tEnter > 8f && veh.speed < 0.15f && veh.stuckTime > 4f) break;
            }
            r.time = tEnter > 0 ? Time.time - tEnter : -1f; r.stopZ = veh.transform.position.z;
            Cleanup();
        }

        static string F(StripRes r) { return (r.passed ? "PASS" : "STUCK@" + r.stopZ.ToString("F0")) + " t=" + r.time.ToString("F0") + "s sink=" + r.sink.ToString("F2") + "m slip=" + r.slip.ToString("F2"); }

        // ------------------------------------------------------------------ the suite

        IEnumerator Routine(bool quick)
        {
            Running = true; Passed = Failed = 0; Lines.Clear(); Progress = 0f;
            var gm = GameManager.Instance;
            WorldKind prevKind = gm != null && gm.World != null ? gm.World.kind : WorldKind.ProvingGround;
            string prevVeh = gm != null && gm.Player != null ? gm.Player.def.name.ToLowerInvariant() : "utility";
            float prevScale = Time.timeScale; float prevFixed = Time.fixedDeltaTime;
            var savedWorld = gm != null ? gm.World : null;
            if (gm != null) gm.Teardown();
            Time.timeScale = timeScale;
            Log("== MudRunner automated physics suite (" + DateTime.Now.ToString("s") + ", timescale x" + timeScale + (quick ? ", quick" : "") + ") ==");
            string[] keys = { "scout", "utility", "hauler" };
            int totalSteps = quick ? 8 : 24, step = 0;

            // ---- 1. static sinkage table (pure math)
            Status = "sinkage table"; step++;
            Install(TestArena.Flat(SurfaceType.FirmSoil, 40f), Vector3.zero, 0.3f);
            foreach (var key in keys)
            {
                var d = Def(key); var tire = d.axles[0].tire; float w = d.mass * 9.81f / (d.axles.Length * 2);
                var sb = new StringBuilder(key + " static sinkage (z) / net thrust margin:");
                foreach (var st in new[] { SurfaceType.FirmSoil, SurfaceType.ShallowMud, SurfaceType.DeepMud, SurfaceType.Bog })
                {
                    Cleanup(); var m = TestArena.Flat(st, 40f); gs = TestArena.Install(m, Vector3.zero, 0.3f);
                    var soil = gs.SampleSoil(0f, 0f);
                    float z = TireSoilModel.SolveSinkage(tire, w, soil, 1f, soil.softDepth, out bool bot_);
                    var c = TireSoilModel.Evaluate(tire, w, z, soil, 1f, bot_);
                    sb.Append(" | ").Append(st).Append(" ").Append(z.ToString("F2")).Append("m ").Append(((c.thrustCap - c.compactionResistance - c.bulldozeResistance) * d.axles.Length * 2 / 1000f).ToString("+0.0;-0.0")).Append("kN");
                }
                Log(sb.ToString());
                yield return null;
            }
            Cleanup(); Progress = step / (float)totalSteps;

            // ---- 2. surface crossing matrix
            var surfaces = quick ? new[] { SurfaceType.ShallowMud, SurfaceType.DeepMud } : new[] { SurfaceType.ShallowMud, SurfaceType.DeepMud, SurfaceType.Bog };
            foreach (var key in keys)
                foreach (var surf in surfaces)
                {
                    Status = key + " " + surf; step++;
                    var line = new StringBuilder("crossing " + key + " / " + surf + ":");
                    bool openPass = false, lockedPass = false;
                    foreach (var st in new[] { Strat.Open, Strat.Locked })
                    {
                        var r = new StripRes(); yield return Strip(key, surf, st, r);
                        line.Append(" ").Append(st.label).Append("=").Append(F(r));
                        if (st.label == "open") openPass = r.passed; else lockedPass = r.passed;
                    }
                    // expectations: shallow mud passable by all; light vehicle bogs in deep mud; nobody (naively) crosses bog
                    bool ok = surf == SurfaceType.ShallowMud ? (openPass && lockedPass)
                            : surf == SurfaceType.DeepMud ? (key == "scout" ? !openPass : (key == "utility" ? (lockedPass || openPass) : openPass))
                            : !openPass;
                    Log(line.ToString() + (ok ? "  [expected]" : "  [UNEXPECTED]"), ok, true);
                    Progress = step / (float)totalSteps;
                }

            // ---- 3. spin vs controlled throttle (from a standstill in deep mud, locked + low range)
            Status = "spin vs controlled"; step++;
            {
                var res = new List<string>(); float sinkSpin = 0, sinkCtl = 0, zSpin = 0, zCtl = 0;
                foreach (bool ctl in new[] { false, true })
                {
                    Install(TestArena.Strips((-5f, 120f, SurfaceType.DeepMud, 0f)), new Vector3(0, 0, 0f), 0.4f);
                    Spawn("utility", new Vector3(0, 0, 0f));
                    var dt = veh.drivetrain; dt.awd = true; dt.lowRange = true; dt.centreLock = true; for (int i = 0; i < dt.axleLock.Length; i++) dt.axleLock[i] = true;
                    if (ctl) { bot.targetSpeed = 1.5f; bot.tractionControl = true; bot.slipSpeedAllowance = 0.35f; } else { bot.fullThrottleNoGovernor = true; }
                    yield return Wait(18f);
                    float z = veh.transform.position.z, sink = veh.maxSinkage;
                    res.Add((ctl ? "controlled" : "spinning") + ": moved " + z.ToString("F1") + " m, sinkage " + sink.ToString("F2") + " m");
                    if (ctl) { sinkCtl = sink; zCtl = z; } else { sinkSpin = sink; zSpin = z; }
                    Cleanup();
                }
                bool ok = sinkSpin > sinkCtl * 1.15f || zCtl > zSpin + 3f;
                Log("spin vs controlled throttle (utility from standstill, deep mud, 18 s): " + string.Join(" | ", res) + (ok ? "  [spinning digs deeper / progresses less]" : "  [UNEXPECTED: no demonstrable difference]"), ok, true);
                Progress = step / (float)totalSteps;
            }

            // ---- 4. hill climb: locks/low range help
            foreach (var key in quick ? new[] { "utility" } : new[] { "utility", "hauler" })
            {
                Status = "hill " + key; step++;
                var line = new StringBuilder("hill 18deg mud " + key + ":"); var climbed = new Dictionary<string, bool>();
                foreach (var st in new[] { new Strat { label = "2wd", awd = false, speed = 4f, tc = true }, Strat.Open, Strat.Locked })
                {
                    Install(TestArena.Slope(18f, SurfaceType.ShallowMud, 0f), new Vector3(0, 0, -25f), 0.5f);
                    Spawn(key, new Vector3(0, 0, -25f));
                    var dt = veh.drivetrain; dt.awd = st.awd; dt.lowRange = st.low; dt.centreLock = st.locks; for (int i = 0; i < dt.axleLock.Length; i++) dt.axleLock[i] = st.locks;
                    bot.targetSpeed = st.speed; bot.tractionControl = true;
                    float t0 = Time.time; bool top = false;
                    while (Time.time - t0 < 60f) { yield return new WaitForFixedUpdate(); if (veh.transform.position.z > 40f) { top = true; break; } if (Time.time - t0 > 15f && veh.speed < 0.1f && veh.stuckTime > 5f) break; }
                    line.Append(" ").Append(st.label).Append("=").Append(top ? "TOP(" + (Time.time - t0).ToString("F0") + "s)" : "stalled");
                    climbed[st.label] = top; Cleanup();
                }
                bool ok = (climbed["locked+low"] || climbed["open"]) && !(climbed["2wd"] && !climbed["locked+low"]);
                Log(line.ToString() + (ok ? "  [4x4/locks/low range >= 2WD]" : "  [UNEXPECTED]"), ok, true);
                Progress = step / (float)totalSteps;
            }

            // ---- 5. winch recovery
            Status = "winch"; step++;
            {
                Install(TestArena.Strips((0f, 30f, SurfaceType.Bog, 0f)), new Vector3(0, 0, -30f), 0.5f);
                Spawn("utility", new Vector3(0, 0, -30f));
                var post = new GameObject("SuiteAnchor"); post.transform.position = new Vector3(0.5f, gs.GroundHeight(0.5f, 35f) + 0.2f, 35f); post.AddComponent<WinchAnchor>();
                bot.fullThrottleNoGovernor = true;
                float t0 = Time.time; while (Time.time - t0 < 40f) { yield return new WaitForFixedUpdate(); if (veh.transform.position.z > 4f && veh.speed < 0.15f && veh.stuckTime > 4f) break; }
                float stuckZ = veh.transform.position.z;
                bot.fullThrottleNoGovernor = false; bot.throttleOverride = 0f; bot.targetSpeed = 0f; veh.drivetrain.mode = GearMode.Manual; veh.drivetrain.gear = 0;
                bool attached = veh.winch != null && veh.winch.TryAutoAttach(); if (attached) veh.winch.input = 1f;
                float t1 = Time.time; float maxT = 0f; bool outOk = false;
                while (Time.time - t1 < 90f) { yield return new WaitForFixedUpdate(); maxT = Mathf.Max(maxT, veh.winch.Tension); if (veh.transform.position.z > 31f) { outOk = true; break; } }
                bool wasStuck = stuckZ < 25f;
                Log("winch recovery (utility, bog): stuck at z=" + stuckZ.ToString("F1") + " attached=" + attached + " recovered=" + outOk + " in " + (Time.time - t1).ToString("F0") + "s peak tension " + (maxT / 1000f).ToString("F1") + " kN", wasStuck && attached && outOk, true);
                Destroy(post); Cleanup();
                Progress = step / (float)totalSteps;
            }

            // ---- 6. water fording
            foreach (var key in quick ? new[] { "scout" } : keys)
            {
                Status = "ford " + key; step++;
                var line = new StringBuilder("ford " + key + " (current 1.5 m/s):"); var res = new Dictionary<float, bool>(); float ratingMeasured = 0f;
                foreach (float depth in new[] { 0.4f, 0.8f, 1.2f, 1.6f, 2.0f, 2.4f })
                {
                    var map = TestArena.Flat(SurfaceType.Gravel, 240f);
                    var wm = new WaterMap(map.size, map.cell, map.origin);
                    for (int iz = 0; iz < map.size; iz++) { float zz = map.origin.y + iz * map.cell; if (zz >= 0f && zz <= 20f) for (int ix = 0; ix < map.size; ix++) wm.Set(ix, iz, depth, new Vector2(1.5f, 0f)); }
                    map.water = wm;
                    Install(map, new Vector3(0, 0, -30f), 0.3f); Spawn(key, new Vector3(0, 0, -30f)); ratingMeasured = veh.FordingRating;
                    bot.targetSpeed = 3.5f; bot.tractionControl = true; veh.drivetrain.lowRange = true;
                    float t0 = Time.time; bool crossed = false, flooded = false;
                    while (Time.time - t0 < 50f) { yield return new WaitForFixedUpdate(); flooded |= veh.water.engineFlooded; if (veh.transform.position.z > 24f) { crossed = true; break; } if (flooded && veh.speed < 0.3f && Time.time - t0 > 6f) break; }
                    res[depth] = crossed; line.Append(" ").Append(depth.ToString("F1")).Append("m=").Append(crossed ? "OK" : (flooded ? "FAIL(stall)" : "FAIL"));
                    Cleanup();
                }
                float rating = Def(key).fordingDepth; if (ratingMeasured > 0f) rating = ratingMeasured;
                bool okBelow = true, okAbove = true; bool anyAbove = false;
                foreach (var kv in res) { if (kv.Key <= rating - 0.3f && !kv.Value) okBelow = false; if (kv.Key >= rating + 0.35f) { anyAbove = true; if (kv.Value) okAbove = false; } }
                bool ok = okBelow && okAbove;
                Log(line.ToString() + "  (rated " + rating.ToString("F2") + " m = min(intake height, float depth))" + (ok ? (anyAbove ? "  [passes below rating, fails/floats above]" : "  [passes below rating; deeper than tested range to fail]") : "  [UNEXPECTED]"), ok, true);
                Progress = step / (float)totalSteps;
            }

            // ---- 7. rock course: suspension stability and articulation
            foreach (var key in quick ? new[] { "utility" } : keys)
            {
                Status = "rocks " + key; step++;
                Install(TestArena.Flat(SurfaceType.FirmSoil, 200f), new Vector3(0, 0, -30f), 0.2f);
                var rocks = new GameObject("RockCourse");
                for (int i = 0; i < 8; i++)
                {
                    var rk = GameObject.CreatePrimitive(PrimitiveType.Cube); rk.transform.SetParent(rocks.transform);
                    float side = i % 2 == 0 ? -1f : 1f;
                    float h = 0.16f + 0.04f * (i % 3);
                    rk.transform.position = new Vector3(side * 0.85f, h * 0.35f, 5f + i * 4.5f);
                    rk.transform.localScale = new Vector3(1.0f, h, 1.4f);
                    rk.transform.rotation = Quaternion.Euler(0f, 18f * side, 0f);
                    rk.layer = GameLayers.Props;
                }
                Spawn(key, new Vector3(0, 0, -30f));
                bot.targetSpeed = 2.2f; bot.tractionControl = true; bot.useWaypoints = false;
                float t0 = Time.time; float maxAng = 0f, maxTilt = 0f, maxArt = 0f, maxHeave = 0f; bool nan = false; bool done = false;
                while (Time.time - t0 < 45f)
                {
                    yield return new WaitForFixedUpdate();
                    var p = veh.transform.position; if (float.IsNaN(p.x) || float.IsNaN(p.y)) { nan = true; break; }
                    maxAng = Mathf.Max(maxAng, veh.rb.angularVelocity.magnitude);
                    maxTilt = Mathf.Max(maxTilt, Vector3.Angle(Vector3.up, veh.transform.up));
                    maxHeave = Mathf.Max(maxHeave, Mathf.Abs(veh.rb.linearVelocity.y));
                    for (int a = 0; a < veh.def.axles.Length; a++) maxArt = Mathf.Max(maxArt, Mathf.Abs(veh.wheels[a * 2].length - veh.wheels[a * 2 + 1].length));
                    if (veh.transform.position.z > 45f) { done = true; break; }
                }
                bool ok = !nan && done && maxAng < 3.0f && maxHeave < 3.0f && maxTilt < 40f;
                Log("rock course " + key + ": completed=" + done + " max angular vel " + maxAng.ToString("F2") + " rad/s, tilt " + maxTilt.ToString("F0") + " deg, vertical speed " + maxHeave.ToString("F1") + " m/s, axle articulation (L-R strut length diff) " + maxArt.ToString("F2") + " m", ok, true);
                Destroy(rocks); Cleanup();
                Progress = step / (float)totalSteps;
            }

            // ---- 8. trailer
            Status = "trailer"; step++;
            {
                Install(TestArena.Strips((50f, 90f, SurfaceType.ShallowMud, 0f)), new Vector3(0, 0, -30f), 0.4f);
                Spawn("utility", new Vector3(0, 0, -30f));
                var ts = TrailerSystem.EnsureInstance(); ts.Attach(veh); ts.LoadCargo("logs");
                bot.targetSpeed = 3.5f; bot.tractionControl = true; veh.drivetrain.awd = true;
                int deck0 = ts.CargoOnDeck; float t0 = Time.time; bool crossed = false; float maxYaw = 0f;
                while (Time.time - t0 < 60f) { yield return new WaitForFixedUpdate(); maxYaw = Mathf.Max(maxYaw, Mathf.Abs(Mathf.DeltaAngle(veh.transform.eulerAngles.y, ts.Trailer.transform.eulerAngles.y))); if (veh.transform.position.z > 100f) { crossed = true; break; } }
                bool ok = crossed && ts.CargoOnDeck == deck0;
                Log("trailer + " + ts.CargoMass.ToString("F0") + " kg logs through shallow mud (utility): crossed=" + crossed + " cargo " + ts.CargoOnDeck + "/" + deck0 + " max hitch angle " + maxYaw.ToString("F0") + " deg", ok, true);
                ts.DetachTrailer(true); Destroy(ts.gameObject); Cleanup();
                Progress = step / (float)totalSteps;
            }

            // ---- 9. performance: 4 vehicles churning mud
            Status = "performance"; step++;
            {
                Install(TestArena.Flat(SurfaceType.DeepMud, 300f), Vector3.zero, 0.5f);
                var list = new List<Vehicle>();
                string[] ks = { "scout", "utility", "hauler", "utility" };
                for (int i = 0; i < ks.Length; i++)
                {
                    var v = Spawn(ks[i], new Vector3(-30f + i * 20f, 0, -40f)); list.Add(v);
                    bot.fullThrottleNoGovernor = true; bot.maxThrottle = 0.6f; v.drivetrain.lowRange = true;
                }
                gs.focus = list[1].transform;
                yield return Wait(4f);
                float acc = 0f; int n = 0; float worst = 0f; Vehicle.ResetFixedStats();
                float t0 = Time.unscaledTime;
                while (Time.unscaledTime - t0 < 5f) { yield return null; float dt = Time.unscaledDeltaTime; acc += dt; n++; worst = Mathf.Max(worst, dt); }
                float fixedMs = Vehicle.FixedMsPerStep;
                float avgMs = n > 0 ? acc / n * 1000f : 0f;
                bool ok = fixedMs < 3.0f;
                Log("performance (4 vehicles churning mud, timescale x" + timeScale + "): average frame " + avgMs.ToString("F1") + " ms (" + (n > 0 ? n / acc : 0f).ToString("F0") + " fps incl. timescale catch-up), worst " + (worst * 1000f).ToString("F1") + " ms, vehicle physics " + fixedMs.ToString("F3") + " ms per fixed step for 4 vehicles, field uploads/frame " + (gs.Field != null ? gs.Field.GpuTilesUploadedLastSync : 0), ok, true);
                foreach (var v in list) if (v != null) Destroy(v.gameObject);
                veh = null; Cleanup();
                Progress = 1f;
            }

            // ---- done
            Time.timeScale = prevScale; Time.fixedDeltaTime = prevFixed;
            Log("== suite finished: " + Passed + " checks passed, " + Failed + " unexpected ==");
            try { Directory.CreateDirectory(Path.GetDirectoryName(ReportPath)); File.WriteAllText(ReportPath, Report); } catch (Exception) { }
            Status = "done";
            if (gm != null) gm.StartWorld(prevKind, prevVeh.Contains("scout") ? "scout" : prevVeh.Contains("hauler") ? "hauler" : "utility");
            Running = false;
        }
    }
}
