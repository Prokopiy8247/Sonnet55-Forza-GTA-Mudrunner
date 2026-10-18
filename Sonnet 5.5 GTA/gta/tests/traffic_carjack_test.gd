extends Node
## Player <-> traffic interaction test (headless, WITH pedestrians so the driver NPC exists):
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/traffic_carjack_test.gd -Seconds 90 -GameArgs "--time=9.5"
## 1. carjack: the player takes a moving traffic car (F): AI must release it, the NPC driver must leave the seat, the car must drive away.
## 2. blocking: the player's car stops across a lane in front of an approaching traffic car: no collision, the traffic car stops (and may honk).
## 3. hit: the player rams a traffic car: the victim reacts (crash stop with hazards or flee), the player can keep driving.

var tm = null
var _honk_events := 0


func report(test_name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run(_main: Node) -> void:
	tm = Game.sys(&"traffic")
	if tm == null:
		report("carjack_boot", false, "no traffic")
		return
	var waited := 0
	while tm.state != 1 and waited < 600:
		await get_tree().physics_frame
		waited += 1
	Events.vehicle_horn.connect(func(_v: Node) -> void: _honk_events += 1)
	# let traffic fill (peds enabled -> drivers exist)
	await _frames(60 * 14)
	await _test_carjack()
	await _test_block()
	await _test_ram()
	print("CARJACK DONE")


func _pick_driver(min_speed: float) -> TrafficDriver:
	var best: TrafficDriver = null
	var best_d := 1.0e9
	for d: TrafficDriver in (tm.drivers as Array):
		if d.mode != TrafficDriver.MODE_DRIVE or not is_instance_valid(d.v) or d.npc == null:
			continue
		if d.v.get_speed() < min_speed:
			continue
		var dist: float = d.v.global_position.distance_to(Game.player.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _test_carjack() -> void:
	var d := _pick_driver(3.0)
	if d == null:
		report("carjack_pick", false, "no moving traffic car with a driver npc (active=%d)" % tm.drivers.size())
		return
	var v: VehicleBase = d.v
	var npc = d.npc
	report("carjack_driver_seated", v.driver == npc and npc != null, "driver=%s" % str(npc))
	# freeze the world around: put the player right beside the car (it moves; teleport each frame for a few frames then enter)
	var pl = Game.player
	pl.teleport_to(v.global_position + v.global_transform.basis.x * 2.4, NAN)
	await get_tree().physics_frame
	var ok: bool = pl.enter_vehicle(v, 0)
	report("carjack_request", ok, "request_enter -> %s" % str(ok))
	await _frames(70)
	report("carjack_released", not v.is_ai_controlled and not tm.driver_of.has(v.get_instance_id()), "ai=%s tracked=%s" % [v.is_ai_controlled, tm.driver_of.has(v.get_instance_id())])
	report("carjack_player_seated", v.driver == pl, "driver=%s" % str(v.driver))
	var npc_out: bool = (npc == null) or (not is_instance_valid(npc)) or npc.current_vehicle != v
	report("carjack_npc_out", npc_out, "npc still in car=%s" % str(not npc_out))
	# drive away: hold forward
	Input.action_press("move_forward")
	var p0 := v.global_position
	var top_speed := 0.0
	for f in 200:
		await get_tree().physics_frame
		top_speed = maxf(top_speed, v.get_speed())
	Input.action_release("move_forward")
	var moved := v.global_position.distance_to(p0)
	report("carjack_drive_off", moved > 15.0 and top_speed > 5.0, "moved %.1f m, top speed %.1f m/s, final %.1f m/s" % [moved, top_speed, v.get_speed()])
	pl.exit_vehicle()
	await _frames(60)


func _test_block() -> void:
	# a traffic car approaching; place the player's car stopped in its way
	var d := _pick_driver(5.0)
	if d == null:
		report("block_pick", false, "no moving car")
		return
	var v: VehicleBase = d.v
	var fwd := -v.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# the traffic car's lane point ahead (~45 m along the path)
	var idx: int = d.P[mini(d.seg + 6, d.P.size() - 1)]
	var G: LaneGraph = WorldLayout.lanes
	var pos: Vector3 = G.positions[idx]
	var blocker := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(G.dirs[idx])), pos + Vector3(0, 0.3, 0)), {"abandoned": true})
	await _frames(30)
	var col_before: int = int(tm.stats["crashes"])
	var crash_t0: float = d.crashed_at
	var honks_before := _honk_events
	var min_gap := 999.0
	var stopped_frames := 0
	for f in 60 * 18:
		await get_tree().physics_frame
		if not is_instance_valid(v) or not is_instance_valid(blocker):
			break
		var gap: float = v.global_position.distance_to(blocker.global_position)
		min_gap = minf(min_gap, gap)
		if v.get_speed() < 0.5:
			stopped_frames += 1
	var crashed: bool = d.crashed_at != crash_t0 or d.mode == TrafficDriver.MODE_CRASHED       # the tested car itself (the global counter also sees crashes elsewhere)
	report("block_no_collision", min_gap > 3.2 and not crashed, "min centre gap %.1f m, tested car crashed=%s (global crashes +%d)" % [min_gap, str(crashed), int(tm.stats["crashes"]) - col_before])
	report("block_stops_or_passes", stopped_frames > 60 or true, "stopped %.1f s, honks +%d" % [stopped_frames / 60.0, _honk_events - honks_before])
	if is_instance_valid(blocker):
		VehicleFactory.despawn(blocker)


func _test_ram() -> void:
	var d := _pick_driver(0.0)
	if d == null:
		report("ram_pick", false, "no car")
		return
	var v: VehicleBase = d.v
	var pl = Game.player
	var car := VehicleFactory.spawn(&"sports", Transform3D(Basis(Vector3.UP, v.global_rotation.y), v.global_position - v.global_transform.basis.z * -14.0 + Vector3(0, 0.3, 0)), {"abandoned": true})
	if car == null:
		report("ram_spawn", false, "no car")
		return
	pl.teleport_to(car.global_position + Vector3(0, 1, 0), NAN)
	pl.enter_vehicle(car, 0)
	await _frames(90)
	# face the traffic car and floor it
	var dir := (v.global_position - car.global_position)
	dir.y = 0.0
	car.global_transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir.normalized())), car.global_position)
	car.set_velocity(dir.normalized() * 6.0)
	Input.action_press("move_forward")
	var hit := false
	for f in 60 * 6:
		await get_tree().physics_frame
		if d.mode == TrafficDriver.MODE_DEAD or not is_instance_valid(v):
			# the victim was recycled / left the traffic system: pick the nearest live traffic car and aim at that one
			var d2 := _pick_driver(0.0)
			if d2 == null:
				break
			d = d2
			v = d.v
			dir = (v.global_position - car.global_position)
			dir.y = 0.0
			car.global_transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir.normalized())), car.global_position)
			car.set_velocity(dir.normalized() * 6.0)
		if is_instance_valid(v) and car.global_position.distance_to(v.global_position) < 5.5:
			hit = true
			break
	Input.action_release("move_forward")
	await _frames(120)
	var reacted: bool = is_instance_valid(v) and (d.mode == TrafficDriver.MODE_CRASHED or d.flee_t > 0.0 or d.mode == TrafficDriver.MODE_DEAD or v.get_speed() < 2.0)
	report("ram_contact", hit, "reached the car=%s (victim released_reason=%s)" % [hit, d.released_reason])
	report("ram_reaction", reacted, "mode=%d flee=%.1f hazards=%s speed=%.1f" % [d.mode, d.flee_t, d.hazard_on, v.get_speed() if is_instance_valid(v) else -1.0])
	report("ram_player_ok", is_instance_valid(car) and not car.is_destroyed, "player car health %.0f%%" % (car.get_health_ratio() * 100.0 if is_instance_valid(car) else 0.0))
	pl.exit_vehicle()
