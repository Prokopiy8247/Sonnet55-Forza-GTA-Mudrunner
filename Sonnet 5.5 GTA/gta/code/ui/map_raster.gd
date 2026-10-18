class_name MapRaster
extends Node
## Rasterises WorldLayout (water, land tint, districts, parks, roads by class/width, building footprints, piers, runway)
## ONCE into an ImageTexture shared by the minimap and the full-screen map. Until the world is ready a placeholder
## grid texture is served. The raster is repeated (up to MAX_REBUILDS) when the layout data changes (e.g. buildings
## arrive after the roads), then left alone.
##
## Rendering uses a throw-away SubViewport + canvas draw calls (anti-aliased, MSAA 2D); the result is copied to an
## ImageTexture with mipmaps so the shared texture survives after the viewport is freed. Headless runs (no renderer)
## keep the placeholder and log it.

signal rebuilt

const TEX_SIZE := 1536
const ORIGIN := Vector2(-320.0, -320.0)      # world (x, z) of texture pixel (0, 0)
const SIZE := Vector2(640.0, 640.0)          # metres covered
const MAX_REBUILDS := 4

# palette (dark navy basemap, light roads)
const C_VOID := Color("#070b11")
const C_SEA := Color("#0d2840")
const C_SEA_DEEP := Color("#0a1f33")
const C_LAND := Color("#1c2733")
const C_PARK := Color("#244535")
const C_FOREST := Color("#1d3a2e")
const C_HILL := Color("#2a3a39")
const C_BUILDING := Color("#33414f")
const C_BUILDING_HI := Color("#3f4f5f")
const C_SAND := Color("#4a4a42")
const C_PIER := Color("#6b6350")

var texture: Texture2D = null
var is_real := false
var rebuild_count := 0
var last_build_ms := 0

var _vp: SubViewport = null
var _building := false
var _built_sig := ""
var _seen_sig := ""
var _stable := 0.0
var _poll := 0.0
var debug_skip: Dictionary = {}     # layer names to skip (debugging the basemap)


static func world_to_uv(x: float, z: float) -> Vector2:
	return (Vector2(x, z) - ORIGIN) / SIZE


static func world_ready() -> bool:
	return WorldLayout.built or WorldLayout.roads.size() > 0


static func layout_signature() -> String:
	return "%d/%d/%d/%d/%d/%d" % [WorldLayout.roads.size(), WorldLayout.building_footprints.size(), WorldLayout.water_polys.size(),
		WorldLayout.districts.size(), WorldLayout.nature_zones.size(), 1 if WorldLayout.built else 0]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture = make_placeholder()


func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.5 or _building:
		return
	_poll = 0.0
	if rebuild_count >= MAX_REBUILDS or not world_ready():
		return
	var sig := layout_signature()
	if sig != _seen_sig:
		_seen_sig = sig
		_stable = 0.0
		return
	_stable += 0.5
	if _stable >= 1.0 and sig != _built_sig:
		build()


## Hill shading texture sampled from WorldLayout.terrain_height (null on a flat world). Created BEFORE the painter is drawn
## so the texture is fully uploaded when the canvas draw runs.
static func make_relief_texture() -> Texture2D:
	var n := 96
	var step := SIZE.x / n
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var maxh := 0.0
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			var h := WorldLayout.terrain_height(ORIGIN.x + (i + 0.5) * step, ORIGIN.y + (j + 0.5) * step)
			if not is_finite(h):
				h = 0.0
			h = clampf(h, -80.0, 250.0)
			hs[j * n + i] = h
			maxh = maxf(maxh, h)
	if maxh < 5.0:
		return null
	for j in n:
		for i in n:
			var h2 := hs[j * n + i]
			var t := clampf(h2 / maxh, 0.0, 1.0)
			var band := 0.5 + 0.5 * cos(h2 / 10.0 * TAU)
			var al := clampf(t * 0.28 + (band * 0.05 if h2 > 3.0 else 0.0), 0.0, 0.4)
			img.set_pixel(i, j, Color(0.78, 0.9, 0.82, al if h2 > 1.0 else 0.0))
	return ImageTexture.create_from_image(img)


func make_placeholder() -> Texture2D:
	var n := 192
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(C_LAND)
	var px_per_m := float(n) / SIZE.x
	for k in range(-300, 301, 100):
		var p := int((float(k) - ORIGIN.x) * px_per_m)
		for t in n:
			img.set_pixel(clampi(p, 0, n - 1), t, Color(1, 1, 1, 0.12) if k != 0 else Color(0.2, 0.88, 1.0, 0.25))
			img.set_pixel(t, clampi(p, 0, n - 1), Color(1, 1, 1, 0.12) if k != 0 else Color(0.2, 0.88, 1.0, 0.25))
	return ImageTexture.create_from_image(img)


## Renders the basemap. Safe to call repeatedly; returns when the texture has been swapped (or skipped).
func build() -> void:
	if _building:
		return
	if DisplayServer.get_name() == "headless":
		_built_sig = layout_signature()
		print("[MapRaster] headless: keeping placeholder texture")
		return
	_building = true
	var t0 := Time.get_ticks_msec()
	_vp = SubViewport.new()
	_vp.size = Vector2i(TEX_SIZE, TEX_SIZE)
	_vp.transparent_bg = false
	_vp.disable_3d = true
	_vp.msaa_2d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var painter := Painter.new()
	painter.size = Vector2(TEX_SIZE, TEX_SIZE)
	painter.scale_px = float(TEX_SIZE) / SIZE.x
	painter.skip = debug_skip
	painter.relief_tex = make_relief_texture()
	_vp.add_child(painter)
	add_child(_vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = _vp.get_texture().get_image() if is_instance_valid(_vp) else null
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
		is_real = true
		rebuild_count += 1
		_built_sig = layout_signature()
		last_build_ms = Time.get_ticks_msec() - t0
		print("[MapRaster] built %dx%d basemap in %d ms (roads=%d buildings=%d water=%d)" % [TEX_SIZE, TEX_SIZE, last_build_ms,
			WorldLayout.roads.size(), WorldLayout.building_footprints.size(), WorldLayout.water_polys.size()])
		rebuilt.emit()
	else:
		push_warning("[MapRaster] viewport readback failed; keeping previous texture")
		_built_sig = layout_signature()
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_building = false


# =====================================================================================================================
class Painter extends Control:
	var scale_px := 1.0
	var skip: Dictionary = {}
	var relief_tex: Texture2D = null

	func _w2p(x: float, z: float) -> Vector2:
		return (Vector2(x, z) - MapRaster.ORIGIN) * scale_px

	func _poly(pts: PackedVector2Array, col: Color) -> void:
		if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() >= 3:
			draw_colored_polygon(pts, col)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(MapRaster.TEX_SIZE, MapRaster.TEX_SIZE)), MapRaster.C_VOID)
		if not skip.has("land"):
			_draw_land_and_water()
		if not skip.has("districts"):
			_draw_districts()
		if not skip.has("nature"):
			_draw_nature()
		if not skip.has("relief"):
			_draw_relief()
		if not skip.has("piers"):
			_draw_piers()
		if not skip.has("airport"):
			_draw_airport()
		if not skip.has("roads"):
			_draw_roads()
		if not skip.has("buildings"):
			_draw_buildings()
		# playable-area border
		var a := _w2p(-GC.WORLD_HALF, -GC.WORLD_HALF)
		var b := _w2p(GC.WORLD_HALF, GC.WORLD_HALF)
		draw_rect(Rect2(a, b - a), Color(0.2, 0.88, 1.0, 0.25), false, 2.0)

	# ---- water / land --------------------------------------------------------------------------------------------
	func _draw_land_and_water() -> void:
		var half := GC.WORLD_HALF
		var a := _w2p(-half, -half)
		var b := _w2p(half, half)
		var polys: Array = WorldLayout.water_polys
		if not polys.is_empty():
			# land everywhere inside the playable square, sea polygons on top; outside = sea (the island ends at the border)
			draw_rect(Rect2(Vector2.ZERO, Vector2(MapRaster.TEX_SIZE, MapRaster.TEX_SIZE)), MapRaster.C_SEA)
			draw_rect(Rect2(a, b - a), MapRaster.C_LAND)
			for poly in polys:
				var pts := PackedVector2Array()
				for v in poly:
					pts.append(_w2p(v.x, v.y))
				_poly(pts, MapRaster.C_SEA)
			return
		# fallback: sample WorldLayout.is_water on a grid
		var step := 2.5
		var n := int(MapRaster.SIZE.x / step)
		draw_rect(Rect2(Vector2.ZERO, Vector2(MapRaster.TEX_SIZE, MapRaster.TEX_SIZE)), MapRaster.C_LAND)
		for j in n:
			var z := MapRaster.ORIGIN.y + (j + 0.5) * step
			var run_start := -1
			for i in n + 1:
				var water := false
				if i < n:
					var x := MapRaster.ORIGIN.x + (i + 0.5) * step
					water = WorldLayout.is_water(x, z)
				if water and run_start < 0:
					run_start = i
				elif not water and run_start >= 0:
					var p0 := _w2p(MapRaster.ORIGIN.x + run_start * step, MapRaster.ORIGIN.y + j * step)
					var p1 := _w2p(MapRaster.ORIGIN.x + i * step, MapRaster.ORIGIN.y + (j + 1) * step)
					draw_rect(Rect2(p0, p1 - p0 + Vector2(0.6, 0.6)), MapRaster.C_SEA)
					run_start = -1

	func _draw_districts() -> void:
		for d in WorldLayout.districts:
			var r: Rect2 = d.get("rect", Rect2())
			if r.size == Vector2.ZERO:
				continue
			var col: Color = d.get("color", Color(0.5, 0.5, 0.6))
			# clip to land: only tint cells that are land (cheap: rely on draw order; water drawn after in sea-poly mode is not repeated)
			var p0 := _w2p(r.position.x, r.position.y)
			var p1 := _w2p(r.end.x, r.end.y)
			draw_rect(Rect2(p0, p1 - p0), Color(col.r, col.g, col.b, 0.11))

	func _draw_nature() -> void:
		for z in WorldLayout.nature_zones:
			var kind: StringName = z.get("kind", &"park")
			var col := MapRaster.C_PARK
			match kind:
				&"forest": col = MapRaster.C_FOREST
				&"hills": col = MapRaster.C_HILL
				&"beach_palms": col = MapRaster.C_SAND
				&"roadside": continue
			var pts := PackedVector2Array()
			for v in z.get("poly", PackedVector2Array()):
				pts.append(_w2p(v.x, v.y))
			_poly(pts, col)

	func _draw_relief() -> void:
		if relief_tex != null:
			draw_texture_rect(relief_tex, Rect2(Vector2.ZERO, Vector2(MapRaster.TEX_SIZE, MapRaster.TEX_SIZE)), false)

	func _draw_piers() -> void:
		for p in WorldLayout.piers:
			var r: Rect2 = p.get("rect", Rect2())
			var p0 := _w2p(r.position.x, r.position.y)
			var p1 := _w2p(r.end.x, r.end.y)
			draw_rect(Rect2(p0, p1 - p0), MapRaster.C_PIER)

	func _draw_airport() -> void:
		var ap: Dictionary = WorldLayout.airport
		if ap.is_empty():
			return
		var apron: Rect2 = ap.get("apron", Rect2())
		if apron.size != Vector2.ZERO:
			var p0 := _w2p(apron.position.x, apron.position.y)
			var p1 := _w2p(apron.end.x, apron.end.y)
			draw_rect(Rect2(p0, p1 - p0), Color(0.3, 0.36, 0.43))
		var tw: Array = ap.get("taxiway", [])
		if tw.size() >= 2:
			var pts := PackedVector2Array()
			for v in tw:
				pts.append(_w2p(v.x, v.z))
			draw_polyline(pts, Color(0.42, 0.49, 0.57), 5.5 * scale_px / 1.7, true)
		if ap.has("runway_start") and ap.has("runway_end"):
			var s: Vector3 = ap["runway_start"]
			var e: Vector3 = ap["runway_end"]
			var w: float = ap.get("runway_width", 30.0)
			draw_line(_w2p(s.x, s.z), _w2p(e.x, e.z), Color(0.1, 0.13, 0.17), w * scale_px + 4.0, true)
			draw_line(_w2p(s.x, s.z), _w2p(e.x, e.z), Color(0.5, 0.57, 0.66), w * scale_px, true)
			draw_dashed_line(_w2p(s.x, s.z), _w2p(e.x, e.z), Color(1, 1, 1, 0.55), 2.0, 10.0)

	# ---- roads ----------------------------------------------------------------------------------------------------------
	func _draw_roads() -> void:
		var roads: Array = WorldLayout.roads.duplicate()
		roads.sort_custom(func(a, b): return float(a.get("width", 8.0)) < float(b.get("width", 8.0)))
		var casing := Color(0.035, 0.05, 0.07, 0.95)
		for pass_i in 2:
			for r in roads:
				var raw: PackedVector2Array = r.get("points", PackedVector2Array())
				if raw.size() < 2:
					continue
				var pts := PackedVector2Array()
				for v in raw:
					pts.append(_w2p(v.x, v.y))
				var wm: float = r.get("width", 8.0)
				var wpx := maxf(wm * scale_px, 3.2)
				if pass_i == 0:
					draw_polyline(pts, casing, wpx + 4.0, true)
				else:
					draw_polyline(pts, _road_color(r.get("kind", &"street"), wm), wpx, true)

	func _road_color(kind: StringName, wm: float) -> Color:
		match kind:
			&"hill", &"track", &"path", &"trail":
				return Color(0.55, 0.5, 0.4)
			&"service", &"taxiway", &"alley":
				return Color(0.42, 0.49, 0.57)
			&"arterial", &"highway", &"main":
				return Color(0.86, 0.9, 0.95)
		if wm >= 13.0:
			return Color(0.84, 0.88, 0.93)
		if wm >= 9.0:
			return Color(0.66, 0.73, 0.81)
		return Color(0.5, 0.58, 0.67)

	func _draw_buildings() -> void:
		for b in WorldLayout.building_footprints:
			var r: Rect2 = b.get("rect", Rect2())
			if r.size == Vector2.ZERO:
				continue
			var h: float = b.get("height", 10.0)
			var p0 := _w2p(r.position.x, r.position.y)
			var p1 := _w2p(r.end.x, r.end.y)
			var col := MapRaster.C_BUILDING.lerp(MapRaster.C_BUILDING_HI, clampf(h / 70.0, 0.0, 1.0))
			draw_rect(Rect2(p0, p1 - p0), col)
