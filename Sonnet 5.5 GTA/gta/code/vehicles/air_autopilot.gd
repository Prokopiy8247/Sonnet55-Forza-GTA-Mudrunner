class_name AirAutopilot
extends Node
## AI pilot for HeliVehicle and PlaneVehicle (Air&Sea agent): writes the vehicle's input_* every physics frame.
## Usable by any module:
##     var ap := AirAutopilot.attach(heli)          # child node named "AirAutopilot" (returns the existing one when present)
##     ap.goto(Vector3(120, 90, -40))               # fly there (helicopter: hover on arrival; plane: keep passing it unless `loop`)
##     ap.orbit(center, 150.0, 110.0)               # circle a point (radius m, altitude m above sea level)
##     ap.follow(target_node, Vector3(0, 45, 0), 30.0)   # hold an offset above / behind a moving node (trail distance)
##     ap.set_waypoints([Vector3, ...], true)       # patrol route
##     ap.hover() / ap.stop() / ap.takeoff(alt)     # (takeoff: planes roll + climb, helicopters lift)
## Signals: arrived(point) when a goto / waypoint is reached, takeoff_done.
## The autopilot sets the vehicle AI-controlled while it flies and releases it on stop(). Helicopters get `direct_cyclic = true`
## (the stick is an acceleration command, no velocity-hold assist fighting the autopilot).

signal arrived(point: Vector3)
signal takeoff_done()

enum Mode { OFF, HOVER, GOTO, ORBIT, FOLLOW, WAYPOINTS, TAKEOFF }

var vehicle: VehicleBase = null
var mode: Mode = Mode.OFF
var enabled := true
var cruise_speed := 30.0             # m/s horizontal (helicopter) / airspeed (plane)
var max_speed := 55.0
var min_agl := 25.0                  # terrain / building clearance
var arrive_radius := 6.0
var heading_target := NAN            # helicopters: face this yaw (rad) instead of the course; NAN = face the course
var look_at_point := Vector3.INF     # helicopters: face this point (e.g. the player) while flying
var target_pos := Vector3.ZERO
var target_node: Node3D = null
var follow_offset := Vector3(0, 45, 0)
var follow_trail := 30.0
var follow_lag := 1.2                # seconds of smoothing of the followed point (smooth lag behind a fast target)
var follow_min_radius := 0.0         # >0: never hover closer than this (horizontal, m) to the followed node; a slow / stationary target is orbited
var follow_orbit_dps := 9.0          # deg/s of the slow orbit around a (nearly) stationary target while follow_min_radius applies
var orbit_center := Vector3.ZERO
var orbit_radius := 150.0
var orbit_alt := 110.0
var orbit_cw := true
var waypoints: Array = []
var wp_loop := true
var wp_index := 0
var takeoff_alt := 80.0

var _orbit_angle := 0.0
var _follow_ang := NAN               # current bearing (rad) of the helicopter around the followed node (min-radius orbit)
var _smoothed_target := Vector3.ZERO
var _smoothed_init := false
var _probe_t := 0.0
var _clearance_y := -INF            # highest obstacle seen ahead (absolute y)
var _was_ai := false
var _tick := 0
var _tk_phase := 0
var _tk_t := 0.0
var _arrived_sent := false


static func attach(v: VehicleBase) -> AirAutopilot:
	var ex := v.get_node_or_null("AirAutopilot")
	if ex is AirAutopilot:
		return ex
	var ap := AirAutopilot.new()
	ap.name = "AirAutopilot"
	ap.vehicle = v
	v.add_child(ap)
	return ap


func _ready() -> void:
	if vehicle == null and get_parent() is VehicleBase:
		vehicle = get_parent() as VehicleBase
	process_priority = -5            # write the inputs before the vehicle simulates
	set_physics_process(true)


# =====================================================================================================
# Commands
# =====================================================================================================
func stop() -> void:
	mode = Mode.OFF
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.reset_controls()
		if not _was_ai:
			vehicle.set_ai_controlled(false)


func hover(pos: Vector3 = Vector3.INF) -> void:
	_engage(Mode.HOVER)
	target_pos = pos if pos != Vector3.INF else vehicle.global_position


func goto(pos: Vector3, speed: float = -1.0, alt: float = NAN) -> void:
	_engage(Mode.GOTO)
	target_pos = pos
	if not is_nan(alt):
		target_pos.y = alt
	if speed > 0.0:
		cruise_speed = speed
	_arrived_sent = false


func orbit(center: Vector3, radius: float, alt: float, speed: float = -1.0, clockwise: bool = true) -> void:
	_engage(Mode.ORBIT)
	orbit_center = center
	orbit_radius = radius
	orbit_alt = alt
	orbit_cw = clockwise
	if speed > 0.0:
		cruise_speed = speed
	var rel := vehicle.global_position - center
	_orbit_angle = atan2(rel.z, rel.x)


func follow(node: Node3D, offset: Vector3 = Vector3(0, 45, 0), trail: float = 30.0, speed: float = -1.0) -> void:
	_engage(Mode.FOLLOW)
	target_node = node
	follow_offset = offset
	follow_trail = trail
	_smoothed_init = false
	_follow_ang = NAN
	if speed > 0.0:
		max_speed = speed


func set_waypoints(points: Array, loop: bool = true, speed: float = -1.0) -> void:
	_engage(Mode.WAYPOINTS)
	waypoints = points
	wp_loop = loop
	wp_index = 0
	if speed > 0.0:
		cruise_speed = speed
	_arrived_sent = false


func takeoff(alt: float = 80.0) -> void:
	_engage(Mode.TAKEOFF)
	takeoff_alt = alt
	_tk_phase = 0
	_tk_t = 0.0


func _engage(m: Mode) -> void:
	if vehicle == null:
		return
	if mode == Mode.OFF:
		_was_ai = vehicle.is_ai_controlled
	mode = m
	vehicle.set_ai_controlled(true)
	if vehicle is HeliVehicle:
		(vehicle as HeliVehicle).direct_cyclic = true


# =====================================================================================================
# Per-frame
# =====================================================================================================
func _physics_process(dt: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or mode == Mode.OFF or not enabled:
		return
	if vehicle.is_destroyed:
		return
	if vehicle.driver != null and vehicle.driver.has_method("is_player") and vehicle.driver.is_player():
		return                          # a human took the controls
	_tick += 1
	if vehicle is HeliVehicle:
		_fly_heli(vehicle as HeliVehicle, dt)
	elif vehicle is PlaneVehicle:
		_fly_plane(vehicle as PlaneVehicle, dt)


## Highest obstacle (building roof / hill) ahead of the vehicle along its velocity, 10 Hz.
func _probe_clearance(v: VehicleBase, dt: float, lead_s: float = 4.0) -> void:
	_probe_t -= dt
	if _probe_t > 0.0:
		return
	_probe_t = 0.15
	var p := v.global_position
	var vel := v.linear_velocity
	var worst := -INF
	for k in [0.0, 0.5, 1.0]:
		var q: Vector3 = p + Vector3(vel.x, 0.0, vel.z) * lead_s * float(k)
		var r := AirCommon.probe_down(v, Vector3(q.x, p.y + 220.0, q.z), 500.0, [v])
		if r["y"] != -INF:
			worst = maxf(worst, float(r["y"]))
	_clearance_y = worst


# ---- helicopter -----------------------------------------------------------------------------------------------------------
func _fly_heli(h: HeliVehicle, dt: float) -> void:
	var p := h.global_position
	var v := h.linear_velocity
	var goal := p
	var want_speed := cruise_speed
	var hold_here := false
	match mode:
		Mode.HOVER:
			goal = target_pos
			hold_here = true
		Mode.GOTO:
			goal = target_pos
			if Vector2(goal.x - p.x, goal.z - p.z).length() < arrive_radius and absf(goal.y - p.y) < 8.0:
				if not _arrived_sent:
					_arrived_sent = true
					arrived.emit(goal)
				hold_here = true
		Mode.ORBIT:
			var w := cruise_speed / maxf(orbit_radius, 20.0)
			_orbit_angle += w * dt * (1.0 if orbit_cw else -1.0)
			# aim a little ahead on the circle so the helicopter flows along it
			var a2 := _orbit_angle + 0.35 * (1.0 if orbit_cw else -1.0)
			goal = orbit_center + Vector3(cos(a2) * orbit_radius, 0.0, sin(a2) * orbit_radius)
			goal.y = orbit_alt
			# keep up with the orbit point: catch up when behind
			var cur := orbit_center + Vector3(cos(_orbit_angle) * orbit_radius, 0.0, sin(_orbit_angle) * orbit_radius)
			var lag := Vector2(cur.x - p.x, cur.z - p.z).length()
			want_speed = clampf(cruise_speed + lag * 0.5, cruise_speed * 0.6, max_speed)
		Mode.FOLLOW:
			if target_node == null or not is_instance_valid(target_node):
				mode = Mode.HOVER
				target_pos = p
				return
			var tp := target_node.global_position
			var tv := Vector3.ZERO
			var t_lv = target_node.get("linear_velocity")
			if t_lv is Vector3:
				tv = t_lv
			elif target_node.get("velocity") is Vector3:
				tv = target_node.velocity
			var back := Vector3.ZERO
			if Vector2(tv.x, tv.z).length() > 2.0:
				back = -Vector3(tv.x, 0.0, tv.z).normalized() * follow_trail
			var raw := tp + back + follow_offset + tv * 0.6
			if follow_min_radius > 0.0:
				# keep a stand-off ring: the beam of a police helicopter must not hang straight above (and around) the camera
				var tsp := Vector2(tv.x, tv.z).length()
				if is_nan(_follow_ang):
					_follow_ang = atan2(p.z - tp.z, p.x - tp.x)
				if tsp < 3.0:
					_follow_ang += deg_to_rad(follow_orbit_dps) * dt * (1.0 if orbit_cw else -1.0)
				var off_h := Vector2(raw.x - tp.x, raw.z - tp.z)
				if off_h.length() < follow_min_radius:
					var ang := _follow_ang if tsp < 3.0 else atan2(p.z - tp.z, p.x - tp.x)
					raw.x = tp.x + cos(ang) * follow_min_radius
					raw.z = tp.z + sin(ang) * follow_min_radius
				else:
					_follow_ang = atan2(off_h.y, off_h.x)
			if not _smoothed_init:
				_smoothed_target = raw
				_smoothed_init = true
			_smoothed_target = _smoothed_target.lerp(raw, 1.0 - exp(-dt / maxf(follow_lag, 0.05)))
			goal = _smoothed_target
			var dist_h := Vector2(goal.x - p.x, goal.z - p.z).length()
			want_speed = clampf(dist_h * 0.9 + Vector2(tv.x, tv.z).length(), 3.0, max_speed)
		Mode.WAYPOINTS:
			if waypoints.is_empty():
				mode = Mode.HOVER
				target_pos = p
				return
			goal = waypoints[wp_index]
			if Vector2(goal.x - p.x, goal.z - p.z).length() < arrive_radius * 2.0 and absf(goal.y - p.y) < 12.0:
				arrived.emit(goal)
				wp_index += 1
				if wp_index >= waypoints.size():
					if wp_loop:
						wp_index = 0
					else:
						mode = Mode.HOVER
						target_pos = goal
						return
				goal = waypoints[wp_index]
		Mode.TAKEOFF:
			goal = Vector3(p.x, takeoff_alt, p.z)
			hold_here = true
			if p.y > takeoff_alt - 4.0:
				takeoff_done.emit()
				mode = Mode.HOVER
				target_pos = Vector3(p.x, takeoff_alt, p.z)
	# ---- velocity command -------------------------------------------------------------------------------------------------
	var to := Vector3(goal.x - p.x, 0.0, goal.z - p.z)
	var dist := to.length()
	var v_des := Vector3.ZERO
	if not hold_here or dist > 1.0:
		var sp := minf(want_speed, sqrt(2.0 * 3.2 * maxf(dist - 1.0, 0.0)) + 1.0)        # brake into the target (3.2 m/s^2)
		if dist > 0.5:
			v_des = to / dist * sp
	_probe_clearance(h, dt)
	var goal_y := goal.y
	if _clearance_y > -INF:
		goal_y = maxf(goal_y, _clearance_y + min_agl)
	# accelerations -> sticks
	var b := h.global_transform.basis
	var hf := Vector3(-b.z.x, 0.0, -b.z.z)
	hf = hf.normalized() if hf.length_squared() > 1e-4 else Vector3(0, 0, -1)
	var hr := Vector3(b.x.x, 0.0, b.x.z)
	hr = hr.normalized() if hr.length_squared() > 1e-4 else Vector3(1, 0, 0)
	var a_cmd := (v_des - Vector3(v.x, 0.0, v.z)) * 1.25
	var a_max := 9.81 * tan(h.tilt_max)
	h.input_pitch = clampf(-a_cmd.dot(hf) / a_max, -1.0, 1.0)         # forward accel = nose down
	h.input_roll = clampf(a_cmd.dot(hr) / (9.81 * tan(h.bank_max)), -1.0, 1.0)
	if absf(h.input_pitch) < 0.052:
		h.input_pitch = 0.052 * signf(h.input_pitch + 1e-6)
	if absf(h.input_roll) < 0.052:
		h.input_roll = 0.052 * signf(h.input_roll + 1e-6)
	# climb
	var ey := goal_y - p.y
	h.input_collective = clampf(ey / 10.0, -1.0, 1.0)
	if absf(ey) < 1.2:
		h.input_collective = 0.0
	# yaw: face the look point, the explicit heading or the course
	var cur_yaw := Util.dir_to_yaw(hf)
	var want_yaw := cur_yaw
	if look_at_point != Vector3.INF:
		var lp := look_at_point - p
		want_yaw = Util.dir_to_yaw(Vector3(lp.x, 0.0, lp.z))
	elif not is_nan(heading_target):
		want_yaw = heading_target
	elif Vector2(v_des.x, v_des.z).length() > 3.0:
		want_yaw = Util.dir_to_yaw(Vector3(v_des.x, 0.0, v_des.z))
	var yaw_err := wrapf(want_yaw - cur_yaw, -PI, PI)
	h.input_yaw = clampf(-yaw_err * 1.7, -1.0, 1.0)
	h.input_throttle = 1.0
	h.input_brake = 0.0


# ---- plane ------------------------------------------------------------------------------------------------------------------
func _fly_plane(pl: PlaneVehicle, dt: float) -> void:
	var p := pl.global_position
	var vel := pl.linear_velocity
	var spd := vel.length()
	var goal := p
	var thr_target := 0.7
	match mode:
		Mode.TAKEOFF:
			_tk_t += dt
			pl.input_throttle = 1.0
			pl.input_brake = 0.0
			var rot := pl.stall_speed * 1.12
			var fwd := -pl.global_transform.basis.z
			pl.input_yaw = 0.0
			pl.input_steer = 0.0
			if _tk_phase == 0:
				pl.input_pitch = 0.0
				if spd > rot:
					_tk_phase = 1
			elif _tk_phase == 1:
				pl.input_pitch = 0.55
				if pl.grounded_count == 0:
					_tk_phase = 2
			else:
				pl.input_pitch = 0.0
				pl.input_roll = 0.0
				if pl.agl > takeoff_alt * 0.6:
					takeoff_done.emit()
					mode = Mode.WAYPOINTS if not waypoints.is_empty() else Mode.ORBIT
					if mode == Mode.ORBIT:
						orbit_center = p + fwd * 400.0
						orbit_alt = p.y + 60.0
			return
		Mode.GOTO:
			goal = target_pos
			if Vector2(goal.x - p.x, goal.z - p.z).length() < 60.0 and not _arrived_sent:
				_arrived_sent = true
				arrived.emit(goal)
		Mode.ORBIT:
			var rel := Vector3(p.x - orbit_center.x, 0.0, p.z - orbit_center.z)
			var ang := atan2(rel.z, rel.x) + 0.55 * (1.0 if orbit_cw else -1.0)
			goal = orbit_center + Vector3(cos(ang) * orbit_radius, 0.0, sin(ang) * orbit_radius)
			goal.y = orbit_alt
		Mode.WAYPOINTS:
			if waypoints.is_empty():
				return
			goal = waypoints[wp_index]
			if Vector2(goal.x - p.x, goal.z - p.z).length() < maxf(60.0, spd * 1.6):
				arrived.emit(goal)
				wp_index = (wp_index + 1) % waypoints.size() if wp_loop else mini(wp_index + 1, waypoints.size() - 1)
				goal = waypoints[wp_index]
		Mode.FOLLOW:
			if target_node == null or not is_instance_valid(target_node):
				return
			goal = target_node.global_position + follow_offset
		Mode.HOVER:
			goal = p + (-pl.global_transform.basis.z) * 300.0
			goal.y = target_pos.y if target_pos.y != 0.0 else p.y
	_probe_clearance(pl, dt, 5.0)
	var goal_y := goal.y
	if _clearance_y > -INF:
		goal_y = maxf(goal_y, _clearance_y + min_agl * 2.0)
	# heading -> bank (the plane holds bank angles); altitude -> vertical-speed -> pitch; speed -> throttle
	var hf := Vector3(vel.x, 0.0, vel.z)
	if hf.length() < 5.0:
		hf = Vector3(-pl.global_transform.basis.z.x, 0.0, -pl.global_transform.basis.z.z)
	var cur_h := Util.dir_to_yaw(hf.normalized())
	var to := Vector3(goal.x - p.x, 0.0, goal.z - p.z)
	var want_h := Util.dir_to_yaw(to.normalized()) if to.length() > 1.0 else cur_h
	var herr := wrapf(want_h - cur_h, -PI, PI)
	pl.input_roll = clampf(-herr * 1.6, -1.0, 1.0)            # positive heading error (target to the left) -> roll left (negative)
	pl.input_yaw = 0.0
	pl.input_steer = 0.0
	var vz_des := clampf((goal_y - p.y) * 0.18, -7.0, 8.0)
	pl.input_pitch = clampf((vz_des - vel.y) * 0.06, -0.45, 0.45)
	var want_spd := cruise_speed
	thr_target = clampf(0.55 + (want_spd - spd) * 0.05, 0.15, 1.0)
	pl.input_throttle = thr_target
	pl.input_brake = 0.0
