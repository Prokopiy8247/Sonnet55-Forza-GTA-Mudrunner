using System;
using System.Collections.Generic;
using UnityEngine;

namespace MudRunner.Ground
{
    /// <summary>Soil state at a point after wetness / global tuning, ready for the tyre-soil model.</summary>
    public struct SoilSample
    {
        public float kc, kphi, n;            // Bekker (kN-based)
        public float cohesion;               // kPa
        public float phiDeg, tanPhi;         // friction angle
        public float shearK;                 // Janosi K (m)
        public float softDepth;              // m, total soft layer (incl. hidden depth)
        public float viscosity;              // 0..1
        public float compactionGain, digRate, unitWeight, bulldozeFactor, hardGrip;
        public float wet;                    // effective wetness 0..1
        public float fluidity;               // rut relax rate (1/s)
        public SurfaceType dominant;
    }

    /// <summary>
    /// Owns the <see cref="GroundMap"/> and the <see cref="MudField"/> of the running world, applies global
    /// mud tuning (debug menu) and wetness (rain), and keeps the GPU mirror of the field in sync.
    /// </summary>
    [DefaultExecutionOrder(-100)]
    public sealed class GroundService : MonoBehaviour
    {
        public static GroundService Instance { get; private set; }

        public GroundMap Map { get; private set; }
        public MudField Field { get; private set; }

        [Header("Global mud tuning (debug menu)")]
        [Tooltip("Multiplies the thickness of the soft layer (deeper bogs).")]
        public float mudDepthScale = 1f;
        [Tooltip(">1 = softer ground (bearing moduli are divided by this).")]
        public float softnessScale = 1f;
        [Tooltip("Global wetness 0..1 (rain raises it, drying lowers it).")]
        [Range(0f, 1f)] public float wetness = 0.3f;
        [Tooltip("Multiplier for how fast ruts flow back.")]
        public float rutRelaxScale = 1f;

        [Header("Field window focus")]
        public Transform focus;

        public float fieldCellSize = 0.25f;

        // global shader properties (consumed by the ground renderer / water)
        static readonly int ID_MudTex = Shader.PropertyToID("_MR_MudField");
        static readonly int ID_MudParams = Shader.PropertyToID("_MR_MudParams");        // x = cell size, y = window world size, z = 1/windowWorldSize, w = enabled
        static readonly int ID_Wetness = Shader.PropertyToID("_MR_Wetness");
        static readonly int ID_MapParams = Shader.PropertyToID("_MR_MapParams");        // x,y = origin, z = world size, w = 1/worldSize
        static readonly int ID_MudWindowOrigin = Shader.PropertyToID("_MR_MudWindowOrigin"); // xy = world XZ of the field window's min corner (used by the ground shader to fade the window border)

        readonly List<Transform> extraFocus = new List<Transform>();

        public event Action<GroundMap> MapReplaced;

        void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
        }

        /// <summary>
        /// Release the singleton slot right now. <c>Destroy</c> only takes effect at the end of the frame, so a world switch that
        /// destroys the old service and creates a new one in the same frame would otherwise let the new one see the old
        /// <see cref="Instance"/> in Awake and destroy itself (no ground, vehicles fall through the world).
        /// </summary>
        public void Retire()
        {
            if (Instance == this) Instance = null;
            gameObject.SetActive(false);
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
            Field?.DestroyGpuResources();
        }

        /// <summary>Install a map and (re)create the deformation field.</summary>
        public void Initialize(GroundMap map, float cellSize = 0.25f, Vector3? initialFocus = null)
        {
            Map = map;
            fieldCellSize = cellSize;
            Field?.DestroyGpuResources();
            Field = new MudField(cellSize);
            Field.CreateGpuResources();
            Field.Recenter(initialFocus ?? new Vector3(map.Center.x, 0f, map.Center.y), true);
            PushShaderGlobals();
            MapReplaced?.Invoke(map);
        }

        public void AddFocus(Transform t) { if (t != null && !extraFocus.Contains(t)) extraFocus.Add(t); }
        public void RemoveFocus(Transform t) { extraFocus.Remove(t); }

        void FixedUpdate()
        {
            if (Field == null) return;
            Field.StepRelax(Time.fixedDeltaTime, Map, wetness, rutRelaxScale);
        }

        void LateUpdate()
        {
            if (Field == null) return;
            Transform f = focus;
            if (f == null) for (int i = 0; i < extraFocus.Count; i++) if (extraFocus[i] != null) { f = extraFocus[i]; break; }
            if (f != null) Field.Recenter(f.position);
            Field.SyncGpu();
            PushShaderGlobals();
        }

        void PushShaderGlobals()
        {
            if (Field == null) return;
            if (Field.GpuTexture != null) Shader.SetGlobalTexture(ID_MudTex, Field.GpuTexture);
            float ws = Field.WindowWorldSize;
            Shader.SetGlobalVector(ID_MudParams, new Vector4(Field.cell, ws, 1f / ws, Field.GpuTexture != null ? 1f : 0f));
            Shader.SetGlobalFloat(ID_Wetness, wetness);
            Vector2 wo = Field.WindowOriginWorld;
            Shader.SetGlobalVector(ID_MudWindowOrigin, new Vector4(wo.x, wo.y, 0f, 0f));
            if (Map != null)
                Shader.SetGlobalVector(ID_MapParams, new Vector4(Map.origin.x, Map.origin.y, Map.WorldSize, 1f / Map.WorldSize));
        }

        // ------------------------------------------------------------------ queries used by physics

        /// <summary>Macro (undeformed) ground height. Falls back to 0 outside the map.</summary>
        public float GroundHeight(float x, float z) => Map != null ? Map.SampleHeight(x, z) : 0f;

        /// <summary>Effective (deformed) ground height = macro + field offset.</summary>
        public float SurfaceHeight(float x, float z)
        {
            float h = Map != null ? Map.SampleHeight(x, z) : 0f;
            return Field != null ? h + Field.SampleDh(x, z) : h;
        }

        /// <summary>Soil at (x,z) with wetness and global tuning applied (field churn/compaction NOT included).</summary>
        public SoilSample SampleSoil(float x, float z)
        {
            SoilSample s = default;
            if (Map == null || !Map.Contains(x, z))
            {
                SurfaceParams p = SurfaceDatabase.Table[(int)SurfaceType.FirmSoil];
                Fill(ref s, p, 0f, 0f, SurfaceType.FirmSoil);
                return s;
            }
            Span<float> w = stackalloc float[GroundMap.LayerCount];
            Map.SampleWeights(x, z, w);
            GroundMap.Blend(w, out SurfaceParams bp);
            int best = 0; float bw = -1f;
            for (int k = 0; k < w.Length; k++) if (w[k] > bw) { bw = w[k]; best = k; }
            Fill(ref s, bp, Map.SampleExtraDepth(x, z), Map.SampleBaseWetness(x, z), (SurfaceType)best);
            s.fluidity = Map.SampleFluidity(x, z);
            return s;
        }

        void Fill(ref SoilSample s, in SurfaceParams p, float extraDepth, float baseWet, SurfaceType dominant)
        {
            float wetEff = 1f - (1f - Mathf.Clamp01(baseWet)) * (1f - Mathf.Clamp01(wetness));
            float sens = wetEff * p.wetnessSensitivity;
            float soft = 1f / Mathf.Max(0.05f, softnessScale);
            float kMul = (1f - 0.6f * sens) * soft;
            s.kc = p.kc * kMul;
            s.kphi = p.kphi * kMul;
            s.n = p.n;
            s.cohesion = p.cohesion * (1f - 0.5f * sens);
            s.tanPhi = Mathf.Tan(p.frictionAngle * Mathf.Deg2Rad) * (1f - 0.3f * sens);
            s.phiDeg = Mathf.Atan(s.tanPhi) * Mathf.Rad2Deg;
            s.shearK = p.shearK * (1f + 0.3f * sens);
            bool soft_ = p.softDepth > 0.001f;
            s.softDepth = soft_ ? (p.softDepth + extraDepth) * mudDepthScale * (1f + 0.35f * sens) : extraDepth * mudDepthScale;
            s.viscosity = p.viscosity;
            s.compactionGain = p.compactionGain;
            s.digRate = p.digRate;
            s.unitWeight = p.unitWeight;
            s.bulldozeFactor = p.bulldozeFactor;
            s.hardGrip = p.hardGrip * (1f - 0.35f * sens);
            s.wet = wetEff;
            s.dominant = dominant;
            s.fluidity = 0f;
        }

        public void SetWetness(float w) { wetness = Mathf.Clamp01(w); }
    }
}
