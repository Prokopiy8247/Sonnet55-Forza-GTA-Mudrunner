class_name VehicleModsMeshes
extends RefCounted
## Mesh helpers for the garage (flat-shaded MB builder used by the livery ribbons) + shared part materials.

# ---- shared materials (resource_name = glTF-style names so Util.replace_material / set_paint / wreck logic work) -----
static var _mats: Dictionary = {}
static var _mesh_cache: Dictionary = {}


static func material(name_: String) -> StandardMaterial3D:
	if _mats.has(name_):
		return _mats[name_]
	var m := StandardMaterial3D.new()
	m.resource_name = name_
	match name_:
		"Paint":
			m.albedo_color = Color(0.8, 0.1, 0.1)
			m.roughness = 0.3
			m.metallic = 0.12
			m.clearcoat_enabled = true
			m.clearcoat = 0.55
		"Trim":
			m.albedo_color = Color(0.05, 0.055, 0.065)
			m.roughness = 0.5
			m.metallic = 0.2
		"Carbon":
			m.albedo_color = Color(0.035, 0.037, 0.045)
			m.roughness = 0.32
			m.metallic = 0.45
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
		"Chrome":
			m.albedo_color = Color(0.86, 0.88, 0.92)
			m.metallic = 1.0
			m.roughness = 0.12
		"Rim":
			m.albedo_color = Color(0.78, 0.8, 0.84)
			m.metallic = 0.85
			m.roughness = 0.22
		"RimDark":
			m.albedo_color = Color(0.03, 0.03, 0.035)
			m.roughness = 0.7
		"PartGlow":
			m.albedo_color = Color(1.0, 0.82, 0.45)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.8, 0.4)
			m.emission_energy_multiplier = 2.2
		"Burnt":
			m.albedo_color = Color(0.02, 0.02, 0.02)
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[name_] = m
	return m


# =====================================================================================================
# Tiny flat-shaded mesh builder
# =====================================================================================================
class MB:
	var tris: Dictionary = {}                 # material name -> PackedVector3Array (3 per triangle)
	var nrm: Dictionary = {}                  # material name -> PackedVector3Array (per vertex)

	## Triangle whose FRONT face looks toward `out_dir` (Godot: front faces are clockwise).
	func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, out_dir: Vector3) -> void:
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			return
		if n.dot(out_dir) < 0.0:
			var t := b
			b = c
			c = t
			n = -n
		n = n.normalized()
		if not tris.has(mat):
			tris[mat] = PackedVector3Array()
			nrm[mat] = PackedVector3Array()
		var arr: PackedVector3Array = tris[mat]
		var na: PackedVector3Array = nrm[mat]
		arr.append(a)
		arr.append(b)
		arr.append(c)
		na.append(n)
		na.append(n)
		na.append(n)
		tris[mat] = arr
		nrm[mat] = na

	func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out_dir: Vector3) -> void:
		tri(mat, a, b, c, out_dir)
		tri(mat, a, c, d, out_dir)

	## Oriented box (center, size, optional rotation basis).
	func box(mat: String, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
		var h := size * 0.5
		var p: Array[Vector3] = []
		for i in 8:
			var sx := 1.0 if (i & 1) != 0 else -1.0
			var sy := 1.0 if (i & 2) != 0 else -1.0
			var sz := 1.0 if (i & 4) != 0 else -1.0
			p.append(center + basis * Vector3(h.x * sx, h.y * sy, h.z * sz))
		var faces := [[1, 3, 7, 5, Vector3.RIGHT], [0, 4, 6, 2, Vector3.LEFT], [2, 6, 7, 3, Vector3.UP], [0, 1, 5, 4, Vector3.DOWN], [4, 5, 7, 6, Vector3.BACK], [0, 2, 3, 1, Vector3.FORWARD]]
		for f in faces:
			quad(mat, p[f[0]], p[f[1]], p[f[2]], p[f[3]], basis * (f[4] as Vector3))

	## Prism: polygon `profile` given as (z, y) points, extruded along X from x0 to x1 (convex or mildly concave profiles).
	func extrude_x(mat: String, profile: Array, x0: float, x1: float) -> void:
		var n := profile.size()
		var cen := Vector2.ZERO
		for p in profile:
			cen += p as Vector2
		cen /= float(n)
		for i in n:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[(i + 1) % n]
			var mid := (p0 + p1) * 0.5
			var out2 := (mid - cen)
			var out := Vector3(0, out2.y, out2.x)
			quad(mat, Vector3(x0, p0.y, p0.x), Vector3(x1, p0.y, p0.x), Vector3(x1, p1.y, p1.x), Vector3(x0, p1.y, p1.x), out)
		for i in range(1, n - 1):
			var a: Vector2 = profile[0]
			var b: Vector2 = profile[i]
			var c: Vector2 = profile[i + 1]
			tri(mat, Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x1, c.y, c.x), Vector3.RIGHT)
			tri(mat, Vector3(x0, a.y, a.x), Vector3(x0, b.y, b.x), Vector3(x0, c.y, c.x), Vector3.LEFT)

	## Cylinder along an arbitrary axis (basis.y is the axis), faceted, optional second radius (cone frustum). Caps included.
	func cyl(mat: String, center: Vector3, radius: float, length: float, segs: int, basis: Basis = Basis.IDENTITY, radius2: float = -1.0, caps: bool = true) -> void:
		var r2 := radius if radius2 < 0.0 else radius2
		var h := length * 0.5
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var p00 := center + basis * (d0 * radius + Vector3(0, -h, 0))
			var p01 := center + basis * (d1 * radius + Vector3(0, -h, 0))
			var p10 := center + basis * (d0 * r2 + Vector3(0, h, 0))
			var p11 := center + basis * (d1 * r2 + Vector3(0, h, 0))
			var mid := basis * ((d0 + d1) * 0.5)
			quad(mat, p00, p01, p11, p10, mid)
			if caps:
				tri(mat, center + basis * Vector3(0, h, 0), p10, p11, basis * Vector3.UP)
				tri(mat, center + basis * Vector3(0, -h, 0), p00, p01, basis * Vector3.DOWN)

	func build() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for mat in tris:
			var arrs: Array = []
			arrs.resize(Mesh.ARRAY_MAX)
			arrs[Mesh.ARRAY_VERTEX] = tris[mat]
			arrs[Mesh.ARRAY_NORMAL] = nrm[mat]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
			var idx := mesh.get_surface_count() - 1
			mesh.surface_set_material(idx, VehicleModsMeshes.material(String(mat)))
			mesh.surface_set_name(idx, String(mat))
		return mesh


