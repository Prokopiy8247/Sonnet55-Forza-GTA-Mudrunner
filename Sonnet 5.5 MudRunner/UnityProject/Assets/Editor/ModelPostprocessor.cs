using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Import settings for every Blender FBX under Assets/Game/Art: metres, no cameras/lights/animation, optimised meshes,
    /// and `MR_*` materials remapped to the project material library (Assets/Game/Materials).
    /// </summary>
    public sealed class ModelPostprocessor : AssetPostprocessor
    {
        static bool IsArt(string path) { return path.StartsWith("Assets/Game/Art/") && path.EndsWith(".fbx", System.StringComparison.OrdinalIgnoreCase); }

        void OnPreprocessModel()
        {
            if (!IsArt(assetPath)) return;
            var m = (ModelImporter)assetImporter;
            m.globalScale = 1f;
            m.useFileScale = true;
            m.importCameras = false; m.importLights = false; m.importBlendShapes = false; m.importVisibility = false;
            m.animationType = ModelImporterAnimationType.None;
            m.importAnimation = false;
            m.meshCompression = ModelImporterMeshCompression.Off;
            m.isReadable = true;                  // collision proxies / prop placement need mesh bounds & vertices
            m.optimizeMeshPolygons = true; m.optimizeMeshVertices = true;
            m.weldVertices = true;
            m.importNormals = ModelImporterNormals.Import;
            m.importTangents = ModelImporterTangents.CalculateMikk;
            m.generateSecondaryUV = false;
            m.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;
            m.materialLocation = ModelImporterMaterialLocation.InPrefab;
        }

        void OnPostprocessModel(GameObject root)
        {
            if (!IsArt(assetPath)) return;
            foreach (var r in root.GetComponentsInChildren<Renderer>(true))
            {
                var mats = r.sharedMaterials;
                bool changed = false;
                for (int i = 0; i < mats.Length; i++)
                {
                    if (mats[i] == null) continue;
                    string n = mats[i].name;
                    if (!n.StartsWith("MR_")) continue;
                    int dot = n.IndexOf('.');                 // Blender duplicates: MR_Paint.001
                    if (dot > 0) n = n.Substring(0, dot);
                    var lib = AssetDatabase.LoadAssetAtPath<Material>(MaterialLibrary.Folder + "/" + n + ".mat");
                    if (lib != null) { mats[i] = lib; changed = true; }
                }
                if (changed) r.sharedMaterials = mats;
            }
        }
    }
}
