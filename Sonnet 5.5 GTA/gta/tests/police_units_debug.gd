extends Node
## Scratch debug runner for Police-B: why does the brain stay idle with a visible target? (prints TEST dbg lines)
const ORIGIN := Vector3(5000.0, 0.0, 5000.0)

class Dummy:
	extends CharacterBase

func run(main: Node) -> String:
	await get_tree().process_frame
	PoliceUnits.autostart_hostiles = false
	var a := Node3D.new()
	main.add_child(a)
	a.global_position = ORIGIN
	var fb := StaticBody3D.new()
	fb.collision_layer = GC.L_WORLD
	fb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	fb.add_child(cs)
	a.add_child(fb)
	await get_tree().physics_frame
	var o := PoliceUnits.spawn_officer(&"patrol", Transform3D(Basis(), ORIGIN)) as PoliceOfficer
	var d := Dummy.new()
	d.faction = GC.F_GANG
	d.collision_layer = GC.L_NPC
	d.add_to_group(GC.G_HOSTILE)
	var cs2 := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs2.shape = cap
	cs2.position = Vector3(0, 0.9, 0)
	d.add_child(cs2)
	a.add_child(d)
	d.position = Vector3(0, 0, -20)
	d.max_health = 100000.0
	d.health = 100000.0
	for s in 30:
		await get_tree().create_timer(0.2).timeout
		print("TEST dbg t=%.1f %s combat=%s alert_until=%.1f now=%.1f busy=%.1f mode=%s hold=%s since_cover=%.1f cover_q=%d" % [s * 0.2, o.brain.describe(), o.brain.combat_enabled, o.brain._alert_until, o.brain._now, o.brain._busy_until, o.mode, o.brain.hold_position, o.brain._since_cover, CombatBrain.cover_queries])
	return "done"
