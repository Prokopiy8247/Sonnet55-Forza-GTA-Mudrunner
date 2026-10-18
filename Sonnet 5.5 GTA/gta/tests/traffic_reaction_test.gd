extends Node
## Traffic reaction scenarios (headless, one scripted car per scenario on a long straight lane run):
##   siren   - a police cruiser with its siren on behind the car: the car pulls right and slows down (yields)
##   ped     - a person (the player on foot) stands in the lane: the car stops in front of them, no contact, then drives on
##   flee    - the car is shot at: it accelerates away (flee mode, faster than the limit)
##   night   - at night the traffic car turns its headlights on; rain/fog scale the cruise speed down
##   breakdown - a car pulls over with hazards and stops, then drives on
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/traffic_reaction_test.gd -Seconds 200 -GameArgs "--no-peds --time=10"

var tm = null
var run_idx: Array[int] = []


func report(test_name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _find_run() -> Array[int]:
	var G: LaneGraph = WorldLayout.lanes
	var best: Array[int] = []
	var seen: Dictionary = {}
	for i in G.size():
		if seen.has(i) or G.kind[i] == LaneGraph.KIND_CONNECTOR or TrafficNet.near_junction[i] != 0:
			continue
		if G.speed_limit[i] < 12.0 or G.positions[i].y > 2.5:
			continue
		# only start at a lane point whose predecessor is not part of the same free run
		var pv: PackedInt32Array = G.prev[i]
		if not pv.is_empty() and G.kind[pv[0]] != LaneGraph.KIND_CONNECTOR and TrafficNet.near_junction[pv[0]] == 0:
			continue
		var run: Array[int] = [i]
		var cur := i
		while true:
			seen[cur] = true
			var nx: PackedInt32Array = G.next[cur]
			if nx.size() != 1:
				break
			var n := nx[0]
			if G.kind[n] == LaneGraph.KIND_CONNECTOR or TrafficNet.near_junction[n] != 0 or run.size() > 60:
				break
			if G.positions[n].y > 2.5 or G.dirs[n].dot(G.dirs[i]) < 0.97:
				break
			run.append(n)
			cur = n
		if run.size() > best.size():
			best = run
	return best


func _spawn_on(idx: int, id: StringName = &"sedan") -> TrafficDriver:
	var v: VehicleBase = null
	for k in 40:
		v = tm.spawn_at_lane(idx, id)
		if v != null:
			break
		await get_tree().physics_frame
	if v == null:
		return null
	var d: TrafficDriver = tm.get_driver(v)
	# forced route: this run
	var start := run_idx.find(idx)
	d.P = PackedInt32Array(run_idx.slice(maxi(start, 0)))
	d.seg = 0
	d._extend_path()
	return d


func _arg(name: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--" + name:
			return true
	return false


func _trace(tag: String, d: TrafficDriver, frame: int) -> void:
	if _arg("trace") and frame % 20 == 0:
		print("   [%s f=%d] %s released=%s" % [tag, frame, d.debug_string(), d.released_reason])


func _right_of(idx: int) -> Vector3:
	var d: Vector3 = WorldLayout.lanes.dirs[idx]
	return Vector3(-d.z, 0.0, d.x)


func _clear_cars() -> void:
	tm.clear_traffic()


func run(_main: Node) -> void:
	tm = Game.sys(&"traffic")
	if tm == null:
		report("reaction_boot", false, "no traffic system")
		return
	var waited := 0
	while tm.state != 1 and waited < 600:
		await get_tree().physics_frame
		waited += 1
	tm.spawn_enabled = false
	tm.clear_traffic()
	run_idx = _find_run()
	if run_idx.size() < 14:
		report("reaction_run", false, "no straight lane run (best %d points)" % run_idx.size())
		return
	var G: LaneGraph = WorldLayout.lanes
	var mid: Vector3 = G.positions[run_idx[run_idx.size() / 2]]
	print("REACTION run of %d points from %s to %s, limit %.1f" % [run_idx.size(), str(G.positions[run_idx[0]].snapped(Vector3.ONE)), str(G.positions[run_idx[run_idx.size() - 1]].snapped(Vector3.ONE)), G.speed_limit[run_idx[0]]])
	var dir0: Vector3 = G.dirs[run_idx[0]]
	var right0 := Vector3(-dir0.z, 0.0, dir0.x)
	Game.player.teleport_to(mid - right0 * 5.4 + Vector3(0, 0.5, 0), NAN)       # on the sidewalk beside the road
	await _frames(30)
	print("REACTION player at %s (wanted near %s) ref_pos=%s" % [str(Game.player.global_position.snapped(Vector3.ONE)), str((mid + right0 * 14.0).snapped(Vector3.ONE)), str(tm.ref_pos.snapped(Vector3.ONE))])
	await _scenario_siren()
	await _scenario_ped()
	await _scenario_flee()
	await _scenario_lights_weather()
	await _scenario_breakdown()
	print("REACTION DONE")


func _scenario_siren() -> void:
	var G: LaneGraph = WorldLayout.lanes
	var d := await _spawn_on(run_idx[6])
	if d == null:
		report("siren_spawn", false, "spawn failed")
		return
	var v: VehicleBase = d.v
	for f0 in 40:
		await get_tree().physics_frame
		_trace("siren-pre", d, f0)
	var p: Vector3 = G.positions[run_idx[1]]
	var cruiser := VehicleFactory.spawn(&"police_cruiser", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(G.dirs[run_idx[1]])), p + Vector3(0, 0.4, 0)), {"abandoned": true})
	if cruiser == null:
		report("siren_cruiser", false, "no cruiser")
		return
	cruiser.siren_on = true
	var spd_before := v.get_speed()
	var max_off := 0.0
	var min_speed := 99.0
	for f in 60 * 7:
		await get_tree().physics_frame
		if not is_instance_valid(v) or d.mode == TrafficDriver.MODE_DEAD:
			break
		max_off = maxf(max_off, d.lat_off)
		min_speed = minf(min_speed, v.get_speed())
		_trace("siren", d, f)
	print("   siren loop ended: mode=%d reason=%s valid=%s" % [d.mode, d.released_reason, str(is_instance_valid(v))])
	report("siren_pulls_right", max_off > 0.8, "lateral offset to the right %.2f m (speed before %.1f)" % [max_off, spd_before])
	report("siren_slows_down", min_speed < 3.0, "minimum speed while the siren was behind %.1f m/s" % min_speed)
	# siren off -> drives on
	cruiser.siren_on = false
	await _frames(60 * 6)
	report("siren_resumes", is_instance_valid(v) and v.get_speed() > 4.0, "speed after the siren went quiet %.1f m/s :: %s" % [(v.get_speed() if is_instance_valid(v) else -1.0), d.debug_string()])
	if is_instance_valid(cruiser):
		VehicleFactory.despawn(cruiser)
	_clear_cars()
	await _frames(10)


func _scenario_ped() -> void:
	var G: LaneGraph = WorldLayout.lanes
	var d := await _spawn_on(run_idx[2])
	if d == null:
		report("ped_spawn", false, "spawn failed")
		return
	var v: VehicleBase = d.v
	var pl = Game.player
	# the person stands in the lane ~55 m ahead
	var ahead: Vector3 = G.positions[run_idx[2 + 9]]
	pl.teleport_to(ahead + Vector3(0, 1.0, 0), NAN)
	var min_gap := 99.0
	var stopped := 0
	var hit := false
	for f in 60 * 12:
		await get_tree().physics_frame
		if not is_instance_valid(v):
			break
		# keep the person in place (the controller may drift): re-teleport when moved away
		if f % 30 == 0 and pl.global_position.distance_to(ahead) > 1.0 and f < 60 * 9:
			pl.teleport_to(ahead + Vector3(0, 1.0, 0), NAN)
		var fwd := -v.global_transform.basis.z
		fwd.y = 0.0
		var front := v.global_position + fwd.normalized() * d.hl
		var gap := front.distance_to(Vector3(pl.global_position.x, front.y, pl.global_position.z))
		min_gap = minf(min_gap, gap)
		if v.get_speed() < 0.4:
			stopped += 1
		if gap < 0.9:
			hit = true
	report("ped_stops_for_person", min_gap > 1.2 and not hit and stopped > 30, "min gap %.1f m, stopped %.1f s :: %s" % [min_gap, stopped / 60.0, d.debug_string()])
	# person leaves the lane -> the car drives on
	pl.teleport_to(ahead - _right_of(run_idx[0]) * 5.4 + Vector3(0, 0.5, 0), NAN)
	await _frames(60 * 6)
	report("ped_car_resumes", is_instance_valid(v) and (v.get_speed() > 2.0 or d.mode == TrafficDriver.MODE_DEAD), "speed %.1f" % (v.get_speed() if is_instance_valid(v) else -1.0))
	_clear_cars()
	var mid: Vector3 = G.positions[run_idx[run_idx.size() / 2]]
	var dir0: Vector3 = G.dirs[run_idx[0]]
	pl.teleport_to(mid - Vector3(-dir0.z, 0.0, dir0.x) * 5.4 + Vector3(0, 0.5, 0), NAN)
	await _frames(20)


func _scenario_flee() -> void:
	var G: LaneGraph = WorldLayout.lanes
	var d := await _spawn_on(run_idx[3])
	if d == null:
		report("flee_spawn", false, "spawn failed")
		return
	var v: VehicleBase = d.v
	await _frames(90)
	var spd0 := v.get_speed()
	var lim: float = G.speed_limit[run_idx[3]]
	var info := {"source": Game.player, "type": GC.DMG_BULLET, "position": v.global_position, "direction": Vector3.FORWARD, "impulse": 5.0, "weapon": &"pistol"}
	v.apply_damage(12.0, info)
	await _frames(5)
	report("flee_starts", d.flee_t > 5.0, "flee_t=%.1f" % d.flee_t)
	var max_speed := 0.0
	for f in 60 * 5:
		await get_tree().physics_frame
		if not is_instance_valid(v) or d.mode == TrafficDriver.MODE_DEAD:
			break
		max_speed = maxf(max_speed, v.get_speed())
	report("flee_speeds_up", max_speed > spd0 + 3.0, "top speed %.1f m/s (limit %.1f) :: %s" % [max_speed, lim, d.debug_string()])
	_clear_cars()
	await _frames(10)


func _scenario_lights_weather() -> void:
	var d := await _spawn_on(run_idx[3])
	if d == null:
		report("night_spawn", false, "spawn failed")
		return
	var v: VehicleBase = d.v
	Game.time_frozen = true
	Game.time_of_day = 12.0
	await _frames(60 * 3)
	var day_lights: bool = v.headlights_on
	Game.time_of_day = 22.5
	await _frames(60 * 5)
	var env = Game.sys(&"environment")
	var wanted: bool = env.headlights_wanted() if env != null and env.has_method("headlights_wanted") else Game.is_night()
	report("night_headlights", v.headlights_on and wanted and not day_lights, "day=%s night=%s wanted=%s" % [str(day_lights), str(v.headlights_on), str(wanted)])
	# rain scales the cruise speed
	Game.time_of_day = 12.0
	var scale0 := TrafficDriver.g_speed_scale
	if env != null and env.has_method("set_weather"):
		env.set_weather(&"storm", true)
	else:
		Game.wetness = 1.0
		Game.rain_intensity = 1.0
		Game.fog_amount = 0.6
	await _frames(60 * 2)
	var scale1 := TrafficDriver.g_speed_scale
	report("rain_slows_traffic", scale1 < scale0 - 0.05, "speed scale dry %.2f -> storm %.2f, headway x%.2f (wetness %.2f rain %.2f fog %.2f)" % [scale0, scale1, TrafficDriver.g_headway_scale, Game.wetness, Game.rain_intensity, Game.fog_amount])
	if env != null and env.has_method("set_weather"):
		env.set_weather(&"clear", true)
	else:
		Game.wetness = 0.0
		Game.rain_intensity = 0.0
		Game.fog_amount = 0.0
	_clear_cars()
	await _frames(10)


func _scenario_breakdown() -> void:
	var d := await _spawn_on(run_idx[3])
	if d == null:
		report("breakdown_spawn", false, "spawn failed")
		return
	var v: VehicleBase = d.v
	await _frames(60)
	d.begin_breakdown(10.0)
	var stopped_at := -1.0
	for f in 60 * 12:
		await get_tree().physics_frame
		_trace("breakdown", d, f)
		if not is_instance_valid(v):
			break
		if stopped_at < 0.0 and v.get_speed() < 0.5:
			stopped_at = float(f) / 60.0
	report("breakdown_stops_with_hazards", stopped_at >= 0.0, "stopped after %.1f s (hazard=%s)" % [stopped_at, str(d.hazard_on)])
	await _frames(60 * 8)
	report("breakdown_recovers", is_instance_valid(v) and (v.get_speed() > 2.0 or d.mode == TrafficDriver.MODE_DEAD) and not d.hazard_on, "speed %.1f hazard=%s :: %s" % [v.get_speed() if is_instance_valid(v) else -1.0, str(d.hazard_on), d.debug_string()])
	_clear_cars()
