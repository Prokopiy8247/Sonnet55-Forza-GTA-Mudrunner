class_name ContentMesh
extends RefCounted
## Tiny non-indexed mesh builder for the world content (flat-shaded low poly, vertex colours, named surfaces).
## Colours are given in sRGB and stored as linear vertex colours (alpha = foliage sway weight when used).
## Winding is fixed automatically from the requested normal, so callers never think about triangle order.

class Surf extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()

var surfs: Dictionary = {}     # StringName -> Surf (insertion ordered)
var xf := Transform3D.IDENTITY # optional transform applied to everything added afterwards (push/pop below)
var _stack: Array[Transform3D] = []


func push(t: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * t


func pop() -> void:
	if not _stack.is_empty():
		xf = _stack.pop_back()


func surf(key: StringName) -> Surf:
	var s = surfs.get(key)
	if s == null:
		s = Surf.new()
		surfs[key] = s
	return s


func is_empty() -> bool:
	return surfs.is_empty()


## One triangle; `normal` decides which side is the front.
func tri(key: StringName, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, w := 0.0) -> void:
	var s := surf(key)
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var nn := xf.basis * normal
	nn = nn.normalized() if nn.length_squared() > 0.0000001 else Vector3.UP
	var geo := (pb - pa).cross(pc - pa)
	var lin := col.srgb_to_linear()
	lin.a = w
	# Godot front faces are clockwise: the geometric normal of a front face points AWAY from the viewer.
	if geo.dot(nn) > 0.0:
		var tp := pb
		pb = pc
		pc = tp
		var tu := ub
		ub = uc
		uc = tu
	s.v.append(pa)
	s.v.append(pb)
	s.v.append(pc)
	s.n.append(nn)
	s.n.append(nn)
	s.n.append(nn)
	s.uv.append(ua)
	s.uv.append(ub)
	s.uv.append(uc)
	s.c.append(lin)
	s.c.append(lin)
	s.c.append(lin)


## Quad a(bottom-left) b(bottom-right) c(top-right) d(top-left) as seen from the front. `uv0`/`uv1` map a -> uv0, c -> uv1.
func quad(key: StringName, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, col: Color, uv0 := Vector2.ZERO, uv1 := Vector2.ONE, w := 0.0) -> void:
	tri(key, a, b, c, normal, col, uv0, Vector2(uv1.x, uv0.y), uv1, w)
	tri(key, a, c, d, normal, col, uv0, uv1, Vector2(uv0.x, uv1.y), w)


## Smooth-shaded quad (per-corner normals) - for round things.
func quad_smooth(key: StringName, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color, wa := 0.0, wb := 0.0, wc := 0.0, wd := 0.0) -> void:
	var s := surf(key)
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var pd := xf * d
	var lin := col.srgb_to_linear()
	var ncorner: Array[Vector3] = [
		(xf.basis * na).normalized(), (xf.basis * nb).normalized(), (xf.basis * nc).normalized(), (xf.basis * nd).normalized()]
	var avg := ncorner[0] + ncorner[1] + ncorner[2] + ncorner[3]
	var pts: Array[Vector3] = [pa, pb, pc, pd]
	var ws: Array[float] = [wa, wb, wc, wd]
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	var geo := (pb - pa).cross(pc - pa)
	if geo.dot(avg) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		s.v.append(pts[i])
		s.n.append(ncorner[i])
		s.uv.append(Vector2.ZERO)
		var cc := lin
		cc.a = ws[i]
		s.c.append(cc)


## Axis-aligned box (in the current transform). skip: bit mask of faces to omit (1=+X 2=-X 4=+Y 8=-Y 16=+Z 32=-Z).
## uv_metres: UVs hold metre coordinates on each face (for windows / stripes).
func box(key: StringName, center: Vector3, size: Vector3, col := Color.WHITE, skip := 0, w := 0.0) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	if not (skip & 1):    # +X face seen from +X looking -X: left = +Z ... use explicit corners
		quad(key, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3.RIGHT, col, Vector2.ZERO, Vector2.ONE, w)
	if not (skip & 2):
		quad(key, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, col, Vector2.ZERO, Vector2.ONE, w)
	if not (skip & 4):
		quad(key, Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.UP, col, Vector2.ZERO, Vector2.ONE, w)
	if not (skip & 8):
		quad(key, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, col, Vector2.ZERO, Vector2.ONE, w)
	if not (skip & 16):
		quad(key, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, col, Vector2.ZERO, Vector2.ONE, w)
	if not (skip & 32):
		quad(key, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.FORWARD, col, Vector2.ZERO, Vector2.ONE, w)


## Box with different top / side colours.
func box2(key: StringName, center: Vector3, size: Vector3, side: Color, top: Color, skip := 0) -> void:
	box(key, center, size, side, skip | 4)
	if not (skip & 4):
		var h := size * 0.5
		var y1 := center.y + h.y
		quad(key, Vector3(center.x - h.x, y1, center.z + h.z), Vector3(center.x + h.x, y1, center.z + h.z), Vector3(center.x + h.x, y1, center.z - h.z), Vector3(center.x - h.x, y1, center.z - h.z), Vector3.UP, top)


## Frustum / cylinder / cone along +Y. r0 at the bottom, r1 at the top. `smooth` = round normals.
## sway0/sway1: vertex alpha (foliage sway weight) at bottom / top.
func cyl(key: StringName, base: Vector3, r0: float, r1: float, height: float, segs: int, col: Color, smooth := false, cap_bottom := false, cap_top := true, sway0 := 0.0, sway1 := 0.0, col_top := Color(0, 0, 0, 0), phase := 0.0) -> void:
	var ct := col if col_top.a == 0.0 else col_top
	var slope := (r0 - r1) / maxf(height, 0.0001)
	for i in segs:
		var a0 := phase + TAU * float(i) / float(segs)
		var a1 := phase + TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var p00 := base + d0 * r0
		var p10 := base + d1 * r0
		var p11 := base + Vector3(0, height, 0) + d1 * r1
		var p01 := base + Vector3(0, height, 0) + d0 * r1
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		if smooth:
			quad_smooth(key, p00, p10, p11, p01, n0, n1, n1, n0, col, sway0, sway0, sway1, sway1)
		else:
			var dm := ((d0 + d1) * 0.5).normalized()
			var nn := (dm + Vector3(0, slope, 0)).normalized()
			if r1 < 0.0005:
				tri(key, p00, p10, p01, nn, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, sway0)
			else:
				quad(key, p00, p10, p11, p01, nn, col, Vector2.ZERO, Vector2.ONE, sway0)
		if cap_top and r1 > 0.0005:
			tri(key, base + Vector3(0, height, 0), p01, p11, Vector3.UP, ct, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, sway1)
		if cap_bottom:
			tri(key, base, p10, p00, Vector3.DOWN, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, sway0)


## Low-poly faceted blob (jittered icosahedron). Used for tree crowns, bushes, rocks.
## squash scales Y; sway: alpha at the lowest / highest vertex.
func blob(key: StringName, center: Vector3, radius: Vector3, col: Color, seed_v: int, jitter := 0.18, detail := 1, col_top := Color(0, 0, 0, 0), sway_lo := 0.0, sway_hi := 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	if detail >= 1:
		var nverts := verts.duplicate()
		var cache := {}
		var nfaces: Array = []
		var mid := func(a: int, b: int) -> int:
			var k := (mini(a, b) << 16) | maxi(a, b)
			if cache.has(k):
				return cache[k]
			nverts.append(((nverts[a] + nverts[b]) * 0.5).normalized())
			cache[k] = nverts.size() - 1
			return nverts.size() - 1
		for f in faces:
			var a: int = f[0]
			var b: int = f[1]
			var c: int = f[2]
			var ab: int = mid.call(a, b)
			var bc: int = mid.call(b, c)
			var ca: int = mid.call(c, a)
			nfaces.append([a, ab, ca])
			nfaces.append([b, bc, ab])
			nfaces.append([c, ca, bc])
			nfaces.append([ab, bc, ca])
		verts = nverts
		faces = nfaces
	# per-vertex radial jitter (shared between faces so the blob stays closed)
	var jv: Array[float] = []
	for i in verts.size():
		jv.append(1.0 + rng.randf_range(-jitter, jitter))
	var ct := col if col_top.a == 0.0 else col_top
	for f in faces:
		var p: Array[Vector3] = []
		var ys: Array[float] = []
		for k in 3:
			var vv: Vector3 = verts[f[k]]
			p.append(center + Vector3(vv.x * radius.x, vv.y * radius.y, vv.z * radius.z) * jv[f[k]])
			ys.append(vv.y)
		var centroid := (p[0] + p[1] + p[2]) / 3.0
		var nn := (centroid - center).normalized()
		var yy := clampf((centroid.y - center.y) / maxf(radius.y, 0.001) * 0.5 + 0.5, 0.0, 1.0)
		var cc := col.lerp(ct, yy)
		cc = cc.lerp(cc.darkened(0.12), clampf(0.5 - yy, 0.0, 0.5))
		tri(key, p[0], p[1], p[2], nn, cc, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, lerpf(sway_lo, sway_hi, yy))


## Appends another builder's geometry through a transform.
func append(other: ContentMesh, t: Transform3D = Transform3D.IDENTITY) -> void:
	var tt := xf * t
	var nb := tt.basis.inverse().transposed()
	for key in other.surfs:
		var o: Surf = other.surfs[key]
		var s := surf(key)
		for i in o.v.size():
			s.v.append(tt * o.v[i])
			s.n.append((nb * o.n[i]).normalized())
		s.uv.append_array(o.uv)
		s.c.append_array(o.c)


const WALL_SLOTS := {&"WallA": 0, &"WallB": 1, &"WallC": 2, &"WallD": 3, &"Roof": 4, &"Trim": 5, &"V": 6, &"Metal": 7}


## ArrayMesh with one surface per key. `materials` maps key -> Material (missing keys fall back to FacadeMaterials.vcol()).
## With merge_walls (default) every wall-shader key (WallA..D, Roof, Trim, V, Metal) is merged into ONE surface whose slot is baked
## into the vertex alpha (slot / 8) - one draw call for all opaque surfaces of a module.
func to_mesh(materials: Dictionary = {}, merge_walls := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if merge_walls:
		var wv := PackedVector3Array()
		var wn := PackedVector3Array()
		var wuv := PackedVector2Array()
		var wc := PackedColorArray()
		for key in surfs:
			if not WALL_SLOTS.has(key):
				continue
			var s: Surf = surfs[key]
			if s.v.is_empty():
				continue
			var code := float(WALL_SLOTS[key]) / 8.0
			wv.append_array(s.v)
			wn.append_array(s.n)
			wuv.append_array(s.uv)
			var base := wc.size()
			wc.append_array(s.c)
			for i in range(base, wc.size()):
				var c := wc[i]
				c.a = code
				wc[i] = c
		if not wv.is_empty():
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = wv
			arrays[Mesh.ARRAY_NORMAL] = wn
			arrays[Mesh.ARRAY_TEX_UV] = wuv
			arrays[Mesh.ARRAY_COLOR] = wc
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var si := mesh.get_surface_count() - 1
			mesh.surface_set_material(si, FacadeMaterials.wall_merged())
			mesh.surface_set_name(si, "walls")
	for key in surfs:
		if merge_walls and WALL_SLOTS.has(key):
			continue
		var s2: Surf = surfs[key]
		if s2.v.is_empty():
			continue
		var arrays2: Array = []
		arrays2.resize(Mesh.ARRAY_MAX)
		arrays2[Mesh.ARRAY_VERTEX] = s2.v
		arrays2[Mesh.ARRAY_NORMAL] = s2.n
		arrays2[Mesh.ARRAY_TEX_UV] = s2.uv
		arrays2[Mesh.ARRAY_COLOR] = s2.c
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays2)
		var si2 := mesh.get_surface_count() - 1
		var m: Material = materials.get(key)
		if m == null:
			m = FacadeMaterials.vcol()
		mesh.surface_set_material(si2, m)
		mesh.surface_set_name(si2, String(key))
	return mesh


func vertex_count() -> int:
	var n := 0
	for key in surfs:
		n += (surfs[key] as Surf).v.size()
	return n
