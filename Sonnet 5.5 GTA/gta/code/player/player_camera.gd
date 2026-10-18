class_name PlayerCamera
extends Camera3D
## The gameplay camera. One Camera3D that is NOT a child of the body (owned by PlayerSystem).
## Modes (chosen automatically from the player's state): FOLLOW (third person orbit / over-the-shoulder aim / first person),
## VEHICLE and AIRCRAFT chase cameras, DEATH orbit camera.
##
## Public API: yaw/pitch, get_aim_forward(), first_person_active(), toggle_first_person(), swap_shoulder(),
## add_shake(strength, duration), add_recoil(pitch_up_rad, yaw_rad), set_fov_override()/clear_fov_override(),
## set_flashlight(on), snap_behind(yaw).

enum Mode { FOLLOW, VEHICLE, AIRCRAFT, DEATH }

const MOUSE_BASE_SENS := 0.0022
const PITCH_MIN := -1.25
const PITCH_MAX := 1.15
const PROBE_RADIUS := 0.22

# third person distances / heights
const DIST_DEFAULT := 3.45
const DIST_SPRINT := 3.8
const DIST_CROUCH := 3.0
const DIST_AIM := 1.65
const DIST_SWIM := 4.0
const PIVOT_STAND := 1.55
const PIVOT_CROUCH := 1.1
const PIVOT_AIM := 1.62
const SHOULDER_DEFAULT := 0.38
const SHOULDER_AIM := 0.62
const AIM_FOV_MULT := 0.8
const SPRINT_FOV_KICK := 7.0

var player = null                      # Player
var mode: Mode = Mode.FOLLOW
var yaw := 0.0
var pitch := -0.12
var first_person := false              # user toggle (V)
var shoulder_side := 1.0               # +1 right shoulder, -1 left
var fov_override := -1.0               # >0: scripted FOV (scopes / cinematics)
var look_back_active := false

var _dist := DIST_DEFAULT
var _pivot_h := PIVOT_STAND
var _shoulder := SHOULDER_DEFAULT
var _fov_cur := 75.0
var _pivot_y := 0.0
var _coll_frac := 1.0
var _coll_clear_time := 0.0
var _arm_hidden := false
var _fp_applied := false
var _aim_basis := Basis.IDENTITY
var _aim_origin := Vector3.ZERO
var _force_snap := true

# transition blend between modes
var _trans_from := Transform3D.IDENTITY
var _trans_t := 1.0

# vehicle camera
var _veh: Node3D = null
var _veh_prev := Vector3.ZERO
var _veh_curr := Vector3.ZERO
var _veh_prev_yaw := 0.0
var _veh_curr_yaw := 0.0
var _chase_yaw := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _look_idle := 0.0
var _veh_focus_dist := 0.0

# death camera
var _death_t := 0.0
var _death_pivot := Vector3.ZERO

# shake & recoil
var _shakes: Array = []                # [{amp, t, dur}]
var _kick_pitch := 0.0
var _kick_yaw := 0.0
var _bob_t := 0.0

var _query: PhysicsShapeQueryParameters3D
var _probe: SphereShape3D
var _flash: SpotLight3D = null
var _mouse_released_by_user := false
var _automation_run := false          # --shot / --exec runs never grab the user's mouse


func _ready() -> void:
	name = "PlayerCamera"
	# The camera is positioned in _process from targets that are already interpolated by hand (Player.get_visual_position(),
	# the vehicle prev/curr pair + Engine.get_physics_interpolation_fraction()), so the engine's own physics interpolation
	# must stay OFF: otherwise it warns ('Interpolated Camera3D triggered from outside physics process') and could smooth twice.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.07
	far = 1500.0
	_fov_cur = _base_fov()
	fov = _fov_cur
	_probe = SphereShape3D.new()
	_probe.radius = PROBE_RADIUS
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _probe
	_query.collision_mask = GC.M_CAMERA
	_query.collide_with_areas = false
	process_priority = 100
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--shot") or String(a).begins_with("--exec"):
			_automation_run = true
	Events.explosion.connect(_on_explosion)
	Events.vehicle_collision.connect(_on_vehicle_collision)
	Events.gunshot.connect(_on_gunshot)


func setup(p) -> void:
	player = p
	yaw = p.rotation.y
	_snap_now()


# ==========================================================================================================
# Input
# ==========================================================================================================
func _input(event: InputEvent) -> void:
	if player == null:
		return
	if event is InputEventMouseMotion:
		if (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless") or not _input_allowed():
			return
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		var sens := MOUSE_BASE_SENS * float(Game.settings.get("mouse_sensitivity", 1.0))
		sens *= clampf(fov / maxf(_base_fov(), 1.0), 0.35, 1.0)     # slower when zoomed
		var inv := -1.0 if bool(Game.settings.get("invert_y", false)) else 1.0
		_apply_look(-rel.x * sens, -rel.y * sens * inv)
		return
	# manual mouse release when no UI exists to manage the cursor (dev runs)
	if not _ui_manages_mouse():
		if event.is_action_pressed(&"pause"):
			_mouse_released_by_user = true
		elif event is InputEventMouseButton and event.pressed and _mouse_released_by_user:
			_mouse_released_by_user = false


func _apply_look(d_yaw: float, d_pitch: float) -> void:
	match mode:
		Mode.FOLLOW:
			yaw += d_yaw
			pitch = clampf(pitch + d_pitch, PITCH_MIN, PITCH_MAX)
			yaw = wrapf(yaw, -PI, PI)
		Mode.VEHICLE, Mode.AIRCRAFT:
			_look_yaw = clampf(_look_yaw + d_yaw, -PI, PI)
			_look_pitch = clampf(_look_pitch + d_pitch, -0.9, 0.9)
			_look_idle = 0.0
		_:
			pass


func _input_allowed() -> bool:
	if Game.paused or (player != null and player.input_locked):
		return false
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("is_menu_open") and ui.is_menu_open():
		return false
	return true


func _ui_manages_mouse() -> bool:
	var ui = Game.ui
	return ui != null and is_instance_valid(ui) and ui.has_method("is_menu_open")


func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless" or _automation_run:
		return
	var want := _input_allowed() and not _mouse_released_by_user
	var mm := Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mm:
		Input.mouse_mode = mm


# ==========================================================================================================
# Public API
# ==========================================================================================================
func first_person_active() -> bool:
	return first_person and mode == Mode.FOLLOW


func toggle_first_person() -> void:
	first_person = not first_person
	_trans_from = global_transform
	_trans_t = 0.55 if mode == Mode.FOLLOW else 0.0


func swap_shoulder() -> void:
	shoulder_side = -shoulder_side


func get_aim_forward() -> Vector3:
	return -_aim_basis.z


func get_aim_origin() -> Vector3:
	return _aim_origin


func get_yaw() -> float:
	return yaw


## Trauma style shake. strength 0..1, duration seconds. Respects Game.settings.camera_shake.
func add_shake(strength: float, duration: float) -> void:
	if not bool(Game.settings.get("camera_shake", true)) or strength <= 0.001:
		return
	_shakes.append({"amp": clampf(strength, 0.0, 1.0), "t": duration, "dur": maxf(duration, 0.05)})
	if _shakes.size() > 12:
		_shakes.pop_front()


## Camera kick for gunfire: pitch up and yaw (radians). Returns smoothly to the aim line.
func add_recoil(pitch_up: float, yaw_kick: float = 0.0) -> void:
	_kick_pitch = clampf(_kick_pitch + pitch_up, -0.3, 0.35)
	_kick_yaw = clampf(_kick_yaw + yaw_kick, -0.2, 0.2)


func set_fov_override(deg: float) -> void:
	fov_override = deg


func clear_fov_override() -> void:
	fov_override = -1.0


func set_flashlight(on: bool) -> void:
	if on and _flash == null:
		_flash = SpotLight3D.new()
		_flash.name = "Flashlight"
		_flash.spot_range = 32.0
		_flash.spot_angle = 34.0
		_flash.spot_angle_attenuation = 0.8
		_flash.light_energy = 3.2
		_flash.light_color = Color(1.0, 0.95, 0.82)
		_flash.shadow_enabled = false
		add_child(_flash)
	if _flash != null:
		_flash.visible = on


func snap_behind(body_yaw: float) -> void:
	yaw = body_yaw
	pitch = -0.12
	_kick_pitch = 0.0
	_kick_yaw = 0.0
	_snap_now()


func on_player_teleported() -> void:
	_snap_now()


func on_vehicle_entered(v: Node) -> void:
	_veh = v as Node3D
	if _veh == null:
		return
	_veh_curr = _veh.global_position
	_veh_prev = _veh_curr
	_veh_curr_yaw = Util.dir_to_yaw(Util.flat(-_veh.global_transform.basis.z))
	_veh_prev_yaw = _veh_curr_yaw
	_chase_yaw = yaw         # start from where the orbit camera was, the chase then swings behind the vehicle
	_look_yaw = 0.0
	_look_pitch = 0.0
	_trans_from = global_transform
	_trans_t = 0.0


func on_vehicle_exited() -> void:
	if _veh != null and is_instance_valid(_veh):
		yaw = _chase_yaw + _look_yaw
	pitch = -0.15
	_veh = null
	_look_yaw = 0.0
	_look_pitch = 0.0
	_trans_from = global_transform
	_trans_t = 0.0


## Re-apply the first-person head hiding (call after the rig was re-dressed).
func refresh_first_person_visuals() -> void:
	if _fp_applied and player != null and player.rig != null:
		player.rig.set_first_person(true)


func _snap_now() -> void:
	_force_snap = true
	_trans_t = 1.0
	_coll_frac = 1.0


# ==========================================================================================================
# Frame update
# ==========================================================================================================
func _physics_process(_dt: float) -> void:
	if _veh != null and is_instance_valid(_veh):
		_veh_prev = _veh_curr
		_veh_prev_yaw = _veh_curr_yaw
		_veh_curr = _veh.global_position
		_veh_curr_yaw = Util.dir_to_yaw(Util.flat(-_veh.global_transform.basis.z))
		if (_veh_curr - _veh_prev).length_squared() > 2500.0:
			_veh_prev = _veh_curr


func _process(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	dt = minf(dt, 0.1)
	_update_mouse_mode()
	var new_mode := _desired_mode()
	if new_mode != mode:
		_on_mode_changed(mode, new_mode)
		mode = new_mode
	var target := global_transform
	var target_fov := _base_fov()
	match mode:
		Mode.FOLLOW:
			var r := _update_follow(dt)
			target = r[0]
			target_fov = r[1]
		Mode.VEHICLE, Mode.AIRCRAFT:
			var r2 := _update_vehicle(dt)
			target = r2[0]
			target_fov = r2[1]
		Mode.DEATH:
			var r3 := _update_death(dt)
			target = r3[0]
			target_fov = r3[1]
	if fov_override > 0.0:
		target_fov = fov_override
	# smooth FOV
	_fov_cur = target_fov if _force_snap else Util.damp(_fov_cur, target_fov, 8.0, dt)
	fov = _fov_cur
	# mode transition blend
	if _trans_t < 1.0:
		_trans_t = minf(_trans_t + dt / 0.6, 1.0)
		var k := _trans_t * _trans_t * (3.0 - 2.0 * _trans_t)
		target = _trans_from.interpolate_with(target, k)
	# aim ray basis (no shake)
	_aim_basis = target.basis
	_aim_origin = target.origin
	# recoil / shake
	target = _apply_kick_and_shake(target, dt)
	global_transform = target
	_force_snap = false
	_update_underwater()
	_update_visibility()


func _desired_mode() -> Mode:
	if player.is_dead and player.move_mode == Player.Move.DEAD:
		return Mode.DEATH
	if player.is_in_vehicle() and is_instance_valid(_veh):
		var vclass = _veh.get("vclass")
		if vclass == GC.VC_HELI or vclass == GC.VC_PLANE:
			return Mode.AIRCRAFT
		return Mode.VEHICLE
	if player.is_in_vehicle() and not is_instance_valid(_veh):
		_veh = player.current_vehicle as Node3D
		if _veh != null:
			on_vehicle_entered(_veh)
	return Mode.FOLLOW


func _on_mode_changed(from: Mode, to: Mode) -> void:
	_trans_from = global_transform
	_trans_t = 0.0
	if to == Mode.DEATH:
		_death_t = 0.0
		_death_pivot = player.global_position + Vector3(0, 0.9, 0)
	if from == Mode.DEATH and to == Mode.FOLLOW:
		_trans_t = 1.0
		yaw = player.rotation.y
		pitch = -0.12
		_force_snap = true


func _base_fov() -> float:
	return float(Game.settings.get("fov", 75.0))


# ---- Third person ----------------------------------------------------------------------------------------------
func _update_follow(dt: float) -> Array:
	var p = player
	var fp: bool = first_person
	var aiming: bool = p.aiming and not p.is_swimming
	var crouch: bool = p.crouching
	var swim: bool = p.is_swimming
	var sprint: bool = p.sprinting
	var vis_pos: Vector3 = p.get_visual_position()

	var t_dist := DIST_DEFAULT
	var t_pivot := PIVOT_STAND
	var t_shoulder := SHOULDER_DEFAULT * shoulder_side
	var fov_t := _base_fov()
	if fp:
		t_dist = 0.0
		t_pivot = Player.EYE_CROUCH if crouch else Player.EYE_STAND
		if swim:
			t_pivot = 1.25
		t_shoulder = 0.0
	elif aiming:
		t_dist = DIST_AIM
		t_pivot = PIVOT_AIM
		t_shoulder = SHOULDER_AIM * shoulder_side
		if crouch:
			t_pivot = 1.25
	elif swim:
		t_dist = DIST_SWIM
		t_pivot = 1.35 if not p.head_underwater else 0.95
		t_shoulder = 0.2 * shoulder_side
	elif crouch:
		t_dist = DIST_CROUCH
		t_pivot = PIVOT_CROUCH
	elif sprint:
		t_dist = DIST_SPRINT
	if p.move_mode == Player.Move.COVER and not aiming and not fp:
		t_dist = 2.9
		t_shoulder = 0.7 * shoulder_side
	if aiming:
		fov_t *= AIM_FOV_MULT
	if sprint and not fp:
		fov_t += SPRINT_FOV_KICK
	elif sprint and fp:
		fov_t += 4.0
	if p.move_mode == Player.Move.PARACHUTE:
		t_dist = 4.8
		fov_t += 6.0

	var rate_d := 10.0 if aiming else 7.0
	if _force_snap:
		_dist = t_dist
		_pivot_h = t_pivot
		_shoulder = t_shoulder
	else:
		_dist = Util.damp(_dist, t_dist, rate_d, dt)
		_pivot_h = Util.damp(_pivot_h, t_pivot, 8.0, dt)
		_shoulder = Util.damp(_shoulder, t_shoulder, 9.0, dt)

	# pivot with vertical smoothing (hides stair/step jitter)
	var want_y := vis_pos.y + _pivot_h
	if _force_snap or absf(want_y - _pivot_y) > 2.5:
		_pivot_y = want_y
	else:
		_pivot_y = Util.damp(_pivot_y, want_y, 16.0, dt)
	var pivot := Vector3(vis_pos.x, _pivot_y, vis_pos.z)

	var cb := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	var desired := pivot + cb.x * _shoulder + cb.z * _dist
	var cam_pos := desired
	if _dist > 0.15:
		cam_pos = _collide(pivot, desired, dt)
	else:
		_coll_frac = 1.0
		# first person: slightly in front of the eyes + gentle head bob
		cam_pos = pivot - cb.z * 0.1
		var spd := Vector2(p.velocity.x, p.velocity.z).length()
		if p.is_on_floor() and spd > 0.5:
			_bob_t += dt * (6.0 + spd * 0.9)
			cam_pos.y += sin(_bob_t) * 0.012 * minf(spd / 5.0, 1.4)
			cam_pos += cb.x * cos(_bob_t * 0.5) * 0.006 * minf(spd / 5.0, 1.4)
	var fov_final := fov_t
	return [Transform3D(cb, cam_pos), fov_final]


## Sphere-cast from the pivot to the desired camera position; returns the clipped, smoothed camera position.
func _collide(from: Vector3, to: Vector3, dt: float) -> Vector3:
	var motion := to - from
	var full := motion.length()
	if full < 0.01:
		return to
	_query.transform = Transform3D(Basis.IDENTITY, from)
	_query.motion = motion
	_query.exclude = []
	var safe := 1.0
	var res := get_world_3d().direct_space_state.cast_motion(_query)
	if res.size() >= 1:
		safe = clampf(res[0], 0.0, 1.0)
	var allowed := clampf(safe - 0.04 / full, 0.0, 1.0)
	if _force_snap:
		_coll_frac = allowed
	elif allowed < _coll_frac:
		_coll_frac = Util.damp(_coll_frac, allowed, 45.0, dt)    # snap in fast so we never see through walls
		_coll_clear_time = 0.0
	else:
		_coll_clear_time += dt
		if _coll_clear_time > 0.12:
			_coll_frac = Util.damp(_coll_frac, allowed, 3.5, dt)  # ease back out
	_coll_frac = minf(_coll_frac, 1.0)
	return from + motion * _coll_frac


# ---- Vehicle & aircraft chase ----------------------------------------------------------------------------------------
func _update_vehicle(dt: float) -> Array:
	var v := _veh
	if v == null or not is_instance_valid(v):
		return [global_transform, _base_fov()]
	var hints: Dictionary = {}
	if v.has_method("get_camera_hints"):
		hints = v.get_camera_hints()
	var aircraft := mode == Mode.AIRCRAFT
	var dist: float = float(hints.get("distance", 6.5))
	var height: float = float(hints.get("height", 2.4))
	var look_ahead: float = float(hints.get("look_ahead", 3.0))
	var hint_fov: float = float(hints.get("fov", _base_fov()))
	var f := Engine.get_physics_interpolation_fraction()
	var vpos := _veh_prev.lerp(_veh_curr, f)
	var heading := lerp_angle(_veh_prev_yaw, _veh_curr_yaw, f)
	var vel := Vector3.ZERO
	var lv = v.get("linear_velocity")
	if lv is Vector3:
		vel = lv
	var speed := vel.length()
	var fwd_speed := 0.0
	if v.has_method("get_forward_speed"):
		fwd_speed = v.get_forward_speed()
	var kmh := speed * 3.6

	# decay the manual look offsets when the mouse is idle
	_look_idle += dt
	if _look_idle > 1.7:
		_look_yaw = Util.damp(_look_yaw, 0.0, 2.6, dt)
		_look_pitch = Util.damp(_look_pitch, 0.0, 2.6, dt)

	look_back_active = Input.is_action_pressed(&"look_back") and _input_allowed()
	var target_yaw := heading
	if speed > 4.0 and not aircraft:
		var vy := Util.dir_to_yaw(Util.flat(vel).normalized())
		if fwd_speed > 0.0:
			target_yaw = lerp_angle(heading, vy, clampf((speed - 6.0) / 20.0, 0.0, 0.5))
	if look_back_active:
		target_yaw += PI
	var rate := (1.6 if aircraft else 2.7) + clampf(speed / 30.0, 0.0, 1.0) * (1.4 if aircraft else 2.4)
	if look_back_active:
		rate = 9.0
	if _force_snap:
		_chase_yaw = target_yaw
	else:
		_chase_yaw = lerp_angle(_chase_yaw, target_yaw, 1.0 - exp(-rate * dt))

	var fp_view: bool = first_person and not aircraft
	var cam_t: Transform3D
	var fov_t := hint_fov + clampf((kmh - 50.0) / 150.0, 0.0, 1.0) * (6.0 if aircraft else 11.0)
	if fp_view:
		var off: Vector3 = hints.get("first_person_offset", hints.get("fp_offset", _find_driver_eye_offset(v)))
		var vb := Basis(Vector3.UP, heading)
		var eye := vpos + vb * off
		var b := Basis(Vector3.UP, heading + _look_yaw) * Basis(Vector3.RIGHT, _look_pitch)
		cam_t = Transform3D(b, eye)
		yaw = heading + _look_yaw
		pitch = _look_pitch
		return [cam_t, fov_t + 4.0]

	var final_yaw := _chase_yaw + _look_yaw
	var yb := Basis(Vector3.UP, final_yaw)
	var focus := vpos + Vector3(0, height * (0.55 if not aircraft else 0.3), 0) + yb * Vector3(0, 0, -look_ahead * clampf(speed / 14.0, 0.25, 1.0))
	var arm := Vector3(0, height * (0.55 if not aircraft else 0.9), dist)
	if aircraft:
		var vf: Vector3 = -v.global_transform.basis.z
		arm.y += clampf(-vf.y, -0.6, 0.6) * dist * 0.4
	var arm_world := yb * arm
	if absf(_look_pitch) > 0.001:
		arm_world = arm_world.rotated(yb.x, _look_pitch)
	var desired := focus + arm_world
	var cam_pos := _collide(focus, desired, dt)
	var cam_basis := Basis.looking_at((focus - cam_pos).normalized(), Vector3.UP)
	yaw = final_yaw
	pitch = asin(clampf(cam_basis.z.y * -1.0, -1.0, 1.0))
	return [Transform3D(cam_basis, cam_pos), fov_t]


func _find_driver_eye_offset(v: Node3D) -> Vector3:
	var seat := v.find_child("SeatDriver", true, false)
	if seat is Node3D:
		return v.to_local((seat as Node3D).global_position) + Vector3(0, 0.62, -0.05)
	return Vector3(-0.35, 1.2, -0.2)


# ---- Death ---------------------------------------------------------------------------------------------------------------
func _update_death(dt: float) -> Array:
	_death_t += dt
	var k := clampf(_death_t / 4.0, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 3.0)
	yaw += 0.16 * dt
	pitch = lerpf(pitch, -0.62, 1.0 - exp(-1.2 * dt))
	var dist := lerpf(DIST_DEFAULT, 7.5, ease_k)
	var focus: Vector3 = player.global_position
	if player.rig != null and player.rig.has_method("get_ragdoll_position"):
		focus = player.rig.get_ragdoll_position()
	_death_pivot = _death_pivot.lerp(focus + Vector3(0, 0.6, 0), 1.0 - exp(-5.0 * dt))
	var pivot := _death_pivot + Vector3(0, ease_k * 1.0, 0)
	var cb := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	var desired := pivot + cb.z * dist
	var cam_pos := _collide(pivot, desired, dt)
	return [Transform3D(cb, cam_pos), _base_fov() - 8.0 * ease_k]


# ---- Shake / recoil ---------------------------------------------------------------------------------------------------------
func _apply_kick_and_shake(t: Transform3D, dt: float) -> Transform3D:
	var wc = player.weapons if player != null else null
	if wc != null and wc.get("scope_active") == true:
		var sw = wc.get("scope_sway")
		if sw is Vector2:
			t.basis = Basis(Vector3.UP, (sw as Vector2).x) * t.basis * Basis(Vector3.RIGHT, (sw as Vector2).y)
			_aim_basis = t.basis
	if absf(_kick_pitch) > 0.0001 or absf(_kick_yaw) > 0.0001:
		var kb := Basis(Vector3.UP, _kick_yaw) * t.basis * Basis(Vector3.RIGHT, _kick_pitch)
		# keep the aim ray in sync: recoil is part of the aim
		_aim_basis = kb
		t.basis = kb
		_kick_pitch = Util.damp(_kick_pitch, 0.0, 7.0, dt)
		_kick_yaw = Util.damp(_kick_yaw, 0.0, 7.0, dt)
	if _shakes.is_empty():
		return t
	var total := 0.0
	var i := _shakes.size() - 1
	while i >= 0:
		var s: Dictionary = _shakes[i]
		s["t"] = float(s["t"]) - dt
		if float(s["t"]) <= 0.0:
			_shakes.remove_at(i)
		else:
			var kk := float(s["t"]) / float(s["dur"])
			total += float(s["amp"]) * kk * kk
		i -= 1
	total = minf(total, 1.0)
	if total <= 0.0:
		return t
	var tm := Time.get_ticks_msec() * 0.001
	var off := Vector3(sin(tm * 47.0), sin(tm * 53.0 + 1.7), sin(tm * 41.0 + 3.1)) * total * 0.10
	var rot := Vector3(sin(tm * 61.0 + 0.4), sin(tm * 57.0 + 2.2), sin(tm * 43.0 + 5.1)) * total * 0.03
	t.origin += t.basis * off
	t.basis = t.basis * Basis.from_euler(rot)
	return t


func _on_explosion(pos: Vector3, radius: float, _source: Node) -> void:
	var d := pos.distance_to(global_position)
	var reach := radius * 3.5 + 40.0
	if d > reach:
		return
	var a := 1.0 - d / reach
	add_shake(clampf(a * 1.1, 0.05, 1.0), 0.45 + radius * 0.05)


func _on_vehicle_collision(vehicle: Node, _other: Node, impulse: float) -> void:
	if player == null or vehicle != player.current_vehicle:
		return
	add_shake(clampf(impulse / 9000.0, 0.05, 0.75), 0.4)


func _on_gunshot(pos: Vector3, loudness: float, source: Node) -> void:
	if source == player or player == null:
		return
	var d := pos.distance_to(global_position)
	if d < 12.0 and loudness > 30.0:
		add_shake(0.05, 0.12)


# ---- Flags & visibility ---------------------------------------------------------------------------------------------------
func _update_underwater() -> void:
	var sy: float = player.water_surface_y
	var under := not is_nan(sy) and global_position.y < sy - 0.02
	player.is_underwater = under


func _update_visibility() -> void:
	var vis_node: Node3D = player.visual
	if vis_node == null:
		return
	var need_fp := false
	var hide_all := false
	if mode == Mode.FOLLOW:
		var head: Vector3 = player.get_visual_position() + Vector3(0, 1.5 if not player.crouching else 1.05, 0)
		var dd := global_position.distance_to(head)
		if first_person and _dist < 0.9:
			need_fp = true
		elif dd < 0.75:
			hide_all = true
	elif mode == Mode.VEHICLE or mode == Mode.AIRCRAFT:
		if first_person:
			hide_all = true
	if hide_all != _arm_hidden:
		_arm_hidden = hide_all
		vis_node.visible = not hide_all
	if need_fp != _fp_applied:
		_fp_applied = need_fp
		if player.rig != null:
			player.rig.set_first_person(need_fp)       # hides head / hair / hat meshes; the body stays visible below the camera


