class_name PlaneVehicle
extends VehicleBase
## Fixed-wing aircraft (plane_prop, plane_jet) on a RigidBody3D (Air&Sea agent).
##   * thrust (prop: static thrust fading with airspeed / jet: dry + afterburner), lift from airspeed and angle of attack with a
##     real stall (lift collapses, nose drops, control authority drops), induced + parasite drag, sideslip restoring force;
##   * control authority scales with dynamic pressure (prop slipstream helps at low speed); pitch / roll / yaw are rate commands with
##     arcade auto-stabilisation (wings level, flight-path hold, coordinated turns) - Shift/Ctrl throttle, W/S pitch, A/D roll, Q/E yaw;
##   * three-wheel raycast gear: spring / damper, rolling resistance, brakes, nose-wheel steering, touchdown sink-rate damage;
##   * crash on buildings / terrain (-> VehicleBase.explode), bail-out by holding F, airspace limits, control-surface + prop animation.
## Inputs: input_throttle (target 0..1), input_brake, input_steer / input_yaw, input_pitch (+1 nose up), input_roll (+1 right).

const GRAV := 9.81
const RHO := 1.225

# ---- tunables (def) ----------------------------------------------------------------------------------------------------------------
var wing_area := 12.0
var stall_speed := 33.0            # m/s, 1 g, level
var cl_slope := 5.0                # per rad
var cl_max := 1.3
var alpha0 := -0.04                # zero-lift angle (rad), EFFECTIVE value (base incidence minus the automatic flaps)
var alpha0_base := -0.04           # wing incidence of the def
var flap_alpha := 0.09             # extra zero-lift shift of the automatic flaps (full below 1.2 Vs, retracted above 1.75 Vs)
var flap := 0.0                    # 0..1 flap state
var alpha_stall := 0.22            # rad (derived)
var cd0 := 0.036
var induced_k := 0.06
var thrust_n := 7500.0
var thrust_v0 := 90.0
var engine_lag := 1.1
var pitch_rate := 0.95
var roll_rate := 2.2
var yaw_rate := 0.55
var is_jet := false
var afterburner := 0.0
var assist := 1.0
var hard_land_sink := 3.2
var crash_land_sink := 9.5
var inertia_v := Vector3(3800, 7200, 5400)
var vref := 50.0                   # airspeed with full control authority
var prop_slip := 13.0              # m/s of slipstream over the tail at full throttle (props)
var steer_lock := deg_to_rad(30.0)
var brake_decel := 7.5
var bank_lim := deg_to_rad(56.0)    # maximum bank angle the roll stick commands (assist)
var tail_clear := 0.0               # rad: pitch at which the aft fuselage touches the runway (computed from the collision boxes)
var _tail_z := 0.0                  # the critical aft collision point (vehicle space): behind the origin / above the ground
var _tail_y := 0.0
var rot_speed_k := 1.0              # arcade take-off: rotation starts at this multiple of the stall speed
var rot_rate := 0.45                # ... with this pitch rate (rad/s)
var climb_gamma := deg_to_rad(10.0) # climb path the neutral stick settles on shortly after lift-off

# ---- state ---------------------------------------------------------------------------------------------------------------------------------------
var throttle_state := 0.0          # spooled engine power 0..1
var engine_failed := false
var grounded_count := 0
var on_ground := true
var airborne_time := 0.0
var ground_time := 0.0
var airspeed := 0.0
var aoa := 0.0
var sideslip := 0.0
var stalled := 0.0                 # 0..1
var g_load := 1.0
var agl := 100.0
var last_touchdown_sink := 0.0
var bail_progress := 0.0
var takeoff_x := 0.0
var gears: Array = []
var steer_state := 0.0
var rpm01 := 0.0
var ai: Node = null
var burner := 0.0                  # 0..1 afterburner visual / audio state

var _query: PhysicsRayQueryParameters3D = null
var _t := 0.0
var _agl_t := 0.0
var _airspace := {}
var _bail_t := 0.0
var _stall_warn_cd := 0.0
var _scrape_t := 0.0
var _scrape_total := 0.0
var _roll_hold := 0.0
var _rollover := false
var _warned_exit_t := -10.0
var _fx_t := 0.0
var _prop_node: Node3D = null
var _prop_rest := Basis.IDENTITY
var _prop_angle := 0.0
var _prop_blur: MeshInstance3D = null
var _blur_mat: StandardMaterial3D = null
var _ail_l: Node3D = null
var _ail_r: Node3D = null
var _elev: Node3D = null
var _rudd: Node3D = null
var _ail_rest: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _elev_rest := Basis.IDENTITY
var _rudd_rest := Basis.IDENTITY
var _defl := Vector3.ZERO          # smoothed (aileron, elevator, rudder) deflection, rad
var _burner_nodes: Array[MeshInstance3D] = []
var _burner_mat: StandardMaterial3D = null
var _burner_light: OmniLight3D = null
var _nav_t := 0.0
var _nav_mats: Dictionary = {}
var _nav_surfs: Array = []
var _nav_scanned := false
var _nav_on := false


# =====================================================================================================
# Setup
# =====================================================================================================
func setup_air() -> void:
	mass = float(def.get("mass", 1100.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = def.get("com", Vector3(0, 1.0, 0))
	inertia_v = def.get("inertia", inertia_v)
	inertia = inertia_v
	angular_damp = 0.02
	wing_area = float(def.get("wing_area", wing_area))
	stall_speed = float(def.get("stall_kmh", 120.0)) / 3.6
	cl_slope = float(def.get("cl_slope", cl_slope))
	alpha0_base = float(def.get("alpha0", alpha0_base))     # wing incidence: more negative = more lift at ground attitude (shorter take-off)
	alpha0 = alpha0_base
	flap_alpha = float(def.get("flap_alpha", flap_alpha))
	bank_lim = deg_to_rad(float(def.get("bank_limit_deg", 56.0)))
	rot_rate = float(def.get("rot_rate", rot_rate))
	rot_speed_k = float(def.get("rot_speed_k", rot_speed_k))
	climb_gamma = deg_to_rad(float(def.get("climb_deg", 10.0)))
	cd0 = float(def.get("cd0", cd0))
	induced_k = float(def.get("induced_k", induced_k))
	thrust_n = float(def.get("thrust_n", thrust_n))
	thrust_v0 = float(def.get("thrust_v0", thrust_v0))
	engine_lag = float(def.get("engine_lag", engine_lag))
	pitch_rate = float(def.get("pitch_rate", pitch_rate))
	roll_rate = float(def.get("roll_rate", roll_rate))
	yaw_rate = float(def.get("yaw_rate", yaw_rate))
	afterburner = float(def.get("afterburner", 0.0))
	is_jet = String(def.get("engine", "")) == "jet"
	hard_land_sink = float(def.get("hard_landing", hard_land_sink))
	crash_land_sink = float(def.get("crash_landing", crash_land_sink))
	var g_eff := GRAV * gravity_scale
	cl_max = 2.0 * mass * g_eff / (RHO * wing_area * stall_speed * stall_speed)
	alpha_stall = cl_max / cl_slope + alpha0
	vref = stall_speed * 1.5
	prop_slip = 0.0 if is_jet else 13.0
	run_over_enabled = true
	_find_parts()
	_build_gears()
	_build_effects()
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = GC.M_GROUND
	_query.exclude = [get_rid()]
	_airspace = {"cd": 0.0}
	# setup_air runs from VehicleFactory._build BEFORE the body is in the tree: global_position would raise
	# "!is_inside_tree()" - use the local transform (the body's parent is the identity-placed container).
	takeoff_x = global_position.x if is_inside_tree() else transform.origin.x


func _find_parts() -> void:
	_prop_node = model.find_child("Prop", true, false) as Node3D
	if _prop_node != null:
		_prop_rest = _prop_node.transform.basis
	_ail_l = model.find_child("Aileron_L", true, false) as Node3D
	_ail_r = model.find_child("Aileron_R", true, false) as Node3D
	_elev = model.find_child("Elevator", true, false) as Node3D
	_rudd = model.find_child("Rudder", true, false) as Node3D
	if _ail_l != null:
		_ail_rest[0] = _ail_l.transform.basis
	if _ail_r != null:
		_ail_rest[1] = _ail_r.transform.basis
	if _elev != null:
		_elev_rest = _elev.transform.basis
	if _rudd != null:
		_rudd_rest = _rudd.transform.basis


func _build_gears() -> void:
	gears.clear()
	for wn in ["Wheel_F", "Wheel_RL", "Wheel_RR"]:
		var node := model.find_child(wn, true, false) as Node3D
		if node == null:
			continue
		var bb := VehicleFactory._subtree_aabb(model, node)
		var radius := maxf(bb.size.y, bb.size.z) * 0.5
		if radius < 0.1 or radius > 1.0:
			radius = 0.3
		var centre := Util._rel_transform(model, node).origin
		var rest := 0.2
		var g := AirCommon.make_gear(StringName(wn), centre + Vector3(0, rest, 0), radius, 0.4, rest, node)
		g.steered = wn == "Wheel_F"
		gears.append(g)
	if gears.size() != 3:
		push_warning("PlaneVehicle[%s]: expected Wheel_F / Wheel_RL / Wheel_RR, found %d gear nodes" % [def_id, gears.size()])
	AirCommon.static_shares(gears, center_of_mass)
	AirCommon.tune_springs(gears, mass, GRAV * gravity_scale, 1.9, 0.5)
	# tail clearance angle: rotation about the main wheels before the aft fuselage touches the ground
	var axle_z := 0.0
	var n_main := 0
	for g in gears:
		var gg := g as AirCommon.Gear
		if not gg.steered:
			axle_z += gg.top.z
			n_main += 1
	if n_main > 0:
		axle_z /= float(n_main)
	tail_clear = 0.0
	var best := 1.0
	_tail_z = 0.0
	_tail_y = 0.0
	for b in def.get("col_boxes", []):
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		var zmax := c.z + s.z * 0.5
		var ymin := c.y - s.y * 0.5
		if zmax > axle_z + 0.5 and ymin > 0.0:
			var ang := atan2(ymin, zmax - axle_z)
			if ang < best:
				best = ang
				_tail_z = zmax
				_tail_y = ymin
	if best < 1.0:
		tail_clear = best


func _build_effects() -> void:
	_blur_mat = StandardMaterial3D.new()
	_blur_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blur_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blur_mat.albedo_color = Color(0.1, 0.11, 0.13, 0.0)
	_blur_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_blur_mat.disable_receive_shadows = true
	if _prop_node != null and not is_jet:
		var cm := CylinderMesh.new()
		cm.top_radius = float(def.get("prop_radius", 0.95))
		cm.bottom_radius = cm.top_radius
		cm.height = 0.02
		cm.radial_segments = 20
		_prop_blur = MeshInstance3D.new()
		_prop_blur.name = "PropBlur"
		_prop_blur.mesh = cm
		_prop_blur.material_override = _blur_mat
		_prop_blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_prop_blur.position = _prop_node.transform.origin + Vector3(0, 0, -0.04)
		_prop_blur.rotation = Vector3(PI * 0.5, 0, 0)
		_prop_blur.visible = false
		model.add_child(_prop_blur)
	if is_jet:
		_burner_mat = StandardMaterial3D.new()
		_burner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_burner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_burner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_burner_mat.albedo_color = Color(1.0, 0.62, 0.22, 0.85)
		_burner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for en in ["ExhaustL", "ExhaustR"]:
			var n := model.find_child(en, true, false) as Node3D
			if n == null:
				continue
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.34
			cone.height = 1.0
			cone.radial_segments = 8
			var mi := MeshInstance3D.new()
			mi.name = "Burner_" + en
			mi.mesh = cone
			mi.material_override = _burner_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = n.transform.origin + Vector3(0, 0, 0.55)
			mi.rotation = Vector3(PI * 0.5, 0, 0)       # apex points backwards (+Z)
			mi.visible = false
			mi.set_meta(&"anchor", mi.position)
			model.add_child(mi)
			_burner_nodes.append(mi)


func _reset_extra() -> void:
	throttle_state = 0.0
	engine_failed = false
	airborne_time = 0.0
	ground_time = 0.0
	stalled = 0.0
	steer_state = 0.0
	rpm01 = 0.0
	burner = 0.0
	bail_progress = 0.0
	if ai != null and is_instance_valid(ai):
		ai.queue_free()
	ai = null


func _is_settled() -> bool:
	return grounded_count >= 3 and airspeed < 1.0 and throttle_state < 0.03


# =====================================================================================================
# VehicleBase overrides
# =====================================================================================================
func get_rpm01() -> float:
	return rpm01


func get_engine_load() -> float:
	return clampf(throttle_state, 0.0, 1.0)


func is_airborne() -> bool:
	return not on_ground


func can_be_entered_by(character: Node) -> bool:
	if not super.can_be_entered_by(character):
		return false
	return on_ground or agl < 3.0


func enter(character: Node, seat: int = 0, animated: bool = false) -> bool:
	var ok := super.enter(character, seat, animated)
	if ok:
		wake()
		sleeping = false
	return ok


func get_interaction(character: Node) -> Dictionary:
	var d := super.get_interaction(character)
	if str(d.get("text", "")).begins_with("Enter "):
		d["text"] = "Fly " + display_name
	return d


func _report_theft(character: Node) -> void:
	if is_stolen or abandoned or is_player_owned:
		return
	is_stolen = true
	var crime: StringName = GC.CRIME_POLICE_VEHICLE_THEFT if faction == GC.F_POLICE else GC.CRIME_AIRCRAFT_THEFT
	Events.crime_committed.emit(crime, global_position, character, {"vehicle": self, "witnessed_by_npc": false, "severity": 1.5})


func exit(character: Node, forced: bool = false, carjack_exit: bool = false) -> void:
	if not forced and not is_destroyed and (not on_ground or airspeed > 9.0):
		if _is_player(character):
			var now := Time.get_ticks_msec() * 0.001
			if now - _warned_exit_t > 3.0:
				_warned_exit_t = now
				if on_ground:
					AirCommon.notify("Stop the aircraft first (hold the brake)", &"warn")
				else:
					AirCommon.notify("In flight - HOLD F to bail out (parachute)", &"warn")
		return
	super.exit(character, forced, carjack_exit)


func _is_player(c: Node) -> bool:
	return c != null and is_instance_valid(c) and c.has_method("is_player") and c.is_player()


func get_camera_hints() -> Dictionary:
	var sp := clampf(get_speed() / 120.0, 0.0, 1.0)
	return {
		"distance": float(def.get("cam_distance", 15.0)) * (1.0 + sp * 0.18),
		"height": float(def.get("cam_height", 4.6)),
		"look_ahead": float(def.get("cam_look_ahead", 5.0)) * (0.4 + sp),
		"fov": float(def.get("cam_fov", 72.0)) + sp * 12.0,
		"shake": clampf(sp * 0.10 + stalled * 0.35 + burner * 0.04, 0.0, 0.6),
		"speed_kmh": get_speed_kmh(),
		"first_person_offset": (seats[0]["pos"] as Vector3) + Vector3(0, 0.62, -0.25) if seats.size() > 0 else Vector3(0, 1.8, -1.0),
	}


# =====================================================================================================
# Aerodynamics
# =====================================================================================================
func lift_coefficient(a: float) -> float:
	var x := a - alpha0
	var lim := alpha_stall - alpha0
	if absf(x) <= lim:
		return cl_slope * x
	var s := smoothstep(lim, lim + 0.14, absf(x))
	var cl_p := lerpf(cl_max, cl_max * 0.55, s)
	if absf(x) > lim + 0.5:
		cl_p = lerpf(cl_p, sin(2.0 * absf(x)) * 0.8, clampf((absf(x) - lim - 0.5) / 0.6, 0.0, 1.0))
	return signf(x) * cl_p


func thrust_at(v_fwd: float) -> float:
	var t := throttle_state
	if engine_failed or is_destroyed or not engine_on:
		return 0.0
	var fade := maxf(0.0, 1.0 - maxf(v_fwd, 0.0) / thrust_v0)
	if is_jet:
		var ab := smoothstep(0.75, 0.95, t) if afterburner > 0.0 else 0.0
		return thrust_n * lerpf(t * 0.6, 1.0, ab) * fade
	return thrust_n * t * fade


func _simulate(dt: float) -> void:
	if _query == null or gears.is_empty():
		return
	_t += dt
	if sleeping:
		sleeping = false
	var xf := global_transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var lv := linear_velocity
	var g_eff := GRAV * gravity_scale
	var piloted := driver != null or is_ai_controlled
	_agl_t -= dt
	if _agl_t <= 0.0:
		_agl_t = 0.1
		agl = AirCommon.agl_of(self, [self])
	# ---- engine ------------------------------------------------------------------------------------------------------------------------------
	var thr_in := clampf(input_throttle, 0.0, 1.0) if piloted else 0.0
	if not engine_on or engine_failed or is_destroyed:
		thr_in = 0.0
	throttle_state = Util.damp(throttle_state, thr_in, 1.0 / maxf(engine_lag, 0.1) * 2.2, dt)
	if throttle_state < 0.002 and thr_in == 0.0:
		throttle_state = 0.0
	var target_rpm := 0.0
	if engine_on and not is_destroyed:
		target_rpm = 0.22 + 0.78 * throttle_state if not engine_failed else (0.18 + 0.4 * clampf(airspeed / 60.0, 0.0, 1.0))
	rpm01 = Util.damp(rpm01, target_rpm, 3.5, dt)
	burner = Util.damp(burner, smoothstep(0.75, 0.95, throttle_state) if (is_jet and engine_on and not engine_failed) else 0.0, 6.0, dt)
	if not engine_failed and not is_destroyed and get_health_ratio() < 0.18:
		engine_failed = true
		if _is_player(driver):
			AirCommon.notify("Engine failure!", &"bad")
	if is_destroyed:
		engine_on = false
		_update_visuals(dt)
		return
	# ---- air data ----------------------------------------------------------------------------------------------------------------------------
	var wind := AirCommon.wind_ms()
	var vrel := lv - wind
	var vb := b.inverse() * vrel
	var v_fwd := -vb.z
	var spd := vrel.length()
	airspeed = spd
	# automatic flaps (arcade): extra lift at low speed so that the aircraft leaves the runway before its tail touches it
	flap = Util.damp(flap, clampf((stall_speed * 1.75 - spd) / (stall_speed * 0.55), 0.0, 1.0), 2.5, dt)
	alpha0 = alpha0_base - flap * flap_alpha
	alpha_stall = cl_max / cl_slope + alpha0
	aoa = atan2(-vb.y, maxf(v_fwd, 0.5)) if v_fwd > 0.5 else 0.0
	sideslip = atan2(vb.x, maxf(v_fwd, 0.5)) if v_fwd > 0.5 else 0.0
	var q := 0.5 * RHO * spd * spd
	# ---- landing gear ---------------------------------------------------------------------------------------------------------------
	var ground_speed := Vector2(lv.x, lv.z).length()
	var brake_cmd := clampf(input_brake, 0.0, 1.0) if piloted else 0.0
	if input_handbrake:
		brake_cmd = 1.0
	var parked := driver == null and not is_ai_controlled
	if piloted and thr_in < 0.04 and ground_speed < 7.0:
		brake_cmd = maxf(brake_cmd, 0.5)             # idle: do not creep
	if parked:
		brake_cmd = 1.0
	var steer_in := clampf(input_steer + input_yaw * 0.6 + input_roll * 0.45, -1.0, 1.0) if piloted else 0.0
	var steer_lim := lerpf(steer_lock, deg_to_rad(3.5), clampf(ground_speed / 32.0, 0.0, 1.0))
	steer_state = move_toward(steer_state, steer_in * steer_lim, dt * deg_to_rad(95.0))
	var gr := AirCommon.step_gears(self, gears, dt, _query, {
		"mu": 1.0, "roll": 0.028, "brake": brake_cmd, "brake_decel": brake_decel, "steer": steer_state, "hold": parked or (piloted and brake_cmd > 0.9 and thr_in < 0.05), "lift": 0.55})
	var was_ground := grounded_count > 0
	grounded_count = int(gr["grounded"])
	on_ground = grounded_count > 0
	if on_ground:
		ground_time += dt
		if not was_ground and airborne_time > 0.4:
			_on_touchdown(float(gr["touchdown"]))
		airborne_time = 0.0
	else:
		airborne_time += dt
		ground_time = 0.0
	apply_central_force(gr["f"])
	apply_torque(gr["t"])
	run_over_enabled = on_ground
	# ---- aerodynamic forces -------------------------------------------------------------------------------------------------------
	var bank := AirCommon.bank_of(b)
	var pitch := AirCommon.pitch_of(b)
	var vdir := vrel / spd if spd > 0.5 else fwd
	if spd > 0.5:
		var cl := lift_coefficient(aoa)
		var cd := cd0 + induced_k * cl * cl
		var xa := absf(aoa - alpha0)
		var lim := alpha_stall - alpha0
		stalled = smoothstep(lim - 0.015, lim + 0.07, xa) if v_fwd > 0.5 else 1.0
		if xa > lim:
			cd += 0.9 * (sin(xa) * sin(xa)) * smoothstep(0.0, 0.3, xa - lim)
		var l_dir := b.x.cross(vdir)
		l_dir = l_dir.normalized() if l_dir.length_squared() > 1e-4 else up
		var lift_f := l_dir * (q * wing_area * cl)
		var drag_f := -vdir * (q * wing_area * cd)
		var side_f := -b.x * (q * wing_area * 1.1 * sin(sideslip)) if v_fwd > 0.5 else Vector3.ZERO
		apply_central_force(lift_f + drag_f + side_f)
		g_load = lerpf(g_load, lift_f.dot(up) / (mass * g_eff), 0.2)
	else:
		stalled = 1.0 if not on_ground else 0.0
	apply_central_force(fwd * thrust_at(v_fwd))
	# ---- control torques --------------------------------------------------------------------------------------------------------------
	var stab := AirCommon.stability_mult()
	var v_eff := sqrt(spd * spd + (prop_slip * throttle_state) * (prop_slip * throttle_state))
	var auth := clampf((v_eff * v_eff) / (vref * vref), 0.0, 1.0)
	var auth_hard := auth * (1.0 - 0.6 * stalled)
	var in_p := clampf(input_pitch, -1.0, 1.0) if piloted else 0.0
	var in_r := clampf(input_roll, -1.0, 1.0) if piloted else 0.0
	var in_y := clampf(input_yaw, -1.0, 1.0) if piloted else 0.0
	var lav := b.inverse() * angular_velocity
	var airborne := not on_ground
	# pitch: rate command; neutral stick = arcade flight-path levelling (the climb / dive angle fades with a 3.5 s time constant and the
	# nose never rises past 82 % of the stalling angle on its own); stall nose drop
	var wx := in_p * pitch_rate * auth_hard
	if absf(in_p) < 0.05 and airborne and q > 80.0 and assist > 0.0:
		var gamma := atan2(vrel.y, maxf(Vector2(vrel.x, vrel.z).length(), 1.0))
		# take-off climb assist: shortly after lift-off with a neutral stick the path settles at +9 deg (clears the end of the runway)
		var gamma_t := climb_gamma * clampf(1.0 - airborne_time / 14.0, 0.0, 1.0) * (1.0 if (agl < 55.0 and spd > stall_speed * 1.05) else 0.0)
		var tau := lerpf(2.0, 3.5, clampf(agl / 30.0, 0.0, 1.0))          # a brisker initial climb-out clears the airfield fence
		var l_need := mass * (g_eff * cos(gamma) - spd * (gamma - gamma_t) / tau) / maxf(cos(bank), 0.35)
		var a_level := clampf(l_need / (q * wing_area * cl_slope) + alpha0, -0.08, alpha_stall * 0.82)
		wx += clampf(1.7 * (a_level - aoa), -0.6, 0.6) * auth * assist
		# feed-forward: in a banked turn part of the turn rate is a pitch rate about the body axis; without it the controller sits
		# 1 deg of angle of attack short and the aircraft sinks through every turn
		wx += angular_velocity.y * b.x.y * assist
	elif absf(in_p) < 0.05 and on_ground and assist > 0.0 and throttle_state > 0.85 and spd > stall_speed * rot_speed_k and ground_time > 0.5:
		# arcade take-off: with the throttle wide open and the stick neutral the nose comes up by itself at rotation speed
		wx += rot_rate * clampf((spd - stall_speed * rot_speed_k) / (stall_speed * 0.06), 0.0, 1.0)
	# tail-strike protection for a neutral stick: close to the ground the nose never rises past the tail clearance angle
	if assist > 0.0 and absf(in_p) < 0.05 and agl < 7.0 and _tail_z > 0.0:
		# the pitch where the aft fuselage would be 0.12 m above the ground, from the live altitude (frees itself while climbing out)
		var lim := 0.45
		for k in 40:
			var th := 0.02 + 0.012 * float(k)
			if agl + _tail_y * cos(th) - _tail_z * sin(th) < 0.12:
				lim = th - 0.012
				break
		if pitch > lim:
			wx = minf(wx, -3.0 * (pitch - lim))
		elif wx > 0.0 and pitch > lim - 0.04:
			wx *= clampf((lim - pitch) / 0.04, 0.0, 1.0)
	wx -= stalled * 0.85 * (1.0 if airborne else 0.0)
	# roll: A / D command a BANK ANGLE (up to 56 deg) and the plane holds it; keep holding at the limit for 0.8 s to roll over
	# (rate command); neutral stick = wings level
	var wz := 0.0
	if assist > 0.5 and airborne:
		if absf(in_r) > 0.6 and absf(bank) > bank_lim * 0.92:
			_roll_hold += dt
		else:
			_roll_hold = maxf(_roll_hold - dt * 2.0, 0.0)
		if _roll_hold > 0.8:
			_rollover = true
		if absf(in_r) < 0.15:
			_rollover = false
			_roll_hold = 0.0
		if _rollover:
			wz = -in_r * roll_rate * auth_hard
		else:
			var bank_t := in_r * bank_lim
			wz = clampf(3.2 * (bank - bank_t), -roll_rate, roll_rate) * auth_hard
			if absf(in_r) < 0.05:
				wz = clampf(2.4 * bank, -roll_rate * 0.8, roll_rate * 0.8) * auth
	else:
		wz = -in_r * roll_rate * auth_hard
	# yaw: rudder + weathervane (sideslip -> nose follows the flight path = coordinated turns)
	var wy := -in_y * yaw_rate * auth_hard
	if airborne and spd > 12.0:
		wy += -clampf(3.0 * sideslip, -0.8, 0.8) * auth * stab
		wy += -clampf(bank, -1.0, 1.0) * 0.12 * auth * assist * (1.0 if absf(in_y) < 0.05 else 0.0)
	var ctl := clampf(maxf(auth_hard, 0.3), 0.0, 1.0) if airborne else auth_hard      # a floor of damping in the air; on the wheels only real airflow counts
	var kx := 6.0
	var kz := 8.0
	var ky := 4.0
	var tq := Vector3((wx - lav.x) * kx * ctl, (wy - lav.y) * ky * maxf(ctl, 0.0), (wz - lav.z) * kz * ctl)
	# turbulence
	if airborne and spd > 15.0:
		var turb := (0.12 + wind.length() * 0.03) * stab
		tq.x += sin(_t * 1.9 + 0.3) * 0.35 * turb
		tq.z += cos(_t * 1.5 + 1.0) * 0.5 * turb
		apply_central_force(Vector3(sin(_t * 0.9), sin(_t * 1.3 + 2.0) * 0.5, cos(_t * 0.7)) * mass * turb * 1.5)
	apply_torque(b * Vector3(tq.x * inertia_v.x, tq.y * inertia_v.y, tq.z * inertia_v.z))
	# stall feedback
	_stall_warn_cd -= dt
	if stalled > 0.7 and airborne and _is_player(driver) and _stall_warn_cd <= 0.0:
		_stall_warn_cd = 4.0
		AirCommon.notify("STALL - nose down, add power", &"bad")
	# ---- hazards ------------------------------------------------------------------------------------------------------------------------------
	if not on_ground and linear_velocity.length() > 22.0 and get_contact_count() > 0:
		# fuselage / tail / wing dragging over the ground or a wall without the wheels: damage grows with the time and the speed
		_scrape_t += dt
		_scrape_total += dt
		if _scrape_t > 0.2:
			_scrape_t = 0.0
			_apply_health_loss(max_health * (0.07 + 0.1 * clampf(airspeed / 60.0, 0.0, 1.0)), null, {"type": GC.DMG_COLLISION, "position": global_position})
			if VehicleFx.inst != null:
				VehicleFx.inst.spark(global_position + global_transform.basis.z * 3.0 + Vector3.DOWN * 0.3, Vector3.UP, 6)
			if _is_player(driver) and _scrape_total < 0.5:
				AirCommon.notify("Tail strike!", &"warn")
		if _scrape_total > 2.2 and not is_destroyed:
			_apply_health_loss(max_health * 3.0, null, {"type": GC.DMG_COLLISION, "position": global_position})
			return
	else:
		_scrape_t = 0.0
		if on_ground or get_contact_count() == 0:
			_scrape_total = maxf(_scrape_total - dt * 0.5, 0.0)
	if _is_player(driver):
		AirCommon.airspace_tick(self, dt, _airspace)
		_tick_bail(dt)
	else:
		bail_progress = 0.0
	if visual_lod == 0:
		_update_visuals(dt)
		_update_fx(dt)
	else:
		_prop_angle = fposmod(_prop_angle + rpm01 * 120.0 * dt, TAU)


# =====================================================================================================
# Landing, crash, bail
# =====================================================================================================
func _on_touchdown(sink: float) -> void:
	last_touchdown_sink = sink
	if sink > crash_land_sink:
		_apply_health_loss(max_health * 2.0, null, {"type": GC.DMG_COLLISION, "position": global_position})
		return
	if sink > hard_land_sink:
		var d := (sink - hard_land_sink) * max_health * 0.09
		_apply_health_loss(d, null, {"type": GC.DMG_COLLISION, "position": global_position})
		if audio != null:
			audio.play_impact(sink * 1.6)
		if VehicleFx.inst != null:
			VehicleFx.inst.spark(global_position + Vector3.UP * 0.2, Vector3.UP, 8)
		if _is_player(driver):
			AirCommon.notify("Hard landing!", &"warn")
	elif _is_player(driver) and sink < 2.0 and airspeed > 22.0:
		AirCommon.record_flying(2.0)


func _on_crash(impact: float) -> void:
	# fuselage / wing hits: anything faster than ~14 m/s of velocity change at flight speed wrecks the aircraft
	if impact > (14.0 if not on_ground else 20.0):
		_apply_health_loss(max_health * 3.0, null, {"type": GC.DMG_COLLISION, "position": global_position, "impulse": impact * mass})


func _tick_bail(dt: float) -> void:
	if on_ground or agl < 8.0 or airspeed < 5.0:
		bail_progress = 0.0
		_bail_t = 0.0
		return
	if Input.is_action_pressed(&"enter_exit"):
		_bail_t += dt
		bail_progress = clampf(_bail_t / 0.9, 0.0, 1.0)
		if _bail_t >= 0.9:
			_bail_t = 0.0
			bail_progress = 0.0
			bail_out(driver)
	else:
		_bail_t = 0.0
		bail_progress = 0.0


func bail_out(c: Node) -> void:
	AirCommon.bail_out_character(self, c)


# =====================================================================================================
# Visuals
# =====================================================================================================
func _update_visuals(dt: float) -> void:
	# propeller
	_prop_angle = fposmod(_prop_angle + rpm01 * 120.0 * dt, TAU)
	if _prop_node != null and not is_jet:
		_prop_node.transform.basis = _prop_rest * Basis(Vector3.BACK, _prop_angle)
		if _prop_blur != null:
			var a := smoothstep(0.35, 0.8, rpm01) * 0.22
			_blur_mat.albedo_color.a = a
			_prop_blur.visible = a > 0.01
			_prop_node.visible = a < 0.14
	# control surfaces
	var in_r := clampf(input_roll, -1.0, 1.0)
	var in_p := clampf(input_pitch, -1.0, 1.0)
	var in_y := clampf(input_yaw, -1.0, 1.0)
	_defl.x = Util.damp(_defl.x, in_r * 0.5, 9.0, dt)
	_defl.y = Util.damp(_defl.y, in_p * 0.42, 9.0, dt)
	_defl.z = Util.damp(_defl.z, in_y * 0.42, 9.0, dt)
	if _ail_l != null:
		_ail_l.transform.basis = _ail_rest[0] * Basis(Vector3.RIGHT, _defl.x)         # roll right: left aileron trailing edge down
	if _ail_r != null:
		_ail_r.transform.basis = _ail_rest[1] * Basis(Vector3.RIGHT, -_defl.x)        # ... right aileron up
	if _elev != null:
		_elev.transform.basis = _elev_rest * Basis(Vector3.RIGHT, -_defl.y)
	if _rudd != null:
		_rudd.transform.basis = _rudd_rest * Basis(Vector3.UP, _defl.z)
	# wheels: suspension travel, spin, nose-wheel steering
	for g in gears:
		var gg := g as AirCommon.Gear
		if gg.node == null:
			continue
		gg.spin = fposmod(gg.spin + gg.w * dt, TAU)
		var pos := gg.top - Vector3.UP * gg.length
		var bas := Basis(Vector3.UP, -gg.steer_angle if gg.steered else 0.0) * Basis(Vector3.RIGHT, -gg.spin) * gg.node_basis
		gg.node.transform = Transform3D(bas, pos)
	# afterburner flames
	if not _burner_nodes.is_empty():
		var len_ := lerpf(0.35, 2.6, burner) * lerpf(0.6, 1.0, throttle_state)
		for mi in _burner_nodes:
			mi.visible = throttle_state > 0.12 and engine_on and not engine_failed
			mi.scale = Vector3(lerpf(0.5, 1.1, burner), len_ * (0.9 + 0.15 * sin(_t * 47.0)), lerpf(0.5, 1.1, burner))
			var anc: Vector3 = mi.get_meta(&"anchor")
			mi.position = Vector3(anc.x, anc.y, anc.z - 0.55 + len_ * 0.5)
		_burner_mat.albedo_color.a = lerpf(0.25, 0.95, burner)
	_nav_t -= dt
	if _nav_t <= 0.0:
		_nav_t = 0.25
		_tick_nav_lights()


func _tick_nav_lights() -> void:
	# nav lights (the LightRed / LightGreen surfaces of the model): glow while the engine runs. VehicleLights treats LightRed as a
	# siren lamp and keeps it dark, so the aircraft swaps its own emissive materials in (once per state change).
	var on := engine_on and not is_destroyed
	if _nav_surfs.is_empty() and not _nav_scanned:
		_nav_scanned = true
		for mi in ModelLib.meshes(model):
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if m != null and (m.resource_name == "LightRed" or m.resource_name == "LightGreen"):
					_nav_surfs.append([mi, i, m.resource_name == "LightRed"])
	if on == _nav_on:
		return
	_nav_on = on
	if _nav_mats.is_empty():
		for kind in ["red", "green"]:
			var m := StandardMaterial3D.new()
			m.resource_name = "LightRed" if kind == "red" else "LightGreen"
			m.albedo_color = Color(0.5, 0.05, 0.05) if kind == "red" else Color(0.05, 0.45, 0.1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.08) if kind == "red" else Color(0.1, 1.0, 0.25)
			m.emission_energy_multiplier = 3.5
			_nav_mats[kind] = m
	for e in _nav_surfs:
		var mi: MeshInstance3D = e[0]
		if not is_instance_valid(mi):
			continue
		if on:
			mi.set_surface_override_material(e[1], _nav_mats["red" if e[2] else "green"])
		else:
			mi.set_surface_override_material(e[1], null)


func _update_fx(dt: float) -> void:
	_fx_t -= dt
	if _fx_t > 0.0:
		return
	_fx_t = 0.06
	if not on_ground or throttle_state < 0.45 or agl > 4.0:
		return
	# prop wash / jet blast on unpaved ground: dust behind the engine
	var fx := AirFx.get_fx()
	if fx == null:
		return
	var surf := AirCommon.surface_of(null)
	for g in gears:
		var gg := g as AirCommon.Gear
		if gg.grounded:
			surf = gg.surface
			break
	if surf == &"asphalt" or surf == &"concrete" or surf == &"road":
		if throttle_state > 0.85 and airspeed < 12.0:
			fx.downwash(global_position + global_transform.basis.z * 3.0, &"concrete", 0.35, 6.0, 1)
		return
	fx.downwash(global_position + global_transform.basis.z * 2.5, surf, clampf(throttle_state, 0.0, 1.0), 6.0, 2)
