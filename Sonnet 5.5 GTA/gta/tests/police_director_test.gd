extends Node
## Headless PoliceManager / PoliceDirector tests with mock units (Police-A). Run:
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/police_director_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds"
## `--only=a,b` filters the groups. The director is driven by hand (manual = true, tick(dt)).

const Mock = preload("res://gta/tests/wanted_mock.gd")

var wanted: WantedSystem
var pm: PoliceManager
var player: Player
var factory: Mock.Factory
var mocks: Node3D
var _passes := 0
var _fails := 0
var _veh: VehicleBase = null
var moving := true


func _check(test_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST %s PASS %s" % [test_name, detail])
	else:
		_fails += 1
		print("TEST %s FAIL %s" % [test_name, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _tick(seconds: float, dt: float = 0.1) -> void:
	for i in int(round(seconds / dt)):
		pm.tick(dt)
		if moving:
			_wiggle(dt)


## Mock units "drive": they slide back and forth so the idle recycler leaves them alone (physics frames do not run inside _tick).
func _wiggle(dt: float) -> void:
	var dirx := 2.0 if sin(pm._t * 0.4) >= 0.0 else -2.0
	for c in mocks.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Mock.Car or c is Mock.Officer:
			var lo: Variant = c.get("last_order")
			if lo is Dictionary and lo.get("mode") == &"leave":
				# a unit told to leave drives away from the player like the real ones do
				var away := Util.flat((c as Node3D).global_position - player.global_position)
				away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
				(c as Node3D).global_position += away * 16.0 * dt
			else:
				(c as Node3D).global_position += Vector3(dirx, 0, 0) * dt


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().find_world_3d().direct_space_state


func _retire_all() -> void:
	for c in mocks.get_children():
		var stack: Array[Node] = [c]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for g in n.get_groups():
				if not String(g).begins_with("_"):
					n.remove_from_group(g)
			for k in n.get_children():
				stack.append(k)
		c.queue_free()
	pm.units.clear()


func _reset() -> void:
	wanted.clear()
	wanted._dead = false
	wanted._busted = false
	_retire_all()
	factory.n_cars = 0
	factory.n_vans = 0
	factory.n_foot = 0
	factory.n_blocks = 0
	factory.n_despawn = 0
	factory.refuse = false
	factory.spawn_log.clear()
	moving = true
	pm._t += 1000.0                       # past every cooldown
	pm._stand_down = false
	pm._fail_until.clear()
	pm._last_level = 0
	pm._response_ready_t = 0.0
	pm._surge_until = 0.0
	pm._next_wave_t = 0.0
	pm._block_cd = 0.0
	pm._heli_cd = 0.0
	pm._spawn_cd = 0.0
	pm._site_fails = 0
	pm._first_response = false


func _count(kind: StringName) -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and pm._kind_of(n) == kind:
			if kind in [&"car", &"van", &"heli"] and not pm._counts_as_police_vehicle(n):
				continue
			c += 1
	return c


func _world_counts() -> Dictionary:
	var veh := 0
	var off := 0
	var heli := 0
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		match pm._kind_of(n):
			&"heli":
				if pm._counts_as_police_vehicle(n):
					heli += 1
			&"car", &"van":
				if pm._counts_as_police_vehicle(n):
					veh += 1
			&"foot", &"swat":
				off += 1
	return {"veh": veh, "off": off, "heli": heli}


func _put_player(pos: Vector3, yaw_deg: float = 0.0) -> void:
	if player.is_in_vehicle():
		player.exit_vehicle(true)
		await _frames(10)
	player.teleport_to(pos, deg_to_rad(yaw_deg))
	await _frames(25)


func run(_main: Node) -> Variant:
	await _frames(5)
	wanted = Game.sys(&"wanted") as WantedSystem
	pm = Game.sys(&"police") as PoliceManager
	player = Game.player as Player
	if wanted == null or pm == null or player == null:
		print("TEST boot FAIL wanted=%s police=%s player=%s" % [str(wanted), str(pm), str(player)])
		return false
	wanted.manual = true
	pm.manual = true
	player.use_real_input = false
	player.invulnerable = true
	mocks = Node3D.new()
	mocks.name = "DirectorMocks"
	Game.world.add_child(mocks)
	factory = Mock.Factory.new(mocks)
	pm.set_factory(factory)
	pm.heli_spawner = Callable(factory, "spawn_heli")
	pm.director.rng.seed = 12345
	await _frames(30)

	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	var groups := ["force", "sites", "levels", "orders", "calm", "excess", "recycle", "roadblock", "heli", "refuse", "station", "busted", "real"]
	for g in groups:
		if only == "" or only.split(",").has(g):
			_reset()
			await call("_t_" + g)
	_reset()
	pm.set_factory(null)
	player.invulnerable = false
	print("TEST SUMMARY passes=%d fails=%d" % [_passes, _fails])
	return _fails == 0


# =====================================================================================================================
func _t_force() -> void:
	var d := pm.director
	var cars: Array = []
	var helis: Array = []
	for l in 6:
		var f := d.force_for(l, &"pursuit")
		cars.append(f["cars"])
		helis.append(f["heli"])
	_check("force_cars_per_level", cars == [0, 1, 3, 4, 5, 6], str(cars))
	_check("force_helis_per_level", helis == [0, 0, 0, 1, 1, 2], str(helis))
	_check("force_roadblocks_from_level_3", d.force_for(2, &"pursuit")["blocks"] == 0 and d.force_for(3, &"pursuit")["blocks"] >= 1 and d.force_for(4, &"pursuit")["blocks"] >= 2)
	_check("force_tactical_vans_from_level_4", d.force_for(3, &"pursuit")["vans"] == 0 and d.force_for(4, &"pursuit")["vans"] >= 1 and d.force_for(5, &"pursuit")["vans"] >= 2)
	_check("force_lethal_from_level_2", not d.force_for(1, &"pursuit")["lethal"] and d.force_for(2, &"pursuit")["lethal"])
	_check("force_search_is_smaller_without_roadblocks", d.force_for(4, &"search")["cars"] < d.force_for(4, &"pursuit")["cars"] and d.force_for(4, &"search")["blocks"] == 0)
	var cap_ok := PoliceDirector.MAX_VEHICLES == 10 and PoliceDirector.MAX_OFFICERS == 20 and PoliceDirector.MAX_HELIS == 2
	_check("force_hard_caps_constants", cap_ok)
	var f5 := d.force_for(5, &"pursuit")
	_check("force_5_star_is_8_plus_vehicles", int(f5["cars"]) + int(f5["vans"]) >= 8, "cars+vans=%d" % (int(f5["cars"]) + int(f5["vans"])))
	var roles := {}
	for i in 5:
		var r := d.pick_role(5, roles)
		roles[r] = int(roles.get(r, 0)) + 1
	_check("force_roles_are_mixed", roles.has(&"tail") and roles.has(&"intercept") and roles.size() >= 3, str(roles))


func _t_sites() -> void:
	var lanes: LaneGraph = WorldLayout.lanes
	_check("sites_lane_graph_exists", lanes != null and lanes.size() > 1000, "points=%d" % (lanes.size() if lanes != null else 0))
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 2500.0
	add_child(cam)
	var d := PoliceDirector.new()
	d.rng.seed = 777
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var space := _space()
	var tested := 0
	var found := 0
	var bad_dist := 0
	var bad_view := 0
	var bad_graph := 0
	var bad_cam_dist := 0
	var in_view_total := 0
	for k in 60:
		var idx := rng.randi() % lanes.size()
		var p := lanes.positions[idx]
		var yaw := rng.randf() * TAU
		cam.global_position = p + Vector3(0, 3.5, 0) - Util.yaw_to_dir(yaw) * 5.0
		cam.global_rotation = Vector3(deg_to_rad(-8.0), yaw, 0.0)
		for want in [&"any", &"ahead", &"behind", &"side"]:
			var req := {"center": p, "player": p, "camera": cam, "space": space, "min_dist": 80.0, "max_dist": 260.0, "want": want,
				"heading": Util.yaw_to_dir(yaw), "avoid": []}
			var site := d.find_road_site(req)
			tested += 1
			if site.is_empty():
				continue
			found += 1
			var sp: Vector3 = site["pos"]
			if Util.dist_xz(sp, p) < 80.0:
				bad_dist += 1
			if Util.dist_xz(sp, cam.global_position) < 80.0:
				bad_cam_dist += 1
			if cam.is_position_in_frustum(sp + Vector3.UP):
				in_view_total += 1
				# only acceptable when a wall hides it
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, sp + Vector3.UP, GC.M_LOS)
				if space.intersect_ray(q).is_empty():
					bad_view += 1
			var ln := lanes.nearest(sp, Vector3.ZERO, 1.0)
			if ln < 0 or lanes.kind[ln] == LaneGraph.KIND_CONNECTOR:
				bad_graph += 1
	_check("sites_found_most_of_the_time", found >= int(tested * 0.9), "found %d of %d" % [found, tested])
	_check("sites_at_least_80m_from_player", bad_dist == 0, "bad=%d" % bad_dist)
	_check("sites_at_least_80m_from_camera", bad_cam_dist == 0, "bad=%d" % bad_cam_dist)
	_check("sites_never_visible_to_the_camera", bad_view == 0, "visible=%d (hidden-by-wall in frustum: %d)" % [bad_view, in_view_total])
	_check("sites_on_the_lane_graph", bad_graph == 0, "bad=%d" % bad_graph)
	_check("sites_frustum_rejection_happened", int(d.stats["rej_view"]) > 0, "rej_view=%d rej_near=%d" % [int(d.stats["rej_view"]), int(d.stats["rej_near"])])
	# directional wishes
	var ahead_ok := 0
	var ahead_n := 0
	var behind_ok := 0
	var behind_n := 0
	for k in 25:
		var idx2 := rng.randi() % lanes.size()
		var p2 := lanes.positions[idx2]
		var yaw2 := rng.randf() * TAU
		var heading := Util.yaw_to_dir(yaw2)
		cam.global_position = p2 + Vector3(0, 3.5, 0) - heading * 5.0
		cam.global_rotation = Vector3(deg_to_rad(-8.0), yaw2, 0.0)
		var s1 := d.find_road_site({"center": p2, "player": p2, "camera": cam, "space": space, "want": &"ahead", "heading": heading, "avoid": [], "pref_dist": 190.0})
		if not s1.is_empty():
			ahead_n += 1
			if heading.dot(Util.flat((s1["pos"] as Vector3) - p2).normalized()) > 0.0:
				ahead_ok += 1
		var s2 := d.find_road_site({"center": p2, "player": p2, "camera": cam, "space": space, "want": &"behind", "heading": heading, "avoid": [], "pref_dist": 115.0})
		if not s2.is_empty():
			behind_n += 1
			if heading.dot(Util.flat((s2["pos"] as Vector3) - p2).normalized()) < 0.2:
				behind_ok += 1
	_check("sites_ahead_wish_mostly_honoured", ahead_n > 5 and ahead_ok >= int(ahead_n * 0.7), "%d/%d" % [ahead_ok, ahead_n])
	_check("sites_behind_wish_mostly_honoured", behind_n > 5 and behind_ok >= int(behind_n * 0.7), "%d/%d" % [behind_ok, behind_n])
	# spacing: a new site keeps its distance from existing units
	var avoid: Array = []
	var near_avoid := 0
	for k in 12:
		var s := d.find_road_site({"center": Vector3(0, 0, 40), "player": Vector3(0, 0, 40), "camera": null, "space": space, "avoid": avoid})
		if s.is_empty():
			continue
		for a in avoid:
			if Util.dist_xz(a, s["pos"]) < 28.0:
				near_avoid += 1
		avoid.append(s["pos"])
	_check("sites_keep_spacing_between_units", near_avoid == 0 and avoid.size() >= 6, "violations=%d sites=%d" % [near_avoid, avoid.size()])
	# a foot site on the ped graph
	var fs := d.find_foot_site({"center": Vector3(0, 0, 40), "player": Vector3(0, 0, 40), "camera": cam, "space": space})
	_check("sites_foot_site_on_ped_graph", not fs.is_empty() and Util.dist_xz(fs["pos"], Vector3(0, 0, 40)) >= 80.0)
	cam.queue_free()


# ---- the response per level with mock units ----------------------------------------------------------------------------------------
func _t_levels() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	var cam := pm._camera()
	var space := _space()
	var peak := {}
	for lvl in [1, 2, 3, 4, 5]:
		_reset()
		wanted.set_level(lvl)
		var t_first := -1.0
		var t := 0.0
		var spawn_times: Array = []
		var last_cars := 0
		while t < 75.0:
			pm.tick(0.1)
			_wiggle(0.1)
			t += 0.1
			if factory.n_cars + factory.n_vans + factory.n_foot > last_cars:
				last_cars = factory.n_cars + factory.n_vans + factory.n_foot
				spawn_times.append(t)
				if t_first < 0.0:
					t_first = t
		var c := _world_counts()
		var cars := _count(&"car")
		var vans := _count(&"van")
		var f := pm.director.force_for(lvl, &"pursuit")
		peak[lvl] = c
		_check("levels_L%d_cars_match_force" % lvl, cars == int(f["cars"]), "cars=%d want=%d (spawned %d)" % [cars, int(f["cars"]), factory.n_cars])
		_check("levels_L%d_vans_match_force" % lvl, vans == int(f["vans"]), "vans=%d want=%d" % [vans, int(f["vans"])])
		_check("levels_L%d_foot_officers_present" % lvl, factory.n_foot >= mini(int(f["foot"]), 1) if int(f["foot"]) > 0 else true, "foot=%d" % factory.n_foot)
		_check("levels_L%d_within_caps" % lvl, c["veh"] <= 10 and c["off"] <= 20 and c["heli"] <= 2, str(c))
		_check("levels_L%d_response_delay" % lvl, t_first >= 1.5 and t_first <= 9.5, "first unit after %.1f s" % t_first)
		var gaps_ok := true
		for i in range(1, spawn_times.size()):
			if spawn_times[i] - spawn_times[i - 1] < 1.2:
				gaps_ok = false
		_check("levels_L%d_spawns_are_staggered" % lvl, gaps_ok, str(spawn_times.slice(0, 6)))
		# every unit appeared legally: >= 80 m from the player, outside the camera frustum, cars on a lane
		var bad_far := 0
		var bad_view := 0
		var bad_lane := 0
		for e in factory.spawn_log:
			var np: Vector3 = e["pos"]
			if e["kind"] == &"heli":
				continue
			if Util.dist_xz(np, player.global_position) < 80.0:
				bad_far += 1
			if cam != null and cam.is_position_in_frustum(np + Vector3.UP):
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, np + Vector3.UP, GC.M_LOS)
				if space.intersect_ray(q).is_empty():
					bad_view += 1
			if e["kind"] in [&"car", &"van"] and WorldLayout.lanes.nearest(np, Vector3.ZERO, 2.0) < 0:
				bad_lane += 1
		_check("levels_L%d_spawn_rules" % lvl, bad_far == 0 and bad_view == 0 and bad_lane == 0, "near=%d visible=%d off_lane=%d" % [bad_far, bad_view, bad_lane])
	_check("levels_5_stars_has_8_plus_vehicles", int(peak[5]["veh"]) >= 8, str(peak[5]))
	_check("levels_force_grows_with_level", int(peak[1]["veh"]) < int(peak[3]["veh"]) and int(peak[3]["veh"]) < int(peak[5]["veh"]), "%d %d %d" % [peak[1]["veh"], peak[3]["veh"], peak[5]["veh"]])
	# the registry is the single list of what the director owns
	_check("levels_registry_matches_world", pm.units.size() >= 8, "registered=%d" % pm.units.size())


func _t_orders() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	wanted.set_level(2)
	_tick(30.0)
	var recs := pm.get_records()
	var cars: Array = []
	for r in recs:
		if r["kind"] == &"car":
			cars.append(r)
	_check("orders_cars_got_orders", cars.size() == 3 and cars.all(func(r): return (r["node"] as Mock.Car).order_count > 0), "cars=%d" % cars.size())
	var o: Dictionary = (cars[0]["node"] as Mock.Car).last_order
	_check("orders_pursuit_mode_targets_player", o.get("mode") == &"pursue" and o.get("target") == player, str(o.get("mode")))
	_check("orders_lethal_at_two_stars", bool(o.get("lethal")) and float(o.get("aggression", 0.0)) >= 0.5, "aggr=%.2f" % float(o.get("aggression", 0.0)))
	var roles := {}
	for r in cars:
		roles[r["role"]] = true
	_check("orders_cars_have_different_roles", roles.size() >= 2, str(roles.keys()))
	# search state
	var saved_sight := [wanted.sight_range_day, wanted.sight_range_night, wanted.track_radius, wanted.blind_radius]
	wanted.sight_range_day = 1.0
	wanted.sight_range_night = 1.0
	wanted.track_radius = 1.0
	wanted.blind_radius = 1.0
	wanted.tick(0.3)
	wanted._seen_now = false
	wanted._last_seen_t = -999.0
	wanted.tick(0.1)
	_check("orders_precondition_search", wanted.state == &"search", String(wanted.state))
	_tick(3.0)
	var so: Dictionary = (cars[0]["node"] as Mock.Car).last_order
	_check("orders_search_mode_with_area", so.get("mode") == &"search" and (so["pos"] as Vector3).distance_to(wanted.last_known) < 1.0 and float(so.get("radius", 0.0)) > 30.0,
		"%s r=%.0f" % [str(so.get("mode")), float(so.get("radius", 0.0))])
	_check("orders_search_not_lethal", not bool(so.get("lethal")))
	# re-sighting turns them back to pursuit
	wanted.sight_range_day = saved_sight[0]
	wanted.sight_range_night = saved_sight[1]
	wanted.track_radius = saved_sight[2]
	wanted.blind_radius = saved_sight[3]
	wanted.report_sighting(player.global_position, null)
	_tick(2.5)
	var po: Dictionary = (cars[0]["node"] as Mock.Car).last_order
	_check("orders_resighting_back_to_pursuit", po.get("mode") == &"pursue", str(po.get("mode")))
	# level up -> higher aggression
	var aggr2 := float(po.get("aggression", 0.0))
	wanted.set_level(5)
	_tick(3.0)
	var o5: Dictionary = (cars[0]["node"] as Mock.Car).last_order
	_check("orders_aggression_grows_with_level", float(o5.get("aggression", 0.0)) > aggr2, "%.2f -> %.2f" % [aggr2, float(o5.get("aggression", 0.0))])
	# stationary player -> box him in
	var tactic_seen := false
	for r in pm.get_records():
		if r["kind"] == &"car" and (r["node"] as Mock.Car).last_order.get("tactic") == &"box":
			tactic_seen = true
	_check("orders_stationary_player_gets_boxed", tactic_seen)
	# busted: everyone holds
	Events.player_busted.emit()
	_tick(2.5)
	var hold_all := true
	for r in pm.get_records():
		if r["kind"] != &"roadblock" and (r["node"] as Object).get("last_order") != null and (r["node"] as Object).get("last_order").get("mode") != &"hold":
			hold_all = false
	_check("orders_busted_units_hold", hold_all)
	Events.player_respawned.emit(player.global_position)
	wanted.clear()
	_tick(2.5)
	var leave_all := true
	for r in pm.get_records():
		var lo: Variant = (r["node"] as Object).get("last_order")
		if lo != null and lo.get("mode") != &"leave":
			leave_all = false
	_check("orders_clear_sends_everyone_away", leave_all)


func _t_calm() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	wanted.set_level(4)
	_tick(60.0)
	var before := pm.units.size()
	_check("calm_precondition_units_exist", before >= 8, "units=%d" % before)
	wanted.clear()
	_tick(1.0)
	var leaving := 0
	for r in pm.get_records():
		if r["leaving"]:
			leaving += 1
	_check("calm_everyone_flagged_leaving", leaving == pm.units.size() or pm.units.is_empty(), "leaving=%d of %d" % [leaving, pm.units.size()])
	_tick(30.0)
	_check("calm_units_removed_when_out_of_sight", pm.units.size() == 0 and factory.n_despawn >= before - 1, "left=%d despawned=%d of %d" % [pm.units.size(), factory.n_despawn, before])
	# re-escalation works afterwards
	wanted.set_level(2)
	_tick(30.0)
	_check("calm_new_pursuit_spawns_again", _count(&"car") == 3, "cars=%d" % _count(&"car"))


func _t_excess() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	wanted.set_level(5)
	_tick(70.0)
	var cars5 := pm._active_count([&"car"])
	_check("excess_precondition_5_stars", cars5 == 6, "cars=%d" % cars5)
	wanted.set_level(2)
	_tick(1.0)
	print("DBG excess lvl=%d state=%s force=%s excess_cd=%.1f t=%.1f" % [Game.wanted_level, String(Game.wanted_state), str(pm._snap.get("force")), pm._excess_cd, pm._t])
	var active_after_1s := pm._active_count([&"car"])
	_check("excess_fades_out_gradually", active_after_1s >= 5, "active cars after 1 s: %d (was 6)" % active_after_1s)
	_tick(25.0)
	for r in pm.get_records():
		print("DBG rec kind=%s role=%s leaving=%s owned=%s pinned=%s" % [str(r["kind"]), str(r["role"]), str(r["leaving"]), str(r["owned"]), str(r["pinned"])])
	_check("excess_ends_at_new_force", pm._active_count([&"car"]) == 3 and pm._active_count([&"van"]) == 0, "cars=%d vans=%d" % [pm._active_count([&"car"]), pm._active_count([&"van"])])
	_check("excess_helis_gone_at_2_stars", pm._active_count([&"heli"]) == 0, "helis=%d" % pm._active_count([&"heli"]))


func _t_recycle() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	moving = false
	wanted.set_level(2)
	_tick(15.0)
	var first_cars := factory.n_cars
	_check("recycle_precondition", first_cars == 3, "cars=%d" % first_cars)
	_tick(30.0)       # the mock units never move: idle for > 20 s out of sight
	_check("recycle_idle_units_are_replaced", factory.n_despawn >= 1 and factory.n_cars > first_cars, "despawned=%d spawned=%d" % [factory.n_despawn, factory.n_cars])
	_check("recycle_never_exceeds_force", _count(&"car") <= 3, "cars=%d" % _count(&"car"))
	# a unit that is on screen is never recycled (only out of sight)
	var cam := pm._camera()
	_check("recycle_camera_exists", cam != null)


func _t_roadblock() -> void:
	# put the player into a real car on a road, driving
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	var lanes: LaneGraph = WorldLayout.lanes
	var start := lanes.nearest(player.global_position, Vector3.ZERO, 40.0)
	var dirv := lanes.dirs[start]
	var veh := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dirv)), lanes.positions[start] + Vector3(0, 0.4, 0)), {"abandoned": true})
	if veh == null:
		_check("roadblock_vehicle_spawned", false)
		return
	await _frames(30)
	player.global_position = veh.global_position + Vector3(2.0, 0.4, 0.0)
	player.enter_vehicle(veh, 0)
	await _frames(70)
	_check("roadblock_player_in_car", player.is_in_vehicle())
	var heading := Util.flat(dirv).normalized()
	wanted.set_level(3)
	var min_ahead := 1e9
	var spawned_center := Vector3.ZERO
	for i in 600:
		veh.linear_velocity = heading * 22.0
		pm.tick(0.1)
		if factory.n_blocks > 0 and spawned_center == Vector3.ZERO:
			for n in mocks.get_children():
				if n is Mock.Block:
					spawned_center = n.global_position
	_check("roadblock_spawned_at_3_stars", factory.n_blocks >= 1, "blocks=%d" % factory.n_blocks)
	if spawned_center != Vector3.ZERO:
		var rel := spawned_center - player.global_position
		var dist := Util.flat(rel).length()
		_check("roadblock_distance_150_to_350m", dist >= 150.0 and dist <= 380.0, "dist=%.0f" % dist)
		_check("roadblock_ahead_of_travel_direction", heading.dot(Util.flat(rel).normalized()) > 0.3, "dot=%.2f" % heading.dot(Util.flat(rel).normalized()))
		_check("roadblock_on_the_road", lanes.nearest(spawned_center, Vector3.ZERO, 12.0) >= 0)
		var cam := pm._camera()
		var vis := cam != null and cam.is_position_in_frustum(spawned_center + Vector3.UP * 1.5)
		var hidden := false
		if vis:
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, spawned_center + Vector3.UP * 1.5, GC.M_LOS)
			hidden = not _space().intersect_ray(q).is_empty()
		_check("roadblock_not_visible_when_created", not vis or hidden)
	var active_blocks := pm._active_count([&"roadblock"])
	_check("roadblock_at_most_planned_concurrently", active_blocks <= pm.director.force_for(3, &"pursuit")["blocks"], "active=%d" % active_blocks)
	var c := _world_counts()
	_check("roadblock_respects_caps", c["veh"] <= 10 and c["off"] <= 20, str(c))
	# replaced after its lifetime, removed once the level drops
	wanted.set_level(4)
	for i in 300:
		veh.linear_velocity = heading * 22.0
		pm.tick(0.1)
	_check("roadblock_second_one_at_4_stars", pm._active_count([&"roadblock"]) <= 2 and factory.n_blocks >= 2, "active=%d total=%d" % [pm._active_count([&"roadblock"]), factory.n_blocks])
	wanted.set_level(2)
	for i in 400:
		veh.linear_velocity = heading * 22.0
		pm.tick(0.1)
	_check("roadblock_removed_when_level_drops", pm._active_count([&"roadblock"]) == 0, "active=%d" % pm._active_count([&"roadblock"]))
	# on foot: no roadblocks
	VehicleFactory.despawn(veh)


func _t_heli() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	wanted.set_level(2)
	_tick(40.0)
	_check("heli_none_at_2_stars", _count(&"heli") == 0)
	wanted.set_level(3)
	_tick(45.0)
	_check("heli_one_at_3_stars", _count(&"heli") == 1, "helis=%d" % _count(&"heli"))
	wanted.set_level(5)
	_tick(60.0)
	_check("heli_two_at_5_stars_max", _count(&"heli") == 2, "helis=%d" % _count(&"heli"))
	var heli_pos_ok := true
	for n in mocks.get_children():
		pass
	for e in factory.spawn_log:
		if e["kind"] == &"heli" and Util.dist_xz(e["pos"], player.global_position) < 150.0:
			heli_pos_ok = false
	_check("heli_spawn_far_from_player", heli_pos_ok)
	var any_order := false
	for r in pm.get_records():
		if r["kind"] == &"heli" and (r["node"] as Mock.Car).order_count > 0:
			any_order = true
	_check("heli_receives_orders", any_order)
	wanted.set_level(1)
	_tick(120.0)
	_check("heli_leaves_when_level_drops", _count(&"heli") == 0, "helis=%d" % _count(&"heli"))


func _t_refuse() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	factory.refuse = true
	wanted.set_level(4)
	_tick(20.0)
	for r in pm.get_records():
		print("DBG refuse rec kind=%s role=%s node=%s" % [str(r["kind"]), str(r["role"]), str(r["node"])])
	_check("refuse_factory_returns_null_no_crash", pm.units.is_empty() and _count(&"car") == 0, "units=%d cars=%d" % [pm.units.size(), _count(&"car")])
	_check("refuse_backoff_set", pm._fail_until.has(&"car"), str(pm._fail_until.keys()))
	factory.refuse = false
	_tick(30.0)
	_check("refuse_recovers_after_backoff", _count(&"car") > 0, "cars=%d" % _count(&"car"))


func _t_station() -> void:
	# the player is far from the station: the first responder comes out of the station
	var station: Vector3 = WorldLayout.location_pos(&"police_station")
	await _put_player(WorldLayout.location_pos(&"helipad_airport") + Vector3(0, 0.3, 4))
	wanted.set_level(1)
	var t0 := pm._t
	pm.tick(0.1)
	var rq := pm._site_req(&"tail", true)
	print("DBG station req station=%s min=%s max=%s avoid=%d" % [str(rq["station"]), str(rq["min_dist"]), str(rq["max_dist"]), (rq["avoid"] as Array).size()])
	var ds := pm.director.find_road_site(rq)
	print("DBG station direct site=", ds, " stats=", pm.director.stats)
	print("DBG station first_response=%s ready_in=%.1f snap_lk=%s level=%d last_level=%d" % [str(pm._first_response), pm._response_ready_t - pm._t, str(pm._snap.get("last_known")), Game.wanted_level, pm._last_level])
	for k in 140:
		_tick(0.1)
		if pm.units.size() > 0:
			print("DBG station first unit at t=%.1f stats=%s fr=%s" % [pm._t, str(pm.director.stats), str(pm._first_response)])
			break
	_tick(2.0)
	var first: Dictionary = {}
	for r in pm.get_records():
		print("DBG station rec kind=%s role=%s source=%s pos=%s" % [str(r["kind"]), str(r["role"]), str(r["source"]), str((r["node"] as Node3D).global_position)])
		if r["kind"] == &"car" and first.is_empty():
			first = r
	_check("station_first_car_spawned", not first.is_empty())
	if not first.is_empty():
		var np := (first["node"] as Node3D).global_position
		_check("station_first_car_comes_from_the_station", first["source"] == &"station" and Util.dist_xz(np, station) < 45.0, "source=%s dist_to_station=%.0f" % [str(first["source"]), Util.dist_xz(np, station)])
	_reset()
	# the player stands right at the station: the car must not appear in his face
	await _put_player(station + Vector3(0, 0.3, 6))
	wanted.set_level(1)
	_tick(14.0)
	var ok := true
	for n in mocks.get_children():
		if n is Mock.Car and Util.dist_xz(n.global_position, player.global_position) < 80.0:
			ok = false
	_check("station_never_spawns_within_80m_of_the_player", ok and factory.n_cars >= 1, "cars=%d" % factory.n_cars)


func _t_busted() -> void:
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	wanted.set_level(3)
	_tick(20.0)
	var n0 := factory.n_cars
	Events.player_busted.emit()
	_tick(10.0)
	_check("busted_no_new_spawns_while_standing_down", factory.n_cars == n0, "before=%d after=%d" % [n0, factory.n_cars])
	Events.player_respawned.emit(player.global_position)
	wanted.clear()


# ---- Police-B's real units (only when delivered) ----------------------------------------------------------------------------------
func _t_real() -> void:
	pm.set_factory(null)
	var scr := PoliceManager._resolve_script(&"PoliceUnits")
	if scr == null:
		_check("real_police_units_loadable", false, "PoliceUnits cannot be loaded")
		return
	await _put_player(WorldLayout.location_pos(&"player_spawn") + Vector3(0, 0.2, 0))
	var site := pm.director.find_road_site({"center": player.global_position, "player": player.global_position, "camera": pm._camera(), "space": _space(), "avoid": []})
	if site.is_empty():
		_check("real_site_found", false)
		return
	var xf := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(site["dir"])), site["pos"])
	var car = scr.call("spawn_patrol_car", xf, 2)
	if car == null:
		print("TEST real_patrol_car SKIP PoliceUnits.spawn_patrol_car returned null (Police-B not delivered yet)")
		pm.set_factory(factory)
		return
	await _frames(20)
	_check("real_patrol_car_spawned", is_instance_valid(car) and car.is_in_group(GC.G_POLICE), str(car))
	_check("real_patrol_car_has_set_order", car.has_method("set_order") or (car.has_meta(&"police_ai") and car.get_meta(&"police_ai").has_method("set_order")))
	scr.call("despawn", car)
	pm.set_factory(factory)
