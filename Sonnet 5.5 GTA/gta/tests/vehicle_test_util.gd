class_name VehicleTestUtil
extends RefCounted
## Shared helpers of the vehicle tests (flat test floor, spawning, measuring, TEST lines).

static var passed := 0
static var failed := 0
## All tests run in a private studio far from the city so the real world's colliders never interfere.
const ORIGIN := Vector3(3000.0, 0.0, 3000.0)


static func o(rel: Vector3) -> Vector3:
	return ORIGIN + rel


static func report(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


static func make_floor(parent: Node, half: float = 5000.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "TestFloor"
	sb.collision_layer = GC.L_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(half * 2.0, 1.0, half * 2.0)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_position = ORIGIN
	return sb


static func make_box(parent: Node, pos: Vector3, size: Vector3, rot_deg := Vector3.ZERO, tag := "TestBox") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = tag
	sb.collision_layer = GC.L_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_transform = Transform3D(Basis.from_euler(rot_deg * PI / 180.0), ORIGIN + pos)
	return sb


static func frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame


static func spawn(id: StringName, pos: Vector3, yaw_deg := 0.0, opts := {}) -> VehicleBase:
	var o := {"ai": true, "engine_on": true, "snap_ground": true}
	o.merge(opts, true)
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), ORIGIN + pos)
	return VehicleFactory.spawn(id, xf, o)


static func kmh(v: VehicleBase) -> float:
	return v.get_speed_kmh()


static func is_sane(v: VehicleBase) -> bool:
	var p := v.global_position
	return is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and p.y > -5.0 and p.y < 50.0


static func remove_all(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group(GC.G_VEHICLE):
		if is_instance_valid(n):
			VehicleFactory.despawn(n)
	var sys = Game.sys(&"vehicles")
	if sys != null:
		sys.clear_pool()
