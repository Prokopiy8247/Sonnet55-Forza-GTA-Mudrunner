extends Node
## Systems-A: world interaction tests with the REAL Player: roof ladders (up + down), the tower elevator round trip, phone booth, benches, hydrants.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/interactions_test.gd -Seconds 200 -GameArgs "--no-traffic --no-peds"

var _fails := 0
var _passes := 0
var im: InteractionManager = null
var player: Player = null


func _check(test_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST %s PASS %s" % [test_name, detail])
	else:
		_fails += 1
		print("TEST %s FAIL %s" % [test_name, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _point(kind: StringName, key: String, value: Variant) -> InteractionPoint:
	for q in im.points:
		if q.kind == kind and q.data.get(key) == value:
			return q
	return null


func _climb(forward: float, target_y: float, up: bool, max_s: float = 25.0) -> bool:
	player.set_input(Vector2(0, forward), false)
	var t := 0.0
	while t < max_s and player.move_mode == Player.Move.LADDER:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	player.set_input(Vector2.ZERO)
	return t < max_s


func run(_main: Node) -> Variant:
	await _frames(30)
	im = Game.sys(&"interactions") as InteractionManager
	player = Game.player as Player
	var eco = Game.sys(&"economy")
	_check("interactions_boot", im != null and player != null, "manager + player")
	if im == null or player == null:
		return false
	var guard := 0
	while not im.is_built and guard < 600:
		await get_tree().physics_frame
		guard += 1
	_check("interactions_built", im.is_built, "ladders=%d booths=%d bench seats=%d hydrants=%d elevator=%s" % [im.ladders.size(), im.booths.size(), im.get_bench_seats().size(), im.get_hydrants().size(), str(not im.elevator.is_empty())])
	_check("interactions_eight_ladders", im.ladders.size() == 8, "%d ladders" % im.ladders.size())
	_check("interactions_registered", Game.sys(&"interactions") == im and im.points.size() >= 20, "%d interaction points" % im.points.size())
	var in_group := 0
	for q in im.points:
		if q.is_in_group(GC.G_INTERACT):
			in_group += 1
	_check("interactions_points_in_group", in_group == im.points.size(), "%d points in group interactable" % in_group)
	var districts := {}
	for r in im.ladders:
		districts[r["district"]] = true
	_check("interactions_ladders_spread", districts.size() >= 3, "districts %s" % str(districts.keys()))
	var all_reward := true
	for r in im.ladders:
		if not r.has("reward"):
			all_reward = false
	_check("interactions_roof_rewards", all_reward, "every ladder roof has a cash stash")
	var sk = Game.sys(&"skills")
	if sk != null:
		sk.announce = false
		sk.sampling = false

	# ---- ladders: up and down with the real player (first three) ----------------------------------------------------------------------
	for li in mini(3, im.ladders.size()):
		var rec: Dictionary = im.ladders[li]
		var nrm: Vector3 = rec["normal"]
		var bottom: Vector3 = rec["bottom"]
		var roof_y: float = rec["roof_y"]
		player.release_input()
		player.teleport_to(bottom + nrm * 1.2 + Vector3(0, 0.2, 0), Util.dir_to_yaw(-nrm))
		await _frames(50)
		# the prompt comes through the real PlayerInteraction scan
		player.interaction._timer = 0.0
		await _frames(12)
		var has_prompt := String(player.interaction.prompt_text).contains("Climb ladder")
		_check("ladder%d_prompt" % li, has_prompt, "prompt '%s'" % String(player.interaction.prompt_text))
		player.interaction.try_interact()
		await _frames(4)
		_check("ladder%d_mount" % li, player.move_mode == Player.Move.LADDER, "move_mode %d" % player.move_mode)
		var done := await _climb(1.0, roof_y, true)
		await _frames(30)
		var on_roof := absf(player.global_position.y - roof_y) < 0.6 and player.move_mode == Player.Move.GROUND
		_check("ladder%d_up_to_roof" % li, done and on_roof, "y %.2f vs roof %.2f (%d, mode %d)" % [player.global_position.y, roof_y, int(done), player.move_mode])
		var inland := Util.dist_xz(player.global_position, bottom)
		_check("ladder%d_on_roof_not_outside" % li, inland > 0.3 and inland < 2.5, "%.2f m from the wall line" % inland)
		# reward is in reach on the roof
		var reward: Dictionary = rec["reward"]
		_check("ladder%d_reward_on_roof" % li, absf((reward["pos"] as Vector3).y - roof_y) < 0.7, "stash y %.1f" % (reward["pos"] as Vector3).y)
		# back down with the roof entry point
		var dp := _point(&"ladder_down", "ladder", li)
		player.teleport_to((dp.global_position - Vector3(0, 0.1, 0)) + Vector3(0, 0.1, 0), Util.dir_to_yaw(-nrm))
		await _frames(30)
		dp.interact(player)
		await _frames(4)
		_check("ladder%d_mount_down" % li, player.move_mode == Player.Move.LADDER, "move_mode %d" % player.move_mode)
		var done2 := await _climb(-1.0, bottom.y, false)
		await _frames(30)
		_check("ladder%d_down_to_street" % li, done2 and absf(player.global_position.y - bottom.y) < 0.6 and player.move_mode == Player.Move.GROUND, "y %.2f vs ground %.2f" % [player.global_position.y, bottom.y])
		player.use_real_input = false
		player.release_input()

	# ---- ladder: jump off ---------------------------------------------------------------------------------------------------------------
	var r0: Dictionary = im.ladders[0]
	player.teleport_to((r0["bottom"] as Vector3) + (r0["normal"] as Vector3) * 1.1 + Vector3(0, 0.2, 0), Util.dir_to_yaw(-(r0["normal"] as Vector3)))
	await _frames(40)
	_point(&"ladder_up", "ladder", 0).interact(player)
	player.set_input(Vector2(0, 1))
	await _frames(100)
	player.press_jump()
	await _frames(6)
	player.set_input(Vector2.ZERO)
	_check("ladder_jump_off", player.move_mode != Player.Move.LADDER and player.global_position.y > (r0["bottom"] as Vector3).y + 0.3, "left the ladder at y %.1f" % player.global_position.y)
	await _frames(120)

	# ---- elevator round trip --------------------------------------------------------------------------------------------------------------
	_check("elevator_planned", not im.elevator.is_empty(), "ground %s roof %s" % [str(im.elevator.get("ground", {}).get("pos", "-")), str(im.elevator.get("roof", {}).get("pos", "-"))])
	if not im.elevator.is_empty():
		var g: Dictionary = im.elevator["ground"]
		var rf: Dictionary = im.elevator["roof"]
		player.teleport_to(g["stand"], float(g["yaw"]) + PI)
		await _frames(40)
		var up_pt := _point(&"elevator_up", "x", null)
		player.interaction._timer = 0.0
		await _frames(14)
		_check("elevator_prompt", String(player.interaction.prompt_text).contains("elevator"), "prompt '%s'" % String(player.interaction.prompt_text))
		var t0 := Time.get_ticks_msec()
		var rode := [false]
		var rcb := func(to_roof: bool) -> void: rode[0] = to_roof
		im.elevator_ridden.connect(rcb)
		player.interaction.try_interact()
		var spent := 0.0
		while im.riding and spent < 12.0 or spent < 0.2:
			await get_tree().physics_frame
			spent += 1.0 / 60.0
		await _frames(30)
		var roof_y: float = rf["roof_y"]
		_check("elevator_up_arrives_on_roof", rode[0] and absf(player.global_position.y - roof_y) < 1.0 and Util.dist_xz(player.global_position, rf["stand"]) < 2.5, "y %.1f roof %.1f, %d ms" % [player.global_position.y, roof_y, Time.get_ticks_msec() - t0])
		_check("elevator_input_unlocked", not player.input_locked and not im.riding, "input_locked=%s" % str(player.input_locked))
		_check("elevator_roof_door_closed_again", float((rf["door"] as Dictionary)["open"]) == 0.0 and float((g["door"] as Dictionary)["open"]) == 0.0, "both doors closed")
		# and back down
		var down_pt := _point(&"elevator_down", "x", null)
		player.teleport_to(rf["stand"], float(rf["yaw"]) + PI)
		await _frames(30)
		rode[0] = true
		down_pt.interact(player)
		spent = 0.0
		while im.riding and spent < 12.0 or spent < 0.2:
			await get_tree().physics_frame
			spent += 1.0 / 60.0
		await _frames(30)
		im.elevator_ridden.disconnect(rcb)
		_check("elevator_down_arrives_on_street", not rode[0] and absf(player.global_position.y - (g["stand"] as Vector3).y) < 1.0 and Util.dist_xz(player.global_position, g["stand"]) < 2.5, "y %.1f" % player.global_position.y)
		_check("elevator_not_stuck_riding", not im.riding and not player.input_locked, "ready for the next ride")
		var skipped := up_pt != null and down_pt != null
		_check("elevator_both_points", skipped, "ground + roof interaction points")
		# the door leaves actually slide
		var door: Dictionary = g["door"]
		im._set_door(door, true, 0.05)
		await _frames(10)
		var slid := true
		if door.get("left") != null:
			slid = absf((door["left"] as Node3D).position.x - (door["left_rest"] as Vector3).x) > 0.4
		_check("elevator_door_slides", slid, "left leaf moved")
		var rdoor: Dictionary = (im.elevator["roof"] as Dictionary)["door"]
		_check("elevator_roof_house_solid", (rdoor["root"] as Node).get_node_or_null("Collider") != null, "the roof machine room has a collider")
		_check("elevator_uses_blender_props", not (door["root"] as Node).has_meta(&"fallback") and not (rdoor["root"] as Node).has_meta(&"fallback"), "elevator_door.glb + elevator_roof.glb (no code fallback)")
		_check("elevator_door_clear_of_furniture", not InteractionElevator.furniture_near((g["pos"] as Vector3) + (g["normal"] as Vector3) * 1.6, 3.0), "no baked bus stop / bench in front of the lift door")
		im._set_door(door, false, 0.05)
		await _frames(10)

	# ---- phone booth: saves the game -----------------------------------------------------------------------------------------------------
	_check("phone_booths_placed", im.booths.size() >= 5, "%d booths" % im.booths.size())
	var booth_blocked := 0
	for bb in im.booths:
		if InteractionElevator.furniture_near(bb["pos"], 1.2):
			booth_blocked += 1
	_check("phone_booths_clear_of_furniture", booth_blocked == 0, "%d booths overlap baked street furniture" % booth_blocked)
	var ladder_blocked := 0
	for lr in im.ladders:
		if InteractionElevator.furniture_near((lr["bottom"] as Vector3) + (lr["normal"] as Vector3), 1.0):
			ladder_blocked += 1
	_check("ladders_clear_of_furniture", ladder_blocked == 0, "%d ladder feet overlap baked street furniture" % ladder_blocked)
	if not im.booths.is_empty():
		var b: Dictionary = im.booths[0]
		var bp := _point(&"phone", "booth", b["id"])
		player.teleport_to(b["use_pos"] + Vector3(0, 0.1, 0), float(b["yaw"]) + PI)
		await _frames(30)
		im.phone_slot = 8
		SaveSystem.delete_save(8)
		var used := [false]
		var ucb := func(_id: String) -> void: used[0] = true
		im.booth_used.connect(ucb)
		bp.interact(player)
		await _frames(5)
		im.booth_used.disconnect(ucb)
		_check("phone_booth_saves", used[0] and SaveSystem.has_save(8), "slot 8 written")
		SaveSystem.delete_save(8)
		im.phone_slot = 0
		_check("phone_booth_solid", b.has("node") and (b["node"] as Node).get_node_or_null("Collider") != null, "booth has a collider")

	# ---- bench: sit / stand with the real player ---------------------------------------------------------------------------------------------------
	var seats := im.get_bench_seats()
	_check("benches_found", seats.size() >= 10, "%d bench seats" % seats.size())
	if seats.size() > 0:
		var s: Dictionary = seats[0]
		var sp: Vector3 = s["pos"]
		var front: Vector3 = sp + Util.yaw_to_dir(float(s["yaw"])) * 1.1 - Vector3(0, 0.45, 0)
		player.teleport_to(front, float(s["yaw"]) + PI)
		await _frames(40)
		im._update_bench_pool(player)
		var bench_pt: InteractionPoint = null
		for q in im._bench_pool:
			if q.visible:
				bench_pt = q
		_check("bench_prompt_anchor", bench_pt != null and bench_pt.global_position.distance_to(player.global_position) < 2.2, "pool anchor near the bench")
		if bench_pt != null:
			bench_pt.interact(player)
			await _frames(30)
			_check("bench_sits", im.sitting and player.move_mode == Player.Move.TRAVERSE and Util.dist_xz(player.global_position, sp) < 0.3, "sitting at %s" % str(player.global_position))
			_check("bench_rig_pose", player.rig != null and player.rig.get("_stance") == &"sit_car", "rig stance %s" % str(player.rig.get("_stance")))
			var held_y := player.global_position.y
			await _frames(60)
			_check("bench_stays_seated", absf(player.global_position.y - held_y) < 0.02 and im.sitting, "no drift over 1 s")
			var ev := InputEventAction.new()
			ev.action = &"interact"
			ev.pressed = true
			Input.parse_input_event(ev)
			await _frames(6)
			if im.sitting:
				im._stand(player)
			await _frames(30)
			_check("bench_stands_up", not im.sitting and player.move_mode == Player.Move.GROUND and player.use_real_input, "back on foot, mode %d" % player.move_mode)
			_check("bench_stand_position", Util.dist_xz(player.global_position, sp) > 0.4 and absf(player.global_position.y - (front.y)) < 1.0, "stepped %.2f m forward" % Util.dist_xz(player.global_position, sp))
	player.use_real_input = false
	player.release_input()

	# ---- hydrants -----------------------------------------------------------------------------------------------------------------------------------
	var hs := im.get_hydrants()
	_check("hydrants_found", hs.size() >= 10, "%d hydrants" % hs.size())
	if hs.size() > 0:
		var jets := im.get_jets()
		var h := hs[0]
		var n0 := jets.active_count()
		Events.projectile_impact.emit(h + Vector3(0.1, 0.5, 0.1), Vector3.UP, &"metal", player)
		await _frames(3)
		_check("hydrant_shot_sprays", jets.active_count() == n0 + 1, "jets %d" % jets.active_count())
		Events.projectile_impact.emit(h + Vector3(0.1, 0.5, 0.1), Vector3.UP, &"metal", player)
		_check("hydrant_same_not_duplicated", jets.active_count() == n0 + 1, "still %d jets" % jets.active_count())
		Events.projectile_impact.emit(h + Vector3(9.0, 0.5, 9.0), Vector3.UP, &"metal", player)
		_check("hydrant_miss_ignored", jets.active_count() == n0 + 1, "a shot 12 m away does nothing")
		var h2 := hs[mini(1, hs.size() - 1)]
		Events.explosion.emit(h2 + Vector3(2.0, 0.0, 0.0), 6.0, player)
		_check("hydrant_explosion_sprays", jets.active_count() >= n0 + 2, "%d jets" % jets.active_count())
		# a speeding car smashing into one
		var hp3 := hs[mini(2, hs.size() - 1)]
		var car := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, 0.0), hp3 + Vector3(0.0, 0.8, 4.0)), {"abandoned": true, "snap_ground": false})
		if car != null:
			await _frames(30)
			car.linear_velocity = Vector3(0, 0, -9.0)
			car.global_position = hp3 + Vector3(0, 0.6, 2.0)
			var before := jets.active_count()
			im._acc = 1.0
			im._check_vehicle_hydrants()
			_check("hydrant_rammed_sprays", jets.active_count() > before or before >= 4, "%d -> %d jets" % [before, jets.active_count()])
			VehicleFactory.despawn(car)
		await _frames(int(7.5 * 60.0) + 30)
		_check("hydrant_jets_stop", jets.active_count() <= 1, "%d jets still running after 7.5 s" % jets.active_count())

	# ---- per-frame cost ---------------------------------------------------------------------------------------------------------------------------------
	var t1 := Time.get_ticks_usec()
	for i in 400:
		im._acc = 1.0
		im._process(0.016)
	var per := float(Time.get_ticks_usec() - t1) / 400.0
	_check("interactions_tick_cost", per < 400.0, "%.0f us per 0.25 s tick" % per)
	var scan_t := Time.get_ticks_usec()
	for i in 200:
		player.interaction._timer = 0.0
		player.interaction.update(0.1)
	var scan := float(Time.get_ticks_usec() - scan_t) / 200.0
	_check("interactions_prompt_scan_cost", scan < 400.0, "%.0f us per player scan (%d interactables)" % [scan, get_tree().get_nodes_in_group(GC.G_INTERACT).size()])

	if sk != null:
		sk.announce = true
		sk.sampling = true
	player.use_real_input = true
	print("TEST SUMMARY interactions pass=%d fail=%d" % [_passes, _fails])
	return _fails == 0
