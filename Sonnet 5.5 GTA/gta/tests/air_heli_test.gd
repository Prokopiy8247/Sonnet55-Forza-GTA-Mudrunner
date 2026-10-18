extends Node
## Helicopter physics: spool-up, climb, hover stability, forward flight, yaw, landing damage thresholds, autorotation, rotor strike.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/air_heli_test.gd -Seconds 150 -GameArgs "--no-vehicles --no-traffic --no-peds"

var T := VehicleTestUtil
var tree: SceneTree
var main_node: Node
var results := {}


func run(main: Node) -> String:
	tree = get_tree()
	main_node = main
	T.make_floor(main)
	Game.wetness = 0.0
	await T.frames(tree, 10)
	await _t_basic(&"heli_civil")
	await _t_basic(&"heli_police")
	await _t_landing()
	await _t_autorotation()
	await _t_strikes()
	await _t_exit_rules()
	print("TEST SUMMARY passed=%d failed=%d" % [T.passed, T.failed])
	return "passed=%d failed=%d" % [T.passed, T.failed]


func _spawn(id: StringName, pos := Vector3(0, 0.3, 0), snap := true) -> HeliVehicle:
	var v := T.spawn(id, pos, 0.0, {"ai": true, "engine_on": true, "abandoned": true, "snap_ground": snap}) as HeliVehicle
	return v


func _hold(v: VehicleBase, frames: int, pitch := 0.0, roll := 0.0, yaw := 0.0, coll := 0.0) -> void:
	for i in frames:
		v.input_pitch = pitch
		v.input_roll = roll
		v.input_yaw = yaw
		v.input_collective = coll
		await tree.physics_frame


func _t_basic(id: StringName) -> void:
	var tag := String(id)
	var v := _spawn(id)
	T.report(tag + "_spawned", v != null and v is HeliVehicle, "class ok, seats=%d" % (v.seats.size() if v != null else -1))
	if v == null:
		return
	T.report(tag + "_pilot_seat_first", v.seats.size() >= 2 and v.seats[0]["name"] == &"driver", "seat0=%s seats=%s" % [v.seats[0]["name"] if v.seats.size() > 0 else "-", v.seats.map(func(s): return s["name"])])
	await T.frames(tree, 90)
	T.report(tag + "_rests_on_skids", v.grounded_count >= 3 and v.global_position.y < 0.4 and absf(v.linear_velocity.y) < 0.2, "grounded=%d y=%.2f vy=%.2f" % [v.grounded_count, v.global_position.y, v.linear_velocity.y])
	# spool up (ai flag: engine_on already true via opts -> _engine_cmd set)
	v.set_engine(true)
	await T.frames(tree, 60 * 5)
	T.report(tag + "_rotor_spoolup", v.rotor_rpm > 0.97, "rpm=%.2f after 5 s" % v.rotor_rpm)
	T.report(tag + "_idle_on_ground", v.grounded_count >= 2 and v.global_position.y < 0.5, "grounded=%d y=%.2f (rotor at flight rpm, collective idle)" % [v.grounded_count, v.global_position.y])
	# climb
	var y0 := v.global_position.y
	var max_vz := 0.0
	var t_lift := -1.0
	for i in 60 * 3:
		v.input_collective = 1.0
		await tree.physics_frame
		max_vz = maxf(max_vz, v.linear_velocity.y)
		if t_lift < 0.0 and v.grounded_count == 0:
			t_lift = float(i) / 60.0
	T.report(tag + "_liftoff", t_lift >= 0.0 and t_lift < 1.6, "lifted off after %.2f s" % t_lift)
	T.report(tag + "_climb_rate", max_vz > 5.0 and max_vz < 9.5, "max climb %.2f m/s" % max_vz)
	for i in 60 * 3:
		v.input_collective = 1.0
		await tree.physics_frame
	var alt := v.global_position.y
	T.report(tag + "_climbed", alt > 18.0, "altitude %.1f m after 6 s" % alt)
	# release: altitude hold + hover assist
	await _hold(v, 60 * 3)
	var a1 := v.global_position
	await _hold(v, 60 * 6)
	var a2 := v.global_position
	var tilt := rad_to_deg(acos(clampf(v.global_transform.basis.y.y, -1.0, 1.0)))
	T.report(tag + "_hover_altitude_hold", absf(a2.y - a1.y) < 1.0, "dy=%.2f m over 6 s" % (a2.y - a1.y))
	T.report(tag + "_hover_position_hold", Vector2(a2.x - a1.x, a2.z - a1.z).length() < 3.5, "drift %.2f m over 6 s (gusts on)" % Vector2(a2.x - a1.x, a2.z - a1.z).length())
	T.report(tag + "_hover_level", tilt < 4.0, "tilt %.1f deg" % tilt)
	# forward flight
	var top := 0.0
	for i in 60 * 32:
		v.input_pitch = -1.0
		await tree.physics_frame
		top = maxf(top, v.get_speed())
	var kmh := top * 3.6
	var want_kmh := float(v.def.get("top_speed_kmh", 230.0))
	T.report(tag + "_forward_speed", kmh > want_kmh * 0.85 and kmh < want_kmh * 1.1, "top %.0f km/h (def %.0f)" % [kmh, want_kmh])
	T.report(tag + "_forward_altitude", absf(v.global_position.y - alt) < 6.0, "altitude change %.1f m during the run (vertical compensation)" % (v.global_position.y - alt))
	# release: must brake
	await _hold(v, 60 * 9)
	T.report(tag + "_brakes_to_hover", v.get_speed() < 3.0, "speed after release %.1f m/s" % v.get_speed())
	# strafe
	var p0 := v.global_position
	await _hold(v, 60 * 3, 0.0, 1.0)
	var moved := (v.global_position - p0)
	var right := v.global_transform.basis.x
	T.report(tag + "_bank_strafe", moved.dot(Vector3(right.x, 0, right.z).normalized()) > 4.0, "moved %.1f m to the right in 3 s" % moved.dot(Vector3(right.x, 0, right.z).normalized()))
	await _hold(v, 60 * 4)
	# yaw
	var yaw0 := v.global_transform.basis.get_euler().y
	var yaw_acc := 0.0
	var prev := yaw0
	for i in 60 * 2:
		v.input_yaw = 1.0
		await tree.physics_frame
		var cur := v.global_transform.basis.get_euler().y
		yaw_acc += wrapf(cur - prev, -PI, PI)
		prev = cur
	T.report(tag + "_yaw_right", yaw_acc < -2.0, "turned %.0f deg to the right in 2 s" % rad_to_deg(-yaw_acc))
	await _hold(v, 60 * 3)
	# descent to the ground: soft landing
	var sink_max := 0.0
	for i in 60 * 20:
		v.input_collective = -0.6
		await tree.physics_frame
		sink_max = maxf(sink_max, -v.linear_velocity.y)
		if v.grounded_count >= 3 and i > 120:
			break
	await _hold(v, 90)
	T.report(tag + "_soft_landing", v.grounded_count >= 3 and v.health >= v.max_health * 0.99, "landed, health %.0f / %.0f, touchdown sink %.2f m/s, max sink %.1f" % [v.health, v.max_health, v.last_touchdown_sink, sink_max])
	T.report(tag + "_no_bounce", absf(v.linear_velocity.y) < 0.3 and v.global_position.y < 0.5, "vy=%.2f y=%.2f" % [v.linear_velocity.y, v.global_position.y])
	# engine off -> spool down
	v.set_engine(false)
	await T.frames(tree, 60 * 12)
	T.report(tag + "_spooldown", v.rotor_rpm < 0.05 and not v.engine_on, "rpm=%.2f engine_on=%s" % [v.rotor_rpm, v.engine_on])
	v.set_ai_controlled(false)
	await T.frames(tree, 120)
	T.report(tag + "_sleeps_when_parked", v.sleeping, "sleeping=%s" % v.sleeping)
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_landing() -> void:
	# touchdown damage thresholds (the same function the gear calls on first contact)
	var res := {}
	for sink in [1.5, 4.0, 6.5, 11.0]:
		var v := _spawn(&"heli_civil", Vector3(0, 0.3, 0))
		await T.frames(tree, 30)
		var h0 := v.health
		v._on_touchdown(sink)
		res[sink] = [h0 - v.health, v.is_destroyed]
		T.remove_all(tree)
		await T.frames(tree, 3)
	T.report("heli_landing_soft_ok", res[1.5][0] < 1.0 and not res[1.5][1], "sink 1.5 -> damage %.0f" % res[1.5][0])
	T.report("heli_landing_hard_damages", res[4.0][0] > 20.0 and not res[4.0][1], "sink 4.0 -> damage %.0f destroyed=%s" % [res[4.0][0], res[4.0][1]])
	T.report("heli_landing_harder_more", res[6.5][0] > res[4.0][0] and not res[6.5][1], "sink 6.5 -> damage %.0f (more than %.0f)" % [res[6.5][0], res[4.0][0]])
	T.report("heli_landing_crash", res[11.0][1], "sink 11 -> destroyed=%s" % res[11.0][1])
	# real drop with a dead rotor from 6 m: the gear measures the sink rate and the airframe pays for it
	var v2 := _spawn(&"heli_civil", Vector3(0, 6.0, 0), false)
	await T.frames(tree, 2)
	v2.rotor_hp = 0.0
	v2.engine_failed = true
	var h1 := v2.health
	await T.frames(tree, 150)
	T.report("heli_drop_damage", v2.last_touchdown_sink > 7.0 and (v2.health < h1 - 100.0 or v2.is_destroyed), "dropped 6 m: touchdown %.1f m/s, health %.0f -> %.0f destroyed=%s" % [v2.last_touchdown_sink, h1, v2.health, v2.is_destroyed])
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_autorotation() -> void:
	var v := _spawn(&"heli_civil")
	await T.frames(tree, 30)
	v.set_engine(true)
	await T.frames(tree, 60 * 4)
	await _hold(v, 60 * 4, 0.0, 0.0, 0.0, 1.0)
	await _hold(v, 60 * 6, 0.0, 0.0, 0.0, 1.0)
	var alt := v.global_position.y
	v.engine_failed = true
	var vmax := 0.0
	var t := 0.0
	for i in 60 * 40:
		await tree.physics_frame
		vmax = maxf(vmax, -v.linear_velocity.y)
		t += 1.0 / 60.0
		if v.grounded_count > 0:
			break
	T.report("heli_autorotation_descent", vmax > 3.0 and vmax < 14.5 and t > 5.0, "from %.0f m: max sink %.1f m/s, %.1f s to the ground (a free fall would be %.1f s)" % [alt, vmax, t, sqrt(2.0 * alt / 9.81)])
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_strikes() -> void:
	var v := _spawn(&"heli_civil", Vector3(0, 0.3, 0))
	await T.frames(tree, 30)
	v.set_engine(true)
	await T.frames(tree, 60 * 4)
	await _hold(v, 60 * 3, 0.0, 0.0, 0.0, 1.0)
	await _hold(v, 60 * 2)
	# a wall 16 m ahead, tall: fly into it
	T.make_box(main_node, Vector3(0, 10, -22), Vector3(30, 40, 3), Vector3.ZERO, "TestWall")
	var h0 := v.health
	var hp0 := v.rotor_hp
	for i in 60 * 9:
		v.input_pitch = -1.0
		await tree.physics_frame
		if v.rotor_hp < hp0 - 1.0:
			break
	T.report("heli_rotor_strike", v.rotor_hp < hp0 - 10.0 and v.health < h0, "rotor_hp %.0f -> %.0f, health %.0f -> %.0f" % [hp0, v.rotor_hp, h0, v.health])
	T.remove_all(tree)
	for n in main_node.get_children():
		if n.name == &"TestWall":
			n.queue_free()
	await T.frames(tree, 3)


func _t_exit_rules() -> void:
	var v := _spawn(&"heli_civil", Vector3(0, 0.3, 0))
	await T.frames(tree, 30)
	var c := CharacterBase.new()
	c.name = "MockPilot"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	c.add_child(cs)
	main_node.add_child(c)
	c.global_position = v.get_entry_position(0) + Vector3(-1.0, 0, 0)
	c.collision_layer = GC.L_PLAYER
	c.collision_mask = 0
	var ok := v.request_enter(c, 0)
	await T.frames(tree, 120)
	T.report("heli_enter_sets_driver", ok and v.driver == c and v.engine_on, "driver=%s engine_on=%s" % [v.driver == c, v.engine_on])
	await _hold(v, 60 * 5, 0.0, 0.0, 0.0, 1.0)
	await _hold(v, 60 * 3, 0.0, 0.0, 0.0, 1.0)
	v.exit(c)
	await T.frames(tree, 3)
	T.report("heli_exit_refused_in_air", v.driver == c and c.current_vehicle == v, "alt %.1f m, still seated=%s" % [v.global_position.y, v.driver == c])
	v.bail_out(c)
	await T.frames(tree, 3)
	T.report("heli_bail_out_releases", v.driver == null and c.current_vehicle == null, "driver=%s" % v.driver)
	c.queue_free()
	T.remove_all(tree)
	await T.frames(tree, 3)
