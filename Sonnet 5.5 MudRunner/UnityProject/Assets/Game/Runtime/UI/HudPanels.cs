using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    public enum NoteKind { Info, Good, Warn, Bad }

    /// <summary>Key binding reference shared by the help overlay and the pause menu "Controls" page.</summary>
    public static class UiControls
    {
        public struct Row { public string key, action; public Row(string k, string a) { key = k; action = a; } }
        public sealed class Section { public string title; public Row[] rows; }

        public static readonly Section[][] Columns =
        {
            new[]
            {
                new Section { title = "DRIVING", rows = new[] { new Row("W / ↑", "Throttle"), new Row("S / ↓", "Brake / reverse"), new Row("A D / ← →", "Steer"), new Row("Space", "Handbrake"),
                    new Row("Shift / Ctrl", "Shift up / down (manual)"), new Row("M", "Automatic / manual gearbox"), new Row("I", "Engine on / off"), new Row("Backspace", "Recover vehicle (costs fuel + time)") } },
                new Section { title = "WINCH", rows = new[] { new Row("Z", "Attach nearest anchor / detach"), new Row("E", "Reel in"), new Row("Q", "Pay out") } },
            },
            new[]
            {
                new Section { title = "DRIVETRAIN", rows = new[] { new Row("R", "Low / high range"), new Row("T", "All-wheel drive"), new Row("F", "Front differential lock"), new Row("G", "Rear differential lock"), new Row("V", "Centre differential lock"), new Row("L", "Headlights") } },
                new Section { title = "CAMERA", rows = new[] { new Row("C", "Change camera"), new Row("Mouse", "Look around / orbit"), new Row("Wheel", "Zoom in chase / top camera"), new Row("[  ]", "Select wheel (close-up camera)"), new Row("F10", "Hide / show the HUD") } },
            },
            new[]
            {
                new Section { title = "INTERFACE", rows = new[] { new Row("Tab", "Full map (drag, wheel, right-click waypoint)"), new Row("H", "This help"), new Row("Esc", "Pause menu"), new Row("Enter", "Garage (inside a garage zone)"), new Row("-  =", "Minimap zoom"), new Row("F5 / F9", "Quick save / quick load") } },
                new Section { title = "DEBUG", rows = new[] { new Row("F1 / `", "Debug + benchmark menu"), new Row("F2", "Physics overlay (per-wheel data)"), new Row("F3", "FPS counter"), new Row("Gamepad", "RT/LT pedals, stick steer, A brake") } },
            },
        };

        /// <summary>Builds the three-column key reference inside <paramref name="parent"/>; returns the height used.</summary>
        public static float Build(Transform parent, float width, float topPad = 0f)
        {
            float gap = 30f, colW = (width - gap * 2f) / 3f, maxH = 0f;
            for (int c = 0; c < Columns.Length; c++)
            {
                float y = topPad;
                float x = c * (colW + gap);
                foreach (var sec in Columns[c])
                {
                    var h = UiFactory.Label(parent, sec.title, 15, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
                    UiFactory.Place(h.rectTransform, UiFactory.TL, new Vector2(x, -y), new Vector2(colW, 22));
                    var line = UiFactory.Rect(parent, "Line", new Color(1f, 0.69f, 0.125f, 0.35f));
                    UiFactory.Place(line.rectTransform, UiFactory.TL, new Vector2(x, -(y + 24)), new Vector2(colW, 1));
                    y += 32f;
                    foreach (var r in sec.rows)
                    {
                        var kt = UiFactory.Label(parent, r.key, 14, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Mono);
                        float kw = Mathf.Max(30f, kt.preferredWidth + 14f);
                        var chip = UiFactory.Img(parent, "Key", UiAssets.Rounded(6), new Color(1f, 1f, 1f, 0.11f), Image.Type.Sliced);
                        UiFactory.Place(chip.rectTransform, UiFactory.TL, new Vector2(x, -y), new Vector2(kw, 24));
                        kt.transform.SetParent(chip.transform, false); UiFactory.Fill(kt.rectTransform);
                        var at = UiFactory.Label(parent, r.action, 15, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Body);
                        UiFactory.Place(at.rectTransform, UiFactory.TL, new Vector2(x + 112, -y), new Vector2(colW - 112, 24));
                        if (kw > 100f) at.rectTransform.anchoredPosition = new Vector2(x + kw + 10, -y);
                        y += 29f;
                    }
                    y += 14f;
                }
                maxH = Mathf.Max(maxH, y);
            }
            return maxH;
        }
    }

    /// <summary>Top-left objective card driven by <see cref="ObjectiveManager"/>.</summary>
    public sealed class HudObjective : HudWidget
    {
        UiPanel panel; Text tag, status, title, detail, dist, distCap, timeT, extra;
        Image arrow, accentBar;
        string lastTitle, lastDetail; bool lastHasTarget, lastTimer, lastExtra;
        int lastDist = -1, lastTime = -1;
        const float W = 404f;

        public override void Build(HudContext c, RectTransform parent)
        {
            panel = UiFactory.Panel(parent, "Objective", UiTheme.Bg, 12, true, true);
            root = panel.rt;
            UiFactory.Place(root, UiFactory.TL, new Vector2(UiTheme.Margin, -UiTheme.Margin), new Vector2(W, 160), UiFactory.TL);
            accentBar = UiFactory.Img(root, "Accent", UiAssets.Rounded(2), UiTheme.Accent, Image.Type.Sliced);
            UiFactory.Place(accentBar.rectTransform, UiFactory.ML, new Vector2(0, 0), new Vector2(4, 120), UiFactory.ML);
            tag = UiFactory.Label(root, "FREE DRIVE", 12, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(tag.rectTransform, UiFactory.TL, new Vector2(18, -16), new Vector2(200, 16));
            status = UiFactory.Label(root, "", 12, UiTheme.Good, TextAnchor.MiddleRight, UiFont.Bold);
            UiFactory.Place(status.rectTransform, UiFactory.TR, new Vector2(-16, -16), new Vector2(180, 16));
            title = UiFactory.Label(root, "", 22, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(title.rectTransform, UiFactory.TL, new Vector2(18, -40), new Vector2(W - 36, 28));
            detail = UiFactory.Paragraph(root, "", 15, UiTheme.TextDim, new Vector2(W - 36, 60), TextAnchor.UpperLeft);
            UiFactory.Place(detail.rectTransform, UiFactory.TL, new Vector2(18, -68), new Vector2(W - 36, 60));
            arrow = UiFactory.Img(root, "Arrow", UiAssets.Arrow, UiTheme.Accent);
            UiFactory.Place(arrow.rectTransform, UiFactory.TL, new Vector2(18, -140), new Vector2(26, 26));
            dist = UiFactory.Label(root, "", 30, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(dist.rectTransform, UiFactory.TL, new Vector2(54, -136), new Vector2(150, 34));
            distCap = UiFactory.Label(root, "TO TARGET", 11, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(distCap.rectTransform, UiFactory.TL, new Vector2(56, -168), new Vector2(120, 14));
            timeT = UiFactory.Label(root, "", 26, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Display);
            UiFactory.Place(timeT.rectTransform, UiFactory.TR, new Vector2(-16, -136), new Vector2(150, 32));
            extra = UiFactory.Label(root, "", 14, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Body);
            UiFactory.Place(extra.rectTransform, UiFactory.TL, new Vector2(18, -190), new Vector2(W - 36, 20));
        }

        // snapshot of the fields the card shows (taken from ObjectiveManager, or a plain "free drive" card when none exists)
        struct ObjView
        {
            public string title, detail, cargoStatus, resultText;
            public bool hasTarget, completed, failed;
            public Vector3 targetPosition; public float targetRadius, timeLeft, fuelLimit;
            public static ObjView From(ObjectiveManager m)
            {
                return new ObjView { title = m.title, detail = m.detail, cargoStatus = m.cargoStatus, resultText = m.resultText, hasTarget = m.hasTarget, completed = m.completed, failed = m.failed,
                    targetPosition = m.targetPosition, targetRadius = m.targetRadius, timeLeft = m.timeLeft, fuelLimit = m.fuelLimit };
            }
            public float DistanceToTarget(Vector3 from)
            {
                return hasTarget ? Vector3.Distance(new Vector3(from.x, 0, from.z), new Vector3(targetPosition.x, 0, targetPosition.z)) : 0f;
            }
        }

        static ObjView Fallback(HudContext c)
        {
            string t = "Free drive";
            if (c.gm != null && c.gm.World != null)
            {
                var k = c.gm.World.kind;
                t = k == WorldKind.ProvingGround ? "Free drive — Proving ground" : k == WorldKind.Wilderness ? "Free drive — Wilderness" : "Free drive";
            }
            return new ObjView { title = t, detail = "Explore the map and test the vehicle.   [Tab] map    [H] controls    [C] camera", timeLeft = -1f, fuelLimit = -1f, cargoStatus = "", resultText = "", targetRadius = 12f };
        }

        public override void Tick(HudContext c)
        {
            var real = ObjectiveManager.Instance;
            if (c.v == null) { UiFactory.SetActive(root, false); return; }
            UiFactory.SetActive(root, true);
            ObjView om = real != null ? ObjView.From(real) : Fallback(c);
            bool hasTarget = om.hasTarget && !om.completed && !om.failed;
            bool hasTimer = om.timeLeft >= 0f && !om.completed && !om.failed;
            string cargo = om.cargoStatus ?? "";
            string fuelTxt = om.fuelLimit >= 0f ? "Fuel limit " + Mathf.RoundToInt(om.fuelLimit) + " L" : "";
            string extraTxt = cargo.Length > 0 ? (fuelTxt.Length > 0 ? cargo + "   |   " + fuelTxt : cargo) : fuelTxt;
            bool hasExtra = extraTxt.Length > 0;
            string tStr = om.title ?? "", dStr = om.completed || om.failed ? (string.IsNullOrEmpty(om.resultText) ? om.detail : om.resultText) : om.detail;
            bool relayout = tStr != lastTitle || dStr != lastDetail || hasTarget != lastHasTarget || hasTimer != lastTimer || hasExtra != lastExtra;
            if (relayout)
            {
                lastTitle = tStr; lastDetail = dStr; lastHasTarget = hasTarget; lastTimer = hasTimer; lastExtra = hasExtra;
                title.text = tStr; detail.text = dStr ?? "";
                bool free = !om.hasTarget && !om.completed && !om.failed && om.timeLeft < 0f;
                tag.text = om.completed ? "OBJECTIVE" : om.failed ? "OBJECTIVE" : (free ? "FREE DRIVE" : "OBJECTIVE");
                float dh = Mathf.Clamp(detail.preferredHeight, 18f, 86f);
                detail.rectTransform.sizeDelta = new Vector2(W - 36, dh);
                float y = 68f + dh + 10f;
                bool info = hasTarget || hasTimer;
                UiFactory.SetActive(arrow, hasTarget); UiFactory.SetActive(dist, hasTarget); UiFactory.SetActive(distCap, hasTarget); UiFactory.SetActive(timeT, hasTimer);
                if (info)
                {
                    arrow.rectTransform.anchoredPosition = new Vector2(18, -(y + 4));
                    dist.rectTransform.anchoredPosition = new Vector2(54, -y);
                    distCap.rectTransform.anchoredPosition = new Vector2(56, -(y + 31));
                    timeT.rectTransform.anchoredPosition = new Vector2(-16, -y);
                    y += 50f;
                }
                UiFactory.SetActive(extra, hasExtra);
                if (hasExtra) { extra.rectTransform.anchoredPosition = new Vector2(18, -y); y += 24f; }
                y += 12f;
                root.sizeDelta = new Vector2(W, y);
                accentBar.rectTransform.sizeDelta = new Vector2(4, y - 28f);
            }
            status.text = om.completed ? "COMPLETE" : om.failed ? "FAILED" : "";
            status.color = om.completed ? UiTheme.Good : UiTheme.Bad;
            accentBar.color = om.completed ? UiTheme.Good : om.failed ? UiTheme.Bad : UiTheme.Accent;
            if (hasExtra) extra.text = extraTxt;
            if (hasTarget)
            {
                float d = om.DistanceToTarget(c.v.transform.position);
                int di = d >= 1000f ? Mathf.RoundToInt(d / 10f) + 100000 : Mathf.RoundToInt(d);
                if (di != lastDist) { lastDist = di; dist.text = HudCompass.FormatDist(d); }
                Vector3 to = om.targetPosition - c.v.transform.position; to.y = 0f;
                float bearing = Mathf.Atan2(to.x, to.z) * Mathf.Rad2Deg;
                float delta = Mathf.DeltaAngle(c.cam != null ? c.cam.transform.eulerAngles.y : 0f, bearing);
                arrow.rectTransform.localRotation = Quaternion.Euler(0, 0, -delta);
                bool inside = d < om.targetRadius;
                dist.color = inside ? UiTheme.Good : UiTheme.Text;
                distCap.text = inside ? "IN TARGET AREA" : "TO TARGET";
            }
            if (hasTimer)
            {
                int ti = Mathf.CeilToInt(om.timeLeft);
                if (ti != lastTime) { lastTime = ti; timeT.text = (ti / 60).ToString("00") + ":" + (ti % 60).ToString("00"); }
                timeT.color = om.timeLeft < 30f ? (Mathf.Repeat(c.time, 1f) < 0.6f ? UiTheme.Bad : UiTheme.Warn) : UiTheme.Text;
            }
        }
    }

    /// <summary>Stacked notification toasts (top-right). Use <see cref="Hud.Notify(string, float)"/> to post one.</summary>
    public sealed class HudToasts : HudWidget
    {
        sealed class Toast
        {
            public RectTransform rt; public Image bg, bar; public Text text; public float age, dur, y; public bool active;
        }
        readonly List<Toast> toasts = new List<Toast>();
        readonly Queue<(string, float, NoteKind)> pending = new Queue<(string, float, NoteKind)>();
        public float topOffset;       // extra offset for the stats panel
        public int ActiveCount { get { int n = 0; foreach (var t in toasts) if (t.active) n++; return n; } }
        public string NewestText { get { Toast best = null; foreach (var t in toasts) if (t.active && (best == null || t.age < best.age)) best = t; return best != null ? best.text.text : ""; } }
        float offsetSm;
        const float W = 392f, H = 46f;
        const int MaxToasts = 6;

        public void Post(string msg, float seconds, NoteKind kind) { pending.Enqueue((msg, seconds, kind)); }

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("Toasts", parent);
            UiFactory.Place(root, UiFactory.TR, new Vector2(-UiTheme.Margin, -UiTheme.Margin), new Vector2(W, 400), UiFactory.TR);
            for (int i = 0; i < MaxToasts + 1; i++)
            {
                var t = new Toast();
                t.rt = UiFactory.NewRect("Toast" + i, root);
                t.rt.sizeDelta = new Vector2(W, H);
                t.rt.anchorMin = t.rt.anchorMax = UiFactory.TR; t.rt.pivot = UiFactory.TR;
                var panel = UiFactory.Panel(t.rt, "P", UiTheme.BgDeep, 10, true, true);
                UiFactory.Fill(panel.rt);
                t.bg = panel.bg;
                t.bar = UiFactory.Img(t.rt, "Bar", UiAssets.Rounded(2), UiTheme.Accent, Image.Type.Sliced);
                UiFactory.Place(t.bar.rectTransform, UiFactory.ML, new Vector2(0, 0), new Vector2(4, H - 14), UiFactory.ML);
                t.text = UiFactory.Label(t.rt, "", 17, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Body);
                t.text.horizontalOverflow = HorizontalWrapMode.Wrap; t.text.verticalOverflow = VerticalWrapMode.Truncate;
                UiFactory.Fill(t.text.rectTransform, 18, 2, 12, 2);
                t.rt.gameObject.SetActive(false);
                toasts.Add(t);
            }
        }

        static Color KindColor(NoteKind k)
        {
            switch (k) { case NoteKind.Good: return UiTheme.Good; case NoteKind.Warn: return UiTheme.Warn; case NoteKind.Bad: return UiTheme.Bad; default: return UiTheme.Accent; }
        }

        public override void Tick(HudContext c)
        {
            float dt = Time.unscaledDeltaTime;
            while (pending.Count > 0)
            {
                var (msg, dur, kind) = pending.Dequeue();
                Toast slot = null;
                foreach (var t in toasts) if (!t.active) { slot = t; break; }
                if (slot == null)
                {   // recycle the oldest
                    float oldest = -1f;
                    foreach (var t in toasts) if (t.age > oldest) { oldest = t.age; slot = t; }
                }
                slot.active = true; slot.age = 0f; slot.dur = Mathf.Max(1f, dur); slot.text.text = msg;
                slot.bar.color = KindColor(kind);
                slot.rt.gameObject.SetActive(true); slot.rt.SetAsLastSibling();
                // newest toast starts at the top
                slot.y = 0f;
            }
            offsetSm = Mathf.Lerp(offsetSm, topOffset, 1f - Mathf.Exp(-10f * dt));
            // order by age (newest first)
            float y = offsetSm;
            var order = ScratchOrder;
            order.Clear();
            foreach (var t in toasts) if (t.active) order.Add(t);
            order.Sort(AgeCompare);
            for (int i = 0; i < order.Count; i++)
            {
                var t = order[i];
                t.age += dt;
                if (t.age > t.dur) { t.active = false; t.rt.gameObject.SetActive(false); continue; }
                float h = t.text.preferredHeight > 24f ? 62f : H;
                t.rt.sizeDelta = new Vector2(W, h);
                t.bar.rectTransform.sizeDelta = new Vector2(4, h - 14f);
                t.y = Mathf.Lerp(t.y, y, 1f - Mathf.Exp(-14f * dt));
                float slide = Mathf.Clamp01(t.age / 0.28f); slide = 1f - (1f - slide) * (1f - slide);
                float fade = Mathf.Clamp01((t.dur - t.age) / 0.45f);
                t.rt.anchoredPosition = new Vector2((1f - slide) * 70f, -t.y);
                float a = slide * fade;
                SetAlpha(t, a);
                y += h + 8f;
            }
        }

        static readonly List<Toast> ScratchOrder = new List<Toast>();
        static readonly System.Comparison<Toast> AgeCompare = (a, b) => a.age.CompareTo(b.age);

        static void SetAlpha(Toast t, float a)
        {
            var cg = t.rt.GetComponent<CanvasGroup>();
            if (cg == null) cg = t.rt.gameObject.AddComponent<CanvasGroup>();
            cg.alpha = a;
        }
    }

    /// <summary>Centre overlay with the key bindings (H). Auto-shown for the first seconds of a session.</summary>
    public sealed class HudHelp : HudWidget
    {
        CanvasGroup group; float autoHideAt = -1f;
        public bool IsOpen { get; private set; }
        Text hintText;

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("Help", parent);
            UiFactory.Fill(root);
            group = root.gameObject.AddComponent<CanvasGroup>();
            var dim = UiFactory.Rect(root, "Dim", new Color(0f, 0f, 0f, 0.42f));
            UiFactory.Fill(dim.rectTransform);
            const float W = 1060f;
            var panel = UiFactory.Panel(root, "Panel", new Color(0.035f, 0.041f, 0.049f, 0.95f), 14, true, true);
            UiFactory.Place(panel.rt, UiFactory.C, Vector2.zero, new Vector2(W, 560));
            var t = UiFactory.Label(panel.rt, "CONTROLS", 30, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(t.rectTransform, UiFactory.TL, new Vector2(34, -38), new Vector2(400, 40));
            hintText = UiFactory.Label(panel.rt, "[H] close", 15, UiTheme.TextDim, TextAnchor.MiddleRight, UiFont.Body);
            UiFactory.Place(hintText.rectTransform, UiFactory.TR, new Vector2(-34, -38), new Vector2(300, 24));
            var body = UiFactory.NewRect("Body", panel.rt);
            UiFactory.Place(body, UiFactory.TL, new Vector2(34, -76), new Vector2(W - 68, 440), UiFactory.TL);
            float h = UiControls.Build(body, W - 68);
            panel.rt.sizeDelta = new Vector2(W, h + 120f);
            root.gameObject.SetActive(false);
        }

        public void Open(bool open, float autoHideSeconds = -1f)
        {
            IsOpen = open; UiState.HelpOpen = open;
            root.gameObject.SetActive(open);
            autoHideAt = open && autoHideSeconds > 0f ? Time.unscaledTime + autoHideSeconds : -1f;
            if (hintText != null) hintText.text = autoHideAt > 0f ? "[H] close — hides automatically" : "[H] close";
        }

        public void Toggle() { Open(!IsOpen); }

        public override void SetVisible(bool on) { }

        public override void Tick(HudContext c)
        {
            if (IsOpen && autoHideAt > 0f && Time.unscaledTime > autoHideAt) Open(false);
        }
    }

    /// <summary>Flashing "vehicle stuck" banner with context sensitive recovery hints.</summary>
    public sealed class HudStuck : HudWidget
    {
        UiPanel panel; Text head, hints; Image icon;
        Vehicle lastV; string lastHints;
        float pulse;
        public bool IsShowing => root != null && root.gameObject.activeSelf;

        public override void Build(HudContext c, RectTransform parent)
        {
            panel = UiFactory.Panel(parent, "StuckBanner", new Color(0.30f, 0.05f, 0.04f, 0.90f), 12, true, true);
            root = panel.rt;
            UiFactory.Place(root, UiFactory.TC, new Vector2(0, -(UiTheme.Margin + 132)), new Vector2(880, 96), UiFactory.TC);
            panel.border.color = new Color(1f, 0.35f, 0.25f, 0.9f);
            icon = UiFactory.Img(root, "Icon", UiAssets.Triangle, UiTheme.Bad);
            UiFactory.Place(icon.rectTransform, UiFactory.ML, new Vector2(30, 6), new Vector2(46, 42), UiFactory.ML);
            var ex = UiFactory.Label(icon.transform, "!", 28, Color.white, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Fill(ex.rectTransform, 0, -6, 0, 0);
            head = UiFactory.Label(root, "VEHICLE STUCK", 32, Color.white, TextAnchor.MiddleLeft, UiFont.Display, shadow: true);
            UiFactory.Place(head.rectTransform, UiFactory.TL, new Vector2(94, -22), new Vector2(600, 40));
            hints = UiFactory.Label(root, "", 17, new Color(1f, 0.9f, 0.85f), TextAnchor.UpperLeft, UiFont.Body);
            hints.horizontalOverflow = HorizontalWrapMode.Wrap; hints.verticalOverflow = VerticalWrapMode.Truncate;
            UiFactory.Place(hints.rectTransform, UiFactory.TL, new Vector2(94, -58), new Vector2(760, 36));
            root.gameObject.SetActive(false);
        }

        public override void Tick(HudContext c)
        {
            var v = c.v;
            bool stuck = v != null && v.isStuck && !UiState.ModalOpen;
            if (!stuck) { if (root.gameObject.activeSelf) root.gameObject.SetActive(false); pulse = 0f; return; }
            if (!root.gameObject.activeSelf) root.gameObject.SetActive(true);
            pulse += c.dt;
            float f = 0.5f + 0.5f * Mathf.Sin(pulse * 6.5f);
            panel.bg.color = new Color(0.22f + 0.2f * f, 0.04f, 0.035f, 0.90f);
            panel.border.color = new Color(1f, 0.30f + 0.3f * f, 0.2f, 0.55f + 0.45f * f);
            icon.color = Color.Lerp(UiTheme.Bad, UiTheme.Warn, f);
            if (v != lastV || lastHints == null)
            {
                lastV = v;
                var parts = new List<string>();
                var d = v.drivetrain;
                if (v.def.hasLowRange && !d.lowRange) parts.Add("[R] low range");
                bool anyLock = d.centreLock; foreach (var l in d.axleLock) anyLock |= l;
                if (!anyLock) parts.Add("[F] [G] [V] diff locks");
                if (v.def.hasAwdSwitch && !d.awd) parts.Add("[T] all-wheel drive");
                if (v.winch != null) parts.Add("[Z] winch to an anchor, then [E] reel in");
                parts.Add("ease off the throttle and try reverse");
                parts.Add("[Backspace] recover (costs fuel + time)");
                lastHints = string.Join("   •   ", parts);
                hints.text = lastHints;
            }
            else
            {
                // refresh when the state of the aids changed
                var d = v.drivetrain;
                bool anyLock = d.centreLock; foreach (var l in d.axleLock) anyLock |= l;
                int key = (d.lowRange ? 1 : 0) | (anyLock ? 2 : 0) | (d.awd ? 4 : 0);
                if (key != lastKey) { lastKey = key; lastHints = null; }
            }
        }
        int lastKey;
    }

    /// <summary>Winch status card (bottom centre): shows when the vehicle has a winch and a cable is attached or an anchor is in reach.</summary>
    public sealed class HudWinch : HudWidget
    {
        Text state, rope, tension; Image ropeFill, tensionFill;
        float nextProbe; bool anchorInReach;
        public bool IsShowing => root != null && root.gameObject.activeSelf;

        public override void Build(HudContext c, RectTransform parent)
        {
            var p = UiFactory.Panel(parent, "Winch", UiTheme.Bg, 12, true, true);
            root = p.rt;
            UiFactory.Place(root, UiFactory.BC, new Vector2(0, UiTheme.Margin), new Vector2(430, 104), UiFactory.BC);
            var t = UiFactory.Label(root, "WINCH", 14, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(t.rectTransform, UiFactory.TL, new Vector2(16, -18), new Vector2(80, 18));
            state = UiFactory.Label(root, "", 15, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Bold);
            UiFactory.Place(state.rectTransform, UiFactory.TR, new Vector2(-16, -18), new Vector2(320, 18));
            var rl = UiFactory.Label(root, "ROPE", 12, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(rl.rectTransform, UiFactory.TL, new Vector2(16, -48), new Vector2(60, 16));
            ropeFill = UiFactory.Bar(root, "RopeBar", new Vector2(200, 12), UiTheme.Info, out _);
            UiFactory.Place((RectTransform)ropeFill.transform.parent, UiFactory.TL, new Vector2(84, -50), new Vector2(200, 12));
            rope = UiFactory.Label(root, "", 15, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Display);
            UiFactory.Place(rope.rectTransform, UiFactory.TR, new Vector2(-16, -46), new Vector2(130, 20));
            var tl = UiFactory.Label(root, "LOAD", 12, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(tl.rectTransform, UiFactory.TL, new Vector2(16, -76), new Vector2(60, 16));
            tensionFill = UiFactory.Bar(root, "TensionBar", new Vector2(200, 12), UiTheme.Good, out _);
            UiFactory.Place((RectTransform)tensionFill.transform.parent, UiFactory.TL, new Vector2(84, -78), new Vector2(200, 12));
            tension = UiFactory.Label(root, "", 15, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Display);
            UiFactory.Place(tension.rectTransform, UiFactory.TR, new Vector2(-16, -74), new Vector2(130, 20));
        }

        public override void Tick(HudContext c)
        {
            var v = c.v; var w = v != null ? v.winch : null;
            if (w == null) { UiFactory.SetActive(root, false); return; }
            if (c.time > nextProbe)
            {
                nextProbe = c.time + 0.3f;
                anchorInReach = false;
                Vector3 f = w.FairleadWorld;
                for (int i = 0; i < WinchAnchor.All.Count && !anchorInReach; i++)
                {
                    var a = WinchAnchor.All[i]; if (a == null) continue;
                    float d = Vector3.Distance(a.WorldPoint, f);
                    if (d < w.maxLength - 1f && d > 1.5f && Vector3.Angle(v.transform.forward, a.WorldPoint - f) < 75f) anchorInReach = true;
                }
            }
            bool show = w.Attached || anchorInReach;
            UiFactory.SetActive(root, show);
            if (!show) return;
            if (!w.Attached)
            {
                state.text = "anchor in reach — [Z] attach"; state.color = UiTheme.Info;
                rope.text = "- / " + Mathf.RoundToInt(w.maxLength) + " m"; tension.text = "0 kN";
                UiFactory.SetBar(ropeFill, 0f); UiFactory.SetBar(tensionFill, 0f);
                return;
            }
            string st = w.AnchorName.Length > 0 ? w.AnchorName : "anchor";
            if (w.input > 0.1f) { state.text = "REELING IN — " + st; state.color = UiTheme.Warn; }
            else if (w.input < -0.1f) { state.text = "PAYING OUT — " + st; state.color = UiTheme.Info; }
            else { state.text = (w.IsTaut ? "TAUT — " : "ATTACHED — ") + st; state.color = w.IsTaut ? UiTheme.Warn : UiTheme.Good; }
            rope.text = w.RopeLength.ToString("0.0") + " / " + Mathf.RoundToInt(w.maxLength) + " m";
            UiFactory.SetBar(ropeFill, w.RopeLength / Mathf.Max(1f, w.maxLength));
            float tf = w.Tension / Mathf.Max(1f, w.ratedPull);
            tension.text = (w.Tension / 1000f).ToString("0.0") + " / " + Mathf.RoundToInt(w.ratedPull / 1000f) + " kN";
            tensionFill.color = UiTheme.UsageColor(tf);
            UiFactory.SetBar(tensionFill, tf);
        }
    }

    /// <summary>Contextual prompt pill above the winch card: garage entrance, flooded engine and similar one-liners.</summary>
    public sealed class HudPrompt : HudWidget
    {
        Text text; Image bg;
        public string current = "";
        public override void Build(HudContext c, RectTransform parent)
        {
            var p = UiFactory.Panel(parent, "Prompt", new Color(0.04f, 0.047f, 0.056f, 0.88f), 14, true, true);
            root = p.rt;
            UiFactory.Place(root, UiFactory.BC, new Vector2(0, UiTheme.Margin + 126), new Vector2(420, 42), UiFactory.BC);
            text = UiFactory.Label(root, "", 18, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Bold);
            UiFactory.Fill(text.rectTransform);
            root.gameObject.SetActive(false);
        }
        public override void Tick(HudContext c)
        {
            var v = c.v;
            string s = "";
            if (v != null && !UiState.ModalOpen)
            {
                var gz = GarageZone.Find(v.transform.position);
                if (gz != null) s = "<color=#FFB020>[Enter]</color>  " + gz.displayName;
                else if (v.water != null && v.water.engineFlooded) s = "<color=#FF5442>Engine flooded</color> — wait for it to drain";
            }
            if (s != current) { current = s; text.text = s; }
            bool on = s.Length > 0;
            if (root.gameObject.activeSelf != on) root.gameObject.SetActive(on);
        }
    }

    /// <summary>Debug stats (top-right): FPS with 1% low, coordinates. Only shown when enabled from the debug menu / F3.</summary>
    public sealed class HudStats : HudWidget
    {
        Text fps, coords; UiPanel panel;
        public bool Visible => UiState.ShowFps || UiState.ShowCoords;
        public float Height { get; private set; }

        public override void Build(HudContext c, RectTransform parent)
        {
            panel = UiFactory.Panel(parent, "Stats", UiTheme.BgDeep, 8, true, false);
            root = panel.rt;
            UiFactory.Place(root, UiFactory.TR, new Vector2(-UiTheme.Margin, -UiTheme.Margin), new Vector2(392, 60), UiFactory.TR);
            fps = UiFactory.Label(root, "", 15, UiTheme.Good, TextAnchor.MiddleLeft, UiFont.Mono);
            UiFactory.Place(fps.rectTransform, UiFactory.TL, new Vector2(12, -8), new Vector2(372, 20));
            coords = UiFactory.Label(root, "", 15, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Mono);
            UiFactory.Place(coords.rectTransform, UiFactory.TL, new Vector2(12, -30), new Vector2(372, 20));
            root.gameObject.SetActive(false);
        }

        public override void Tick(HudContext c)
        {
            bool a = UiState.ShowFps, b = UiState.ShowCoords;
            bool vis = a || b;
            if (root.gameObject.activeSelf != vis) root.gameObject.SetActive(vis);
            Height = vis ? 70f : 0f;
            if (!vis) return;
            float h = 12f + (a ? 22f : 0f) + (b ? 22f : 0f);
            root.sizeDelta = new Vector2(392, h);
            UiFactory.SetActive(fps, a); UiFactory.SetActive(coords, b);
            float y = -8f;
            if (a)
            {
                fps.rectTransform.anchoredPosition = new Vector2(12, y); y -= 22f;
                float f = FpsCounter.Fps;
                fps.text = "FPS " + f.ToString("0").PadLeft(3) + "  " + FpsCounter.FrameMs.ToString("0.0") + " ms   1% low " + FpsCounter.Low1.ToString("0");
                fps.color = f >= 60f ? UiTheme.Good : f >= 30f ? UiTheme.Warn : UiTheme.Bad;
            }
            if (b && c.v != null)
            {
                coords.rectTransform.anchoredPosition = new Vector2(12, y);
                Vector3 p = c.v.transform.position;
                float yaw = c.v.transform.eulerAngles.y;
                coords.text = "X " + p.x.ToString("0.0") + "  Y " + p.y.ToString("0.0") + "  Z " + p.z.ToString("0.0") + "  " + yaw.ToString("0") + "°";
            }
        }
    }
}
