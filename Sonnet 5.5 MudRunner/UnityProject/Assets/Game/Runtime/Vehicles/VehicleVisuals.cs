using System;
using System.Collections.Generic;
using MudRunner.Game;
using UnityEngine;

namespace MudRunner.Vehicles
{
    /// <summary>Blender object names are file-global, so exported nodes may carry an "Asset__" prefix (Scout__Wheel_FL). Matching ignores it.</summary>
    public static class ModelNames
    {
        public static string Norm(string name)
        {
            int i = name.LastIndexOf("__", System.StringComparison.Ordinal);
            return i >= 0 ? name.Substring(i + 2) : name;
        }
    }

    /// <summary>Named anchor points taken from the Blender model's empties (Anchor_Winch, Anchor_Hitch, Cam_Cockpit, Intake, Exhaust, CargoOrigin).</summary>
    public sealed class VehicleAnchors : MonoBehaviour
    {
        public Transform winch, hitch, cockpit, intake, exhaust, cargo, fuelCap;

        public static VehicleAnchors Collect(GameObject root)
        {
            var a = root.GetComponent<VehicleAnchors>() ?? root.AddComponent<VehicleAnchors>();
            foreach (var t in root.GetComponentsInChildren<Transform>(true))
            {
                switch (ModelNames.Norm(t.name))
                {
                    case "Anchor_Winch": case "Anchor_TowFront": if (a.winch == null) a.winch = t; break;
                    case "Anchor_Hitch": a.hitch = t; break;
                    case "Cam_Cockpit": a.cockpit = t; break;
                    case "Intake": a.intake = t; break;
                    case "Exhaust": a.exhaust = t; break;
                    case "CargoOrigin": a.cargo = t; break;
                    case "Fuel_Cap": a.fuelCap = t; break;
                }
            }
            return a;
        }

        public Vector3 Local(Transform t) { return transform.InverseTransformPoint(t.position); }

        /// <summary>Push the model's anchor positions into the definition-driven systems (winch fairlead, hitch, intake).</summary>
        public void Apply(Vehicle v)
        {
            if (winch != null && v.winch != null) v.winch.fairleadLocal = Local(winch);
            if (intake != null) v.intakeOverrideLocal = Local(intake);
            if (hitch != null) v.hitchOverrideLocal = Local(hitch);
        }
    }

    /// <summary>
    /// Makes the visible suspension of a Blender-authored vehicle follow the physics: axle beams tilt and rise with the hubs, coil springs
    /// compress/extend and re-aim, shock bodies/rods telescope, links swing, leaf packs ride with the axle. Parts are found BY NAME
    /// (Docs/ART_SPEC.md §4.1) and their rest pose is captured from the prefab pose.
    /// </summary>
    [DefaultExecutionOrder(50)]
    public sealed class SuspensionVisuals : MonoBehaviour
    {
        enum Kind { Axle, Spring, ShockBody, ShockRod, Link, Follow }

        sealed class Part
        {
            public Transform t; public Kind kind; public int wheelA = -1, wheelB = -1;
            public Vector3 restPos; public Quaternion restRot; public Vector3 restScale;
            public Vector3 topRest, botRest, restDir; public float restLen;
            public Vector3 localAxis;
            public Vector3 leftRest, rightRest;   // axle: rest hub positions
        }

        readonly List<Part> parts = new List<Part>();
        Vehicle vehicle;
        public int PartCount => parts.Count;

        static int AxleIndex(string token, int axleCount)
        {
            switch (token)
            {
                case "Front": return 0;
                case "Mid": return axleCount > 2 ? 1 : 0;
                case "Rear": return axleCount - 1;
            }
            return -1;
        }

        static bool ParseAxleSide(string name, int axleCount, out int axle, out int side)
        {
            axle = -1; side = -1;
            var toks = name.Split('_');
            foreach (var tk in toks)
            {
                int a = AxleIndex(tk, axleCount); if (a >= 0) axle = a;
                if (tk == "L") side = 0; else if (tk == "R") side = 1;
            }
            return axle >= 0;
        }

        public void Setup(Vehicle v)
        {
            vehicle = v; parts.Clear();
            var root = transform;
            var byName = new Dictionary<string, Transform>();
            foreach (var t in GetComponentsInChildren<Transform>(true)) byName[ModelNames.Norm(t.name)] = t;
            int axleCount = v.def.axles.Length;

            foreach (var kv in byName)
            {
                string n = kv.Key; Transform t = kv.Value;
                if (t == root) continue;
                if (n.StartsWith("Axle_"))
                {
                    if (!ParseAxleSide(n, axleCount, out int ax, out _)) continue;
                    var p = Base(t, Kind.Axle); p.wheelA = ax * 2; p.wheelB = ax * 2 + 1;
                    p.leftRest = HubRest(v, ax * 2); p.rightRest = HubRest(v, ax * 2 + 1);
                    parts.Add(p);
                }
                else if (n.StartsWith("Spring_") || n.StartsWith("Shock_") || n.StartsWith("Link_"))
                {
                    bool isRod = n.EndsWith("_Rod"), isBody = n.EndsWith("_Body");
                    string stem = n;
                    if (isRod) stem = n.Substring(0, n.Length - 4); else if (isBody) stem = n.Substring(0, n.Length - 5);
                    string kindToken = n.StartsWith("Spring_") ? "Spring" : n.StartsWith("Shock_") ? "Shock" : "Link";
                    string tail = stem.Substring(kindToken.Length + 1);                         // e.g. Front_L / TrailingArm_Front_L
                    string topName, botName;
                    if (kindToken == "Link") { topName = "Mount_Link_" + tail.Split('_')[0] + "_Body"; botName = "Mount_Link_" + tail.Split('_')[0] + "_Axle"; }
                    else { topName = "Mount_" + kindToken + "_" + tail + "_Top"; botName = "Mount_" + kindToken + "_" + tail + "_Bot"; }
                    if (kindToken == "Link" && (!byName.ContainsKey(topName) || !byName.ContainsKey(botName)))
                    {   // links may carry axle/side in the mount names instead
                        topName = "Mount_" + stem + "_Body"; botName = "Mount_" + stem + "_Axle";
                    }
                    if (!byName.TryGetValue(topName, out var top) || !byName.TryGetValue(botName, out var bot)) continue;
                    ParseAxleSide(stem, axleCount, out int ax, out int side);
                    if (ax < 0) continue;
                    var p = Base(t, kindToken == "Spring" ? Kind.Spring : kindToken == "Link" ? Kind.Link : (isRod ? Kind.ShockRod : Kind.ShockBody));
                    p.topRest = root.InverseTransformPoint(top.position); p.botRest = root.InverseTransformPoint(bot.position);
                    p.restDir = p.botRest - p.topRest; p.restLen = Mathf.Max(0.01f, p.restDir.magnitude); p.restDir /= p.restLen;
                    p.localAxis = (Quaternion.Inverse(p.restRot) * p.restDir);
                    p.wheelA = side >= 0 ? ax * 2 + side : ax * 2; p.wheelB = side >= 0 ? -1 : ax * 2 + 1;
                    parts.Add(p);
                }
                else if (n.StartsWith("Leaf_"))
                {
                    if (!ParseAxleSide(n, axleCount, out int ax, out int side)) continue;
                    var p = Base(t, Kind.Follow); p.wheelA = side >= 0 ? ax * 2 + side : ax * 2; p.wheelB = side >= 0 ? -1 : ax * 2 + 1;
                    parts.Add(p);
                }
            }
        }

        Part Base(Transform t, Kind k)
        {
            var root = transform;
            return new Part { t = t, kind = k, restPos = root.InverseTransformPoint(t.position), restRot = Quaternion.Inverse(root.rotation) * t.rotation, restScale = t.localScale };
        }

        static Vector3 HubRest(Vehicle v, int w) { var wh = v.wheels[w]; return wh.anchorLocal - Vector3.up * wh.restLength; }

        float Disp(int w) { var wh = vehicle.wheels[w]; return wh.restLength - wh.visualLength; }   // + = hub moved up (compressed)

        void LateUpdate()
        {
            if (vehicle == null || vehicle.wheels == null) return;
            var root = transform;
            foreach (var p in parts)
            {
                if (p.t == null) continue;
                float dA = Disp(p.wheelA), dB = p.wheelB >= 0 ? Disp(p.wheelB) : dA;
                float d = p.wheelB >= 0 ? 0.5f * (dA + dB) : dA;
                switch (p.kind)
                {
                    case Kind.Axle:
                        {
                            Vector3 l = p.leftRest + Vector3.up * dA, r = p.rightRest + Vector3.up * dB;
                            Quaternion roll = Quaternion.FromToRotation(p.rightRest - p.leftRest, r - l);
                            Vector3 mid = 0.5f * (l + r) - 0.5f * (p.leftRest + p.rightRest);
                            Place(p.t, p.restPos + mid, roll * p.restRot, p.restScale);
                            break;
                        }
                    case Kind.Follow:
                        Place(p.t, p.restPos + Vector3.up * d, p.restRot, p.restScale);
                        break;
                    case Kind.Spring:
                    case Kind.Link:
                        {
                            Vector3 bot = p.botRest + Vector3.up * d; Vector3 dir = bot - p.topRest; float len = Mathf.Max(0.01f, dir.magnitude);
                            Quaternion rot = Quaternion.FromToRotation(p.restDir, dir / len) * p.restRot;
                            float ratio = p.kind == Kind.Spring ? len / p.restLen : Mathf.Lerp(1f, len / p.restLen, 0.5f);
                            Vector3 a = new Vector3(Mathf.Abs(p.localAxis.x), Mathf.Abs(p.localAxis.y), Mathf.Abs(p.localAxis.z));
                            Vector3 sc = new Vector3(p.restScale.x * (1f + a.x * (ratio - 1f)), p.restScale.y * (1f + a.y * (ratio - 1f)), p.restScale.z * (1f + a.z * (ratio - 1f)));
                            Place(p.t, p.topRest + (p.restPos - p.topRest), rot, sc);
                            break;
                        }
                    case Kind.ShockBody:
                        {
                            Vector3 bot = p.botRest + Vector3.up * d; Vector3 dir = (bot - p.topRest).normalized;
                            Place(p.t, p.restPos, Quaternion.FromToRotation(p.restDir, dir) * p.restRot, p.restScale);
                            break;
                        }
                    case Kind.ShockRod:
                        {
                            Vector3 bot = p.botRest + Vector3.up * d; Vector3 dir = (bot - p.topRest).normalized;
                            Place(p.t, p.restPos + Vector3.up * d, Quaternion.FromToRotation(p.restDir, dir) * p.restRot, p.restScale);
                            break;
                        }
                }
            }
        }

        void Place(Transform t, Vector3 rootLocalPos, Quaternion rootLocalRot, Vector3 scale)
        {
            var root = transform;
            t.position = root.TransformPoint(rootLocalPos);
            t.rotation = root.rotation * rootLocalRot;
            t.localScale = scale;
        }
    }

    /// <summary>Head/tail/brake/reverse lights of a vehicle. Headlight spot lights are created at the Light_Head_* meshes; lenses glow through emission.</summary>
    public sealed class VehicleLights : MonoBehaviour
    {
        public Vehicle vehicle;
        public bool headlights;
        readonly List<Light> spots = new List<Light>();
        readonly List<Renderer> head = new List<Renderer>(), tail = new List<Renderer>();
        MaterialPropertyBlock mpb;
        static readonly int EmissionId = Shader.PropertyToID("_EmissionColor");

        public void Setup(Vehicle v)
        {
            vehicle = v; mpb = new MaterialPropertyBlock();
            foreach (var r in GetComponentsInChildren<Renderer>(true))
            {
                string n = ModelNames.Norm(r.name);
                if (n.StartsWith("Light_Head") || n.StartsWith("Light_Work")) { head.Add(r); AddSpot(r.transform, n.StartsWith("Light_Work") ? 55f : 45f, n.StartsWith("Light_Work") ? 60f : 95f); }
                else if (n.StartsWith("Light_Tail") || n.StartsWith("Light_Brake") || n.StartsWith("Light_Reverse")) tail.Add(r);
            }
        }

        void AddSpot(Transform at, float range, float angle)
        {
            var go = new GameObject("HeadSpot"); go.transform.SetParent(at, false);
            go.transform.localPosition = Vector3.zero;
            go.transform.rotation = vehicle.transform.rotation * Quaternion.Euler(4f, 0f, 0f);
            var l = go.AddComponent<Light>(); l.type = LightType.Spot; l.range = range; l.spotAngle = angle; l.innerSpotAngle = angle * 0.6f;
            l.intensity = 120f; l.color = new Color(1f, 0.95f, 0.82f); l.shadows = LightShadows.None; l.enabled = false;
            spots.Add(l);
        }

        public void SetHeadlights(bool on) { headlights = on; foreach (var l in spots) l.enabled = on; }
        public void Toggle() { SetHeadlights(!headlights); }

        void Update()
        {
            if (vehicle == null) return;
            var gm = GameManager.Instance;
            if (gm != null && gm.Player == vehicle && gm.PlayerInput != null && gm.PlayerInput.pressedHeadlights) Toggle();
            float brake = vehicle.brakeEff > 0.05f || vehicle.input.handbrake ? 1f : 0f;
            bool reverse = vehicle.drivetrain != null && vehicle.drivetrain.gear < 0;
            Glow(head, headlights ? 2.2f : 0f, new Color(1f, 0.95f, 0.75f));
            Glow(tail, (headlights ? 0.35f : 0f) + brake * 1.8f + (reverse ? 0.2f : 0f), new Color(1f, 0.05f, 0.03f));
        }

        void Glow(List<Renderer> list, float intensity, Color c)
        {
            if (list.Count == 0) return;
            mpb.SetColor(EmissionId, c * intensity);
            foreach (var r in list) if (r != null) r.SetPropertyBlock(mpb);
        }
    }
}
