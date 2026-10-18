class_name StuntBuilder
extends RefCounted
## Stunt ramps for the locations stunt_jump_1..3 (launch ramp at the location, landing ramp at its "land" point when it is on land).
## Static wedge meshes with convex colliders (surface "concrete"), neon edge strips so the ramps read at night.

const LEN := 12.0
const WIDTH := 7.0
const HEIGHT := 2.3


static func build(world: Node3D) -> void:
	for id in [&"stunt_jump_1", &"stunt_jump_2", &"stunt_jump_3"]:
		var loc := WorldLayout.get_location(id)
		if loc.is_empty() or not loc.get("ramp", false):
			continue
		var pos: Vector3 = loc["pos"]
		var yaw: float = loc["yaw"]
		var dir := Util.yaw_to_dir(yaw)
		# launch ramp: base at pos (low end), rising along dir
		_ramp(world, pos, dir, true, String(id))
		var land: Vector3 = loc.get("land", Vector3.ZERO)
		if land != Vector3.ZERO and land.y > -0.5:
			# landing ramp: descends along dir, high end first
			var start := land - dir * LEN * 0.5
			_ramp(world, Vector3(start.x, land.y, start.z), dir, false, String(id) + "_land")


static func _ramp(world: Node3D, base: Vector3, dir: Vector3, up: bool, nm: String) -> void:
	var right := Vector3(-dir.z, 0.0, dir.x)   # horizontal, 90 degrees clockwise seen from above
	var hw := WIDTH * 0.5
	var h := HEIGHT
	var p0 := base
	var p1 := base + dir * LEN
	var y0 := 0.0 if up else h
	var y1 := h if up else 0.0
	var a := Vector3(p0.x - right.x * hw, p0.y + y0, p0.z - right.z * hw)
	var b := Vector3(p0.x + right.x * hw, p0.y + y0, p0.z + right.z * hw)
	var c := Vector3(p1.x + right.x * hw, p1.y + y1, p1.z + right.z * hw)
	var d := Vector3(p1.x - right.x * hw, p1.y + y1, p1.z - right.z * hw)
	var a2 := Vector3(a.x, p0.y - 0.3, a.z)
	var b2 := Vector3(b.x, p0.y - 0.3, b.z)
	var c2 := Vector3(c.x, p0.y - 0.3, c.z)
	var d2 := Vector3(d.x, p0.y - 0.3, d.z)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var surf := Color(0.30, 0.31, 0.35)
	var side := Color(0.55, 0.55, 0.58)
	var stripe := Color(1.0, 0.24, 0.6)
	_quad(verts, norms, cols, a, d, c, b, surf)       # top
	_quad(verts, norms, cols, a, a2, d2, d, side)     # side -right
	_quad(verts, norms, cols, b, c, c2, b2, side)     # side +right
	if up:
		_quad(verts, norms, cols, c, d, d2, c2, side)  # back (high end)
	else:
		_quad(verts, norms, cols, a, b, b2, a2, side)
	# neon edge strips
	var lift := Vector3(0, 0.04, 0)
	var sw := 0.25
	_strip(verts, norms, cols, a + lift, d + lift, right * sw, stripe)
	_strip(verts, norms, cols, b + lift, c + lift, -right * sw, stripe)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(1, 0.24, 0.6)
	mat.emission_energy_multiplier = 0.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ramp_" + nm
	mi.mesh = mesh
	var holder := StaticBody3D.new()
	holder.name = "Ramp_" + nm
	holder.collision_layer = GC.L_WORLD
	holder.collision_mask = 0
	holder.set_meta("surface", &"concrete")
	var pts := PackedVector3Array([a, b, c, d, a2, b2, c2, d2])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	holder.add_child(cs)
	holder.add_child(mi)
	var parent: Node3D = world.call("get_sector_parent", base) if world.has_method("get_sector_parent") else world
	parent.add_child(holder)


static func _quad(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color) -> void:
	# (a,b,cc,d) in order; make the front face the side the normal (cross) of (b-a, d-a) points away from
	# clockwise winding = front; our vertices a->b->cc->d: front normal is -cross(b-a, cc-a)
	var front := -(b - a).cross(cc - a).normalized()
	var pts := [a, b, cc, a, cc, d]
	for p in pts:
		v.append(p)
		n.append(front)
		c.append(col)


static func _strip(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, p0: Vector3, p1: Vector3, w: Vector3, col: Color) -> void:
	var a := p0
	var b := p0 + w
	var cc := p1 + w
	var d := p1
	var front := -(b - a).cross(cc - a).normalized()
	if front.y < 0.0:
		var t := b
		b = d
		d = t
		front = -(b - a).cross(cc - a).normalized()
	for p in [a, b, cc, a, cc, d]:
		v.append(p)
		n.append(front)
		c.append(col)
