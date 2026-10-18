using System.Collections.Generic;
using MudRunner.Ground;
using UnityEngine;
using static MudRunner.WorldGen.PgLayout;

namespace MudRunner.WorldGen
{
    /// <summary>Proving ground part of the terrain pipeline: analytic height features, surface overrides, water of the ford.</summary>
    public sealed partial class TerrainGenerator
    {
        /// <summary>Corridor through the ridge west of the proving ground (the service road passes here).</summary>
        float PgPass(float x, float z)
        {
            if (x < 720f || x > 850f) return 0f;
            float dz = (z + 196f) / 24f;
            return Mathf.Exp(-dz * dz) * Sm(730f, 770f, x) * (1f - Sm(805f, 840f, x));
        }

        float PgFeatures(float x, float z)
        {
            float d = 0f;
            // steep mud hill + firm return slope
            if (x > HillX - 70f && x < HillX + 70f && z > HillZ0 - 4f && z < HillZ(5) + 4f)
            {
                float P = HillProfile(z);
                if (P > 0f)
                {
                    float lat = Mathf.Max(0f, Mathf.Abs(x - HillX) - HillHalfTop) * HillSide;
                    d += Mathf.Max(0f, P - lat);
                }
            }
            // side slope bench
            if (x > SideX0 - 12f && x < SideX1 + 12f && Mathf.Abs(z - SideZ) < 30f)
            {
                float tilt = Mathf.Tan(SideTiltDeg(x) * Mathf.Deg2Rad);
                float v = z - SideZ;
                float core = SideBench + tilt * Mathf.Clamp(v, -SideHalf, SideHalf);
                float val;
                if (v > SideHalf) val = Mathf.Lerp(core, 0f, Sm(SideHalf, 22f, v));
                else if (v < -SideHalf) val = Mathf.Lerp(core, 0f, Sm(-SideHalf, -22f, v));
                else val = core;
                float ramp = Sm(SideX0 - 8f, SideX0 + 2f, x) * (1f - Sm(SideX1 - 2f, SideX1 + 8f, x));
                d += val * ramp;
            }
            // mud pits (dished)
            if (x > SpineX - 12f && x < SpineX + 12f && z > PitZ0(0) - 4f && z < PitZ0(PitCount - 1) + PitLen + 4f)
                for (int k = 0; k < PitCount; k++)
                {
                    float sdf = RectSdf(x, z, SpineX - PitHalfW, SpineX + PitHalfW, PitZ0(k), PitZ0(k) + PitLen);
                    d -= PitDepth * (1f - Sm(-1.2f, 0.8f, sdf));
                }
            // articulation holes
            if (x > SpineX - 5f && x < SpineX + 5f && z > ArtZ0 - 3f && z < ArtZ1 + 3f)
                for (int i = 0; i < ArtStations; i++)
                {
                    ArtItems(i, out _, out Vector2 hole);
                    float dd = Mathf.Sqrt((x - hole.x) * (x - hole.x) + (z - hole.y) * (z - hole.y));
                    d -= 0.4f * (1f - Sm(0.3f, 1.3f, dd));
                }
            // sand box
            if (x > SandX0 - 4f && x < SandX1 + 4f && z > SandZ0 - 4f && z < SandZ1 + 4f)
                d -= 0.18f * (1f - Sm(-2f, 1.5f, RectSdf(x, z, SandX0, SandX1, SandZ0, SandZ1)));
            // ford channel (bed profile across z, channel runs along +x)
            if (z > FordZ0 - 5f && z < FordZ1 + 5f && x > FordX0 - 12f && x < FordX1 + 12f)
            {
                float rel;
                if (z >= FordZ0 && z <= FordZ1) rel = (FordWl - Floor) - FordDepth(z);
                else
                {
                    float dz = z < FordZ0 ? FordZ0 - z : z - FordZ1;
                    rel = Mathf.Lerp(FordWl - Floor, 0f, Sm(0f, 3f, dz));
                }
                float cw = Sm(FordX0 - 8f, FordX0 + 6f, x) * (1f - Sm(FordX1 - 6f, FordX1 + 8f, x));
                d = Mathf.Lerp(d, rel, cw);
            }
            return d;
        }

        float PgHeight(float x, float z, float h)
        {
            if (x < 760f || x > 1040f || z < -340f || z > 340f) return h;
            float sdf = RectSdf(x, z, BowlX0, BowlX1, BowlZ0, BowlZ1);
            float bowl = 1f - Sm(0f, 26f, sdf);
            if (bowl <= 0f) return h;
            // the floor is flat apart from the stations; a little relief in the unused corners
            float f = Floor + PgFeatures(x, z);
            return Mathf.Lerp(h, f, bowl);
        }

        List<TrackDef> PgTracks() { return PgLayout.Tracks(cfg.full); }

        // ------------------------------------------------------------------ surfaces

        static void SetVec(float[] w, SurfaceType t, float a, float rest = 0f)
        {
            for (int k = 0; k < 8; k++) w[k] = 0f;
            w[(int)t] = a;
        }

        static void Blend(float[] w, SurfaceType t, float alpha)
        {
            if (alpha <= 0f) return;
            for (int k = 0; k < 8; k++) w[k] *= (1f - alpha);
            w[(int)t] += alpha;
        }

        /// <summary>Base ground of the proving ground valley (applied before roads): dry packed floor with grass tufts and some gravel.</summary>
        void PgBase(float x, float z, float slope, float[] w, ref float wet, ref float extra)
        {
            if (x < 790f || x > 1030f || z < -310f || z > 310f) return;
            float sdf = RectSdf(x, z, BowlX0, BowlX1, BowlZ0, BowlZ1);
            float bowl = 1f - Sm(0f, 20f, sdf);
            if (bowl <= 0f) return;
            float n3 = noise.Perlin(x * 0.19f + 5f, z * 0.19f - 2f);
            float n2 = noise.Fbm(x * 0.05f, z * 0.05f, 2);
            float g = 0.30f + 0.2f * n2, gr = 0.12f + 0.1f * n3;
            for (int k = 0; k < 8; k++) w[k] = w[k] * (1f - bowl);
            float rockS = Sm(27f, 40f, slope);
            w[(int)SurfaceType.Grass] += bowl * (1f - rockS) * g;
            w[(int)SurfaceType.FirmSoil] += bowl * (1f - rockS) * (0.6f - 0.2f * n2);
            w[(int)SurfaceType.Gravel] += bowl * (1f - rockS) * gr;
            w[(int)SurfaceType.Rock] += bowl * rockS;
            wet = Mathf.Lerp(wet, 0.15f, bowl);
            extra *= 1f - bowl;
        }

        /// <summary>Station surfaces (applied after the roads so they win inside the feature areas).</summary>
        void PgSurface(float x, float z, float h, float slope, float[] w, ref float wet, ref float extra)
        {
            if (x < 790f || x > 1030f || z < -310f || z > 310f) return;
            float sdf = RectSdf(x, z, BowlX0, BowlX1, BowlZ0, BowlZ1);
            if (sdf > 0.5f) return;
            float n3 = noise.Perlin(x * 0.19f + 5f, z * 0.19f - 2f);

            // start / measure pad
            float pad = RectSdf(x, z, PadX0, PadX1, PadZ0, PadZ1);
            if (pad < 3f)
            {
                float a = 1f - Sm(0f, 2.5f, pad + 0.4f * n3);
                Blend(w, SurfaceType.Gravel, a * 0.9f); wet = Mathf.Lerp(wet, 0.05f, a);
                // painted 5 m grid
                if (pad < 0f)
                {
                    float gx = Mathf.Abs(((x - PadX0) % 5f + 5f) % 5f - 0.0f), gz = Mathf.Abs(((z - PadZ0) % 5f + 5f) % 5f - 0.0f);
                    bool line = gx < 0.14f || gx > 4.86f || gz < 0.14f || gz > 4.86f;
                    if (line) Blend(w, SurfaceType.Rock, 0.9f);
                }
            }
            // straight with painted edges and 10 m marks
            if (x > SpineX - 8f && x < SpineX + 8f && z > StraightZ0 - 1f && z < StraightZ1 + 1f)
            {
                float lane = 1f - Sm(5.4f, 6.4f, Mathf.Abs(x - SpineX));
                Blend(w, SurfaceType.Gravel, 0.85f * lane);
                float ex = Mathf.Abs(Mathf.Abs(x - SpineX) - 5.8f);
                bool edge = ex < 0.14f;
                float mz = ((z - StraightZ0) % 10f + 10f) % 10f;
                bool mark = (mz < 0.16f || mz > 9.84f) && Mathf.Abs(x - SpineX) < 5.9f;
                if (edge || mark) Blend(w, SurfaceType.Rock, 0.85f);
                wet = Mathf.Lerp(wet, 0.05f, lane);
            }
            // pit lane: firm run-up/causeways and the pits
            if (x > SpineX - 9f && x < SpineX + 9f && z > PitZ0(0) - 20f && z < PitZ0(PitCount - 1) + PitLen + 12f)
            {
                float lane = 1f - Sm(PitHalfW + 0.6f, PitHalfW + 2f, Mathf.Abs(x - SpineX));
                float inZ = Sm(PitZ0(0) - 20.5f, PitZ0(0) - 19f, z) * (1f - Sm(PitZ0(PitCount - 1) + PitLen + 10f, PitZ0(PitCount - 1) + PitLen + 12f, z));
                Blend(w, SurfaceType.Gravel, 0.8f * lane * inZ);
                for (int k = 0; k < PitCount; k++)
                {
                    float sd = RectSdf(x, z, SpineX - PitHalfW, SpineX + PitHalfW, PitZ0(k), PitZ0(k) + PitLen);
                    float a = 1f - Sm(-0.3f, 0.9f, sd + 0.35f * n3);
                    if (a <= 0f) continue;
                    Blend(w, PitSurface[k], a);
                    if (PitSurface[k] == SurfaceType.DeepMud) { Blend(w, SurfaceType.ShallowMud, 0.12f * a); }
                    wet = Mathf.Lerp(wet, 0.95f, a);
                    extra = Mathf.Lerp(extra, PitExtra[k], a);
                }
            }
            // steep mud hill
            if (x > HillX - 60f && x < HillX + 60f && z > HillZ0 - 6f && z < HillZ(5) + 6f)
            {
                float P = HillProfile(z);
                float lat = Mathf.Abs(x - HillX);
                float onTop = 1f - Sm(HillHalfTop - 1.5f, HillHalfTop + 0.8f, lat);
                float mudZone = 1f - Sm(HillZ(4) - 1f, HillZ(4) + 1.5f, z);          // mud up to the end of the plateau, firm beyond
                mudZone *= Sm(HillZ0 - 2f, HillZ0 + 1f, z);
                if (onTop > 0f)
                {
                    float a = onTop * mudZone;
                    Blend(w, SurfaceType.ShallowMud, 0.9f * a); Blend(w, SurfaceType.DeepMud, 0.12f * a * (0.5f + 0.5f * n3));
                    wet = Mathf.Lerp(wet, 0.92f, a);
                    float f = onTop * (1f - mudZone) * Sm(HillZ(4) - 1f, HillZ(4) + 1.5f, z);
                    Blend(w, SurfaceType.Gravel, 0.5f * f); Blend(w, SurfaceType.FirmSoil, 0.4f * f);
                    wet = Mathf.Lerp(wet, 0.1f, f);
                }
            }
            // side slope track
            if (x > SideX0 - 6f && x < SideX1 + 6f && Mathf.Abs(z - SideZ) < SideHalf + 3f)
            {
                float a = (1f - Sm(SideHalf - 0.5f, SideHalf + 1.5f, Mathf.Abs(z - SideZ) + 0.4f * n3)) * Sm(SideX0 - 4f, SideX0 + 1f, x) * (1f - Sm(SideX1 - 1f, SideX1 + 4f, x));
                Blend(w, SurfaceType.ShallowMud, 0.85f * a); Blend(w, SurfaceType.FirmSoil, 0.1f * a);
                wet = Mathf.Lerp(wet, 0.75f, a);
            }
            // articulation course bed
            if (x > SpineX - 6f && x < SpineX + 6f && z > ArtZ0 - 3f && z < ArtZ1 + 3f)
            {
                float a = (1f - Sm(4f, 5f, Mathf.Abs(x - SpineX))) * Sm(ArtZ0 - 3f, ArtZ0 - 1f, z) * (1f - Sm(ArtZ1 + 1f, ArtZ1 + 3f, z));
                Blend(w, SurfaceType.FirmSoil, 0.7f * a); Blend(w, SurfaceType.Gravel, 0.25f * a);
            }
            // ford
            if (z > FordZ0 - 3f && z < FordZ1 + 3f && x > FordX0 - 2f && x < FordX1 + 2f)
            {
                float zin = z - FordZ0;
                float inside = Sm(-0.2f, 1.5f, zin) * (1f - Sm(FordZ1 - FordZ0 - 1.5f, FordZ1 - FordZ0 + 0.2f, zin));
                float cw = Sm(FordX0, FordX0 + 8f, x) * (1f - Sm(FordX1 - 8f, FordX1, x));
                float a = inside * cw;
                for (int k = 0; k < 8; k++) w[k] *= 1f - a;
                w[(int)SurfaceType.Gravel] += 0.6f * a; w[(int)SurfaceType.Sand] += 0.3f * a; w[(int)SurfaceType.Rock] += 0.1f * a;
                // muddy banks
                float bank = (1f - Sm(0f, 3f, Mathf.Min(Mathf.Abs(z - FordZ0), Mathf.Abs(z - FordZ1)))) * cw * (1f - inside);
                Blend(w, SurfaceType.ShallowMud, 0.55f * bank); wet = Mathf.Max(wet, 0.8f * Mathf.Max(a, bank));
                wet = Mathf.Lerp(wet, 1f, a);
            }
            // sandbox
            {
                float sd = RectSdf(x, z, SandX0, SandX1, SandZ0, SandZ1);
                float a = 1f - Sm(-0.5f, 1.0f, sd + 0.3f * n3);
                Blend(w, SurfaceType.Sand, 0.95f * a); extra = Mathf.Max(extra, 0.15f * a);
            }
            // measuring pad with a painted turning circle and cone grid lines
            float meas = RectSdf(x, z, MeasX0, MeasX1, MeasZ0, MeasZ1);
            if (meas < 3f)
            {
                float a = 1f - Sm(0f, 2.5f, meas + 0.4f * n3);
                Blend(w, SurfaceType.Gravel, 0.9f * a); wet = Mathf.Lerp(wet, 0.05f, a);
                if (meas < 0f)
                {
                    float r = Mathf.Sqrt((x - MeasCenter.x) * (x - MeasCenter.x) + (z - MeasCenter.y) * (z - MeasCenter.y));
                    if (Mathf.Abs(r - 12f) < 0.15f || Mathf.Abs(r - 24f) < 0.15f) Blend(w, SurfaceType.Rock, 0.9f);
                }
            }
            // roads of the proving ground use the generic road overlay (applied before this function), keep their gravel intact on top of the base
        }

        // ------------------------------------------------------------------ water of the ford

        void PgWater(WaterMap water)
        {
            int ix0 = Mathf.Max(0, Mathf.FloorToInt(FordX0 - 4f - origin.x)), ix1 = Mathf.Min(size - 1, Mathf.CeilToInt(FordX1 + 4f - origin.x));
            int iz0 = Mathf.Max(0, Mathf.FloorToInt(FordZ0 - 3f - origin.y)), iz1 = Mathf.Min(size - 1, Mathf.CeilToInt(FordZ1 + 3f - origin.y));
            for (int iz = iz0; iz <= iz1; iz++)
                for (int ix = ix0; ix <= ix1; ix++)
                {
                    float x = origin.x + ix, z = origin.y + iz;
                    int idx = iz * size + ix;
                    float cw = Sm(FordX0 - 8f, FordX0 + 6f, x) * (1f - Sm(FordX1 - 6f, FordX1 + 8f, x));
                    if (cw < 0.98f) continue;
                    if (map.height[idx] < FordWl - 0.02f)
                    {
                        float dn = Mathf.Clamp01(FordDepth(z) / 1.6f);
                        water.level[idx] = FordWl;
                        water.flowX[idx] = (sbyte)Mathf.RoundToInt(FordCurrent * (0.75f + 0.25f * dn) * 10f);
                        water.flowZ[idx] = 0;
                    }
                }
        }

        void PostPg() { }
    }
}
