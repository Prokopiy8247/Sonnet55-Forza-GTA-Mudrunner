class_name PedNav
extends RefCounted
## Navigation helpers for pedestrians on WorldLayout.ped_graph: nearest node, persistent random walks (sidewalk strolling),
## greedy flee steps (away from a threat along the graph), A* routes (goal driven walks), lane offsets (keep right) and soft
## avoidance of static street furniture (lamps, hydrants, benches...) from a coarse circle grid. All static, no per-ped state.

const OBST_CELL := 6.0
const OBST_RADIUS := {
	&"lamp": 0.34, &"signal": 0.42, &"hydrant": 0.30, &"bin": 0.38, &"bollard": 0.24, &"mailbox": 0.36, &"parking_meter": 0.22,
	&"utility_box": 0.58, &"tree_street": 0.45, &"palm": 0.42, &"billboard": 0.7, &"sign_stop": 0.16, &"sign_speed": 0.16,
	&"bench": 0.82, &"barrier": 0.5, &"cone": 0.25,
}

static var _obst: Dictionary = {}          # Vector2i -> PackedFloat32Array [x, z, r, ...]
static var _obst_for := -1
static var obstacle_count := 0
static var _y_fix: Dictionary = {}         # node index -> corrected walking height
static var _no_go: Dictionary = {}         # node index -> true (stunt ramps etc.: avoided by random walks and spawns)
static var heights_fixed := 0


# ---- graph queries ---------------------------------------------------------------------------------------------------
static func graph() -> PedGraph:
	return WorldLayout.ped_graph


static func nearest_node(pos: Vector3, max_dist: float = 30.0) -> int:
	return WorldLayout.ped_graph.nearest(pos, max_dist)


## Walkable position of a node (y corrected by fix_heights: pier nodes sit on the deck, not on the sea floor).
static func node_pos(i: int) -> Vector3:
	var p: Vector3 = WorldLayout.ped_graph.positions[i]
	if _y_fix.has(i):
		p.y = _y_fix[i]
	return p


static func node_y(i: int) -> float:
	if _y_fix.has(i):
		return _y_fix[i]
	return WorldLayout.ped_graph.positions[i].y


## Some graph points (pier / dock nodes over the water, a hill path next to the road) carry the terrain height instead of the walkable
## surface above it. Probes every node once against the static world and stores the corrected heights. Returns the number of nodes fixed.
static func fix_heights(space: PhysicsDirectSpaceState3D) -> int:
	_y_fix.clear()
	_no_go.clear()
	var pg := WorldLayout.ped_graph
	for i in pg.size():
		var p: Vector3 = pg.positions[i]
		# pier nodes sit on the sea floor (up to -9 m): the deck is far above them, so their ray starts higher (the deck is < 3 m high)
		var dock: bool = pg.zone[i] == PedGraph.ZONE_DOCK
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 14.0 if dock else 5.0, 0.0), p + Vector3(0.0, -6.0, 0.0), GC.M_GROUND)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var top: float = (hit["position"] as Vector3).y
		if dock and top > 3.0:
			continue
		if top - p.y > 0.12:
			_y_fix[i] = top + 0.02
		# a stunt ramp / launch pad lies across the path: strollers do not walk onto it
		var col = hit["collider"]
		if col != null and String((col as Node).name).begins_with("Ramp"):
			_no_go[i] = true
	# dock points over open water without any deck (gaps / ends of a pier): nobody walks there, and if one ever does it stays at deck level
	for i in pg.size():
		if pg.zone[i] == PedGraph.ZONE_DOCK and node_y(i) < -0.6:
			_no_go[i] = true
			_y_fix[i] = 0.05
	heights_fixed = _y_fix.size()
	return heights_fixed


static func no_go(i: int) -> bool:
	return _no_go.has(i)


static func zone_of(i: int) -> int:
	return WorldLayout.ped_graph.zone[i]


static func neighbors(i: int) -> PackedInt32Array:
	return WorldLayout.ped_graph.links[i]


## Right-hand perpendicular (xz) of a forward vector: forward (0,0,-1) -> (1,0,0).
static func right_of(f: Vector3) -> Vector3:
	return Vector3(-f.z, 0.0, f.x)


## Next node of a persistent random walk: prefers going straight on, crossing a road is chosen with weight `cross_w`
## relative to continuing along the pavement, walking back only at dead ends. `fwd` = current xz heading (any length).
static func next_random(cur: int, prev: int, fwd: Vector3, rng: RandomNumberGenerator, cross_w: float = 0.35) -> int:
	var pg := WorldLayout.ped_graph
	var links: PackedInt32Array = pg.links[cur]
	if links.is_empty():
		return -1
	var here := pg.positions[cur]
	var f := Vector3(fwd.x, 0.0, fwd.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.ZERO
	var best := -1
	var total := 0.0
	var ws: Array[float] = []
	for n in links:
		if n == prev and links.size() > 1:
			ws.append(0.0)
			continue
		var d := pg.positions[n] - here
		d.y = 0.0
		var dn := d.normalized() if d.length() > 0.01 else f
		var w := 0.3 + 1.0 * maxf(f.dot(dn), 0.0)
		if pg.zone[n] == PedGraph.ZONE_CROSSING and pg.zone[cur] != PedGraph.ZONE_CROSSING:
			w *= cross_w
		elif _no_go.has(n):
			w *= 0.01
		elif pg.zone[n] == PedGraph.ZONE_INDOOR:
			w *= 0.1
		elif (pg.links[n] as PackedInt32Array).size() <= 1:
			w *= 0.5
		ws.append(w)
		total += w
	if total <= 0.0001:
		return prev if prev >= 0 else links[0]
	var t := rng.randf() * total
	for k in links.size():
		t -= ws[k]
		if t <= 0.0 and ws[k] > 0.0:
			best = links[k]
			break
	if best < 0:
		best = links[links.size() - 1]
	return best


## Greedy flee step: depth-3 lookahead for the neighbour sequence that ends farthest from the threat (xz). Never returns -1
## for a node that has links.
static func flee_next(cur: int, prev: int, threat: Vector3, rng: RandomNumberGenerator) -> int:
	var pg := WorldLayout.ped_graph
	var links: PackedInt32Array = pg.links[cur]
	if links.is_empty():
		return -1
	var best := -1
	var best_s := -INF
	for n in links:
		var s := _flee_score(n, cur, threat, 2, pg)
		if n == prev:
			s -= 28.0
		if pg.zone[n] == PedGraph.ZONE_INDOOR:
			s -= 40.0
		if _no_go.has(n):
			s -= 60.0
		s += rng.randf() * 3.0
		if s > best_s:
			best_s = s
			best = n
	return best


static func _flee_score(node: int, from_node: int, threat: Vector3, depth: int, pg: PedGraph) -> float:
	var p := pg.positions[node]
	var dx := p.x - threat.x
	var dz := p.z - threat.z
	var s := sqrt(dx * dx + dz * dz)
	if depth <= 0:
		return s
	var best := s
	for n in pg.links[node]:
		if n == from_node:
			continue
		best = maxf(best, _flee_score(n, node, threat, depth - 1, pg) * 0.97)
	return best


## A* over the ped graph. Returns node indices from `from` to `to` inclusive, empty when no path (or the search budget ran out).
static func find_path(from: int, to: int, max_expand: int = 450) -> PackedInt32Array:
	var out := PackedInt32Array()
	if from < 0 or to < 0:
		return out
	if from == to:
		out.append(from)
		return out
	var pg := WorldLayout.ped_graph
	var goal := pg.positions[to]
	var g: Dictionary = {from: 0.0}
	var came: Dictionary = {}
	var heap_f: Array[float] = []
	var heap_n: Array[int] = []
	_heap_push(heap_f, heap_n, 0.0, from)
	var closed: Dictionary = {}
	var expanded := 0
	while not heap_n.is_empty() and expanded < max_expand:
		var cur := _heap_pop(heap_f, heap_n)
		if closed.has(cur):
			continue
		closed[cur] = true
		expanded += 1
		if cur == to:
			var node := to
			out.append(node)
			while came.has(node):
				node = came[node]
				out.append(node)
			out.reverse()
			return out
		var pc := pg.positions[cur]
		for n in pg.links[cur]:
			if closed.has(n):
				continue
			var pn := pg.positions[n]
			var step := Vector2(pn.x - pc.x, pn.z - pc.z).length()
			if pg.zone[n] == PedGraph.ZONE_CROSSING and pg.zone[cur] != PedGraph.ZONE_CROSSING:
				step += 6.0       # prefer staying on the pavement
			var ng: float = float(g[cur]) + step
			if not g.has(n) or ng < float(g[n]):
				g[n] = ng
				came[n] = cur
				var h := Vector2(pn.x - goal.x, pn.z - goal.z).length()
				_heap_push(heap_f, heap_n, ng + h, n)
	return out


static func _heap_push(hf: Array[float], hn: Array[int], f: float, n: int) -> void:
	hf.append(f)
	hn.append(n)
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


static func _heap_pop(hf: Array[float], hn: Array[int]) -> int:
	var top := hn[0]
	var last := hf.size() - 1
	hf[0] = hf[last]
	hn[0] = hn[last]
	hf.resize(last)
	hn.resize(last)
	var i := 0
	var n := hf.size()
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < n and hf[l] < hf[m]:
			m = l
		if r < n and hf[r] < hf[m]:
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


## Length (m) of a node path.
static func path_length(path: PackedInt32Array) -> float:
	var pg := WorldLayout.ped_graph
	var d := 0.0
	for i in range(1, path.size()):
		var a := pg.positions[path[i - 1]]
		var b := pg.positions[path[i]]
		d += Vector2(b.x - a.x, b.z - a.z).length()
	return d


# ---- static obstacles --------------------------------------------------------------------------------------------------
static func ensure_obstacles() -> void:
	if _obst_for == WorldLayout.furniture.size() and not _obst.is_empty():
		return
	_obst.clear()
	obstacle_count = 0
	for f in WorldLayout.furniture:
		var kind: StringName = f.get("kind", &"")
		if not OBST_RADIUS.has(kind) and kind != &"bus_stop":
			continue
		var p: Vector3 = f["pos"]
		var yaw: float = float(f.get("yaw", 0.0))
		if kind == &"bus_stop":
			# shelter ~5 m wide along the facing's right axis
			var rx := Vector2(cos(yaw), -sin(yaw))
			_add_obstacle(Vector2(p.x, p.z), 0.95)
			_add_obstacle(Vector2(p.x, p.z) + rx * 1.7, 0.7)
			_add_obstacle(Vector2(p.x, p.z) - rx * 1.7, 0.7)
		elif kind == &"bench":
			var rx2 := Vector2(cos(yaw), -sin(yaw))
			_add_obstacle(Vector2(p.x, p.z) + rx2 * 0.45, 0.5)
			_add_obstacle(Vector2(p.x, p.z) - rx2 * 0.45, 0.5)
		else:
			_add_obstacle(Vector2(p.x, p.z), float(OBST_RADIUS[kind]))
	_obst_for = WorldLayout.furniture.size()


static func _add_obstacle(p: Vector2, r: float) -> void:
	var key := Vector2i(int(floor(p.x / OBST_CELL)), int(floor(p.y / OBST_CELL)))
	var arr: PackedFloat32Array = _obst.get(key, PackedFloat32Array())
	arr.append(p.x)
	arr.append(p.y)
	arr.append(r)
	_obst[key] = arr
	obstacle_count += 1


## Soft repulsion (xz, unit-ish) from static obstacles within `margin` of the body circle of radius 0.28 at (x, z).
static func avoid(x: float, z: float, margin: float = 0.55) -> Vector2:
	var cx := int(floor(x / OBST_CELL))
	var cz := int(floor(z / OBST_CELL))
	var out := Vector2.ZERO
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr: PackedFloat32Array = _obst.get(Vector2i(cx + dx, cz + dz), PackedFloat32Array())
			var n := arr.size()
			var i := 0
			while i < n:
				var ox := x - arr[i]
				var oz := z - arr[i + 1]
				var reach := arr[i + 2] + 0.28 + margin
				var d2 := ox * ox + oz * oz
				if d2 < reach * reach and d2 > 0.0001:
					var d := sqrt(d2)
					var k := (reach - d) / margin
					out += Vector2(ox, oz) / d * clampf(k, 0.0, 2.0)
				i += 3
	return out


## True when a circle of radius r at (x, z) overlaps a static obstacle (spawn checks).
static func blocked(x: float, z: float, r: float = 0.3) -> bool:
	var cx := int(floor(x / OBST_CELL))
	var cz := int(floor(z / OBST_CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr: PackedFloat32Array = _obst.get(Vector2i(cx + dx, cz + dz), PackedFloat32Array())
			var i := 0
			while i < arr.size():
				var ox := x - arr[i]
				var oz := z - arr[i + 1]
				var reach := arr[i + 2] + r
				if ox * ox + oz * oz < reach * reach:
					return true
				i += 3
	return false
