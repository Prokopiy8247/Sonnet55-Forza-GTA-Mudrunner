class_name MapScreen
extends MenuBase
## Full-screen map (M): pan (drag / WASD / stick), zoom (wheel / Q E / + -), district labels, location icons with a
## legend, player marker, police blips, GPS route line along the lane graph and waypoint set / clear.
##   LMB click = set waypoint (click the pin again to clear) · RMB click = clear · C = centre on player · F = focus waypoint
## The waypoint lives in UIRoot (`waypoint`, `has_waypoint`, mirrored to Game's meta "waypoint"). No teleporting, no mission markers.

var raster: MapRaster = null
var view: MapView
var _legend_box: VBoxContainer
var _legend_sig := -1
var _info_label: Label


func _init() -> void:
	super._init()
	pauses_game = true
	closes_on_pause = true
	dim_background = false
	var bg := ColorRect.new()
	bg.color = MapRaster.C_VOID
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	view = MapView.new()
	view.screen = self
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	# title block (top-left)
	var top_pill := UIKit.panel(&"Pill")
	top_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UIKit.vbox(2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_pill.add_child(top)
	top_pill.anchor_left = 0.5
	top_pill.anchor_right = 0.5
	top_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_pill.offset_left = -190.0
	top_pill.offset_right = 190.0
	top_pill.offset_top = UITheme.SAFE_Y - 12.0
	top_pill.offset_bottom = UITheme.SAFE_Y + 76.0
	top.add_child(UIKit.header("Map", GC.GAME_NAME))
	_info_label = UIKit.label("", 19, UITheme.C_DIM, false, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_info_label)
	add_child(top_pill)
	# legend (right)
	var lp := UIKit.panel(&"PanelHi")
	lp.mouse_filter = Control.MOUSE_FILTER_STOP
	lp.anchor_left = 1.0
	lp.anchor_right = 1.0
	lp.anchor_top = 0.0
	lp.anchor_bottom = 1.0
	lp.offset_left = -(UITheme.SAFE_X + 300.0)
	lp.offset_right = -UITheme.SAFE_X
	lp.offset_top = UITheme.SAFE_Y + 70.0
	lp.offset_bottom = -(UITheme.SAFE_Y + 70.0)
	add_child(lp)
	var lv := UIKit.vbox(6)
	lp.add_child(lv)
	lv.add_child(UIKit.caption("Legend"))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sc)
	_legend_box = UIKit.vbox(6)
	_legend_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_legend_box)
	# hint bar (bottom centre)
	var hb := UIKit.hbox(28)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.anchor_left = 0.5
	hb.anchor_right = 0.5
	hb.anchor_top = 1.0
	hb.anchor_bottom = 1.0
	hb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hb.offset_top = -(UITheme.SAFE_Y + 44.0)
	hb.offset_bottom = -UITheme.SAFE_Y
	for h in [["LMB", "Set waypoint"], ["RMB", "Clear"], ["Wheel", "Zoom"], ["Drag", "Pan"], ["C", "Centre on me"], ["Esc", "Close"]]:
		var item := UIKit.hbox(8)
		item.add_child(UIKit.keycap(h[0]))
		var l := UIKit.label(h[1], 18, UITheme.C_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(l)
		hb.add_child(item)
	add_child(hb)


func attach_raster(r: MapRaster) -> void:
	raster = r


func _on_open(_d: Dictionary) -> void:
	view.reset_view()
	_refresh_legend()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	if not visible:
		return
	if WorldLayout.locations.size() != _legend_sig:
		_refresh_legend()
	var ui = Game.ui
	if ui != null and ui.get("has_waypoint") == true:
		var wp: Vector3 = ui.get("waypoint")
		var pp := Game.get_player_position()
		var d := Vector2(wp.x - pp.x, wp.z - pp.z).length()
		_info_label.text = "Waypoint  %s" % (("%d m" % int(d)) if d < 1000.0 else ("%.1f km" % (d / 1000.0)))
	else:
		_info_label.text = "No waypoint set"


func _refresh_legend() -> void:
	_legend_sig = WorldLayout.locations.size()
	for c in _legend_box.get_children():
		c.queue_free()
	var seen: Dictionary = {}
	for id in WorldLayout.locations:
		var info: Array = UIIcons.location_info(id)
		if info.is_empty():
			continue
		var label_text: String = info[3]
		if seen.has(label_text):
			continue
		seen[label_text] = true
		var row := UIKit.hbox(12)
		var ic := UIKit.IconBox.new()
		ic.custom_minimum_size = Vector2(30, 30)
		var gid: StringName = info[0]
		var gcol: Color = info[1]
		ic.draw_cb = func(ci: Control, rect: Rect2): UIIcons.draw_glyph(ci, gid, rect.get_center(), 12.0, gcol, 1.0, false)
		row.add_child(ic)
		var l := UIKit.label(label_text, 19, UITheme.C_TEXT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_legend_box.add_child(row)
	var pr := UIKit.hbox(12)
	var pic := UIKit.IconBox.new()
	pic.custom_minimum_size = Vector2(30, 30)
	pic.draw_cb = func(ci: Control, rect: Rect2): UIIcons.draw_glyph(ci, &"pin", rect.get_center(), 12.0, UITheme.C_ACCENT2, 1.0, false)
	pr.add_child(pic)
	pr.add_child(UIKit.label("Waypoint", 19, UITheme.C_TEXT))
	_legend_box.add_child(pr)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_C or k == KEY_SPACE:
			view.center_on_player()
			get_viewport().set_input_as_handled()
		elif k == KEY_F:
			view.focus_waypoint()
			get_viewport().set_input_as_handled()
		elif k == KEY_BACKSPACE or k == KEY_DELETE:
			if Game.ui != null and Game.ui.has_method("clear_waypoint"):
				Game.ui.clear_waypoint()
			get_viewport().set_input_as_handled()


# =====================================================================================================================
class MapView extends Control:
	var screen: MapScreen
	var zoom := 2.0
	var pan := Vector2.ZERO
	var _drag := false
	var _drag_moved := false
	var _drag_from := Vector2.ZERO
	var _pan_start := Vector2.ZERO
	var _mouse := Vector2.ZERO
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func fit_zoom() -> float:
		return minf(size.x, size.y) / (MapRaster.SIZE.x * 0.96)

	func w2s(w: Vector2) -> Vector2:
		return size * 0.5 + (w - pan) * zoom

	func s2w(s: Vector2) -> Vector2:
		return (s - size * 0.5) / zoom + pan

	func reset_view() -> void:
		zoom = maxf(fit_zoom() * 1.55, 1.0)
		center_on_player()

	func center_on_player() -> void:
		var p := Game.get_player_position()
		pan = Vector2(p.x, p.z)
		_clamp()

	func focus_waypoint() -> void:
		if Game.ui != null and Game.ui.get("has_waypoint") == true:
			var wp: Vector3 = Game.ui.get("waypoint")
			pan = Vector2(wp.x, wp.z)
			_clamp()

	func _clamp() -> void:
		zoom = clampf(zoom, fit_zoom() * 0.9, 9.0)
		var lim := GC.WORLD_HALF + 20.0
		pan.x = clampf(pan.x, -lim, lim)
		pan.y = clampf(pan.y, -lim, lim)

	func _zoom_at(screen_pt: Vector2, factor: float) -> void:
		var before := s2w(screen_pt)
		zoom = clampf(zoom * factor, fit_zoom() * 0.9, 9.0)
		var after := s2w(screen_pt)
		pan += before - after
		_clamp()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			_mouse = mm.position
			if _drag:
				if not _drag_moved and mm.position.distance_to(_drag_from) > 7.0:
					_drag_moved = true
				if _drag_moved:
					pan = _pan_start - (mm.position - _drag_from) / zoom
					_clamp()
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_zoom_at(mb.position, 1.18)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_zoom_at(mb.position, 1.0 / 1.18)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_drag = true
					_drag_moved = false
					_drag_from = mb.position
					_pan_start = pan
				else:
					if _drag and not _drag_moved and mb.button_index == MOUSE_BUTTON_LEFT:
						_click_waypoint(mb.position)
					_drag = false
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				if Game.ui != null and Game.ui.has_method("clear_waypoint"):
					Game.ui.clear_waypoint()
					Sfx.play_ui(&"ui_back")

	func _click_waypoint(sp: Vector2) -> void:
		var ui = Game.ui
		if ui == null or not ui.has_method("set_waypoint"):
			return
		# clicking the existing pin clears it
		if ui.get("has_waypoint") == true:
			var wp: Vector3 = ui.get("waypoint")
			var pin := w2s(Vector2(wp.x, wp.z))
			if pin.distance_to(sp) < 22.0 or (pin + Vector2(0, -14.0)).distance_to(sp) < 22.0:
				ui.clear_waypoint()
				Sfx.play_ui(&"ui_back")
				return
		var w := s2w(sp)
		if absf(w.x) > GC.WORLD_HALF or absf(w.y) > GC.WORLD_HALF:
			Sfx.play_ui(&"ui_error")
			return
		ui.set_waypoint(Vector3(w.x, WorldLayout.terrain_height(w.x, w.y), w.y))
		Sfx.play_ui(&"ui_confirm")

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		# keyboard / stick pan + zoom
		var mv := Vector2.ZERO
		mv.x = Input.get_axis(&"move_left", &"move_right")
		mv.y = Input.get_axis(&"move_forward", &"move_back")
		mv += Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)) if absf(Input.get_joy_axis(0, JOY_AXIS_LEFT_X)) + absf(Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)) > 0.3 else Vector2.ZERO
		if mv != Vector2.ZERO:
			pan += mv.limit_length(1.0) * (520.0 / zoom) * delta
			_clamp()
		var zi := 0.0
		if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
			zi += 1.0
		if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
			zi -= 1.0
		if zi != 0.0:
			_zoom_at(size * 0.5, 1.0 + zi * delta * 1.6)
		queue_redraw()

	# ---- drawing -------------------------------------------------------------------------------------------------------
	func _draw() -> void:
		var tex: Texture2D = screen.raster.texture if screen != null and screen.raster != null else null
		var f := UITheme.font(true)
		var fd := UITheme.font_display()
		if tex != null:
			var p0 := w2s(MapRaster.ORIGIN)
			draw_texture_rect(tex, Rect2(p0, MapRaster.SIZE * zoom), false)
		# 100 m grid
		var gcol := Color(1, 1, 1, 0.045)
		for k in range(-300, 301, 100):
			var a := w2s(Vector2(k, -300))
			var b := w2s(Vector2(k, 300))
			draw_line(a, b, gcol, 1.0)
			draw_line(w2s(Vector2(-300, k)), w2s(Vector2(300, k)), gcol, 1.0)
		# district labels
		var da := clampf(1.5 - zoom / 4.5, 0.18, 0.85)
		for d in WorldLayout.districts:
			var r: Rect2 = d.get("rect", Rect2())
			if r.size == Vector2.ZERO:
				continue
			var nm := str(d.get("name", d.get("id", ""))).to_upper()
			var c := w2s(r.get_center())
			var sz := int(clampf(18.0 * (0.8 + zoom * 0.18), 16.0, 34.0))
			var col: Color = d.get("color", Color(0.8, 0.9, 1.0))
			col = col.lerp(Color.WHITE, 0.6)
			var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
			UIDraw.text_shadow(self, f, nm, c + Vector2(-tw * 0.5, sz * 0.35), sz, Color(col.r, col.g, col.b, da))
		# route
		var ui = Game.ui
		if ui != null and ui.get("has_waypoint") == true:
			var route = ui.get("route")
			if route is UIRoute and route.points.size() >= 2:
				var pts := PackedVector2Array()
				for v in route.points:
					pts.append(w2s(Vector2(v.x, v.z)))
				draw_polyline(pts, Color(0, 0, 0, 0.6), 8.0, true)
				draw_polyline(pts, UITheme.C_ACCENT, 4.5, true)
		# locations
		var hover_name := ""
		var hover_d := 22.0
		for id in WorldLayout.locations:
			var info: Array = UIIcons.location_info(id)
			if info.is_empty():
				continue
			if int(info[2]) == 2 and zoom < 2.4:
				continue
			var lp: Vector3 = WorldLayout.locations[id].get("pos", Vector3.ZERO)
			var sp := w2s(Vector2(lp.x, lp.z))
			if sp.x < -30 or sp.y < -30 or sp.x > size.x + 30 or sp.y > size.y + 30:
				continue
			var rad := clampf(10.0 + zoom * 0.9, 11.0, 17.0)
			UIIcons.draw_glyph(self, info[0], sp, rad, info[1], 1.0)
			var dist := sp.distance_to(_mouse)
			if dist < hover_d:
				hover_d = dist
				hover_name = str(WorldLayout.locations[id].get("name", info[3]))
			elif zoom > 4.0:
				var lbl: String = str(WorldLayout.locations[id].get("name", info[3]))
				UIDraw.text_shadow(self, f, lbl, sp + Vector2(rad + 5.0, 6.0), 16, Color(1, 1, 1, 0.8))
		# police
		for n in get_tree().get_nodes_in_group(GC.G_POLICE):
			if n is Node3D:
				var pn := n as Node3D
				var sp2 := w2s(Vector2(pn.global_position.x, pn.global_position.z))
				var red := fmod(_t * 3.2 + float(pn.get_instance_id() % 7) * 0.37, 2.0) < 1.0
				draw_rect(Rect2(sp2 - Vector2(4, 4), Vector2(8, 8)), UITheme.C_POLICE_RED if red else UITheme.C_POLICE_BLUE)
		# wanted search area
		if Game.wanted_level > 0 and Game.wanted_state == &"search":
			var ws = Game.sys(&"wanted")
			if ws != null and ws.has_method("get_last_known_position"):
				var lk: Vector3 = ws.get_last_known_position()
				var rad2: float = float(ws.get("search_radius")) if ws.get("search_radius") != null else 80.0
				var cc := w2s(Vector2(lk.x, lk.z))
				draw_circle(cc, rad2 * zoom, Color(0.23, 0.48, 1.0, 0.14))
				draw_arc(cc, rad2 * zoom, 0.0, TAU, 64, Color(0.4, 0.6, 1.0, 0.8), 2.5, true)
		# waypoint pin
		if ui != null and ui.get("has_waypoint") == true:
			var wp: Vector3 = ui.get("waypoint")
			var ws2 := w2s(Vector2(wp.x, wp.z))
			var pulse := 0.5 + 0.5 * sin(_t * 4.0)
			draw_circle(ws2, 12.0 + pulse * 8.0, Color(UITheme.C_ACCENT2.r, UITheme.C_ACCENT2.g, UITheme.C_ACCENT2.b, 0.25 * (1.0 - pulse)))
			UIIcons.draw_glyph(self, &"pin", ws2 + Vector2(0, -14.0), 15.0, UITheme.C_ACCENT2, 1.0)
		# player marker
		var pl = Game.player
		if is_instance_valid(pl) and pl is Node3D:
			var pn2 := pl as Node3D
			var fwd := -pn2.global_transform.basis.z
			var veh = pl.get("current_vehicle")
			if veh != null and is_instance_valid(veh) and veh is Node3D:
				fwd = -(veh as Node3D).global_transform.basis.z
			var ang := atan2(fwd.x, -fwd.z)
			var pp := w2s(Vector2(pn2.global_position.x, pn2.global_position.z))
			var pr := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(pp, 16.0 + pr * 6.0, Color(1, 1, 1, 0.12 * (1.0 - pr)))
			UIDraw.triangle(self, pp, 15.0, ang, Color(0, 0, 0, 0.8))
			UIDraw.triangle(self, pp, 12.0, ang, Color.WHITE)
		# cursor readout
		var cw := s2w(_mouse)
		if is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(_mouse):
			var dn := WorldLayout.district_at(cw.x, cw.y)
			var txt := "%d, %d" % [int(cw.x), int(cw.y)]
			if hover_name != "":
				txt = hover_name
			var tw2 := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19).x
			var rect := Rect2(_mouse + Vector2(18, 18), Vector2(tw2 + 28.0, 36.0))
			if rect.end.x > size.x - 10.0:
				rect.position.x = _mouse.x - rect.size.x - 18.0
			UIDraw.rrect(self, rect, Color(0.03, 0.04, 0.06, 0.9), 10, 1, Color(1, 1, 1, 0.14))
			UIDraw.text(self, f, txt, rect.position + Vector2(14, 25), 19, Color.WHITE)
			if hover_name == "":
				UIDraw.text(self, f, String(dn).replace("_", " ").to_upper(), rect.position + Vector2(14, 54), 14, UITheme.C_DIM)
