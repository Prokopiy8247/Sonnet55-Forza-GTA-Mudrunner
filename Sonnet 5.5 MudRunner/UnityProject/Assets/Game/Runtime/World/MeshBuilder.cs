using System;
using System.Collections.Generic;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>Tiny procedural mesh helper: primitives with flat/smooth normals, up to 4 submeshes, a current transform.</summary>
    public sealed class MeshBuilder
    {
        readonly List<Vector3> v = new List<Vector3>();
        readonly List<Vector3> nrm = new List<Vector3>();
        readonly List<Vector2> uv = new List<Vector2>();
        readonly List<int>[] tris = { new List<int>(), new List<int>(), new List<int>(), new List<int>() };
        public Matrix4x4 xf = Matrix4x4.identity;
        public int sub;
        public float uvScale = 0.5f;

        public int VertexCount => v.Count;

        public void Reset() { xf = Matrix4x4.identity; sub = 0; }

        public void SetTransform(Vector3 pos, Quaternion rot, Vector3? scale = null)
        {
            xf = Matrix4x4.TRS(pos, rot, scale ?? Vector3.one);
        }

        int AddV(Vector3 p, Vector3 n)
        {
            Vector3 wp = xf.MultiplyPoint3x4(p);
            Vector3 wn = xf.MultiplyVector(n);
            wn = wn.sqrMagnitude > 1e-12f ? wn.normalized : Vector3.up;
            v.Add(wp); nrm.Add(wn);
            uv.Add(new Vector2((wp.x + wp.z) * uvScale, wp.y * uvScale));
            return v.Count - 1;
        }

        public void Tri(Vector3 a, Vector3 b, Vector3 c)
        {
            Vector3 n = Vector3.Cross(b - a, c - a);
            if (n.sqrMagnitude < 1e-14f) return;
            n.Normalize();
            int i0 = AddV(a, n), i1 = AddV(b, n), i2 = AddV(c, n);
            var t = tris[sub]; t.Add(i0); t.Add(i1); t.Add(i2);
        }

        public void TriSmooth(Vector3 a, Vector3 na, Vector3 b, Vector3 nb, Vector3 c, Vector3 nc)
        {
            int i0 = AddV(a, na), i1 = AddV(b, nb), i2 = AddV(c, nc);
            var t = tris[sub]; t.Add(i0); t.Add(i1); t.Add(i2);
        }

        /// <summary>Quad a-b-c-d, counter-clockwise seen from the front.</summary>
        public void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            Tri(a, b, c); Tri(a, c, d);
        }

        public void QuadDouble(Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            Quad(a, b, c, d); Quad(d, c, b, a);
        }

        public void Box(Vector3 center, Vector3 size)
        {
            Vector3 h = size * 0.5f;
            Vector3 p000 = center + new Vector3(-h.x, -h.y, -h.z), p100 = center + new Vector3(h.x, -h.y, -h.z);
            Vector3 p010 = center + new Vector3(-h.x, h.y, -h.z), p110 = center + new Vector3(h.x, h.y, -h.z);
            Vector3 p001 = center + new Vector3(-h.x, -h.y, h.z), p101 = center + new Vector3(h.x, -h.y, h.z);
            Vector3 p011 = center + new Vector3(-h.x, h.y, h.z), p111 = center + new Vector3(h.x, h.y, h.z);
            Quad(p001, p101, p111, p011);   // +z
            Quad(p100, p000, p010, p110);   // -z
            Quad(p101, p100, p110, p111);   // +x
            Quad(p000, p001, p011, p010);   // -x
            Quad(p011, p111, p110, p010);   // +y
            Quad(p000, p100, p101, p001);   // -y
        }

        /// <summary>Box from min/max corners.</summary>
        public void BoxMinMax(Vector3 min, Vector3 max) { Box((min + max) * 0.5f, max - min); }

        /// <summary>Cylinder / truncated cone along +Y from <paramref name="b"/> (bottom centre). Smooth side normals.</summary>
        public void Cylinder(Vector3 b, float r0, float r1, float h, int seg, bool capTop = true, bool capBottom = true)
        {
            float slope = (r0 - r1) / Mathf.Max(1e-4f, h);
            for (int i = 0; i < seg; i++)
            {
                float a0 = i / (float)seg * Mathf.PI * 2f, a1 = (i + 1) / (float)seg * Mathf.PI * 2f;
                Vector3 d0 = new Vector3(Mathf.Cos(a0), 0, Mathf.Sin(a0)), d1 = new Vector3(Mathf.Cos(a1), 0, Mathf.Sin(a1));
                Vector3 n0 = (d0 + Vector3.up * slope).normalized, n1 = (d1 + Vector3.up * slope).normalized;
                Vector3 p00 = b + d0 * r0, p10 = b + d1 * r0, p01 = b + d0 * r1 + Vector3.up * h, p11 = b + d1 * r1 + Vector3.up * h;
                TriSmooth(p00, n0, p11, n1, p10, n1);
                if (r1 > 1e-4f) TriSmooth(p00, n0, p01, n0, p11, n1);
                if (capTop && r1 > 1e-4f) Tri(b + Vector3.up * h, p11, p01);
                if (capBottom) Tri(b, p00, p10);
            }
        }

        /// <summary>Cylinder along an arbitrary axis (centre c, length len, radius r).</summary>
        public void CylinderAxis(Vector3 c, Vector3 axis, float len, float r0, float r1, int seg, bool caps = true, int capSub = -1)
        {
            var save = xf;
            Quaternion q = Quaternion.FromToRotation(Vector3.up, axis.normalized);
            xf = save * Matrix4x4.TRS(c, q, Vector3.one);
            int s0 = sub;
            if (capSub < 0) Cylinder(new Vector3(0, -len * 0.5f, 0), r0, r1, len, seg, caps, caps);
            else
            {
                Cylinder(new Vector3(0, -len * 0.5f, 0), r0, r1, len, seg, false, false);
                sub = capSub;
                if (caps)
                {
                    for (int i = 0; i < seg; i++)
                    {
                        float a0 = i / (float)seg * Mathf.PI * 2f, a1 = (i + 1) / (float)seg * Mathf.PI * 2f;
                        Tri(new Vector3(0, len * 0.5f, 0), new Vector3(Mathf.Cos(a1) * r1, len * 0.5f, Mathf.Sin(a1) * r1), new Vector3(Mathf.Cos(a0) * r1, len * 0.5f, Mathf.Sin(a0) * r1));
                        Tri(new Vector3(0, -len * 0.5f, 0), new Vector3(Mathf.Cos(a0) * r0, -len * 0.5f, Mathf.Sin(a0) * r0), new Vector3(Mathf.Cos(a1) * r0, -len * 0.5f, Mathf.Sin(a1) * r0));
                    }
                }
                sub = s0;
            }
            xf = save;
        }

        /// <summary>Beam between two points with a square-ish cross section.</summary>
        public void Beam(Vector3 a, Vector3 b, float w, float t)
        {
            Vector3 d = b - a;
            float len = d.magnitude;
            if (len < 1e-4f) return;
            var save = xf;
            Quaternion q = Quaternion.LookRotation(d / len, Mathf.Abs(Vector3.Dot(d / len, Vector3.up)) > 0.98f ? Vector3.right : Vector3.up);
            xf = save * Matrix4x4.TRS((a + b) * 0.5f, q, Vector3.one);
            Box(Vector3.zero, new Vector3(w, t, len));
            xf = save;
        }

        /// <summary>Faceted lumpy ellipsoid (rocks, bushes, crowns).</summary>
        public void Blob(Vector3 c, Vector3 radii, int seg, int rings, float rough, uint seed, float yMin = -1f)
        {
            var rng = new Rng(seed);
            var pts = new Vector3[(rings + 1) * seg];
            for (int r = 0; r <= rings; r++)
            {
                float pv = r / (float)rings;
                float phi = pv * Mathf.PI;
                for (int s = 0; s < seg; s++)
                {
                    float th = s / (float)seg * Mathf.PI * 2f + (r % 2) * 0.35f;
                    float j = 1f + (rng.Next01() - 0.5f) * 2f * rough;
                    if (r == 0 || r == rings) j = 1f + (rng.Next01() - 0.5f) * rough;
                    Vector3 d = new Vector3(Mathf.Sin(phi) * Mathf.Cos(th), Mathf.Cos(phi), Mathf.Sin(phi) * Mathf.Sin(th));
                    Vector3 p = Vector3.Scale(d, radii) * j;
                    if (p.y < yMin * radii.y) p.y = yMin * radii.y;
                    pts[r * seg + s] = c + p;
                }
            }
            for (int r = 0; r < rings; r++)
                for (int s = 0; s < seg; s++)
                {
                    int s1 = (s + 1) % seg;
                    Vector3 a = pts[r * seg + s], b = pts[r * seg + s1], cc = pts[(r + 1) * seg + s], d = pts[(r + 1) * seg + s1];
                    if (r == 0) Tri(a, d, cc);
                    else if (r == rings - 1) Tri(a, b, cc);
                    else { Tri(a, b, cc); Tri(b, d, cc); }
                }
        }

        public Mesh ToMesh(string name)
        {
            var m = new Mesh { name = name };
            if (v.Count > 65000) m.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            m.SetVertices(v); m.SetNormals(nrm); m.SetUVs(0, uv);
            int subs = 0;
            for (int i = 0; i < tris.Length; i++) if (tris[i].Count > 0) subs = i + 1;
            if (subs == 0) subs = 1;
            m.subMeshCount = subs;
            for (int i = 0; i < subs; i++) m.SetTriangles(tris[i], i, false);
            m.RecalculateBounds();
            m.RecalculateTangents();
            return m;
        }

        public int SubCount { get { int subs = 0; for (int i = 0; i < tris.Length; i++) if (tris[i].Count > 0) subs = i + 1; return Mathf.Max(1, subs); } }
        public int TriangleCount { get { int c = 0; for (int i = 0; i < tris.Length; i++) c += tris[i].Count / 3; return c; } }
    }
}
