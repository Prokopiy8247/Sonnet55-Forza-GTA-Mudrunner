class_name TrafficGrid
extends RefCounted
## Spatial registry of everything a driver must not hit: all vehicles (traffic, parked, player, police, ...) and pedestrians.
## Rebuilt by TrafficManager ~20-30 times per second into flat packed arrays + a hashed cell index (no per-entry objects).
## kinds: 0 = vehicle, 1 = pedestrian / player on foot.

const CELL := 20.0
const KIND_VEH := 0
const KIND_PED := 1

var count := 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var fwd := PackedVector3Array()          # unit heading (XZ)
var hl := PackedFloat32Array()           # half length
var hw := PackedFloat32Array()           # half width
var kind := PackedByteArray()
var moving_ai := PackedByteArray()       # 1 = driven by a TrafficDriver
var node: Array = []                     # VehicleBase or the pedestrian node
var sirens: Array = []                   # indices of vehicles with an active siren
var cells: Dictionary = {}
var _dims: Dictionary = {}               # def_id -> Vector2(half length, half width)


static func cell_key(cx: int, cz: int) -> int:
	return (cx + 2048) * 4096 + (cz + 2048)


func clear() -> void:
	count = 0
	node.clear()
	sirens.clear()
	cells.clear()


func _ensure_capacity(n: int) -> void:
	if pos.size() < n:
		var m := n + 32
		pos.resize(m)
		vel.resize(m)
		fwd.resize(m)
		hl.resize(m)
		hw.resize(m)
		kind.resize(m)
		moving_ai.resize(m)


func _dims_of(v: VehicleBase) -> Vector2:
	var id := v.def_id
	var d: Variant = _dims.get(id, null)
	if d == null:
		d = Vector2(float(v.def.get("length", 4.5)) * 0.5, float(v.def.get("width", 1.8)) * 0.5)
		_dims[id] = d
	return d


func add_vehicle(v: VehicleBase, is_ai: bool) -> int:
	var i := count
	_ensure_capacity(i + 1)
	count = i + 1
	var xf := v.global_transform
	var b := xf.basis
	var f := Vector3(-b.z.x, 0.0, -b.z.z)
	var fl := f.length()
	if fl > 0.001:
		f /= fl
	else:
		f = Vector3(0.0, 0.0, -1.0)
	var dims := _dims_of(v)
	pos[i] = xf.origin
	vel[i] = v.linear_velocity
	fwd[i] = f
	hl[i] = dims.x
	hw[i] = dims.y
	kind[i] = KIND_VEH
	moving_ai[i] = 1 if is_ai else 0
	node.append(v)
	if v.siren_on:
		sirens.append(i)
	_insert(i, xf.origin)
	return i


func add_ped(n: Node3D, velocity: Vector3) -> int:
	var i := count
	_ensure_capacity(i + 1)
	count = i + 1
	var p := n.global_position
	pos[i] = p
	vel[i] = velocity
	var f := Vector3(velocity.x, 0.0, velocity.z)
	fwd[i] = f.normalized() if f.length_squared() > 0.04 else Vector3(0.0, 0.0, -1.0)
	hl[i] = 0.4
	hw[i] = 0.4
	kind[i] = KIND_PED
	moving_ai[i] = 0
	node.append(n)
	_insert(i, p)
	return i


func _insert(i: int, p: Vector3) -> void:
	var key := cell_key(int(floorf(p.x / CELL)), int(floorf(p.z / CELL)))
	var arr: Variant = cells.get(key, null)
	if arr == null:
		cells[key] = [i]
	else:
		(arr as Array).append(i)


## Fills `out` with the entry indices whose cell touches the square [centre +- radius].
func query(centre: Vector3, radius: float, out: PackedInt32Array) -> void:
	out.clear()
	var x0 := int(floorf((centre.x - radius) / CELL))
	var x1 := int(floorf((centre.x + radius) / CELL))
	var z0 := int(floorf((centre.z - radius) / CELL))
	var z1 := int(floorf((centre.z + radius) / CELL))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var arr: Variant = cells.get(cell_key(cx, cz), null)
			if arr != null:
				for i in (arr as Array):
					out.append(i)
