using System;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.Testing
{
    /// <summary>
    /// Programmatic test worlds used by the automated physics tests and the prototype scene.
    /// All maps are centred on the origin (world x/z in [-size/2, size/2]).
    /// </summary>
    public static class TestArena
    {
        public delegate SurfaceType SurfaceFn(float x, float z);
        public delegate float HeightFn(float x, float z);

        public static GroundMap CreateMap(float worldSize, float cell, HeightFn h, SurfaceFn s, Func<float, float, float> extraDepth = null)
        {
            int n = Mathf.RoundToInt(worldSize / cell) + 1;
            var map = new GroundMap(n, cell, new Vector2(-worldSize * 0.5f, -worldSize * 0.5f));
            for (int iz = 0; iz < n; iz++)
                for (int ix = 0; ix < n; ix++)
                {
                    float x = map.origin.x + ix * cell, z = map.origin.y + iz * cell;
                    map.height[iz * n + ix] = h != null ? h(x, z) : 0f;
                    map.SetWeights(ix, iz, s != null ? s(x, z) : SurfaceType.FirmSoil);
                    if (extraDepth != null) map.SetExtraDepth(ix, iz, extraDepth(x, z));
                }
            map.Finalize_();
            return map;
        }

        /// <summary>Install a map into a fresh GroundService (destroys any previous one).</summary>
        public static GroundService Install(GroundMap map, Vector3? focus = null, float wetness = 0.3f)
        {
            if (GroundService.Instance != null) UnityEngine.Object.DestroyImmediate(GroundService.Instance.gameObject);
            var go = new GameObject("GroundService");
            var gs = go.AddComponent<GroundService>();
            gs.wetness = wetness;
            gs.Initialize(map, 0.25f, focus ?? Vector3.zero);
            return gs;
        }

        public static GroundMap Flat(SurfaceType type, float size = 200f)
        {
            return CreateMap(size, 1f, null, (x, z) => type);
        }

        /// <summary>Strips of surface along +Z: each segment is [startZ, endZ) with the given surface; firm elsewhere.</summary>
        public static GroundMap Strips(params (float zStart, float zEnd, SurfaceType type, float extraDepth)[] segs)
        {
            return CreateMap(240f, 1f, null,
                (x, z) =>
                {
                    foreach (var s in segs) if (z >= s.zStart && z < s.zEnd) return s.type;
                    return SurfaceType.FirmSoil;
                },
                (x, z) =>
                {
                    foreach (var s in segs) if (z >= s.zStart && z < s.zEnd) return s.extraDepth;
                    return 0f;
                });
        }

        /// <summary>Uniform slope climbing along +Z (angle in degrees) starting at z = startZ, flat before.</summary>
        public static GroundMap Slope(float angleDeg, SurfaceType type, float startZ = 10f, float size = 240f)
        {
            float t = Mathf.Tan(angleDeg * Mathf.Deg2Rad);
            return CreateMap(size, 1f, (x, z) => z > startZ ? (z - startZ) * t : 0f, (x, z) => z > startZ ? type : SurfaceType.FirmSoil);
        }

        // ------------------------------------------------------------------ rendering showcase (added by the rendering worker)

        /// <summary>Fills the 8 layer weights (any non-negative values, normalised by the map) for a world position.</summary>
        public delegate void WeightsFn(float x, float z, Span<float> weights);

        /// <summary>Like <see cref="CreateMap"/> but with soft multi-layer weights, base wetness and hidden extra depth.</summary>
        public static GroundMap CreateBlendMap(float worldSize, float cell, HeightFn h, WeightsFn weights,
            Func<float, float, float> extraDepth = null, Func<float, float, float> baseWet = null)
        {
            int n = Mathf.RoundToInt(worldSize / cell) + 1;
            var map = new GroundMap(n, cell, new Vector2(-worldSize * 0.5f, -worldSize * 0.5f));
            Span<float> w = stackalloc float[GroundMap.LayerCount];
            for (int iz = 0; iz < n; iz++)
                for (int ix = 0; ix < n; ix++)
                {
                    float x = map.origin.x + ix * cell, z = map.origin.y + iz * cell;
                    map.height[iz * n + ix] = h != null ? h(x, z) : 0f;
                    w.Clear();
                    weights(x, z, w);
                    map.SetWeights(ix, iz, w);
                    if (extraDepth != null) map.SetExtraDepth(ix, iz, extraDepth(x, z));
                    if (baseWet != null) map.SetBaseWetness(ix, iz, baseWet(x, z));
                }
            map.Finalize_();
            return map;
        }

        // layout constants of the showcase: mud basin in the middle, 8 surface bands along x, river valley in +z, steep hill in +x
        public const float ShowcaseBandX0 = -64f, ShowcaseBandWidth = 16f;

        /// <summary>HLSL-style smoothstep(edge0, edge1, x).</summary>
        static float Smooth(float edge0, float edge1, float x)
        {
            float t = Mathf.Clamp01((x - edge0) / (edge1 - edge0));
            return t * t * (3f - 2f * t);
        }

        static float ShowcaseRiverZ(float x) => 120f + 28f * Mathf.Sin(x * 0.02f);
        static float ShowcaseRoadZ(float x) => -95f + 18f * Mathf.Sin(x * 0.017f + 0.5f);

        public static float ShowcaseHeight(float x, float z)
        {
            float h = 5.0f * Mathf.Sin(x * 0.011f + 0.6f) * Mathf.Cos(z * 0.014f - 0.3f)
                    + 2.2f * Mathf.Sin(x * 0.031f + 1.7f) * Mathf.Sin(z * 0.026f)
                    + 1.1f * (Mathf.PerlinNoise((x + 300f) * 0.045f, (z + 300f) * 0.045f) - 0.5f)
                    + 0.25f * (Mathf.PerlinNoise((x + 700f) * 0.19f, (z + 700f) * 0.19f) - 0.5f);
            // flattened bowl for the mud basin
            float r = Mathf.Sqrt(x * x / (100f * 100f) + z * z / (70f * 70f));
            float basin = 1f - Smooth(0.7f, 1.45f, r);
            h = Mathf.Lerp(h, -1.2f + 0.12f * Mathf.Sin(x * 0.09f) * Mathf.Cos(z * 0.12f), basin);
            // river valley
            float d = z - ShowcaseRiverZ(x);
            h -= 5.5f * Mathf.Exp(-(d * d) / (2f * 15f * 15f));
            // steep hill to the east
            h += Smooth(105f, 170f, x) * 42f;
            return h;
        }

        /// <summary>
        /// 400 m showcase map for the ground renderer: rolling hills, a mud basin where the 8 surface types lie side by side as
        /// bands along +x (x = -64..64, 16 m each: Rock, FirmSoil, Grass, Gravel, ShallowMud, DeepMud, Bog, Sand), a gravel road,
        /// a river-valley depression with bog and sand banks (+z) and a steep rocky slope (+x).
        /// </summary>
        public static GroundMap RenderShowcase(float worldSize = 400f, float cell = 1f)
        {
            return CreateBlendMap(worldSize, cell, ShowcaseHeight,
                (x, z, w) =>
                {
                    // background cover
                    float n1 = Mathf.PerlinNoise((x + 400f) * 0.017f, (z + 400f) * 0.017f);
                    float n2 = Mathf.PerlinNoise((x + 900f) * 0.05f, (z + 900f) * 0.05f);
                    float firm = Smooth(0.52f, 0.70f, n1);
                    w[(int)SurfaceType.Grass] = (1f - firm) * (0.7f + 0.3f * n2);
                    w[(int)SurfaceType.FirmSoil] = firm * 0.9f + 0.1f;
                    // steepness -> rock
                    float e = 1.5f;
                    float gx = (ShowcaseHeight(x + e, z) - ShowcaseHeight(x - e, z)) / (2f * e);
                    float gz = (ShowcaseHeight(x, z + e) - ShowcaseHeight(x, z - e)) / (2f * e);
                    float slope = Mathf.Atan(Mathf.Sqrt(gx * gx + gz * gz)) * Mathf.Rad2Deg;
                    float rock = Smooth(24f, 36f, slope + (n2 - 0.5f) * 8f);
                    // gravel road
                    float road = 1f - Smooth(1.5f, 3.2f, Mathf.Abs(z - ShowcaseRoadZ(x)));
                    // river valley: shallow mud shore, bog floor, sand bank
                    float dr = Mathf.Abs(z - ShowcaseRiverZ(x));
                    float valley = 1f - Smooth(16f, 34f, dr);
                    float bog = 1f - Smooth(4f, 11f, dr + (n2 - 0.5f) * 8f);
                    float sand = Smooth(8f, 12f, dr) * (1f - Smooth(14f, 21f, dr));
                    float shore = valley * (1f - bog) * (1f - sand);
                    // mud basin bands
                    float bx = (x - ShowcaseBandX0) / ShowcaseBandWidth;
                    float zFade = 1f - Smooth(34f, 46f, Mathf.Abs(z) + (n2 - 0.5f) * 6f);
                    float xIn = Mathf.Clamp01(Mathf.Min(bx + 0.001f, 8f - bx + 0.001f) * 4f);
                    float band = zFade * xIn;
                    float bandPos = bx * 1f;
                    Span<float> bw = stackalloc float[8];
                    for (int k = 0; k < 8; k++)
                    {
                        float center = k + 0.5f;
                        bw[k] = Mathf.Clamp01(1f - (Mathf.Abs(bandPos - center) - 0.35f) / 0.3f);
                    }
                    float bsum = 0f; for (int k = 0; k < 8; k++) bsum += bw[k];
                    if (bsum > 1e-4f) for (int k = 0; k < 8; k++) bw[k] /= bsum;

                    float baseCover = (1f - rock) * (1f - road * 0.95f) * (1f - valley) * (1f - band);
                    for (int k = 0; k < 8; k++) w[k] *= baseCover;
                    w[(int)SurfaceType.Rock] += rock * (1f - band);
                    w[(int)SurfaceType.Gravel] += road * (1f - band) * (1f - rock);
                    w[(int)SurfaceType.Bog] += bog * valley * (1f - band);
                    w[(int)SurfaceType.Sand] += sand * valley * (1f - band);
                    w[(int)SurfaceType.ShallowMud] += shore * 0.9f * (1f - band);
                    w[(int)SurfaceType.DeepMud] += shore * 0.25f * (1f - band);
                    for (int k = 0; k < 8; k++) w[k] += bw[k] * band;
                },
                (x, z) =>
                {
                    float bx = (x - ShowcaseBandX0) / ShowcaseBandWidth;
                    float band = bx > 0f && bx < 8f && Mathf.Abs(z) < 40f ? 1f : 0f;
                    int k = Mathf.Clamp(Mathf.FloorToInt(bx), 0, 7);
                    float d = k == 4 ? 0.25f : k == 5 ? 0.9f : k == 6 ? 1.3f : 0f;
                    float dr = Mathf.Abs(z - ShowcaseRiverZ(x));
                    return Mathf.Max(d * band, 1.0f * (1f - Smooth(3f, 9f, dr)));
                },
                (x, z) =>
                {
                    float dr = Mathf.Abs(z - ShowcaseRiverZ(x));
                    float bx = (x - ShowcaseBandX0) / ShowcaseBandWidth;
                    bool mud = bx > 4f && bx < 7f && Mathf.Abs(z) < 40f;
                    return Mathf.Max(mud ? 0.35f : 0f, 0.9f * (1f - Smooth(4f, 14f, dr)));
                });
        }
    }
}
