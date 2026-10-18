using System.Collections.Generic;
using MudRunner.Game;
using UnityEngine;

namespace MudRunner.Vehicles
{
    /// <summary>Marks a tree / post / rock / ground anchor the winch can hook onto.</summary>
    public sealed class WinchAnchor : MonoBehaviour
    {
        public static readonly List<WinchAnchor> All = new List<WinchAnchor>();
        public Vector3 localPoint = Vector3.up * 0.5f;     // hook point in local space
        public float maxPull = 1e9f;                       // N the anchor can take before it fails (trees: huge, ground anchors: moderate)
        public Rigidbody body;                             // optional (dynamic anchors such as logs)
        public Vector3 WorldPoint => transform.TransformPoint(localPoint);
        void OnEnable() { All.Add(this); }
        void OnDisable() { All.Remove(this); }
        void OnDrawGizmos() { Gizmos.color = Color.yellow; Gizmos.DrawWireSphere(WorldPoint, 0.25f); }
    }

    /// <summary>
    /// Vehicle winch: a rope that can only pull. Tension = stiff spring on the stretch beyond the paid-out length, capped by
    /// the rated line pull. Reeling in shortens the paid-out length at a speed that drops under load; reeling out pays rope.
    /// Anchors: <see cref="WinchAnchor"/> objects (static or dynamic) or another <see cref="Vehicle"/>.
    /// </summary>
    [DefaultExecutionOrder(5)]
    public sealed class Winch : MonoBehaviour
    {
        public Vehicle vehicle;
        public Vector3 fairleadLocal = new Vector3(0f, 0.55f, 2.4f);
        public float ratedPull = 40000f;           // N
        public float maxLength = 25f;              // m
        public float reelInSpeed = 0.45f, reelOutSpeed = 1.2f;   // m/s
        public float ropeStiffness = 120000f;      // N/m of stretch
        public float ropeDamping = 9000f;          // N s/m
        public bool autoAnchorInRange = true;

        public bool Attached { get; private set; }
        public float RopeLength { get; private set; }
        public float Tension { get; private set; }
        public float Distance { get; private set; }
        public float input;                        // +1 reel in, -1 reel out (set by player input / tests)
        public Vector3 AnchorWorldPoint => anchorBody != null ? anchorBody.transform.TransformPoint(anchorLocal)
            : anchorXf != null ? anchorXf.TransformPoint(anchorLocal) : anchorStatic;
        public Vector3 FairleadWorld => transform.TransformPoint(fairleadLocal);
        public string AnchorName { get; private set; } = "";

        Rigidbody anchorBody; Transform anchorXf; Vector3 anchorLocal; Vector3 anchorStatic;
        float anchorMaxPull = 1e9f;
        LineRenderer line;
        Transform hook;
        const int Segs = 18;
        readonly Vector3[] pts = new Vector3[Segs + 1];

        public void Setup(Vehicle v)
        {
            vehicle = v;
            ratedPull = v.def.winchForce; maxLength = v.def.winchLength;
            var s = v.def.bodySize; var c = v.def.bodyCenter;
            fairleadLocal = new Vector3(0f, c.y - s.y * 0.25f, c.z + s.z * 0.5f + 0.15f);
            EnsureVisuals();
        }

        void EnsureVisuals()
        {
            if (line != null) return;
            var go = new GameObject("WinchCable");
            go.transform.SetParent(transform, false);
            line = go.AddComponent<LineRenderer>();
            line.useWorldSpace = true; line.positionCount = Segs + 1;
            line.startWidth = line.endWidth = 0.035f;
            var sh = Shader.Find("Universal Render Pipeline/Unlit") ?? Shader.Find("Sprites/Default");
            if (sh != null) { var m = new Material(sh); m.color = new Color(0.12f, 0.12f, 0.13f); if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", new Color(0.12f, 0.12f, 0.13f)); line.sharedMaterial = m; }
            line.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            line.enabled = false;
            var h = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            h.name = "WinchHook"; Destroy(h.GetComponent<Collider>());
            h.transform.SetParent(go.transform, false); h.transform.localScale = Vector3.one * 0.14f;
            var r = h.GetComponent<Renderer>(); if (r != null && sh != null) { var m2 = new Material(sh); m2.color = new Color(0.8f, 0.6f, 0.1f); r.sharedMaterial = m2; }
            hook = h.transform; hook.gameObject.SetActive(false);
        }

        // ------------------------------------------------------------------ attach / detach

        public bool AttachTo(WinchAnchor a)
        {
            if (a == null) return false;
            anchorBody = a.body; anchorXf = a.transform; anchorLocal = a.localPoint; anchorStatic = a.WorldPoint; anchorMaxPull = a.maxPull;
            AnchorName = a.name;
            return Begin();
        }

        public bool AttachTo(Vehicle other)
        {
            if (other == null || other == vehicle) return false;
            anchorBody = other.rb; anchorXf = other.transform;
            anchorLocal = new Vector3(0f, other.def.bodyCenter.y - other.def.bodySize.y * 0.3f, -other.def.bodySize.z * 0.5f - 0.1f);
            anchorMaxPull = 1e9f; AnchorName = other.def.displayName;
            return Begin();
        }

        bool Begin()
        {
            Distance = Vector3.Distance(FairleadWorld, AnchorWorldPoint);
            if (Distance > maxLength + 1f) { Detach(); return false; }
            RopeLength = Mathf.Min(maxLength, Distance + 0.05f);
            Attached = true; Tension = 0f;
            EnsureVisuals(); line.enabled = true; hook.gameObject.SetActive(true);
            return true;
        }

        public void Detach()
        {
            Attached = false; Tension = 0f; anchorBody = null; anchorXf = null; AnchorName = "";
            if (line != null) { line.enabled = false; hook.gameObject.SetActive(false); }
        }

        /// <summary>Hook the best anchor in front of the vehicle (nearest in a ~75 degree cone) or another vehicle in range.</summary>
        public bool TryAutoAttach()
        {
            Vector3 f = FairleadWorld; Vector3 fwd = transform.forward;
            WinchAnchor best = null; float bestScore = float.MaxValue;
            foreach (var a in WinchAnchor.All)
            {
                Vector3 d = a.WorldPoint - f; float dist = d.magnitude;
                if (dist > maxLength - 1f || dist < 1.5f) continue;
                float ang = Vector3.Angle(fwd, d);
                if (ang > 75f) continue;
                float score = dist + ang * 0.15f;
                if (score < bestScore) { bestScore = score; best = a; }
            }
            Vehicle bestV = null;
            foreach (var v in Vehicle.All)
            {
                if (v == vehicle) continue;
                Vector3 d = v.transform.position - f; float dist = d.magnitude;
                if (dist > maxLength - 1f) continue;
                float ang = Vector3.Angle(fwd, d);
                if (ang > 75f) continue;
                float score = dist + ang * 0.15f + 4f;
                if (score < bestScore) { bestScore = score; bestV = v; best = null; }
            }
            if (best != null) return AttachTo(best);
            if (bestV != null) return AttachTo(bestV);
            return false;
        }

        public void Toggle() { if (Attached) Detach(); else TryAutoAttach(); }

        // ------------------------------------------------------------------ simulation

        void FixedUpdate()
        {
            if (!Attached || vehicle == null) { Tension = 0f; return; }
            float dt = Time.fixedDeltaTime;
            Vector3 fp = FairleadWorld, ap = AnchorWorldPoint;
            Vector3 d = ap - fp; float dist = d.magnitude;
            Distance = dist;
            if (dist < 1e-3f) return;
            Vector3 dir = d / dist;

            // closing speed of the rope ends along the line
            Vector3 vF = vehicle.rb.GetPointVelocity(fp);
            Vector3 vA = anchorBody != null ? anchorBody.GetPointVelocity(ap) : Vector3.zero;
            float stretchRate = Vector3.Dot(vA - vF, dir);      // > 0: ends separating

            // paying rope
            float load = Mathf.Clamp01(Tension / ratedPull);
            if (input > 0.01f)
                RopeLength = Mathf.Max(0.5f, RopeLength - input * reelInSpeed * (1f - 0.75f * load) * dt);
            else if (input < -0.01f)
                RopeLength = Mathf.Min(maxLength, RopeLength - input * reelOutSpeed * dt);

            float stretch = dist - RopeLength;
            float maxStretch = ratedPull / ropeStiffness;
            if (stretch > maxStretch && input > 0.01f) { RopeLength = dist - maxStretch; stretch = maxStretch; }   // drum stalls at rated pull
            float t = 0f;
            if (stretch > 0f) t = ropeStiffness * stretch + ropeDamping * Mathf.Max(0f, stretchRate);
            t = Mathf.Clamp(t, 0f, ratedPull * 1.25f);
            Tension = t;
            if (t > anchorMaxPull) { Detach(); return; }
            if (t > 0f)
            {
                vehicle.rb.AddForceAtPosition(dir * t, fp, ForceMode.Force);
                if (anchorBody != null) anchorBody.AddForceAtPosition(-dir * t, ap, ForceMode.Force);
            }
        }

        // ------------------------------------------------------------------ player input + visuals

        void Update()
        {
            var gm = GameManager.Instance;
            if (gm != null && gm.Player == vehicle && gm.PlayerInput != null)
            {
                if (gm.PlayerInput.pressedWinchAttach) Toggle();
                input = gm.PlayerInput.winchAxis;
            }
            if (!Attached || line == null) return;
            Vector3 a = FairleadWorld, b = AnchorWorldPoint;
            float dist = Vector3.Distance(a, b);
            float slack = Mathf.Max(0f, RopeLength - dist);
            float sag = Mathf.Min(2.5f, Mathf.Sqrt(slack * (dist + RopeLength) * 0.5f) * 0.55f);
            for (int i = 0; i <= Segs; i++)
            {
                float u = i / (float)Segs;
                Vector3 p = Vector3.Lerp(a, b, u);
                p.y -= sag * 4f * u * (1f - u);
                pts[i] = p;
            }
            line.SetPositions(pts);
            float tn = Mathf.Clamp01(Tension / Mathf.Max(1f, ratedPull));
            line.widthMultiplier = Mathf.Lerp(1f, 0.8f, tn);
            hook.position = b;
        }

        public bool IsTaut => Attached && Tension > ratedPull * 0.05f;
    }
}
