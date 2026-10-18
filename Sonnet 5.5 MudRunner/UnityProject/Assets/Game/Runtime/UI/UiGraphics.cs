using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>
    /// Anti-aliased arc / ring segment mesh (gauges, progress rings). Angles are degrees clockwise from 12 o'clock.
    /// A 270 degree dial uses startAngle -135, sweep 270. <see cref="fill"/> (0..1) shortens the arc from its start.
    /// </summary>
    public sealed class UiArc : MaskableGraphic
    {
        public float outerRadius = 100f, thickness = 10f, startAngle = -135f, sweep = 270f, feather = 1.1f;
        [Range(0f, 1f)] public float fill = 1f;
        public bool useGradient;
        public Color endColor = Color.white;
        /// <summary>Optional: only draw the part of the sweep between these fractions (used for the redline zone).</summary>
        public float rangeFrom = 0f, rangeTo = 1f;

        public void SetFill(float f)
        {
            f = Mathf.Clamp01(f);
            if (Mathf.Abs(f - fill) < 0.0012f) return;
            fill = f; SetVerticesDirty();
        }

        public void Configure(float outer, float thick, float start, float sweepDeg)
        {
            outerRadius = outer; thickness = thick; startAngle = start; sweep = sweepDeg; SetVerticesDirty();
        }

        public void SetGradient(Color a, Color b) { color = a; endColor = b; useGradient = true; SetVerticesDirty(); }

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();
            float f0 = Mathf.Clamp01(rangeFrom), f1 = Mathf.Min(Mathf.Clamp01(rangeTo), fill);
            if (f1 <= f0 + 1e-4f || thickness <= 0f) return;
            Vector2 c = rectTransform.rect.center;
            float a0 = startAngle + sweep * f0, a1 = startAngle + sweep * f1;
            int n = Mathf.Max(2, Mathf.CeilToInt(Mathf.Abs(a1 - a0) / 2.25f));
            float rIn = Mathf.Max(0.1f, outerRadius - thickness), rOut = outerRadius, f = feather;
            Color32 baseC = color;
            for (int i = 0; i <= n; i++)
            {
                float u = i / (float)n;
                float ang = Mathf.Lerp(a0, a1, u) * Mathf.Deg2Rad;
                float s = Mathf.Sin(ang), co = Mathf.Cos(ang);
                Color32 col = useGradient ? (Color32)Color.Lerp(color, endColor, Mathf.Lerp(f0, f1, u)) : baseC;
                Color32 col0 = col; col0.a = 0;
                vh.AddVert(c + new Vector2(s, co) * (rIn - f), col0, Vector4.zero);
                vh.AddVert(c + new Vector2(s, co) * rIn, col, Vector4.zero);
                vh.AddVert(c + new Vector2(s, co) * rOut, col, Vector4.zero);
                vh.AddVert(c + new Vector2(s, co) * (rOut + f), col0, Vector4.zero);
            }
            for (int i = 0; i < n; i++)
            {
                int b = i * 4, nb = b + 4;
                for (int band = 0; band < 3; band++)
                {
                    vh.AddTriangle(b + band, nb + band, nb + band + 1);
                    vh.AddTriangle(b + band, nb + band + 1, b + band + 1);
                }
            }
        }
    }

    /// <summary>Batched anti-aliased line segments in the graphic's local space (ticks, routes, grid, leader lines, gizmos).</summary>
    public sealed class UiLines : MaskableGraphic
    {
        public struct Seg { public Vector2 a, b; public float w; public Color32 c; }
        readonly List<Seg> segs = new List<Seg>(128);
        public float feather = 0.9f;
        public int Count => segs.Count;

        public void Clear() { segs.Clear(); }
        public void Add(Vector2 a, Vector2 b, float width, Color c) { segs.Add(new Seg { a = a, b = b, w = width, c = c }); }
        public void AddPolyline(IList<Vector2> pts, float width, Color c)
        {
            for (int i = 0; i + 1 < pts.Count; i++) Add(pts[i], pts[i + 1], width, c);
        }
        public void AddCircle(Vector2 center, float radius, float width, Color c, int steps = 20)
        {
            Vector2 prev = center + new Vector2(radius, 0f);
            for (int i = 1; i <= steps; i++)
            {
                float a = i / (float)steps * Mathf.PI * 2f;
                Vector2 p = center + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * radius;
                Add(prev, p, width, c); prev = p;
            }
        }
        public void Apply() { SetVerticesDirty(); }

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();
            int vi = 0;
            for (int i = 0; i < segs.Count; i++)
            {
                var s = segs[i];
                Vector2 d = s.b - s.a; float len = d.magnitude;
                if (len < 0.01f) continue;
                d /= len;
                Vector2 n = new Vector2(-d.y, d.x);
                float w2 = Mathf.Max(0.5f, s.w * 0.5f), f = feather;
                Color32 c1 = s.c, c0 = s.c; c0.a = 0;
                vh.AddVert(s.a + n * (w2 + f), c0, Vector4.zero);
                vh.AddVert(s.a + n * w2, c1, Vector4.zero);
                vh.AddVert(s.a - n * w2, c1, Vector4.zero);
                vh.AddVert(s.a - n * (w2 + f), c0, Vector4.zero);
                vh.AddVert(s.b + n * (w2 + f), c0, Vector4.zero);
                vh.AddVert(s.b + n * w2, c1, Vector4.zero);
                vh.AddVert(s.b - n * w2, c1, Vector4.zero);
                vh.AddVert(s.b - n * (w2 + f), c0, Vector4.zero);
                for (int band = 0; band < 3; band++)
                {
                    int a0 = vi + band, a1 = vi + band + 1, b0 = vi + 4 + band, b1 = vi + 5 + band;
                    vh.AddTriangle(a0, b0, b1);
                    vh.AddTriangle(a0, b1, a1);
                }
                vi += 8;
            }
        }
    }
}
