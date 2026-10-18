extends Node
## Fixed-wing physics: take-off roll (< 190 m), climb, cruise, top speed, roll / pitch / yaw, stall + recovery, braking, nose-wheel
## steering, landing damage thresholds, crash.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/air_plane_test.gd -Seconds 200 -GameArgs "--no-vehicles --no-traffic --no-peds"

var T := VehicleTestUtil
var tree: SceneTree
var main_node: Node


func run(main: Node) -> String:
	tree = get_tree()
	main_node = main
	T.make_floor(main, 30000.0)
	Game.wetness = 0.0
	await T.frames(tree, 10)
	await _t_plane(&"plane_prop")
	await _t_plane(&"plane_jet")
	await _t_stall()
	await _t_crash()
	print("TEST SUMMARY passed=%d failed=%d" % [T.passed, T.failed])
	return "passed=%d failed=%d" % [T.passed, T.failed]


func _spawn(id: StringName, pos := Vector3(0, 0.1, 0), snap := true) -> PlaneVehicle:
	return T.spawn(id, pos, -90.0, {"ai": true, "engine_on": true, "abandoned": true, "snap_ground": snap}) as PlaneVehicle


func _in(v: VehicleBase, thr: float, pitch := 0.0, roll := 0.0, yaw := 0.0, brake := 0.0) -> void:
	v.input_throttle = thr
	v.input_pitch = pitch
	v.input_roll = roll
	v.input_yaw = yaw
	v.input_steer = yaw
	v.input_brake = brake


func _t_plane(id: StringName) -> void:
	var tag := String(id)
	var v := _spawn(id)
	T.report(tag + "_spawned", v != null and v is PlaneVehicle, "gears=%d seats=%d" % [v.gears.size() if v != null else -1, v.seats.size() if v != null else -1])
	if v == null:
		return
	var x0 := T.ORIGIN.x
	await T.frames(tree, 90)
	T.report(tag + "_rests_on_gear", v.grounded_count == 3 and v.global_position.y < 0.35 and v.linear_velocity.length() < 0.3, "grounded=%d y=%.2f v=%.2f" % [v.grounded_count, v.global_position.y, v.linear_velocity.length()])
	T.report(tag + "_tail_clearance_known", v.tail_clear > deg_to_rad(4.0) and v.tail_clear < deg_to_rad(20.0), "tail strike angle %.1f deg" % rad_to_deg(v.tail_clear))
	T.report(tag + "_pilot_seat_first", v.seats.size() >= 1 and v.seats[0]["name"] == &"driver", "seat0=%s" % (v.seats[0]["name"] if v.seats.size() > 0 else "-"))
	# brakes hold at idle
	await T.frames(tree, 60)
	T.report(tag + "_holds_at_idle", absf(v.global_position.x - x0) < 0.5, "moved %.2f m at idle for 1 s" % (v.global_position.x - x0))
	# ---- take-off roll ---------------------------------------------------------------------------------------------------------------
	var vr: float = v.stall_speed * 1.12
	var lift_x := -1.0
	var rotated := false
	var t := 0.0
	var vmax := 0.0
	for i in 60 * 40:
		var spd := v.linear_velocity.length()
		var pitch := 0.0
		if spd > vr and not rotated:
			rotated = true
		if rotated and lift_x < 0.0:
			pitch = 0.55
		_in(v, 1.0, pitch)
		await tree.physics_frame
		t += 1.0 / 60.0
		vmax = maxf(vmax, spd)
		if lift_x < 0.0 and v.grounded_count == 0 and i > 30:
			lift_x = v.global_position.x - x0
			break
	T.report(tag + "_takeoff_distance", lift_x > 0.0 and lift_x < 190.0, "airborne after %.0f m / %.1f s (stall %.0f km/h, rotated at %.0f km/h)" % [lift_x, t, v.stall_speed * 3.6, vr * 3.6])
	if lift_x < 0.0:
		T.remove_all(tree)
		return
	# ---- climb ---------------------------------------------------------------------------------------------------------------------
	var clim_t := 0.0
	for i in 60 * 12:
		_in(v, 1.0, 0.0)
		if v.global_position.y < 30.0 and v.linear_velocity.length() > vr * 1.12:
			v.input_pitch = 0.18
		await tree.physics_frame
	var alt := v.global_position.y
	T.report(tag + "_climbs_out", alt > 30.0 and v.linear_velocity.length() > v.stall_speed * 1.05 and v.grounded_count == 0, "altitude %.0f m, speed %.0f km/h after 12 s" % [alt, v.linear_velocity.length() * 3.6])
	# ---- top speed in level flight -----------------------------------------------------------------------------------------------------
	var top := 0.0
	var y_start := v.global_position.y
	for i in 60 * 40:
		_in(v, 1.0, 0.0)
		# hold altitude by hand around the start altitude
		var dy := y_start - v.global_position.y
		v.input_pitch = clampf(dy * 0.04 - v.linear_velocity.y * 0.08, -0.3, 0.3)
		await tree.physics_frame
		top = maxf(top, v.linear_velocity.length())
	var want_kmh := float(v.def.get("top_speed_kmh", 260.0))
	T.report(tag + "_top_speed", top * 3.6 > want_kmh * 0.82 and top * 3.6 < want_kmh * 1.18, "top %.0f km/h (def %.0f)" % [top * 3.6, want_kmh])
	# ---- stick released: stays flying level ---------------------------------------------------------------------------------------------
	_in(v, 0.7)
	var y1 := v.global_position.y
	for i in 60 * 8:
		_in(v, 0.7)
		await tree.physics_frame
	var y2 := v.global_position.y
	var bank_deg := rad_to_deg(AirCommon.bank_of(v.global_transform.basis))
	# a gentle phugoid is fine: the path angle must be small after 8 s (< 2.6 deg) and the bank level
	var path_deg := rad_to_deg(atan2(v.linear_velocity.y, Vector2(v.linear_velocity.x, v.linear_velocity.z).length()))
	T.report(tag + "_neutral_stick_flies_level", absf(path_deg) < 2.6 and absf(y2 - y1) < maxf(45.0, 0.6 * v.linear_velocity.length()) and absf(bank_deg) < 8.0, "dy %.1f m over 8 s, path %.1f deg, bank %.1f deg, speed %.0f km/h" % [y2 - y1, path_deg, bank_deg, v.linear_velocity.length() * 3.6])
	# ---- roll ----------------------------------------------------------------------------------------------------------------------------------
	var max_bank := 0.0
	for i in 60 * 2:
		_in(v, 0.7, 0.0, 1.0)
		await tree.physics_frame
		max_bank = maxf(max_bank, absf(rad_to_deg(AirCommon.bank_of(v.global_transform.basis))))
	T.report(tag + "_roll_authority", max_bank > 60.0, "banked %.0f deg after 2 s of full roll" % max_bank)
	# release: auto-level
	for i in 60 * 6:
		_in(v, 0.7)
		await tree.physics_frame
	bank_deg = rad_to_deg(AirCommon.bank_of(v.global_transform.basis))
	T.report(tag + "_auto_level", absf(bank_deg) < 12.0, "bank %.1f deg 6 s after release" % bank_deg)
	# ---- turn: banked turn changes heading ---------------------------------------------------------------------------------------------
	var h0 := Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	var y_turn := v.global_position.y
	# coordinated turn rate g*tan(bank)/V, accept half of it over the 6 s (the roll-in and the settling take time)
	var need_deg := clampf(0.5 * rad_to_deg(9.81 * tan(0.7 * v.bank_lim) / maxf(v.linear_velocity.length(), 30.0)) * 6.0, 8.0, 40.0)
	for i in 60 * 6:
		_in(v, 0.8, 0.0, 0.7)         # 0.7 stick = hold ~40 deg of bank (full stick for > 0.8 s at the limit starts a barrel roll)
		await tree.physics_frame
	var h1 :=Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	T.report(tag + "_banked_turn", absf(rad_to_deg(wrapf(h1 - h0, -PI, PI))) > need_deg and absf(v.global_position.y - y_turn) < maxf(60.0, 0.45 * v.linear_velocity.length()), "heading changed %.0f deg in 6 s (need %.0f), altitude change %.0f m, bank %.0f deg" % [rad_to_deg(wrapf(h1 - h0, -PI, PI)), need_deg, v.global_position.y - y_turn, rad_to_deg(AirCommon.bank_of(v.global_transform.basis))])
	# ---- pitch ----------------------------------------------------------------------------------------------------------------------------------
	for i in 60 * 5:
		_in(v, 0.8)
		await tree.physics_frame
	var p0 := AirCommon.pitch_of(v.global_transform.basis)
	var max_p := -PI
	for i in 60 * 2:
		_in(v, 1.0, 1.0)
		await tree.physics_frame
		max_p = maxf(max_p, AirCommon.pitch_of(v.global_transform.basis))
	T.report(tag + "_pitch_up", rad_to_deg(max_p - p0) > 20.0, "pitch rose %.0f deg in 2 s of back-stick (p0 %.0f, max %.0f, speed %.0f km/h, alt %.0f, destroyed=%s)" % [rad_to_deg(max_p - p0), rad_to_deg(p0), rad_to_deg(max_p), v.linear_velocity.length() * 3.6, v.global_position.y, v.is_destroyed])
	T.remove_all(tree)
	await T.frames(tree, 3)
	# ---- ground handling: brakes + nose-wheel steering ----------------------------------------------------------------------------------------
	var g := _spawn(id, Vector3(0, 0.1, 0))
	await T.frames(tree, 90)
	var gx := g.global_position.x
	for i in 60 * 12:
		_in(g, 0.6)
		await tree.physics_frame
		if g.linear_velocity.length() > 20.0:
			break
	var sp0 := g.linear_velocity.length()
	var xs := g.global_position.x
	for i in 60 * 12:
		_in(g, 0.0, 0.0, 0.0, 0.0, 1.0)
		await tree.physics_frame
		if g.linear_velocity.length() < 0.5:
			break
	var stop_d := g.global_position.x - xs
	T.report(tag + "_brakes", g.linear_velocity.length() < 1.0 and stop_d < 90.0, "from %.1f m/s stopped in %.0f m" % [sp0, stop_d])
	# steering at taxi speed
	var yaw0 := g.global_transform.basis.get_euler().y
	for i in 60 * 6:
		_in(g, 0.35, 0.0, 0.0, 1.0)
		await tree.physics_frame
		if g.linear_velocity.length() > 9.0:
			g.input_throttle = 0.0
	var yaw1 := g.global_transform.basis.get_euler().y
	T.report(tag + "_nosewheel_steering", absf(rad_to_deg(wrapf(yaw1 - yaw0, -PI, PI))) > 20.0, "turned %.0f deg while taxiing right, speed %.1f m/s" % [rad_to_deg(wrapf(yaw1 - yaw0, -PI, PI)), g.linear_velocity.length()])
	T.remove_all(tree)
	await T.frames(tree, 3)
	# ---- arcade take-off: throttle only, stick neutral -> rotates and lifts off by itself within the 220 m runway ----------------------------------
	var tk := _spawn(id, Vector3(0, 0.1, 0))
	await T.frames(tree, 90)
	var tx := tk.global_position.x
	var lifted_d := -1.0
	for i in 60 * 30:
		_in(tk, 1.0)
		await tree.physics_frame
		if tk.grounded_count == 0 and i > 30:
			lifted_d = tk.global_position.x - tx
			break
	var climb_ok := false
	if lifted_d > 0.0:
		for i in 60 * 3:
			_in(tk, 1.0)
			await tree.physics_frame
		climb_ok = tk.global_position.y > 2.0 and not tk.is_destroyed
	T.report(tag + "_takeoff_neutral_stick", lifted_d > 0.0 and lifted_d < 160.0 and climb_ok, "lifted after %.0f m with the stick neutral, y=%.1f m 3 s later" % [lifted_d, tk.global_position.y])
	T.remove_all(tree)
	await T.frames(tree, 3)
	# ---- landing damage thresholds -------------------------------------------------------------------------------------------------------------
	var res := {}
	for sink in [1.5, 4.5, 7.0, 13.0]:
		var p := _spawn(id, Vector3(0, 0.1, 0))
		await T.frames(tree, 30)
		var h := p.health
		p._on_touchdown(sink)
		res[sink] = [h - p.health, p.is_destroyed]
		T.remove_all(tree)
		await T.frames(tree, 3)
	T.report(tag + "_landing_soft_ok", res[1.5][0] < 1.0, "sink 1.5 -> damage %.0f" % res[1.5][0])
	T.report(tag + "_landing_hard", res[4.5][0] > 10.0 and res[7.0][0] > res[4.5][0] and not res[7.0][1], "sink 4.5 -> %.0f, 7.0 -> %.0f" % [res[4.5][0], res[7.0][0]])
	T.report(tag + "_landing_crash", res[13.0][1], "sink 13 -> destroyed=%s" % res[13.0][1])


func _t_stall() -> void:
	var v := _spawn(&"plane_prop", Vector3(0, 400, 0), false)
	var fwd := Vector3(1, 0, 0)
	v.set_velocity(fwd * 60.0)
	v.engine_on = true
	await T.frames(tree, 20)
	# pull up hard with the engine at idle until the nose is high and the speed collapses
	var stalled_seen := false
	var min_speed := 999.0
	for i in 60 * 25:
		_in(v, 0.0, 1.0 if i < 60 * 10 else 0.0)
		await tree.physics_frame
		if v.stalled > 0.6:
			stalled_seen = true
			if i > 60 * 6:
				break
		min_speed = minf(min_speed, v.linear_velocity.length())
	T.report("plane_stall_happens", stalled_seen, "stalled=%s min speed %.0f km/h (stall %.0f)" % [stalled_seen, min_speed * 3.6, v.stall_speed * 3.6])
	var pitch_at_stall := AirCommon.pitch_of(v.global_transform.basis)
	# recovery: nose down, full power
	var rec_t := -1.0
	for i in 60 * 25:
		_in(v, 1.0, -0.6 if v.stalled > 0.1 else 0.0)
		await tree.physics_frame
		if v.stalled < 0.05 and v.linear_velocity.length() > v.stall_speed * 1.2:
			rec_t = float(i) / 60.0
			break
	T.report("plane_stall_recovery", rec_t >= 0.0 and v.global_position.y > 150.0, "recovered after %.1f s at %.0f m, %.0f km/h (pitch at stall %.0f deg)" % [rec_t, v.global_position.y, v.linear_velocity.length() * 3.6, rad_to_deg(pitch_at_stall)])
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_crash() -> void:
	var v := _spawn(&"plane_prop", Vector3(0, 80, 0), false)
	v.assist = 0.0
	v.set_velocity(Vector3(40, -35, 0))
	v.look_at_from_position(v.global_position, v.global_position + Vector3(40, -35, 0))
	v.set_velocity(Vector3(40, -35, 0))
	var destroyed := false
	for i in 60 * 8:
		_in(v, 0.6)
		await tree.physics_frame
		if v.is_destroyed:
			destroyed = true
			break
	T.report("plane_dive_crash_explodes", destroyed, "destroyed=%s health %.0f" % [destroyed, v.health])
	T.remove_all(tree)
	await T.frames(tree, 3)
