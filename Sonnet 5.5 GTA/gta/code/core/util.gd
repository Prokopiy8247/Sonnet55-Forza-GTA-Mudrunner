class_name Util
extends RefCounted
## Small static helpers used across modules. Additive changes only.


# ---- Math --------------------------------------------------------------------------------
## Frame-rate independent exponential smoothing.
static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * dt))


static func damp_v3(current: Vector3, target: Vector3, rate: float, dt: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-rate * dt))


static func angle_diff(from_rad: float, to_rad: float) -> float:
	return wrapf(to_rad - from_rad, -PI, PI)


## Yaw 0 faces -Z (Godot forward). Positive yaw turns left (counter-clockwise from above).
static func yaw_to_dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func dir_to_yaw(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func dist_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func rand_in_ring(center: Vector3, rmin: float, rmax: float, rng: RandomNumberGenerator = null) -> Vector3:
	var r_ := rng if rng != null else Game.rng
	var a := r_.randf() * TAU
	var d := sqrt(lerpf(rmin * rmin, rmax * rmax, r_.randf()))
	return center + Vector3(cos(a) * d, 0.0, sin(a) * d)


static func format_money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if n < 0 else "$") + out


static func format_clock(hour: float) -> String:
	var h := int(floor(hour)) % 24
	var m := int((hour - floor(hour)) * 60.0)
	return "%02d:%02d" % [h, m]


# ---- Scene-tree helpers ----------------------------------------------------------------------
static func find_all(root: Node, predicate: Callable) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if predicate.call(n):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


static func find_first_of_class(root: Node, cls: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls):
			return n
		for c in n.get_children():
			stack.append(c)
	return null


## Sets layer/mask on every CollisionObject3D under (and including) root.
static func set_collision(root: Node, layer: int, mask: int) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject3D:
			n.collision_layer = layer
			n.collision_mask = mask
		for c in n.get_children():
			stack.append(c)


## Combined AABB of all MeshInstance3D under root, expressed in root's local space.
static func local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for mi in ModelLib.meshes(root):
		var xf: Transform3D = inv * mi.global_transform if root.is_inside_tree() else _rel_transform(root, mi)
		var bb := xf * mi.get_aabb()
		if first:
			result = bb
			first = false
		else:
			result = result.merge(bb)
	return result


static func _rel_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Replace every surface material named `mat_name` (glTF material name) below root via per-surface
## overrides, so shared mesh resources are never mutated. Returns the number of surfaces replaced.
static func replace_material(root: Node, mat_name: String, replacement: Material) -> int:
	var count := 0
	for mi in ModelLib.meshes(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m != null and m.resource_name == mat_name:
				mi.set_surface_override_material(i, replacement)
				count += 1
	return count


## Returns the first material named `mat_name` found below root (or null).
static func find_material(root: Node, mat_name: String) -> Material:
	for mi in ModelLib.meshes(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m != null and m.resource_name == mat_name:
				return m
	return null


# ---- Skeleton helpers ----------------------------------------------------------------------------
## Rotates a bone by `delta` expressed in MODEL space on top of its rest orientation, independent of the
## bone roll authored in Blender. Call parents before children each frame.
static func bone_set_model_delta(skel: Skeleton3D, bone: int, delta: Basis) -> void:
	var parent := skel.get_bone_parent(bone)
	var parent_global := Transform3D.IDENTITY if parent < 0 else skel.get_bone_global_pose(parent)
	var rest_global := skel.get_bone_global_rest(bone)
	var target_basis := delta * rest_global.basis
	var local_basis := parent_global.basis.inverse() * target_basis
	skel.set_bone_pose_rotation(bone, local_basis.orthonormalized().get_rotation_quaternion())


# ---- Physics query helpers --------------------------------------------------------------------------
static func raycast(node: Node3D, from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var space := node.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var rids: Array[RID] = []
	for e in exclude:
		if e is CollisionObject3D:
			rids.append(e.get_rid())
	q.exclude = rids
	return space.intersect_ray(q)


static func has_line_of_sight(node: Node3D, from: Vector3, to: Vector3, mask: int = GC.M_LOS, exclude: Array = []) -> bool:
	return raycast(node, from, to, mask, exclude).is_empty()
