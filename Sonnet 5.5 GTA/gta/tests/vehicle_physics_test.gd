extends Node
## Headless drive tests on a flat floor: spawn-all, settle, acceleration / top speed, braking, turning, handbrake slide,
## ramp jump, flip recovery, collision damage -> explosion chain.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/vehicle_physics_test.gd -Seconds 400 -GameArgs "--no-vehicles --no-traffic --no-peds"

var T := VehicleTestUtil
var tree: SceneTree


func run(main: Node) -> String:
	tree = get_tree()
	T.make_floor(main)
	Game.wetness = 0.0
	await T.frames(tree, 10)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	var sections := only.split(",", false)
	var want := func(n: String) -> bool: return sections.is_empty() or sections.has(n)
	if want.call("spawn"):
		await _t_spawn_all(main)
	var accel_ids: Array = [&"compact", &"sedan", &"sports", &"muscle", &"suv", &"pickup", &"van", &"police_cruiser", &"taxi", &"ambulance", &"firetruck", &"truck", &"police_tactical", &"motorcycle", &"bicycle"]
	accel_ids = []
	for part in sections:
		if part.begins_with("accel:"):
			for p2 in part.substr(6).split("+"):
				accel_ids.append(StringName(p2))
	if sections.has("accel"):
		accel_ids = [&"compact", &"sedan", &"sports", &"muscle", &"suv", &"pickup", &"van", &"police_cruiser", &"taxi", &"ambulance", &"firetruck", &"truck", &"police_tactical", &"motorcycle", &"bicycle"]
	for id in accel_ids:
		await _t_accel(id)
	if want.call("brake"):
		for id in [&"sedan", &"sports", &"truck", &"suv"]:
			await _t_brake(id)
	if want.call("turn"):
		for id in [&"compact", &"sedan", &"sports", &"muscle", &"suv", &"truck", &"motorcycle"]:
			await _t_turn(id)
	if want.call("handbrake"):
		await _t_handbrake(&"sports")
		await _t_handbrake(&"muscle")
	if want.call("ramp"):
		await _t_ramp(main, &"sedan")
		await _t_ramp(main, &"suv")
	if want.call("flip"):
		await _t_flip(&"sedan")
	if want.call("crash"):
		await _t_crash(main)
	if want.call("reverse"):
		await _t_reverse(&"sedan")
	print("TEST SUMMARY passed=%d failed=%d" % [T.passed, T.failed])
	return "passed=%d failed=%d" % [T.passed, T.failed]


func _t_spawn_all(main: Node) -> void:
	# ground vehicles only (CarVehicle / BikeVehicle): the air / sea classes have their own tests (air_*_test.gd, boat_test.gd)
	var ids: Array = VehicleDefs.implemented_ids().filter(func(i): var c: StringName = VehicleDefs.get_def(i).get("class", GC.VC_CAR); return c != GC.VC_HELI and c != GC.VC_PLANE and c != GC.VC_BOAT)
	var xoff := 0.0
	var vs: Array[CarVehicle] = []
	for id in ids:
		var v := T.spawn(id, Vector3(xoff, 0.5, 0), 0.0, {"engine_on": false, "ai": false}) as CarVehicle
		T.report("spawn_%s" % id, v != null, "fallback=%s" % VehicleFactory.fallback_used.has(id))
		if v != null:
			vs.append(v as CarVehicle)
		xoff += 9.0
	await T.frames(tree, 150)
	for v in vs:
		var ok: bool = T.is_sane(v) and absf(v.global_position.y) < 0.35 and v.get("grounded_count") >= v.wheels.size() - 1
		T.report("settle_%s" % v.def_id, ok, "y=%.3f grounded=%d/%d asleep=%s" % [v.global_position.y, v.grounded_count, v.wheels.size(), v.sleeping])
	T.remove_all(tree)
	await T.frames(tree, 5)


func _drive_straight(v: VehicleBase, seconds: float, throttle := 1.0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var res := {"t100": -1.0, "top": 0.0, "dev": 0.0, "min_up": 1.0, "t": 0.0, "gears": 0, "rpm_max": 0.0, "dist_100": 0.0}
	var start := v.global_position
	var fwd := -v.global_transform.basis.z
	var last_gear := v.gear
	var n := int(seconds * 60.0)
	for i in n:
		v.input_throttle = throttle
		v.input_brake = 0.0
		await tree.physics_frame
		var kmh := v.get_speed_kmh()
		res["top"] = maxf(res["top"], kmh)
		if res["t100"] < 0.0 and kmh >= 100.0:
			res["t100"] = float(i) / 60.0
			res["dist_100"] = start.distance_to(v.global_position)
		res["min_up"] = minf(res["min_up"], v.global_transform.basis.y.y)
		res["rpm_max"] = maxf(res["rpm_max"], v.rpm)
		if v.gear != last_gear:
			res["gears"] += 1
			last_gear = v.gear
	var d := v.global_position - start
	res["dev"] = absf(d.dot(v.global_transform.basis.x))
	res["dist"] = d.length()
	return res


func _t_accel(id: StringName) -> void:
	var v := T.spawn(id, Vector3(0, 0.3, 0), 0.0) as CarVehicle
	if v == null:
		T.report("accel_%s" % id, false, "spawn failed")
		return
	await T.frames(tree, 40)
	var def: Dictionary = v.def
	var secs := 38.0 if id != &"bicycle" else 30.0
	var r := await _drive_straight(v, secs)
	var top_def := float(def["top_speed_kmh"])
	var top_ok: bool = r["top"] > top_def * 0.82 and r["top"] < top_def * 1.12
	var up_ok: bool = r["min_up"] > 0.8
	var dev_ok: bool = r["dev"] < maxf(r["dist"] * 0.06, 4.0)
	T.report("accel_%s" % id, top_ok and up_ok and dev_ok and T.is_sane(v), "top=%.0f km/h (def %.0f) 0-100=%.1fs shifts=%d rpm_max=%.0f lateral_dev=%.1fm dist=%.0fm min_up=%.2f" % [r["top"], top_def, r["t100"], r["gears"], r["rpm_max"], r["dev"], r["dist"], r["min_up"]])
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_brake(id: StringName) -> void:
	var v := T.spawn(id, Vector3(0, 0.3, 0), 0.0) as CarVehicle
	await T.frames(tree, 40)
	var speed := 27.8
	v.set_velocity(-v.global_transform.basis.z * speed)
	await T.frames(tree, 3)
	var start := v.global_position
	var t := 0.0
	for i in 600:
		v.input_throttle = 0.0
		v.input_brake = 1.0
		await tree.physics_frame
		t += 1.0 / 60.0
		if v.get_speed() < 0.4:
			break
	var dist := start.distance_to(v.global_position)
	var dev := absf((v.global_position - start).dot(v.global_transform.basis.x))
	var expected := speed * speed / (2.0 * float(v.def["brake"]))
	var ok: bool = dist > expected * 0.7 and dist < expected * 1.7 and dev < 3.0 and v.get_speed() < 1.0
	T.report("brake_%s" % id, ok, "100->0 in %.1fm / %.1fs (ideal %.1fm) lateral=%.1fm" % [dist, t, expected, dev])
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_turn(id: StringName) -> void:
	var v := T.spawn(id, Vector3(0, 0.3, 0), 0.0) as CarVehicle
	await T.frames(tree, 40)
	var target := 40.0 / 3.6 if id != &"truck" else 30.0 / 3.6
	v.set_velocity(-v.global_transform.basis.z * target)
	var min_up := 1.0
	var yaw_acc := 0.0
	var prev_yaw := v.global_transform.basis.get_euler().y
	var samples: Array[float] = []
	for i in 360:
		var sp := v.get_forward_speed()
		v.input_throttle = clampf((target - sp) * 0.5, 0.0, 1.0)
		v.input_brake = clampf((sp - target) * 0.4, 0.0, 1.0)
		v.input_steer = 1.0
		await tree.physics_frame
		min_up = minf(min_up, v.global_transform.basis.y.y)
		if i > 180:
			samples.append(absf(v.angular_velocity.y))
	var w_avg := 0.0
	for s in samples:
		w_avg += s
	w_avg /= maxf(float(samples.size()), 1.0)
	var radius := v.get_speed() / maxf(w_avg, 0.001)
	var ok: bool = min_up > (0.6 if id == &"motorcycle" else 0.85) and radius > 4.0 and radius < 60.0 and T.is_sane(v)
	T.report("turn_%s" % id, ok, "40km/h full lock radius=%.1fm speed=%.1f km/h min_up=%.2f" % [radius, v.get_speed_kmh(), min_up])
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_handbrake(id: StringName) -> void:
	var v := T.spawn(id, Vector3(0, 0.3, 0), 0.0) as CarVehicle
	await T.frames(tree, 40)
	var speed := 70.0 / 3.6
	v.set_velocity(-v.global_transform.basis.z * speed)
	var max_slip := 0.0
	var min_up := 1.0
	# 0.6s of steering + handbrake, then release and counter-steer
	for i in 36:
		v.input_throttle = 0.0
		v.input_steer = 0.8
		v.input_handbrake = true
		await tree.physics_frame
		max_slip = maxf(max_slip, absf(v.get_slip_angle()))
		min_up = minf(min_up, v.global_transform.basis.y.y)
	for i in 240:
		v.input_handbrake = false
		var sa: float = v.get_slip_angle()
		v.input_steer = clampf(-sa * 1.5, -1.0, 1.0) * -1.0
		v.input_throttle = 0.3
		await tree.physics_frame
		min_up = minf(min_up, v.global_transform.basis.y.y)
		max_slip = maxf(max_slip, absf(v.get_slip_angle()))
	var ok: bool = max_slip > deg_to_rad(18.0) and min_up > 0.7 and T.is_sane(v)
	T.report("handbrake_slide_%s" % id, ok, "peak slip angle=%.0f deg min_up=%.2f final slip=%.0f deg speed=%.0f km/h" % [rad_to_deg(max_slip), min_up, rad_to_deg(v.get_slip_angle()), v.get_speed_kmh()])
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_ramp(main: Node, id: StringName) -> void:
	# 12 degree ramp, 12 m long, then a flat gap
	var ang := 12.0
	var length := 12.0
	var h := sin(deg_to_rad(ang)) * length
	var ramp := T.make_box(main, Vector3(0, h * 0.5 - 0.15, -60.0), Vector3(8.0, 0.5, length), Vector3(ang, 0, 0), "Ramp")
	# ramp rises toward -Z (forward): rotate about X by +ang lifts the -Z end?  verify via top height at both ends
	var v := T.spawn(id, Vector3(0, 0.3, 20.0), 0.0) as CarVehicle
	await T.frames(tree, 30)
	var speed := 85.0 / 3.6
	v.set_velocity(-v.global_transform.basis.z * speed)
	var max_h := 0.0
	var airborne_frames := 0
	var min_up := 1.0
	var health0 := v.health
	var landed_ok := false
	var impacts: Array = []
	v.collided.connect(func(o, imp): impacts.append("%.1f@z%.0f" % [imp, v.global_position.z]))
	for i in 420:
		v.input_throttle = 0.5
		await tree.physics_frame
		max_h = maxf(max_h, v.global_position.y)
		if v.grounded_count == 0:
			airborne_frames += 1
		min_up = minf(min_up, v.global_transform.basis.y.y)
	landed_ok = v.global_transform.basis.y.y > 0.85 and v.global_position.y < 1.0
	var ok: bool = landed_ok and T.is_sane(v) and v.health > health0 * 0.6
	T.report("ramp_jump_%s" % id, ok, "apex=%.2fm air=%.2fs min_up=%.2f final_up=%.2f health=%.0f%% z=%.0f" % [max_h, airborne_frames / 60.0, min_up, v.global_transform.basis.y.y, 100.0 * v.health / v.max_health, v.global_position.z]  + " impacts=" + str(impacts))
	ramp.queue_free()
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_flip(id: StringName) -> void:
	var v := T.spawn(id, Vector3(0, 0.3, 0), 0.0) as CarVehicle
	await T.frames(tree, 30)
	v.global_transform = Transform3D(Basis(Vector3(0, 0, -1), PI), T.o(Vector3(0, 1.2, 0)))
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	await T.frames(tree, 60)
	var flipped_first := v.global_transform.basis.y.y < 0.3
	await T.frames(tree, 420)
	var ok: bool = flipped_first and v.global_transform.basis.y.y > 0.9
	T.report("flip_recovery_%s" % id, ok, "upside down first=%s, after 7s up=%.2f" % [flipped_first, v.global_transform.basis.y.y])
	VehicleFactory.despawn(v)
	await T.frames(tree, 3)


func _t_crash(main: Node) -> void:
	var wall := T.make_box(main, Vector3(0, 1.5, -80.0), Vector3(30.0, 3.0, 1.0), Vector3.ZERO, "Wall")
	var v := T.spawn(&"sedan", Vector3(0, 0.3, -20.0), 0.0) as CarVehicle
	var bystander := T.spawn(&"compact", Vector3(3.4, 0.3, -76.0), 0.0, {"ai": false, "engine_on": false})
	await T.frames(tree, 40)
	var destroyed_flag := [false]
	var exploded := [false]
	v.destroyed.connect(func(_k): destroyed_flag[0] = true)
	Events.explosion.connect(func(_p, _r, _s): exploded[0] = true)
	var health0 := v.health
	var speed := 120.0 / 3.6
	var best_drop := 0.0
	for attempt in 6:
		if destroyed_flag[0]:
			break
		v.place_at(Transform3D(Basis(), T.o(Vector3(0, 0.3, -40.0))))
		await T.frames(tree, 20)
		v.set_velocity(Vector3(0, 0, -speed))
		var h_before := v.health
		for i in 150:
			v.input_throttle = 1.0
			await tree.physics_frame
		best_drop = maxf(best_drop, h_before - v.health)
		if attempt == 0:
			T.report("crash_damage_120kmh", v.health < health0 * 0.9 and v.health > 0.0 or destroyed_flag[0], "health %.0f -> %.0f (-%.0f)" % [health0, v.health, h_before - v.health])
	T.report("crash_destroy_explode", destroyed_flag[0] and exploded[0] and v.is_destroyed, "destroyed=%s explosion_event=%s" % [destroyed_flag[0], exploded[0]])
	await T.frames(tree, 20)
	T.report("explosion_chain_bystander", is_instance_valid(bystander) and bystander.health < bystander.max_health * 0.95, "bystander health %.0f/%.0f (~5 m from the blast)" % [bystander.health, bystander.max_health])
	# wreck is no longer drivable and despawns after 60 s
	T.report("wreck_not_enterable", not v.can_be_entered_by(null), "can_be_entered=%s" % v.can_be_entered_by(null))
	await T.frames(tree, 62 * 60)
	T.report("wreck_despawn_60s", not is_instance_valid(v) or not v.is_inside_tree(), "valid=%s" % is_instance_valid(v))
	wall.queue_free()
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_reverse(id: StringName) -> void:
	var v := T.spawn(id, Vector3(0, 0.3, 0), 0.0) as CarVehicle
	await T.frames(tree, 40)
	var max_back := 0.0
	for i in 360:
		v.input_throttle = 0.0
		v.input_brake = 1.0
		await tree.physics_frame
		max_back = maxf(max_back, -v.get_forward_speed())
	# then throttle should brake then drive forward again
	for i in 480:
		v.input_throttle = 1.0
		v.input_brake = 0.0
		await tree.physics_frame
	var ok: bool = max_back > 4.0 and v.get_forward_speed() > 5.0
	T.report("reverse_then_forward_%s" % id, ok, "max reverse speed %.1f m/s, then forward speed %.1f m/s" % [max_back, v.get_forward_speed()])
	VehicleFactory.despawn(v)
