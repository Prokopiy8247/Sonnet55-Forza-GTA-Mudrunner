using System;
using System.Runtime.CompilerServices;
using UnityEngine;

namespace MudRunner.WorldGen
{
    /// <summary>
    /// Deterministic, thread-safe (read-only after construction) gradient noise plus integer hashing helpers.
    /// Nothing in here touches UnityEngine.Random or Mathf.PerlinNoise so it can run on worker threads and gives
    /// identical results for identical seeds.
    /// </summary>
    public sealed class WorldNoise
    {
        readonly byte[] perm = new byte[512];
        readonly float[] gx = new float[256];
        readonly float[] gz = new float[256];

        public readonly uint seed;

        public WorldNoise(uint seed)
        {
            this.seed = seed;
            var rng = new Rng(seed ^ 0xA511E9B3u);
            var p = new byte[256];
            for (int i = 0; i < 256; i++) p[i] = (byte)i;
            for (int i = 255; i > 0; i--)
            {
                int j = (int)(rng.Next() % (uint)(i + 1));
                byte t = p[i]; p[i] = p[j]; p[j] = t;
            }
            for (int i = 0; i < 512; i++) perm[i] = p[i & 255];
            for (int i = 0; i < 256; i++)
            {
                float a = rng.Next01() * Mathf.PI * 2f;
                gx[i] = Mathf.Cos(a); gz[i] = Mathf.Sin(a);
            }
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static float Fade(float t) { return t * t * t * (t * (t * 6f - 15f) + 10f); }

        /// <summary>Classic gradient noise, range about [-1, 1].</summary>
        public float Perlin(float x, float z)
        {
            int xi = (int)Mathf.Floor(x), zi = (int)Mathf.Floor(z);
            float xf = x - xi, zf = z - zi;
            int x0 = xi & 255, z0 = zi & 255;
            int h00 = perm[perm[x0] + z0], h10 = perm[perm[x0 + 1] + z0];
            int h01 = perm[perm[x0] + z0 + 1], h11 = perm[perm[x0 + 1] + z0 + 1];
            float n00 = gx[h00] * xf + gz[h00] * zf;
            float n10 = gx[h10] * (xf - 1f) + gz[h10] * zf;
            float n01 = gx[h01] * xf + gz[h01] * (zf - 1f);
            float n11 = gx[h11] * (xf - 1f) + gz[h11] * (zf - 1f);
            float u = Fade(xf), v = Fade(zf);
            float a = n00 + (n10 - n00) * u;
            float b = n01 + (n11 - n01) * u;
            return (a + (b - a) * v) * 1.41421356f;
        }

        /// <summary>Fractal sum of Perlin octaves, normalised to about [-1, 1].</summary>
        public float Fbm(float x, float z, int octaves, float lacunarity = 2f, float gain = 0.5f)
        {
            float sum = 0f, amp = 1f, norm = 0f, f = 1f;
            for (int i = 0; i < octaves; i++)
            {
                sum += amp * Perlin(x * f + i * 37.17f, z * f - i * 19.31f);
                norm += amp; amp *= gain; f *= lacunarity;
            }
            return sum / norm;
        }

        /// <summary>Ridged multifractal, 0..1 (sharp crests).</summary>
        public float Ridged(float x, float z, int octaves, float lacunarity = 2f, float gain = 0.5f)
        {
            float sum = 0f, amp = 1f, norm = 0f, f = 1f;
            for (int i = 0; i < octaves; i++)
            {
                float n = 1f - Mathf.Abs(Perlin(x * f + i * 11.7f, z * f + i * 5.3f));
                n *= n;
                sum += amp * n; norm += amp; amp *= gain; f *= lacunarity;
            }
            return sum / norm;
        }

        // ------------------------------------------------------------------ integer hashing (placement jitter etc.)

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static uint Hash(int x, int z, uint seed)
        {
            uint h = (uint)x * 0x9E3779B1u ^ (uint)z * 0x85EBCA77u ^ (seed + 0x165667B1u) * 0xC2B2AE3Du;
            h ^= h >> 15; h *= 0x2C1B3C6Du; h ^= h >> 12; h *= 0x297A2D39u; h ^= h >> 15;
            return h;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static float Hash01(int x, int z, uint seed) { return (Hash(x, z, seed) >> 8) * (1f / 16777216f); }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static float Smooth(float e0, float e1, float x)
        {
            float t = (x - e0) / (e1 - e0);
            t = t < 0f ? 0f : (t > 1f ? 1f : t);
            return t * t * (3f - 2f * t);
        }
    }

    /// <summary>Small deterministic PRNG (xorshift32 / splitmix seeding).</summary>
    public struct Rng
    {
        uint s;
        public Rng(uint seed)
        {
            uint z = seed + 0x9E3779B9u;
            z = (z ^ (z >> 16)) * 0x85EBCA6Bu; z = (z ^ (z >> 13)) * 0xC2B2AE35u; z ^= z >> 16;
            s = z == 0 ? 0x1234567u : z;
        }
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public uint Next() { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s; }
        public float Next01() { return (Next() >> 8) * (1f / 16777216f); }
        public float Range(float a, float b) { return a + (b - a) * Next01(); }
        public int Range(int a, int bExclusive) { return a + (int)(Next() % (uint)(bExclusive - a)); }
    }
}
