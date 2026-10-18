class_name RoadBuilder
extends RefCounted
## Builds all ground surfaces that are not the terrain itself: asphalt strips (u across / v along in metres), junction patches with
## rounded curbs, raised sidewalks (0.15 m) + curb faces, crosswalks and stop lines (paint decals), park dirt paths, plus a generic
## API (`add_poly`, `add_strip`, `add_box_collider`) used by the airport / harbour / lot ground builders.
## All meshes are grouped per 100 m sector and material; collision is generated from the same triangles (ConcavePolygonShape3D)
## with meta "surface" (asphalt / concrete / dirt / wood).

const SHADER := "res://gta/generated/shaders/world_road.gdshader"
const Y_ROAD := 0.04
const Y_PAINT := 0.075
const Y_SW := 0.15

const SURFACE_OF := {
	"junction": "asphalt", "sidewalk": "concrete", "curb": "concrete", "dirt": "dirt", "apron": "concrete", "runway": "asphalt",
	"taxiway": "asphalt", "parking": "asphalt", "planks": "wood", "plaza": "concrete", "yard": "concrete", "helipad": "concrete",
	"rail": "metal", "viaduct": "concrete",
}
const NO_COLLIDER := ["paint"]

class Acc:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var faces := PackedVector3Array()
	var collide := true

var world: Node3D
var accs: Dictionary = {}           # "ix,iz|key" -> Acc
var stats := {"tris": 0, "meshes": 0}
static var _mats: Dictionary = {}
var _shader: Shader


func _init(world_root: Node3D) -> void:
	world = world_root
	_shader = load(SHADER)
	if _shader == null:
		push_warning("RoadBuilder: missing shader %s" % SHADER)


# ---- materials --------------------------------------------------------------------------------------------------------
func material(key: String) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.resource_name = "World_" + key
	m.shader = _shader
	if key.begins_with("road_"):
		var cls := StringName(key.substr(5))
		var c: Dictionary = LayoutRoadNet.CLASSES[cls]
		var hw: float
		if bool(c["oneway"]):
			hw = float(c["lanes"]) * float(c["lane_w"]) * 0.5 + 0.5
		else:
			hw = float(c["median"]) * 0.5 + float(c["lanes"]) * float(c["lane_w"]) + 0.25
		m.set_shader_parameter("mode", 0)
		m.set_shader_parameter("half_w", hw)
		m.set_shader_parameter("lane_w", float(c["lane_w"]))
		m.set_shader_parameter("median_w", float(c["median"]))
		m.set_shader_parameter("mark", int(c["mark"]))
	else:
		var mode_of := {"junction": 1, "sidewalk": 2, "paint": 3, "dirt": 4, "curb": 5, "apron": 6, "runway": 7, "taxiway": 8,
			"parking": 9, "planks": 10, "plaza": 11, "yard": 12, "helipad": 13, "rail": 5, "viaduct": 5}
		m.set_shader_parameter("mode", int(mode_of.get(key, 1)))
		if key == "rail":
			m.set_shader_parameter("mode", 5)
			m.set_shader_parameter("concrete", Color(0.22, 0.24, 0.28))
		elif key == "viaduct":
			m.set_shader_parameter("mode", 5)
			m.set_shader_parameter("concrete", Color(0.62, 0.63, 0.66))
		if key == "runway":
			m.set_shader_parameter("half_w", LayoutPlaces.RUNWAY_W * 0.5)
			m.set_shader_parameter("length_m", LayoutPlaces.RUNWAY_X1 - LayoutPlaces.RUNWAY_X0)
		elif key == "taxiway":
			m.set_shader_parameter("half_w", 6.0)
		elif key == "helipad":
			m.set_shader_parameter("half_w", 9.0)
	_mats[key] = m
	return m


# ---- accumulation ------------------------------------------------------------------------------------------------------
func _acc(p: Vector3, key: String) -> Acc:
	var k := "%d,%d|%s" % [int(floor(p.x / SectorManager.CELL)), int(floor(p.z / SectorManager.CELL)), key]
	var a: Acc = accs.get(k, null)
	if a == null:
		a = Acc.new()
		a.collide = not (key in NO_COLLIDER)
		accs[k] = a
	return a


## Triangle facing `want` (front normal). Vertices get uv / colour.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, color: Color, want: Vector3 = Vector3.UP) -> void:
	var cr := (b - a).cross(c - a)
	var front := -cr
	var bb := b
	var cc := c
	var bu := ub
	var cu := uc
	if front.dot(want) < 0.0:
		bb = c
		cc = b
		bu = uc
		cu = ub
		front = -front
	if front.length_squared() < 0.0000001:
		return
	var n := front.normalized()
	var acc := _acc((a + b + c) / 3.0, key)
	acc.verts.append(a)
	acc.verts.append(bb)
	acc.verts.append(cc)
	acc.norms.append(n)
	acc.norms.append(n)
	acc.norms.append(n)
	acc.uvs.append(ua)
	acc.uvs.append(bu)
	acc.uvs.append(cu)
	acc.cols.append(color)
	acc.cols.append(color)
	acc.cols.append(color)
	if acc.collide:
		acc.faces.append(a)
		acc.faces.append(bb)
		acc.faces.append(cc)
	stats["tris"] += 1


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, color: Color, want: Vector3 = Vector3.UP) -> void:
	tri(key, a, b, c, ua, ub, uc, color, want)
	tri(key, a, c, d, ua, uc, ud, color, want)


func _y(p: Vector2) -> float:
	return LayoutTerrain.height(p.x, p.y)


## Horizontal polygon (x,z) at terrain height + dy, triangulated; UV = world xz (metres) unless uv_fn is given.
func add_poly(key: String, poly: PackedVector2Array, dy: float, color: Color = Color(0, 0.5, 0, 1), flat_y: float = NAN) -> void:
	if poly.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		# fallback fan around the centroid
		var cen := Vector2.ZERO
		for p in poly:
			cen += p
		cen /= float(poly.size())
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			_tri_h(key, cen, p0, p1, dy, color, flat_y)
		return
	for t in range(0, idx.size(), 3):
		_tri_h(key, poly[idx[t]], poly[idx[t + 1]], poly[idx[t + 2]], dy, color, flat_y)


func _tri_h(key: String, p0: Vector2, p1: Vector2, p2: Vector2, dy: float, color: Color, flat_y: float) -> void:
	var a := Vector3(p0.x, (flat_y if not is_nan(flat_y) else _y(p0)) + dy, p0.y)
	var b := Vector3(p1.x, (flat_y if not is_nan(flat_y) else _y(p1)) + dy, p1.y)
	var c := Vector3(p2.x, (flat_y if not is_nan(flat_y) else _y(p2)) + dy, p2.y)
	tri(key, a, b, c, p0, p1, p2, color)


## Centre-line strip with explicit half width: UV.x = lateral metres (right = +), UV.y = metres along (starting at v0).
func add_strip(key: String, pts: PackedVector2Array, half_w: float, dy: float, v0: float = 0.0, color: Color = Color(0, 0.5, 0, 1), step: float = 4.0, lat0: float = NAN, lat1: float = NAN) -> void:
	if pts.size() < 2:
		return
	var rs := LayoutGeo.resample(pts, step)
	var cum := LayoutGeo.cum_lengths(rs)
	var l_lat := -half_w if is_nan(lat0) else lat0
	var r_lat := half_w if is_nan(lat1) else lat1
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_v := 0.0
	for i in rs.size():
		var d := LayoutGeo.dir_smooth(rs, cum[i], cum)
		var r := LayoutGeo.right_of(d)
		var c := rs[i]
		var y := _y(c) + dy
		var pl := c + r * l_lat
		var pr := c + r * r_lat
		var vl := Vector3(pl.x, y, pl.y)
		var vr := Vector3(pr.x, y, pr.y)
		var v := v0 + cum[i]
		if i > 0:
			quad(key, prev_l, vl, vr, prev_r, Vector2(l_lat, prev_v), Vector2(l_lat, v), Vector2(r_lat, v), Vector2(r_lat, prev_v), color)
		prev_l = vl
		prev_r = vr
		prev_v = v


## Vertical wall between two ground-plan points from y0 up to y1, facing `want`.
func wall(key: String, p0: Vector2, p1: Vector2, y0: float, y1: float, want: Vector3, color: Color = Color(0, 0.5, 0, 1)) -> void:
	var a := Vector3(p0.x, y0, p0.y)
	var b := Vector3(p1.x, y0, p1.y)
	var c := Vector3(p1.x, y1, p1.y)
	var d := Vector3(p0.x, y1, p0.y)
	quad(key, a, b, c, d, Vector2(0, 0), Vector2(p0.distance_to(p1), 0), Vector2(p0.distance_to(p1), y1 - y0), Vector2(0, y1 - y0), color, want)


# ---- build -----------------------------------------------------------------------------------------------------------------
## Axis aligned box (all six faces) in a ground material key; collides like the key's surface.
func add_box(key: String, center: Vector3, size: Vector3, color: Color = Color(0, 0.5, 0, 1)) -> void:
	var h := size * 0.5
	var c := center
	var p := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)], [4, 0, 3, 7, Vector3(-1, 0, 0)],
		[1, 5, 6, 2, Vector3(1, 0, 0)], [3, 2, 6, 7, Vector3(0, 1, 0)], [4, 5, 1, 0, Vector3(0, -1, 0)]]
	for f in faces:
		var a: Vector3 = c + (p[f[0]] as Vector3)
		var b: Vector3 = c + (p[f[1]] as Vector3)
		var cc: Vector3 = c + (p[f[2]] as Vector3)
		var d: Vector3 = c + (p[f[3]] as Vector3)
		quad(key, a, b, cc, d, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(cc.x, cc.z), Vector2(d.x, d.z), color, f[4])


func build_roads() -> void:
	for e in LayoutRoadNet.edges:
		_edge_strip(e)
		_edge_sidewalks(e)
	for id in LayoutRoadNet.node_ids:
		_junction(id)
	_dirt_paths()


func _edge_strip(e: Dictionary) -> void:
	var pts: PackedVector2Array = e["pts"]
	var s0: float = e["trim_a"]
	var s1: float = float(e["len"]) - float(e["trim_b"])
	if s1 - s0 < 0.5:
		return
	var sub := LayoutGeo.sub(pts, s0, s1)
	var key := "road_" + String(e["cls"])
	add_strip(key, sub, float(e["hw"]), Y_ROAD, s0, Color(0.0, fposmod(float(e["id"]) * 0.381, 1.0), 0.0, 1.0), 4.0)


func _edge_sidewalks(e: Dictionary) -> void:
	var sw: float = e["sw"]
	if sw < 0.1:
		return
	var pts: PackedVector2Array = e["pts"]
	var s0: float = e["trim_a"]
	var s1: float = float(e["len"]) - float(e["trim_b"])
	if s1 - s0 < 0.5:
		return
	var sub := LayoutGeo.resample(LayoutGeo.sub(pts, s0, s1), 4.0)
	var cum := LayoutGeo.cum_lengths(sub)
	var hw: float = e["hw"]
	var col := Color(0, 0.5, 0, 1)
	for side_i in 2:
		var side: float = 1.0 if side_i == 0 else -1.0
		var prev_i := Vector2.ZERO
		var prev_o := Vector2.ZERO
		for i in sub.size():
			var d: Vector2 = LayoutGeo.dir_smooth(sub, cum[i], cum)
			var r: Vector2 = LayoutGeo.right_of(d) * side
			var ci: Vector2 = sub[i] + r * hw
			var co: Vector2 = sub[i] + r * (hw + sw)
			if i > 0:
				_sidewalk_quad(prev_i, ci, co, prev_o, side > 0.0)
			prev_i = ci
			prev_o = co


## One sidewalk panel between two cross-sections: inner edge (road side) i0->i1, outer edge o0->o1. Adds top + curb faces.
func _sidewalk_quad(i0: Vector2, i1: Vector2, o1: Vector2, o0: Vector2, _is_right: bool) -> void:
	var yi0 := _y(i0)
	var yi1 := _y(i1)
	var yo0 := _y(o0)
	var yo1 := _y(o1)
	var col := Color(0, 0.5, 0, 1)
	var a := Vector3(i0.x, yi0 + Y_SW, i0.y)
	var b := Vector3(i1.x, yi1 + Y_SW, i1.y)
	var c := Vector3(o1.x, yo1 + Y_SW, o1.y)
	var d := Vector3(o0.x, yo0 + Y_SW, o0.y)
	quad("sidewalk", a, b, c, d, i0, i1, o1, o0, col)
	# curb face (toward the road) from road level up to the sidewalk
	var inward := Vector3((i0 - o0).x, 0.0, (i0 - o0).y).normalized()
	var ra := Vector3(i0.x, yi0 + Y_ROAD, i0.y)
	var rb := Vector3(i1.x, yi1 + Y_ROAD, i1.y)
	quad("curb", ra, rb, b, a, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col, inward)
	# back face (toward the lots) down to the terrain
	var outward := -inward
	var ba := Vector3(o0.x, yo0 - 0.05, o0.y)
	var bb := Vector3(o1.x, yo1 - 0.05, o1.y)
	quad("curb", ba, bb, c, d, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col, outward)


func _junction(id: String) -> void:
	var j: Dictionary = LayoutRoadNet.junctions[id]
	var n: Dictionary = LayoutRoadNet.nodes[id]
	var c: Vector2 = n["pos"]
	var patch: PackedVector2Array = j["patch"]
	var cy := _y(c)
	# asphalt patch: fan around the node centre (patch polygon is star-shaped w.r.t. the centre)
	for i in patch.size():
		var p0 := patch[i]
		var p1 := patch[(i + 1) % patch.size()]
		var a := Vector3(c.x, cy + Y_ROAD, c.y)
		var b := Vector3(p0.x, _y(p0) + Y_ROAD, p0.y)
		var cc := Vector3(p1.x, _y(p1) + Y_ROAD, p1.y)
		tri("junction", a, b, cc, c, p0, p1, Color(0, 0.5, 0, 1))
	var arms: Array = n["arms"]
	for pad in j["pads"]:
		if pad.get("bulb", false):
			_bulb_ring(pad, n)
			continue
		var poly := PackedVector2Array(pad["poly"])
		add_poly("sidewalk", poly, Y_SW)
		# curb faces: the road-side boundary (er -> arc -> ej) and the lot-side boundary (sj -> X -> si)
		var m := poly.size()
		# polygon layout: er, arc..., ej, sj, [X], si
		var has_x := not bool(pad["straight"]) and m >= 5
		var n_road := m - (3 if has_x else 2)
		for k in range(0, n_road - 1):
			_curb_edge(poly[k], poly[k + 1], c, true)
		var lot_start := n_road - 1
		for k in range(lot_start, m):
			var q0 := poly[k]
			var q1 := poly[(k + 1) % m]
			if k == lot_start:
				continue   # ej -> sj is the sidewalk cut at the arm mouth (joins the strip), no face
			if k == m - 1:
				continue   # si -> er likewise
			_curb_edge(q0, q1, c, false)
	# crosswalks + stop lines
	if arms.size() >= 3:
		for a in arms:
			_arm_paint(c, a)


func _curb_edge(p0: Vector2, p1: Vector2, center: Vector2, road_side: bool) -> void:
	if p0.distance_squared_to(p1) < 0.0004:
		return
	var y0 := _y(p0)
	var y1 := _y(p1)
	var mid := (p0 + p1) * 0.5
	var nrm2 := (p1 - p0).orthogonal().normalized()
	# face direction: toward the junction centre for road-side edges, away for lot-side edges
	var to_c := (center - mid)
	if (nrm2.dot(to_c) > 0.0) != road_side:
		nrm2 = -nrm2
	var want := Vector3(nrm2.x, 0.0, nrm2.y)
	if road_side:
		quad("curb", Vector3(p0.x, y0 + Y_ROAD, p0.y), Vector3(p1.x, y1 + Y_ROAD, p1.y), Vector3(p1.x, y1 + Y_SW, p1.y), Vector3(p0.x, y0 + Y_SW, p0.y),
			Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Color(0, 0.5, 0, 1), want)
	else:
		quad("curb", Vector3(p0.x, y0 - 0.05, p0.y), Vector3(p1.x, y1 - 0.05, p1.y), Vector3(p1.x, y1 + Y_SW, p1.y), Vector3(p0.x, y0 + Y_SW, p0.y),
			Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Color(0, 0.5, 0, 1), want)


func _bulb_ring(pad: Dictionary, n: Dictionary) -> void:
	var outer: PackedVector2Array = pad["ring_outer"]
	var inner: PackedVector2Array = pad["ring_inner"]
	var c: Vector2 = n["pos"]
	var d: Vector2 = pad["dir"]
	var cnt := outer.size()
	for k in cnt:
		var k2 := (k + 1) % cnt
		var dirk := ((inner[k] + inner[k2]) * 0.5 - c).normalized()
		if dirk.dot(d) > 0.5:
			continue
		var a := Vector3(inner[k].x, _y(inner[k]) + Y_SW, inner[k].y)
		var b := Vector3(inner[k2].x, _y(inner[k2]) + Y_SW, inner[k2].y)
		var cc := Vector3(outer[k2].x, _y(outer[k2]) + Y_SW, outer[k2].y)
		var dd := Vector3(outer[k].x, _y(outer[k]) + Y_SW, outer[k].y)
		quad("sidewalk", a, b, cc, dd, inner[k], inner[k2], outer[k2], outer[k], Color(0, 0.5, 0, 1))
		_curb_edge(inner[k], inner[k2], c, true)
		_curb_edge(outer[k], outer[k2], c, false)


func _arm_paint(c: Vector2, a: Dictionary) -> void:
	var d: Vector2 = a["dir"]
	var r := LayoutGeo.right_of(d)
	var hw: float = a["hw"]
	var trim: float = a["trim"]
	var e: Dictionary = LayoutRoadNet.edges[a["edge"]]
	# crosswalk (zebra) when the arm has sidewalks
	if float(a["sw"]) > 0.1:
		_paint_rect(c, d, r, trim + 0.3, trim + 3.3, -hw + 0.35, hw - 0.35, 0.1)
	# stop line across the incoming lanes (outward-left half of the arm)
	var in_dir_exists := true
	if e["oneway"]:
		in_dir_exists = (a["end"] == 1)
	if in_dir_exists:
		var med: float = float(e["median"]) * 0.5 + 0.35
		if e["oneway"]:
			_paint_rect(c, d, r, trim + 4.0, trim + 4.5, -hw + 0.3, hw - 0.3, 0.2)
		else:
			_paint_rect(c, d, r, trim + 4.0, trim + 4.5, -hw + 0.3, -med, 0.2)


func _paint_rect(c: Vector2, d: Vector2, r: Vector2, s0: float, s1: float, l0: float, l1: float, id: float) -> void:
	var p00 := c + d * s0 + r * l0
	var p01 := c + d * s0 + r * l1
	var p11 := c + d * s1 + r * l1
	var p10 := c + d * s1 + r * l0
	var col := Color(id, 0.5, 0.0, 1.0)
	var a := Vector3(p00.x, _y(p00) + Y_PAINT, p00.y)
	var b := Vector3(p01.x, _y(p01) + Y_PAINT, p01.y)
	var cc := Vector3(p11.x, _y(p11) + Y_PAINT, p11.y)
	var dd := Vector3(p10.x, _y(p10) + Y_PAINT, p10.y)
	quad("paint", a, b, cc, dd, Vector2(l0, s0), Vector2(l1, s0), Vector2(l1, s1), Vector2(l0, s1), col)


func build_grounds() -> void:
	for g in LayoutLots.grounds:
		var key: String = g["key"]
		if key == "lawn":
			continue
		var r: Rect2 = g["rect"]
		var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var dy := 0.05 if key == "plaza" else 0.03
		add_poly(key, poly, dy)


func _dirt_paths() -> void:
	for ep in LayoutPlaces.ped_paths():
		if int(ep["zone"]) != PedGraph.ZONE_PARK:
			continue
		var pts: PackedVector2Array = ep["pts"]
		if pts.size() < 2:
			continue
		add_strip("dirt", pts, 1.1, 0.025, 0.0, Color(0, 0.5, 0, 1), 3.0)


# ---- flush: create nodes ------------------------------------------------------------------------------------------------
func flush() -> void:
	var bodies: Dictionary = {}     # "ix,iz|surface" -> Array of faces
	var mesh_count := 0
	for k in accs:
		var acc: Acc = accs[k]
		if acc.verts.is_empty():
			continue
		var parts: PackedStringArray = String(k).split("|")
		var cell_parts: PackedStringArray = parts[0].split(",")
		var key := parts[1]
		var sector_pos := Vector3((float(cell_parts[0]) + 0.5) * SectorManager.CELL, 0.0, (float(cell_parts[1]) + 0.5) * SectorManager.CELL)
		var parent := _sector(sector_pos)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = acc.verts
		arrays[Mesh.ARRAY_NORMAL] = acc.norms
		arrays[Mesh.ARRAY_TEX_UV] = acc.uvs
		arrays[Mesh.ARRAY_COLOR] = acc.cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material(key))
		var mi := MeshInstance3D.new()
		mi.name = "Ground_" + key
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if (key == "paint" or key.begins_with("road_") or key == "junction" or key == "dirt" or key == "parking" or key == "yard") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mi)
		mesh_count += 1
		if acc.collide and not acc.faces.is_empty():
			var surf := "asphalt" if key.begins_with("road_") else String(SURFACE_OF.get(key, "concrete"))
			var bk := "%s|%s" % [parts[0], surf]
			if not bodies.has(bk):
				bodies[bk] = PackedVector3Array()
			var arr: PackedVector3Array = bodies[bk]
			arr.append_array(acc.faces)
			bodies[bk] = arr
	for bk in bodies:
		var parts2: PackedStringArray = String(bk).split("|")
		var cp: PackedStringArray = parts2[0].split(",")
		var sector_pos2 := Vector3((float(cp[0]) + 0.5) * SectorManager.CELL, 0.0, (float(cp[1]) + 0.5) * SectorManager.CELL)
		var body := StaticBody3D.new()
		body.name = "Col_" + parts2[1]
		body.collision_layer = GC.L_WORLD
		body.collision_mask = 0
		body.set_meta("surface", StringName(parts2[1]))
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(bodies[bk])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		_sector(sector_pos2).add_child(body)
	stats["meshes"] = mesh_count
	accs.clear()


func _sector(pos: Vector3) -> Node3D:
	if world.has_method("get_sector_parent"):
		return world.call("get_sector_parent", pos)
	return world


## Axis-aligned or rotated box collider (surface meta) added under the sector of `center`.
func add_box_collider(center: Vector3, size: Vector3, yaw: float, surface: StringName) -> void:
	var body := StaticBody3D.new()
	body.name = "Box_" + String(surface)
	body.collision_layer = GC.L_WORLD
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	_sector(center).add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), center)
