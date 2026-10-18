using MudRunner.Game;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>Bottom-right instrument cluster: speedometer (arc + digital), tachometer with redline, gear/range, indicator lamps.</summary>
    public sealed class HudGauges : HudWidget
    {
        Dial speedDial, rpmDial;
        Text speedText, speedUnit, gearText, gearSub, rpmText, rpmUnit, engineState;
        Image gearPill;
        Lamp lAwd, lDiffF, lDiffC, lDiffR, lEngine, lPark, lLights;
        int lastSpeed = -1, lastRpm = -1, lastDialMax;
        string lastGear;
        Vehicle lastVehicle;
        float speedMax = 120f, rpmMax = 5000f;
        bool imperial;

        // read-outs for tests / other systems
        public string SpeedString => speedText != null ? speedText.text : "";
        public string RpmString => rpmText != null ? rpmText.text : "";
        public string GearString => gearText != null ? gearText.text : "";
        public float SpeedDialMax => speedMax;
        public Dial SpeedDial => speedDial;
        public Dial RpmDial => rpmDial;

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("Gauges", parent);
            UiFactory.Place(root, UiFactory.BR, new Vector2(-UiTheme.Margin, UiTheme.Margin), new Vector2(560, 350), UiFactory.BR);
            imperial = UiSettings.Imperial;
            BuildDials(imperial ? 75f : 120f, 5000f, 4000f);

            // gear / range pill inside the speed dial's open bottom
            gearPill = UiFactory.Img(speedDial.root, "GearPill", UiAssets.Rounded(12), new Color(0f, 0f, 0f, 0.55f), Image.Type.Sliced);
            UiFactory.Place(gearPill.rectTransform, UiFactory.C, new Vector2(0, -104), new Vector2(128, 34));
            gearText = UiFactory.Label(gearPill.transform, "1 | HIGH", 24, UiTheme.Accent, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Fill(gearText.rectTransform);
            gearSub = UiFactory.Label(speedDial.root, "AUTO", 13, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Bold);
            UiFactory.Place(gearSub.rectTransform, UiFactory.C, new Vector2(0, -128), new Vector2(120, 16));

            // lamps row above the dials
            float lw = 76f, gap = 5f, h = 28f;
            string[] names = { "AWD", "DIFF F", "DIFF C", "DIFF R", "ENGINE", "PARK", "LIGHTS" };
            var lamps = new Lamp[names.Length];
            float total = names.Length * lw + (names.Length - 1) * gap;
            for (int i = 0; i < names.Length; i++)
            {
                lamps[i] = Lamp.Create(root, names[i], new Vector2(lw, h), 13);
                UiFactory.Place(lamps[i].root, UiFactory.BR, new Vector2(-(total - (i + 1) * lw - i * gap) , 312), new Vector2(lw, h), UiFactory.BR);
                lamps[i].root.anchoredPosition = new Vector2(-(names.Length - 1 - i) * (lw + gap), 312);
            }
            lAwd = lamps[0]; lDiffF = lamps[1]; lDiffC = lamps[2]; lDiffR = lamps[3]; lEngine = lamps[4]; lPark = lamps[5]; lLights = lamps[6];
        }

        void BuildDials(float sMax, float rMax, float redline)
        {
            if (speedDial != null) Object.Destroy(speedDial.root.gameObject);
            if (rpmDial != null) Object.Destroy(rpmDial.root.gameObject);
            speedMax = sMax; rpmMax = rMax;
            speedDial = Dial.Create(root, "SpeedDial", 304f, 15f, sMax, imperial ? 10f : 20f, imperial ? 5f : 10f, v => ((int)v).ToString(), 16);
            UiFactory.Place(speedDial.root, UiFactory.BR, new Vector2(-152f, 152f), new Vector2(304, 304), UiFactory.C);
            speedDial.root.anchorMin = speedDial.root.anchorMax = UiFactory.BR; speedDial.root.pivot = UiFactory.C;
            speedDial.fill.SetGradient(new Color(1f, 0.74f, 0.2f), new Color(1f, 0.42f, 0.12f));
            speedText = UiFactory.Label(speedDial.root, "0", 88, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display, shadow: true);
            UiFactory.Place(speedText.rectTransform, UiFactory.C, new Vector2(0, 8), new Vector2(200, 100));
            speedUnit = UiFactory.Label(speedDial.root, imperial ? "mph" : "km/h", 20, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Body);
            UiFactory.Place(speedUnit.rectTransform, UiFactory.C, new Vector2(0, -48), new Vector2(120, 24));

            rpmDial = Dial.Create(root, "RpmDial", 214f, 12f, rMax, 1000f, 500f, v => (v / 1000f).ToString("0"), 15, redline);
            rpmDial.root.anchorMin = rpmDial.root.anchorMax = UiFactory.BR; rpmDial.root.pivot = UiFactory.C;
            rpmDial.root.anchoredPosition = new Vector2(-304f - 8f - 107f, 107f);
            rpmDial.root.sizeDelta = new Vector2(214, 214);
            rpmDial.fill.color = new Color(0.82f, 0.92f, 1f);
            rpmText = UiFactory.Label(rpmDial.root, "0", 40, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display, shadow: true);
            UiFactory.Place(rpmText.rectTransform, UiFactory.C, new Vector2(0, 4), new Vector2(150, 50));
            rpmUnit = UiFactory.Label(rpmDial.root, "x1000 rpm", 14, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Body);
            UiFactory.Place(rpmUnit.rectTransform, UiFactory.C, new Vector2(0, -30), new Vector2(120, 18));
            engineState = UiFactory.Label(rpmDial.root, "", 18, UiTheme.Bad, TextAnchor.MiddleCenter, UiFont.Bold, shadow: true);
            UiFactory.Place(engineState.rectTransform, UiFactory.C, new Vector2(0, -66), new Vector2(150, 22));
            // keep gear pill above rpm dial siblings
            if (gearPill != null) { gearPill.transform.SetParent(speedDial.root, false); gearSub.transform.SetParent(speedDial.root, false); }
        }

        public override void Tick(HudContext c)
        {
            var v = c.v;
            if (v == null || v.def == null || v.drivetrain == null) return;
            var d = v.drivetrain;
            if (v != lastVehicle)
            {
                lastVehicle = v;
                float sMax = v.def.mass > 7000f ? 100f : 120f;
                if (imperial) sMax = Mathf.Round(sMax * 0.621371f / 5f) * 5f;
                float rMax = Mathf.Max(3000f, Mathf.Ceil(v.def.redlineRpm * 1.08f / 1000f) * 1000f);
                if (!Mathf.Approximately(sMax, speedMax) || !Mathf.Approximately(rMax, rpmMax) || rpmDial.zone == null || Mathf.Abs(rpmDial.zone.rangeFrom - v.def.redlineRpm / rMax) > 0.01f)
                {
                    BuildDials(sMax, rMax, v.def.redlineRpm);
                }
                lastGear = null; lastSpeed = -1; lastRpm = -1;
            }

            // ---- speed
            if (imperial != UiSettings.Imperial)
            {
                imperial = UiSettings.Imperial;
                float sm = v.def.mass > 7000f ? 100f : 120f;
                BuildDials(imperial ? Mathf.Round(sm * 0.621371f / 5f) * 5f : sm, rpmMax, v.def.redlineRpm);
                lastSpeed = -1;
            }
            float kmh = v.speedKmh * (imperial ? 0.621371f : 1f);
            int sp = Mathf.RoundToInt(kmh);
            if (sp != lastSpeed) { lastSpeed = sp; speedText.text = sp.ToString(); }
            speedDial.SetValue(kmh);

            // ---- rpm
            float rpm = d.rpm;
            bool engineRunning = d.engineOn;
            int rp = Mathf.RoundToInt(rpm / 10f);
            if (rp != lastRpm) { lastRpm = rp; rpmText.text = (rp * 10).ToString(); }
            rpmDial.SetValue(rpm);
            float redFrac = rpm / Mathf.Max(1f, v.def.redlineRpm);
            Color rc = redFrac > 1.0f ? UiTheme.Bad : redFrac > 0.86f ? UiTheme.Warn : new Color(0.82f, 0.92f, 1f);
            rpmDial.SetFillColor(rc);
            rpmText.color = redFrac > 1.0f ? UiTheme.Bad : UiTheme.Text;

            bool flooded = v.water != null && v.water.engineFlooded;
            if (!engineRunning)
            {
                engineState.text = flooded ? "FLOODED" : (v.fuel <= 0.01f ? "NO FUEL" : "ENGINE OFF [I]");
                engineState.color = Mathf.Repeat(c.time, 1f) < 0.62f ? UiTheme.Bad : new Color(UiTheme.Bad.r, UiTheme.Bad.g, UiTheme.Bad.b, 0.35f);
            }
            else if (engineState.text.Length != 0) engineState.text = "";

            // ---- gear / range
            string range = v.def.hasLowRange ? (d.lowRange ? "LOW" : "HIGH") : "";
            string gear = d.GearLabel;
            string g = range.Length > 0 ? gear + " | " + range : gear;
            if (g != lastGear)
            {
                lastGear = g; gearText.text = g;
                gearText.color = d.lowRange && v.def.hasLowRange ? UiTheme.Warn : UiTheme.Accent;
            }
            string mode = d.mode == GearMode.Automatic ? "AUTO" : "MANUAL";
            if (gearSub.text != mode) gearSub.text = mode;

            // ---- lamps
            bool allDriven = true;
            for (int i = 0; i < v.def.axles.Length; i++) if (!d.AxleDriven(i)) { allDriven = false; break; }
            lAwd.Set(allDriven && v.def.axles.Length > 1, UiTheme.Good, v.def.axles.Length >= 3 ? "6x6" : "AWD");
            lDiffF.Set(d.axleLock.Length > 0 && d.axleLock[0], UiTheme.Warn);
            bool rearLock = false; for (int i = 1; i < d.axleLock.Length; i++) rearLock |= d.axleLock[i];
            lDiffR.Set(rearLock, UiTheme.Warn);
            lDiffC.Set(d.centreLock && v.def.hasCentreDiffLock, UiTheme.Warn);
            if (flooded) lEngine.Set(Mathf.Repeat(c.time, 0.8f) < 0.5f, UiTheme.Bad, "FLOODED");
            else if (engineRunning) lEngine.Set(true, UiTheme.Good, "ENGINE");
            else lEngine.Set(true, UiTheme.Bad, "ENG OFF");
            lPark.Set(v.input.handbrake, UiTheme.Bad);
            var hl = v.GetComponent<VehicleHeadlights>();
            lLights.Set(hl != null && hl.On, UiTheme.Info);
        }
    }
}
