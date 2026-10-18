using MudRunner.Ground;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Vfx
{
    /// <summary>
    /// Per-vehicle wheel effects (one component per Vehicle incl. trailers, created and ticked by <see cref="VfxDirector"/>):
    ///  * mud: chunky blobs flung rearwards / upwards from the tyre (rate ~ wheel-spin slip x softness), soft slurry puffs, a short "slap" burst when the wheel digs hard,
    ///    entry splash when a fast wheel hits mud; ballistic particles with a computed flight time, colour from the surface tint
    ///  * dust on dry firm / gravel / sand surfaces at speed, pebbles on gravel
    ///  * water: spray droplets + mist + foam trail + ripple rings while the wheel is in water, entry splash bursts above ~2 m/s
    /// Reads Wheel.grounded / slipVelocity / sinkage / soil / patchCenter / contactNormal / churn / lastDigPerStep, WaterMap and the wind.
    /// </summary>
    public sealed class WheelVfx : MonoBehaviour
    {
        sealed class WState
        {
            public float accBlob, accSlurry, accDust, accPebble, accDrop, accMist, accFoam, accRipple;
            public bool wasInWater;
            public float prevMud, prevSinkage, slapCooldown;
            public float emitted;       // telemetry
        }

        Vehicle vehicle;
        WState[] st;
        VfxDirector director;

        public int EmittedThisFrame { get; private set; }
        public float MudIntensity { get; private set; }     // max over wheels, 0..1 (telemetry / tests)

        public void Setup(Vehicle v, VfxDirector dir)
        {
            vehicle = v; director = dir;
            st = new WState[v.wheels.Length];
            for (int i = 0; i < st.Length; i++) st[i] = new WState();
        }

        // ------------------------------------------------------------------ surface palette

        public static Color SurfaceColor(SurfaceType t, float wet)
        {
            Color c;
            switch (t)
            {
                case SurfaceType.Rock: c = new Color(0.52f, 0.51f, 0.49f); break;
                case SurfaceType.FirmSoil: c = new Color(0.44f, 0.35f, 0.25f); break;
                case SurfaceType.Grass: c = new Color(0.31f, 0.25f, 0.15f); break;
                case SurfaceType.Gravel: c = new Color(0.58f, 0.53f, 0.46f); break;
                case SurfaceType.ShallowMud: c = new Color(0.30f, 0.21f, 0.13f); break;
                case SurfaceType.DeepMud: c = new Color(0.22f, 0.15f, 0.10f); break;
                case SurfaceType.Bog: c = new Color(0.13f, 0.11f, 0.07f); break;
                default: c = new Color(0.66f, 0.58f, 0.41f); break;     // sand / silt
            }
            float dark = Mathf.Lerp(1.15f, 0.9f, Mathf.Clamp01(wet));
            return new Color(c.r * dark, c.g * dark, c.b * dark, 1f);
        }

        /// <summary>How muddy the material thrown by a tyre on this surface is (0 dry dust ... 1 liquid mud).</summary>
        public static float Mudiness(SurfaceType t, float wet, float churn)
        {
            float m;
            switch (t)
            {
                case SurfaceType.Rock: m = 0.02f; break;
                case SurfaceType.FirmSoil: m = 0.10f + 0.75f * wet; break;
                case SurfaceType.Grass: m = 0.22f + 0.65f * wet; break;
                case SurfaceType.Gravel: m = 0.04f + 0.40f * wet; break;
                case SurfaceType.ShallowMud: m = 0.92f; break;
                case SurfaceType.Sand: m = 0.08f + 0.40f * wet; break;
                default: m = 1f; break;                                  // deep mud, bog
            }
            return Mathf.Clamp01(m + churn * 0.35f);
        }

        static float Dustiness(SurfaceType t)
        {
            switch (t)
            {
                case SurfaceType.Rock: return 0.45f;
                case SurfaceType.FirmSoil: return 1f;
                case SurfaceType.Grass: return 0.30f;
                case SurfaceType.Gravel: return 1.0f;
                case SurfaceType.Sand: return 1.25f;
                default: return 0f;
            }
        }

        static float Pebbliness(SurfaceType t)
        {
            switch (t)
            {
                case SurfaceType.Gravel: return 1f;
                case SurfaceType.Rock: return 0.3f;
                case SurfaceType.FirmSoil: return 0.18f;
                default: return 0f;
            }
        }

        static float Smooth(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3f - 2f * t); }

        static byte B(float v) { return (byte)Mathf.Clamp(Mathf.RoundToInt(v * 255f), 0, 255); }

        static Color32 Tint(Color c, float jitter, float alpha)
        {
            float j = Random.Range(1f - jitter, 1f + jitter);
            return new Color32(B(c.r * j), B(c.g * j), B(c.b * j), B(alpha));
        }

        static float Flight(float vy, float h0)
        {
            const float g = 9.81f;
            return (vy + Mathf.Sqrt(Mathf.Max(0f, vy * vy + 2f * g * h0))) / g;
        }

        static int Take(ref float acc, float rate, float dt)
        {
            acc += rate * dt;
            int n = (int)acc;
            if (n > 0) acc -= n;
            if (n > 12) { n = 12; acc = 0f; }
            return n;
        }

        // ------------------------------------------------------------------ tick

        public void Tick(float dt)
        {
            EmittedThisFrame = 0; MudIntensity = 0f;
            if (vehicle == null || vehicle.wheels == null || director == null) return;
            var gs = GroundService.Instance;
            if (gs == null || gs.Map == null) return;
            var hub = director.Hub; if (hub == null) return;
            var water = gs.Map.water;
            float qs = VfxDirector.Scale;
            Rigidbody rb = vehicle.rb;
            Transform vt = vehicle.transform;
            Vector3 wind = director.Wind;
            float fixedDt = Mathf.Max(Time.fixedDeltaTime, 1e-3f);

            for (int i = 0; i < vehicle.wheels.Length; i++)
            {
                var w = vehicle.wheels[i]; var s = st[i];
                s.slapCooldown -= dt;
                if (!w.grounded) { s.wasInWater = false; s.prevMud = 0f; s.prevSinkage = 0f; continue; }

                // ---- geometry of the contact
                Vector3 n = w.contactNormal;
                Vector3 fwd = Quaternion.AngleAxis(w.steerAngle, vt.up) * vt.forward;
                fwd = fwd - n * Vector3.Dot(fwd, n);
                fwd = fwd.sqrMagnitude > 1e-6f ? fwd.normalized : vt.forward;
                Vector3 side = Vector3.Cross(n, fwd);
                Vector3 pc = w.patchCenter;
                Vector3 vel = rb.GetPointVelocity(pc);
                Vector3 velH = new Vector3(vel.x, 0f, vel.z);
                float speed = velH.magnitude;
                float halfW = Mathf.Max(0.08f, w.tire.width * 0.42f);
                float halfL = Mathf.Max(0.12f, w.soilContact.contactLength * 0.5f);
                float sizeK = Mathf.Clamp(w.tire.width / 0.375f, 0.7f, 1.5f);

                float spin = w.slipVelocity;
                float absSlip = Mathf.Abs(spin);
                float sgn = spin >= 0f ? 1f : -1f;

                // ---- surface
                var soil = w.soil;
                SurfaceType dom = soil.dominant;
                float wet = Mathf.Clamp01(soil.wet);
                float mud = Mudiness(dom, wet, w.churn);
                float soft = Mathf.Clamp01(soil.softDepth / 0.55f);
                float depthK = Mathf.Clamp01(0.35f + 0.65f * soft + w.sinkage * 1.2f);
                Color surf = SurfaceColor(dom, wet + w.churn * 0.4f);
                float dustK = Dustiness(dom) * (1f - mud) * (1f - wet * 0.85f);
                float pebbleK = Pebbliness(dom) * (1f - mud * 0.8f);

                // ---- water at the patch
                bool inWater = false; float waterY = 0f; float waterDepth = 0f; Vector2 flow = Vector2.zero;
                if (water != null && water.Sample(pc.x, pc.z, out waterY, out flow))
                {
                    waterDepth = waterY - pc.y;
                    inWater = waterDepth > 0.035f;
                }
                float depthN = inWater ? Mathf.Clamp01(waterDepth / 0.55f) : 0f;
                float mudEff = mud * (1f - Mathf.Clamp01(waterDepth / 0.25f));
                if (mudEff > MudIntensity) MudIntensity = mudEff;
                float speedK = Mathf.Clamp01(speed / 9f);

                // ============================================================== mud
                float spinK = Smooth(0.5f, 5f, absSlip);
                float blobRate = (200f * spinK * mudEff * depthK + 38f * mudEff * speedK * speedK) * qs;
                int nBlob = Take(ref s.accBlob, blobRate, dt);
                for (int k = 0; k < nBlob; k++)
                {
                    Vector3 org = pc + side * Random.Range(-halfW, halfW) - fwd * (halfL * sgn * Random.Range(0.4f, 1f)) + n * Random.Range(0.02f, 0.10f);
                    float throwSpeed = Mathf.Clamp(absSlip * 0.60f + speed * 0.22f, 1.8f, 15f) * Random.Range(0.45f, 1.1f);
                    bool spinning = absSlip > 1.0f;
                    Vector3 dir = spinning ? -sgn * fwd : -fwd;              // spinning: against the slip direction, rolling: shed to the rear
                    Throw(hub, Fx.MudBlob, org, dir, throwSpeed, 28f, 75f, 22f, vel * 0.95f, Tint(surf, 0.13f, 0.95f),
                          Mathf.Lerp(0.045f, 0.16f, Mathf.Pow(Random.value, 1.8f)) * sizeK, 1f);
                }
                int nSlurry = Take(ref s.accSlurry, blobRate * 0.30f, dt);
                for (int k = 0; k < nSlurry; k++)
                {
                    Vector3 org = pc + side * Random.Range(-halfW, halfW) - fwd * (halfL * sgn) + n * 0.06f;
                    float throwSpeed = Mathf.Clamp(absSlip * 0.40f + speed * 0.15f, 1.2f, 9f) * Random.Range(0.4f, 1f);
                    Throw(hub, Fx.MudSlurry, org, -sgn * fwd, throwSpeed, 20f, 60f, 28f, vel * 0.8f, Tint(surf, 0.10f, 0.50f),
                          Random.Range(0.22f, 0.42f) * sizeK, 0.8f, 0.55f);
                }

                // entry splash (fast wheel hits mud)
                if (mudEff > 0.55f && s.prevMud < 0.30f && speed > 2f)
                {
                    int cnt = Mathf.Clamp(Mathf.RoundToInt((10f + speed * 4f) * qs), 3, 60);
                    for (int k = 0; k < cnt; k++)
                    {
                        Vector3 org = pc + side * Random.Range(-halfW, halfW) + fwd * halfL + n * 0.05f;
                        Throw(hub, Fx.MudBlob, org, Random.value < 0.5f ? side : -side, Random.Range(1.5f, 5f) + speed * 0.25f, 35f, 80f, 55f, vel * 0.55f, Tint(surf, 0.13f, 0.95f),
                              Mathf.Lerp(0.04f, 0.14f, Mathf.Pow(Random.value, 1.7f)) * sizeK, 1f);
                    }
                    for (int k = 0; k < cnt / 4; k++)
                        Throw(hub, Fx.MudSlurry, pc + n * 0.1f, side * (Random.value < 0.5f ? 1f : -1f), Random.Range(1f, 3f), 20f, 55f, 40f, vel * 0.5f, Tint(surf, 0.1f, 0.5f), Random.Range(0.3f, 0.5f) * sizeK, 0.8f, 0.55f);
                }

                // slap: the wheel digs hard -> a heavy burst up and out to both sides
                float digRate = w.lastDigPerStep / fixedDt;
                float dSink = (w.sinkage - s.prevSinkage) / Mathf.Max(dt, 1e-3f);
                if (s.slapCooldown <= 0f && mudEff > 0.4f && absSlip > 1.2f && (digRate > 0.20f || dSink > 0.40f))
                {
                    s.slapCooldown = Random.Range(0.18f, 0.32f);
                    int cnt = Mathf.Clamp(Mathf.RoundToInt((9f + absSlip * 2.2f) * qs), 3, 40);
                    for (int k = 0; k < cnt; k++)
                    {
                        Vector3 org = pc + side * Random.Range(-halfW, halfW) + n * 0.05f;
                        Vector3 dirK = (Random.value < 0.5f ? side : -side) * Random.Range(0.3f, 1f) + (-sgn * fwd) * Random.Range(0.2f, 1f);
                        Throw(hub, Fx.MudBlob, org, dirK.normalized, Random.Range(2.5f, 6.5f) + absSlip * 0.3f, 40f, 82f, 25f, vel * 0.5f, Tint(surf, 0.13f, 0.95f),
                              Mathf.Lerp(0.05f, 0.18f, Mathf.Pow(Random.value, 1.6f)) * sizeK, 1f);
                    }
                }
                s.prevSinkage = w.sinkage;
                s.prevMud = Mathf.Lerp(s.prevMud, mudEff, 0.5f);

                // ============================================================== dust + pebbles
                float dustRate = 62f * dustK * (Smooth(2.5f, 16f, speed) * 0.85f + Smooth(0.6f, 5f, absSlip)) * qs;
                int nDust = Take(ref s.accDust, dustRate, dt);
                if (nDust > 0)
                {
                    Color dc = Color.Lerp(surf, Color.white, 0.38f);
                    float a = Mathf.Clamp01(0.32f * Mathf.Clamp01(dustK + 0.2f));
                    for (int k = 0; k < nDust; k++)
                    {
                        Vector3 org = pc + side * Random.Range(-halfW * 1.4f, halfW * 1.4f) - fwd * (halfL * 0.8f * sgn) + n * Random.Range(0.03f, 0.18f);
                        Vector3 v0 = -velH * Random.Range(0.0f, 0.08f) + vel * 0.35f + wind * 0.4f + n * Random.Range(0.4f, 1.7f) + side * Random.Range(-0.9f, 0.9f) - sgn * fwd * Mathf.Clamp(absSlip * 0.18f, 0f, 2.5f);
                        hub.Emit(Fx.Dust, org, v0, Tint(dc, 0.06f, a), Random.Range(0.55f, 1.0f) * sizeK, Random.Range(1.9f, 3.4f));
                    }
                    EmittedThisFrame += nDust;
                }
                int nPeb = Take(ref s.accPebble, 18f * pebbleK * (Smooth(1f, 8f, speed) * 0.5f + Smooth(0.8f, 5f, absSlip)) * qs, dt);
                for (int k = 0; k < nPeb; k++)
                {
                    Vector3 org = pc + side * Random.Range(-halfW, halfW) - fwd * (halfL * sgn) + n * 0.04f;
                    float throwSpeed = Mathf.Clamp(absSlip * 0.5f + speed * 0.3f, 1.5f, 11f) * Random.Range(0.4f, 1.1f);
                    float g = Random.Range(0.55f, 0.75f);
                    Throw(hub, Fx.Pebble, org, -sgn * fwd, throwSpeed, 15f, 65f, 30f, vel * 0.9f, new Color32(B(g), B(g * 0.97f), B(g * 0.9f), 255), Random.Range(0.02f, 0.05f), 1f);
                }

                // ============================================================== water
                if (inWater)
                {
                    Vector3 relV = new Vector3(vel.x - flow.x, 0f, vel.z - flow.y);
                    float relSpeed = relV.magnitude;
                    float sK = Mathf.Clamp01(relSpeed / 8f);
                    float surfY = waterY + 0.02f;
                    float dropRate = (270f * Mathf.Pow(sK, 1.15f) * (0.22f + 0.78f * depthN) + 130f * Smooth(0.5f, 5f, absSlip) * depthN) * qs;
                    int nDrop = Take(ref s.accDrop, dropRate, dt);
                    Color32 white = new Color32(235, 242, 246, 255);
                    for (int k = 0; k < nDrop; k++)
                    {
                        float sd = Random.value < 0.5f ? 1f : -1f;
                        Vector3 org = new Vector3(pc.x, surfY, pc.z) + side * (sd * Random.Range(halfW * 0.5f, halfW * 1.1f)) + fwd * Random.Range(-halfL, halfL * 1.6f);
                        Vector3 vOut = side * (sd * Random.Range(0.8f, 3.2f)) + relV * Random.Range(0.2f, 0.7f) + Vector3.up * Random.Range(1.6f, 4.5f + relSpeed * 0.35f) + Vector3.right * flow.x * 0.5f + Vector3.forward * flow.y * 0.5f;
                        float life = Mathf.Clamp(Flight(vOut.y, 0.02f), 0.2f, 1.6f);
                        hub.Emit(Fx.Droplet, org, vOut, white, Random.Range(0.025f, 0.075f), life);
                    }
                    int nMist = Take(ref s.accMist, dropRate * 0.16f, dt);
                    for (int k = 0; k < nMist; k++)
                    {
                        float sd = Random.value < 0.5f ? 1f : -1f;
                        Vector3 org = new Vector3(pc.x, surfY + 0.05f, pc.z) + side * (sd * Random.Range(halfW * 0.5f, halfW * 1.2f));
                        hub.Emit(Fx.Mist, org, side * (sd * Random.Range(0.3f, 1.2f)) + relV * 0.3f + Vector3.up * Random.Range(0.4f, 1.4f), new Color32(225, 235, 240, B(0.38f)), Random.Range(0.25f, 0.45f), Random.Range(0.8f, 1.5f));
                    }
                    // foam trail on the surface behind the tyre
                    int nFoam = Take(ref s.accFoam, 48f * sK * (0.35f + 0.65f * depthN) * qs, dt);
                    for (int k = 0; k < nFoam; k++)
                    {
                        Vector3 org = new Vector3(pc.x, surfY, pc.z) + side * Random.Range(-halfW * 1.3f, halfW * 1.3f) - fwd * Random.Range(0f, halfL * 2f);
                        Vector3 v0 = new Vector3(flow.x, 0f, flow.y) + side * Random.Range(-0.5f, 0.5f);
                        hub.Emit(Fx.Foam, org, v0, new Color32(240, 245, 248, B(Random.Range(0.5f, 0.8f))), Random.Range(0.35f, 0.7f) * sizeK, Random.Range(1.8f, 3.2f));
                    }
                    // slow wheel: ripple rings
                    int nRip = Take(ref s.accRipple, 2.4f * depthN * (1f - sK) * qs, dt);
                    for (int k = 0; k < nRip; k++)
                        hub.Emit(Fx.Ripple, new Vector3(pc.x + Random.Range(-halfW, halfW), surfY, pc.z), new Vector3(flow.x, 0f, flow.y), new Color32(235, 242, 246, B(0.55f)), Random.Range(0.5f, 0.9f) * sizeK, Random.Range(1.2f, 1.9f));

                    // entry burst
                    if (!s.wasInWater && relSpeed > 2f)
                    {
                        int cnt = Mathf.Clamp(Mathf.RoundToInt((12f + relSpeed * 6f) * qs), 4, 80);
                        for (int k = 0; k < cnt; k++)
                        {
                            float sd = Random.value < 0.5f ? 1f : -1f;
                            Vector3 org = new Vector3(pc.x, surfY, pc.z) + side * (sd * Random.Range(0f, halfW)) + fwd * Random.Range(0f, halfL * 1.5f);
                            Vector3 vOut = side * (sd * Random.Range(1f, 4.5f)) + fwd * Random.Range(0.3f, 1f) * relSpeed * 0.35f + Vector3.up * Random.Range(2.2f, 6.5f + relSpeed * 0.3f);
                            hub.Emit(Fx.Droplet, org, vOut, white, Random.Range(0.03f, 0.09f), Mathf.Clamp(Flight(vOut.y, 0.02f), 0.25f, 1.8f));
                        }
                        for (int k = 0; k < Mathf.Max(2, cnt / 6); k++)
                            hub.Emit(Fx.Mist, new Vector3(pc.x, surfY + 0.1f, pc.z), side * Random.Range(-1.5f, 1.5f) + Vector3.up * Random.Range(0.8f, 2.2f), new Color32(225, 235, 240, B(0.45f)), Random.Range(0.3f, 0.6f), Random.Range(1f, 1.8f));
                        for (int k = 0; k < 3; k++)
                            hub.Emit(Fx.Ripple, new Vector3(pc.x + Random.Range(-0.2f, 0.2f), surfY, pc.z + Random.Range(-0.2f, 0.2f)), Vector3.zero, new Color32(235, 242, 246, B(0.6f)), Random.Range(0.8f, 1.5f), Random.Range(1.4f, 2.1f));
                        EmittedThisFrame += cnt;
                    }
                }
                s.wasInWater = inWater;
                EmittedThisFrame += nBlob + nSlurry + nPeb;
            }
        }

        /// <summary>Emit a ballistic particle thrown along <paramref name="dir"/> (horizontal-ish) with elevation in [elevMin, elevMax] degrees and an azimuth spread.</summary>
        static void Throw(ParticleHub hub, Fx fx, Vector3 origin, Vector3 dir, float speed, float elevMin, float elevMax, float spreadDeg,
                          Vector3 inherit, Color32 color, float size, float lifeMul, float lifeMin = 0f)
        {
            float elev = Random.Range(elevMin, elevMax) * Mathf.Deg2Rad;
            dir.y = 0f;
            dir = dir.sqrMagnitude > 1e-6f ? dir.normalized : Vector3.forward;
            Vector3 horiz = Quaternion.AngleAxis(Random.Range(-spreadDeg, spreadDeg), Vector3.up) * dir;
            Vector3 v = (horiz * Mathf.Cos(elev) + Vector3.up * Mathf.Sin(elev)) * speed + inherit;
            float life = Flight(v.y, 0.12f) * lifeMul;
            life = Mathf.Clamp(life, Mathf.Max(0.3f, lifeMin), 2.6f);
            hub.Emit(fx, origin, v, color, size, life);
        }
    }
}
