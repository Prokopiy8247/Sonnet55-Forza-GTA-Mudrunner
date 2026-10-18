extends Node
## Signal scenario test: one traffic car approaches a signalised stop line at full speed, the light turns red while it is still far
## away; the car must stop before the line (no red running), wait, and go again on green.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/traffic_signal_test.gd -Seconds 120 -GameArgs "--no-peds --no-traffic --time=9.5 --sig=8"
## Options: --sig=N (signal id), --trace (per-update trace of the approach), --probe (only list the lane points of the signal)

var tm = null


func _arg(name: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + name + "="):
			return s.substr(name.length() + 3)
		if s == "--" + name:
			return "true"
	return default_value


func report(test_name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func run(_main: Node) -> void:
	tm = Game.sys(&"traffic")
	if tm == null:
		report("signal_boot", false, "no traffic")
		return
	var waited := 0
	while tm.state != 1 and waited < 600:
		await get_tree().physics_frame
		waited += 1
	Game.cheats["traffic"] = true
	tm.spawn_enabled = false
	if _arg("list") != "":
		for i in WorldLayout.signals.size():
			var sd: Dictionary = WorldLayout.signals[i]
			print("SIGLIST %d pos=%s cycle=%.0f yellow=%.0f offset=%.1f" % [i, str((sd["pos"] as Vector3).snapped(Vector3.ONE)), float(sd.get("cycle", 0)), float(sd.get("yellow", 0)), float(sd.get("offset", 0))])
		return
	var sig := int(_arg("sig", "8"))
	var G: LaneGraph = WorldLayout.lanes
	var stops: Array[int] = []
	for i in G.size():
		if G.signal_id[i] == sig:
			stops.append(i)
	print("SIGTEST signal %d has %d stop points" % [sig, stops.size()])
	for i in stops:
		print("  stop idx=%d pos=%s dir=%s phase=%d lim=%.1f kind=%d" % [i, str(G.positions[i].snapped(Vector3(0.1, 0.1, 0.1))), str(G.dirs[i].snapped(Vector3(0.01, 0.01, 0.01))), G.signal_phase[i], G.speed_limit[i], G.kind[i]])
		var cur := i
		for k in 10:
			var pv: PackedInt32Array = G.prev[cur]
			if pv.is_empty():
				break
			cur = pv[0]
			print("      back %d idx=%d pos=%s lim=%.1f kind=%d sig=%d" % [k + 1, cur, str(G.positions[cur].snapped(Vector3(0.1, 0.1, 0.1))), G.speed_limit[cur], G.kind[cur], G.signal_id[cur]])
	if _arg("probe") != "" or stops.is_empty():
		return
	# park the player far away so the car is "tier 2 / unseen" like in the real runs? no: keep the player near so physics stays active
	var results := 0
	var nstops := int(_arg("nstops", "99"))
	for si in stops.slice(0, nstops):
		var flips: Array = [0.3, 1.2, 2.2, 3.2, 4.2]
		if _arg("flip") != "":
			flips = [float(_arg("flip"))]
		for flip_in: float in flips:
			await _run_approach(si, results, flip_in)
			results += 1


func _run_approach(stop_idx: int, n: int, flip_in: float) -> void:
	var G: LaneGraph = WorldLayout.lanes
	# walk back ~120 m along prev to find the spawn point
	var cur := stop_idx
	var dist := 0.0
	var back_list: Array[int] = [stop_idx]
	while dist < 40.0:
		var pv: PackedInt32Array = G.prev[cur]
		if pv.is_empty():
			break
		var nx := pv[0]
		dist += G.positions[nx].distance_to(G.positions[cur])
		cur = nx
		back_list.append(cur)
		if G.kind[cur] == LaneGraph.KIND_CONNECTOR or G.signal_id[cur] >= 0:
			print("SIGTEST skip stop %d: another junction within 40 m upstream" % stop_idx)
			return
	back_list.reverse()
	var spawn_pos: Vector3 = G.positions[cur]
	Game.player.teleport_to(G.positions[stop_idx] + Vector3(6, 1, 10), NAN)
	await get_tree().physics_frame
	var ph0: int = G.signal_phase[stop_idx]
	var best0: float = tm.clock
	for k0 in 2000:
		var t0: float = tm.clock + float(k0) * 0.05
		if WorldLayout.signal_state(G.signal_id[stop_idx], ph0, t0) == 0 and WorldLayout.signal_state(G.signal_id[stop_idx], ph0, t0 + flip_in) == 1 and WorldLayout.signal_state(G.signal_id[stop_idx], ph0, t0 + flip_in - 0.1) == 0:
			best0 = t0
			break
	tm.clock = best0
	var v: VehicleBase = null
	var tries := 0
	while v == null and tries < 30:
		v = tm.spawn_at_lane(cur, &"sedan")
		tries += 1
		if v == null:
			await get_tree().physics_frame
	if v == null:
		report("signal_spawn_%d" % n, false, "spawn failed at lane %d" % cur)
		return
	var d: TrafficDriver = tm.get_driver(v)
	d.P = PackedInt32Array(back_list)     # force the route over the stop line
	d.seg = 0
	d._extend_path()
	var ph: int = G.signal_phase[stop_idx]
	# force the signal phase: put the clock so that the light turns red ~ 4 s from now (the car needs ~7 s to arrive)
	var sdef: Dictionary = WorldLayout.signals[G.signal_id[stop_idx]]
	var cycle: float = sdef.get("cycle", 24.0)
	var yellow: float = sdef.get("yellow", 2.0)
	var half := cycle * 0.5
	# find a clock value t0 such that signal_state flips green->yellow in 3 s
	var best_t: float = tm.clock
	for k in 2000:
		var t: float = tm.clock + float(k) * 0.05
		if WorldLayout.signal_state(G.signal_id[stop_idx], ph, t) == 0 and WorldLayout.signal_state(G.signal_id[stop_idx], ph, t + flip_in) == 1 and WorldLayout.signal_state(G.signal_id[stop_idx], ph, t + flip_in - 0.1) == 0:
			best_t = t
			break
	print("SIGTEST approach %d: flip (green->yellow) in %.1f s, spawn at %s (clock %.1f -> %.1f)" % [n, flip_in, str(spawn_pos.snapped(Vector3.ONE)), tm.clock, best_t])
	tm.clock = best_t
	d.last_update = tm.clock
	var crossed_state := -1
	var line: Vector3 = G.positions[stop_idx] + G.dirs[stop_idx] * 2.2
	var ddir: Vector3 = G.dirs[stop_idx]
	var min_s := 999.0
	var max_speed_past := 0.0
	var passed_t := -1.0
	var stopped_before := false
	var trace := _arg("trace") != ""
	for f in 60 * 40:
		await get_tree().physics_frame
		if not is_instance_valid(v) or d.mode == TrafficDriver.MODE_DEAD:
			break
		var fwd := -v.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var front := v.global_position + fwd * d.hl
		var s := (front.x - line.x) * ddir.x + (front.z - line.z) * ddir.z
		var st := WorldLayout.signal_state(G.signal_id[stop_idx], ph, tm.clock)
		if trace and f % 12 == 0:
			print("   f=%d s=%.1f spd=%.1f st=%d %s" % [f, s, v.get_speed(), st, d.debug_string()])
		if s < 0.0:
			min_s = minf(min_s, -s)
			if v.get_speed() < 0.3:
				stopped_before = true
		if s >= 0.0 and passed_t < 0.0:
			passed_t = tm.clock
			crossed_state = st
			max_speed_past = v.get_speed()
			var red_for := 0.0
			# how long has the light been red when we cross?
			for k in 400:
				if WorldLayout.signal_state(G.signal_id[stop_idx], ph, tm.clock - float(k) * 0.05) == 2:
					red_for = float(k) * 0.05
				else:
					break
			print("SIGTEST crossed the line: state=%d (2=red) red_for=%.1f s speed=%.1f" % [st, red_for, v.get_speed()])
			if st == 2 and red_for > 1.0:
				report("signal_no_red_run_%d" % n, false, "ran the red light (red for %.1f s) at %.1f m/s" % [red_for, v.get_speed()])
			else:
				report("signal_no_red_run_%d" % n, true, "crossed on state %d, red for %.1f s" % [st, red_for])
			break
		if stopped_before and st != 2 and s < 0.0 and f > 60 * 5:
			pass
	if passed_t < 0.0:
		report("signal_stops_%d" % n, stopped_before, "did not cross within 40 s, stopped=%s s=%.1f" % [str(stopped_before), min_s])
		# now wait for green, the car must go
		var go_ok := false
		for f2 in 60 * 40:
			await get_tree().physics_frame
			if not is_instance_valid(v):
				break
			var fwd2 := -v.global_transform.basis.z
			fwd2.y = 0.0
			var front2 := v.global_position + fwd2.normalized() * d.hl
			var s2 := (front2.x - line.x) * ddir.x + (front2.z - line.z) * ddir.z
			if s2 > 2.0:
				go_ok = true
				break
		report("signal_goes_on_green_%d" % n, go_ok, "proceeded after the light changed")
	tm.recycle_driver(d, "recycle")
	await get_tree().physics_frame
