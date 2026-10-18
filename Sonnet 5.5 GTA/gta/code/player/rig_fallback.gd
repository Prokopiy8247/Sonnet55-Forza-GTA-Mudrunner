class_name RigFallback
extends RefCounted
## FALLBACK ONLY: procedural stand-in for characters/human.glb (docs/ARCHITECTURE.md section 12 skeleton + simple faceted
## capsule-limb meshes), used until the Blender-authored GLB exists. Builds the same node structure as the GLB:
##   Human (Node3D) > Armature (Node3D) > Skeleton (Skeleton3D) > Body_A/B/C, Hair_1..6, Hat_*, Helmet_Tactical, Glasses_*,
##   Vest_*, Jacket_*, Backpack, Beard_* (skinned MeshInstance3D, surfaces named by material slot).
## CharacterRig logs a warning every time this is used.

# name, parent, head, tail  (Godot coordinates: X right, Y up, -Z forward). _L bones are mirrored from _R.
const BONES_R := [
	["Shoulder_R", "Chest", Vector3(0.03, 1.40, 0), Vector3(0.17, 1.42, 0)],
	["UpperArm_R", "Shoulder_R", Vector3(0.19, 1.40, 0), Vector3(0.30, 1.12, 0)],
	["LowerArm_R", "UpperArm_R", Vector3(0.30, 1.12, 0), Vector3(0.40, 0.87, 0)],
	["Hand_R", "LowerArm_R", Vector3(0.40, 0.87, 0), Vector3(0.44, 0.76, 0)],
	["UpperLeg_R", "Hips", Vector3(0.09, 0.92, 0), Vector3(0.10, 0.50, 0)],
	["LowerLeg_R", "UpperLeg_R", Vector3(0.10, 0.50, 0), Vector3(0.10, 0.09, 0)],
	["Foot_R", "LowerLeg_R", Vector3(0.10, 0.09, 0), Vector3(0.10, 0.03, -0.14)],
	["Toe_R", "Foot_R", Vector3(0.10, 0.03, -0.14), Vector3(0.10, 0.02, -0.24)],
]
const BODY_BONES := [
	["Hips", "", Vector3(0, 0.95, 0), Vector3(0, 1.02, 0)],
	["Spine", "Hips", Vector3(0, 1.02, 0), Vector3(0, 1.18, 0)],
	["Chest", "Spine", Vector3(0, 1.18, 0), Vector3(0, 1.40, 0)],
	["Neck", "Chest", Vector3(0, 1.40, 0), Vector3(0, 1.52, 0)],
	["Head", "Neck", Vector3(0, 1.52, 0), Vector3(0, 1.80, 0)],
]

# per body type proportions: [chest_rx, chest_rz, waist_rx, waist_rz, hip_rx, hip_rz, thigh_r, arm_r, head_scale]
const PROPORTIONS := {
	&"A": [0.200, 0.120, 0.160, 0.105, 0.175, 0.115, 0.088, 0.052, 1.0],
	&"B": [0.168, 0.110, 0.120, 0.090, 0.185, 0.120, 0.090, 0.044, 0.96],
	&"C": [0.235, 0.160, 0.215, 0.165, 0.215, 0.150, 0.108, 0.064, 1.04],
}
const HAIR_STYLES := 6


## Returns the model root (Node3D "Human") with the skeleton and all meshes. `wanted_body` etc. are NOT applied here.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "HumanFallback"
	var arm := Node3D.new()
	arm.name = "Armature"
	root.add_child(arm)
	var sk := _make_skeleton()
	arm.add_child(sk)
	var skin := sk.create_skin_from_rest_transforms()
	for body in [&"A", &"B", &"C"]:
		_add_mesh(sk, skin, "Body_" + String(body), _build_body(body, sk))
	for i in HAIR_STYLES:
		_add_mesh(sk, skin, "Hair_%d" % (i + 1), _build_hair(i + 1, sk))
	for n in ["Hat_Cap", "Hat_Beanie", "Hat_Police", "Helmet_Tactical", "Glasses_Round", "Glasses_Shades", "Vest_Armor",
			"Vest_Tactical", "Jacket_Short", "Jacket_Long", "Backpack", "Beard_1", "Beard_2"]:
		_add_mesh(sk, skin, n, _build_accessory(n, sk))
	return root


static func _add_mesh(sk: Skeleton3D, skin: Skin, mesh_name: String, mesh: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skin


static func _make_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	var defs: Array = []
	defs.append_array(BODY_BONES)
	for e in BONES_R:
		defs.append(e)
	for e in BONES_R:
		var nm := String(e[0]).replace("_R", "_L")
		var par := String(e[1])
		par = par.replace("_R", "_L")
		defs.append([nm, par, _mirror(e[2]), _mirror(e[3])])
	var index := {}
	var bases := {}
	var heads := {}
	for e in defs:
		var bone_name: String = e[0]
		var i := sk.add_bone(bone_name)
		index[bone_name] = i
		var head: Vector3 = e[2]
		var tail: Vector3 = e[3]
		var dir := (tail - head).normalized()
		var b := Basis(Quaternion(Vector3.UP, dir))
		bases[bone_name] = b
		heads[bone_name] = head
		var par_name: String = e[1]
		if par_name == "":
			sk.set_bone_rest(i, Transform3D(b, head))
		else:
			sk.set_bone_parent(i, index[par_name])
			var pb: Basis = bases[par_name]
			sk.set_bone_rest(i, Transform3D(pb.transposed() * b, pb.transposed() * (head - heads[par_name])))
	sk.reset_bone_poses()
	return sk


static func _mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


# ---- Mesh construction -----------------------------------------------------------------------------------------------
class MB:
	extends RefCounted
	var surfaces := {}      # material name -> {v, n, b, w}
	var order: Array[String] = []

	func _surf(mat: String) -> Dictionary:
		if not surfaces.has(mat):
			surfaces[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "b": PackedInt32Array(), "w": PackedFloat32Array()}
			order.append(mat)
		return surfaces[mat]

	func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, bone: int, center: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		var cen := (a + b + c) / 3.0
		if n.dot(cen - center) < 0.0:
			var t := b
			b = c
			c = t
			n = -n
		n = n.normalized()
		var s := _surf(mat)
		for p in [a, b, c]:
			s["v"].append(p)
			s["n"].append(n)
			s["b"].append_array(PackedInt32Array([bone, 0, 0, 0]))
			s["w"].append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))

	func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, bone: int, center: Vector3) -> void:
		tri(mat, a, b, c, bone, center)
		tri(mat, a, c, d, bone, center)

	## Axis-aligned (optionally rotated) box.
	func box(mat: String, c: Vector3, size: Vector3, bone: int, rot: Basis = Basis.IDENTITY) -> void:
		var h := size * 0.5
		var pts: Array[Vector3] = []
		for i in 8:
			var p := Vector3(h.x if (i & 1) else -h.x, h.y if (i & 2) else -h.y, h.z if (i & 4) else -h.z)
			pts.append(c + rot * p)
		var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]
		for f in faces:
			quad(mat, pts[f[0]], pts[f[1]], pts[f[2]], pts[f[3]], bone, c)

	## Elliptic loft from p0 to p1 (radii r = (rx, rz) in the plane perpendicular to the axis), optional dome caps.
	func loft(mat: String, p0: Vector3, p1: Vector3, r0: Vector2, r1: Vector2, bone: int, segs: int = 8, cap0: float = 0.5, cap1: float = 0.5) -> void:
		var axis := p1 - p0
		var ax := axis.normalized()
		var e1 := Vector3.RIGHT - ax * ax.dot(Vector3.RIGHT)
		if e1.length() < 0.2:
			e1 = Vector3.BACK - ax * ax.dot(Vector3.BACK)
		e1 = e1.normalized()
		var e2 := ax.cross(e1).normalized()
		var mid := (p0 + p1) * 0.5
		var ring0: Array[Vector3] = []
		var ring1: Array[Vector3] = []
		for k in segs:
			var a := TAU * float(k) / float(segs) + PI / float(segs)
			var ca := cos(a)
			var sa := sin(a)
			ring0.append(p0 + e1 * (r0.x * ca) + e2 * (r0.y * sa))
			ring1.append(p1 + e1 * (r1.x * ca) + e2 * (r1.y * sa))
		for k in segs:
			var k2 := (k + 1) % segs
			quad(mat, ring0[k], ring0[k2], ring1[k2], ring1[k], bone, mid)
		if cap0 > 0.0:
			var pole := p0 - ax * (minf(r0.x, r0.y) * cap0 * 2.0)
			for k in segs:
				tri(mat, ring0[k], ring0[(k + 1) % segs], pole, bone, mid)
		if cap1 > 0.0:
			var pole := p1 + ax * (minf(r1.x, r1.y) * cap1 * 2.0)
			for k in segs:
				tri(mat, ring1[k], ring1[(k + 1) % segs], pole, bone, mid)

	## Ellipsoid (radii per axis); lat_min/lat_max in degrees (-90..90) allow caps / domes.
	func sphere(mat: String, c: Vector3, r: Vector3, bone: int, segs: int = 8, rings: int = 5, lat_min: float = -90.0, lat_max: float = 90.0) -> void:
		var grid: Array = []
		for j in rings + 1:
			var lat := deg_to_rad(lerpf(lat_min, lat_max, float(j) / float(rings)))
			var row: Array[Vector3] = []
			for k in segs:
				var a := TAU * float(k) / float(segs) + PI / float(segs)
				row.append(c + Vector3(cos(lat) * cos(a) * r.x, sin(lat) * r.y, cos(lat) * sin(a) * r.z))
			grid.append(row)
		for j in rings:
			for k in segs:
				var k2 := (k + 1) % segs
				var a: Vector3 = grid[j][k]
				var b: Vector3 = grid[j][k2]
				var cc: Vector3 = grid[j + 1][k2]
				var d: Vector3 = grid[j + 1][k]
				if a.is_equal_approx(b):
					tri(mat, a, cc, d, bone, c)
				elif cc.is_equal_approx(d):
					tri(mat, a, b, cc, bone, c)
				else:
					quad(mat, a, b, cc, d, bone, c)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for mat in order:
			var s: Dictionary = surfaces[mat]
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = s["v"]
			arrays[Mesh.ARRAY_NORMAL] = s["n"]
			arrays[Mesh.ARRAY_BONES] = s["b"]
			arrays[Mesh.ARRAY_WEIGHTS] = s["w"]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var m := StandardMaterial3D.new()
			m.resource_name = mat
			m.albedo_color = Color(0.8, 0.8, 0.8)
			m.roughness = 0.85
			mesh.surface_set_material(mesh.get_surface_count() - 1, m)
		return mesh


static func _bi(sk: Skeleton3D, n: String) -> int:
	return sk.find_bone(n)


static func _build_body(body: StringName, sk: Skeleton3D) -> ArrayMesh:
	var pr: Array = PROPORTIONS[body]
	var b := MB.new()
	var hips := _bi(sk, "Hips")
	var spine := _bi(sk, "Spine")
	var chest := _bi(sk, "Chest")
	var neck := _bi(sk, "Neck")
	var head := _bi(sk, "Head")
	var hs: float = pr[8]
	# pelvis / waist / chest
	b.loft("Pants", Vector3(0, 0.86, 0), Vector3(0, 1.04, 0), Vector2(pr[4] * 0.95, pr[5]), Vector2(pr[2], pr[3]), hips, 8, 0.0, 0.0)
	b.loft("Accent", Vector3(0, 1.03, 0), Vector3(0, 1.075, 0), Vector2(pr[2] * 1.04, pr[3] * 1.05), Vector2(pr[2] * 1.04, pr[3] * 1.05), hips, 8, 0.0, 0.0)
	b.loft("Shirt", Vector3(0, 1.07, 0), Vector3(0, 1.20, 0), Vector2(pr[2], pr[3]), Vector2(pr[0] * 0.92, pr[1] * 0.95), spine, 8, 0.0, 0.0)
	b.loft("Shirt", Vector3(0, 1.19, 0), Vector3(0, 1.42, 0), Vector2(pr[0] * 0.92, pr[1] * 0.95), Vector2(pr[0], pr[1]), chest, 8, 0.0, 0.35)
	b.loft("Skin", Vector3(0, 1.40, 0), Vector3(0, 1.58, 0), Vector2(0.058, 0.06), Vector2(0.054, 0.056), neck, 8, 0.0, 0.0)
	# head with simple face (nose + eyes show the facing direction)
	var hc := Vector3(0, 1.675, 0)
	b.sphere("Skin", hc, Vector3(0.105, 0.125, 0.115) * hs, head, 8, 5)
	b.box("Skin", hc + Vector3(0, -0.02, -0.118) * hs, Vector3(0.026, 0.05, 0.04) * hs, head)
	b.box("Trim", hc + Vector3(-0.04, 0.025, -0.108) * hs, Vector3(0.026, 0.016, 0.02) * hs, head)
	b.box("Trim", hc + Vector3(0.04, 0.025, -0.108) * hs, Vector3(0.026, 0.016, 0.02) * hs, head)
	# shoulders / arms / legs / feet (mirrored)
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var sh := _bi(sk, "Shoulder_R" if side == 0 else "Shoulder_L")
		var ua := _bi(sk, "UpperArm_R" if side == 0 else "UpperArm_L")
		var la := _bi(sk, "LowerArm_R" if side == 0 else "LowerArm_L")
		var hd := _bi(sk, "Hand_R" if side == 0 else "Hand_L")
		var ul := _bi(sk, "UpperLeg_R" if side == 0 else "UpperLeg_L")
		var ll := _bi(sk, "LowerLeg_R" if side == 0 else "LowerLeg_L")
		var ft := _bi(sk, "Foot_R" if side == 0 else "Foot_L")
		var toe := _bi(sk, "Toe_R" if side == 0 else "Toe_L")
		var ar: float = pr[7]
		b.loft("Shirt", Vector3(sx * 0.03, 1.405, 0), Vector3(sx * 0.18, 1.415, 0), Vector2(0.055, 0.075), Vector2(0.06, 0.08), sh, 6, 0.0, 0.0)
		b.sphere("Shirt", Vector3(sx * 0.205, 1.385, 0), Vector3(ar * 1.45, ar * 1.5, ar * 1.45), ua, 6, 4)
		b.loft("Shirt", Vector3(sx * 0.19, 1.39, 0), Vector3(sx * 0.30, 1.12, 0), Vector2(ar * 1.35, ar * 1.3), Vector2(ar * 1.15, ar * 1.1), ua, 7, 0.0, 0.0)
		b.loft("Skin", Vector3(sx * 0.30, 1.12, 0), Vector3(sx * 0.40, 0.87, 0), Vector2(ar * 1.05, ar * 1.0), Vector2(ar * 0.8, ar * 0.8), la, 7, 0.5, 0.0)
		b.loft("Skin", Vector3(sx * 0.405, 0.865, 0), Vector3(sx * 0.44, 0.765, 0), Vector2(0.040, 0.025), Vector2(0.034, 0.022), hd, 6, 0.0, 0.6)
		b.box("Skin", Vector3(sx * 0.425, 0.84, -0.03), Vector3(0.014, 0.045, 0.02), hd)   # thumb
		var tr: float = pr[6]
		b.loft("Pants", Vector3(sx * 0.09, 0.93, 0), Vector3(sx * 0.10, 0.50, 0), Vector2(tr * 1.15, tr * 1.15), Vector2(tr * 0.82, tr * 0.82), ul, 8, 0.4, 0.0)
		b.loft("Pants", Vector3(sx * 0.10, 0.50, 0), Vector3(sx * 0.10, 0.12, 0), Vector2(tr * 0.82, tr * 0.82), Vector2(tr * 0.62, tr * 0.62), ll, 8, 0.0, 0.0)
		b.box("Shoes", Vector3(sx * 0.10, 0.045, -0.055), Vector3(0.10, 0.075, 0.24), ft)
		b.box("Shoes", Vector3(sx * 0.10, 0.03, -0.205), Vector3(0.095, 0.05, 0.10), toe)
	return b.commit()


static func _build_hair(style: int, sk: Skeleton3D) -> ArrayMesh:
	var b := MB.new()
	var head := _bi(sk, "Head")
	var hc := Vector3(0, 1.675, 0)
	match style:
		1:  # short crop
			b.sphere("Hair", hc + Vector3(0, 0.02, 0.012), Vector3(0.113, 0.125, 0.125), head, 8, 4, 8.0, 90.0)
		2:  # side part, medium back
			b.sphere("Hair", hc + Vector3(0, 0.022, 0.015), Vector3(0.118, 0.13, 0.13), head, 8, 4, 5.0, 90.0)
			b.box("Hair", hc + Vector3(0, -0.01, 0.1), Vector3(0.2, 0.14, 0.05), head)
			b.box("Hair", hc + Vector3(-0.07, 0.085, -0.11), Vector3(0.09, 0.03, 0.04), head)
		3:  # long
			b.sphere("Hair", hc + Vector3(0, 0.022, 0.015), Vector3(0.12, 0.132, 0.132), head, 8, 4, 0.0, 90.0)
			b.box("Hair", hc + Vector3(0, -0.12, 0.105), Vector3(0.23, 0.36, 0.06), head)
			b.box("Hair", hc + Vector3(0.112, -0.06, 0.03), Vector3(0.025, 0.22, 0.12), head)
			b.box("Hair", hc + Vector3(-0.112, -0.06, 0.03), Vector3(0.025, 0.22, 0.12), head)
		4:  # ponytail
			b.sphere("Hair", hc + Vector3(0, 0.02, 0.015), Vector3(0.115, 0.127, 0.128), head, 8, 4, 5.0, 90.0)
			b.loft("Hair", hc + Vector3(0, 0.02, 0.12), hc + Vector3(0, -0.2, 0.19), Vector2(0.04, 0.04), Vector2(0.025, 0.025), head, 6, 0.4, 0.6)
		5:  # big rounded
			b.sphere("Hair", hc + Vector3(0, 0.05, 0.02), Vector3(0.17, 0.165, 0.17), head, 8, 5, -15.0, 90.0)
		_:  # 6: mohawk
			b.sphere("Hair", hc + Vector3(0, 0.0, 0.02), Vector3(0.106, 0.118, 0.118), head, 8, 3, 25.0, 90.0)
			b.box("Hair", hc + Vector3(0, 0.12, 0.0), Vector3(0.04, 0.07, 0.22), head)
	return b.commit()


static func _build_accessory(n: String, sk: Skeleton3D) -> ArrayMesh:
	var b := MB.new()
	var head := _bi(sk, "Head")
	var chest := _bi(sk, "Chest")
	var spine := _bi(sk, "Spine")
	var hips := _bi(sk, "Hips")
	var hc := Vector3(0, 1.675, 0)
	match n:
		"Hat_Cap":
			b.sphere("Accent", hc + Vector3(0, 0.03, 0.01), Vector3(0.118, 0.12, 0.13), head, 8, 4, 8.0, 90.0)
			b.box("Accent", hc + Vector3(0, 0.045, -0.14), Vector3(0.19, 0.012, 0.12), head)
		"Hat_Beanie":
			b.sphere("Accent", hc + Vector3(0, 0.03, 0.01), Vector3(0.122, 0.15, 0.13), head, 8, 4, -12.0, 90.0)
			b.loft("Accent", hc + Vector3(0, 0.035, 0.0), hc + Vector3(0, 0.07, 0.0), Vector2(0.126, 0.136), Vector2(0.126, 0.136), head, 8, 0.0, 0.0)
		"Hat_Police":
			b.loft("Accent", hc + Vector3(0, 0.05, 0.0), hc + Vector3(0, 0.15, 0.0), Vector2(0.118, 0.13), Vector2(0.128, 0.138), head, 8, 0.0, 0.0)
			b.box("Trim", hc + Vector3(0, 0.055, -0.135), Vector3(0.2, 0.012, 0.11), head)
			b.box("Trim", hc + Vector3(0, 0.07, -0.123), Vector3(0.12, 0.014, 0.012), head)
		"Helmet_Tactical":
			b.sphere("Accent", hc + Vector3(0, 0.02, 0.02), Vector3(0.14, 0.145, 0.155), head, 10, 5, -5.0, 90.0)
			b.box("Trim", hc + Vector3(0, 0.1, -0.1), Vector3(0.06, 0.04, 0.05), head)
		"Glasses_Round":
			b.box("Trim", hc + Vector3(-0.042, 0.022, -0.118), Vector3(0.05, 0.042, 0.012), head)
			b.box("Trim", hc + Vector3(0.042, 0.022, -0.118), Vector3(0.05, 0.042, 0.012), head)
			b.box("Trim", hc + Vector3(0, 0.03, -0.118), Vector3(0.05, 0.01, 0.012), head)
		"Glasses_Shades":
			b.box("Trim", hc + Vector3(0, 0.02, -0.12), Vector3(0.21, 0.046, 0.014), head)
		"Vest_Armor":
			b.loft("Accent", Vector3(0, 1.10, 0), Vector3(0, 1.42, 0), Vector2(0.205, 0.135), Vector2(0.215, 0.138), chest, 8, 0.0, 0.0)
		"Vest_Tactical":
			b.loft("Accent", Vector3(0, 1.08, 0), Vector3(0, 1.42, 0), Vector2(0.21, 0.14), Vector2(0.22, 0.142), chest, 8, 0.0, 0.0)
			b.box("Trim", Vector3(-0.09, 1.16, -0.155), Vector3(0.09, 0.1, 0.05), chest)
			b.box("Trim", Vector3(0.09, 1.16, -0.155), Vector3(0.09, 0.1, 0.05), chest)
		"Jacket_Short":
			b.loft("Shirt", Vector3(0, 1.02, 0), Vector3(0, 1.42, 0), Vector2(0.185, 0.128), Vector2(0.225, 0.14), chest, 8, 0.0, 0.0)
			for sx in [1.0, -1.0]:
				var ua := _bi(sk, "UpperArm_R" if sx > 0 else "UpperArm_L")
				var la := _bi(sk, "LowerArm_R" if sx > 0 else "LowerArm_L")
				b.loft("Shirt", Vector3(sx * 0.19, 1.395, 0), Vector3(sx * 0.30, 1.12, 0), Vector2(0.068, 0.066), Vector2(0.06, 0.058), ua, 7, 0.0, 0.0)
				b.loft("Shirt", Vector3(sx * 0.30, 1.12, 0), Vector3(sx * 0.385, 0.91, 0), Vector2(0.058, 0.056), Vector2(0.05, 0.05), la, 7, 0.0, 0.0)
		"Jacket_Long":
			b.loft("Shirt", Vector3(0, 0.74, 0), Vector3(0, 1.42, 0), Vector2(0.21, 0.14), Vector2(0.226, 0.142), chest, 8, 0.0, 0.0)
			for sx in [1.0, -1.0]:
				var ua := _bi(sk, "UpperArm_R" if sx > 0 else "UpperArm_L")
				var la := _bi(sk, "LowerArm_R" if sx > 0 else "LowerArm_L")
				b.loft("Shirt", Vector3(sx * 0.19, 1.395, 0), Vector3(sx * 0.30, 1.12, 0), Vector2(0.07, 0.068), Vector2(0.062, 0.06), ua, 7, 0.0, 0.0)
				b.loft("Shirt", Vector3(sx * 0.30, 1.12, 0), Vector3(sx * 0.395, 0.88, 0), Vector2(0.06, 0.058), Vector2(0.052, 0.052), la, 7, 0.0, 0.0)
		"Backpack":
			b.box("Accent", Vector3(0, 1.22, 0.17), Vector3(0.28, 0.36, 0.14), chest)
			b.box("Trim", Vector3(0, 1.12, 0.245), Vector3(0.2, 0.14, 0.03), chest)
		"Beard_1":
			b.sphere("Hair", hc + Vector3(0, -0.07, -0.05), Vector3(0.09, 0.07, 0.07), head, 7, 3, -90.0, 20.0)
		"Beard_2":
			b.sphere("Hair", hc + Vector3(0, -0.075, -0.045), Vector3(0.105, 0.09, 0.08), head, 7, 3, -90.0, 30.0)
			b.box("Hair", hc + Vector3(0, -0.033, -0.108), Vector3(0.07, 0.012, 0.02), head)
	if b.order.is_empty():
		b.box("Accent", Vector3(0, 1.0, 0), Vector3(0.01, 0.01, 0.01), hips)
	return b.commit()
