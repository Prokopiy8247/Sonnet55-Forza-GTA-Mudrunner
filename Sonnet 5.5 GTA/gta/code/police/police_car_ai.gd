class_name PoliceCarAI
extends Node
## Driver AI of a police VehicleBase (cruiser or tactical van). A child node of the vehicle; it writes the vehicle's input_* every
## physics frame (set_ai_controlled(true)), never touches the physics body directly (no teleports, no forces) so a car can never be
## "cheated" into flips - ramming and PIT contact is real rigid-body contact, limited by what the controller asks for.
##
## Modes (set_order mode): patrol  - lane-follow like traffic but brisker, siren off, obeys red signals
##                         pursue  - siren on, chase the target (lane graph when far / on road, pure pursuit when close / off road),
##                                   roles by rank (tail / flank / pit / intercept), PIT, boxing-in, ramming at 3+ stars,
##                                   stop ~12 m from a target on foot and deploy the officers, re-collect them afterwards
##                         search  - cruise the search area at moderate speed, spotlight sweep at night
##                         hold    - parked (roadblock cars): brake, lights
##                         leave   - drive away along the lanes and despawn when far + unseen
## Orders: {"mode", "target": Node, "pos": Vector3, "radius": float, "aggression": 0..1, "lethal": bool, "level": int}.

const LAT_ACCEL_PURSUIT := 9.0
const BOX_SPEED := 6.0
const DEPLOY_DIST := 13.0
const PIT_MIN_SPEED := 11.0
const PIT_COOLDOWN := 3.2

static var fleet: Array = []
static var stat_usec := 0
static var stat_ticks := 0
static var pit_attempts := 0
static var pit_contacts := 0
static var rams := 0
static var deploys := 0
static var debug_names := false          # tests: remember what blocks the way (ahead_name)

var car: VehicleBase = null
var mode: StringName = &"patrol"
var order: Dictionary = {}
var target: Node3D = null
var aggression := 0.5
var lethal := false
var level := 0
var role: StringName = &"tail"
var role_hint: StringName = &""        # role suggested by the director's order (wins over the rank-based role while we are the nearest)
var deployed := false
var search_center := Vector3.ZERO
var search_radius := 60.0
var active := true
var last_steer := 0.0

# ---- lane following state ------------------------------------------------------------------------------------------------
var _lane_i := -1
var _dest := Vector3.ZERO
var _guide := 0                          # 0 random, 1 toward _dest, 2 away from _away
var _away := Vector3.ZERO
var _seed := 0
var _now := 0.0
var _sense_t := 0.0
var _rank_t := 0.0
var _rank := 0
var _ahead := 99.0                       # distance to the nearest obstacle in front (m)
var _ahead_vehicle := false
var _target_on_road := false
var _aim_dir := Vector3.ZERO
var _aim_valid := false
var _guided := false                      # steering by the lane graph (static roadside obstacles only brake, no side-stepping)
var _ahead_static := false
var ahead_name := ""
var _avoid_off := 0.0                    # lateral offset (m) added to the aim point to pass an obstacle
var _avoid_until := 0.0
var _blocked_t := 0.0
var _stuck_t := 0.0
var _reverse_until := 0.0
var _reverse_steer := 0.0
var _stuck_count := 0
var _steer_cmd := 0.0
var _pit_cd := 0.0
var _pit_until := 0.0
var _pit_side := 0.0
var _ram_cd := 0.0
var _contact_t := -10.0
var _deploy_t := 0.0
var _leave_t := 0.0
var _hold_still := false
var _lod_skip := 0
var _frame := 0
var _q := PhysicsRayQueryParameters3D.new()
var _spot: SpotLight3D = null
var _search_next := 0.0
var _flipped_t := 0.0
var _aim_cache_off := Vector3.ZERO
var _aim_cache_side := 0.0
var _aim_cache_until := 0.0
var _stuck_hist: Array[float] = []        # timestamps of recent stuck events (escalating recovery)
var _blocked: Dictionary = {}             # lane index -> time until which the lane counts as blocked (static obstacle ahead)
var _lane_i_last := -1                    # last valid lane index (the stuck handler clears _lane_i before noting the stuck event)
var _guided_last := false
var _responding := false                  # search mode, still far from the search area: driving there with the siren on
var top_response := 24.0                  # m/s cap while responding
static var recoveries := 0                # statistic: hidden relocations to the road after repeated stuck events
var _lat_limit := 12.0
var _wheelbase := 2.8
var _steer_gain := 1.5
var _steer_min := 0.05
var _steer_lock := 0.55
var _top_speed := 55.0
var _orig_siren := false
var _order_time := -100.0
var _auto_t := 0.0
var speed_factor := 1.12                  # patrol cruising speed relative to the lane speed limit
var obey_signals := true                  # patrol / search stop at red lights (pursuit never does)
var driverless := false                   # drive without an officer at the wheel (scripted runners / tests)
var autonomous := true                   # derive orders from Game.wanted_* when the director sends none (VehicleBase has no set_order)


# =====================================================================================================================
# Attach / detach
# =====================================================================================================================
static func attach(v: VehicleBase) -> PoliceCarAI:
	if v == null or not is_instance_valid(v):
		return null
	if v.has_meta(&"police_ai"):
		var ex = v.get_meta(&"police_ai")
		if is_instance_valid(ex):
			return ex
	var ai := PoliceCarAI.new()
	ai.name = "PoliceCarAI"
	v.add_child(ai)
	ai._setup(v)
	v.set_meta(&"police_ai", ai)
	return ai


static func detach(v: VehicleBase) -> void:
	if v != null and is_instance_valid(v) and v.has_meta(&"police_ai"):
		var ai = v.get_meta(&"police_ai")
		v.remove_meta(&"police_ai")
		if is_instance_valid(ai):
			ai.queue_free()


func _setup(v: VehicleBase) -> void:
	car = v
	car.set_ai_controlled(true)
	car.keep_engine_on = true
	_seed = int(v.get_instance_id() % 9973)
	_q.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_NPC | GC.L_PLAYER | GC.L_PROP
	_q.exclude = [v.get_rid()]
	_top_speed = float(v.def.get("top_speed_kmh", 200.0)) / 3.6
	_wheelbase = float(v.def.get("wheelbase", 2.8))
	if v is CarVehicle:
		var cv := v as CarVehicle
		_lat_limit = cv.lat_accel_limit
		_steer_gain = cv.steer_gain
		_steer_min = cv.steer_min
		_steer_lock = cv.steer_lock
	fleet.append(self)
	if v.has_signal("collided"):
		v.collided.connect(_on_collided)
	_frame = int(v.get_instance_id() % 4)


func _exit_tree() -> void:
	fleet.erase(self)
	if is_instance_valid(_spot):
		_spot.queue_free()


# =====================================================================================================================
# Orders
# =====================================================================================================================
func set_order(o: Dictionary) -> void:
	_order_time = _now
	order = o.duplicate()
	var new_mode: StringName = order.get("mode", &"patrol")
	var changed := new_mode != mode
	mode = new_mode
	var t = order.get("target", null)
	if t != null and is_instance_valid(t) and t is Node3D:
		target = t
	elif mode == &"pursue" and Game.player != null and is_instance_valid(Game.player):
		target = Game.player
	elif mode != &"pursue":
		target = null
	aggression = clampf(float(order.get("aggression", 0.5)), 0.0, 1.0)
	lethal = bool(order.get("lethal", Game.wanted_level >= 2))
	level = int(order.get("level", Game.wanted_level))
	if order.has("pos"):
		search_center = order["pos"]
	search_radius = float(order.get("radius", 60.0))
	if order.has("role") and order["role"] in [&"tail", &"flank", &"intercept", &"pit", &"block"]:
		role_hint = order["role"] if order["role"] != &"block" else &"intercept"
	if changed:
		_lane_i = -1
		_avoid_off = 0.0
		_stuck_t = 0.0
		_responding = false
		if mode != &"pursue":
			deployed = false
		_apply_siren()
	_guide = 1 if mode in [&"search", &"pursue"] else 0
	_search_next = 0.0


## Without orders (the director cannot call set_order on a VehicleBase) the car reads the wanted state itself.
func _autonomous_order() -> void:
	if _now - _order_time < 6.0:
		return
	var lvl := Game.wanted_level
	var want_mode: StringName = &"patrol"
	if lvl > 0:
		want_mode = &"search" if Game.wanted_state == &"search" else &"pursue"
	if want_mode == mode and (mode == &"patrol" or mode == &"search" or (mode == &"pursue" and level == lvl)):
		return
	var o := {"mode": want_mode, "target": Game.player if want_mode == &"pursue" else null, "aggression": [0.1, 0.25, 0.55, 0.75, 0.9, 1.0][clampi(lvl, 0, 5)],
		"lethal": lvl >= 2 and want_mode == &"pursue", "level": lvl, "radius": 70.0}
	var w = Game.sys(&"wanted")
	if want_mode == &"search":
		o["pos"] = w.get_last_known_position() if w != null and w.has_method("get_last_known_position") else car.global_position
		o["radius"] = w.get_search_radius() if w != null and w.has_method("get_search_radius") else 70.0
	set_order(o)
	_order_time = -100.0       # keep it autonomous: a real order from the director will set _order_time again


func _apply_siren() -> void:
	if car == null:
		return
	match mode:
		&"pursue", &"hold":
			car.siren_on = true
			car.headlights_on = true
		&"search":
			car.siren_on = false
			car.headlights_on = true
		&"leave":
			car.siren_on = false
		_:
			car.siren_on = false


# =====================================================================================================================
# Tick
# =====================================================================================================================
func _physics_process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var t0 := Time.get_ticks_usec()
	_now += dt
	_frame += 1
	if car.is_destroyed:
		_release()
		return
	var drv := car.driver
	active = drv != null and drv is PoliceOfficer and not (drv as PoliceOfficer).is_dead and car.is_ai_controlled
	if driverless and car.is_ai_controlled and (drv == null or not drv.is_in_group(GC.G_PLAYER)):
		active = true
	if not active:
		if drv == null or drv is PoliceOfficer:
			_hold_brake(dt, 0.7)
		return
	# distance tier: far cars update their controller less often
	var pl = Game.player
	var far := 0.0
	if pl != null and is_instance_valid(pl):
		far = (pl as Node3D).global_position.distance_to(car.global_position)
	_lod_skip = 0 if far < 120.0 else (1 if far < 220.0 else 3)
	if _lod_skip > 0 and (_frame % (_lod_skip + 1)) != 0:
		return
	var step := dt * float(_lod_skip + 1)
	_auto_t -= step
	if autonomous and _auto_t <= 0.0:
		_auto_t = 0.6
		_autonomous_order()
	_sense_t -= step
	if _sense_t <= 0.0:
		_sense_t = 0.09 if _lod_skip == 0 else 0.2
		_sense()
	_pit_cd = maxf(_pit_cd - step, 0.0)
	_ram_cd = maxf(_ram_cd - step, 0.0)
	_check_flipped(step)
	_guided = false
	match mode:
		&"pursue":
			_pursue(step)
		&"search":
			_search(step)
		&"leave":
			_leave(step)
		&"hold":
			_hold_brake(step, 0.9)
		_:
			_patrol(step)
	_feed_driver_rig()
	stat_usec += Time.get_ticks_usec() - t0
	stat_ticks += 1


func _release() -> void:
	car.input_throttle = 0.0
	car.input_brake = 0.0
	car.input_steer = 0.0
	car.input_handbrake = false


func _hold_brake(_dt: float, amount: float) -> void:
	car.input_throttle = 0.0
	car.input_brake = amount if absf(car.get_forward_speed()) > 0.4 else 0.25
	car.input_steer = 0.0
	car.input_handbrake = car.get_speed() < 1.5


func _feed_driver_rig() -> void:
	var drv = car.driver
	if drv != null and drv.get("rig") != null and is_instance_valid(drv.rig) and drv.rig.has_method("set_steering"):
		drv.rig.set_steering(last_steer)


func _check_flipped(dt: float) -> void:
	if car.is_flipped_over():
		_flipped_t += dt
		if _flipped_t > 3.5:
			car.unflip()
			_flipped_t = 0.0
	else:
		_flipped_t = 0.0


func _on_collided(other: Node, impact: float) -> void:
	if other == null:
		return
	if target != null and (other == target or other == target.get("current_vehicle")):
		_contact_t = _now
		if _now < _pit_until + 0.6:
			pit_contacts += 1
	elif impact > 6.0 and mode == &"pursue" and _now - _contact_t > 0.3:
		# hit something else hard: back off the throttle for a moment
		_avoid_until = _now + 0.6


# =====================================================================================================================
# Sensing
# =====================================================================================================================
func _sense() -> void:
	var xf := car.global_transform
	var fwd := -xf.basis.z
	# probe along the intended path (the aim point), not straight ahead: at a junction the straight ray would hit the corner furniture
	if _aim_valid:
		var af := Vector3(_aim_dir.x, 0.0, _aim_dir.z)
		if af.length() > 0.1 and af.normalized().dot(fwd) > 0.75:
			fwd = af.normalized()
	var right := fwd.cross(Vector3.UP)
	var v := car.get_forward_speed()
	var reach := clampf(7.0 + maxf(v, 0.0) * 0.8, 7.0, 42.0)
	var space := car.get_world_3d().direct_space_state
	var best := reach
	_ahead_vehicle = false
	var half_w := float(car.def.get("width", 1.9)) * 0.5 - 0.15
	var base := xf.origin + fwd * float(car.def.get("length", 4.7)) * 0.5 + Vector3(0, 0.75, 0)
	var offsets := [0.0, -half_w, half_w]
	for off in offsets:
		_q.from = base + right * off
		_q.to = _q.from + fwd * reach
		var hit := space.intersect_ray(_q)
		if hit.is_empty():
			continue
		var col: Object = hit["collider"]
		# the chase target itself is not an obstacle to avoid (we want to get there / bump it on purpose)
		if target != null and (col == target or col == target.get("current_vehicle")):
			continue
		if absf((hit["normal"] as Vector3).y) > 0.7:
			continue          # ramps, road slopes
		var d := _q.from.distance_to(hit["position"])
		if d < best:
			best = d
			_ahead_vehicle = col is VehicleBase
			_ahead_static = col is StaticBody3D
			if debug_names:
				ahead_name = "%s/%s" % [(col as Node).get_parent().name if (col as Node).get_parent() != null else "", (col as Node).name]
	_ahead = best
	# decide a side-step around a slow obstacle: the side with the longer free ray wins
	if best < reach * 0.55 and absf(v) < 6.0:
		_blocked_t += 0.09
	else:
		_blocked_t = maxf(_blocked_t - 0.09, 0.0)
	# lane-guided cars only brake for roadside statics (no side-stepping onto sidewalks), unless the way has been blocked for a while
	# (a bollard / bin standing in the lane of a narrow alley)
	var may_sidestep := not (_guided and _ahead_static) or _blocked_t > 1.3
	if may_sidestep and ((best < 14.0 and _now > _avoid_until and absf(v) > 1.0) or _blocked_t > 0.8):
		var l := _free_len(space, base, (fwd - right * 0.55).normalized(), 18.0)
		var r := _free_len(space, base, (fwd + right * 0.55).normalized(), 18.0)
		if absf(l - r) > 2.0 or _blocked_t > 0.8:
			_avoid_off = -3.2 if l > r else 3.2
			_avoid_until = _now + 1.4
	elif _now > _avoid_until:
		_avoid_off = 0.0
	# is the chase target on a road? (decides lane-guided vs direct pursuit)
	if target != null and is_instance_valid(target) and _lanes().size() > 0:
		var tp: Vector3 = target.global_position
		var tv = target if target is VehicleBase else target.get("current_vehicle")
		if tv != null and is_instance_valid(tv):
			tp = (tv as Node3D).global_position
		_target_on_road = _lanes().nearest(tp, Vector3.ZERO, 9.0) >= 0
	# role rank (cheap, fleet <= 10)
	_rank_t -= 0.09
	if _rank_t <= 0.0:
		_rank_t = 0.6
		_update_rank()


func _free_len(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float) -> float:
	_q.from = from
	_q.to = from + dir * length
	var hit := space.intersect_ray(_q)
	if hit.is_empty():
		return length
	return from.distance_to(hit["position"])


func _update_rank() -> void:
	if target == null or not is_instance_valid(target):
		_rank = 0
		return
	var mine := car.global_position.distance_squared_to(target.global_position)
	var rank := 0
	for o in fleet:
		var ai: PoliceCarAI = o
		if ai == self or not is_instance_valid(ai) or ai.car == null or not ai.active or ai.mode != &"pursue" or ai.target != target:
			continue
		if ai.car.global_position.distance_squared_to(target.global_position) < mine:
			rank += 1
	_rank = rank
	match rank:
		0:
			role = &"tail"
		1:
			role = &"flank"
		2:
			role = &"pit"
		_:
			role = &"intercept" if rank % 2 == 1 else &"flank"
	if role_hint != &"":
		role = role_hint


# =====================================================================================================================
# Lane graph helpers
# =====================================================================================================================
func _lanes() -> LaneGraph:
	return WorldLayout.lanes


func _ensure_lane() -> bool:
	var lg := _lanes()
	if lg.size() == 0:
		return false
	var xf := car.global_transform
	var pos := xf.origin
	if _lane_i >= 0:
		var lp := lg.positions[_lane_i]
		if Util.dist_xz(lp, pos) > 22.0:
			_lane_i = -1
	if _lane_i < 0:
		var fwd := -xf.basis.z
		_lane_i = lg.nearest(pos, fwd, 26.0)
		if _lane_i < 0:
			_lane_i = lg.nearest(pos, Vector3.ZERO, 40.0)
		if _lane_i < 0:
			return false
		if _is_blocked(_lane_i):
			# a lane we already wedged on (dead end / road works): take the best free lane nearby, the opposite direction included (U-turn)
			var best := -1
			var best_s := INF
			for j in lg.points_in_radius(pos, 32.0):
				if _is_blocked(j):
					continue
				var s := Util.dist_xz(lg.positions[j], pos) + (1.0 - lg.dirs[j].dot(fwd)) * 10.0
				if s < best_s:
					best_s = s
					best = j
			if best >= 0:
				_lane_i = best
	# advance past points that are behind the car
	var guard := 0
	while guard < 8:
		guard += 1
		var lp2 := lg.positions[_lane_i]
		var d := lp2 - pos
		var ahead := d.dot(-xf.basis.z)
		if ahead < 1.0 + maxf(car.get_forward_speed(), 0.0) * 0.12 and Util.dist_xz(lp2, pos) < 14.0:
			var nx := _choose_next(_lane_i)
			if nx < 0:
				break
			_lane_i = nx
		else:
			break
	return true


func _choose_next(i: int) -> int:
	var lg := _lanes()
	var nx: PackedInt32Array = lg.next[i]
	if nx.size() == 0:
		return -1
	if nx.size() == 1:
		return nx[0]
	var best := nx[0]
	var best_s := INF
	for k in nx.size():
		var s := nx[k]
		var sc := 0.0
		match _guide:
			1:
				sc = Util.dist_xz(lg.positions[s] + lg.dirs[s] * 80.0, _dest)
			2:
				sc = -Util.dist_xz(lg.positions[s] + lg.dirs[s] * 80.0, _away)
			_:
				sc = float((i * 2654435 + k * 40503 + _seed * 31) % 1000)
		if lg.dirs[s].dot(lg.dirs[i]) < -0.5:
			sc += 500.0
		if _is_blocked(s):
			sc += 900.0
		if sc < best_s:
			best_s = sc
			best = s
	return best


## Lookahead that shortens before a sharp corner (pure pursuit with a long chord would cut the junction corner and hit the curb).
func _lane_look(dist: float) -> Dictionary:
	var info := _lane_ahead(dist)
	var corner: float = info["corner"]
	if corner > 0.45:
		var cd: float = info["corner_dist"]
		if cd < dist:
			info = _lane_ahead(clampf(cd * 0.9, 4.5, dist))
	return info


## Point `dist` metres ahead along the lane chain from the current lane index, plus info about the corner coming up.
func _lane_ahead(dist: float) -> Dictionary:
	var lg := _lanes()
	var i := _lane_i
	var acc := 0.0
	var p := lg.positions[i]
	var limit := lg.speed_limit[i]
	var corner := 0.0
	var d0 := lg.dirs[i]
	var stop_dist := INF
	var guard := 0
	var corner_dist := 0.0
	while acc < dist and guard < 24:
		guard += 1
		var nx := _choose_next(i)
		if nx < 0:
			break
		acc += Util.dist_xz(lg.positions[nx], lg.positions[i])
		i = nx
		p = lg.positions[i]
		if acc < 38.0:
			var ang := acos(clampf(d0.dot(lg.dirs[i]), -1.0, 1.0))
			if ang > corner:
				corner = ang
				corner_dist = acc
		if obey_signals and not _responding and lg.signal_id[i] >= 0 and stop_dist == INF:
			var st := WorldLayout.signal_state(lg.signal_id[i], lg.signal_phase[i], Time.get_ticks_msec() / 1000.0)
			if st != 0:
				stop_dist = (p - car.global_position).length()
	return {"p": p, "corner": corner, "corner_dist": corner_dist, "limit": limit, "stop": stop_dist}


# =====================================================================================================================
# Driving primitive
# =====================================================================================================================
## Pure-pursuit steering to world point P with target speed v_target (m/s). Handles reverse recovery, obstacle slow-down and the
## speed limit imposed by curvature. Returns the steering command.
func _drive_to(p_world: Vector3, v_target: float, dt: float, allow_reverse := true) -> void:
	var xf := car.global_transform
	var v := car.get_forward_speed()
	# ---- reverse recovery after getting stuck
	if _now < _reverse_until:
		car.input_throttle = 0.0
		car.input_brake = 1.0
		car.input_steer = _reverse_steer
		car.input_handbrake = false
		last_steer = _reverse_steer
		return
	var aim := p_world
	if _avoid_off != 0.0:
		aim += xf.basis.x * _avoid_off
	_aim_dir = aim - xf.origin
	_aim_valid = true
	var local := xf.affine_inverse() * aim
	var fwd_d := -local.z
	var lat := local.x
	var ld := maxf(Vector2(lat, fwd_d).length(), 1.5)
	var alpha := atan2(lat, maxf(fwd_d, 0.001)) if fwd_d > 0.0 else (PI * 0.5 * signf(lat) if lat != 0.0 else PI * 0.5)
	var kappa := 2.0 * sin(alpha) / ld
	var delta := atan(_wheelbase * kappa)
	var max_ang := clampf(_steer_gain * _wheelbase * _lat_limit / (v * v + 4.0), _steer_min, _steer_lock)
	var steer := clampf(delta / max_ang, -1.0, 1.0)
	if fwd_d < 0.5:
		steer = signf(lat) if lat != 0.0 else 1.0
	# ---- speed
	var a_lat := LAT_ACCEL_PURSUIT * lerpf(0.8, 1.05, aggression) if mode == &"pursue" else 6.0
	var v_curve := sqrt(a_lat / maxf(absf(kappa), 0.004))
	var v_des := minf(v_target, v_curve)
	var v_wanted := v_des
	# obstacles in front
	var ob_brake := 0.0
	if _ahead < 40.0:
		var closing_room := _ahead - (3.5 + maxf(v, 0.0) * 0.18)
		var v_obs := sqrt(maxf(2.0 * 7.0 * maxf(closing_room, 0.0), 0.0))
		if _ahead_vehicle:
			v_obs = maxf(v_obs, 0.0)
		v_des = minf(v_des, v_obs + (1.5 if closing_room > 0.0 else 0.0))
		if _ahead < 2.8 and v > 1.0:
			ob_brake = 1.0
	_steer_cmd = lerpf(_steer_cmd, steer, 1.0 - exp(-14.0 * dt))
	car.input_steer = _steer_cmd
	last_steer = _steer_cmd
	var err := v_des - v
	var thr := 0.0
	var brk := 0.0
	if err > 0.4:
		thr = clampf(err * 0.32, 0.18, 1.0)
		# big steering at speed: do not accelerate hard through the turn
		thr *= lerpf(1.0, 0.55, clampf(absf(steer) - 0.6, 0.0, 0.4) / 0.4)
	elif err < -1.0:
		brk = clampf(-err * 0.11, 0.05, 1.0)
	car.input_throttle = thr
	car.input_brake = maxf(brk, ob_brake)
	car.input_handbrake = false
	if car.input_brake > 0.0 and thr > 0.0:
		car.input_throttle = 0.0
	# ---- stuck detection (wants to move, does not)
	if allow_reverse:
		if v_wanted > 3.0 and absf(v) < 0.7 and not _hold_still:
			_stuck_t += dt * (2.0 if _ahead < 1.6 else 1.0)
			if _stuck_t > 1.7:
				_stuck_t = 0.0
				_stuck_count += 1
				_reverse_until = _now + randf_range(1.0, 1.7)
				_reverse_steer = -signf(last_steer) if absf(last_steer) > 0.15 else (1.0 if randf() < 0.5 else -1.0)
				_avoid_off = 0.0
				_lane_i_last = _lane_i
				_guided_last = _guided
				_lane_i = -1
				_note_stuck()
		else:
			_stuck_t = maxf(_stuck_t - dt * 2.0, 0.0)


## Called after every stuck event. Repeated events inside 22 s escalate: a long full-lock reverse first, then (when nobody can see it)
## a hidden relocation onto the nearest free lane point facing along the lane.
func _is_blocked(lane_index: int) -> bool:
	return _blocked.size() > 0 and float(_blocked.get(lane_index, 0.0)) > _now


## Remembers the lanes ahead of a static obstacle that stopped the car (30 s) so that the router picks another way / turns around.
func _mark_blocked_ahead() -> void:
	var lg := _lanes()
	var i := _lane_i_last
	for k in 8:
		if i < 0 or i >= lg.size():
			break
		_blocked[i] = _now + 30.0
		var nx: PackedInt32Array = lg.next[i]
		if nx.size() != 1:
			break
		i = nx[0]


func _note_stuck() -> void:
	if _lane_i_last >= 0 and _ahead < 8.0 and _ahead_static and _guided_last:
		_mark_blocked_ahead()
	_stuck_hist.append(_now)
	while _stuck_hist.size() > 0 and _now - _stuck_hist[0] > 22.0:
		_stuck_hist.remove_at(0)
	var n := _stuck_hist.size()
	if n >= 2:
		_reverse_until = _now + randf_range(1.8, 2.6)
	if n >= 3 and _recover_to_road():
		_stuck_hist.clear()


func _recover_to_road() -> bool:
	var lg := _lanes()
	if lg.size() == 0:
		return false
	var cam: Camera3D = Game.gameplay_camera
	if cam != null and is_instance_valid(cam):
		var d := cam.global_position.distance_to(car.global_position)
		if d < 22.0 or (d < 90.0 and cam.is_position_in_frustum(car.global_position)):
			return false                       # somebody would see the car pop: keep struggling instead
	var i := lg.nearest(car.global_position, Vector3.ZERO, 45.0)
	if i < 0:
		return false
	for k in 5:
		var p := lg.positions[i]
		var dir := lg.dirs[i]
		if _spot_is_free(p, dir):
			var xf := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), p + Vector3(0, 0.45, 0))
			car.place_at(xf)
			car.set_velocity(dir * 5.0)
			_lane_i = i
			_avoid_off = 0.0
			_reverse_until = 0.0
			recoveries += 1
			return true
		var nx := lg.next[i] as PackedInt32Array
		if nx.size() == 0:
			break
		i = nx[0]
	return false


func _spot_is_free(p: Vector3, dir: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.3, 1.5, 5.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), p + Vector3(0, 1.1, 0))
	q.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP | GC.L_NPC | GC.L_PLAYER
	q.exclude = [car.get_rid()]
	return car.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# =====================================================================================================================
# Modes
# =====================================================================================================================
func _patrol(dt: float) -> void:
	_hold_still = false
	if not _ensure_lane():
		_hold_brake(dt, 0.5)
		return
	_guided = true
	var v := car.get_forward_speed()
	var info := _lane_look(6.0 + maxf(v, 0.0) * 0.4)
	var limit: float = info["limit"]
	var vt := limit * speed_factor
	vt = _apply_corner_and_stop(vt, info, v)
	_drive_to(info["p"], vt, dt)


func _apply_corner_and_stop(vt: float, info: Dictionary, v: float) -> float:
	var corner: float = info["corner"]
	if corner > 0.35:
		var cd: float = maxf(info["corner_dist"], 4.0)
		var v_turn := lerpf(9.0, 5.0, clampf((corner - 0.35) / 1.2, 0.0, 1.0))
		# brake in time: v^2 = v_turn^2 + 2 a d
		var v_allow := sqrt(v_turn * v_turn + 2.0 * 6.0 * cd)
		vt = minf(vt, v_allow)
	var stop: float = info["stop"]
	if stop < INF:
		var room := maxf(stop - 7.5, 0.0)
		var v_stop := sqrt(2.0 * 5.5 * room)
		vt = minf(vt, v_stop)
	return vt


func _search(dt: float) -> void:
	_hold_still = false
	# far from the search area: respond at emergency speed with the siren on (signals ignored), then cruise the area at patrol pace
	var d_center := Util.dist_xz(car.global_position, search_center)
	var was_responding := _responding
	_responding = search_center != Vector3.ZERO and d_center > maxf(search_radius * 1.2, 55.0)
	if _responding:
		_guide = 1
		_dest = search_center
		_search_next = _now + 3.0
		if not car.siren_on:
			car.siren_on = true
		if not _ensure_lane():
			_hold_brake(dt, 0.5)
			return
		_guided = true
		var vr := car.get_forward_speed()
		var info_r := _lane_look(7.0 + maxf(vr, 0.0) * 0.45)
		var vt_r := minf(maxf(float(info_r["limit"]) * 1.35, 14.0), top_response)
		vt_r = _apply_corner_and_stop_pursuit(vt_r, info_r)
		_drive_to(info_r["p"], vt_r, dt)
		return
	if was_responding:
		car.siren_on = false
		_search_next = 0.0
	if _now > _search_next:
		_search_next = _now + randf_range(14.0, 24.0)
		var lg := _lanes()
		var p := Util.rand_in_ring(search_center, 0.0, search_radius)
		var idx := lg.nearest(p, Vector3.ZERO, 60.0) if lg.size() > 0 else -1
		_dest = lg.positions[idx] if idx >= 0 else p
	_guide = 1
	if not _ensure_lane():
		_hold_brake(dt, 0.5)
		return
	_guided = true
	var v := car.get_forward_speed()
	var info := _lane_look(6.0 + maxf(v, 0.0) * 0.4)
	var vt := minf(float(info["limit"]) * 0.95, 15.0)
	vt = _apply_corner_and_stop(vt, info, v)
	_drive_to(info["p"], vt, dt)
	_update_spotlight(dt)


func _update_spotlight(_dt: float) -> void:
	var want := Game.is_night() and mode == &"search"
	if want and _spot == null:
		_spot = SpotLight3D.new()
		_spot.name = "SearchLight"
		_spot.spot_range = 45.0
		_spot.spot_angle = 17.0
		_spot.light_energy = 6.0
		_spot.light_color = Color(1.0, 0.97, 0.88)
		_spot.shadow_enabled = false
		car.add_child(_spot)
		_spot.position = Vector3(0.0, 1.55, -0.5)
	if _spot != null:
		_spot.visible = want
		if want:
			var sweep := sin(_now * 0.9) * 0.9
			_spot.rotation = Vector3(-0.08, sweep + 1.0 * signf(sin(_now * 0.17)), 0.0)


func _leave(dt: float) -> void:
	_hold_still = false
	_leave_t += dt
	var pl = Game.player
	if pl != null and is_instance_valid(pl):
		_away = (pl as Node3D).global_position
	_guide = 2
	if not _ensure_lane():
		_hold_brake(dt, 0.5)
		return
	_guided = true
	var v := car.get_forward_speed()
	var info := _lane_look(6.0 + maxf(v, 0.0) * 0.4)
	var vt := float(info["limit"]) * 0.9
	vt = _apply_corner_and_stop(vt, info, v)
	_drive_to(info["p"], vt, dt)
	if _leave_t > 12.0 and pl != null and is_instance_valid(pl):
		var d: float = (pl as Node3D).global_position.distance_to(car.global_position)
		var seen := false
		var cam: Camera3D = Game.gameplay_camera
		if cam != null and is_instance_valid(cam) and d < 200.0:
			seen = cam.is_position_in_frustum(car.global_position)
		if d > 150.0 and not seen:
			PoliceUnits.despawn(car)


# ---- pursuit ----------------------------------------------------------------------------------------------------------------
func _pursue(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		if Game.player != null and is_instance_valid(Game.player):
			target = Game.player
		else:
			_hold_brake(dt, 0.6)
			return
	var tgt := target
	var tpos := tgt.global_position
	var tveh = tgt if tgt is VehicleBase else tgt.get("current_vehicle")
	var t_in_car: bool = tveh != null and is_instance_valid(tveh)
	var tvel := Vector3.ZERO
	var tbasis := tgt.global_transform.basis
	if t_in_car:
		tvel = (tveh as VehicleBase).linear_velocity
		tbasis = (tveh as Node3D).global_transform.basis
		tpos = (tveh as Node3D).global_position
	elif tgt is CharacterBody3D:
		tvel = (tgt as CharacterBody3D).velocity
	elif tgt is RigidBody3D:
		tvel = (tgt as RigidBody3D).linear_velocity
		tbasis = tgt.global_transform.basis
	tvel.y = 0.0
	var tspeed := tvel.length()
	var here := car.global_position
	var to_t := Vector3(tpos.x - here.x, 0.0, tpos.z - here.z)
	var dist := to_t.length()
	var v := car.get_forward_speed()
	var top := _top_speed
	_hold_still = false
	# ---- deployed: the car waits while its officers work on foot
	if deployed:
		_pursue_deployed(dt, t_in_car, tspeed, dist)
		return
	# ---- target on foot: stop at ~12 m and deploy
	if not t_in_car:
		var vt_foot := clampf((dist - DEPLOY_DIST) * 0.9, 0.0, 22.0)
		if dist < DEPLOY_DIST + 3.0 and absf(v) < 3.0:
			_hold_brake(dt, 0.9)
			_hold_still = true
			_deploy_t += dt
			if _deploy_t > 0.35:
				_deploy()
			return
		_deploy_t = 0.0
		var p_foot := tpos
		if dist > 30.0 or not _clear_to(tpos):
			if _ensure_lane():
				_dest = tpos
				_guide = 1
				_guided = true
				var info := _lane_look(7.0 + maxf(v, 0.0) * 0.45)
				p_foot = info["p"]
				var vt := minf(maxf(float(info["limit"]) * lerpf(1.4, 1.9, aggression), 14.0), top * 0.8)
				vt = _apply_corner_and_stop_pursuit(vt, info)
				_drive_to(p_foot, vt, dt)
				return
		_drive_to(p_foot, minf(vt_foot + 2.0, 20.0), dt)
		return
	# ---- target in a vehicle ----
	_deploy_t = 0.0
	if tspeed < BOX_SPEED and dist < 40.0:
		_box_in(dt, tpos, tvel, tbasis, dist, v)
		return
	# PIT execution window overrides everything for a moment
	if _now < _pit_until:
		car.input_throttle = 0.85
		car.input_brake = 0.0
		_steer_cmd = lerpf(_steer_cmd, _pit_side * 0.55, 1.0 - exp(-12.0 * dt))
		car.input_steer = _steer_cmd
		last_steer = _steer_cmd
		return
	var fwd_t := -tbasis.z
	fwd_t.y = 0.0
	fwd_t = fwd_t.normalized() if fwd_t.length() > 0.1 else Vector3(0, 0, -1)
	var right_t := Vector3(-fwd_t.z, 0.0, fwd_t.x)
	var aim := tpos
	var v_goal := tspeed
	match role:
		&"flank":
			var side := 1.0 if (car.get_instance_id() % 2 == 0) else -1.0
			aim = _road_aim(tpos + tvel * clampf(dist / 25.0, 0.4, 2.2), right_t, side, 4.2)
			v_goal = tspeed + clampf(dist * 0.5, 2.0, 12.0)
		&"intercept":
			var lead := clampf(dist / maxf(v + 8.0, 12.0), 1.0, 5.0)
			aim = tpos + tvel * lead
			v_goal = maxf(tspeed + 10.0, 18.0)
		&"pit":
			aim = _road_aim(tpos - fwd_t * 3.0, right_t, 1.0 if (car.get_instance_id() % 2 == 0) else -1.0, 2.0)
			v_goal = tspeed + clampf(dist * 0.4, 1.0, 10.0)
		_:
			aim = tpos + tvel * clampf(dist / 30.0, 0.15, 1.0)
			v_goal = tspeed + clampf((dist - 7.0) * 0.55, -2.0, 16.0)
			if level >= 3 and aggression > 0.45 and dist < 14.0:
				v_goal = tspeed + 5.0                    # keep pushing: real ramming contact at 3+ stars
	# PIT / ramming opportunities (the unit is next to the target's rear quarter)
	if level >= 2 and tspeed > PIT_MIN_SPEED and dist < 16.0 and _pit_cd <= 0.0:
		if _try_pit(tpos, tbasis, tvel):
			return
	if level >= 3 and aggression > 0.45 and dist < 9.0 and _ram_cd <= 0.0 and tspeed > 6.0 and role == &"tail":
		_ram_cd = 4.0
		rams += 1                                   # statistic: a ram attempt (the push above produces the contact)
	# guidance
	var use_lane := _target_on_road and (dist > 16.0 or not _clear_to(tpos))
	if use_lane and _ensure_lane():
		_dest = tpos + tvel * clampf(dist / 28.0, 0.5, 3.0)
		_guide = 1
		_guided = true
		var info2 := _lane_look(7.0 + maxf(v, 0.0) * 0.45)
		var vt2 := minf(maxf(float(info2["limit"]) * lerpf(1.45, 1.95, aggression), maxf(tspeed + 8.0, 16.0)), top * 0.82)
		vt2 = _apply_corner_and_stop_pursuit(vt2, info2)
		_drive_to(info2["p"], vt2, dt)
	else:
		var vt3 := clampf(v_goal, 3.0, top * 0.8)
		# tail car never rams its own target by accident above a modest closing speed
		if dist < 10.0 and role == &"tail" and level < 3:
			vt3 = minf(vt3, tspeed + 3.0)
		_drive_to(aim, vt3, dt)


func _apply_corner_and_stop_pursuit(vt: float, info: Dictionary) -> float:
	var corner: float = info["corner"]
	if corner > 0.3:
		var cd: float = maxf(info["corner_dist"], 4.0)
		var v_turn := lerpf(13.0, 6.5, clampf((corner - 0.3) / 1.2, 0.0, 1.0))
		var v_allow := sqrt(v_turn * v_turn + 2.0 * 7.5 * cd)
		vt = minf(vt, v_allow)
	return vt


## True when the ground under `p` is road (asphalt collider): lateral offsets of flanking cars must never push the aim point onto a sidewalk
## full of lamp posts / hydrants / facades (the car would wedge itself there).
func _on_asphalt(p: Vector3) -> bool:
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p + Vector3(0, -3.0, 0), GC.L_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var col: Object = hit["collider"]
	return col is Node and (col as Node).has_meta(&"surface") and StringName(str((col as Node).get_meta(&"surface"))) == &"asphalt"


## `base` shifted sideways by `mag` m (preferred side first), shrinking / flipping until the point is on the road. Cached for a short
## time (a few rays per call). When the target is off-road the plain offset is used.
func _road_aim(base: Vector3, right: Vector3, side: float, mag: float) -> Vector3:
	if not _target_on_road:
		return base + right * mag * side
	if _now < _aim_cache_until and _aim_cache_side == side:
		return base + _aim_cache_off
	var chosen := Vector3.ZERO
	var found := false
	for m in [mag, mag * 0.55]:
		for s in [side, -side]:
			var off: Vector3 = right * float(m) * float(s)
			# the point and a 1.3 m margin beyond it (the car body is 1.9 m wide) must both be road surface
			if _on_asphalt(base + off) and _on_asphalt(base + off + right * float(s) * 1.3):
				chosen = off
				found = true
				break
		if found:
			break
	_aim_cache_off = chosen
	_aim_cache_side = side
	_aim_cache_until = _now + 0.3
	return base + chosen


func _clear_to(p: Vector3) -> bool:
	var from := car.global_position + Vector3(0, 0.8, 0)
	_q.from = from
	_q.to = Vector3(p.x, from.y, p.z)
	var saved := _q.collision_mask
	_q.collision_mask = GC.L_WORLD
	var hit := car.get_world_3d().direct_space_state.intersect_ray(_q)
	_q.collision_mask = saved
	return hit.is_empty()


func _try_pit(tpos: Vector3, tbasis: Basis, tvel: Vector3) -> bool:
	var tf := Transform3D(tbasis, tpos)
	var rel := tf.affine_inverse() * car.global_position
	# behind the target's centre (z > 0 in its local frame = toward its rear) and beside its rear quarter
	if rel.z < 0.5 or rel.z > 4.8 or absf(rel.x) < 1.1 or absf(rel.x) > 3.4:
		return false
	var closing := car.linear_velocity.dot(tvel.normalized()) - tvel.length() if tvel.length() > 0.5 else 0.0
	if absf(closing) > 9.0:
		return false
	_pit_side = -signf(rel.x)                # steer toward the target
	_pit_until = _now + 0.7
	_pit_cd = PIT_COOLDOWN + randf() * 2.0
	pit_attempts += 1
	return true


func _box_in(dt: float, tpos: Vector3, tvel: Vector3, tbasis: Basis, dist: float, v: float) -> void:
	var fwd_t := -tbasis.z
	fwd_t.y = 0.0
	fwd_t = fwd_t.normalized() if fwd_t.length() > 0.1 else Vector3(0, 0, -1)
	var right_t := Vector3(-fwd_t.z, 0.0, fwd_t.x)
	var slot := Vector3.ZERO
	match _rank % 3:
		0:
			slot = tpos - fwd_t * 6.2
		1:
			slot = tpos + fwd_t * 7.4
		_:
			slot = tpos + right_t * 3.6 * (1.0 if (car.get_instance_id() % 2 == 0) else -1.0) - fwd_t * 0.5
	slot += tvel * 0.4
	var d_slot := Util.dist_xz(slot, car.global_position)
	if d_slot < 1.6 and absf(v) < 2.5:
		_hold_brake(dt, 0.9)
		_hold_still = true
		return
	_drive_to(slot, clampf(d_slot * 0.6, 1.5, 10.0), dt)


func _pursue_deployed(dt: float, t_in_car: bool, tspeed: float, dist: float) -> void:
	_hold_brake(dt, 0.9)
	_hold_still = true
	# collect the officers again once the target is on the move
	var moving_away := (t_in_car and tspeed > 5.0) or dist > 55.0
	if moving_away:
		_deploy_t += dt
		if car.driver != null and car.driver is PoliceOfficer:
			deployed = false
			_deploy_t = 0.0
			return
		# officers re-enter by themselves (they run for their home vehicle); wait for the driver
		if _deploy_t > 14.0:
			deployed = false
			_deploy_t = 0.0
	else:
		_deploy_t = 0.0


## Exits every seated officer (doors open) and hands them the pursuit order.
func _deploy() -> void:
	deployed = true
	deploys += 1
	var occupants: Array = car.get_occupants()
	for c in occupants:
		if c is PoliceOfficer:
			var o: PoliceOfficer = c
			car.exit(o, false)
			var od := order.duplicate()
			od["mode"] = &"pursue"
			if target != null:
				od["target"] = target
			o.set_order(od)
	# keep the AI alive without a driver: it simply holds the brake until an officer sits down again
