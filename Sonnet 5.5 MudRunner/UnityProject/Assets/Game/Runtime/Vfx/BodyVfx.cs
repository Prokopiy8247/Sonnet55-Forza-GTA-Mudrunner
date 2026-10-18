using MudRunner.Ground;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Vfx
{
    /// <summary>
    /// Per-vehicle body effects: hull bow wave + side foam sheets + stern turbulence + bow spray when <c>VehicleWater</c> says the hull is wet
    /// (scaled by the speed RELATIVE to the current and the submerged fraction), exhaust smoke (diesel puff on throttle tip-in, thin black smoke under
    /// heavy load, white smoke when cold, starter / stall puffs, water spurts + bubbles when the pipe is under water) and engine-flooded steam / splutter.
    /// </summary>
    public sealed class BodyVfx : MonoBehaviour
    {
        Vehicle vehicle;
        VfxDirector director;
        Transform exhaustT;
        Vector3 exhaustLocal;
        bool exhaustVertical;

        float accBowL, accBowR, accSideL, accSideR, accStern, accSprayL, accSprayR, accMist, accRipple;
        float accIdle, accLoad, accCold, accSteam;
        float prevThrottle, puffCooldown, coldTimer, spluttterTimer;
        bool prevEngineOn;

        public int EmittedThisFrame { get; private set; }
        public float WakeIntensity { get; private set; }
        public float SmokeIntensity { get; private set; }

        public void Setup(Vehicle v, VfxDirector dir)
        {
            vehicle = v; director = dir;
            var anchors = v.GetComponent<VehicleAnchors>();
            if (anchors != null && anchors.exhaust != null)
            {
                exhaustT = anchors.exhaust;
                exhaustLocal = v.transform.InverseTransformPoint(exhaustT.position);
            }
            else
            {
                var d = v.def;
                exhaustLocal = d.bodyCenter + new Vector3(d.bodySize.x * 0.32f, -d.bodySize.y * 0.15f, -d.bodySize.z * 0.5f - 0.05f);
            }
            exhaustVertical = exhaustLocal.y > v.def.bodyCenter.y + v.def.bodySize.y * 0.45f;
            prevEngineOn = v.drivetrain != null && v.drivetrain.engineOn;
        }

        static float Smooth(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3f - 2f * t); }
        static byte B(float v) { return (byte)Mathf.Clamp(Mathf.RoundToInt(v * 255f), 0, 255); }
        static float Flight(float vy, float h0) { const float g = 9.81f; return (vy + Mathf.Sqrt(Mathf.Max(0f, vy * vy + 2f * g * h0))) / g; }

        static int Take(ref float acc, float rate, float dt)
        {
            acc += rate * dt;
            int n = (int)acc;
            if (n > 0) acc -= n;
            if (n > 12) { n = 12; acc = 0f; }
            return n;
        }

        public void Tick(float dt)
        {
            EmittedThisFrame = 0;
            if (vehicle == null || director == null || director.Hub == null) return;
            Hull(dt);
            Exhaust(dt);
        }

        // ------------------------------------------------------------------ hull wake

        void Hull(float dt)
        {
            WakeIntensity = 0f;
            var vw = vehicle.water;
            var gs = GroundService.Instance;
            if (vw == null || gs == null || gs.Map == null || gs.Map.water == null) return;
            var water = gs.Map.water;
            var def = vehicle.def; var t = vehicle.transform; var hub = director.Hub;
            if (vw.submergedFraction < 0.005f && !vw.inWater) return;

            float qs = VfxDirector.Scale;
            Vector3 vel = vehicle.rb.linearVelocity;
            if (!water.Sample(t.position.x, t.position.z, out float levelC, out Vector2 flowC)) return;
            Vector3 flow3 = new Vector3(flowC.x, 0f, flowC.y);
            Vector3 rel = new Vector3(vel.x - flowC.x, 0f, vel.z - flowC.y);
            float relSpeed = rel.magnitude;
            float sub = Mathf.Clamp01(vw.submergedFraction * 4f + 0.15f);
            float wake = Smooth(0.35f, 6f, relSpeed) * sub;
            WakeIntensity = wake;

            Vector3 size = def.bodySize, c = def.bodyCenter;
            Vector3 fwd = t.forward; fwd.y = 0f; fwd = fwd.sqrMagnitude > 1e-4f ? fwd.normalized : Vector3.forward;
            Vector3 right = new Vector3(fwd.z, 0f, -fwd.x);
            Vector3 relDir = relSpeed > 0.2f ? rel / relSpeed : fwd;
            float halfW = size.x * 0.5f, halfL = size.z * 0.5f;
            Vector3 centre = t.TransformPoint(c);
            Color32 foamCol = new Color32(240, 245, 248, 255);
            Color32 white = new Color32(235, 242, 246, 255);
            // water level helper at a world point (falls back to the centre level)
            float Level(Vector3 p) { return water.Sample(p.x, p.z, out float l, out _) ? l : levelC; }

            for (int sideIdx = 0; sideIdx < 2; sideIdx++)
            {
                float sd = sideIdx == 0 ? -1f : 1f;
                Vector3 bow = centre + fwd * (halfL * 0.95f) + right * (sd * halfW * 0.92f);
                float lvl = Level(bow);
                // bow wave: foam pushed outwards, leaves a V shaped trail
                int nBow = Take(ref sideIdx == 0 ? ref accBowL : ref accBowR, 85f * wake * qs, dt);
                for (int k = 0; k < nBow; k++)
                {
                    Vector3 org = new Vector3(bow.x, lvl + 0.025f, bow.z) + fwd * Random.Range(-0.25f, 0.4f) + right * (sd * Random.Range(0f, 0.25f));
                    Vector3 v0 = flow3 + right * (sd * Random.Range(0.45f, 1.5f) * (0.5f + 0.5f * Mathf.Clamp01(relSpeed / 5f))) + vel * Random.Range(0.02f, 0.14f);
                    v0.y = 0f;
                    hub.Emit(Fx.Foam, org, v0, new Color32(foamCol.r, foamCol.g, foamCol.b, B(Random.Range(0.55f, 0.9f))), Random.Range(0.55f, 1.1f) * Mathf.Lerp(0.8f, 1.4f, Mathf.Clamp01(size.z / 7f)), Random.Range(2.4f, 4.2f));
                }
                // side foam along the hull
                int nSide = Take(ref sideIdx == 0 ? ref accSideL : ref accSideR, 55f * wake * qs, dt);
                for (int k = 0; k < nSide; k++)
                {
                    float z = Mathf.Lerp(-0.45f, 0.85f, Mathf.Pow(Random.value, 0.8f)) * halfL;
                    Vector3 p = centre + fwd * z + right * (sd * halfW * 1.02f);
                    float l2 = Level(p);
                    Vector3 v0 = flow3 + right * (sd * Random.Range(0.15f, 0.7f)) + vel * Random.Range(0.0f, 0.06f);
                    v0.y = 0f;
                    hub.Emit(Fx.Foam, new Vector3(p.x, l2 + 0.022f, p.z), v0, new Color32(foamCol.r, foamCol.g, foamCol.b, B(Random.Range(0.4f, 0.75f))), Random.Range(0.4f, 0.85f), Random.Range(2.0f, 3.6f));
                }
                // bow spray
                float sprayK = Smooth(2.2f, 8f, relSpeed) * sub;
                int nSpray = Take(ref sideIdx == 0 ? ref accSprayL : ref accSprayR, 120f * sprayK * qs, dt);
                for (int k = 0; k < nSpray; k++)
                {
                    Vector3 org = new Vector3(bow.x, lvl + 0.04f, bow.z) + right * (sd * Random.Range(-0.1f, 0.3f)) + fwd * Random.Range(-0.2f, 0.5f);
                    Vector3 v0 = right * (sd * Random.Range(0.8f, 3.4f)) + relDir * (relSpeed * Random.Range(0.1f, 0.45f)) + Vector3.up * Random.Range(1.4f, 3.8f + relSpeed * 0.3f) + flow3 * 0.5f;
                    hub.Emit(Fx.Droplet, org, v0, white, Random.Range(0.03f, 0.08f), Mathf.Clamp(Flight(v0.y, 0.04f), 0.25f, 1.6f));
                }
            }
            // stern turbulence
            int nStern = Take(ref accStern, 40f * wake * qs, dt);
            for (int k = 0; k < nStern; k++)
            {
                Vector3 p = centre - fwd * (halfL * 1.0f + Random.Range(0f, 1.5f)) + right * Random.Range(-halfW, halfW);
                float l2 = Level(p);
                Vector3 v0 = flow3 + vel * Random.Range(0f, 0.08f);
                v0.y = 0f;
                hub.Emit(Fx.Foam, new Vector3(p.x, l2 + 0.02f, p.z), v0, new Color32(foamCol.r, foamCol.g, foamCol.b, B(Random.Range(0.35f, 0.7f))), Random.Range(0.6f, 1.3f), Random.Range(2.0f, 3.4f));
            }
            // mist above a fast bow wave
            int nMist = Take(ref accMist, 30f * Smooth(4f, 10f, relSpeed) * sub * qs, dt);
            for (int k = 0; k < nMist; k++)
            {
                Vector3 p = centre + fwd * (halfL * 0.9f) + right * Random.Range(-halfW, halfW);
                hub.Emit(Fx.Mist, new Vector3(p.x, Level(p) + 0.15f, p.z), relDir * relSpeed * 0.2f + Vector3.up * Random.Range(0.4f, 1.2f), new Color32(225, 235, 240, B(0.35f)), Random.Range(0.35f, 0.7f), Random.Range(1f, 1.8f));
            }
            // standing / drifting: ripple rings around the hull
            if (relSpeed < 1.6f && vw.inWater)
            {
                int nRip = Take(ref accRipple, 1.6f * sub * qs, dt);
                for (int k = 0; k < nRip; k++)
                {
                    Vector3 p = centre + fwd * Random.Range(-halfL, halfL) + right * (Random.value < 0.5f ? -halfW : halfW);
                    hub.Emit(Fx.Ripple, new Vector3(p.x, Level(p) + 0.02f, p.z), flow3, new Color32(235, 242, 246, B(0.55f)), Random.Range(0.9f, 1.8f), Random.Range(1.5f, 2.3f));
                }
            }
            EmittedThisFrame += 1;
        }

        // ------------------------------------------------------------------ exhaust + steam

        void Exhaust(float dt)
        {
            SmokeIntensity = 0f;
            var dtn = vehicle.drivetrain;
            if (dtn == null || vehicle.def.isTrailer) return;
            var def = vehicle.def; var t = vehicle.transform; var hub = director.Hub;
            float qs = VfxDirector.Scale;
            bool on = dtn.engineOn;
            Vector3 pos = exhaustT != null ? exhaustT.position : t.TransformPoint(exhaustLocal);
            Vector3 vel = vehicle.rb.linearVelocity;
            Vector3 wind = director.Wind;
            Vector3 jetDir = exhaustVertical ? (Vector3.up * 0.95f - t.forward * 0.15f) : (-t.forward * 0.75f + Vector3.up * 0.25f + t.right * 0.1f);
            jetDir.Normalize();

            float thr = vehicle.throttleEff;
            float load = dtn.loadFraction;
            float rpmN = Mathf.Clamp01(dtn.rpm / Mathf.Max(1f, def.redlineRpm));
            puffCooldown -= dt;

            // exhaust under water? -> bubbles + spurts instead of smoke
            var gs = GroundService.Instance;
            bool pipeUnder = false; float surfY = 0f;
            if (gs != null && gs.Map != null && gs.Map.water != null && gs.Map.water.Sample(pos.x, pos.z, out surfY, out Vector2 fl)) pipeUnder = pos.y < surfY;

            if (on && !prevEngineOn)
            {
                coldTimer = 7f;
                if (!pipeUnder) for (int k = 0; k < 6; k++) EmitSmoke(hub, pos, jetDir, vel, wind, 0.06f, 0.55f, 0.22f, 0.34f, 2.6f + 3f * rpmN);
            }
            if (!on && prevEngineOn && !pipeUnder)
                for (int k = 0; k < 4; k++) EmitSmoke(hub, pos, jetDir, vel, wind, 0.10f, 0.45f, 0.2f, 0.3f, 1.5f);
            prevEngineOn = on;

            if (on && !pipeUnder)
            {
                coldTimer = Mathf.Max(0f, coldTimer - dt);
                float dThr = (thr - prevThrottle) / Mathf.Max(dt, 1e-3f);
                // tip-in puff
                if (dThr > 2.0f && thr > 0.45f && puffCooldown <= 0f)
                {
                    puffCooldown = 0.8f;
                    int cnt = Mathf.Clamp(Mathf.RoundToInt((5f + 11f * rpmN) * qs), 2, 18);
                    for (int k = 0; k < cnt; k++) EmitSmoke(hub, pos, jetDir, vel, wind, Random.Range(0.05f, 0.14f), 0.62f, 0.22f, 0.38f, 3f + 4f * rpmN);
                }
                // idle wisp
                int nIdle = Take(ref accIdle, 7f * qs, dt);
                for (int k = 0; k < nIdle; k++) EmitSmoke(hub, pos, jetDir, vel, wind, 0.50f, 0.10f, 0.12f, 0.2f, 1.2f + 1.5f * rpmN);
                // load smoke
                float loadK = Smooth(0.5f, 0.95f, load) * Smooth(0.2f, 0.8f, thr);
                int nLoad = Take(ref accLoad, 75f * loadK * qs, dt);
                for (int k = 0; k < nLoad; k++) EmitSmoke(hub, pos, jetDir, vel, wind, Random.Range(0.05f, 0.12f), 0.58f, 0.2f, 0.36f, 2.4f + 3.2f * rpmN);
                SmokeIntensity = loadK;
                // cold smoke
                float coldK = Mathf.Clamp01(coldTimer / 6f) * (1f - load * 0.7f);
                int nCold = Take(ref accCold, 26f * coldK * qs, dt);
                for (int k = 0; k < nCold; k++) EmitSmoke(hub, pos, jetDir, vel, wind, 0.80f, 0.26f, 0.2f, 0.34f, 1.6f);
            }
            prevThrottle = thr;

            // water at the pipe
            if (pipeUnder && on)
            {
                int nB = Take(ref accSteam, 14f * qs, dt);
                for (int k = 0; k < nB; k++)
                {
                    Vector3 vOut = Vector3.up * Random.Range(1.5f, 3.5f) + new Vector3(Random.Range(-0.5f, 0.5f), 0f, Random.Range(-0.5f, 0.5f));
                    hub.Emit(Fx.Droplet, new Vector3(pos.x, surfY + 0.02f, pos.z), vOut, new Color32(235, 242, 246, 255), Random.Range(0.03f, 0.07f), Mathf.Clamp(Flight(vOut.y, 0.02f), 0.2f, 1f));
                }
                if (Random.value < 2f * dt)
                    hub.Emit(Fx.Ripple, new Vector3(pos.x, surfY + 0.02f, pos.z), Vector3.zero, new Color32(235, 242, 246, B(0.5f)), Random.Range(0.4f, 0.8f), Random.Range(1.2f, 1.8f));
            }

            // flooded engine: steam from the bonnet + splutters from the pipe
            var vw = vehicle.water;
            if (vw != null && vw.engineFlooded)
            {
                float k = vw.floodTimer > 0f ? 1f : Mathf.Clamp01(1f + vw.floodTimer / 12f);
                Vector3 bonnet = t.TransformPoint(def.bodyCenter + new Vector3(0f, def.bodySize.y * 0.5f + 0.05f, def.bodySize.z * 0.30f));
                int nSteam = Take(ref accSteam, 16f * k * qs, dt);
                for (int i = 0; i < nSteam; i++)
                {
                    Vector3 org = bonnet + t.right * Random.Range(-0.5f, 0.5f) + t.forward * Random.Range(-0.4f, 0.4f);
                    hub.Emit(Fx.Steam, org, vel * 0.5f + wind * 0.5f + Vector3.up * Random.Range(0.6f, 1.4f), new Color32(235, 238, 240, B(0.30f * k + 0.08f)), Random.Range(0.25f, 0.4f), Random.Range(1.6f, 2.6f));
                }
                spluttterTimer -= dt;
                if (spluttterTimer <= 0f && !pipeUnder)
                {
                    spluttterTimer = Random.Range(0.7f, 1.6f);
                    for (int i = 0; i < 6; i++)
                    {
                        Vector3 v0 = jetDir * Random.Range(2f, 5f) + Random.insideUnitSphere * 0.6f + vel * 0.6f;
                        hub.Emit(Fx.Droplet, pos, v0, new Color32(235, 242, 246, 255), Random.Range(0.03f, 0.07f), Mathf.Clamp(Flight(Mathf.Max(v0.y, 0.5f), 0.4f), 0.3f, 1.2f));
                    }
                    for (int i = 0; i < 3; i++) EmitSmoke(hub, pos, jetDir, vel, wind, 0.55f, 0.35f, 0.18f, 0.3f, 3f);
                }
            }
        }

        static void EmitSmoke(ParticleHub hub, Vector3 pos, Vector3 jetDir, Vector3 vel, Vector3 wind, float grey, float alpha, float sizeMin, float sizeMax, float jet)
        {
            Vector3 v0 = jetDir * (jet * Random.Range(0.5f, 1f)) + vel * 0.85f + wind * 0.3f + Random.insideUnitSphere * 0.35f;
            // slightly bluish thin smoke, neutral black smoke
            Color32 c = new Color32(B(grey), B(grey), B(grey * 1.03f), B(alpha));
            hub.Emit(Fx.Smoke, pos + Random.insideUnitSphere * 0.03f, v0, c, Random.Range(sizeMin, sizeMax), Random.Range(1.6f, 3.0f));
        }
    }
}
