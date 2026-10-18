using System;
using System.Threading.Tasks;
using MudRunner.Ground;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>
    /// Renders the whole <see cref="GroundMap"/> once into a texture (surface tints blended per cell, hillshade, contour lines,
    /// water). The pixel work runs on a worker thread; the texture appears when <see cref="Ready"/> turns true.
    /// One texture per map instance (rebuilt when the world changes).
    /// </summary>
    public sealed class WorldMapTexture
    {
        public const int MaxSize = 2048;
        public GroundMap Map { get; private set; }
        public Texture2D Texture { get; private set; }
        public bool Ready { get; private set; }
        public bool Failed { get; private set; }
        public float GenerationMs { get; private set; }

        Color32[] pixels; Task job; int n;
        public Vector2 Origin => Map.origin;
        public float WorldSize => Map.WorldSize;

        static WorldMapTexture current;

        /// <summary>Returns (and starts generating, if needed) the map texture for <paramref name="map"/>.</summary>
        public static WorldMapTexture For(GroundMap map)
        {
            if (map == null) return null;
            if (current != null && current.Map == map) return current;
            current?.Dispose();
            current = new WorldMapTexture();
            current.Start(map);
            return current;
        }

        public static void Release() { current?.Dispose(); current = null; }

        void Start(GroundMap map)
        {
            Map = map;
            n = Mathf.Min(MaxSize, map.size);
            pixels = new Color32[n * n];
            var tints = new Color[GroundMap.LayerCount];
            for (int i = 0; i < tints.Length; i++)
            {
                Color t = SurfaceDatabase.Table[i].tint;
                // lift the dark mud / bog tones a little and saturate so the map reads on a dark UI
                float lum = t.r * 0.3f + t.g * 0.59f + t.b * 0.11f;
                t = new Color(Mathf.Clamp01(lum + (t.r - lum) * 1.25f), Mathf.Clamp01(lum + (t.g - lum) * 1.25f), Mathf.Clamp01(lum + (t.b - lum) * 1.25f));
                t = new Color(Mathf.Pow(t.r, 0.82f), Mathf.Pow(t.g, 0.82f), Mathf.Pow(t.b, 0.82f));
                tints[i] = t;
            }
            float hmin = map.minHeight, hmax = Mathf.Max(map.maxHeight, map.minHeight + 1f);
            var px = pixels; int nn = n;
            var sw = System.Diagnostics.Stopwatch.StartNew();
            job = Task.Run(() =>
            {
                try { Generate(map, px, nn, hmin, hmax, tints); }
                catch (Exception e) { Debug.LogError("[MudRunner] WorldMapTexture failed: " + e); Failed = true; }
                GenerationMs = (float)sw.Elapsed.TotalMilliseconds;
            });
        }

        /// <summary>Call from the main thread each frame until Ready.</summary>
        public void Poll()
        {
            if (Ready || job == null || !job.IsCompleted || Failed) return;
            Texture = new Texture2D(n, n, TextureFormat.RGBA32, true, false)
            {
                wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Trilinear, anisoLevel = 4, hideFlags = HideFlags.HideAndDontSave, name = "WorldMap"
            };
            Texture.SetPixels32(pixels);
            Texture.Apply(true, false);
            pixels = null; Ready = true;
        }

        /// <summary>Blocks until the worker finished (tests / screenshots).</summary>
        public void WaitReady()
        {
            if (job != null && !job.IsCompleted) { try { job.Wait(20000); } catch { } }
            Poll();
        }

        public void Dispose()
        {
            if (Texture != null) UnityEngine.Object.Destroy(Texture);
            Texture = null; Ready = false;
        }

        static void Generate(GroundMap map, Color32[] px, int n, float hmin, float hmax, Color[] tint)
        {
            int S = map.size;
            float[] hgt = map.height; byte[] wt = map.weights; var water = map.water;
            bool waterSameGrid = water != null && water.size == S;
            float cell = map.cell;
            const float Lx = -0.50f, Ly = 0.72f, Lz = 0.48f;
            float ln = (float)Math.Sqrt(Lx * Lx + Ly * Ly + Lz * Lz);
            float lx = Lx / ln, ly = Ly / ln, lz = Lz / ln;
            float flat = ly;
            float invH = 1f / (hmax - hmin);
            float scaleXY = (S - 1) / (float)(n - 1);
            for (int iz = 0; iz < n; iz++)
            {
                int gz = Math.Min(S - 1, (int)(iz * scaleXY + 0.5f));
                int gz0 = Math.Max(gz - 1, 0), gz1 = Math.Min(gz + 1, S - 1);
                for (int ix = 0; ix < n; ix++)
                {
                    int gx = Math.Min(S - 1, (int)(ix * scaleXY + 0.5f));
                    int gx0 = Math.Max(gx - 1, 0), gx1 = Math.Min(gx + 1, S - 1);
                    int idx = gz * S + gx;
                    float h = hgt[idx];
                    int wo = idx * GroundMap.LayerCount;
                    float r = 0f, g = 0f, b = 0f, sum = 0f;
                    for (int k = 0; k < GroundMap.LayerCount; k++)
                    {
                        float a = wt[wo + k]; if (a <= 0f) continue;
                        r += tint[k].r * a; g += tint[k].g * a; b += tint[k].b * a; sum += a;
                    }
                    if (sum > 0f) { r /= sum; g /= sum; b /= sum; } else { r = g = b = 0.4f; }

                    float dzdx = (hgt[gz * S + gx1] - hgt[gz * S + gx0]) / Math.Max(1f, (gx1 - gx0) * cell);
                    float dzdz = (hgt[gz1 * S + gx] - hgt[gz0 * S + gx]) / Math.Max(1f, (gz1 - gz0) * cell);
                    float inv = 1f / (float)Math.Sqrt(dzdx * dzdx + 1f + dzdz * dzdz);
                    float shade = (-dzdx * lx + 1f * ly - dzdz * lz) * inv;
                    float f = 0.64f + (shade - flat) * 1.7f;
                    f = Math.Max(0.40f, Math.Min(1.40f, f));
                    float hf = (h - hmin) * invH;
                    f *= 0.86f + 0.26f * hf;

                    // contour lines every 10 m (stronger every 50 m)
                    float hr = hgt[gz * S + gx1], hu = hgt[gz1 * S + gx];
                    int c0 = (int)Math.Floor(h * 0.1f), c1 = (int)Math.Floor(hr * 0.1f), c2 = (int)Math.Floor(hu * 0.1f);
                    if (c0 != c1 || c0 != c2)
                    {
                        int hi = Math.Max(c0, Math.Max(c1, c2));
                        f *= hi % 5 == 0 ? 0.70f : 0.84f;
                    }
                    r *= f; g *= f; b *= f;

                    if (water != null)
                    {
                        float wl = waterSameGrid ? water.level[idx] : float.NegativeInfinity;
                        if (!waterSameGrid) { float wx = map.origin.x + gx * map.cell, wz = map.origin.y + gz * map.cell; if (water.Sample(wx, wz, out float s, out _)) wl = s; }
                        if (!float.IsNegativeInfinity(wl) && wl > h + 0.03f)
                        {
                            float depth = wl - h;
                            float a = Math.Min(0.92f, 0.62f + depth * 0.18f);
                            float dk = Math.Max(0.55f, 1f - depth * 0.12f);
                            r = r * (1f - a) + 0.13f * dk * a * (0.9f + 0.2f * f);
                            g = g * (1f - a) + 0.40f * dk * a * (0.9f + 0.2f * f);
                            b = b * (1f - a) + 0.62f * dk * a * (0.9f + 0.2f * f);
                        }
                    }
                    px[iz * n + ix] = new Color32(
                        (byte)Math.Max(0, Math.Min(255, (int)(r * 255f))),
                        (byte)Math.Max(0, Math.Min(255, (int)(g * 255f))),
                        (byte)Math.Max(0, Math.Min(255, (int)(b * 255f))), 255);
                }
            }
        }
    }
}
