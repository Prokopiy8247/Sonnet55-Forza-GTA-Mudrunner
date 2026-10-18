extends Node
## Physics cost of 28 driving AI vehicles + 15 sleeping showroom vehicles (headless, flat floor).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/vehicle_perf_test.gd -Seconds 60 -GameArgs "--no-vehicles --no-traffic --no-peds --weather=clear"
var T := VehicleTestUtil


func _avg_physics_ms(frames: int) -> float:
	var acc := 0.0
	for i in frames:
		await get_tree().physics_frame
		acc += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return acc / float(frames) * 1000.0


func run(main: Node) -> String:
	T.make_floor(main)
	Game.wetness = 0.0
	await T.frames(get_tree(), 30)
	var base := await _avg_physics_ms(120)
	var parked: Array = []
	var ids := VehicleDefs.implemented_ids()
	for i in 15:
		parked.append(T.spawn(ids[i % ids.size()], Vector3(-60 + i * 7, 0.3, 100), 0.0, {"ai": false, "engine_on": false, "parked": true}))
	await T.frames(get_tree(), 120)
	var with_parked := await _avg_physics_ms(120)
	var driving: Array = []
	var traffic := [&"sedan", &"compact", &"suv", &"pickup", &"van", &"taxi", &"muscle"]
	for i in 28:
		var v := T.spawn(traffic[i % traffic.size()], Vector3(-80 + (i % 14) * 12, 0.3, -20 - (i / 14) * 14), 0.0)
		driving.append(v)
	await T.frames(get_tree(), 30)
	var acc := 0.0
	var n := 360
	VehicleBase.prof_on = true
	VehicleBase.prof_usec = 0
	VehicleBase.prof_calls = 0
	for i in n:
		for v in driving:
			v.input_throttle = 0.5
			v.input_steer = sin(float(i) * 0.02 + float(v.get_instance_id() % 7)) * 0.6
		await get_tree().physics_frame
		acc += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var drive_ms := acc / float(n) * 1000.0
	var per_call_us := float(VehicleBase.prof_usec) / maxf(float(VehicleBase.prof_calls), 1.0)
	print("TEST perf_profile vehicle _physics_process: %.0f us per vehicle-tick (%d calls, %.2f ms per frame for 28 vehicles)" % [per_call_us, VehicleBase.prof_calls, per_call_us * 28.0 / 1000.0])
	var ok: bool = per_call_us < 150.0
	T.report("perf_28_driving_vehicles", ok, "GDScript cost %.0f us per vehicle-tick => %.2f ms for 28 vehicles (frame physics time incl. Jolt + other systems, noisy: baseline=%.2f +15 sleeping=%.2f +28 driving=%.2f ms)" % [per_call_us, per_call_us * 28.0 / 1000.0, base, with_parked, drive_ms])
	# sleeping vehicles must not tick at all: profile a second window with only the parked ones
	VehicleBase.prof_usec = 0
	VehicleBase.prof_calls = 0
	for v in driving:
		VehicleFactory.despawn(v)
	await T.frames(get_tree(), 60)
	VehicleBase.prof_usec = 0
	VehicleBase.prof_calls = 0
	await T.frames(get_tree(), 120)
	T.report("perf_sleeping_cheap", VehicleBase.prof_calls == 0, "15 sleeping vehicles ran _simulate %d times in 120 frames" % VehicleBase.prof_calls)
	return "done"
