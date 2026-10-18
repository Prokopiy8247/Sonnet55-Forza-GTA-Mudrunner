using System.Collections.Generic;
using MudRunner.Vehicles;
using UnityEngine;

namespace MudRunner.Testing
{
    /// <summary>
    /// Scripted driver used by the automated physics tests and for demos: holds a target speed and steers toward a list
    /// of waypoints (or straight along +Z). Writes into <see cref="Vehicle.input"/> every fixed step.
    /// </summary>
    [DefaultExecutionOrder(-20)]
    public sealed class BotDriver : MonoBehaviour
    {
        public Vehicle vehicle;
        public float targetSpeed = 4f;           // m/s, forward; negative = reverse
        public float maxThrottle = 1f;
        public bool useWaypoints;
        public List<Vector3> waypoints = new List<Vector3>();
        public float waypointRadius = 4f;
        public int waypointIndex;
        public float steerGain = 1.6f;
        public bool holdBrake;
        [Header("Throttle shaping")]
        public bool fullThrottleNoGovernor;     // ignore target speed, floor it (spinning-wheels test)
        public float throttleOverride = -1f;    // >= 0 forces this throttle
        [Tooltip("Careful driver: backs off the throttle when the wheels slip (what a good player does in mud).")]
        public bool tractionControl;
        public float slipLimit = 0.38f;                 // legacy (ratio based), unused by the slip-speed controller
        public float slipSpeedAllowance = 0.45f;        // m/s of tyre slip tolerated at standstill

        public bool ReachedLastWaypoint { get; private set; }

        void FixedUpdate()
        {
            if (vehicle == null) return;
            var inp = vehicle.input;
            float v = vehicle.forwardSpeed;
            float thr = 0f, brk = 0f;

            inp.handbrake = holdBrake;
            if (holdBrake) { thr = 0f; brk = 0f; }
            else if (throttleOverride >= 0f) { thr = throttleOverride; }
            else if (fullThrottleNoGovernor) { thr = maxThrottle; }
            else
            {
                float err = targetSpeed - v;
                if (targetSpeed >= 0f)
                {
                    thr = Mathf.Clamp01(err * 0.6f + 0.25f) * maxThrottle;
                    if (err < -0.8f) { thr = 0f; brk = Mathf.Clamp01(-err * 0.3f); }
                }
                else
                {
                    // reverse: in automatic mode brake pedal = reverse throttle
                    brk = Mathf.Clamp01(-err * 0.6f + 0.25f) * maxThrottle; thr = 0f;
                }
            }
            if (tractionControl && !fullThrottleNoGovernor && vehicle.groundedWheels > 0)
            {
                // back off when the tyres slip faster than the soil can use: allowance grows with ground speed
                float allowed = slipSpeedAllowance + 0.35f * Mathf.Abs(vehicle.forwardSpeed);
                float over = (vehicle.meanSlipSpeed - allowed) / (allowed + 0.5f);
                if (over > 0f) { float f = Mathf.Clamp01(1f - over * 1.2f); thr *= Mathf.Max(0.3f, f); if (targetSpeed < 0f) brk *= Mathf.Max(0.3f, f); }
            }
            inp.throttle = thr; inp.brake = brk;

            float steer = 0f;
            if (useWaypoints && waypoints.Count > 0 && waypointIndex < waypoints.Count)
            {
                Vector3 to = waypoints[waypointIndex] - vehicle.transform.position; to.y = 0f;
                if (to.magnitude < waypointRadius) { waypointIndex++; if (waypointIndex >= waypoints.Count) ReachedLastWaypoint = true; }
                else
                {
                    float ang = Vector3.SignedAngle(vehicle.transform.forward, to, Vector3.up);
                    steer = Mathf.Clamp(ang / 30f * steerGain, -1f, 1f);
                }
            }
            inp.steer = steer;
            vehicle.input = inp;
        }
    }
}
