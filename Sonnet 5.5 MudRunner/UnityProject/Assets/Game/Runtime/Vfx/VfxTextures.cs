using UnityEngine;

namespace MudRunner.Vfx
{
    /// <summary>
    /// Procedural textures of the VFX layer (nothing is imported). All are generated lazily once and cached.
    /// Sprite textures store a VIEW-SPACE normal in RGB (x right, y up, z towards the camera, *0.5+0.5) and the coverage in A, so the
    /// particle shader can light billboards as if they were small 3D lumps / puffs (sun + ambient) instead of flat decals.
    /// </summary>
    public static class VfxTextures
    {
        static Texture2D puff, blob, droplet, foam, ring, water, cloud, dirt;

        public static Texture2D Puff => Get(ref puff, BuildPuff);
        public static Texture2D Blob => Get(ref blob, BuildBlob);
        public static Texture2D Droplet => Get(ref droplet, BuildDroplet);
        public static Texture2D Foam => Get(ref foam, BuildFoam);
        public static Texture2D Ring => Get(ref ring, BuildRing);
        /// <summary>Tileable 256^2: RG = normal xy, B = height, A = lacy foam mask.</summary>
        public static Texture2D Water => Get(ref water, BuildWater);
        /// <summary>Tileable 256^2 noise set for the sky: R broad clouds, G detail, B billows, A coverage macro.</summary>
        public static Texture2D Cloud => Get(ref cloud, BuildCloud);
        /// <summary>Tileable 128^2: R patches, G speckle, B splatter cells, A mid fbm (vehicle dirt).</summary>
        public static Texture2D Dirt => Get(ref dirt, BuildDirt);

        public static void DestroyAll()
        {
            Kill(ref puff); Kill(ref blob); Kill(ref droplet); Kill(ref foam); Kill(ref ring); Kill(ref water); Kill(ref cloud); Kill(ref dirt);
        }

        static void Kill(ref Texture2D t) { if (t != null) { if (Application.isPlaying) Object.Destroy(t); else Object.DestroyImmediate(t); } t = null; }

        static Texture2D Get(ref Texture2D slot, System.Func<Texture2D> build)
        {
            if (slot == null) slot = build();
            return slot;
        }

        static Texture2D Make(string name, int w, int h, Color32[] px, bool mips, TextureWrapMode wrap, int aniso = 1)
        {
            var t = new Texture2D(w, h, TextureFormat.RGBA32, mips, true) { name = name, wrapMode = wrap, filterMode = FilterMode.Bilinear, anisoLevel = aniso, hideFlags = HideFlags.DontSave };
            t.SetPixels32(px);
            t.Apply(mips, true);
            return t;
        }

        static byte B(float v) { return (byte)Mathf.Clamp(Mathf.RoundToInt(v * 255f), 0, 255); }

        static Color32 Pack(Vector3 n, float a)
        {
            n.Normalize();
            return new Color32(B(n.x * 0.5f + 0.5f), B(n.y * 0.5f + 0.5f), B(n.z * 0.5f + 0.5f), B(a));
        }

        /// <summary>Normal (x right, y up, z out) from a height field with unit pixel spacing 'scale' (height units per pixel step).</summary>
        static Vector3 NormalFromHeights(float[] hgt, int w, int h, int x, int y, float strength)
        {
            float hl = hgt[y * w + Mathf.Max(0, x - 1)], hr = hgt[y * w + Mathf.Min(w - 1, x + 1)];
            float hd = hgt[Mathf.Max(0, y - 1) * w + x], hu = hgt[Mathf.Min(h - 1, y + 1) * w + x];
            return new Vector3(-(hr - hl) * strength, -(hu - hd) * strength, 1f);
        }

        // ------------------------------------------------------------------ billowy puff (smoke / dust / spray / slurry)
        // 2x2 atlas of 128^2 frames
        static Texture2D BuildPuff()
        {
            const int F = 128, A = 2, W = F * A;
            var px = new Color32[W * W];
            var hgt = new float[F * F]; var alp = new float[F * F];
            for (int frame = 0; frame < A * A; frame++)
            {
                int seed = 11 + frame * 37;
                for (int y = 0; y < F; y++)
                    for (int x = 0; x < F; x++)
                    {
                        float u = (x + 0.5f) / F * 2f - 1f, v = (y + 0.5f) / F * 2f - 1f;
                        float r = Mathf.Sqrt(u * u + v * v);
                        float n1 = VfxNoise.FbmFree(u * 1.3f + frame * 5.1f, v * 1.3f + frame * 2.7f, 3, seed);
                        float n2 = VfxNoise.FbmFree(u * 3.1f + frame * 1.9f, v * 3.1f - frame * 4.3f, 3, seed + 7);
                        float rad = 0.62f + 0.38f * (n1 - 0.5f) * 2f;
                        float shape = 1f - r / Mathf.Max(0.2f, rad);
                        float a = VfxNoise.SmoothStep(0f, 0.7f, shape + 0.20f * (n2 - 0.5f));
                        a *= a * (3f - 2f * a);                       // extra soft edge
                        // billowy relief: sphere + noise lumps
                        float hh = Mathf.Sqrt(Mathf.Max(0f, 1f - Mathf.Min(1f, r * r))) * (0.65f + 0.7f * n2) + 0.35f * n1;
                        hgt[y * F + x] = hh; alp[y * F + x] = Mathf.Clamp01(a);
                    }
                int ox = (frame % A) * F, oy = (frame / A) * F;
                for (int y = 0; y < F; y++)
                    for (int x = 0; x < F; x++)
                    {
                        float u = (x + 0.5f) / F * 2f - 1f, v = (y + 0.5f) / F * 2f - 1f;
                        Vector3 n = NormalFromHeights(hgt, F, F, x, y, 9f);
                        // blend to the plain sphere normal near the rim so the silhouette shades smoothly
                        float r = Mathf.Min(1f, Mathf.Sqrt(u * u + v * v));
                        Vector3 sph = new Vector3(u * 0.85f, v * 0.85f, Mathf.Sqrt(Mathf.Max(0.05f, 1f - r * r * 0.72f)));
                        n = Vector3.Lerp(sph, n.normalized, 0.55f);
                        px[(oy + y) * W + ox + x] = Pack(n, alp[y * F + x]);
                    }
            }
            return Make("VFX_Puff", W, W, px, true, TextureWrapMode.Clamp, 1);
        }

        // ------------------------------------------------------------------ chunky mud / pebble lump (hard silhouette)
        // 2x2 atlas of 128^2 frames
        static Texture2D BuildBlob()
        {
            const int F = 128, A = 2, W = F * A;
            var px = new Color32[W * W];
            var hgt = new float[F * F]; var alp = new float[F * F];
            for (int frame = 0; frame < A * A; frame++)
            {
                int seed = 91 + frame * 53;
                float off = frame * 3.7f;
                for (int y = 0; y < F; y++)
                    for (int x = 0; x < F; x++)
                    {
                        float u = (x + 0.5f) / F * 2f - 1f, v = (y + 0.5f) / F * 2f - 1f;
                        float r = Mathf.Sqrt(u * u + v * v);
                        float ang = Mathf.Atan2(v, u);
                        float edge = VfxNoise.FbmFree(Mathf.Cos(ang) * 1.8f + off, Mathf.Sin(ang) * 1.8f + off * 0.5f, 3, seed);
                        float edge2 = VfxNoise.FbmFree(Mathf.Cos(ang) * 4.5f + 9f + off, Mathf.Sin(ang) * 4.5f - off, 2, seed + 3);
                        float rad = 0.66f + 0.13f * (edge - 0.5f) * 2f + 0.018f * (edge2 - 0.5f) * 2f;
                        rad = Mathf.Clamp(rad, 0.5f, 0.82f);
                        float s = r / rad;
                        float a = 1f - VfxNoise.SmoothStep(0.88f, 1.0f, s);
                        float crag = VfxNoise.FbmFree(u * 3.3f + off, v * 3.3f, 3, seed + 11);
                        float ridged = 1f - Mathf.Abs(VfxNoise.FbmFree(u * 3f - off, v * 3f, 2, seed + 21) * 2f - 1f);
                        float hh = Mathf.Sqrt(Mathf.Max(0f, 1f - Mathf.Min(1f, s * s))) * (0.7f + 0.55f * crag) + 0.10f * ridged;
                        hgt[y * F + x] = hh; alp[y * F + x] = a;
                    }
                int ox = (frame % A) * F, oy = (frame / A) * F;
                for (int y = 0; y < F; y++)
                    for (int x = 0; x < F; x++)
                    {
                        Vector3 n = NormalFromHeights(hgt, F, F, x, y, 11f);
                        px[(oy + y) * W + ox + x] = Pack(n, alp[y * F + x]);
                    }
            }
            return Make("VFX_Blob", W, W, px, true, TextureWrapMode.Clamp, 1);
        }

        // ------------------------------------------------------------------ droplet (round, crisp)
        static Texture2D BuildDroplet()
        {
            const int S = 64;
            var px = new Color32[S * S];
            for (int y = 0; y < S; y++)
                for (int x = 0; x < S; x++)
                {
                    float u = (x + 0.5f) / S * 2f - 1f, v = (y + 0.5f) / S * 2f - 1f;
                    float r = Mathf.Sqrt(u * u + v * v);
                    float a = 1f - VfxNoise.SmoothStep(0.55f, 0.98f, r);
                    Vector3 n = new Vector3(u * 0.9f, v * 0.9f, Mathf.Sqrt(Mathf.Max(0.05f, 1f - Mathf.Min(1f, r * r))));
                    px[y * S + x] = Pack(n, a);
                }
            return Make("VFX_Droplet", S, S, px, true, TextureWrapMode.Clamp, 1);
        }

        // ------------------------------------------------------------------ foam sheet (lacy bubble patches), 2x2 atlas of 128^2
        static Texture2D BuildFoam()
        {
            const int F = 128, A = 2, W = F * A;
            var px = new Color32[W * W];
            for (int frame = 0; frame < A * A; frame++)
            {
                int seed = 301 + frame * 29;
                int ox = (frame % A) * F, oy = (frame / A) * F;
                for (int y = 0; y < F; y++)
                    for (int x = 0; x < F; x++)
                    {
                        float u = (x + 0.5f) / F * 2f - 1f, v = (y + 0.5f) / F * 2f - 1f;
                        float r = Mathf.Sqrt(u * u + v * v);
                        float n1 = VfxNoise.FbmFree(u * 1.6f + frame * 3.3f, v * 1.6f - frame * 1.7f, 3, seed);
                        float rad = 0.70f + 0.30f * (n1 - 0.5f) * 2f;
                        float patch = 1f - VfxNoise.SmoothStep(0.30f, 1.0f, r / Mathf.Max(0.25f, rad));
                        float f2;
                        float f1 = VfxNoise.Voronoi((u * 0.5f + 0.5f + frame * 0.13f) % 1f, (v * 0.5f + 0.5f) % 1f, 9, seed, out f2);
                        float bubbles = 1f - VfxNoise.SmoothStep(0.12f, 0.46f, f1);
                        float lace = VfxNoise.SmoothStep(0.42f, 0.62f, VfxNoise.FbmFree(u * 5.5f + frame, v * 5.5f, 3, seed + 5));
                        float cov = Mathf.Clamp01(0.30f + 0.70f * Mathf.Max(lace, bubbles));
                        float a = patch * cov;
                        px[(oy + y) * W + ox + x] = new Color32(128, 128, 255, B(a));
                    }
            }
            return Make("VFX_Foam", W, W, px, true, TextureWrapMode.Clamp, 1);
        }

        // ------------------------------------------------------------------ ripple ring
        static Texture2D BuildRing()
        {
            const int S = 128;
            var px = new Color32[S * S];
            for (int y = 0; y < S; y++)
                for (int x = 0; x < S; x++)
                {
                    float u = (x + 0.5f) / S * 2f - 1f, v = (y + 0.5f) / S * 2f - 1f;
                    float r = Mathf.Sqrt(u * u + v * v);
                    float ang = Mathf.Atan2(v, u);
                    float wob = 0.03f * Mathf.Sin(ang * 5f) + 0.02f * Mathf.Sin(ang * 11f + 1f);
                    float d = r + wob;
                    float main = Mathf.Exp(-Mathf.Pow((d - 0.78f) / 0.075f, 2f));
                    float inner = 0.45f * Mathf.Exp(-Mathf.Pow((d - 0.52f) / 0.055f, 2f));
                    float a = Mathf.Clamp01(main + inner) * (1f - VfxNoise.SmoothStep(0.88f, 1f, r));
                    px[y * S + x] = new Color32(128, 128, 255, B(a));
                }
            return Make("VFX_Ring", S, S, px, true, TextureWrapMode.Clamp, 1);
        }

        // ------------------------------------------------------------------ water: tileable normal + height + lacy foam
        static Texture2D BuildWater()
        {
            const int N = 256;
            var hgt = new float[N * N];
            var lace = new float[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = x / (float)N, v = y / (float)N;
                    // domain-warped tileable fbm; two ridged octaves give sharp wave crests
                    float wu = u + 0.035f * (VfxNoise.Perlin(u * 6f, v * 6f, 6, 3) - 0.5f);
                    float wv = v + 0.035f * (VfxNoise.Perlin(u * 6f, v * 6f, 6, 4) - 0.5f);
                    float h = VfxNoise.Fbm(wu, wv, 4, 4, 5, 0.55f);
                    float rg = 1f - Mathf.Abs(VfxNoise.Perlin(wu * 12f, wv * 12f, 12, 7) * 2f - 1f);
                    float rg2 = 1f - Mathf.Abs(VfxNoise.Perlin(wu * 24f, wv * 24f, 24, 8) * 2f - 1f);
                    hgt[y * N + x] = h * 1.0f + rg * 0.28f + rg2 * 0.12f;
                    float f2;
                    float f1 = VfxNoise.Voronoi(u, v, 10, 17, out f2);
                    float edge = f2 - f1;
                    float cells = 1f - VfxNoise.SmoothStep(0.0f, 0.22f, edge);
                    float fb = VfxNoise.Fbm(u, v, 8, 3, 23);
                    lace[y * N + x] = Mathf.Clamp01(cells * 0.9f + (fb - 0.5f) * 0.9f + 0.1f);
                }
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    int xl = (x - 1 + N) % N, xr = (x + 1) % N, yd = (y - 1 + N) % N, yu = (y + 1) % N;
                    float dx = (hgt[y * N + xr] - hgt[y * N + xl]) * 0.5f;
                    float dy = (hgt[yu * N + x] - hgt[yd * N + x]) * 0.5f;
                    float s = 22f;
                    Vector2 g = new Vector2(-dx * s, -dy * s);
                    px[y * N + x] = new Color32(B(g.x * 0.5f + 0.5f), B(g.y * 0.5f + 0.5f), B(hgt[y * N + x] * 0.7f), B(lace[y * N + x]));
                }
            return Make("VFX_Water", N, N, px, true, TextureWrapMode.Repeat, 4);
        }

        // ------------------------------------------------------------------ sky noise
        static Texture2D BuildCloud()
        {
            const int N = 256;
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = x / (float)N, v = y / (float)N;
                    float r = VfxNoise.Fbm(u, v, 4, 5, 41, 0.52f);
                    float g = VfxNoise.Fbm(u, v, 8, 4, 53, 0.5f);
                    float f2; float f1 = VfxNoise.Voronoi(u, v, 6, 61, out f2);
                    float bil = 1f - Mathf.Clamp01(f1 * 1.1f);
                    float a = VfxNoise.Fbm(u, v, 3, 3, 71, 0.5f);
                    px[y * N + x] = new Color32(B(r), B(g), B(bil), B(a));
                }
            return Make("VFX_Cloud", N, N, px, true, TextureWrapMode.Repeat, 2);
        }

        // ------------------------------------------------------------------ vehicle dirt
        static Texture2D BuildDirt()
        {
            const int N = 128;
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = x / (float)N, v = y / (float)N;
                    float r = VfxNoise.Fbm(u, v, 3, 4, 81, 0.55f);
                    float g = VfxNoise.Fbm(u, v, 16, 3, 83, 0.6f);
                    float f2; float f1 = VfxNoise.Voronoi(u, v, 14, 85, out f2);
                    float cell = 1f - Mathf.Clamp01(f1 * 1.25f);
                    float a = VfxNoise.Fbm(u, v, 8, 3, 87, 0.5f);
                    px[y * N + x] = new Color32(B(r), B(g), B(cell), B(a));
                }
            return Make("VFX_Dirt", N, N, px, true, TextureWrapMode.Repeat, 4);
        }
    }
}
