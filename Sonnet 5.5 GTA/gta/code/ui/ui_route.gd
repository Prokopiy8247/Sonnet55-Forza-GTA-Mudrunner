class_name UIRoute
extends RefCounted
## GPS route along the directed lane graph (WorldLayout.lanes): A* over lane points. Returns world-space points
## (Y from the lane graph) from `from` to `to`. Falls back to a straight line (approx = true) when there is no lane
## graph yet or no path exists. Cheap enough to call on waypoint changes and every few seconds while driving.

const MAX_EXPANSIONS := 30000

var points := PackedVector3Array()
var approx := true
var length := 0.0


static func find(from: Vector3, to: Vector3) -> UIRoute:
	var r := UIRoute.new()
	var g: LaneGraph = WorldLayout.lanes
	if g == null or g.size() < 2:
		r._straight(from, to)
		return r
	var s := g.nearest(from, Vector3.ZERO, 70.0)
	var t := g.nearest(to, Vector3.ZERO, 90.0)
	if s < 0 or t < 0:
		r._straight(from, to)
		return r
	# A*
	var n := g.size()
	var gscore := PackedFloat32Array()
	gscore.resize(n)
	gscore.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap_f := PackedFloat32Array()
	var heap_n := PackedInt32Array()
	gscore[s] = 0.0
	_push(heap_f, heap_n, _h(g, s, t), s)
	var expansions := 0
	var found := false
	while heap_n.size() > 0 and expansions < MAX_EXPANSIONS:
		var cur := _pop(heap_f, heap_n)
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		expansions += 1
		if cur == t:
			found = true
			break
		for nx in (g.next[cur] as PackedInt32Array):
			if closed[nx] == 1:
				continue
			var step := g.positions[cur].distance_to(g.positions[nx])
			var ng := gscore[cur] + step
			if ng < gscore[nx]:
				gscore[nx] = ng
				came[nx] = cur
				_push(heap_f, heap_n, ng + _h(g, nx, t), nx)
	if not found:
		r._straight(from, to)
		return r
	var path: Array[int] = []
	var c := t
	while c != -1:
		path.append(c)
		c = came[c]
	path.reverse()
	r.points.append(from)
	for i in path:
		r.points.append(g.positions[i])
	r.points.append(to)
	r.approx = false
	r._measure()
	return r


func _straight(a: Vector3, b: Vector3) -> void:
	points = PackedVector3Array([a, b])
	approx = true
	_measure()


func _measure() -> void:
	length = 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])


static func _h(g: LaneGraph, a: int, b: int) -> float:
	return g.positions[a].distance_to(g.positions[b])


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
	var sz := last
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < sz and hf[l] < hf[m]:
			m = l
		if r < sz and hf[r] < hf[m]:
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
