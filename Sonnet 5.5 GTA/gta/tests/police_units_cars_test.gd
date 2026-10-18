extends Node
## Police-B headless tests: patrol cars, PoliceCarAI (lane loop pursuit, PIT, deploy on foot), roadblock, caps / despawn, performance.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/police_units_cars_test.gd -Seconds 240 -GameArgs "--no-traffic --no-peds --no-hostiles"
## Runs in the real city (lane graph needed).

var passed := 0
var failed := 0
var main_node: Node = null
var _skip: Dictionary = {}


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


func _only(name: String) -> bool:
	var want := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			want = String(a).substr(7)
	return want == "" or want.split(",").has(name)


func run(main: Node) -> String:
	main_node = main
	await get_tree().process_frame
	PoliceUnits.autostart_hostiles = false
	var pm = Game.sys(&"police")
	if pm != null:
		pm.enabled = false
	Game.cheats["invulnerable"] = true
	Game.cheats["traffic"] = false
	if is_instance_valid(Game.player):
		Game.player.teleport_to(Vector3(-100, 0.2, 100), 0.0)
	await seconds(1.0)
	if _only("spawn"):
		await _t_spawn_and_caps()
	if _only("patrol"):
		await _t_patrol_loop()
	if _only("chase"):
		await _t_chase_loop()
	if _only("pit"):
		await _t_pit()
	if _only("deploy"):
		await _t_deploy()
	if _only("roadblock"):
		await _t_roadblock()
	if _only("spike"):
		await _t_spike()
	if _only("perf"):
		await _t_perf()
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
	return "passed=%d failed=%d" % [passed, failed]


func lane_xf(world_pos: Vector3, dir_hint: Vector3, back := 0.0) -> Transform3D:
	var lg := WorldLayout.lanes
	var i := lg.nearest(world_pos, dir_hint, 30.0)
	if i < 0:
		i = lg.nearest(world_pos, Vector3.ZERO, 60.0)
	var p := lg.positions[i] - lg.dirs[i] * back
	return Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(lg.dirs[i])), p + Vector3(0, 0.5, 0))


# --------------------------------------------------------------------------------------------------------------------
func _t_spawn_and_caps() -> void:
	var xf := lane_xf(Vector3(105, 0, 60), Vector3(0, 0, -1))
	var car := PoliceUnits.spawn_patrol_car(xf, 2)
	check("car_spawn", car != null and car is VehicleBase, "")
	if car == null:
		return
	await seconds(0.5)
	check("car_faction_group", car.faction == GC.F_POLICE and car.is_in_group(GC.G_POLICE) and car.has_meta(&"police_ai"), "")
	var occ := car.get_occupants()
	check("car_officers_seated", occ.size() == 2 and occ[0] is PoliceOfficer and car.driver is PoliceOfficer, "occupants=%d" % occ.size())
	check("car_ai_controlled", car.is_ai_controlled and not car.siren_on, "siren=%s" % car.siren_on)
	var van := PoliceUnits.spawn_tactical_van(lane_xf(Vector3(105, 0, 20), Vector3(0, 0, -1), 25.0))
	await seconds(0.3)
	check("van_four_swat", van != null and van.get_occupants().size() == 4 and (van.get_occupants()[0] as PoliceOfficer).kind == &"swat", "occ=%d" % (van.get_occupants().size() if van else -1))
	# caps
	var spawned: Array = [car, van]
	for i in 14:
		var c := PoliceUnits.spawn_patrol_car(lane_xf(Vector3(-105 + i * 5, 0, 20), Vector3(0, 0, 1), 0.0), 1)
		if c != null:
			spawned.append(c)
	await seconds(0.3)
	check("cap_police_cars_10", PoliceUnits.count_cars() <= PoliceUnits.MAX_CARS and PoliceUnits.rejected > 0, "cars=%d rejected=%d" % [PoliceUnits.count_cars(), PoliceUnits.rejected])
	for c in spawned:
		PoliceUnits.despawn(c)
	await seconds(0.6)
	check("despawn_cars_free_slots", PoliceUnits.count_cars() == 0 and PoliceUnits.count_officers() == 0, "cars=%d officers=%d" % [PoliceUnits.count_cars(), PoliceUnits.count_officers()])
	var offs: Array = []
	for i in 50:
		var o := PoliceUnits.spawn_officer(&"patrol", Transform3D(Basis(), Vector3(-100 + (i % 10) * 2, 0.5, 100 + (i / 10) * 2)))
		if o != null:
			offs.append(o)
	check("cap_officers", PoliceUnits.count_officers() <= PoliceUnits.MAX_OFFICERS, "officers=%d" % PoliceUnits.count_officers())
	for o in offs:
		PoliceUnits.despawn(o)
	await seconds(0.3)
	check("despawn_officers", PoliceUnits.count_officers() == 0, "left=%d" % PoliceUnits.count_officers())


func _t_patrol_loop() -> void:
	# a cruiser patrols the lane graph for 45 s: stays upright, covers ground, never gets stuck for long
	var xf := lane_xf(Vector3(105, 0, 60), Vector3(0, 0, -1))
	var car := PoliceUnits.spawn_patrol_car(xf, 1)
	var ai := car.get_meta(&"police_ai") as PoliceCarAI
	ai.autonomous = false
	ai.set_order({"mode": &"patrol"})
	var start := car.global_position
	var dist := 0.0
	var last := start
	var worst_up := 1.0
	var slow_t := 0.0
	var t := 0.0
	while t < 45.0:
		await frames(30)
		t += 0.5
		dist += car.global_position.distance_to(last)
		last = car.global_position
		worst_up = minf(worst_up, car.global_transform.basis.y.y)
		if car.get_speed() < 1.0:
			slow_t += 0.5
	check("patrol_drives_lanes", dist > 300.0, "dist=%.0f m in 45 s (red lights obeyed, traffic on)" % dist)
	check("patrol_stays_upright", worst_up > 0.85, "min up.y=%.2f" % worst_up)
	check("patrol_not_stuck", slow_t < 8.0, "slow=%.1f s" % slow_t)
	PoliceUnits.despawn(car)
	await seconds(0.5)


func _t_chase_loop() -> void:
	# a runner follows the lane loop; three cruisers chase it for 60 s without flipping, staying with it
	var lg := WorldLayout.lanes
	var xf := lane_xf(Vector3(105, 0, 60), Vector3(0, 0, -1))
	var d0 := -xf.basis.z
	var runner := VehicleFactory.spawn(&"sedan", xf, {"ai": true})
	var rai := PoliceCarAI.attach(runner)
	rai.autonomous = false
	rai.driverless = true
	rai.obey_signals = false
	rai.speed_factor = 1.25
	rai.set_order({"mode": &"patrol"})
	runner.faction = GC.F_CIVILIAN
	var cars: Array = []
	for i in 3:
		var cxf := lane_xf(xf.origin - d0 * (16.0 + 12.0 * i), d0)
		var c := PoliceUnits.spawn_patrol_car(cxf, 2)
		var ai := c.get_meta(&"police_ai") as PoliceCarAI
		ai.autonomous = false
		ai.set_order({"mode": &"pursue", "target": runner, "aggression": 0.8, "lethal": false, "level": 2, "role": [&"tail", &"flank", &"intercept"][i]})
		cars.append(c)
	var t := 0.0
	var worst_up := 1.0
	var within := 0.0
	var flips := 0
	var runner_dist := 0.0
	var rl := runner.global_position
	var nearest_min := 999.0
	while t < 60.0:
		await frames(30)
		t += 0.5
		runner_dist += runner.global_position.distance_to(rl)
		rl = runner.global_position
		var best := 999.0
		for c in cars:
			worst_up = minf(worst_up, c.global_transform.basis.y.y)
			if c.is_flipped_over():
				flips += 1
			best = minf(best, c.global_position.distance_to(runner.global_position))
		nearest_min = minf(nearest_min, best)
		if t > 20.0 and best < 45.0:
			within += 0.5
	check("chase_runner_moves", runner_dist > 400.0, "runner drove %.0f m in 60 s (traffic on)" % runner_dist)
	check("chase_no_flips", flips == 0 and worst_up > 0.5, "flip samples=%d min up.y=%.2f" % [flips, worst_up])
	check("chase_stays_on_target", within > 24.0, "nearest cruiser < 45 m for %.0f of 40 s (closest %.1f m)" % [within, nearest_min])
	print("TEST chase_stats pit_attempts=%d pit_contacts=%d rams=%d recoveries=%d" % [PoliceCarAI.pit_attempts, PoliceCarAI.pit_contacts, PoliceCarAI.rams, PoliceCarAI.recoveries])
	var slow_cars := 0
	for c in cars:
		if (c.get_meta(&"police_ai") as PoliceCarAI)._stuck_count > 6:
			slow_cars += 1
	check("chase_cars_not_wedged", slow_cars == 0, "cars with > 6 stuck events in 60 s: %d (stuck counts %s)" % [slow_cars, str(cars.map(func(c2): return (c2.get_meta(&"police_ai") as PoliceCarAI)._stuck_count))])
	for c in cars:
		PoliceUnits.despawn(c)
	PoliceUnits.despawn(runner)
	await seconds(0.5)


func _t_pit() -> void:
	# deterministic PIT: target cruises straight along the north arterial, the pursuer sits at its rear quarter
	var lg := WorldLayout.lanes
	var i0 := lg.nearest(Vector3(-85, 0, -88), Vector3(1, 0, 0), 30.0)
	if i0 < 0:
		check("pit_setup", false, "no lane at the north arterial")
		return
	var p0 := lg.positions[i0]
	var d0 := lg.dirs[i0]
	var yaw := Util.dir_to_yaw(d0)
	var target := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, yaw), p0 + Vector3(0, 0.5, 0)), {"ai": true})
	var tai := PoliceCarAI.attach(target)
	tai.autonomous = false
	tai.driverless = true
	tai.obey_signals = false
	tai.speed_factor = 0.95
	tai.set_order({"mode": &"patrol"})
	target.faction = GC.F_CIVILIAN
	target.set_velocity(d0 * 19.0)
	var side := Vector3(-d0.z, 0, d0.x)                  # right of the travel direction
	var cp := p0 + d0 * (-2.6) + side * 2.5 * -1.0       # behind-left rear quarter
	var cop := PoliceUnits.spawn_patrol_car(Transform3D(Basis(Vector3.UP, yaw), cp + Vector3(0, 0.5, 0)), 1)
	var ai := cop.get_meta(&"police_ai") as PoliceCarAI
	ai.autonomous = false
	cop.set_velocity(d0 * 19.5)
	ai.set_order({"mode": &"pursue", "target": target, "aggression": 0.8, "lethal": true, "level": 3, "role": &"tail"})
	var yaw0 := target.global_rotation.y
	var max_dyaw := 0.0
	var contact := [false]
	cop.collided.connect(func(other, _imp): if other == target: contact[0] = true)
	var worst_up := 1.0
	var min_gap := 99.0
	var t := 0.0
	var attempts0 := PoliceCarAI.pit_attempts
	while t < 6.0:
		await frames(6)
		t += 0.1
		max_dyaw = maxf(max_dyaw, absf(wrapf(target.global_rotation.y - yaw0, -PI, PI)))
		min_gap = minf(min_gap, cop.global_position.distance_to(target.global_position))
		worst_up = minf(worst_up, minf(cop.global_transform.basis.y.y, target.global_transform.basis.y.y))
	check("pit_attempted", PoliceCarAI.pit_attempts > attempts0, "attempts=%d" % (PoliceCarAI.pit_attempts - attempts0))
	check("pit_contact", contact[0] or min_gap < 2.4, "collided=%s min centre gap=%.2f m" % [contact[0], min_gap])
	check("pit_turns_target", max_dyaw > deg_to_rad(20.0), "target yaw change %.0f deg" % rad_to_deg(max_dyaw))
	check("pit_no_flip", worst_up > 0.35, "min up.y=%.2f" % worst_up)
	PoliceUnits.despawn(cop)
	PoliceUnits.despawn(target)
	await seconds(0.5)


func _t_deploy() -> void:
	# target on foot: the car stops ~12 m away and the officers get out and go for the target
	var pl = Game.player
	pl.teleport_to(Vector3(105.0, 0.3, 30.0), 0.0)
	await seconds(1.0)
	var xf := lane_xf(Vector3(105, 0, 90), Vector3(0, 0, -1))
	var car := PoliceUnits.spawn_patrol_car(xf, 2)
	var ai := car.get_meta(&"police_ai") as PoliceCarAI
	ai.autonomous = false
	car.set_velocity((-xf.basis.z) * 10.0)
	ai.set_order({"mode": &"pursue", "target": pl, "aggression": 0.3, "lethal": false, "level": 1})
	var t := 0.0
	var deployed := false
	var stop_dist := 0.0
	while t < 25.0 and not deployed:
		await frames(15)
		t += 0.25
		if ai.deployed:
			deployed = true
			stop_dist = Util.dist_xz(car.global_position, pl.global_position)
	check("deploy_car_stops_and_deploys", deployed, "t=%.1f stop_dist=%.1f" % [t, stop_dist])
	check("deploy_stop_distance", deployed and stop_dist > 5.0 and stop_dist < 22.0, "%.1f m" % stop_dist)
	await seconds(0.8)
	var on_foot := 0
	for o in PoliceUnits.officers():
		if not (o as PoliceOfficer).is_in_vehicle():
			on_foot += 1
	check("deploy_officers_on_foot", on_foot == 2, "on_foot=%d" % on_foot)
	# they walk up to the player and arrest him (unarmed, standing still) -> BUSTED
	var busted := [false]
	var on_busted := func(): busted[0] = true
	Events.player_busted.connect(on_busted)
	var close := 999.0
	var t2 := 0.0
	while t2 < 14.0 and not busted[0]:
		await frames(15)
		t2 += 0.25
		for o in PoliceUnits.officers():
			close = minf(close, Util.dist_xz((o as Node3D).global_position, pl.global_position))
	Events.player_busted.disconnect(on_busted)
	check("deploy_officers_approach_target", close < 3.2, "closest %.1f m" % close)
	check("deploy_arrest", busted[0], "busted=%s after %.1f s" % [busted[0], t2])
	for o in PoliceUnits.officers():
		PoliceUnits.despawn(o)
	PoliceUnits.despawn(car)
	await seconds(4.0)           # let the player respawn flow finish
	Game.cheats["invulnerable"] = true
	pl.teleport_to(Vector3(-100, 0.2, 100), 0.0)


func _t_roadblock() -> void:
	for lvl in [3, 4, 5]:
		var c := Vector3(105.0, 0.1, -10.0)
		var rb := PoliceUnits.spawn_roadblock(c, Vector3(0, 0, -1), lvl) as PoliceRoadblock
		check("roadblock_built_l%d" % lvl, rb != null, "")
		if rb == null:
			continue
		await seconds(2.5)
		# scan across the road: rays along the travel direction at 0.5 m spacing must all hit something solid
		var space := get_viewport().world_3d.direct_space_state
		var misses := 0
		var miss_us: Array = []
		var max_gap := 0
		var cur := 0
		var n := 0
		var u := -rb.half_width - 1.0
		while u <= rb.half_width + 1.0:
			var from := rb.center + rb.axis * u - rb.travel_dir * 14.0 + Vector3(0, 0.7, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + rb.travel_dir * 20.0, GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP)
			var hit := space.intersect_ray(q)
			n += 1
			if hit.is_empty():
				miss_us.append(snappedf(u, 0.1))
				misses += 1
				cur += 1
				max_gap = maxi(max_gap, cur)
			else:
				cur = 0
			u += 0.5
		check("roadblock_seals_road_l%d" % lvl, max_gap <= 3, "(no gap a 1.9 m car fits through) half_width=%.1f rays=%d misses=%d longest gap=%.1f m at u=%s" % [rb.half_width, n, misses, max_gap * 0.5, str(miss_us)])
		check("roadblock_units_l%d" % lvl, rb.cars.size() >= 2 and rb.officers.size() >= 2, "cars=%d officers=%d props=%d spike=%s" % [rb.cars.size(), rb.officers.size(), rb.props.size(), rb.spike != null])
		var holders := 0
		for o in rb.officers:
			if is_instance_valid(o) and (o as PoliceOfficer).mode == &"hold":
				holders += 1
		check("roadblock_officers_hold_l%d" % lvl, holders == rb.officers.size(), "holding=%d" % holders)
		var cars := rb.cars.duplicate()
		var offs := rb.officers.duplicate()
		PoliceUnits.despawn(rb)
		await seconds(0.6)
		var freed := true
		for o in offs:
			if is_instance_valid(o):
				freed = false
		check("roadblock_cleanup_l%d" % lvl, freed and PoliceUnits.count_cars() == 0 and PoliceUnits.count_officers() == 0, "cars=%d officers=%d" % [PoliceUnits.count_cars(), PoliceUnits.count_officers()])


func _t_perf() -> void:
	# the whole force in a fight: 3 cruisers + a van + 12 officers around the player's plaza, measured cost per physics frame
	var pl = Game.player
	pl.teleport_to(Vector3(14.0, 0.2, 38.0), 180.0)
	await seconds(1.0)
	var lg := WorldLayout.lanes
	var cars: Array = []
	for i in 3:
		var c := PoliceUnits.spawn_patrol_car(lane_xf(Vector3(-35 + i * 35, 0, -20), Vector3(0, 0, 1)), 2)
		if c != null:
			cars.append(c)
	var van := PoliceUnits.spawn_tactical_van(lane_xf(Vector3(35, 0, 50), Vector3(0, 0, 1)))
	if van != null:
		cars.append(van)
	var foot: Array = []
	for i in 12:
		var o := PoliceUnits.spawn_officer(&"swat" if i % 4 == 0 else &"patrol", Transform3D(Basis(), Vector3(14 + (i - 6) * 2.5, 0.3, 14 + (i % 3) * 3)))
		if o != null:
			foot.append(o)
	await seconds(1.0)
	for o in PoliceUnits.officers():
		(o as PoliceOfficer).set_order({"mode": &"pursue", "target": pl, "aggression": 0.8, "lethal": true})
	for c in cars:
		var ai := c.get_meta(&"police_ai") as PoliceCarAI
		ai.autonomous = false
		ai.set_order({"mode": &"pursue", "target": pl, "aggression": 0.8, "lethal": true, "level": 3})
	await seconds(4.0)
	PoliceUnits.reset_stats()
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	await seconds(10.0)
	var frames_n := maxi(Engine.get_physics_frames() - f0, 1)
	var st := PoliceUnits.stats()
	var brain_ms := float(st["brain_usec"]) / 1000.0 / float(frames_n)
	var car_ms := float(st["car_usec"]) / 1000.0 / float(frames_n)
	print("TEST perf_detail brain_ms/frame=%.3f car_ms/frame=%.3f paths=%d path_ms=%.1f cover_queries=%d officers=%d cars=%d wall=%.1fs" % [brain_ms, car_ms,
		int(st["paths"]), float(st["path_usec"]) / 1000.0, int(st["cover_queries"]), int(st["officers"]), int(st["cars"]), (Time.get_ticks_usec() - t0) / 1.0e6])
	check("perf_force_under_3ms", brain_ms + car_ms < 3.0, "brain=%.3f ms car=%.3f ms per frame" % [brain_ms, car_ms])
	for c in cars:
		PoliceUnits.despawn(c)
	for o in PoliceUnits.officers():
		PoliceUnits.despawn(o)
	await seconds(0.5)


func _t_spike() -> void:
	# a civilian car rolling over a spike strip loses its tyres; a police car passes unharmed
	var xf := lane_xf(Vector3(105, 0, 60), Vector3(0, 0, -1))
	var d0 := -xf.basis.z
	var strip_pos := xf.origin + d0 * 45.0
	var strip := PoliceUnits.spawn_spike_strip(strip_pos, d0, 8.0) as SpikeStrip
	check("spike_strip_spawned", strip != null, "")
	if strip == null:
		return
	var across := strip.global_transform.basis.x
	check("spike_strip_across_road", absf(across.dot(d0)) < 0.2, "width axis . travel dir = %.2f" % across.dot(d0))
	# deterministic: the car is dropped onto the strip (traffic in the city would steer a free-driving car around it)
	var on_strip := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(d0)), strip_pos + Vector3(0, 0.5, 0))
	var civ := VehicleFactory.spawn(&"sedan", on_strip, {"ai": true})
	civ.faction = GC.F_CIVILIAN
	civ.set_velocity(d0 * 6.0)
	await seconds(2.0)
	var flats := 0
	for w in civ.wheels:
		if (w as VehicleWheel).flat:
			flats += 1
	check("spike_punctures_civilian_tyres", flats >= 1 and strip.hits >= 1, "flat wheels=%d hits=%d" % [flats, strip.hits])
	PoliceUnits.despawn(civ)
	await seconds(0.5)
	var cop := PoliceUnits.spawn_patrol_car(on_strip, 1)
	cop.set_velocity(d0 * 6.0)
	await seconds(2.0)
	var cop_flats := 0
	for w in cop.wheels:
		if (w as VehicleWheel).flat:
			cop_flats += 1
	check("spike_spares_police", cop_flats == 0, "police flats=%d" % cop_flats)
	PoliceUnits.despawn(cop)
	strip.queue_free()
	await seconds(0.5)
