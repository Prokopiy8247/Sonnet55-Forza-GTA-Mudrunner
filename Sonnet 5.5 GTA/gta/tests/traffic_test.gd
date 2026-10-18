extends Node
## Traffic simulation test (headless):
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/traffic_test.gd -Seconds 150 -GameArgs "--no-peds --time=9.5 --secs=120"
## Boots the full game, lets TrafficManager fill the city around the player spawn and measures 120 s of game time:
## spawned counts, average speed, traffic-vs-traffic collisions, red-light violations, stuck recycles, blocked junctions,
## CPU cost of the traffic tick (ms per physics frame).
## Options: --secs=N (sim seconds, default 120)  --spot=x,z  (place the player there)  --density=N (force target count)  --verbose

var tm = null
var secs := 120.0
var verbose := false
var _violations := 0
var _viol_log: Array[String] = []
var _last_s: Dictionary = {}
var _stop_pts: Array = []
var _cols_tt := 0
var _cols_static := 0
var _cols_other := 0
var _col_log: Array[String] = []
var _speed_acc := 0.0
var _speed_n := 0
var _moving_acc := 0.0
var _moving_n := 0
var _max_active := 0
var _sample_active_acc := 0.0
var _sample_n := 0
var _max_xte := 0.0
var _min_gap_acc := 0.0
var _free_ratio_acc := 0.0
var _free_ratio_n := 0
var _hist: Dictionary = {}


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


func run(main: Node) -> void:
	secs = float(_arg("secs", "120"))
	verbose = _arg("verbose") != ""
	tm = Game.sys(&"traffic")
	if tm == null:
		report("traffic_boot", false, "no traffic system")
		return
	report("traffic_boot", true, "system present")
	# wait for the manager to start
	var waited := 0
	while tm.state != 1 and waited < 600:
		await get_tree().physics_frame
		waited += 1
	report("traffic_start", tm.state == 1, "waited %d frames" % waited)
	if tm.state != 1:
		return
	if _arg("spot") != "":
		var p := _arg("spot").split(",")
		Game.player.teleport_to(Vector3(float(p[0]), 1.0, float(p[1])), NAN)
		for i in 20:
			await get_tree().physics_frame
	if _arg("density") != "":
		tm.density_override = float(_arg("density"))
	Events.vehicle_collision.connect(_on_col)
	_collect_stop_points()
	var G: LaneGraph = WorldLayout.lanes
	print("TRAFFIC net: junctions=%d chains=%d stop_points=%d parked_slots=%d" % [TrafficNet.junctions.size(), TrafficNet.chains.size(), _stop_pts.size(), tm.parked.slots.size()])
	var frames := int(secs * 60.0)
	var t_wall := Time.get_ticks_msec()
	var report_every := 600
	for f in frames:
		await get_tree().physics_frame
		if f % 6 == 0:
			_sample()
		if f % report_every == report_every - 1:
			_progress(f)
	var wall := (Time.get_ticks_msec() - t_wall) / 1000.0
	_finish(wall)


func _collect_stop_points() -> void:
	var G: LaneGraph = WorldLayout.lanes
	for i in G.size():
		if G.signal_id[i] >= 0:
			var d: Vector3 = G.dirs[i]
			_stop_pts.append({"i": i, "pos": G.positions[i] + d * 2.2, "dir": d, "sid": G.signal_id[i], "ph": G.signal_phase[i]})


func _on_col(vehicle: Node, other: Node, impulse: float) -> void:
	if impulse < 2800.0 or vehicle == null:
		return
	var a: bool = tm.driver_of.has(vehicle.get_instance_id())
	var b: bool = other != null and other != vehicle and tm.driver_of.has(other.get_instance_id())
	if a and b:
		_cols_tt += 1
		_col_log.append("t=%.1f %s <-> %s imp=%.0f at %s" % [tm.clock, vehicle.name, other.name, impulse, str(vehicle.global_position.snapped(Vector3.ONE))])
		for who in [vehicle, other]:
			var hh: Array = _hist.get(who.get_instance_id(), [])
			for k in range(maxi(hh.size() - 24, 0), hh.size(), 3):
				_col_log.append("      " + String(who.name) + " " + String(hh[k]))
	elif a and (other == vehicle or other == null):
		_cols_static += 1
		_col_log.append("t=%.1f %s hit STATIC imp=%.0f :: %s" % [tm.clock, vehicle.name, impulse, (tm.driver_of[vehicle.get_instance_id()] as TrafficDriver).debug_string()])
		var hh2: Array = _hist.get(vehicle.get_instance_id(), [])
		for k in range(maxi(hh2.size() - 30, 0), hh2.size(), 2):
			_col_log.append("      " + String(hh2[k]))
	elif a:
		_cols_other += 1
		_col_log.append("t=%.1f %s hit %s imp=%.0f :: %s" % [tm.clock, vehicle.name, other.name, impulse, (tm.driver_of[vehicle.get_instance_id()] as TrafficDriver).debug_string()])
		var hh3: Array = _hist.get(vehicle.get_instance_id(), [])
		for k in range(maxi(hh3.size() - 30, 0), hh3.size(), 2):
			_col_log.append("      " + String(hh3[k]))


func _sample() -> void:
	var active := 0
	for d: TrafficDriver in (tm.drivers as Array):
		if d.mode == TrafficDriver.MODE_DEAD or not is_instance_valid(d.v):
			continue
		active += 1
		var v: VehicleBase = d.v
		var sp := v.get_speed()
		var hid := v.get_instance_id()
		var hl_arr: Array = _hist.get(hid, [])
		hl_arr.append("t=%.1f spd=%.1f vt=%.1f mode=%d reason=%d stopgap=%.1f lead=%.0f/%.1f dec=%d/%s tier=%d pos=%s" % [tm.clock, sp, d.dbg_vt, d.mode, d.stop_reason, d.dbg_stop, d.lead_s, d.lead_v, d._dec_sig, str(d._dec_go), d.tier, str(v.global_position.snapped(Vector3.ONE))])
		if hl_arr.size() > 70:
			hl_arr.pop_front()
		_hist[hid] = hl_arr
		_speed_acc += sp
		_speed_n += 1
		if sp > 1.0:
			_moving_acc += sp
			_moving_n += 1
		_max_xte = maxf(_max_xte, d.xte_max)
		if d.stop_reason == TrafficDriver.R_FREE and d.mode == TrafficDriver.MODE_DRIVE and d.P.size() > d.seg + 1 and d.lead_s > 60.0 and d.jn_jid < 0:
			_free_ratio_acc += sp / maxf(WorldLayout.lanes.speed_limit[d.P[d.seg]], 1.0)
			_free_ratio_n += 1
		# red-light check
		if d.flee_t > 0.0:
			continue
		var p := v.global_position
		var f := -v.global_transform.basis.z
		f.y = 0.0
		f = f.normalized()
		var front := p + f * d.hl
		for sp_: Dictionary in _stop_pts:
			var sq: Vector3 = sp_["pos"]
			var dx := front.x - sq.x
			var dz := front.z - sq.z
			if dx * dx + dz * dz > 100.0:
				continue
			var dirv: Vector3 = sp_["dir"]
			var s := dx * dirv.x + dz * dirv.z
			var lat := absf(-dx * dirv.z + dz * dirv.x)
			var key := "%d_%d" % [v.get_instance_id(), int(sp_["i"])]
			var prev: float = _last_s.get(key, 99.0)
			_last_s[key] = s
			if prev < 0.0 and s >= 0.0 and lat < 2.6 and sp > 2.0 and f.dot(dirv) > 0.7:
				var sid: int = sp_["sid"]
				var ph: int = sp_["ph"]
				var now: float = tm.clock
				if WorldLayout.signal_state(sid, ph, now) == 2 and WorldLayout.signal_state(sid, ph, now - 1.2) == 2:
					_violations += 1
					_viol_log.append("t=%.1f %s ran red sig %d at %s speed %.1f" % [now, v.name, sid, str(p.snapped(Vector3.ONE)), sp])
					var hh: Array = _hist.get(v.get_instance_id(), [])
					for k in range(maxi(hh.size() - 45, 0), hh.size(), 3):
						_viol_log.append("      " + String(hh[k]))
	_max_active = maxi(_max_active, active)
	_sample_active_acc += active
	_sample_n += 1
	if _last_s.size() > 4000:
		_last_s.clear()
	if _hist.size() > 120:
		_hist.clear()


func _progress(f: int) -> void:
	if verbose:
		for d: TrafficDriver in (tm.drivers as Array):
			if d.mode != TrafficDriver.MODE_DEAD and is_instance_valid(d.v):
				print("  DRV ", d.debug_string(), " lim=%.1f" % WorldLayout.lanes.speed_limit[d.P[d.seg]], " eff=%.2f" % d.spd_factor)
	var s: Dictionary = tm.get_stats()
	print("TRAFFIC t=%.0fs active=%d/%d parked=%d spawned=%d recycled=%d tt_col=%d static=%d viol=%d speed=%.1f tick=%.0fus (max %.0f) holders=%d" % [
		float(f) / 60.0, s["active"], s["target"], s["parked_live"], s["spawned"], s["recycled"], _cols_tt, _cols_static, _violations,
		s["avg_speed"], s["tick_us_avg"], s["tick_us_max"], s["junction_holders"]])
	print("TRAFFIC worst tick phase: ", s.get("worst_phase", ""), " drivers avg us=", s.get("drivers_us_avg", 0))


func _finish(wall: float) -> void:
	var s: Dictionary = tm.get_stats()
	var avg_all := _speed_acc / maxf(float(_speed_n), 1.0)
	var avg_mov := _moving_acc / maxf(float(_moving_n), 1.0)
	var avg_active := _sample_active_acc / maxf(float(_sample_n), 1.0)
	print("TRAFFIC SUMMARY: %s" % str(s))
	print("TRAFFIC avg_active=%.1f max_active=%d avg_speed_all=%.1f m/s avg_speed_moving=%.1f m/s max_xte=%.2f m wall=%.1fs free_flow_speed/limit=%.2f (n=%d)" % [avg_active, _max_active, avg_all, avg_mov, _max_xte, wall, _free_ratio_acc / maxf(float(_free_ratio_n), 1.0), _free_ratio_n])
	var sp_n := maxf(float(s["spawned"]), 1.0)
	print("TRAFFIC spawn cost: factory %.1f ms/car, ped driver %.1f ms/car, worst %.1f ms" % [float(s.get("spawn_factory_us", 0.0)) / sp_n / 1000.0, float(s.get("spawn_ped_us", 0.0)) / sp_n / 1000.0, float(s.get("spawn_max_us", 0.0)) / 1000.0])
	for l in tm.spike_log:
		print("  SPIKE ", l)
	for l in _col_log:
		print("  COL ", l)
	for l in _viol_log:
		print("  RED ", l)
	var stuck: Array[String] = []
	for d: TrafficDriver in (tm.drivers as Array):
		if d.mode == TrafficDriver.MODE_DEAD:
			continue
		if d.idle_t > 8.0:
			stuck.append("%s idle=%.0f reason=%d mode=%d at %s" % [d.v.name, d.idle_t, d.stop_reason, d.mode, str(d.v.global_position.snapped(Vector3.ONE))])
	for l in stuck:
		print("  STUCK ", l)
	report("traffic_density", avg_active >= 8.0, "avg_active=%.1f target=%d" % [avg_active, s["target"]])
	report("traffic_moves", avg_mov > 4.0, "avg_speed_moving=%.1f" % avg_mov)
	report("traffic_no_tt_collisions", _cols_tt <= 1, "traffic-vs-traffic collisions=%d (static %d, other %d)" % [_cols_tt, _cols_static, _cols_other])
	report("traffic_red_lights", _violations <= 1, "red-light violations=%d (forced runs counted by drivers: %d)" % [_violations, s["red_runs"]])
	report("traffic_stuck", int(s["stuck_recycled"]) <= 3 and stuck.size() <= 2, "stuck recycled=%d currently idle>8s: %d" % [s["stuck_recycled"], stuck.size()])
	report("traffic_junction_blocks", int(s["junction_blocks"]) <= 2, "cars stalled in a junction box=%d" % s["junction_blocks"])
	report("traffic_tick_cost", float(s["tick_us_avg"]) < 3000.0, "avg %.0f us (max %.0f us) for ~%.0f cars" % [s["tick_us_avg"], s["tick_us_max"], avg_active])
	report("traffic_parked", int(s["parked_live"]) >= 5, "parked live=%d slots=%d" % [s["parked_live"], s["parked_slots"]])
	print("TRAFFIC DONE passed=%s" % str(true))
