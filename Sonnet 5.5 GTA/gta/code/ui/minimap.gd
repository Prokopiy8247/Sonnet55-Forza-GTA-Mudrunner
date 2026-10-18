class_name Minimap
extends Control
## Radar (bottom-left): rotating basemap (shader samples the shared MapRaster texture), clipped to a disc / rounded square,
## with blips drawn on top: player arrow + view cone, police units (red / blue flash), wanted search area, location icons,
## the player's own vehicles, and the waypoint (edge-clamped when out of range).
## Updates every frame for smooth rotation; the (cheap) node scans for blips run at 8 Hz.

const SIZE_PX := 290.0
const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 map_origin = vec2(-320.0, -320.0);
uniform vec2 map_size = vec2(640.0, 640.0);
uniform vec2 center = vec2(0.0);
uniform vec2 fwd = vec2(0.0, -1.0);
uniform float radius_m = 90.0;
uniform vec4 void_color : source_color = vec4(0.027, 0.043, 0.067, 1.0);
uniform float dim = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * radius_m;
	vec2 right = vec2(-fwd.y, fwd.x);
	vec2 w = center + p.x * right + p.y * (-fwd);
	vec2 uv = (w - map_origin) / map_size;
	vec4 c = textureLod(map_tex, uv, log2(max(radius_m / 90.0, 1.0)) * 0.6);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		c = void_color;
	}
	// indoors: desaturated, darkened street map around the door we came through
	c.rgb = mix(c.rgb, vec3(dot(c.rgb, vec3(0.30, 0.59, 0.11))) * 0.42, dim);
	// soft inner shade towards the rim to give depth
	float d = length(UV - 0.5) * 2.0;
	c.rgb *= 1.0 - 0.28 * smoothstep(0.6, 1.0, d);
	COLOR = vec4(c.rgb, 1.0);
}
"""

var raster: MapRaster = null
var round_shape := true
var override_center := Vector3.INF      # tests / showcase: fixed centre instead of the player
var override_heading := NAN             # radians (yaw convention of Util.dir_to_yaw)
var stamina := 1.0                      # ring below the radar

var _clip: Panel
var _map_rect: ColorRect
var _blips: Control
var _overlay: Control
var _mat: ShaderMaterial
var _radius_m := 90.0
var _fwd := Vector2(0, -1)
var _center := Vector2.ZERO
var _t := 0.0
var _scan_acc := 0.0
var _police: Array[Node3D] = []
var _own_vehicles: Array[Node3D] = []
var _locs: Array = []                   # [{id, pos(Vector2), glyph}]
var _locs_sig := -1
var _player_fwd := Vector2(0, -1)
var _ring_flash := 0.0
var _speed_kmh := 0.0
var _flying := false
var _boat := false
var _stamina_alpha := 0.0
var _indoors := 0.0                     # 0..1 blend: the player is inside an interior (Game.get_meta(&"indoors")) -> faded street map around the door
var _last_street := Vector3.ZERO        # last outdoor position (the map is centred there while indoors: interiors sit ~1.7 km outside the city)
var _has_street := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE_PX + 24.0, SIZE_PX + 24.0)
	_clip = Panel.new()
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(_clip)
	_map_rect = ColorRect.new()
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_rect.color = Color.WHITE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_map_rect.material = _mat
	_clip.add_child(_map_rect)
	_blips = BlipLayer.new()
	_blips.owner_map = self
	_clip.add_child(_blips)
	_overlay = OverlayLayer.new()
	_overlay.owner_map = self
	add_child(_overlay)
	resized.connect(_layout)
	set_shape(true)


func _layout() -> void:
	var s := minf(size.x, size.y) - 24.0
	var off := (size - Vector2(s, s)) * 0.5
	_clip.position = off
	_clip.size = Vector2(s, s)
	_map_rect.position = Vector2.ZERO
	_map_rect.size = Vector2(s, s)
	_blips.position = Vector2.ZERO
	_blips.size = Vector2(s, s)
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	set_shape(round_shape)


func set_shape(is_round: bool) -> void:
	round_shape = is_round
	var s := minf(size.x, size.y) - 24.0
	if s <= 0.0:
		s = SIZE_PX
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(int(s * 0.5) if is_round else 22)
	sb.corner_detail = 24
	sb.anti_aliasing = true
	_clip.add_theme_stylebox_override("panel", sb)
	if _overlay != null:
		_overlay.queue_redraw()


func _ready() -> void:
	_layout()


func attach_raster(r: MapRaster) -> void:
	raster = r
	_apply_texture()
	if not r.rebuilt.is_connected(_apply_texture):
		r.rebuilt.connect(_apply_texture)


func _apply_texture() -> void:
	if raster != null and raster.texture != null:
		_mat.set_shader_parameter("map_tex", raster.texture)


# =====================================================================================================================
func _process(delta: float) -> void:
	delta = delta / maxf(Engine.time_scale, 0.05)
	_t += delta
	_scan_acc += delta
	if _scan_acc >= 0.125:
		_scan_acc = 0.0
		_scan_nodes()
	var p: Node3D = Game.player as Node3D if is_instance_valid(Game.player) and (Game.player as Node).is_inside_tree() else null
	var in_room := bool(Game.get_meta(&"indoors", false))
	_indoors = move_toward(_indoors, 1.0 if in_room else 0.0, delta * 3.0)
	var pos := Vector3.ZERO
	if override_center != Vector3.INF:
		pos = override_center
	elif p != null:
		if in_room and _has_street:
			pos = _last_street
		else:
			pos = p.global_position
			if not in_room:
				_last_street = pos
				_has_street = true
	_center = Vector2(pos.x, pos.z)
	# heading = camera forward on the ground plane
	var f := Vector2(0, -1)
	if not is_nan(override_heading):
		var d := Util.yaw_to_dir(override_heading)
		f = Vector2(d.x, d.z)
	elif is_instance_valid(Game.gameplay_camera) and Game.gameplay_camera.is_inside_tree():
		var cf := -Game.gameplay_camera.global_transform.basis.z
		if Vector2(cf.x, cf.z).length() > 0.2:
			f = Vector2(cf.x, cf.z).normalized()
		else:
			f = _fwd
	elif p != null:
		var pf := -p.global_transform.basis.z
		f = Vector2(pf.x, pf.z).normalized()
	_fwd = f
	if p != null and not in_room:
		var pf2 := -p.global_transform.basis.z
		_player_fwd = Vector2(pf2.x, pf2.z).normalized() if Vector2(pf2.x, pf2.z).length() > 0.01 else _player_fwd
	# zoom
	var target := 85.0
	var veh = p.get("current_vehicle") if p != null else null
	if veh != null and is_instance_valid(veh) and veh is Node3D and (veh as Node3D).is_inside_tree():
		var vn := veh as Node3D
		var vf := -vn.global_transform.basis.z
		_player_fwd = Vector2(vf.x, vf.z).normalized() if Vector2(vf.x, vf.z).length() > 0.01 else _player_fwd
		var vc = veh.get("vclass")
		_flying = vc == GC.VC_HELI or vc == GC.VC_PLANE
		_boat = vc == GC.VC_BOAT
		_speed_kmh = float(veh.get_speed_kmh()) if veh.has_method("get_speed_kmh") else 0.0
		if _flying:
			target = lerpf(230.0, 360.0, clampf(_speed_kmh / 300.0, 0.0, 1.0))
		elif _boat:
			target = 150.0
		else:
			target = lerpf(105.0, 190.0, clampf(_speed_kmh / 120.0, 0.0, 1.0))
	else:
		_flying = false
		_boat = false
		_speed_kmh = 0.0
	_radius_m = Util.damp(_radius_m, target, 2.5, delta)
	_mat.set_shader_parameter("center", _center)
	_mat.set_shader_parameter("fwd", _fwd)
	_mat.set_shader_parameter("radius_m", _radius_m)
	_mat.set_shader_parameter("dim", _indoors * 0.85)
	_mat.set_shader_parameter("map_origin", MapRaster.ORIGIN)
	_mat.set_shader_parameter("map_size", MapRaster.SIZE)
	# stamina ring fade
	_stamina_alpha = move_toward(_stamina_alpha, 1.0 if stamina < 0.985 else 0.0, delta * 3.0)
	_blips.queue_redraw()
	_overlay.queue_redraw()


func _scan_nodes() -> void:
	_police.clear()
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if n is Node3D and (n as Node3D).is_inside_tree() and _police.size() < 48:
			if n.get("is_dead") == true or n.get("is_destroyed") == true:
				continue
			_police.append(n)
	_own_vehicles.clear()
	for v in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if v is Node3D and v.get("is_player_owned") == true and _own_vehicles.size() < 6:
			_own_vehicles.append(v)
	if WorldLayout.locations.size() != _locs_sig:
		_locs_sig = WorldLayout.locations.size()
		_locs.clear()
		for id in WorldLayout.locations:
			var info: Array = UIIcons.location_info(id)
			if info.is_empty() or int(info[2]) != 1:
				continue
			var lp: Vector3 = WorldLayout.locations[id].get("pos", Vector3.ZERO)
			_locs.append({"id": id, "pos": Vector2(lp.x, lp.z)})


## world (x, z) -> position inside the blip layer.
func world_to_local(wx: float, wz: float, half: float) -> Vector2:
	var rel := Vector2(wx, wz) - _center
	var sx := -rel.x * _fwd.y + rel.y * _fwd.x
	var sy := -(rel.x * _fwd.x + rel.y * _fwd.y)
	return Vector2(half, half) + Vector2(sx, sy) * (half / _radius_m)


func get_radius_m() -> float:
	return _radius_m


# =====================================================================================================================
func _draw_blips(ci: Control) -> void:
	var half := ci.size.x * 0.5
	var ppm := half / _radius_m
	var rim := half - 7.0
	# --- wanted search area ---
	if Game.wanted_level > 0 and Game.wanted_state == &"search":
		var wsys = Game.sys(&"wanted")
		if wsys != null and wsys.has_method("get_last_known_position"):
			var lk: Vector3 = wsys.get_last_known_position()
			var rad: float = float(wsys.get("search_radius")) if wsys.get("search_radius") != null else 80.0
			var sp := world_to_local(lk.x, lk.z, half)
			var pulse := 0.5 + 0.5 * sin(_t * 4.0)
			var blue := fmod(_t * 2.0, 1.0) < 0.5
			var base := UITheme.C_POLICE_BLUE if blue else UITheme.C_POLICE_RED
			ci.draw_circle(sp, rad * ppm, Color(base.r, base.g, base.b, 0.10 + 0.08 * pulse))
			ci.draw_arc(sp, rad * ppm, 0.0, TAU, 56, Color(base.r, base.g, base.b, 0.55 + 0.3 * pulse), 2.4, true)
	# --- GPS route ---
	var ui = Game.ui
	if ui != null and ui.get("has_waypoint") == true:
		var rt = ui.get("route")
		if rt is UIRoute and rt.points.size() >= 2:
			var run := PackedVector2Array()
			var lim := half * 1.7
			for v in rt.points:
				var rs := world_to_local(v.x, v.z, half)
				if absf(rs.x - half) < lim and absf(rs.y - half) < lim:
					run.append(rs)
				else:
					if run.size() >= 2:
						ci.draw_polyline(run, Color(0, 0, 0, 0.55), 6.0, true)
						ci.draw_polyline(run, UITheme.C_ACCENT, 3.2, true)
					run = PackedVector2Array()
			if run.size() >= 2:
				ci.draw_polyline(run, Color(0, 0, 0, 0.55), 6.0, true)
				ci.draw_polyline(run, UITheme.C_ACCENT, 3.2, true)
	# --- locations ---
	for l in _locs:
		var lp2: Vector2 = l["pos"]
		var s := world_to_local(lp2.x, lp2.y, half)
		if s.distance_to(Vector2(half, half)) < rim - 4.0:
			UIIcons.draw_location(ci, l["id"], s, 8.5, 0.95)
	# --- own vehicles ---
	for v in _own_vehicles:
		if is_instance_valid(v):
			var vs := world_to_local(v.global_position.x, v.global_position.z, half)
			if vs.distance_to(Vector2(half, half)) < rim:
				UIIcons.draw_glyph(ci, &"car", vs, 8.0, UITheme.C_ACCENT, 0.95)
	# --- waypoint ---
	var wp = ui.get("waypoint") if ui != null else null
	if wp is Vector3 and ui.get("has_waypoint") == true:
		var ws := world_to_local(wp.x, wp.z, half)
		var cen := Vector2(half, half)
		var dv := ws - cen
		if dv.length() > rim - 6.0:
			var dir := dv.normalized()
			var ep := cen + dir * (rim - 4.0)
			UIDraw.triangle(ci, ep, 9.0, atan2(dir.x, -dir.y), UITheme.C_ACCENT2)
		else:
			UIIcons.draw_glyph(ci, &"pin", ws + Vector2(0, -6), 9.0, UITheme.C_ACCENT2, 1.0)
	# --- police ---
	var phase_t := _t * 3.2
	for n in _police:
		if not is_instance_valid(n):
			continue
		var ps := world_to_local(n.global_position.x, n.global_position.z, half)
		var cen2 := Vector2(half, half)
		var off := ps - cen2
		if off.length() > rim:
			if n.is_in_group(GC.G_VEHICLE) and n.get("vclass") == GC.VC_HELI:
				ps = cen2 + off.normalized() * (rim - 2.0)
			else:
				continue
		var red := fmod(phase_t + float(n.get_instance_id() % 7) * 0.37, 2.0) < 1.0
		var col := UITheme.C_POLICE_RED if red else UITheme.C_POLICE_BLUE
		var vc = n.get("vclass")
		if vc == GC.VC_HELI:
			var dm := PackedVector2Array([ps + Vector2(0, -8), ps + Vector2(8, 0), ps + Vector2(0, 8), ps + Vector2(-8, 0)])
			ci.draw_colored_polygon(dm, Color(0, 0, 0, 0.7))
			ci.draw_colored_polygon(PackedVector2Array([ps + Vector2(0, -6), ps + Vector2(6, 0), ps + Vector2(0, 6), ps + Vector2(-6, 0)]), col)
		elif vc != null:
			ci.draw_rect(Rect2(ps - Vector2(5.5, 5.5), Vector2(11, 11)), Color(0, 0, 0, 0.7))
			ci.draw_rect(Rect2(ps - Vector2(4, 4), Vector2(8, 8)), col)
		else:
			ci.draw_circle(ps, 5.0, Color(0, 0, 0, 0.7))
			ci.draw_circle(ps, 3.6, col)
	# --- player: view cone + arrow ---
	var c := Vector2(half, half)
	var cone_len := half * 0.55
	var cone := PackedVector2Array([c, c + Vector2(-0.45, -1.0).normalized() * cone_len, c + Vector2(0.45, -1.0).normalized() * cone_len])
	ci.draw_colored_polygon(cone, Color(1, 1, 1, 0.07))
	if _indoors > 0.01:
		# inside a building: a pulsing ring marks the door we came through, the arrow becomes a small dot and a label says where we are
		var pulse2 := 0.5 + 0.5 * sin(_t * 3.0)
		ci.draw_arc(c, 15.0 + 4.0 * pulse2, 0.0, TAU, 32, Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, (0.55 + 0.35 * pulse2) * _indoors), 2.2, true)
		ci.draw_circle(c, 6.0, Color(0, 0, 0, 0.7 * _indoors))
		ci.draw_circle(c, 4.2, Color(1, 1, 1, 0.95 * _indoors))
		UIDraw.text_center(ci, UITheme.font(true), "INTERIOR", c + Vector2(0, half * 0.56), 17, Color(1, 1, 1, 0.9 * _indoors))
		if _indoors >= 0.999:
			return
	# player heading relative to the camera heading
	var rs := -_player_fwd.x * _fwd.y + _player_fwd.y * _fwd.x
	var ru := -(_player_fwd.x * _fwd.x + _player_fwd.y * _fwd.y)
	var ang := atan2(rs, -ru)
	UIDraw.triangle(ci, c, 11.5, ang, Color(0, 0, 0, 0.75))
	UIDraw.triangle(ci, c, 9.0, ang, Color.WHITE)


func _draw_overlay(ci: Control) -> void:
	var c := ci.size * 0.5
	var s := minf(ci.size.x, ci.size.y) - 24.0
	var R := s * 0.5
	# ring colour reflects the police state
	var ring := Color(0.07, 0.09, 0.13, 0.98)
	var accent := Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, 0.55)
	if Game.wanted_level > 0 and Game.wanted_state == &"pursuit":
		var blue := fmod(_t * 3.0, 2.0) >= 1.0
		var pc := UITheme.C_POLICE_BLUE if blue else UITheme.C_POLICE_RED
		accent = Color(pc.r, pc.g, pc.b, 0.95)
	elif Game.wanted_level > 0:
		var pc2 := UITheme.C_POLICE_BLUE
		accent = Color(pc2.r, pc2.g, pc2.b, 0.45 + 0.4 * (0.5 + 0.5 * sin(_t * 4.0)))
	if round_shape:
		ci.draw_arc(c, R + 6.0, 0.0, TAU, 96, Color(0, 0, 0, 0.35), 8.0, true)
		ci.draw_arc(c, R + 3.0, 0.0, TAU, 96, ring, 7.0, true)
		ci.draw_arc(c, R - 1.0, 0.0, TAU, 96, accent, 2.2, true)
		# stamina ring (bottom-right arc) with fade
		if _stamina_alpha > 0.01:
			var a0 := deg_to_rad(8.0)
			var a1 := deg_to_rad(82.0)
			ci.draw_arc(c, R + 3.0, a0, a1, 24, Color(1, 1, 1, 0.16 * _stamina_alpha), 5.0, true)
			var sc := UITheme.C_WARN.lerp(UITheme.C_DANGER, 1.0 - smoothstep(0.05, 0.35, stamina))
			ci.draw_arc(c, R + 3.0, a0, lerpf(a0, a1, clampf(stamina, 0.0, 1.0)), 24, Color(sc.r, sc.g, sc.b, _stamina_alpha), 5.0, true)
		# north marker
		var nd := Vector2(-_fwd.x, _fwd.y)    # direction of north in screen space: (-fx, fz)
		var np := c + nd.normalized() * (R + 3.0)
		ci.draw_circle(np, 11.0, Color(0.05, 0.07, 0.1, 0.98))
		ci.draw_arc(np, 11.0, 0.0, TAU, 24, Color(UITheme.C_ACCENT2.r, UITheme.C_ACCENT2.g, UITheme.C_ACCENT2.b, 0.9), 1.8, true)
		UIDraw.text_center(ci, UITheme.font(true), "N", np + Vector2(0, 0.5), 15, Color.WHITE)
	else:
		var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
		UIDraw.rrect(ci, r.grow(4.0), Color(0, 0, 0, 0), 24, 6.0, ring)
		UIDraw.rrect(ci, r, Color(0, 0, 0, 0), 22, 2.0, accent)


class BlipLayer extends Control:
	var owner_map: Minimap

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if owner_map != null:
			owner_map._draw_blips(self)


class OverlayLayer extends Control:
	var owner_map: Minimap

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if owner_map != null:
			owner_map._draw_overlay(self)
