extends Node
## LIVE integration test (Police-A): the real WantedSystem + PoliceManager + Police-B's real units (PoliceUnits, PoliceCarAI, PoliceOfficer)
## on the real city. Both systems are driven from this node's _physics_process (manual = true) so their CPU cost can be timed.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/police_director_live_test.gd -Seconds 500 -GameArgs "--no-traffic --no-peds --time=14"
## `--only=pursuit_foot,pursuit_drive,escape,arrest` filters the groups. Prints "TEST <name> PASS|FAIL <detail>" and "LIVE ..." metric lines.

var wanted: WantedSystem
var pm: PoliceManager
var player: Player
var _passes := 0
var _fails := 0

# per-run measurements
var _t_run := 0.0
var _cost_w := 0
var _cost_p := 0
var _cost_n := 0
var _cost_max_p := 0
var _seen_ids: Dictionary = {}
var _spawn_log: Array = []
var _max_veh := 0
var _max_off := 0
var _max_heli := 0
var _max_blocks := 0
var _dmin := 1e9
var _t_first_close := -1.0
var _cap_acc := 0.0
var _running := false
var _busted_count := 0
var _changes: Array = []
var _trace := false
var _trace_acc := 0.0

# driving helper (kinematic nudge of the player's car along the lane graph)
var _veh: VehicleBase = null
var _drive_on := false
var _lane_i := -1
var _drive_speed := 17.0


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


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().find_world_3d().direct_space_state


func _physics_process(dt: float) -> void:
	if not _running or wanted == null or pm == null:
		return
	_t_run += dt
	var t0 := Time.get_ticks_usec()
	wanted.tick(dt)
	var t1 := Time.get_ticks_usec()
	pm.tick(dt)
	var t2 := Time.get_ticks_usec()
	_cost_w += t1 - t0
	_cost_p += t2 - t1
	_cost_n += 1
	_cost_max_p = maxi(_cost_max_p, t2 - t1)
	if _drive_on:
		_drive(dt)
	_watch_spawns()
	_trace_acc += dt
	if _trace and _trace_acc >= 2.0:
		_trace_acc = 0.0
		var dn := 1e9
		var kinds := {}
		for id in pm.units:
			var nn: Variant = pm.units[id]["node"]
			if is_instance_valid(nn) and nn is Node3D:
				var dd := Util.dist_xz((nn as Node3D).global_position, player.global_position)
				dn = minf(dn, dd)
				var kk: StringName = pm.units[id]["kind"]
				var prev: Array = kinds.get(kk, [0, 1e9])
				kinds[kk] = [int(prev[0]) + 1, minf(float(prev[1]), dd)]
		var ks := ""
		for k in kinds:
			ks += " %s:%d@%.0f" % [String(k), int(kinds[k][0]), float(kinds[k][1])]
		print("TRACE t=%.0f L%d %s seen=%s prog=%.2f mult=%.2f inside=%s lk_dist=%.0f r=%.0f%s" % [_t_run, wanted.level, String(wanted.state), str(wanted._seen_now), wanted.escape_progress(), wanted.get_escape_multiplier(), str(wanted.is_inside_search_area()), Util.dist_xz(wanted.last_known, player.global_position), wanted.search_radius, ks])
	_cap_acc += dt
	if _cap_acc >= 0.5:
		_cap_acc = 0.0
		var st := pm.get_stats()
		_max_veh = maxi(_max_veh, int(st["vehicles"]))
		_max_off = maxi(_max_off, int(st["officers"]))
		_max_heli = maxi(_max_heli, int(st["helis"]))
		_max_blocks = maxi(_max_blocks, int(st["roadblocks"]))
		for id in pm.units:
			var rec: Dictionary = pm.units[id]
			var n: Variant = rec["node"]
			if is_instance_valid(n) and rec["kind"] != &"roadblock" and rec["kind"] != &"heli":
				var d := Util.dist_xz((n as Node3D).global_position, player.global_position)
				if d < _dmin:
					_dmin = d
				if d < 30.0 and _t_first_close < 0.0:
					_t_first_close = _t_run


func _watch_spawns() -> void:
	var cam := pm._camera()
	for id in pm.units:
		if _seen_ids.has(id):
			continue
		_seen_ids[id] = true
		var rec: Dictionary = pm.units[id]
		var n: Variant = rec["node"]
		if not is_instance_valid(n) or not (n is Node3D) or rec["role"] == &"adopted":
			continue
		var pos := (n as Node3D).global_position
		var vis := false
		if cam != null and rec["kind"] != &"heli" and rec["kind"] != &"roadblock":
			vis = pm.director.visible_to_camera(cam, pos, -(n as Node3D).global_transform.basis.z, _space())
		var on_lane: bool = WorldLayout.lanes.nearest(pos, Vector3.ZERO, 4.0) >= 0
		_spawn_log.append({"kind": rec["kind"], "role": rec["role"], "pos": pos, "dist": Util.dist_xz(pos, player.global_position), "visible": vis,
			"lane": on_lane, "t": _t_run})


func _drive(_dt: float) -> void:
	## Pure-pursuit along the lane graph with the player's own command fields (cmd_move.x steer, cmd_move.y throttle / brake).
	if _veh == null or not is_instance_valid(_veh) or not player.is_in_vehicle():
		return
	var lanes: LaneGraph = WorldLayout.lanes
	var pos := _veh.global_position
	var fwd := Util.flat(-_veh.global_transform.basis.z).normalized()
	if _lane_i < 0:
		_lane_i = lanes.nearest(pos, fwd, 25.0)
		if _lane_i < 0:
			return
	var guard := 0
	while Util.dist_xz(lanes.positions[_lane_i], pos) < 16.0 and guard < 8:
		var nx: PackedInt32Array = lanes.next[_lane_i]
		if nx.is_empty():
			break
		var best: int = nx[0]
		var best_dot := -2.0
		for o in nx:
			var od: Vector3 = Util.flat(lanes.positions[o] - lanes.positions[_lane_i])
			if od.length() > 0.01 and od.normalized().dot(fwd) > best_dot:
				best_dot = od.normalized().dot(fwd)
				best = o
		_lane_i = best
		guard += 1
	var to := Util.flat(lanes.positions[_lane_i] - pos)
	if to.length() < 0.1:
		return
	to = to.normalized()
	var steer := clampf((fwd.x * to.z - fwd.z * to.x) * 2.2, -1.0, 1.0)
	var spd := _veh.linear_velocity.length()
	var thr := 1.0 if spd < _drive_speed else (-0.4 if spd > _drive_speed + 4.0 else 0.0)
	player.cmd_move = Vector2(steer, thr)


# =====================================================================================================================
func run(_main: Node) -> Variant:
	await _frames(5)
	wanted = Game.sys(&"wanted") as WantedSystem
	pm = Game.sys(&"police") as PoliceManager
	player = Game.player as Player
	if wanted == null or pm == null or player == null:
		print("TEST boot FAIL wanted=%s police=%s player=%s" % [str(wanted), str(pm), str(player)])
		return false
	wanted.manual = true
	wanted.debug_clear = true
	pm.manual = true
	player.use_real_input = false
	player.invulnerable = true
	Game.cheats["invulnerable"] = true      # the real officers shoot (lethal from 2 stars)
	Events.player_busted.connect(func():
		_busted_count += 1
		_changes.append([snappedf(_t_run, 0.1), -1, "BUSTED"]))
	Events.wanted_changed.connect(func(l, s): _changes.append([snappedf(_t_run, 0.1), l, String(s)]))
	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	var groups := ["pursuit_foot", "pursuit_drive", "escape", "escape_interior", "arrest", "witness_real"]
	for g in groups:
		if only == "" or only.split(",").has(g):
			await _reset()
			await call("_t_" + g)
	await _reset()
	_running = false
	pm.manual = false
	wanted.manual = false
	player.invulnerable = false
	Game.cheats["invulnerable"] = false
	print("TEST SUMMARY passes=%d fails=%d" % [_passes, _fails])
	return _fails == 0


func _reset() -> void:
	_running = false
	_drive_on = false
	PoliceOfficer.arrest_enabled = false      # the officers' own arrest only in the arrest group (a standing player would be cuffed in every scenario)
	if player.is_in_vehicle():
		player.exit_vehicle(true)
		await _frames(20)
	# a previous arrest / death leaves the player in the busted state with a pending respawn: start every group clean
	player.respawn_at(&"player_spawn", {"silent": true, "keep_health": true})
	await _frames(10)
	if _veh != null and is_instance_valid(_veh):
		VehicleFactory.despawn(_veh)
	_veh = null
	wanted.clear()
	wanted._dead = false
	wanted._busted = false
	pm.despawn_all()
	pm._stand_down = false
	pm._last_level = 0
	pm._response_ready_t = 0.0
	pm._surge_until = 0.0
	pm._block_cd = 0.0
	pm._heli_cd = 0.0
	pm._spawn_cd = 0.0
	pm._site_fails = 0
	pm._first_response = false
	# the police that are left over from the previous group
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if is_instance_valid(n) and n.has_meta(&"police_director"):
			PoliceUnits.despawn(n)
	await _frames(10)
	_seen_ids.clear()
	_spawn_log.clear()
	_max_veh = 0
	_max_off = 0
	_max_heli = 0
	_max_blocks = 0
	_dmin = 1e9
	_t_first_close = -1.0
	_cost_w = 0
	_cost_p = 0
	_cost_n = 0
	_cost_max_p = 0
	_t_run = 0.0
	_changes.clear()
	wanted.bust_quiet_time = 1e9          # no arrests unless a group wants them
	wanted.hail_enabled = false


func _put_player(pos: Vector3, yaw_deg: float = 0.0) -> void:
	if player.is_in_vehicle():
		player.exit_vehicle(true)
		await _frames(15)
	player.teleport_to(pos, deg_to_rad(yaw_deg))
	await _frames(40)


## A point on a street near the spawn (the police can reach it by road, officers deploy from the cars).
func _street_pos() -> Vector3:
	var lanes: LaneGraph = WorldLayout.lanes
	var base := WorldLayout.location_pos(&"player_spawn")
	var i := lanes.nearest(base, Vector3.ZERO, 80.0)
	return (lanes.positions[i] + Vector3(0, 0.3, 0)) if i >= 0 else base + Vector3(0, 0.2, 0)


func _wait(seconds: float, until: Callable = Callable()) -> float:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if until.is_valid() and until.call():
			break
	return t


func _report(tag: String) -> void:
	var st := pm.get_stats()
	var n := maxi(_cost_n, 1)
	print("LIVE %s level=%d state=%s veh=%d off=%d heli=%d blocks=%d | peak veh=%d off=%d heli=%d blocks=%d | dmin=%.0f first_close=%.1fs | spawned cars=%d vans=%d foot=%d helis=%d blocks=%d despawned=%d" % [
		tag, wanted.level, String(wanted.state), int(st["vehicles"]), int(st["officers"]), int(st["helis"]), int(st["roadblocks"]),
		_max_veh, _max_off, _max_heli, _max_blocks, _dmin, _t_first_close, int(st["spawned_cars"]), int(st["spawned_vans"]), int(st["spawned_foot"]),
		int(st["spawned_helis"]), int(st["spawned_blocks"]), int(st["despawned"])])
	print("LIVE %s changes=%s spawn_ms_max=%s" % [tag, str(_changes), str(st["spawn_ms_max"])])
	print("LIVE %s cost wanted avg=%.1f us  director avg=%.1f us max=%d us over %d ticks" % [tag, float(_cost_w) / n, float(_cost_p) / n, _cost_max_p, _cost_n])


func _spawn_rules_ok() -> Dictionary:
	var near := 0
	var vis := 0
	var off_lane := 0
	var n := 0
	for e in _spawn_log:
		if e["kind"] == &"heli":
			continue
		n += 1
		if e["dist"] < 80.0:
			near += 1
		if e["visible"]:
			vis += 1
		if e["kind"] in [&"car", &"van"] and not e["lane"]:
			off_lane += 1
	return {"n": n, "near": near, "visible": vis, "off_lane": off_lane}


# ---- scenario 1: on foot, the player kills an officer -> 3 stars, the whole response arrives ------------------------------------------
func _t_pursuit_foot() -> void:
	await _put_player(_street_pos())
	_running = true
	_trace = true
	var cop := PoliceUnits.spawn_officer(&"patrol", Transform3D(Basis(), player.global_position + Vector3(0, 0.3, -14.0)))
	await _frames(20)
	_check("foot_real_officer_spawned", cop != null and cop.is_in_group(GC.G_POLICE))
	if cop == null:
		return
	cop.apply_damage(5000.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": cop.global_position, "weapon": &"pistol"})
	await _frames(10)
	_check("foot_killing_an_officer_gives_3_stars", wanted.level >= 3, "level=%d heat=%.0f state=%s" % [wanted.level, wanted.heat, String(wanted.state)])
	_check("foot_state_after_officer_down", wanted.state == &"pursuit" or wanted.state == &"search", String(wanted.state))
	await _wait(75.0)
	_report("pursuit_foot")
	var rules := _spawn_rules_ok()
	_check("foot_units_spawned", int(rules["n"]) >= 4, str(rules))
	_check("foot_spawn_rules_distance_80m", int(rules["near"]) == 0, str(rules))
	_check("foot_spawn_rules_outside_frustum", int(rules["visible"]) == 0, str(rules))
	_check("foot_spawn_rules_cars_on_lane_graph", int(rules["off_lane"]) == 0, str(rules))
	_check("foot_caps_vehicles", _max_veh <= PoliceDirector.MAX_VEHICLES, "peak=%d" % _max_veh)
	_check("foot_caps_officers", _max_off <= PoliceDirector.MAX_OFFICERS + 1, "peak=%d" % _max_off)
	_check("foot_caps_helis", _max_heli <= PoliceDirector.MAX_HELIS, "peak=%d" % _max_heli)
	_check("foot_police_reach_the_player", _t_first_close > 0.0 and _t_first_close < 60.0, "first within 30 m after %.1f s (dmin %.0f)" % [_t_first_close, _dmin])
	_check("foot_still_hunted_after_75s", wanted.level >= 2 and wanted.state == &"pursuit", "level=%d %s" % [wanted.level, String(wanted.state)])
	var ordered := 0
	var total := 0
	for id in pm.units:
		var rec: Dictionary = pm.units[id]
		if is_instance_valid(rec["node"]) and rec["kind"] in [&"car", &"van", &"foot", &"swat"]:
			total += 1
			if rec["mode"] == &"pursue":
				ordered += 1
	_check("foot_units_ordered_to_pursue", total > 0 and ordered >= total - 1, "%d of %d" % [ordered, total])
	# performance of the two systems
	var avg_w := float(_cost_w) / maxi(_cost_n, 1)
	var avg_p := float(_cost_p) / maxi(_cost_n, 1)
	_check("foot_wanted_cost_below_300us", avg_w < 300.0, "avg=%.1f us" % avg_w)
	_check("foot_director_cost_below_400us", avg_p < 400.0, "avg=%.1f us max=%d us" % [avg_p, _cost_max_p])


# ---- scenario 2: the player drives (lane following), 4 stars: roadblocks ahead, flankers, helicopters --------------------------------
func _t_pursuit_drive() -> void:
	await _put_player(_street_pos())
	var lanes: LaneGraph = WorldLayout.lanes
	var start := lanes.nearest(player.global_position, Vector3.ZERO, 40.0)
	if start < 0:
		_check("drive_lane_found", false)
		return
	var dirv := lanes.dirs[start]
	_veh = VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dirv)), lanes.positions[start] + Vector3(0, 0.5, 0)), {"abandoned": true})
	if _veh == null:
		_check("drive_vehicle_spawned", false)
		return
	await _frames(40)
	player.global_position = _veh.global_position + Vector3(2.0, 0.4, 0.0)
	player.enter_vehicle(_veh, 0)
	await _frames(80)
	_check("drive_player_in_car", player.is_in_vehicle())
	_lane_i = -1
	_drive_on = true
	_running = true
	wanted.set_level(4)
	for probe in 3:
		await _wait(20.0, func(): return _max_blocks >= 1)
		var pv: Vector3 = pm._snap.get("pvel", Vector3.ZERO)
		print("LIVE drive probe: speed=%.1f state=%s level=%d veh=%d off=%d blocks=%d block_cd=%.1f t=%.1f ready=%.1f pos=%s" % [Util.flat(pv).length(), String(wanted.state), wanted.level, pm._veh_world, pm._off_world, _max_blocks, pm._block_cd, pm._t, pm._response_ready_t, str(player.global_position)])
	var blk_t := await _wait(30.0, func(): return _max_blocks >= 1)
	print("LIVE drive first roadblock after %.1f s (blocks=%d)" % [blk_t, _max_blocks])
	_check("drive_roadblock_built_ahead", _max_blocks >= 1, "blocks=%d" % _max_blocks)
	await _wait(40.0)
	_report("pursuit_drive")
	var rules := _spawn_rules_ok()
	_check("drive_spawn_rules_distance_80m", int(rules["near"]) == 0, str(rules))
	_check("drive_spawn_rules_outside_frustum", int(rules["visible"]) == 0, str(rules))
	_check("drive_spawn_rules_cars_on_lane_graph", int(rules["off_lane"]) == 0, str(rules))
	_check("drive_caps", _max_veh <= PoliceDirector.MAX_VEHICLES and _max_off <= PoliceDirector.MAX_OFFICERS + 1 and _max_heli <= PoliceDirector.MAX_HELIS, "veh=%d off=%d heli=%d" % [_max_veh, _max_off, _max_heli])
	var roles := {}
	for e in _spawn_log:
		if e["kind"] == &"car":
			roles[e["role"]] = int(roles.get(e["role"], 0)) + 1
	_check("drive_cars_arrive_from_different_roles", roles.size() >= 2, str(roles))
	var avg_p := float(_cost_p) / maxi(_cost_n, 1)
	_check("drive_director_cost_below_500us", avg_p < 500.0, "avg=%.1f us max=%d us" % [avg_p, _cost_max_p])
	# level drops: the force fades out
	_drive_on = false
	wanted.set_level(1)
	await _wait(60.0)
	_report("pursuit_drive_after_drop")
	var st := pm.get_stats()
	_check("drive_force_shrinks_with_the_level", int(st["vehicles"]) <= 4 and int(st["roadblocks"]) == 0, "veh=%d blocks=%d" % [int(st["vehicles"]), int(st["roadblocks"])])


# ---- scenario 3: the player vanishes -> search -> escape ------------------------------------------------------------------------------
func _t_escape() -> void:
	await _put_player(_street_pos())
	_running = true
	wanted.set_level(2)
	await _wait(25.0)
	var st1 := pm.get_stats()
	_check("escape_force_exists_before", int(st1["vehicles"]) + int(st1["officers"]) >= 3, "veh=%d off=%d" % [int(st1["vehicles"]), int(st1["officers"])])
	# hide far away from every unit: the lane point that maximises the distance to all police (and >= 150 m from where we stand)
	var far := WorldLayout.location_pos(&"helipad_airport")
	var best_d := -1.0
	var lanes: LaneGraph = WorldLayout.lanes
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 400:
		var lp := lanes.positions[rng.randi() % lanes.size()]
		if Util.dist_xz(lp, player.global_position) < 280.0:      # beyond the largest search circle (240 m): the player really got away
			continue
		var dmin := 1e9
		for n in get_tree().get_nodes_in_group(GC.G_POLICE):
			if is_instance_valid(n) and n is Node3D:
				dmin = minf(dmin, Util.dist_xz((n as Node3D).global_position, lp))
		if dmin > best_d:
			best_d = dmin
			far = lp
	await _put_player(far + Vector3(0, 0.3, 4))
	var t_search := await _wait(30.0, func(): return wanted.state == &"search" or wanted.level == 0)
	print("LIVE escape: state=%s after %.1f s at %s (nearest unit %.0f m)" % [String(wanted.state), t_search, str(far), best_d])
	_check("escape_goes_to_search_when_unseen", wanted.state == &"search" or wanted.level == 0, "%s level=%d" % [String(wanted.state), wanted.level])
	await _wait(2.5)
	if wanted.state == &"search":
		_check("escape_search_orders_given", _count_mode(&"search") >= 1, "search-mode units=%d" % _count_mode(&"search"))
	var t_clear := await _wait(120.0, func(): return wanted.level == 0)
	print("LIVE escape: cleared after %.1f s more (level=%d state=%s) changes=%s" % [t_clear, wanted.level, String(wanted.state), str(_changes)])
	_check("escape_clears_the_wanted_level", wanted.level == 0, "level=%d state=%s progress=%.2f" % [wanted.level, String(wanted.state), wanted.escape_progress()])
	await _wait(80.0)
	var st2 := pm.get_stats()
	_report("escape_after")
	_check("escape_units_leave_after_clear", int(st2["registered"]) <= 1, "registered=%d vehicles=%d officers=%d" % [int(st2["registered"]), int(st2["vehicles"]), int(st2["officers"])])


# ---- scenario 3b: the player hides in an interior (far-away room): nobody can see him, the bar runs 2.6x ---------------------------------------
func _t_escape_interior() -> void:
	await _put_player(_street_pos())
	_running = true
	wanted.set_level(2)
	await _wait(14.0)
	var street := player.global_position
	await _put_player(Vector3(120.0, -400.0, 0.0))      # where InteriorSystem puts the rooms
	var t := await _wait(60.0, func(): return wanted.level == 0)
	print("LIVE escape_interior: level=%d state=%s after %.1f s multiplier=%.1f" % [wanted.level, String(wanted.state), t, wanted.get_escape_multiplier()])
	_check("escape_interior_clears_fast", wanted.level == 0 and t < 40.0, "level=%d after %.1f s" % [wanted.level, t])
	await _put_player(street)


func _count_mode(mode: StringName) -> int:
	var c := 0
	for id in pm.units:
		var rec: Dictionary = pm.units[id]
		if is_instance_valid(rec["node"]) and rec["mode"] == mode:
			c += 1
	return c


# ---- scenario 4: 1 star, standing still: a real officer walks up and arrests the player ----------------------------------------------
func _t_arrest() -> void:
	_trace = true
	PoliceOfficer.arrest_enabled = true
	wanted.bust_quiet_time = 2.0
	await _put_player(_street_pos())
	player.invulnerable = true
	_running = true
	var b0 := _busted_count
	wanted.set_level(1)
	var t := await _wait(150.0, func(): return _busted_count > b0)
	print("LIVE arrest: busted=%d after %.1f s, level=%d changes=%s" % [_busted_count - b0, t, wanted.level, str(_changes)])
	_check("arrest_player_busted_by_real_officers", _busted_count > b0, "after %.1f s" % t)
	await _frames(30)
	_check("arrest_wanted_cleared_or_frozen", wanted.level == 0 or wanted._busted, "level=%d" % wanted.level)
	var t_free := await _wait(12.0, func(): return wanted.level == 0 and not wanted._busted)
	_check("arrest_released_and_wanted_cleared", wanted.level == 0 and not wanted._busted, "level=%d busted=%s after %.1f s" % [wanted.level, str(wanted._busted), t_free])
	PoliceOfficer.arrest_enabled = false
	wanted.bust_quiet_time = 1e9


# ---- scenario 5: REAL pedestrians (Peds agent) witness a crime: phone call -> Events.crime_reported -> heat (needs peds: no --no-peds) ----------
func _nearest_ped(maxd: float) -> Node3D:
	var best: Node3D = null
	var bd := maxd
	for n in get_tree().get_nodes_in_group(GC.G_PED):
		if is_instance_valid(n) and n is Node3D and n.get("is_dead") != true:
			var d := Util.dist_xz((n as Node3D).global_position, player.global_position)
			if d < bd:
				bd = d
				best = n
	return best


func _t_witness_real() -> void:
	var peds: Variant = Game.sys(&"peds")
	if peds == null or not peds.has_method("get_witnesses") or not bool(Game.cheats.get("pedestrians", true)):
		print("TEST witness_real SKIP (PedManager.get_witnesses not available or peds disabled)")
		return
	await _put_player(_street_pos())
	_running = true
	var ped: Node3D = null
	var waited := 0.0
	while ped == null and waited < 40.0:
		await _frames(30)
		waited += 0.5
		ped = _nearest_ped(32.0)
	_check("witness_real_pedestrian_nearby", ped != null, "waited %.0f s" % waited)
	if ped == null:
		return
	var reported := [0]
	var cb := func(_c, _p, _q): reported[0] += 1
	Events.crime_reported.connect(cb)
	var pos := ped.global_position
	var near: Variant = peds.get_witnesses(pos, player, 45.0)
	_check("witness_real_get_witnesses_returns_array", near is Array, str(near.size() if near is Array else -1))
	wanted.search_area_rule = true
	var ok := wanted.report_crime(GC.CRIME_ASSAULT, pos, player)
	_check("witness_real_crime_accepted", ok)
	_check("witness_real_no_instant_heat", wanted.level == 0, "level=%d heat=%.1f incidents=%d" % [wanted.level, wanted.heat, wanted._incidents.size()])
	var t := await _wait(14.0, func(): return reported[0] > 0)
	print("LIVE witness_real: crime_reported after %.1f s (witnesses=%d) level=%d heat=%.1f state=%s" % [t, (near.size() if near is Array else 0), wanted.level, wanted.heat, String(wanted.state)])
	if near is Array and near.size() > 0:
		_check("witness_real_report_arrives_after_phone_call", reported[0] > 0 and t >= 3.0, "after %.1f s" % t)
		_check("witness_real_heat_applied", wanted.level >= 1 and wanted.state == &"search", "level=%d state=%s" % [wanted.level, String(wanted.state)])
	else:
		_check("witness_real_no_witness_no_heat", wanted.level == 0, "level=%d" % wanted.level)
	await _wait(4.0)      # the other witnesses finish their calls too: one crime is counted once
	_check("witness_real_many_reports_count_once", wanted.heat < 16.0 and wanted.level <= 2, "reports=%d heat=%.1f level=%d" % [reported[0], wanted.heat, wanted.level])
	Events.crime_reported.disconnect(cb)
	# a witness that dies before the call ends makes no report
	wanted.clear()
	wanted._last_crime_t.clear()
	await _frames(10)
	var ped2 := _nearest_ped(32.0)
	if ped2 != null:
		reported[0] = 0
		var cb2 := func(_c, _p, _q): reported[0] += 1
		Events.crime_reported.connect(cb2)
		var w2: Variant = peds.get_witnesses(ped2.global_position, player, 45.0)
		var n_w: int = w2.size() if w2 is Array else 0
		wanted.report_crime(GC.CRIME_ASSAULT, ped2.global_position, player)
		await _frames(20)
		# every witness dies (killed by "nobody": not a crime of the player)
		for w in get_tree().get_nodes_in_group(GC.G_PED):
			if is_instance_valid(w) and w is Node3D and Util.dist_xz((w as Node3D).global_position, ped2.global_position) < 70.0 and w.has_method("apply_damage"):
				w.apply_damage(9999.0, {"source": null, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": (w as Node3D).global_position})
		await _wait(12.0)
		print("LIVE witness_real_dead: witnesses=%d reports=%d level=%d" % [n_w, reported[0], wanted.level])
		_check("witness_real_dead_witness_no_report", reported[0] == 0 or wanted.level == 0, "witnesses=%d reports=%d level=%d" % [n_w, reported[0], wanted.level])
		Events.crime_reported.disconnect(cb2)
	wanted.search_area_rule = true
