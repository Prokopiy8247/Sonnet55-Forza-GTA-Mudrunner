extends Node
## Headless tests of the advanced player layer (stealth, cover, traversal, melee, passenger / drive-by, first person, parachute, scuba).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/player_adv_test.gd -Seconds 200 -GameArgs "--no-traffic --no-peds --no-hostiles"
## Filter with `-GameArgs "... --only=stealth,cover"`. Prints "TEST <name> PASS|FAIL <detail>".

const ARENA := Vector3(4000.0, 100.0, -4000.0)      # far outside the real map, high above any water

var player: Player
var cam: PlayerCamera
var _fails := 0
var _passes := 0
var _shots := 0


## Minimal NPC for takedown / melee tests: a CharacterBase in group npc with the duck-typed members the AI classes have.
class DummyNpc extends CharacterBase:
	var knocked := 0.0
	var panic := 0.0
	var provoked := false
	var hits := 0
	var last_info: Dictionary = {}
	func _ready() -> void:
		super._ready()
		add_to_group(GC.G_NPC)
		faction = GC.F_CIVILIAN
		collision_layer = GC.L_NPC
		collision_mask = GC.L_WORLD
		var c := CollisionShape3D.new()
		var s := CapsuleShape3D.new()
		s.radius = 0.35
		s.height = 1.8
		c.shape = s
		c.position = Vector3(0, 0.9, 0)
		add_child(c)
	func knock_down(_impulse: Vector3, duration: float = 2.2) -> void:
		knocked = duration
	func is_knocked_down() -> bool:
		return knocked > 0.0
	func _on_damaged(_a: float, info: Dictionary) -> void:
		hits += 1
		last_info = info


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


func _npc(pos: Vector3, yaw: float = 0.0) -> DummyNpc:
	var n := DummyNpc.new()
	add_child(n)
	n.global_position = pos
	n.rotation.y = yaw
	return n


func _reset_player(at: Vector3 = ARENA, yaw: float = 0.0) -> void:
	player.release_input()
	player.edge_jump = false
	player.edge_crouch = false
	player.crouching = false
	player.is_dead = false
	player.health = player.max_health
	player.spawn_protection = 0.0
	player.invulnerable = false
	player.move_yaw_override = yaw
	if player.cover != null and player.cover.active:
		player.cover.leave(true)
	if player.traversal != null:
		player.traversal.cancel()
	player.move_mode = Player.Move.GROUND
	player.teleport_to(at + Vector3(0, 0.1, 0), yaw)
	await _frames(12)


func _equip(id: StringName, ammo: int = 60) -> void:
	if player.weapons == null:
		return
	player.weapons.give_weapon(id, ammo)
	player.weapons.equip(id)
	await _frames(20)


func run(_main: Node) -> Variant:
	await _frames(3)
	player = Game.player as Player
	cam = player.camera as PlayerCamera
	player.use_real_input = false
	player.move_yaw_override = 0.0
	_box(ARENA + Vector3(0, -1, 0), Vector3(160, 2, 160))
	await _frames(4)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	var tests := {
		"bugs": Callable(self, "_t_bugs"),
		"stealth": Callable(self, "_t_stealth"),
		"takedown": Callable(self, "_t_takedown"),
		"cover": Callable(self, "_t_cover"),
	}
	for k in tests:
		if only == "" or only.split(",").has(k):
			await tests[k].call()
	print("TEST SUMMARY passes=%d fails=%d" % [_passes, _fails])
	return _fails == 0


# ---------------------------------------------------------------------------------------------------------------
func _t_bugs() -> void:
	await _reset_player()
	# lungs start full even when the lung skill raises the capacity after boot
	var sk = Game.sys(&"skills")
	if sk != null and sk.has_method("set_skill"):
		sk.set_skill(&"lung", 35.0)
	await _seconds(0.5)
	_check("lungs_full_at_rest", player.lungs >= player.max_lungs - 0.05, "lungs=%.2f max=%.2f" % [player.lungs, player.max_lungs])
	var hud = Game.ui.get("hud") if Game.ui != null else null
	if hud != null and hud.get("air") != null:
		await _seconds(1.0)
		_check("hud_air_bar_hidden_at_spawn", float(hud.air.shown) < 0.05, "shown=%.2f ratio=%.2f" % [hud.air.shown, hud.air.ratio])
	else:
		_check("hud_air_bar_hidden_at_spawn", true, "no hud in this run (skipped)")
	if sk != null and sk.has_method("set_skill"):
		sk.set_skill(&"lung", 0.0)
	# the camera is not an engine-interpolated node any more
	_check("camera_not_engine_interpolated", cam.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF)
	_check("visual_not_engine_interpolated", player.visual.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF)


func _t_stealth() -> void:
	await _reset_player()
	await _equip(&"pistol")
	player.set_input(Vector2.ZERO)
	await _seconds(0.6)
	_check("noise_still_zero", player.noise_radius < 0.5, "noise=%.2f" % player.noise_radius)
	player.set_input(Vector2(0, 1), false, false, true)
	await _seconds(0.9)
	var n_walk := player.noise_radius
	player.set_input(Vector2(0, 1))
	await _seconds(0.9)
	var n_run := player.noise_radius
	player.set_input(Vector2(0, 1), true)
	await _seconds(0.9)
	var n_sprint := player.noise_radius
	player.set_input(Vector2.ZERO)
	await _seconds(0.5)
	player.press_crouch()
	await _seconds(0.3)
	player.set_input(Vector2(0, 1))
	await _seconds(0.9)
	var n_crouch := player.noise_radius
	_check("noise_crouch_lt_walk", n_crouch < n_walk and n_crouch > 0.5, "crouch=%.1f walk=%.1f" % [n_crouch, n_walk])
	_check("noise_walk_lt_run", n_walk < n_run, "walk=%.1f run=%.1f" % [n_walk, n_run])
	_check("noise_run_lt_sprint", n_run < n_sprint, "run=%.1f sprint=%.1f" % [n_run, n_sprint])
	_check("noise_published_on_get", is_equal_approx(player.get_noise_radius(), player.noise_radius))
	player.set_input(Vector2.ZERO)
	await _seconds(0.6)
	_check("noise_collapses_when_still", player.noise_radius < 0.5, "noise=%.2f" % player.noise_radius)

	# gunshot noise incl. suppressor
	player.press_crouch()
	await _seconds(0.5)
	var heard_loud := [0.0]
	var cb := func(_p: Vector3, l: float, src: Node) -> void:
		if src == player:
			heard_loud[0] = maxf(heard_loud[0], l)
	Events.gunshot.connect(cb)
	player.cmd_fire = true
	await _frames(3)
	player.cmd_fire = false
	await _seconds(0.1)
	var n_shot := player.noise_radius
	Events.gunshot.disconnect(cb)
	_check("noise_gunshot_loud", n_shot > 25.0 and n_shot >= heard_loud[0] * 0.9 and heard_loud[0] > 0.0, "noise=%.1f event=%.1f" % [n_shot, heard_loud[0]])
	await _seconds(2.6)
	_check("noise_gunshot_decays", player.noise_radius < 2.0, "noise=%.1f" % player.noise_radius)
	if player.weapons.has_method("set_mod"):
		player.weapons.set_mod(&"pistol", &"suppressor", true)
		await _seconds(0.5)
		heard_loud[0] = 0.0
		var cb2 := func(_p: Vector3, l: float, src: Node) -> void:
			if src == player:
				heard_loud[0] = maxf(heard_loud[0], l)
		Events.gunshot.connect(cb2)
		await _seconds(0.6)
		player.cmd_fire = true
		await _frames(3)
		player.cmd_fire = false
		await _seconds(0.1)
		Events.gunshot.disconnect(cb2)
		_check("noise_suppressed_quieter", heard_loud[0] > 0.0 and player.noise_radius < n_shot * 0.55, "supp=%.1f unsupp=%.1f" % [player.noise_radius, n_shot])
		player.weapons.set_mod(&"pistol", &"suppressor", false)
	await _seconds(2.4)

	# visibility: light, posture, cover
	Game.time_frozen = true
	Game.time_of_day = 12.0
	await _reset_player()
	await _seconds(1.5)
	var v_day := player.visibility01
	var range_day := player.detection_range
	player.press_crouch()
	await _seconds(0.8)
	var v_day_crouch := player.visibility01
	player.press_crouch()
	await _seconds(0.6)
	Game.time_of_day = 0.5
	var env = Game.sys(&"environment")
	if env != null and env.has_method("set_time"):
		env.set_time(0.5)
	await _seconds(3.0)
	var v_night := player.visibility01
	var range_night := player.detection_range
	player.press_crouch()
	await _seconds(0.8)
	var v_night_crouch := player.visibility01
	_check("visibility_crouch_lower", v_day_crouch < v_day - 0.1, "stand=%.2f crouch=%.2f" % [v_day, v_day_crouch])
	_check("visibility_night_lower", v_night < v_day - 0.15, "day=%.2f night=%.2f (game hour %.1f)" % [v_day, v_night, Game.time_of_day])
	_check("visibility_night_crouch_lowest", v_night_crouch < v_night and v_night_crouch < v_day_crouch, "night_crouch=%.2f" % v_night_crouch)
	_check("detection_range_follows_visibility", range_night < range_day and range_day <= PlayerStealth.SIGHT_MAX, "day=%.0f night=%.0f" % [range_day, range_night])
	_check("exposed_flag", (v_day >= PlayerStealth.EXPOSED_AT) == true and player.stealth_exposed == (player.visibility01 >= PlayerStealth.EXPOSED_AT))
	# per-viewer
	var near := player.get_visibility_from(player.global_position + Vector3(0, 0, 4))
	var far := player.get_visibility_from(player.global_position + Vector3(0, 0, 60))
	_check("visibility_from_distance", near > far, "near=%.2f far=%.2f" % [near, far])
	# cover reduces visibility for a viewer on the wall side
	Game.time_of_day = 12.0
	await _reset_player()
	var wall := _box(ARENA + Vector3(0, 1.5, -1.6), Vector3(6, 3, 0.4))
	await _frames(4)
	var before := player.visibility01
	player.cover.toggle()
	await _seconds(0.9)
	var in_cover: bool = player.cover.active
	var vis_front := player.get_visibility_from(player.global_position + Vector3(0, 0, 6))
	var vis_behind_wall := player.get_visibility_from(player.global_position + Vector3(0, 0, -6))
	_check("visibility_cover_lowers", in_cover and player.visibility01 < before - 0.1, "before=%.2f cover=%.2f" % [before, player.visibility01])
	_check("visibility_from_behind_wall_low", vis_behind_wall < vis_front * 0.5, "front=%.2f behind=%.2f" % [vis_front, vis_behind_wall])
	player.cover.leave(true)
	wall.queue_free()
	Game.time_frozen = false
	await _frames(4)


func _t_takedown() -> void:
	await _reset_player()
	await _equip(&"pistol")
	var shots_heard := [0]
	var cb := func(_p: Vector3, _l: float, src: Node) -> void:
		if src == player:
			shots_heard[0] += 1
	Events.gunshot.connect(cb)
	# 1. fists: knock out from behind (NPC faces -Z like the player, i.e. away from us)
	player.weapons.equip(&"fists")
	await _frames(15)
	var npc := _npc(ARENA + Vector3(0, 0.05, -1.7), 0.0)
	await _seconds(0.5)
	_check("takedown_candidate_found", player.takedown_target == npc, "target=%s" % str(player.takedown_target))
	_check("takedown_prompt_flag", player.stealth.target == npc)
	player.melee(false)
	await _seconds(1.4)
	_check("takedown_ko_not_dead", not npc.is_dead and npc.knocked > 0.0, "dead=%s knocked=%.1f" % [str(npc.is_dead), npc.knocked])
	_check("takedown_ko_info_silent", npc.last_info.get("silent", false) == true and npc.last_info.get("weapon", &"") == &"takedown", "info=%s" % str(npc.last_info.keys()))
	_check("takedown_noise_free", shots_heard[0] == 0 and player.noise_radius < 3.5, "gunshots=%d noise=%.1f" % [shots_heard[0], player.noise_radius])
	_check("takedown_player_behind", Util.dist_xz(player.global_position, npc.global_position) < 1.4, "dist=%.2f" % Util.dist_xz(player.global_position, npc.global_position))
	npc.queue_free()
	await _seconds(1.0)
	# 2. knife: silent kill
	await _reset_player()
	await _equip(&"knife", 1)
	var npc2 := _npc(ARENA + Vector3(0, 0.05, -1.5), 0.0)
	await _seconds(0.5)
	player.melee(false)
	await _seconds(1.4)
	_check("takedown_knife_kills", npc2.is_dead, "dead=%s hp=%.0f" % [str(npc2.is_dead), npc2.health])
	_check("takedown_kill_no_gunshot", shots_heard[0] == 0)
	npc2.queue_free()
	await _seconds(0.6)
	# 3. NPC facing us -> no takedown, normal melee
	await _reset_player()
	var npc3 := _npc(ARENA + Vector3(0, 0.05, -1.5), PI)
	await _seconds(0.5)
	_check("takedown_not_from_front", player.takedown_target == null, "target=%s" % str(player.takedown_target))
	npc3.queue_free()
	# 4. aware NPC (panicked) -> no takedown
	var npc4 := _npc(ARENA + Vector3(0, 0.05, -1.5), 0.0)
	npc4.panic = 0.9
	await _seconds(0.5)
	_check("takedown_not_when_aware", player.takedown_target == null)
	npc4.queue_free()
	# 5. too far
	var npc5 := _npc(ARENA + Vector3(0, 0.05, -6.0), 0.0)
	await _seconds(0.5)
	_check("takedown_not_when_far", player.takedown_target == null)
	npc5.queue_free()
	Events.gunshot.disconnect(cb)
	await _frames(4)


# ---------------------------------------------------------------------------------------------------------------
func _enter_cover_at(wall_z: float, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var w := _box(ARENA + Vector3(0, size.y * 0.5, wall_z), size)
	await _frames(4)
	player.cover.toggle()
	await _seconds(0.7)
	return w


func _t_cover() -> void:
	# ---- corner transition: an L-shaped building corner, slide right round it -----------------------------------------------
	await _reset_player()
	var wa := _box(ARENA + Vector3(0, 1.5, -1.6), Vector3(6, 3, 0.4))                  # front wall x -3..3, z -1.8..-1.4
	var wb := _box(ARENA + Vector3(3.0, 1.5, -5.0), Vector3(0.4, 3, 7.0))              # side wall going back from the right end (x 2.8..3.2)
	await _frames(4)
	player.cover.toggle()
	await _seconds(0.7)
	_check("cover_enter_wall", player.cover.active and not player.cover.low and player.move_mode == Player.Move.COVER, "active=%s low=%s" % [str(player.cover.active), str(player.cover.low)])
	_check("cover_claims_point_for_ai", CoverFinder.is_claimed(player.global_position, 0), "claimed by the player's id")
	player.set_input(Vector2(1, 0))
	await _seconds(0.5)
	var x_mid: float = player.global_position.x - ARENA.x
	_check("cover_slides_right", x_mid > 0.4, "x=%.2f" % x_mid)
	var wrapped := false
	for i in 200:
		await get_tree().physics_frame
		if player.cover.active and not player.cover.transitioning and player.cover.normal.x > 0.9:
			wrapped = true
			break
	await _seconds(0.5)                                   # the held key keeps pushing 'away': it must NOT leave the cover straight after a wrap
	var rel := player.global_position - ARENA
	_check("cover_corner_wrap_position", wrapped and player.cover.active and rel.x > 3.3 and rel.x < 4.2 and rel.z < -1.55, "wrapped=%s rel=%s" % [str(wrapped), str(rel)])
	_check("cover_corner_new_normal", player.cover.active and player.cover.normal.dot(Vector3(1, 0, 0)) > 0.9, "normal=%s" % str(player.cover.normal))
	player.release_input()
	await _seconds(0.4)
	_check("cover_corner_not_transitioning", not player.cover.transitioning and player.cover.active)
	player.cover.toggle()
	await _seconds(0.3)
	_check("cover_leave_q", not player.cover.active and player.move_mode == Player.Move.GROUND)
	wa.queue_free()
	wb.queue_free()
	await _frames(4)

	# ---- low cover: stance, vault, aim over the top, blind fire ---------------------------------------------------------------
	await _reset_player()
	await _equip(&"pistol")
	var low := _box(ARENA + Vector3(0, 0.5, -1.5), Vector3(5, 1.0, 0.5))
	await _frames(4)
	player.cover.toggle()
	await _seconds(0.6)
	_check("cover_low_stance", player.cover.active and player.cover.low and player.stance == &"cover_low", "stance=%s" % str(player.stance))
	var tgt := _npc(ARENA + Vector3(0.0, 0.05, -9.0), 0.0)
	tgt.max_health = 5000.0
	tgt.health = 5000.0
	await _frames(4)
	# blind fire: LMB without aim
	player.cmd_fire = true
	await _frames(6)
	_check("cover_blind_fire_flag", player.cover.blind_firing and player.aim_jitter_deg > 1.0, "blind=%s jitter=%.1f" % [str(player.cover.blind_firing), player.aim_jitter_deg])
	player.cmd_fire = false
	await _seconds(0.3)
	# aimed fire over the top: no jitter, peek lean
	player.cmd_aim = true
	await _seconds(0.6)
	_check("cover_low_aim_over_top", player.aiming and absf(player.cover.peek) > 0.5 and player.aim_jitter_deg < 0.1, "aiming=%s peek=%.2f" % [str(player.aiming), player.cover.peek])
	var hp0 := tgt.health
	var dirv := (tgt.global_position + Vector3(0, 1.3, 0) - cam.global_position).normalized()
	cam.yaw = Util.dir_to_yaw(dirv)
	cam.pitch = asin(dirv.y)
	await _seconds(0.3)
	player.cmd_fire = true
	await _seconds(0.9)
	player.cmd_fire = false
	_check("cover_fire_from_low_cover_hits_target", tgt.health < hp0, "hp %.0f -> %.0f" % [hp0, tgt.health])
	player.cmd_aim = false
	await _seconds(0.4)
	# vault over it with jump
	player.set_input(Vector2.ZERO)
	player.press_jump(false)
	await _seconds(1.2)
	var rz := player.global_position.z - ARENA.z
	_check("cover_jump_vaults_low_cover", rz < -2.0 and not player.cover.active, "z=%.2f mode=%d" % [rz, player.move_mode])
	low.queue_free()
	tgt.queue_free()
	await _frames(4)

	# ---- vehicle cover ------------------------------------------------------------------------------------------------------------
	await _reset_player()
	var car = VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, PI * 0.5), ARENA + Vector3(0, 0.6, -2.0)), {"parked": true, "abandoned": true})
	await _seconds(1.2)
	if car != null:
		player.cover.toggle()
		await _seconds(0.7)
		_check("cover_vehicle_low_stance", player.cover.active and player.cover.low and player.cover.cover_body == car, "active=%s low=%s body=%s" % [str(player.cover.active), str(player.cover.low), str(player.cover.cover_body)])
		car.linear_velocity = Vector3(0, 0, -6)
		await _seconds(0.4)
		_check("cover_leaves_moving_vehicle", not player.cover.active, "active=%s" % str(player.cover.active))
		VehicleFactory.despawn(car)
	else:
		_check("cover_vehicle_low_stance", false, "could not spawn a sedan")

	# ---- assist: nothing within the ray fan (wall 4 m ahead), the shared AI cover probe finds it -------------------------------------
	await _reset_player()
	var far_wall := _box(ARENA + Vector3(0, 1.5, -4.2), Vector3(2.0, 3, 0.4))
	await _frames(4)
	player.cover.toggle()
	await _seconds(0.2)
	var started: bool = player.cover.active and player.cover.transitioning
	await _seconds(1.6)
	var rz2 := player.global_position.z - ARENA.z
	_check("cover_assist_glides_to_cover_finder_spot", started and player.cover.active and not player.cover.transitioning and rz2 < -2.5 and player.cover.normal.z > 0.8,
		"started=%s active=%s z=%.2f normal=%s" % [str(started), str(player.cover.active), rz2, str(player.cover.normal)])
	if player.cover.active:
		player.cover.leave(true)
	far_wall.queue_free()
	await _frames(4)
