extends Node
## Emergency response (headless): a dead pedestrian -> ambulance (siren, paramedics treat + collect the body, leaves); a destroyed car -> fire engine
## (firefighters spray, fire is out, leaves). One unit of each kind at a time.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/emergency_test.gd -Seconds 700 -GameArgs "--no-traffic --time=12"


func report(test_name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run(_main: Node) -> void:
	var es = Game.sys(&"emergency")
	var tm = Game.sys(&"traffic")
	var peds = Game.sys(&"peds")
	report("emg_systems", es != null and tm != null and peds != null)
	if es == null or tm == null or peds == null:
		return
	var waited := 0
	while int(tm.state) != 1 and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var pl = Game.player
	var base := WorldLayout.location_pos(&"taxi_stand")
	pl.teleport_to(base + Vector3(0, 0.5, 0))
	await _frames(120)
	var f := 0
	var fire_only: bool = OS.get_cmdline_user_args().has("--fire-only")
	if not fire_only:
		# ---- medical -------------------------------------------------------------------------------------------------------
		var ped = peds.spawn_pedestrian(base + Vector3(-6, 0.3, 4), &"civilian", {"force": true})
		report("emg_ped_spawned", ped != null)
		await _frames(30)
		ped.apply_damage(999.0, {"source": null, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO})
		await _frames(10)
		report("emg_incident_queued", es.incidents.size() == 1 and es.incidents[0]["kind"] == &"medical", "incidents=%d" % es.incidents.size())
		f = 0
		while not es.units.has(&"medical") and f < 60 * 25:
			await get_tree().physics_frame
			f += 1
		report("emg_ambulance_dispatched", es.units.has(&"medical"), "after %.0f s" % (f / 60.0))
		if not es.units.has(&"medical"):
			return
		var u = es.units[&"medical"]
		var amb: VehicleBase = u.vehicle
		report("emg_ambulance_siren", amb.siren_on and amb.def_id == &"ambulance" and amb.is_in_group(&"emergency_vehicle"), "siren=%s id=%s" % [str(amb.siren_on), str(amb.def_id)])
		var d0: float = Util.dist_xz(amb.global_position, ped.global_position)
		f = 0
		while u.state == 0 and f < 60 * 170:
			await get_tree().physics_frame
			f += 1
		report("emg_ambulance_arrived", u.state == 1, "start %.0f m away, drove %.0f s, now %.1f m from the body, unsticks=%d" % [d0, f / 60.0, Util.dist_xz(amb.global_position, ped.global_position), int(es.stats["unsticks"])])
		await _frames(30)
		report("emg_paramedics_out", u.crew.size() == 2, "crew=%d" % u.crew.size())
		f = 0
		while int(es.stats["bodies"]) < 1 and f < 60 * 40:
			await get_tree().physics_frame
			f += 1
		report("emg_body_collected", int(es.stats["bodies"]) >= 1, "after %.0f s of work" % (f / 60.0))
		f = 0
		while es.units.has(&"medical") and f < 60 * 150:
			await get_tree().physics_frame
			f += 1
		report("emg_ambulance_gone", not es.units.has(&"medical"), "after %.0f s" % (f / 60.0))
	# ---- fire ----------------------------------------------------------------------------------------------------------
	pl.teleport_to(base + Vector3(0, 0.5, 0))
	var lane := RoutePlanner.nearest_lane(base + Vector3(-20, 0, 0), Vector3.ZERO, 40.0)
	var G := RoutePlanner.graph()
	var car := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(G.dirs[lane])), G.positions[lane]), {})
	await _frames(60)
	car.explode(null)
	await _frames(10)
	report("emg_fire_incident", es.incidents.size() >= 1 or es.units.has(&"fire"), "incidents=%d" % es.incidents.size())
	f = 0
	while not es.units.has(&"fire") and f < 60 * 25:
		await get_tree().physics_frame
		f += 1
	report("emg_firetruck_dispatched", es.units.has(&"fire"), "after %.0f s" % (f / 60.0))
	if not es.units.has(&"fire"):
		return
	var fu = es.units[&"fire"]
	f = 0
	while fu.state == 0 and f < 60 * 170:
		await get_tree().physics_frame
		f += 1
	report("emg_firetruck_arrived", fu.state == 1, "drove %.0f s, %.1f m from the fire" % [f / 60.0, Util.dist_xz(fu.vehicle.global_position, car.global_position)])
	f = 0
	while fu.phase < 1 and f < 60 * 30:
		await get_tree().physics_frame
		f += 1
	await _frames(90)
	var spraying := 0
	for c in fu.crew:
		if c.spraying:
			spraying += 1
	report("emg_firefighters_spray", spraying == 2, "spraying crew=%d" % spraying)
	f = 0
	while int(es.stats["fires_out"]) < 1 and f < 60 * 30:
		await get_tree().physics_frame
		f += 1
	report("emg_fire_out", int(es.stats["fires_out"]) >= 1 and not car.on_fire, "fires_out=%d burnt=%s" % [int(es.stats["fires_out"]), str(car.dmg.get("_burnt") if car.dmg != null else "-")])
	f = 0
	while es.units.has(&"fire") and f < 60 * 160:
		await get_tree().physics_frame
		f += 1
	report("emg_firetruck_gone", not es.units.has(&"fire"), "after %.0f s" % (f / 60.0))
	print("EMERGENCY TEST DONE ", es.get_state())
