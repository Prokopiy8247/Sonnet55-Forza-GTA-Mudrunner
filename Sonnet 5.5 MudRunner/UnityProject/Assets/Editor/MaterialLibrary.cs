using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Project-owned URP materials for the Blender `MR_*` material names (Docs/ART_SPEC.md §3).
    /// Procedural detail textures (paint wear, brushed metal, rubber, rust, wood grain, bark, foliage, rock, concrete, fabric)
    /// are generated in code and saved as PNG assets, then used by URP/Lit materials. Regenerate with
    ///   Unity.exe -batchmode -nographics -projectPath ... -executeMethod MudRunner.EditorTools.MaterialLibrary.BuildAllFromCli -quit
    /// </summary>
    public static class MaterialLibrary
    {
        public const string Folder = "Assets/Game/Materials";
        public const string TexFolder = "Assets/Game/Materials/Textures";

        struct Def
        {
            public string name; public Color color; public float smooth, metal; public string tex; public float texScale; public bool emissive; public Color emission; public bool transparent;
            public Def(string n, Color c, float s, float m, string t = null, float ts = 1f, bool em = false, Color? ec = null, bool tr = false)
            { name = n; color = c; smooth = s; metal = m; tex = t; texScale = ts; emissive = em; emission = ec ?? Color.black; transparent = tr; }
        }

        static Color C(float r, float g, float b, float a = 1f) { return new Color(r, g, b, a); }

        static readonly Def[] Defs =
        {
            new Def("MR_Paint", C(0.46f,0.38f,0.18f), 0.55f, 0.15f, "paint", 3f),
            new Def("MR_PaintSecondary", C(0.12f,0.12f,0.12f), 0.45f, 0.1f, "paint", 3f),
            new Def("MR_MetalDark", C(0.10f,0.10f,0.11f), 0.4f, 0.8f, "metal", 2f),
            new Def("MR_MetalBright", C(0.6f,0.61f,0.63f), 0.75f, 1.0f, "metal", 2f),
            new Def("MR_Chrome", C(0.85f,0.85f,0.87f), 0.92f, 1.0f),
            new Def("MR_Rust", C(0.36f,0.18f,0.09f), 0.2f, 0.4f, "rust", 2f),
            new Def("MR_Rubber", C(0.035f,0.035f,0.035f), 0.15f, 0f, "rubber", 4f),
            new Def("MR_Rim", C(0.22f,0.22f,0.22f), 0.5f, 0.9f, "metal", 2f),
            new Def("MR_Glass", C(0.18f,0.26f,0.28f,0.32f), 0.95f, 0f, null, 1f, false, null, true),
            new Def("MR_LightHead", C(0.95f,0.93f,0.8f), 0.9f, 0f, null, 1f, true, C(2.2f,2.1f,1.7f)),
            new Def("MR_LightTail", C(0.75f,0.05f,0.04f), 0.8f, 0f, null, 1f, true, C(0.9f,0.05f,0.04f)),
            new Def("MR_LightAmber", C(0.9f,0.5f,0.05f), 0.8f, 0f, null, 1f, true, C(1.2f,0.55f,0.05f)),
            new Def("MR_InteriorDark", C(0.07f,0.07f,0.07f), 0.3f, 0f, "fabric", 4f),
            new Def("MR_SeatFabric", C(0.14f,0.12f,0.09f), 0.1f, 0f, "fabric", 6f),
            new Def("MR_PlasticBlack", C(0.045f,0.045f,0.045f), 0.35f, 0f, "rubber", 4f),
            new Def("MR_Cable", C(0.3f,0.3f,0.32f), 0.5f, 0.9f, "metal", 4f),
            new Def("MR_Wood", C(0.42f,0.28f,0.15f), 0.2f, 0f, "wood", 2f),
            new Def("MR_Bark", C(0.22f,0.15f,0.10f), 0.1f, 0f, "bark", 2f),
            new Def("MR_LogEnd", C(0.55f,0.40f,0.22f), 0.15f, 0f, "wood", 1f),
            new Def("MR_Foliage", C(0.10f,0.25f,0.08f), 0.2f, 0f, "foliage", 3f),
            new Def("MR_Rock", C(0.40f,0.39f,0.36f), 0.15f, 0f, "rock", 2f),
            new Def("MR_Moss", C(0.17f,0.27f,0.10f), 0.1f, 0f, "foliage", 3f),
            new Def("MR_Concrete", C(0.50f,0.50f,0.48f), 0.1f, 0f, "concrete", 2f),
            new Def("MR_RoofMetal", C(0.30f,0.18f,0.12f), 0.3f, 0.5f, "rust", 3f),
            new Def("MR_Hazard", C(0.9f,0.7f,0.05f), 0.4f, 0f, "paint", 2f),
            new Def("MR_Canvas", C(0.35f,0.38f,0.25f), 0.05f, 0f, "fabric", 5f),
            new Def("MR_Sand", C(0.6f,0.52f,0.35f), 0.05f, 0f, "concrete", 4f),
        };

        static readonly Dictionary<string, Material> cache = new Dictionary<string, Material>();

        [MenuItem("MudRunner/Build/Material Library")]
        public static void BuildAll()
        {
            Directory.CreateDirectory(Folder); Directory.CreateDirectory(TexFolder);
            cache.Clear();
            var textures = new Dictionary<string, Texture2D>();
            foreach (var d in Defs)
            {
                Texture2D tex = null;
                if (d.tex != null && !textures.TryGetValue(d.tex, out tex)) { tex = MakeTexture(d.tex); textures[d.tex] = tex; }
                var path = Folder + "/" + d.name + ".mat";
                var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
                if (mat == null) { mat = new Material(Shader.Find("Universal Render Pipeline/Lit")); AssetDatabase.CreateAsset(mat, path); }
                mat.shader = Shader.Find("Universal Render Pipeline/Lit");
                mat.SetColor("_BaseColor", d.color);
                mat.SetFloat("_Smoothness", d.smooth);
                mat.SetFloat("_Metallic", d.metal);
                if (tex != null) { mat.SetTexture("_BaseMap", tex); mat.SetTextureScale("_BaseMap", new Vector2(d.texScale, d.texScale)); }
                if (d.emissive) { mat.EnableKeyword("_EMISSION"); mat.SetColor("_EmissionColor", d.emission); mat.globalIlluminationFlags = MaterialGlobalIlluminationFlags.BakedEmissive; }
                if (d.transparent)
                {
                    mat.SetFloat("_Surface", 1f); mat.SetFloat("_Blend", 0f);
                    mat.SetOverrideTag("RenderType", "Transparent");
                    mat.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
                    mat.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
                    mat.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                    mat.SetInt("_ZWrite", 0);
                    mat.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                }
                EditorUtility.SetDirty(mat);
            }
            AssetDatabase.SaveAssets(); AssetDatabase.Refresh();
            Debug.Log("[MudRunner] Material library built: " + Defs.Length + " materials in " + Folder);
        }

        public static void BuildAllFromCli() { BuildAll(); }

        public static Material Get(string name)
        {
            if (cache.TryGetValue(name, out var m) && m != null) return m;
            m = AssetDatabase.LoadAssetAtPath<Material>(Folder + "/" + name + ".mat");
            if (m == null) { BuildAll(); m = AssetDatabase.LoadAssetAtPath<Material>(Folder + "/" + name + ".mat"); }
            cache[name] = m; return m;
        }

        // ------------------------------------------------------------------ procedural textures (tileable, 256^2, greyscale-ish detail around white so _BaseColor tints them)

        static float Hash(int x, int y, int seed) { unchecked { int h = x * 374761393 + y * 668265263 + seed * 1442695041; h = (h ^ (h >> 13)) * 1274126177; return ((h ^ (h >> 16)) & 0xffff) / 65535f; } }

        static float Noise(float x, float y, int period, int seed)
        {
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = x - x0, fy = y - y0; fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
            int xa = ((x0 % period) + period) % period, xb = (xa + 1) % period, ya = ((y0 % period) + period) % period, yb = (ya + 1) % period;
            float a = Hash(xa, ya, seed), b = Hash(xb, ya, seed), c = Hash(xa, yb, seed), d = Hash(xb, yb, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fy);
        }

        static float Fbm(float u, float v, int baseFreq, int oct, int seed)
        {
            float s = 0, amp = 0.5f, tot = 0; int f = baseFreq;
            for (int i = 0; i < oct; i++) { s += Noise(u * f, v * f, f, seed + i * 17) * amp; tot += amp; amp *= 0.5f; f *= 2; }
            return s / tot;
        }

        static Texture2D MakeTexture(string kind)
        {
            const int N = 256;
            var tex = new Texture2D(N, N, TextureFormat.RGBA32, true, false);
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = x / (float)N, v = y / (float)N; float g;
                    switch (kind)
                    {
                        case "paint": g = 0.86f + 0.14f * Fbm(u, v, 8, 4, 1) - 0.12f * Mathf.Pow(Fbm(u, v, 24, 3, 9), 6f) * 3f; break;           // subtle orange-peel + chips
                        case "metal": g = 0.8f + 0.2f * Noise(u * 4, v * 128, 128, 3) * 0.5f + 0.1f * Fbm(u, v, 16, 3, 4); break;                    // brushed streaks
                        case "rust": { float n = Fbm(u, v, 6, 5, 5); g = 0.45f + 0.55f * Mathf.SmoothStep(0.3f, 0.75f, n); break; }
                        case "rubber": g = 0.7f + 0.3f * Fbm(u, v, 32, 3, 6); break;
                        case "wood": g = 0.65f + 0.35f * Mathf.Sin((v * 14f + Fbm(u, v, 4, 3, 7) * 3f) * Mathf.PI * 2f) * 0.5f + 0.1f * Fbm(u, v, 32, 2, 8); g = Mathf.Clamp01(g); break;
                        case "bark": { float n = Fbm(u * 0.25f + 0f, v, 4, 5, 10); float ridge = Mathf.Abs(Mathf.Sin((u * 10f + Fbm(u, v, 6, 3, 11) * 2f) * Mathf.PI)); g = 0.35f + 0.65f * (0.55f * ridge + 0.45f * n); break; }
                        case "foliage": g = 0.55f + 0.45f * Fbm(u, v, 16, 4, 12); break;
                        case "rock": { float n = Fbm(u, v, 5, 6, 13); float cr = Mathf.Abs(Fbm(u, v, 9, 3, 14) - 0.5f); g = 0.5f + 0.5f * n - (cr < 0.025f ? 0.25f : 0f); g = Mathf.Clamp01(g); break; }
                        case "concrete": g = 0.7f + 0.3f * Fbm(u, v, 12, 5, 15) - (Hash(x / 3, y / 3, 16) > 0.995f ? 0.3f : 0f); break;
                        default: g = 0.75f + 0.25f * ((x + y) % 2 == 0 ? 1f : 0.6f) * Fbm(u, v, 48, 2, 17); break; // fabric weave
                    }
                    byte b = (byte)Mathf.Clamp(Mathf.RoundToInt(g * 255f), 0, 255);
                    px[y * N + x] = new Color32(b, b, b, 255);
                }
            tex.SetPixels32(px); tex.Apply(true);
            string path = TexFolder + "/MR_detail_" + kind + ".png";
            File.WriteAllBytes(path, tex.EncodeToPNG());
            Object.DestroyImmediate(tex);
            AssetDatabase.ImportAsset(path);
            var imp = (TextureImporter)AssetImporter.GetAtPath(path);
            imp.textureType = TextureImporterType.Default; imp.sRGBTexture = true; imp.mipmapEnabled = true; imp.wrapMode = TextureWrapMode.Repeat; imp.anisoLevel = 8;
            imp.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }
    }
}
