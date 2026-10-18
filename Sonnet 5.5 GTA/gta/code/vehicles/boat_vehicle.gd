class_name BoatVehicle
extends VehicleBase
## Speedboat on a RigidBody3D (Air&Sea agent): hull-point buoyancy against the animated sea surface (same wave function as the
## water shader), outboard thrust at the stern, planing (drag drops, bow lifts), speed-dependent rudder with inward heel, keel side
## grip, wave pitch / roll, flip guard, grounding on the seabed (the hull collider rests on the terrain), bow wave + wake + spray
## + prop churn (AirFx pools), sinking wreck, boarding from the water (E while swimming) or a pier (F), exit onto piers / quays / water.
## Inputs: input_throttle, input_brake (reverse when slow), input_steer (+1 right).

const GRAV := 9.81

# ---- tunables (def) ------------------------------------------------------------------------------------------------------------------
var thrust_n := 7600.0
var turn_rate := 1.15
var top_speed := 30.5               # m/s
var c_disp := 55.0                  # quadratic drag coefficient while ploughing
var c_plane := 7.4                  # ... and while planing
var inertia_v := Vector3(2400, 2600, 1000)
var hull: Array[Vector3] = []       # buoyancy sample points (hull bottom, vehicle space)
var k_buoy := 2700.0
var c_buoy := 700.0

# ---- state ----------------------------------------------------------------------------------------------------------------------------------------
var throttle_state := 0.0
var planing := 0.0                  # 0..1
var wet := 0.0                      # fraction of hull points under water
var submerged_depth := 0.0
var rudder := 0.0                   # -1..1 smoothed
var rpm01 := 0.0
var wave_h := 0.0                   # surface height under the CoM
var sinking := 0.0                  # seconds since the hull was destroyed
var grounded := false
var ai: Node = null

var _pt_water: Array[bool] = []
var _t := 0.0
var _prop: Node3D = null
var _prop_rest := Basis.IDENTITY
var _prop_angle := 0.0
var _wake_dist := 0.0
var _spray_t := 0.0
var _bob_t := 0.0
var _model_rest := Transform3D.IDENTITY
var _stern := Vector3(0, -0.25, 3.15)
var _bow := Vector3(0, 0.0, -2.9)
var _exhaust := Vector3(0, -0.1, 3.2)
var _last_planing_msg := false


var interact_range := 5.2           # PlayerInteraction reads this: swimmers board with E from up to this far


func _ready() -> void:
	super._ready()
	add_to_group(GC.G_INTERACT)


# =====================================================================================================
# Setup
# =====================================================================================================
func setup_air() -> void:
	mass = float(def.get("mass", 1100.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = def.get("com", Vector3(0, 0.02, 0.35))
	inertia_v = def.get("inertia", inertia_v)
	inertia = inertia_v
	angular_damp = 0.1
	thrust_n = float(def.get("thrust_n", thrust_n))
	turn_rate = float(def.get("turn_rate", turn_rate))
	top_speed = float(def.get("top_speed_kmh", 110.0)) / 3.6
	c_plane = maxf(thrust_n - 60.0 * top_speed, thrust_n * 0.5) / (top_speed * top_speed)
	c_disp = c_plane * 7.4
	run_over_enabled = false
	_prop = model.find_child("Prop", true, false) as Node3D
	if _prop != null:
		_prop_rest = _prop.transform.basis
		_stern = _prop.transform.origin
	var ex := model.find_child("Exhaust", true, false) as Node3D
	if ex != null:
		_exhaust = ex.transform.origin
	_model_rest = model.transform
	_build_hull()


func _build_hull() -> void:
	hull.clear()
	var zs := [-2.75, -1.65, -0.45, 0.85, 2.05, 3.0]
	var keel_y := [-0.05, -0.22, -0.3, -0.3, -0.3, -0.38]
	for i in zs.size():
		for xs in [-0.85, 0.0, 0.85]:
			var y: float = keel_y[i] + (0.0 if xs == 0.0 else 0.19)
			hull.append(Vector3(xs, y, zs[i]))
	_pt_water.clear()
	for i in hull.size():
		_pt_water.append(true)
	# stiffness so that the hull floats with its keel ~0.25 m deep: n * k * depth = m g
	k_buoy = mass * GRAV * gravity_scale / (float(hull.size()) * 0.2)
	c_buoy = 2.0 * 0.5 * sqrt(k_buoy * mass / float(hull.size()))


func _reset_extra() -> void:
	throttle_state = 0.0
	planing = 0.0
	rudder = 0.0
	rpm01 = 0.0
	sinking = 0.0
	if ai != null and is_instance_valid(ai):
		ai.queue_free()
	ai = null
	if model != null:
		model.transform = _model_rest


func _is_settled() -> bool:
	return wet > 0.2 and linear_velocity.length_squared() < 0.04


# =====================================================================================================
# VehicleBase overrides
# =====================================================================================================
func get_rpm01() -> float:
	return rpm01


func get_engine_load() -> float:
	return clampf(throttle_state * 0.8 + planing * 0.2, 0.0, 1.0)


func _tick_water(_dt: float) -> void:
	pass                                    # boats float: no sinking-car logic


func get_camera_hints() -> Dictionary:
	var sp := clampf(get_speed() / top_speed, 0.0, 1.0)
	return {
		"distance": float(def.get("cam_distance", 9.6)) * (1.0 + sp * 0.28),
		"height": float(def.get("cam_height", 3.6)),
		"look_ahead": float(def.get("cam_look_ahead", 5.0)) * (0.5 + sp),
		"fov": float(def.get("cam_fov", 72.0)) + sp * 10.0,
		"shake": sp * sp * 0.12,
		"speed_kmh": get_speed_kmh(),
		"first_person_offset": (seats[0]["pos"] as Vector3) + Vector3(0, 0.62, -0.2) if seats.size() > 0 else Vector3(-0.4, 1.3, 0.0),
	}


func can_be_entered_by(_character: Node) -> bool:
	return not is_destroyed and global_transform.basis.y.y > 0.0


func enter(character: Node, seat: int = 0, animated: bool = false) -> bool:
	var ok := super.enter(character, seat, animated)
	if ok:
		wake()
		sleeping = false
	return ok


## F (from a pier / quay) goes through VehicleBase's prompt; swimmers use E: this returns the interactable text only when the
## player is in the water, so the two prompts never show together.
func get_interaction(character: Node) -> Dictionary:
	if is_destroyed:
		return {}
	if character != null and character.get("is_swimming") == true:
		return {"text": "Board " + display_name, "key": "E", "enabled": true}
	return {}


func interact(character: Node) -> void:
	request_enter(character)


func _report_theft(_character: Node) -> void:
	pass                                    # boats are free to take


# ---- exit placement: pier / quay when one is within reach, else the water beside the hull ------------------------------------
func _find_exit_position(seat_idx: int, forced: bool) -> Vector3:
	var xf := global_transform
	var side := float(seats[seat_idx].get("side", -1.0))
	var space := get_world_3d().direct_space_state
	var cands: Array[Vector3] = []
	var ex: Vector3 = seats[seat_idx]["exit"]
	cands.append(xf * Vector3(side * 2.6, 0.0, ex.z))
	cands.append(xf * Vector3(-side * 2.6, 0.0, ex.z))
	cands.append(xf * Vector3(side * 3.6, 0.0, ex.z + 0.8))
	cands.append(xf * Vector3(-side * 3.6, 0.0, ex.z + 0.8))
	cands.append(xf * Vector3(side * 4.8, 0.0, ex.z))
	cands.append(xf * Vector3(-side * 4.8, 0.0, ex.z))
	cands.append(xf * Vector3(0.0, 0.0, -4.4))
	cands.append(xf * Vector3(0.0, 0.0, 4.6))
	for p in cands:
		var from := Vector3(p.x, GC.WATER_LEVEL + 3.2, p.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.5, GC.M_GROUND)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.position.y > GC.WATER_LEVEL - 0.15:
			var hp: Vector3 = hit.position
			# free space check for a standing character
			if _stand_free(space, hp):
				return hp + Vector3(0, 0.04, 0)
	# open water: stand just above the surface beside the seat; the player's own water logic takes over (swimming)
	var w := xf * Vector3(side * 2.1, 0.0, ex.z)
	return Vector3(w.x, GC.WATER_LEVEL + 0.25, w.z)


func _stand_free(space: PhysicsDirectSpaceState3D, ground: Vector3) -> bool:
	if _exit_capsule == null:
		_exit_capsule = CapsuleShape3D.new()
		_exit_capsule.radius = 0.32
		_exit_capsule.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _exit_capsule
	q.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.95)
	q.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()


# =====================================================================================================
# Simulation
# =====================================================================================================
func _simulate(dt: float) -> void:
	if hull.is_empty():
		return
	_t += dt
	if sleeping:
		sleeping = false
	var xf := global_transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var lv := linear_velocity
	var av := angular_velocity
	var g_eff := GRAV * gravity_scale
	var com_w := xf * center_of_mass
	var clock := Time.get_ticks_msec() * 0.001
	var rain := Game.rain_intensity
	var piloted := driver != null or is_ai_controlled
	if is_destroyed:
		sinking += dt
	var buoy_scale := 1.0 if not is_destroyed else clampf(1.0 - sinking / 7.0, 0.04, 1.0)
	# ---- buoyancy ----------------------------------------------------------------------------------------------------------------------------
	var tot_f := Vector3.ZERO
	var tot_t := Vector3.ZERO
	var wet_n := 0
	var depth_sum := 0.0
	var recheck := (_tick % 4) == 0
	for i in hull.size():
		var wp: Vector3 = xf * hull[i]
		if recheck:
			_pt_water[i] = WorldLayout.terrain_height(wp.x, wp.z) < GC.WATER_LEVEL - 0.05
		if not _pt_water[i]:
			continue
		var sh := GC.WATER_LEVEL + AirCommon.wave_height(wp.x, wp.z, clock, rain)
		var depth := sh - wp.y
		if depth <= 0.0:
			continue
		depth = minf(depth, 0.9)
		wet_n += 1
		depth_sum += depth
		var vpt := lv + av.cross(wp - com_w)
		var f := maxf(k_buoy * depth - c_buoy * vpt.y, 0.0) * buoy_scale
		var fv := Vector3.UP * f
		tot_f += fv
		tot_t += (wp - com_w).cross(fv)
	wet = float(wet_n) / float(hull.size())
	submerged_depth = depth_sum / maxf(float(wet_n), 1.0)
	wave_h = AirCommon.wave_height(com_w.x, com_w.z, clock, rain)
	grounded = wet < 0.12 and not is_destroyed
	# ---- engine / steering ------------------------------------------------------------------------------------------------------------------
	var fs := lv.dot(fwd)
	var speed_h := Vector2(lv.x, lv.z).length()
	var thr_in := clampf(input_throttle, 0.0, 1.0) if piloted else 0.0
	var brk_in := clampf(input_brake, 0.0, 1.0) if piloted else 0.0
	if not engine_on or is_destroyed or power_scale < 0.2:
		thr_in = 0.0
		brk_in = 0.0
	throttle_state = Util.damp(throttle_state, thr_in if brk_in < 0.1 else -brk_in * 0.6, 3.2, dt)      # brake = reverse thrust (water brake)
	var stern_w := xf * _stern
	var wet_stern := clampf(wet * 1.6, 0.0, 1.0)
	var steer_in := clampf(input_steer, -1.0, 1.0) if piloted else 0.0
	rudder = Util.damp(rudder, steer_in, 5.5, dt)
	planing = Util.damp(planing, smoothstep(6.5, 13.5, speed_h) * clampf(throttle_state * 3.0, 0.0, 1.0) * clampf(wet * 2.0, 0.0, 1.0), 2.2, dt)
	# thrust (outboard: acts at the stern, below the CoM -> bow-up moment); damaged engine loses power
	var thrust := thrust_n * throttle_state * wet_stern * power_scale * mod_power
	if thrust < 0.0:
		thrust *= 0.55
	var thrust_dir := fwd.rotated(up, -rudder * 0.12)
	var tf := thrust_dir * thrust
	tot_f += tf
	tot_t += (stern_w - com_w).cross(tf)
	# ---- hydrodynamic drag (body axes) -------------------------------------------------------------------------------------------------------
	var vb := b.inverse() * lv
	var c_fwd := lerpf(c_disp, c_plane, planing)
	var k_lat := lerpf(5.5, 2.0, planing)
	var drag_x := -vb.x * k_lat * mass
	var drag_z := -signf(vb.z) * vb.z * vb.z * c_fwd - vb.z * 60.0       # vb.z < 0 when moving forward -> force along +Z
	var wet_f := clampf(wet * 1.4, 0.0, 1.0)
	var drag_w := b * Vector3(drag_x * wet_f, 0.0, drag_z * wet_f)
	tot_f += drag_w
	# aground / scraping the bottom: heavy friction, the hull stops within a few metres of the shore
	if get_contact_count() > 0 and wet < 0.8:
		tot_f += -Vector3(lv.x, 0.0, lv.z) * mass * 3.2 * (1.0 - wet)
	# unattended boats do not wander off: strong damping (anchored)
	if driver == null and not is_ai_controlled:
		tot_f += -Vector3(lv.x, 0.0, lv.z) * mass * 1.4 * wet_f
	# in the air (jump off a wave): no water forces, a little air drag
	# ---- yaw: rate command (rudder scaled by speed) + heel into the turn -------------------------------------------------------------------------------
	var lav := b.inverse() * av
	var sp_f := smoothstep(0.4, 6.0, absf(fs)) * wet_f
	var turn_scale := lerpf(1.0, 0.72, planing)
	var yaw_target := -rudder * turn_rate * sp_f * turn_scale * (1.0 if fs >= -0.5 else -1.0)
	var yaw_acc := 3.2 * (yaw_target - lav.y) * wet_f
	var heel := -rudder * minf(absf(fs), 22.0) * minf(absf(fs), 22.0) * 4.3 * wet_f      # inward lean: roll right (negative about +Z) when turning right
	var tq := Vector3(0.0, yaw_acc * inertia_v.y, heel)
	# bow-up trim when planing (thrust line + hydrodynamic lift on the aft hull)
	tq.x += planing * mass * g_eff * 1.5 * (1.0 - throttle_state * 0.25)
	# damping of pitch / roll oscillations in the water
	tq.x += -lav.x * inertia_v.x * 1.1 * wet_f
	tq.z += -lav.z * inertia_v.z * 1.4 * wet_f
	tot_t += b * tq
	# planing lift: unloads the hull as the speed grows (drag + draft fall), applied slightly aft
	var lift := mass * g_eff * 0.30 * planing * wet_f * buoy_scale
	tot_f += Vector3.UP * lift
	tot_t += (xf * Vector3(0, 0, 0.9) - com_w).cross(Vector3.UP * lift)
	# ---- flip guard: righting torque beyond ~50 deg of tilt -----------------------------------------------------------------------------------------------------
	var tilt := acos(clampf(up.y, -1.0, 1.0))
	if tilt > 0.85 and wet > 0.1 and not is_destroyed:
		tot_t += up.cross(Vector3.UP) * inertia_v.z * 7.0 * (tilt - 0.85)
	apply_central_force(tot_f)
	apply_torque(tot_t)
	# ---- visuals / fx -------------------------------------------------------------------------------------------------------------------------------------
	rpm01 = Util.damp(rpm01, (0.18 + 0.82 * clampf(absf(throttle_state), 0.0, 1.0)) if engine_on and not is_destroyed else 0.0, 4.0, dt)
	if visual_lod == 0:
		_update_visuals(dt, thrust)
		_update_fx(dt, fs, speed_h, xf)


func _sleep_tick(dt: float) -> void:
	super._sleep_tick(dt)
	if model == null:
		return
	# parked boats bob on the swell even though their body sleeps (visual only)
	_bob_t += dt
	var clock := Time.get_ticks_msec() * 0.001
	var h := AirCommon.wave_height(global_position.x, global_position.z, clock, Game.rain_intensity)
	var rock := sin(clock * 0.9 + float(get_instance_id() % 17)) * 0.012
	model.transform = Transform3D(_model_rest.basis * Basis(Vector3.RIGHT, rock) * Basis(Vector3.BACK, rock * 0.8), _model_rest.origin + Vector3(0, h * 0.8, 0))


func _update_visuals(dt: float, thrust: float) -> void:
	if _prop != null:
		_prop_angle = fposmod(_prop_angle + (absf(throttle_state) * 90.0 + 3.0 * float(engine_on)) * dt * signf(thrust + 0.001), TAU)
		_prop.transform.basis = _prop_rest * Basis(Vector3.BACK, _prop_angle)
	if model != null and not is_destroyed:
		model.transform = _model_rest


func _update_fx(dt: float, fs: float, speed_h: float, xf: Transform3D) -> void:
	var fx := AirFx.get_fx()
	if fx == null:
		return
	var b := xf.basis
	var fwd := -b.z
	var right := b.x
	var level := GC.WATER_LEVEL + wave_h
	if wet < 0.15 or is_destroyed:
		return
	# ---- wake foam: trail behind the stern, V wake along the hull sides, bow wave ---------------------------------------------------------------------------------------
	_wake_dist += speed_h * dt
	if speed_h > 1.8 and _wake_dist > lerpf(0.55, 1.1, clampf(speed_h / 25.0, 0.0, 1.0)):
		_wake_dist = 0.0
		var dir_back := -fwd
		dir_back.y = 0.0
		dir_back = dir_back.normalized()
		var sp := clampf(speed_h / 20.0, 0.0, 1.0)
		var stern := xf * (_stern + Vector3(0, 0, 0.4))
		var centre := Vector3(stern.x, level + 0.035, stern.z)
		fx.wake_patch(centre, fwd, 1.1 + sp * 0.5, 2.6 + sp * 2.2, 2.8 + sp * 3.0, 3.6 + sp * 2.0, 0.55 + sp * 0.25)
		for s in [-1.0, 1.0]:
			var p: Vector3 = xf * (Vector3(s * 0.95, 0.0, 2.2))
			var d: Vector3 = dir_back.rotated(Vector3.UP, s * 0.28)
			fx.wake_patch(Vector3(p.x, level + 0.03, p.z), d, 0.5 + sp * 0.25, 1.5 + sp * 1.4, 2.4 + sp * 2.0, 2.4 + sp * 1.4, 0.4 + sp * 0.2)
			var pb: Vector3 = xf * (Vector3(s * 0.7, 0.0, -2.35))
			var db: Vector3 = dir_back.rotated(Vector3.UP, s * 0.62)
			fx.wake_patch(Vector3(pb.x, level + 0.04, pb.z), db, 0.4 + sp * 0.3, 1.0 + sp * 1.1, 1.6 + sp * 1.4, 1.1 + sp * 0.5, 0.5 + sp * 0.3)
	# ---- spray -----------------------------------------------------------------------------------------------------------------------------------------------------------------
	_spray_t -= dt
	if _spray_t <= 0.0 and speed_h > 5.0:
		_spray_t = lerpf(0.09, 0.04, clampf(speed_h / 22.0, 0.0, 1.0))
		var sp2 := clampf((speed_h - 5.0) / 18.0, 0.0, 1.0)
		for s in [-1.0, 1.0]:
			var bp: Vector3 = xf * (Vector3(s * 0.8, 0.1, -2.1))
			bp.y = level + 0.1
			var v: Vector3 = right * s * (2.4 + sp2 * 2.5) + Vector3.UP * (1.8 + sp2 * 2.2) + fwd * speed_h * 0.35
			fx.spray_burst(bp, v, 1 + int(sp2 * 2.0), 0.7 + sp2 * 0.5, 0.35 + sp2 * 0.25)
		if planing > 0.4:
			var rp: Vector3 = xf * _exhaust
			rp.y = level + 0.1
			var rv := -fwd * (3.0 + sp2 * 4.0) + Vector3.UP * (3.5 + sp2 * 3.0)
			fx.spray_burst(rp, rv, 2, 0.8, 0.55)
	# prop churn at the stern when the throttle is open at low speed
	if throttle_state > 0.15 and speed_h < 9.0 and engine_on:
		var cp: Vector3 = xf * _stern
		cp.y = level + 0.05
		if _tick % 3 == 0:
			fx.mist_puff(cp, Vector3(randf_range(-0.6, 0.6), randf_range(0.4, 1.2), randf_range(-0.6, 0.6)) - fwd * 0.8, 1.2 + throttle_state, 0.28, 1.0)
			fx.spray_burst(cp, -fwd * 1.5 + Vector3.UP * 1.5, 1, 0.7, 0.4)
