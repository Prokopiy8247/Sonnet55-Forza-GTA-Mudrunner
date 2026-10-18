class_name RouteDriver
extends TrafficDriver
## A TrafficDriver that follows a PLANNED route (RoutePlanner) and stops at its end (curb). Everything else (lane following, junction
## reservations, signals, leaders, pedestrians, sirens yield) is the normal traffic behaviour. Ticked by its owner (taxi / emergency
## services), not by TrafficManager: call update(dt, TrafficManager.clock) every physics frame.
##
##   var d := RouteDriver.new(); d.setup(vehicle, lane_idx, rng, tm.grid, tm.junction, tm.clock)
##   d.set_route(RoutePlanner.plan_positions(a, b))        # stops at the last lane point (d.arrived = true)
##   d.release_arrival()                                   # afterwards: wander like ordinary traffic

const TAIL := 16
const STOP_DECEL := 2.3

var hold := false                  # true: the path is exactly the planned one (no random extension)
var goal_lane := -1
var arrived := false
var pull_over := true
var route_count := 0


func _extend_path() -> void:
	if hold:
		return
	super._extend_path()


## Installs the route. Points behind the vehicle are dropped. `stop_at_end` = park at the last point.
func set_route(route: PackedInt32Array, stop_at_end: bool = true) -> bool:
	var G: LaneGraph = WorldLayout.lanes
	if route.size() < 2 or G == null or v == null or not is_instance_valid(v):
		return false
	var xf := v.global_transform
	var fwd := Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized()
	var p := PackedInt32Array()
	var skipping := true
	for k in route.size():
		var idx: int = route[k]
		if skipping and k < route.size() - 2:
			var rel: Vector3 = G.positions[idx] - xf.origin
			if rel.x * fwd.x + rel.z * fwd.z < 1.0:
				continue
		skipping = false
		p.append(idx)
	if p.size() < 2:
		p = route.slice(maxi(route.size() - 3, 0))
	var last: int = p[p.size() - 1]
	var cur := last
	for t in TAIL:
		var nx: PackedInt32Array = G.next[cur]
		if nx.is_empty():
			break
		cur = nx[0]
		p.append(cur)
	if jn_granted or jn_jid >= 0:
		junction.release(self)
	P = p
	seg = 0
	lat_off = 0.0
	hold = stop_at_end
	goal_lane = last if stop_at_end else -1
	arrived = false
	route_count += 1
	if mode == MODE_REVERSE or mode == MODE_CRASHED:
		mode = MODE_DRIVE
	idle_t = 0.0
	stuck_count = 0
	return true


## Re-plans along the route to the goal when pushed off the path (never leaves the planned route for a random walk).
func replan(p: Vector3, fwd: Vector3) -> bool:
	if hold and goal_lane >= 0:
		var starts := RoutePlanner.lane_candidates(p, 16.0, 6, false, fwd)
		var route := RoutePlanner.plan(starts, PackedInt32Array([goal_lane]))
		if route.size() >= 2 and set_route(route, true):
			return true
	var was := hold
	hold = false
	var ok := super.replan(p, fwd)
	hold = was
	return ok


## Path distance from the vehicle to the goal point (negative = already passed it).
func remaining() -> float:
	if goal_lane < 0 or v == null or not is_instance_valid(v):
		return 999.0
	var gk := P.find(goal_lane, maxi(seg - 1, 0))
	if gk >= 0:
		var k := gk - seg
		if k < 0:
			return -1.0
		if k <= m_ahead:
			return ad[k]
	return Util.dist_xz(v.global_position, _pos[goal_lane])


func update(dt: float, now_: float) -> void:
	if mode == MODE_DEAD or v == null or not is_instance_valid(v):
		super.update(dt, now_)
		return
	now = now_
	if arrived:
		_tick_lights(dt)
		v.input_throttle = 0.0
		v.input_brake = 0.0
		v.input_steer = 0.0
		v.input_handbrake = true
		return
	super.update(dt, now_)
	if mode != MODE_DRIVE or goal_lane < 0:
		return
	var rem := remaining()
	if rem > 60.0:
		return
	if pull_over and rem < 26.0:
		lat_off = move_toward(lat_off, 1.0, 2.0 * dt)
	var spd: float = v.get_forward_speed()
	var vt := sqrt(2.0 * STOP_DECEL * maxf(rem - 0.4, 0.0))
	if spd > vt + 0.5:
		v.input_throttle = 0.0
		v.input_brake = clampf((spd - vt) * 0.45 + 0.15, 0.0, 1.0) if spd > BRAKE_MIN_SPEED else 0.0
	elif spd < vt - 0.4:
		v.input_throttle = minf(v.input_throttle, 0.5)
	else:
		v.input_throttle = minf(v.input_throttle, 0.18)
		v.input_brake = 0.0
	if vt < 0.5 and spd < BRAKE_MIN_SPEED:
		v.input_throttle = 0.0
		v.input_brake = 0.0
	if (rem < 1.6 or rem < 0.0) and absf(spd) < 0.8:
		arrived = true
		set_hazard(true)


## Leave the planned route and drive on as ordinary traffic.
func release_arrival() -> void:
	arrived = false
	hold = false
	goal_lane = -1
	pull_over = false
	set_hazard(false)
	idle_t = 0.0
	if v != null and is_instance_valid(v):
		v.input_handbrake = false
		var xf := v.global_transform
		replan(xf.origin, Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized())


## Blocked for too long: jumps ~`metres` further along the planned path (the driver "finds a gap"). Returns false when the goal is that close.
func jump_ahead(metres: float = 28.0) -> bool:
	var G := RoutePlanner.graph()
	if G == null or v == null or not is_instance_valid(v):
		return false
	var k := seg
	var acc := 0.0
	while k < P.size() - 2 and acc < metres:
		if P[k + 1] == goal_lane:
			break
		acc += Util.dist_xz(G.positions[P[k]], G.positions[P[k + 1]])
		k += 1
	idle_t = 0.0
	stuck_count = 0
	if k <= seg + 1:
		return false
	var idx: int = P[k]
	if jn_granted or jn_jid >= 0:
		junction.release(self)
	v.place_at(Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(G.dirs[idx])), G.positions[idx] + Vector3(0.0, 0.3, 0.0)))
	v.set_velocity(G.dirs[idx] * 3.0)
	seg = k
	lat_off = 0.0
	mode = MODE_DRIVE
	return true
