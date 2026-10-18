using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Stand-in water surface: a semi-transparent blue mesh generated from the <see cref="WaterMap"/> raster (row-run merged quads in
    /// 64 m blocks). Vertex colours carry the current (rg) and the water depth (b) for a future water shader. Isolated on purpose: replace
    /// this component / call by the real water renderer without touching the world builders.
    /// </summary>
    public static class WaterSurfaceMesh
    {
        public const int BlockCells = 64;

        public static Material CreateMaterial()
        {
            Shader sh = Shader.Find("Universal Render Pipeline/Lit");
            if (sh == null) sh = Shader.Find("Standard");
            var m = new Material(sh) { name = "MR_Water_StandIn", hideFlags = HideFlags.DontSave };
            Color c = new Color(0.10f, 0.27f, 0.33f, 0.66f);
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c);
            if (m.HasProperty("_Color")) m.SetColor("_Color", c);
            if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", 0.96f);
            if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", 0f);
            if (m.HasProperty("_Surface"))
            {
                m.SetFloat("_Surface", 1f); m.SetFloat("_Blend", 0f);
                m.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha); m.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
                if (m.HasProperty("_SrcBlendAlpha")) { m.SetFloat("_SrcBlendAlpha", (float)BlendMode.One); m.SetFloat("_DstBlendAlpha", (float)BlendMode.OneMinusSrcAlpha); }
                m.SetFloat("_ZWrite", 0f);
                m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                m.SetOverrideTag("RenderType", "Transparent");
                m.SetShaderPassEnabled("ShadowCaster", false);
            }
            m.renderQueue = (int)RenderQueue.Transparent;
            return m;
        }

        /// <summary>Builds the water surface: the VFX layer's WaterRenderer (shader MudRunner/Water); falls back to the flat stand-in mesh when its shader is unavailable.</summary>
        public static GameObject Build(WaterMap water, GroundMap map, Transform parent, Material mat, out int quadCount)
        {
            var wr = MudRunner.Vfx.WaterRenderer.Create(water, map, parent);
            if (wr != null) { quadCount = wr.QuadCount; return wr.gameObject; }
            return BuildStandIn(water, map, parent, mat, out quadCount);
        }

        /// <summary>Stand-in: one mesh object per 64 m block that contains water. Returns the parent; quadCount = total quads.</summary>
        public static GameObject BuildStandIn(WaterMap water, GroundMap map, Transform parent, Material mat, out int quadCount)
        {
            quadCount = 0;
            var root = new GameObject("WaterSurface");
            root.transform.SetParent(parent, false);
            int n = water.size;
            int blocks = (n + BlockCells - 1) / BlockCells;
            var verts = new List<Vector3>(4096); var cols = new List<Color32>(4096); var uvs = new List<Vector2>(4096); var tris = new List<int>(8192);
            for (int bz = 0; bz < blocks; bz++)
                for (int bx = 0; bx < blocks; bx++)
                {
                    verts.Clear(); cols.Clear(); uvs.Clear(); tris.Clear();
                    int x0 = bx * BlockCells, z0 = bz * BlockCells;
                    int x1 = Mathf.Min(n, x0 + BlockCells), z1 = Mathf.Min(n, z0 + BlockCells);
                    float minY = float.MaxValue, maxY = float.MinValue;
                    for (int iz = z0; iz < z1; iz++)
                    {
                        int ix = x0;
                        while (ix < x1)
                        {
                            int idx = iz * n + ix;
                            float lv = water.level[idx];
                            if (float.IsNegativeInfinity(lv)) { ix++; continue; }
                            int jx = ix + 1;
                            float sum = lv; int cnt = 1;
                            while (jx < x1)
                            {
                                float l2 = water.level[iz * n + jx];
                                if (float.IsNegativeInfinity(l2) || Mathf.Abs(l2 - lv) > 0.04f) break;
                                sum += l2; cnt++; jx++;
                            }
                            float y = sum / cnt + 0.01f;
                            float xa = water.origin.x + ix * water.cell - 0.5f * water.cell, xb = water.origin.x + jx * water.cell - 0.5f * water.cell;
                            float za = water.origin.y + iz * water.cell - 0.5f * water.cell, zb = za + water.cell;
                            int mid = (ix + jx - 1) / 2;
                            float fx = water.flowX[iz * n + mid] * 0.1f, fz = water.flowZ[iz * n + mid] * 0.1f;
                            float ground = map != null ? map.height[iz * n + mid] : y - 1f;
                            float depth = Mathf.Clamp01((y - ground) / 3f);
                            var c = new Color32((byte)Mathf.Clamp(Mathf.RoundToInt(127.5f + fx * 10f), 0, 255), (byte)Mathf.Clamp(Mathf.RoundToInt(127.5f + fz * 10f), 0, 255), (byte)Mathf.RoundToInt(depth * 255f), 255);
                            int vi = verts.Count;
                            verts.Add(new Vector3(xa, y, za)); verts.Add(new Vector3(xb, y, za)); verts.Add(new Vector3(xb, y, zb)); verts.Add(new Vector3(xa, y, zb));
                            for (int k = 0; k < 4; k++) { cols.Add(c); }
                            uvs.Add(new Vector2(xa, za) * 0.1f); uvs.Add(new Vector2(xb, za) * 0.1f); uvs.Add(new Vector2(xb, zb) * 0.1f); uvs.Add(new Vector2(xa, zb) * 0.1f);
                            tris.Add(vi); tris.Add(vi + 2); tris.Add(vi + 1); tris.Add(vi); tris.Add(vi + 3); tris.Add(vi + 2);
                            if (y < minY) minY = y; if (y > maxY) maxY = y;
                            ix = jx;
                        }
                    }
                    if (verts.Count == 0) continue;
                    var mesh = new Mesh { name = "Water_" + bx + "_" + bz };
                    mesh.indexFormat = IndexFormat.UInt32;
                    mesh.SetVertices(verts); mesh.SetColors(cols); mesh.SetUVs(0, uvs); mesh.SetTriangles(tris, 0);
                    var normals = new Vector3[verts.Count];
                    for (int i = 0; i < normals.Length; i++) normals[i] = Vector3.up;
                    mesh.normals = normals;
                    mesh.RecalculateBounds();
                    var go = new GameObject("Water_" + bx + "_" + bz);
                    go.transform.SetParent(root.transform, false);
                    go.AddComponent<MeshFilter>().sharedMesh = mesh;
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.sharedMaterial = mat;
                    mr.shadowCastingMode = ShadowCastingMode.Off;
                    mr.receiveShadows = false;
                    quadCount += verts.Count / 4;
                }
            return root;
        }
    }
}
