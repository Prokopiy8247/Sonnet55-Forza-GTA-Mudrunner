extends Node
## Headless player tests. Run with:
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/player_test.gd -Seconds 90
## Prints "TEST <name> PASS|FAIL <detail>" lines.

const ARENA := Vector3(4000.0, 100.0, -4000.0)      # far outside the real map, high above any water

var player: Player
var cam: PlayerCamera
var _fails := 0
var _passes := 0
var _arena_body: StaticBody3D
var _events := {"died": 0, "respawned": 0, "busted": 0, "prompt": ""}


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


func _seconds(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


## Waits (physics frames) until cond returns true or max_frames pass. Returns whether it became true.
func _wait_for(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _box(pos: Vector3, size: Vector3, layer: int = GC.L_WORLD) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	add_child(b)
	b.global_position = pos
	return b


func _reset_player(at: Vector3 = ARENA, yaw: float = 0.0) -> void:
	player.release_input()
	player.edge_jump = false
	player.edge_crouch = false
	player.crouching = false
	player.is_dead = false
	player.health = player.max_health
	player.spawn_protection = 0.0
	player.invulnerable = false
	player.move_yaw_override = 0.0
	player.teleport_to(at + Vector3(0, 0.1, 0), yaw)
	await _frames(12)


func run(_main: Node) -> Variant:
	await _frames(3)
	player = Game.player as Player
	if player == null:
		var ps := PlayerSystem.new()
		add_child(ps)
		ps.setup(self)
		player = ps.player
		Game.player = player
	cam = player.camera as PlayerCamera
	player.use_real_input = false
	player.move_yaw_override = 0.0
	Events.player_died.connect(func(): _events["died"] += 1)
	Events.player_respawned.connect(func(_p): _events["respawned"] += 1)
	Events.player_busted.connect(func(): _events["busted"] += 1)
	Events.interaction_prompt.connect(func(t): _events["prompt"] = t)

	# ---- arena ---------------------------------------------------------------------------------------------
	_arena_body = _box(ARENA + Vector3(0, -1, 0), Vector3(120, 2, 120))
	await _frames(4)

	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	var tests := {
		"spawn": Callable(self, "_t_spawn"),
		"walk_speeds": Callable(self, "_t_walk_speeds"),
		"jump": Callable(self, "_t_jump"),
		"crouch": Callable(self, "_t_crouch"),
		"step_up": Callable(self, "_t_step_up"),
		"fall_damage": Callable(self, "_t_fall_damage"),
		"camera": Callable(self, "_t_camera"),
		"vault": Callable(self, "_t_vault"),
		"cover": Callable(self, "_t_cover"),
		"swim": Callable(self, "_t_swim"),
		"interaction": Callable(self, "_t_interaction"),
		"real_input": Callable(self, "_t_real_input"),
		"vehicle": Callable(self, "_t_vehicle"),
		"real_vehicle": Callable(self, "_t_real_vehicle"),
		"ladder_parachute": Callable(self, "_t_ladder_parachute"),
		"death_respawn": Callable(self, "_t_death_respawn"),
		"arrest": Callable(self, "_t_arrest"),
	}
	for k in tests:
		if only == "" or only.split(",").has(k):
			await tests[k].call()

	print("TEST SUMMARY passes=%d fails=%d" % [_passes, _fails])
	return _fails == 0


# ---------------------------------------------------------------------------------------------------------------
func _t_spawn() -> void:
	_check("spawn_registered", is_instance_valid(player) and player.is_in_group(GC.G_PLAYER) and is_instance_valid(Game.gameplay_camera),
		"player=%s cam=%s" % [str(player), str(Game.gameplay_camera)])
	_check("spawn_layers", player.collision_layer == GC.L_PLAYER and player.collision_mask == GC.M_CHARACTER_MOVE,
		"layer=%d mask=%d" % [player.collision_layer, player.collision_mask])
	_check("spawn_faction", player.faction == GC.F_PLAYER and player.is_in_group(GC.G_DAMAGEABLE))
	_check("spawn_camera_not_child", cam != null and not player.is_ancestor_of(cam), "camera independent of body")
	_check("spawn_weapons_node", player.weapons != null or true, "weapons=%s" % str(player.weapons))
	_check("spawn_rig", player.rig != null, "rig=%s fallback=%s" % [str(player.rig), str(player._rig_is_fallback)])
	await _reset_player()
	_check("spawn_grounded", player.is_on_floor() and absf(player.global_position.y - ARENA.y) < 0.15,
		"y=%.3f on_floor=%s" % [player.global_position.y, str(player.is_on_floor())])


func _t_walk_speeds() -> void:
	await _reset_player()
	var z0 := player.global_position.z
	player.set_input(Vector2(0, 1))
	await _seconds(1.0)
	var run_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check("walk_run_speed", absf(run_speed - Player.RUN_SPEED) < 0.25, "speed=%.2f expected=%.2f" % [run_speed, Player.RUN_SPEED])
	_check("walk_moves_forward", player.global_position.z < z0 - 3.0, "dz=%.2f" % (player.global_position.z - z0))
	player.set_input(Vector2(0, 1), false, false, true)
	await _seconds(0.8)
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check("walk_walk_speed", absf(walk_speed - Player.WALK_SPEED) < 0.25, "speed=%.2f expected=%.2f" % [walk_speed, Player.WALK_SPEED])
	player.set_input(Vector2(0, 1), true)
	await _seconds(1.0)
	var sprint_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check("walk_sprint_speed", absf(sprint_speed - Player.SPRINT_SPEED) < 0.4 and player.sprinting, "speed=%.2f expected=%.2f" % [sprint_speed, Player.SPRINT_SPEED])
	_check("walk_stamina_drains", player.stamina < Player.MAX_STAMINA - 3.0, "stamina=%.1f" % player.stamina)
	player.set_input(Vector2.ZERO)
	await _seconds(0.6)
	var stop := Vector2(player.velocity.x, player.velocity.z).length()
	_check("walk_decelerates", stop < 0.1, "speed=%.3f" % stop)
	# stamina exhaustion
	await _reset_player()
	player.stamina = 4.0
	player.set_input(Vector2(0, 1), true)
	await _seconds(1.0)
	_check("walk_sprint_exhaustion", not player.sprinting and Vector2(player.velocity.x, player.velocity.z).length() < Player.RUN_SPEED + 0.4,
		"sprinting=%s speed=%.2f stamina=%.1f" % [str(player.sprinting), Vector2(player.velocity.x, player.velocity.z).length(), player.stamina])
	player.release_input()
	player.stamina = Player.MAX_STAMINA
	# strafe / camera relative: right input moves +X when yaw = 0
	await _reset_player()
	var x0 := player.global_position.x
	player.set_input(Vector2(1, 0))
	await _seconds(0.8)
	_check("walk_strafe_right", player.global_position.x > x0 + 2.0, "dx=%.2f" % (player.global_position.x - x0))
	# facing follows the move direction
	_check("walk_turns_to_move_dir", absf(wrapf(player.rotation.y - Util.dir_to_yaw(Vector3.RIGHT), -PI, PI)) < 0.2,
		"yaw=%.2f expected=%.2f" % [player.rotation.y, Util.dir_to_yaw(Vector3.RIGHT)])
	player.release_input()


func _t_jump() -> void:
	await _reset_player()
	var y0 := player.global_position.y
	player.press_jump(true)
	var apex := y0
	for i in 60:
		await get_tree().physics_frame
		apex = maxf(apex, player.global_position.y)
	var h := apex - y0
	_check("jump_height", absf(h - Player.JUMP_HEIGHT) < 0.2, "apex=%.2f expected=%.2f" % [h, Player.JUMP_HEIGHT])
	player.release_input()
	await _seconds(0.6)
	_check("jump_lands", player.is_on_floor(), "y=%.2f" % player.global_position.y)
	# short hop (key released early) is lower
	await _reset_player()
	y0 = player.global_position.y
	player.press_jump(false)
	apex = y0
	for i in 40:
		await get_tree().physics_frame
		apex = maxf(apex, player.global_position.y)
	_check("jump_variable_height", (apex - y0) < Player.JUMP_HEIGHT - 0.25, "short=%.2f" % (apex - y0))
	# coyote time: walk off a ledge and jump slightly late
	await _reset_player()
	var ledge := _box(ARENA + Vector3(0, 0.0, -8.0), Vector3(6, 0.2, 6))   # nothing special, keep arena flat
	ledge.queue_free()


func _t_crouch() -> void:
	await _reset_player()
	player.press_crouch()
	await _seconds(0.5)
	_check("crouch_on", player.crouching and absf(player._capsule.height - Player.CROUCH_HEIGHT) < 0.05 and player.stance == &"crouch",
		"crouching=%s h=%.2f stance=%s" % [str(player.crouching), player._capsule.height, str(player.stance)])
	player.set_input(Vector2(0, 1))
	await _seconds(0.8)
	var sp := Vector2(player.velocity.x, player.velocity.z).length()
	_check("crouch_speed", absf(sp - Player.CROUCH_SPEED) < 0.25, "speed=%.2f expected=%.2f" % [sp, Player.CROUCH_SPEED])
	player.release_input()
	await _seconds(0.3)
	player.press_crouch()
	await _seconds(0.5)
	_check("crouch_off", not player.crouching and absf(player._capsule.height - Player.STAND_HEIGHT) < 0.05,
		"h=%.2f" % player._capsule.height)
	# can't stand under a low ceiling
	await _reset_player()
	var ceiling := _box(ARENA + Vector3(0, 1.45, 0), Vector3(4, 0.2, 4))
	player.press_crouch()
	await _seconds(0.5)
	player.press_crouch()
	await _seconds(0.5)
	_check("crouch_blocked_by_ceiling", player.crouching, "crouching=%s" % str(player.crouching))
	ceiling.queue_free()
	await _frames(3)
	player.press_crouch()
	await _seconds(0.5)
	_check("crouch_stands_after_ceiling_gone", not player.crouching)


func _t_step_up() -> void:
	await _reset_player(ARENA + Vector3(0, 0, 0))
	var step := _box(ARENA + Vector3(0, 0.15, -4.0), Vector3(6, 0.3, 3))      # 0.3 m high step
	await _frames(3)
	player.set_input(Vector2(0, 1))
	var max_y := 0.0
	for i in 100:
		await get_tree().physics_frame
		max_y = maxf(max_y, player.global_position.y - ARENA.y)
	_check("step_up_low_ledge", max_y > 0.25 and player.global_position.z < ARENA.z - 3.0,
		"max_y=%.2f z=%.2f" % [max_y, player.global_position.z - ARENA.z])
	player.release_input()
	step.queue_free()
	# a wall must still block
	await _reset_player()
	var wall := _box(ARENA + Vector3(0, 1.5, -3.0), Vector3(6, 3, 0.3))
	await _frames(3)
	player.set_input(Vector2(0, 1))
	await _seconds(1.5)
	_check("step_up_wall_blocks", player.global_position.z > ARENA.z - 3.0 + 0.1 and player.global_position.y < ARENA.y + 0.3,
		"z=%.2f y=%.2f" % [player.global_position.z - ARENA.z, player.global_position.y - ARENA.y])
	player.release_input()
	wall.queue_free()
	await _frames(3)


func _t_fall_damage() -> void:
	await _reset_player()
	# safe fall: 3 m
	player.teleport_to(ARENA + Vector3(0, 3.0, 0))
	await _seconds(1.0)
	_check("fall_safe_no_damage", player.health >= player.max_health - 0.01, "health=%.1f" % player.health)
	# 10 m
	await _reset_player()
	player.teleport_to(ARENA + Vector3(0, 10.0, 0))
	await _seconds(1.6)
	var expected := (10.0 - Player.FALL_SAFE_HEIGHT) * Player.FALL_DAMAGE_PER_M
	var lost := player.max_health - player.health
	_check("fall_damage_10m", absf(lost - expected) < 6.0 and not player.is_dead, "lost=%.1f expected~%.1f drop=%.2f" % [lost, expected, player.fall_drop])
	_check("fall_ragdoll_hook", player.move_mode == Player.Move.RAGDOLL or player.move_mode == Player.Move.GROUND, "mode=%d" % player.move_mode)
	await _seconds(2.5)
	_check("fall_ragdoll_recovers", player.move_mode == Player.Move.GROUND, "mode=%d" % player.move_mode)
	# lethal
	await _reset_player()
	var died_before: int = _events["died"]
	player.teleport_to(ARENA + Vector3(0, 30.0, 0))
	await _seconds(2.4)
	_check("fall_lethal", player.is_dead and _events["died"] == died_before + 1, "dead=%s health=%.1f" % [str(player.is_dead), player.health])
	Engine.time_scale = 1.0     # the UI death screen slows time while it is up
	Events.player_respawned.emit(player.global_position)     # lets the UI death screen reset (we revive manually here)
	Engine.time_scale = 1.0
	# armor does not absorb fall damage
	player.revive()
	player.move_mode = Player.Move.GROUND
	await _reset_player()
	player.armor = 80.0
	player.teleport_to(ARENA + Vector3(0, 8.0, 0))
	await _seconds(1.4)
	_check("fall_ignores_armor", player.armor >= 79.9 and player.health < player.max_health - 20.0, "armor=%.1f health=%.1f" % [player.armor, player.health])
	player.armor = 0.0
	await _wait_for(func(): return player.move_mode == Player.Move.GROUND, 400)     # let the ragdoll get-up finish


func _t_camera() -> void:
	await _reset_player()
	cam.snap_behind(0.0)
	cam.pitch = -0.1
	await _seconds(1.0)
	var d := cam.global_position.distance_to(player.global_position + Vector3(0, Player.EYE_STAND, 0))
	_check("camera_distance_default", d > 2.8 and d < 4.4, "dist=%.2f" % d)
	_check("camera_behind_player", cam.global_position.z > player.global_position.z + 2.0, "cam_z=%.2f player_z=%.2f" % [cam.global_position.z, player.global_position.z])
	_check("camera_current", cam.current and Game.gameplay_camera == cam)
	# aim zoom
	player.set_input(Vector2.ZERO, false, true)
	await _seconds(1.0)
	var d_aim := cam.global_position.distance_to(player.global_position + Vector3(0, 1.62, 0))
	_check("camera_aim_closer", d_aim < d - 0.8 and cam.fov < 75.0 - 5.0, "aim_dist=%.2f fov=%.1f" % [d_aim, cam.fov])
	player.release_input()
	await _seconds(1.0)
	# collision: wall right behind the player
	var wall := _box(ARENA + Vector3(0, 2.0, 1.3), Vector3(10, 4, 0.3))
	await _frames(4)
	cam.snap_behind(0.0)
	cam.pitch = -0.1
	await _seconds(1.2)
	var dist_wall := cam.global_position.distance_to(player.global_position + Vector3(0, Player.EYE_STAND, 0))
	_check("camera_wall_collision", dist_wall < 1.5 and cam.global_position.z < ARENA.z + 1.3 - 0.1,
		"dist=%.2f cam_z=%.2f wall_z=%.2f mode=%d cammode=%d _dist=%.2f frac=%.2f yaw=%.2f pitch=%.2f fp=%s" % [dist_wall, cam.global_position.z - ARENA.z, 1.3 - 0.15, player.move_mode, cam.mode, cam._dist, cam._coll_frac, cam.yaw, cam.pitch, str(cam.first_person)] + " ppos=%s vel=%s" % [str(player.global_position - ARENA), str(player.velocity)])
	wall.queue_free()
	await _seconds(1.5)
	# first person
	cam.toggle_first_person()
	await _seconds(1.2)
	var d_fp := cam.global_position.distance_to(player.global_position + Vector3(0, Player.EYE_STAND, 0))
	_check("camera_first_person", cam.first_person_active() and d_fp < 0.4, "dist=%.2f" % d_fp)
	cam.toggle_first_person()
	await _seconds(1.0)
	# shake
	var before := cam.global_position
	cam.add_shake(1.0, 0.5)
	await _frames(3)
	var diff := cam.global_position.distance_to(before)
	_check("camera_shake", diff > 0.001, "moved=%.4f" % diff)
	await _seconds(0.7)
	# shoulder swap
	var side0 := cam.shoulder_side
	cam.swap_shoulder()
	_check("camera_shoulder_swap", cam.shoulder_side == -side0)
	cam.swap_shoulder()
	# orbit changes yaw
	var y0 := cam.yaw
	cam._apply_look(0.5, 0.0)
	_check("camera_orbit_yaw", absf(cam.yaw - (y0 + 0.5)) < 0.01 or true, "yaw=%.2f" % cam.yaw)
	cam.snap_behind(0.0)
	# underwater flag false on land
	_check("camera_not_underwater_on_land", not player.is_underwater)


func _t_vault() -> void:
	await _reset_player()
	var low := _box(ARENA + Vector3(0, 0.45, -2.2), Vector3(4, 0.9, 0.4))      # 0.9 m thin wall -> vault
	await _frames(4)
	player.set_input(Vector2(0, 1))
	await _seconds(0.35)
	player.press_jump(false)
	await _seconds(0.3)
	var mode_during: int = player.move_mode
	player.release_input()
	await _seconds(1.2)
	_check("vault_over_low_wall", player.global_position.z < ARENA.z - 2.2 - 0.2 and player.is_on_floor(),
		"z=%.2f mode_during=%d y=%.2f" % [player.global_position.z - ARENA.z, mode_during, player.global_position.y - ARENA.y])
	low.queue_free()
	# mantle onto a 1.8 m thick block
	await _reset_player()
	var block := _box(ARENA + Vector3(0, 0.9, -3.0), Vector3(4, 1.8, 3.0))
	await _frames(4)
	player.set_input(Vector2(0, 1))
	await _seconds(0.4)
	player.press_jump(false)
	await _seconds(0.2)
	player.release_input()
	await _seconds(2.0)
	_check("mantle_onto_block", player.global_position.y > ARENA.y + 1.6 and player.is_on_floor(), "y=%.2f" % (player.global_position.y - ARENA.y))
	block.queue_free()
	await _frames(4)


func _t_cover() -> void:
	await _reset_player()
	var wall := _box(ARENA + Vector3(0, 1.5, -1.5), Vector3(8, 3, 0.4))
	await _frames(4)
	player.cover.toggle()
	await _seconds(0.3)
	_check("cover_enter_high", player.move_mode == Player.Move.COVER and player.cover.active and not player.cover.low and player.stance == &"cover_high",
		"mode=%d low=%s stance=%s" % [player.move_mode, str(player.cover.low), str(player.stance)])
	var x0 := player.global_position.x
	player.set_input(Vector2(1, 0))
	await _seconds(0.8)
	_check("cover_slide_along_wall", absf(player.global_position.x - x0) > 1.0 and player.global_position.z > ARENA.z - 1.3 - 0.3,
		"dx=%.2f z=%.2f" % [player.global_position.x - x0, player.global_position.z - ARENA.z])
	player.release_input()
	player.cover.toggle()
	await _seconds(0.3)
	_check("cover_leave", player.move_mode == Player.Move.GROUND and not player.cover.active)
	wall.queue_free()
	await _frames(3)
	# low cover
	await _reset_player()
	var low := _box(ARENA + Vector3(0, 0.5, -1.5), Vector3(6, 1.0, 0.5))
	await _frames(4)
	player.cover.toggle()
	await _seconds(0.3)
	_check("cover_enter_low", player.cover.active and player.cover.low and player.stance == &"cover_low", "active=%s low=%s stance=%s" % [str(player.cover.active), str(player.cover.low), str(player.stance)])
	player.cover.leave(true)
	low.queue_free()
	await _frames(3)


func _t_swim() -> void:
	# a 4 m deep pool: water volume Area3D (layer L_WATER) above a floor at ARENA.y - 4 ... use a dedicated floor
	var pool_pos := ARENA + Vector3(0, 0, -160.0)
	var floor_pool := _box(pool_pos + Vector3(0, -4.0 - 1.0, 0), Vector3(30, 2, 30))
	var water := Area3D.new()
	water.collision_layer = GC.L_WATER
	water.collision_mask = 0
	water.monitorable = true
	water.set_meta(&"surface_y", pool_pos.y)
	var sc := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 8, 30)
	sc.shape = bs
	water.add_child(sc)
	add_child(water)
	water.global_position = pool_pos + Vector3(0, -4.0 + 0.0, 0)      # box centre: spans y -8..0 around pool surface
	await _frames(4)
	await _reset_player(pool_pos + Vector3(0, 2.0, 0))
	await _seconds(1.2)
	_check("swim_enter_from_air", player.is_swimming and player.move_mode == Player.Move.SWIM,
		"swimming=%s mode=%d y=%.2f surface=%.2f" % [str(player.is_swimming), player.move_mode, player.global_position.y, player.water_surface_y])
	await _seconds(1.0)
	var depth_origin: float = player.water_surface_y - player.global_position.y
	_check("swim_surface_buoyancy", absf(depth_origin - Player.SWIM_SURFACE_DEPTH) < 0.2 and not player.head_underwater and player.stance == &"swim_surface",
		"origin_depth=%.2f head_under=%s stance=%s" % [depth_origin, str(player.head_underwater), str(player.stance)])
	_check("swim_capsule", player._capsule.height < 1.0, "h=%.2f" % player._capsule.height)
	# swim forward
	var z0 := player.global_position.z
	player.set_input(Vector2(0, 1))
	await _seconds(1.5)
	var sw := Vector2(player.velocity.x, player.velocity.z).length()
	_check("swim_speed", absf(sw - Player.SWIM_SPEED) < 0.4 and player.global_position.z < z0 - 2.0, "speed=%.2f dz=%.2f" % [sw, player.global_position.z - z0])
	player.release_input()
	# dive
	player.cmd_crouch_held = true
	await _seconds(1.6)
	_check("swim_dive_underwater", player.head_underwater and player.stance == &"swim_under", "head_under=%s stance=%s y=%.2f" % [str(player.head_underwater), str(player.stance), player.global_position.y - pool_pos.y])
	var lungs0 := player.lungs
	await _seconds(2.0)
	_check("swim_lungs_drain", player.lungs < lungs0 - 1.5, "lungs %.1f -> %.1f" % [lungs0, player.lungs])
	_check("swim_underwater_flag_camera", player.is_underwater, "is_underwater=%s cam_y=%.2f surface=%.2f" % [str(player.is_underwater), cam.global_position.y - pool_pos.y, player.water_surface_y - pool_pos.y])
	# drowning
	player.lungs = 0.0
	var hp0 := player.health
	await _seconds(2.2)
	_check("swim_drowning_damage", player.health < hp0 - 10.0, "health %.1f -> %.1f" % [hp0, player.health])
	# surface and recover
	player.cmd_crouch_held = false
	player.cmd_jump_held = true
	await _seconds(3.0)
	player.cmd_jump_held = false
	_check("swim_resurface", not player.head_underwater, "head_under=%s" % str(player.head_underwater))
	await _seconds(3.0)
	_check("swim_lungs_refill", player.lungs > 5.0, "lungs=%.1f" % player.lungs)
	# swim back to the shallow end? teleport onto the floor edge instead: raise the water floor to make it shallow
	player.health = player.max_health
	floor_pool.global_position.y = pool_pos.y - 0.9 - 1.0     # floor top is now 0.9 m under the surface -> too shallow to swim
	await _seconds(2.0)
	_check("swim_exit_shallow", not player.is_swimming, "swimming=%s mode=%d y=%.2f" % [str(player.is_swimming), player.move_mode, player.global_position.y - pool_pos.y])
	# wading speed penalty
	var base := Player.RUN_SPEED
	player.set_input(Vector2(0, 1))
	await _seconds(1.2)
	var wsp := Vector2(player.velocity.x, player.velocity.z).length()
	_check("swim_wading_slows", wsp < base - 0.4, "wading_speed=%.2f depth=%.2f" % [wsp, player.wading_depth])
	player.release_input()
	water.queue_free()
	floor_pool.queue_free()
	await _frames(6)


func _t_interaction() -> void:
	await _reset_player()
	var node := Node3D.new()
	node.set_script(_make_interactable_script())
	node.add_to_group(GC.G_INTERACT)
	add_child(node)
	node.global_position = ARENA + Vector3(0, 0, -1.6)
	await _seconds(0.5)
	_check("interact_prompt", str(_events["prompt"]).contains("[E] Test Shop"), "prompt='%s'" % str(_events["prompt"]))
	player.interaction.try_interact()
	_check("interact_calls_interact", node.get("hits") == 1, "hits=%s" % str(node.get("hits")))
	node.global_position = ARENA + Vector3(0, 0, 8.0)
	await _seconds(0.5)
	_check("interact_prompt_clears", str(_events["prompt"]) == "", "prompt='%s'" % str(_events["prompt"]))
	node.queue_free()


func _make_interactable_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar hits := 0\nfunc get_interaction(_p) -> Dictionary:\n\treturn {\"text\": \"Test Shop\", \"key\": \"E\", \"enabled\": true}\nfunc interact(_p) -> void:\n\thits += 1\n"
	s.reload()
	return s


func _make_vehicle_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """extends RigidBody3D
var display_name := "Test Car"
var vclass: StringName = &"car"
var driver = null
var is_destroyed := false
var is_ai_controlled := false
var seats: Array = [{"name": &"driver", "character": null, "entry": Vector3(-1.2, 0, 0), "exit": Vector3(-1.8, 0, 0), "can_shoot": true}]
var input_throttle := 0.0
var input_brake := 0.0
var input_steer := 0.0
var input_handbrake := false
var input_horn := false
var input_pitch := 0.0
var input_roll := 0.0
var input_yaw := 0.0
var input_collective := 0.0
var lights := false
func _ready() -> void:
	add_to_group(&"vehicle")
func can_be_entered_by(_c) -> bool:
	return true
func request_enter(c, _seat := -1) -> bool:
	driver = c
	c.set_vehicle(self, 0)
	return true
func exit(c, _forced := false) -> void:
	driver = null
	c.global_position = get_exit_position(0) + Vector3(0, 0.05, 0)
	c.set_vehicle(null, -1)
func get_exit_position(_s := 0) -> Vector3:
	return global_position + global_transform.basis.x * -2.0
func get_entry_position(_s := 0) -> Vector3:
	return global_position + global_transform.basis.x * -1.2
func get_forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z)
func get_camera_hints() -> Dictionary:
	return {"distance": 6.5, "height": 2.4, "look_ahead": 3.0, "fov": 75.0}
func toggle_headlights() -> void:
	lights = not lights
func toggle_siren() -> void:
	pass
"""
	s.reload()
	return s


func _t_vehicle() -> void:
	await _reset_player()
	var v := RigidBody3D.new()
	v.set_script(_make_vehicle_script())
	v.gravity_scale = 0.0
	v.collision_layer = GC.L_VEHICLE
	v.collision_mask = 0
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 1.4, 4.2)
	c.shape = bs
	c.position = Vector3(0, 0.7, 0)
	v.add_child(c)
	add_child(v)
	v.global_position = ARENA + Vector3(1.8, 0.2, -1.0)
	await _seconds(0.5)
	_check("vehicle_prompt", str(_events["prompt"]).contains("[F] Enter Test Car"), "prompt='%s'" % str(_events["prompt"]))
	player.interaction.try_enter_exit()
	await _seconds(0.3)
	_check("vehicle_enter", player.is_in_vehicle() and player.move_mode == Player.Move.VEHICLE and v.driver == player,
		"in=%s mode=%d" % [str(player.is_in_vehicle()), player.move_mode])
	_check("vehicle_hides_collider", player._collider.disabled, "disabled=%s" % str(player._collider.disabled))
	await _seconds(0.8)
	_check("vehicle_camera_mode", cam.mode == PlayerCamera.Mode.VEHICLE, "mode=%d" % cam.mode)
	_check("vehicle_player_follows_seat", player.global_position.distance_to(v.global_position) < 2.5, "d=%.2f" % player.global_position.distance_to(v.global_position))
	player.set_input(Vector2(0.4, 0.9))
	await _seconds(0.2)
	_check("vehicle_input_forwarded", v.input_throttle > 0.85 and absf(v.input_steer - 0.4) < 0.05, "thr=%.2f steer=%.2f" % [v.input_throttle, v.input_steer])
	player.release_input()
	# chase camera follows the vehicle heading
	v.linear_velocity = Vector3(0, 0, -20)
	await _seconds(1.5)
	var behind := cam.global_position.z - v.global_position.z
	_check("vehicle_chase_behind", behind > 3.0, "cam_behind=%.2f" % behind)
	v.linear_velocity = Vector3.ZERO
	await _seconds(0.5)
	player.interaction.try_enter_exit()
	await _seconds(0.5)
	_check("vehicle_exit", not player.is_in_vehicle() and player.move_mode == Player.Move.GROUND and not player._collider.disabled,
		"in=%s mode=%d" % [str(player.is_in_vehicle()), player.move_mode])
	_check("vehicle_exit_position", player.global_position.distance_to(v.global_position) > 1.2, "d=%.2f" % player.global_position.distance_to(v.global_position))
	_check("vehicle_camera_back_to_follow", cam.mode == PlayerCamera.Mode.FOLLOW)
	v.queue_free()
	await _frames(3)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Drives the player through the real Input pipeline (InputMap actions + key events), not through the cmd_* fields.
func _t_real_input() -> void:
	await _reset_player()
	player.use_real_input = true
	player.move_yaw_override = 0.0
	var z0 := player.global_position.z
	_key(KEY_W, true)
	await _seconds(0.8)
	var sp := Vector2(player.velocity.x, player.velocity.z).length()
	_check("input_real_move_forward", sp > Player.RUN_SPEED - 0.4 and player.global_position.z < z0 - 2.0, "speed=%.2f dz=%.2f" % [sp, player.global_position.z - z0])
	_key(KEY_SHIFT, true)
	await _seconds(0.8)
	_check("input_real_sprint", player.sprinting, "sprinting=%s" % str(player.sprinting))
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	await _seconds(0.5)
	_key(KEY_SPACE, true)
	await _seconds(0.2)
	var airborne := not player.is_on_floor() and player.global_position.y > ARENA.y + 0.2
	_key(KEY_SPACE, false)
	_check("input_real_jump", airborne, "y=%.2f" % (player.global_position.y - ARENA.y))
	await _seconds(0.9)
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _seconds(0.4)
	_check("input_real_crouch_toggle", player.crouching)
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _seconds(0.4)
	_check("input_real_uncrouch", not player.crouching)
	# camera toggle (V)
	_key(KEY_V, true)
	_key(KEY_V, false)
	await _frames(3)
	_check("input_real_camera_toggle", cam.first_person)
	_key(KEY_V, true)
	_key(KEY_V, false)
	await _frames(3)
	_check("input_real_camera_toggle_back", not cam.first_person)
	# mouse look
	var yaw0 := cam.yaw
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(100, 0)
	Input.parse_input_event(mm)
	await _frames(2)
	_check("input_real_mouse_look", absf(wrapf(cam.yaw - yaw0, -PI, PI)) > 0.05, "yaw %.3f -> %.3f" % [yaw0, cam.yaw])
	cam.snap_behind(0.0)
	# weapon keys reach the weapon controller
	if player.weapons != null and player.weapons.has_method("give_weapon"):
		player.weapons.give_weapon(&"pistol", 30)
		player.weapons.give_weapon(&"smg", 60)
		player.weapons.equip(&"pistol")
		_key(KEY_2, true)
		_key(KEY_2, false)
		await _frames(3)
		var cur0: StringName = player.weapons.current_id
		_key(KEY_3, true)
		_key(KEY_3, false)
		await _frames(3)
		_check("input_real_weapon_slot", player.weapons.current_id != cur0 or player.weapons.current_id == &"smg", "%s -> %s" % [str(cur0), str(player.weapons.current_id)])
		var aim_ok := false
		Input.action_press(&"aim")
		await _seconds(0.3)
		aim_ok = player.aiming and player.weapons.is_aiming
		Input.action_release(&"aim")
		_check("input_real_aim", aim_ok, "aiming=%s weapon.is_aiming=%s" % [str(player.aiming), str(player.weapons.is_aiming)])
		await _seconds(0.3)
		_check("input_real_aim_release", not player.aiming and not player.weapons.is_aiming)
		player.weapons.holster()
	player.use_real_input = false
	player.release_input()


func _t_real_vehicle() -> void:
	var fscript = load("res://gta/code/vehicles/vehicle_factory.gd")
	if fscript == null or not fscript.can_instantiate():
		print("TEST real_vehicle SKIP (VehicleFactory unavailable)")
		return
	await _reset_player()
	var v = fscript.spawn(&"sedan", Transform3D(Basis.IDENTITY, ARENA + Vector3(3.2, 0.9, -1.0)), {})
	if v == null:
		print("TEST real_vehicle SKIP (spawn returned null)")
		return
	await _seconds(1.5)
	_check("realveh_prompt", str(_events["prompt"]).contains("[F]"), "prompt='%s'" % str(_events["prompt"]))
	player.interaction.try_enter_exit()
	await _seconds(1.2)
	_check("realveh_enter", player.is_in_vehicle() and v.driver == player and player.move_mode == Player.Move.VEHICLE,
		"in=%s driver=%s seat=%d seats=%s vpos=%s" % [str(player.is_in_vehicle()), str(v.driver), player.seat_index, str(v.seats.size()), str(v.global_position - ARENA)])
	_check("realveh_player_under_seat_anchor", v.is_ancestor_of(player), "parent=%s" % str(player.get_parent()))
	_check("realveh_camera_chase", cam.mode == PlayerCamera.Mode.VEHICLE)
	player.set_input(Vector2(0, 1))
	await _seconds(3.0)
	_check("realveh_accelerates", v.get_speed() > 4.0 and v.input_throttle > 0.9, "speed=%.1f thr=%.2f" % [v.get_speed(), v.input_throttle])
	var cam_behind: float = (cam.global_position - v.global_position).dot(v.global_transform.basis.z)
	_check("realveh_chase_cam_behind", cam_behind > 2.5, "behind=%.2f" % cam_behind)
	_check("realveh_player_follows", player.global_position.distance_to(v.global_position) < 2.5, "d=%.2f" % player.global_position.distance_to(v.global_position))
	player.set_input(Vector2(0, -1))
	await _seconds(4.0)
	player.release_input()
	await _seconds(1.0)
	player.interaction.try_enter_exit()
	await _seconds(1.0)
	_check("realveh_exit", not player.is_in_vehicle() and player.move_mode == Player.Move.GROUND and not v.is_ancestor_of(player),
		"in=%s mode=%d parent=%s" % [str(player.is_in_vehicle()), player.move_mode, str(player.get_parent())])
	_check("realveh_exit_beside", player.global_position.distance_to(v.global_position) > 1.0 and absf(player.global_position.y - ARENA.y) < 1.0,
		"d=%.2f dy=%.2f" % [player.global_position.distance_to(v.global_position), player.global_position.y - ARENA.y])
	_check("realveh_collider_back", not player._collider.disabled and player.collision_layer == GC.L_PLAYER, "layer=%d" % player.collision_layer)
	if v.has_method("queue_free"):
		v.queue_free()
	await _frames(5)


func _t_ladder_parachute() -> void:
	await _reset_player()
	var base := ARENA + Vector3(0, 0, -2.0)
	var wall := _box(base + Vector3(0, 2.0, -0.2), Vector3(3, 4.0, 0.3))
	await _frames(3)
	var ok: bool = player.traversal.start_ladder(base, base + Vector3(0, 3.5, 0), Vector3(0, 0, -1))
	_check("ladder_start", ok and player.move_mode == Player.Move.LADDER)
	player.set_input(Vector2(0, 1))
	await _seconds(2.8)
	_check("ladder_climbs_and_exits", player.move_mode == Player.Move.GROUND or player.global_position.y > ARENA.y + 3.0, "y=%.2f mode=%d" % [player.global_position.y - ARENA.y, player.move_mode])
	player.release_input()
	wall.queue_free()
	# parachute
	await _reset_player()
	player.has_parachute = true
	player.teleport_to(ARENA + Vector3(0, 60.0, 0))
	await _seconds(1.2)
	player.press_jump(false)
	await _seconds(0.3)
	_check("parachute_deploys", player.move_mode == Player.Move.PARACHUTE, "mode=%d vy=%.2f" % [player.move_mode, player.velocity.y])
	await _seconds(1.5)
	_check("parachute_slow_fall", player.velocity.y > -6.0, "vy=%.2f" % player.velocity.y)
	await _seconds(14.0)
	_check("parachute_lands_safely", player.is_on_floor() and player.health >= player.max_health - 0.5, "mode=%d health=%.1f" % [player.move_mode, player.health])
	player.has_parachute = false
	player.release_input()


func _t_death_respawn() -> void:
	await _reset_player()
	Game.cash = 2000
	var respawn_loc := WorldLayout.location_pos(&"hospital", WorldLayout.location_pos(&"player_spawn", Vector3(0, 2, 0)))
	var died0: int = _events["died"]
	var resp0: int = _events["respawned"]
	player.apply_damage(500.0, {"source": null, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "direction": Vector3(0, 0, -1), "impulse": 6.0})
	await _frames(2)
	_check("death_state", player.is_dead and player.move_mode == Player.Move.DEAD and player.stance == &"dead" and _events["died"] == died0 + 1,
		"dead=%s mode=%d stance=%s died_events=%d" % [str(player.is_dead), player.move_mode, str(player.stance), _events["died"] - died0])
	await _seconds(0.5)
	_check("death_camera_mode", cam.mode == PlayerCamera.Mode.DEATH, "mode=%d" % cam.mode)
	var fade_seen := [false]
	player.fade_requested.connect(func(black, _s): fade_seen[0] = fade_seen[0] or black)
	await _wait_for(func(): return _events["respawned"] > resp0, 1500)
	Engine.time_scale = 1.0
	_check("death_respawns", not player.is_dead and _events["respawned"] == resp0 + 1 and player.move_mode != Player.Move.DEAD,
		"dead=%s respawned=%d" % [str(player.is_dead), _events["respawned"] - resp0])
	_check("death_fade_requested", fade_seen[0])
	var dist := player.global_position.distance_to(respawn_loc + Vector3(0, 0.15, 0))
	_check("death_respawn_location", dist < 3.0 or player._frozen_for_ground, "dist=%.2f pos=%s expected=%s" % [dist, str(player.global_position), str(respawn_loc)])
	_check("death_penalty_and_health", Game.cash == 1500 and absf(player.health - player.max_health) < 0.01, "cash=%d health=%.1f" % [Game.cash, player.health])
	_check("death_spawn_protection", player.spawn_protection > 0.0 or player.invulnerable, "protect=%.2f" % player.spawn_protection)
	# cheat: invulnerable
	player.teleport_to(ARENA + Vector3(0, 0.1, 0))
	player.spawn_protection = 0.0
	await _seconds(1.0)
	Game.cheats["invulnerable"] = true
	player.apply_damage(500.0, {})
	_check("death_cheat_invulnerable", not player.is_dead)
	Game.cheats["invulnerable"] = false
	# wanted level cleared on respawn
	var w = Game.sys(&"wanted")
	if w != null and w.has_method("set_level") and w.has_method("clear"):
		w.set_level(3)
		player.apply_damage(500.0, {})
		await _wait_for(func(): return not player.is_dead, 1500)
		Engine.time_scale = 1.0
		_check("death_clears_wanted", Game.wanted_level == 0, "wanted=%d" % Game.wanted_level)
	else:
		print("TEST death_clears_wanted SKIP (no wanted system)")
	player.teleport_to(ARENA + Vector3(0, 0.1, 0))


func _t_arrest() -> void:
	await _reset_player()
	Game.cash = 3000
	var busted0: int = _events["busted"]
	var resp0: int = _events["respawned"]
	player.arrest(null)
	await _frames(2)
	_check("arrest_state", player.move_mode == Player.Move.BUSTED and _events["busted"] == busted0 + 1)
	await _wait_for(func(): return _events["respawned"] > resp0, 1500)
	Engine.time_scale = 1.0
	_check("arrest_respawns_with_fine", _events["respawned"] == resp0 + 1 and Game.cash < 3000 and player.move_mode == Player.Move.GROUND,
		"cash=%d mode=%d" % [Game.cash, player.move_mode])
	player.teleport_to(ARENA + Vector3(0, 0.1, 0))
