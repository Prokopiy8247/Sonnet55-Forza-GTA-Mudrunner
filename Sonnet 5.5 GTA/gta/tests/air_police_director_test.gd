extends Node
## The REAL police director (PoliceManager + WantedSystem) brings a PoliceHeliAI at wanted level >= 3, orders it, and takes it away again.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/air_police_director_test.gd -Seconds 240 -GameArgs "--no-traffic --no-peds --time=21.5"

var T := VehicleTestUtil


func run(main: Node) -> String:
	var tree := get_tree()
	var wanted = Game.sys(&"wanted")
	var police = Game.sys(&"police")
	var player = Game.player
	T.report("director_present", wanted != null and police != null and player != null, "wanted=%s police=%s" % [wanted, police])
	if wanted == null or police == null or player == null:
		return "missing systems"
	await T.frames(tree, 120)
	Game.cheats["invulnerable"] = true
	player.teleport_to(WorldLayout.location_pos(&"player_spawn"))
	await T.frames(tree, 60)
	wanted.set_level(4)
	var heli: VehicleBase = null
	for i in 60 * 90:
		await tree.physics_frame
		if PoliceHeliAI.active_count() > 0:
			for n in tree.get_nodes_in_group(GC.G_POLICE):
				if n is HeliVehicle and PoliceHeliAI.of(n) != null:
					heli = n
			if heli != null:
				break
	T.report("director_spawns_police_heli_at_level4", heli != null, "active=%d" % PoliceHeliAI.active_count())
	if heli == null:
		wanted.clear()
		return "no heli"
	var ai := PoliceHeliAI.of(heli)
	await T.frames(tree, 60 * 20)
	T.report("director_orders_pursue", ai.mode == &"pursue" and ai.get_target() == player, "mode=%s target=%s" % [ai.mode, ai.get_target()])
	var d := Vector2(heli.global_position.x - player.global_position.x, heli.global_position.z - player.global_position.z).length()
	T.report("heli_arrives_over_the_player", d < 140.0 and heli.global_position.y > 25.0, "horizontal distance %.0f m, altitude %.0f m" % [d, heli.global_position.y])
	await T.frames(tree, 60 * 25)
	T.report("heli_sights_the_player", int(ai.stats["sightings"]) > 0 and ai.player_lit, "sightings=%d lit=%s" % [ai.stats["sightings"], ai.player_lit])
	T.report("heli_door_gunner_at_level4", int(ai.stats["rounds"]) > 0, "rounds=%d bursts=%d (wanted level %d)" % [ai.stats["rounds"], ai.stats["bursts"], Game.wanted_level])
	T.report("heli_stays_alive_and_flying", not heli.is_destroyed and heli.rotor_rpm > 0.9, "rpm=%.2f destroyed=%s" % [heli.rotor_rpm, heli.is_destroyed])
	var st: Dictionary = police.stats if police.get("stats") != null else {}
	T.report("director_counts_the_heli", int(st.get("spawned_helis", 0)) >= 1, "stats.spawned_helis=%s" % st.get("spawned_helis", "n/a"))
	# lose the cops: the helicopter must stop shooting and eventually go away
	wanted.clear()
	var gone := false
	for i in 60 * 120:
		await tree.physics_frame
		if not is_instance_valid(heli) or PoliceHeliAI.active_count() == 0:
			gone = true
			break
	T.report("heli_leaves_after_wanted_clear", gone, "gone=%s mode=%s" % [gone, ai.mode if is_instance_valid(ai) else "freed"])
	Game.cheats["invulnerable"] = false
	return "ok"
