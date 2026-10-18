using System;
using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>Per-frame data handed to every HUD widget.</summary>
    public sealed class HudContext
    {
        public Vehicle v;
        public GameManager gm;
        public Camera cam;
        public Canvas canvas;
        public RectTransform root;      // full-screen, bottom-left origin
        public float dt, time;
        public float Scale => canvas != null ? Mathf.Max(0.01f, canvas.scaleFactor) : 1f;
        public Vector2 ScreenToCanvas(Vector2 screen) { return screen / Scale; }
        public Vector2 CanvasSize
        {
            get
            {
                var cam = Camera.main;
                Vector2 px = cam != null && cam.pixelWidth > 0 ? new Vector2(cam.pixelWidth, cam.pixelHeight) : new Vector2(Screen.width, Screen.height);
                return px / Scale;
            }
        }
    }

    public abstract class HudWidget
    {
        public RectTransform root;
        public abstract void Build(HudContext c, RectTransform parent);
        public abstract void Tick(HudContext c);
        public virtual void OnVehicleChanged(HudContext c) { }
        public virtual void SetVisible(bool on) { if (root != null) UiFactory.SetActive(root.gameObject, on); }
    }

    /// <summary>Round dial (speedometer / tachometer): translucent disc, 270 degree track + value arc, ticks and numerals.</summary>
    public sealed class Dial
    {
        public RectTransform root;
        public UiArc track, fill, zone;
        public Image tip, tipGlow;
        public float radius, thickness, vmax;
        readonly List<Text> labels = new List<Text>();
        public const float StartDeg = -135f, SweepDeg = 270f;

        public static Dial Create(Transform parent, string name, float diameter, float thick, float vmax, float major, float minor,
            Func<float, string> labelFmt, int labelSize, float redFrom = -1f)
        {
            var d = new Dial { radius = diameter * 0.5f, thickness = thick, vmax = vmax };
            d.root = UiFactory.NewRect(name, parent);
            d.root.sizeDelta = new Vector2(diameter, diameter);
            var disc = UiFactory.Img(d.root, "Disc", UiAssets.Circle, new Color(0.035f, 0.042f, 0.052f, 0.80f));
            UiFactory.Fill(disc.rectTransform);
            var rim = UiFactory.Img(d.root, "Rim", UiAssets.Ring, new Color(1f, 1f, 1f, 0.13f));
            UiFactory.Fill(rim.rectTransform);
            var inner = UiFactory.Img(d.root, "InnerRim", UiAssets.Ring, new Color(1f, 1f, 1f, 0.06f));
            UiFactory.Fill(inner.rectTransform, diameter * 0.17f, diameter * 0.17f, diameter * 0.17f, diameter * 0.17f);

            float outerR = d.radius - 9f;
            d.track = Arc(d.root, "Track", outerR, thick, new Color(1f, 1f, 1f, 0.09f));
            if (redFrom > 0f)
            {
                d.zone = Arc(d.root, "RedZone", outerR, thick, new Color(0.9f, 0.18f, 0.12f, 0.85f));
                d.zone.rangeFrom = Mathf.Clamp01(redFrom / vmax); d.zone.rangeTo = 1f;
            }
            d.fill = Arc(d.root, "Fill", outerR, thick, UiTheme.Accent);
            d.fill.fill = 0f;

            // ticks + numerals
            var ticks = UiFactory.NewRect("Ticks", d.root);
            UiFactory.Fill(ticks);
            var lines = ticks.gameObject.AddComponent<UiLines>(); lines.raycastTarget = false;
            float rTick = outerR - thick - 3f;
            for (float v = 0; v <= vmax + 0.01f; v += minor)
            {
                bool isMajor = Mathf.Abs(v / major - Mathf.Round(v / major)) < 0.001f;
                float a = (StartDeg + SweepDeg * Mathf.Clamp01(v / vmax)) * Mathf.Deg2Rad;
                Vector2 dir = new Vector2(Mathf.Sin(a), Mathf.Cos(a));
                float len = isMajor ? 13f : 6f;
                bool red = redFrom > 0f && v >= redFrom - 0.01f;
                Color c = red ? new Color(1f, 0.38f, 0.30f, 0.95f) : new Color(1f, 1f, 1f, isMajor ? 0.78f : 0.38f);
                lines.Add(dir * rTick, dir * (rTick - len), isMajor ? 2.2f : 1.3f, c);
                if (isMajor && labelFmt != null)
                {
                    var t = UiFactory.Label(d.root, labelFmt(v), labelSize, red ? new Color(1f, 0.45f, 0.38f) : UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Display);
                    t.rectTransform.anchoredPosition = dir * (rTick - len - labelSize * 0.95f);
                    t.rectTransform.sizeDelta = new Vector2(60, labelSize + 8);
                    d.labels.Add(t);
                }
            }
            lines.Apply();

            d.tipGlow = UiFactory.Img(d.root, "TipGlow", UiAssets.Circle, new Color(1f, 0.8f, 0.4f, 0.28f));
            d.tipGlow.rectTransform.sizeDelta = new Vector2(thick * 2.6f, thick * 2.6f);
            d.tip = UiFactory.Img(d.root, "Tip", UiAssets.Circle, Color.white);
            d.tip.rectTransform.sizeDelta = new Vector2(thick * 0.95f, thick * 0.95f);
            d.SetValue(0f);
            return d;
        }

        static UiArc Arc(Transform parent, string name, float outer, float thick, Color c)
        {
            var rt = UiFactory.NewRect(name, parent);
            UiFactory.Fill(rt);
            var a = rt.gameObject.AddComponent<UiArc>();
            a.raycastTarget = false; a.color = c;
            a.Configure(outer, thick, StartDeg, SweepDeg);
            return a;
        }

        public void SetValue(float value)
        {
            float f = Mathf.Clamp01(value / vmax);
            fill.SetFill(f);
            float a = (StartDeg + SweepDeg * f) * Mathf.Deg2Rad;
            Vector2 p = new Vector2(Mathf.Sin(a), Mathf.Cos(a)) * (radius - 9f - thickness * 0.5f);
            tip.rectTransform.anchoredPosition = p; tipGlow.rectTransform.anchoredPosition = p;
        }

        public void SetFillColor(Color c) { if (fill.color != c) fill.color = c; if (tipGlow.color.r != c.r || tipGlow.color.g != c.g) tipGlow.color = new Color(c.r, c.g, c.b, 0.3f); }
    }

    /// <summary>Small status lamp pill (AWD, diff locks, engine ...).</summary>
    public sealed class Lamp
    {
        public RectTransform root; public Image bg, dot; public Text text;
        Color cur;

        public static Lamp Create(Transform parent, string label, Vector2 size, int fontSize = 14)
        {
            var l = new Lamp();
            l.root = UiFactory.NewRect("Lamp_" + label, parent); l.root.sizeDelta = size;
            l.bg = UiFactory.Img(l.root, "Bg", UiAssets.Rounded(6), UiTheme.Bg, Image.Type.Sliced);
            UiFactory.Fill(l.bg.rectTransform);
            l.dot = UiFactory.Img(l.root, "Dot", UiAssets.Circle, UiTheme.LampOff);
            UiFactory.Place(l.dot.rectTransform, UiFactory.ML, new Vector2(9, 0), new Vector2(8, 8));
            l.text = UiFactory.Label(l.root, label, fontSize, UiTheme.TextFaint, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Fill(l.text.rectTransform, 21, 0, 4, 0);
            return l;
        }

        public void Set(bool on, Color onColor, string label = null)
        {
            Color c = on ? onColor : UiTheme.LampOff;
            if (c != cur)
            {
                cur = c;
                dot.color = on ? onColor : UiTheme.LampOff;
                text.color = on ? Color.Lerp(onColor, Color.white, 0.35f) : UiTheme.TextFaint;
                bg.color = on ? new Color(onColor.r * 0.28f, onColor.g * 0.28f, onColor.b * 0.28f, 0.88f) : UiTheme.Bg;
            }
            if (label != null && text.text != label) text.text = label;
        }
    }

    /// <summary>Tiny helper to avoid per-frame string garbage: only re-format when the quantised value changes.</summary>
    public sealed class CachedLabel
    {
        public readonly Text t; int key = int.MinValue; string lastStr;
        public CachedLabel(Text text) { t = text; }
        public void Set(int newKey, Func<string> make) { if (newKey == key) return; key = newKey; t.text = make(); }
        public void Set(string s) { if (ReferenceEquals(s, lastStr) || s == lastStr) return; lastStr = s; t.text = s; }
    }
}
