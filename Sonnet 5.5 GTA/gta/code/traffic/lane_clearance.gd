class_name LaneClearance
extends RefCounted
## Lazy, cached "can a car actually drive here?" test for lane points. The lane graph is pure data: the world sometimes puts a lamp or
## signal pole at the edge (or even the middle) of a lane. For every lane point a car-sized box (2.0 m wide, 0.5 m tall, floating 0.5 m
## above the road so kerbs and asphalt never count) is tested against the static world (layer WORLD):
##   FREE (1)    nothing in the way
##   DODGE (2)   blocked on the lane centre but free after shifting the track sideways (dodge[i] metres, + = right)
##   BLOCKED (3) no free track within +-0.9 m  -> drivers treat it as a solid obstacle, route planning avoids it
## Results are computed the first time a driver looks at a point (a few shape queries) and cached for everybody.

const UNKNOWN := 0
const FREE := 1
const DODGE := 2
const BLOCKED := 3
const OFFSETS: Array[float] = [0.0, -0.45, 0.45, -0.9, 0.9]

static var state := PackedByteArray()
static var dodge := PackedFloat32Array()
static var checked := 0
static var blocked_count := 0
static var dodge_count := 0
static var _box: BoxShape3D = null
static var _q: PhysicsShapeQueryParameters3D = null
static var _graph: LaneGraph = null


static func _ensure() -> void:
	var g: LaneGraph = WorldLayout.lanes
	if _graph != g or state.size() != g.size():
		_graph = g
		state = PackedByteArray()
		state.resize(g.size())
		dodge = PackedFloat32Array()
		dodge.resize(g.size())
		checked = 0
		blocked_count = 0
		dodge_count = 0
	if _box == null:
		_box = BoxShape3D.new()
		_q = PhysicsShapeQueryParameters3D.new()
		_q.collision_mask = GC.L_WORLD
		_q.shape = _box


static func get_state(idx: int) -> int:
	if state.size() != WorldLayout.lanes.size():
		_ensure()
	var s: int = state[idx]
	if s != UNKNOWN:
		return s
	return _compute(idx)


static func get_dodge(idx: int) -> float:
	return dodge[idx] if idx < dodge.size() else 0.0


static func _compute(idx: int) -> int:
	_ensure()
	if Game.world == null or not (Game.world is Node3D) or not (Game.world as Node3D).is_inside_tree():
		return FREE
	var g: LaneGraph = _graph
	var p: Vector3 = g.positions[idx]
	var d: Vector3 = g.dirs[idx]
	checked += 1
	# hill road (cut into the terrain, banks very close to the lane): not tested
	if WorldLayout.district_at(p.x, p.z) == GC.D_PARK and p.y > 3.0:
		state[idx] = FREE
		return FREE
	var space := (Game.world as Node3D).get_world_3d().direct_space_state
	var is_conn: bool = g.kind[idx] == LaneGraph.KIND_CONNECTOR
	_box.size = Vector3(2.0, 0.5, 3.8 if is_conn else 7.4)
	var fwd := Vector3(d.x, 0.0, d.z)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	for o in OFFSETS:
		_q.transform = Transform3D(basis, p + right * o + Vector3(0.0, 0.75, 0.0))
		if space.intersect_shape(_q, 1).is_empty():
			if o == 0.0:
				state[idx] = FREE
				return FREE
			state[idx] = DODGE
			dodge[idx] = o
			dodge_count += 1
			return DODGE
	state[idx] = BLOCKED
	blocked_count += 1
	return BLOCKED


## True when a connector chain can be driven (none of its points is BLOCKED). Checks the chain lazily.
static func chain_passable(chain_pts: PackedInt32Array) -> bool:
	for pt in chain_pts:
		if get_state(pt) == BLOCKED:
			return false
	return true
