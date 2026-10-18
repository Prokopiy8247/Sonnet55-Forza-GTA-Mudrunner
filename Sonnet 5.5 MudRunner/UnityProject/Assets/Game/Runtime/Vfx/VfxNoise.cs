using UnityEngine;

namespace MudRunner.Vfx
{
    /// <summary>Small deterministic noise toolbox (tileable gradient noise, fbm, voronoi) used by the procedural VFX textures. CPU only, no allocations.</summary>
    public static class VfxNoise
    {
        static uint Hash(uint x, uint y, uint seed)
        {
            unchecked
            {
                uint h = x * 374761393u + y * 668265263u + seed * 2246822519u + 0x9E3779B9u;
                h = (h ^ (h >> 13)) * 1274126177u;
                return h ^ (h >> 16);
            }
        }

        /// <summary>Hash to 0..1.</summary>
        public static float Rand(int x, int y, int seed)
        {
            return (Hash((uint)x, (uint)y, (uint)seed) & 0xFFFFFFu) / 16777215f;
        }

        static int Mod(int a, int m) { int r = a % m; return r < 0 ? r + m : r; }

        static float GradDot(int ix, int iy, float dx, float dy, int seed)
        {
            float a = Rand(ix, iy, seed) * 6.2831853f;
            return Mathf.Cos(a) * dx + Mathf.Sin(a) * dy;
        }

        /// <summary>Tileable gradient (Perlin) noise, 0..1 (centred on 0.5). x,y in lattice units; the pattern repeats every <paramref name="period"/> cells.</summary>
        public static float Perlin(float x, float y, int period, int seed)
        {
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = x - x0, fy = y - y0;
            float u = fx * fx * fx * (fx * (fx * 6f - 15f) + 10f);
            float v = fy * fy * fy * (fy * (fy * 6f - 15f) + 10f);
            int xa = Mod(x0, period), xb = Mod(x0 + 1, period), ya = Mod(y0, period), yb = Mod(y0 + 1, period);
            float g00 = GradDot(xa, ya, fx, fy, seed);
            float g10 = GradDot(xb, ya, fx - 1f, fy, seed);
            float g01 = GradDot(xa, yb, fx, fy - 1f, seed);
            float g11 = GradDot(xb, yb, fx - 1f, fy - 1f, seed);
            float r = Mathf.Lerp(Mathf.Lerp(g00, g10, u), Mathf.Lerp(g01, g11, u), v);
            return Mathf.Clamp01(r * 0.7071f + 0.5f);
        }

        /// <summary>Tileable fbm over the unit square: u,v in 0..1 (wrapping), basePeriod = lattice cells across at octave 0. Returns 0..1.</summary>
        public static float Fbm(float u, float v, int basePeriod, int octaves, int seed, float gain = 0.5f)
        {
            float sum = 0f, amp = 0.5f, tot = 0f; int p = basePeriod;
            for (int i = 0; i < octaves; i++)
            {
                sum += Perlin(u * p, v * p, p, seed + i * 31) * amp;
                tot += amp; amp *= gain; p *= 2;
            }
            return sum / tot;
        }

        /// <summary>Non tileable fbm for radial sprites (large period so nothing repeats inside the sprite).</summary>
        public static float FbmFree(float x, float y, int octaves, int seed, float gain = 0.5f)
        {
            float sum = 0f, amp = 0.5f, tot = 0f, f = 1f;
            for (int i = 0; i < octaves; i++)
            {
                sum += Perlin(x * f + 64f, y * f + 64f, 4096, seed + i * 17) * amp;
                tot += amp; amp *= gain; f *= 2f;
            }
            return sum / tot;
        }

        /// <summary>Tileable voronoi: returns F1 distance (cell units) for u,v in 0..1 with <paramref name="cells"/> cells across.</summary>
        public static float Voronoi(float u, float v, int cells, int seed, out float f2)
        {
            float x = u * cells, y = v * cells;
            int ix = Mathf.FloorToInt(x), iy = Mathf.FloorToInt(y);
            float f1 = 9f; f2 = 9f;
            for (int j = -1; j <= 1; j++)
                for (int i = -1; i <= 1; i++)
                {
                    int cx = ix + i, cy = iy + j;
                    int wx = Mod(cx, cells), wy = Mod(cy, cells);
                    float px = cx + Rand(wx, wy, seed) , py = cy + Rand(wx, wy, seed + 101);
                    float dx = px - x, dy = py - y;
                    float d = Mathf.Sqrt(dx * dx + dy * dy);
                    if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) f2 = d;
                }
            return f1;
        }

        public static float SmoothStep(float a, float b, float x)
        {
            float t = Mathf.Clamp01((x - a) / (b - a));
            return t * t * (3f - 2f * t);
        }
    }
}
