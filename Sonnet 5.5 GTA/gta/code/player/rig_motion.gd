class_name RigMotion
extends RefCounted
## Procedural animation brain of CharacterRig. Turns the high level inputs (speed, direction, stance, aim, weapon kind,
## actions) into a RigPose each frame; RigSolver converts that pose to bone rotations.
## Architecture: one pose GENERATOR per mode (ground / swim / sit / ladder / parachute / dead / airborne), blended with
## critically damped mode weights, then ACTION overlays (punch, reload, hit react ...) and look-at are applied on top.
## Rig space: +X right, +Y up, -Z forward. Foot cycle phase accumulates with time at f/2 Hz where the foot half-stride R is
## derived from the real speed (R = duty * speed / step_frequency), so planted feet do not slide.

# ---- modes ---------------------------------------------------------------------------------------------------------
const M_GROUND := 0
const M_SWIM_S := 1
const M_SWIM_U := 2
const M_SIT_CAR := 3
const M_SIT_BIKE := 4
const M_LADDER := 5
const M_PARA := 6
const M_DEAD := 7
const M_AIR := 8
const M_COUNT := 9
const MODE_TIME: Array[float] = [0.12, 0.30, 0.30, 0.22, 0.22, 0.26, 0.45, 0.14, 0.09]

# ---- gait tables (speed m/s -> value) -------------------------------------------------------------------------------------
const GAIT_V: Array[float] = [0.3, 1.4, 2.2, 3.0, 4.5, 7.0, 9.0]
const GAIT_F: Array[float] = [1.15, 2.0, 2.5, 2.8, 3.0, 3.4, 3.7]        # steps per second
const GAIT_D: Array[float] = [0.70, 0.56, 0.46, 0.40, 0.33, 0.27, 0.25]  # stance fraction of the cycle
const GAIT_LIFT: Array[float] = [0.03, 0.09, 0.13, 0.17, 0.21, 0.26, 0.29]
const GAIT_ARM: Array[float] = [0.06, 0.18, 0.22, 0.24, 0.25, 0.26, 0.27]

const ANKLE_H := 0.09
const STANCE_W := 0.115

# ---- weapon hold table: [carry_r, carry_dir_r, carry_l, carry_dir_l, aim_r, aim_l, two_handed(0/1), left_swings(0/1)] ----------------
# aim_* are (forward, right, up) coefficients in the aim frame; carry_* are chest-space positions / directions.
const HOLD := {
	&"none": [Vector3(0.285, -0.53, -0.04), Vector3(0, -0.3, -1), Vector3(-0.285, -0.53, -0.04), Vector3(0, -0.3, -1), Vector3(0.30, 0.10, -0.01), Vector3(0.30, -0.10, -0.01), 0.0, 1.0],
	&"pistol": [Vector3(0.25, -0.34, -0.30), Vector3(0.02, -0.40, -0.92), Vector3(-0.285, -0.53, -0.04), Vector3(0, -0.3, -1), Vector3(0.50, 0.06, 0.05), Vector3(0.47, -0.035, 0.03), 0.0, 1.0],
	&"smg": [Vector3(0.20, -0.38, -0.26), Vector3(0, -0.5, -0.87), Vector3(-0.05, -0.30, -0.46), Vector3(0.1, -0.45, -0.89), Vector3(0.30, 0.15, -0.09), Vector3(0.52, -0.03, -0.06), 1.0, 0.0],
	&"rifle": [Vector3(0.20, -0.38, -0.25), Vector3(0, -0.5, -0.87), Vector3(-0.05, -0.28, -0.50), Vector3(0.1, -0.45, -0.89), Vector3(0.27, 0.16, -0.10), Vector3(0.56, -0.03, -0.07), 1.0, 0.0],
	&"shotgun": [Vector3(0.20, -0.38, -0.25), Vector3(0, -0.5, -0.87), Vector3(-0.05, -0.28, -0.50), Vector3(0.1, -0.45, -0.89), Vector3(0.27, 0.16, -0.10), Vector3(0.54, -0.03, -0.07), 1.0, 0.0],
	&"sniper": [Vector3(0.20, -0.38, -0.25), Vector3(0, -0.5, -0.87), Vector3(-0.05, -0.28, -0.50), Vector3(0.1, -0.45, -0.89), Vector3(0.26, 0.16, -0.10), Vector3(0.58, -0.02, -0.07), 1.0, 0.0],
	&"heavy": [Vector3(0.27, -0.12, -0.08), Vector3(0, 0.2, -1), Vector3(-0.05, -0.12, -0.50), Vector3(0.1, 0.1, -1), Vector3(0.20, 0.22, -0.02), Vector3(0.48, -0.02, -0.08), 1.0, 0.0],
	&"melee_knife": [Vector3(0.24, -0.38, -0.26), Vector3(0.05, -0.35, -0.93), Vector3(-0.285, -0.53, -0.04), Vector3(0, -0.3, -1), Vector3(0.30, 0.10, 0.00), Vector3(0.30, -0.12, 0.02), 0.0, 1.0],
	&"melee_bat": [Vector3(0.28, -0.30, -0.18), Vector3(0.1, 0.55, -0.82), Vector3(-0.285, -0.53, -0.04), Vector3(0, -0.3, -1), Vector3(0.30, 0.10, 0.0), Vector3(0.30, -0.12, 0.02), 0.0, 1.0],
	&"thrown": [Vector3(0.25, -0.42, -0.14), Vector3(0, -0.6, -0.8), Vector3(-0.285, -0.53, -0.04), Vector3(0, -0.3, -1), Vector3(0.34, 0.08, 0.0), Vector3(0.30, -0.12, 0.0), 0.0, 1.0],
}


class Spr:
	extends RefCounted
	var x := 0.0
	var vel := 0.0

	func set_now(value: float) -> void:
		x = value
		vel = 0.0

	## Critically damped spring towards `target` (smooth_time ~ time to settle, seconds).
	func update(target: float, smooth_time: float, dt: float) -> float:
		var st := maxf(smooth_time, 0.0001)
		var omega := 2.0 / st
		var k := omega * dt
		var e := 1.0 / (1.0 + k + 0.48 * k * k + 0.235 * k * k * k)
		var change := x - target
		var temp := (vel + omega * change) * dt
		vel = (vel - omega * temp) * e
		x = target + (change + temp) * e
		return x


var solver: RigSolver = null
var pose := RigPose.new()          # final blended pose that was solved last
var ready_ok := false

# ---- inputs (written by CharacterRig) -------------------------------------------------------------------------------------
var speed := 0.0
var move_dir := Vector3(0, 0, -1)  # local; x right, z back (forward = -z), y vertical (swimming)
var sprinting := false
var stance: StringName = &"stand"
var aim_on := false
var aim_pitch := 0.0
var aim_yaw := 0.0
var weapon: StringName = &"none"
var look_dir_local := Vector3(0, 0, -1)   # direction to look at (rig-local, unit); only used when look_weight > 0
var look_weight := 0.0
var yaw_rate := 0.0                       # rad/s of the owner turning (for lean)
var steering := 0.0                       # -1..1 (vehicle seats, parachute)
var lean_roll := 0.0                      # radians (bike lean)
var cover_peek := 0.0                     # -1 left .. +1 right
var ride_style: StringName = &"motorcycle"
var seat_role: StringName = &"driver"     # &"driver" | &"passenger"
var seat_offset := Vector3.ZERO
var grounded := true
var air_vy := 0.0
var hands_up := false
var hands_up_hold := 25.0                  # seconds before hands_up releases itself (call play_action(&"hands_up") again to renew)
var _hands_up_t := 0.0
var first_person := false
var dead_face_down := false
var idle_phase_offset := 0.0
var idle_style: StringName = &"relaxed"
var support_offset_rest := Vector3.ZERO   # weapon Grip_L relative to the right wrist at rest (model axes)
var has_support_grip := false
var hit_dir := Vector3(0, 0, 1)           # local direction the last hit pushed the body (xz)

# ---- state ---------------------------------------------------------------------------------------------------------------
var _t := 0.0
var _phase := 0.0
var _ladder_phase := 0.0
var _pedal_phase := 0.0
var _swim_phase := 0.0
var _air_t := 0.0
var _sp_speed := Spr.new()
var _sp_gait := Spr.new()
var _sp_crouch := Spr.new()
var _sp_aim := Spr.new()
var _sp_sprint := Spr.new()
var _sp_hold_r := Spr.new()
var _sp_hold_l := Spr.new()
var _sp_lean := Spr.new()
var _sp_roll := Spr.new()
var _sp_cover_low := Spr.new()
var _sp_cover_high := Spr.new()
var _sp_handsup := Spr.new()
var _sp_peek := Spr.new()
var _sp_look := Spr.new()
var _sp_steer := Spr.new()
var _sp_tread := Spr.new()
var _sp_pitch := Spr.new()
var _sp_two := Spr.new()
var _sp_lfree := Spr.new()
var _dir_s := Vector3(0, 0, -1)
var _look_cur := Vector2.ZERO                # yaw, pitch of head tracking (smoothed)
var _w: Array[Spr] = []
var _poses: Array[RigPose] = []
var _hold: PackedVector3Array = PackedVector3Array()   # smoothed hold params (6 vectors)
var _hold_kind: StringName = &""
var _act: StringName = &""
var _act_t := 0.0
var _act_dur := 1.0
var _act_side := 0
var _punch_toggle := 0
var _flinch_t := 99.0
var _flinch_dir := Vector3(0, 0, 1)
var _flinch_amt := 1.0
var _land_t := 99.0
var _land_amt := 1.0
var _stance_changed_t := 99.0
var _air_owner_driven := false             # true once the owner reports airborne state itself (set_airborne_report)
var _foot_pitch := 0.0
var _rng := RandomNumberGenerator.new()
var _hips_quiet := Vector3.ZERO


func _init() -> void:
	for i in M_COUNT:
		_w.append(Spr.new())
		_poses.append(RigPose.new())
	_w[M_GROUND].set_now(1.0)
	_hold.resize(6)
	_sp_roll.set_now(0.0)
	_rng.randomize()


func setup(s: RigSolver) -> void:
	solver = s
	ready_ok = s != null and s.valid
	_t = _rng.randf() * 20.0
	_phase = _rng.randf()
	idle_phase_offset = _rng.randf() * TAU
	_set_hold_instant(weapon)
	pose.f[RigPose.F_GROUND] = 1.0


# ===================================================================================================================
# Public control
# ===================================================================================================================
func play(action: StringName, duration: float = -1.0) -> void:
	match action:
		&"punch", &"kick", &"melee_swing", &"reload", &"throw", &"enter_vehicle", &"exit_vehicle":
			_act = action
			_act_t = 0.0
			_act_dur = duration if duration > 0.0 else _default_duration(action)
			if action == &"punch":
				_act_side = _punch_toggle
				_punch_toggle = 1 - _punch_toggle
			elif action == &"melee_swing":
				_act_side = _punch_toggle
				_punch_toggle = 1 - _punch_toggle
		&"hit_react":
			_flinch_t = 0.0
			_flinch_dir = Vector3(_rng.randf_range(-0.55, 0.55), 0.0, 1.0).normalized() if hit_dir == Vector3(0, 0, 1) else hit_dir
			_flinch_amt = 1.0
		&"jump":
			grounded = false
			_air_t = 0.0
			air_vy = maxf(air_vy, 4.0)
			_air_owner_driven = false
		&"land":
			if not grounded or _w[M_AIR].x > 0.2:
				_land_t = 0.0
				_land_amt = clampf(absf(air_vy) / 6.0, 0.35, 1.3)
			grounded = true
		&"hands_up":
			hands_up = true
			_hands_up_t = 0.0
		&"hands_down":
			hands_up = false
		&"stop":
			_act = &""


func _default_duration(a: StringName) -> float:
	match a:
		&"punch":
			return 0.42
		&"kick":
			return 0.62
		&"melee_swing":
			return 0.62 if weapon == &"melee_bat" else 0.48
		&"reload":
			return 1.7
		&"throw":
			return 0.75
		&"enter_vehicle":
			return 0.55
		&"exit_vehicle":
			return 0.5
	return 0.5


## The owner drives the airborne state itself (set_grounded) - disables the automatic landing of a jump hop.
func report_airborne() -> void:
	_air_owner_driven = true


## True when nothing fast is going on (standing / crouching still, no action): CharacterRig then updates at 30 Hz.
func is_calm() -> bool:
	return _sp_speed.x < 0.05 and _act == &"" and _flinch_t > 0.5 and _land_t > 0.6 and grounded and not aim_on and not hands_up 		and (stance == &"stand" or stance == &"crouch") and look_weight < 0.01 and _w[M_GROUND].x > 0.99


func action_progress() -> float:
	if _act == &"":
		return 1.0
	return clampf(_act_t / _act_dur, 0.0, 1.0)


func current_action() -> StringName:
	return _act


func hit_react_active() -> bool:
	return _flinch_t < 0.45


func flinch(dir_local: Vector3, strength: float = 1.0) -> void:
	_flinch_t = 0.0
	_flinch_dir = Vector3(dir_local.x, 0, dir_local.z)
	if _flinch_dir.length() < 0.01:
		_flinch_dir = Vector3(0, 0, 1)
	_flinch_dir = _flinch_dir.normalized()
	_flinch_amt = clampf(strength, 0.3, 2.0)


func snap_to_stance() -> void:
	## Jump the blend weights straight to the current stance (after setup / teleport / respawn).
	var target := _mode_for_stance()
	for i in M_COUNT:
		_w[i].set_now(1.0 if i == target else 0.0)
	_sp_crouch.set_now(_crouch_target())
	_sp_aim.set_now(1.0 if aim_on else 0.0)


# ===================================================================================================================
# Frame update
# ===================================================================================================================
func update(dt: float) -> void:
	if not ready_ok:
		return
	dt = clampf(dt, 0.0001, 0.1)
	_t += dt
	_update_smoothers(dt)
	var air_target := 0.0 if grounded else 1.0
	_w[M_AIR].update(air_target, MODE_TIME[M_AIR] if air_target > 0.5 else 0.12, dt)
	var mode := _mode_for_stance()
	for i in M_COUNT - 1:
		_w[i].update(1.0 if i == mode else 0.0, MODE_TIME[i], dt)
	# generate the active poses and blend
	var sum := 0.0
	var first := true
	var air_w: float = clampf(_w[M_AIR].x, 0.0, 1.0)
	for i in M_COUNT - 1:
		_w[i].x = clampf(_w[i].x, 0.0, 1.0)
		sum += _w[i].x
	if sum < 0.0001:
		_w[mode].x = 1.0
		sum = 1.0
	var accum := 0.0
	for i in M_COUNT - 1:
		var wi: float = _w[i].x / sum * (1.0 - air_w)
		if wi < 0.003:
			continue
		_generate(i, _poses[i], dt)
		if first:
			pose.copy_from(_poses[i])
			accum = wi
			first = false
		else:
			accum += wi
			pose.mix(_poses[i], wi / accum)
	if air_w > 0.003:
		_generate(M_AIR, _poses[M_AIR], dt)
		if first:
			pose.copy_from(_poses[M_AIR])
		else:
			pose.mix(_poses[M_AIR], air_w)
	_apply_overlays(pose, dt)
	_apply_look(pose, dt)
	solver.solve(pose, dt)


func _mode_for_stance() -> int:
	match stance:
		&"swim_surface":
			return M_SWIM_S
		&"swim_under":
			return M_SWIM_U
		&"sit_car":
			return M_SIT_CAR
		&"sit_bike":
			return M_SIT_BIKE
		&"ladder":
			return M_LADDER
		&"parachute":
			return M_PARA
		&"dead":
			return M_DEAD
	return M_GROUND


func _crouch_target() -> float:
	match stance:
		&"crouch":
			return 1.0
		&"cover_low":
			return 1.28 if not aim_on else 0.62
	return 0.0


func _update_smoothers(dt: float) -> void:
	var sp := maxf(speed, 0.0)
	_sp_speed.update(sp, 0.07, dt)
	var gait_target := smoothstep(0.12, 0.55, _sp_speed.x)
	_sp_gait.update(gait_target, 0.10, dt)
	_sp_crouch.update(_crouch_target(), 0.16, dt)
	_sp_aim.update(1.0 if aim_on else 0.0, 0.15, dt)
	_sp_sprint.update(1.0 if (sprinting and sp > 4.0) else 0.0, 0.2, dt)
	var has_w := weapon != &"none"
	_sp_hold_r.update(1.0 if has_w else 0.0, 0.14, dt)
	var two: float = _hold[0].x if false else float(HOLD.get(weapon, HOLD[&"none"])[6])
	var lfree: float = float(HOLD.get(weapon, HOLD[&"none"])[7])
	_sp_two.update(two, 0.14, dt)
	_sp_lfree.update(lfree, 0.14, dt)
	var left_target := 0.0
	if has_w and two > 0.5:
		left_target = 1.0
	elif has_w and aim_on:
		left_target = 1.0
	_sp_hold_l.update(left_target, 0.14, dt)
	_sp_lean.update(clampf(yaw_rate * clampf(_sp_speed.x, 0.0, 6.0) * 0.045, -0.35, 0.35), 0.16, dt)
	_sp_cover_low.update(1.0 if stance == &"cover_low" else 0.0, 0.18, dt)
	_sp_cover_high.update(1.0 if stance == &"cover_high" else 0.0, 0.18, dt)
	_sp_peek.update(cover_peek, 0.12, dt)
	_sp_handsup.update(1.0 if hands_up else 0.0, 0.12, dt)
	_sp_look.update(clampf(look_weight, 0.0, 1.0), 0.18, dt)
	_sp_steer.update(clampf(steering, -1.0, 1.0), 0.10, dt)
	_sp_roll.update(lean_roll, 0.20, dt)
	_sp_pitch.update(clampf(move_dir.y, -1.0, 1.0), 0.3, dt)
	# smoothed movement direction (xz)
	var md := Vector3(move_dir.x, 0, move_dir.z)
	if md.length() > 0.05 and sp > 0.1:
		md = md.normalized()
		_dir_s = _dir_s.lerp(md, 1.0 - exp(-12.0 * dt))
		if _dir_s.length() < 0.05:
			_dir_s = md
		_dir_s = _dir_s.normalized()
	# hold parameters follow the current weapon kind
	if weapon != _hold_kind:
		_hold_kind = weapon
	var tab: Array = HOLD.get(weapon, HOLD[&"none"])
	for i in 6:
		_hold[i] = _hold[i].lerp(tab[i], 1.0 - exp(-11.0 * dt))
	# advance cycle phases
	if _sp_gait.x > 0.02 and stance != &"dead":
		var f := _tab(GAIT_F, _sp_speed.x) * (1.0 + 0.3 * clampf(_sp_crouch.x, 0.0, 1.0)) * (1.0 + 0.9 * absf(_dir_s.x))
		_phase = fposmod(_phase + dt * f * 0.5, 1.0)
	_air_t += dt
	if not grounded and not _air_owner_driven and _air_t > 1.4:
		play(&"land")                       # a plain jump() hop that nobody reported as a fall: land by itself
	if hands_up:
		_hands_up_t += dt
		if _hands_up_t > hands_up_hold:
			hands_up = false
	_flinch_t += dt
	_land_t += dt
	if _act != &"":
		_act_t += dt
		if _act_t >= _act_dur:
			_act = &""
	var lad_dir := signf(move_dir.y) if absf(move_dir.y) > 0.1 else (-signf(move_dir.z) if absf(move_dir.z) > 0.1 else 1.0)
	var lad_speed := lad_dir * speed
	if stance == &"ladder":
		_ladder_phase += dt * lad_speed / 0.62
	if stance == &"sit_bike" and ride_style == &"bicycle":
		_pedal_phase = fposmod(_pedal_phase + dt * (0.6 + sp * 0.55) * (1.0 if sp > 0.3 else 0.0), 1.0)
	_swim_phase = fposmod(_swim_phase + dt * (0.45 + clampf(sp, 0.0, 3.0) * 0.28), 1.0)


func _set_hold_instant(kind: StringName) -> void:
	var tab: Array = HOLD.get(kind, HOLD[&"none"])
	for i in 6:
		_hold[i] = tab[i]
	_hold_kind = kind


func _tab(ys: Array, x: float) -> float:
	var xs: Array[float] = GAIT_V
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1]))
	return ys[ys.size() - 1]


# ===================================================================================================================
# Pose generators
# ===================================================================================================================
func _generate(mode: int, p: RigPose, dt: float) -> void:
	_reset(p)
	match mode:
		M_GROUND:
			_gen_ground(p)
		M_SWIM_S, M_SWIM_U:
			_gen_swim(p, mode == M_SWIM_U)
		M_SIT_CAR:
			_gen_sit_car(p)
		M_SIT_BIKE:
			_gen_sit_bike(p)
		M_LADDER:
			_gen_ladder(p)
		M_PARA:
			_gen_para(p)
		M_DEAD:
			_gen_dead(p)
		M_AIR:
			_gen_air(p)


func _reset(p: RigPose) -> void:
	for i in RigPose.VCOUNT:
		p.v[i] = Vector3.ZERO
	p.v[RigPose.ARM_R] = Vector3(0.285, -0.53, -0.04)
	p.v[RigPose.ARM_L] = Vector3(-0.285, -0.53, -0.04)
	p.v[RigPose.POLE_R] = Vector3(0.35, -0.35, 0.85)
	p.v[RigPose.POLE_L] = Vector3(-0.35, -0.35, 0.85)
	p.v[RigPose.HDIR_R] = Vector3(0, -0.3, -1)
	p.v[RigPose.HDIR_L] = Vector3(0, -0.3, -1)
	p.v[RigPose.HUP_R] = Vector3(0, 1, 0)
	p.v[RigPose.HUP_L] = Vector3(0, 1, 0)
	p.v[RigPose.LEG_R] = Vector3(STANCE_W, ANKLE_H, 0)
	p.v[RigPose.LEG_L] = Vector3(-STANCE_W, ANKLE_H, 0)
	p.v[RigPose.KNEE_R] = Vector3(0.08, 0.0, -1)
	p.v[RigPose.KNEE_L] = Vector3(-0.08, 0.0, -1)
	p.v[RigPose.FOOT_R] = Vector3(0, -0.12, 0)
	p.v[RigPose.FOOT_L] = Vector3(0, 0.12, 0)
	for i in RigPose.FCOUNT:
		p.f[i] = 0.0
	p.f[RigPose.F_GROUND] = 1.0


static func _ankle_y(pitch: float) -> float:
	if pitch >= 0.0:
		return 0.09 * cos(pitch) + 0.085 * sin(pitch)
	return 0.03 + 0.06 * cos(pitch) + 0.14 * sin(-pitch)


## Chest orientation implied by the hips / spine / chest channels of a pose (for converting model-space aim directions).
static func _chest_basis(p: RigPose) -> Basis:
	return Basis.from_euler(p.v[RigPose.HIPS_ROT]) * Basis.from_euler(p.v[RigPose.SPINE_ROT]) * Basis.from_euler(p.v[RigPose.CHEST_ROT])


## Neck-base position (model space) implied by the hips / spine / chest channels of a pose.
func _neck_model(p: RigPose) -> Vector3:
	var rh := solver.rest_head
	var dh := Basis.from_euler(p.v[RigPose.HIPS_ROT])
	var hp: Vector3 = rh[RigSolver.HIPS] + p.v[RigPose.HIPS_POS]
	var dsp := dh * Basis.from_euler(p.v[RigPose.SPINE_ROT])
	var p_sp: Vector3 = hp + dh * (rh[RigSolver.SPINE] - rh[RigSolver.HIPS])
	var dch := dsp * Basis.from_euler(p.v[RigPose.CHEST_ROT])
	var p_ch: Vector3 = p_sp + dsp * (rh[RigSolver.CHEST] - rh[RigSolver.SPINE])
	return p_ch + dch * (rh[RigSolver.NECK] - rh[RigSolver.CHEST])


## Converts a model-space point (rig origin = feet / seat) into the chest space the arm channels use.
func _to_chest(p: RigPose, t_model: Vector3) -> Vector3:
	return _chest_basis(p).transposed() * (t_model - _neck_model(p))


func _off_to_chest(p: RigPose, off_model: Vector3) -> Vector3:
	return _chest_basis(p).transposed() * off_model


func _dir_to_chest(p: RigPose, d_model: Vector3) -> Vector3:
	return (_chest_basis(p).transposed() * d_model).normalized()


func _gen_ground(p: RigPose) -> void:
	var v := _sp_speed.x
	var gw := _sp_gait.x
	var c := _sp_crouch.x
	var aw := _sp_aim.x
	var runw := smoothstep(1.8, 3.2, v)
	var sprw := smoothstep(4.8, 7.0, v)
	var cl := _sp_cover_low.x
	var ch := _sp_cover_high.x
	var cov := maxf(cl, ch)
	var hr := _sp_hold_r.x
	var hl := _sp_hold_l.x
	var ph := _phase
	var tau_ph := TAU * ph
	var cph := cos(tau_ph)
	var sph := sin(tau_ph)
	var it := _t + idle_phase_offset
	# ---- gait parameters
	var lat_k := absf(_dir_s.x)
	var f := _tab(GAIT_F, v) * (1.0 + 0.3 * clampf(c, 0.0, 1.0)) * (1.0 + 0.9 * lat_k)
	var d := _tab(GAIT_D, v)
	var lift := _tab(GAIT_LIFT, v) * (1.0 - 0.4 * clampf(c, 0.0, 1.0))
	var half := d * v / maxf(f, 0.1)               # half stride (ankle travel / 2), no foot sliding by construction
	var lean := clampf(0.025 + 0.09 * runw + 0.12 * sprw, 0.0, 0.3) * gw
	var dir := _dir_s
	# ---- hips + torso
	# vertical hip bob: walking = lowest at double support (heel strikes, phase 0 / 0.5), running = lowest at mid-stance
	var bob_walk := 0.5 + 0.5 * cos(2.0 * tau_ph)
	var bob_run := 0.5 + 0.5 * cos(2.0 * tau_ph - TAU * d)
	var bob := lerpf(-0.030 * bob_walk, -0.065 * bob_run, runw) * gw
	var sway := 0.022 * sph * (1.0 - 0.5 * runw) * gw
	var hips := Vector3(sway, -0.028 - 0.30 * c + bob, 0.085 * c)
	# idle weight shift / breathing
	var wshift := sin(it * 0.55) * (1.0 - gw)
	hips.x += 0.012 * wshift
	var hips_rot := Vector3(-0.35 * lean, 0.0, 0.0)
	hips_rot.y = (0.07 + 0.09 * runw) * cph * gw
	hips_rot.z = 0.03 * sph * gw + 0.012 * wshift - _sp_lean.x * 0.5
	var spine_rot := Vector3(-0.30 * lean - 0.16 * c, -0.45 * hips_rot.y, 0.0)
	var chest_rot := Vector3(-0.30 * lean - 0.12 * c + 0.012 * sin(it * 1.55), -0.55 * hips_rot.y, -0.5 * hips_rot.z - _sp_lean.x * 0.6)
	var neck_rot := Vector3(0.12 * c + 0.3 * lean + 0.02 * sin(it * 0.8), 0.0, 0.0)
	var head_rot := Vector3(0.28 * lean + 0.10 * c + 0.015 * sin(it * 0.7 + 1.0), 0.04 * sin(it * 0.33), -hips_rot.z * 0.4 - _sp_lean.x * 0.3)
	# idle micro motion (stops when walking)
	chest_rot.x += 0.014 * sin(it * 1.55) * (1.0 - gw)
	# ---- aim posture (upper body follows the aim pitch / yaw offset)
	var pitch := clampf(aim_pitch, -1.2, 1.2)
	var yaw_off := clampf(aim_yaw, -1.2, 1.2)
	spine_rot.x += pitch * 0.18 * aw
	chest_rot.x += pitch * 0.30 * aw
	neck_rot.x += pitch * 0.15 * aw
	head_rot.x += pitch * 0.25 * aw
	spine_rot.y += yaw_off * 0.25 * aw
	chest_rot.y += yaw_off * 0.45 * aw
	neck_rot.y += yaw_off * 0.12 * aw
	head_rot.y += yaw_off * 0.18 * aw
	# aiming with a long gun: slight lean into the weapon, knees bent
	hips.y -= 0.035 * aw * hr
	# ---- cover posture
	if cov > 0.01:
		var peek := _sp_peek.x
		hips.z += 0.06 * cov
		hips_rot.x += 0.05 * cl
		spine_rot.x += 0.03 * ch + 0.10 * cl
		chest_rot.x += 0.03 * ch + 0.06 * cl
		head_rot.x += 0.02 * cov
		head_rot.y += -peek * 0.35 * cov
		hips.x += peek * 0.12 * cov
		spine_rot.z -= peek * 0.20 * cov
		chest_rot.z -= peek * 0.24 * cov
		neck_rot.z -= peek * 0.10 * cov
	p.v[RigPose.HIPS_POS] = hips
	p.v[RigPose.HIPS_ROT] = hips_rot
	p.v[RigPose.SPINE_ROT] = spine_rot
	p.v[RigPose.CHEST_ROT] = chest_rot
	p.v[RigPose.NECK_ROT] = neck_rot
	p.v[RigPose.HEAD_ROT] = head_rot
	# ---- legs
	var width := STANCE_W + 0.02 * aw + 0.025 * c + 0.03 * cov
	var lat := absf(dir.x)
	width += 0.09 * lat * gw
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var u := fposmod(ph + 0.5 * side, 1.0)
		var idle_t := Vector3(sx * width, ANKLE_H, 0.0)
		var foot_pitch := 0.0
		var t := idle_t
		if gw > 0.003:
			var f_off := 0.0
			var h := 0.0
			var th := 0.30 * (1.0 - runw) + 0.12 * runw
			var tt := 0.50 + 0.25 * runw
			if u < d:
				var s := u / d
				f_off = half * (1.0 - 2.0 * s)
				foot_pitch = th * (1.0 - smoothstep(0.0, 0.22, s)) - tt * smoothstep(0.62, 1.0, s)
			else:
				var w := (u - d) / maxf(1.0 - d, 0.05)
				var e := w * w * (3.0 - 2.0 * w)
				f_off = -half + 2.0 * half * e
				h = lift * pow(sin(PI * w), 0.85)
				foot_pitch = lerpf(-tt, th, smoothstep(0.1, 1.0, w))
			var gt := Vector3(sx * width + dir.x * f_off, _ankle_y(foot_pitch) + h, dir.z * f_off)
			t = idle_t.lerp(gt, gw)
			foot_pitch *= gw
		p.v[RigPose.LEG_R + side] = t
		# crouch: heels stay down, knees forward and slightly out
		p.v[RigPose.KNEE_R + side] = Vector3(sx * (0.10 + 0.12 * c + 0.1 * lat), 0.0, -1.0)
		p.v[RigPose.FOOT_R + side] = Vector3(foot_pitch, -sx * 0.12 + sx * (0.0), 0.0)
		p.f[RigPose.F_TOE_R + side] = clampf(-foot_pitch * 0.85, 0.0, 0.7)
	# ---- arms: relaxed / swinging (elbows flex progressively with speed)
	var amp := _tab(GAIT_ARM, v) * gw
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var swing := (cph if side == 0 else -cph) * amp            # + = backwards
		var k_fwd := -swing / maxf(amp, 0.001)                      # +1 hand fully forward, -1 fully back
		var base := Vector3(sx * (0.285 - 0.055 * runw), -0.53 + 0.31 * runw + 0.02 * sprw, -0.04 - 0.09 * runw)
		var pos := base + Vector3(0, 0, swing)
		pos.y += maxf(k_fwd, 0.0) * (0.05 + 0.13 * runw) * gw - maxf(-k_fwd, 0.0) * 0.03 * runw * gw
		pos.x += sx * (0.02 * sin(it * 0.9 + side)) * (1.0 - gw)
		p.v[RigPose.ARM_R + side] = pos
		p.v[RigPose.POLE_R + side] = Vector3(sx * (0.40 + 0.25 * runw), -0.35 - 0.45 * runw, 0.85)
	# ---- weapon hold on top of the swing
	_gen_hold(p, aw, hr, hl, cl, ch, runw)
	# ---- idle style
	_apply_idle_style(p, gw, aw, hr)
	# ---- hands up (surrender): wins over weapons
	var hu := _sp_handsup.x
	if hu > 0.01:
		var ph2 := sin(it * 2.3) * 0.01
		for side in 2:
			var sx := 1.0 if side == 0 else -1.0
			var tgt := Vector3(sx * 0.24, 0.36 + ph2, -0.12)
			p.v[RigPose.ARM_R + side] = p.v[RigPose.ARM_R + side].lerp(tgt, hu)
			p.v[RigPose.POLE_R + side] = p.v[RigPose.POLE_R + side].lerp(Vector3(sx * 0.9, -0.5, 0.3), hu)
			p.f[RigPose.F_HOVR_R + side] = lerpf(p.f[RigPose.F_HOVR_R + side], 1.0, hu)
			p.v[RigPose.HDIR_R + side] = p.v[RigPose.HDIR_R + side].lerp(Vector3(sx * 0.15, 1.0, -0.25), hu)
			p.v[RigPose.HUP_R + side] = p.v[RigPose.HUP_R + side].lerp(Vector3(0, 0.0, -1.0), hu)
		p.v[RigPose.SPINE_ROT].x += 0.05 * hu
		p.v[RigPose.HIPS_POS].y -= 0.03 * hu


func _apply_idle_style(p: RigPose, gw: float, aw: float, hr: float) -> void:
	if idle_style == &"relaxed" or gw > 0.05 or aw > 0.05 or hr > 0.05:
		return
	var k := 1.0 - gw
	match idle_style:
		&"arms_crossed":
			p.v[RigPose.ARM_R] = p.v[RigPose.ARM_R].lerp(Vector3(-0.05, -0.30, -0.22), k)
			p.v[RigPose.ARM_L] = p.v[RigPose.ARM_L].lerp(Vector3(0.12, -0.36, -0.20), k)
			p.v[RigPose.POLE_R] = p.v[RigPose.POLE_R].lerp(Vector3(0.3, -1.0, 0.1), k)
			p.v[RigPose.POLE_L] = p.v[RigPose.POLE_L].lerp(Vector3(-0.3, -1.0, 0.1), k)
		&"hands_pockets":
			p.v[RigPose.ARM_R] = p.v[RigPose.ARM_R].lerp(Vector3(0.23, -0.55, -0.12), k)
			p.v[RigPose.ARM_L] = p.v[RigPose.ARM_L].lerp(Vector3(-0.23, -0.55, -0.12), k)
			p.v[RigPose.POLE_R] = p.v[RigPose.POLE_R].lerp(Vector3(1.0, -0.2, 0.5), k)
			p.v[RigPose.POLE_L] = p.v[RigPose.POLE_L].lerp(Vector3(-1.0, -0.2, 0.5), k)
		&"phone":
			var tgt := Vector3(0.12, 0.12, -0.30)
			p.v[RigPose.ARM_R] = p.v[RigPose.ARM_R].lerp(tgt, k)
			p.v[RigPose.POLE_R] = p.v[RigPose.POLE_R].lerp(Vector3(0.6, -0.8, 0.3), k)
			p.v[RigPose.HEAD_ROT].x -= 0.18 * k
			p.v[RigPose.NECK_ROT].x -= 0.10 * k
			p.v[RigPose.ARM_L] = p.v[RigPose.ARM_L].lerp(Vector3(-0.07, -0.30, -0.24), k)
			p.v[RigPose.POLE_L] = p.v[RigPose.POLE_L].lerp(Vector3(-0.3, -1.0, 0.1), k)


## Weapon hold / guard: blends the swinging arm targets towards the carry (low ready) or aim pose.
func _gen_hold(p: RigPose, aw: float, hr: float, hl: float, cl: float, ch: float, runw: float) -> void:
	var melee := weapon == &"none" or weapon == &"melee_knife" or weapon == &"melee_bat" or weapon == &"thrown"
	# aim frame in chest space
	var cb := _chest_basis(p)
	var a_model := Basis.from_euler(Vector3(clampf(aim_pitch, -1.2, 1.2), clampf(aim_yaw, -1.2, 1.2), 0.0)) * Vector3(0, 0, -1)
	var fwd := (cb.transposed() * a_model).normalized()
	var up_c := cb.transposed() * Vector3.UP
	var right := fwd.cross(up_c)
	if right.length() < 0.05:
		right = Vector3.RIGHT
	right = right.normalized()
	var upv := right.cross(fwd).normalized()
	var ar: Vector3 = _hold[4]
	var al: Vector3 = _hold[5]
	var aim_r := fwd * ar.x + right * ar.y + upv * ar.z
	var aim_l := fwd * al.x + right * al.y + upv * al.z
	# carry (low ready) positions; sprinting tucks the weapon in, covers hold it at the chest muzzle-up
	var carry_r: Vector3 = _hold[0]
	var cdir_r: Vector3 = _hold[1]
	var carry_l: Vector3 = _hold[2]
	var cdir_l: Vector3 = _hold[3]
	var cover := maxf(cl, ch)
	if cover > 0.01:
		carry_r = carry_r.lerp(Vector3(0.17, -0.22, -0.20), cover)
		cdir_r = cdir_r.lerp(Vector3(0.38, 0.8, -0.45), cover)
		carry_l = carry_l.lerp(Vector3(0.0, -0.20, -0.36), cover)
		cdir_l = cdir_l.lerp(Vector3(0.3, 0.7, -0.6), cover)
	var spr := _sp_sprint.x
	if spr > 0.01:
		carry_r = carry_r.lerp(Vector3(0.20, -0.30, -0.14), spr)
		carry_l = carry_l.lerp(Vector3(-0.02, -0.30, -0.34), spr)
	var hold_w_r := hr
	var hold_w_l := hl
	# melee / fists: aiming raises the guard even without a weapon
	if melee and aw > 0.01:
		hold_w_r = maxf(hold_w_r, aw)
		hold_w_l = maxf(hold_w_l, aw)
	if hold_w_r < 0.005 and hold_w_l < 0.005:
		return
	for side in 2:
		var is_r := side == 0
		var w := hold_w_r if is_r else hold_w_l
		if w < 0.005:
			continue
		var cpos := carry_r if is_r else carry_l
		var cdir := cdir_r if is_r else cdir_l
		var apos := aim_r if is_r else aim_l
		var adir := fwd
		if not is_r:
			adir = (fwd + right * 0.25).normalized()
			if has_support_grip and not melee:
				adir = (fwd + right * 0.3 - upv * 0.2).normalized()
		var pos := cpos.lerp(apos, aw)
		var hd := cdir.normalized().lerp(adir, aw).normalized()
		var hup := Vector3.UP
		if absf(hd.y) > 0.9:
			hup = Vector3(0, 0, -1) * signf(-hd.y)
		var carry_up := (hup - hd * hup.dot(hd)).normalized()
		var hu := carry_up.lerp(upv, aw).normalized()
		if melee and weapon == &"none":
			hd = hd.lerp(fwd, 0.5).normalized()
		# left hand of a two-handed weapon sits on the forend (exact when the weapon provides Grip_L)
		var i_pos := RigPose.ARM_R + side
		p.v[i_pos] = p.v[i_pos].lerp(pos, w)
		p.v[RigPose.HDIR_R + side] = hd
		p.v[RigPose.HUP_R + side] = hu
		p.f[RigPose.F_HOVR_R + side] = w
		if side == 1 and has_support_grip and not melee:
			p.f[RigPose.F_SUPPORT] = w
		# elbows: down and slightly out while holding
		var sx := 1.0 if is_r else -1.0
		p.v[RigPose.POLE_R + side] = p.v[RigPose.POLE_R + side].lerp(Vector3(sx * 0.45, -0.85, 0.25), w)


func _gen_swim(p: RigPose, underwater: bool) -> void:
	var v := _sp_speed.x
	var amt := smoothstep(0.15, 1.6, v)
	var pitch_move := _sp_pitch.x
	var body_pitch := lerpf(-0.12, -1.38, amt)
	if underwater:
		body_pitch = lerpf(-0.35, -1.42, amt) + pitch_move * 0.55
	var ph := _swim_phase
	var tau_ph := TAU * ph
	var rest_h := solver.rest_head[RigSolver.HIPS]
	var hips_pos := Vector3(0, lerpf(-0.30, -0.80, amt), lerpf(0.0, 0.08, amt))
	if underwater:
		hips_pos = Vector3(0, lerpf(-0.10, -0.55, amt), 0.0)
	var roll := 0.18 * sin(tau_ph) * amt * (0.6 if underwater else 1.0)
	p.v[RigPose.HIPS_POS] = hips_pos
	p.v[RigPose.HIPS_ROT] = Vector3(body_pitch, 0.0, roll)
	var hb := Basis.from_euler(p.v[RigPose.HIPS_ROT])
	p.v[RigPose.SPINE_ROT] = Vector3(0.10 * amt, 0.0, 0.0)
	p.v[RigPose.CHEST_ROT] = Vector3(0.14 * amt, 0.0, -roll * 0.5)
	p.v[RigPose.NECK_ROT] = Vector3(lerpf(0.0, 0.55, amt), 0.0, 0.0)
	p.v[RigPose.HEAD_ROT] = Vector3(lerpf(0.0, 0.50, amt) - (0.0 if not underwater else 0.25 * amt), 0.28 * sin(tau_ph) * amt * (0.0 if underwater else 1.0), roll * 0.3)
	p.f[RigPose.F_GROUND] = 0.0
	# arms: crawl stroke (chest space; y = towards the head, z+ = back = up when prone) / treading water scull
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var a := fposmod(ph + 0.5 * side, 1.0)
		var stroke := Vector3.ZERO
		if underwater:
			# slow breast-stroke style glide
			var k := 0.5 - 0.5 * cos(tau_ph)
			stroke = Vector3(sx * lerpf(0.30, 0.17, k), lerpf(0.55, 0.05, k), lerpf(-0.12, -0.24, k))
		elif a < 0.5:
			var k := a / 0.5                                       # pull under the body
			stroke = Vector3(sx * lerpf(0.20, 0.17, k), lerpf(0.55, -0.12, k), lerpf(-0.25, -0.45, sin(k * PI * 0.5)))
		else:
			var k := (a - 0.5) / 0.5                               # recovery above the surface
			var arc := sin(k * PI)
			stroke = Vector3(sx * (0.17 + 0.22 * arc), lerpf(-0.12, 0.55, k), -0.40 + 0.72 * arc)
		var tread := Vector3(sx * (0.30 + 0.06 * sin(tau_ph * 2.0 + side)), -0.30 + 0.05 * cos(tau_ph * 2.0 + side), -0.20)
		p.v[RigPose.ARM_R + side] = tread.lerp(stroke, amt)
		p.v[RigPose.POLE_R + side] = Vector3(sx * 0.7, -0.5, 0.6)
	# legs: flutter kick, expressed in the hips frame (legs trail behind along the body axis)
	var hp := rest_h + hips_pos
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var kick := sin(tau_ph * 3.0 + PI * side)
		var local := Vector3(sx * 0.09, -0.80 + 0.04 * (1.0 - amt), -0.10 * amt * kick - 0.08 * (1.0 - amt))
		# treading: bicycle kick (knees up)
		var tr := Vector3(sx * 0.11, -0.62 + 0.14 * sin(tau_ph * 2.0 + PI * side), -0.26 + 0.14 * cos(tau_ph * 2.0 + PI * side))
		local = tr.lerp(local, amt)
		p.v[RigPose.LEG_R + side] = hp + hb * local
		p.v[RigPose.KNEE_R + side] = hb * Vector3(sx * 0.1, 0.0, -1.0)
		p.v[RigPose.FOOT_R + side] = Vector3(-0.6 * amt, -sx * 0.1, 0.0)


func _gen_sit_car(p: RigPose) -> void:
	var driver := seat_role == &"driver"
	var steer := _sp_steer.x
	var so := seat_offset
	p.v[RigPose.HIPS_POS] = Vector3(0, -0.865, 0) + so
	p.v[RigPose.HIPS_ROT] = Vector3(0.02, 0, 0)
	p.v[RigPose.SPINE_ROT] = Vector3(0.05, 0, 0)
	p.v[RigPose.CHEST_ROT] = Vector3(0.04 + 0.01 * sin(_t * 1.5), 0.0, 0.0)
	p.v[RigPose.NECK_ROT] = Vector3(-0.05, 0, 0)
	p.v[RigPose.HEAD_ROT] = Vector3(-0.02, -steer * 0.12, 0)
	p.f[RigPose.F_GROUND] = 0.0
	var hips_y := 0.95 - 0.865 + so.y
	# legs: thighs forward, shins down to the pedals
	var pedal := 0.0
	var ft_r := Vector3(0.12, hips_y - 0.34, -0.62 + so.z)
	var ft_l := Vector3(-0.15, hips_y - 0.28, -0.52 + so.z)
	if not driver:
		ft_r = Vector3(0.13, hips_y - 0.36, -0.54 + so.z)
		ft_l = Vector3(-0.13, hips_y - 0.36, -0.54 + so.z)
	ft_r.x += so.x
	ft_l.x += so.x
	p.v[RigPose.LEG_R] = ft_r
	p.v[RigPose.LEG_L] = ft_l
	p.v[RigPose.KNEE_R] = Vector3(0.15, 0.55, -1.0)
	p.v[RigPose.KNEE_L] = Vector3(-0.15, 0.55, -1.0)
	p.v[RigPose.FOOT_R] = Vector3(-0.55, -0.15, 0)
	p.v[RigPose.FOOT_L] = Vector3(-0.35, 0.15, 0)
	var _pd := pedal
	if driver:
		# hands on the wheel: centre ahead of the chest, rotated by steering
		var centre := Vector3(0.0, -0.23, -0.45)
		var axis := Vector3(0, 0.38, -0.93).normalized()
		var wup := Vector3(0, 0.93, 0.38).normalized()
		var wright := Vector3.RIGHT
		var radius := 0.18
		var ang := steer * 1.9                                           # up to ~110 degrees of hand travel
		for side in 2:
			var sx := 1.0 if side == 0 else -1.0
			var a := sx * 0.95 + ang                                      # clock position of the hand on the rim
			var pos := centre + wright * (sin(a) * radius) + wup * (cos(a) * radius)
			p.v[RigPose.ARM_R + side] = pos
			p.v[RigPose.POLE_R + side] = Vector3(sx * 0.7, -0.8, 0.3)
			p.v[RigPose.HDIR_R + side] = Vector3(sx * -0.2, 0.0, -1.0).normalized()
			p.v[RigPose.HUP_R + side] = Vector3(sx * -0.4, 1.0, 0.0).normalized()
			p.f[RigPose.F_HOVR_R + side] = 1.0
	else:
		# passenger: hands resting on the thighs
		for side in 2:
			var sx := 1.0 if side == 0 else -1.0
			p.v[RigPose.ARM_R + side] = Vector3(sx * 0.17, -0.52, -0.30)
			p.v[RigPose.POLE_R + side] = Vector3(sx * 0.8, -0.5, 0.6)
			p.f[RigPose.F_HOVR_R + side] = 0.0
	if aim_on and weapon != &"none":
		# drive-by: right hand out with the weapon (very simple)
		var tab := HOLD.get(weapon, HOLD[&"pistol"]) as Array
		p.v[RigPose.ARM_R] = Vector3(0.28, 0.02, -0.45)
		p.v[RigPose.HDIR_R] = Vector3(0.7, 0.0, -0.7).normalized()
		p.v[RigPose.HUP_R] = Vector3.UP
		p.f[RigPose.F_HOVR_R] = 1.0
		var _t2 := tab


func _gen_sit_bike(p: RigPose) -> void:
	var steer := _sp_steer.x
	var roll := _sp_roll.x
	var bicycle := ride_style == &"bicycle"
	var so := seat_offset
	p.v[RigPose.HIPS_POS] = Vector3(0, -0.88, 0.0) + so
	p.v[RigPose.HIPS_ROT] = Vector3(-0.05 if not bicycle else -0.2, 0.0, roll * 0.4)
	p.v[RigPose.SPINE_ROT] = Vector3(-0.30 if not bicycle else -0.38, 0.0, roll * 0.3)
	p.v[RigPose.CHEST_ROT] = Vector3(-0.25 if not bicycle else -0.30, 0.0, roll * 0.2)
	p.v[RigPose.NECK_ROT] = Vector3(0.38, 0, -roll * 0.3)
	p.v[RigPose.HEAD_ROT] = Vector3(0.28, -steer * 0.2, -roll * 0.35)
	p.f[RigPose.F_GROUND] = 0.0
	var hips_y := 0.07 + so.y
	# legs: straddle, feet on pegs (motorcycle) or pedals (bicycle)
	if bicycle:
		for side in 2:
			var a := TAU * fposmod(_pedal_phase + 0.5 * side, 1.0)
			var sx := 1.0 if side == 0 else -1.0
			p.v[RigPose.LEG_R + side] = Vector3(sx * 0.14, hips_y - 0.42 + 0.17 * cos(a) * -1.0, -0.12 - 0.17 * sin(a))
			p.v[RigPose.KNEE_R + side] = Vector3(sx * 0.35, 0.3, -1.0)
			p.v[RigPose.FOOT_R + side] = Vector3(-0.1 + 0.2 * sin(a), 0.0, 0.0)
	else:
		for side in 2:
			var sx := 1.0 if side == 0 else -1.0
			p.v[RigPose.LEG_R + side] = Vector3(sx * 0.19, hips_y - 0.43, -0.12)
			p.v[RigPose.KNEE_R + side] = Vector3(sx * 0.7, 0.2, -1.0)
			p.v[RigPose.FOOT_R + side] = Vector3(-0.15, -sx * 0.1, 0.0)
	# hands on the handlebars (model space, converted to chest space so the forward lean does not drag them to the floor)
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var bar := Vector3(sx * 0.33, 0.40, -0.52) if not bicycle else Vector3(sx * 0.22, 0.34, -0.47)
		bar.x += steer * 0.07
		bar.z += -sx * steer * 0.05
		bar += so
		p.v[RigPose.ARM_R + side] = _to_chest(p, bar)
		p.v[RigPose.POLE_R + side] = Vector3(sx * 0.9, -0.5, 0.2)
		p.v[RigPose.HDIR_R + side] = _dir_to_chest(p, Vector3(-sx * 0.22, -0.25, -1.0))
		p.v[RigPose.HUP_R + side] = _dir_to_chest(p, Vector3(-sx * 0.3, 1.0, -0.1))
		p.f[RigPose.F_HOVR_R + side] = 1.0


func _gen_ladder(p: RigPose) -> void:
	var ph := _ladder_phase
	var up_lean := 0.0
	p.v[RigPose.HIPS_POS] = Vector3(0, -0.04 + 0.02 * sin(TAU * ph), -0.02)
	p.v[RigPose.HIPS_ROT] = Vector3(-0.08, 0.0, 0.05 * sin(TAU * ph))
	p.v[RigPose.SPINE_ROT] = Vector3(-0.10, 0.0, 0.0)
	p.v[RigPose.CHEST_ROT] = Vector3(-0.05, 0.12 * sin(TAU * ph), 0.0)
	p.v[RigPose.NECK_ROT] = Vector3(0.28, 0.0, 0.0)
	p.v[RigPose.HEAD_ROT] = Vector3(0.15, 0.0, 0.0)
	p.f[RigPose.F_GROUND] = 0.0
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		# diagonal pattern: right hand with left foot
		var hphase := fposmod(ph + 0.5 * side, 1.0)
		var fphase := fposmod(ph + 0.5 * (1 - side), 1.0)
		# hands: rung height cycles 0.0 (low) .. 0.42 (high); quick lift in the second half
		var hy := _ladder_cycle(hphase)
		p.v[RigPose.ARM_R + side] = Vector3(sx * 0.21, 0.02 + 1.0 * hy, -0.32 - 0.05 * sin(hphase * PI))
		p.v[RigPose.POLE_R + side] = Vector3(sx * 0.9, -0.6, 0.3)
		p.v[RigPose.HDIR_R + side] = Vector3(0, 1.0, -0.2).normalized()
		p.v[RigPose.HUP_R + side] = Vector3(0, 0.2, -1.0).normalized()
		p.f[RigPose.F_HOVR_R + side] = 1.0
		var fy := _ladder_cycle(fphase)
		p.v[RigPose.LEG_R + side] = Vector3(sx * 0.13, 0.14 + 1.0 * fy, -0.22 - 0.03 * sin(fphase * PI))
		p.v[RigPose.KNEE_R + side] = Vector3(sx * 0.4, 0.0, -1.0)
		p.v[RigPose.FOOT_R + side] = Vector3(0.65, -sx * 0.1, 0.0)
	var _ul := up_lean


## Limb height relative to the body over one climbing cycle (0..0.3 m): supported (pulled down) for half a cycle, then lifted.
static func _ladder_cycle(u: float) -> float:
	if u < 0.5:
		return 0.3 * (1.0 - 2.0 * u)
	return 0.3 * smoothstep(0.5, 1.0, u)


func _gen_para(p: RigPose) -> void:
	var steer := _sp_steer.x
	var sw := sin(_t * 0.9)
	p.v[RigPose.HIPS_POS] = Vector3(0, -0.02, 0.0)
	p.v[RigPose.HIPS_ROT] = Vector3(0.08, 0.0, 0.05 * sw + steer * 0.1)
	p.v[RigPose.SPINE_ROT] = Vector3(-0.05, 0, 0)
	p.v[RigPose.CHEST_ROT] = Vector3(-0.06, 0, 0.0)
	p.v[RigPose.NECK_ROT] = Vector3(0.1, 0, 0)
	p.v[RigPose.HEAD_ROT] = Vector3(0.1, steer * 0.2, 0)
	p.f[RigPose.F_GROUND] = 0.0
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var pull := clampf(sx * steer, 0.0, 1.0)                # pulling the line on the steering side
		p.v[RigPose.ARM_R + side] = Vector3(sx * 0.22, 0.52 - 0.22 * pull, -0.06)
		p.v[RigPose.POLE_R + side] = Vector3(sx * 0.9, -0.3, 0.4)
		p.v[RigPose.HDIR_R + side] = Vector3(0, 1.0, 0.0)
		p.v[RigPose.HUP_R + side] = Vector3(0, 0.0, -1.0)
		p.f[RigPose.F_HOVR_R + side] = 1.0
		p.v[RigPose.LEG_R + side] = Vector3(sx * 0.11, 0.17 + 0.03 * sw * sx, -0.14 + 0.02 * sw)
		p.v[RigPose.KNEE_R + side] = Vector3(sx * 0.1, 0.0, -1.0)
		p.v[RigPose.FOOT_R + side] = Vector3(-0.5, -sx * 0.08, 0.0)


func _gen_dead(p: RigPose) -> void:
	var face_down := dead_face_down
	var pitch := -1.50 if face_down else 1.50
	var hips_pos := Vector3(0, -0.95 + 0.115, 0.0)
	p.v[RigPose.HIPS_POS] = hips_pos
	p.v[RigPose.HIPS_ROT] = Vector3(pitch, 0.0, 0.0)
	var hb := Basis.from_euler(p.v[RigPose.HIPS_ROT])
	p.f[RigPose.F_GROUND] = 0.0
	if face_down:
		p.v[RigPose.SPINE_ROT] = Vector3(0.06, 0.0, 0.0)
		p.v[RigPose.CHEST_ROT] = Vector3(0.08, 0.0, 0.0)
		p.v[RigPose.NECK_ROT] = Vector3(0.0, 0.0, 0.0)
		p.v[RigPose.HEAD_ROT] = Vector3(0.1, 0.9, 0.0)           # face turned to the side
	else:
		p.v[RigPose.SPINE_ROT] = Vector3(-0.06, 0.0, 0.0)
		p.v[RigPose.CHEST_ROT] = Vector3(-0.06, 0.0, 0.0)
		p.v[RigPose.NECK_ROT] = Vector3(-0.1, 0.0, 0.0)
		p.v[RigPose.HEAD_ROT] = Vector3(-0.1, 0.35, 0.1)
	var rest_h := solver.rest_head[RigSolver.HIPS]
	var hp := rest_h + hips_pos
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		# legs: splayed, one knee slightly bent
		var local := Vector3(sx * (0.16 if side == 0 else 0.20), -0.78, 0.02)
		p.v[RigPose.LEG_R + side] = hp + hb * local
		p.v[RigPose.KNEE_R + side] = hb * Vector3(sx * 0.4, 0.0, -1.0)
		p.v[RigPose.FOOT_R + side] = Vector3(0.0 if face_down else -0.15, -sx * 0.3, 0.0)
		# arms: out at the sides (chest space; supine -> arms lie along +-x)
		var apos := Vector3(sx * (0.52 if side == 0 else 0.40), -0.22 if side == 0 else -0.40, 0.12 if not face_down else -0.1)
		p.v[RigPose.ARM_R + side] = apos
		p.v[RigPose.POLE_R + side] = Vector3(0, 0, 1.0)


func _gen_air(p: RigPose) -> void:
	var rising := air_vy > 0.5
	var t := _air_t
	var tuck := 0.0
	var stretch := 0.0
	if rising:
		tuck = smoothstep(0.0, 0.25, t) * clampf(air_vy / 4.0, 0.4, 1.0)
	else:
		tuck = 0.45 * (1.0 - smoothstep(0.0, 0.5, -air_vy / 6.0))
		stretch = smoothstep(0.5, 6.0, -air_vy)
	p.f[RigPose.F_GROUND] = 0.0
	p.v[RigPose.HIPS_POS] = Vector3(0, -0.05 - 0.1 * tuck, 0.0)
	p.v[RigPose.HIPS_ROT] = Vector3(-0.05 * stretch, 0, 0.0)
	p.v[RigPose.SPINE_ROT] = Vector3(-0.10 * tuck, 0, 0)
	p.v[RigPose.CHEST_ROT] = Vector3(-0.05, 0, 0)
	p.v[RigPose.NECK_ROT] = Vector3(0.05, 0, 0)
	p.v[RigPose.HEAD_ROT] = Vector3(0.05, 0, 0)
	var flail := sin(_t * 9.0) * stretch
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var s2 := sx * flail
		# legs: knees up when rising, reaching down + apart when falling
		var knee_up := 0.34 * tuck
		p.v[RigPose.LEG_R + side] = Vector3(sx * (0.13 + 0.05 * stretch), 0.14 + knee_up + 0.0 * s2, -0.12 - 0.22 * tuck - 0.05 * stretch * (1 if side == 0 else -1))
		p.v[RigPose.KNEE_R + side] = Vector3(sx * 0.2, 0.0, -1.0)
		p.v[RigPose.FOOT_R + side] = Vector3(0.3 * tuck, -sx * 0.12, 0.0)
		# arms out for balance
		var spread := 0.45 + 0.25 * stretch
		p.v[RigPose.ARM_R + side] = Vector3(sx * spread, -0.12 + 0.35 * stretch + 0.06 * s2, -0.12 - 0.1 * tuck)
		p.v[RigPose.POLE_R + side] = Vector3(sx * 0.8, -0.6, 0.4)
	if weapon != &"none" and _sp_hold_r.x > 0.1:
		_gen_hold(p, _sp_aim.x, _sp_hold_r.x, _sp_hold_l.x, 0.0, 0.0, 0.0)


# ===================================================================================================================
# Overlays: actions, flinch, landing
# ===================================================================================================================
func _apply_overlays(p: RigPose, dt: float) -> void:
	if _land_t < 0.5:
		var u := _land_t / 0.5
		var e := sin(PI * minf(u * 1.2, 1.0)) * (1.0 - smoothstep(0.6, 1.0, u)) * _land_amt
		p.v[RigPose.HIPS_POS].y -= 0.19 * e
		p.v[RigPose.HIPS_POS].z += 0.06 * e
		p.v[RigPose.SPINE_ROT].x -= 0.28 * e
		p.v[RigPose.HEAD_ROT].x += 0.2 * e
		for side in 2:
			p.v[RigPose.ARM_R + side].y += 0.1 * e
			p.v[RigPose.ARM_R + side].x += (0.1 if side == 0 else -0.1) * e
	if _flinch_t < 0.4:
		var u := _flinch_t / 0.4
		var e := sin(PI * pow(u, 0.6)) * (1.0 - u * 0.3) * _flinch_amt
		# direction the body is pushed (x right, z back): a push towards +z leans the torso back
		var push := _flinch_dir
		p.v[RigPose.HIPS_POS] += Vector3(push.x * 0.05, -0.02, push.z * 0.05) * e
		p.v[RigPose.SPINE_ROT].x += 0.20 * push.z * e
		p.v[RigPose.CHEST_ROT].x += 0.20 * push.z * e
		p.v[RigPose.CHEST_ROT].z += -0.25 * push.x * e
		p.v[RigPose.CHEST_ROT].y += 0.18 * push.x * e
		p.v[RigPose.HEAD_ROT].x += 0.38 * push.z * e
		p.v[RigPose.HEAD_ROT].z += -0.2 * push.x * e
		for side in 2:
			p.v[RigPose.ARM_R + side] += Vector3(0.0, 0.06, push.z * 0.12) * e
	if _act == &"":
		return
	var u := clampf(_act_t / _act_dur, 0.0, 1.0)
	match _act:
		&"punch":
			_ov_punch(p, u)
		&"kick":
			_ov_kick(p, u)
		&"melee_swing":
			if weapon == &"melee_bat":
				_ov_bat(p, u)
			elif weapon == &"melee_knife":
				_ov_knife(p, u)
			else:
				_ov_punch(p, u)
		&"reload":
			_ov_reload(p, u)
		&"throw":
			_ov_throw(p, u)
		&"enter_vehicle":
			_ov_enter(p, u)
		&"exit_vehicle":
			_ov_exit(p, u)


static func _env(u: float, a: float, b: float) -> float:
	return smoothstep(0.0, a, u) * (1.0 - smoothstep(b, 1.0, u))


func _ov_blend_arm(p: RigPose, side: int, pos: Vector3, dir: Vector3, up: Vector3, w: float, pole: Vector3 = Vector3.ZERO) -> void:
	var i := RigPose.ARM_R + side
	p.v[i] = p.v[i].lerp(pos, w)
	p.v[RigPose.HDIR_R + side] = p.v[RigPose.HDIR_R + side].lerp(dir.normalized(), w) if p.f[RigPose.F_HOVR_R + side] > 0.01 else dir.normalized()
	p.v[RigPose.HUP_R + side] = p.v[RigPose.HUP_R + side].lerp(up.normalized(), w) if p.f[RigPose.F_HOVR_R + side] > 0.01 else up.normalized()
	p.f[RigPose.F_HOVR_R + side] = lerpf(p.f[RigPose.F_HOVR_R + side], 1.0, w)
	if pole != Vector3.ZERO:
		p.v[RigPose.POLE_R + side] = p.v[RigPose.POLE_R + side].lerp(pole, w)


func _ov_punch(p: RigPose, u: float) -> void:
	var side := _act_side
	var other := 1 - side
	var sx := 1.0 if side == 0 else -1.0
	var x := 0.0
	if u < 0.15:
		x = -0.25 * smoothstep(0.0, 0.15, u)
	elif u < 0.40:
		x = lerpf(-0.25, 1.0, smoothstep(0.15, 0.40, u))
	elif u < 0.52:
		x = 1.0
	else:
		x = 1.0 - smoothstep(0.52, 1.0, u)
	var w := _env(u, 0.3, 0.6)
	# torso twist first (a right punch turns the torso left, a left punch right), so the targets below follow it
	var tw := x * sx * w
	p.v[RigPose.CHEST_ROT].y += 0.30 * tw
	p.v[RigPose.SPINE_ROT].y += 0.15 * tw
	p.v[RigPose.HIPS_ROT].y += 0.10 * tw
	p.v[RigPose.HIPS_POS].z -= 0.10 * x * w
	p.v[RigPose.HIPS_POS].y -= 0.03 * x * w
	p.v[RigPose.CHEST_ROT].x -= 0.08 * x * w
	# targets are offsets from the neck base along the BODY axes (not the twisted chest axes)
	var guard := Vector3(sx * 0.16, -0.07, -0.26)
	var strike := Vector3(sx * 0.09, -0.07, -0.66)
	var off := guard.lerp(strike, x)
	var fist_dir := Vector3(0, 0, -1).lerp(Vector3(sx * -0.2, 0.3, -1), 1.0 - x)
	_ov_blend_arm(p, side, _off_to_chest(p, off), _dir_to_chest(p, fist_dir), _dir_to_chest(p, Vector3(sx * 0.3, 1.0, 0.0)), w, Vector3(sx * 0.7, -0.7, 0.3))
	_ov_blend_arm(p, other, _off_to_chest(p, Vector3(-sx * 0.15, -0.08, -0.25)), _dir_to_chest(p, Vector3(sx * 0.3, 0.2, -1)), _dir_to_chest(p, Vector3(-sx * 0.3, 1.0, 0.0)), w * 0.9, Vector3(-sx * 0.7, -0.7, 0.3))


func _ov_kick(p: RigPose, u: float) -> void:
	# right leg front kick
	var e := _env(u, 0.35, 0.75)
	var ext := smoothstep(0.25, 0.5, u) * (1.0 - smoothstep(0.55, 0.85, u))
	var tgt := Vector3(0.13, 0.72, -0.34 - 0.30 * ext)
	p.v[RigPose.LEG_R] = p.v[RigPose.LEG_R].lerp(tgt, e)
	p.v[RigPose.FOOT_R] = p.v[RigPose.FOOT_R].lerp(Vector3(-0.5 + 0.8 * ext, -0.1, 0), e)
	p.v[RigPose.KNEE_R] = p.v[RigPose.KNEE_R].lerp(Vector3(0.1, 0.9, -1.0), e)
	p.v[RigPose.HIPS_ROT].x += 0.20 * e
	p.v[RigPose.SPINE_ROT].x += 0.15 * e
	p.v[RigPose.HIPS_POS].y -= 0.03 * e
	p.v[RigPose.HIPS_POS].z += 0.06 * e
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		_ov_blend_arm(p, side, Vector3(sx * 0.46, -0.12, -0.12), Vector3(sx, 0, -0.3), Vector3(0, 1, 0), e * 0.8, Vector3(sx * 0.8, -0.5, 0.5))


func _ov_bat(p: RigPose, u: float) -> void:
	var w := _env(u, 0.25, 0.7)
	# swing angle from forward towards the right: windup +75deg (right/back) -> through the front to -60deg (left)
	var th := 0.0
	if u < 0.32:
		th = lerpf(0.0, 1.35, smoothstep(0.0, 0.32, u))
	elif u < 0.56:
		th = lerpf(1.35, -1.1, smoothstep(0.32, 0.56, u))
	else:
		th = lerpf(-1.1, 0.0, smoothstep(0.56, 1.0, u))
	# torso follows the swing (turns right during the windup), applied first so the hand targets can be body-axis based
	var tw := th * 0.40
	p.v[RigPose.CHEST_ROT].y += -tw * w * 0.5
	p.v[RigPose.SPINE_ROT].y += -tw * w * 0.3
	p.v[RigPose.HIPS_ROT].y += -tw * w * 0.2
	p.v[RigPose.HIPS_POS].y -= 0.04 * w
	p.v[RigPose.CHEST_ROT].x -= 0.1 * w
	p.v[RigPose.HEAD_ROT].y += tw * w * 0.6
	var hy := lerpf(0.0, -0.18, smoothstep(0.32, 0.56, u))
	var rad := Vector3(sin(th), 0.0, -cos(th))
	var off_r := Vector3(rad.x * 0.40 + 0.10, hy, rad.z * 0.40 - 0.03)
	var off_l := Vector3(rad.x * 0.30 + 0.10, hy - 0.05, rad.z * 0.30 - 0.03)
	var hdir := Vector3(rad.x, 0.22 + 0.5 * (1.0 - smoothstep(0.32, 0.56, u)) * smoothstep(0.0, 0.32, u), rad.z).normalized()
	var up := _dir_to_chest(p, Vector3.UP)
	_ov_blend_arm(p, 0, _off_to_chest(p, off_r), _dir_to_chest(p, hdir), up, w, Vector3(0.6, -0.6, 0.7))
	_ov_blend_arm(p, 1, _off_to_chest(p, off_l), _dir_to_chest(p, hdir), up, w, Vector3(-0.6, -0.6, 0.7))


func _ov_knife(p: RigPose, u: float) -> void:
	var w := _env(u, 0.3, 0.55)
	var x := 0.0
	if u < 0.2:
		x = -0.3 * smoothstep(0.0, 0.2, u)
	elif u < 0.4:
		x = lerpf(-0.3, 1.0, smoothstep(0.2, 0.4, u))
	elif u < 0.55:
		x = 1.0
	else:
		x = 1.0 - smoothstep(0.55, 1.0, u)
	p.v[RigPose.CHEST_ROT].y += 0.22 * x * w
	p.v[RigPose.HIPS_ROT].y += 0.12 * x * w
	p.v[RigPose.HIPS_POS].z -= 0.12 * x * w
	p.v[RigPose.CHEST_ROT].x -= 0.12 * x * w
	var off := Vector3(0.22, -0.34, -0.18).lerp(Vector3(0.10, -0.12, -0.62), x)
	_ov_blend_arm(p, 0, _off_to_chest(p, off), _dir_to_chest(p, Vector3(0.0, -0.15, -1.0).lerp(Vector3(0, -0.5, -0.8), 1.0 - x)), _dir_to_chest(p, Vector3.UP), w, Vector3(0.6, -0.8, 0.3))
	_ov_blend_arm(p, 1, _off_to_chest(p, Vector3(-0.2, -0.22, -0.24)), _dir_to_chest(p, Vector3(0.3, 0.1, -1)), _dir_to_chest(p, Vector3.UP), w * 0.8, Vector3(-0.7, -0.7, 0.3))


func _ov_reload(p: RigPose, u: float) -> void:
	var w := _env(u, 0.14, 0.88)
	var two_h: bool = _sp_two.x > 0.5
	var mag_cycles := 3.0 if weapon == &"shotgun" else 1.0
	var pos_r := Vector3(0.14, -0.20, -0.30)
	var pos_l := Vector3(0.0, -0.30, -0.30)
	if two_h:
		pos_r = Vector3(0.17, -0.18, -0.26)
		pos_l = Vector3(0.0, -0.28, -0.42)
	var k := sin(u * PI * mag_cycles)
	if weapon == &"shotgun":
		pos_l.z -= 0.12 * absf(k)
	else:
		# left hand dips to the magazine, pulls, pushes back
		var dip := smoothstep(0.2, 0.42, u) * (1.0 - smoothstep(0.42, 0.55, u)) + smoothstep(0.55, 0.7, u) * (1.0 - smoothstep(0.7, 0.82, u))
		pos_l.y -= 0.22 * dip
		pos_l.x += 0.05 * dip
	var dir_r := Vector3(0.0, 0.55, -0.83)
	_ov_blend_arm(p, 0, pos_r, dir_r, Vector3(0.2, 0.2, 1.0).normalized() if false else Vector3.UP.lerp(Vector3(-0.3, 0.7, 0.6), 0.6), w, Vector3(0.5, -0.85, 0.3))
	_ov_blend_arm(p, 1, pos_l, Vector3(0.2, 0.2, -1.0), Vector3.UP, w, Vector3(-0.5, -0.85, 0.3))
	p.v[RigPose.HEAD_ROT].x -= 0.18 * w
	p.v[RigPose.NECK_ROT].x -= 0.1 * w
	p.v[RigPose.CHEST_ROT].x -= 0.06 * w


func _ov_throw(p: RigPose, u: float) -> void:
	var w := _env(u, 0.3, 0.6)
	var off := Vector3.ZERO
	var tw := 0.0
	if u < 0.4:
		var k := smoothstep(0.0, 0.4, u)
		off = Vector3(0.28, -0.10, -0.05).lerp(Vector3(0.34, 0.40, 0.30), k)
		tw = -0.45 * k
	elif u < 0.58:
		var k := smoothstep(0.4, 0.58, u)
		off = Vector3(0.34, 0.40, 0.30).lerp(Vector3(0.12, 0.22, -0.64), k)
		tw = lerpf(-0.45, 0.40, k)
	else:
		var k := smoothstep(0.58, 1.0, u)
		off = Vector3(0.12, 0.22, -0.64).lerp(Vector3(0.20, -0.30, -0.30), k)
		tw = lerpf(0.40, 0.0, k)
	p.v[RigPose.CHEST_ROT].y += tw * w * 0.55
	p.v[RigPose.SPINE_ROT].y += tw * w * 0.3
	p.v[RigPose.HIPS_ROT].y += tw * w * 0.15
	p.v[RigPose.CHEST_ROT].x -= 0.1 * w * sin(PI * u)
	p.v[RigPose.HIPS_POS].y -= 0.03 * w
	var rel := Vector3(0.0, 0.2, -1.0).lerp(Vector3(0, 0.9, 0.3), 1.0 - smoothstep(0.4, 0.58, u))
	_ov_blend_arm(p, 0, _off_to_chest(p, off), _dir_to_chest(p, rel), _dir_to_chest(p, Vector3.UP), w, Vector3(0.9, -0.4, 0.6))
	var loff := Vector3(-0.15, 0.05, -0.50).lerp(Vector3(-0.22, -0.2, -0.2), smoothstep(0.5, 1.0, u))
	_ov_blend_arm(p, 1, _off_to_chest(p, loff), _dir_to_chest(p, Vector3(0, 0, -1)), _dir_to_chest(p, Vector3.UP), w * 0.8, Vector3(-0.8, -0.5, 0.4))


func _ov_enter(p: RigPose, u: float) -> void:
	var w := _env(u, 0.25, 0.8)
	p.v[RigPose.HIPS_ROT].x -= 0.28 * w
	p.v[RigPose.SPINE_ROT].x -= 0.35 * w
	p.v[RigPose.HEAD_ROT].x += 0.2 * w
	p.v[RigPose.HIPS_POS].y -= 0.10 * w
	_ov_blend_arm(p, 0, Vector3(0.22, -0.18, -0.52), Vector3(0, -0.2, -1), Vector3.UP, w, Vector3(0.6, -0.7, 0.4))


func _ov_exit(p: RigPose, u: float) -> void:
	var w := _env(u, 0.35, 0.6)
	p.v[RigPose.HIPS_ROT].x -= 0.22 * w
	p.v[RigPose.SPINE_ROT].x -= 0.28 * w
	p.v[RigPose.HIPS_POS].y -= 0.07 * w
	_ov_blend_arm(p, 0, Vector3(0.36, -0.30, -0.30), Vector3(0.3, -0.5, -1), Vector3.UP, w, Vector3(0.8, -0.5, 0.4))


# ===================================================================================================================
# Look at
# ===================================================================================================================
func _apply_look(p: RigPose, dt: float) -> void:
	var lw := _sp_look.x
	var target := Vector2.ZERO
	if lw > 0.003:
		var d := look_dir_local
		var yaw := atan2(-d.x, -d.z)
		var hz := Vector2(d.x, d.z).length()
		var pitch := atan2(d.y, maxf(hz, 0.0001))
		target = Vector2(clampf(wrapf(yaw, -PI, PI), -1.35, 1.35), clampf(pitch, -0.7, 0.7))
	_look_cur = _look_cur.lerp(target * lw, 1.0 - exp(-9.0 * dt))
	if _look_cur.length_squared() < 1e-8:
		return
	var yaw_c := _look_cur.x
	var pit_c := _look_cur.y
	# the body parts that already turn (hips / chest) are subtracted so the gaze reaches the target
	p.v[RigPose.SPINE_ROT].y += yaw_c * 0.12
	p.v[RigPose.CHEST_ROT].y += yaw_c * 0.18
	p.v[RigPose.NECK_ROT].y += yaw_c * 0.30
	p.v[RigPose.HEAD_ROT].y += yaw_c * 0.40
	p.v[RigPose.NECK_ROT].x += pit_c * 0.35
	p.v[RigPose.HEAD_ROT].x += pit_c * 0.55
