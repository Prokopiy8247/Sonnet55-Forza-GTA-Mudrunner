using System.Collections;
using System.IO;
using UnityEngine;

namespace MudRunner.UI
{
    /// <summary>
    /// Screenshot helper for the UI verification tests: grabs the final frame (overlay canvas + IMGUI included) to Captures/ui_*.png.
    /// If the back buffer capture comes back blank (some batch-mode setups) it falls back to rendering the main camera with the canvas
    /// switched to camera space into a RenderTexture (everything except IMGUI).
    /// </summary>
    public static class UiScreenshot
    {
        public static string Dir
        {
            get { return Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Captures"); }
        }

        public static string LastPath { get; private set; }
        public static int LastWidth, LastHeight;
        public static bool LastOk, LastBlank;

        /// <summary>Output size of the offscreen path (the batch-mode Game view is only 640x480).</summary>
        public static int TargetWidth = 1920, TargetHeight = 1080;

        /// <summary>Appends a line to Logs/cli/ui_trace.txt (flushed immediately: survives a watchdog kill).</summary>
        public static void Trace(string s)
        {
            try { File.AppendAllText(Path.Combine(Directory.GetParent(Application.dataPath).FullName, "Logs", "cli", "ui_trace.txt"), System.DateTime.Now.ToString("HH:mm:ss.fff") + "  " + s + System.Environment.NewLine); } catch { }
        }

        /// <summary>
        /// Writes Captures/ui_&lt;name&gt;.png. Default: the main camera + canvas are rendered into a TargetWidth x TargetHeight RenderTexture
        /// (no IMGUI). <paramref name="needsImgui"/> instead grabs the real back buffer (whatever size the Game view has). Never throws.
        /// </summary>
        public static IEnumerator Capture(string name, bool needsImgui = false)
        {
            LastOk = false;
            Trace("capture " + name + (needsImgui ? " (backbuffer)" : " (offscreen)"));
            if (!needsImgui) { CaptureOffscreenNow(name); yield return null; Trace("captured " + name + " ok=" + LastOk); yield break; }
            yield return new WaitForEndOfFrame();
            Texture2D tex = null;
            try
            {
                tex = ScreenCapture.CaptureScreenshotAsTexture();
                if (tex != null) { LastBlank = IsBlank(tex); Save(name, tex); }
                else Debug.Log("[MudRunner] UI screenshot " + name + ": CaptureScreenshotAsTexture returned null");
            }
            catch (System.Exception e) { Debug.Log("[MudRunner] UI screenshot " + name + " failed: " + e.Message); }
            finally { if (tex != null) Object.Destroy(tex); }
            Trace("captured " + name + " ok=" + LastOk);
        }

        static void Save(string name, Texture2D tex)
        {
            Directory.CreateDirectory(Dir);
            LastPath = Path.Combine(Dir, "ui_" + name + ".png");
            File.WriteAllBytes(LastPath, tex.EncodeToPNG());
            LastWidth = tex.width; LastHeight = tex.height; LastOk = true;
            Debug.Log("[MudRunner] UI screenshot " + name + " -> " + LastPath + " (" + tex.width + "x" + tex.height + (LastBlank ? ", BLANK" : "") + ")");
        }

        static bool IsBlank(Texture2D tex)
        {
            try
            {
                int w = tex.width, h = tex.height;
                float min = 1f, max = 0f;
                for (int i = 0; i < 400; i++)
                {
                    var c = tex.GetPixel((i * 97) % w, (i * 61) % h);
                    float l = (c.r + c.g + c.b) / 3f;
                    if (l < min) min = l; if (l > max) max = l;
                }
                return max - min < 0.01f;
            }
            catch { return false; }
        }

        static void CaptureOffscreenNow(string name)
        {
            var cam = Camera.main;
            var ui = UiRoot.Instance;
            var canvas = ui != null ? ui.Canvas : null;
            if (cam == null) return;
            int w = TargetWidth, h = TargetHeight;
            RenderTexture rt = null; Texture2D tex = null;
            var oldMode = RenderMode.ScreenSpaceOverlay; Camera oldCam = null; float oldPlane = 100f, oldScale = 1f; var oldTarget = cam.targetTexture;
            UnityEngine.UI.CanvasScaler scaler = canvas != null ? canvas.GetComponent<UnityEngine.UI.CanvasScaler>() : null;
            bool scalerWas = scaler != null && scaler.enabled;
            try
            {
                rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
                rt.Create();
                if (canvas != null)
                {
                    oldMode = canvas.renderMode; oldCam = canvas.worldCamera; oldPlane = canvas.planeDistance; oldScale = canvas.scaleFactor;
                    if (scaler != null) scaler.enabled = false;           // the scaler would size the UI for the 640x480 Game view
                    canvas.renderMode = RenderMode.ScreenSpaceCamera; canvas.worldCamera = cam; canvas.planeDistance = Mathf.Max(0.5f, cam.nearClipPlane + 0.5f);
                    canvas.scaleFactor = h / (float)UiTheme.RefHeight;
                }
                cam.targetTexture = rt;
                Canvas.ForceUpdateCanvases();
                cam.Render();
                cam.targetTexture = oldTarget;
                var prev = RenderTexture.active;
                RenderTexture.active = rt;
                tex = new Texture2D(w, h, TextureFormat.RGB24, false);
                tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
                tex.Apply();
                RenderTexture.active = prev;
                LastBlank = IsBlank(tex);
                Save(name, tex);
            }
            catch (System.Exception e) { Debug.Log("[MudRunner] UI offscreen screenshot " + name + " failed: " + e); }
            finally
            {
                cam.targetTexture = oldTarget;
                if (canvas != null)
                {
                    canvas.renderMode = oldMode; canvas.worldCamera = oldCam; canvas.planeDistance = oldPlane;
                    if (scaler != null) scaler.enabled = scalerWas;
                    if (scaler == null) canvas.scaleFactor = oldScale;
                    Canvas.ForceUpdateCanvases();
                }
                if (rt != null) { rt.Release(); Object.Destroy(rt); }
                if (tex != null) Object.Destroy(tex);
            }
        }
    }
}
