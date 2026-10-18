extends Node
## Police helicopter (PoliceHeliAI + AirAutopilot + AirSearchlight): spawn contract, patrol orbit, pursuit with lag at 40-60 m, search
## circles, searchlight cone on the target, sightings -> WantedSystem, door-gunner bursts at level >= 4, orders, cap, despawn.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/air_police_test.gd -Seconds 240 -GameArgs "--no-vehicles --no-traffic --no-peds --time=22"

var T := VehicleTestUtil
var tree: SceneTree
var player: Node


func run(main: Node) -> String:
	tree = get_tree()
	player = Game.player
	Game.wetness = 0.0
	await T.frames(tree, 30)
	await _t_contract()
	await _t_modes()
	await _t_orders()
	await _t_gunner()
	await _t_autopilot_plane()
	print("TEST SUMMARY passed=%d failed=%d" % [T.passed, T.failed])
	return "passed=%d failed=%d" % [T.passed, T.failed]


func _dummy_target(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "ChaseDummy"
	get_tree().root.add_child(n)
	n.global_position = pos
	return n


func _t_contract() -> void:
	var v := PoliceHeliAI.spawn(Vector3(120, 90, 160))
	T.report("police_heli_spawn_returns_vehicle", v != null and v is HeliVehicle and v.def_id == &"heli_police", "class=%s" % (v.get_class() if v != null else "null"))
	if v == null:
		return
	var ai := PoliceHeliAI.of(v)
	T.report("police_heli_has_ai", ai != null and v.ai == ai and v.get_meta(&"police_ai") == ai, "ai=%s" % ai)
	T.report("police_heli_faction_group", v.faction == GC.F_POLICE and v.is_in_group(GC.G_POLICE) and v.siren_on, "faction=%s siren=%s" % [v.faction, v.siren_on])
	T.report("police_heli_born_flying", v.rotor_rpm > 0.99 and v.engine_on, "rpm=%.2f engine=%s y=%.0f" % [v.rotor_rpm, v.engine_on, v.global_position.y])
	await T.frames(tree, 60 * 3)
	T.report("police_heli_holds_altitude_at_spawn", v.global_position.y > 60.0 and not v.is_destroyed, "y=%.1f" % v.global_position.y)
	T.report("police_heli_has_searchlight", ai.searchlight != null, "searchlight=%s" % ai.searchlight)
	# cap
	var v2 := PoliceHeliAI.spawn(Vector3(-120, 90, 160))
	var v3 := PoliceHeliAI.spawn(Vector3(0, 90, -160))
	T.report("police_heli_cap_two", v2 != null and v3 == null and PoliceHeliAI.active_count() == 2, "active=%d third=%s" % [PoliceHeliAI.active_count(), v3])
	VehicleFactory.despawn(v2)
	await T.frames(tree, 3)
	VehicleFactory.despawn(v)
	await T.frames(tree, 5)
	T.report("police_heli_despawn_clears_active", PoliceHeliAI.active_count() == 0, "active=%d" % PoliceHeliAI.active_count())
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_modes() -> void:
	Game.time_of_day = 22.0
	var v := PoliceHeliAI.spawn(Vector3(150, 100, 120)) as HeliVehicle
	var ai := PoliceHeliAI.of(v)
	# ---- patrol: orbits the city at 80-120 m -----------------------------------------------------------------------------------
	ai.set_mode(&"patrol")
	var tmin := 999.0
	var tmax := 0.0
	var path := 0.0
	var prev := v.global_position
	var rmin := 999.0
	var rmax := 0.0
	for i in 60 * 45:
		await tree.physics_frame
		if i > 60 * 12:
			tmin = minf(tmin, v.global_position.y)
			tmax = maxf(tmax, v.global_position.y)
			var r := Vector2(v.global_position.x - ai.patrol_center.x, v.global_position.z - ai.patrol_center.z).length()
			rmin = minf(rmin, r)
			rmax = maxf(rmax, r)
		path += v.global_position.distance_to(prev)
		prev = v.global_position
	T.report("police_heli_patrol_altitude", tmin > 70.0 and tmax < 135.0, "altitude %.0f..%.0f m" % [tmin, tmax])
	T.report("police_heli_patrol_orbit", rmin > 90.0 and rmax < 230.0 and path > 400.0, "radius %.0f..%.0f m around the centre, flew %.0f m" % [rmin, rmax, path])
	T.report("police_heli_patrol_light_at_night", ai.searchlight != null and ai.searchlight.enabled, "light on=%s" % (ai.searchlight.enabled if ai.searchlight != null else "n/a"))
	# ---- pursue a moving target: follows at 40-60 m above with smooth lag ---------------------------------------------------------------
	var park := Vector3(-30, 0, -140)                 # the open park in the north: no towers to push the helicopter up, a clear ground for the beam
	var tgt := _dummy_target(Vector3(0, 0, 0))
	tgt.global_position = park + Vector3(40, 0.5, 0)
	ai.set_target(tgt)
	ai.set_mode(&"pursue")
	var tpos := tgt.global_position
	var lag_max := 0.0
	var dh := 0.0
	var dy := 0.0
	var samples := 0
	var covers_frames := 0
	for i in 60 * 50:
		var a := float(i) / 60.0
		tpos = park + Vector3(cos(a * 0.3) * 45.0, 0.0, sin(a * 0.3) * 45.0)
		tpos.y = WorldLayout.terrain_height(tpos.x, tpos.z) + 0.5
		tgt.global_position = tpos
		await tree.physics_frame
		if i > 60 * 22:
			var hp := v.global_position
			dh = Vector2(hp.x - tpos.x, hp.z - tpos.z).length()
			dy = hp.y - tpos.y
			lag_max = maxf(lag_max, dh)
			samples += 1
			if ai.searchlight != null and ai.searchlight.covers(tpos + Vector3(0, 0.9, 0), 3.0):
				covers_frames += 1
	T.report("police_heli_pursue_keeps_up", lag_max < 80.0 and samples > 0, "max horizontal offset %.0f m while the target circles at ~%.0f m/s" % [lag_max, 45.0 * 0.3])
	T.report("police_heli_pursue_altitude_band", dy > 38.0 and dy < 62.0, "%.0f m above the target" % dy)
	T.report("police_heli_beam_on_target", covers_frames > samples * 0.6, "beam covers the target in %d%% of frames" % int(100.0 * covers_frames / maxf(samples, 1)))
	var sl := ai.searchlight
	T.report("police_heli_beam_hits_target_area", sl != null and sl.hit_pos.distance_to(tpos) < 25.0, "beam end %.1f m from the target (dist %.0f)" % [sl.hit_pos.distance_to(tpos) if sl != null else -1.0, sl.hit_dist if sl != null else -1.0])
	# ---- search: slow circles over the search area ----------------------------------------------------------------------------------
	ai.set_order({"mode": &"search", "target": null, "pos": Vector3(-60, 0, 40), "radius": 100.0, "aggression": 0.5, "lethal": false})
	var rs_min := 999.0
	var rs_max := 0.0
	var alts := []
	var sweep_moved := 0.0
	var last_aim := sl.hit_pos if sl != null else Vector3.ZERO
	for i in 60 * 40:
		await tree.physics_frame
		if i > 60 * 20:
			var r := Vector2(v.global_position.x + 60.0, v.global_position.z - 40.0).length()
			rs_min = minf(rs_min, r)
			rs_max = maxf(rs_max, r)
			alts.append(v.global_position.y)
			if sl != null:
				sweep_moved += sl.hit_pos.distance_to(last_aim)
				last_aim = sl.hit_pos
	T.report("police_heli_search_circles_area", rs_min > 20.0 and rs_max < 130.0, "orbit radius %.0f..%.0f m around the search centre" % [rs_min, rs_max])
	T.report("police_heli_search_beam_sweeps", sweep_moved > 200.0, "beam end travelled %.0f m on the ground" % sweep_moved)
	tgt.queue_free()
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_orders() -> void:
	var v := PoliceHeliAI.spawn(Vector3(100, 90, 100)) as HeliVehicle
	var ai := PoliceHeliAI.of(v)
	ai.set_order({"mode": &"pursue", "target": player, "pos": Vector3.ZERO, "radius": 55.0, "aggression": 0.9, "lethal": true})
	T.report("police_heli_order_pursue", ai.mode == &"pursue" and ai.get_target() == player and absf(ai.aggression - 0.9) < 0.01, "mode=%s" % ai.mode)
	ai.set_order({"mode": &"hold", "target": null})
	T.report("police_heli_order_hold", ai.mode == &"hold", "mode=%s" % ai.mode)
	ai.set_mode(&"bogus")
	T.report("police_heli_unknown_mode_is_patrol", ai.mode == &"patrol", "mode=%s" % ai.mode)
	# the director's duck-typing: set_mode / set_target on a child of the vehicle
	var found := false
	for c in v.get_children():
		if c.has_method("set_mode") and c.has_method("set_target"):
			found = true
	T.report("police_heli_director_can_find_api", found and v.has_meta(&"police_ai") and v.get_meta(&"police_ai").has_method("set_order"), "")
	# leave: flies away and removes itself
	ai.set_mode(&"leave")
	var gone := false
	for i in 60 * 70:
		await tree.physics_frame
		if not is_instance_valid(v) or not v.is_inside_tree() or v.get_parent() == null or not v.visible:
			gone = true
			break
		if PoliceHeliAI.active_count() == 0:
			gone = true
			break
	T.report("police_heli_leave_despawns", gone, "gone=%s" % gone)
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_gunner() -> void:
	if player == null:
		return
	Game.time_of_day = 22.0
	player.teleport_to(WorldLayout.location_pos(&"player_spawn"))
	await T.frames(tree, 20)
	var pp: Vector3 = player.global_position
	var v := PoliceHeliAI.spawn(pp + Vector3(90, 70, 60)) as HeliVehicle
	var ai := PoliceHeliAI.of(v)
	ai.level_override = 4
	ai.set_order({"mode": &"pursue", "target": player, "aggression": 1.0, "lethal": true})
	var h0: float = player.health
	var shots := [0]
	var cb := func(_pos: Vector3, _loud: float, src: Node) -> void:
		if src == v:
			shots[0] += 1
	Events.gunshot.connect(cb)
	var lit_t := 0.0
	for i in 60 * 40:
		await tree.physics_frame
		if ai.player_lit:
			lit_t += 1.0 / 60.0
	Events.gunshot.disconnect(cb)
	T.report("police_heli_sees_player", ai.stats["sightings"] > 0 and lit_t > 5.0, "sightings=%d, player lit %.1f s" % [ai.stats["sightings"], lit_t])
	T.report("police_heli_gunner_fires_at_level4", ai.stats["bursts"] >= 2 and ai.stats["rounds"] >= 6, "bursts=%d rounds=%d gunshot events=%d" % [ai.stats["bursts"], ai.stats["rounds"], shots[0]])
	T.report("police_heli_gunner_rate_limited", ai.stats["rounds"] < 120, "%d rounds in 40 s" % ai.stats["rounds"])
	T.report("police_heli_gunner_inaccurate", player.health > h0 - 70.0 or Game.cheats.get("invulnerable", false), "player health %.0f -> %.0f" % [h0, player.health])
	# level 2: no gunfire
	ai.level_override = 2
	var r0: int = ai.stats["rounds"]
	await T.frames(tree, 60 * 12)
	T.report("police_heli_no_gunfire_below_level4", ai.stats["rounds"] == r0, "rounds %d -> %d" % [r0, ai.stats["rounds"]])
	if player.health < 30.0:
		player.revive()
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_autopilot_plane() -> void:
	# AirAutopilot on a plane: takeoff + orbit, in the private test studio
	var floor_node := T.make_floor(get_tree().root, 20000.0)
	await T.frames(tree, 10)
	var p := T.spawn(&"plane_prop", Vector3(0, 0.1, 0), -90.0, {"ai": false, "abandoned": true, "snap_ground": true}) as PlaneVehicle
	await T.frames(tree, 60)
	var ap := AirAutopilot.attach(p)
	p.set_engine(true)
	ap.takeoff(90.0)
	var done := [false]
	ap.takeoff_done.connect(func() -> void: done[0] = true)
	for i in 60 * 45:
		await tree.physics_frame
		if done[0]:
			break
	T.report("autopilot_plane_takes_off", done[0] and p.global_position.y > 40.0 and not p.is_destroyed, "alt %.0f m after %s" % [p.global_position.y, "takeoff_done" if done[0] else "timeout"])
	ap.orbit(p.global_position + Vector3(0, 0, 500), 450.0, 160.0, 55.0)
	await T.frames(tree, 60 * 30)
	T.report("autopilot_plane_orbits", not p.is_destroyed and p.global_position.y > 60.0 and p.linear_velocity.length() > p.stall_speed, "alt %.0f m speed %.0f km/h" % [p.global_position.y, p.linear_velocity.length() * 3.6])
	ap.stop()
	T.remove_all(tree)
	floor_node.queue_free()
	await T.frames(tree, 3)
