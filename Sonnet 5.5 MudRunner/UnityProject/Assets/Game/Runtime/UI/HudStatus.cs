using MudRunner.Ground;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>Bottom-left status card: vehicle name, fuel, hull damage, surface + sinkage readout and the inclinometer.</summary>
    public sealed class HudStatus : HudWidget
    {
        Text title, fuelLabel, fuelValue, fuelWarn, hullValue, surfaceName, surfaceSink, pitchText, rollText;
        Image fuelFill, hullFill, surfaceChip;
        RectTransform pitchCar, rollCar;
        Image[] pitchParts, rollParts;
        float pitchSm, rollSm;
        int lastFuel = -1, lastHull = -1, lastSink = -1, lastPitch = int.MinValue, lastRoll = int.MinValue;
        string lastSurface;
        public const float Width = 336f, Height = 280f;
        public string SurfaceString => surfaceName != null ? surfaceName.text : "";
        public string FuelString => fuelValue != null ? fuelValue.text : "";
        public string PitchString => pitchText != null ? pitchText.text : "";

        public override void Build(HudContext c, RectTransform parent)
        {
            var p = UiFactory.Panel(parent, "Status", UiTheme.Bg, 12, true, true);
            root = p.rt;
            UiFactory.Place(root, UiFactory.BL, new Vector2(UiTheme.Margin + 280f + 14f, UiTheme.Margin), new Vector2(Width, Height), UiFactory.BL);

            title = UiFactory.Label(root, "VEHICLE", 17, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(title.rectTransform, UiFactory.TL, new Vector2(16, -22), new Vector2(Width - 32, 24));

            // fuel
            var fl = UiFactory.Label(root, "FUEL", 13, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(fl.rectTransform, UiFactory.TL, new Vector2(16, -54), new Vector2(50, 18)); fuelLabel = fl;
            fuelFill = UiFactory.Bar(root, "FuelBar", new Vector2(176, 12), UiTheme.Good, out _);
            UiFactory.Place(((RectTransform)fuelFill.transform.parent), UiFactory.TL, new Vector2(66, -57), new Vector2(176, 12));
            fuelValue = UiFactory.Label(root, "0 L", 18, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Display);
            UiFactory.Place(fuelValue.rectTransform, UiFactory.TR, new Vector2(-16, -54), new Vector2(80, 22));
            fuelWarn = UiFactory.Label(root, "LOW FUEL", 12, UiTheme.Bad, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(fuelWarn.rectTransform, UiFactory.TL, new Vector2(68, -69), new Vector2(120, 14));

            // hull
            var hl = UiFactory.Label(root, "HULL", 13, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(hl.rectTransform, UiFactory.TL, new Vector2(16, -90), new Vector2(50, 18));
            hullFill = UiFactory.Bar(root, "HullBar", new Vector2(176, 12), UiTheme.Good, out _);
            UiFactory.Place(((RectTransform)hullFill.transform.parent), UiFactory.TL, new Vector2(66, -93), new Vector2(176, 12));
            hullValue = UiFactory.Label(root, "100%", 18, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Display);
            UiFactory.Place(hullValue.rectTransform, UiFactory.TR, new Vector2(-16, -90), new Vector2(80, 22));

            // surface
            surfaceChip = UiFactory.Img(root, "SurfaceChip", UiAssets.Circle, Color.gray);
            UiFactory.Place(surfaceChip.rectTransform, UiFactory.TL, new Vector2(18, -131), new Vector2(14, 14));
            surfaceName = UiFactory.Label(root, "Firm soil", 17, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(surfaceName.rectTransform, UiFactory.TL, new Vector2(40, -128), new Vector2(190, 22));
            surfaceSink = UiFactory.Label(root, "sink 0 cm", 15, UiTheme.TextDim, TextAnchor.MiddleRight, UiFont.Body);
            UiFactory.Place(surfaceSink.rectTransform, UiFactory.TR, new Vector2(-16, -128), new Vector2(110, 22));

            var sep = UiFactory.Rect(root, "Sep", new Color(1f, 1f, 1f, 0.10f));
            UiFactory.Place(sep.rectTransform, UiFactory.TC, new Vector2(0, -158), new Vector2(Width - 32, 1));

            BuildInclinometer(UiFactory.Place(UiFactory.NewRect("Pitch", root), UiFactory.BL, new Vector2(16, 12), new Vector2(150, 108)), true);
            BuildInclinometer(UiFactory.Place(UiFactory.NewRect("Roll", root), UiFactory.BR, new Vector2(-16, 12), new Vector2(150, 108), UiFactory.BR), false);
        }

        void BuildInclinometer(RectTransform box, bool side)
        {
            var bg = UiFactory.Img(box, "Bg", UiAssets.Rounded(8), new Color(1f, 1f, 1f, 0.05f), Image.Type.Sliced);
            UiFactory.Fill(bg.rectTransform);
            var cap = UiFactory.Label(box, side ? "PITCH" : "ROLL", 12, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(cap.rectTransform, UiFactory.TL, new Vector2(10, -13), new Vector2(60, 16));
            var val = UiFactory.Label(box, "0°", 22, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Display);
            UiFactory.Place(val.rectTransform, UiFactory.TR, new Vector2(-10, -14), new Vector2(70, 24));
            var horizon = UiFactory.Rect(box, "Horizon", new Color(1f, 1f, 1f, 0.30f));
            UiFactory.Place(horizon.rectTransform, UiFactory.BC, new Vector2(0, 22), new Vector2(120, 1.5f));
            var car = UiFactory.NewRect("Car", box);
            UiFactory.Place(car, UiFactory.BC, new Vector2(0, 22), new Vector2(10, 10), new Vector2(0.5f, 0f));
            Color body = new Color(0.92f, 0.94f, 0.96f, 0.95f);
            Image[] parts;
            if (side)
            {
                // side silhouette facing right
                var b = UiFactory.Img(car, "Body", UiAssets.Rounded(5), body, Image.Type.Sliced); UiFactory.Place(b.rectTransform, UiFactory.BC, new Vector2(0, 11), new Vector2(76, 18));
                var cab = UiFactory.Img(car, "Cab", UiAssets.Rounded(5), body, Image.Type.Sliced); UiFactory.Place(cab.rectTransform, UiFactory.BC, new Vector2(-8, 26), new Vector2(40, 15));
                var w1 = UiFactory.Img(car, "W1", UiAssets.Circle, new Color(0.15f, 0.16f, 0.18f, 1f)); UiFactory.Place(w1.rectTransform, UiFactory.BC, new Vector2(-24, 2), new Vector2(18, 18));
                var w2 = UiFactory.Img(car, "W2", UiAssets.Circle, new Color(0.15f, 0.16f, 0.18f, 1f)); UiFactory.Place(w2.rectTransform, UiFactory.BC, new Vector2(24, 2), new Vector2(18, 18));
                var hub1 = UiFactory.Img(car, "H1", UiAssets.Circle, body); UiFactory.Place(hub1.rectTransform, UiFactory.BC, new Vector2(-24, 11), new Vector2(6, 6));
                var hub2 = UiFactory.Img(car, "H2", UiAssets.Circle, body); UiFactory.Place(hub2.rectTransform, UiFactory.BC, new Vector2(24, 11), new Vector2(6, 6));
                var nose = UiFactory.Img(car, "Nose", UiAssets.Triangle, new Color(1f, 0.69f, 0.125f, 1f)); UiFactory.Place(nose.rectTransform, UiFactory.BC, new Vector2(43, 14), new Vector2(8, 8));
                nose.rectTransform.localRotation = Quaternion.Euler(0, 0, -90f);
                parts = new[] { b, cab };
                pitchCar = car; pitchText = val; pitchParts = parts;
            }
            else
            {
                var b = UiFactory.Img(car, "Body", UiAssets.Rounded(5), body, Image.Type.Sliced); UiFactory.Place(b.rectTransform, UiFactory.BC, new Vector2(0, 12), new Vector2(54, 24));
                var cab = UiFactory.Img(car, "Cab", UiAssets.Rounded(5), body, Image.Type.Sliced); UiFactory.Place(cab.rectTransform, UiFactory.BC, new Vector2(0, 30), new Vector2(40, 13));
                var w1 = UiFactory.Img(car, "W1", UiAssets.Rounded(3), new Color(0.15f, 0.16f, 0.18f, 1f), Image.Type.Sliced); UiFactory.Place(w1.rectTransform, UiFactory.BC, new Vector2(-33, 9), new Vector2(11, 20));
                var w2 = UiFactory.Img(car, "W2", UiAssets.Rounded(3), new Color(0.15f, 0.16f, 0.18f, 1f), Image.Type.Sliced); UiFactory.Place(w2.rectTransform, UiFactory.BC, new Vector2(33, 9), new Vector2(11, 20));
                parts = new[] { b, cab };
                rollCar = car; rollText = val; rollParts = parts;
            }
        }

        public override void Tick(HudContext c)
        {
            var v = c.v;
            if (v == null || v.def == null) return;
            if (title.text != v.def.displayName) title.text = v.def.displayName.ToUpperInvariant();

            // fuel
            float cap = Mathf.Max(1f, v.def.fuelCapacity);
            float fFrac = Mathf.Clamp01(v.fuel / cap);
            int fi = Mathf.CeilToInt(v.fuel);
            if (fi != lastFuel) { lastFuel = fi; fuelValue.text = fi + " L"; }
            bool low = fFrac < 0.15f, crit = fFrac < 0.06f;
            Color fc = crit ? UiTheme.Bad : low ? UiTheme.Warn : UiTheme.Good;
            if (low && Mathf.Repeat(c.time, 1f) > 0.55f) fc = new Color(fc.r, fc.g, fc.b, 0.4f);
            fuelFill.color = fc;
            UiFactory.SetBar(fuelFill, fFrac);
            UiFactory.SetActive(fuelWarn, low);
            if (low) fuelWarn.text = crit ? "FUEL CRITICAL" : "LOW FUEL";
            fuelWarn.color = crit ? UiTheme.Bad : UiTheme.Warn;

            // hull
            float dmg = Mathf.Clamp01(v.damage01);
            int hp = Mathf.RoundToInt((1f - dmg) * 100f);
            if (hp != lastHull) { lastHull = hp; hullValue.text = hp + "%"; }
            hullFill.color = UiTheme.HealthColor(1f - dmg);
            UiFactory.SetBar(hullFill, 1f - dmg);

            // surface
            var gs = GroundService.Instance;
            if (gs != null && gs.Map != null)
            {
                Vector3 p = v.transform.position;
                var soil = gs.SampleSoil(p.x, p.z);
                var sp = SurfaceDatabase.Table[(int)soil.dominant];
                string nm = sp.name;
                if (nm != lastSurface) { lastSurface = nm; surfaceName.text = nm; var tint = sp.tint; surfaceChip.color = Color.Lerp(tint, Color.white, 0.18f); }
                bool inWater = v.water != null && v.water.inWater;
                int sink = Mathf.RoundToInt(v.maxSinkage * 100f);
                if (sink != lastSink) { lastSink = sink; surfaceSink.text = "sink " + sink + " cm"; }
                surfaceSink.color = sink > 25 ? UiTheme.Bad : sink > 12 ? UiTheme.Warn : UiTheme.TextDim;
                if (inWater) { surfaceName.text = "Water " + (v.waterDepthAtVehicle * 100f).ToString("0") + " cm"; lastSurface = null; surfaceChip.color = UiTheme.Info; }
            }

            // inclinometer
            Vector3 f = v.transform.forward, r = v.transform.right;
            float pitch = Mathf.Asin(Mathf.Clamp(f.y, -1f, 1f)) * Mathf.Rad2Deg;
            float roll = Mathf.Asin(Mathf.Clamp(-r.y, -1f, 1f)) * Mathf.Rad2Deg;
            float k = 1f - Mathf.Exp(-12f * c.dt);
            pitchSm = Mathf.Lerp(pitchSm, pitch, k); rollSm = Mathf.Lerp(rollSm, roll, k);
            pitchCar.localRotation = Quaternion.Euler(0, 0, pitchSm);
            rollCar.localRotation = Quaternion.Euler(0, 0, -rollSm);
            int pi = Mathf.RoundToInt(pitchSm), ri = Mathf.RoundToInt(rollSm);
            if (pi != lastPitch) { lastPitch = pi; pitchText.text = pi + "°"; }
            if (ri != lastRoll) { lastRoll = ri; rollText.text = ri + "°"; }
            Tint(pitchText, pitchParts, Mathf.Abs(pitchSm), 30f, 42f);
            Tint(rollText, rollParts, Mathf.Abs(rollSm), 25f, 38f);
        }

        static void Tint(Text t, Image[] parts, float a, float warn, float bad)
        {
            Color col = a > bad ? UiTheme.Bad : a > warn ? UiTheme.Warn : UiTheme.Text;
            t.color = col;
            Color body = a > bad ? UiTheme.Bad : a > warn ? UiTheme.Warn : new Color(0.92f, 0.94f, 0.96f, 0.95f);
            for (int i = 0; i < parts.Length; i++) parts[i].color = body;
        }
    }
}
