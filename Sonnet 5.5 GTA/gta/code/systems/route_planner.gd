class_name RoutePlanner
extends RefCounted
## Lane-graph routing for the Transit / Emergency services (and anybody who needs a drivable route).
##
## A* over WorldLayout.lanes following the directed successor links (junction connectors included), cost = travel TIME
## (segment length / speed limit) + a small penalty per junction crossing and per signalised stop line. Results are cached.
## Everything is static; the lane graph is read-only here.
##
##   var route := RoutePlanner.plan_positions(from_pos, to_pos)          # PackedInt32Array of lane point indices ([] = no route)
##   var pts   := RoutePlanner.get_route_points(from_pos, to_pos)        # PackedVector3Array (for a UI route line)
##   RoutePlanner.route_length(route) / route_time(route)
##   RoutePlanner.find_curb_stop(pos)                                    # lane point where a car can pull over near pos
##   RoutePlanner.find_spawn_point(goal_idx, 140.0, 260.0, seen_cb)      # lane point from which goal_idx is reachable, unseen
## Lane changes are not part of a route: a TrafficDriver following it keeps its lane (the planner tries several start lanes).

const MIN_SPEED := 3.0
const JUNCTION_PENALTY_S := 0.7
const SIGNAL_PENALTY_S := 3.0
const MAX_EXPANSIONS := 60000
const CACHE_MAX := 96
const V_MAX := 23.0                    # fastest lane in the graph (80 km/h = 22.2 m/s) for the A* heuristic

static var stats := {"plans": 0, "cache_hits": 0, "failed": 0, "expansions": 0}
static var _cache: Dictionary = {}
static var _cache_keys: Array = []
static var _graph_size := -1


static func graph() -> LaneGraph:
	var g: LaneGraph = WorldLayout.lanes
	if g == null or g.size() < 4:
		return null
	if g.size() != _graph_size:
		_graph_size = g.size()
		_cache.clear()
		_cache_keys.clear()
	return g


static func clear_cache() -> void:
	_cache.clear()
	_cache_keys.clear()


# =====================================================================================================================
# Lookup helpers
# =====================================================================================================================
## Nearest lane point (not a junction connector unless nothing else is near), optionally agreeing with a heading.
static func nearest_lane(pos: Vector3, dir_hint: Vector3 = Vector3.ZERO, max_dist: float = 40.0, allow_connector: bool = false) -> int:
	var g := graph()
	if g == null:
		return -1
	var best := -1
	var best_d := max_dist * max_dist
	for i in g.points_in_radius(pos, max_dist):
		if not allow_connector and g.kind[i] == LaneGraph.KIND_CONNECTOR:
			continue
		if dir_hint != Vector3.ZERO and g.dirs[i].dot(dir_hint) < 0.3:
			continue
		var d: Vector3 = g.positions[i] - pos
		var d2 := d.x * d.x + d.z * d.z
		if d2 < best_d:
			best_d = d2
			best = i
	if best < 0 and not allow_connector:
		return nearest_lane(pos, dir_hint, max_dist, true)
	return best


## Lane points within `radius` of pos (XZ), nearest first, at most `limit`. Connectors are excluded unless include_connectors.
static func lane_candidates(pos: Vector3, radius: float, limit: int = 12, include_connectors: bool = false, dir_hint: Vector3 = Vector3.ZERO) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g := graph()
	if g == null:
		return out
	var items: Array = []
	for i in g.points_in_radius(pos, radius):
		if not include_connectors and g.kind[i] == LaneGraph.KIND_CONNECTOR:
			continue
		if dir_hint != Vector3.ZERO and g.dirs[i].dot(dir_hint) < 0.3:
			continue
		if (g.next[i] as PackedInt32Array).is_empty():
			continue
		var d: Vector3 = g.positions[i] - pos
		items.append([d.x * d.x + d.z * d.z, i])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in mini(limit, items.size()):
		out.append(int(items[k][1]))
	return out


# =====================================================================================================================
# A*
# =====================================================================================================================
## Cheapest route (by travel time) from ANY start point to ANY goal point. Returns the lane indices start..goal, or an empty array.
static func plan(starts: PackedInt32Array, goals: PackedInt32Array) -> PackedInt32Array:
	var g := graph()
	if g == null or starts.is_empty() or goals.is_empty():
		return PackedInt32Array()
	var key := hash([starts, goals])
	if _cache.has(key):
		var ent: Dictionary = _cache[key]
		if ent["s"] == starts and ent["g"] == goals:
			stats["cache_hits"] += 1
			return ent["r"]
	stats["plans"] += 1
	var n := g.size()
	var gscore := PackedFloat32Array()
	gscore.resize(n)
	gscore.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var is_goal := PackedByteArray()
	is_goal.resize(n)
	var centroid := Vector3.ZERO
	for gi in goals:
		is_goal[gi] = 1
		centroid += g.positions[gi]
	centroid /= float(goals.size())
	var goal_r := 0.0
	for gi in goals:
		goal_r = maxf(goal_r, Util.dist_xz(g.positions[gi], centroid))
	var heap_f := PackedFloat32Array()
	var heap_n := PackedInt32Array()
	for si in starts:
		gscore[si] = 0.0
		_push(heap_f, heap_n, _h(g, si, centroid, goal_r), si)
	var expansions := 0
	var found := -1
	while heap_n.size() > 0 and expansions < MAX_EXPANSIONS:
		var cur := _pop(heap_f, heap_n)
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		expansions += 1
		if is_goal[cur] == 1:
			found = cur
			break
		var cp: Vector3 = g.positions[cur]
		var cl: float = g.speed_limit[cur]
		var ck: int = g.kind[cur]
		for nx in (g.next[cur] as PackedInt32Array):
			if closed[nx] == 1:
				continue
			if is_goal[nx] == 0 and LaneClearance.get_state(nx) == LaneClearance.BLOCKED:
				continue                         # a pole stands in the lane: traffic cannot pass, plan around it
			var np: Vector3 = g.positions[nx]
			var seg_len := Vector2(np.x - cp.x, np.z - cp.z).length()
			var lim := maxf(minf(cl, g.speed_limit[nx]), MIN_SPEED)
			var cost := seg_len / lim
			if g.kind[nx] == LaneGraph.KIND_CONNECTOR and ck != LaneGraph.KIND_CONNECTOR:
				cost += JUNCTION_PENALTY_S
			if g.signal_id[nx] >= 0:
				cost += SIGNAL_PENALTY_S
			var ng := gscore[cur] + cost
			if ng < gscore[nx]:
				gscore[nx] = ng
				came[nx] = cur
				_push(heap_f, heap_n, ng + _h(g, nx, centroid, goal_r), nx)
	stats["expansions"] += expansions
	var route := PackedInt32Array()
	if found >= 0:
		var c := found
		while c != -1:
			route.append(c)
			c = came[c]
		route.reverse()
	else:
		stats["failed"] += 1
	_cache[key] = {"s": starts, "g": goals, "r": route}
	_cache_keys.append(key)
	if _cache_keys.size() > CACHE_MAX:
		_cache.erase(_cache_keys.pop_front())
	return route


static func _h(g: LaneGraph, i: int, centroid: Vector3, goal_r: float) -> float:
	var p: Vector3 = g.positions[i]
	return maxf(Vector2(p.x - centroid.x, p.z - centroid.z).length() - goal_r, 0.0) / V_MAX


static func _push(hf: PackedFloat32Array, hn: PackedInt32Array, f: float, node: int) -> void:
	hf.append(f)
	hn.append(node)
	var i := hf.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hf[p] <= hf[i]:
			break
		var tf := hf[p]
		hf[p] = hf[i]
		hf[i] = tf
		var tn := hn[p]
		hn[p] = hn[i]
		hn[i] = tn
		i = p


static func _pop(hf: PackedFloat32Array, hn: PackedInt32Array) -> int:
	var top := hn[0]
	var last := hf.size() - 1
	hf[0] = hf[last]
	hn[0] = hn[last]
	hf.resize(last)
	hn.resize(last)
	var i := 0
	var size := last
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < size and hf[l] < hf[m]:
			m = l
		if r < size and hf[r] < hf[m]:
			m = r
		if m == i:
			break
		var tf := hf[m]
		hf[m] = hf[i]
		hf[i] = tf
		var tn := hn[m]
		hn[m] = hn[i]
		hn[i] = tn
		i = m
	return top


# =====================================================================================================================
# Position based API
# =====================================================================================================================
## Route between two world positions. `start_dir` (optional) restricts the start lanes to the heading of a vehicle.
static func plan_positions(from: Vector3, to: Vector3, start_dir: Vector3 = Vector3.ZERO) -> PackedInt32Array:
	var starts := lane_candidates(from, 14.0, 6, false, start_dir)
	if starts.is_empty():
		var s1 := nearest_lane(from, start_dir, 60.0)
		if s1 >= 0:
			starts.append(s1)
	var goals := lane_candidates(to, 16.0, 10, false)
	if goals.is_empty():
		var g1 := nearest_lane(to, Vector3.ZERO, 80.0)
		if g1 >= 0:
			goals.append(g1)
	return plan(starts, goals)


## World points of the route between two positions (starts at `from`, ends at `to`; straight line when no route exists).
static func get_route_points(from: Vector3, to: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var g := graph()
	var route := plan_positions(from, to)
	if g == null or route.is_empty():
		pts.append(from)
		pts.append(to)
		return pts
	pts.append(from)
	for i in route:
		pts.append(g.positions[i])
	pts.append(to)
	return pts


static func is_reachable(from: Vector3, to: Vector3) -> bool:
	return not plan_positions(from, to).is_empty()


static func route_length(route: PackedInt32Array) -> float:
	var g := graph()
	if g == null or route.size() < 2:
		return 0.0
	var total := 0.0
	for k in range(1, route.size()):
		total += Util.dist_xz(g.positions[route[k - 1]], g.positions[route[k]])
	return total


## Travel time estimate in seconds along the route at the lane speed limits.
static func route_time(route: PackedInt32Array) -> float:
	var g := graph()
	if g == null or route.size() < 2:
		return 0.0
	var t := 0.0
	for k in range(1, route.size()):
		var a := route[k - 1]
		var b := route[k]
		t += Util.dist_xz(g.positions[a], g.positions[b]) / maxf(minf(g.speed_limit[a], g.speed_limit[b]), MIN_SPEED)
	return t


## Cumulative distance table (cum[k] = metres from route[0] to route[k]).
static func cumulative(route: PackedInt32Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	var g := graph()
	cum.resize(route.size())
	if g == null or route.is_empty():
		return cum
	var total := 0.0
	cum[0] = 0.0
	for k in range(1, route.size()):
		total += Util.dist_xz(g.positions[route[k - 1]], g.positions[route[k]])
		cum[k] = total
	return cum


# =====================================================================================================================
# Stops and spawns
# =====================================================================================================================
## True when the lane point is a decent place to stop a car: a plain lane (no junction connector / stop line within the next ~25 m
## or the last ~7 m), outermost lane of its direction (curb on the right).
static func is_stoppable(i: int, strict: bool = true) -> bool:
	var g := graph()
	if g == null or i < 0:
		return false
	if g.kind[i] != LaneGraph.KIND_STRAIGHT:
		return false
	if strict and g.right_of[i] >= 0:
		return false
	if LaneClearance.get_state(i) != LaneClearance.FREE:
		return false
	var cur := i
	for step in 4:
		var nx: PackedInt32Array = g.next[cur]
		if nx.is_empty():
			return false
		cur = nx[0]
		if g.kind[cur] == LaneGraph.KIND_CONNECTOR or g.signal_id[cur] >= 0 or LaneClearance.get_state(cur) == LaneClearance.BLOCKED:
			return false
	var pr: PackedInt32Array = g.prev[i]
	for p in pr:
		if g.kind[p] == LaneGraph.KIND_CONNECTOR:
			return false
	return true


## Best lane point to pull over near a world position (nearest stoppable lane point; falls back to any plain lane).
## `dir_hint` (optional) prefers lanes driven in that direction.
static func find_curb_stop(pos: Vector3, max_dist: float = 70.0, dir_hint: Vector3 = Vector3.ZERO, strict: bool = true) -> int:
	var g := graph()
	if g == null:
		return -1
	var best := -1
	var best_score := INF
	var fallback := -1
	var fb_d := INF
	for i in g.points_in_radius(pos, max_dist):
		if g.kind[i] == LaneGraph.KIND_CONNECTOR:
			continue
		var d := Util.dist_xz(g.positions[i], pos)
		if d < fb_d:
			fb_d = d
			fallback = i
		if not is_stoppable(i, strict):
			continue
		var score := d
		if g.kind[i] == LaneGraph.KIND_HIGHWAY:
			score += 25.0
		if dir_hint != Vector3.ZERO and g.dirs[i].dot(dir_hint) < 0.0:
			score += 12.0
		if score < best_score:
			best_score = score
			best = i
	return best if best >= 0 else fallback


## Lane points (with their path distance) from which `goal` can be reached, found by walking the graph BACKWARDS from the goal.
## Returns {idx: metres}. Used to pick spawn points that are guaranteed to be connected.
static func reverse_reach(goal: int, max_m: float) -> Dictionary:
	var out: Dictionary = {}
	var g := graph()
	if g == null or goal < 0:
		return out
	out[goal] = 0.0
	var frontier: Array = [goal]
	var head := 0
	while head < frontier.size():
		var cur: int = frontier[head]
		head += 1
		var dcur: float = out[cur]
		for p in (g.prev[cur] as PackedInt32Array):
			var nd := dcur + Util.dist_xz(g.positions[p], g.positions[cur])
			if nd > max_m:
				continue
			if not out.has(p) or nd < float(out[p]):
				out[p] = nd
				frontier.append(p)
	return out


## Random spawn lane point whose route to `goal` is between min_m and max_m long, on a plain lane, for which `seen_cb(pos) -> bool`
## is false (nothing visible spawns in front of the player). -1 when nothing fits.
static func find_spawn_point(goal: int, min_m: float, max_m: float, seen_cb: Callable = Callable(), rng: RandomNumberGenerator = null) -> int:
	var g := graph()
	if g == null or goal < 0:
		return -1
	var reach := reverse_reach(goal, max_m)
	var cands: Array = []
	for k in reach:
		var d: float = reach[k]
		if d < min_m or d > max_m:
			continue
		if g.kind[k] != LaneGraph.KIND_STRAIGHT and g.kind[k] != LaneGraph.KIND_HIGHWAY:
			continue
		if (g.next[k] as PackedInt32Array).is_empty():
			continue
		cands.append(int(k))
	if cands.is_empty():
		return -1
	var r := rng if rng != null else Game.rng
	for attempt in 24:
		var idx: int = cands[r.randi() % cands.size()]
		if seen_cb.is_valid() and bool(seen_cb.call(g.positions[idx])):
			continue
		return idx
	return -1
