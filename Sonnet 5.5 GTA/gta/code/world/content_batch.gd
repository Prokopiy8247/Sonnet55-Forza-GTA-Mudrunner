class_name ContentBatch
extends RefCounted
## Collects every static instance of the world content and flushes it into MultiMeshInstance3D nodes per
## (100 m sector, mesh key) plus merged box / cylinder colliders per sector. Sector parents come from
## WorldRoot.get_sector_parent(pos) when it exists, else from an internal "CityContent" node.
##
## Instance custom data (all building / prop shaders): Color(x, y, z, w) - see the building_*.gdshader headers.

const CELL := 100.0
const HALF := 300.0

class Item extends RefCounted:
	var xf: Array[Transform3D] = []
	var cd := PackedFloat32Array()

class ColSpec extends RefCounted:
	var xf: Transform3D
	var size: Vector3
	var radius := 0.0     # > 0 -> cylinder (size.y = height)
	var shape: Shape3D = null   # explicit shape (trimesh / convex) overrides box / cylinder
	var surface: StringName = &"concrete"

var world: Node3D
var content_root: Node3D
var items: Dictionary = {}          # cell id (int) -> {key: Item}
var colliders: Dictionary = {}      # cell id -> Array[ColSpec]
var lod: Dictionary = {}            # key -> {begin, end, margin, shadow}
var default_lod := {"begin": 0.0, "end": 0.0, "margin": 8.0, "shadow": true}
var stats := {"instances": 0, "multimeshes": 0, "colliders": 0, "keys": {}}
var owned: Array[Node] = []         # every node this batch created under a sector (freed by CityBuilder.clear)
var built: Dictionary = {}          # "cell|key" -> MultiMesh (after flush)
var _sector_cache: Dictionary = {}  # cell id -> Node3D
var _inv_cache: Dictionary = {}     # cell id -> Transform3D (world -> parent local)
var _has_sector_api := false


func _init(world_node: Node3D) -> void:
	world = world_node
	_has_sector_api = world != null and world.has_method("get_sector_parent")
	content_root = Node3D.new()
	content_root.name = "CityContent"
	if world != null:
		world.add_child(content_root)


static func cell_id(p: Vector3) -> int:
	var cx := clampi(int(floor((p.x + HALF) / CELL)), 0, 5)
	var cz := clampi(int(floor((p.z + HALF) / CELL)), 0, 5)
	return cz * 6 + cx


static func cell_center(id: int) -> Vector3:
	var cx := id % 6
	var cz := id / 6
	return Vector3(-HALF + (cx + 0.5) * CELL, 0.0, -HALF + (cz + 0.5) * CELL)


## shadow: true / false, or 2 = shadows only (invisible in the main pass).
func set_lod(key: StringName, begin: float, end: float, margin := 12.0, shadow: Variant = true) -> void:
	lod[key] = {"begin": begin, "end": end, "margin": margin, "shadow": shadow}


## Returns the instance index inside its (sector, key) MultiMesh (needed to address one instance later, e.g. signals).
func add(key: StringName, xf: Transform3D, custom := Color(0, 0.5, 0.5, 0.5)) -> int:
	var id := cell_id(xf.origin)
	if not items.has(id):
		items[id] = {}
	var cell: Dictionary = items[id]
	var it: Item = cell.get(key) as Item
	if it == null:
		it = Item.new()
		cell[key] = it
	it.xf.append(xf)
	it.cd.append(custom.r)
	it.cd.append(custom.g)
	it.cd.append(custom.b)
	it.cd.append(custom.a)
	return it.xf.size() - 1


## MultiMesh created for (cell id, key) by flush() - null before flush / when the key was empty.
func get_multimesh(id: int, key: StringName) -> MultiMesh:
	return built.get("%d|%s" % [id, key]) as MultiMesh


func add_box_collider(xf: Transform3D, size: Vector3, surface: StringName = &"concrete") -> void:
	var c := ColSpec.new()
	c.xf = xf
	c.size = size
	c.surface = surface
	var id := cell_id(xf.origin)
	if not colliders.has(id):
		colliders[id] = []
	colliders[id].append(c)


func add_shape_collider(xf: Transform3D, shape: Shape3D, surface: StringName = &"concrete") -> void:
	var c := ColSpec.new()
	c.xf = xf
	c.shape = shape
	c.surface = surface
	var id := cell_id(xf.origin)
	if not colliders.has(id):
		colliders[id] = []
	colliders[id].append(c)


func add_cyl_collider(pos: Vector3, radius: float, height: float, surface: StringName = &"metal") -> void:
	var c := ColSpec.new()
	c.xf = Transform3D(Basis.IDENTITY, pos + Vector3(0, height * 0.5, 0))
	c.size = Vector3(radius * 2.0, height, radius * 2.0)
	c.radius = radius
	c.surface = surface
	var id := cell_id(pos)
	if not colliders.has(id):
		colliders[id] = []
	colliders[id].append(c)


func sector_parent(id: int) -> Node3D:
	if _sector_cache.has(id):
		return _sector_cache[id]
	var p: Node3D = null
	var center := cell_center(id)
	if _has_sector_api:
		p = world.call("get_sector_parent", center) as Node3D
	if p == null:
		p = Node3D.new()
		p.name = "Sector_%d" % id
		content_root.add_child(p)
	_sector_cache[id] = p
	var inv := Transform3D.IDENTITY
	if p.is_inside_tree():
		inv = p.global_transform.affine_inverse()
	else:
		var xf := Transform3D.IDENTITY
		var n: Node = p
		while n != null:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		inv = xf.affine_inverse()
	_inv_cache[id] = inv
	return p


func own(n: Node) -> void:
	owned.append(n)


## Parent for per-frame / physics nodes of a sector (WorldRoot.get_dynamic_parent when available).
func dynamic_parent(id: int) -> Node3D:
	if _has_sector_api and world.has_method("get_dynamic_parent"):
		var d := world.call("get_dynamic_parent", cell_center(id)) as Node3D
		if d != null:
			return d
	return sector_parent(id)


## Creates all MultiMeshInstance3D / collision nodes. mesh_of(key) -> Mesh (null skips the key).
func flush(mesh_of: Callable) -> void:
	for id in items:
		var parent := sector_parent(id)
		var inv: Transform3D = _inv_cache[id]
		var cell: Dictionary = items[id]
		for key in cell:
			var it: Item = cell[key]
			var mesh: Mesh = mesh_of.call(key)
			if mesh == null or it.xf.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh
			var n := it.xf.size()
			mm.instance_count = n
			for i in n:
				mm.set_instance_transform(i, inv * it.xf[i])
				mm.set_instance_custom_data(i, Color(it.cd[i * 4], it.cd[i * 4 + 1], it.cd[i * 4 + 2], it.cd[i * 4 + 3]))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "MM_" + String(key).replace(":", "_")
			mmi.multimesh = mm
			var l: Dictionary = lod.get(key, default_lod)
			if l.get("end", 0.0) > 0.0 or l.get("begin", 0.0) > 0.0:
				mmi.visibility_range_begin = l.get("begin", 0.0)
				mmi.visibility_range_end = l.get("end", 0.0)
				mmi.visibility_range_begin_margin = l.get("margin", 8.0) if l.get("begin", 0.0) > 0.0 else 0.0
				mmi.visibility_range_end_margin = l.get("margin", 8.0) if l.get("end", 0.0) > 0.0 else 0.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			var sh = l.get("shadow", true)
			if sh is int and int(sh) == 2:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			else:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(sh) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			parent.add_child(mmi)
			owned.append(mmi)
			built["%d|%s" % [id, key]] = mm
			stats["instances"] += n
			stats["multimeshes"] += 1
			var ks: Dictionary = stats["keys"]
			ks[key] = int(ks.get(key, 0)) + n
	items.clear()
	_flush_colliders()


func _flush_colliders() -> void:
	for id in colliders:
		var parent := sector_parent(id)
		var inv: Transform3D = _inv_cache[id]
		var by_surface := {}
		for c: ColSpec in colliders[id]:
			if not by_surface.has(c.surface):
				by_surface[c.surface] = []
			by_surface[c.surface].append(c)
		for surface in by_surface:
			var body := StaticBody3D.new()
			body.name = "Col_%s" % surface
			body.collision_layer = GC.L_WORLD
			body.collision_mask = 0
			body.set_meta("surface", String(surface))
			body.add_to_group(&"world_static")
			parent.add_child(body)
			owned.append(body)
			for c: ColSpec in by_surface[surface]:
				var cs := CollisionShape3D.new()
				if c.shape != null:
					cs.shape = c.shape
				elif c.radius > 0.0:
					var sh := CylinderShape3D.new()
					sh.radius = c.radius
					sh.height = c.size.y
					cs.shape = sh
				else:
					var sb := BoxShape3D.new()
					sb.size = c.size
					cs.shape = sb
				cs.transform = inv * c.xf
				body.add_child(cs)
				stats["colliders"] += 1
	colliders.clear()
