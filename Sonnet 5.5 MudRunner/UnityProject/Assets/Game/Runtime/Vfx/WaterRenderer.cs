using System;
using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace MudRunner.Vfx
{
    /// <summary>
    /// Water surface renderer (replaces the stand-in WaterSurfaceMesh): builds 32 m chunk meshes from the <see cref="WaterMap"/> raster (quads that touch
    /// at least one water node; the part above the terrain is hidden by the depth test, so the shore line is exact per pixel), vertex colours carry the current
    /// and the murkiness (from the ground surface under the water). Chunks beyond <see cref="maxDistance"/> are disabled (5 Hz check).
    /// Shader <c>MudRunner/Water</c> needs the camera depth + opaque textures: PC_RPAsset has both enabled, and this component also forces them on the main camera.
    /// </summary>
    public sealed class WaterRenderer : MonoBehaviour
    {
        public float maxDistance = 600f;
        public const float ChunkSize = 32f;

        public GroundMap Map { get; private set; }
        public int QuadCount { get; private set; }
        public int ChunkCount => chunks.Count;
        public int VisibleChunks { get; private set; }

        sealed class Chunk { public MeshRenderer mr; public Vector3 center; public float radius; }
        readonly List<Chunk> chunks = new List<Chunk>();
        Material mat;
        float timer;

        public static WaterRenderer Create(WaterMap water, GroundMap map, Transform parent)
        {
            var sh = VfxResources.WaterShader;
            if (sh == null || water == null) return null;
            var go = new GameObject("WaterSurface");
            if (parent != null) go.transform.SetParent(parent, false);
            var wr = go.AddComponent<WaterRenderer>();
            wr.Build(water, map, sh);
            return wr;
        }

        void Build(WaterMap water, GroundMap map, Shader sh)
        {
            Map = map;
            mat = VfxResources.NewMaterial(sh, "VFX_Water");
            mat.SetTexture("_WaterTex", VfxTextures.Water);
            mat.renderQueue = (int)RenderQueue.Transparent - 20;

            int n = water.size; float cell = water.cell;
            int cc = Mathf.Max(4, Mathf.RoundToInt(ChunkSize / cell));
            int chunksPerSide = (n - 1 + cc - 1) / cc;
            var verts = new List<Vector3>(4096); var cols = new List<Color32>(4096); var tris = new List<int>(6144);
            Span<float> w = stackalloc float[GroundMap.LayerCount];
            var lv = new float[4]; var ok = new bool[4];
            for (int cz = 0; cz < chunksPerSide; cz++)
                for (int cx = 0; cx < chunksPerSide; cx++)
                {
                    verts.Clear(); cols.Clear(); tris.Clear();
                    int x0 = cx * cc, z0 = cz * cc, x1 = Mathf.Min(n - 1, x0 + cc), z1 = Mathf.Min(n - 1, z0 + cc);
                    float minY = float.MaxValue, maxY = float.MinValue;
                    for (int iz = z0; iz < z1; iz++)
                        for (int ix = x0; ix < x1; ix++)
                        {
                            int i00 = iz * n + ix;
                            int idx0 = i00, idx1 = i00 + 1, idx2 = i00 + n + 1, idx3 = i00 + n;     // (0,0) (1,0) (1,1) (0,1)
                            int cnt = 0; float sum = 0f; float fx = 0f, fz = 0f;
                            for (int k = 0; k < 4; k++)
                            {
                                int id = k == 0 ? idx0 : k == 1 ? idx1 : k == 2 ? idx2 : idx3;
                                float l = water.level[id];
                                ok[k] = !float.IsNegativeInfinity(l); lv[k] = l;
                                if (ok[k]) { cnt++; sum += l; fx += water.flowX[id]; fz += water.flowZ[id]; }
                            }
                            if (cnt == 0) continue;
                            float avg = sum / cnt;
                            fx = fx / cnt * 0.1f; fz = fz / cnt * 0.1f;
                            float murk = 0f;
                            float wx = water.origin.x + (ix + 0.5f) * cell, wz = water.origin.y + (iz + 0.5f) * cell;
                            if (map != null)
                            {
                                map.SampleWeights(wx, wz, w);
                                murk = Mathf.Clamp01(w[(int)SurfaceType.ShallowMud] * 0.55f + w[(int)SurfaceType.DeepMud] * 0.85f + w[(int)SurfaceType.Bog] + w[(int)SurfaceType.Grass] * 0.1f);
                            }
                            var c = new Color32(Enc(fx), Enc(fz), (byte)Mathf.RoundToInt(murk * 255f), 255);
                            int vi = verts.Count;
                            for (int k = 0; k < 4; k++)
                            {
                                float y = ok[k] ? lv[k] : avg;
                                float px = water.origin.x + (ix + (k == 1 || k == 2 ? 1 : 0)) * cell;
                                float pz = water.origin.y + (iz + (k >= 2 ? 1 : 0)) * cell;
                                verts.Add(new Vector3(px, y + 0.005f, pz)); cols.Add(c);
                                if (y < minY) minY = y; if (y > maxY) maxY = y;
                            }
                            tris.Add(vi); tris.Add(vi + 2); tris.Add(vi + 1); tris.Add(vi); tris.Add(vi + 3); tris.Add(vi + 2);
                        }
                    if (verts.Count == 0) continue;
                    var mesh = new Mesh { name = "Water_" + cx + "_" + cz, hideFlags = HideFlags.DontSave };
                    if (verts.Count > 65000) mesh.indexFormat = IndexFormat.UInt32;
                    mesh.SetVertices(verts); mesh.SetColors(cols); mesh.SetTriangles(tris, 0);
                    mesh.RecalculateBounds();
                    var go = new GameObject("Water_" + cx + "_" + cz);
                    go.transform.SetParent(transform, false);
                    go.AddComponent<MeshFilter>().sharedMesh = mesh;
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.sharedMaterial = mat;
                    mr.shadowCastingMode = ShadowCastingMode.Off;
                    mr.receiveShadows = false;
                    mr.lightProbeUsage = LightProbeUsage.Off;
                    mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
                    chunks.Add(new Chunk { mr = mr, center = mesh.bounds.center, radius = mesh.bounds.extents.magnitude });
                    QuadCount += verts.Count / 4;
                }
        }

        static byte Enc(float flow) { return (byte)Mathf.Clamp(Mathf.RoundToInt((flow / 6.4f * 0.5f + 0.5f) * 255f), 0, 255); }

        void Update()
        {
            timer -= Time.unscaledDeltaTime;
            if (timer > 0f) return;
            timer = 0.2f;
            var cam = Camera.main;
            if (cam == null) return;
            var data = cam.GetUniversalAdditionalCameraData();
            if (data != null) { if (!data.requiresDepthTexture) data.requiresDepthTexture = true; if (!data.requiresColorTexture) data.requiresColorTexture = true; }
            Vector3 cp = cam.transform.position;
            int vis = 0;
            for (int i = 0; i < chunks.Count; i++)
            {
                var c = chunks[i];
                bool on = (c.center - cp).magnitude < maxDistance + c.radius;
                if (c.mr.enabled != on) c.mr.enabled = on;
                if (on) vis++;
            }
            VisibleChunks = vis;
        }

        void OnDestroy()
        {
            foreach (var c in chunks)
                if (c.mr != null) { var mf = c.mr.GetComponent<MeshFilter>(); if (mf != null && mf.sharedMesh != null) Destroy(mf.sharedMesh); }
            if (mat != null) Destroy(mat);
        }
    }
}
