using System;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace MudRunner.UI
{
    public enum BtnStyle { Normal, Primary, Danger, Ghost, Segment }

    /// <summary>A rounded panel: container with optional soft shadow, background and hairline border. Add content to <see cref="rt"/>.</summary>
    public sealed class UiPanel
    {
        public RectTransform rt; public Image bg, border, shadow;
        public static implicit operator RectTransform(UiPanel p) { return p.rt; }
    }

    /// <summary>Button with dark-glass look, amber accent bar and hover/selected states. Keyboard navigation is disabled on purpose.</summary>
    public sealed class UiButton : Button
    {
        public Image bg, accent;
        public Text label;
        public Color cNormal, cHover, cPressed, cDisabled, cSelected;
        public Color tNormal = UiTheme.Text, tSelected = Color.black, tDisabled = UiTheme.TextFaint;
        public bool alwaysAccent, accentOnSelect = true;
        bool selected;
        public bool Selected { get { return selected; } set { selected = value; Refresh(true); } }

        void Refresh(bool instant)
        {
            if (bg == null) return;
            DoStateTransition(currentSelectionState, instant);
        }

        protected override void DoStateTransition(SelectionState state, bool instant)
        {
            if (bg == null) return;
            Color c = selected ? cSelected : cNormal;
            Color t = selected ? tSelected : tNormal;
            switch (state)
            {
                case SelectionState.Highlighted: c = selected ? Color.Lerp(cSelected, Color.white, 0.14f) : cHover; break;
                case SelectionState.Pressed: c = selected ? cSelected * 0.85f : cPressed; break;
                case SelectionState.Disabled: c = cDisabled; t = tDisabled; break;
            }
            if (!Application.isPlaying || instant) bg.canvasRenderer.SetColor(c); else bg.CrossFadeColor(c, 0.07f, true, true);
            if (label != null) label.color = t;
            if (accent != null) accent.enabled = alwaysAccent || (selected && accentOnSelect);
        }

        public override void OnPointerClick(PointerEventData eventData)
        {
            base.OnPointerClick(eventData);
            if (EventSystem.current != null) EventSystem.current.SetSelectedGameObject(null);
        }

        public void SetLabel(string s) { if (label != null) label.text = s; }
    }

    /// <summary>Factory helpers that build uGUI hierarchies from code.</summary>
    public static class UiFactory
    {
        public static readonly Vector2 BL = new Vector2(0, 0), BR = new Vector2(1, 0), TL = new Vector2(0, 1), TR = new Vector2(1, 1),
            TC = new Vector2(0.5f, 1), BC = new Vector2(0.5f, 0), C = new Vector2(0.5f, 0.5f), ML = new Vector2(0, 0.5f), MR = new Vector2(1, 0.5f);

        public static RectTransform NewRect(string name, Transform parent)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.layer = 5;
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            return rt;
        }

        public static RectTransform Place(RectTransform rt, Vector2 anchor, Vector2 pos, Vector2 size, Vector2? pivot = null)
        {
            rt.anchorMin = rt.anchorMax = anchor;
            rt.pivot = pivot ?? anchor;
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            return rt;
        }

        public static RectTransform Fill(RectTransform rt, float l = 0, float b = 0, float r = 0, float t = 0)
        {
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one; rt.pivot = new Vector2(0.5f, 0.5f);
            rt.offsetMin = new Vector2(l, b); rt.offsetMax = new Vector2(-r, -t);
            return rt;
        }

        public static Image Img(Transform parent, string name, Sprite sprite, Color color, Image.Type type = Image.Type.Simple, bool raycast = false)
        {
            var rt = NewRect(name, parent);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = sprite; img.color = color; img.type = type; img.raycastTarget = raycast;
            if (type == Image.Type.Sliced) img.fillCenter = true;
            return img;
        }

        /// <summary>Solid rectangle (no sprite smoothing) - bars, separators.</summary>
        public static Image Rect(Transform parent, string name, Color color, bool raycast = false)
        {
            return Img(parent, name, UiAssets.White, color, Image.Type.Simple, raycast);
        }

        public static UiPanel Panel(Transform parent, string name, Color? bg = null, int radius = 10, bool border = true, bool shadow = false)
        {
            var p = new UiPanel { rt = NewRect(name, parent) };
            if (shadow)
            {
                p.shadow = Img(p.rt, "Shadow", UiAssets.Shadow(20), new Color(0f, 0f, 0f, 0.55f), Image.Type.Sliced);
                Fill(p.shadow.rectTransform, -20, -20, -20, -20);
            }
            p.bg = Img(p.rt, "Bg", UiAssets.Rounded(radius), bg ?? UiTheme.Bg, Image.Type.Sliced);
            Fill(p.bg.rectTransform);
            if (border)
            {
                p.border = Img(p.rt, "Border", UiAssets.RoundedOutline(radius), UiTheme.Border, Image.Type.Sliced);
                Fill(p.border.rectTransform);
            }
            return p;
        }

        public static Text Label(Transform parent, string text, int size, Color color, TextAnchor align = TextAnchor.MiddleLeft,
            UiFont font = UiFont.Body, FontStyle style = FontStyle.Normal, bool shadow = false, string name = null)
        {
            var rt = NewRect(name ?? "Text", parent);
            var t = rt.gameObject.AddComponent<Text>();
            t.font = UiAssets.Get(font);
            if (font == UiFont.Bold && !UiAssets.HasDedicatedBold) style = FontStyle.Bold;
            t.fontStyle = style;
            t.fontSize = size; t.color = color; t.alignment = align; t.text = text;
            t.horizontalOverflow = HorizontalWrapMode.Overflow; t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false; t.supportRichText = true; t.alignByGeometry = false;
            if (shadow) AddShadow(t);
            return t;
        }

        /// <summary>Wrapping paragraph label inside a fixed box.</summary>
        public static Text Paragraph(Transform parent, string text, int size, Color color, Vector2 boxSize, TextAnchor align = TextAnchor.UpperLeft,
            UiFont font = UiFont.Body, float lineSpacing = 1.1f)
        {
            var t = Label(parent, text, size, color, align, font);
            t.horizontalOverflow = HorizontalWrapMode.Wrap; t.verticalOverflow = VerticalWrapMode.Truncate; t.lineSpacing = lineSpacing;
            t.rectTransform.sizeDelta = boxSize;
            return t;
        }

        public static void AddShadow(Text t, float alpha = 0.7f, float dist = 1.3f)
        {
            var sh = t.gameObject.AddComponent<Shadow>();
            sh.effectColor = new Color(0f, 0f, 0f, alpha); sh.effectDistance = new Vector2(dist, -dist);
        }

        public static UiButton Button(Transform parent, string label, Action onClick, Vector2 size, BtnStyle style = BtnStyle.Normal, int fontSize = 20, UiFont font = UiFont.Bold)
        {
            var rt = NewRect("Btn_" + label, parent);
            rt.sizeDelta = size;
            var btn = rt.gameObject.AddComponent<UiButton>();
            var bg = Img(rt, "Bg", UiAssets.Rounded(8), Color.white, Image.Type.Sliced, true);
            Fill(bg.rectTransform);
            btn.bg = bg; btn.targetGraphic = bg; btn.transition = Selectable.Transition.None;
            btn.navigation = new Navigation { mode = Navigation.Mode.None };
            switch (style)
            {
                case BtnStyle.Primary:
                    btn.cNormal = new Color(1f, 0.69f, 0.125f, 0.92f); btn.cHover = new Color(1f, 0.78f, 0.30f, 1f); btn.cPressed = new Color(0.85f, 0.55f, 0.08f, 1f);
                    btn.cSelected = UiTheme.Accent; btn.tNormal = new Color(0.08f, 0.06f, 0.02f, 1f); btn.tSelected = btn.tNormal; btn.accentOnSelect = false;
                    break;
                case BtnStyle.Danger:
                    btn.cNormal = new Color(0.55f, 0.13f, 0.11f, 0.85f); btn.cHover = new Color(0.78f, 0.2f, 0.16f, 0.95f); btn.cPressed = new Color(0.4f, 0.09f, 0.08f, 1f);
                    btn.cSelected = UiTheme.Bad; btn.tSelected = Color.white;
                    break;
                case BtnStyle.Ghost:
                    btn.cNormal = new Color(1f, 1f, 1f, 0.0f); btn.cHover = new Color(1f, 1f, 1f, 0.10f); btn.cPressed = new Color(1f, 1f, 1f, 0.16f);
                    btn.cSelected = new Color(1f, 0.69f, 0.125f, 0.22f); btn.tSelected = UiTheme.Accent;
                    break;
                case BtnStyle.Segment:
                    btn.cNormal = new Color(1f, 1f, 1f, 0.07f); btn.cHover = new Color(1f, 1f, 1f, 0.15f); btn.cPressed = new Color(1f, 1f, 1f, 0.20f);
                    btn.cSelected = UiTheme.Accent; btn.tSelected = new Color(0.08f, 0.06f, 0.02f, 1f); btn.accentOnSelect = false;
                    break;
                default:
                    btn.cNormal = new Color(1f, 1f, 1f, 0.085f); btn.cHover = new Color(1f, 1f, 1f, 0.17f); btn.cPressed = new Color(1f, 1f, 1f, 0.24f);
                    btn.cSelected = new Color(1f, 0.69f, 0.125f, 0.30f); btn.tSelected = UiTheme.Accent;
                    break;
            }
            btn.cDisabled = new Color(1f, 1f, 1f, 0.04f);
            // accent bar on the left edge
            var acc = Img(rt, "Accent", UiAssets.Rounded(2), UiTheme.Accent, Image.Type.Sliced);
            Place(acc.rectTransform, ML, new Vector2(3, 0), new Vector2(4, size.y - 14));
            acc.enabled = false; btn.accent = acc;
            var t = Label(rt, label, fontSize, btn.tNormal, TextAnchor.MiddleCenter, font);
            Fill(t.rectTransform, 6, 0, 6, 0);
            btn.label = t;
            if (onClick != null) btn.onClick.AddListener(() => onClick());
            btn.Selected = false;
            return btn;
        }

        /// <summary>Slider with track, fill and round handle. Returns the Slider; value label is up to the caller.</summary>
        public static Slider Slider(Transform parent, Vector2 size, float min, float max, float value, Action<float> onChanged, bool wholeNumbers = false)
        {
            var rt = NewRect("Slider", parent);
            rt.sizeDelta = size;
            var slider = rt.gameObject.AddComponent<Slider>();
            slider.navigation = new Navigation { mode = Navigation.Mode.None };
            var track = Img(rt, "Track", UiAssets.Rounded(3), new Color(1f, 1f, 1f, 0.14f), Image.Type.Sliced);
            Place(track.rectTransform, C, Vector2.zero, new Vector2(size.x, 6));
            track.rectTransform.anchorMin = new Vector2(0, 0.5f); track.rectTransform.anchorMax = new Vector2(1, 0.5f); track.rectTransform.sizeDelta = new Vector2(0, 6); track.rectTransform.anchoredPosition = Vector2.zero;
            var fillArea = NewRect("FillArea", rt);
            fillArea.anchorMin = new Vector2(0, 0.5f); fillArea.anchorMax = new Vector2(1, 0.5f); fillArea.sizeDelta = new Vector2(-6, 6); fillArea.anchoredPosition = Vector2.zero;
            var fill = Img(fillArea, "Fill", UiAssets.Rounded(3), UiTheme.Accent, Image.Type.Sliced);
            fill.rectTransform.anchorMin = Vector2.zero; fill.rectTransform.anchorMax = new Vector2(0, 1); fill.rectTransform.sizeDelta = new Vector2(6, 0);
            var handleArea = NewRect("HandleArea", rt);
            Fill(handleArea, 10, 0, 10, 0);
            var handle = Img(handleArea, "Handle", UiAssets.Circle, Color.white, Image.Type.Simple, true);
            handle.rectTransform.sizeDelta = new Vector2(20, 20);
            slider.fillRect = fill.rectTransform; slider.handleRect = handle.rectTransform; slider.targetGraphic = handle;
            slider.direction = UnityEngine.UI.Slider.Direction.LeftToRight;
            slider.minValue = min; slider.maxValue = max; slider.wholeNumbers = wholeNumbers; slider.SetValueWithoutNotify(value);
            if (onChanged != null) slider.onValueChanged.AddListener(v => onChanged(v));
            return slider;
        }

        /// <summary>Thin horizontal bar: track + coloured fill (fill rect anchored left, width driven by <see cref="SetBar"/>).</summary>
        public static Image Bar(Transform parent, string name, Vector2 size, Color fillColor, out Image track, int radius = 3)
        {
            var rt = NewRect(name, parent); rt.sizeDelta = size;
            track = Img(rt, "Track", UiAssets.Rounded(radius), UiTheme.Track, Image.Type.Sliced);
            Fill(track.rectTransform);
            var fill = Img(rt, "Fill", UiAssets.Rounded(radius), fillColor, Image.Type.Sliced);
            fill.rectTransform.anchorMin = Vector2.zero; fill.rectTransform.anchorMax = new Vector2(0, 1); fill.rectTransform.pivot = new Vector2(0, 0.5f);
            fill.rectTransform.offsetMin = Vector2.zero; fill.rectTransform.offsetMax = Vector2.zero;
            return fill;
        }

        /// <summary>Sets a bar fill created by <see cref="Bar"/> (0..1).</summary>
        public static void SetBar(Image fill, float t)
        {
            t = Mathf.Clamp01(t);
            var rt = fill.rectTransform;
            var parent = (RectTransform)rt.parent;
            float w = parent.rect.width;
            rt.anchorMax = new Vector2(0, 1);
            rt.sizeDelta = new Vector2(Mathf.Max(0f, w * t), 0f);
            rt.anchoredPosition = Vector2.zero;
            fill.enabled = t > 0.002f;
        }

        public static void SetActive(Component c, bool on) { if (c != null && c.gameObject.activeSelf != on) c.gameObject.SetActive(on); }
        public static void SetActive(GameObject g, bool on) { if (g != null && g.activeSelf != on) g.SetActive(on); }
    }
}
