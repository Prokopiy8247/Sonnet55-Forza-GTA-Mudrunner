using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.Vehicles
{
    /// <summary>
    /// Water interaction of one vehicle: hull + tyre buoyancy, drag relative to the current, and engine flooding when the
    /// air intake goes under. Everything is derived from <see cref="WaterMap"/>; no triggers or per-object queries.
    /// Buoyancy pushes the body up, so the suspension automatically carries less load (wheels lose traction when floating).
    /// </summary>
    [DefaultExecutionOrder(20)]
    public sealed class VehicleWater : MonoBehaviour
    {
        public Vehicle vehicle;
        public const float Rho = 1000f;
        public float submergedFraction;       // 0..1 of the hull volume currently under water
        public float maxWaterDepthAtWheels;   // m
        public bool inWater;
        public bool engineFlooded;
        public float floodTimer;
        public float currentSpeed;            // m/s of the current at the vehicle
        public bool floating;                 // net buoyancy lifts the vehicle off the bed

        static readonly Vector2[] cols = {
            new Vector2(-1,-1), new Vector2(0,-1), new Vector2(1,-1),
            new Vector2(-1, 0), new Vector2(0, 0), new Vector2(1, 0),
            new Vector2(-1, 1), new Vector2(0, 1), new Vector2(1, 1) };

        void FixedUpdate()
        {
            var v = vehicle; if (v == null || v.def == null) return;
            var gs = GroundService.Instance; var water = gs != null && gs.Map != null ? gs.Map.water : null;
            submergedFraction = 0f; maxWaterDepthAtWheels = 0f; inWater = false; currentSpeed = 0f; v.waterDepthAtVehicle = 0f;
            if (water == null) { if (engineFlooded && floodTimer > 0f) floodTimer -= Time.fixedDeltaTime; return; }
            var rb = v.rb; var def = v.def; var t = v.transform;
            Vector3 size = def.bodySize;

            // ---- hull columns
            float vol = def.displacedVolume / cols.Length;
            float drag = def.waterDragArea / cols.Length;
            float sumFrac = 0f;
            for (int i = 0; i < cols.Length; i++)
            {
                Vector3 lb = def.bodyCenter + new Vector3(cols[i].x * size.x * 0.4f, -size.y * 0.5f, cols[i].y * size.z * 0.4f);
                Vector3 lt = lb + new Vector3(0f, size.y, 0f);
                Vector3 b = t.TransformPoint(lb), top = t.TransformPoint(lt);
                if (!water.Sample(b.x, b.z, out float lvl, out Vector2 flow)) continue;
                float yLo = Mathf.Min(b.y, top.y), yHi = Mathf.Max(b.y, top.y);
                float frac = Mathf.Clamp01((lvl - yLo) / Mathf.Max(0.05f, yHi - yLo));
                if (frac <= 0f) continue;
                sumFrac += frac; inWater = true;
                Vector3 p = Vector3.Lerp(b, top, 0.5f * frac);
                // buoyancy
                rb.AddForceAtPosition(Vector3.up * (Rho * 9.81f * vol * frac), p, ForceMode.Force);
                // drag against the moving water
                Vector3 vw = new Vector3(flow.x, 0f, flow.y);
                Vector3 rel = rb.GetPointVelocity(p) - vw;
                float sp = rel.magnitude;
                if (sp > 0.01f)
                {
                    const float cd = 1.05f;
                    Vector3 fd = -0.5f * Rho * cd * drag * frac * sp * rel;
                    float cap = rb.mass * 0.3f / cols.Length * 9.81f * 6f;
                    if (fd.magnitude > cap) fd = fd.normalized * cap;
                    rb.AddForceAtPosition(fd, p, ForceMode.Force);
                }
                currentSpeed = Mathf.Max(currentSpeed, flow.magnitude);
            }
            submergedFraction = sumFrac / cols.Length;
            v.waterDepthAtVehicle = submergedFraction * size.y;

            // ---- tyre buoyancy
            float buoyTotal = 0f;
            foreach (var w in v.wheels)
            {
                Vector3 hub = w.hubWorld;
                if (!water.Sample(hub.x, hub.z, out float lvl, out Vector2 flow)) continue;
                float R = w.tire.radius;
                float sub = Mathf.Clamp01((lvl - (hub.y - R)) / (2f * R));
                float gh = gs.GroundHeight(hub.x, hub.z);
                maxWaterDepthAtWheels = Mathf.Max(maxWaterDepthAtWheels, Mathf.Max(0f, lvl - gh));
                if (sub <= 0f) continue;
                float vt = 0.5f * Mathf.PI * R * R * w.tire.width;       // hollow tyre displaces ~half its envelope
                float fb = Rho * 9.81f * vt * sub; buoyTotal += fb;
                rb.AddForceAtPosition(Vector3.up * fb, hub, ForceMode.Force);
            }
            floating = (submergedFraction * def.displacedVolume * Rho * 9.81f + buoyTotal) > rb.mass * 9.81f * 0.98f;

            // ---- engine intake
            Vector3 intake = t.TransformPoint(v.IntakeLocal);
            bool underwater = water.Sample(intake.x, intake.z, out float il, out _) && intake.y < il;
            if (underwater)
            {
                floodTimer += Time.fixedDeltaTime;
                if (floodTimer > 0.6f && !engineFlooded)
                {
                    engineFlooded = true;
                    if (v.drivetrain.engineOn) v.drivetrain.engineOn = false;
                }
            }
            else if (engineFlooded)
            {
                floodTimer -= Time.fixedDeltaTime;                 // drains slowly once the intake is out of the water
                if (floodTimer < -12f) { engineFlooded = false; floodTimer = 0f; }
            }
            else floodTimer = Mathf.Max(0f, floodTimer - Time.fixedDeltaTime);
        }

        public bool CanStartEngine => !engineFlooded;
    }
}
