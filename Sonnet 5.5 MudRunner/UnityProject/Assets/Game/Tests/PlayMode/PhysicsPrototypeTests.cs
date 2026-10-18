using System.Collections;
using System.Text;
using MudRunner.Ground;
using MudRunner.Testing;
using MudRunner.Vehicles;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace MudRunner.Tests
{
    /// <summary>Physics prototype / validation tests. Numbers are logged with the [MudRunner] prefix for the report.</summary>
    public class PhysicsPrototypeTests
    {
        GroundService gs;
        Vehicle veh;
        BotDriver bot;

        [SetUp]
        public void SetUp() { Time.captureFramerate = 60; }

        [TearDown]
        public void TearDown()
        {
            Time.captureFramerate = 0;
            if (veh != null) Object.Destroy(veh.gameObject);
            if (GroundService.Instance != null) Object.Destroy(GroundService.Instance.gameObject);
            Physics.SyncTransforms();
        }

        public static VehicleDefinition Def(string n)
        {
            switch (n)
            {
                case "scout": return VehicleDefinition.CreateScout();
                case "utility": return VehicleDefinition.CreateUtility();
                default: return VehicleDefinition.CreateHauler();
            }
        }

        Vehicle Spawn(VehicleDefinition d, Vector3 pos, float yaw = 0f)
        {
            var a = d.axles[0];
            float groundY = gs.GroundHeight(pos.x, pos.z);
            pos.y = groundY + (a.tire.radius - a.hubY) + 0.06f;
            var v = VehicleFactory.CreatePrimitive(d, pos, Quaternion.Euler(0f, yaw, 0f), withVisuals: false);
            gs.focus = v.transform;
            var b = v.gameObject.AddComponent<BotDriver>(); b.vehicle = v; bot = b;
            veh = v;
            return v;
        }

        IEnumerator Run(float seconds)
        {
            float t0 = Time.time;
            while (Time.time - t0 < seconds) yield return new WaitForFixedUpdate();
        }

        static readonly string[] Names = { "scout", "utility", "hauler" };

        [UnityTest]
        public IEnumerator Settle_OnFirmGround([ValueSource(nameof(Names))] string name)
        {
            gs = TestArena.Install(TestArena.Flat(SurfaceType.FirmSoil), Vector3.zero, 0.2f);
            var d = Def(name);
            Spawn(d, Vector3.zero);
            bot.holdBrake = true;
            yield return Run(6f);
            var sb = new StringBuilder();
            sb.Append("[MudRunner] SETTLE ").Append(name).Append(": y=").Append(veh.transform.position.y.ToString("F3"))
              .Append(" speed=").Append(veh.speed.ToString("F4")).Append(" grounded=").Append(veh.groundedWheels).Append(" maxSink=").Append(veh.maxSinkage.ToString("F3"));
            foreach (var w in veh.wheels) sb.Append(" | ").Append(w.name).Append(" L=").Append(w.length.ToString("F3")).Append("/").Append(w.restLength.ToString("F2")).Append(" F=").Append((w.supportForce / 1000f).ToString("F1")).Append("kN");
            Debug.Log(sb.ToString());
            Assert.AreEqual(veh.wheels.Length, veh.groundedWheels, "all wheels grounded");
            Assert.Less(veh.speed, 0.1f, "vehicle at rest");
            Assert.IsFalse(float.IsNaN(veh.transform.position.y));
        }


        /// <summary>Static vehicle on soft ground: must sink to a steady state without bouncing.</summary>
        [UnityTest]
        public IEnumerator Settle_OnMud([ValueSource(nameof(Names))] string name)
        {
            gs = TestArena.Install(TestArena.Flat(SurfaceType.DeepMud), Vector3.zero, 0.4f);
            var d = Def(name);
            Spawn(d, Vector3.zero);
            bot.holdBrake = true;
            yield return Run(12f);
            float t0 = Time.time; float yMin = 99, yMax = -99, lMin = 1e9f, lMax = 0f, sink = 0;
            while (Time.time - t0 < 4f)
            {
                yield return new WaitForFixedUpdate();
                float y = veh.transform.position.y; yMin = Mathf.Min(yMin, y); yMax = Mathf.Max(yMax, y);
                float ld = veh.wheels[0].load; lMin = Mathf.Min(lMin, ld); lMax = Mathf.Max(lMax, ld);
                sink = veh.maxSinkage;
            }
            Debug.Log("[MudRunner] SETTLE_MUD " + name + ": y=[" + yMin.ToString("F3") + "," + yMax.ToString("F3") + "] FL load=[" + lMin.ToString("F0") + "," + lMax.ToString("F0") + "] N maxSink=" + sink.ToString("F2") + " belly=" + veh.bellyContact.ToString("F2") + " speed=" + veh.speed.ToString("F3"));
            Assert.Less(yMax - yMin, 0.03f, "no bouncing at rest on soft ground");
        }


        /// <summary>Pure-math tuning table: static sinkage / resistance / thrust per vehicle and surface (no simulation).</summary>
        [Test]
        public void Table_StaticSinkage()
        {
            var gsObj = TestArena.Install(TestArena.Flat(SurfaceType.FirmSoil), Vector3.zero, 0.3f);
            gs = gsObj;
            var types = new[] { SurfaceType.FirmSoil, SurfaceType.Grass, SurfaceType.ShallowMud, SurfaceType.DeepMud, SurfaceType.Bog, SurfaceType.Sand };
            foreach (var name in Names)
            {
                var d = Def(name);
                var sb = new StringBuilder("[MudRunner] TABLE " + name + " (" + d.mass.ToString("F0") + "kg, tyre r=" + d.axles[0].tire.radius.ToString("F2") + " w=" + d.axles[0].tire.width.ToString("F3") + "):");
                float perWheel = d.mass * 9.81f / (d.axles.Length * 2);
                foreach (var t in types)
                {
                    var soil = SoilFor(t);
                    var tire = d.axles[0].tire;
                    float z = TireSoilModel.SolveSinkage(tire, perWheel, soil, 1f, soil.softDepth, out bool bot);
                    var c = TireSoilModel.Evaluate(tire, perWheel, z, soil, 1f, bot);
                    float res = c.compactionResistance + c.bulldozeResistance;
                    sb.Append(" | ").Append(t).Append(": z=").Append(z.ToString("F2")).Append("m Fres=").Append((res * d.axles.Length * 2 / 1000f).ToString("F1")).Append("kN cap=").Append((c.thrustCap * d.axles.Length * 2 / 1000f).ToString("F1")).Append("kN (W=").Append((d.mass * 9.81f / 1000f).ToString("F0")).Append(")");
                }
                Debug.Log(sb.ToString());
            }
        }

        SoilSample SoilFor(SurfaceType t)
        {
            // sample the service at a point painted with that single surface
            var map = TestArena.Flat(t, 40f);
            var g = TestArena.Install(map, Vector3.zero, 0.3f);
            gs = g;
            return g.SampleSoil(0f, 0f);
        }

        // ------------------------------------------------------------------ strip crossing matrix

        public struct Strategy
        {
            public string label; public bool awd, lockAxles, lockCentre, lowRange; public float speed; public bool spin;
            public static Strategy Open => new Strategy { label = "open", awd = true, speed = 4f };
            public static Strategy Locked => new Strategy { label = "locked", awd = true, lockAxles = true, lockCentre = true, lowRange = true, speed = 2.5f };
            public static Strategy TwoWd => new Strategy { label = "2wd", awd = false, speed = 4f };
            public static Strategy Spin => new Strategy { label = "spin", awd = true, lockAxles = true, lockCentre = true, lowRange = false, speed = 6f, spin = true };
        }

        public class StripResult { public bool passed; public float time, maxSink, stopZ, maxSlip, fuel; }

        IEnumerator RunStrip(string name, SurfaceType surface, float extra, Strategy st, StripResult res, float lengthM = 40f, float timeLimit = 80f)
        {
            // run-up firm 60 m, test strip [0,length), firm exit
            var map = TestArena.Strips((0f, lengthM, surface, extra));
            gs = TestArena.Install(map, new Vector3(0, 0, -60f), 0.4f);
            var d = Def(name);
            Spawn(d, new Vector3(0, 0, -60f));
            veh.drivetrain.awd = st.awd; veh.drivetrain.lowRange = st.lowRange; veh.drivetrain.centreLock = st.lockCentre;
            for (int i = 0; i < veh.drivetrain.axleLock.Length; i++) veh.drivetrain.axleLock[i] = st.lockAxles;
            bot.targetSpeed = st.speed; bot.fullThrottleNoGovernor = st.spin;
            float t0 = Time.time, tEnter = -1f;
            res.maxSink = 0f; res.maxSlip = 0f; res.passed = false;
            while (Time.time - t0 < timeLimit)
            {
                yield return new WaitForFixedUpdate();
                float z = veh.transform.position.z;
                if (z > 0f && tEnter < 0f) tEnter = Time.time;
                if (z > 0f && z < lengthM) { res.maxSink = Mathf.Max(res.maxSink, veh.maxSinkage); res.maxSlip = Mathf.Max(res.maxSlip, veh.meanSlipAbs); }
                if (z > lengthM + 2f) { res.passed = true; break; }
                if (tEnter > 0f && Time.time - tEnter > 8f && veh.speed < 0.15f && veh.stuckTime > 4f) break;
            }
            res.time = tEnter > 0 ? Time.time - tEnter : -1f;
            res.stopZ = veh.transform.position.z;
            res.fuel = veh.fuel;
        }

        static string Fmt(StripResult r) => (r.passed ? "PASS" : "STUCK@" + r.stopZ.ToString("F1")) + " t=" + r.time.ToString("F1") + "s sink=" + r.maxSink.ToString("F2") + "m slip=" + r.maxSlip.ToString("F2");

        [UnityTest]
        public IEnumerator Matrix_Surfaces()
        {
            var surfaces = new[] { (SurfaceType.ShallowMud, 0f, "shallow"), (SurfaceType.DeepMud, 0f, "deep"), (SurfaceType.Bog, 0f, "bog") };
            var strategies = new[] { Strategy.TwoWd, Strategy.Open, Strategy.Locked };
            var sb = new StringBuilder();
            foreach (var name in Names)
                foreach (var s in surfaces)
                {
                    var line = new StringBuilder("[MudRunner] MATRIX " + name + " " + s.Item3 + ":");
                    foreach (var st in strategies)
                    {
                        var r = new StripResult();
                        yield return RunStrip(name, s.Item1, s.Item2, st, r);
                        line.Append(" ").Append(st.label).Append("=").Append(Fmt(r)).Append(" |");
                        CleanupVehicle();
                    }
                    Debug.Log(line.ToString());
                }
        }


        // ------------------------------------------------------------------ spin vs controlled throttle, hill climb

        IEnumerator RunStripTC(string name, SurfaceType surface, Strategy st, bool tc, StripResult res, float lengthM = 40f)
        {
            var map = TestArena.Strips((0f, lengthM, surface, 0f));
            gs = TestArena.Install(map, new Vector3(0, 0, -30f), 0.4f);
            var d = Def(name);
            Spawn(d, new Vector3(0, 0, -30f));
            veh.drivetrain.awd = st.awd; veh.drivetrain.lowRange = st.lowRange; veh.drivetrain.centreLock = st.lockCentre;
            for (int i = 0; i < veh.drivetrain.axleLock.Length; i++) veh.drivetrain.axleLock[i] = st.lockAxles;
            bot.targetSpeed = st.speed; bot.tractionControl = tc;
            float t0 = Time.time, tEnter = -1f; res.maxSink = 0f; res.maxSlip = 0f; res.passed = false;
            while (Time.time - t0 < 90f)
            {
                yield return new WaitForFixedUpdate();
                float z = veh.transform.position.z;
                if (z > 0f && tEnter < 0f) tEnter = Time.time;
                if (z > 0f && z < lengthM) { res.maxSink = Mathf.Max(res.maxSink, veh.maxSinkage); res.maxSlip = Mathf.Max(res.maxSlip, veh.meanSlipAbs); }
                if (z > lengthM + 2f) { res.passed = true; break; }
                if (tEnter > 0f && Time.time - tEnter > 10f && veh.speed < 0.15f && veh.stuckTime > 4f) break;
            }
            res.time = tEnter > 0 ? Time.time - tEnter : -1f; res.stopZ = veh.transform.position.z; res.fuel = veh.fuel;
        }

        [UnityTest]
        public IEnumerator SpinVsControlled_DeepMud()
        {
            var sb = new StringBuilder("[MudRunner] SPINTEST deep mud, utility, locked+low:");
            foreach (var tc in new[] { false, true })
            {
                var r = new StripResult();
                yield return RunStripTC("utility", SurfaceType.DeepMud, Strategy.Locked, tc, r);
                sb.Append(tc ? " controlled=" : " spinning=").Append(Fmt(r)).Append(" |");
                CleanupVehicle();
            }
            foreach (var tc in new[] { false, true })
            {
                var r = new StripResult();
                yield return RunStripTC("scout", SurfaceType.DeepMud, Strategy.Locked, tc, r);
                sb.Append(tc ? " scout controlled=" : " scout spinning=").Append(Fmt(r)).Append(" |");
                CleanupVehicle();
            }
            Debug.Log(sb.ToString());
        }

        [UnityTest]
        public IEnumerator HillClimb_Strategies([ValueSource(nameof(Names))] string name)
        {
            var sb = new StringBuilder("[MudRunner] HILL " + name + " 18deg shallow mud:");
            var strategies = new[] { Strategy.TwoWd, Strategy.Open, new Strategy { label = "low", awd = true, lowRange = true, speed = 3f }, Strategy.Locked };
            foreach (var st in strategies)
            {
                var map = TestArena.Slope(18f, SurfaceType.ShallowMud, 0f);
                gs = TestArena.Install(map, new Vector3(0, 0, -25f), 0.5f);
                var d = Def(name);
                Spawn(d, new Vector3(0, 0, -25f));
                veh.drivetrain.awd = st.awd; veh.drivetrain.lowRange = st.lowRange; veh.drivetrain.centreLock = st.lockCentre;
                for (int i = 0; i < veh.drivetrain.axleLock.Length; i++) veh.drivetrain.axleLock[i] = st.lockAxles;
                bot.targetSpeed = st.speed; bot.tractionControl = true;
                float t0 = Time.time; float zMax = -99f; bool top = false;
                while (Time.time - t0 < 70f)
                {
                    yield return new WaitForFixedUpdate();
                    zMax = Mathf.Max(zMax, veh.transform.position.z);
                    if (veh.transform.position.z > 40f) { top = true; break; }
                    if (Time.time - t0 > 15f && veh.speed < 0.1f && veh.stuckTime > 5f) break;
                }
                sb.Append(" ").Append(st.label).Append("=").Append(top ? "TOP" : "stalled@z" + zMax.ToString("F0")).Append(" t=").Append((Time.time - t0).ToString("F0")).Append("s |");
                CleanupVehicle();
            }
            Debug.Log(sb.ToString());
        }


        [UnityTest]
        public IEnumerator Winch_RecoversStuckVehicle()
        {
            // bog strip z in [0,30]; anchor post on firm ground at z = 35; utility (45 kN winch) drives in and bogs down
            var map = TestArena.Strips((0f, 30f, SurfaceType.Bog, 0f));
            gs = TestArena.Install(map, new Vector3(0, 0, -30f), 0.5f);
            var d = Def("utility");
            Spawn(d, new Vector3(0, 0, -30f));
            var postGo = new GameObject("TestAnchorPost");
            postGo.transform.position = new Vector3(0.5f, gs.GroundHeight(0.5f, 35f) + 0.2f, 35f);
            var anchor = postGo.AddComponent<MudRunner.Vehicles.WinchAnchor>();
            bot.fullThrottleNoGovernor = true;     // floor it -> spin, dig, bog down
            veh.drivetrain.lowRange = false;
            float t0 = Time.time;
            while (Time.time - t0 < 40f) { yield return new WaitForFixedUpdate(); if (veh.transform.position.z > 4f && veh.speed < 0.15f && veh.stuckTime > 4f) break; }
            float stuckZ = veh.transform.position.z; float sink = veh.maxSinkage;
            bool wasStuck = stuckZ < 25f;
            // driver releases the throttle, selects neutral, hooks the winch and reels in
            bot.fullThrottleNoGovernor = false; bot.throttleOverride = 0f; bot.targetSpeed = 0f; veh.drivetrain.mode = GearMode.Manual; veh.drivetrain.gear = 0;
            bool attached = veh.winch != null && veh.winch.TryAutoAttach();
            veh.winch.input = 1f;
            float t1 = Time.time; float maxT = 0f; bool out_ = false;
            while (Time.time - t1 < 90f)
            {
                yield return new WaitForFixedUpdate();
                maxT = Mathf.Max(maxT, veh.winch.Tension);
                if (veh.transform.position.z > 31f) { out_ = true; break; }
            }
            Debug.Log("[MudRunner] WINCH utility bogged at z=" + stuckZ.ToString("F1") + " sink=" + sink.ToString("F2") + " (stuck=" + wasStuck + ") attached=" + attached + " recovered=" + out_ + " in " + (Time.time - t1).ToString("F1") + "s maxTension=" + (maxT / 1000f).ToString("F1") + "kN of " + (d.winchForce / 1000f).ToString("F0") + "kN, finalZ=" + veh.transform.position.z.ToString("F1"));
            Object.Destroy(postGo);
            Assert.IsTrue(attached, "winch found the anchor");
            Assert.IsTrue(out_, "vehicle recovered by winch");
        }


        [UnityTest]
        public IEnumerator Ford_Depths([ValueSource(nameof(Names))] string name)
        {
            var sb = new StringBuilder("[MudRunner] FORD " + name + " (current 1.5 m/s toward +x, river z in [0,20]):");
            foreach (float depth in new[] { 0.4f, 0.8f, 1.2f, 1.6f, 2.0f })
            {
                var map = TestArena.Flat(SurfaceType.Gravel, 240f);
                var wm = new WaterMap(map.size, map.cell, map.origin);
                for (int iz = 0; iz < map.size; iz++)
                    for (int ix = 0; ix < map.size; ix++)
                    {
                        float z = map.origin.y + iz * map.cell;
                        if (z >= 0f && z <= 20f) wm.Set(ix, iz, depth, new Vector2(1.5f, 0f));
                    }
                map.water = wm;
                gs = TestArena.Install(map, new Vector3(0, 0, -30f), 0.3f);
                var d = Def(name);
                Spawn(d, new Vector3(0, 0, -30f));
                bot.targetSpeed = 3.5f; bot.tractionControl = true;
                veh.drivetrain.awd = true; veh.drivetrain.lowRange = true;
                float t0 = Time.time; bool crossed = false; float maxLat = 0f; bool flooded = false, floated = false;
                while (Time.time - t0 < 60f)
                {
                    yield return new WaitForFixedUpdate();
                    maxLat = Mathf.Max(maxLat, Mathf.Abs(veh.transform.position.x));
                    flooded |= veh.water.engineFlooded; floated |= veh.water.floating;
                    if (veh.transform.position.z > 24f) { crossed = true; break; }
                    if (flooded && veh.speed < 0.3f && Time.time - t0 > 6f) break;
                }
                sb.Append(" ").Append(depth.ToString("F1")).Append("m=").Append(crossed ? "OK" : "FAIL").Append(flooded ? "(stalled)" : "").Append(floated ? "(floated)" : "").Append(" drift=").Append(maxLat.ToString("F1")).Append("m |");
                CleanupVehicle();
            }
            Debug.Log(sb.ToString());
        }


        [UnityTest]
        public IEnumerator Trailer_HaulsLogs([ValueSource(nameof(TowNames))] string name)
        {
            var map = TestArena.Strips((60f, 100f, SurfaceType.ShallowMud, 0f));
            gs = TestArena.Install(map, new Vector3(0, 0, -30f), 0.4f);
            var d = Def(name);
            Spawn(d, new Vector3(0, 0, -30f));
            var ts = MudRunner.Cargo.TrailerSystem.EnsureInstance();
            ts.Attach(veh);
            ts.LoadCargo("logs");
            bot.targetSpeed = 3.5f; bot.tractionControl = true; veh.drivetrain.awd = true;
            yield return Run(3f);
            float cargoKg = ts.CargoMass; int onDeck0 = ts.CargoOnDeck;
            float t0 = Time.time; float maxHitchYaw = 0f; bool crossed = false;
            float sinkLoaded = 0f;
            while (Time.time - t0 < 70f)
            {
                yield return new WaitForFixedUpdate();
                float yaw = Mathf.Abs(Mathf.DeltaAngle(veh.transform.eulerAngles.y, ts.Trailer.transform.eulerAngles.y));
                maxHitchYaw = Mathf.Max(maxHitchYaw, yaw);
                if (veh.transform.position.z > 60f && veh.transform.position.z < 100f) sinkLoaded = Mathf.Max(sinkLoaded, ts.Trailer.maxSinkage);
                if (veh.transform.position.z > 108f) { crossed = true; break; }
            }
            Debug.Log("[MudRunner] TRAILER " + name + ": cargo " + cargoKg.ToString("F0") + "kg, onDeck " + ts.CargoOnDeck + "/" + onDeck0 + " crossed=" + crossed + " t=" + (Time.time - t0).ToString("F1") + "s maxHitchYaw=" + maxHitchYaw.ToString("F1") + "deg trailerSinkInMud=" + sinkLoaded.ToString("F2") + "m");
            ts.DetachTrailer(true);
            Object.Destroy(ts.gameObject);
            Assert.IsTrue(crossed, "tow vehicle with loaded trailer crosses shallow mud");
            Assert.AreEqual(onDeck0, ts.CargoOnDeck, "no cargo lost");
        }
        static readonly string[] TowNames = { "utility", "hauler" };


        [UnityTest]
        public IEnumerator Diag_HillHauler()
        {
            var map = TestArena.Slope(18f, SurfaceType.ShallowMud, 0f);
            gs = TestArena.Install(map, new Vector3(0, 0, -25f), 0.5f);
            Spawn(Def("hauler"), new Vector3(0, 0, -25f));
            var dt = veh.drivetrain; dt.awd = true; dt.lowRange = true; dt.centreLock = true; for (int i = 0; i < dt.axleLock.Length; i++) dt.axleLock[i] = true;
            bot.targetSpeed = 3f; bot.tractionControl = true;
            float t0 = Time.time, next = 0f;
            while (Time.time - t0 < 40f)
            {
                yield return new WaitForFixedUpdate();
                float el = Time.time - t0;
                if (el >= next) { next = el + 2f;
                    var w = veh.wheels[0]; var wm = veh.wheels[2]; var wr = veh.wheels[4];
                    Debug.Log("[MudRunner] DIAGHILL t=" + el.ToString("F0") + " z=" + veh.transform.position.z.ToString("F1") + " v=" + veh.forwardSpeed.ToString("F2") + " thr=" + veh.throttleEff.ToString("F2") + " rpm=" + dt.rpm.ToString("F0") + " g=" + dt.GearLabel + " eng=" + dt.engagement.ToString("F2") + " Tc=" + dt.clutchTorque.ToString("F0") + " slipMean=" + veh.meanSlipAbs.ToString("F2")
                        + " | F load=" + w.load.ToString("F0") + " sink=" + w.sinkage.ToString("F2") + " cap=" + w.soilContact.thrustCap.ToString("F0") + " Ftr=" + w.fTrac.ToString("F0") + " res=" + w.fResist.ToString("F0")
                        + " | M load=" + wm.load.ToString("F0") + " Ftr=" + wm.fTrac.ToString("F0") + " | R load=" + wr.load.ToString("F0") + " Ftr=" + wr.fTrac.ToString("F0") + " slope=" + Vector3.Angle(Vector3.up, veh.transform.up).ToString("F0"));
                }
            }
        }


        [UnityTest]
        public IEnumerator Sweep_SpinVsControlled()
        {
            var cases = new[] { ("utility", SurfaceType.DeepMud, 0.4f), ("utility", SurfaceType.Bog, 0f), ("hauler", SurfaceType.Bog, 0f), ("hauler", SurfaceType.DeepMud, 0f) };
            foreach (var c in cases)
            {
                var sb = new StringBuilder("[MudRunner] SPINSWEEP " + c.Item1 + " " + c.Item2 + " +" + c.Item3.ToString("F1") + "m:");
                foreach (int mode in new[] { 0, 1, 2 })   // 0 spin, 1 controlled (TC 0.25), 2 half throttle
                {
                    var map = TestArena.Strips((-5f, 150f, c.Item2, c.Item3));
                    gs = TestArena.Install(map, new Vector3(0, 0, 0f), 0.4f);
                    Spawn(Def(c.Item1), new Vector3(0, 0, 0f));
                    var dt = veh.drivetrain; dt.awd = true; dt.lowRange = true; dt.centreLock = true; for (int i = 0; i < dt.axleLock.Length; i++) dt.axleLock[i] = true;
                    if (mode == 0) bot.fullThrottleNoGovernor = true;
                    else if (mode == 1) { bot.targetSpeed = 1.5f; bot.tractionControl = true; bot.slipLimit = 0.2f; }
                    else { bot.throttleOverride = 0.35f; }
                    yield return Run(20f);
                    sb.Append(" ").Append(mode == 0 ? "spin" : mode == 1 ? "TC" : "35%").Append("=z").Append(veh.transform.position.z.ToString("F1")).Append("/sink").Append(veh.maxSinkage.ToString("F2")).Append("/slip").Append(veh.meanSlipAbs.ToString("F2")).Append(" |");
                    CleanupVehicle();
                }
                Debug.Log(sb.ToString());
            }
        }


        [UnityTest]
        public IEnumerator Diag_SpinBog()
        {
            var map = TestArena.Strips((-5f, 150f, SurfaceType.Bog, 0f));
            gs = TestArena.Install(map, Vector3.zero, 0.4f);
            Spawn(Def("utility"), Vector3.zero);
            var dt = veh.drivetrain; dt.awd = true; dt.lowRange = true; dt.centreLock = true; for (int i = 0; i < dt.axleLock.Length; i++) dt.axleLock[i] = true;
            bot.fullThrottleNoGovernor = true;
            float t0 = Time.time, next = 0f;
            while (Time.time - t0 < 16f)
            {
                yield return new WaitForFixedUpdate();
                float el = Time.time - t0;
                if (el >= next) { next = el + 2f; var w = veh.wheels[0];
                    Debug.Log("[MudRunner] DIAGSPIN t=" + el.ToString("F0") + " z=" + veh.transform.position.z.ToString("F2") + " rpm=" + dt.rpm.ToString("F0") + " g=" + dt.GearLabel + " eng=" + dt.engagement.ToString("F2") + " Tc=" + dt.clutchTorque.ToString("F0") + " | w0 omega=" + w.omega.ToString("F2") + " slipV=" + w.slipVelocity.ToString("F2") + " excess=" + w.lastExcess.ToString("F2") + " dig/step=" + w.lastDigPerStep.ToString("F5") + " sink=" + w.sinkage.ToString("F2") + " tgt=" + w.targetSinkage.ToString("F2") + " load=" + w.load.ToString("F0") + " cap=" + w.soilContact.thrustCap.ToString("F0") + " Ftr=" + w.fTrac.ToString("F0") + " churn=" + w.churn.ToString("F2") + " soft=" + w.soil.softDepth.ToString("F2")); }
            }
        }

        void CleanupVehicle()
        {
            if (veh != null) Object.Destroy(veh.gameObject);
            veh = null;
            if (GroundService.Instance != null) Object.DestroyImmediate(GroundService.Instance.gameObject);
        }

        /// <summary>Diagnostic: time series of one vehicle in deep mud (per-wheel soil/tyre numbers), 1 line / 0.75 s.</summary>
        [UnityTest]
        public IEnumerator Diag_DeepMud([ValueSource(nameof(Names))] string name)
        {
            var map = TestArena.Strips((0f, 60f, SurfaceType.DeepMud, 0f));
            gs = TestArena.Install(map, new Vector3(0, 0, -30f), 0.4f);
            var d = Def(name);
            Spawn(d, new Vector3(0, 0, -30f));
            veh.drivetrain.awd = true; veh.drivetrain.centreLock = true; veh.drivetrain.lowRange = true;
            for (int i = 0; i < veh.drivetrain.axleLock.Length; i++) veh.drivetrain.axleLock[i] = true;
            bot.targetSpeed = 2.5f;
            float t0 = Time.time, nextLog = 0f;
            while (Time.time - t0 < 40f)
            {
                yield return new WaitForFixedUpdate();
                float el = Time.time - t0;
                if (el >= nextLog && veh.transform.position.z > -4f)
                {
                    nextLog = el + 1.5f;
                    var w = veh.wheels[0]; var wr = veh.wheels[veh.wheels.Length - 1];
                    var dt = veh.drivetrain;
                    Debug.Log("[MudRunner] DIAG " + name + " t=" + el.ToString("F1") + " z=" + veh.transform.position.z.ToString("F1") + " v=" + veh.forwardSpeed.ToString("F2")
                        + " rpm=" + dt.rpm.ToString("F0") + " g=" + dt.GearLabel + " Tc=" + dt.clutchTorque.ToString("F0") + " Te=" + dt.engineTorque.ToString("F0")
                        + " | FL sink=" + w.sinkage.ToString("F2") + " tgt=" + w.targetSinkage.ToString("F2") + " load=" + w.load.ToString("F0") + " slip=" + w.slipRatio.ToString("F2")
                        + " cap=" + w.soilContact.thrustCap.ToString("F0") + " Ftr=" + w.fTrac.ToString("F0") + " Rc=" + w.soilContact.compactionResistance.ToString("F0") + " Rb=" + w.soilContact.bulldozeResistance.ToString("F0")
                        + " | RR sink=" + wr.sinkage.ToString("F2") + " slip=" + wr.slipRatio.ToString("F2") + " Ftr=" + wr.fTrac.ToString("F0") + " belly=" + veh.bellyContact.ToString("F2"));
                }
            }
        }
    }
}
