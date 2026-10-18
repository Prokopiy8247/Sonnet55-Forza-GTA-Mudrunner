class_name BikeVehicle
extends CarVehicle
## Motorcycle and bicycle: two raycast wheels + a virtual lean controller (inverted-pendulum PD on the roll angle) that holds the
## bike upright at rest, leans it into corners, optional wheelie on hard acceleration, pedal power for the bicycle.
## A crash (hard impact or leaning past ~65 deg) throws the rider off (forced exit + damage) and the bike lies down;
## entering it picks it back up.

var lean_max := deg_to_rad(44.0)
var is_bicycle := false
var fallen := false
var lean := 0.0
var lean_target := 0.0
var wheelie_on := false
var pedal_force := 0.0
var _fork: Node3D = null
var _fork_rest := Basis.IDENTITY
var _pedals: Node3D = null
var _pedal_phase := 0.0
var _fall_time := 0.0
var _wheelie_allowed := false
var pitch_angle := 0.0


func setup_bike() -> void:
	is_bicycle = vclass == GC.VC_BICYCLE
	lean_max = deg_to_rad(float(def.get("lean_max", 42.0)))
	pedal_force = float(def.get("pedal_force", 0.0))
	_wheelie_allowed = bool(def.get("wheelie", false))
	_fork = model.find_child("Fork", true, false) as Node3D
	if _fork != null:
		_fork_rest = _fork.transform.basis
	_pedals = model.find_child("Pedals", true, false) as Node3D
	lat_accel_limit = minf(mu_base, tan(lean_max) * 0.82) * eff_g
	steer_gain = minf(steer_gain, 0.95)
	# bikes brake with both wheels: bias to the front like a real bike
	brake_bias = 0.6
	angular_damp = 0.15


func _reset_extra() -> void:
	super._reset_extra()
	fallen = false
	lean = 0.0
	lean_target = 0.0
	wheelie_on = false


func enter(character: Node, seat: int = 0, animated: bool = false) -> bool:
	if fallen and seat == 0:
		pick_up()
	return super.enter(character, seat, animated)


func can_be_entered_by(_character: Node) -> bool:
	return not is_destroyed


func pick_up() -> void:
	fallen = false
	_fall_time = 0.0
	unflip()
	lean = 0.0


func _is_settled() -> bool:
	return fallen or grounded_count >= 1 and absf(lean) < 0.06


func _simulate(dt: float) -> void:
	if fallen:
		_fallen_tick(dt)
		return
	super._simulate(dt)


func _fallen_tick(dt: float) -> void:
	_fall_time += dt
	if engine_on:
		set_engine(false)
	_thr = 0.0
	_brk = 0.0
	braking = false
	# the lying bike just slides on its collision box; keep wheels spinning down visually
	for w in wheels:
		w.w = move_toward(w.w, 0.0, 12.0 * dt)
	if visual_lod == 0:
		_update_visuals(dt, 0.0)
	var v := linear_velocity
	if v.length() > 0.5:
		apply_central_force(-v.normalized() * mass * 3.0)
	grounded_count = 0


func _extra_torque(dt: float, b: Basis, lav: Vector3, fs: float, grounded: int) -> Vector3:
	var fwd := -b.z
	var right := b.x
	lean = atan2(-right.y, b.y.y)
	pitch_angle = asin(clampf(fwd.y, -1.0, 1.0))
	if absf(lean) > deg_to_rad(66.0) and linear_velocity.length() > 1.0 and grounded > 0:
		_fall_over(linear_velocity)
		return Vector3.ZERO
	if grounded == 0 and _airborne > 0.35:
		return Vector3.ZERO     # air control from super: levelling
	var spd := clampf(absf(fs) / 7.0, 0.0, 1.0)
	var yaw_rate := angular_velocity.y
	var lat_acc := -yaw_rate * fs
	var tgt := atan(lat_acc / eff_g) * 0.95 + (_steer / maxf(steer_lock, 0.01)) * lean_max * 0.3 * spd
	tgt = clampf(tgt, -lean_max, lean_max)
	lean_target = lerpf(lean_target, tgt, minf(1.0, dt * 9.0))
	var I := inertia_v.z
	var rate := angular_velocity.dot(fwd)
	var kp := 70.0
	var kd := 13.0
	var tau := I * clampf(-kp * (lean - lean_target) - kd * rate, -90.0, 90.0)
	var t := fwd * tau
	# ---- wheelie: full throttle in the low gears lifts the front wheel to a controlled angle
	var want := _wheelie_allowed and not is_bicycle and engine_on and ((_thr > 0.92 and gear <= 2 and fs < 24.0 and fs > -1.0) or input_pitch > 0.4)
	wheelie_on = want
	if want and grounded > 0:
		var target_pitch := deg_to_rad(30.0 if input_pitch <= 0.4 else 38.0)
		var prate := angular_velocity.dot(right)
		var ptau := inertia_v.x * clampf(18.0 * (target_pitch - pitch_angle) - 5.5 * prate, -14.0, 24.0)
		t += right * ptau
	elif input_pitch < -0.4 and grounded > 0 and fs > 8.0 and not is_bicycle:
		# stoppie nudge
		t += right * (-inertia_v.x * 6.0)
	return t


func _on_crash(impact: float) -> void:
	super._on_crash(impact)
	var limit := 6.0 if is_bicycle else 8.5
	if impact > limit and not fallen:
		_fall_over(linear_velocity)


func _fall_over(vel: Vector3) -> void:
	if fallen or is_destroyed:
		return
	fallen = true
	_fall_time = 0.0
	set_engine(false)
	# rider(s) fly off
	for c in get_occupants():
		exit(c, true)
		if c.has_method("knockback"):
			c.knockback(vel * 0.7 + Vector3.UP * 2.5 + global_transform.basis.x * randf_range(-2.0, 2.0))
		if c.has_method("apply_damage") and vel.length() > 6.0:
			c.apply_damage(clampf((vel.length() - 6.0) * 2.2, 3.0, 70.0), {"source": self, "type": GC.DMG_COLLISION, "zone": GC.ZONE_LIMB, "position": global_position})
	# tip the bike over
	var side := 1.0 if lean >= 0.0 else -1.0
	apply_torque_impulse(global_transform.basis.z * side * mass * 1.6)
	wake()


func _update_engine(dt: float, fs: float) -> float:
	if not is_bicycle:
		return super._update_engine(dt, fs)
	gear = 1
	rpm = 0.0
	var vmax := float(def.get("top_speed_kmh", 30.0)) / 3.6
	var f := 0.0
	if _thr > 0.02 and not is_destroyed:
		if _rev:
			f = -pedal_force * 0.5 * _thr * clampf(1.0 - absf(fs) / 2.5, 0.0, 1.0)
		else:
			f = pedal_force * _thr * clampf(1.0 - maxf(fs, 0.0) / vmax, 0.0, 1.0)
		_pedal_phase += dt * (3.0 + absf(fs) * 0.9) * signf(f + 0.0001)
	elif absf(fs) > 0.5:
		_pedal_phase += dt * absf(fs) * 0.25
	return f


func _update_extra_visuals(_dt: float) -> void:
	if _fork != null:
		_fork.transform.basis = Basis(Vector3.UP, -_steer) * _fork_rest
	if _pedals != null:
		_pedals.transform.basis = Basis(Vector3.RIGHT, -_pedal_phase)


func get_camera_hints() -> Dictionary:
	var h := super.get_camera_hints()
	h["lean"] = lean
	return h
