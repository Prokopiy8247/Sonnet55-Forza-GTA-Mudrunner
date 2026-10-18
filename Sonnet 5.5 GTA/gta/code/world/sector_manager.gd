class_name SectorManager
extends Node
## 100 m sector cells. `get_sector_parent(pos)` lazily creates a Node3D per cell ("S_<ix>_<iz>"); static world content (road meshes,
## buildings, props) is parented there so whole cells can be hidden when far from the focus (player / camera).
## Each sector may have a child "Dynamic" (get_dynamic_parent) whose process_mode is disabled while the sector is inactive -
## put per-frame nodes there, NOT static colliders (disabled bodies leave the physics space).
## Emits Events.sector_activated / sector_deactivated(sector_id: Vector2i).

const CELL := 100.0

## Sectors farther than this from the focus are hidden; hysteresis keeps them from flickering.
@export var show_radius := 430.0
@export var hide_radius := 470.0
@export var update_interval := 0.25

var sectors: Dictionary = {}          # Vector2i -> Node3D
var active: Dictionary = {}           # Vector2i -> bool
var root: Node3D
var focus_override: Node3D = null
var _acc := 0.0
var _last_focus := Vector3(1e9, 0, 1e9)


func setup(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Sectors"
	parent.add_child(root)
	set_process(true)


static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL)), int(floor(pos.z / CELL)))


static func cell_center(id: Vector2i) -> Vector3:
	return Vector3((id.x + 0.5) * CELL, 0.0, (id.y + 0.5) * CELL)


func get_sector_parent(pos: Vector3) -> Node3D:
	var id := cell_of(pos)
	var s: Node3D = sectors.get(id, null)
	if s == null or not is_instance_valid(s):
		s = Node3D.new()
		s.name = "S_%d_%d" % [id.x, id.y]
		s.set_meta("sector_id", id)
		root.add_child(s)
		sectors[id] = s
		active[id] = true
	return s


func get_dynamic_parent(pos: Vector3) -> Node3D:
	var s := get_sector_parent(pos)
	var d: Node3D = s.get_node_or_null("Dynamic") as Node3D
	if d == null:
		d = Node3D.new()
		d.name = "Dynamic"
		s.add_child(d)
		d.process_mode = Node.PROCESS_MODE_INHERIT if bool(active.get(cell_of(pos), true)) else Node.PROCESS_MODE_DISABLED
	return d


func is_active(pos: Vector3) -> bool:
	return bool(active.get(cell_of(pos), true))


func _process(delta: float) -> void:
	_acc += delta
	if _acc < update_interval:
		return
	_acc = 0.0
	var f := _focus_pos()
	if f.x > 1e8:
		return
	if f.distance_squared_to(_last_focus) < 1.0 and _last_focus.x < 1e8:
		return
	_last_focus = f
	update_focus(f)


func _focus_pos() -> Vector3:
	if is_instance_valid(focus_override):
		return focus_override.global_position
	var cam := Game.gameplay_camera
	if is_instance_valid(cam):
		return cam.global_position
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3(1e9, 0, 1e9)


## Distance from a point to the rectangle of a sector cell (XZ).
static func dist_to_cell(p: Vector3, id: Vector2i) -> float:
	var x0 := id.x * CELL
	var z0 := id.y * CELL
	var dx := maxf(maxf(x0 - p.x, p.x - (x0 + CELL)), 0.0)
	var dz := maxf(maxf(z0 - p.z, p.z - (z0 + CELL)), 0.0)
	return sqrt(dx * dx + dz * dz)


func update_focus(f: Vector3) -> void:
	for id in sectors:
		var s: Node3D = sectors[id]
		if not is_instance_valid(s):
			continue
		var d := dist_to_cell(f, id)
		var was: bool = active.get(id, true)
		var now := was
		if was and d > hide_radius:
			now = false
		elif not was and d < show_radius:
			now = true
		if now != was:
			active[id] = now
			s.visible = now
			var dyn := s.get_node_or_null("Dynamic")
			if dyn != null:
				dyn.process_mode = Node.PROCESS_MODE_INHERIT if now else Node.PROCESS_MODE_DISABLED
			if now:
				Events.sector_activated.emit(id)
			else:
				Events.sector_deactivated.emit(id)


func active_count() -> int:
	var n := 0
	for id in active:
		if active[id]:
			n += 1
	return n
