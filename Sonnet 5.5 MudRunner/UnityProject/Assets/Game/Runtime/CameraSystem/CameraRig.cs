using System;
using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.UI;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.InputSystem;

namespace MudRunner.CameraSystem
{
    public enum CameraMode { Chase = 0, Cockpit = 1, Wheel = 2, Top = 3, Free = 4, Showcase = 5 }

    /// <summary>
    /// The game camera. Replaces SimpleChaseCamera. Modes (C cycles Chase, Cockpit, Wheel close-up, Top): smooth 0.4 s blends between them,
    /// heavy-vehicle damping with look-ahead, mouse orbit (auto re-centres after 2 s), terrain + prop collision, speed based FOV,
    /// subtle impact shake. Free is entered from the debug menu, Showcase is the slow turntable used behind the menus.
    /// </summary>
    [DefaultExecutionOrder(100)]
    [RequireComponent(typeof(Camera))]
    public sealed class CameraRig : MonoBehaviour
    {
        public static CameraRig Instance { get; private set; }
        public Camera Cam { get; private set; }

        [Header("General")]
        public float blendTime = 0.4f;
        public float mouseSensitivity = 0.11f;      // degrees per pixel
        public float gamepadLookSpeed = 150f;       // degrees per second at full deflection
        public bool shakeEnabled = true;
        [Header("Chase")]
        public float chaseMinDistance = 4f, chaseMaxDistance = 20f;
        public float recenterDelay = 2f;
        public Vector2 chaseFov = new Vector2(60f, 72f);

        public CameraMode Mode { get; private set; } = CameraMode.Chase;
        public CameraMode ReturnMode { get; private set; } = CameraMode.Chase;
        public int SelectedWheel { get; private set; }
        public Vehicle Target => veh;
        public bool IsBlending => blendT < 1f;
        public float Fov => Cam != null ? Cam.fieldOfView : 0f;
        public event Action<CameraMode> ModeChanged;

        static readonly CameraMode[] CycleOrder = { CameraMode.Chase, CameraMode.Cockpit, CameraMode.Wheel, CameraMode.Top };

        struct Pose { public Vector3 pos; public Quaternion rot; public float fov; }

        Vehicle veh;
        Pose from, cur;
        float blendT = 1f;
        float trauma;
        Vector3 prevVel; bool hasPrevVel;

        // ---- chase state
        float chaseYaw, chaseYawVel, orbitYaw, orbitYawVel, orbitPitch, orbitPitchVel, idleTimer;
        float zoom = 9f, zoomTarget = 9f, zoomVel;
        Vector3 pivot, pivotVel; float pivotY, pivotYVel;
        float curLen = 9f;
        float fovSm, fovVel;

        // ---- cockpit state
        float cockYaw, cockPitch, cockIdle;
        Vector3 bob, bobVel;
        Transform eyeTf; Vehicle eyeFor;

        // ---- wheel state
        float wheelYaw, wheelPitch, wheelDistScale = 1f, wheelIdle;
        Vector3 wheelPos, wheelPosVel, wheelLook, wheelLookVel;

        // ---- top state
        float topHeight = 38f, topYaw, topYawVel, topOrbitYaw, topIdle;
        Vector3 topPivot, topPivotVel;

        // ---- free state
        Vector3 freePos; float freeYaw, freePitch, freeSpeed = 14f;

        // ---- showcase
        float showAngle = 28f;
        public float showcaseShift = 0.20f;

        // ------------------------------------------------------------------ lifecycle

        void Awake()
        {
            Instance = this;
            Cam = GetComponent<Camera>();
        }

        void OnDestroy() { if (Instance == this) Instance = null; }

        void OnEnable()
        {
            var sc = GetComponent<SimpleChaseCamera>();
            if (sc != null) sc.enabled = false;
        }

        // ------------------------------------------------------------------ public API

        public void SetMode(CameraMode m, bool instant = false)
        {
            if (m == Mode && !instant) return;
            var prev = Mode;
            if (m == CameraMode.Free && prev != CameraMode.Free) ReturnMode = prev == CameraMode.Showcase ? CameraMode.Chase : prev;
            from = new Pose { pos = transform.position, rot = transform.rotation, fov = Cam.fieldOfView };
            Mode = m;
            blendT = instant ? 1f : 0f;
            EnterMode(m, prev);
            UiState.FreeCamera = m == CameraMode.Free;
            ModeChanged?.Invoke(m);
        }

        public void CycleMode()
        {
            if (Mode == CameraMode.Free || Mode == CameraMode.Showcase) { SetMode(ReturnMode == CameraMode.Free || ReturnMode == CameraMode.Showcase ? CameraMode.Chase : ReturnMode); return; }
            int i = Array.IndexOf(CycleOrder, Mode);
            SetMode(CycleOrder[(i + 1) % CycleOrder.Length]);
        }

        public void ExitFree() { if (Mode == CameraMode.Free) SetMode(ReturnMode == CameraMode.Free ? CameraMode.Chase : ReturnMode); }

        public void SelectWheel(int delta)
        {
            if (veh == null || veh.wheels == null || veh.wheels.Length == 0) return;
            int n = veh.wheels.Length;
            SelectedWheel = ((SelectedWheel + delta) % n + n) % n;
            wheelIdle = 0f;
        }

        public void SetWheel(int index)
        {
            if (veh == null || veh.wheels == null || veh.wheels.Length == 0) return;
            SelectedWheel = Mathf.Clamp(index, 0, veh.wheels.Length - 1);
        }

        /// <summary>Adds screen shake (0..1).</summary>
        public void AddTrauma(float amount) { trauma = Mathf.Clamp01(trauma + amount); }

        /// <summary>Jump straight to the current mode's target pose (after teleports / spawns).</summary>
        public void Snap() { if (veh != null) EnterMode(Mode, Mode); blendT = 1f; }

        public void SetZoom(float meters) { zoomTarget = Mathf.Clamp(meters, chaseMinDistance, chaseMaxDistance); }
        public float ChaseDistance => zoomTarget;

        // ------------------------------------------------------------------ vehicle tracking

        void TrackVehicle()
        {
            var gm = GameManager.Instance;
            var p = gm != null ? gm.Player : null;
            if (p == veh) return;
            veh = p;
            if (veh == null) return;
            zoomTarget = zoom = curLen = Mathf.Clamp(5.5f + veh.def.bodySize.z * 0.85f, chaseMinDistance + 1f, chaseMaxDistance);
            SelectedWheel = Mathf.Clamp(SelectedWheel, 0, Mathf.Max(0, veh.wheels.Length - 1));
            eyeFor = null; hasPrevVel = false;
            EnterMode(Mode, Mode);
            blendT = 1f;
        }

        void EnterMode(CameraMode m, CameraMode prev)
        {
            if (veh == null) { if (m == CameraMode.Free) InitFree(); return; }
            switch (m)
            {
                case CameraMode.Chase:
                    chaseYaw = veh.transform.eulerAngles.y; chaseYawVel = 0f; orbitYaw = orbitPitch = 0f; idleTimer = 0f;
                    pivot = ChasePivotTarget(); pivotVel = Vector3.zero; pivotY = pivot.y; pivotYVel = 0f; curLen = zoom;
                    fovSm = chaseFov.x; fovVel = 0f;
                    break;
                case CameraMode.Cockpit:
                    cockYaw = cockPitch = 0f; cockIdle = 0f; bob = bobVel = Vector3.zero;
                    break;
                case CameraMode.Wheel:
                    wheelYaw = wheelPitch = 0f; wheelIdle = 0f; wheelDistScale = 1f;
                    wheelPos = WheelTarget(out wheelLook); wheelPosVel = wheelLookVel = Vector3.zero;
                    break;
                case CameraMode.Top:
                    topYaw = veh.transform.eulerAngles.y; topYawVel = 0f; topOrbitYaw = 0f; topIdle = 0f;
                    topPivot = veh.transform.position; topPivotVel = Vector3.zero;
                    break;
                case CameraMode.Free:
                    InitFree();
                    break;
                case CameraMode.Showcase:
                    showAngle = veh.transform.eulerAngles.y + 148f;
                    break;
            }
        }

        void InitFree()
        {
            freePos = transform.position;
            var e = transform.rotation.eulerAngles;
            freeYaw = e.y; freePitch = e.x > 180f ? e.x - 360f : e.x;
        }

        // ------------------------------------------------------------------ frame

        void LateUpdate()
        {
            if (Cam == null) return;
            TrackVehicle();
            float dt = Time.deltaTime, rdt = Mathf.Min(Time.unscaledDeltaTime, 0.1f);
            HandleKeys();

            if (veh == null && Mode != CameraMode.Free) return;

            Pose to = cur;
            switch (Mode)
            {
                case CameraMode.Chase: to = UpdateChase(dt, rdt); break;
                case CameraMode.Cockpit: to = UpdateCockpit(dt, rdt); break;
                case CameraMode.Wheel: to = UpdateWheel(dt, rdt); break;
                case CameraMode.Top: to = UpdateTop(dt, rdt); break;
                case CameraMode.Free: to = UpdateFree(rdt); break;
                case CameraMode.Showcase: to = UpdateShowcase(rdt); break;
            }

            Pose p = to;
            if (blendT < 1f)
            {
                blendT = Mathf.Min(1f, blendT + rdt / Mathf.Max(0.01f, blendTime));
                float t = blendT * blendT * (3f - 2f * blendT);
                p.pos = Vector3.Lerp(from.pos, to.pos, t);
                p.rot = Quaternion.Slerp(from.rot, to.rot, t);
                p.fov = Mathf.Lerp(from.fov, to.fov, t);
            }
            cur = p;

            // impact shake
            Vector3 off = Vector3.zero; float roll = 0f;
            if (veh != null && veh.rb != null && Time.deltaTime > 0f)
            {
                Vector3 vel = veh.rb.linearVelocity;
                if (hasPrevVel && shakeEnabled)
                {
                    float a = (vel - prevVel).magnitude / Time.deltaTime;
                    if (a > 32f) trauma = Mathf.Min(0.55f, trauma + (a - 32f) / 160f);
                }
                prevVel = vel; hasPrevVel = true;
            }
            if (trauma > 0.001f)
            {
                trauma = Mathf.MoveTowards(trauma, 0f, 1.4f * rdt);
                float s = trauma * trauma, tm = Time.unscaledTime;
                off = new Vector3(Mathf.PerlinNoise(tm * 24f, 0.3f) - 0.5f, Mathf.PerlinNoise(0.7f, tm * 24f) - 0.5f, 0f) * (0.28f * s);
                roll = (Mathf.PerlinNoise(tm * 20f, 5.1f) - 0.5f) * 5f * s;
                off = p.rot * off;
            }
            transform.SetPositionAndRotation(p.pos + off, p.rot * Quaternion.Euler(0f, 0f, roll));
            Cam.fieldOfView = p.fov;
            float near = Mode == CameraMode.Cockpit || Mode == CameraMode.Wheel ? 0.12f : Mode == CameraMode.Top ? 0.5f : 0.25f;
            if (Mathf.Abs(Cam.nearClipPlane - near) > 0.001f) Cam.nearClipPlane = near;
        }

        // ------------------------------------------------------------------ input

        bool InputAllowed => !UiState.ModalOpen && !UiState.TextFieldFocus;

        void HandleKeys()
        {
            if (!InputAllowed) return;
            var kb = Keyboard.current; var pad = Gamepad.current;
            bool cycle = (kb != null && kb.cKey.wasPressedThisFrame) || (pad != null && pad.dpad.up.wasPressedThisFrame);
            if (cycle) CycleMode();
            if (kb != null)
            {
                if (kb.rightBracketKey.wasPressedThisFrame || kb.pageDownKey.wasPressedThisFrame) SelectWheel(+1);
                if (kb.leftBracketKey.wasPressedThisFrame || kb.pageUpKey.wasPressedThisFrame) SelectWheel(-1);
            }
        }

        Vector2 ReadLook(float rdt)
        {
            if (!InputAllowed || UiState.MapOpen) return Vector2.zero;
            Vector2 d = Vector2.zero;
            var m = Mouse.current;
            if (m != null && (!UiState.CursorFree || m.rightButton.isPressed))
                d += m.delta.ReadValue() * mouseSensitivity;
            var pad = Gamepad.current;
            if (pad != null) { Vector2 s = pad.rightStick.ReadValue(); if (s.sqrMagnitude > 0.04f) d += new Vector2(s.x, s.y) * gamepadLookSpeed * rdt; }
            return d;
        }

        float ReadScroll()
        {
            if (!InputAllowed || UiState.MapOpen || UiState.DebugOpen && UiState.CursorFree && !RightHeld()) return 0f;
            var m = Mouse.current; if (m == null) return 0f;
            float s = m.scroll.ReadValue().y;
            if (Mathf.Abs(s) > 5f) s /= 120f;
            return s;
        }

        static bool RightHeld() { var m = Mouse.current; return m != null && m.rightButton.isPressed; }

        // ------------------------------------------------------------------ chase

        Vector3 ChasePivotTarget()
        {
            var def = veh.def;
            Vector3 vp = veh.transform.position;
            Vector3 vel = veh.rb != null ? veh.rb.linearVelocity : Vector3.zero;
            Vector3 ahead = Vector3.ClampMagnitude(new Vector3(vel.x, 0f, vel.z) * 0.22f, 3.0f);
            float roof = def.bodyCenter.y + def.bodySize.y * 0.5f;
            return new Vector3(vp.x + ahead.x, vp.y + roof * 0.62f, vp.z + ahead.z);
        }

        Pose UpdateChase(float dt, float rdt)
        {
            var def = veh.def;
            float massF = Mathf.InverseLerp(2000f, 9000f, def.mass);
            Vector3 vel = veh.rb != null ? veh.rb.linearVelocity : Vector3.zero;
            float speed = new Vector2(vel.x, vel.z).magnitude;

            // ---- pivot (damped, vertical axis damped harder so bumps do not bounce the view)
            Vector3 tgt = ChasePivotTarget();
            if ((tgt - pivot).sqrMagnitude > 1600f) { EnterMode(CameraMode.Chase, CameraMode.Chase); blendT = 1f; tgt = pivot; }
            float st = Mathf.Lerp(0.05f, 0.16f, massF);
            Vector3 hp = Vector3.SmoothDamp(new Vector3(pivot.x, 0f, pivot.z), new Vector3(tgt.x, 0f, tgt.z), ref pivotVel, st, Mathf.Infinity, dt);
            pivotY = Mathf.SmoothDamp(pivotY, tgt.y, ref pivotYVel, st * 2.8f + 0.06f, Mathf.Infinity, dt);
            pivot = new Vector3(hp.x, pivotY, hp.z);

            // ---- heading: vehicle yaw, blended toward the velocity direction when driving forward fast
            float headYaw = veh.transform.eulerAngles.y;
            if (speed > 2.5f && veh.forwardSpeed > 0.5f)
            {
                float velYaw = Mathf.Atan2(vel.x, vel.z) * Mathf.Rad2Deg;
                float k = Mathf.SmoothStep(0f, 1f, (speed - 2.5f) / 6f) * 0.55f;
                headYaw += Mathf.DeltaAngle(headYaw, velYaw) * k;
            }
            chaseYaw = Mathf.SmoothDampAngle(chaseYaw, headYaw, ref chaseYawVel, Mathf.Lerp(0.26f, 0.55f, massF), Mathf.Infinity, dt);

            // ---- orbit input + auto recentre
            Vector2 look = ReadLook(rdt);
            if (look.sqrMagnitude > 0.0004f)
            {
                orbitYaw += look.x; orbitPitch = Mathf.Clamp(orbitPitch - look.y, -22f, 50f); idleTimer = 0f;
                orbitYawVel = orbitPitchVel = 0f;
            }
            else idleTimer += rdt;
            if (idleTimer > recenterDelay)
            {
                orbitYaw = Mathf.SmoothDampAngle(orbitYaw, 0f, ref orbitYawVel, 0.65f, Mathf.Infinity, rdt);
                orbitPitch = Mathf.SmoothDamp(orbitPitch, 0f, ref orbitPitchVel, 0.65f, Mathf.Infinity, rdt);
            }
            orbitYaw = Mathf.DeltaAngle(0f, orbitYaw);

            // ---- zoom
            float scroll = ReadScroll();
            if (Mathf.Abs(scroll) > 0.01f) zoomTarget = Mathf.Clamp(zoomTarget * Mathf.Pow(0.88f, scroll), chaseMinDistance, chaseMaxDistance);
            zoom = Mathf.SmoothDamp(zoom, zoomTarget, ref zoomVel, 0.12f, Mathf.Infinity, rdt);

            float basePitch = Mathf.Lerp(10f, 21f, Mathf.InverseLerp(4f, 20f, zoom)) + 0.8f * Mathf.Clamp(def.bodySize.y - 1f, 0f, 1f) * 4f;
            float pitch = Mathf.Clamp(basePitch + orbitPitch, -4f, 78f);
            Quaternion orbit = Quaternion.Euler(pitch, chaseYaw + orbitYaw, 0f);
            Vector3 dir = orbit * Vector3.back;

            // ---- collision (props via sphere cast, terrain via the ground service height)
            float want = zoom, hitLen = want;
            if (Physics.SphereCast(pivot, 0.32f, dir, out RaycastHit hit, want, GameLayers.CameraMask, QueryTriggerInteraction.Ignore))
                hitLen = Mathf.Max(1.6f, hit.distance - 0.12f);
            curLen = hitLen < curLen ? hitLen : Mathf.MoveTowards(curLen, hitLen, 16f * rdt);
            Vector3 pos = pivot + dir * curLen;
            var gs = GroundService.Instance;
            if (gs != null && gs.Map != null)
            {
                float gh = gs.SurfaceHeight(pos.x, pos.z) + 0.6f;
                if (pos.y < gh) pos.y = gh;
            }
            Vector3 lookAt = pivot + Vector3.up * (zoom * 0.075f);
            Quaternion rot = Quaternion.LookRotation(lookAt - pos, Vector3.up);

            float fovT = Mathf.Lerp(chaseFov.x, chaseFov.y, Mathf.SmoothStep(0f, 1f, speed / 26f));
            fovSm = Mathf.SmoothDamp(fovSm, fovT, ref fovVel, 0.35f, Mathf.Infinity, rdt);
            return new Pose { pos = pos, rot = rot, fov = fovSm };
        }

        // ------------------------------------------------------------------ cockpit

        static Transform FindDeep(Transform root, string name)
        {
            var q = new Queue<Transform>(); q.Enqueue(root);
            while (q.Count > 0)
            {
                var t = q.Dequeue();
                if (t.name == name) return t;
                for (int i = 0; i < t.childCount; i++) q.Enqueue(t.GetChild(i));
            }
            return null;
        }

        Vector3 EyeLocal()
        {
            var d = veh.def;
            float top = d.bodyCenter.y + d.bodySize.y * 0.5f;
            return new Vector3(-Mathf.Min(0.42f, d.bodySize.x * 0.2f), top - 0.28f, d.bodyCenter.z + d.bodySize.z * 0.12f);
        }

        Pose UpdateCockpit(float dt, float rdt)
        {
            if (eyeFor != veh) { eyeFor = veh; eyeTf = FindDeep(veh.transform, "Cam_Cockpit"); }
            Transform t = veh.transform;
            Vector3 eye = eyeTf != null ? eyeTf.position : t.TransformPoint(EyeLocal());
            Quaternion baseRot = eyeTf != null ? eyeTf.rotation : t.rotation;

            // head bob: suspension travel + body acceleration pushing the head around (damped spring)
            float comp = 0f; int n = 0;
            foreach (var w in veh.wheels) { if (w.grounded) { comp += (w.restLength - w.length); n++; } }
            if (n > 0) comp /= n;
            Vector3 acc = Vector3.zero;
            if (veh.rb != null && hasPrevVel && Time.deltaTime > 0f) acc = (veh.rb.linearVelocity - prevVel) / Time.deltaTime;
            Vector3 la = t.InverseTransformDirection(acc);
            Vector3 bobT = new Vector3(Mathf.Clamp(-la.x * 0.006f, -0.07f, 0.07f), Mathf.Clamp(-la.y * 0.004f + comp * 0.5f, -0.09f, 0.09f), Mathf.Clamp(-la.z * 0.004f, -0.06f, 0.06f));
            bob = Vector3.SmoothDamp(bob, bobT, ref bobVel, 0.08f, Mathf.Infinity, dt > 0f ? dt : 0.0001f);
            eye += t.TransformDirection(bob);

            Vector2 look = ReadLook(rdt);
            if (look.sqrMagnitude > 0.0004f)
            {
                cockYaw = Mathf.Clamp(cockYaw + look.x, -125f, 125f); cockPitch = Mathf.Clamp(cockPitch - look.y, -50f, 55f); cockIdle = 0f;
            }
            else cockIdle += rdt;
            if (cockIdle > 2.5f) { float k = 1f - Mathf.Exp(-2.2f * rdt); cockYaw = Mathf.Lerp(cockYaw, 0f, k); cockPitch = Mathf.Lerp(cockPitch, 0f, k); }

            float speed = veh.speed;
            float fov = Mathf.Lerp(66f, 75f, Mathf.SmoothStep(0f, 1f, speed / 26f));
            return new Pose { pos = eye, rot = baseRot * Quaternion.Euler(cockPitch, cockYaw, 0f), fov = fov };
        }

        // ------------------------------------------------------------------ wheel close-up

        Vector3 WheelTarget(out Vector3 lookPoint)
        {
            var w = veh.wheels[Mathf.Clamp(SelectedWheel, 0, veh.wheels.Length - 1)];
            Transform t = veh.transform;
            Vector3 hubRest = t.TransformPoint(w.anchorLocal) - t.up * w.restLength;
            float side = w.isLeft ? -1f : 1f;
            float dist = (w.tire.radius * 3.2f + 0.9f) * wheelDistScale;
            // default view: from outside, slightly ahead of the wheel and above, so tyre sidewall, hub and spring are all visible
            Vector3 local = new Vector3(side * 0.88f, 0.34f, 0.40f).normalized;
            Quaternion adj = Quaternion.Euler(wheelPitch, wheelYaw, 0f);
            local = adj * local;
            Vector3 pos = hubRest + t.rotation * (local * dist);
            // look between hub and axle centre so the axle / suspension articulation stays in frame
            lookPoint = w.hubWorld + t.right * (-side * Mathf.Min(0.55f, w.axle.track * 0.18f)) + t.up * 0.05f;
            return pos;
        }

        Pose UpdateWheel(float dt, float rdt)
        {
            Vector3 tgtLook;
            Vector3 tgt = WheelTarget(out tgtLook);
            float dts = dt > 0f ? dt : 0.0001f;
            wheelPos = Vector3.SmoothDamp(wheelPos, tgt, ref wheelPosVel, 0.07f, Mathf.Infinity, dts);
            wheelLook = Vector3.SmoothDamp(wheelLook, tgtLook, ref wheelLookVel, 0.05f, Mathf.Infinity, dts);
            Vector2 look = ReadLook(rdt);
            if (look.sqrMagnitude > 0.0004f)
            {
                wheelYaw += look.x; wheelPitch = Mathf.Clamp(wheelPitch - look.y, -35f, 60f); wheelIdle = 0f;
            }
            else wheelIdle += rdt;
            if (wheelIdle > 3.5f) { float k = 1f - Mathf.Exp(-1.6f * rdt); wheelYaw = Mathf.LerpAngle(wheelYaw, 0f, k); wheelPitch = Mathf.Lerp(wheelPitch, 0f, k); }
            float scroll = ReadScroll();
            if (Mathf.Abs(scroll) > 0.01f) wheelDistScale = Mathf.Clamp(wheelDistScale * Mathf.Pow(0.88f, scroll), 0.65f, 1.7f);

            Vector3 pos = wheelPos;
            var gs = GroundService.Instance;
            if (gs != null && gs.Map != null)
            {
                float gh = gs.SurfaceHeight(pos.x, pos.z) + 0.18f;
                if (pos.y < gh) pos.y = gh;
            }
            return new Pose { pos = pos, rot = Quaternion.LookRotation(wheelLook - pos, Vector3.up), fov = 52f };
        }

        // ------------------------------------------------------------------ top / far

        Pose UpdateTop(float dt, float rdt)
        {
            float dts = dt > 0f ? dt : 0.0001f;
            Vector3 tgt = veh.transform.position + Vector3.up * 1f;
            if ((tgt - topPivot).sqrMagnitude > 2500f) topPivot = tgt;
            topPivot = Vector3.SmoothDamp(topPivot, tgt, ref topPivotVel, 0.2f, Mathf.Infinity, dts);
            float headYaw = veh.transform.eulerAngles.y;
            topYaw = Mathf.SmoothDampAngle(topYaw, headYaw, ref topYawVel, 0.8f, Mathf.Infinity, dts);
            Vector2 look = ReadLook(rdt);
            if (look.sqrMagnitude > 0.0004f) { topOrbitYaw += look.x; topIdle = 0f; }
            else topIdle += rdt;
            if (topIdle > 4f) topOrbitYaw = Mathf.LerpAngle(topOrbitYaw, 0f, 1f - Mathf.Exp(-1.5f * rdt));
            float scroll = ReadScroll();
            if (Mathf.Abs(scroll) > 0.01f) topHeight = Mathf.Clamp(topHeight * Mathf.Pow(0.88f, scroll), 14f, 160f);
            float pitch = 66f;
            Quaternion rot = Quaternion.Euler(pitch, topYaw + topOrbitYaw, 0f);
            Vector3 pos = topPivot + rot * Vector3.back * (topHeight / Mathf.Sin(pitch * Mathf.Deg2Rad));
            var gs = GroundService.Instance;
            if (gs != null && gs.Map != null) { float gh = gs.SurfaceHeight(pos.x, pos.z) + 3f; if (pos.y < gh) pos.y = gh; }
            return new Pose { pos = pos, rot = Quaternion.LookRotation(topPivot - pos, Vector3.up), fov = 56f };
        }

        // ------------------------------------------------------------------ free camera

        Pose UpdateFree(float rdt)
        {
            Vector2 look = ReadLook(rdt);
            freeYaw += look.x; freePitch = Mathf.Clamp(freePitch - look.y, -89f, 89f);
            Quaternion rot = Quaternion.Euler(freePitch, freeYaw, 0f);
            Vector3 move = Vector3.zero;
            var kb = Keyboard.current;
            if (kb != null && !UiState.TextFieldFocus && !UiState.ModalOpen)
            {
                if (kb.wKey.isPressed) move += Vector3.forward;
                if (kb.sKey.isPressed) move += Vector3.back;
                if (kb.dKey.isPressed) move += Vector3.right;
                if (kb.aKey.isPressed) move += Vector3.left;
                if (kb.eKey.isPressed) move += Vector3.up;
                if (kb.qKey.isPressed) move += Vector3.down;
                float mult = kb.leftShiftKey.isPressed ? 4f : kb.leftCtrlKey.isPressed ? 0.25f : 1f;
                freePos += rot * move.normalized * (move.sqrMagnitude > 0f ? freeSpeed * mult * rdt : 0f);
            }
            float scroll = ReadScroll();
            if (Mathf.Abs(scroll) > 0.01f) freeSpeed = Mathf.Clamp(freeSpeed * Mathf.Pow(1.2f, scroll), 1f, 200f);
            return new Pose { pos = freePos, rot = rot, fov = 62f };
        }

        // ------------------------------------------------------------------ showcase (behind menus)

        Pose UpdateShowcase(float rdt)
        {
            showAngle += 9f * rdt;
            Vector3 c = veh.transform.position + Vector3.up * (veh.def.bodyCenter.y * 0.75f);
            float len = veh.def.bodySize.z;
            float radius = len * 1.35f + 3.2f;
            float h = 0.9f + veh.def.bodySize.y * 0.45f + Mathf.Sin(Time.unscaledTime * 0.25f) * 0.35f;
            Vector3 pos = c + Quaternion.Euler(0f, showAngle, 0f) * new Vector3(0f, h, -radius);
            var gs = GroundService.Instance;
            if (gs != null && gs.Map != null) { float gh = gs.SurfaceHeight(pos.x, pos.z) + 0.5f; if (pos.y < gh) pos.y = gh; }
            Quaternion look0 = Quaternion.LookRotation(c - pos, Vector3.up);
            // subject sits right of centre so the menu can use the left side
            Vector3 right = look0 * Vector3.right;
            Quaternion rot = Quaternion.LookRotation((c - right * (radius * showcaseShift)) - pos, Vector3.up);
            return new Pose { pos = pos, rot = rot, fov = 42f };
        }
    }
}
