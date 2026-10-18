extends Node
## Speedboat physics on the real sea: floating, wave pitch / roll, top speed + planing, steering + heel, reverse, flip guard,
## grounding on the beach, exit placement (pier / water), sinking when destroyed.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/boat_test.gd -Seconds 200 -GameArgs "--no-vehicles --no-traffic --no-peds"

var T := VehicleTestUtil
var tree: SceneTree
var main_node: Node
const SPAWN := Vector3(-117.0, -1.2, 230.0)


func run(main: Node) -> String:
	tree = get_tree()
	main_node = main
	Game.wetness = 0.0
	await T.frames(tree, 20)
	await _t_float_and_speed()
	await _t_flip_and_sink()
	await _t_beach()
	await _t_exit()
	print("TEST SUMMARY passed=%d failed=%d" % [T.passed, T.failed])
	return "passed=%d failed=%d" % [T.passed, T.failed]


func _boat(pos := SPAWN, yaw_deg := 180.0) -> BoatVehicle:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	return VehicleFactory.spawn(&"speedboat", xf, {"ai": true, "engine_on": true, "abandoned": true, "snap_ground": false}) as BoatVehicle


func _in(v: VehicleBase, thr: float, steer := 0.0, brake := 0.0) -> void:
	v.input_throttle = thr
	v.input_steer = steer
	v.input_brake = brake


func _tilt(v: VehicleBase) -> Vector2:
	var b := v.global_transform.basis
	return Vector2(rad_to_deg(AirCommon.pitch_of(b)), rad_to_deg(AirCommon.bank_of(b)))


func _t_float_and_speed() -> void:
	var v := _boat(Vector3(-250, -1.2, 300), -90.0)       # heading east along the open bay
	T.report("boat_spawned", v != null and v is BoatVehicle and v.seats.size() == 4, "seats=%d hull pts=%d mass=%.0f" % [v.seats.size(), v.hull.size(), v.mass])
	if v == null:
		return
	await T.frames(tree, 180)
	var level := GC.WATER_LEVEL
	var y := v.global_position.y
	T.report("boat_floats_at_waterline", y > level - 0.45 and y < level + 0.55, "origin y %.2f (sea %.2f), wet %.2f, depth %.2f" % [y, level, v.wet, v.submerged_depth])
	# calm swell: pitch / roll stay small
	var max_p := 0.0
	var max_r := 0.0
	var ymin := 99.0
	var ymax := -99.0
	for i in 60 * 6:
		_in(v, 0.0)
		await tree.physics_frame
		var t := _tilt(v)
		max_p = maxf(max_p, absf(t.x))
		max_r = maxf(max_r, absf(t.y))
		ymin = minf(ymin, v.global_position.y)
		ymax = maxf(ymax, v.global_position.y)
	T.report("boat_wave_pitch_roll_sane", max_p < 4.0 and max_r < 4.0 and ymax - ymin < 0.5, "idle for 6 s: pitch +-%.1f roll +-%.1f deg, heave %.2f m" % [max_p, max_r, ymax - ymin])
	# full throttle
	var top := 0.0
	var t_plane := -1.0
	var trim := 0.0
	var roll_max := 0.0
	for i in 60 * 14:
		_in(v, 1.0)
		await tree.physics_frame
		top = maxf(top, v.get_speed())
		if t_plane < 0.0 and v.planing > 0.85:
			t_plane = float(i) / 60.0
		if i > 60 * 10:
			trim = maxf(trim, _tilt(v).x)
			roll_max = maxf(roll_max, absf(_tilt(v).y))
		if v.global_position.x > 285.0:
			break
	var want := float(v.def.get("top_speed_kmh", 110.0))
	T.report("boat_top_speed", top * 3.6 > want * 0.78 and top * 3.6 < want * 1.12, "top %.0f km/h (def %.0f), travelled to x=%.0f" % [top * 3.6, want, v.global_position.x])
	T.report("boat_planing", t_plane > 0.0 and t_plane < 9.0, "planing after %.1f s" % t_plane)
	T.report("boat_planing_trim", trim > 1.0 and trim < 11.0 and roll_max < 6.0, "bow-up trim %.1f deg, roll +-%.1f deg at full speed" % [trim, roll_max])
	# turn at speed
	await _turn_test(v)
	T.remove_all(tree)
	await T.frames(tree, 3)


func _turn_test(v: BoatVehicle) -> void:
	# restart from the western bay heading east again
	v.place_at(Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(-280, -1.2, 290)))
	v.set_velocity(Vector3(18, 0, 0))
	for i in 60 * 3:
		_in(v, 1.0)
		await tree.physics_frame
	var h0 := Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	var max_heel := 0.0
	var spd_min := 99.0
	for i in 60 * 3:
		_in(v, 1.0, 1.0)
		await tree.physics_frame
		max_heel = maxf(max_heel, _tilt(v).y)
		spd_min = minf(spd_min, v.get_speed())
	var h1 := Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	var turned := rad_to_deg(wrapf(h0 - h1, -PI, PI))        # right turn = decreasing yaw
	T.report("boat_turns_right_at_speed", turned > 55.0, "turned %.0f deg to the right in 3 s, slowest %.1f m/s" % [turned, spd_min])
	T.report("boat_heels_into_turn", max_heel > 1.5 and max_heel < 16.0, "max heel %.1f deg to the inside" % max_heel)
	# slow-speed steering authority (fresh water, away from the south wall)
	v.place_at(Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(-200, -1.2, 300)))
	_in(v, 0.0)
	for i in 60 * 5:
		_in(v, 0.0)
		await tree.physics_frame
	var h2 := Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	for i in 60 * 4:
		_in(v, 0.3, -1.0)
		await tree.physics_frame
	var h3 := Util.dir_to_yaw(Util.flat(-v.global_transform.basis.z).normalized())
	T.report("boat_turns_left_slow", rad_to_deg(wrapf(h3 - h2, -PI, PI)) > 20.0, "turned %.0f deg left in 4 s at low throttle (speed %.1f m/s)" % [rad_to_deg(wrapf(h3 - h2, -PI, PI)), v.get_speed()])
	# reverse
	for i in 60 * 6:
		_in(v, 0.0, 0.0, 1.0)
		await tree.physics_frame
	T.report("boat_reverses", v.get_forward_speed() < -1.0, "forward speed %.1f m/s with the brake held" % v.get_forward_speed())


func _t_flip_and_sink() -> void:
	var v := _boat(Vector3(-117, -1.2, 250))
	await T.frames(tree, 120)
	# knock it 70 degrees over: the flip guard rights it
	v.global_transform = Transform3D(v.global_transform.basis * Basis(Vector3.BACK, deg_to_rad(70.0)), v.global_position)
	v.angular_velocity = Vector3.ZERO
	await T.frames(tree, 60 * 5)
	var t := _tilt(v)
	T.report("boat_flip_guard", absf(t.y) < 25.0, "after being heeled 70 deg: roll %.0f deg after 5 s" % t.y)
	# destroy: it sinks
	v.explode(null)
	var y0 := v.global_position.y
	await T.frames(tree, 60 * 10)
	T.report("boat_sinks_when_destroyed", v.is_destroyed and v.global_position.y < y0 - 1.0, "y %.2f -> %.2f after 10 s" % [y0, v.global_position.y])
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_beach() -> void:
	var v := _boat(Vector3(0, -1.2, 215), 0.0)           # facing north (-Z) towards the beach
	await T.frames(tree, 90)
	var zmin := 999.0
	for i in 60 * 14:
		_in(v, 1.0)
		await tree.physics_frame
		zmin = minf(zmin, v.global_position.z)
	await T.frames(tree, 60)
	var h := WorldLayout.terrain_height(v.global_position.x, v.global_position.z)
	var z_shore := 0.0
	for zz in range(150, 260):
		if WorldLayout.terrain_height(0.0, float(zz)) < GC.WATER_LEVEL:
			z_shore = float(zz)
			break
	T.report("boat_grounds_on_beach", v.get_speed() < 3.0 and absf(v.global_position.z - z_shore) < 22.0 and v.global_position.y > h - 0.8, "stopped at z=%.1f (shoreline z=%.0f, terrain y %.2f, boat y %.2f), speed %.1f" % [v.global_position.z, z_shore, h, v.global_position.y, v.get_speed()])
	T.remove_all(tree)
	await T.frames(tree, 3)


func _t_exit() -> void:
	# a mock pilot (the real Player is covered by air_player_test.gd)
	var v := _boat(Vector3(-117, -1.2, 214), 180.0)
	await T.frames(tree, 120)
	var c := CharacterBase.new()
	c.name = "MockSkipper"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	c.add_child(cs)
	main_node.add_child(c)
	c.global_position = v.get_entry_position(0) + Vector3(-1.0, 0.5, 0)
	c.collision_layer = GC.L_PLAYER
	c.collision_mask = 0
	var ok := v.request_enter(c, 0)
	await T.frames(tree, 90)
	T.report("boat_enter_sets_driver", ok and v.driver == c and v.engine_on, "driver=%s engine=%s" % [v.driver == c, v.engine_on])
	v.exit(c)
	await T.frames(tree, 4)
	var p := c.global_position
	T.report("boat_exit_onto_water_level", v.driver == null and c.current_vehicle == null and p.y > GC.WATER_LEVEL - 0.5 and p.y < GC.WATER_LEVEL + 2.5 and p.distance_to(v.global_position) > 1.5, "exit at %s (boat %s)" % [p, v.global_position])
	# mooring: boat next to the marina pier -> the exit lands on the pier deck
	c.queue_free()
	T.remove_all(tree)
	await T.frames(tree, 3)
