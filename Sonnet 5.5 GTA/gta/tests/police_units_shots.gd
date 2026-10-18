extends Node
## Police-B screenshot scenes (real renderer). Usage:
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\police\officers.png -GameArgs "--exec=res://gta/tests/police_units_shots.gd --scene=officers --time=17.6 --delay=3 --no-traffic --no-peds --no-hostiles"
## scenes: officers (aiming at the player), chase (dusk pursuit), roadblock, gang (encounter), cover (cover use), arrest
## The harness calls run(main) after --delay seconds, waits for it, then saves the viewport.

var main_node: Node = null
var cam: Camera3D = null
var scene_name := "officers"
var follow: Node3D = null
var follow_off := Vector3(0, 3.0, 9.0)
var look_off := Vector3(0, 1.0, 0)


func _arg(key: String, default_v: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
	return default_v


func run(main: Node) -> String:
	main_node = main
	scene_name = _arg("scene", "officers")
	PoliceUnits.autostart_hostiles = scene_name == "gang"
	var pm = Game.sys(&"police")
	if pm != null:
		pm.enabled = false
	Game.cheats["invulnerable"] = true
	cam = Camera3D.new()
	cam.name = "ShotCam"
	cam.fov = float(_arg("fov", "62"))
	cam.far = 900.0
	main.add_child(cam)
	cam.make_current()
	match scene_name:
		"officers":
			await _officers()
		"chase":
			await _chase()
		"roadblock":
			await _roadblock()
		"gang":
			await _gang()
		"cover":
			await _cover()
		"arrest":
			await _arrest()
	return "scene " + scene_name


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
		_update_cam(get_process_delta_time())


func _update_cam(dt: float) -> void:
	if cam != null and not cam.current:
		cam.make_current()            # the player's aim camera grabs the view again when the weapon is raised
	if follow != null and is_instance_valid(follow):
		var basis := follow.global_transform.basis
		var yaw := follow.global_rotation.y
		var want := follow.global_position + Basis(Vector3.UP, yaw) * follow_off
		cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-6.0 * dt))
		cam.look_at(follow.global_position + look_off, Vector3.UP)


func _place_cam(pos: Vector3, look: Vector3) -> void:
	follow = null
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _wanted(n: int) -> void:
	var w = Game.sys(&"wanted")
	if w != null and w.has_method("set_level"):
		w.set_level(n)
	else:
		Game.wanted_level = n


func _teleport_player(p: Vector3, yaw_deg := 0.0) -> void:
	if is_instance_valid(Game.player):
		Game.player.teleport_to(p, deg_to_rad(yaw_deg))


# ----------------------------------------------------------------------------------------------------------------------------------
func _officers() -> void:
	var base := Vector3(14.0, 0.1, 38.0)
	_teleport_player(base, 180.0)             # faces north (-Z is yaw 0; 180 deg faces +Z) -> the plaza
	await _wait(0.6)
	_wanted(2)
	var o1 := PoliceUnits.spawn_officer(&"patrol", Transform3D(Basis(Vector3.UP, PI), base + Vector3(-3.5, 0, -11))) as PoliceOfficer
	var o2 := PoliceUnits.spawn_officer(&"swat", Transform3D(Basis(Vector3.UP, PI), base + Vector3(0.5, 0, -13))) as PoliceOfficer
	var o3 := PoliceUnits.spawn_officer(&"patrol", Transform3D(Basis(Vector3.UP, PI), base + Vector3(4.0, 0, -10.5))) as PoliceOfficer
	for o in [o1, o2, o3]:
		if o != null:
			o.set_order({"mode": &"pursue", "target": Game.player, "aggression": 0.7, "lethal": true})
			o.brain.use_cover = false
			o.brain.pref_min = 5.0
			o.brain.pref_max = 14.0
			o.brain.shoot_allowed = true
	_place_cam(base + Vector3(5.5, 1.7, -3.0), base + Vector3(0.0, 1.2, -11.5))
	await _wait(float(_arg("wait", "4.5")))


func _cover() -> void:
	var base := Vector3(14.0, 0.1, 38.0)
	_teleport_player(base, 180.0)
	await _wait(0.6)
	_wanted(3)
	var os: Array = []
	for i in 3:
		var o := PoliceUnits.spawn_officer(&"swat" if i == 1 else &"patrol", Transform3D(Basis(Vector3.UP, PI), base + Vector3(-6 + i * 6, 0, -20))) as PoliceOfficer
		if o != null:
			o.set_order({"mode": &"pursue", "target": Game.player, "aggression": 0.9, "lethal": true})
			o.brain.cover_bias = 1.0
			os.append(o)
	_place_cam(base + Vector3(10.0, 2.4, -2.0), base + Vector3(-2.0, 1.0, -16.0))
	await _wait(float(_arg("wait", "8.0")))


func _roadblock() -> void:
	var c := Vector3(105.0, 0.1, 20.0)
	_teleport_player(Vector3(105.0, 0.2, 90.0), 0.0)
	_wanted(4)
	await _wait(0.5)
	var rb := PoliceUnits.spawn_roadblock(c, Vector3(0, 0, -1), 4)
	_place_cam(c + Vector3(-5.0, 2.2, 22.0), c + Vector3(0, 1.0, 0))
	await _wait(float(_arg("wait", "4.0")))
	if rb != null:
		print("TEST roadblock cars=%d officers=%d props=%d" % [rb.cars.size(), rb.officers.size(), rb.props.size()])


func _arrest() -> void:
	var base := Vector3(14.0, 0.1, 38.0)
	_teleport_player(base, 180.0)
	await _wait(0.6)
	_wanted(1)
	var o1 := PoliceUnits.spawn_officer(&"patrol", Transform3D(Basis(Vector3.UP, PI), base + Vector3(-4, 0, -12))) as PoliceOfficer
	var o2 := PoliceUnits.spawn_officer(&"patrol", Transform3D(Basis(Vector3.UP, PI), base + Vector3(4, 0, -13))) as PoliceOfficer
	for o in [o1, o2]:
		o.set_order({"mode": &"pursue", "target": Game.player, "aggression": 0.3, "lethal": false})
	_place_cam(base + Vector3(6.0, 1.9, 5.0), base + Vector3(0, 1.2, -5.0))
	await _wait(float(_arg("wait", "5.0")))


func _chase() -> void:
	# a fleeing sports car on the Halcyon Ring with three cruisers behind it (dusk)
	_teleport_player(Vector3(-100.0, 0.2, 100.0), 0.0)
	var lg := WorldLayout.lanes
	var start_i := lg.nearest(Vector3(105.0, 0.0, 60.0), Vector3(0, 0, -1), 30.0)
	if start_i < 0:
		start_i = lg.nearest(Vector3(105.0, 0.0, 60.0), Vector3.ZERO, 60.0)
	var p0 := lg.positions[start_i]
	var d0 := lg.dirs[start_i]
	var yaw := Util.dir_to_yaw(d0)
	var runner := VehicleFactory.spawn(&"sports", Transform3D(Basis(Vector3.UP, yaw), p0 + Vector3(0, 0.5, 0)), {"ai": true, "paint": Color("#34e0ff")})
	var ai := PoliceCarAI.attach(runner)
	ai.autonomous = false
	ai.driverless = true
	ai.obey_signals = false
	ai.speed_factor = 1.45
	ai.set_order({"mode": &"patrol"})
	runner.faction = GC.F_CIVILIAN
	if runner.is_in_group(GC.G_POLICE):
		runner.remove_from_group(GC.G_POLICE)
	runner.set_velocity(d0 * 12.0)
	var cars: Array = []
	for i in 3:
		var back := p0 - d0 * (14.0 + 11.0 * i)
		var ci := lg.nearest(back, d0, 25.0)
		var cp := lg.positions[ci] if ci >= 0 else back
		var car := PoliceUnits.spawn_patrol_car(Transform3D(Basis(Vector3.UP, yaw), cp + Vector3(0, 0.5, 0)), 2)
		if car != null:
			car.set_velocity(d0 * 12.0)
			PoliceUnits.set_order(car, {"mode": &"pursue", "target": runner, "aggression": 0.8, "lethal": false, "level": 3,
				"role": [&"tail", &"flank", &"intercept"][i]})
			var ca := car.get_meta(&"police_ai") as PoliceCarAI
			ca.autonomous = false
			cars.append(car)
	follow = runner
	follow_off = Vector3(-6.5, 3.0, 11.0)
	look_off = Vector3(0, 0.8, -3.0)
	cam.global_position = runner.global_position + Vector3(-6.5, 3.0, 11.0)
	await _wait(float(_arg("wait", "9.0")))


func _gang() -> void:
	var hm = PoliceUnits.ensure_hostile_manager()
	hm.force_spawn_all()
	await _wait(1.0)
	var gi := int(_arg("group", "-1"))
	if gi < 0:
		gi = 0
		for i in hm.groups.size():
			if hm.groups[i]["turf"]["kind"] == &"alley":
				gi = i
	var g: Dictionary = hm.groups[gi]
	var turf: Vector3 = g["turf"]["center"]
	# a camera spot 9-13 m from the group with a clear line of sight (no fence / wall in between); the player stands just in front of it
	var spot := turf + Vector3(0, 1.7, 12)
	var found := false
	for r in [13.0, 11.0, 15.0, 9.0]:
		for k in 24:
			var a := TAU * float(k) / 24.0
			var p := turf + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var gp := _ground_at(p)
			if gp == Vector3.INF or gp.y < -0.3 or gp.y > 0.5:
				continue
			if not Util.has_line_of_sight(cam, gp + Vector3(0, 0.3, 0), gp + Vector3(0, 2.2, 0), GC.M_LOS, []):
				continue
			if Util.has_line_of_sight(cam, gp + Vector3(0, 1.7, 0), turf + Vector3(0, 1.3, 0), GC.M_LOS, []) and Util.has_line_of_sight(cam, gp + Vector3(0, 1.0, 0), turf + Vector3(0, 1.0, 0), GC.M_LOS, []):
				spot = gp + Vector3(0, 1.7, 0)
				found = true
				break
		if found:
			break
	print("TEST info gang camera spot found=%s spot=%s turf=%s" % [found, str(spot), str(turf)])
	var to_turf := Util.flat(turf - spot).normalized()
	var pl = Game.player
	var ppos := spot + to_turf * 2.8
	ppos.y = _ground_at(ppos).y if _ground_at(ppos) != Vector3.INF else spot.y - 1.7
	_teleport_player(ppos + Vector3(0, 0.1, 0), rad_to_deg(Util.dir_to_yaw(to_turf)))
	pl.weapons.give_weapon(&"smg", 200, true)
	await _wait(0.5)
	# the player raises the weapon: the gang reacts
	var members: Array = g["members"]
	for m in members:
		if is_instance_valid(m):
			(m as GangNpc).provoke(pl)
	_place_cam(spot + Vector3(0, 0.1, 0) - to_turf * 0.0 + Util.flat(to_turf).cross(Vector3.UP) * 0.9, turf + Vector3(0, 1.2, 0))
	await _wait(float(_arg("wait", "3.5")))
	var vc := get_viewport().get_camera_3d()
	print("TEST info gang active cam=%s pos=%s shotcam=%s pos=%s player=%s" % [vc.name if vc else "-", str(vc.global_position) if vc else "-", cam.current, str(cam.global_position), str(pl.global_position)])
	for m in members:
		if is_instance_valid(m):
			print("TEST info gang member %s pos=%s state=%s" % [m.name, str((m as Node3D).global_position), (m as GangNpc).brain.describe()])


func _ground_at(p: Vector3) -> Vector3:
	var space := (Game.world as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6.0, 0), p + Vector3(0, -8.0, 0), GC.L_WORLD)
	var h := space.intersect_ray(q)
	if h.is_empty() or absf((h["normal"] as Vector3).y) < 0.8:
		return Vector3.INF
	return h["position"]




