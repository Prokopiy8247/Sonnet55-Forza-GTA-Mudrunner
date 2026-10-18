extends Node
## Wildlife + underwater test (headless exec):
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/wildlife_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds"
## Prints TEST <name> PASS|FAIL <detail>.

var _fails := 0
var wl: WildlifeSystem = null
var player: Node3D = null


func _check(test_name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("TEST %s %s %s" % [test_name, "PASS" if cond else "FAIL", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _tp(p: Vector3) -> void:
	player.teleport_to(p, 0.0)


func run(_main: Node) -> Variant:
	await _frames(70)
	wl = Game.sys(&"wildlife") as WildlifeSystem
	player = Game.player
	_check("wildlife_boot", wl != null and player != null and wl.uw != null and wl.fish != null, "system + underwater + fish")
	if wl == null or player == null:
		return false
	var sk = Game.sys(&"skills")
	if sk != null:
		sk.announce = false
	var headless := DisplayServer.get_name() == "headless"      # the dummy renderer keeps no mesh arrays: merged meshes / trimesh colliders need a real renderer
	_check("wildlife_wreck", wl.uw.stats["wreck"] == 1 and (headless or wl.uw.wreck_body != null), "stats=%s headless=%s" % [str(wl.uw.stats), str(headless)])
	_check("wildlife_seabed_props", headless or (int(wl.uw.stats["coral"]) > 10 and int(wl.uw.stats["kelp"]) > 10 and int(wl.uw.stats["rock"]) > 3), "coral %d kelp %d rock %d urchin %d (headless=%s)" % [wl.uw.stats["coral"], wl.uw.stats["kelp"], wl.uw.stats["rock"], wl.uw.stats["urchin"], str(headless)])

	# ---- hills / park: spawn ring ---------------------------------------------------------------------------------------
	_tp(Vector3(-12.0, 0.1, -125.0))
	await _frames(240)
	var land := 0
	var species := {}
	var bad_pos := 0
	var under_ground := 0
	for a in wl.get_animals():
		if a.is_dead:
			continue
		if a.kind == &"land" or a.kind == &"bird":
			land += 1
			species[a.sp] = int(species.get(a.sp, 0)) + 1
		if a.kind == &"land":
			if WorldLayout.is_water(a.pos.x, a.pos.z):
				bad_pos += 1
			if a.pos.y < WorldLayout.terrain_height(a.pos.x, a.pos.z) - 0.4:
				under_ground += 1
	print("TEST INFO park animals=%d species=%s" % [land, str(species)])
	_check("wildlife_spawn_park", land >= 3, "%d animals around the park" % land)
	_check("wildlife_no_water_spawns", bad_pos == 0 and under_ground == 0, "water %d, underground %d" % [bad_pos, under_ground])
	_check("wildlife_cap", wl.active_count() <= WildlifeDefs.CAP_LAND, "%d <= %d" % [wl.active_count(), WildlifeDefs.CAP_LAND])

	# ---- flee from the player -----------------------------------------------------------------------------------------------
	wl.auto_population = false
	wl.despawn_all()
	var base := Vector3(-12.0, 0.0, -125.0)
	_tp(base + Vector3(0.0, 0.2, 40.0))
	await _frames(20)
	var deer := wl.spawn_group(&"deer", base, 3, {"buck": true})
	_check("wildlife_herd_spawn", deer.size() == 3 and (deer[0] as Animal).herd.size() == 3, "%d deer, buck %s" % [deer.size(), str((deer[0] as Animal).sp)])
	await _frames(90)
	var d0: Animal = deer[1]
	var start := d0.pos
	_tp(d0.pos + Vector3(0.0, 0.2, 7.0))
	player.set_input(Vector2(0, -1), true, false, false) if player.has_method("set_input") else null
	await _frames(70)
	var fleeing := 0
	for a in deer:
		if (a as Animal).state == WildlifeBrain.S_FLEE or (a as Animal).state == WildlifeBrain.S_ALERT:
			fleeing += 1
	_check("wildlife_deer_flee", fleeing >= 2, "%d/3 fleeing or alert after the player ran at them" % fleeing)
	await _frames(120)
	var moved := Util.dist_xz(d0.pos, start)
	_check("wildlife_deer_flee_distance", moved > 6.0, "moved %.1f m" % moved)
	if player.has_method("release_input"):
		player.release_input()
	# ---- gait sanity: legs swing while moving --------------------------------------------------------------------------------
	var leg := d0.parts.get("Leg_FL") as Node3D
	_check("wildlife_gait", leg != null and absf(leg.rotation.x) > 0.01 or d0.speed < 0.2, "Leg_FL rot %.2f speed %.1f" % [leg.rotation.x if leg != null else 0.0, d0.speed])

	# ---- gunshot scares animals that did not see the player --------------------------------------------------------------------
	wl.despawn_all()
	_tp(base + Vector3(60.0, 0.2, 0.0))
	await _frames(20)
	var rabbit := wl.spawn_animal(&"rabbit", base + Vector3(40.0, 0.0, 0.0), {})
	await _frames(40)
	Events.gunshot.emit(base + Vector3(44.0, 1.2, 0.0), 90.0, player)
	await _frames(40)
	_check("wildlife_gunshot_flee", rabbit.state == WildlifeBrain.S_FLEE or rabbit.state == WildlifeBrain.S_ALERT, "rabbit state %d" % rabbit.state)

	# ---- damage contract + death ---------------------------------------------------------------------------------------------------
	_check("wildlife_damageable", rabbit.is_in_group(GC.G_DAMAGEABLE) and rabbit.is_in_group(GC.G_ANIMAL) and rabbit.collision_layer == GC.L_ANIMAL, "groups + layer")
	rabbit.apply_damage(50.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "direction": Vector3.FORWARD, "impulse": 4.0})
	await _frames(90)
	_check("wildlife_death", rabbit.is_dead and absf(rabbit.roll_visual) > 0.5 and not rabbit.airborne, "dead, rolled %.2f rad" % rabbit.roll_visual)

	# ---- cheat toggle -------------------------------------------------------------------------------------------------------------------
	wl.auto_population = true
	_tp(base)
	await _frames(240)
	var before := wl.get_animals().size()
	Game.cheats["wildlife"] = false
	await _frames(10)
	var off_count := wl.get_animals().size()
	Game.cheats["wildlife"] = true
	await _frames(300)
	var on_count := wl.get_animals().size()
	_check("wildlife_cheat_toggle", before > 0 and off_count == 0 and on_count > 0, "on %d -> off %d -> on %d" % [before, off_count, on_count])

	# ---- performance: fill to the cap ------------------------------------------------------------------------------------------------------
	var filled := 0
	for sp in [&"deer", &"boar", &"rabbit", &"coyote", &"crow"]:
		var n := wl.spawn_group(sp, base + Vector3(randf_range(-25.0, 25.0), 0.0, randf_range(-20.0, 20.0)), 6, {})
		filled += n.size()
	await _frames(200)
	print("TEST INFO tick_us=%.0f animals=%d land=%d birds=%d fish=%d" % [wl.stats["tick_us"], wl.get_animals().size(), wl.stats["land"], wl.stats["birds"], wl.stats["fish"]])
	_check("wildlife_perf", float(wl.stats["tick_us"]) < 1500.0, "%.0f us / tick with %d animals" % [wl.stats["tick_us"], wl.get_animals().size()])
	wl.despawn_all()

	# ---- beach: seagulls -----------------------------------------------------------------------------------------------------------------------
	_tp(Vector3(0.0, 0.2, 150.0))
	wl.instant_fill = 3.0
	await _frames(300)
	var gulls := wl.count_species(&"seagull")
	_check("wildlife_seagulls", gulls >= 2, "%d seagulls near the beach pier" % gulls)

	# ---- fish --------------------------------------------------------------------------------------------------------------------------------------
	_tp(Vector3(-146.0, 0.2, 232.0))
	wl.fish.clear()
	wl.instant_fill = 2.0
	await _frames(240)
	_check("wildlife_fish", wl.fish.school_count() >= 1 and wl.fish.visible_fish >= 5 and wl.fish.total_fish <= WildlifeDefs.CAP_FISH, "%d schools, %d visible fish (cap %d)" % [wl.fish.school_count(), wl.fish.visible_fish, WildlifeDefs.CAP_FISH])

	# ---- shark: attack conditions ---------------------------------------------------------------------------------------------------------------------
	_check("wildlife_shark_conditions", MarineBrain.attackable_pos(Vector3(-22.0, -2.0, 300.0)) and not MarineBrain.attackable_pos(Vector3(0.0, -2.0, 185.0)) and not MarineBrain.attackable_pos(Vector3(-146.0, -2.0, 232.0)) and not MarineBrain.attackable_pos(Vector3(0.0, -2.0, 210.0)), "deep yes / shallows, marina pier and beach-pier waters no")
	wl.despawn_all()
	wl.auto_population = false
	_tp(Vector3(-22.0, -2.2, 305.0))
	await _frames(60)
	var shark := wl.spawn_shark(Vector3(-22.0, -2.0, 335.0))
	_check("wildlife_shark_spawn", shark != null, "shark spawned")
	var hp0 := float(player.health)
	var stalked := false
	var bitten := false
	for i in 1500:
		await get_tree().physics_frame
		if shark.state == WildlifeBrain.S_STALK or shark.state == WildlifeBrain.S_ATTACK:
			stalked = true
		if float(player.health) < hp0 - 5.0:
			bitten = true
			break
		if i % 200 == 0 and not is_instance_valid(shark):
			break
	print("TEST INFO player swimming=%s y=%.1f shark state=%d dist=%.1f health %.0f" % [str(player.get("is_swimming")), player.global_position.y, shark.state, shark.pos.distance_to(player.global_position), float(player.health)])
	_check("wildlife_shark_stalk", stalked, "shark noticed the swimmer")
	_check("wildlife_shark_bite", bitten, "swimmer health %.0f -> %.0f" % [hp0, float(player.health)])
	# shallow swimmer is safe
	player.health = 100.0
	_tp(Vector3(0.0, -1.3, 186.0))
	shark.place(Vector3(0.0, -2.0, 236.0), 0.0)
	shark.home = shark.pos
	await _frames(600)
	_check("wildlife_shark_shallows_safe", float(player.health) >= 99.0, "player health %.0f after 10 s swimming in the shallows with a shark 50 m away" % float(player.health))
	wl.despawn_all()
	print("TEST SUMMARY fails=%d fallbacks=%s" % [_fails, str(AnimalModel.fallbacks)])
	return _fails == 0
