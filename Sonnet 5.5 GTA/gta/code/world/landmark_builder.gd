class_name LandmarkBuilder
extends RefCounted
## Hero buildings: lots of kind "landmark" place models/buildings/<lot.landmark>.glb (footprint centre at the lot centre, front door
## toward the street = lot yaw) and expose door / anchor empties as plain Marker3D nodes in group "location_anchor" (matching
## WorldLayout.locations by id or position) so the Systems agent can attach its interaction logic.
## A missing GLB falls back to a code-built building (BuildingKit assembly or a gas station / tower) - logged, listed in the report.

const FALLBACK_KIND := {
	&"hospital": [&"office", 5], &"police_station": [&"office", 4], &"weapon_shop": [&"shop", 2], &"clothing_store": [&"shop", 2],
	&"barber": [&"shop", 2], &"scuba_shop": [&"shop", 2], &"garage_shop": [&"warehouse", 1], &"safehouse": [&"apartment", 4],
	&"airport_terminal": [&"office", 3], &"dealer_lot": [&"shop", 2], &"train_station_a": [&"warehouse", 1], &"train_station_b": [&"warehouse", 1],
	&"gas_station": [&"gas", 1], &"airport_tower": [&"tower", 1], &"marina_office": [&"shop", 2], &"shooting_range": [&"warehouse", 1],
	&"diving_shop": [&"shop", 2],
}

## landmark id -> GLB id when the Blender asset has a different name
const GLB_ALIAS := {&"airport_terminal": &"terminal", &"airport_tower": &"control_tower", &"marina_office": &"pier_hut"}

static var stats := {"landmarks": 0, "glb": 0, "fallback": 0, "anchors": 0, "missing_ids": []}


static func reset() -> void:
	stats = {"landmarks": 0, "glb": 0, "fallback": 0, "anchors": 0, "missing_ids": []}


static func _ground(c: Vector2) -> float:
	return WorldLayout.terrain_height(c.x, c.y)


## Code-built gas station: canopy on columns + kiosk + pumps + price pylon. Origin = footprint centre, front -Z.
static func gas_station_mesh() -> ContentMesh:
	var m := ContentMesh.new()
	var steel := Color("#8d96a0")
	m.box(&"WallA", Vector3(0, 5.2, -1.5), Vector3(16.0, 0.5, 9.0), Color.WHITE, 8)
	m.box(&"WallB", Vector3(0, 5.2, -1.5), Vector3(16.2, 0.2, 9.2), Color.WHITE, 4 | 8)
	m.box(&"NeonCyan", Vector3(0, 4.92, -6.0), Vector3(16.0, 0.08, 0.08))
	m.box(&"NeonMagenta", Vector3(0, 4.92, 3.0), Vector3(16.0, 0.08, 0.08))
	for sx in [-6.0, 6.0]:
		for sz in [-4.5, 1.5]:
			m.cyl(&"V", Vector3(sx, 0, sz), 0.28, 0.28, 5.0, 8, Color("#e6e2d6"), true, false, true)
	for sx in [-3.0, 3.0]:
		for sz in [-3.0, 0.0]:
			m.box(&"V", Vector3(sx, 0.9, sz), Vector3(0.8, 1.8, 0.55), Color("#d93a3a"), 8)
			m.box(&"NeonCyan", Vector3(sx, 1.4, sz - 0.28), Vector3(0.5, 0.25, 0.02))
			m.box(&"V", Vector3(sx, 0.08, sz), Vector3(2.4, 0.16, 1.1), Color("#9a958c"), 8)
	for i in 4:
		m.box(&"LampGlow", Vector3(-4.5 + i * 3.0, 4.93, -1.5), Vector3(0.9, 0.04, 0.6), Color.WHITE, 1 | 2 | 4 | 16 | 32)
	# kiosk at the back
	m.box(&"WallA", Vector3(0, 1.7, 6.5), Vector3(10.0, 3.4, 4.5), Color.WHITE, 8)
	m.box(&"Roof", Vector3(0, 3.5, 6.5), Vector3(10.6, 0.25, 5.1), Color.WHITE, 8)
	m.quad(&"Window_shop", Vector3(-4.2, 0.4, 4.24), Vector3(4.2, 0.4, 4.24), Vector3(4.2, 2.6, 4.24), Vector3(-4.2, 2.6, 4.24), Vector3(0, 0, -1), Color.WHITE, Vector2(-4.2, 0.4), Vector2(4.2, 2.6))
	m.box(&"Metal", Vector3(0, 1.4, 4.2), Vector3(0.07, 2.2, 0.07), steel)
	m.box(&"WallB", Vector3(0, 3.05, 4.15), Vector3(10.0, 0.7, 0.2), Color.WHITE)
	m.box(&"Neon", Vector3(0, 3.05, 4.03), Vector3(6.0, 0.22, 0.04))
	# price pylon
	m.cyl(&"Metal", Vector3(-9.5, 0, -6.0), 0.2, 0.2, 7.5, 8, Color("#4b525b"), true, false, true)
	m.box(&"V", Vector3(-9.5, 7.6, -6.0), Vector3(2.2, 2.2, 0.35), Color("#2a2d33"))
	m.box(&"NeonAmber", Vector3(-9.5, 8.2, -6.2), Vector3(1.8, 0.35, 0.05))
	m.box(&"NeonAmber", Vector3(-9.5, 7.6, -6.2), Vector3(1.8, 0.35, 0.05))
	m.box(&"NeonCyan", Vector3(-9.5, 7.0, -6.2), Vector3(1.8, 0.35, 0.05))
	return m


static func tower_mesh() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"WallD", Vector3(0, 3.0, 0), Vector3(10.0, 6.0, 8.0), Color.WHITE, 8)
	m.box(&"Roof", Vector3(0, 6.1, 0), Vector3(10.4, 0.25, 8.4), Color.WHITE, 8)
	m.cyl(&"WallA", Vector3(0, 6.2, 0), 2.3, 2.1, 17.0, 10, Color.WHITE, false, false, true)
	m.cyl(&"WallD", Vector3(0, 23.2, 0), 4.2, 4.6, 0.7, 10, Color.WHITE, false, true, true)
	m.cyl(&"Window_shop", Vector3(0, 23.9, 0), 4.4, 4.4, 2.6, 10, Color.WHITE, false, false, false)
	m.cyl(&"WallD", Vector3(0, 26.5, 0), 4.7, 3.6, 0.7, 10, Color.WHITE, false, true, true)
	m.cyl(&"Metal", Vector3(0, 27.2, 0), 0.08, 0.05, 6.0, 5, Color("#8d96a0"), true, false, false)
	m.box(&"NeonRed", Vector3(0, 33.3, 0), Vector3(0.3, 0.3, 0.3))
	return m


static func _fallback_mesh(id: StringName) -> ContentMesh:
	return gas_station_mesh() if id == &"gas_station" else tower_mesh()


## Builds all landmark lots. Returns the number of landmarks placed.
static func build(batch: ContentBatch) -> int:
	var rng := RandomNumberGenerator.new()
	for lot in WorldLayout.lots:
		if lot.get("kind", &"") != &"landmark":
			continue
		var id: StringName = lot.get("landmark", &"")
		if id == &"":
			continue
		rng.seed = hash(int(lot.get("id", 0)) * 31 + 7)
		_build_one(batch, lot, id, rng)
	return int(stats["landmarks"])


static func _build_one(batch: ContentBatch, lot: Dictionary, id: StringName, rng: RandomNumberGenerator) -> void:
	var rect: Rect2 = lot["rect"]
	var yaw := float(lot.get("yaw", 0.0))
	var c: Vector2 = rect.get_center()
	var y0 := _ground(c)
	var root := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y0, c.y))
	var rel := "buildings/" + String(GLB_ALIAS.get(id, id))
	var pal := clampi(int(lot.get("palette", 0)), 0, 3)
	var bright := rng.randf()
	var bseed := rng.randf()
	stats["landmarks"] += 1
	var anchors: Dictionary = {}
	var key := StringName("landmark_" + String(id))
	if ModelLib.exists(rel):
		var node := ModelLib.instance(rel)
		if node != null:
			var mesh := ContentLib.flatten(node, [])
			anchors = ContentLib.empties(node)
			var col_mesh: ArrayMesh = _collision_mesh(node)
			node.free()
			if mesh != null and mesh.get_surface_count() > 0:
				ContentLib.put(key, mesh, "glb:" + rel)
				ContentLib.glb_loaded.append(rel)
				stats["glb"] += 1
				batch.set_lod(key, 0.0, 0.0, 0.0, true)
				# centre on the lot, front edge 1.5 m behind the lot's street edge so the door faces the sidewalk
				var bb := mesh.get_aabb()
				var swap := absf(sin(yaw)) > 0.7071
				var lot_d: float = rect.size.x if swap else rect.size.y
				var dz := -lot_d * 0.5 + 1.5 - bb.position.z
				if bb.size.z > lot_d - 2.0:
					dz = -(bb.position.z + bb.size.z * 0.5)
				var place := root * Transform3D(Basis.IDENTITY, Vector3(-(bb.position.x + bb.size.x * 0.5), 0.0, dz))
				batch.add(key, place, Color(float(pal + 1), bright, bseed, 0.5))
				_collide(batch, place, bb, col_mesh)
				_anchors(batch, lot, id, place, anchors)
				FillBuilder.landmark_roof_pad(batch, id, place, anchors)   # world-fill: marked helipad pad + location y on landmark roofs
				return
	# --- fallback
	stats["fallback"] += 1
	(stats["missing_ids"] as Array).append(String(id))
	push_warning("LandmarkBuilder: GLB '%s' missing - code-built FALLBACK for landmark '%s'" % [rel, id])
	var fb: Array = FALLBACK_KIND.get(id, [&"shop", 2])
	var kind: StringName = fb[0]
	if kind == &"gas" or kind == &"tower":
		var cm := _fallback_mesh(id)
		var mesh2 := cm.to_mesh(ContentLib._default_materials())
		ContentLib.put(key, mesh2, "fallback")
		batch.set_lod(key, 0.0, 0.0, 0.0, true)
		batch.add(key, root, Color(float(pal + 1), bright, bseed, 0.5))
		var bb := mesh2.get_aabb()
		if kind == &"gas":
			batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 6.5)), Vector3(10.0, 3.4, 4.5), &"concrete")
			for sx in [-6.0, 6.0]:
				for sz in [-4.5, 1.5]:
					batch.add_cyl_collider((root * Transform3D(Basis.IDENTITY, Vector3(sx, 0, sz))).origin, 0.3, 5.0, &"concrete")
			for sx in [-3.0, 3.0]:
				for sz in [-3.0, 0.0]:
					batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(sx, 0.9, sz)), Vector3(0.8, 1.8, 0.55), &"metal")
		else:
			batch.add_box_collider(root * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 0)), Vector3(10.0, 6.0, 8.0), &"concrete")
			batch.add_cyl_collider(root.origin, 2.4, 24.0, &"concrete")
		anchors = {"Door": Transform3D(Basis.IDENTITY, Vector3(0, 0, -4.2 if kind == &"tower" else -1.5))}
		_anchors(batch, lot, id, root, anchors)
		return
	# BuildingKit assembly as a stand-in
	var fl: Dictionary = lot.duplicate()
	fl["kind"] = kind
	fl["floors"] = fb[1]
	fl["height"] = float(fb[1]) * 3.6 if kind != &"warehouse" else 8.0
	BuildingKit.ensure_library()
	match kind:
		&"office", &"apartment", &"shop":
			BuildingKit.build_block(batch, fl, rng, false)
		&"warehouse":
			BuildingKit.build_industrial(batch, fl, rng)
		_:
			BuildingKit.build_block(batch, fl, rng, false)
	# the door of a BuildingKit block is the centre of its front facade
	anchors = {"Door": Transform3D(Basis.IDENTITY, Vector3(0, 0, -(float(rect.size.y if absf(sin(yaw)) < 0.7 else rect.size.x) * 0.5 - 0.5)))}
	_anchors(batch, lot, id, root, anchors)


static func _collision_mesh(node: Node3D) -> ArrayMesh:
	for mi in ModelLib.meshes(node):
		var nm := String(mi.name)
		if nm.begins_with("Collision") or nm.ends_with("_col") or nm.begins_with("Col_"):
			return ContentLib.flatten_local(mi)
	return null


static func _collide(batch: ContentBatch, root: Transform3D, bb: AABB, col_mesh: ArrayMesh) -> void:
	# one box per landmark (the hero models are blocky); a trimesh from a GLB 'Collision*' mesh is used when it exists
	if col_mesh != null:
		var shape := col_mesh.create_trimesh_shape()
		if shape != null:
			batch.add_shape_collider(root, shape, &"concrete")
			return
	var size := bb.size * Vector3(0.97, 1.0, 0.97)
	batch.add_box_collider(root * Transform3D(Basis.IDENTITY, bb.position + bb.size * 0.5), size, &"concrete")


## Marker3D anchors (group "location_anchor") for every empty of the model + the WorldLayout location of this landmark.
static func _anchors(batch: ContentBatch, lot: Dictionary, id: StringName, root: Transform3D, empties: Dictionary) -> void:
	var cid := ContentBatch.cell_id(root.origin)
	var parent := batch.sector_parent(cid)
	var holder := Node3D.new()
	holder.name = "Landmark_" + String(id)
	parent.add_child(holder)
	batch.own(holder)
	var inv := Transform3D.IDENTITY
	if parent.is_inside_tree():
		inv = parent.global_transform.affine_inverse()
	holder.transform = inv * root
	for nm in empties:
		var mk := Marker3D.new()
		mk.name = String(nm)
		mk.add_to_group(&"landmark_anchor")
		mk.set_meta("landmark", String(id))
		mk.transform = empties[nm]
		holder.add_child(mk)
		stats["anchors"] += 1
	# plain Marker3D at every matching WorldLayout location (id match or inside the lot)
	var rect: Rect2 = (lot["rect"] as Rect2).grow(6.0)
	for lid in WorldLayout.locations:
		var loc: Dictionary = WorldLayout.locations[lid]
		var p: Vector3 = loc.get("pos", Vector3.ZERO)
		if lid == id or (rect.has_point(Vector2(p.x, p.z)) and not String(lid).begins_with("district_center") and not String(lid).begins_with("helipad")):
			_location_marker(batch, parent, lid, loc, id)
		elif String(lid).begins_with("helipad") and rect.has_point(Vector2(p.x, p.z)):
			_location_marker(batch, parent, lid, loc, id)


static func _location_marker(batch: ContentBatch, parent: Node3D, lid: StringName, loc: Dictionary, landmark: StringName) -> void:
	for n in parent.get_children():
		if n.name == "Anchor_" + String(lid):
			return
	var mk := Marker3D.new()
	mk.name = "Anchor_" + String(lid)
	mk.add_to_group(&"location_anchor")
	mk.set_meta("location_id", String(lid))
	mk.set_meta("landmark", String(landmark))
	mk.set_meta("radius", float(loc.get("radius", 3.0)))
	parent.add_child(mk)
	batch.own(mk)
	var inv := Transform3D.IDENTITY
	if parent.is_inside_tree():
		inv = parent.global_transform.affine_inverse()
	mk.transform = inv * Transform3D(Basis(Vector3.UP, float(loc.get("yaw", 0.0))), loc.get("pos", Vector3.ZERO))
	stats["anchors"] += 1
