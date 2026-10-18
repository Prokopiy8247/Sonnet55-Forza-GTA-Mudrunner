extends Node
## Physics cost of the air / sea fleet (headless, flat floor): 2 helicopters + a police helicopter with searchlight, 2 planes, 2 boats, all
## flying / driving under the AirAutopilot or fixed inputs; per-vehicle _physics_process cost via VehicleBase.prof_*.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/air_perf_test.gd -Seconds 90 -GameArgs "--no-vehicles --no-traffic --no-peds"

var T := VehicleTestUtil


func run(main: Node) -> String:
	var tree := get_tree()
	T.make_floor(main, 20000.0)
	Game.time_of_day = 22.0
	await T.frames(tree, 10)
	var fleet: Array[VehicleBase] = []
	fleet.append(T.spawn(&"heli_civil", Vector3(0, 60, 0), 0.0, {"ai": true, "snap_ground": false}))
	fleet.append(T.spawn(&"heli_civil", Vector3(60, 60, 0), 0.0, {"ai": true, "snap_ground": false}))
	var pol := PoliceHeliAI.spawn(T.o(Vector3(-60, 60, 0)), {"force": true})
	fleet.append(pol)
	fleet.append(T.spawn(&"plane_prop", Vector3(0, 200, 100), -90.0, {"ai": true, "snap_ground": false}))
	fleet.append(T.spawn(&"plane_jet", Vector3(0, 300, 200), -90.0, {"ai": true, "snap_ground": false}))
	for v in fleet:
		if v is HeliVehicle:
			(v as HeliVehicle).start_airborne(0.0)
		elif v is PlaneVehicle:
			v.set_velocity(Vector3(70.0 if v.def_id == &"plane_prop" else 200.0, 0, 0))
	var ai_pol := PoliceHeliAI.of(pol)
	ai_pol.set_mode(&"search")
	ai_pol.search_center = T.o(Vector3(0, 0, 0))
	for v in fleet:
		if v is PlaneVehicle:
			v.input_throttle = 0.8
	await T.frames(tree, 60 * 5)
	VehicleBase.prof_on = true
	VehicleBase.prof_usec = 0
	VehicleBase.prof_calls = 0
	await T.frames(tree, 60 * 10)
	VehicleBase.prof_on = false
	var per_call := float(VehicleBase.prof_usec) / maxf(float(VehicleBase.prof_calls), 1.0)
	var alive := 0
	for v in fleet:
		if is_instance_valid(v) and not v.is_destroyed:
			alive += 1
	print("TEST air_perf_profile air _simulate: %.0f us per vehicle-tick (%d calls = %d aircraft, %.2f ms per frame for the whole fleet)" % [per_call, VehicleBase.prof_calls, alive, per_call * float(alive) / 1000.0])
	T.report("air_perf_cheap", per_call < 350.0, "%.0f us per aircraft per tick" % per_call)
	T.report("air_perf_fleet_alive", alive == fleet.size(), "%d / %d alive after 15 s" % [alive, fleet.size()])
	T.remove_all(tree)
	return "ok"
