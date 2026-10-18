class_name CarVehicle
extends VehicleBase
## Raycast-suspension wheeled vehicle on a project-owned RigidBody3D (Jolt): cars, SUVs, vans, trucks (4 or 6 wheels).
## Per wheel: ray -> spring/damper/bump-stop, anti-roll bars, slip-angle tyre model with friction ellipse, drift grip fall-off,
## handbrake break-away, ABS braking, simplified engine + automatic gearbox (torque curve, ratios derived from top speed),
## aero drag/downforce, air levelling and body-roll friendly low CoM.  BikeVehicle extends this class.

const SURFACE_GRIP := {
	&"road": 1.0, &"asphalt": 1.0, &"concrete": 1.0, &"metal": 0.9, &"wood": 0.9, &"grass": 0.62, &"dirt": 0.78,
	&"gravel": 0.72, &"sand": 0.58, &"mud": 0.5, &"snow": 0.45,
}
const SLIP_STIFF := 12.0           # slip-angle stiffness of the tyre curve (1/rad)
const V_REG := 2.0                 # low speed regulariser of the slip angle (m/s)
const LAT_DAMP_RESP := 0.7         # how hard the stiction clamp kills lateral velocity (<1 = stable)
const CRR := 0.014                 # rolling resistance coefficient
const ABS_FRAC := 0.88

# ---- tuning (filled from the def in setup_physics) ---------------------------------------------------------------------
var mu_base := 1.15
var drift_grip := 0.65
var front_grip := 1.0
var rear_grip := 1.0
var grip_lift := 0.75
var steer_lock := deg_to_rad(34.0)
var steer_min := deg_to_rad(3.0)
var steer_gain := 1.5
var brake_decel := 11.0
var brake_bias := 0.65
var handbrake_grip := 0.3
var cda := 0.7
var downforce_k := 0.0
var rpm_idle := 900.0
var rpm_red := 6500.0
var torque_peak := 200.0
var gear_ratios: Array[float] = []
var rev_ratio := 10.0
var drive_radius := 0.33
var reverse_max := 13.0
var wheelbase := 2.7
var track_w := 1.55
var inertia_v := Vector3.ONE
var eff_g := 9.81
var lat_accel_limit := 12.0       # m/s^2 the steering lock schedule is built around (grip, or lean limit for bikes)

# ---- runtime ---------------------------------------------------------------------------------------------------------------
var _thr := 0.0
var _brk := 0.0
var _rev := false
var braking := false                 # brake lights
var _steer := 0.0                    # rad, + right
var _shift_timer := 0.0
var _gear_hold := 0.0
var _airborne := 0.0
var grounded_count := 0
var skill_grip := 1.0              # Systems-A hook: SkillsSystem 'driving' (tyre grip multiplier, set while the player drives)
var skill_recovery := 0.0          # Systems-A hook: raises the drift grip floor (spin recovery)
var skid_level := 0.0
var drive_force_dbg := 0.0
var _query: PhysicsRayQueryParameters3D = null
var _n_wheels := 4
var _driven_count := 1
var _wheelspin := 0.0
var _steer_in_smooth := 0.0
var _last_visual_t := 0.0
var arb_k := 0.3
var _cache_f := Vector3.ZERO
var _cache_t := Vector3.ZERO
var _cache_ok := false
var n_front := 2


## Called by the factory once the model is bound: wheels, mass properties, drivetrain.
func setup_physics() -> void:
	mu_base = float(def.get("grip", 1.15))
	drift_grip = float(def.get("drift_grip", 0.65))
	front_grip = float(def.get("front_grip", 1.0))
	rear_grip = float(def.get("rear_grip", 1.0))
	grip_lift = float(def.get("grip_lift", 0.75))
	steer_lock = deg_to_rad(float(def.get("steer_lock", 34.0)))
	steer_min = deg_to_rad(float(def.get("steer_min", 3.0)))
	steer_gain = float(def.get("steer_gain", 1.5))
	brake_decel = float(def.get("brake", 11.0))
	handbrake_grip = float(def.get("handbrake_grip", 0.3))
	cda = float(def.get("cda", 0.7))
	downforce_k = float(def.get("downforce", 0.0))
	rpm_idle = float(def.get("rpm_idle", 900.0))
	rpm_red = float(def.get("rpm_red", 6500.0))
	wheelbase = float(def.get("wheelbase", 2.7))
	track_w = float(def.get("track", 1.55))
	eff_g = G * gravity_scale
	lat_accel_limit = mu_base * eff_g
	_build_wheels()
	_setup_mass()
	_setup_drivetrain()
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = GC.M_GROUND
	_query.exclude = [get_rid()]
	_query.hit_from_inside = false


func _build_wheels() -> void:
	wheels.clear()
	var infos: Array = minfo.get("wheels", [])
	var mass_ := float(def.get("mass", 1400.0))
	var com: Vector3 = def.get("com", Vector3(0, 0.5, 0))
	# axle grouping by z (front = most negative)
	var zs: Array[float] = []
	for inf in infos:
		var z: float = snappedf((inf["pos"] as Vector3).z, 0.25)
		if not zs.has(z):
			zs.append(z)
	zs.sort()
	var n_axles := zs.size()
	# static load share per axle (lever rule generalised)
	var inv_sum := 0.0
	var inv: Array[float] = []
	for z in zs:
		var v := 1.0 / (absf(z - com.z) + 0.6)
		inv.append(v)
		inv_sum += v
	var travel := float(def.get("susp_travel", 0.28))
	var freq := float(def.get("susp_freq", 2.0)) * mod_susp
	var zeta := float(def.get("susp_damp", 0.5))
	var arb := float(def.get("arb", 0.5))
	var drive: StringName = def.get("drive", &"fwd")
	for inf in infos:
		var w := VehicleWheel.new()
		w.wname = inf["name"]
		w.node = model.find_child(String(inf["name"]), true, false) as Node3D if model != null else null
		w.rest_basis = inf.get("basis", Basis.IDENTITY)
		w.rest = inf["pos"]
		w.radius = float(inf["radius"])
		w.width = float(inf.get("width", 0.22))
		var zq: float = snappedf(w.rest.z, 0.25)
		w.axle = zs.find(zq)
		w.front = w.axle == 0
		w.side = -1.0 if w.rest.x < -0.05 else (1.0 if w.rest.x > 0.05 else 0.0)
		w.steered = w.front
		w.handbrake = w.axle == n_axles - 1
		match drive:
			&"fwd":
				w.driven = w.axle == 0
			&"awd":
				w.driven = true
			_:
				w.driven = w.axle == n_axles - 1 or (n_axles >= 3 and w.axle >= 1)
		var share: float = inv[w.axle] / inv_sum
		var per_axle := 0
		for inf2 in infos:
			if snappedf((inf2["pos"] as Vector3).z, 0.25) == zq:
				per_axle += 1
		var m_w := mass_ * share / maxf(float(per_axle), 1.0)
		var omega := TAU * freq
		w.k = m_w * omega * omega
		var cc := 2.0 * zeta * sqrt(w.k * m_w)
		w.c_bump = cc * 0.85
		w.c_reb = cc * 1.25
		var x0 := m_w * eff_g / w.k
		w.eq_len = travel
		w.max_len = travel + 0.12
		w.length = w.eq_len
		w.prev_length = w.eq_len
		w.hp = w.rest + Vector3.UP * w.eq_len
		w.free_len = w.eq_len + x0
		wheels.append(w)
	_n_wheels = wheels.size()
	_driven_count = 0
	for w in wheels:
		if w.driven:
			_driven_count += 1
	_driven_count = maxi(_driven_count, 1)
	var rsum := 0.0
	var rn := 0
	for w in wheels:
		if w.driven:
			rsum += w.radius
			rn += 1
	drive_radius = rsum / maxf(float(rn), 1.0) if rn > 0 else float(def.get("wheel_radius", 0.33))
	arb_k = arb * 0.6
	n_front = 0
	for w in wheels:
		if w.front:
			n_front += 1


func _setup_mass() -> void:
	var m := float(def.get("mass", 1400.0))
	mass = m
	var l := float(def.get("length", 4.5))
	var w := float(def.get("width", 1.8))
	var h := float(def.get("height", 1.45))
	var s := float(def.get("inertia_scale", 1.0))
	# roll inertia slightly lower than a solid box: the body leans readily but is never twitchy
	inertia_v = Vector3(m / 12.0 * (h * h + l * l) * 0.85, m / 12.0 * (w * w + l * l) * 0.9, m / 12.0 * (w * w + h * h) * 0.9) * s
	inertia = inertia_v
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = def.get("com", Vector3(0, 0.5, 0))


func _setup_drivetrain() -> void:
	var power_w: float = float(def.get("power_kw", 100.0)) * 1000.0 * float(def.get("power_mult", 1.25))
	var omega_red := rpm_red * TAU / 60.0
	torque_peak = power_w / (0.75 * omega_red)
	var v_top := float(def.get("top_speed_kmh", 180.0)) / 3.6
	var g_top := rpm_red * 0.97 * TAU / 60.0 * drive_radius / v_top
	var g1 := g_top / float(def.get("first_gear_frac", 0.28))
	var n := maxi(int(def.get("gear_count", 5)), 1)
	gear_ratios.clear()
	for i in n:
		var f := float(i) / maxf(float(n - 1), 1.0)
		gear_ratios.append(g1 * pow(g_top / g1, f))
	rev_ratio = g1 * 0.95
	reverse_max = clampf(v_top * 0.28, 6.0, 15.0)


func _reset_extra() -> void:
	_cache_ok = false
	_thr = 0.0
	_brk = 0.0
	_rev = false
	_steer = 0.0
	_shift_timer = 0.0
	_gear_hold = 0.0
	_airborne = 0.0
	skid_level = 0.0
	braking = false


func _on_mods_changed() -> void:
	if not wheels.is_empty():
		_build_wheels()


# =====================================================================================================
# Simulation
# =====================================================================================================
func _simulate(dt: float) -> void:
	if wheels.is_empty() or _query == null:
		return
	# distance LOD: AI vehicles far from the camera re-apply the last forces on the in-between ticks
	if sim_stride > 1 and _cache_ok and (_tick + _stagger) % sim_stride != 0 and (driver == null or not driver.is_in_group(GC.G_PLAYER)):
		apply_central_force(_cache_f)
		apply_torque(_cache_t)
		return
	var xf := global_transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var com_w := xf * center_of_mass
	var lv := linear_velocity
	var av := angular_velocity
	var fs := lv.dot(fwd)
	var inv_dt := 1.0 / dt
	var space := get_world_3d().direct_space_state

	_update_pedals(fs)
	_update_steer(dt, fs)
	var drive_total := _update_engine(dt, fs)

	var tot_f := Vector3.ZERO
	var tot_t := Vector3.ZERO
	var wet := 1.0 - 0.28 * Game.wetness
	var m_eff := mass / float(_n_wheels)
	var grounded := 0

	# ---- pass 1: ray + spring/damper ---------------------------------------------------------------------------------------
	for w in wheels:
		var hp_w := xf * w.hp
		var eff_r := w.radius * (0.84 if w.flat else 1.0)
		_query.from = hp_w
		_query.to = hp_w - up * (w.max_len + eff_r)
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			w.grounded = false
			w.length = move_toward(w.length, w.max_len, 1.6 * dt)
			w.prev_length = w.length
			w.normal_force = 0.0
			w.slip = 0.0
			continue
		var cpos: Vector3 = hit.position
		var d := hp_w.distance_to(cpos)
		var len_ := clampf(d - eff_r, 0.0, w.max_len)
		var cid: int = hit.collider_id
		if cid != w.collider_id:
			w.collider_id = cid
			_update_surface(w, hit.collider)
		var comp_speed := (w.prev_length - len_) * inv_dt if w.grounded else 0.0
		comp_speed = clampf(comp_speed, -6.0, 6.0)
		var f_spring: float = w.k * maxf(w.free_len - len_, 0.0)
		if len_ < 0.07:
			f_spring += w.k * (2.0 * (0.07 - len_) + 6.0 * maxf(0.02 - len_, 0.0))
		var f_damp: float = (w.c_bump if comp_speed > 0.0 else w.c_reb) * comp_speed
		w.normal_force = maxf(f_spring + f_damp, 0.0)
		w.length = len_
		w.prev_length = len_
		w.contact = cpos
		w.normal = hit.normal
		w.grounded = true
		grounded += 1
	grounded_count = grounded
	var sum_fn := 0.0
	for w in wheels:
		sum_fn += w.normal_force

	# ---- anti-roll bars ---------------------------------------------------------------------------------------------------------
	if _n_wheels >= 4:
		for i in range(0, _n_wheels - 1):
			var wl: VehicleWheel = wheels[i]
			if wl.side >= 0.0:
				continue
			var wr: VehicleWheel = null
			for j in range(i + 1, _n_wheels):
				if wheels[j].axle == wl.axle and wheels[j].side > 0.0:
					wr = wheels[j]
					break
			if wr == null or not wl.grounded or not wr.grounded:
				continue
			var arb_f := arb_k * wl.k * (wr.length - wl.length)
			wl.normal_force = maxf(wl.normal_force + arb_f, 0.0)
			wr.normal_force = maxf(wr.normal_force - arb_f, 0.0)

	# ---- pass 2: forces ----------------------------------------------------------------------------------------------------------
	var brake_cmd := _brk * brake_decel * mass * mod_brake
	# Garage brake upgrade: stock brakes already sit at the ABS grip limit, so better pads/discs also raise the usable fraction of peak grip
	var abs_frac := minf(ABS_FRAC + (mod_brake - 1.0) * 0.25, 0.97)
	var hold_mode := _thr < 0.03 and _brk < 0.03 and absf(fs) < 0.9
	var drive_per := drive_total / float(_driven_count)
	var max_slip := 0.0
	var any_spin := 0.0
	for w in wheels:
		if w.steered:
			w.steer_angle = _ackermann(w, _steer)
		if not w.grounded:
			if w.driven and _thr > 0.1 and engine_on:
				w.w = move_toward(w.w, 120.0 * signf(drive_total + 0.001), 160.0 * dt)
			else:
				w.w = move_toward(w.w, 0.0, (40.0 if _brk > 0.1 or (input_handbrake and w.handbrake) else 4.0) * dt)
			continue
		var fn: float = w.normal_force
		var cp: Vector3 = w.contact
		var n: Vector3 = w.normal
		# wheel heading (steered wheels rotate about the suspension axis, Ackermann)
		var wf_dir := fwd
		if w.steered:
			var ang := w.steer_angle
			wf_dir = fwd * cos(ang) + right * sin(ang)
		var wf := (wf_dir - n * wf_dir.dot(n)).normalized()
		var wr := wf.cross(n)
		var vpt := lv + av.cross(cp - com_w)
		var vf := vpt.dot(wf)
		var vl := vpt.dot(wr)
		var mu := mu_base * (front_grip if w.front else rear_grip) * mod_grip * skill_grip * w.surface_mult * wet * (0.55 if w.flat else 1.0)
		var fmax := mu * fn
		# ---- longitudinal request
		var fx := 0.0
		if w.driven:
			fx += drive_per
		var locked := w.handbrake and input_handbrake
		var brake_cap := 0.0
		if _brk > 0.01:
			var static_share := brake_bias / maxf(float(n_front), 1.0) if w.front else (1.0 - brake_bias) / maxf(float(_n_wheels - n_front), 1.0)
			var dyn_share := fn / maxf(sum_fn, 1.0)
			brake_cap = brake_cmd * lerpf(static_share, dyn_share, 0.65)
		var vstop := absf(vf) * m_eff * inv_dt
		if locked:
			brake_cap = maxf(brake_cap, fmax * 0.9)
		if brake_cap > 0.0:
			fx -= signf(vf) * minf(minf(brake_cap, fmax * abs_frac if not locked else fmax * 0.92), vstop)
		# rolling resistance + stationary hold (parking brake feel on slopes)
		var rr := CRR * fn * (4.0 if w.flat else 1.0) * (1.0 + (1.0 - w.surface_mult) * 2.0)
		fx -= signf(vf) * minf(rr, vstop)
		if hold_mode or (driver == null and not is_ai_controlled and absf(vf) < 2.0):
			fx -= vf * m_eff * inv_dt * 0.5
		if driver == null and not is_ai_controlled and absf(vf) >= 2.0:
			fx -= signf(vf) * minf(fn * 0.12, vstop)      # unattended rolling vehicle slows down
		# ---- friction ellipse
		var spinning := false
		var fx_c := fx
		var lim := fmax * (0.97 if not (_brk > 0.01) else abs_frac)
		if absf(fx) > lim:
			fx_c = signf(fx) * lim * (0.92 if (w.driven and absf(drive_per) > absf(fx) * 0.8 and _brk < 0.05) else 1.0)
			spinning = w.driven and signf(fx) == signf(drive_per) and _brk < 0.05
		# ---- lateral
		var vg := sqrt(vf * vf + vl * vl)
		var s_ratio := absf(vl) / (vg + 1.0)
		var g := lerpf(1.0, minf(drift_grip + skill_recovery, 0.98), smoothstep(0.14, 0.55, s_ratio))
		if locked:
			g *= handbrake_grip
		var alpha := vl / (absf(vf) + V_REG)
		var xs := alpha * SLIP_STIFF
		var fy_avail := sqrt(maxf(fmax * fmax - fx_c * fx_c, 0.0))
		var fy_curve := fy_avail * (xs / sqrt(1.0 + xs * xs)) * g
		var fy_stiction := absf(vl) * m_eff * inv_dt * LAT_DAMP_RESP
		var fy := -signf(vl) * minf(absf(fy_curve), fy_stiction)
		# ---- apply (traction forces act near the CoM height: arcade stability without losing weight transfer)
		var spring_f := up * fn
		var f_trac := wf * fx_c + wr * fy
		var lift_pt := cp + up * ((com_w - cp).dot(up) * grip_lift)
		tot_f += spring_f + f_trac
		tot_t += (xf * (w.hp - Vector3.UP * w.length) - com_w).cross(spring_f) + (lift_pt - com_w).cross(f_trac)
		# ---- wheel speed / skid state for visuals + fx
		var w_ground := vf / w.radius
		var slip_amt := 0.0
		if locked and absf(vf) > 1.5:
			w.w = move_toward(w.w, 0.0, 90.0 * dt)
			slip_amt = 0.9
		elif spinning:
			var spin_excess := clampf((absf(drive_per) - fmax) / maxf(fmax, 1.0), 0.0, 1.5)
			w.w = lerpf(w.w, w_ground + signf(drive_per) * (8.0 + spin_excess * 30.0), minf(1.0, dt * 12.0))
			slip_amt = clampf(0.4 + spin_excess, 0.0, 1.0)
			any_spin = maxf(any_spin, spin_excess)
		elif brake_cap > fmax * 0.85 and absf(vf) > 4.0:
			w.w = lerpf(w.w, w_ground * 0.8, minf(1.0, dt * 10.0))
			slip_amt = 0.25
		else:
			w.w = lerpf(w.w, w_ground, minf(1.0, dt * 22.0))
		if absf(vf) > 2.5:
			slip_amt = maxf(slip_amt, clampf((s_ratio - 0.10) * 2.4, 0.0, 1.0))
		w.slip = slip_amt
		w.slip_lat = vl
		max_slip = maxf(max_slip, slip_amt)
	skid_level = lerpf(skid_level, max_slip, minf(1.0, dt * 14.0))
	_wheelspin = any_spin

	# ---- aero / downforce -------------------------------------------------------------------------------------------------------
	var speed := lv.length()
	if speed > 0.5:
		tot_f -= lv * (0.5 * 1.225 * cda * speed)
	var df := (downforce_k + mod_downforce * 0.5) * speed * speed
	if df > 0.0 and grounded > 0:
		var df_c := minf(df, mass * eff_g * 1.2)
		tot_f -= up * df_c
		# downforce biased to the rear axle with the CoM slightly forward: no torque term kept (stable)
	# ---- stability / air control --------------------------------------------------------------------------------------------------
	var lav := b.inverse() * av
	tot_t += b * Vector3(-lav.x * inertia_v.x * 0.9, -lav.y * inertia_v.y * 0.08, -lav.z * inertia_v.z * 1.1)
	if grounded == 0:
		_airborne += dt
		if _airborne > 0.12 and up.y > 0.2:
			var tilt := up.cross(Vector3.UP)
			tot_t += tilt * (inertia_v.x + inertia_v.z) * 0.5 * 2.2
			tot_t -= (b.x * lav.x * inertia_v.x + b.z * lav.z * inertia_v.z) * 1.4
	else:
		_airborne = 0.0
	# damaged steering pull
	if _steer_bias != 0.0 and absf(fs) > 3.0:
		tot_t += up * (-_steer_bias * mass * 6.0)
	# subclass hook (bike lean, wheelie, ...)
	tot_t += _extra_torque(dt, b, lav, fs, grounded)

	apply_central_force(tot_f)
	apply_torque(tot_t)
	_cache_f = tot_f
	_cache_t = tot_t
	_cache_ok = true
	if visual_lod == 0:
		_update_visuals(dt, fs)
		_wheel_fx(dt, speed)


func _extra_torque(_dt: float, _b: Basis, _lav: Vector3, _fs: float, _grounded: int) -> Vector3:
	return Vector3.ZERO


func _is_settled() -> bool:
	return grounded_count >= _n_wheels - 1


func _update_surface(w: VehicleWheel, collider: Object) -> void:
	var sname: StringName = &"road"
	if collider != null:
		if collider.has_meta("surface"):
			sname = collider.get_meta("surface")
		elif collider is Node:
			var nm := String((collider as Node).name).to_lower()
			if nm.contains("grass") or nm.contains("park") or nm.contains("lawn"):
				sname = &"grass"
			elif nm.contains("sand") or nm.contains("beach"):
				sname = &"sand"
			elif nm.contains("dirt") or nm.contains("hill") or nm.contains("terrain"):
				sname = &"dirt"
	w.surface = sname
	w.surface_mult = SURFACE_GRIP.get(sname, 1.0)


func _ackermann(w: VehicleWheel, steer: float) -> float:
	if absf(steer) < 0.001 or w.side == 0.0:
		return steer
	var t := tan(absf(steer))
	var half := track_w * 0.5
	var inner := w.side * signf(steer) > 0.0
	var denom := wheelbase - (half * t if inner else -half * t)
	return signf(steer) * atan(wheelbase * t / maxf(denom, 0.3))


# ---- driver intent -----------------------------------------------------------------------------------------------------------------
func _update_pedals(fs: float) -> void:
	var thr_in := clampf(input_throttle, 0.0, 1.0)
	var brk_in := clampf(input_brake, 0.0, 1.0)
	if not _rev:
		if brk_in > 0.05 and thr_in < 0.05 and fs < 1.0:
			_rev = true
	else:
		if thr_in > 0.05 and brk_in < 0.05 and fs > -1.0:
			_rev = false
	if _rev:
		_thr = brk_in
		_brk = thr_in if fs < -0.5 else 0.0
	else:
		_thr = thr_in
		_brk = brk_in
	if is_destroyed or (driver == null and not is_ai_controlled):
		_thr = 0.0
		_brk = 0.0 if driver == null else _brk
	braking = (_brk > 0.05 and not _rev) or (_rev and fs < -0.5 and thr_in > 0.05) or input_handbrake


func _update_steer(dt: float, fs: float) -> void:
	var v := absf(fs)
	var limit := steer_gain * wheelbase * lat_accel_limit / (v * v + 4.0)
	var max_ang := clampf(limit, steer_min, steer_lock)
	var target := clampf(input_steer, -1.0, 1.0) * max_ang
	# digital keys: ease in; centring is quicker than turn-in
	var rate := lerpf(3.2, 1.5, clampf(v / 35.0, 0.0, 1.0)) * steer_lock
	if absf(target) < absf(_steer) or signf(target) != signf(_steer):
		rate *= 1.8
	_steer = move_toward(_steer, target, rate * dt)
	if absf(_steer) > max_ang:
		_steer = signf(_steer) * max_ang


## Garage turbo upgrade: boost spools up under hard throttle at mid/high revs (mod_turbo_spool slows it), drops fast when lifting
## (blow-off whistle). Returns the power multiplier (1.0 without a turbo).
var turbo_level := 0.0                # 0..1 current boost


func _turbo_factor(dt: float, thr: float, rpm01: float) -> float:
	if mod_turbo_boost <= 0.0:
		turbo_level = 0.0
		return 1.0
	var target := clampf((thr - 0.55) / 0.45, 0.0, 1.0) * clampf((rpm01 - 0.25) / 0.3, 0.0, 1.0)
	var rate := 1.0 / (0.9 * maxf(mod_turbo_spool, 0.2)) if target > turbo_level else 1.0 / 0.3
	var before := turbo_level
	turbo_level = move_toward(turbo_level, target, rate * dt)
	if before >= 0.6 and turbo_level < 0.6 and thr < 0.3 and audio != null:
		audio._snd(&"turbo_whistle", -8.0, 1.0, 45.0)
	return 1.0 + mod_turbo_boost * turbo_level


## Returns the total drive force at the wheels (N, + forward, - reverse) and advances rpm / gear.
func _update_engine(dt: float, fs: float) -> float:
	var thr := _thr
	if not engine_on or is_destroyed:
		rpm = move_toward(rpm, 0.0, 3000.0 * dt)
		gear = 1 if not _rev else -1
		return 0.0
	# gear selection
	if _rev:
		gear = -1
	else:
		if gear < 1:
			gear = 1
		_shift_timer = maxf(_shift_timer - dt, 0.0)
		_gear_hold = maxf(_gear_hold - dt, 0.0)
		if _shift_timer <= 0.0 and _gear_hold <= 0.0:
			var n := gear_ratios.size()
			var up_rpm := lerpf(0.58, 0.92, clampf(thr * 1.2, 0.0, 1.0)) * rpm_red
			var dn_rpm := lerpf(0.26, 0.5, clampf(thr * 1.2, 0.0, 1.0)) * rpm_red
			if rpm > up_rpm and gear < n and thr > 0.05:
				gear += 1
				_shift_timer = 0.2 * mod_shift
				_gear_hold = 0.5
			elif gear > 1 and rpm < dn_rpm:
				gear -= 1
				_gear_hold = 0.35
	var g_total := rev_ratio if gear < 0 else gear_ratios[clampi(gear - 1, 0, gear_ratios.size() - 1)] / mod_topspeed
	# engine speed follows the driven wheels (with a launch "clutch slip" floor)
	var wsum := 0.0
	var wn := 0
	for w in wheels:
		if w.driven:
			wsum += absf(w.w)
			wn += 1
	var wheel_rpm := (wsum / maxf(float(wn), 1.0)) * g_total * 60.0 / TAU
	var launch := rpm_idle + thr * (float(def.get("launch_rpm", 2600.0)) - rpm_idle)
	var target := maxf(wheel_rpm, maxf(rpm_idle, launch if _shift_timer <= 0.0 else rpm_idle))
	rpm = lerpf(rpm, minf(target, rpm_red * 1.03), 1.0 - exp(-13.0 * dt))
	if rpm < rpm_idle:
		rpm = rpm_idle
	# torque
	var x := rpm / rpm_red
	var curve := clampf(1.0 - 1.875 * (x - 0.6) * (x - 0.6), 0.25, 1.0)
	var limiter := clampf((rpm_red * 0.99 - rpm) / (rpm_red * 0.05), 0.0, 1.0)
	var tq := 0.0
	if _shift_timer > 0.0:
		tq = 0.0
	elif thr > 0.02:
		tq = torque_peak * curve * thr * limiter * power_scale * mod_power * _turbo_factor(dt, thr, x)
	else:
		tq = -torque_peak * 0.17 * clampf(rpm / rpm_red, 0.0, 1.0)
		if turbo_level > 0.0:
			_turbo_factor(dt, 0.0, x)
	var f := tq * g_total * 0.9 / drive_radius
	if gear < 0:
		f = -f
		if fs < -reverse_max:
			f = 0.0
	drive_force_dbg = f
	return f


# ---- visuals -------------------------------------------------------------------------------------------------------------------------
func _update_visuals(dt: float, _fs: float) -> void:
	for w in wheels:
		if w.node == null:
			continue
		w.spin = fposmod(w.spin + w.w * dt, TAU)
		var pos := w.hp - Vector3.UP * w.length
		var basis_ := Basis(Vector3.UP, -w.steer_angle) * Basis(Vector3.RIGHT, -w.spin) * w.rest_basis
		w.node.transform = Transform3D(basis_, pos)
	_update_extra_visuals(dt)


func _update_extra_visuals(_dt: float) -> void:
	pass


func _wheel_fx(dt: float, speed: float) -> void:
	var fx: VehicleFx = VehicleFx.inst
	if fx == null:
		return
	for w in wheels:
		if not w.grounded:
			w.skid_active = false
			continue
		if w.slip > 0.42 and speed > 2.5:
			var pos := w.contact + w.normal * 0.025
			if not w.skid_active:
				w.skid_active = true
				w.skid_last = pos
			elif pos.distance_squared_to(w.skid_last) > 0.16:
				var dir := (pos - w.skid_last)
				fx.skid_segment(w.skid_last, pos, w.normal, w.width * 0.9, clampf(w.slip, 0.3, 1.0))
				w.skid_last = pos
			w.smoke_acc += dt * (8.0 + w.slip * 22.0) * (0.6 + speed * 0.04)
			while w.smoke_acc >= 1.0:
				w.smoke_acc -= 1.0
				fx.tire_smoke(w.contact, linear_velocity * 0.35 + Vector3(randf_range(-0.6, 0.6), randf_range(0.4, 1.2), randf_range(-0.6, 0.6)), w.slip)
		else:
			w.skid_active = false
			if w.surface_mult < 0.85 and speed > 6.0 and absf(w.w) > 3.0:
				w.smoke_acc += dt * 6.0 * minf(speed / 20.0, 1.0)
				while w.smoke_acc >= 1.0:
					w.smoke_acc -= 1.0
					fx.dust(w.contact, linear_velocity * 0.15 + Vector3(randf_range(-0.5, 0.5), randf_range(0.5, 1.4), randf_range(-0.5, 0.5)), w.surface)


func _on_crash(impact: float) -> void:
	# wake wheels' slip so tyres squeal after a big hit
	if impact > 6.0:
		skid_level = 1.0


## Drift-friendly helper for AI / tests: signed slip angle of the body (rad) between heading and velocity.
func get_slip_angle() -> float:
	var v := linear_velocity
	v.y = 0.0
	if v.length() < 2.0:
		return 0.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return fwd.signed_angle_to(v.normalized(), Vector3.UP)


func get_wheel_count() -> int:
	return wheels.size()
