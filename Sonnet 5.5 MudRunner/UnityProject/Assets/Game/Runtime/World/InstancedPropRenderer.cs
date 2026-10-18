using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Draws every instanced prop (trees, rocks, reeds ...) with Graphics.RenderMeshInstanced: the <see cref="PropSet"/> is sorted into
    /// 32 m cells x types; every frame the cells in range are frustum culled, a LOD (0/1/2) is chosen per cell and type from the distance,
    /// and the cell's matrices are copied into per-(type, LOD) batch buffers of 1023 instances which are flushed as instanced draws.
    /// No GameObject per tree, no per-frame allocations after the first frame.
    /// </summary>
    [DefaultExecutionOrder(100)]
    public sealed class InstancedPropRenderer : MonoBehaviour
    {
        public PropSet set;
        public IPropLibrary library;
        public Camera targetCamera;
        [Tooltip("Multiplier on all draw distances (quality setting).")]
        public float distanceScale = 1f;
        public bool drawShadows = true;
        public bool drawInEditMode;

        PropDef[] defs;
        Matrix4x4[][] bufs;      // [type * 3 + lod]
        int[] bufCount;
        RenderParams[][] rps;    // [type*3+lod][submesh]
        readonly Plane[] planes = new Plane[6];
        int T;

        public int LastDrawnInstances { get; private set; }
        public int LastDrawCalls { get; private set; }
        public int LastCellsVisible { get; private set; }

        public void Init(PropSet s, IPropLibrary lib)
        {
            set = s; library = lib ?? PropLibraries.Current;
            T = s.typeIds.Length;
            defs = new PropDef[T];
            bufs = new Matrix4x4[T * 3][];
            bufCount = new int[T * 3];
            rps = new RenderParams[T * 3][];
            for (int t = 0; t < T; t++)
            {
                defs[t] = library.Get(s.typeIds[t]);
                for (int lod = 0; lod < 3; lod++)
                {
                    var mesh = defs[t].lods[Mathf.Min(lod, defs[t].lods.Length - 1)];
                    bufs[t * 3 + lod] = new Matrix4x4[1023];
                    int subs = mesh != null ? mesh.subMeshCount : 1;
                    rps[t * 3 + lod] = new RenderParams[subs];
                    for (int sIdx = 0; sIdx < subs; sIdx++)
                    {
                        var mat = defs[t].materials[Mathf.Min(sIdx, defs[t].materials.Length - 1)];
                        if (mat != null) mat.enableInstancing = true;
                        var rp = new RenderParams(mat)
                        {
                            shadowCastingMode = (defs[t].castShadows && lod < 2) ? ShadowCastingMode.On : ShadowCastingMode.Off,
                            receiveShadows = true,
                            layer = 0,
                            lightProbeUsage = LightProbeUsage.Off,
                            reflectionProbeUsage = ReflectionProbeUsage.Off,
                            motionVectorMode = MotionVectorGenerationMode.ForceNoMotion,
                        };
                        rps[t * 3 + lod][sIdx] = rp;
                    }
                }
            }
        }

        void LateUpdate()
        {
            if (!Application.isPlaying && !drawInEditMode) return;
            var cam = targetCamera != null ? targetCamera : Camera.main;
            if (cam == null) return;
            Render(cam, false);
        }

        /// <summary>Submit the instanced draws for <paramref name="cam"/> (call right before Camera.Render for captures: restrictToCamera = true).</summary>
        public void Render(Camera cam, bool restrictToCamera)
        {
            if (set == null || defs == null || SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null) return;
            GeometryUtility.CalculateFrustumPlanes(cam, planes);
            Vector3 cp = cam.transform.position;
            float cs = set.cellSize;
            float maxD = 0f;
            for (int t = 0; t < T; t++) maxD = Mathf.Max(maxD, defs[t].maxDist * distanceScale);
            maxD = Mathf.Min(maxD, cam.farClipPlane + 40f);
            int cx0 = Mathf.Max(0, Mathf.FloorToInt((cp.x - maxD - set.gridOrigin.x) / cs)), cx1 = Mathf.Min(set.cellsX - 1, Mathf.FloorToInt((cp.x + maxD - set.gridOrigin.x) / cs));
            int cz0 = Mathf.Max(0, Mathf.FloorToInt((cp.z - maxD - set.gridOrigin.y) / cs)), cz1 = Mathf.Min(set.cellsZ - 1, Mathf.FloorToInt((cp.z + maxD - set.gridOrigin.y) / cs));
            float y0 = set.minY - 1f, y1 = set.maxY + 16f;
            LastDrawnInstances = 0; LastDrawCalls = 0; LastCellsVisible = 0;
            var wb = new Bounds(cp, new Vector3(maxD * 2.2f, 4000f, maxD * 2.2f));
            for (int cz = cz0; cz <= cz1; cz++)
                for (int cx = cx0; cx <= cx1; cx++)
                {
                    float minX = set.gridOrigin.x + cx * cs, minZ = set.gridOrigin.y + cz * cs;
                    float dx = Mathf.Max(Mathf.Max(minX - cp.x, 0f), cp.x - (minX + cs));
                    float dz = Mathf.Max(Mathf.Max(minZ - cp.z, 0f), cp.z - (minZ + cs));
                    float d = Mathf.Sqrt(dx * dx + dz * dz);
                    if (d > maxD) continue;
                    var bounds = new Bounds(new Vector3(minX + cs * 0.5f, (y0 + y1) * 0.5f, minZ + cs * 0.5f), new Vector3(cs + 8f, y1 - y0, cs + 8f));
                    if (!GeometryUtility.TestPlanesAABB(planes, bounds)) continue;
                    LastCellsVisible++;
                    int cell = cz * set.cellsX + cx;
                    for (int t = 0; t < T; t++)
                    {
                        var def = defs[t];
                        float md = def.maxDist * distanceScale;
                        if (d > md) continue;
                        set.CellRange(cell, t, out int a, out int b);
                        if (b <= a) continue;
                        int lod = d < def.lod0Dist * distanceScale ? 0 : d < def.lod1Dist * distanceScale ? 1 : 2;
                        int bi = t * 3 + lod;
                        int n = b - a, src = a;
                        while (n > 0)
                        {
                            int room = 1023 - bufCount[bi];
                            int take = n < room ? n : room;
                            Array.Copy(set.mats, src, bufs[bi], bufCount[bi], take);
                            bufCount[bi] += take; src += take; n -= take;
                            if (bufCount[bi] >= 1023) Flush(bi, t, lod, wb, cam, restrictToCamera);
                        }
                    }
                }
            for (int t = 0; t < T; t++)
                for (int lod = 0; lod < 3; lod++)
                {
                    int bi = t * 3 + lod;
                    if (bufCount[bi] > 0) Flush(bi, t, lod, wb, cam, restrictToCamera);
                }
        }

        void Flush(int bi, int t, int lod, Bounds wb, Camera cam, bool restrict)
        {
            int n = bufCount[bi];
            bufCount[bi] = 0;
            if (n <= 0) return;
            var mesh = defs[t].lods[Mathf.Min(lod, defs[t].lods.Length - 1)];
            if (mesh == null) return;
            var arr = rps[bi];
            for (int s = 0; s < arr.Length; s++)
            {
                var rp = arr[s];
                rp.worldBounds = wb;
                if (restrict) rp.camera = cam;
                if (!drawShadows) rp.shadowCastingMode = ShadowCastingMode.Off;
                Graphics.RenderMeshInstanced(rp, mesh, s, bufs[bi], n, 0);
                LastDrawCalls++;
            }
            LastDrawnInstances += n;
        }
    }
}
