class_name HeliVehicle
extends VehicleBase
## Helicopter (heli_civil, heli_police): arcade-realistic rotor-craft on a RigidBody3D (Air&Sea agent).
##   * rotor RPM state (spool-up / spool-down, engine failure -> autorotation), lift ~ rpm^2, ground effect, translational lift;
##   * collective = climb-rate command (Shift/Space up, Ctrl down) with altitude hold when released; cyclic = attitude command
##     (W/S pitch, A/D bank) with hover assist (auto-level + velocity hold when the stick is released);
##     yaw pedals (Q/E) with tail-rotor authority (tail strike -> spin), wind gusts, flying-skill turbulence reduction;
##   * skid raycast gear (soft / hard landing damage), rotor + tail-rotor strikes on buildings / ground, crash -> VehicleBase.explode;
##   * rotor / tail visuals + translucent rotor discs, downwash dust / sand / spray (AirFx), landing light, bail-out by holding F.
## Inputs (written by the driver every physics frame): input_pitch (+1 nose up), input_roll (+1 right), input_yaw (+1 right),
## input_collective (-1..1). AirAutopilot / PoliceHeliAI drive the same inputs.

const GRAV := 9.81

# ---- tunables (overridden from the def) ------------------------------------------------------------------------------
var rotor_radius := 5.2
var hub_local := Vector3(0, 3.05, 0)
var tail_local := Vector3(0.22, 2.5, 6.8)
var tail_radius := 0.8
var thrust_g := 1.75               # max rotor thrust as a multiple of the weight at full rpm
var climb_rate := 7.5
var descend_rate := 6.0
var tilt_max := deg_to_rad(24.0)
var bank_max := deg_to_rad(27.0)
var yaw_rate_max := 1.7
var spool_up_t := 3.6
var spool_down_t := 9.0
var assist := 1.0                  # hover assist strength 0..1 (velocity hold + auto level), 0 = raw cyclic
var alt_hold := true
var direct_cyclic := false         # true (AirAutopilot): the stick is always a direct attitude command, no velocity / position hold
var hard_land_sink := 2.6          # m/s: above this the landing damages the airframe
var crash_land_sink := 8.5         # m/s: above this the helicopter is destroyed
var inertia_v := Vector3(4200, 5200, 3000)
var drag_lat := 0.20
var drag_fwd := 0.035
var drag_fwd2 := 0.00055

# ---- state --------------------------------------------------------------------------------------------------------------
var rotor_rpm := 0.0               # 0..1 (1 = flight rpm)
var rotor_angle := 0.0
var tail_angle := 0.0
var rotor_hp := 100.0
var tail_hp := 100.0
var engine_failed := false         # engine lost -> autorotation
var grounded_count := 0
var agl := 100.0                   # altitude above ground / sea (m), refreshed at 10 Hz
var collective_state := 0.0
var airborne_time := 0.0
var ground_time := 0.0
var last_touchdown_sink := 0.0
var bail_progress := 0.0           # 0..1 while F is held in the air
var gears: Array = []

var _engine_cmd := false
var _query: PhysicsRayQueryParameters3D = null
var _t := 0.0
var _agl_t := 0.0
var _hold_y := 0.0
var _hold_set := false
var _hold_xz := Vector2.ZERO
var _hold_xz_set := false
var _strike_t := 0.0
var _strike_cd := 0.0
var _fx_t := 0.0
var _vis_t := 0.0
var _airspace := {}
var _bail_t := 0.0
var _rotor_node: Node3D = null
var _tail_node: Node3D = null
var _rotor_rest := Basis.IDENTITY
var _tail_rest := Basis.IDENTITY
var _blur_main: MeshInstance3D = null
var _blur_tail: MeshInstance3D = null
var _blur_shader_mat: ShaderMaterial = null
var _blur_level := -1.0
var _warned_exit_t := -10.0
var _spot_t := 0.0
var _flying_prev := false
var ai: Node = null                # PoliceHeliAI / AirAutopilot child (optional)
var searchlight: AirSearchlight = null   # heli_police only (model node `Searchlight`): key L for the pilot, PoliceHeliAI for the AI
var skid_surface: StringName = &"asphalt"
var ground_point := Vector3.ZERO
var tilt_visual := Vector2.ZERO


# =====================================================================================================
# Setup (called by VehicleFactory right after the model is bound)
# =====================================================================================================
func setup_air() -> void:
	mass = float(def.get("mass", 1500.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = def.get("com", Vector3(0, 1.4, 0))
	inertia_v = def.get("inertia", inertia_v)
	inertia = inertia_v
	angular_damp = 0.05
	rotor_radius = float(def.get("rotor_radius", rotor_radius))
	hub_local = def.get("rotor_hub", hub_local)
	tail_local = def.get("tail_rotor_pos", tail_local)
	tail_radius = float(def.get("tail_rotor_radius", tail_radius))
	thrust_g = float(def.get("thrust_g", thrust_g))
	climb_rate = float(def.get("climb_rate", climb_rate))
	descend_rate = float(def.get("descend_rate", descend_rate))
	tilt_max = deg_to_rad(float(def.get("tilt_max_deg", 24.0)))
	bank_max = deg_to_rad(float(def.get("bank_max_deg", 27.0)))
	yaw_rate_max = float(def.get("yaw_rate", yaw_rate_max))
	spool_up_t = float(def.get("spool_up", spool_up_t))
	spool_down_t = float(def.get("spool_down", spool_down_t))
	hard_land_sink = float(def.get("hard_landing", hard_land_sink))
	crash_land_sink = float(def.get("crash_landing", crash_land_sink))
	drag_fwd = float(def.get("drag_fwd", drag_fwd))
	drag_fwd2 = float(def.get("drag_fwd2", drag_fwd2))
	run_over_enabled = false
	_rotor_node = model.find_child("RotorMain", true, false) as Node3D
	_tail_node = model.find_child("RotorTail", true, false) as Node3D
	if _rotor_node != null:
		_rotor_rest = _rotor_node.transform.basis
		hub_local = _rotor_node.transform.origin
	if _tail_node != null:
		_tail_rest = _tail_node.transform.basis
		tail_local = _tail_node.transform.origin
	_build_gears()
	_build_blur()
	searchlight = AirSearchlight.create(self)
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = GC.M_GROUND
	_query.exclude = [get_rid()]
	_airspace = {"cd": 0.0}


func _build_gears() -> void:
	gears.clear()
	var pts: Array = def.get("gear", [Vector3(-1.2, 0, -1.8), Vector3(1.2, 0, -1.8), Vector3(-1.2, 0, 1.0), Vector3(1.2, 0, 1.0)])
	var i := 0
	for p in pts:
		var rest := 0.34
		var g := AirCommon.make_gear(StringName("skid%d" % i), (p as Vector3) + Vector3(0, rest, 0), 0.0, 0.62, rest)
		gears.append(g)
		i += 1
	AirCommon.static_shares(gears, center_of_mass)
	AirCommon.tune_springs(gears, mass, GRAV * gravity_scale, 2.1, 0.55)


const BLUR_SHADER := "
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 0.0;
uniform vec3 tint = vec3(0.12, 0.13, 0.15);
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float body = smoothstep(0.10, 0.34, r) * (1.0 - smoothstep(0.90, 1.0, r));
	float tip = smoothstep(0.80, 0.92, r) * (1.0 - smoothstep(0.96, 1.0, r));
	ALBEDO = tint * (1.0 + 1.6 * tip);
	ALPHA = clamp((body * 0.55 + tip * 0.9) * strength, 0.0, 1.0);
}
"


func _build_blur() -> void:
	# rotor / tail-rotor motion blur: a faceted translucent disc with a radial gradient and a darker tip ring (AirSearchlight's disc mesh)
	_blur_shader_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	_blur_shader_mat.shader = sh
	if _rotor_node != null:
		_blur_main = MeshInstance3D.new()
		_blur_main.name = "RotorBlur"
		_blur_main.mesh = AirSearchlight._disc_mesh(24)
		_blur_main.material_override = _blur_shader_mat
		_blur_main.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blur_main.position = hub_local + Vector3(0, 0.04, 0)
		_blur_main.scale = Vector3(rotor_radius, 1.0, rotor_radius)
		model.add_child(_blur_main)
	if _tail_node != null:
		_blur_tail = MeshInstance3D.new()
		_blur_tail.name = "TailBlur"
		_blur_tail.mesh = AirSearchlight._disc_mesh(14)
		_blur_tail.material_override = _blur_shader_mat
		_blur_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blur_tail.position = tail_local + Vector3(0.03, 0, 0)
		_blur_tail.rotation = Vector3(0, 0, PI * 0.5)
		_blur_tail.scale = Vector3(tail_radius, 1.0, tail_radius)
		model.add_child(_blur_tail)
	_set_blur(0.0)


func _reset_extra() -> void:
	rotor_rpm = 0.0
	rotor_hp = 100.0
	tail_hp = 100.0
	engine_failed = false
	_engine_cmd = false
	collective_state = 0.0
	airborne_time = 0.0
	ground_time = 0.0
	_hold_set = false
	bail_progress = 0.0
	if ai != null and is_instance_valid(ai):
		ai.queue_free()
	ai = null
	set_meta("siren_lights", false)
	_set_blur(0.0)
	if searchlight != null:
		searchlight.external_control = false
		searchlight.set_enabled(false)
	siren_on = false
	direct_cyclic = false


func _is_settled() -> bool:
	return rotor_rpm < 0.02 and grounded_count >= 3


# =====================================================================================================
# VehicleBase overrides
# =====================================================================================================
func set_engine(on: bool) -> void:
	if on and (is_destroyed or water_depth > 0.6):
		return
	_engine_cmd = on
	if on:
		engine_on = true
		if audio != null and rotor_rpm < 0.05:
			audio.play_ignition()


func get_rpm01() -> float:
	return clampf(rotor_rpm, 0.0, 1.0)


func get_engine_load() -> float:
	return clampf(0.35 + absf(collective_state) * 0.5 + (0.0 if grounded_count > 1 else 0.25), 0.0, 1.0)


func is_airborne() -> bool:
	return grounded_count == 0 and agl > 1.2


func can_be_entered_by(character: Node) -> bool:
	if not super.can_be_entered_by(character):
		return false
	return agl < 3.0 or grounded_count > 0


func enter(character: Node, seat: int = 0, animated: bool = false) -> bool:
	var ok := super.enter(character, seat, animated)
	if ok:
		wake()
		sleeping = false
		_hold_set = false
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


## Leaving mid-air is refused (a toast explains it): land first, or HOLD the exit key above 8 m to bail out with a parachute.
func exit(character: Node, forced: bool = false, carjack_exit: bool = false) -> void:
	if not forced and not is_destroyed and _in_flight():
		if _is_player(character):
			var now := Time.get_ticks_msec() * 0.001
			if now - _warned_exit_t > 3.0:
				_warned_exit_t = now
				AirCommon.notify("Land first - or HOLD F in the air to bail out (parachute)", &"warn")
		return
	super.exit(character, forced, carjack_exit)


func _in_flight() -> bool:
	return grounded_count == 0 and agl > 2.2 and rotor_rpm > 0.3 or (grounded_count == 0 and agl > 4.0)


func _is_player(c: Node) -> bool:
	return c != null and is_instance_valid(c) and c.has_method("is_player") and c.is_player()


func get_camera_hints() -> Dictionary:
	var sp := clampf(get_speed() / 55.0, 0.0, 1.0)
	var shake := sp * 0.12 + clampf(rotor_rpm, 0.0, 1.0) * 0.03
	return {
		"distance": float(def.get("cam_distance", 17.0)) * (1.0 + sp * 0.22),
		"height": float(def.get("cam_height", 6.0)),
		"look_ahead": float(def.get("cam_look_ahead", 5.0)) * (0.5 + sp),
		"fov": float(def.get("cam_fov", 72.0)) + sp * 9.0,
		"shake": shake,
		"speed_kmh": get_speed_kmh(),
		"first_person_offset": (seats[0]["pos"] as Vector3) + Vector3(0, 0.62, -0.2) if seats.size() > 0 else Vector3(0, 1.6, -1.5),
	}


func unflip() -> void:
	super.unflip()
	rotor_hp = maxf(rotor_hp, 40.0)


# =====================================================================================================
# Simulation
# =====================================================================================================
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
	var right := b.x
	var lv := linear_velocity
	var g_eff := GRAV * gravity_scale
	var piloted := driver != null or is_ai_controlled
	_update_rotor(dt)
	if searchlight != null:
		_update_searchlight(dt)
	_agl_t -= dt
	if _agl_t <= 0.0:
		_agl_t = 0.1
		agl = AirCommon.agl_of(self, [self])
		_update_ground_sense()
	if is_destroyed:
		_update_visuals(dt)
		return
	# ---- landing gear (skids) ---------------------------------------------------------------------------------------------
	var gr := AirCommon.step_gears(self, gears, dt, _query, {"mu": 0.62, "hold": driver == null and not is_ai_controlled, "lift": 0.6})
	var gf: Vector3 = gr["f"]
	var gt: Vector3 = gr["t"]
	var was_grounded := grounded_count > 0
	grounded_count = int(gr["grounded"])
	if grounded_count > 0:
		ground_time += dt
		if not was_grounded and airborne_time > 0.35:
			_on_touchdown(float(gr["touchdown"]))
		airborne_time = 0.0
	else:
		airborne_time += dt
		ground_time = 0.0
	apply_central_force(gf)
	apply_torque(gt)
	# ---- controls ---------------------------------------------------------------------------------------------------------------
	var in_p := clampf(input_pitch, -1.0, 1.0) if piloted else 0.0
	var in_r := clampf(input_roll, -1.0, 1.0) if piloted else 0.0
	var in_y := clampf(input_yaw, -1.0, 1.0) if piloted else 0.0
	var in_c := clampf(input_collective, -1.0, 1.0) if piloted else 0.0
	collective_state = Util.damp(collective_state, in_c, 5.0, dt)
	var rpm := rotor_rpm
	var stab := AirCommon.stability_mult()
	var wind := AirCommon.wind_ms()
	var hs_v := Vector3(lv.x, 0.0, lv.z)
	var hs := hs_v.length()
	# ---- vertical channel: climb-rate command + altitude hold ---------------------------------------------------------------------
	var airborne := grounded_count == 0
	var want_vz := collective_state * (climb_rate if collective_state > 0.0 else descend_rate)
	if assist > 0.0 and agl < 14.0 and want_vz < 0.0:
		want_vz = maxf(want_vz, -(0.45 + maxf(agl, 0.0) * 0.42))      # landing assist: gentle sink rate near the ground
	if absf(in_c) < 0.05:
		if not _hold_set and absf(lv.y) < 1.2 and airborne:
			_hold_y = xf.origin.y
			_hold_set = true
		if airborne and assist > 0.0 and alt_hold and _hold_set:
			want_vz = clampf((_hold_y - xf.origin.y) * 1.3, -2.2, 2.2)
	else:
		_hold_set = false
	var ge := clampf(1.0 - agl / (rotor_radius * 2.2), 0.0, 1.0)
	var tl := 1.0 + 0.09 * clampf((hs - 7.0) / 12.0, 0.0, 1.0)
	var t_avail := mass * g_eff * thrust_g * rpm * rpm * (1.0 + 0.10 * ge) * tl * power_scale
	var a_cmd := 0.0
	if grounded_count >= 2 and in_c < 0.05:
		a_cmd = -0.42 * g_eff                                       # light on the skids
	else:
		a_cmd = clampf((want_vz - lv.y) * 2.6, -0.7 * g_eff, 0.85 * g_eff)
	var tilt_cos := maxf(up.y, 0.5)
	var thrust := minf(mass * (g_eff + a_cmd) / tilt_cos * (1.0 - 0.05 * ge), t_avail)
	if rotor_hp <= 0.0:
		thrust = 0.0
	elif engine_failed or (not _engine_cmd and rpm > 0.1 and airborne):
		# autorotation: the windmilling rotor lifts ~ 0.55..0.9 g and cushions the flare (collective up)
		var auto := clampf(0.42 + rpm * 0.42 + clampf(-lv.y, 0.0, 12.0) * 0.012, 0.0, 0.95)
		thrust = mass * g_eff * auto * (1.0 + clampf(collective_state, 0.0, 1.0) * 0.18 * rpm)
	apply_central_force(up * thrust)
	# ---- cyclic: attitude command with hover assist -----------------------------------------------------------------------------------
	var pitch := AirCommon.pitch_of(b)
	var bank := AirCommon.bank_of(b)
	var hf := Vector3(fwd.x, 0.0, fwd.z)
	hf = hf.normalized() if hf.length_squared() > 1e-4 else Vector3(0, 0, -1)
	var hr := Vector3(right.x, 0.0, right.z)
	hr = hr.normalized() if hr.length_squared() > 1e-4 else Vector3(1, 0, 0)
	var v_f := lv.dot(hf)
	var v_r := lv.dot(hr)
	var free_p := absf(in_p) < 0.05 and not direct_cyclic
	var free_r := absf(in_r) < 0.05 and not direct_cyclic
	# GPS-style hold: remember the spot when the sticks are released at a crawl, then tilt back towards it
	var pos_hold := free_p and free_r and airborne and assist > 0.0
	if pos_hold:
		if not _hold_xz_set and hs < 2.0:
			_hold_xz = Vector2(xf.origin.x, xf.origin.z)
			_hold_xz_set = true
	else:
		_hold_xz_set = false
	var err_f := 0.0
	var err_r := 0.0
	if pos_hold and _hold_xz_set:
		var e := Vector3(xf.origin.x - _hold_xz.x, 0.0, xf.origin.z - _hold_xz.y)
		err_f = clampf(e.dot(hf), -14.0, 14.0)
		err_r = clampf(e.dot(hr), -14.0, 14.0)
	# wind feed-forward: tilt against the drag the current wind puts on a hovering craft
	var vb_w := b.inverse() * (-wind)
	var dw := b * Vector3(-vb_w.x * (drag_lat + 0.0045 * absf(vb_w.x)), 0.0, -vb_w.z * (drag_fwd + drag_fwd2 * absf(vb_w.z)))
	var ff_p := clampf(dw.dot(hf) / g_eff, -0.3, 0.3)
	var ff_r := clampf(-dw.dot(hr) / g_eff, -0.3, 0.3)
	var pitch_t := in_p * tilt_max
	var bank_t := in_r * bank_max
	if free_p:
		# braking flare: a fast helicopter may pitch its nose up further than it noses down (stops from 60 m/s in ~7 s)
		var flare := 1.0 + 0.45 * clampf((v_f - 8.0) / 22.0, 0.0, 1.0)
		pitch_t = clampf(v_f * 0.05 + err_f * 0.012 + ff_p, -tilt_max, tilt_max * flare) * assist
	if free_r:
		bank_t = clampf(-(v_r * 0.05 + err_r * 0.012) + ff_r, -bank_max, bank_max) * assist
	if grounded_count >= 2 and in_c < 0.3:
		pitch_t = 0.0
		bank_t = 0.0
	if rotor_hp <= 0.0 or rpm < 0.3:
		pitch_t = 0.0
		bank_t = 0.0
	var lav := b.inverse() * angular_velocity
	var ctl := clampf(rpm * 1.3, 0.0, 1.0)
	var acc_x := (15.0 * (pitch_t - pitch) - 6.5 * lav.x) * ctl
	var acc_z := (-15.0 * (bank_t - bank) - 6.5 * lav.z) * ctl
	# yaw: pedals command a rate through the tail rotor; banked forward flight turns the nose (coordinated turn)
	var tail_auth := rpm * (1.0 if tail_hp > 0.0 else 0.0)
	var turn_c := -(GRAV * tan(clampf(bank, -0.6, 0.6)) / maxf(hs, 12.0)) * clampf(hs / 14.0, 0.0, 1.0) * 0.65 * ctl
	var yaw_t := -in_y * yaw_rate_max * tail_auth + turn_c
	var acc_y := 4.2 * (yaw_t - lav.y) * (tail_auth if tail_hp > 0.0 else 0.0)
	if tail_hp <= 0.0:
		acc_y = -3.1 * rpm - 0.35 * lav.y              # main rotor torque with no anti-torque: the cabin spins
	else:
		acc_y -= 0.9 * lav.y
	# turbulence (wind gusts), reduced by the flying skill
	var turb := (0.25 + wind.length() * 0.06) * stab
	if airborne:
		var gust := Vector3(sin(_t * 0.71 + 1.3) + 0.6 * sin(_t * 1.93), 0.35 * sin(_t * 1.13 + 0.5), cos(_t * 0.83) + 0.5 * sin(_t * 2.31)) * 0.5
		apply_central_force(gust * mass * turb * 1.4)
		acc_x += sin(_t * 1.7 + 0.4) * 0.35 * turb
		acc_z += cos(_t * 1.3 + 2.0) * 0.35 * turb
	var tq := Vector3(clampf(acc_x, -70.0, 70.0) * inertia_v.x, clampf(acc_y, -40.0, 40.0) * inertia_v.y, clampf(acc_z, -70.0, 70.0) * inertia_v.z)
	apply_torque(b * tq)
	# ---- aerodynamic drag (body axes; relative to the air mass) ------------------------------------------------------------------------
	var vb := b.inverse() * (lv - wind)
	var dr := Vector3(
		-vb.x * (drag_lat + 0.0045 * absf(vb.x)),
		-vb.y * (0.10 + 0.004 * absf(vb.y)) * (0.5 if airborne else 3.0),
		-vb.z * (drag_fwd + drag_fwd2 * absf(vb.z)))
	apply_central_force(b * dr * mass)
	# ---- hazards ----------------------------------------------------------------------------------------------------------------------------------
	_strike_t -= dt
	if _strike_t <= 0.0 and rpm > 0.3:
		_strike_t = 0.05
		_check_strikes()
	if driver != null and _is_player(driver):
		AirCommon.airspace_tick(self, dt, _airspace)
		_tick_bail(dt)
	else:
		bail_progress = 0.0
	if visual_lod == 0:
		_update_visuals(dt)
		_update_fx(dt)
	else:
		rotor_angle = fposmod(rotor_angle + rotor_rpm * 32.0 * dt, TAU)


# =====================================================================================================
# Rotor state
# =====================================================================================================
func _update_rotor(dt: float) -> void:
	var target := 0.0
	var airborne := grounded_count == 0 and agl > 1.5
	if is_destroyed or rotor_hp <= 0.0:
		target = 0.0
	elif _engine_cmd and not engine_failed and not on_fire_critical():
		target = 1.0
	elif airborne and rotor_rpm > 0.15:
		target = clampf(0.62 + clampf(-linear_velocity.y, 0.0, 12.0) * 0.02, 0.5, 0.82)       # autorotation rpm
	var rate := 1.0 / spool_up_t if target > rotor_rpm else 1.0 / spool_down_t
	if target < rotor_rpm and (is_destroyed or rotor_hp <= 0.0):
		rate = 0.35
	if target > rotor_rpm:
		rate *= lerpf(1.25, 0.8, clampf(rotor_rpm, 0.0, 1.0))           # starts a little quicker, settles softly
	rotor_rpm = move_toward(rotor_rpm, target, rate * dt)
	if not _engine_cmd and rotor_rpm < 0.02 and engine_on:
		engine_on = false
	if is_destroyed:
		engine_on = false
	# engine failure from heavy damage
	if not engine_failed and not is_destroyed and get_health_ratio() < 0.22:
		engine_failed = true
		if _is_player(driver):
			AirCommon.notify("Engine failure - autorotate!", &"bad")
	rpm = rotor_rpm


func on_fire_critical() -> bool:
	return false


## Puts a freshly spawned helicopter straight into flight: rotor at flight rpm, engine running, altitude hold engaged at the spawn height
## (police helicopters appear in the air). `forward_speed` m/s along the nose.
func start_airborne(forward_speed: float = 0.0) -> void:
	_engine_cmd = true
	engine_on = true
	rotor_rpm = 1.0
	grounded_count = 0
	agl = maxf(agl, 40.0)
	airborne_time = 5.0
	_hold_set = false
	sleeping = false
	set_velocity(-global_transform.basis.z * forward_speed)
	wake()


## Searchlight: the pilot's key L toggles it and the beam follows the camera; PoliceHeliAI takes it over (`external_control`).
func _update_searchlight(dt: float) -> void:
	if not searchlight.external_control:
		var on := headlights_on and driver != null and rotor_rpm > 0.5 and not is_destroyed
		searchlight.set_enabled(on)
		if on:
			var d := -global_transform.basis.z
			var cam = Game.gameplay_camera
			if cam != null and _is_player(driver):
				d = -(cam as Camera3D).global_transform.basis.z
			if d.y > -0.2:
				d = Vector3(d.x, -0.2, d.z).normalized()
			searchlight.aim_dir(d)
	searchlight.update(dt)


func _update_ground_sense() -> void:
	pass


# =====================================================================================================
# Landing / strikes / bail
# =====================================================================================================
func _on_touchdown(sink: float) -> void:
	last_touchdown_sink = sink
	if sink > crash_land_sink:
		_apply_health_loss(max_health * 2.0, null, {"type": GC.DMG_COLLISION, "position": global_position})
		return
	if sink > hard_land_sink:
		var d := (sink - hard_land_sink) * max_health * 0.085
		_apply_health_loss(d, null, {"type": GC.DMG_COLLISION, "position": global_position})
		if audio != null:
			audio.play_impact(sink * 1.5)
		if VehicleFx.inst != null:
			VehicleFx.inst.spark(global_position + Vector3.UP * 0.1, Vector3.UP, 8)
		for c in get_occupants():
			if c.has_method("apply_damage") and sink > hard_land_sink + 2.0:
				c.apply_damage((sink - hard_land_sink - 2.0) * 3.0, {"source": self, "type": GC.DMG_COLLISION, "zone": GC.ZONE_TORSO})
		if _is_player(driver):
			AirCommon.notify("Hard landing!", &"warn")
	elif _is_player(driver) and sink < 1.2 and rotor_rpm > 0.5:
		AirCommon.record_flying(1.5)             # clean touchdown trains the flying skill


func _check_strikes() -> void:
	if _strike_cd > 0.0:
		_strike_cd -= 0.05
	var xf := global_transform
	var space := get_world_3d().direct_space_state
	var mask := GC.L_WORLD | GC.L_PROP
	var hub := xf * hub_local
	var ang := rotor_angle
	var b := xf.basis
	for i in 6:
		var a := ang + float(i) * TAU / 6.0
		var dirv := b.x * cos(a) + b.z * sin(a)
		var q := PhysicsRayQueryParameters3D.create(hub, hub + dirv * (rotor_radius + 0.15), mask)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_rotor_strike(hit.position, hit.normal)
			return
	if tail_hp > 0.0:
		var tp := xf * tail_local
		for dd: Vector3 in [Vector3.UP, Vector3.DOWN, b.z, -b.z]:
			var q2 := PhysicsRayQueryParameters3D.create(tp, tp + dd * (tail_radius + 0.1), mask)
			q2.exclude = [get_rid()]
			var h2 := space.intersect_ray(q2)
			if not h2.is_empty():
				_tail_strike(h2.position)
				return


func _rotor_strike(pos: Vector3, normal: Vector3) -> void:
	if _strike_cd > 0.0:
		return
	_strike_cd = 0.5
	rotor_hp -= 55.0 * clampf(rotor_rpm, 0.3, 1.0)
	rotor_rpm *= 0.55
	_apply_health_loss(max_health * 0.14, null, {"type": GC.DMG_COLLISION, "position": pos})
	if VehicleFx.inst != null:
		VehicleFx.inst.spark(pos, normal, 14)
	if audio != null:
		audio.play_impact(14.0)
	apply_central_impulse(normal * mass * 1.4)
	apply_torque_impulse(global_transform.basis.y * mass * randf_range(-3.0, 3.0))
	if _is_player(driver):
		var cam = Game.gameplay_camera
		if cam != null and cam.has_method("add_shake"):
			cam.add_shake(0.8, 0.6)
		AirCommon.notify("Rotor strike!", &"bad")
	if rotor_hp <= 0.0 and not is_destroyed:
		engine_failed = true


func _tail_strike(pos: Vector3) -> void:
	if _strike_cd > 0.0:
		return
	_strike_cd = 0.5
	tail_hp -= 55.0
	_apply_health_loss(max_health * 0.07, null, {"type": GC.DMG_COLLISION, "position": pos})
	if VehicleFx.inst != null:
		VehicleFx.inst.spark(pos, Vector3.UP, 10)
	if audio != null:
		audio.play_impact(9.0)
	if tail_hp <= 0.0 and _is_player(driver):
		AirCommon.notify("Tail rotor lost!", &"bad")


## Hold the exit key in the air (> 8 m up) for 0.9 s: the pilot jumps out and tries to open an emergency parachute.
func _tick_bail(dt: float) -> void:
	if not _in_flight() or agl < 8.0:
		bail_progress = 0.0
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
# Visuals / FX
# =====================================================================================================
func _set_blur(a: float) -> void:
	_blur_level = a
	if _blur_shader_mat != null:
		_blur_shader_mat.set_shader_parameter("strength", a)
	if _blur_main != null:
		_blur_main.visible = a > 0.01
	if _blur_tail != null:
		_blur_tail.visible = a > 0.01


func _update_visuals(dt: float) -> void:
	var spin := rotor_rpm * 34.0
	rotor_angle = fposmod(rotor_angle + spin * dt, TAU)
	tail_angle = fposmod(tail_angle + (spin * 1.6 if tail_hp > 0.0 else spin * 0.4) * dt, TAU)
	if _rotor_node != null:
		# the rotor disc follows the cyclic a little (lags behind the fuselage tilt)
		var tp := Util.damp(tilt_visual.x, clampf(input_pitch, -1, 1) * 0.07, 5.0, dt)
		var tr := Util.damp(tilt_visual.y, clampf(input_roll, -1, 1) * 0.07, 5.0, dt)
		tilt_visual = Vector2(tp, tr)
		_rotor_node.transform.basis = Basis(Vector3.RIGHT, tp) * Basis(Vector3.BACK, -tr) * _rotor_rest * Basis(Vector3.UP, rotor_angle)
	if _tail_node != null:
		_tail_node.transform.basis = _tail_rest * Basis(Vector3.RIGHT, tail_angle)
		_tail_node.visible = tail_hp > 0.0 or rotor_rpm < 0.2
	var blur := smoothstep(0.3, 0.95, rotor_rpm)
	if absf(blur - _blur_level) > 0.004:
		_set_blur(blur)
	if _blur_main != null:
		_blur_main.transform.basis = Basis(Vector3.RIGHT, tilt_visual.x) * Basis(Vector3.BACK, -tilt_visual.y) * Basis.from_scale(Vector3(rotor_radius, 1.0, rotor_radius))
	_spot_t -= dt
	if _spot_t <= 0.0:
		_spot_t = 0.5
		_tweak_landing_light()
		if _blur_shader_mat != null:
			# the blur discs are unshaded: dim them with the daylight so they do not glow at night
			var l := lerpf(0.25, 1.0, clampf(Game.daylight() * 1.2, 0.0, 1.0))
			_blur_shader_mat.set_shader_parameter("tint", Vector3(0.12, 0.13, 0.15) * l)


func _tweak_landing_light() -> void:
	for ch in get_children():
		if ch is SpotLight3D and ch.name == &"HeadSpot":
			var s := ch as SpotLight3D
			s.rotation_degrees = Vector3(-34.0, 0.0, 0.0)
			s.spot_range = 70.0
			s.spot_angle = 26.0
			s.light_energy = 4.5


func _update_fx(dt: float) -> void:
	_fx_t -= dt
	if _fx_t > 0.0:
		return
	_fx_t = 0.05
	if rotor_rpm < 0.45 or agl > rotor_radius * 3.2:
		return
	var fx := AirFx.get_fx()
	if fx == null:
		return
	var strength := clampf(rotor_rpm * (1.0 - agl / (rotor_radius * 3.2)) * 1.25, 0.0, 1.0)
	if grounded_count > 0 and collective_state < 0.1 and rotor_rpm < 0.85:
		strength *= 0.55
	var origin := global_position + Vector3.UP * 0.5
	var info := AirCommon.probe_down(self, origin, rotor_radius * 3.4, [self])
	if info["dist"] == INF:
		return
	skid_surface = info["surface"]
	var gp := Vector3(global_position.x, float(info["y"]), global_position.z)
	ground_point = gp
	var n := int(clampf(strength * 7.0, 1.0, 8.0))
	fx.downwash(gp, skid_surface, strength, rotor_radius, n)
