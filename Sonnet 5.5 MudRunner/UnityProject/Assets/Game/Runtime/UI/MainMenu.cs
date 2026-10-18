using System;
using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Objectives;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>
    /// Main menu shown over the live world with a slow showcase camera around the selected vehicle:
    /// free drive (wilderness / proving ground), scenario list, vehicle choice with stat block, quit.
    /// </summary>
    public sealed class MainMenu : UiMenu
    {
        public enum Page { Home, Vehicles, Scenarios }
        public Page CurrentPage { get; private set; } = Page.Home;

        public Action<WorldKind, ScenarioDef> onStart;
        public Action<string> onPreviewVehicle;

        RectTransform home, vehiclePanel, scenarioPanel;
        UiButton btnVehicle;
        readonly UiButton[] vehicleTabs = new UiButton[3];
        Text vName, vDesc, vDrive;
        readonly List<Text> statValues = new List<Text>();
        readonly List<Image> statBars = new List<Image>();
        readonly List<GameObject> scenarioCards = new List<GameObject>();
        readonly List<UiButton> scenarioButtons = new List<UiButton>();
        Text sTitle, sDesc, sBrief, sMeta;
        UiButton startScenario;
        ScenarioDef pickedScenario;
        VehicleStats maxStats;

        public override void Build(RectTransform parent)
        {
            root = UiFactory.NewRect("MainMenu", parent);
            UiFactory.Fill(root);

            // readability shades (left and bottom)
            var shade = UiFactory.Img(root, "ShadeLeft", UiAssets.Gradient, new Color(0.02f, 0.025f, 0.03f, 0.94f));
            shade.rectTransform.anchorMin = shade.rectTransform.anchorMax = new Vector2(0f, 0.5f);
            shade.rectTransform.pivot = new Vector2(0.5f, 0.5f);
            shade.rectTransform.sizeDelta = new Vector2(1500f, 1300f);                // pre-rotation: w = shade height, h = shade width
            shade.rectTransform.anchoredPosition = new Vector2(650f, 0f);
            shade.rectTransform.localRotation = Quaternion.Euler(0, 0, 90f);          // opaque side to the left
            var bottom = UiFactory.Img(root, "ShadeBottom", UiAssets.Gradient, new Color(0f, 0f, 0f, 0.55f));
            bottom.rectTransform.anchorMin = new Vector2(0, 0); bottom.rectTransform.anchorMax = new Vector2(1, 0);
            bottom.rectTransform.pivot = new Vector2(0.5f, 0.5f); bottom.rectTransform.sizeDelta = new Vector2(0, 260); bottom.rectTransform.anchoredPosition = new Vector2(0, 130);
            bottom.rectTransform.localScale = new Vector3(1, -1, 1);

            BuildHome();
            BuildVehiclePanel();
            BuildScenarioPanel();

            var ver = UiFactory.Label(root, "Prototype build • Unity 6 • custom soil physics", 14, UiTheme.TextFaint, TextAnchor.MiddleLeft, UiFont.Body);
            UiFactory.Place(ver.rectTransform, UiFactory.BL, new Vector2(110, 40), new Vector2(600, 20));
            var hint = UiFactory.Label(root, "Esc  back", 14, UiTheme.TextFaint, TextAnchor.MiddleRight, UiFont.Body);
            UiFactory.Place(hint.rectTransform, UiFactory.BR, new Vector2(-50, 40), new Vector2(300, 20));
            root.gameObject.SetActive(false);
            ShowPage(Page.Home);
        }

        // ------------------------------------------------------------------ home

        UiButton MenuButton(Transform parent, string title, string sub, Action click, float y, bool primary = false, bool danger = false)
        {
            var b = UiFactory.Button(parent, title, click, new Vector2(470, 66), danger ? BtnStyle.Danger : primary ? BtnStyle.Primary : BtnStyle.Normal, 22, UiFont.Display);
            UiFactory.Place((RectTransform)b.transform, UiFactory.TL, new Vector2(0, -y), new Vector2(470, 66));
            b.label.alignment = TextAnchor.MiddleLeft;
            UiFactory.Fill(b.label.rectTransform, 24, 0, 8, 0);
            b.label.supportRichText = true;
            string subCol = primary ? "#3A2A08" : "#9AA6B2";
            b.label.text = title + (string.IsNullOrEmpty(sub) ? "" : "\n<size=14><color=" + subCol + ">" + sub + "</color></size>");
            b.alwaysAccent = !primary; b.accent.enabled = !primary;
            return b;
        }

        void BuildHome()
        {
            home = UiFactory.NewRect("Home", root);
            UiFactory.Place(home, UiFactory.TL, new Vector2(110, -130), new Vector2(520, 760), UiFactory.TL);
            var t = UiFactory.Label(home, "MUD <color=#FFB020>RUNNER</color>", 104, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Display, shadow: true);
            UiFactory.Place(t.rectTransform, UiFactory.TL, new Vector2(0, 0), new Vector2(700, 120));
            var bar = UiFactory.Rect(home, "Bar", UiTheme.Accent);
            UiFactory.Place(bar.rectTransform, UiFactory.TL, new Vector2(4, -132), new Vector2(120, 5));
            var sub = UiFactory.Label(home, "OFF-ROAD MUD DRIVING SIMULATION", 18, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(sub.rectTransform, UiFactory.TL, new Vector2(4, -158), new Vector2(560, 24));

            float y = 232f;
            MenuButton(home, "FREE DRIVE — WILDERNESS", "1.5 km of forest, river fords and swamp", () => onStart?.Invoke(WorldKind.Wilderness, null), y, true); y += 76f;
            MenuButton(home, "FREE DRIVE — PROVING GROUND", "Mud pits, steep hill, ford and test lanes", () => onStart?.Invoke(WorldKind.ProvingGround, null), y); y += 76f;
            MenuButton(home, "SCENARIOS", "Missions with objectives and par times", () => ShowPage(Page.Scenarios), y); y += 76f;
            btnVehicle = MenuButton(home, "VEHICLE", "", () => ShowPage(Page.Vehicles), y); y += 76f;
            MenuButton(home, "QUIT", "", UiRoot.QuitGame, y + 14f, false, true);
        }

        // ------------------------------------------------------------------ vehicle page

        static readonly string[] StatNames = { "MASS", "ENGINE POWER", "PEAK TORQUE", "TYRES", "WINCH", "FORDING DEPTH", "FUEL TANK" };

        void BuildVehiclePanel()
        {
            var p = UiFactory.Panel(root, "VehiclePanel", new Color(0.035f, 0.041f, 0.049f, 0.90f), 16, true, true);
            vehiclePanel = p.rt;
            UiFactory.Place(vehiclePanel, UiFactory.MR, new Vector2(-70, 0), new Vector2(720, 740), UiFactory.MR);
            var h = UiFactory.Label(vehiclePanel, "VEHICLE", 14, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(h.rectTransform, UiFactory.TL, new Vector2(30, -30), new Vector2(200, 18));
            string[] tabNames = { "SCOUT", "UTILITY", "HAULER" };
            float tw = (720 - 60 - 16) / 3f;
            for (int i = 0; i < 3; i++)
            {
                int idx = i;
                vehicleTabs[i] = UiFactory.Button(vehiclePanel, tabNames[i], () => PickVehicle(GameManager.VehicleKeys[idx]), new Vector2(tw, 46), BtnStyle.Segment, 18, UiFont.Display);
                UiFactory.Place((RectTransform)vehicleTabs[i].transform, UiFactory.TL, new Vector2(30 + i * (tw + 8f), -54), new Vector2(tw, 46));
            }
            vName = UiFactory.Label(vehiclePanel, "", 36, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(vName.rectTransform, UiFactory.TL, new Vector2(30, -124), new Vector2(660, 44));
            vDrive = UiFactory.Label(vehiclePanel, "", 15, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(vDrive.rectTransform, UiFactory.TL, new Vector2(30, -168), new Vector2(660, 20));
            vDesc = UiFactory.Paragraph(vehiclePanel, "", 16, UiTheme.TextDim, new Vector2(660, 70), TextAnchor.UpperLeft);
            UiFactory.Place(vDesc.rectTransform, UiFactory.TL, new Vector2(30, -196), new Vector2(660, 70));

            float y = 290f;
            for (int i = 0; i < StatNames.Length; i++)
            {
                var row = UiFactory.Rect(vehiclePanel, "Row", i % 2 == 0 ? UiTheme.Row : new Color(0, 0, 0, 0));
                UiFactory.Place(row.rectTransform, UiFactory.TL, new Vector2(24, -y), new Vector2(672, 48));
                var l = UiFactory.Label(vehiclePanel, StatNames[i], 13, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
                UiFactory.Place(l.rectTransform, UiFactory.TL, new Vector2(38, -y), new Vector2(160, 48));
                var v = UiFactory.Label(vehiclePanel, "", 18, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Body);
                v.horizontalOverflow = HorizontalWrapMode.Wrap;
                UiFactory.Place(v.rectTransform, UiFactory.TL, new Vector2(200, -y), new Vector2(300, 48));
                statValues.Add(v);
                var bar = UiFactory.Bar(vehiclePanel, "Bar" + i, new Vector2(170, 10), UiTheme.Accent, out _);
                UiFactory.Place((RectTransform)bar.transform.parent, UiFactory.TL, new Vector2(510, -y - 19), new Vector2(170, 10));
                statBars.Add(bar);
                y += 52f;
            }
            var back = UiFactory.Button(vehiclePanel, "BACK", () => ShowPage(Page.Home), new Vector2(180, 50), BtnStyle.Normal, 18);
            UiFactory.Place((RectTransform)back.transform, UiFactory.BL, new Vector2(30, 28), new Vector2(180, 50));
            var note = UiFactory.Label(vehiclePanel, "The selected vehicle is used for the next game.", 14, UiTheme.TextFaint, TextAnchor.MiddleRight, UiFont.Body);
            UiFactory.Place(note.rectTransform, UiFactory.BR, new Vector2(-30, 40), new Vector2(440, 20));
        }

        void PickVehicle(string key)
        {
            GameSession.VehicleKey = key;
            RefreshVehicle();
            onPreviewVehicle?.Invoke(key);
        }

        public void RefreshVehicle()
        {
            if (maxStats == null) maxStats = VehicleStats.MaxOfAll();
            var s = VehicleStats.From(GameSession.VehicleKey);
            for (int i = 0; i < 3; i++) vehicleTabs[i].Selected = GameManager.VehicleKeys[i] == GameSession.VehicleKey;
            vName.text = s.name;
            vDrive.text = s.Drive + "   •   " + (s.hasLowRange ? "low range" : "single range") + "   •   " + s.diffLocks + " diff lock" + (s.diffLocks == 1 ? "" : "s");
            vDesc.text = s.description;
            string[] vals =
            {
                s.mass.ToString("0") + " kg",
                s.powerKw.ToString("0") + " kW   (" + s.powerHp.ToString("0") + " hp)",
                s.peakTorque.ToString("0") + " Nm  @ " + s.peakTorqueRpm.ToString("0") + " rpm",
                s.TyreText,
                s.hasWinch ? s.winchKn.ToString("0") + " kN pull, " + s.winchLen.ToString("0") + " m cable" : "none",
                s.fording.ToString("0.00") + " m",
                s.fuel.ToString("0") + " L",
            };
            float[] fr =
            {
                s.mass / maxStats.mass, s.powerKw / maxStats.powerKw, s.peakTorque / maxStats.peakTorque, s.tyreWidth / maxStats.tyreWidth,
                s.hasWinch ? s.winchKn / maxStats.winchKn : 0f, s.fording / maxStats.fording, s.fuel / maxStats.fuel,
            };
            for (int i = 0; i < vals.Length; i++) { statValues[i].text = vals[i]; UiFactory.SetBar(statBars[i], fr[i]); }
            if (btnVehicle != null)
                btnVehicle.label.text = "VEHICLE\n<size=14><color=#9AA6B2>" + s.name + "</color></size>";
        }

        // ------------------------------------------------------------------ scenario page

        void BuildScenarioPanel()
        {
            var p = UiFactory.Panel(root, "ScenarioPanel", new Color(0.035f, 0.041f, 0.049f, 0.90f), 16, true, true);
            scenarioPanel = p.rt;
            UiFactory.Place(scenarioPanel, UiFactory.MR, new Vector2(-70, 0), new Vector2(720, 740), UiFactory.MR);
            var h = UiFactory.Label(scenarioPanel, "SCENARIOS", 14, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(h.rectTransform, UiFactory.TL, new Vector2(30, -30), new Vector2(200, 18));
            float y = 56f;
            var catalog = ScenarioCatalog.All;
            for (int ci = 0; ci < catalog.Count && ci < 5; ci++)
            {
                var sc = catalog[ci];
                var captured = sc;
                var b = UiFactory.Button(scenarioPanel, sc.title, () => PickScenario(captured), new Vector2(660, 64), BtnStyle.Normal, 21, UiFont.Display);
                UiFactory.Place((RectTransform)b.transform, UiFactory.TL, new Vector2(30, -y), new Vector2(660, 64));
                b.label.alignment = TextAnchor.MiddleLeft; UiFactory.Fill(b.label.rectTransform, 22, 0, 150, 0);
                int dif = Mathf.Clamp(sc.difficulty, 1, 3);
                string stars = new string('●', dif) + "<color=#4A525A>" + new string('●', 3 - dif) + "</color>";
                b.label.text = sc.title + "\n<size=14><color=#9AA6B2>" + (sc.world == WorldKind.ProvingGround ? "Proving ground" : "Wilderness") + "  •  " + sc.vehicle + "</color></size>";
                var st = UiFactory.Label(b.transform, stars, 18, UiTheme.Accent, TextAnchor.MiddleRight, UiFont.Body);
                UiFactory.Fill(st.rectTransform, 0, 0, 18, 0);
                scenarioButtons.Add(b);
                y += 72f;
            }
            y += 10f;
            var sep = UiFactory.Rect(scenarioPanel, "Sep", new Color(1, 1, 1, 0.1f));
            UiFactory.Place(sep.rectTransform, UiFactory.TL, new Vector2(30, -y), new Vector2(660, 1)); y += 18f;
            sTitle = UiFactory.Label(scenarioPanel, "", 30, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(sTitle.rectTransform, UiFactory.TL, new Vector2(30, -y), new Vector2(660, 40)); y += 46f;
            sMeta = UiFactory.Label(scenarioPanel, "", 15, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(sMeta.rectTransform, UiFactory.TL, new Vector2(30, -y), new Vector2(660, 20)); y += 30f;
            sDesc = UiFactory.Paragraph(scenarioPanel, "", 17, UiTheme.Text, new Vector2(660, 84), TextAnchor.UpperLeft);
            UiFactory.Place(sDesc.rectTransform, UiFactory.TL, new Vector2(30, -y), new Vector2(660, 84)); y += 88f;
            sBrief = UiFactory.Paragraph(scenarioPanel, "", 15, UiTheme.TextDim, new Vector2(660, 70), TextAnchor.UpperLeft);
            UiFactory.Place(sBrief.rectTransform, UiFactory.TL, new Vector2(30, -y), new Vector2(660, 70));
            startScenario = UiFactory.Button(scenarioPanel, "START SCENARIO", () => { if (pickedScenario != null) onStart?.Invoke(pickedScenario.world, pickedScenario); }, new Vector2(300, 56), BtnStyle.Primary, 21, UiFont.Display);
            UiFactory.Place((RectTransform)startScenario.transform, UiFactory.BR, new Vector2(-30, 28), new Vector2(300, 56));
            var back = UiFactory.Button(scenarioPanel, "BACK", () => ShowPage(Page.Home), new Vector2(180, 50), BtnStyle.Normal, 18);
            UiFactory.Place((RectTransform)back.transform, UiFactory.BL, new Vector2(30, 28), new Vector2(180, 50));
            PickScenario(catalog[0]);
        }

        void PickScenario(ScenarioDef sc)
        {
            pickedScenario = sc;
            var cat = ScenarioCatalog.All;
            for (int i = 0; i < scenarioButtons.Count; i++) scenarioButtons[i].Selected = cat[i] == sc;
            sTitle.text = sc.title;
            sMeta.text = ScenarioCatalog.DifficultyName(sc).ToUpperInvariant() + "   •   " + (sc.world == WorldKind.ProvingGround ? "PROVING GROUND" : "WILDERNESS")
                + "   •   " + GameManager.GetDefinition(sc.vehicle).displayName.ToUpperInvariant() + (sc.withTrailer ? " + TRAILER" : "")
                + (sc.timeLimitSeconds > 0f ? "   •   LIMIT " + Mathf.RoundToInt(sc.timeLimitSeconds / 60f) + " MIN" : "") + (sc.fuelLimitLitres > 0f ? "   •   " + Mathf.RoundToInt(sc.fuelLimitLitres) + " L FUEL" : "");
            sDesc.text = sc.description;
            var sbr = new System.Text.StringBuilder();
            for (int i = 0; i < sc.stages.Count; i++)
                sbr.Append(i + 1).Append(".  ").Append(string.IsNullOrEmpty(sc.stages[i].label) ? sc.stages[i].kind + " " + sc.stages[i].site : sc.stages[i].label).Append((char)10);
            sBrief.text = sbr.ToString();
        }

        // ------------------------------------------------------------------ pages / open / close

        public void ShowPage(Page p)
        {
            CurrentPage = p;
            UiFactory.SetActive(vehiclePanel, p == Page.Vehicles);
            UiFactory.SetActive(scenarioPanel, p == Page.Scenarios);
            if (p == Page.Vehicles) RefreshVehicle();
            if (btnVehicle != null && p == Page.Home) RefreshVehicle();
        }

        public void Open()
        {
            IsOpen = true; UiState.MainMenuOpen = true;
            root.gameObject.SetActive(true);
            ShowPage(Page.Home);
            RefreshVehicle();
        }

        public void Close()
        {
            IsOpen = false; UiState.MainMenuOpen = false;
            root.gameObject.SetActive(false);
        }

        public override bool OnBack()
        {
            if (CurrentPage != Page.Home) { ShowPage(Page.Home); return true; }
            return true;
        }
    }

    /// <summary>Full-screen loading card shown while a world is generated.</summary>
    public sealed class LoadingOverlay : UiMenu
    {
        Text label, dots; float t;
        public override void Build(RectTransform parent)
        {
            root = UiFactory.NewRect("Loading", parent);
            UiFactory.Fill(root);
            var bg = UiFactory.Rect(root, "Bg", new Color(0.02f, 0.025f, 0.03f, 0.97f), true);
            UiFactory.Fill(bg.rectTransform);
            label = UiFactory.Label(root, "LOADING", 46, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Place(label.rectTransform, UiFactory.C, new Vector2(0, 20), new Vector2(1000, 60));
            dots = UiFactory.Label(root, "", 24, UiTheme.Accent, TextAnchor.MiddleCenter, UiFont.Bold);
            UiFactory.Place(dots.rectTransform, UiFactory.C, new Vector2(0, -30), new Vector2(400, 30));
            root.gameObject.SetActive(false);
        }
        public void Show(string text) { IsOpen = true; UiState.LoadingWorld = true; label.text = text; root.gameObject.SetActive(true); t = 0f; }
        public void Hide() { IsOpen = false; UiState.LoadingWorld = false; root.gameObject.SetActive(false); }
        public override void Tick(float dt)
        {
            if (!IsOpen) return;
            t += dt; int n = 1 + (int)(t * 3f) % 4;
            dots.text = new string('●', n);
        }
    }
}
