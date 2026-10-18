using MudRunner.Game;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>Garage (Enter inside a <see cref="GarageZone"/>): switch vehicle, refuel, repair. Freezes time while open.</summary>
    public sealed class GarageMenu : UiMenu
    {
        readonly UiButton[] cards = new UiButton[3];
        Text title, status, fuelText, hullText, zoneText;
        Image fuelFill, hullFill;
        UiButton refuel, repair;
        GarageZone zone;
        float statusTimer;
        public GarageZone Zone => zone;

        public override void Build(RectTransform parent)
        {
            root = UiFactory.NewRect("GarageMenu", parent);
            UiFactory.Fill(root);
            var dim = UiFactory.Rect(root, "Dim", new Color(0f, 0f, 0f, 0.55f), true);
            UiFactory.Fill(dim.rectTransform);
            const float W = 940f, H = 640f;
            var p = UiFactory.Panel(root, "Panel", new Color(0.035f, 0.041f, 0.049f, 0.97f), 16, true, true);
            UiFactory.Place(p.rt, UiFactory.C, Vector2.zero, new Vector2(W, H));
            title = UiFactory.Label(p.rt, "GARAGE", 40, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(title.rectTransform, UiFactory.TL, new Vector2(36, -44), new Vector2(500, 52));
            zoneText = UiFactory.Label(p.rt, "", 16, UiTheme.Accent, TextAnchor.MiddleRight, UiFont.Bold);
            UiFactory.Place(zoneText.rectTransform, UiFactory.TR, new Vector2(-36, -44), new Vector2(360, 24));
            var bar = UiFactory.Rect(p.rt, "Bar", UiTheme.Accent);
            UiFactory.Place(bar.rectTransform, UiFactory.TL, new Vector2(38, -78), new Vector2(64, 4));

            var sec1 = UiFactory.Label(p.rt, "SELECT VEHICLE", 13, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(sec1.rectTransform, UiFactory.TL, new Vector2(36, -108), new Vector2(300, 16));
            float cw = (W - 72 - 24) / 3f;
            for (int i = 0; i < 3; i++)
            {
                int idx = i;
                cards[i] = UiFactory.Button(p.rt, GameManager.VehicleKeys[i], () => Switch(GameManager.VehicleKeys[idx]), new Vector2(cw, 170), BtnStyle.Normal, 18, UiFont.Body);
                UiFactory.Place((RectTransform)cards[i].transform, UiFactory.TL, new Vector2(36 + i * (cw + 12f), -132), new Vector2(cw, 170));
                cards[i].label.alignment = TextAnchor.UpperLeft; UiFactory.Fill(cards[i].label.rectTransform, 20, 18, 14, 14);
                cards[i].label.supportRichText = true; cards[i].label.verticalOverflow = VerticalWrapMode.Truncate; cards[i].label.horizontalOverflow = HorizontalWrapMode.Wrap;
                cards[i].tSelected = UiTheme.Text; cards[i].accentOnSelect = true;
            }

            var sec2 = UiFactory.Label(p.rt, "SERVICE", 13, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(sec2.rectTransform, UiFactory.TL, new Vector2(36, -330), new Vector2(300, 16));
            // fuel row
            var fl = UiFactory.Label(p.rt, "FUEL", 14, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(fl.rectTransform, UiFactory.TL, new Vector2(36, -362), new Vector2(60, 24));
            fuelFill = UiFactory.Bar(p.rt, "FuelBar", new Vector2(300, 14), UiTheme.Good, out _);
            UiFactory.Place((RectTransform)fuelFill.transform.parent, UiFactory.TL, new Vector2(100, -367), new Vector2(300, 14));
            fuelText = UiFactory.Label(p.rt, "", 17, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(fuelText.rectTransform, UiFactory.TL, new Vector2(416, -362), new Vector2(150, 24));
            refuel = UiFactory.Button(p.rt, "REFUEL", Refuel, new Vector2(300, 48), BtnStyle.Normal, 18);
            UiFactory.Place((RectTransform)refuel.transform, UiFactory.TR, new Vector2(-36, -352), new Vector2(300, 48));
            // hull row
            var hl = UiFactory.Label(p.rt, "HULL", 14, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(hl.rectTransform, UiFactory.TL, new Vector2(36, -430), new Vector2(60, 24));
            hullFill = UiFactory.Bar(p.rt, "HullBar", new Vector2(300, 14), UiTheme.Good, out _);
            UiFactory.Place((RectTransform)hullFill.transform.parent, UiFactory.TL, new Vector2(100, -435), new Vector2(300, 14));
            hullText = UiFactory.Label(p.rt, "", 17, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(hullText.rectTransform, UiFactory.TL, new Vector2(416, -430), new Vector2(150, 24));
            repair = UiFactory.Button(p.rt, "REPAIR", Repair, new Vector2(300, 48), BtnStyle.Normal, 18);
            UiFactory.Place((RectTransform)repair.transform, UiFactory.TR, new Vector2(-36, -420), new Vector2(300, 48));

            status = UiFactory.Label(p.rt, "", 17, UiTheme.Good, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(status.rectTransform, UiFactory.BL, new Vector2(36, 98), new Vector2(700, 24));
            var back = UiFactory.Button(p.rt, "BACK TO THE TRAIL   [Esc]", () => UiRoot.Instance?.CloseGarage(), new Vector2(380, 56), BtnStyle.Primary, 20, UiFont.Display);
            UiFactory.Place((RectTransform)back.transform, UiFactory.BL, new Vector2(36, 30), new Vector2(380, 56));
            root.gameObject.SetActive(false);
        }

        public void Open(GarageZone z)
        {
            zone = z; IsOpen = true; UiState.GarageOpen = true;
            root.gameObject.SetActive(true);
            zoneText.text = z != null ? z.displayName.ToUpperInvariant() : "";
            status.text = "";
            Refresh();
            UiTime.Refresh();
        }

        public void Close()
        {
            if (!IsOpen) return;
            IsOpen = false; UiState.GarageOpen = false;
            root.gameObject.SetActive(false);
            UiTime.Refresh();
        }

        void Say(string s, bool good = true) { status.text = s; status.color = good ? UiTheme.Good : UiTheme.Warn; statusTimer = 4f; }

        public void Switch(string key)
        {
            var gm = GameManager.Instance; if (gm == null || gm.World == null) return;
            if (zone != null && !zone.allowVehicleSwitch) { Say("Vehicle switching is not available here", false); return; }
            if (gm.Player != null && gm.Player.def == GameManager.GetDefinition(key)) { Say("Already driving this vehicle", false); return; }
            gm.SwitchPlayerVehicle(key);
            GameSession.VehicleKey = key;
            Say("Switched to " + GameManager.GetDefinition(key).displayName);
            Refresh();
        }

        public void Refuel()
        {
            var v = GameManager.Instance?.Player; if (v == null) return;
            if (zone != null && !zone.allowRefuel) { Say("No fuel pump here", false); return; }
            float added = v.def.fuelCapacity - v.fuel;
            v.Refuel();
            Say("Refuelled +" + added.ToString("0") + " L");
            Refresh();
        }

        public void Repair()
        {
            var v = GameManager.Instance?.Player; if (v == null) return;
            if (zone != null && !zone.allowRepair) { Say("No workshop here", false); return; }
            v.Repair();
            Say("Hull repaired");
            Refresh();
        }

        void Refresh()
        {
            var gm = GameManager.Instance; var v = gm != null ? gm.Player : null;
            for (int i = 0; i < 3; i++)
            {
                var s = VehicleStats.From(GameManager.VehicleKeys[i]);
                bool active = v != null && v.def == GameManager.GetDefinition(GameManager.VehicleKeys[i]);
                cards[i].label.text = "<size=22><b>" + s.name + "</b></size>\n<color=#FFB020>" + s.Drive + (s.hasWinch ? "  •  winch" : "") + "</color>\n"
                    + "<color=#9AA6B2>" + s.mass.ToString("0") + " kg   •   " + s.powerKw.ToString("0") + " kW\ntyres " + (s.tyreRadius * 2000f).ToString("0") + " mm\nfording " + s.fording.ToString("0.00") + " m</color>"
                    + (active ? "\n<color=#68DA76><b>IN USE</b></color>" : "");
                cards[i].Selected = active;
            }
            if (v == null) return;
            float fFrac = v.fuel / Mathf.Max(1f, v.def.fuelCapacity);
            UiFactory.SetBar(fuelFill, fFrac); fuelFill.color = fFrac < 0.15f ? UiTheme.Bad : fFrac < 0.35f ? UiTheme.Warn : UiTheme.Good;
            fuelText.text = Mathf.CeilToInt(v.fuel) + " / " + Mathf.RoundToInt(v.def.fuelCapacity) + " L";
            float missing = v.def.fuelCapacity - v.fuel;
            refuel.label.text = missing < 0.5f ? "TANK FULL" : "REFUEL   +" + missing.ToString("0") + " L";
            refuel.interactable = missing >= 0.5f && (zone == null || zone.allowRefuel);
            float hp = 1f - Mathf.Clamp01(v.damage01);
            UiFactory.SetBar(hullFill, hp); hullFill.color = UiTheme.HealthColor(hp);
            hullText.text = Mathf.RoundToInt(hp * 100f) + "%";
            repair.label.text = v.damage01 < 0.005f ? "NO DAMAGE" : "REPAIR   " + Mathf.RoundToInt(v.damage01 * 100f) + "% damage";
            repair.interactable = v.damage01 >= 0.005f && (zone == null || zone.allowRepair);
        }

        public override void Tick(float dt)
        {
            if (!IsOpen) return;
            if (statusTimer > 0f) { statusTimer -= dt; if (statusTimer <= 0f) status.text = ""; }
        }

        public override bool OnBack() { UiRoot.Instance?.CloseGarage(); return true; }
    }
}
