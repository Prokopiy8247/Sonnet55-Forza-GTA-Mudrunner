class_name PedGraph
extends RefCounted
## Undirected walkable-point graph (sidewalks, crossings, park paths, plazas, beach, docks) used by
## pedestrian AI. Built once by the World agent (WorldLayout.ped_graph); consumers use the query API.

const ZONE_SIDEWALK := 0
const ZONE_CROSSING := 1
const ZONE_PARK := 2
const ZONE_PLAZA := 3
const ZONE_BEACH := 4
const ZONE_DOCK := 5
const ZONE_INDOOR := 6

var positions := PackedVector3Array()
var zone := PackedByteArray()
## For ZONE_CROSSING points: traffic signal id that governs it (-1 = uncontrolled), and which phase
## (0/1) of that signal makes traffic STOP (i.e. pedestrians may walk).
var signal_id := PackedInt32Array()
var walk_phase := PackedInt32Array()
var links: Array = []            # Array[PackedInt32Array], undirected adjacency

var _cell := 24.0
var _grid: Dictionary = {}


func size() -> int:
	return positions.size()


func add_point(pos: Vector3, point_zone: int = ZONE_SIDEWALK) -> int:
	positions.append(pos)
	zone.append(point_zone)
	signal_id.append(-1)
	walk_phase.append(0)
	links.append(PackedInt32Array())
	return positions.size() - 1


func connect_points(a: int, b: int) -> void:
	var la: PackedInt32Array = links[a]
	if not la.has(b):
		la.append(b)
		links[a] = la
	var lb: PackedInt32Array = links[b]
	if not lb.has(a):
		lb.append(a)
		links[b] = lb


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


func nearest(pos: Vector3, max_dist: float = 30.0) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in points_in_radius(pos, max_dist):
		var d := positions[i] - pos
		var d2 := d.x * d.x + d.z * d.z
		if d2 < best_d:
			best_d = d2
			best = i
	return best


func random_point_in_ring(center: Vector3, rmin: float, rmax: float, rng: RandomNumberGenerator, tries: int = 24) -> int:
	for t in tries:
		var cand := Util.rand_in_ring(center, rmin, rmax, rng)
		var idx := nearest(cand, 16.0)
		if idx >= 0 and (links[idx] as PackedInt32Array).size() > 0:
			var d := Util.dist_xz(positions[idx], center)
			if d >= rmin and d <= rmax:
				return idx
	return -1
