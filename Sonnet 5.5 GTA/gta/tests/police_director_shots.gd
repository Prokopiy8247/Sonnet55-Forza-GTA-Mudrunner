extends Node
## Police-A screenshot scenes (real renderer, real WantedSystem + PoliceManager + Police-B units). Usage:
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\police\pursuit.png -GameArgs "--exec=res://gta/tests/police_director_shots.gd --scene=pursuit --time=19.3 --delay=3 --no-traffic --no-peds"
## scenes: pursuit (dusk chase, player car driven along the lanes, 3 stars), roadblock (4 stars, the block ahead), search (on foot, stars flashing),
##         busted (the arrest). The standard gameplay camera is used so the HUD (stars, minimap) is part of the picture.

var player: Player
var wanted: WantedSystem
var pm: PoliceManager
var veh: VehicleBase = null
var drive_on := false
var drive_speed := 14.0
var lane_i := -1
var scene_name := "pursuit"
var cam: Camera3D = null
var cam_mode := ""          # "front": in front of the player car looking back at the chasers; "behind": behind it looking at the roadblock
var cam_target := Vector3.ZERO


func _arg(key: String, default_v: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
	return default_v


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A lane point that starts a long, straight, junction-free run of road (the chase needs room to breathe).
func _straight_start() -> int:
	var lanes: LaneGraph = WorldLayout.lanes
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var best := -1
	var best_score := -1e9
	for k in 500:
		var i0 := rng.randi() % lanes.size()
		var p0 := lanes.positions[i0]
		if absf(p0.x) > 230.0 or absf(p0.z) > 230.0 or lanes.kind[i0] == LaneGraph.KIND_CONNECTOR:
			continue
		var d0 := Util.flat(lanes.dirs[i0]).normalized()
		var cur := i0
		var dist := 0.0
		var conns := 0
		var dev := 1.0
		while dist < 420.0:
			var nx: PackedInt32Array = lanes.next[cur]
			if nx.is_empty():
				break
			var pick: int = nx[0]
			var bd := -2.0
			for o in nx:
				var od := Util.flat(lanes.positions[o] - lanes.positions[cur]).normalized()
				if od.dot(d0) > bd:
					bd = od.dot(d0)
					pick = o
			dist += lanes.positions[pick].distance_to(lanes.positions[cur])
			if lanes.kind[pick] == LaneGraph.KIND_CONNECTOR:
				conns += 1
			dev = minf(dev, Util.flat(lanes.dirs[pick]).normalized().dot(d0))
			cur = pick
		var score := dist - float(conns) * 25.0 + dev * 120.0
		if score > best_score:
			best_score = score
			best = i0
	return best


func _street_pos() -> Vector3:
	var lanes: LaneGraph = WorldLayout.lanes
	var i := lanes.nearest(WorldLayout.location_pos(&"player_spawn"), Vector3.ZERO, 80.0)
	return (lanes.positions[i] + Vector3(0, 0.3, 0)) if i >= 0 else WorldLayout.location_pos(&"player_spawn")


func _physics_process(_dt: float) -> void:
	if drive_on:
		_drive()


func _nearest_police_car() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if is_instance_valid(n) and n is VehicleBase and n.vclass == GC.VC_CAR and not n.is_queued_for_deletion():
			var d := Util.dist_xz((n as Node3D).global_position, player.global_position)
			if d < bd and d > 6.0:
				bd = d
				best = n
	return best


func _process(_dt: float) -> void:
	if cam != null and cam_mode == "orbit":
		var tgt := _nearest_police_car()
		if tgt != null:
			var away := Util.flat(player.global_position - tgt.global_position)
			away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
			var want := player.global_position + away * 4.2 + Vector3(0, 2.1, 0) + Vector3(away.z, 0, -away.x) * 1.0
			cam.global_position = cam.global_position.lerp(want, 0.15) if cam.global_position.length() > 1.0 else want
			cam.look_at(tgt.global_position + Vector3(0, 1.0, 0), Vector3.UP)
		return
	if cam == null or cam_mode == "" or veh == null or not is_instance_valid(veh):
		return
	var fwd := Util.flat(-veh.global_transform.basis.z).normalized()
	var p := veh.global_position
	var want := Vector3.ZERO
	var look := Vector3.ZERO
	if cam_mode == "front":
		want = p + fwd * 15.0 + Vector3(0, 3.6, 0) + Vector3(fwd.z, 0, -fwd.x) * 2.2
		look = p - fwd * 14.0 + Vector3(0, 0.8, 0)
	else:
		want = p - fwd * 9.0 + Vector3(0, 3.4, 0)
		look = cam_target + Vector3(0, 1.2, 0)
	cam.global_position = cam.global_position.lerp(want, 0.18) if cam.global_position.length() > 1.0 else want
	cam.look_at(look, Vector3.UP)


func _make_cam(mode: String) -> void:
	cam = Camera3D.new()
	cam.name = "ShotCam"
	cam.fov = 66.0
	cam.far = 900.0
	add_child(cam)
	cam.make_current()
	cam_mode = mode


func _drive() -> void:
	if veh == null or not is_instance_valid(veh) or not player.is_in_vehicle():
		return
	var lanes: LaneGraph = WorldLayout.lanes
	var pos := veh.global_position
	var fwd := Util.flat(-veh.global_transform.basis.z).normalized()
	if lane_i < 0:
		lane_i = lanes.nearest(pos, fwd, 25.0)
		if lane_i < 0:
			return
	var guard := 0
	while Util.dist_xz(lanes.positions[lane_i], pos) < 16.0 and guard < 8:
		var nx: PackedInt32Array = lanes.next[lane_i]
		if nx.is_empty():
			break
		var best: int = nx[0]
		var best_dot := -2.0
		for o in nx:
			var od: Vector3 = Util.flat(lanes.positions[o] - lanes.positions[lane_i])
			if od.length() > 0.01 and od.normalized().dot(fwd) > best_dot:
				best_dot = od.normalized().dot(fwd)
				best = o
		lane_i = best
		guard += 1
	var to := Util.flat(lanes.positions[lane_i] - pos)
	if to.length() < 0.1:
		return
	to = to.normalized()
	var steer := clampf((fwd.x * to.z - fwd.z * to.x) * 2.2, -1.0, 1.0)
	var spd := veh.linear_velocity.length()
	# slow down for bends: compare the heading now with the heading of the lane ~35 m further
	var far_i := lane_i
	var run := 0.0
	for k in 6:
		var nx2: PackedInt32Array = lanes.next[far_i]
		if nx2.is_empty():
			break
		run += lanes.positions[nx2[0]].distance_to(lanes.positions[far_i])
		far_i = nx2[0]
		if run > 35.0:
			break
	var bend := 1.0 - clampf(fwd.dot(Util.flat(lanes.positions[far_i] - pos).normalized()), -1.0, 1.0)
	var target_speed := lerpf(drive_speed, 6.0, clampf(bend * 6.0, 0.0, 1.0))
	var thr := 1.0 if spd < target_speed else (-0.5 if spd > target_speed + 3.0 else 0.0)
	if drive_speed < 0.5:
		thr = -0.8 if spd > 1.0 else 0.0
	player.cmd_move = Vector2(steer, thr)


func _start_car() -> bool:
	var lanes: LaneGraph = WorldLayout.lanes
	var start := _straight_start()
	if start < 0:
		return false
	print("SHOT start lane %d at %s" % [start, str(lanes.positions[start])])
	var dirv := lanes.dirs[start]
	veh = VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dirv)), lanes.positions[start] + Vector3(0, 0.5, 0)), {"abandoned": true})
	if veh == null:
		return false
	await _frames(30)
	player.teleport_to(veh.global_position + Vector3(2.0, 0.4, 0.0), Util.dir_to_yaw(dirv))
	await _frames(10)
	player.enter_vehicle(veh, 0)
	await _frames(90)
	lane_i = -1
	drive_on = true
	return player.is_in_vehicle()


func _police_near(radius: float) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if is_instance_valid(n) and n is VehicleBase and n.vclass == GC.VC_CAR and not n.is_queued_for_deletion():
			if Util.dist_xz((n as Node3D).global_position, player.global_position) <= radius:
				out.append(n)
	return out


func run(_main: Node) -> String:
	player = Game.player as Player
	wanted = Game.sys(&"wanted") as WantedSystem
	pm = Game.sys(&"police") as PoliceManager
	scene_name = _arg("scene", "pursuit")
	player.use_real_input = false
	Game.cheats["invulnerable"] = true
	PoliceOfficer.arrest_enabled = scene_name == "busted"
	wanted.bust_quiet_time = 2.0 if scene_name == "busted" else 1e9
	wanted.hail_enabled = false
	if _arg("heli", "0") != "1":
		pm.heli_spawner = func(_pos: Vector3) -> Node: return null     # the heli searchlight cone veils the screen when it hovers over the camera
	match scene_name:
		"pursuit":
			await _pursuit()
		"chase":
			await _chase()
		"roadblock":
			await _roadblock()
		"search":
			await _search()
		"busted":
			await _busted()
	return "scene " + scene_name


func _pursuit() -> void:
	## dusk, 3 stars, the player stands in the street (standard gameplay camera): cars arrive with their sirens on, officers deploy
	await _frames(20)
	player.teleport_to(_street_pos(), 0.0)
	await _frames(40)
	wanted.set_level(3)
	if _arg("cam", "orbit") == "orbit":
		_make_cam("orbit")
	var t := 0.0
	var tgt: Node3D = null
	while t < 110.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		tgt = _nearest_police_car()
		if tgt != null and t > 15.0 and Util.dist_xz(tgt.global_position, player.global_position) < 42.0:
			break
	if tgt != null and cam == null:
		var dirv := Util.flat(tgt.global_position - player.global_position).normalized()
		var yaw := Util.dir_to_yaw(dirv)
		player.teleport_to(player.global_position, yaw)
		if player.camera != null and player.camera.has_method("snap_behind"):
			player.camera.snap_behind(yaw)
	print("SHOT pursuit t=%.0f level=%d state=%s stats=%s" % [t, wanted.level, String(wanted.state), str(pm.get_stats())])
	await _frames(70)


func _chase() -> void:
	## the player drives along the lanes at 3 stars; the camera sits in front of the car looking back at the chasers
	await _frames(20)
	player.teleport_to(_street_pos(), 0.0)
	await _frames(40)
	if not await _start_car():
		print("SHOT chase: no car")
		return
	wanted.set_level(3)
	_make_cam("front")
	var t := 0.0
	var close := 0
	while t < 95.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		close = _police_near(36.0).size()
		if close >= 2 and t > 25.0:
			break
	print("SHOT chase t=%.0f cars_within_36m=%d level=%d state=%s stats=%s" % [t, close, wanted.level, String(wanted.state), str(pm.get_stats())])
	await _frames(40)


func _roadblock() -> void:
	## RoadblockPlanner picks the site ahead on the lane graph, the director registers the PoliceUnits roadblock; the player (on foot,
	## standard camera) stands 45 m in front of it looking at it.
	await _frames(20)
	var lanes: LaneGraph = WorldLayout.lanes
	var plan := {}
	var heading := Vector3(0, 0, -1)
	var tries := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	while plan.is_empty() and tries < 60:
		tries += 1
		var start := lanes.nearest(_street_pos(), Vector3.ZERO, 80.0) if tries == 1 else (rng.randi() % lanes.size())
		if absf(lanes.positions[start].x) > 240.0 or absf(lanes.positions[start].z) > 240.0:
			continue
		heading = Util.flat(lanes.dirs[start]).normalized()
		plan = RoadblockPlanner.plan(lanes, lanes.positions[start], heading, null, pm.director.rng, null, [])
		if not plan.is_empty():
			player.teleport_to(lanes.positions[start] + Vector3(0, 0.4, 0), Util.dir_to_yaw(heading))
	await _frames(40)
	wanted.set_level(4)
	if plan.is_empty():
		print("SHOT roadblock: no plan")
		return
	var node: Variant = pm._f_roadblock(plan["road_center"], plan["dir"], 4)
	if node == null:
		print("SHOT roadblock: factory refused")
		return
	var rec := pm._register(node, &"roadblock", &"block")
	rec["block_pos"] = plan["road_center"]
	rec["block_dir"] = plan["dir"]
	# walk back along the lane from the block to a point ~45 m before it and stand there
	var idx: int = plan["idx"]
	var run := 0.0
	while run < 26.0:
		var pv: PackedInt32Array = lanes.prev[idx]
		if pv.is_empty():
			break
		run += lanes.positions[pv[0]].distance_to(lanes.positions[idx])
		idx = pv[0]
	var stand := lanes.positions[idx] + Vector3(1.6, 0.4, 0)
	var face := Util.flat((plan["road_center"] as Vector3) - stand).normalized()
	player.teleport_to(stand, Util.dir_to_yaw(face))
	await _frames(5)
	if player.camera != null and player.camera.has_method("snap_behind"):
		player.camera.snap_behind(Util.dir_to_yaw(face))
	print("SHOT roadblock plan ahead=%.0f block at %s player at %s" % [float(plan["ahead"]), str(plan["road_center"]), str(stand)])
	var t := 0.0
	while t < 7.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _search() -> void:
	await _frames(20)
	player.teleport_to(_street_pos(), 0.0)
	await _frames(40)
	wanted.set_level(3)
	# nobody has seen the player for 6 s -> SEARCH: the stars flash
	var t := 0.0
	while t < 14.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("SHOT search: %s" % wanted.get_debug_string())


func _busted() -> void:
	await _frames(20)
	player.teleport_to(_street_pos(), 0.0)
	await _frames(40)
	wanted.set_level(1)
	var t := 0.0
	while t < 90.0 and Game.player.get("move_mode") != Player.Move.BUSTED:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("SHOT busted after %.0f s" % t)
	await _frames(40)
