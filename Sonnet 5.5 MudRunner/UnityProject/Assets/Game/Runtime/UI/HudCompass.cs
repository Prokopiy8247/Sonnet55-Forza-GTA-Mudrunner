using System.Collections.Generic;
using MudRunner.Atmosphere;
using MudRunner.Game;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>Top-centre compass strip with degree ticks, cardinal letters, objective / waypoint / site markers, trip + clock chips.</summary>
    public sealed class HudCompass : HudWidget
    {
        const float StripW = 700f, StripH = 44f, SpanDeg = 180f;
        static readonly string[] Cardinals = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" };

        UiLines ticks;
        readonly List<Text> labelPool = new List<Text>();
        int labelsUsed;
        RectTransform strip;
        Text headingText, tripText, clockText, weatherText;
        Image centerMark, fadeL, fadeR;

        sealed class MarkerWidget
        {
            public RectTransform rt; public Image icon; public Text name, dist;
        }
        readonly List<MarkerWidget> markerPool = new List<MarkerWidget>();
        struct Cand { public string name; public Vector3 pos; public Color color; public Sprite sprite; public float size; public bool important; public float dist, delta, bearing; }
        readonly List<Cand> cands = new List<Cand>(48);
        float trip; Vehicle lastVeh; Vector3 lastPos;
        public string HeadingString => headingText != null ? headingText.text : "";
        public int MarkersShown { get; private set; }

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("Compass", parent);
            UiFactory.Place(root, UiFactory.TC, new Vector2(0, -UiTheme.Margin + 6), new Vector2(StripW + 340f, 104f), UiFactory.TC);

            var bg = UiFactory.Panel(root, "StripBg", new Color(0.04f, 0.047f, 0.056f, 0.74f), 10, true, true);
            UiFactory.Place(bg.rt, UiFactory.TC, Vector2.zero, new Vector2(StripW, StripH), UiFactory.TC);

            strip = UiFactory.NewRect("Strip", bg.rt);
            UiFactory.Fill(strip, 2, 0, 2, 0);
            var stripImg = strip.gameObject.AddComponent<Image>(); stripImg.sprite = UiAssets.White; stripImg.color = Color.white;
            var stripMask = strip.gameObject.AddComponent<Mask>(); stripMask.showMaskGraphic = false;      // stencil mask (RectMask2D has a bug with deactivated MaskableGraphic subclasses)
            var linesRt = UiFactory.NewRect("Ticks", strip);
            UiFactory.Fill(linesRt);
            ticks = linesRt.gameObject.AddComponent<UiLines>(); ticks.raycastTarget = false;

            // edge fades
            var fl = UiFactory.Img(strip, "FadeL", UiAssets.Gradient, new Color(0.04f, 0.047f, 0.056f, 0.98f));
            UiFactory.Place(fl.rectTransform, UiFactory.ML, new Vector2(0, 0), new Vector2(StripH, 110f), UiFactory.ML);
            fl.rectTransform.localRotation = Quaternion.identity;
            SetupHFade(fl, true); fadeL = fl;
            var fr = UiFactory.Img(strip, "FadeR", UiAssets.Gradient, new Color(0.04f, 0.047f, 0.056f, 0.98f));
            SetupHFade(fr, false); fadeR = fr;

            // centre marker + heading chip
            centerMark = UiFactory.Img(bg.rt, "Center", UiAssets.Triangle, UiTheme.Accent);
            UiFactory.Place(centerMark.rectTransform, UiFactory.TC, new Vector2(0, 3), new Vector2(14, 10), UiFactory.TC);
            centerMark.rectTransform.localRotation = Quaternion.Euler(0, 0, 180f);
            var chip = UiFactory.Panel(root, "HeadingChip", new Color(0.04f, 0.047f, 0.056f, 0.92f), 8, true, false);
            UiFactory.Place(chip.rt, UiFactory.TC, new Vector2(0, -StripH + 4), new Vector2(64, 26), UiFactory.TC);
            headingText = UiFactory.Label(chip.rt, "000°", 19, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Fill(headingText.rectTransform);

            // trip (left) and clock (right)
            var tp = UiFactory.Panel(root, "Trip", new Color(0.04f, 0.047f, 0.056f, 0.74f), 10, true, false);
            UiFactory.Place(tp.rt, UiFactory.TC, new Vector2(-(StripW * 0.5f + 12f), 0), new Vector2(122, StripH), UiFactory.TR);
            var tcap = UiFactory.Label(tp.rt, "TRIP", 11, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Bold);
            UiFactory.Place(tcap.rectTransform, UiFactory.TC, new Vector2(0, -7), new Vector2(110, 14));
            tripText = UiFactory.Label(tp.rt, "0.00 km", 19, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Place(tripText.rectTransform, UiFactory.BC, new Vector2(0, 14), new Vector2(120, 24));

            var ck = UiFactory.Panel(root, "Clock", new Color(0.04f, 0.047f, 0.056f, 0.74f), 10, true, false);
            UiFactory.Place(ck.rt, UiFactory.TC, new Vector2(StripW * 0.5f + 12f, 0), new Vector2(122, StripH), UiFactory.TL);
            clockText = UiFactory.Label(ck.rt, "15:30", 21, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Place(clockText.rectTransform, UiFactory.TC, new Vector2(0, -13), new Vector2(120, 24));
            weatherText = UiFactory.Label(ck.rt, "CLEAR", 11, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Bold);
            UiFactory.Place(weatherText.rectTransform, UiFactory.BC, new Vector2(0, 8), new Vector2(120, 14));
        }

        static void SetupHFade(Image img, bool left)
        {
            var rt = img.rectTransform;
            rt.anchorMin = rt.anchorMax = new Vector2(left ? 0f : 1f, 0.5f);
            rt.pivot = new Vector2(left ? 0f : 1f, 0.5f);
            rt.anchoredPosition = Vector2.zero;
            // sprite gradient runs bottom->top; rotate so that opaque side faces the outside edge
            rt.sizeDelta = new Vector2(StripH, 90f);       // pre-rotation (w = strip height, h = fade width)
            rt.localRotation = Quaternion.Euler(0, 0, left ? 90f : -90f);
            // after rotation the box occupies 90 wide x StripH tall; re-anchor accordingly
            rt.anchoredPosition = new Vector2(left ? 45f : -45f, 0f);
            rt.pivot = new Vector2(0.5f, 0.5f);
            rt.anchorMin = rt.anchorMax = new Vector2(left ? 0f : 1f, 0.5f);
        }

        Text GetLabel(int i)
        {
            while (labelPool.Count <= i)
            {
                var t = UiFactory.Label(strip, "N", 20, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display);
                t.rectTransform.sizeDelta = new Vector2(60, 24);
                labelPool.Add(t);
                if (fadeL != null) { fadeL.transform.SetAsLastSibling(); fadeR.transform.SetAsLastSibling(); }
            }
            return labelPool[i];
        }

        MarkerWidget GetMarker(int i)
        {
            while (markerPool.Count <= i)
            {
                var m = new MarkerWidget();
                m.rt = UiFactory.NewRect("Marker" + markerPool.Count, root);
                m.rt.anchorMin = m.rt.anchorMax = UiFactory.TC; m.rt.pivot = UiFactory.TC; m.rt.sizeDelta = new Vector2(120, 50);
                m.icon = UiFactory.Img(m.rt, "Icon", UiAssets.Diamond, UiTheme.Accent);
                UiFactory.Place(m.icon.rectTransform, UiFactory.TC, Vector2.zero, new Vector2(14, 14));
                m.name = UiFactory.Label(m.rt, "", 13, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Bold, shadow: true);
                UiFactory.Place(m.name.rectTransform, UiFactory.TC, new Vector2(0, -16), new Vector2(120, 16));
                m.dist = UiFactory.Label(m.rt, "", 12, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Body, shadow: true);
                UiFactory.Place(m.dist.rectTransform, UiFactory.TC, new Vector2(0, -31), new Vector2(120, 14));
                markerPool.Add(m);
            }
            return markerPool[i];
        }

        public override void Tick(HudContext c)
        {
            var cam = c.cam; var v = c.v;
            if (cam == null || v == null) return;
            float heading = cam.transform.eulerAngles.y;
            float ppd = StripW / SpanDeg;

            // ---- ticks + labels
            ticks.Clear();
            labelsUsed = 0;
            float start = Mathf.Floor((heading - SpanDeg * 0.5f - 6f) / 5f) * 5f;
            float end = heading + SpanDeg * 0.5f + 6f;
            for (float a = start; a <= end; a += 5f)
            {
                int ai = Mathf.RoundToInt(Mathf.Repeat(a, 360f)) % 360;
                float x = (a - heading) * ppd;
                bool card = ai % 45 == 0, mid = ai % 15 == 0;
                float h = card ? 15f : mid ? 10f : 5f;
                Color col = card ? new Color(1f, 1f, 1f, 0.85f) : new Color(1f, 1f, 1f, mid ? 0.55f : 0.30f);
                ticks.Add(new Vector2(x, StripH * 0.5f - 0f), new Vector2(x, StripH * 0.5f - h), card ? 2.2f : 1.4f, col);
                // note: strip origin is its centre (rect centre) -> lines are expressed in the same space
                if (card || mid)
                {
                    var t = GetLabel(labelsUsed++);
                    UiFactory.SetActive(t, true);
                    if (card)
                    {
                        string s = Cardinals[ai / 45];
                        if (t.text != s) t.text = s;
                        bool north = ai == 0;
                        t.color = north ? UiTheme.Accent : UiTheme.Text;
                        t.fontSize = s.Length == 1 ? 22 : 17;
                    }
                    else
                    {
                        string s = ai.ToString();
                        if (t.text != s) t.text = s;
                        t.color = UiTheme.TextDim; t.fontSize = 13;
                    }
                    t.rectTransform.anchoredPosition = new Vector2(x, card ? -4f : -8f);
                }
            }
            for (int i = labelsUsed; i < labelPool.Count; i++) UiFactory.SetActive(labelPool[i], false);
            ticks.Apply();

            int hd = Mathf.RoundToInt(Mathf.Repeat(heading, 360f)) % 360;
            headingText.text = hd.ToString("000") + "°";

            // ---- markers
            BuildCandidates(c, heading);
            int used = 0;
            float lastX = -9999f;
            for (int i = 0; i < cands.Count && used < 9; i++)
            {
                var cd = cands[i];
                float dlt = cd.delta;
                bool offscreen = Mathf.Abs(dlt) > SpanDeg * 0.5f - 4f;
                if (offscreen && !cd.important) continue;
                float x = Mathf.Clamp(dlt, -SpanDeg * 0.5f + 5f, SpanDeg * 0.5f - 5f) * ppd;
                bool labelOk = Mathf.Abs(x - lastX) > 78f || cd.important;
                var m = GetMarker(used++);
                UiFactory.SetActive(m.rt, true);
                m.rt.anchoredPosition = new Vector2(x, -StripH - 34f);
                m.icon.sprite = offscreen ? UiAssets.Chevron : cd.sprite;
                m.icon.rectTransform.sizeDelta = new Vector2(cd.size, cd.size);
                m.icon.rectTransform.localRotation = offscreen ? Quaternion.Euler(0, 0, dlt > 0 ? -90f : 90f) : Quaternion.identity;
                m.icon.color = cd.color;
                m.name.text = labelOk ? cd.name : "";
                m.name.color = cd.important ? cd.color : UiTheme.Text;
                m.dist.text = labelOk ? FormatDist(cd.dist) : "";
                if (labelOk) lastX = x;
            }
            MarkersShown = used;
            for (int i = used; i < markerPool.Count; i++) UiFactory.SetActive(markerPool[i].rt, false);

            // ---- trip / clock
            if (v != lastVeh) { lastVeh = v; trip = 0f; lastPos = v.transform.position; }
            else { trip += Vector3.Distance(v.transform.position, lastPos); lastPos = v.transform.position; }
            tripText.text = (trip / 1000f).ToString("0.00") + " km";
            var atm = AtmosphereController.Instance;
            if (atm != null)
            {
                int hh = Mathf.FloorToInt(atm.hour), mm = Mathf.FloorToInt((atm.hour - hh) * 60f);
                clockText.text = hh.ToString("00") + ":" + mm.ToString("00");
                weatherText.text = atm.rain > 0.05f ? "RAIN " + Mathf.RoundToInt(atm.rain * 100f) + "%" : (atm.IsNight ? "NIGHT" : "CLEAR");
            }
            else { clockText.text = "--:--"; weatherText.text = ""; }
        }

        void BuildCandidates(HudContext c, float heading)
        {
            cands.Clear();
            Vector3 p = c.v.transform.position;
            var om = ObjectiveManager.Instance;
            if (om != null && om.hasTarget && !om.completed)
                Add(p, heading, string.IsNullOrEmpty(om.title) ? "Objective" : om.title, om.targetPosition, UiTheme.Accent, UiAssets.Diamond, 18f, true);
            var wp = MapMarkers.UserWaypoint;
            if (wp != null) Add(p, heading, "Waypoint", wp.position, UiTheme.Info, UiAssets.Diamond, 14f, true);
            var gm = c.gm;
            if (gm != null && gm.World != null)
            {
                var pts = gm.World.points;
                for (int i = 0; i < pts.Count; i++)
                {
                    if (IsSpawnLike(pts[i].name)) continue;
                    Add(p, heading, pts[i].name, pts[i].position, new Color(0.9f, 0.93f, 0.96f, 0.95f), UiAssets.Circle, 9f, false);
                }
            }
            var mk = MapMarkers.Markers;
            for (int i = 0; i < mk.Count; i++)
            {
                if (!mk[i].showOnCompass) continue;
                Color col = mk[i].kind == MapMarkers.Kind.Garage ? UiTheme.Good : mk[i].kind == MapMarkers.Kind.Fuel ? UiTheme.Warn : mk[i].kind == MapMarkers.Kind.Danger ? UiTheme.Bad : new Color(0.9f, 0.93f, 0.96f, 0.95f);
                Add(p, heading, mk[i].name, mk[i].position, col, mk[i].kind == MapMarkers.Kind.Site ? UiAssets.Circle : UiAssets.Triangle, 10f, false);
            }
            // nearest first (important first)
            cands.Sort(CandCompare);
        }

        static readonly System.Comparison<Cand> CandCompare = (a, b) => { if (a.important != b.important) return a.important ? -1 : 1; return a.dist.CompareTo(b.dist); };

        static bool IsSpawnLike(string n) { return n != null && (n.IndexOf("spawn", System.StringComparison.OrdinalIgnoreCase) >= 0); }

        void Add(Vector3 from, float heading, string name, Vector3 pos, Color col, Sprite sp, float size, bool important)
        {
            Vector3 d = pos - from; d.y = 0f;
            float dist = d.magnitude;
            if (dist < 2f && !important) return;
            float bearing = Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg;
            cands.Add(new Cand { name = name, pos = pos, color = col, sprite = sp, size = size, important = important, dist = dist, bearing = bearing, delta = Mathf.DeltaAngle(heading, bearing) });
        }

        public static string FormatDist(float m)
        {
            if (m >= 1000f) return (m / 1000f).ToString("0.0") + " km";
            return Mathf.RoundToInt(m) + " m";
        }
    }
}
