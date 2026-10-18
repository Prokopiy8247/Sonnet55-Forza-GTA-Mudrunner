class_name WeaponTestKit
extends RefCounted
## Shared helpers for the weapon / combat tests: a private arena far away from the real world, target dummies and a shooter.

const ORIGIN := Vector3(4000.0, 0.0, 4000.0)

static var passed := 0
static var failed := 0


class Dummy:
	extends CharacterBase
	var knocked := 0
	var knock_impulse := Vector3.ZERO
	var react_hits := 0

	func knock_down(impulse: Vector3, _duration: float) -> void:
		knocked += 1
		knock_impulse = impulse

	func _on_damaged(_amount: float, _info: Dictionary) -> void:
		react_hits += 1


static func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


static func approx(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


static func make_arena(parent: Node) -> Node3D:
	var arena := Node3D.new()
	arena.name = "WeaponTestArena"
	parent.add_child(arena)
	arena.global_position = ORIGIN
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = GC.L_WORLD
	floor_body.collision_mask = 0
	floor_body.set_meta(&"surface", &"concrete")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	floor_body.add_child(cs)
	arena.add_child(floor_body)
	return arena


static func make_wall(arena: Node3D, local_pos: Vector3, size: Vector3, surface: StringName) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.name = "Wall_" + String(surface)
	w.collision_layer = GC.L_WORLD
	w.collision_mask = 0
	w.set_meta(&"surface", surface)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	arena.add_child(w)
	w.position = local_pos
	return w


static func make_dummy(arena: Node3D, local_pos: Vector3, faction: StringName = GC.F_GANG) -> Dummy:
	var d := Dummy.new()
	d.faction = faction
	d.collision_layer = GC.L_NPC
	d.collision_mask = GC.L_WORLD
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	d.add_child(cs)
	arena.add_child(d)
	d.position = local_pos
	return d


## Shooter dummy (not in the player group) with a WeaponController. Faces -Z.
static func make_shooter(arena: Node3D, local_pos: Vector3 = Vector3.ZERO) -> Dummy:
	var s := make_dummy(arena, local_pos, GC.F_PLAYER)
	s.name = "TestShooter"
	var wc := WeaponController.new()
	wc.name = "Weapons"
	s.add_child(wc)
	wc.setup(s)
	s.set_meta(&"_acc_override", 1.0)
	return s


static func frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame


static func aim(wc: WeaponController, shooter: CharacterBase, dir: Vector3) -> void:
	wc.set_aim_ray(shooter.get_eye_position(), dir.normalized())


static func summary() -> void:
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
