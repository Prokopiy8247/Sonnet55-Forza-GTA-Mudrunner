using System;
using UnityEngine;
using UnityEngine.Rendering;
using MudRunner.Ground;

namespace MudRunner.Rendering
{
    /// <summary>
    /// Draws the whole ground from a <see cref="GroundMap"/>: 32 m chunks with shared flat grid meshes (5 LODs) displaced in the
    /// vertex shader by the baked height map and the dynamic <see cref="MudField"/>. One material, SRP-Batcher compatible.
    ///
    /// Usage:  var r = new GameObject("Ground").AddComponent&lt;GroundRenderer&gt;(); r.Build(map);
    /// With a <see cref="GroundService"/> in the scene the renderer builds itself from the service map on Start and whenever the
    /// service replaces its map. The LOD selection runs in Update (about 5 Hz sweep, spread over frames, no allocations).
    /// </summary>
    [DefaultExecutionOrder(50)]
    public sealed class GroundRenderer : MonoBehaviour
    {
        public const float ChunkSize = 32f;
        public const int LodCount = 5;
        static readonly int[] LodQuads = { 128, 64, 32, 16, 8 };      // 0.25 m, 0.5 m, 1 m, 2 m, 4 m

        [Header("Setup")]
        [Tooltip("Camera used for LOD selection / culling distance. Defaults to Camera.main.")]
        public Camera targetCamera;
        [Tooltip("Build automatically from GroundService.Instance.Map (Start / MapReplaced).")]
        public bool buildFromGroundService = true;
        [Tooltip("Optional: material template (otherwise Resources 'MudRunner/GroundMaterial', otherwise Shader.Find).")]
        public Material materialTemplate;
        [Tooltip("Physics layer of the chunk objects.")]
        public int chunkLayer = 0;

        [Header("Distances")]
        [Tooltip("Chunks farther than this from the camera are disabled. 0 = use the camera far clip plane.")]
        public float MaxDrawDistance = 0f;
        [Tooltip("Upper distance of LOD0..LOD3 (LOD4 beyond).")]
        public float[] lodDistances = { 40f, 90f, 180f, 400f };
        [Range(0f, 0.3f)] public float lodHysteresis = 0.08f;
        [Tooltip("Full sweeps over all chunks per second (work is spread across frames).")]
        public float lodSweepsPerSecond = 5f;

        [Header("Look")]
        [Tooltip("World size (m) of one repetition of the main surface textures.")]
        public float tileSizeA = 3.2f;
        [Tooltip("World size (m) of the second (rotated) texture scale used to break tiling.")]
        public float tileSizeB = 19.3f;
        public float normalStrength = 1f;
        [Tooltip("Gain on the normals derived from the mud field (ruts).")]
        public float fieldNormalGain = 1f;
        public float rippleStrength = 0.18f;
        [Tooltip(">1: ruts need more depth to hold standing water, <1: less.")]
        public float puddleLevelScale = 1f;
        [Tooltip("Depth (m) of the skirt that hides LOD cracks.")]
        public float skirtDrop = 2.5f;
        [Tooltip("Extra world-space margin for chunk bounds above/below the map heights (field displacement).")]
        public float boundsMargin = 2f;

        // ------------------------------------------------------------------ state
        struct Chunk
        {
            public float minX, maxX, minY, maxY, minZ, maxZ;
            public sbyte lod;                // -1 = disabled
            public MeshFilter filter;
            public MeshRenderer renderer;
        }

        GroundMap map;
        GroundMapTextures mapTextures;
        Material material;
        Mesh[] lodMeshes;
        Chunk[] chunks = Array.Empty<Chunk>();
        readonly int[] lodCounts = new int[LodCount + 1];   // last = disabled
        Transform root;
        int cursor;
        GroundService hookedService;
        float fieldCell = 0.25f;

        public GroundMap Map => map;
        public Material Material => material;
        public int ChunkCount => chunks.Length;
        public int VisibleChunkCount { get; private set; }
        public int VisibleTriangleCount { get; private set; }
        public int ChunksChangedLastCall { get; private set; }
        public int GetLodChunkCount(int lod) => lodCounts[lod];
        public bool IsBuilt => map != null && chunks.Length > 0;

        static readonly int ID_DebugMode = Shader.PropertyToID("_MR_DebugMode");

        // ------------------------------------------------------------------ lifecycle

        void OnEnable() { TryHookService(); }

        void Start()
        {
            TryHookService();
            if (buildFromGroundService && map == null && hookedService != null && hookedService.Map != null)
                Build(hookedService.Map);
        }

        void OnDisable()
        {
            if (hookedService != null) hookedService.MapReplaced -= OnMapReplaced;
            hookedService = null;
        }

        void OnDestroy()
        {
            ReleaseAll();
        }

        void TryHookService()
        {
            var gs = GroundService.Instance;
            if (gs == null || gs == hookedService || !buildFromGroundService) return;
            if (hookedService != null) hookedService.MapReplaced -= OnMapReplaced;
            hookedService = gs;
            hookedService.MapReplaced += OnMapReplaced;
        }

        void OnMapReplaced(GroundMap m) { Build(m); }

        void Update()
        {
            if (hookedService == null && buildFromGroundService) TryHookService();
            if (map == null && buildFromGroundService && hookedService != null && hookedService.Map != null)
                Build(hookedService.Map);                      // service initialised after our Start
            if (chunks.Length == 0) return;
            UpdateLod(false);
        }

        // ------------------------------------------------------------------ public API

        /// <summary>The runtime terrain collider created by <see cref="CreateColliderNow"/> / <see cref="Create"/> (null until then).</summary>
        public Terrain Collider { get; private set; }

        /// <summary>
        /// One-call setup for the game scene: creates a "GroundRenderer" object, builds the chunks from <paramref name="map"/> and
        /// (optionally) the Terrain collider. Call after <c>GroundService.Initialize</c>. Camera defaults to Camera.main.
        /// </summary>
        public static GroundRenderer Create(GroundMap map, Camera camera = null, bool withCollider = true, Transform parent = null)
        {
            var go = new GameObject("GroundRenderer");
            if (parent != null) go.transform.SetParent(parent, false);
            var r = go.AddComponent<GroundRenderer>();
            r.buildFromGroundService = false;      // explicit build below (OnMapReplaced still rebuilds when a service is hooked)
            r.targetCamera = camera;
            r.Build(map);
            if (withCollider) r.CreateColliderNow();
            return r;
        }

        /// <summary>(Re)create the collider-only Terrain (layer Terrain) from the current map.</summary>
        public Terrain CreateColliderNow()
        {
            if (map == null) return null;
            if (Collider != null) GroundColliderBuilder.Destroy(Collider);
            Collider = GroundColliderBuilder.Create(map, transform);
            return Collider;
        }

        /// <summary>Create all GPU resources and chunk objects from the map (replaces any previous build).</summary>
        public void Build(GroundMap newMap)
        {
            if (newMap == null) throw new ArgumentNullException(nameof(newMap));
            ReleaseChunks();
            mapTextures?.Dispose();
            map = newMap;
            if (GroundService.Instance != null && GroundService.Instance.Field != null) fieldCell = GroundService.Instance.Field.cell;

            EnsureMaterial();
            mapTextures = GroundMapTextures.Create(map);
            var tex = GroundTextures.Shared;
            if (lodMeshes == null)
            {
                lodMeshes = new Mesh[LodCount];
                for (int i = 0; i < LodCount; i++) lodMeshes[i] = GroundMeshes.BuildGrid(LodQuads[i], ChunkSize, i);
            }
            BindMaterial(tex);
            BuildChunks();
            UpdateLod(true);
        }

        /// <summary>Re-upload the map textures and rebuild the chunks from the current map data (call after editing the map).</summary>
        public void Rebuild()
        {
            if (map != null) Build(map);
        }

        /// <summary>Set the global debug view: 0 off, 1 surface types, 2 dh, 3 churn, 4 LOD colours, 5 macro+field normal.</summary>
        public static void SetDebugMode(int mode) { Shader.SetGlobalFloat(ID_DebugMode, mode); }

        /// <summary>Re-push inspector tuning values to the material.</summary>
        public void ApplyMaterialSettings()
        {
            if (material == null) return;
            material.SetVector("_GR_Tiling", new Vector4(1f / Mathf.Max(0.1f, tileSizeA), 1f / Mathf.Max(0.1f, tileSizeB), 1f / 53f, 1f / 11.3f));
            material.SetVector("_GR_Misc", new Vector4(skirtDrop, fieldNormalGain, 1f / 0.62f, 0f));
            material.SetVector("_GR_Misc2", new Vector4(normalStrength, rippleStrength, puddleLevelScale, 0f));
        }

        /// <summary>
        /// Select LOD / visibility of the chunks around the camera. force = process every chunk now (use after teleports /
        /// before screenshots); otherwise a time-sliced part of the chunk list is processed.
        /// </summary>
        public void UpdateLod(bool force)
        {
            ChunksChangedLastCall = 0;
            int n = chunks.Length;
            if (n == 0) return;
            if (targetCamera == null) targetCamera = Camera.main;
            if (targetCamera == null) return;

            Vector3 cp = targetCamera.transform.position;
            float maxDist = targetCamera.farClipPlane;
            if (MaxDrawDistance > 0f) maxDist = Mathf.Min(maxDist, MaxDrawDistance);
            int count = n;
            if (!force)
            {
                float dt = Mathf.Min(Time.unscaledDeltaTime, 0.1f);
                count = Mathf.Min(n, Mathf.Max(32, Mathf.CeilToInt(n * dt * lodSweepsPerSecond)));
            }

            float h = lodHysteresis;
            for (int k = 0; k < count; k++)
            {
                ref Chunk c = ref chunks[cursor];
                cursor++; if (cursor >= n) cursor = 0;

                float dx = Mathf.Max(Mathf.Max(c.minX - cp.x, 0f), cp.x - c.maxX);
                float dy = Mathf.Max(Mathf.Max(c.minY - cp.y, 0f), cp.y - c.maxY);
                float dz = Mathf.Max(Mathf.Max(c.minZ - cp.z, 0f), cp.z - c.maxZ);
                float d = Mathf.Sqrt(dx * dx + dy * dy + dz * dz);

                int want;
                if (d > maxDist) want = -1;
                else if (c.lod < 0)
                {
                    want = 0;
                    while (want < LodCount - 1 && d > lodDistances[want]) want++;
                }
                else
                {
                    want = c.lod;
                    while (want < LodCount - 1 && d > lodDistances[want] * (1f + h)) want++;
                    while (want > 0 && d < lodDistances[want - 1] * (1f - h)) want--;
                }

                if (want == c.lod) continue;
                ChunksChangedLastCall++;
                if (c.lod >= 0) lodCounts[c.lod]--; else lodCounts[LodCount]--;
                c.lod = (sbyte)want;
                if (want < 0)
                {
                    c.renderer.enabled = false;
                    lodCounts[LodCount]++;
                }
                else
                {
                    c.filter.sharedMesh = lodMeshes[want];
                    c.renderer.enabled = true;
                    lodCounts[want]++;
                }
            }

            if (ChunksChangedLastCall > 0 || force)
            {
                int vis = 0, tris = 0;
                for (int l = 0; l < LodCount; l++) { vis += lodCounts[l]; tris += lodCounts[l] * GroundMeshes.SurfaceTriangles(LodQuads[l]); }
                VisibleChunkCount = vis; VisibleTriangleCount = tris;
            }
        }

        // ------------------------------------------------------------------ build internals

        void EnsureMaterial()
        {
            if (material != null) return;
            Material tpl = materialTemplate;
            if (tpl == null) tpl = Resources.Load<Material>("MudRunner/GroundMaterial");
            if (tpl != null) material = new Material(tpl);
            else
            {
                var sh = Shader.Find("MudRunner/Ground");
                if (sh == null) throw new InvalidOperationException("Shader 'MudRunner/Ground' not found (add the Resources/MudRunner/GroundMaterial asset or assign materialTemplate).");
                material = new Material(sh);
            }
            material.name = "MR_Ground_Runtime";
            material.enableInstancing = false;
            material.hideFlags = HideFlags.DontSave;
        }

        void BindMaterial(GroundTextures tex)
        {
            var m = material;
            m.SetTexture("_GR_Height", mapTextures.Height);
            m.SetTexture("_GR_NormalMap", mapTextures.NormalMap);
            m.SetTexture("_GR_Control0", mapTextures.Control0);
            m.SetTexture("_GR_Control1", mapTextures.Control1);
            m.SetTexture("_GR_Params", mapTextures.Params);
            m.SetTexture("_GR_Albedo", tex.Albedo);
            m.SetTexture("_GR_Normal", tex.Normal);
            m.SetTexture("_GR_Macro", tex.Macro);
            m.SetTexture("_GR_Detail", tex.DetailNormal);
            m.SetVector("_GR_Map", new Vector4(map.origin.x, map.origin.y, 1f / map.cell, 1f / map.size));
            Vector2 mx = map.Max;
            m.SetVector("_GR_MapRange", new Vector4(map.origin.x, map.origin.y, mx.x, mx.y));
            m.SetVector("_GR_LayerScale0", new Vector4(0.80f, 1.00f, 1.10f, 2.20f));
            m.SetVector("_GR_LayerScale1", new Vector4(0.90f, 0.70f, 0.80f, 1.00f));
            var t = SurfaceDatabase.Table;
            m.SetVector("_GR_WetSens0", new Vector4(t[0].wetnessSensitivity, t[1].wetnessSensitivity, t[2].wetnessSensitivity, t[3].wetnessSensitivity));
            m.SetVector("_GR_WetSens1", new Vector4(t[4].wetnessSensitivity, t[5].wetnessSensitivity, t[6].wetnessSensitivity, t[7].wetnessSensitivity));
            ApplyMaterialSettings();
        }

        void BuildChunks()
        {
            if (root == null)
            {
                var go = new GameObject("GroundChunks") { hideFlags = HideFlags.DontSaveInEditor };
                go.transform.SetParent(transform, false);
                root = go.transform;
            }

            Vector2 mn = map.Min, mx = map.Max;
            int kx0 = Mathf.FloorToInt(mn.x / ChunkSize), kx1 = Mathf.FloorToInt((mx.x - 1e-3f) / ChunkSize);
            int kz0 = Mathf.FloorToInt(mn.y / ChunkSize), kz1 = Mathf.FloorToInt((mx.y - 1e-3f) / ChunkSize);
            int nx = kx1 - kx0 + 1, nz = kz1 - kz0 + 1;
            chunks = new Chunk[nx * nz];
            Array.Clear(lodCounts, 0, lodCounts.Length);

            float shift = fieldCell * 0.5f;                  // vertices sit on the centres of the mud-field texels
            int ci = 0;
            for (int kz = kz0; kz <= kz1; kz++)
                for (int kx = kx0; kx <= kx1; kx++)
                {
                    float x0 = kx * ChunkSize + shift, z0 = kz * ChunkSize + shift;
                    // height range over the map area covered by this chunk
                    float lo = float.MaxValue, hi = float.MinValue;
                    int gx0 = Mathf.Clamp(Mathf.FloorToInt((x0 - map.origin.x) / map.cell), 0, map.size - 1);
                    int gx1 = Mathf.Clamp(Mathf.CeilToInt((x0 + ChunkSize - map.origin.x) / map.cell), 0, map.size - 1);
                    int gz0 = Mathf.Clamp(Mathf.FloorToInt((z0 - map.origin.y) / map.cell), 0, map.size - 1);
                    int gz1 = Mathf.Clamp(Mathf.CeilToInt((z0 + ChunkSize - map.origin.y) / map.cell), 0, map.size - 1);
                    for (int gz = gz0; gz <= gz1; gz++)
                    {
                        int row = gz * map.size;
                        for (int gx = gx0; gx <= gx1; gx++)
                        {
                            float v = map.height[row + gx];
                            if (v < lo) lo = v;
                            if (v > hi) hi = v;
                        }
                    }
                    float yMin = lo - boundsMargin - skirtDrop, yMax = hi + boundsMargin;

                    var go = new GameObject("Chunk_" + kx + "_" + kz) { hideFlags = HideFlags.DontSaveInEditor, layer = chunkLayer };
                    go.transform.SetParent(root, false);
                    go.transform.localPosition = new Vector3(x0, 0f, z0);
                    var mf = go.AddComponent<MeshFilter>();
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.sharedMaterial = material;
                    mr.shadowCastingMode = ShadowCastingMode.On;
                    mr.receiveShadows = true;
                    mr.lightProbeUsage = LightProbeUsage.Off;
                    mr.reflectionProbeUsage = ReflectionProbeUsage.BlendProbesAndSkybox;
                    mr.motionVectorGenerationMode = MotionVectorGenerationMode.ForceNoMotion;
                    mr.allowOcclusionWhenDynamic = false;
                    mr.localBounds = new Bounds(new Vector3(ChunkSize * 0.5f, (yMin + yMax) * 0.5f, ChunkSize * 0.5f), new Vector3(ChunkSize, yMax - yMin, ChunkSize));
                    mr.enabled = false;
                    chunks[ci++] = new Chunk
                    {
                        minX = x0, maxX = x0 + ChunkSize, minZ = z0, maxZ = z0 + ChunkSize, minY = yMin, maxY = yMax,
                        lod = -1, filter = mf, renderer = mr,
                    };
                }
            lodCounts[LodCount] = chunks.Length;
            cursor = 0;
            VisibleChunkCount = 0; VisibleTriangleCount = 0;
        }

        void ReleaseChunks()
        {
            if (root != null)
            {
                if (Application.isPlaying) Destroy(root.gameObject); else DestroyImmediate(root.gameObject);
                root = null;
            }
            chunks = Array.Empty<Chunk>();
            Array.Clear(lodCounts, 0, lodCounts.Length);
            VisibleChunkCount = 0; VisibleTriangleCount = 0;
        }

        void ReleaseAll()
        {
            ReleaseChunks();
            mapTextures?.Dispose(); mapTextures = null;
            if (lodMeshes != null)
            {
                foreach (var m in lodMeshes) if (m != null) { if (Application.isPlaying) Destroy(m); else DestroyImmediate(m); }
                lodMeshes = null;
            }
            if (material != null) { if (Application.isPlaying) Destroy(material); else DestroyImmediate(material); material = null; }
            map = null;
        }
    }
}
