using System;
using System.Collections.Generic;
using UnityEngine;

namespace MudRunner.UI
{
    public enum UiFont { Body, Bold, Display, Mono }

    /// <summary>
    /// Fonts (OS fonts when available, built-in Arimo otherwise) and procedurally generated sprites. Nothing here needs
    /// an imported asset: rounded rectangles (9-sliced, 2x oversampled), circles, polygons, gradients and soft shadows are
    /// rasterised on first use.
    /// </summary>
    public static class UiAssets
    {
        static Font body, bold, display, mono;
        static bool fontsReady;
        public static string FontReport = "";

        static readonly Dictionary<int, Sprite> rounded = new Dictionary<int, Sprite>();
        static readonly Dictionary<int, Sprite> outlines = new Dictionary<int, Sprite>();
        static readonly Dictionary<int, Sprite> shadows = new Dictionary<int, Sprite>();
        static Sprite white, circle, ring, triangle, diamond, arrow, gradient, chevron;

        // ------------------------------------------------------------------ fonts

        public static Font Get(UiFont f)
        {
            EnsureFonts();
            switch (f)
            {
                case UiFont.Bold: return bold != null ? bold : body;
                case UiFont.Display: return display != null ? display : body;
                case UiFont.Mono: return mono != null ? mono : body;
                default: return body;
            }
        }

        /// <summary>True when the bold face is a dedicated font (otherwise the Bold font style should be requested).</summary>
        public static bool HasDedicatedBold { get; private set; }

        static void EnsureFonts()
        {
            if (fontsReady) return;
            fontsReady = true;
            var builtin = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            string[] installed = Array.Empty<string>();
            try { installed = Font.GetOSInstalledFontNames(); } catch { }
            var set = new HashSet<string>(installed, StringComparer.OrdinalIgnoreCase);
            body = FromOs(set, builtin, "Segoe UI", "Helvetica Neue", "Arial");
            bold = FromOsOrNull(set, "Segoe UI Semibold", "Segoe UI Bold");
            HasDedicatedBold = bold != null;
            display = FromOsOrNull(set, "Bahnschrift SemiBold", "Bahnschrift", "Segoe UI Semibold", "Arial Narrow");
            mono = FromOsOrNull(set, "Consolas", "Cascadia Mono", "Lucida Console", "Courier New");
            if (body == null) body = builtin;
            FontReport = "body=" + (body != null ? body.name : "null") + " bold=" + (bold != null ? bold.name : "-") + " display=" + (display != null ? display.name : "-") + " mono=" + (mono != null ? mono.name : "-") + " (OS fonts: " + installed.Length + ")";
        }

        static Font FromOs(HashSet<string> set, Font fallback, params string[] names)
        {
            var f = FromOsOrNull(set, names);
            return f != null ? f : fallback;
        }

        static Font FromOsOrNull(HashSet<string> set, params string[] names)
        {
            foreach (var n in names)
            {
                if (!set.Contains(n)) continue;
                try
                {
                    var f = Font.CreateDynamicFontFromOSFont(n, 32);
                    if (f != null) { f.hideFlags = HideFlags.HideAndDontSave; return f; }
                }
                catch { }
            }
            return null;
        }

        // ------------------------------------------------------------------ sprite plumbing

        static Texture2D NewTex(int w, int h, Color32[] px)
        {
            var t = new Texture2D(w, h, TextureFormat.RGBA32, false, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear, hideFlags = HideFlags.HideAndDontSave };
            t.SetPixels32(px); t.Apply(false, true);
            return t;
        }

        static Sprite NewSprite(Texture2D t, float ppu, Vector4 border)
        {
            var s = Sprite.Create(t, new Rect(0, 0, t.width, t.height), new Vector2(0.5f, 0.5f), ppu, 0, SpriteMeshType.FullRect, border);
            s.hideFlags = HideFlags.HideAndDontSave;
            return s;
        }

        public static Sprite White
        {
            get
            {
                if (white == null)
                {
                    var px = new Color32[16]; for (int i = 0; i < 16; i++) px[i] = new Color32(255, 255, 255, 255);
                    white = NewSprite(NewTex(4, 4, px), 100f, Vector4.zero);
                }
                return white;
            }
        }

        /// <summary>9-sliced rounded rectangle, corner radius in UI pixels (reference resolution).</summary>
        public static Sprite Rounded(int radius)
        {
            radius = Mathf.Clamp(radius, 1, 48);
            if (rounded.TryGetValue(radius, out var s) && s != null) return s;
            s = BuildRounded(radius, 0); rounded[radius] = s; return s;
        }

        /// <summary>9-sliced rounded outline (hairline border), thickness in UI pixels.</summary>
        public static Sprite RoundedOutline(int radius, int thickness = 1)
        {
            radius = Mathf.Clamp(radius, 1, 48);
            int key = radius * 100 + thickness;
            if (outlines.TryGetValue(key, out var s) && s != null) return s;
            s = BuildRounded(radius, thickness); outlines[key] = s; return s;
        }

        static Sprite BuildRounded(int rUi, int outlineUi)
        {
            const int k = 2;
            int R = rUi * k;
            int n = 2 * R + 4;
            var px = new Color32[n * n];
            float half = n * 0.5f, inner = half - R, t = outlineUi * k;
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float cx = x + 0.5f - half, cy = y + 0.5f - half;
                    float qx = Mathf.Abs(cx) - inner, qy = Mathf.Abs(cy) - inner;
                    float d = Mathf.Sqrt(Mathf.Max(qx, 0f) * Mathf.Max(qx, 0f) + Mathf.Max(qy, 0f) * Mathf.Max(qy, 0f)) + Mathf.Min(Mathf.Max(qx, qy), 0f) - R;
                    float a = Mathf.Clamp01(0.5f - d);
                    if (outlineUi > 0) a = Mathf.Clamp01(a - Mathf.Clamp01(0.5f - (d + t)));
                    px[y * n + x] = new Color32(255, 255, 255, (byte)Mathf.RoundToInt(a * 255f));
                }
            return NewSprite(NewTex(n, n, px), 100f * k, new Vector4(R + 1, R + 1, R + 1, R + 1));
        }

        /// <summary>Soft drop shadow (sliced): draw it larger than the panel by <paramref name="blur"/> pixels on each side.</summary>
        public static Sprite Shadow(int blur = 18)
        {
            if (shadows.TryGetValue(blur, out var s) && s != null) return s;
            int n = blur * 2 + 8;
            var px = new Color32[n * n];
            float half = n * 0.5f, inner = Mathf.Max(1f, half - blur);
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float cx = x + 0.5f - half, cy = y + 0.5f - half;
                    float qx = Mathf.Abs(cx) - inner, qy = Mathf.Abs(cy) - inner;
                    float d = Mathf.Sqrt(Mathf.Max(qx, 0f) * Mathf.Max(qx, 0f) + Mathf.Max(qy, 0f) * Mathf.Max(qy, 0f)) + Mathf.Min(Mathf.Max(qx, qy), 0f);
                    float a = Mathf.Exp(-Mathf.Max(d, 0f) * Mathf.Max(d, 0f) / (blur * blur * 0.32f)) * 0.9f;
                    px[y * n + x] = new Color32(255, 255, 255, (byte)Mathf.RoundToInt(Mathf.Clamp01(a) * 255f));
                }
            s = NewSprite(NewTex(n, n, px), 100f, new Vector4(blur + 3, blur + 3, blur + 3, blur + 3));
            shadows[blur] = s; return s;
        }

        public static Sprite Circle
        {
            get
            {
                if (circle == null)
                {
                    const int n = 128;
                    var px = new Color32[n * n];
                    for (int y = 0; y < n; y++)
                        for (int x = 0; x < n; x++)
                        {
                            float d = Mathf.Sqrt((x + 0.5f - n * 0.5f) * (x + 0.5f - n * 0.5f) + (y + 0.5f - n * 0.5f) * (y + 0.5f - n * 0.5f)) - (n * 0.5f - 1f);
                            px[y * n + x] = new Color32(255, 255, 255, (byte)Mathf.RoundToInt(Mathf.Clamp01(0.5f - d) * 255f));
                        }
                    circle = NewSprite(NewTex(n, n, px), 100f, Vector4.zero);
                }
                return circle;
            }
        }

        /// <summary>Thin ring (outline of a circle), used for frames and radius indicators.</summary>
        public static Sprite Ring
        {
            get
            {
                if (ring == null)
                {
                    const int n = 256; const float thick = 3.5f;
                    var px = new Color32[n * n];
                    for (int y = 0; y < n; y++)
                        for (int x = 0; x < n; x++)
                        {
                            float d = Mathf.Sqrt((x + 0.5f - n * 0.5f) * (x + 0.5f - n * 0.5f) + (y + 0.5f - n * 0.5f) * (y + 0.5f - n * 0.5f)) - (n * 0.5f - 1f);
                            float a = Mathf.Clamp01(0.5f - d) - Mathf.Clamp01(0.5f - (d + thick));
                            px[y * n + x] = new Color32(255, 255, 255, (byte)Mathf.RoundToInt(Mathf.Clamp01(a) * 255f));
                        }
                    ring = NewSprite(NewTex(n, n, px), 100f, Vector4.zero);
                }
                return ring;
            }
        }

        static Sprite Polygon(Vector2[] pts, int n = 96)
        {
            var px = new Color32[n * n];
            const int ss = 4;
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    int hit = 0;
                    for (int sy = 0; sy < ss; sy++)
                        for (int sx = 0; sx < ss; sx++)
                        {
                            var p = new Vector2((x + (sx + 0.5f) / ss) / n, (y + (sy + 0.5f) / ss) / n);
                            if (InPoly(pts, p)) hit++;
                        }
                    px[y * n + x] = new Color32(255, 255, 255, (byte)(hit * 255 / (ss * ss)));
                }
            return NewSprite(NewTex(n, n, px), 100f, Vector4.zero);
        }

        static bool InPoly(Vector2[] v, Vector2 p)
        {
            bool inside = false;
            for (int i = 0, j = v.Length - 1; i < v.Length; j = i++)
                if (((v[i].y > p.y) != (v[j].y > p.y)) && (p.x < (v[j].x - v[i].x) * (p.y - v[i].y) / (v[j].y - v[i].y) + v[i].x)) inside = !inside;
            return inside;
        }

        public static Sprite Triangle => triangle != null ? triangle : (triangle = Polygon(new[] { new Vector2(0.5f, 0.96f), new Vector2(0.96f, 0.06f), new Vector2(0.04f, 0.06f) }));
        public static Sprite Diamond => diamond != null ? diamond : (diamond = Polygon(new[] { new Vector2(0.5f, 0.98f), new Vector2(0.98f, 0.5f), new Vector2(0.5f, 0.02f), new Vector2(0.02f, 0.5f) }));
        /// <summary>Navigation arrow (tip up, notched tail) for the player marker.</summary>
        public static Sprite Arrow => arrow != null ? arrow : (arrow = Polygon(new[] { new Vector2(0.5f, 0.98f), new Vector2(0.93f, 0.04f), new Vector2(0.5f, 0.26f), new Vector2(0.07f, 0.04f) }));
        public static Sprite Chevron => chevron != null ? chevron : (chevron = Polygon(new[] { new Vector2(0.5f, 0.92f), new Vector2(0.98f, 0.18f), new Vector2(0.80f, 0.06f), new Vector2(0.5f, 0.52f), new Vector2(0.20f, 0.06f), new Vector2(0.02f, 0.18f) }));

        /// <summary>Vertical gradient: alpha 0 at the bottom to 1 at the top.</summary>
        public static Sprite Gradient
        {
            get
            {
                if (gradient == null)
                {
                    const int h = 128;
                    var px = new Color32[4 * h];
                    for (int y = 0; y < h; y++)
                        for (int x = 0; x < 4; x++)
                            px[y * 4 + x] = new Color32(255, 255, 255, (byte)Mathf.RoundToInt(Mathf.Pow(y / (h - 1f), 1.6f) * 255f));
                    gradient = NewSprite(NewTex(4, h, px), 100f, Vector4.zero);
                }
                return gradient;
            }
        }
    }
}
