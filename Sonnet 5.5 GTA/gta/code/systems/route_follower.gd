class_name RouteFollower
extends RefCounted
## Drives ONE VehicleBase along a RoutePlanner route with the TrafficDriver brain (lane following, signals, junction reservations, leader
## following, pedestrians) but WITHOUT the TrafficManager owning it: this object ticks the brain itself, so the TrafficManager's recycling
## (distance / stuck / unseen) never touches emergency vehicles. (Used by EmergencySystem; the taxi service has its own `RouteDriver`.)
##
##   var rf := RouteFollower.create(vehicle, npc, route, goals, speed_factor)    # null when the traffic module is missing
##   rf.tick(dt)                                                   # every physics frame
##   rf.state: DRIVING | PULLING_OVER | STOPPED | LOST             rf.remaining() -> metres of route left
##   rf.assign_route(new_route, goals) / rf.wander() / rf.stop_here() / rf.teleport_to_end() / rf.release()
## Lane changes of the brain are disabled so the car keeps the lane the route was planned in; if the brain replans (crash recovery,
## reverse manoeuvre) the route is re-planned from where the car is.

enum { DRIVING, PULLING_OVER, STOPPED, LOST }

const FEED_AHEAD := 36
const PULL_TRIGGER_M := 11.0
const APPROACH_M := 80.0
const PULL_LAT := 0.75
const RESCUE_AFTER_S := 40.0

static var _uid_seq := 2000000

var v: VehicleBase = null
var npc: Node = null
var drv: TrafficDriver = null
var state: int = DRIVING
var route := PackedInt32Array()
var cum := PackedFloat32Array()
var goals := PackedInt32Array()
var route_pos: Dictionary = {}
var total_len := 0.0
var pull_over_at_end := true
var wandering := false
var base_spd_factor := 1.0
var reroutes := 0
var stuck_t := 0.0
var rescues := 0
var approach_slowdown := true
var _pull_lat := 0.0
var _reroute_cd := 0.0
var _mgr = null


static func create(vehicle: VehicleBase, driver_npc: Node, new_route: PackedInt32Array, goal_list: PackedInt32Array, speed_factor: float = 1.0) -> RouteFollower:
	var mgr = Game.sys(&"traffic")
	if mgr == null or vehicle == null or new_route.size() < 3:
		return null
	if mgr.get("grid") == null or mgr.get("junction") == null:
		return null
	if not TrafficNet.ensure():
		return null
	var rf := RouteFollower.new()
	rf._mgr = mgr
	rf.v = vehicle
	rf.npc = driver_npc
	var d := TrafficDriver.new()
	_uid_seq += 1
	d.uid = _uid_seq
	d.stagger = d.uid % 6
	d.npc = driver_npc if (driver_npc != null and is_instance_valid(driver_npc)) else null
	d.setup(vehicle, new_route[0], mgr.rng, mgr.grid, mgr.junction, mgr.clock)
	d.last_update = mgr.clock
	d.tier = 0
	rf.drv = d
	rf.base_spd_factor = clampf(d.spd_factor * speed_factor, 0.8, 1.7)
	d.spd_factor = rf.base_spd_factor
	rf.assign_route(new_route, goal_list)
	return rf


func is_valid() -> bool:
	return drv != null and v != null and is_instance_valid(v) and state != LOST


## Replaces the route; the car continues from where it is (the route must start at / near the car).
func assign_route(new_route: PackedInt32Array, goal_list: PackedInt32Array) -> void:
	route = new_route
	goals = goal_list
	route_pos.clear()
	for k in route.size():
		route_pos[route[k]] = k
	cum = RoutePlanner.cumulative(route)
	total_len = cum[cum.size() - 1] if cum.size() > 0 else 0.0
	wandering = false
	if state == STOPPED or state == PULLING_OVER:
		_leave_pull_over()
	state = DRIVING
	if drv != null and not route.is_empty():
		drv.P = route.slice(0, mini(route.size(), FEED_AHEAD))
		drv.seg = 0
		drv.mode = TrafficDriver.MODE_DRIVE
		drv.want_recycle = false
		drv.idle_t = 0.0
		drv.spd_factor = base_spd_factor


## Free driving: random turns like ordinary traffic (drive-off after the job).
func wander() -> void:
	wandering = true
	route = PackedInt32Array()
	route_pos.clear()
	pull_over_at_end = false
	if state == STOPPED or state == PULLING_OVER:
		_leave_pull_over()
	state = DRIVING
	if drv != null and v != null and is_instance_valid(v):
		drv.spd_factor = base_spd_factor
		drv.mode = TrafficDriver.MODE_DRIVE
		drv.replan(v.global_position, -v.global_transform.basis.z)


## Metres of route left (measured from the lane point the car is currently heading to).
func remaining() -> float:
	if drv == null or route.is_empty():
		return INF
	var P := drv.P
	var s := drv.seg
	if s < 0 or s >= P.size():
		return INF
	var ri: int = route_pos.get(P[s], -1)
	if ri < 0:
		return INF
	return maxf(total_len - cum[ri], 0.0)


func progress_ratio() -> float:
	var r := remaining()
	if r == INF or total_len <= 0.0:
		return 0.0
	return clampf(1.0 - r / total_len, 0.0, 1.0)


func is_stopped() -> bool:
	return state == STOPPED


## Pull over at the next chance.
func stop_here() -> void:
	if state == DRIVING:
		_begin_pull_over()


func tick(dt: float) -> void:
	if drv == null or state == LOST:
		return
	if v == null or not is_instance_valid(v) or not v.is_inside_tree() or v.is_destroyed:
		state = LOST
		return
	if drv.mode == TrafficDriver.MODE_DEAD:
		state = LOST
		return
	var mgr = _mgr if is_instance_valid(_mgr) else Game.sys(&"traffic")
	if mgr == null:
		return
	_reroute_cd = maxf(_reroute_cd - dt, 0.0)
	var spd := v.get_speed()
	if state == STOPPED:
		v.input_throttle = 0.0
		v.input_brake = 0.0
		v.input_steer = 0.0
		v.input_handbrake = true
		drv._tick_lights(dt)
		return
	drv.lc_cool = 1.0e9                                   # no lane changes: the route is lane-specific
	if not wandering and not route.is_empty():
		_follow_route(dt, spd)
	if state == PULLING_OVER:
		_pull_lat = move_toward(_pull_lat, PULL_LAT, 0.8 * dt)
		drv.lat_off = minf(drv.lat_off, _pull_lat)
		if spd < 0.35:
			_enter_stopped()
			return
	# stuck handling: the brain reverses / replans by itself; if the car is jammed for a long time hop it ahead (unseen)
	if spd < 0.4 and state == DRIVING and drv.mode == TrafficDriver.MODE_DRIVE and drv.stop_reason != TrafficDriver.R_SIGNAL:
		stuck_t += dt
		if stuck_t > RESCUE_AFTER_S:
			stuck_t = 0.0
			_rescue()
	else:
		stuck_t = maxf(stuck_t - dt * 2.0, 0.0)
	var ddt: float = mgr.clock - drv.last_update
	drv.last_update = mgr.clock
	drv.update(ddt, mgr.clock)
	if drv.mode == TrafficDriver.MODE_DEAD:
		state = LOST


func _follow_route(_dt: float, _spd: float) -> void:
	var P := drv.P
	var seg := drv.seg
	if seg >= P.size():
		return
	var head: int = P[seg]
	var ri: int = route_pos.get(head, -1)
	if ri < 0:
		_reroute(head)                          # the brain re-planned (crash recovery, pushed off the road)
		return
	var guard := 0
	while P.size() - seg < FEED_AHEAD and guard < 64:
		var last: int = P[P.size() - 1]
		var li: int = route_pos.get(last, -1)
		if li < 0 or li >= route.size() - 1:
			break
		P.append(route[li + 1])
		guard += 1
	if guard > 0:
		drv.P = P
	if pull_over_at_end and state == DRIVING:
		var rem := maxf(total_len - cum[ri], 0.0)
		if approach_slowdown:
			drv.spd_factor = base_spd_factor * clampf(rem / APPROACH_M, 0.3, 1.0)
		if rem <= PULL_TRIGGER_M or (ri >= route.size() - 2):
			_begin_pull_over()


func _reroute(from_idx: int) -> void:
	if _reroute_cd > 0.0 or goals.is_empty():
		return
	_reroute_cd = 1.5
	reroutes += 1
	if reroutes > 12:
		wander()
		return
	var starts := PackedInt32Array([from_idx])
	var nr := RoutePlanner.plan(starts, goals)
	if nr.size() < 3:
		var g := RoutePlanner.graph()
		if g != null:
			if g.left_of[from_idx] >= 0:
				starts.append(g.left_of[from_idx])
			if g.right_of[from_idx] >= 0:
				starts.append(g.right_of[from_idx])
			nr = RoutePlanner.plan(starts, goals)
	if nr.size() >= 3:
		var keep_state := state
		assign_route(nr, goals)
		if keep_state == PULLING_OVER:
			_begin_pull_over()


func _begin_pull_over() -> void:
	if state != DRIVING:
		return
	state = PULLING_OVER
	_pull_lat = maxf(drv.lat_off, 0.0)
	drv.begin_breakdown(60.0)


func _leave_pull_over() -> void:
	if drv == null:
		return
	drv.breakdown_t = 0.0
	drv.set_hazard(false)
	_pull_lat = 0.0
	if v != null and is_instance_valid(v):
		v.input_handbrake = false


func _enter_stopped() -> void:
	state = STOPPED
	drv.thr = 0.0
	drv.brk = 0.0
	v.input_throttle = 0.0
	v.input_brake = 0.0
	v.input_handbrake = true
	v.input_steer = 0.0


## Jam breaker: hop the car some metres further along the route when nobody can see it, else keep waiting.
func _rescue() -> void:
	rescues += 1
	if route.is_empty() or drv.P.size() <= drv.seg:
		return
	var ri: int = route_pos.get(drv.P[drv.seg], -1)
	if ri < 0:
		return
	var g := RoutePlanner.graph()
	if g == null:
		return
	var target_i := mini(ri + 6, route.size() - 1)
	var pos: Vector3 = g.positions[route[target_i]]
	var tm = _mgr
	if tm != null and tm.has_method("is_seen") and tm.is_seen(pos):
		return
	var dir: Vector3 = g.dirs[route[target_i]]
	v.place_at(Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), pos + Vector3(0, 0.5, 0)))
	v.set_velocity(Vector3.ZERO)
	drv.P = route.slice(target_i, mini(route.size(), target_i + FEED_AHEAD))
	drv.seg = 0
	drv.mode = TrafficDriver.MODE_DRIVE
	drv.idle_t = 0.0


## Fast-forward: puts the car at the end of the route (stopped, hazards on).
func teleport_to_end() -> void:
	if route.is_empty() or v == null or not is_instance_valid(v):
		return
	var g := RoutePlanner.graph()
	if g == null:
		return
	var last_i := route[route.size() - 1]
	var dir: Vector3 = g.dirs[last_i]
	var right := Vector3(-dir.z, 0.0, dir.x)
	var pos: Vector3 = g.positions[last_i] + right * 0.7
	v.place_at(Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), pos + Vector3(0, 0.4, 0)))
	v.set_velocity(Vector3.ZERO)
	if drv != null:
		drv.breakdown_t = 60.0
		drv.set_hazard(true)
		drv.P = PackedInt32Array([last_i])
		drv.seg = 0
	state = PULLING_OVER
	_enter_stopped()


func set_hazard(on: bool) -> void:
	if drv != null:
		drv.set_hazard(on)


func honk(seconds: float = 0.4) -> void:
	if drv != null:
		drv.honk_now(seconds)


## Gives the car back: AI off, controls neutral. The brain is retired (junction reservations released).
func release() -> void:
	if drv != null:
		drv.release_control()
	state = LOST
