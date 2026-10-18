using System.Collections.Generic;
using MudRunner.Game;
using MudRunner.Ground;
using MudRunner.Objectives;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

namespace MudRunner.UI
{
    /// <summary>Breadcrumb trail of where the player has driven (drawn faintly on both maps).</summary>
    public static class MapTrail
    {
        public static readonly List<Vector2> Points = new List<Vector2>(1024);
        public static void Add(Vector3 p)
        {
            var q = new Vector2(p.x, p.z);
            if (Points.Count > 0 && (Points[Points.Count - 1] - q).sqrMagnitude < 36f) return;
            Points.Add(q);
            if (Points.Count > 2000) Points.RemoveRange(0, 400);
        }
        public static void Clear() { Points.Clear(); }
    }

    /// <summary>Everything that gets an icon on the minimap / full map.</summary>
    public struct MapItem
    {
        public string name; public Vector3 pos; public MapMarkers.Kind kind; public Color color; public bool important; public bool isVehicle; public float yaw;
    }

    public static class MapItems
    {
        public static void Gather(HudContext c, List<MapItem> list, bool includeVehicles)
        {
            list.Clear();
            var om = ObjectiveManager.Instance;
            if (om != null && om.hasTarget && !om.completed)
                list.Add(new MapItem { name = string.IsNullOrEmpty(om.title) ? "Objective" : om.title, pos = om.targetPosition, kind = MapMarkers.Kind.Objective, color = UiTheme.Accent, important = true });
            var wp = MapMarkers.UserWaypoint;
            if (wp != null) list.Add(new MapItem { name = "Waypoint", pos = wp.position, kind = MapMarkers.Kind.Waypoint, color = UiTheme.Info, important = true });
            var gm = c.gm;
            if (gm != null && gm.World != null)
            {
                var pts = gm.World.points;
                for (int i = 0; i < pts.Count; i++)
                    list.Add(new MapItem { name = pts[i].name, pos = pts[i].position, kind = MapMarkers.Kind.Site, color = new Color(0.93f, 0.95f, 0.97f, 0.95f) });
            }
            var mk = MapMarkers.Markers;
            for (int i = 0; i < mk.Count; i++)
            {
                var m = mk[i];
                Color col = m.kind == MapMarkers.Kind.Garage ? UiTheme.Good : m.kind == MapMarkers.Kind.Fuel ? UiTheme.Warn : m.kind == MapMarkers.Kind.Danger ? UiTheme.Bad : m.kind == MapMarkers.Kind.Camp ? UiTheme.Info : new Color(0.93f, 0.95f, 0.97f, 0.95f);
                list.Add(new MapItem { name = m.name, pos = m.position, kind = m.kind, color = col });
            }
            for (int i = 0; i < GarageZone.All.Count; i++)
            {
                var gz = GarageZone.All[i]; if (gz == null) continue;
                bool dup = false;
                for (int k = 0; k < mk.Count && !dup; k++)
                    if (mk[k].kind == MapMarkers.Kind.Garage && (mk[k].position - gz.transform.position).sqrMagnitude < 40f * 40f) dup = true;
                if (!dup) list.Add(new MapItem { name = gz.displayName, pos = gz.transform.position, kind = MapMarkers.Kind.Garage, color = UiTheme.Good });
            }
            if (includeVehicles && gm != null)
                for (int i = 0; i < gm.Vehicles.Count; i++)
                {
                    var ov = gm.Vehicles[i];
                    if (ov == null || ov == c.v) continue;
                    list.Add(new MapItem { name = ov.def != null ? ov.def.displayName : "Vehicle", pos = ov.transform.position, kind = MapMarkers.Kind.Site, color = new Color(0.55f, 0.75f, 1f, 0.95f), isVehicle = true, yaw = ov.transform.eulerAngles.y });
                }
        }
    }

    /// <summary>Pool of icon + glyph + label sets used by the map widgets.</summary>
    public sealed class MapIconPool
    {
        public sealed class Icon { public RectTransform rt; public Image img; public Text glyph, label; }
        readonly Transform parent; readonly List<Icon> items = new List<Icon>(); int used; readonly int labelSize;
        public MapIconPool(Transform parent, int labelSize) { this.parent = parent; this.labelSize = labelSize; }
        public void Begin() { used = 0; }
        public Icon Next()
        {
            if (used >= items.Count)
            {
                var ic = new Icon { rt = UiFactory.NewRect("Icon", parent) };
                ic.rt.sizeDelta = new Vector2(12, 12);
                ic.img = UiFactory.Img(ic.rt, "Img", UiAssets.Circle, Color.white);
                UiFactory.Fill(ic.img.rectTransform);
                ic.glyph = UiFactory.Label(ic.rt, "", 11, Color.black, TextAnchor.MiddleCenter, UiFont.Bold);
                UiFactory.Fill(ic.glyph.rectTransform);
                ic.label = UiFactory.Label(ic.rt, "", labelSize, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Bold, shadow: true);
                ic.label.rectTransform.anchorMin = ic.label.rectTransform.anchorMax = new Vector2(1f, 0.5f);
                ic.label.rectTransform.pivot = new Vector2(0f, 0.5f);
                ic.label.rectTransform.anchoredPosition = new Vector2(5f, 0f);
                ic.label.rectTransform.sizeDelta = new Vector2(180f, labelSize + 6);
                items.Add(ic);
            }
            var r = items[used++];
            if (!r.rt.gameObject.activeSelf) r.rt.gameObject.SetActive(true);
            return r;
        }
        public void End() { for (int i = used; i < items.Count; i++) if (items[i].rt.gameObject.activeSelf) items[i].rt.gameObject.SetActive(false); }

        public static void Style(Icon ic, in MapItem it, bool labels, float scale = 1f)
        {
            Sprite sp; float size; string glyph = ""; Color col = it.color;
            switch (it.kind)
            {
                case MapMarkers.Kind.Objective: sp = UiAssets.Diamond; size = 22f; break;
                case MapMarkers.Kind.Waypoint: sp = UiAssets.Diamond; size = 16f; break;
                case MapMarkers.Kind.Garage: sp = UiAssets.Rounded(4); size = 17f; glyph = "G"; break;
                case MapMarkers.Kind.Fuel: sp = UiAssets.Circle; size = 17f; glyph = "F"; break;
                case MapMarkers.Kind.Camp: sp = UiAssets.Triangle; size = 15f; break;
                case MapMarkers.Kind.Danger: sp = UiAssets.Triangle; size = 16f; glyph = "!"; break;
                default: sp = it.isVehicle ? UiAssets.Arrow : UiAssets.Circle; size = it.isVehicle ? 14f : 10f; break;
            }
            size *= scale;
            ic.img.sprite = sp; ic.img.type = sp == UiAssets.Rounded(4) ? Image.Type.Sliced : Image.Type.Simple;
            ic.img.color = col;
            ic.rt.sizeDelta = new Vector2(size, size);
            ic.rt.localRotation = it.isVehicle ? Quaternion.Euler(0, 0, -it.yaw) : Quaternion.identity;
            if (ic.glyph.text != glyph) ic.glyph.text = glyph;
            ic.glyph.rectTransform.localRotation = it.isVehicle ? Quaternion.Euler(0, 0, it.yaw) : Quaternion.identity;
            string lbl = labels ? it.name : "";
            if (ic.label.text != lbl) ic.label.text = lbl;
            ic.label.rectTransform.localRotation = it.isVehicle ? Quaternion.Euler(0, 0, it.yaw) : Quaternion.identity;
            ic.label.color = it.important ? it.color : UiTheme.Text;
            ic.label.rectTransform.anchoredPosition = new Vector2(size * 0.5f + 3f, 0f);
        }
    }

    /// <summary>Circular north-up minimap (bottom-left) with player arrow, objective/site markers, routes and your breadcrumb trail.</summary>
    public sealed class HudMinimap : HudWidget
    {
        public static readonly float[] ZoomLevels = { 130f, 220f, 360f, 600f };
        public int zoomIndex = 1;
        public const float Size = 280f;
        RawImage view; UiLines lines; Image arrow; Text zoomText, loading;
        MapIconPool icons; readonly List<MapItem> items = new List<MapItem>(48);
        WorldMapTexture tex;
        public bool HasTexture => tex != null && tex.Ready;

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("Minimap", parent);
            UiFactory.Place(root, UiFactory.BL, new Vector2(UiTheme.Margin, UiTheme.Margin), new Vector2(Size, Size), UiFactory.BL);

            var sh = UiFactory.Img(root, "Shadow", UiAssets.Circle, new Color(0f, 0f, 0f, 0.45f));
            UiFactory.Fill(sh.rectTransform, -7, -9, -7, -5);
            var bgd = UiFactory.Img(root, "Backdrop", UiAssets.Circle, new Color(0.04f, 0.05f, 0.06f, 0.95f));
            UiFactory.Fill(bgd.rectTransform);

            var maskRt = UiFactory.NewRect("Mask", root);
            UiFactory.Fill(maskRt, 4, 4, 4, 4);
            var mimg = maskRt.gameObject.AddComponent<Image>(); mimg.sprite = UiAssets.Circle; mimg.color = Color.white;
            var mask = maskRt.gameObject.AddComponent<Mask>(); mask.showMaskGraphic = false;

            var vr = UiFactory.NewRect("View", maskRt);
            UiFactory.Fill(vr);
            view = vr.gameObject.AddComponent<RawImage>(); view.raycastTarget = false; view.color = new Color(1f, 1f, 1f, 1f);
            var lr = UiFactory.NewRect("Lines", maskRt);
            lr.anchorMin = lr.anchorMax = new Vector2(0.5f, 0.5f); lr.sizeDelta = new Vector2(Size, Size);
            lines = lr.gameObject.AddComponent<UiLines>(); lines.raycastTarget = false;
            var ir = UiFactory.NewRect("Icons", maskRt);
            ir.anchorMin = ir.anchorMax = new Vector2(0.5f, 0.5f); ir.sizeDelta = new Vector2(Size, Size);
            icons = new MapIconPool(ir, 12);
            arrow = UiFactory.Img(maskRt, "Player", UiAssets.Arrow, UiTheme.Accent);
            UiFactory.Place(arrow.rectTransform, UiFactory.C, Vector2.zero, new Vector2(26, 26));
            var arrowShadow = UiFactory.Img(arrow.transform, "Outline", UiAssets.Arrow, new Color(0, 0, 0, 0.6f));
            UiFactory.Fill(arrowShadow.rectTransform, -3, -3, -3, -3);
            arrowShadow.transform.SetAsFirstSibling();

            loading = UiFactory.Label(maskRt, "Mapping terrain...", 15, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Body);
            UiFactory.Fill(loading.rectTransform);
            zoomText = UiFactory.Label(maskRt, "", 12, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Bold, shadow: true);
            UiFactory.Place(zoomText.rectTransform, UiFactory.BC, new Vector2(0, 16), new Vector2(120, 16));

            // frame
            var frame = UiFactory.NewRect("Frame", root);
            UiFactory.Fill(frame);
            var ring = frame.gameObject.AddComponent<UiArc>(); ring.raycastTarget = false;
            ring.Configure(Size * 0.5f + 0f, 5f, 0f, 360f); ring.color = new Color(0.06f, 0.07f, 0.085f, 1f);
            var ring2 = UiFactory.NewRect("Frame2", root); UiFactory.Fill(ring2);
            var arc2 = ring2.gameObject.AddComponent<UiArc>(); arc2.raycastTarget = false;
            arc2.Configure(Size * 0.5f - 4.2f, 1.6f, 0f, 360f); arc2.color = new Color(1f, 0.69f, 0.125f, 0.75f);

            var nChip = UiFactory.Img(root, "NChip", UiAssets.Circle, new Color(0.05f, 0.06f, 0.07f, 0.96f));
            UiFactory.Place(nChip.rectTransform, UiFactory.TC, new Vector2(0, 2), new Vector2(24, 24), UiFactory.C);
            nChip.rectTransform.anchoredPosition = new Vector2(0, -4);
            var nT = UiFactory.Label(nChip.transform, "N", 15, UiTheme.Accent, TextAnchor.MiddleCenter, UiFont.Display);
            UiFactory.Fill(nT.rectTransform);
        }

        public void ZoomStep(int d) { zoomIndex = Mathf.Clamp(zoomIndex + d, 0, ZoomLevels.Length - 1); }

        public override void Tick(HudContext c)
        {
            var gs = GroundService.Instance;
            var v = c.v;
            if (gs == null || gs.Map == null || v == null) return;
            tex = WorldMapTexture.For(gs.Map);
            tex.Poll();
            UiFactory.SetActive(loading, !tex.Ready);
            if (!tex.Ready) { view.texture = null; view.color = new Color(0.1f, 0.12f, 0.14f, 1f); }
            else { view.texture = tex.Texture; view.color = Color.white; }

            Vector3 p = v.transform.position;
            float win = ZoomLevels[zoomIndex], ws = tex.WorldSize, half = win / ws * 0.5f;
            float u = (p.x - tex.Origin.x) / ws, vv = (p.z - tex.Origin.y) / ws;
            view.uvRect = new Rect(u - half, vv - half, 2f * half, 2f * half);
            float pxm = (Size - 8f) / win;
            string zt = Mathf.RoundToInt(win) + " m";
            if (zoomText.text != zt) zoomText.text = zt;

            arrow.rectTransform.localRotation = Quaternion.Euler(0, 0, -v.transform.eulerAngles.y);

            // lines: routes + trail
            lines.Clear();
            float lim = win * 0.62f;
            var routes = MapMarkers.Routes;
            for (int r = 0; r < routes.Count; r++)
            {
                var pts = routes[r].points; if (pts == null) continue;
                Color rc = routes[r].color; rc.a = Mathf.Max(rc.a, 0.9f);
                for (int i = 0; i + 1 < pts.Length; i++)
                {
                    float ax = pts[i].x - p.x, az = pts[i].z - p.z, bx = pts[i + 1].x - p.x, bz = pts[i + 1].z - p.z;
                    if ((ax > lim && bx > lim) || (ax < -lim && bx < -lim) || (az > lim && bz > lim) || (az < -lim && bz < -lim)) continue;
                    lines.Add(new Vector2(ax, az) * pxm, new Vector2(bx, bz) * pxm, 3f, rc);
                }
            }
            var trail = MapTrail.Points;
            for (int i = Mathf.Max(0, trail.Count - 400); i + 1 < trail.Count; i++)
            {
                float ax = trail[i].x - p.x, az = trail[i].y - p.z, bx = trail[i + 1].x - p.x, bz = trail[i + 1].y - p.z;
                if (Mathf.Abs(ax) > lim && Mathf.Abs(bx) > lim) continue;
                lines.Add(new Vector2(ax, az) * pxm, new Vector2(bx, bz) * pxm, 2f, new Color(1f, 0.85f, 0.4f, 0.5f));
            }
            lines.Apply();

            // icons
            MapItems.Gather(c, items, true);
            icons.Begin();
            float radius = (Size - 8f) * 0.5f - 7f;
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                Vector2 off = new Vector2(it.pos.x - p.x, it.pos.z - p.z) * pxm;
                float d = off.magnitude;
                bool inside = d <= radius;
                if (!inside && !it.important) continue;
                var ic = icons.Next();
                if (!inside) off = off / d * radius;
                var copy = it; if (!inside) copy.name = "";
                MapIconPool.Style(ic, copy, false, inside ? 1f : 0.85f);
                ic.rt.anchoredPosition = off;
            }
            icons.End();
        }
    }

    /// <summary>Full-screen map (Tab): pan with the left mouse button, zoom with the wheel, right-click sets a waypoint.</summary>
    public sealed class HudFullMap : HudWidget
    {
        public bool IsOpen { get; private set; }
        RectTransform frame, viewRt, mapImgRt, iconsRt; RawImage mapImg; UiLines lines, scaleLine; Image arrow;
        Text title, hover, scaleText, hint, loading;
        MapIconPool icons; readonly List<MapItem> items = new List<MapItem>(64);
        CanvasGroup group;
        Vector2 center; float mpp = 2.5f; bool inited; WorldMapTexture tex; GroundMap lastMap;
        float openTime;
        public bool HasTexture => tex != null && tex.Ready;
        public Vector2 Center => center;
        public float MetersPerPixel => mpp;

        public override void Build(HudContext c, RectTransform parent)
        {
            root = UiFactory.NewRect("FullMap", parent);
            UiFactory.Fill(root);
            group = root.gameObject.AddComponent<CanvasGroup>();
            var back = UiFactory.Rect(root, "Backdrop", new Color(0f, 0f, 0f, 0.58f), true);
            UiFactory.Fill(back.rectTransform);

            var panel = UiFactory.Panel(root, "Panel", new Color(0.035f, 0.041f, 0.049f, 0.97f), 14, true, true);
            frame = panel.rt;
            UiFactory.Fill(frame, 110, 70, 110, 70);

            title = UiFactory.Label(frame, "MAP", 28, UiTheme.Accent, TextAnchor.MiddleLeft, UiFont.Display);
            UiFactory.Place(title.rectTransform, UiFactory.TL, new Vector2(22, -26), new Vector2(600, 36));
            var close = UiFactory.Label(frame, "[Tab] / [Esc]  close", 15, UiTheme.TextDim, TextAnchor.MiddleRight, UiFont.Body);
            UiFactory.Place(close.rectTransform, UiFactory.TR, new Vector2(-22, -26), new Vector2(300, 24));

            viewRt = UiFactory.NewRect("View", frame);
            UiFactory.Fill(viewRt, 14, 58, 14, 56);
            var vbg = UiFactory.Img(viewRt, "Bg", UiAssets.White, new Color(0.02f, 0.025f, 0.03f, 1f), Image.Type.Simple, true);
            UiFactory.Fill(vbg.rectTransform);
            var clip = UiFactory.NewRect("Clip", viewRt);
            UiFactory.Fill(clip);
            var clipImg = clip.gameObject.AddComponent<Image>(); clipImg.sprite = UiAssets.White; clipImg.color = Color.white;
            var clipMask = clip.gameObject.AddComponent<Mask>(); clipMask.showMaskGraphic = false;      // stencil mask: RectMask2D + UiLines threw MissingComponentException on deactivation

            mapImgRt = UiFactory.NewRect("MapImage", clip);
            mapImg = mapImgRt.gameObject.AddComponent<RawImage>(); mapImg.raycastTarget = false;
            var lr = UiFactory.NewRect("Lines", clip);
            lr.anchorMin = lr.anchorMax = new Vector2(0.5f, 0.5f); lr.sizeDelta = new Vector2(100, 100);
            lines = lr.gameObject.AddComponent<UiLines>(); lines.raycastTarget = false;
            var ir = UiFactory.NewRect("Icons", clip);
            ir.anchorMin = ir.anchorMax = new Vector2(0.5f, 0.5f); ir.sizeDelta = new Vector2(100, 100);
            iconsRt = ir;
            icons = new MapIconPool(ir, 15);
            arrow = UiFactory.Img(clip, "Player", UiAssets.Arrow, UiTheme.Accent);
            arrow.rectTransform.anchorMin = arrow.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            arrow.rectTransform.sizeDelta = new Vector2(30, 30);
            var ao = UiFactory.Img(arrow.transform, "Outline", UiAssets.Arrow, new Color(0, 0, 0, 0.7f));
            UiFactory.Fill(ao.rectTransform, -3, -3, -3, -3); ao.transform.SetAsFirstSibling();
            var sr = UiFactory.NewRect("Scale", clip);
            UiFactory.Place(sr, UiFactory.BL, new Vector2(18, 18), new Vector2(240, 30), UiFactory.BL);
            scaleLine = sr.gameObject.AddComponent<UiLines>(); scaleLine.raycastTarget = false;
            scaleText = UiFactory.Label(sr, "250 m", 14, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Bold, shadow: true);
            UiFactory.Place(scaleText.rectTransform, UiFactory.BL, new Vector2(0, 12), new Vector2(160, 18));
            loading = UiFactory.Label(clip, "Mapping terrain...", 20, UiTheme.TextDim, TextAnchor.MiddleCenter, UiFont.Body);
            UiFactory.Fill(loading.rectTransform);

            hover = UiFactory.Label(frame, "", 15, UiTheme.Text, TextAnchor.MiddleLeft, UiFont.Mono);
            UiFactory.Place(hover.rectTransform, UiFactory.BL, new Vector2(22, 26), new Vector2(760, 24));
            hint = UiFactory.Label(frame, "Drag: pan   Wheel: zoom   Right-click: waypoint   Home: centre on vehicle", 14, UiTheme.TextDim, TextAnchor.MiddleRight, UiFont.Body);
            UiFactory.Place(hint.rectTransform, UiFactory.BR, new Vector2(-22, 26), new Vector2(640, 22));
            root.gameObject.SetActive(false);
        }

        public void SetOpen(bool open)
        {
            if (open == IsOpen) return;
            IsOpen = open; UiState.MapOpen = open;
            root.gameObject.SetActive(open);
            if (open) { openTime = Time.unscaledTime; inited = false; }
        }

        public override void SetVisible(bool on) { /* visibility is controlled by SetOpen */ }

        void Fit(Vector2 viewSize, float ws)
        {
            mpp = Mathf.Max(0.25f, ws / Mathf.Min(viewSize.x, viewSize.y) * 1.02f);
        }

        float MaxMpp(Vector2 viewSize, float ws) { return Mathf.Max(0.5f, ws / Mathf.Min(viewSize.x, viewSize.y) * 1.25f); }

        public override void Tick(HudContext c)
        {
            if (!IsOpen) return;
            var gs = GroundService.Instance; var v = c.v;
            if (gs == null || gs.Map == null || v == null) return;
            tex = WorldMapTexture.For(gs.Map); tex.Poll();
            UiFactory.SetActive(loading, !tex.Ready);
            float ws = tex.WorldSize;
            Vector2 vs = viewRt.rect.size;
            Vector3 p = v.transform.position;
            if (!inited || lastMap != gs.Map)
            {
                inited = true; lastMap = gs.Map;
                Fit(vs, ws);
                center = new Vector2(p.x, p.z);
                if (ws > 600f) mpp = Mathf.Max(0.5f, ws / Mathf.Min(vs.x, vs.y) * 0.45f);   // start zoomed on the vehicle for big worlds
                else center = tex.Origin + Vector2.one * ws * 0.5f;
            }
            string kindName = c.gm != null && c.gm.World != null ? c.gm.World.kind.ToString() : "";
            string tt = "MAP  —  " + (kindName == "ProvingGround" ? "Proving ground" : kindName);
            if (title.text != tt) title.text = tt;

            // ---- input
            var mouse = Mouse.current;
            Vector2 hoverWorld = Vector2.zero; bool hovering = false;
            if (mouse != null)
            {
                Vector2 sp = mouse.position.ReadValue();
                if (RectTransformUtility.RectangleContainsScreenPoint(viewRt, sp, null))
                {
                    RectTransformUtility.ScreenPointToLocalPointInRectangle(viewRt, sp, null, out Vector2 local);
                    hoverWorld = center + local * mpp; hovering = true;
                    float scroll = mouse.scroll.ReadValue().y;
                    if (Mathf.Abs(scroll) > 5f) scroll /= 120f;
                    if (Mathf.Abs(scroll) > 0.01f)
                    {
                        float k = Mathf.Pow(0.82f, scroll);
                        float newMpp = Mathf.Clamp(mpp * k, 0.25f, MaxMpp(vs, ws));
                        center = hoverWorld - local * newMpp; mpp = newMpp;
                    }
                    if (mouse.leftButton.isPressed && Time.unscaledTime - openTime > 0.15f)
                    {
                        Vector2 dl = mouse.delta.ReadValue() / c.Scale;
                        center -= dl * mpp;
                    }
                    if (mouse.rightButton.wasPressedThisFrame)
                    {
                        var wpm = MapMarkers.UserWaypoint;
                        if (wpm != null && ((Vector2)new Vector2(wpm.position.x, wpm.position.z) - hoverWorld).magnitude < 18f * mpp) { MapMarkers.SetUserWaypoint(null); Hud.Notify("Waypoint removed", 2f); }
                        else { MapMarkers.SetUserWaypoint(new Vector3(hoverWorld.x, gs.GroundHeight(hoverWorld.x, hoverWorld.y), hoverWorld.y)); Hud.Notify("Waypoint set", 2f); }
                    }
                }
            }
            var kb = Keyboard.current;
            if (kb != null && kb.homeKey.wasPressedThisFrame && !UiState.TextFieldFocus) center = new Vector2(p.x, p.z);
            // keep the map on screen
            float halfX = vs.x * 0.5f * mpp, halfZ = vs.y * 0.5f * mpp;
            Vector2 mn = tex.Origin, mx = tex.Origin + Vector2.one * ws;
            center.x = halfX * 2f >= ws ? tex.Origin.x + ws * 0.5f : Mathf.Clamp(center.x, mn.x + halfX, mx.x - halfX);
            center.y = halfZ * 2f >= ws ? tex.Origin.y + ws * 0.5f : Mathf.Clamp(center.y, mn.y + halfZ, mx.y - halfZ);

            // ---- map image placement
            float imgPx = ws / mpp;
            mapImgRt.anchorMin = mapImgRt.anchorMax = new Vector2(0.5f, 0.5f);
            mapImgRt.pivot = new Vector2(0.5f, 0.5f);
            mapImgRt.sizeDelta = new Vector2(imgPx, imgPx);
            Vector2 mapCenterWorld = tex.Origin + Vector2.one * ws * 0.5f;
            mapImgRt.anchoredPosition = (mapCenterWorld - center) / mpp;
            mapImg.texture = tex.Ready ? tex.Texture : null;
            mapImg.color = tex.Ready ? Color.white : new Color(0.1f, 0.12f, 0.14f, 1f);

            // ---- overlay graphics in view space (origin = view centre)
            var lrt = (RectTransform)lines.transform; lrt.sizeDelta = vs;
            iconsRt.sizeDelta = vs;
            lines.Clear();
            DrawGrid(vs, ws);
            var routes = MapMarkers.Routes;
            Rect view = new Rect(-vs.x * 0.5f - 40, -vs.y * 0.5f - 40, vs.x + 80, vs.y + 80);
            for (int r = 0; r < routes.Count; r++)
            {
                var pts = routes[r].points; if (pts == null) continue;
                for (int i = 0; i + 1 < pts.Length; i++)
                {
                    Vector2 a = ToView(pts[i]), b = ToView(pts[i + 1]);
                    if (!view.Contains(a) && !view.Contains(b)) continue;
                    lines.Add(a, b, 4f, routes[r].color);
                }
            }
            var trail = MapTrail.Points;
            for (int i = 0; i + 1 < trail.Count; i++)
            {
                Vector2 a = ToView(trail[i]), b = ToView(trail[i + 1]);
                if (!view.Contains(a) && !view.Contains(b)) continue;
                lines.Add(a, b, 2.5f, new Color(1f, 0.85f, 0.4f, 0.55f));
            }
            // line from vehicle to objective / waypoint
            var om = ObjectiveManager.Instance;
            if (om != null && om.hasTarget && !om.completed) lines.Add(ToView(new Vector2(p.x, p.z)), ToView(new Vector2(om.targetPosition.x, om.targetPosition.z)), 1.6f, new Color(1f, 0.69f, 0.125f, 0.55f));
            lines.Apply();

            MapItems.Gather(c, items, true);
            icons.Begin();
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                Vector2 vp = ToView(new Vector2(it.pos.x, it.pos.z));
                if (!view.Contains(vp)) continue;
                var ic = icons.Next();
                MapIconPool.Style(ic, it, true, 1.15f);
                ic.rt.anchoredPosition = vp;
            }
            icons.End();
            arrow.rectTransform.anchoredPosition = ToView(new Vector2(p.x, p.z));
            arrow.rectTransform.localRotation = Quaternion.Euler(0, 0, -v.transform.eulerAngles.y);

            // ---- scale bar + hover readout
            DrawScale(vs);
            if (hovering)
            {
                float h = gs.GroundHeight(hoverWorld.x, hoverWorld.y);
                var st = gs.Map.DominantType(hoverWorld.x, hoverWorld.y);
                float dist = Vector2.Distance(hoverWorld, new Vector2(p.x, p.z));
                float brg = Mathf.Repeat(Mathf.Atan2(hoverWorld.x - p.x, hoverWorld.y - p.z) * Mathf.Rad2Deg, 360f);
                string wd = "";
                if (gs.Map.water != null) { float dpt = gs.Map.water.Depth(hoverWorld.x, hoverWorld.y, h); if (dpt > 0.05f) wd = "  water " + dpt.ToString("0.0") + " m"; }
                hover.text = "X " + hoverWorld.x.ToString("0").PadLeft(5) + "  Z " + hoverWorld.y.ToString("0").PadLeft(5) + "   alt " + h.ToString("0") + " m   " + SurfaceDatabase.Table[(int)st].name
                    + wd + "   |   " + HudCompass.FormatDist(dist) + "  brg " + brg.ToString("0") + "°";
            }
            else hover.text = "";
        }

        Vector2 ToView(Vector3 w) { return new Vector2(w.x - center.x, w.z - center.y) / mpp; }
        Vector2 ToView(Vector2 w) { return (w - center) / mpp; }

        void DrawGrid(Vector2 vs, float ws)
        {
            float[] steps = { 50f, 100f, 250f, 500f, 1000f };
            float step = steps[steps.Length - 1];
            for (int i = 0; i < steps.Length; i++) if (steps[i] / mpp >= 90f) { step = steps[i]; break; }
            float x0 = center.x - vs.x * 0.5f * mpp, x1 = center.x + vs.x * 0.5f * mpp, z0 = center.y - vs.y * 0.5f * mpp, z1 = center.y + vs.y * 0.5f * mpp;
            Color gc = new Color(1f, 1f, 1f, 0.07f);
            for (float x = Mathf.Ceil(x0 / step) * step; x <= x1; x += step) lines.Add(ToView(new Vector2(x, z0)), ToView(new Vector2(x, z1)), 1f, Mathf.Approximately(x, 0f) ? new Color(1f, 1f, 1f, 0.16f) : gc);
            for (float z = Mathf.Ceil(z0 / step) * step; z <= z1; z += step) lines.Add(ToView(new Vector2(x0, z)), ToView(new Vector2(x1, z)), 1f, Mathf.Approximately(z, 0f) ? new Color(1f, 1f, 1f, 0.16f) : gc);
        }

        void DrawScale(Vector2 vs)
        {
            float[] nice = { 10f, 20f, 50f, 100f, 200f, 500f, 1000f };
            float len = nice[0];
            for (int i = 0; i < nice.Length; i++) { len = nice[i]; if (len / mpp >= 90f) break; }
            float px = len / mpp;
            scaleLine.Clear();
            scaleLine.Add(new Vector2(0, 4), new Vector2(px, 4), 3f, Color.white);
            scaleLine.Add(new Vector2(0, 0), new Vector2(0, 9), 2f, Color.white);
            scaleLine.Add(new Vector2(px, 0), new Vector2(px, 9), 2f, Color.white);
            scaleLine.Apply();
            string s = len >= 1000f ? (len / 1000f) + " km" : len + " m";
            if (scaleText.text != s) scaleText.text = s;
        }
    }
}
