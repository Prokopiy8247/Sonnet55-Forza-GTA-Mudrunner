class_name LaneGraph
extends RefCounted
## Directed lane-point graph used by civilian traffic, police driving and the taxi service.
## Built once by the World agent (WorldLayout.lanes); consumers only call the query API below.
## A lane point is a position on the centre of a lane with a forward tangent; `next` lists successor points
## (several successors = intersection choices). Lane points are spaced ~6-10 m along roads.

const KIND_STRAIGHT := 0
const KIND_CONNECTOR := 1      # turn path inside an intersection
const KIND_HIGHWAY := 2

var positions := PackedVector3Array()
var dirs := PackedVector3Array()               # unit forward tangent
var speed_limit := PackedFloat32Array()        # m/s
var road_id := PackedInt32Array()
var kind := PackedByteArray()
## >= 0 when vehicles must stop at this point while the signal is red (a stop line); -1 otherwise.
var signal_id := PackedInt32Array()
## Which signal phase (0 or 1) lets traffic through at this stop line.
var signal_phase := PackedInt32Array()
var next: Array = []                           # Array[PackedInt32Array]
var prev: Array = []                           # Array[PackedInt32Array]
## Same-direction neighbouring lane point on the left / right (for lane changes), -1 if none.
var left_of := PackedInt32Array()
var right_of := PackedInt32Array()

var _cell := 24.0
var _grid: Dictionary = {}


func size() -> int:
	return positions.size()


func add_point(pos: Vector3, dir: Vector3, speed_ms: float, road: int = -1, point_kind: int = KIND_STRAIGHT) -> int:
	positions.append(pos)
	dirs.append(dir.normalized())
	speed_limit.append(speed_ms)
	road_id.append(road)
	kind.append(point_kind)
	signal_id.append(-1)
	signal_phase.append(0)
	next.append(PackedInt32Array())
	prev.append(PackedInt32Array())
	left_of.append(-1)
	right_of.append(-1)
	return positions.size() - 1


func link(from_i: int, to_i: int) -> void:
	var n: PackedInt32Array = next[from_i]
	if not n.has(to_i):
		n.append(to_i)
		next[from_i] = n
	var p: PackedInt32Array = prev[to_i]
	if not p.has(from_i):
		p.append(from_i)
		prev[to_i] = p


func set_stop_line(i: int, sig: int, phase: int) -> void:
	signal_id[i] = sig
	signal_phase[i] = phase


## Call once after the graph is complete.
func build_index() -> void:
	_grid.clear()
	for i in positions.size():
		var key := _key(positions[i])
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		var arr: PackedInt32Array = _grid[key]
		arr.append(i)
		_grid[key] = arr


func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / _cell)), int(floor(p.z / _cell)))


func points_in_radius(pos: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius
	var c := _key(pos)
	var span := int(ceil(radius / _cell))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var arr: PackedInt32Array = _grid.get(Vector2i(c.x + dx, c.y + dz), PackedInt32Array())
			for i in arr:
				var d := positions[i] - pos
				if d.x * d.x + d.z * d.z <= r2:
					out.append(i)
	return out


## Nearest lane point to `pos`; with dir_hint != ZERO only points whose tangent agrees (dot > 0.3).
func nearest(pos: Vector3, dir_hint: Vector3 = Vector3.ZERO, max_dist: float = 30.0) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in points_in_radius(pos, max_dist):
		if dir_hint != Vector3.ZERO and dirs[i].dot(dir_hint) < 0.3:
			continue
		var d := positions[i] - pos
		var d2 := d.x * d.x + d.z * d.z
		if d2 < best_d:
			best_d = d2
			best = i
	return best


## Random lane point with a successor, between rmin and rmax from `center` (XZ), or -1.
func random_point_in_ring(center: Vector3, rmin: float, rmax: float, rng: RandomNumberGenerator, tries: int = 24) -> int:
	for t in tries:
		var cand := Util.rand_in_ring(center, rmin, rmax, rng)
		var idx := nearest(cand, Vector3.ZERO, 20.0)
		if idx >= 0 and kind[idx] != KIND_CONNECTOR and (next[idx] as PackedInt32Array).size() > 0:
			var d := Util.dist_xz(positions[idx], center)
			if d >= rmin and d <= rmax:
				return idx
	return -1
