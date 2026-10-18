using System.Collections.Generic;
using System.Text;
using MudRunner.Ground;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>World to canvas projection with near-plane clipping, shared by the physics overlay and the gizmo layer.</summary>
    public sealed class ScreenSpace
    {
        public Camera cam; public float scale = 1f;
        Vector3 pos, fwd; float near = 0.15f;

        public void Begin(Camera c, float canvasScale) { cam = c; scale = Mathf.Max(0.01f, canvasScale); pos = c.transform.position; fwd = c.transform.forward; }

        public bool Point(Vector3 w, out Vector2 canvas)
        {
            canvas = default;
            if (Vector3.Dot(w - pos, fwd) < near) return false;
            Vector3 s = cam.WorldToScreenPoint(w);
            canvas = new Vector2(s.x, s.y) / scale;
            return true;
        }

        public bool Line(Vector3 a, Vector3 b, out Vector2 ca, out Vector2 cb)
        {
            ca = cb = default;
            float da = Vector3.Dot(a - pos, fwd) - near, db = Vector3.Dot(b - pos, fwd) - near;
            if (da < 0f && db < 0f) return false;
            if (da < 0f) a = Vector3.Lerp(a, b, da / (da - db));
            else if (db < 0f) b = Vector3.Lerp(a, b, da / (da - db));
            Vector3 sa = cam.WorldToScreenPoint(a), sb = cam.WorldToScreenPoint(b);
            ca = new Vector2(sa.x, sa.y) / scale; cb = new Vector2(sb.x, sb.y) / scale;
            return true;
        }
    }

    /// <summary>
    /// F2 physics overlay: a data card anchored next to every wheel (load, sinkage, slip, surface, traction usage), a compact table
    /// on the right and the engine / driveline numbers.
    /// </summary>
    public sealed class HudPhysicsOverlay : HudWidget
    {
        sealed class Card
        {
            public RectTransform rt; public Image chip, usage, usageTrack; public Text head, surface, load, sink, slip, usageLabel; public Vector2 pos; public bool init;
        }

        readonly List<Card> cards = new List<Card>();
        UiLines leaders;
        RectTransform cardRoot, table;
        Text tableHead, tableRows, engineText;
        readonly ScreenSpace ss = new ScreenSpace();
        readonly StringBuilder sb = new StringBuilder(512);
        float nextTable;
        const float CW = 188f, CH = 108f;

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("PhysicsOverlay", parent);
            UiFactory.Fill(root);
            var lr = UiFactory.NewRect("Leaders", root);
            lr.anchorMin = lr.anchorMax = Vector2.zero; lr.pivot = Vector2.zero; lr.anchoredPosition = Vector2.zero; lr.sizeDelta = new Vector2(1920, 1080);
            leaders = lr.gameObject.AddComponent<UiLines>(); leaders.raycastTarget = false;
            cardRoot = UiFactory.NewRect("Cards", root);
            cardRoot.anchorMin = cardRoot.anchorMax = Vector2.zero; cardRoot.pivot = Vector2.zero; cardRoot.sizeDelta = Vector2.zero;

            var p = UiFactory.Panel(root, "Table", UiTheme.BgDeep, 12, true, true);
            table = p.rt;
            UiFactory.Place(table, UiFactory.MR, new Vector2(-UiTheme.Margin, 90), new Vector2(520, 470), UiFactory.MR);
            var t = UiFactory.Label(table, "PHYSICS", 15, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(t.rectTransform, UiFactory.TL, new Vector2(14, -16), new Vector2(200, 20));
            var hint = UiFactory.Label(table, "F2 close", 12, UiTheme.TextFaint, TextAnchor.MiddleRight, UiFont.Body);
            UiFactory.Place(hint.rectTransform, UiFactory.TR, new Vector2(-14, -16), new Vector2(120, 16));
            tableHead = UiFactory.Label(table, "", 13, UiTheme.TextDim, TextAnchor.UpperLeft, UiFont.Mono);
            UiFactory.Place(tableHead.rectTransform, UiFactory.TL, new Vector2(14, -42), new Vector2(500, 20));
            tableRows = UiFactory.Label(table, "", 14, UiTheme.Text, TextAnchor.UpperLeft, UiFont.Mono);
            tableRows.lineSpacing = 1.12f;
            UiFactory.Place(tableRows.rectTransform, UiFactory.TL, new Vector2(14, -62), new Vector2(500, 190));
            var sep = UiFactory.Rect(table, "Sep", new Color(1f, 1f, 1f, 0.1f));
            UiFactory.Place(sep.rectTransform, UiFactory.TL, new Vector2(14, -258), new Vector2(492, 1));
            var et = UiFactory.Label(table, "ENGINE / DRIVELINE", 12, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(et.rectTransform, UiFactory.TL, new Vector2(14, -274), new Vector2(300, 16));
            engineText = UiFactory.Label(table, "", 14, UiTheme.Text, TextAnchor.UpperLeft, UiFont.Mono);
            engineText.lineSpacing = 1.12f;
            UiFactory.Place(engineText.rectTransform, UiFactory.TL, new Vector2(14, -296), new Vector2(500, 170));
            root.gameObject.SetActive(false);
        }

        Card GetCard(int i)
        {
            while (cards.Count <= i)
            {
                var c = new Card();
                var p = UiFactory.Panel(cardRoot, "Card" + cards.Count, new Color(0.03f, 0.036f, 0.044f, 0.86f), 8, true, false);
                c.rt = p.rt; c.rt.anchorMin = c.rt.anchorMax = Vector2.zero; c.rt.pivot = new Vector2(0.5f, 0.5f); c.rt.sizeDelta = new Vector2(CW, CH);
                c.chip = UiFactory.Img(c.rt, "Chip", UiAssets.Circle, Color.gray);
                UiFactory.Place(c.chip.rectTransform, UiFactory.TL, new Vector2(10, -13), new Vector2(10, 10));
                c.head = UiFactory.Label(c.rt, "FL", 15, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
                UiFactory.Place(c.head.rectTransform, UiFactory.TL, new Vector2(26, -14), new Vector2(40, 18));
                c.surface = UiFactory.Label(c.rt, "", 12, UiTheme.TextDim, TextAnchor.MiddleRight, UiFont.Body);
                UiFactory.Place(c.surface.rectTransform, UiFactory.TR, new Vector2(-9, -14), new Vector2(130, 16));
                c.load = UiFactory.Label(c.rt, "", 14, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Mono);
                UiFactory.Place(c.load.rectTransform, UiFactory.TL, new Vector2(10, -34), new Vector2(CW - 18, 17));
                c.sink = UiFactory.Label(c.rt, "", 14, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Mono);
                UiFactory.Place(c.sink.rectTransform, UiFactory.TL, new Vector2(10, -51), new Vector2(CW - 18, 17));
                c.slip = UiFactory.Label(c.rt, "", 14, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Mono);
                UiFactory.Place(c.slip.rectTransform, UiFactory.TL, new Vector2(10, -68), new Vector2(CW - 18, 17));
                c.usage = UiFactory.Bar(c.rt, "Usage", new Vector2(CW - 20, 9), UiTheme.Good, out c.usageTrack);
                UiFactory.Place((RectTransform)c.usage.transform.parent, UiFactory.BL, new Vector2(10, 9), new Vector2(CW - 20, 9));
                c.usageLabel = UiFactory.Label(c.rt, "TRACTION", 10, UiTheme.TextFaint, TextAnchor.MiddleLeft, UiFont.Bold);
                UiFactory.Place(c.usageLabel.rectTransform, UiFactory.BL, new Vector2(10, 20), new Vector2(80, 12));
                cards.Add(c);
            }
            return cards[i];
        }

        public void SetOpen(bool on)
        {
            UiState.PhysicsOverlay = on;
            if (root != null) root.gameObject.SetActive(on);
        }

        static string ShortName(Wheel w) { return (w.axle != null && w.axle.name.Length > 0 ? w.axle.name.Substring(0, 1).ToUpperInvariant() : "?") + (w.isLeft ? "L" : "R"); }

        public override void Tick(HudContext c)
        {
            if (!UiState.PhysicsOverlay) { if (root.gameObject.activeSelf) root.gameObject.SetActive(false); return; }
            if (!root.gameObject.activeSelf) root.gameObject.SetActive(true);
            var v = c.v; if (v == null || v.wheels == null || c.cam == null) return;
            ss.Begin(c.cam, c.Scale);
            Vector2 csz = c.CanvasSize;
            ((RectTransform)leaders.transform).sizeDelta = csz;
            leaders.Clear();

            // vehicle screen centre for pushing the cards outwards
            Vector2 centre;
            if (!ss.Point(v.transform.position + Vector3.up * 0.8f, out centre)) centre = csz * 0.5f;

            int n = v.wheels.Length;
            for (int i = 0; i < n; i++)
            {
                var w = v.wheels[i];
                var card = GetCard(i);
                if (!card.rt.gameObject.activeSelf) card.rt.gameObject.SetActive(true);
                Vector2 hub;
                if (!ss.Point(w.hubWorld, out hub)) { card.rt.gameObject.SetActive(false); continue; }
                Vector2 dir = hub - centre;
                if (dir.sqrMagnitude < 25f) dir = new Vector2(w.isLeft ? -1f : 1f, 0.3f);
                dir.Normalize();
                // sideways first: cards sit beside the vehicle, left wheels on the left
                Vector2 target = hub + new Vector2(dir.x * 150f + (w.isLeft ? -40f : 40f), dir.y * 56f + 12f);
                target.x = Mathf.Clamp(target.x, CW * 0.5f + 8f, csz.x - CW * 0.5f - 8f);
                target.y = Mathf.Clamp(target.y, CH * 0.5f + 8f, csz.y - CH * 0.5f - 8f);
                card.pos = card.init ? Vector2.Lerp(card.pos, target, 1f - Mathf.Exp(-16f * c.dt)) : target;
                card.init = true;
            }
            // separate overlapping cards
            for (int it = 0; it < 3; it++)
                for (int i = 0; i < n; i++)
                    for (int j = i + 1; j < n; j++)
                    {
                        Vector2 d = cards[j].pos - cards[i].pos;
                        float ox = CW + 6f - Mathf.Abs(d.x), oy = CH + 6f - Mathf.Abs(d.y);
                        if (ox > 0f && oy > 0f)
                        {
                            float push = oy * 0.5f + 0.5f, s = d.y >= 0f ? 1f : -1f;
                            cards[i].pos.y -= s * push; cards[j].pos.y += s * push;
                        }
                    }

            for (int i = 0; i < n; i++)
            {
                var w = v.wheels[i]; var card = cards[i];
                if (!card.rt.gameObject.activeSelf) continue;
                Vector2 hub; ss.Point(w.hubWorld, out hub);
                card.rt.anchoredPosition = card.pos;
                float usageT = w.tractionUsage;
                Color uc = UiTheme.UsageColor(usageT);
                // leader line from the hub to the nearest card edge
                Vector2 dl = hub - card.pos; float tx = Mathf.Abs(dl.x) > 0.01f ? CW * 0.5f / Mathf.Abs(dl.x) : 99f, ty = Mathf.Abs(dl.y) > 0.01f ? CH * 0.5f / Mathf.Abs(dl.y) : 99f;
                Vector2 edge = card.pos + dl * Mathf.Min(1f, Mathf.Min(tx, ty));
                leaders.Add(hub, edge, 1.6f, new Color(uc.r, uc.g, uc.b, 0.85f));
                leaders.AddCircle(hub, 5.5f, 2f, uc, 14);

                card.head.text = ShortName(w) + (w.grounded ? "" : " air");
                var sp = SurfaceDatabase.Table[(int)w.soil.dominant];
                card.chip.color = Color.Lerp(sp.tint, Color.white, 0.2f);
                card.surface.text = w.grounded ? sp.name : "-";
                sb.Clear().Append("LOAD ").Append((w.load / 1000f).ToString("0.0").PadLeft(5)).Append(" kN"); card.load.text = sb.ToString();
                sb.Clear().Append("SINK ").Append((w.sinkage * 100f).ToString("0.0").PadLeft(5)).Append(" cm"); card.sink.text = sb.ToString();
                sb.Clear().Append("SLIP ").Append((w.slipRatio * 100f).ToString("+0;-0;0").PadLeft(5)).Append(" %"); card.slip.text = sb.ToString();
                card.slip.color = Mathf.Abs(w.slipRatio) > 0.5f ? UiTheme.Bad : Mathf.Abs(w.slipRatio) > 0.25f ? UiTheme.Warn : UiTheme.Text;
                card.sink.color = w.sinkage > 0.25f ? UiTheme.Bad : w.sinkage > 0.12f ? UiTheme.Warn : UiTheme.Text;
                card.usage.color = uc;
                UiFactory.SetBar(card.usage, Mathf.Clamp01(usageT));
            }
            for (int i = n; i < cards.Count; i++) if (cards[i].rt.gameObject.activeSelf) cards[i].rt.gameObject.SetActive(false);
            leaders.Apply();

            if (Time.unscaledTime > nextTable) { nextTable = Time.unscaledTime + 0.1f; RebuildTable(v); }
        }

        void RebuildTable(Vehicle v)
        {
            tableHead.text = "WHL   LOAD kN  SINK cm   SLIP %  TRAC   SURFACE";
            sb.Clear();
            for (int i = 0; i < v.wheels.Length; i++)
            {
                var w = v.wheels[i];
                string col = ColorUtility.ToHtmlStringRGB(UiTheme.UsageColor(w.tractionUsage));
                sb.Append(ShortName(w).PadRight(5)).Append((w.load / 1000f).ToString("0.0").PadLeft(8)).Append((w.sinkage * 100f).ToString("0.0").PadLeft(9))
                  .Append((w.slipRatio * 100f).ToString("+0;-0;0").PadLeft(9)).Append("  <color=#").Append(col).Append('>').Append(w.tractionUsage.ToString("0.00")).Append("</color>   ")
                  .Append(w.grounded ? SurfaceDatabase.Table[(int)w.soil.dominant].name : "airborne");
                if (i < v.wheels.Length - 1) sb.Append('\n');
            }
            tableRows.text = sb.ToString();
            var d = v.drivetrain;
            sb.Clear();
            sb.Append("RPM ").Append(d.rpm.ToString("0").PadLeft(5)).Append("   TORQUE ").Append(d.engineTorque.ToString("0").PadLeft(4)).Append(" Nm\n");
            sb.Append("CLUTCH ").Append(d.clutchTorque.ToString("0").PadLeft(5)).Append(" Nm  ").Append(d.clutchSlipping ? "<color=#FFCC30>SLIP</color>" : "lock").Append("   engage ").Append(d.engagement.ToString("0.00")).Append('\n');
            sb.Append("WHEEL T ").Append(d.wheelTorqueTotal.ToString("0").PadLeft(5)).Append(" Nm   ratio ").Append(d.currentRatio.ToString("0.0")).Append("  gear ").Append(d.GearLabel).Append(d.lowRange ? " LOW" : "").Append('\n');
            sb.Append("LOCK STRESS ").Append(d.lockStress.ToString("0").PadLeft(5)).Append("   fuel ").Append(d.fuelRateLitresPerHour.ToString("0.0")).Append(" L/h\n");
            sb.Append("SPEED ").Append(v.speedKmh.ToString("0.0").PadLeft(5)).Append(" km/h  fwd ").Append(v.forwardSpeed.ToString("0.0")).Append(" m/s\n");
            sb.Append("GROUNDED ").Append(v.groundedWheels).Append('/').Append(v.wheels.Length).Append("  belly ").Append(v.bellyContact.ToString("0.00")).Append("  slip~ ").Append(v.meanSlipAbs.ToString("0.00"));
            engineText.text = sb.ToString();
        }
    }

    /// <summary>
    /// "Collider / force gizmos": body box, wheel circles, contact normals, per-wheel force vectors, belly points, centre of mass and
    /// velocity - projected to screen and drawn as batched UI lines so they appear on top of the Game view on any render pipeline.
    /// </summary>
    public sealed class HudGizmos : HudWidget
    {
        UiLines lines;
        readonly ScreenSpace ss = new ScreenSpace();
        static readonly Color Normal = new Color(0.4f, 1f, 0.5f, 0.95f), Support = new Color(0.3f, 0.8f, 1f, 0.95f), Traction = new Color(1f, 0.6f, 0.15f, 0.95f),
            Lateral = new Color(1f, 0.35f, 0.9f, 0.95f), Resist = new Color(1f, 0.25f, 0.2f, 0.95f), Box = new Color(0.55f, 0.7f, 1f, 0.55f), Tyre = new Color(1f, 1f, 1f, 0.45f);

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("Gizmos", parent);
            root.anchorMin = root.anchorMax = Vector2.zero; root.pivot = Vector2.zero; root.anchoredPosition = Vector2.zero; root.sizeDelta = new Vector2(1920, 1080);
            lines = root.gameObject.AddComponent<UiLines>(); lines.raycastTarget = false;
            root.gameObject.SetActive(false);
        }

        void L(Vector3 a, Vector3 b, float w, Color col)
        {
            if (ss.Line(a, b, out Vector2 ca, out Vector2 cb)) lines.Add(ca, cb, w, col);
        }

        public override void Tick(HudContext c)
        {
            bool on = UiState.ForceGizmos && c.v != null && c.cam != null;
            if (root.gameObject.activeSelf != on) root.gameObject.SetActive(on);
            if (!on) return;
            var v = c.v;
            ss.Begin(c.cam, c.Scale);
            root.sizeDelta = c.CanvasSize;
            lines.Clear();
            var t = v.transform;

            // body collider box
            Vector3 sz = v.def.bodySize * 0.5f, ctr = v.def.bodyCenter;
            for (int i = 0; i < 4; i++)
            {
                Vector3 a = t.TransformPoint(ctr + new Vector3((i & 1) == 0 ? -sz.x : sz.x, (i & 2) == 0 ? -sz.y : sz.y, -sz.z));
                Vector3 b = t.TransformPoint(ctr + new Vector3((i & 1) == 0 ? -sz.x : sz.x, (i & 2) == 0 ? -sz.y : sz.y, sz.z));
                L(a, b, 1.5f, Box);
            }
            for (int zi = 0; zi < 2; zi++)
            {
                float zz = zi == 0 ? -sz.z : sz.z;
                Vector3 p00 = t.TransformPoint(ctr + new Vector3(-sz.x, -sz.y, zz)), p10 = t.TransformPoint(ctr + new Vector3(sz.x, -sz.y, zz));
                Vector3 p01 = t.TransformPoint(ctr + new Vector3(-sz.x, sz.y, zz)), p11 = t.TransformPoint(ctr + new Vector3(sz.x, sz.y, zz));
                L(p00, p10, 1.5f, Box); L(p10, p11, 1.5f, Box); L(p11, p01, 1.5f, Box); L(p01, p00, 1.5f, Box);
            }

            // belly points
            var gs = GroundService.Instance;
            var pts = v.def.bodyPoints;
            for (int i = 0; i < pts.Length; i++)
            {
                Vector3 p = t.TransformPoint(new Vector3(pts[i].x, pts[i].y, pts[i].z));
                bool hit = gs != null && gs.SurfaceHeight(p.x, p.z) > p.y - pts[i].w;
                Color col = hit ? UiTheme.Bad : UiTheme.Warn;
                float r = pts[i].w;
                L(p - t.right * r, p + t.right * r, 2f, col); L(p - t.up * r, p + t.up * r, 2f, col); L(p - t.forward * r, p + t.forward * r, 2f, col);
            }

            // wheels
            for (int i = 0; i < v.wheels.Length; i++)
            {
                var w = v.wheels[i];
                Vector3 n = w.contactNormal;
                // wheel circle in the wheel plane
                Quaternion steer = Quaternion.AngleAxis(w.steerAngle, t.up);
                Vector3 fwd = steer * t.forward;
                Vector3 prev = w.hubWorld + (fwd * Mathf.Cos(0f) + t.up * Mathf.Sin(0f)) * w.tire.radius;
                for (int k = 1; k <= 20; k++)
                {
                    float a = k / 20f * Mathf.PI * 2f;
                    Vector3 cur = w.hubWorld + (fwd * Mathf.Cos(a) + t.up * Mathf.Sin(a)) * w.tire.radius;
                    L(prev, cur, 1.4f, Tyre); prev = cur;
                }
                if (!w.grounded) continue;
                Vector3 pc = w.patchCenter;
                L(pc, pc + n * 1.0f, 2.2f, Normal);
                L(pc, pc + n * (w.supportForce / 10000f * 0.9f), 3f, Support);
                Vector3 fT = fwd - n * Vector3.Dot(fwd, n); fT = fT.sqrMagnitude > 1e-6f ? fT.normalized : fwd;
                Vector3 lT = Vector3.Cross(n, fT);
                Vector3 tp = pc + n * 0.05f;
                L(tp, tp + fT * (w.fTrac / 5000f), 3f, Traction);
                L(tp, tp + lT * (w.fLat / 5000f), 3f, Lateral);
                L(tp, tp + fT * (w.fResist / 5000f), 3f, Resist);
            }
            // CoM + velocity
            Vector3 com = v.rb.worldCenterOfMass;
            L(com - t.right * 0.35f, com + t.right * 0.35f, 2.4f, Color.magenta); L(com - t.up * 0.35f, com + t.up * 0.35f, 2.4f, Color.magenta); L(com - t.forward * 0.35f, com + t.forward * 0.35f, 2.4f, Color.magenta);
            L(com, com + v.rb.linearVelocity * 0.6f, 3f, Color.white);
            lines.Apply();
        }
    }
}
