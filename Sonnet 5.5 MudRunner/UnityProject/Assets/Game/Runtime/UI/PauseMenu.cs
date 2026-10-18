using System;
using MudRunner.CameraSystem;
using MudRunner.Game;
using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.UI;

namespace MudRunner.UI
{
    public abstract class UiMenu
    {
        public RectTransform root;
        public bool IsOpen { get; protected set; }
        public abstract void Build(RectTransform parent);
        public virtual void Tick(float dt) { }
        /// <summary>Esc pressed while this menu is open. Return true when handled (e.g. went back one page).</summary>
        public virtual bool OnBack() { return false; }

        CanvasGroup fadeGroup; float fade = 1f; bool wasOpen;
        /// <summary>Quick fade-in whenever the menu opens (unscaled time, so it also works while paused).</summary>
        public void TickFade(float dt)
        {
            if (root == null) return;
            if (fadeGroup == null) { fadeGroup = root.GetComponent<CanvasGroup>(); if (fadeGroup == null) fadeGroup = root.gameObject.AddComponent<CanvasGroup>(); }
            if (IsOpen && !wasOpen) { fade = 0f; fadeGroup.alpha = 0f; }
            wasOpen = IsOpen;
            if (IsOpen && fade < 1f)
            {
                fade = Mathf.Min(1f, fade + dt / 0.16f);
                fadeGroup.alpha = fade * fade * (3f - 2f * fade);
            }
        }
    }

    public enum QualityPreset { Low = 0, Medium = 1, High = 2 }

    /// <summary>Graphics presets built on QualitySettings and the URP per-camera data (the URP asset itself is left untouched).</summary>
    public static class UiQuality
    {
        public static QualityPreset Current { get; private set; } = QualityPreset.High;

        public static void Apply(QualityPreset p)
        {
            Current = p;
            int count = QualitySettings.names.Length;
            if (count > 0) QualitySettings.SetQualityLevel(p == QualityPreset.Low ? 0 : count - 1, true);
            switch (p)
            {
                case QualityPreset.Low:
                    QualitySettings.lodBias = 0.7f; QualitySettings.globalTextureMipmapLimit = 1; QualitySettings.anisotropicFiltering = AnisotropicFiltering.Disable; break;
                case QualityPreset.Medium:
                    QualitySettings.lodBias = 1.0f; QualitySettings.globalTextureMipmapLimit = 0; QualitySettings.anisotropicFiltering = AnisotropicFiltering.Enable; break;
                default:
                    QualitySettings.lodBias = 1.6f; QualitySettings.globalTextureMipmapLimit = 0; QualitySettings.anisotropicFiltering = AnisotropicFiltering.ForceEnable; break;
            }
            var cam = Camera.main;
            if (cam != null)
            {
                var data = cam.GetUniversalAdditionalCameraData();
                if (data != null)
                {
                    data.renderShadows = p != QualityPreset.Low;
                    data.renderPostProcessing = p != QualityPreset.Low;
                    data.antialiasing = p == QualityPreset.Low ? AntialiasingMode.None : p == QualityPreset.Medium ? AntialiasingMode.FastApproximateAntialiasing : AntialiasingMode.SubpixelMorphologicalAntiAliasing;
                    data.antialiasingQuality = AntialiasingQuality.High;
                }
            }
        }
    }

    /// <summary>Single place that decides Time.timeScale (pause, garage, debug slow motion) and keeps fixedDeltaTime consistent.</summary>
    public static class UiTime
    {
        static float lastScale = 1f;

        public static void Refresh()
        {
            float s = (UiState.PauseOpen || UiState.GarageOpen) ? 0f : UiState.SlowMotion;
            bool changed = !Mathf.Approximately(Time.timeScale, s);
            Time.timeScale = s;
            if (s > 0f) { Time.fixedDeltaTime = UiState.BaseFixedDeltaTime * s; lastScale = s; }
            var gm = GameManager.Instance; if (gm != null) gm.paused = s <= 0f;
            AudioListener.pause = s <= 0f;
            if (changed && s > 0f) { }
        }

        public static void Reset()
        {
            UiState.SlowMotion = 1f;
            Time.timeScale = 1f; Time.fixedDeltaTime = UiState.BaseFixedDeltaTime; AudioListener.pause = false;
            var gm = GameManager.Instance; if (gm != null) gm.paused = false;
        }
    }

    /// <summary>Esc menu: resume, controls, graphics quality, master volume, back to main menu, quit.</summary>
    public sealed class PauseMenu : UiMenu
    {
        RectTransform mainPage, controlsPage;
        UiButton[] quality = new UiButton[3];
        UiButton unitsMetric, unitsImperial;
        Slider volume; Text volumeText;
        public Action onReturnToMain;

        public override void Build(RectTransform parent)
        {
            root = UiFactory.NewRect("PauseMenu", parent);
            UiFactory.Fill(root);
            var dim = UiFactory.Rect(root, "Dim", new Color(0f, 0f, 0f, 0.62f), true);
            UiFactory.Fill(dim.rectTransform);

            // ---- main page
            const float W = 540f;
            var p = UiFactory.Panel(root, "Panel", new Color(0.035f, 0.041f, 0.049f, 0.97f), 16, true, true);
            mainPage = p.rt;
            UiFactory.Place(mainPage, UiFactory.C, Vector2.zero, new Vector2(W, 600));
            var title = UiFactory.Label(mainPage, "PAUSED", 48, UiTheme.Text, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Place(title.rectTransform, UiFactory.TC, new Vector2(0, -52), new Vector2(W, 60));
            var bar = UiFactory.Rect(mainPage, "Bar", UiTheme.Accent);
            UiFactory.Place(bar.rectTransform, UiFactory.TC, new Vector2(0, -92), new Vector2(64, 4));

            float x = 34f, w = W - 68f, y = 122f;
            var resume = UiFactory.Button(mainPage, "RESUME", () => UiRoot.Instance?.Perform(UiAction.Pause), new Vector2(w, 56), BtnStyle.Primary, 22);
            UiFactory.Place(resume.GetComponent<RectTransform>(), UiFactory.TL, new Vector2(x, -y), new Vector2(w, 56)); y += 66f;
            var controls = UiFactory.Button(mainPage, "CONTROLS", () => ShowControls(true), new Vector2(w, 50), BtnStyle.Normal, 19);
            UiFactory.Place(controls.GetComponent<RectTransform>(), UiFactory.TL, new Vector2(x, -y), new Vector2(w, 50)); y += 68f;

            var gl = UiFactory.Label(mainPage, "GRAPHICS QUALITY", 12, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(gl.rectTransform, UiFactory.TL, new Vector2(x, -y), new Vector2(300, 16)); y += 22f;
            string[] qn = { "LOW", "MEDIUM", "HIGH" };
            float sw = (w - 16f) / 3f;
            for (int i = 0; i < 3; i++)
            {
                int idx = i;
                quality[i] = UiFactory.Button(mainPage, qn[i], () => SetQuality((QualityPreset)idx), new Vector2(sw, 44), BtnStyle.Segment, 17);
                UiFactory.Place(quality[i].GetComponent<RectTransform>(), UiFactory.TL, new Vector2(x + i * (sw + 8f), -y), new Vector2(sw, 44));
            }
            y += 62f;

            var vl = UiFactory.Label(mainPage, "MASTER VOLUME", 12, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(vl.rectTransform, UiFactory.TL, new Vector2(x, -y), new Vector2(300, 16));
            volumeText = UiFactory.Label(mainPage, "100%", 16, UiTheme.Text, TextAnchor.MiddleRight, UiFont.Display);
            UiFactory.Place(volumeText.rectTransform, UiFactory.TL, new Vector2(x + w - 100, -y + 2), new Vector2(100, 20)); y += 24f;
            volume = UiFactory.Slider(mainPage, new Vector2(w, 26), 0f, 1f, AudioListener.volume, v => { AudioListener.volume = v; volumeText.text = Mathf.RoundToInt(v * 100f) + "%"; });
            UiFactory.Place(volume.GetComponent<RectTransform>(), UiFactory.TL, new Vector2(x, -y), new Vector2(w, 26)); y += 52f;

            var ul = UiFactory.Label(mainPage, "SPEED UNITS", 12, UiTheme.TextDim, TextAnchor.MiddleLeft, UiFont.Bold);
            UiFactory.Place(ul.rectTransform, UiFactory.TL, new Vector2(x, -y), new Vector2(300, 16)); y += 22f;
            unitsMetric = UiFactory.Button(mainPage, "KM/H", () => { UiSettings.Imperial = false; RefreshUnits(); }, new Vector2((w - 8f) / 2f, 44), BtnStyle.Segment, 17);
            UiFactory.Place((RectTransform)unitsMetric.transform, UiFactory.TL, new Vector2(x, -y), new Vector2((w - 8f) / 2f, 44));
            unitsImperial = UiFactory.Button(mainPage, "MPH", () => { UiSettings.Imperial = true; RefreshUnits(); }, new Vector2((w - 8f) / 2f, 44), BtnStyle.Segment, 17);
            UiFactory.Place((RectTransform)unitsImperial.transform, UiFactory.TL, new Vector2(x + (w - 8f) / 2f + 8f, -y), new Vector2((w - 8f) / 2f, 44)); y += 62f;

            float hw = (w - 8f) / 2f;
            var qs = UiFactory.Button(mainPage, "QUICK SAVE  [F5]", QuickSave, new Vector2(hw, 46), BtnStyle.Normal, 16);
            UiFactory.Place((RectTransform)qs.transform, UiFactory.TL, new Vector2(x, -y), new Vector2(hw, 46));
            var ql = UiFactory.Button(mainPage, "QUICK LOAD  [F9]", QuickLoad, new Vector2(hw, 46), BtnStyle.Normal, 16);
            UiFactory.Place((RectTransform)ql.transform, UiFactory.TL, new Vector2(x + hw + 8f, -y), new Vector2(hw, 46)); y += 62f;

            var main = UiFactory.Button(mainPage, "RETURN TO MAIN MENU", () => { UiRoot.Instance?.Perform(UiAction.Pause); onReturnToMain?.Invoke(); }, new Vector2(w, 50), BtnStyle.Normal, 18);
            UiFactory.Place(main.GetComponent<RectTransform>(), UiFactory.TL, new Vector2(x, -y), new Vector2(w, 50)); y += 60f;
            var quit = UiFactory.Button(mainPage, "QUIT GAME", UiRoot.QuitGame, new Vector2(w, 50), BtnStyle.Danger, 18);
            UiFactory.Place(quit.GetComponent<RectTransform>(), UiFactory.TL, new Vector2(x, -y), new Vector2(w, 50)); y += 50f;
            mainPage.sizeDelta = new Vector2(W, y + 34f);

            // ---- controls page
            const float CWd = 1080f;
            var cp = UiFactory.Panel(root, "ControlsPanel", new Color(0.035f, 0.041f, 0.049f, 0.97f), 16, true, true);
            controlsPage = cp.rt;
            UiFactory.Place(controlsPage, UiFactory.C, Vector2.zero, new Vector2(CWd, 600));
            var ct = UiFactory.Label(controlsPage, "CONTROLS", 34, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(ct.rectTransform, UiFactory.TL, new Vector2(36, -42), new Vector2(400, 44));
            var back = UiFactory.Button(controlsPage, "BACK", () => ShowControls(false), new Vector2(140, 44), BtnStyle.Normal, 17);
            UiFactory.Place(back.GetComponent<RectTransform>(), UiFactory.TR, new Vector2(-34, -22), new Vector2(140, 44));
            var body = UiFactory.NewRect("Body", controlsPage);
            UiFactory.Place(body, UiFactory.TL, new Vector2(36, -84), new Vector2(CWd - 72, 440), UiFactory.TL);
            float h = UiControls.Build(body, CWd - 72);
            controlsPage.sizeDelta = new Vector2(CWd, h + 130f);
            root.gameObject.SetActive(false);
            controlsPage.gameObject.SetActive(false);
        }

        void QuickSave()
        {
            bool ok = SaveSystem.EnsureInstance().Save("quick");
            Hud.Notify(ok ? "Game saved" : "Could not save the game", 2.5f, ok ? NoteKind.Good : NoteKind.Bad);
        }

        void QuickLoad()
        {
            bool ok = SaveSystem.EnsureInstance().Load("quick");
            if (!ok) { Hud.Notify("No quick-save found", 2.5f, NoteKind.Warn); return; }
            UiRoot.Instance?.Perform(UiAction.Pause);
            CameraRig.Instance?.Snap();
            Hud.Notify("Game loaded", 2.5f, NoteKind.Good);
        }

        public void ShowControlsPage(bool on) { ShowControls(on); }

        void ShowControls(bool on)
        {
            mainPage.gameObject.SetActive(!on);
            controlsPage.gameObject.SetActive(on);
        }

        void SetQuality(QualityPreset p)
        {
            UiQuality.Apply(p);
            RefreshQuality();
            Hud.Notify("Graphics: " + p, 2f);
        }

        void RefreshUnits() { unitsMetric.Selected = !UiSettings.Imperial; unitsImperial.Selected = UiSettings.Imperial; }

        void RefreshQuality()
        {
            for (int i = 0; i < 3; i++) quality[i].Selected = (int)UiQuality.Current == i;
        }

        public void Open()
        {
            if (IsOpen) return;
            IsOpen = true; UiState.PauseOpen = true;
            root.gameObject.SetActive(true);
            ShowControls(false);
            RefreshQuality(); RefreshUnits();
            volume.SetValueWithoutNotify(AudioListener.volume); volumeText.text = Mathf.RoundToInt(AudioListener.volume * 100f) + "%";
            UiTime.Refresh();
        }

        public void Close()
        {
            if (!IsOpen) return;
            IsOpen = false; UiState.PauseOpen = false;
            root.gameObject.SetActive(false);
            UiTime.Refresh();
        }

        public override bool OnBack()
        {
            if (controlsPage.gameObject.activeSelf) { ShowControls(false); return true; }
            return false;
        }
    }
}
