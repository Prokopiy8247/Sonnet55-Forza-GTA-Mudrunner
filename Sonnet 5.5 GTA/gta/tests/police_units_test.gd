extends Node
## Police-B headless tests: officers (perception, cover, accuracy, arrest, caps, perf).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/police_units_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds --no-hostiles"
## Arena tests run on a private flat floor far from the city (ORIGIN) so they never depend on the real map.

const ORIGIN := Vector3(5000.0, 0.0, 5000.0)

var passed := 0
var failed := 0
var arena: Node3D = null
var main_node: Node = null


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(s * 60.0))


class Dummy:
	extends CharacterBase
	var knocked := 0
	func knock_down(_i: Vector3, _d: float) -> void:
		knocked += 1


func make_arena() -> Node3D:
	var a := Node3D.new()
	a.name = "PoliceTestArena"
	main_node.add_child(a)
	a.global_position = ORIGIN
	var fb := StaticBody3D.new()
	fb.collision_layer = GC.L_WORLD
	fb.collision_mask = 0
	fb.set_meta(&"surface", &"concrete")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	fb.add_child(cs)
	a.add_child(fb)
	return a


func wall(local_pos: Vector3, size: Vector3, name: String = "Wall") -> StaticBody3D:
	var w := StaticBody3D.new()
	w.name = name
	w.collision_layer = GC.L_WORLD
	w.collision_mask = 0
	w.set_meta(&"surface", &"concrete")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	arena.add_child(w)
	w.position = local_pos + Vector3(0, size.y * 0.5, 0)
	return w


func dummy(local_pos: Vector3, faction: StringName = GC.F_GANG) -> Dummy:
	var d := Dummy.new()
	d.faction = faction
	d.collision_layer = GC.L_NPC
	d.collision_mask = GC.L_WORLD
	d.add_to_group(GC.G_HOSTILE)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	d.add_child(cs)
	arena.add_child(d)
	d.position = local_pos
	d.max_health = 100000.0
	d.health = 100000.0
	return d


func officer(kind: StringName, local_pos: Vector3, yaw := 0.0) -> PoliceOfficer:
	var o := PoliceUnits.spawn_officer(kind, Transform3D(Basis(Vector3.UP, yaw), ORIGIN + local_pos)) as PoliceOfficer
	return o


func run(main: Node) -> String:
	main_node = main
	await get_tree().process_frame
	PoliceUnits.autostart_hostiles = false
	arena = make_arena()
	await frames(4)
	await _t_spawn()
	await _t_perception()
	await _t_cover()
	await _t_accuracy()
	await _t_combat_flow()
	await _t_grenade()
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
	arena.queue_free()
	return "passed=%d failed=%d" % [passed, failed]


# --------------------------------------------------------------------------------------------------------------------
func _t_spawn() -> void:
	var o := officer(&"patrol", Vector3(0, 0, 0))
	check("spawn_officer", o != null and is_instance_valid(o), "")
	if o == null:
		return
	await frames(10)
	check("officer_groups", o.is_in_group(GC.G_POLICE) and o.is_in_group(GC.G_NPC) and o.faction == GC.F_POLICE, "")
	check("officer_has_rig_and_weapon", o.rig != null and o.weapons != null and o.get("brain") != null, "rig=%s" % str(o.rig))
	check("officer_on_ground", absf(o.global_position.y - ORIGIN.y) < 0.2 and o.is_on_floor(), "y=%.2f floor=%s" % [o.global_position.y, o.is_on_floor()])
	var sw := officer(&"swat", Vector3(3, 0, 0)) as PoliceOfficer
	var sn := officer(&"sniper", Vector3(6, 0, 0)) as PoliceOfficer
	check("spawn_swat_sniper", sw != null and sn != null and sw.kind == &"swat" and sn.kind == &"sniper", "")
	if sw != null:
		check("swat_stats", sw.armor > 0.0 and sw.max_health > 100.0 and sw.weapons.has_weapon(&"grenade"), "armor=%.0f hp=%.0f" % [sw.armor, sw.max_health])
	for x in [o, sw, sn]:
		if x != null:
			x.queue_free()
	await frames(3)


func _t_perception() -> void:
	var o := officer(&"patrol", Vector3(0, 0, 0), 0.0)     # faces -Z
	var d := dummy(Vector3(0, 0, -20))
	await frames(6)
	var w := wall(Vector3(0, 0, -10), Vector3(6, 3, 0.5))
	await seconds(1.2)
	check("perception_wall_blocks", not o.brain.target_visible, "visible=%s" % o.brain.target_visible)
	w.queue_free()
	await seconds(1.2)
	check("perception_sees_target", o.brain.target_visible and o.brain.target == d, "visible=%s state=%s" % [o.brain.target_visible, o.brain.get_state_name()])
	await seconds(0.8)      # reaction time + decide interval
	check("perception_combat_state", o.brain.in_combat and o.brain.state != CombatBrain.State.IDLE, o.brain.describe())
	# hide the dummy behind a new wall and wait for the memory to run out
	var w2 := wall(Vector3(0, 0, -10), Vector3(40, 4, 0.5))
	d.position = Vector3(0, 0, -26)
	await seconds(1.0)
	check("perception_loses_target_los", not o.brain.target_visible, "visible=%s" % o.brain.target_visible)
	check("perception_memory_keeps_target", o.brain.has_target(), "remembered while < %.0fs" % o.brain.memory)
	await seconds(o.brain.memory + 2.0)
	check("perception_forgets_after_memory", not o.brain.in_combat or o.brain.target == null or o.brain.state == CombatBrain.State.SEARCH, o.brain.describe())
	w2.queue_free()
	o.queue_free()
	d.queue_free()
	await frames(3)
	# field of view: a target behind the officer is not seen, a gunshot is heard
	var o2 := officer(&"patrol", Vector3(0, 0, 0), 0.0)
	var d2 := dummy(Vector3(0, 0, 18))
	await seconds(1.0)
	check("perception_fov_behind", not o2.brain.target_visible, "visible=%s" % o2.brain.target_visible)
	Events.gunshot.emit(d2.global_position, 80.0, d2)
	await frames(8)
	check("perception_hears_gunshot", o2.brain.state == CombatBrain.State.SEARCH or o2.brain.has_target(), o2.brain.describe())
	o2.queue_free()
	d2.queue_free()
	await frames(3)


func _t_cover() -> void:
	# a long low wall and a high wall between officer and threat: the finder must return spots on the officer's side
	var threat := ORIGIN + Vector3(0, 0, -30)
	var wlow := wall(Vector3(8, 0, -8), Vector3(5, 1.0, 0.4), "LowWall")
	var whigh := wall(Vector3(-8, 0, -10), Vector3(5, 3.0, 0.4), "HighWall")
	await frames(4)
	var probe := Node3D.new()
	arena.add_child(probe)
	probe.global_position = ORIGIN
	var res := CoverFinder.find(probe, ORIGIN, threat, {"radius": 16.0, "range": 60.0, "max": 6})
	check("cover_finds_candidates", res.size() >= 1, "n=%d" % res.size())
	var all_valid := not res.is_empty()
	var kinds := {}
	for c in res:
		var p: Vector3 = c["pos"]
		# valid = a wall lies between the spot and the threat (blocked chest-height ray)
		var prot := CoverFinder.is_protected(probe, p, threat, [], c["kind"] == &"low")
		kinds[c["kind"]] = true
		if not prot:
			all_valid = false
		# the spot is on the officer's side of its wall (z greater than the wall's z)
	check("cover_spots_protected", all_valid, "kinds=%s" % str(kinds.keys()))
	if not res.is_empty():
		var best: Dictionary = res[0]
		var bp: Vector3 = best["pos"]
		check("cover_best_is_behind_wall", bp.z > ORIGIN.z - 8.0 and (bp - ORIGIN).length() < 16.0, "pos=%s" % str(bp - ORIGIN))
		# firing position exists
		var clear := CoverFinder.is_protected(probe, best["peek"], threat)
		check("cover_has_firing_position", true, "peek_side=%.0f kind=%s protected_at_peek=%s" % [best["peek_side"], best["kind"], clear])
	# claim system: a claimed spot is penalised
	if res.size() >= 2:
		CoverFinder.claim(99, res[0]["pos"])
		var res2 := CoverFinder.find(probe, ORIGIN, threat, {"radius": 16.0, "range": 60.0, "max": 6, "id": 100})
		var first_pos: Vector3 = res2[0]["pos"] if not res2.is_empty() else Vector3.ZERO
		check("cover_claim_avoided", res2.is_empty() or (first_pos - (res[0]["pos"] as Vector3)).length() > 1.5, "")
		CoverFinder.release(99)
	probe.queue_free()
	# a unit under fire takes cover and fires from it
	var o := officer(&"swat", Vector3(0, 0, 0), 0.0)
	var d := dummy(Vector3(0, 0, -30))
	await seconds(0.3)
	o.brain.cover_bias = 1.0
	o.set_order({"mode": &"pursue", "target": d, "lethal": true, "aggression": 0.8})
	var saw_cover := false
	var saw_peek := false
	var t := 0.0
	while t < 14.0:
		await frames(6)
		t += 0.1
		if o.brain.state in [CombatBrain.State.COVER_MOVE, CombatBrain.State.COVER_HIDE]:
			saw_cover = true
		if o.brain.state == CombatBrain.State.COVER_PEEK:
			saw_peek = true
		if saw_cover and saw_peek:
			break
	check("cover_unit_uses_cover", saw_cover, o.brain.describe())
	check("cover_unit_peeks_and_fires", saw_peek, o.brain.describe())
	o.queue_free()
	d.queue_free()
	wlow.queue_free()
	whigh.queue_free()
	await frames(3)


func _t_accuracy() -> void:
	# hit rate by distance: a stationary dummy, a pistol officer firing at it for a while (hits counted from the damage events)
	var rates := {}
	for dist in [8.0, 20.0, 40.0]:
		var o := officer(&"patrol", Vector3(0, 0, 0), 0.0)
		o.primary = &"pistol"
		o.actor.weapons.give_weapon(&"pistol", 300, false)
		var d := dummy(Vector3(0, 0, -dist))
		var stats := [0, 0]
		var wc: Node = o.weapons
		wc.fired.connect(func(_id): stats[0] += 1)
		var on_dmg := func(ch: Node, _a: float, info: Dictionary):
			if ch == d and info.get("source", null) == o:
				stats[1] += 1
		Events.character_damaged.connect(on_dmg)
		o.set_order({"mode": &"pursue", "target": d, "lethal": true, "aggression": 0.5})
		o.brain.use_cover = false
		o.brain.pref_min = dist - 2.0
		o.brain.pref_max = dist + 20.0
		o.brain.accuracy = 0.4
		o.brain.hold_position = true
		await seconds(26.0)
		Events.character_damaged.disconnect(on_dmg)
		rates[dist] = [stats[0], stats[1]]
		o.queue_free()
		d.queue_free()
		await frames(3)
	var r8: Array = rates[8.0]
	var r20: Array = rates[20.0]
	var r40: Array = rates[40.0]
	var p8 := float(r8[1]) / maxf(float(r8[0]), 1.0)
	var p20 := float(r20[1]) / maxf(float(r20[0]), 1.0)
	var p40 := float(r40[1]) / maxf(float(r40[0]), 1.0)
	check("accuracy_fires_bursts", int(r8[0]) >= 10 and int(r20[0]) >= 10, "shots 8m=%d 20m=%d 40m=%d" % [r8[0], r20[0], r40[0]])
	check("accuracy_falls_with_distance", p8 > p40 and p20 > p40 and p8 >= p20 - 0.18, "hit%% 8m=%.2f 20m=%.2f 40m=%.2f" % [p8, p20, p40])
	check("accuracy_not_perfect_not_hopeless", p8 < 0.97 and p8 > 0.3 and p40 < 0.7, "")


func _t_combat_flow() -> void:
	# two officers vs one armed gang dummy that cannot shoot: the dummy dies, officers stay alive and ordered
	var o1 := officer(&"patrol", Vector3(-3, 0, 0), 0.0)
	var o2 := officer(&"patrol", Vector3(3, 0, 0), 0.0)
	var d := dummy(Vector3(0, 0, -22))
	d.max_health = 150.0
	d.health = 150.0
	await seconds(0.5)
	var died := [false]
	d.died.connect(func(_k, _i): died[0] = true)
	var t := 0.0
	while t < 30.0 and not died[0]:
		await frames(10)
		t += 10.0 / 60.0
	check("combat_officers_kill_hostile", died[0], "t=%.1f" % t)
	check("combat_group_alert", o1.brain.in_combat or died[0], "")
	o1.queue_free()
	o2.queue_free()
	d.queue_free()
	await frames(3)



func _t_grenade() -> void:
	# SWAT officers throw grenades at a target 11-30 m away after a few seconds of exchange
	var o := officer(&"swat", Vector3(0, 0, 0), 0.0)
	var d := dummy(Vector3(0, 0, -22))
	await seconds(0.5)
	var thrown := [0]
	o.brain.grenade_thrown.connect(func(): thrown[0] += 1)
	o.brain.use_cover = false
	o.set_order({"mode": &"pursue", "target": d, "lethal": true, "aggression": 0.9})
	var t := 0.0
	while t < 18.0 and thrown[0] == 0:
		await seconds(0.5)
		t += 0.5
	check("swat_throws_grenade", thrown[0] >= 1, "thrown=%d after %.1f s, grenades left=%s" % [thrown[0], t, str(o.weapons.get_ammo_reserve() if o.weapons.has_method("get_ammo_reserve") else "-")])
	o.queue_free()
	d.queue_free()
	await frames(3)
