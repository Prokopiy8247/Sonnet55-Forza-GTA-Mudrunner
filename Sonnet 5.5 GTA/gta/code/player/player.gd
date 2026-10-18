class_name Player
extends CharacterBase
## The human player: third-person on-foot controller (walk / run / sprint / crouch / jump / swim / aim / melee),
## vehicle driver proxy, interaction scanner, death + arrest + respawn flow.
##
## Architecture notes
##  * Body = CharacterBody3D (this node). Visuals live in `visual` (a top_level Node3D that is interpolated between physics
##    ticks, so motion stays smooth on any display refresh rate) with the CharacterRig inside it.
##  * Input is polled into `cmd_*` fields. Tests (and cutscenes) set `use_real_input = false` and write the fields directly
##    (see set_input / press_jump / press_crouch).
##  * The camera (PlayerCamera) is NOT a child of the body. Movement is camera-relative through get_move_yaw().
##  * Other agents' classes (CharacterRig, WeaponController, VehicleBase) are only used by duck typing so a broken peer
##    file can never take the player down.

signal landed(drop: float, damage: float)
signal stance_changed(new_stance: StringName)
signal swim_changed(swimming: bool)
signal respawn_started(location_id: StringName, reason: StringName)
signal respawned(position: Vector3)
## PlayerSystem owns the full-screen fade overlay and listens to this.
signal fade_requested(to_black: bool, seconds: float)
signal traversal_started(kind: StringName)

enum Move { GROUND, AIR, SWIM, VEHICLE, TRAVERSE, COVER, LADDER, PARACHUTE, RAGDOLL, DEAD, BUSTED }

# ----------------------------------------------------------------------------------------------------------
# Tunables (metres, seconds)
# ----------------------------------------------------------------------------------------------------------
const RADIUS := 0.35
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.25
const SWIM_HEIGHT := 0.9                    # capsule length while swimming (centre at SWIM_CENTER)
const SWIM_CENTER := 0.95
const EYE_STAND := 1.62
const EYE_CROUCH := 1.15

const WALK_SPEED := 2.0
const RUN_SPEED := 4.8
const SPRINT_SPEED := 7.6
const CROUCH_SPEED := 2.1
const AIM_SPEED := 3.0
const SWIM_SPEED := 2.6
const SWIM_FAST_SPEED := 4.2
const DIVE_SPEED := 2.6
const ACCEL_GROUND := 26.0
const DECEL_GROUND := 34.0
const ACCEL_AIR := 5.0
const SWIM_ACCEL := 8.0
const TURN_RATE := 13.0                     # exp smoothing rate for facing the move direction
const AIM_TURN_RATE := 22.0

const GRAVITY := 24.0
const JUMP_HEIGHT := 1.15
const JUMP_VELOCITY := 7.43                 # sqrt(2 * GRAVITY * JUMP_HEIGHT)
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const TERMINAL_VELOCITY := 55.0
const STEP_HEIGHT := 0.45
const FLOOR_MAX_ANGLE := 0.8727             # 50 degrees
const SNAP_LENGTH := 0.4

const FALL_SAFE_HEIGHT := 4.0               # drops up to this are free
const FALL_LETHAL_HEIGHT := 16.0            # drops >= this kill from full health
const FALL_RAGDOLL_HEIGHT := 6.5            # ragdoll hook threshold
const FALL_DAMAGE_PER_M := 8.4

const MAX_STAMINA := 100.0
const STAMINA_DRAIN := 15.0                 # per second of sprinting
const STAMINA_REGEN := 24.0
const STAMINA_RECOVER_AT := 25.0            # after exhaustion sprinting is locked until stamina reaches this

const LUNG_TIME := 20.0                     # seconds of breath (skills 'lung' stretches it)
const SCUBA_LUNG_MULT := 4.0                # scuba gear: breath x4 (Systems-A)
const SCUBA_DRAIN := 0.04                   # scuba gear: air consumption per second (x0.04 = effectively unlimited)
const DROWN_DPS := 12.0
const SWIM_SURFACE_DEPTH := 0.9             # origin sits this far below the surface while surface-swimming
const SWIM_HEAD_OFFSET := 0.95              # head height above the origin in swim stances
const SWIM_RIG_OFFSET := 0.62               # rig node height above the body origin at full swim speed (rig_motion _gen_swim drops the body with speed); 0 when treading
const SWIM_ENTER_DEPTH := 1.3               # water column deeper than this -> swim
const SWIM_EXIT_DEPTH := 1.05

const DEATH_FADE_DELAY := 2.4               # REAL seconds (the UI slows time while the death screen runs)
const DEATH_RESPAWN_DELAY := 3.7
const BUSTED_RESPAWN_DELAY := 2.9
const RESPAWN_CASH_PENALTY := 500
const SPAWN_PROTECTION := 2.0
const HEALTH_REGEN_CAP := 0.5               # slow regen up to 50% when not hurt for a while
const HEALTH_REGEN_RATE := 1.6
const HEALTH_REGEN_DELAY := 7.0

const INTERACT_RANGE := 2.5
const VEHICLE_RANGE := 3.2

const SURFACE_STEP_IDS := {&"concrete": &"step_concrete", &"grass": &"step_grass", &"sand": &"step_sand",
	&"wood": &"step_wood", &"water": &"step_water", &"metal": &"step_concrete", &"dirt": &"step_grass"}

const RIG_SCRIPT := "res://gta/code/player/character_rig.gd"
const WEAPONS_SCRIPT := "res://gta/code/weapons/weapon_controller.gd"

## weapon id -> CharacterRig.set_weapon_pose kind
const WEAPON_POSE := {&"fists": &"none", &"knife": &"melee_knife", &"bat": &"melee_bat", &"crowbar": &"melee_bat",
	&"pistol": &"pistol", &"revolver": &"pistol", &"smg": &"smg", &"shotgun_pump": &"shotgun", &"shotgun_auto": &"shotgun",
	&"rifle_assault": &"rifle", &"carbine": &"rifle", &"rifle_marksman": &"sniper", &"sniper": &"sniper",
	&"grenade": &"thrown", &"rocket_launcher": &"heavy", &"grenade_launcher": &"heavy"}

# ----------------------------------------------------------------------------------------------------------
# Public state (HUD / other agents read these)
# ----------------------------------------------------------------------------------------------------------
var move_mode: Move = Move.GROUND
var stance: StringName = &"stand"
var crouching := false
var sprinting := false
var aiming := false
var is_swimming := false
var is_underwater := false          # the camera is below the water surface (Environment agent: underwater post-process)
var head_underwater := false        # the head is below the surface (lungs drain)
var water_surface_y := NAN          # NAN when not in/over water
var wading_depth := 0.0             # water above the feet when standing in shallows
var stamina := MAX_STAMINA
var lungs := LUNG_TIME
var max_stamina: float:                # read by the HUD together with `stamina` / `lungs` (ratio = value / max)
	get:
		return MAX_STAMINA
var max_lungs: float:
	get:
		return lung_capacity()
var noise_radius := 0.0             # metres within which the player is currently AUDIBLE (published by PlayerStealth every tick)
var visibility01 := 0.5             # 0..1 how conspicuous the player is at close range (PlayerStealth: light, posture, cover, flash)
var detection_range := 30.0         # metres at which a viewer with line of sight can notice the player (PlayerStealth)
var stealth_exposed := false        # visibility01 >= PlayerStealth.EXPOSED_AT
var takedown_target: Node3D = null  # unaware NPC the melee key would silently take down right now
var stealth = null                  # PlayerStealth
var aim_jitter_deg := 0.0           # random cone (deg) added to the aim ray while blind-firing / rolling (cover, dodge)
var surface_type: StringName = &"concrete"
var has_parachute := false
var has_scuba := false              # scuba gear owned (Systems-A pickup / dive shop): lung capacity x SCUBA_LUNG_MULT
var spawn_protection := 0.0
var fall_drop := 0.0                # last landing drop height (metres)
var camera = null                   # PlayerCamera (set by PlayerSystem)
var visual: Node3D = null
var interaction = null              # PlayerInteraction
var traversal = null                # PlayerTraversal (vault / mantle / ladder / climb out)
var cover = null                    # PlayerCover
var input_locked := false           # cutscenes / UI can freeze the player
var last_vehicle: Node = null

# ---- Command fields (filled from real input every physics frame unless use_real_input is false) -------------
var use_real_input := true
var cmd_move := Vector2.ZERO        # x: +right, y: +forward
var cmd_sprint := false
var cmd_walk := false
var cmd_aim := false
var cmd_fire := false
var cmd_jump_held := false
var cmd_crouch_held := false
var edge_jump := false
var edge_crouch := false
var move_yaw_override := NAN        # test hook: movement yaw (else the camera yaw, else body yaw)

# ---- Internals ---------------------------------------------------------------------------------------------
var _collider: CollisionShape3D
var _capsule: CapsuleShape3D
var _cur_height := STAND_HEIGHT
var _water_sensor: Area3D
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := false
var _fall_peak_y := 0.0
var _land_slow := 0.0
var _stamina_delay := 0.0
var _exhausted := false
var _step_accum := 0.0
var _damage_free_time := 0.0
var _last_stance: StringName = &""
var _last_weapon_pose: StringName = &""
var _trigger_down := false
var _aiming_sent := false
var _melee_down_time := -1.0
var _death_time := 0.0
var _fade_sent := false
var _busted_time := 0.0
var _busted_reason: StringName = &"arrest"
var _frozen_for_ground := false
var _ground_wait_time := 0.0
var _drown_tick := 0.0
var _swim_bob := 0.0
var _fp_ragdoll_until := 0.0
var _ragdoll_time := 0.0
var _air_throttle := 0.0
var _steer_smooth := 0.0
var _prev_rot := Quaternion.IDENTITY
var _curr_rot := Quaternion.IDENTITY
var _rig_airborne := false
var _air_time := 0.0
var _impact_vy := 0.0
var _rig_is_fallback := false
var _fallback_mesh: MeshInstance3D = null
var _head_hidden_for_fp := false
var _seat_logged := false
var _flash_on := false
var _vehicle_enter_cd := 0.0
var _hands_up_sent := false
var _prev_underwater_head := false
var _surfaced_gasp_armed := false
var _stowed_weapon: StringName = &""
var _lung_cap_seen := -1.0


# ==========================================================================================================
# Lifecycle
# ==========================================================================================================
func _ready() -> void:
	super._ready()
	display_name = "Player"
	faction = GC.F_PLAYER
	add_to_group(GC.G_PLAYER)
	collision_layer = GC.L_PLAYER
	collision_mask = GC.M_CHARACTER_MOVE
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = FLOOR_MAX_ANGLE
	floor_snap_length = SNAP_LENGTH
	floor_stop_on_slope = true
	floor_block_on_wall = true
	max_slides = 6
	_build_body()
	_build_visual()
	_build_weapons()
	var iscript = load("res://gta/code/player/player_interaction.gd")
	if iscript != null and iscript.can_instantiate():
		interaction = iscript.new()
		interaction.name = "Interaction"
		add_child(interaction)
		interaction.setup(self)
	var tscript = load("res://gta/code/player/player_traversal.gd")
	if tscript != null and tscript.can_instantiate():
		traversal = tscript.new()
		traversal.name = "Traversal"
		add_child(traversal)
		traversal.setup(self)
	var cscript = load("res://gta/code/player/player_cover.gd")
	if cscript != null and cscript.can_instantiate():
		cover = cscript.new()
		cover.name = "Cover"
		add_child(cover)
		cover.setup(self)
	var sscript = load("res://gta/code/player/player_stealth.gd")
	if sscript != null and sscript.can_instantiate():
		stealth = sscript.new()
		stealth.name = "Stealth"
		add_child(stealth)
		stealth.setup(self)
	_fall_peak_y = global_position.y
	_reset_interp()
	Events.weapon_changed.connect(_on_weapon_changed)
	Events.vehicle_exited.connect(_on_vehicle_exited_event)


func _build_body() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = STAND_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.name = "Collider"
	_collider.shape = _capsule
	_collider.position = Vector3(0, STAND_HEIGHT * 0.5, 0)
	add_child(_collider)
	# water sensor: a small sphere around the torso, sees Area3D water volumes on GC.L_WATER
	_water_sensor = Area3D.new()
	_water_sensor.name = "WaterSensor"
	_water_sensor.collision_layer = 0
	_water_sensor.collision_mask = GC.L_WATER
	_water_sensor.monitorable = false
	_water_sensor.monitoring = true
	var sc := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	sc.shape = sph
	sc.position = Vector3(0, 0.9, 0)
	_water_sensor.add_child(sc)
	add_child(_water_sensor)


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	visual.top_level = true
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # interpolated by hand in _process (see _process)
	add_child(visual)
	var rscript = load(RIG_SCRIPT)
	if rscript != null and rscript.can_instantiate():
		rig = rscript.new()
		rig.name = "Rig"
		visual.add_child(rig)
		rig.setup(_make_variant())
	else:
		push_warning("[Player] CharacterRig script failed to load - using capsule fallback")
	_check_rig_fallback()
	visual.global_transform = global_transform


func _make_variant() -> Dictionary:
	var vs = load("res://gta/code/player/character_variants.gd")
	if vs != null and vs.can_instantiate() and vs.has_method("player_default"):
		return vs.player_default()
	return {"body": &"A", "skin": Color("#d9a07a"), "hair_color": Color("#2b1d16"), "hair": 2, "shirt": Color("#34a8c4"),
		"pants": Color("#2f3a4f"), "shoes": Color("#f1efe8"), "accent": Color("#ff3d9a"), "scale": 1.0}


## If the rig produced no geometry (stub / missing GLB), show an obviously-labelled capsule so the player is visible.
func _check_rig_fallback() -> void:
	var has_geo := false
	if rig != null:
		var skel = rig.get_skeleton()
		has_geo = skel != null or not ModelLib.meshes(rig).is_empty()
	if has_geo:
		_rig_is_fallback = false
		if _fallback_mesh != null:
			_fallback_mesh.queue_free()
			_fallback_mesh = null
		return
	if _fallback_mesh != null:
		return
	_rig_is_fallback = true
	push_warning("[Player] FALLBACK: CharacterRig has no geometry yet - showing capsule placeholder (Rig agent / characters/human.glb pending)")
	var mi := MeshInstance3D.new()
	mi.name = "FallbackCapsule"
	var cm := CapsuleMesh.new()
	cm.radius = RADIUS
	cm.height = STAND_HEIGHT
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#34e0ff")
	mat.emission_enabled = true
	mat.emission = Color("#0a4a58")
	mi.material_override = mat
	mi.position = Vector3(0, STAND_HEIGHT * 0.5, 0)
	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 0.4)
	nose.mesh = bm
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color("#ff3d9a")
	nose.material_override = nm
	nose.position = Vector3(0, 0.5, -0.4)
	mi.add_child(nose)
	visual.add_child(mi)
	_fallback_mesh = mi


func _build_weapons() -> void:
	var wscript = load(WEAPONS_SCRIPT)
	if wscript != null and wscript.can_instantiate():
		weapons = wscript.new()
		weapons.name = "Weapons"
		add_child(weapons)
		weapons.setup(self)
	else:
		push_warning("[Player] WeaponController script failed to load - player is unarmed")


# ==========================================================================================================
# Input
# ==========================================================================================================
func _input(event: InputEvent) -> void:
	if not use_real_input or not _gameplay_input_allowed():
		return
	if event is InputEventMouseMotion or event.is_echo():
		return
	if move_mode == Move.DEAD or move_mode == Move.BUSTED:
		return
	if event.is_action_pressed(&"jump"):
		edge_jump = true
	if event.is_action_pressed(&"crouch"):
		edge_crouch = true
	if event is InputEventKey or event is InputEventMouseButton:
		_handle_action_event(event)


func _handle_action_event(event: InputEvent) -> void:
	var pressed := event.is_pressed()
	if event.is_action(&"melee"):
		if pressed:
			_melee_down_time = 0.0
		elif _melee_down_time >= 0.0:
			melee(_melee_down_time > 0.28)
			_melee_down_time = -1.0
		return
	if not pressed:
		return
	if event.is_action_pressed(&"interact", false, true):
		if interaction != null:
			interaction.try_interact()
	elif event.is_action_pressed(&"enter_exit", false, true):
		if interaction != null:
			interaction.try_enter_exit()
	elif event.is_action_pressed(&"reload", false, true):
		if weapons != null and not is_in_vehicle():
			weapons.start_reload()
	elif event.is_action_pressed(&"weapon_next", false, true):
		if weapons != null:
			if weapons.get("scope_active") == true and weapons.has_method("cycle_zoom"):
				weapons.cycle_zoom()
			else:
				weapons.equip_next()
	elif event.is_action_pressed(&"weapon_prev", false, true):
		if weapons != null:
			if weapons.get("scope_active") == true and weapons.has_method("cycle_zoom"):
				weapons.cycle_zoom()
			else:
				weapons.equip_prev()
	elif event.is_action_pressed(&"look_back", false, true) and not is_in_vehicle():
		if weapons != null and weapons.has_method("toggle_fire_mode"):
			weapons.toggle_fire_mode()
	elif event.is_action_pressed(&"grenade", false, true):
		throw_grenade()
	elif event.is_action_pressed(&"flashlight", false, true):
		toggle_flashlight()
	elif event.is_action_pressed(&"camera_toggle", false, true):
		if is_instance_valid(camera):
			camera.toggle_first_person()
	elif event.is_action_pressed(&"shoulder_swap", false, true):
		if is_instance_valid(camera):
			camera.swap_shoulder()
	elif event.is_action_pressed(&"cover", false, true):
		if cover != null:
			cover.toggle()
	else:
		for i in 9:
			if event.is_action_pressed(StringName("weapon_slot_%d" % (i + 1)), false, true):
				if weapons != null:
					weapons.equip_slot(i + 1)
				break


## True when gameplay input should be processed (no open menu / pause / lock).
func _gameplay_input_allowed() -> bool:
	if input_locked or Game.paused:
		return false
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("is_menu_open") and ui.is_menu_open():
		return false
	return true


func _poll_input() -> void:
	if not use_real_input:
		return
	if not _gameplay_input_allowed() or move_mode == Move.DEAD or move_mode == Move.BUSTED:
		cmd_move = Vector2.ZERO
		cmd_sprint = false
		cmd_walk = false
		cmd_aim = false
		cmd_fire = false
		cmd_jump_held = false
		cmd_crouch_held = false
		edge_jump = false
		edge_crouch = false
		return
	cmd_move = Vector2(Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back"))
	if cmd_move.length() > 1.0:
		cmd_move = cmd_move.normalized()
	cmd_sprint = Input.is_action_pressed(&"sprint")
	cmd_walk = Input.is_action_pressed(&"walk") if InputMap.has_action(&"walk") else false
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	cmd_aim = Input.is_action_pressed(&"aim") and captured
	cmd_fire = Input.is_action_pressed(&"fire") and captured
	cmd_jump_held = Input.is_action_pressed(&"jump")
	cmd_crouch_held = Input.is_action_pressed(&"crouch")
	if _melee_down_time >= 0.0:
		_melee_down_time += get_physics_process_delta_time()


# ---- Test / cutscene input API ------------------------------------------------------------------------------
func set_input(move: Vector2, sprint := false, aim := false, walk := false) -> void:
	use_real_input = false
	cmd_move = move.limit_length(1.0)
	cmd_sprint = sprint
	cmd_aim = aim
	cmd_walk = walk


func press_jump(hold := true) -> void:
	use_real_input = false
	edge_jump = true
	cmd_jump_held = hold


func press_crouch() -> void:
	use_real_input = false
	edge_crouch = true


func release_input() -> void:
	cmd_move = Vector2.ZERO
	cmd_sprint = false
	cmd_aim = false
	cmd_walk = false
	cmd_fire = false
	cmd_jump_held = false
	cmd_crouch_held = false


# ==========================================================================================================
# Main tick
# ==========================================================================================================
func _physics_process(dt: float) -> void:
	if _frozen_for_ground:
		_tick_wait_ground(dt)
		_record_interp()
		return
	_poll_input()
	_tick_timers(dt)
	match move_mode:
		Move.GROUND, Move.AIR:
			_tick_foot(dt)
		Move.SWIM:
			_tick_swim(dt)
		Move.VEHICLE:
			_tick_vehicle(dt)
		Move.TRAVERSE, Move.LADDER, Move.PARACHUTE:
			if traversal != null:
				traversal.tick(dt)
		Move.COVER:
			if cover != null:
				cover.tick(dt)
		Move.RAGDOLL:
			_tick_ragdoll(dt)
		Move.DEAD:
			_tick_dead(dt)
		Move.BUSTED:
			_tick_busted(dt)
	_post_tick(dt)
	edge_jump = false
	edge_crouch = false


func _tick_timers(dt: float) -> void:
	_update_lungs(dt)
	_vehicle_enter_cd = maxf(_vehicle_enter_cd - dt, 0.0)
	spawn_protection = maxf(spawn_protection - dt, 0.0)
	invulnerable = spawn_protection > 0.0
	_land_slow = maxf(_land_slow - dt, 0.0)
	_damage_free_time += dt
	if _damage_free_time > HEALTH_REGEN_DELAY and not is_dead and health < max_health * HEALTH_REGEN_CAP:
		health = minf(health + HEALTH_REGEN_RATE * dt, max_health * HEALTH_REGEN_CAP)


func _on_damaged(_amount: float, info: Dictionary) -> void:
	_damage_free_time = 0.0
	if rig != null and not is_dead and move_mode != Move.RAGDOLL:
		rig.play_action(&"hit_react")
	if is_instance_valid(camera):
		camera.add_shake(clampf(_amount / 60.0, 0.08, 0.5), 0.35)
	var t: StringName = info.get("type", &"")
	if not is_dead and t != GC.DMG_FALL and t != GC.DMG_DROWN:
		Sfx.play_3d(&"hurt_m", global_position + Vector3.UP * 1.5, -2.0, randf_range(0.95, 1.05), 30.0)


# ==========================================================================================================
# On foot
# ==========================================================================================================
func get_move_yaw() -> float:
	if not is_nan(move_yaw_override):
		return move_yaw_override
	if is_instance_valid(camera):
		return camera.yaw
	return rotation.y


func _compute_wish() -> Vector3:
	var yaw := get_move_yaw()
	var fwd := Util.yaw_to_dir(yaw)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var w := fwd * cmd_move.y + right * cmd_move.x
	if w.length() > 1.0:
		w = w.normalized()
	return w


func _tick_foot(dt: float) -> void:
	if stealth != null and stealth.in_takedown:
		stealth.tick_takedown(dt)
		return
	_sample_water()
	if not is_nan(water_surface_y):
		var below := water_surface_y - global_position.y
		wading_depth = clampf(below, 0.0, 2.0)
		if below > 0.25 and _water_column_depth() > SWIM_ENTER_DEPTH:
			_enter_swim()
			return
	else:
		wading_depth = 0.0

	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
		move_mode = Move.GROUND
	else:
		_coyote = maxf(_coyote - dt, 0.0)
		move_mode = Move.AIR
	if edge_jump:
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer = maxf(_jump_buffer - dt, 0.0)

	_update_crouch(dt)
	var wish := _compute_wish()
	var move_len := wish.length()
	_update_sprint(dt, move_len, on_floor)
	var fire_facing := cmd_fire and weapons != null and _weapon_is_ranged()
	aiming = cmd_aim and not sprinting
	var strafe: bool = aiming or fire_facing or (is_instance_valid(camera) and camera.first_person_active())

	# horizontal velocity
	var target_speed := _ground_target_speed(move_len, strafe)
	var target_v := wish.normalized() * target_speed if move_len > 0.02 else Vector3.ZERO
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var accel := ACCEL_AIR
	if on_floor:
		accel = ACCEL_GROUND if target_v.length() >= h.length() - 0.01 else DECEL_GROUND
	h = h.move_toward(target_v, accel * dt)
	if _land_slow > 0.0 and on_floor:
		h *= 1.0 - minf(dt * 9.0, 0.5)
	velocity.x = h.x
	velocity.z = h.z

	# facing
	var turn_rate := TURN_RATE
	if strafe:
		rotation.y = lerp_angle(rotation.y, get_move_yaw(), 1.0 - exp(-AIM_TURN_RATE * dt))
	elif h.length() > 0.35 and move_len > 0.02:
		rotation.y = lerp_angle(rotation.y, Util.dir_to_yaw(h), 1.0 - exp(-turn_rate * dt))

	# vertical: jump / gravity
	if _jump_buffer > 0.0 and _coyote > 0.0:
		if _try_traversal_instead_of_jump():
			_jump_buffer = 0.0
			return
		if crouching and not _try_stand():
			pass
		else:
			_do_jump()
	if not on_floor or velocity.y > 0.0:
		velocity.y = maxf(velocity.y - GRAVITY * dt, -TERMINAL_VELOCITY)
	# variable jump height: releasing the key early shortens the hop
	if velocity.y > 3.2 and not cmd_jump_held and not on_floor:
		velocity.y = 3.2
	# parachute / air actions
	if not on_floor and edge_jump and _jump_buffer > 0.0 and _coyote <= 0.0 and traversal != null:
		if traversal.try_parachute():
			return
		if traversal.try_ledge_grab():
			return
	floor_snap_length = 0.0 if velocity.y > 0.5 else SNAP_LENGTH

	if on_floor and move_len > 0.02:
		_try_step_up(h, dt)
	var vy_before := velocity.y
	move_and_slide()
	_after_move(dt, on_floor)
	if is_on_floor() and not on_floor:
		_impact_vy = vy_before


func _weapon_is_ranged() -> bool:
	if weapons == null:
		return false
	var d = weapons.get_current_def()
	if d is Dictionary and not d.is_empty():
		var k = d.get("kind", d.get("class", &""))
		return k != &"melee" and k != &"fists" and weapons.current_id != &"fists"
	return weapons.current_id != &"fists"


func _ground_target_speed(move_len: float, strafe: bool) -> float:
	if move_len < 0.02:
		return 0.0
	var spd := RUN_SPEED
	if crouching:
		spd = CROUCH_SPEED
	elif sprinting:
		spd = SPRINT_SPEED
	elif strafe:
		spd = AIM_SPEED
	elif cmd_walk or move_len < 0.55:
		spd = WALK_SPEED
	elif move_len < 0.85:
		spd = lerpf(WALK_SPEED, RUN_SPEED, (move_len - 0.55) / 0.3)
	# analog scaling of whatever the base speed is
	spd *= clampf(move_len, 0.0, 1.0) if move_len < 0.55 else 1.0
	if wading_depth > 0.15:
		spd *= 1.0 - clampf(wading_depth / 1.3, 0.0, 1.0) * 0.45
	if _land_slow > 0.0:
		spd *= 0.65
	if health < max_health * 0.2:
		spd *= 0.88
	return spd


func _update_sprint(dt: float, move_len: float, on_floor: bool) -> void:
	var want := cmd_sprint and move_len > 0.5 and not cmd_aim and not _exhausted and wading_depth < 0.9
	if _exhausted and stamina >= STAMINA_RECOVER_AT:
		_exhausted = false
	if want and stamina > 0.0:
		if crouching:
			_try_stand()
		if not crouching:
			sprinting = true
	else:
		sprinting = false
	if sprinting and on_floor:
		stamina = maxf(stamina - STAMINA_DRAIN * dt / _stamina_factor(), 0.0)
		_stamina_delay = 0.9
		_skill_use(&"stamina", dt * 0.6)
		if stamina <= 0.0:
			_exhausted = true
			sprinting = false
	elif not sprinting:
		_stamina_delay = maxf(_stamina_delay - dt, 0.0)
		if _stamina_delay <= 0.0:
			stamina = minf(stamina + STAMINA_REGEN * dt, MAX_STAMINA)


func _stamina_factor() -> float:
	return 1.0 + 1.2 * _skill01(&"stamina")


func _do_jump() -> void:
	velocity.y = JUMP_VELOCITY * (1.06 if sprinting else 1.0)
	_jump_buffer = 0.0
	_coyote = 0.0
	move_mode = Move.AIR
	floor_snap_length = 0.0
	stamina = maxf(stamina - 4.0, 0.0)
	_rig_airborne = true
	if rig != null:
		rig.play_action(&"jump")
	Sfx.play_3d(&"jump", global_position, -8.0, randf_range(0.95, 1.05), 25.0)


func _update_crouch(dt: float) -> void:
	if edge_crouch:
		if crouching:
			_try_stand()
		else:
			crouching = true
			sprinting = false
	if crouching and cmd_sprint and cmd_move.length() > 0.5:
		_try_stand()
	var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	if not is_equal_approx(_cur_height, target_h):
		_cur_height = move_toward(_cur_height, target_h, 5.0 * dt)
		_apply_capsule(_cur_height)


## Stand up if there is headroom. Returns true when standing (or already standing).
func _try_stand() -> bool:
	if not crouching:
		return true
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS - 0.03
	shape.height = STAND_HEIGHT - 0.05
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, STAND_HEIGHT * 0.5 + 0.03, 0))
	params.collision_mask = GC.L_WORLD | GC.L_PROP
	params.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 1)
	if hits.is_empty():
		crouching = false
		return true
	return false


func _apply_capsule(h: float, center: float = -1.0) -> void:
	_capsule.height = maxf(h, RADIUS * 2.0 + 0.01)
	_collider.position.y = h * 0.5 if center < 0.0 else center


## Step-up for stairs/curbs: if the horizontal motion is blocked by a low ledge, lift the body onto it.
func _try_step_up(h: Vector3, dt: float) -> void:
	var motion := Vector3(h.x, 0.0, h.z) * dt
	if motion.length_squared() < 0.0000001:
		return
	motion = motion.normalized() * maxf(motion.length(), 0.06)
	var t := global_transform
	var col := KinematicCollision3D.new()
	if not test_move(t, motion, col, 0.002, false, 1):
		return
	if col.get_normal().y > 0.7:
		return    # a walkable slope, move_and_slide handles it
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(t, up):
		return
	var t_up := t.translated(up)
	var reach := motion.normalized() * (RADIUS + 0.1)     # far enough that the probe lands on the flat top, not the edge
	if test_move(t_up, reach):
		return
	var t_fwd := t_up.translated(reach)
	var dcol := KinematicCollision3D.new()
	if test_move(t_fwd, Vector3.DOWN * (STEP_HEIGHT + 0.06), dcol, 0.002):
		if dcol.get_normal().y >= cos(FLOOR_MAX_ANGLE):
			global_position.y = t_up.origin.y + dcol.get_travel().y + 0.01


func _after_move(dt: float, was_on_floor: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		if not was_on_floor and not _was_on_floor:
			pass
		if not _was_on_floor:
			_on_landed()
		_fall_peak_y = global_position.y
		_step_footsteps(dt)
	else:
		_fall_peak_y = maxf(_fall_peak_y, global_position.y)
	_was_on_floor = on_floor
	# world safety nets
	if global_position.y < -120.0 and is_nan(water_surface_y):
		push_warning("[Player] fell out of the world at %s - respawning" % str(global_position))
		respawn_at(&"player_spawn", {"penalty": 0, "silent": true})


func _on_landed() -> void:
	var drop := maxf(_fall_peak_y - global_position.y, 0.0)
	fall_drop = drop
	if drop < 0.5:
		return
	var in_water := wading_depth > 0.6
	var dmg := 0.0
	if drop > FALL_SAFE_HEIGHT and not in_water:
		dmg = (drop - FALL_SAFE_HEIGHT) * FALL_DAMAGE_PER_M
		var sk = Game.sys(&"skills")                  # Systems-A hook: strength = fall resilience
		if sk != null and sk.has_method("get_modifier"):
			dmg *= float(sk.get_modifier(&"fall_damage"))
		if Game.cheats.get("invulnerable", false) or spawn_protection > 0.0:
			dmg = 0.0
	if dmg > 0.0:
		_apply_unarmored_damage(dmg, {"type": GC.DMG_FALL, "zone": GC.ZONE_TORSO, "source": null, "position": global_position})
	var heavy := drop > 2.2
	if heavy:
		_land_slow = 0.35 if drop < 5.0 else 0.7
	var vol := -14.0 + clampf(drop, 0.0, 8.0) * 1.6
	Sfx.play_3d(&"land", global_position, vol, randf_range(0.92, 1.05), 40.0)
	if is_instance_valid(camera) and drop > 1.2:
		camera.add_shake(clampf(drop * 0.04, 0.05, 0.6), 0.3 + minf(drop * 0.03, 0.3))
	landed.emit(drop, dmg)
	if stealth != null and not in_water:
		stealth.on_landing(drop)
	if not is_dead and drop > FALL_RAGDOLL_HEIGHT and not in_water:
		ragdoll_for(1.4 + minf((drop - FALL_RAGDOLL_HEIGHT) * 0.2, 1.2), velocity)


## Applies damage that ignores armor (fall, drowning).
func _apply_unarmored_damage(amount: float, info: Dictionary) -> void:
	var a := armor
	armor = 0.0
	apply_damage(amount, info)
	if not is_dead:
		armor = a


# ==========================================================================================================
# Footsteps / surface / noise
# ==========================================================================================================
func _step_footsteps(dt: float) -> void:
	var h := Vector2(velocity.x, velocity.z).length()
	if h < 0.8:
		return
	var stride := 1.25
	var vol_db := -6.0
	if sprinting:
		stride = 1.95
		vol_db = -1.0
	elif crouching:
		stride = 1.05
		vol_db = -15.0
	elif h > RUN_SPEED * 0.75:
		stride = 1.65
		vol_db = -3.0
	_step_accum += h * dt
	if _step_accum < stride:
		return
	_step_accum -= stride
	var surf := _detect_surface()
	surface_type = surf
	var id: StringName = SURFACE_STEP_IDS.get(surf, &"step_concrete")
	if Sfx.has_sound(id):
		Sfx.play_3d(id, global_position, vol_db, randf_range(0.92, 1.08), 24.0)
	if surf == &"water" and Sfx.has_sound(&"splash") and wading_depth > 0.3:
		Sfx.play_3d(&"splash", global_position, vol_db - 6.0, randf_range(1.0, 1.25), 18.0)
	_skill_use(&"stealth", 0.0 if not crouching else dt * 0.05)


func _detect_surface() -> StringName:
	if wading_depth > 0.12:
		return &"water"
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y > 0.6:
			var col := c.get_collider() as Node
			var n: Node = col
			var depth := 0
			while n != null and depth < 3:
				if n.has_meta(&"surface"):
					return StringName(n.get_meta(&"surface"))
				n = n.get_parent()
				depth += 1
			break
	var p := global_position
	for pier in WorldLayout.piers:
		var r: Rect2 = pier.get("rect", Rect2())
		if r.has_point(Vector2(p.x, p.z)) and p.y > GC.WATER_LEVEL + 0.5:
			return &"wood"
	match WorldLayout.district_at(p.x, p.z):
		GC.D_BEACH:
			return &"sand"
		GC.D_PARK:
			return &"grass"
	return &"concrete"


# ==========================================================================================================
# Water & swimming
# ==========================================================================================================
func _sample_water() -> void:
	var sy := NAN
	if _water_sensor != null and _water_sensor.monitoring:
		for a in _water_sensor.get_overlapping_areas():
			var t := _area_surface_y(a)
			if is_nan(sy) or t > sy:
				sy = t
	if is_nan(sy):
		var p := global_position
		if WorldLayout.is_water(p.x, p.z):
			sy = GC.WATER_LEVEL
	water_surface_y = sy


static func _area_surface_y(a: Area3D) -> float:
	if a.has_meta(&"surface_y"):
		return float(a.get_meta(&"surface_y"))
	for c in a.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var cs := c as CollisionShape3D
			return cs.global_position.y + (cs.shape as BoxShape3D).size.y * 0.5 * cs.global_transform.basis.get_scale().y
	return GC.WATER_LEVEL


## Water above the floor below the player (floor probed with a ray; unknown floor = very deep).
func _water_column_depth() -> float:
	if is_nan(water_surface_y):
		return 0.0
	var from := global_position + Vector3(0, 0.3, 0)
	var hit := Util.raycast(self, from, from + Vector3.DOWN * 6.0, GC.M_GROUND, [self])
	var floor_y := global_position.y - 6.0
	if not hit.is_empty():
		floor_y = (hit["position"] as Vector3).y
	return water_surface_y - floor_y


func _enter_swim() -> void:
	if is_swimming:
		return
	is_swimming = true
	move_mode = Move.SWIM
	crouching = false
	sprinting = false
	_cur_height = STAND_HEIGHT
	_apply_capsule(SWIM_HEIGHT, SWIM_CENTER)
	var impact := -velocity.y
	if impact > 5.0:
		Sfx.play_3d(&"splash_big", global_position, 0.0, randf_range(0.95, 1.05), 60.0)
		Events.projectile_impact.emit(Vector3(global_position.x, water_surface_y, global_position.z), Vector3.UP, &"water", self)
		if is_instance_valid(camera):
			camera.add_shake(0.12, 0.3)
	else:
		Sfx.play_3d(&"splash", global_position, -2.0, randf_range(0.95, 1.05), 40.0)
	velocity.y *= 0.25
	velocity.x *= 0.7
	velocity.z *= 0.7
	floor_snap_length = 0.0
	_fall_peak_y = global_position.y
	_surfaced_gasp_armed = false
	stow_weapon()          # no gun waving while swimming; re-drawn when we leave the water
	swim_changed.emit(true)


func _exit_swim() -> void:
	if not is_swimming:
		return
	is_swimming = false
	head_underwater = false
	_apply_capsule(STAND_HEIGHT)
	_cur_height = STAND_HEIGHT
	velocity.y = 0.0
	move_mode = Move.GROUND
	_was_on_floor = false
	_fall_peak_y = global_position.y
	unstow_weapon()
	swim_changed.emit(false)


func _tick_swim(dt: float) -> void:
	_sample_water()
	if is_nan(water_surface_y):
		_exit_swim()
		return
	var sy := water_surface_y
	var col_depth := _water_column_depth()
	var origin_depth := sy - global_position.y
	if col_depth < SWIM_EXIT_DEPTH and origin_depth > SWIM_SURFACE_DEPTH - 0.1:
		_exit_swim()
		return
	if edge_jump and traversal != null and traversal.try_climb_out():
		return
	var wish := _compute_wish()
	var move_len := wish.length()
	head_underwater = global_position.y + SWIM_HEAD_OFFSET < sy - 0.06
	var fast := cmd_sprint and stamina > 1.0 and move_len > 0.5 and not head_underwater
	var speed := (SWIM_FAST_SPEED if fast else SWIM_SPEED) if not head_underwater else DIVE_SPEED
	if fast:
		stamina = maxf(stamina - STAMINA_DRAIN * 0.6 * dt / _stamina_factor(), 0.0)
		_stamina_delay = 0.8
		_skill_use(&"stamina", dt * 0.8)
	else:
		_stamina_delay = maxf(_stamina_delay - dt, 0.0)
		if _stamina_delay <= 0.0:
			stamina = minf(stamina + STAMINA_REGEN * 0.5 * dt, MAX_STAMINA)
	sprinting = fast
	aiming = false
	var target_v := wish.normalized() * speed * minf(move_len, 1.0) if move_len > 0.02 else Vector3.ZERO
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_v, SWIM_ACCEL * dt)
	velocity.x = h.x
	velocity.z = h.z
	# vertical control
	var cam_pitch: float = camera.pitch if is_instance_valid(camera) else 0.0
	var vy := 0.0
	var diving := origin_depth > SWIM_SURFACE_DEPTH + 0.2
	if cmd_crouch_held:
		vy -= DIVE_SPEED
	if cmd_jump_held:
		vy += DIVE_SPEED
	if move_len > 0.1 and (diving or cam_pitch < -0.62) and cmd_move.y > 0.1:
		vy += sin(cam_pitch) * speed * cmd_move.y
	_swim_bob += dt
	var surface_y_target := sy - SWIM_SURFACE_DEPTH + sin(_swim_bob * 2.1) * 0.035
	if absf(vy) < 0.05:
		if origin_depth > SWIM_SURFACE_DEPTH + 0.06:
			vy = clampf((surface_y_target - global_position.y) * 2.2, 0.0, 1.1)   # gentle buoyancy
		else:
			vy = (surface_y_target - global_position.y) * 6.0
	elif vy > 0.0 and origin_depth <= SWIM_SURFACE_DEPTH:
		vy = (surface_y_target - global_position.y) * 6.0
	velocity.y = move_toward(velocity.y, vy, 14.0 * dt)
	# facing
	if move_len > 0.05 and h.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, Util.dir_to_yaw(h), 1.0 - exp(-8.0 * dt))
	floor_snap_length = 0.0
	move_and_slide()
	global_position.y = minf(global_position.y, sy - SWIM_SURFACE_DEPTH + 0.1)
	_swim_footsteps(dt, h.length())


func _swim_footsteps(dt: float, h: float) -> void:
	if h < 1.0 or head_underwater:
		return
	_step_accum += h * dt
	if _step_accum > 1.8:
		_step_accum = 0.0
		Sfx.play_3d(&"splash", global_position, -14.0, randf_range(1.1, 1.4), 20.0)


## Runs every physics tick in every move mode (not only while swimming): the lung capacity depends on the skills system, which boots
## AFTER the player, so a stored `lungs` value would otherwise start below `max_lungs` and make the HUD air bar show at spawn.
## A full lung stays full when the capacity changes; dry land refills quickly.
func _update_lungs(dt: float) -> void:
	var cap := lung_capacity()
	if _lung_cap_seen < 0.0 or lungs >= _lung_cap_seen - 0.001 or lungs > cap:
		lungs = cap                                   # was full (or first tick): follow the capacity
	_lung_cap_seen = cap
	var drain := lung_drain_rate()
	if head_underwater and drain > 0.0:
		lungs = maxf(lungs - dt * drain, 0.0)
		_skill_use(&"lung", dt * 0.5)
		_surfaced_gasp_armed = lungs < cap * 0.7
		if lungs <= 0.0:
			_drown_tick -= dt
			if _drown_tick <= 0.0:
				_drown_tick = 0.5
				_apply_unarmored_damage(DROWN_DPS * 0.5, {"type": GC.DMG_DROWN, "zone": GC.ZONE_TORSO, "source": null, "position": global_position})
	else:
		if lungs < cap:
			lungs = minf(lungs + dt * (6.0 if is_swimming else 14.0), cap)
		if _prev_underwater_head and _surfaced_gasp_armed:
			Sfx.play_3d(&"gasp", global_position, -2.0, 1.0, 30.0)
			_surfaced_gasp_armed = false
	_prev_underwater_head = head_underwater
	if not head_underwater:
		_drown_tick = 0.0


## Air consumption per second while the head is under water: 1 normally, ~0 with scuba gear (the tank lasts ~30 min of diving), 0 with the cheats
## (Game.cheats scuba / infinite_lungs; the shop's tank drives cheats['scuba'] while it has air).
func lung_drain_rate() -> float:
	if Game.cheats.get("infinite_lungs", false) or Game.cheats.get("scuba", false):
		return 0.0
	if has_scuba:
		return SCUBA_DRAIN
	return 1.0


func lung_capacity() -> float:
	# Systems-A hook: skill 'lung' 20 s -> 60 s at 100 %, scuba gear (EconomySystem pickup / shop) multiplies it
	return LUNG_TIME * (1.0 + 2.0 * _skill01(&"lung")) * (SCUBA_LUNG_MULT if has_scuba else 1.0)


func get_stamina01() -> float:
	return clampf(stamina / MAX_STAMINA, 0.0, 1.0)


func get_lung01() -> float:
	return clampf(lungs / lung_capacity(), 0.0, 1.0)


# ==========================================================================================================
# Vehicles
# ==========================================================================================================
func set_vehicle(vehicle: Node, seat: int) -> void:
	var was := is_in_vehicle()
	super.set_vehicle(vehicle, seat)
	if vehicle != null and is_instance_valid(vehicle):
		last_vehicle = vehicle
		_on_entered_vehicle(vehicle, seat)
	elif was:
		_on_left_vehicle()


func _on_entered_vehicle(vehicle: Node, _seat: int) -> void:
	if is_dead:
		return
	if is_swimming:
		_exit_swim()
	if traversal != null:
		traversal.cancel()
	if cover != null:
		cover.leave(true)
	move_mode = Move.VEHICLE
	velocity = Vector3.ZERO
	crouching = false
	sprinting = false
	aiming = false
	_cur_height = STAND_HEIGHT
	_apply_capsule(STAND_HEIGHT)
	_collider.set_deferred("disabled", true)
	_air_throttle = 0.0
	_steer_smooth = 0.0
	_seat_logged = false
	if weapons != null:
		weapons.set_trigger(false)
		weapons.set_aiming(false)
	_trigger_down = false
	_aiming_sent = false
	var vclass: StringName = vehicle.get("vclass") if vehicle.get("vclass") != null else GC.VC_CAR
	if rig != null:
		rig.set_stance(&"sit_bike" if (vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE) else &"sit_car")
		_last_stance = &"sit_car"
	if is_instance_valid(camera):
		camera.on_vehicle_entered(vehicle)
	if interaction != null:
		interaction.clear_prompt()


func _on_left_vehicle() -> void:
	if is_dead:
		return
	_collider.set_deferred("disabled", false)
	if move_mode == Move.VEHICLE:
		move_mode = Move.GROUND
	velocity = Vector3.ZERO
	_vehicle_enter_cd = 0.6
	_rig_airborne = false
	_air_time = 0.0
	if rig != null:
		rig.set_stance(&"stand")
		_last_stance = &"stand"
		rig.play_action(&"exit_vehicle")
	if weapons != null:
		weapons.set_trigger(false)
	if is_instance_valid(camera):
		camera.on_vehicle_exited()
	_reset_interp()


func _on_vehicle_exited_event(vehicle: Node, character: Node) -> void:
	if character == self and vehicle != null:
		last_vehicle = vehicle


func _seat_world_transform(vehicle: Node3D, seat: int) -> Transform3D:
	if vehicle.has_method("get_seat_transform"):
		var t = vehicle.get_seat_transform(seat)
		if t is Transform3D:
			return t
	var seats = vehicle.get("seats")
	if seats is Array and seat >= 0 and seat < seats.size() and seats[seat] is Dictionary:
		var sd: Dictionary = seats[seat]
		for key in ["seat", "pos", "local", "seat_pos"]:
			if sd.has(key) and sd[key] is Vector3:
				return vehicle.global_transform * Transform3D(Basis.IDENTITY, sd[key])
	var node := vehicle.find_child("SeatDriver" if seat <= 0 else "SeatPassenger", true, false)
	if node is Node3D:
		return (node as Node3D).global_transform
	return vehicle.global_transform


func _tick_vehicle(dt: float) -> void:
	var v: Node3D = current_vehicle as Node3D
	if v == null or not is_instance_valid(v):
		set_vehicle(null, -1)
		return
	# VehicleBase.enter() parents the character under the seat anchor; only vehicles that do not (fakes, tests) need us to follow
	if not v.is_ancestor_of(self):
		var xf := _seat_world_transform(v, seat_index)
		global_transform = Transform3D(Basis(Vector3.UP, v.global_rotation.y), xf.origin)
	velocity = Vector3.ZERO
	var allowed := _gameplay_input_allowed()
	# exit request is handled in PlayerInteraction.try_enter_exit (F key)
	if seat_index != 0 and seat_index != -1 and v.get("driver") != self:
		_tick_passenger(v, allowed)
		return
	_send_driving_input(v, dt, allowed)
	_tick_drive_by(v, allowed)


func _tick_passenger(v: Node3D, allowed: bool) -> void:
	_tick_drive_by(v, allowed)


func _send_driving_input(v: Node3D, dt: float, allowed: bool) -> void:
	if v.get("is_ai_controlled") == true:
		return
	var vclass: StringName = v.get("vclass") if v.get("vclass") != null else GC.VC_CAR
	var a := allowed and use_real_input
	if not a and use_real_input:
		v.input_throttle = 0.0
		v.input_brake = 0.0
		v.input_steer = 0.0
		v.input_handbrake = false
		v.input_horn = false
		return
	if not use_real_input:
		# cmd_* driven (tests / cutscene): forward = throttle, back = brake, x = steer
		v.input_throttle = maxf(cmd_move.y, 0.0)
		v.input_brake = maxf(-cmd_move.y, 0.0)
		v.input_steer = cmd_move.x
		v.input_handbrake = cmd_jump_held
		return
	if vclass == GC.VC_HELI or vclass == GC.VC_PLANE:
		_send_aircraft_input(v, vclass, dt)
	else:
		var thr := Input.get_action_strength(&"move_forward")
		var brk := Input.get_action_strength(&"move_back")
		var steer_t := Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
		# raw digital steering: the vehicle applies its own speed-sensitive smoothing
		_steer_smooth = steer_t
		v.input_throttle = thr
		v.input_brake = brk
		v.input_steer = steer_t
		v.input_handbrake = Input.is_action_pressed(&"handbrake")
		if vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE:
			# Shift = wheelie, C / Ctrl = stoppie (BikeVehicle reads input_pitch > 0.4 / < -0.4)
			v.input_pitch = (1.0 if Input.is_action_pressed(&"sprint") else 0.0) - (1.0 if Input.is_action_pressed(&"crouch") else 0.0)
	v.input_horn = Input.is_action_pressed(&"horn")
	if Input.is_action_just_pressed(&"headlights"):
		v.toggle_headlights()
	if Input.is_action_just_pressed(&"siren"):
		v.toggle_siren()


func _send_aircraft_input(v: Node3D, vclass: StringName, dt: float) -> void:
	v.input_pitch = Input.get_action_strength(&"air_pitch_up") - Input.get_action_strength(&"air_pitch_down")
	v.input_roll = Input.get_action_strength(&"air_roll_right") - Input.get_action_strength(&"air_roll_left")
	v.input_yaw = Input.get_action_strength(&"air_yaw_right") - Input.get_action_strength(&"air_yaw_left")
	var up := Input.get_action_strength(&"air_throttle_up")
	var down := Input.get_action_strength(&"air_throttle_down")
	if vclass == GC.VC_HELI:
		v.input_collective = up - down
		v.input_throttle = 1.0
		v.input_brake = 0.0
	else:
		_air_throttle = clampf(_air_throttle + (up - down) * 0.55 * dt, 0.0, 1.0)
		v.input_throttle = _air_throttle
		v.input_brake = down if _air_throttle <= 0.01 else 0.0
		v.input_handbrake = false
	v.input_steer = v.input_yaw     # ground steering on the runway


## Drive-by: only when the seat allows shooting and the held weapon is vehicle-safe.
func _tick_drive_by(v: Node3D, allowed: bool) -> void:
	if weapons == null:
		return
	var can_shoot := false
	if v.has_method("can_shoot_from_seat"):
		can_shoot = v.can_shoot_from_seat(seat_index)
	else:
		var seats = v.get("seats")
		if seats is Array and seat_index >= 0 and seat_index < seats.size() and seats[seat_index] is Dictionary:
			can_shoot = bool(seats[seat_index].get("can_shoot", false))
	var want_aim: bool = allowed and use_real_input and Input.is_action_pressed(&"aim") and can_shoot and weapons.can_fire_from_vehicle()
	if not use_real_input:
		want_aim = cmd_aim and can_shoot and weapons.can_fire_from_vehicle()
	aiming = want_aim
	if want_aim != _aiming_sent:
		_aiming_sent = want_aim
		weapons.set_aiming(want_aim)
	var want_fire: bool = want_aim and (cmd_fire or (use_real_input and allowed and Input.is_action_pressed(&"fire")))
	if want_fire != _trigger_down:
		_trigger_down = want_fire
		weapons.set_trigger(want_fire)
	if rig != null:
		var yaw_off := 0.0
		if is_instance_valid(camera):
			yaw_off = clampf(wrapf(camera.yaw - global_rotation.y, -PI, PI), -1.9, 1.9)
		rig.set_aim(want_aim, camera.pitch if is_instance_valid(camera) else 0.0, yaw_off)


# ==========================================================================================================
# Weapons wiring / actions
# ==========================================================================================================
func _update_weapon_input(_dt: float) -> void:
	if weapons == null:
		return
	# feed the camera ray (origin pushed forward to the plane of the player so walls behind us don't block the aim)
	if is_instance_valid(camera):
		var o: Vector3 = camera.global_position
		var d: Vector3 = camera.get_aim_forward()
		if aim_jitter_deg > 0.01:
			d = _jitter_dir(d, aim_jitter_deg)
		var chest := global_position + Vector3(0, 1.3, 0)
		var along := maxf((chest - o).dot(d), 0.0)
		weapons.set_aim_ray(o + d * along, d)
	if is_in_vehicle():
		return
	var can_use := move_mode == Move.GROUND or move_mode == Move.AIR or move_mode == Move.COVER or move_mode == Move.SWIM
	if is_swimming:
		can_use = false
	var aim_now := aiming and can_use
	if aim_now != _aiming_sent:
		_aiming_sent = aim_now
		weapons.set_aiming(aim_now)
	var fire_now := cmd_fire and can_use and not is_dead
	if fire_now != _trigger_down:
		_trigger_down = fire_now
		weapons.set_trigger(fire_now)
	if weapons.get("scope_active") == true and weapons.has_method("hold_breath"):
		weapons.hold_breath(use_real_input and Input.is_action_pressed(&"sprint"))


## `d` rotated by a random angle of up to `deg` degrees (blind fire, shooting while rolling).
func _jitter_dir(d: Vector3, deg: float) -> Vector3:
	var b := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT)
	var a := randf() * TAU
	var r := sqrt(randf()) * deg_to_rad(deg)
	return (b * Vector3(sin(r) * cos(a), sin(r) * sin(a), -cos(r))).normalized()


func melee(heavy := false) -> void:
	if is_dead or is_in_vehicle() or is_swimming or move_mode == Move.BUSTED:
		return
	if cover != null and move_mode == Move.COVER:
		cover.leave(false)
	if stealth_takedown(heavy):
		return
	if stealth != null:
		stealth.on_melee_swing()
	if weapons != null:
		weapons.melee_attack(heavy)
	_skill_use(&"strength", 0.4)


func throw_grenade() -> void:
	if weapons != null and not is_in_vehicle() and not is_dead and not is_swimming:
		weapons.throw_grenade()


## Holsters the current weapon (swimming, parachute, ladders); unstow_weapon() re-draws it unless the player picked another one.
func stow_weapon() -> void:
	if weapons == null or _stowed_weapon != &"":
		return
	_stowed_weapon = weapons.current_id
	weapons.set_trigger(false)
	weapons.set_aiming(false)
	if _stowed_weapon != &"fists":
		weapons.holster()


func unstow_weapon() -> void:
	if weapons != null and _stowed_weapon != &"" and _stowed_weapon != &"fists" and weapons.current_id == &"fists" and weapons.has_weapon(_stowed_weapon):
		weapons.equip(_stowed_weapon)
	_stowed_weapon = &""


func toggle_flashlight() -> void:
	if weapons != null and weapons.has_method("toggle_flashlight"):
		var before = weapons.get("flashlight_on")
		weapons.toggle_flashlight()
		if weapons.get("flashlight_on") != before:
			return        # the weapon has a flashlight attachment: it handled the toggle
	_flash_on = not _flash_on
	if is_instance_valid(camera):
		camera.set_flashlight(_flash_on)


func _on_weapon_changed(character: Node, weapon_id: StringName) -> void:
	if character != self or rig == null:
		return
	var kind: StringName = WEAPON_POSE.get(weapon_id, &"pistol" if weapon_id != &"" else &"none")
	if kind != _last_weapon_pose:
		_last_weapon_pose = kind
		rig.set_weapon_pose(kind)
	if is_instance_valid(camera):
		camera.refresh_first_person_visuals()


## Silent takedown of an unaware NPC from behind (PlayerStealth). `heavy` flips kill <-> knock-out. Returns true when it started.
func stealth_takedown(heavy := false) -> bool:
	return stealth != null and stealth.try_takedown(heavy)


## Scripted-motion helpers for the takedown (the stealth component steers the body itself while in_takedown).
func begin_takedown_motion() -> void:
	crouching = false
	sprinting = false
	aiming = false
	velocity = Vector3.ZERO


func end_takedown_motion() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## Per-viewer visibility (0..1) for AI perception: distance falloff, cover between, light, posture. Falls back to visibility01.
func get_visibility_from(viewer_pos: Vector3) -> float:
	return stealth.get_visibility_from(viewer_pos) if stealth != null else visibility01


func get_detection_range() -> float:
	return detection_range


func is_exposed() -> bool:
	return stealth_exposed


# ==========================================================================================================
# Traversal helpers
# ==========================================================================================================
func _try_traversal_instead_of_jump() -> bool:
	if traversal == null or crouching:
		return false
	return traversal.try_vault_or_mantle()


## Begin a short scripted movement (used by PlayerTraversal). Collisions are suspended during it.
func begin_scripted_motion(kind: StringName) -> void:
	_collider.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	traversal_started.emit(kind)


func end_scripted_motion(exit_velocity: Vector3 = Vector3.ZERO) -> void:
	_collider.set_deferred("disabled", false)
	velocity = exit_velocity
	move_mode = Move.GROUND
	_was_on_floor = false
	_fall_peak_y = global_position.y
	_reset_interp()


# ==========================================================================================================
# Ragdoll hook (non-lethal) / death / arrest / respawn
# ==========================================================================================================
## Briefly ragdoll the (living) player, e.g. after a hard fall or a vehicle impact. The body follows the ragdoll and gets up
## after `seconds`. No-op without a rig.
func ragdoll_for(seconds: float, impulse: Vector3 = Vector3.ZERO) -> void:
	if is_dead or move_mode == Move.VEHICLE or move_mode == Move.BUSTED or rig == null:
		return
	if is_swimming:
		return
	if traversal != null:
		traversal.cancel()
	if cover != null:
		cover.leave(true)
	move_mode = Move.RAGDOLL
	_ragdoll_time = seconds
	velocity = Vector3.ZERO
	crouching = false
	sprinting = false
	aiming = false
	_collider.set_deferred("disabled", true)
	rig.start_ragdoll(impulse.limit_length(12.0), global_position + Vector3.UP)
	_last_stance = &"ragdoll"
	if weapons != null:
		weapons.set_trigger(false)
		weapons.set_aiming(false)


func _tick_ragdoll(dt: float) -> void:
	_ragdoll_time -= dt
	velocity = Vector3.ZERO
	# the body follows the simulated ragdoll (camera + interaction stay with the visible body)
	if rig != null and rig.has_method("get_ragdoll_position"):
		var rp: Vector3 = rig.get_ragdoll_position()
		var hit := Util.raycast(self, rp + Vector3.UP * 0.6, rp + Vector3.DOWN * 3.0, GC.M_GROUND, [self])
		var gy := rp.y - 0.35
		if not hit.is_empty():
			gy = (hit["position"] as Vector3).y
		global_position = Vector3(rp.x, gy + 0.02, rp.z)
	if _ragdoll_time <= 0.0:
		_collider.set_deferred("disabled", false)
		if rig != null:
			rig.stop_ragdoll()
		move_mode = Move.GROUND
		_last_stance = &""
		_land_slow = 0.5
		_was_on_floor = false
		_fall_peak_y = global_position.y
		_reset_interp()


func _on_death(info: Dictionary) -> void:
	if is_in_vehicle():
		var v = current_vehicle
		if v != null and v.has_method("exit"):
			v.exit(self, true)
		set_vehicle(null, -1)
	if traversal != null:
		traversal.cancel()
	if cover != null:
		cover.leave(true)
	if is_swimming:
		_exit_swim()
	move_mode = Move.DEAD
	_death_time = 0.0
	_fade_sent = false
	sprinting = false
	aiming = false
	crouching = false
	_collider.set_deferred("disabled", true)
	if weapons != null:
		weapons.set_trigger(false)
		weapons.set_aiming(false)
	_trigger_down = false
	_aiming_sent = false
	var dir: Vector3 = info.get("direction", -global_transform.basis.z)
	var imp := float(info.get("impulse", 5.0))
	if rig != null:
		rig.start_ragdoll(dir.normalized() * clampf(imp * 0.6, 2.0, 12.0), info.get("position", global_position + Vector3.UP))
		_last_stance = &"dead"
	Sfx.play_3d(&"death_m", global_position + Vector3.UP, 0.0, 1.0, 40.0)
	if interaction != null:
		interaction.clear_prompt()
	Events.player_died.emit()


func _tick_dead(dt: float) -> void:
	_death_time += dt / maxf(Engine.time_scale, 0.05)       # real time, independent of the death slow-motion
	velocity.x = move_toward(velocity.x, 0.0, 12.0 * dt)
	velocity.z = move_toward(velocity.z, 0.0, 12.0 * dt)
	if _death_time > DEATH_FADE_DELAY and not _fade_sent:
		_fade_sent = true
		fade_requested.emit(true, DEATH_RESPAWN_DELAY - DEATH_FADE_DELAY)
	if _death_time >= DEATH_RESPAWN_DELAY:
		var pen := mini(RESPAWN_CASH_PENALTY, Game.cash)
		respawn_at(&"hospital", {"penalty": pen, "reason": &"death"})


## Called by the police system when the player is caught. Hands up, UI event, then a respawn at the police station.
func arrest(_by: Node = null) -> void:
	if is_dead or move_mode == Move.BUSTED:
		return
	if is_in_vehicle():
		if current_vehicle.has_method("exit"):
			current_vehicle.exit(self, true)
		set_vehicle(null, -1)
	if traversal != null:
		traversal.cancel()
	if cover != null:
		cover.leave(true)
	if is_swimming:
		_exit_swim()
	move_mode = Move.BUSTED
	_busted_time = 0.0
	_fade_sent = false
	_busted_reason = &"arrest"
	aiming = false
	sprinting = false
	velocity = Vector3.ZERO
	if weapons != null:
		weapons.set_trigger(false)
		weapons.set_aiming(false)
		weapons.holster()
	if rig != null:
		rig.set_stance(&"stand")
		rig.play_action(&"hands_up")
	Events.player_busted.emit()


func _tick_busted(dt: float) -> void:
	_busted_time += dt / maxf(Engine.time_scale, 0.05)
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = maxf(velocity.y - GRAVITY * dt, -TERMINAL_VELOCITY)
	move_and_slide()
	if not _hands_up_sent and rig != null:
		_hands_up_sent = true
	if _busted_time > BUSTED_RESPAWN_DELAY - 0.6 and not _fade_sent:
		_fade_sent = true
		fade_requested.emit(true, 0.5)
	if _busted_time >= BUSTED_RESPAWN_DELAY:
		_hands_up_sent = false
		var fine := mini(maxi(int(Game.cash * 0.1), 100), 1000)
		fine = mini(fine, Game.cash)
		respawn_at(&"police_station", {"penalty": fine, "reason": &"busted", "confiscate_ammo": 0.5})


## Teleport to a named WorldLayout location (falls back to player_spawn / origin) and bring the player back to life.
## opts: penalty:int (cash), reason:StringName, confiscate_ammo:float (fraction of reserve ammo lost), silent:bool,
## keep_health:bool.
func respawn_at(location_id: StringName, opts: Dictionary = {}) -> void:
	respawn_started.emit(location_id, opts.get("reason", &"manual"))
	var loc: Dictionary = WorldLayout.get_location(location_id)
	if loc.is_empty():
		loc = WorldLayout.get_location(&"player_spawn")
	var pos: Vector3 = loc.get("pos", Vector3(0, 2, 0))
	var yaw: float = loc.get("yaw", 0.0)
	var penalty: int = int(opts.get("penalty", 0))
	if penalty > 0:
		Game.cash = maxi(Game.cash - penalty, 0)
	var frac: float = float(opts.get("confiscate_ammo", 0.0))
	if frac > 0.0 and weapons != null:
		_confiscate_ammo(frac)
	var was_dead := is_dead
	if is_in_vehicle():
		if current_vehicle.has_method("exit"):
			current_vehicle.exit(self, true)
		set_vehicle(null, -1)
	if not bool(opts.get("keep_health", false)) or was_dead:
		revive()
		armor = 0.0 if was_dead or opts.get("reason", &"") == &"busted" else armor
	_clear_wanted()
	_reset_state_after_teleport()
	teleport_to(pos + Vector3(0, 0.15, 0), yaw)
	spawn_protection = SPAWN_PROTECTION
	if is_instance_valid(camera):
		camera.snap_behind(yaw)
	fade_requested.emit(false, 0.9)
	if not bool(opts.get("silent", false)):
		var reason: StringName = opts.get("reason", &"manual")
		if reason == &"death":
			Game.notify("You were treated at the hospital%s" % ((" (-" + Util.format_money(penalty) + ")") if penalty > 0 else ""), &"warn")
		elif reason == &"busted":
			Game.notify("Busted. Released from custody%s" % ((" (fined " + Util.format_money(penalty) + ")") if penalty > 0 else ""), &"warn")
	Events.player_respawned.emit(global_position)
	respawned.emit(global_position)


func _confiscate_ammo(fraction: float) -> void:
	var inv = weapons.get("inventory")
	if not (inv is Dictionary):
		return
	for id in inv.keys():
		var entry = inv[id]
		if entry is Dictionary and entry.has("reserve"):
			entry["reserve"] = int(entry["reserve"] * (1.0 - fraction))
			inv[id] = entry
			Events.ammo_changed.emit(self, id, int(entry.get("mag", 0)), int(entry["reserve"]))


func _clear_wanted() -> void:
	var w = Game.sys(&"wanted")
	if w != null and w.has_method("clear"):
		w.clear()


func _reset_state_after_teleport() -> void:
	move_mode = Move.GROUND
	crouching = false
	sprinting = false
	aiming = false
	is_swimming = false
	head_underwater = false
	_cur_height = STAND_HEIGHT
	_apply_capsule(STAND_HEIGHT)
	_collider.set_deferred("disabled", false)
	stamina = MAX_STAMINA
	_exhausted = false
	lungs = lung_capacity()
	_land_slow = 0.0
	_last_stance = &""
	_hands_up_sent = false
	if rig != null:
		rig.stop_ragdoll()
		rig.set_stance(&"stand")


func _on_revive() -> void:
	_collider.set_deferred("disabled", false)
	_death_time = 0.0
	_fade_sent = false
	_damage_free_time = 0.0
	if rig != null:
		rig.stop_ragdoll()
		rig.set_stance(&"stand")


func teleport_to(pos: Vector3, yaw: float = NAN) -> void:
	super.teleport_to(pos, yaw)
	if move_mode == Move.SWIM:
		_exit_swim()
	_fall_peak_y = pos.y
	_was_on_floor = false
	_reset_interp()
	if visual != null:
		visual.global_transform = global_transform
	_begin_ground_wait()
	if is_instance_valid(camera):
		camera.on_player_teleported()


# ---- Ground gating: never free-fall through a world that is still being built -----------------------------------
func _begin_ground_wait() -> void:
	if not is_inside_tree():
		return
	if _has_ground_below():
		_frozen_for_ground = false
	else:
		_frozen_for_ground = true
		_ground_wait_time = 0.0


func _has_ground_below() -> bool:
	if WorldLayout.is_water(global_position.x, global_position.z):
		return true
	if _water_sensor != null and not _water_sensor.get_overlapping_areas().is_empty():
		return true
	var from := global_position + Vector3(0, 1.0, 0)
	var hit := Util.raycast(self, from, from + Vector3.DOWN * 600.0, GC.M_GROUND | GC.L_VEHICLE, [self])
	return not hit.is_empty()


func _tick_wait_ground(dt: float) -> void:
	_ground_wait_time += dt
	velocity = Vector3.ZERO
	if _has_ground_below():
		_frozen_for_ground = false
		return
	if absf(_ground_wait_time - 5.0) < dt * 0.5 or absf(_ground_wait_time - 20.0) < dt * 0.5:
		push_warning("[Player] waiting for ground under %s (world not built?) for %.0fs" % [str(global_position), _ground_wait_time])


# ==========================================================================================================
# Post tick: weapons feed, rig update, interaction, interpolation
# ==========================================================================================================
func _post_tick(dt: float) -> void:
	if stealth != null:
		stealth.tick(dt)
	_update_weapon_input(dt)
	_update_rig(dt)
	if not is_instance_valid(camera):
		is_underwater = head_underwater
	if interaction != null:
		interaction.update(dt)
	_record_interp()


func _update_rig(dt: float) -> void:
	if rig == null:
		return
	var new_stance := _compute_stance()
	if new_stance != _last_stance:
		_last_stance = new_stance
		rig.set_stance(new_stance)
		stance_changed.emit(new_stance)
	stance = new_stance
	# locomotion (swimming / ladders use the full 3D direction: y = vertical)
	var spd := 0.0
	var local_dir := Vector3.ZERO
	if move_mode == Move.SWIM:
		spd = velocity.length()
		if spd > 0.05:
			local_dir = global_transform.basis.inverse() * (velocity / spd)
	elif move_mode == Move.LADDER:
		spd = absf(cmd_move.y) * 1.7
		local_dir = Vector3(0, signf(cmd_move.y), 0) if spd > 0.05 else Vector3.ZERO
	elif move_mode != Move.VEHICLE and move_mode != Move.DEAD and move_mode != Move.RAGDOLL:
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		spd = flat.length()
		if spd > 0.05:
			local_dir = global_transform.basis.inverse() * (flat / spd)
	rig.set_locomotion(spd, local_dir, sprinting)
	# airborne pose (jump / fall) and landing dip
	if move_mode == Move.GROUND or move_mode == Move.AIR:
		if is_on_floor():
			_air_time = 0.0
			if _rig_airborne:
				_rig_airborne = false
				rig.set_grounded(true, _impact_vy)
		else:
			_air_time += dt
			if not _rig_airborne and _air_time > 0.16 and velocity.y < -2.0:
				_rig_airborne = true
				rig.set_grounded(false, velocity.y)
	elif move_mode == Move.SWIM or move_mode == Move.VEHICLE or move_mode == Move.LADDER or move_mode == Move.COVER or move_mode == Move.PARACHUTE:
		if _rig_airborne:
			_rig_airborne = false
			rig.set_grounded(true, 0.0)
	# aim / look
	if is_instance_valid(camera) and move_mode != Move.DEAD and move_mode != Move.RAGDOLL:
		var yaw_off := clampf(wrapf(camera.yaw - global_rotation.y, -PI, PI), -1.9, 1.9)
		var aim_pose := aiming or (cmd_fire and _weapon_is_ranged() and move_mode != Move.VEHICLE)
		rig.set_aim(aim_pose, camera.pitch, yaw_off)
		rig.look_at_point(camera.global_position + camera.get_aim_forward() * 30.0)
	# vehicle extras
	if move_mode == Move.VEHICLE and is_instance_valid(current_vehicle):
		var steer = current_vehicle.get("input_steer")
		if steer != null:
			rig.set_steering(float(steer))
		var vc = current_vehicle.get("vclass")
		if vc == GC.VC_BIKE or vc == GC.VC_BICYCLE:
			rig.set_ride_style(&"bicycle" if vc == GC.VC_BICYCLE else &"motorcycle")
	elif move_mode == Move.COVER and cover != null:
		rig.set_cover_peek(cover.peek)
	# swimming: the rig expects its origin near the water surface (see SWIM_RIG_OFFSET)
	var off_y := SWIM_RIG_OFFSET * smoothstep(0.15, 1.6, spd) if (move_mode == Move.SWIM) else 0.0
	rig.position.y = Util.damp(rig.position.y, off_y, 12.0, dt)


func _compute_stance() -> StringName:
	match move_mode:
		Move.DEAD:
			return &"dead"
		Move.RAGDOLL:
			return &"ragdoll"
		Move.VEHICLE:
			var vclass = current_vehicle.get("vclass") if is_instance_valid(current_vehicle) else null
			return &"sit_bike" if (vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE) else &"sit_car"
		Move.SWIM:
			return &"swim_under" if head_underwater else &"swim_surface"
		Move.LADDER:
			return &"ladder"
		Move.PARACHUTE:
			return &"parachute"
		Move.COVER:
			return cover.get_stance() if cover != null else &"cover_high"
	if crouching:
		return &"crouch"
	return &"stand"


# ---- Smooth visuals -----------------------------------------------------------------------------------------------
func _reset_interp() -> void:
	_prev_pos = global_position
	_curr_pos = global_position
	_prev_rot = global_transform.basis.orthonormalized().get_rotation_quaternion()
	_curr_rot = _prev_rot


func _record_interp() -> void:
	_prev_pos = _curr_pos
	_prev_rot = _curr_rot
	_curr_pos = global_position
	_curr_rot = global_transform.basis.orthonormalized().get_rotation_quaternion()


func _process(_dt: float) -> void:
	if visual == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var p := _prev_pos.lerp(_curr_pos, f)
	if (_curr_pos - _prev_pos).length_squared() > 25.0:
		p = _curr_pos
	var q := _prev_rot.slerp(_curr_rot, f)
	visual.global_transform = Transform3D(Basis(q), p)


func get_visual_position() -> Vector3:
	var f := Engine.get_physics_interpolation_fraction()
	if (_curr_pos - _prev_pos).length_squared() > 25.0:
		return _curr_pos
	return _prev_pos.lerp(_curr_pos, f)


# ==========================================================================================================
# CharacterBase overrides / queries
# ==========================================================================================================
func get_eye_position() -> Vector3:
	var eye := EYE_CROUCH if crouching else EYE_STAND
	if is_swimming:
		eye = SWIM_HEAD_OFFSET
	return global_position + Vector3(0.0, eye, 0.0)


func get_aim_direction() -> Vector3:
	if is_instance_valid(camera):
		return camera.get_aim_forward()
	return -global_transform.basis.z


func get_hand_position() -> Vector3:
	if rig != null:
		var s = rig.get_hand_socket(true)
		if s is Node3D:
			return (s as Node3D).global_position
	return global_position + Vector3(0.3, 1.1, -0.3)


func is_busy_for_interaction() -> bool:
	return move_mode in [Move.DEAD, Move.BUSTED, Move.TRAVERSE, Move.RAGDOLL, Move.LADDER]


## True for stances where the player is fully controllable on foot (used by other systems).
func is_on_foot() -> bool:
	return not is_in_vehicle() and move_mode != Move.DEAD and move_mode != Move.BUSTED


func get_noise_radius() -> float:
	return noise_radius


# ==========================================================================================================
# Skills (optional system, duck typed)
# ==========================================================================================================
func _skill01(id: StringName) -> float:
	var s = Game.sys(&"skills")
	if s == null:
		return 0.0
	for m in ["get_skill01", "get_level01", "get_skill_ratio"]:
		if s.has_method(m):
			return clampf(float(s.call(m, id)), 0.0, 1.0)
	if s.has_method("get_skill"):
		var v = s.get_skill(id)
		if v is float or v is int:
			return clampf(float(v), 0.0, 1.0) if float(v) <= 1.0 else clampf(float(v) / 100.0, 0.0, 1.0)
	return 0.0


func _skill_use(id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	var s = Game.sys(&"skills")
	if s == null:
		return
	for m in ["train", "add_xp", "record_use", "add_progress", "use_skill"]:
		if s.has_method(m):
			s.call(m, id, amount)
			return


# ==========================================================================================================
# Persistence
# ==========================================================================================================
func serialize() -> Dictionary:
	var d := {
		"pos": [global_position.x, global_position.y, global_position.z], "yaw": rotation.y,
		"health": health, "armor": armor, "stamina": stamina, "has_parachute": has_parachute, "has_scuba": has_scuba,
	}
	if weapons != null:
		d["weapons"] = weapons.serialize()
	return d


func deserialize(data: Dictionary) -> void:
	var p: Array = data.get("pos", [])
	if p.size() == 3:
		teleport_to(Vector3(p[0], p[1], p[2]), float(data.get("yaw", 0.0)))
	health = clampf(float(data.get("health", max_health)), 1.0, max_health)
	armor = clampf(float(data.get("armor", 0.0)), 0.0, max_armor)
	stamina = float(data.get("stamina", MAX_STAMINA))
	has_parachute = bool(data.get("has_parachute", false))
	has_scuba = bool(data.get("has_scuba", false))
	if weapons != null and data.has("weapons"):
		weapons.deserialize(data["weapons"])
