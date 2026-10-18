using System.IO;
using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Creates the base material assets of the VFX shaders in Assets/Game/Runtime/Vfx/Resources/MudRunner/Vfx so the shaders are included in player builds
    /// (VfxResources loads them from Resources, with Shader.Find as the editor fallback). Runs once after editor load if they are missing.
    /// </summary>
    [InitializeOnLoad]
    public static class VfxMaterialAssets
    {
        const string Dir = "Assets/Game/Runtime/Vfx/Resources/MudRunner/Vfx";
        static readonly (string shader, string asset)[] Items =
        {
            ("MudRunner/VfxParticle", "VfxParticle"), ("MudRunner/Water", "Water"), ("MudRunner/Sky", "Sky"), ("MudRunner/Rain", "Rain"),
        };

        static VfxMaterialAssets()
        {
            EditorApplication.delayCall += () => { try { Ensure(); } catch (System.Exception e) { Debug.LogWarning("[MudRunner] VFX material assets: " + e.Message); } };
        }

        [MenuItem("MudRunner/Vfx/Create Material Assets")]
        public static void Ensure()
        {
            bool any = false;
            foreach (var it in Items)
            {
                string path = Dir + "/" + it.asset + ".mat";
                if (AssetDatabase.LoadAssetAtPath<Material>(path) != null) continue;
                var sh = Shader.Find(it.shader);
                if (sh == null) continue;
                Directory.CreateDirectory(Dir);
                AssetDatabase.CreateAsset(new Material(sh) { name = it.asset }, path);
                any = true;
            }
            if (any) { AssetDatabase.SaveAssets(); Debug.Log("[MudRunner] VFX base materials created in " + Dir); }
        }
    }
}
