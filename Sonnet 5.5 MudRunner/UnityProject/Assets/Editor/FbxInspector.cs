using System.Text;
using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Batch helper: prints transform + mesh-bounds info of every node in an imported model so the
    /// Blender -> Unity axis/scale/pivot conventions can be verified without opening the editor UI.
    /// CLI: -executeMethod MudRunner.EditorTools.FbxInspector.InspectFromCli -fbx Assets/Game/Art/x.fbx
    /// </summary>
    public static class FbxInspector
    {
        public static void InspectFromCli()
        {
            string path = GetArg("-fbx");
            if (string.IsNullOrEmpty(path)) { Debug.LogError("[MudRunner] -fbx <asset path> required"); return; }
            AssetDatabase.Refresh();
            Inspect(path);
        }

        static string GetArg(string name)
        {
            var args = System.Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++) if (args[i] == name) return args[i + 1];
            return null;
        }

        public static void Inspect(string path)
        {
            var go = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (go == null) { Debug.LogError("[MudRunner] cannot load " + path); return; }
            var sb = new StringBuilder();
            sb.AppendLine("[MudRunner] FBX " + path + " root=" + go.name + " scale=" + go.transform.localScale + " rot=" + go.transform.eulerAngles);
            foreach (var t in go.GetComponentsInChildren<Transform>(true))
            {
                var mf = t.GetComponent<MeshFilter>();
                string b = "";
                if (mf != null && mf.sharedMesh != null)
                {
                    var mb = mf.sharedMesh.bounds;
                    var wc = t.TransformPoint(mb.center);
                    b = " meshCenterWorld=" + F(wc) + " size=" + F(mb.size) + " verts=" + mf.sharedMesh.vertexCount;
                }
                sb.AppendLine("[MudRunner]   " + t.name + " pos=" + F(t.position) + " rot=" + F(t.eulerAngles) + " scl=" + F(t.lossyScale) + b);
            }
            Debug.Log(sb.ToString());
        }

        static string F(Vector3 v) { return "(" + v.x.ToString("F3") + "," + v.y.ToString("F3") + "," + v.z.ToString("F3") + ")"; }
    }
}
