using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Editor helpers for the UI verification screenshots (Captures/ui_*.png are written by the PlayMode test UiTests.Capture_AllViews,
    /// run with:  GFX=1 Tools/rt.sh ui1 UiTests ).
    ///   - MudRunner/UI/Open Captures Folder
    ///   - MudRunner/UI/Build Contact Sheet   (also batch: Tools/ub.sh sheet MudRunner.EditorTools.UiCapture.BuildContactSheet)
    ///     composes every Captures/ui_*.png into Captures/ui_contact_sheet.png (4 columns) for a quick overview.
    /// </summary>
    public static class UiCapture
    {
        static string CaptureDir => Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Captures");

        [MenuItem("MudRunner/UI/Open Captures Folder")]
        public static void OpenFolder()
        {
            Directory.CreateDirectory(CaptureDir);
            EditorUtility.RevealInFinder(CaptureDir);
        }

        [MenuItem("MudRunner/UI/Build Contact Sheet")]
        public static void BuildContactSheet()
        {
            try
            {
                var files = new List<string>(Directory.GetFiles(CaptureDir, "ui_*.png"));
                files.RemoveAll(f => Path.GetFileName(f).StartsWith("ui_contact_sheet"));
                files.Sort(StringComparer.OrdinalIgnoreCase);
                if (files.Count == 0) { Debug.Log("[MudRunner] UiCapture: no ui_*.png in " + CaptureDir); return; }
                const int cols = 4, tw = 480, th = 270;
                int rows = (files.Count + cols - 1) / cols;
                var sheet = new Texture2D(cols * tw, rows * th, TextureFormat.RGBA32, false);
                var clear = new Color32[sheet.width * sheet.height];
                for (int i = 0; i < clear.Length; i++) clear[i] = new Color32(20, 22, 26, 255);
                sheet.SetPixels32(clear);
                for (int i = 0; i < files.Count; i++)
                {
                    var src = new Texture2D(2, 2, TextureFormat.RGBA32, false);
                    if (!src.LoadImage(File.ReadAllBytes(files[i]))) { UnityEngine.Object.DestroyImmediate(src); continue; }
                    var thumb = Downscale(src, tw, th);
                    int cx = i % cols, cy = rows - 1 - i / cols;
                    sheet.SetPixels32(cx * tw, cy * th, tw, th, thumb);
                    UnityEngine.Object.DestroyImmediate(src);
                }
                sheet.Apply();
                string path = Path.Combine(CaptureDir, "ui_contact_sheet.png");
                File.WriteAllBytes(path, sheet.EncodeToPNG());
                UnityEngine.Object.DestroyImmediate(sheet);
                Debug.Log("[MudRunner] UiCapture: contact sheet of " + files.Count + " screenshots -> " + path);
            }
            catch (Exception e) { Debug.LogError("[MudRunner] UiCapture failed: " + e); if (Application.isBatchMode) EditorApplication.Exit(1); }
        }

        static Color32[] Downscale(Texture2D src, int w, int h)
        {
            var px = src.GetPixels32();
            var res = new Color32[w * h];
            float sx = src.width / (float)w, sy = src.height / (float)h;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int x0 = (int)(x * sx), x1 = Mathf.Max(x0 + 1, (int)((x + 1) * sx)), y0 = (int)(y * sy), y1 = Mathf.Max(y0 + 1, (int)((y + 1) * sy));
                    int r = 0, g = 0, b = 0, n = 0;
                    for (int yy = y0; yy < y1 && yy < src.height; yy++)
                        for (int xx = x0; xx < x1 && xx < src.width; xx++) { var c = px[yy * src.width + xx]; r += c.r; g += c.g; b += c.b; n++; }
                    if (n == 0) n = 1;
                    res[y * w + x] = new Color32((byte)(r / n), (byte)(g / n), (byte)(b / n), 255);
                }
            return res;
        }
    }
}
