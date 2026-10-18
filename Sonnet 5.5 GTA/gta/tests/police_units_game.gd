extends Node
## Police-B integration test with the REAL Police-A director (WantedSystem + PoliceManager) driving the real PoliceUnits factory in the full city
## (traffic + pedestrians + gangs on): stand still unarmed at 1 star -> the officers walk up and arrest (BUSTED); 3 stars -> cruisers, SWAT on foot and
## roadblocks appear and engage; clearing the wanted level sends everybody away.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/police_units_game.gd -Seconds 400
## Options: --only=arrest,pursuit,clear

var passed := 0
var failed := 0
var main_node: Node = null


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(s * 60.0))


func _only(name: String) -> bool:
	var want := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			want = String(a).substr(7)
	return want == "" or want.split(",").has(name)


func _summary() -> String:
	var foot := 0
	var seated := 0
	var engaged := 0
	var drawn := 0
	for o in PoliceUnits.officers():
		var po := o as PoliceOfficer
		if po.is_in_vehicle():
			seated += 1
		else:
			foot += 1
			if po.brain.is_engaged():
				engaged += 1
			if po.weapon_drawn:
				drawn += 1
	return "cars=%d officers=%d (foot=%d seated=%d engaged=%d drawn=%d) roadblocks=%d" % [PoliceUnits.count_cars(), PoliceUnits.count_officers(), foot, seated, engaged, drawn,
		_roadblocks()]


func _roadblocks() -> int:
	var n := 0
	var cont := PoliceUnits.container()
	if cont != null:
		for c in cont.get_children():
			if c is PoliceRoadblock:
				n += 1
	return n


func run(main: Node) -> String:
	main_node = main
	await get_tree().process_frame
	PoliceUnits.autostart_hostiles = true
	Game.cheats["invulnerable"] = true
	var w = Game.sys(&"wanted")
	var pm = Game.sys(&"police")
	check("director_present", w != null and pm != null, "wanted=%s police=%s" % [w != null, pm != null])
	if w == null or pm == null:
		return "no director"
	await seconds(2.0)
	var pl = Game.player
	if _only("arrest"):
		await _t_arrest(w, pl)
	if _only("pursuit"):
		await _t_pursuit(w, pl)
	if _only("clear"):
		await _t_clear(w, pl)
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
	return "passed=%d failed=%d" % [passed, failed]


func _t_arrest(w, pl) -> void:
	pl.teleport_to(Vector3(10.0, 0.3, 40.0), 0.0)
	pl.weapons.equip(&"fists")
	await seconds(1.5)
	var busted := [false]
	var on_busted := func(): busted[0] = true
	Events.player_busted.connect(on_busted)
	w.set_level(1)
	var t := 0.0
	var first_unit_t := -1.0
	var first_foot_t := -1.0
	while t < 90.0 and not busted[0]:
		await seconds(1.0)
		t += 1.0
		if first_unit_t < 0.0 and PoliceUnits.count_officers() > 0:
			first_unit_t = t
		if first_foot_t < 0.0:
			for o in PoliceUnits.officers():
				if not (o as PoliceOfficer).is_in_vehicle():
					first_foot_t = t
					break
		if int(t) % 15 == 0:
			print("TEST info arrest t=%d %s" % [int(t), _summary()])
	Events.player_busted.disconnect(on_busted)
	check("arrest_units_arrive", first_unit_t > 0.0, "first officer at %.0f s, first on foot at %.0f s" % [first_unit_t, first_foot_t])
	check("arrest_busted_at_1_star", busted[0], "busted=%s after %.0f s" % [busted[0], t])
	await seconds(6.0)             # arrest flow / respawn
	Game.cheats["invulnerable"] = true
	w.clear()
	await seconds(2.0)


func _t_pursuit(w, pl) -> void:
	pl.teleport_to(Vector3(10.0, 0.3, 40.0), 0.0)
	await seconds(2.0)
	w.clear()
	await seconds(30.0)           # let the previous units leave
	pl.teleport_to(Vector3(10.0, 0.3, 40.0), 0.0)
	await seconds(1.0)
	var peak_cars := 0
	var peak_foot := 0
	var peak_engaged := 0
	var peak_blocks := 0
	var shots := [0]
	var on_shot := func(_p: Vector3, _l: float, src: Node):
		if src is PoliceOfficer:
			shots[0] += 1
	Events.gunshot.connect(on_shot)
	w.set_level(3)
	var t := 0.0
	var upright_min := 1.0
	while t < 75.0:
		await seconds(1.0)
		t += 1.0
		var foot := 0
		var engaged := 0
		for o in PoliceUnits.officers():
			var po := o as PoliceOfficer
			if not po.is_in_vehicle():
				foot += 1
				if po.brain.is_engaged():
					engaged += 1
		peak_cars = maxi(peak_cars, PoliceUnits.count_cars())
		peak_foot = maxi(peak_foot, foot)
		peak_engaged = maxi(peak_engaged, engaged)
		peak_blocks = maxi(peak_blocks, _roadblocks())
		for c in PoliceUnits.police_cars():
			upright_min = minf(upright_min, (c as Node3D).global_transform.basis.y.y)
		if int(t) % 15 == 0:
			print("TEST info pursuit t=%d lvl=%d %s" % [int(t), w.level, _summary()])
	Events.gunshot.disconnect(on_shot)
	var st := PoliceUnits.stats()
	check("pursuit_cars_spawned", peak_cars >= 2, "peak cars=%d" % peak_cars)
	check("pursuit_officers_on_foot", peak_foot >= 2, "peak on foot=%d" % peak_foot)
	check("pursuit_officers_engage", peak_engaged >= 1, "peak engaged=%d" % peak_engaged)
	check("pursuit_officers_shoot_at_3_stars", shots[0] >= 3, "police gunshots=%d" % shots[0])
	check("pursuit_cars_stay_upright", upright_min > 0.5, "min up.y=%.2f" % upright_min)
	print("TEST info pursuit peak_roadblocks=%d stats=%s" % [peak_blocks, str(st)])


func _t_clear(w, pl) -> void:
	w.clear()
	var t := 0.0
	var left := PoliceUnits.count_officers() + PoliceUnits.count_cars()
	var t_zero := -1.0
	while t < 120.0:
		await seconds(2.0)
		t += 2.0
		if PoliceUnits.count_officers() + PoliceUnits.count_cars() == 0:
			t_zero = t
			break
	check("clear_units_leave", t_zero > 0.0, "units %d -> %d after %.0f s" % [left, PoliceUnits.count_officers() + PoliceUnits.count_cars(), t])
