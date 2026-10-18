class_name FillBuilder
extends RefCounted
## World-fill pass (wave 3): places the complete Blender hero buildings that the kit assembler cannot build (tower_a/b/c, hotel, hangars,
## warehouses, factory, silo cluster), the dock crane + containers, lighthouse, animated ferris wheel, beach life, promenade vendors,
## park playgrounds, yard clutter, downtown newspaper boxes and a marked hospital helipad. Everything static goes through ContentBatch
## (MultiMesh per sector); only the ferris wheel is animated (FillAnimator, one node). A missing GLB is logged and skipped / falls back to
## the kit building (BuildingKit).
##
## Lot heroes: LayoutLots tags `lot["hero"]`; BuildingKit.build_all calls place_hero_lot(). Free-standing heroes use place_free().

const _LB := preload("res://gta/code/world/landmark_builder.gd")

const MIN_SCALE := 0.5

## Hero collision boxes in model space [[centre, size], ...] (when absent: one box of the model AABB).
const HERO_BOXES := {
	"tower_a": [[Vector3(0, 7.15, 0), Vector3(28, 14.3, 28)], [Vector3(4.6, 34, 0), Vector3(17.2, 40, 24)], [Vector3(6, 70, 0), Vector3(13.4, 32, 18)],
		[Vector3(6, 93, 0), Vector3(10, 14, 12)], [Vector3(6, 102.5, 0), Vector3(6.4, 5, 8)]],
	"crane_dock": [[Vector3(7, 12, -9.5), Vector3(2.2, 24, 3.4)], [Vector3(-7, 12, -9.5), Vector3(2.2, 24, 3.4)],
		[Vector3(7, 12, 20.5), Vector3(2.2, 24, 3.4)], [Vector3(-7, 12, 20.5), Vector3(2.2, 24, 3.4)]],
	"lighthouse": [[Vector3(0, 16, 0), Vector3(6.2, 32, 6.2)]],
}

const PROP_LOD_END := 150.0

static var stats := {"heroes": 0, "hero_fallback": 0, "props": 0, "missing": [], "placed": {}}
static var animator: Node = null
static var placed_heroes: Array = []     # [{id, pos, yaw, scale, rect}] (tests / minimap)


static func reset() -> void:
	stats = {"heroes": 0, "hero_fallback": 0, "props": 0, "missing": [], "placed": {}}
	animator = null
	placed_heroes = []


# ---- registration ----------------------------------------------------------------------------------------------------------------------
static func _register_hero(batch: ContentBatch, hero: String) -> StringName:
	var key := StringName("hero_" + hero)
	if ContentLib.has_mesh(key):
		return key
	var rel := "buildings/" + hero
	if not ModelLib.exists(rel):
		return &""
	var node := ModelLib.instance(rel)
	if node == null:
		return &""
	var mesh := ContentLib.flatten(node, [])
	var emp := ContentLib.empties(node)
	node.free()
	if mesh == null or mesh.get_surface_count() == 0:
		return &""
	ContentLib.put(key, mesh, "glb:" + rel)
	ContentLib.glb_loaded.append(rel)
	ContentLib.extras[key] = emp
	batch.set_lod(key, 0.0, 0.0, 0.0, true)
	return key


static func _register_prop(batch: ContentBatch, name: String) -> StringName:
	var key := StringName("fill_" + name)
	if ContentLib.has_mesh(key):
		return key
	if not ContentLib.register_glb_optional(key, "props/" + name):
		if not (stats["missing"] as Array).has(name):
			(stats["missing"] as Array).append(name)
			push_warning("FillBuilder: props/%s.glb missing - skipped" % name)
		return &""
	batch.set_lod(key, 0.0, PROP_LOD_END, 12.0, false)
	return key


static func _ground_y(x: float, z: float) -> float:
	var ph := WorldLayout.pier_height(x, z)
	if ph > -1000.0 and WorldLayout.on_pier(x, z):
		return ph + 0.03
	return WorldLayout.terrain_height(x, z)


## One decorative prop. Returns true when placed. collider: "" / "cyl:<r>:<h>" / "box:<x>:<y>:<z>".
static func prop(batch: ContentBatch, name: String, pos: Vector3, yaw: float, scale := 1.0, collider := "") -> bool:
	var key := _register_prop(batch, name)
	if key == &"":
		return false
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(scale, scale, scale)), pos)
	batch.add(key, xf, Color(0.0, randf(), randf(), randf()))
	stats["props"] += 1
	if collider.begins_with("cyl:"):
		var p := collider.split(":")
		batch.add_cyl_collider(pos, float(p[1]) * scale, float(p[2]) * scale, &"metal")
	elif collider.begins_with("box:"):
		var p2 := collider.split(":")
		var sz := Vector3(float(p2[1]), float(p2[2]), float(p2[3])) * scale
		batch.add_box_collider(Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, sz.y * 0.5, 0)), sz, &"metal")
	return true


static func _box(batch: ContentBatch, place: Transform3D, s: float, centre: Vector3, size: Vector3) -> void:
	var wc := place * centre
	batch.add_box_collider(Transform3D(place.basis.orthonormalized(), wc), size * s, &"concrete")


## Adds the hero mesh + colliders at `place` (model origin transform, uniform scale in the basis). Returns false when the GLB is missing.
static func _put_hero(batch: ContentBatch, hero: String, place: Transform3D, s: float, pal: int, rng: RandomNumberGenerator) -> bool:
	var key := _register_hero(batch, hero)
	if key == &"":
		stats["hero_fallback"] += 1
		if not (stats["missing"] as Array).has(hero):
			(stats["missing"] as Array).append(hero)
			push_warning("FillBuilder: buildings/%s.glb missing - kit fallback / skipped" % hero)
		return false
	batch.add(key, place, Color(float(pal + 1), rng.randf(), rng.randf(), 0.5))
	var bb: AABB = ContentLib.aabbs[key]
	var boxes: Array = HERO_BOXES.get(hero, [])
	if boxes.is_empty():
		_box(batch, place, s, bb.position + bb.size * 0.5, bb.size * Vector3(0.97, 1.0, 0.97))
	else:
		for b in boxes:
			_box(batch, place, s, b[0], b[1])
	stats["heroes"] += 1
	(stats["placed"] as Dictionary)[hero] = int((stats["placed"] as Dictionary).get(hero, 0)) + 1
	return true


# ---- lot heroes ---------------------------------------------------------------------------------------------------------------------------
## Called by BuildingKit.build_all for lots with lot["hero"]. false = GLB missing (the caller builds the normal kit building).
static func place_hero_lot(batch: ContentBatch, lot: Dictionary, rng: RandomNumberGenerator) -> bool:
	var hero := String(lot.get("hero", ""))
	if hero == "":
		return false
	var key := _register_hero(batch, hero)
	if key == &"":
		stats["hero_fallback"] += 1
		push_warning("FillBuilder: hero '%s' GLB missing - kit building used for lot %s" % [hero, str(lot.get("id", -1))])
		return false
	var rect: Rect2 = lot["rect"]
	var yaw := float(lot.get("yaw", 0.0))
	var swap := absf(sin(yaw)) > 0.7071
	var w := rect.size.y if swap else rect.size.x
	var d := rect.size.x if swap else rect.size.y
	var c := rect.get_center()
	var bb: AABB = ContentLib.aabbs[key]
	var s := clampf(minf((w - 0.8) / maxf(bb.size.x, 0.1), (d - 0.8) / maxf(bb.size.z, 0.1)), MIN_SCALE, 1.0)
	var y0: float = BuildingKit._ground(c, rect.size.x, rect.size.y).x
	var root := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y0, c.y))
	var dz := -d * 0.5 + 0.8 - bb.position.z * s
	if bb.size.z * s > d - 1.6:
		dz = -(bb.position.z + bb.size.z * 0.5) * s
	var dx := -(bb.position.x + bb.size.x * 0.5) * s
	if HERO_BOXES.has(hero):
		dx = 0.0   # collision boxes are authored around the model origin; keep the footprint centre on the lot axis
	var place := root * Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(dx, 0.0, dz))
	var pal := clampi(int(lot.get("palette", 0)), 0, 3)
	if not _put_hero(batch, hero, place, s, pal, rng):
		return false
	BuildingKit._count(lot.get("kind", &"office"))
	var emp: Dictionary = ContentLib.extras.get(key, {})
	_update_locations(lot, hero, place, emp)
	_LB._anchors(batch, lot, StringName(hero), place, emp)
	placed_heroes.append({"id": hero, "pos": place.origin, "yaw": yaw, "scale": s, "rect": rect})
	# far-LOD shadow proxy is not needed: heroes are single meshes visible at any range
	return true


## Roof / door anchors of heroes drive the matching WorldLayout locations (helipad on the tower_a podium, hangar door).
static func _update_locations(lot: Dictionary, hero: String, place: Transform3D, emp: Dictionary) -> void:
	if hero == "tower_a" and emp.has("RoofHelipad"):
		var loc: Dictionary = WorldLayout.locations.get(&"helipad_downtown", {})
		if not loc.is_empty():
			var t: Transform3D = place * (emp["RoofHelipad"] as Transform3D)
			loc["pos"] = t.origin + Vector3(0, 0.45, 0)
			loc["lot"] = int(lot.get("id", -1))
	if hero == "hangar_a" and emp.has("HangarDoor"):
		var loc2: Dictionary = WorldLayout.locations.get(&"airport_hangar", {})
		if not loc2.is_empty():
			var t2: Transform3D = place * (emp["HangarDoor"] as Transform3D)
			var out := -place.basis.z.normalized()
			loc2["pos"] = t2.origin + out * 4.0 + Vector3(0, 0.05, 0)


## Landmark hook (LandmarkBuilder._build_one): marked helipad pad on a landmark roof that carries a `RoofHelipad` empty.
static func landmark_roof_pad(batch: ContentBatch, id: StringName, place: Transform3D, emp: Dictionary) -> void:
	if not emp.has("RoofHelipad"):
		return
	var t: Transform3D = place * (emp["RoofHelipad"] as Transform3D)
	var key: StringName = &"K:Roof_Helipad_Pad" if ContentLib.has_mesh(&"K:Roof_Helipad_Pad") else &"helipad"
	var native := 12.0 if key == &"K:Roof_Helipad_Pad" else 19.0
	var sc := 10.0 / native
	batch.set_lod(key, 0.0, 0.0, 0.0, true)
	var yaw := atan2(-place.basis.z.x, -place.basis.z.z)
	batch.add(key, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sc, 1.0, sc)), t.origin), Color(1.0, 0.5, 0.5, 0.5))
	var hid := StringName("helipad_" + String(id))
	var loc: Dictionary = WorldLayout.locations.get(hid, {})
	if not loc.is_empty():
		loc["pos"] = t.origin + Vector3(0, 0.4, 0)
	stats["props"] += 1


# ---- free-standing heroes ---------------------------------------------------------------------------------------------------------------------
static func place_free(batch: ContentBatch, hero: String, pos: Vector3, yaw: float, rng: RandomNumberGenerator, s := 1.0) -> Transform3D:
	var place := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s, s)), pos)
	if not _put_hero(batch, hero, place, s, rng.randi() % 4, rng):
		return Transform3D.IDENTITY
	placed_heroes.append({"id": hero, "pos": pos, "yaw": yaw, "scale": s, "rect": Rect2()})
	return place


# ---- main entry ------------------------------------------------------------------------------------------------------------------------------------
static func build(batch: ContentBatch) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260117
	_docks(batch, rng)
	_ferris_wheel(batch, rng)
	_beach(batch, rng)
	_parks(batch, rng)
	_yards(batch, rng)
	_downtown_life(batch, rng)
	print("[FillBuilder] %d ms: heroes=%s props=%d fallbacks=%d missing=%s" % [Time.get_ticks_msec() - t0, str(stats["placed"]), stats["props"], stats["hero_fallback"], str(stats["missing"])])


# ---- docks ----------------------------------------------------------------------------------------------------------------------------------------
static func _docks(batch: ContentBatch, rng: RandomNumberGenerator) -> void:
	# dock crane on the quay east of Crane Way: boom points seaward (+Z) -> model yaw PI; seaward legs on the quay rim
	place_free(batch, "crane_dock", Vector3(-205.0, 0.02, 184.0), PI, rng)
	for z in [170.0, 178.5, 187.0]:
		place_free(batch, "container_stack", Vector3(-205.0, 0.02, z), 0.0, rng)
	place_free(batch, "container_stack", Vector3(-127.8, 0.02, 180.5), 0.0, rng)
	# lighthouse on the cargo pier tip (pier x -196..-174, z 192..262)
	place_free(batch, "lighthouse", Vector3(-190.5, WorldLayout.pier_height(-190.5, 255.0) + 0.03, 255.0), 0.0, rng)
	# life rings + dock bollards on the pier tips
	for p in WorldLayout.piers:
		if p.get("finger", false):
			continue
		var r: Rect2 = p["rect"]
		var h: float = float(p["height"]) + 0.03
		if r.size.y < 20.0:
			continue
		prop(batch, "life_ring", Vector3(r.position.x + 0.4, h + 0.9, r.end.y - 6.0), PI * 0.5, 1.0)
		prop(batch, "life_ring", Vector3(r.end.x - 0.4, h + 0.9, r.end.y - 14.0), -PI * 0.5, 1.0)
		prop(batch, "dock_bollard", Vector3(r.position.x + 0.6, h, r.end.y - 1.2), 0.0, 1.0, "cyl:0.3:0.6")
		prop(batch, "dock_bollard", Vector3(r.end.x - 0.6, h, r.end.y - 1.2), 0.0, 1.0, "cyl:0.3:0.6")


# ---- ferris wheel (animated) --------------------------------------------------------------------------------------------------------------
static func _ferris_wheel(batch: ContentBatch, rng: RandomNumberGenerator) -> void:
	var rel := "buildings/ferris_wheel"
	if not ModelLib.exists(rel):
		(stats["missing"] as Array).append("ferris_wheel")
		return
	# look for a sand spot east of the beach pier where the 21 x 15 m base fits between the promenade path and the waterline
	var pos := Vector3.INF
	var best_spread := 99.0
	var spokes := [-70.0, -30.0, 10.0, 46.0, 0.0]
	for ix in range(-88, 66, 4):
		var cx := float(ix)
		var near_spoke := false
		for sx in spokes:
			if absf(cx - float(sx)) < (16.0 if float(sx) == 0.0 else 12.0):
				near_spoke = true
		if near_spoke:
			continue
		for iz in range(164, 172, 2):
			var cz := float(iz)
			var lo := 99.0
			var hi := -99.0
			var wet := false
			for ox in [-11.0, 0.0, 11.0]:
				for oz in [-8.0, 0.0, 7.0]:
					var h := WorldLayout.terrain_height(cx + float(ox), cz + float(oz))
					lo = minf(lo, h)
					hi = maxf(hi, h)
					if WorldLayout.is_water(cx + float(ox), cz + float(oz)) or h < -0.9:
						wet = true
			if not wet and hi - lo < best_spread:
				best_spread = hi - lo
				pos = Vector3(cx, hi, cz)
	if pos == Vector3.INF:
		push_warning("FillBuilder: no flat sand spot for the ferris wheel")
		return
	var node := ModelLib.instance(rel)
	if node == null:
		return
	var ground := pos.y - 0.05   # pos.y = highest terrain under the base footprint
	var root_xf := Transform3D(Basis.IDENTITY, Vector3(pos.x, ground, pos.z))
	var cid := ContentBatch.cell_id(pos)
	var parent := batch.sector_parent(cid)
	var inv: Transform3D = batch._inv_cache[cid]
	var wheel_node := node.find_child("Wheel", true, false) as Node3D
	var anim := FillAnimator.get_or_create(batch)
	var entry := {"base": root_xf, "gondolas": [], "speed": 0.11, "angle": rng.randf() * TAU}
	for mi in ModelLib.meshes(node):
		var nm := String(mi.name)
		if nm.begins_with("Collision"):
			continue
		var m := ContentLib.flatten_local(mi)
		if m == null or m.get_surface_count() == 0:
			continue
		var local_xf: Transform3D = ContentLib._rel(node, mi)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = 1
		mm.set_instance_custom_data(0, Color(1.0 + float(rng.randi() % 4), rng.randf(), rng.randf(), 0.5))
		mm.set_instance_transform(0, inv * (root_xf * local_xf))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "FW_" + nm
		mmi.multimesh = mm
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		parent.add_child(mmi)
		batch.own(mmi)
		if nm == "Wheel":
			entry["wheel_mm"] = mm
			entry["wheel_local"] = local_xf
		elif nm.begins_with("Gondola"):
			(entry["gondolas"] as Array).append({"mm": mm, "local": (wheel_node.transform.affine_inverse() * local_xf) if wheel_node != null else local_xf})
	node.free()
	entry["inv"] = inv
	anim.wheels.append(entry)
	# colliders: two A-frame legs + hub block
	batch.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(pos.x - 8.5, ground + 9.0, pos.z)), Vector3(3.0, 18.0, 9.0), &"metal")
	batch.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(pos.x + 8.5, ground + 9.0, pos.z)), Vector3(3.0, 18.0, 9.0), &"metal")
	stats["placed"]["ferris_wheel"] = 1
	placed_heroes.append({"id": "ferris_wheel", "pos": pos, "yaw": 0.0, "scale": 1.0, "rect": Rect2()})


# ---- beach life ----------------------------------------------------------------------------------------------------------------------------------
static func _sand_ok(x: float, z: float, min_h := -0.1) -> bool:
	if z < 160.5 or WorldLayout.is_water(x, z) or WorldLayout.on_pier(x, z):
		return false
	var h := WorldLayout.terrain_height(x, z)
	return h > min_h and h < 1.5


static func _beach(batch: ContentBatch, rng: RandomNumberGenerator) -> void:
	var taken: Array[Vector2] = []
	# keep clear: ferris wheel footprint, beach pier root, ped spokes
	var blockers: Array = []
	for h in placed_heroes:
		if String(h["id"]) == "ferris_wheel":
			var p: Vector3 = h["pos"]
			blockers.append(Rect2(p.x - 13.0, p.z - 10.0, 26.0, 20.0))
	blockers.append(Rect2(-7.0, 160.0, 14.0, 60.0))
	for sx in [-70.0, -30.0, 10.0, 46.0]:
		blockers.append(Rect2(sx - 3.0, 156.0, 7.0, 18.0))
	var is_free := func(x: float, z: float, r: float) -> bool:
		for b in blockers:
			if (b as Rect2).grow(r).has_point(Vector2(x, z)):
				return false
		for t in taken:
			if t.distance_to(Vector2(x, z)) < r:
				return false
		return true
	# umbrellas with towels / chairs
	var n := 0
	var tries := 0
	while n < 16 and tries < 400:
		tries += 1
		var x := rng.randf_range(-92.0, 68.0)
		var z := rng.randf_range(162.0, 171.0)
		if not _sand_ok(x, z) or not is_free.call(x, z, 6.5):
			continue
		taken.append(Vector2(x, z))
		var y := WorldLayout.terrain_height(x, z)
		prop(batch, "beach_umbrella", Vector3(x, y, z), rng.randf() * TAU)
		prop(batch, "beach_towel", Vector3(x - 1.4, y + 0.01, z + 1.2), rng.randf_range(-0.4, 0.4))
		if rng.randf() < 0.7:
			prop(batch, "beach_towel", Vector3(x + 1.6, y + 0.01, z + 1.0), rng.randf_range(-0.4, 0.4))
		if rng.randf() < 0.5:
			prop(batch, "deck_chair", Vector3(x + 0.2, y, z - 1.6), rng.randf_range(-0.3, 0.3))
		n += 1
	# volleyball court, surf racks, campfire + tents at the east end
	for spec in [["volleyball_net", Vector2(-16.0, 165.0), 0.0], ["surfboard_rack", Vector2(-84.0, 162.8), 0.0], ["surfboard_rack", Vector2(24.0, 162.8), 0.0]]:
		var p2: Vector2 = spec[1]
		if _sand_ok(p2.x, p2.y):
			prop(batch, String(spec[0]), Vector3(p2.x, WorldLayout.terrain_height(p2.x, p2.y), p2.y), float(spec[2]), 1.0, "box:0.5:2.0:0.5" if spec[0] == "surfboard_rack" else "")
	var camp := Vector2(60.0, 166.0)
	if not _sand_ok(camp.x, camp.y):
		for cx in [58.0, 62.0, 54.0, -88.0]:
			if _sand_ok(cx, 166.0):
				camp = Vector2(cx, 166.0)
				break
	if _sand_ok(camp.x, camp.y):
		var cy := WorldLayout.terrain_height(camp.x, camp.y)
		prop(batch, "campfire", Vector3(camp.x, cy, camp.y), 0.0)
		for k in 3:
			var a := PI * (0.35 + 0.65 * float(k)) + 0.4
			var tp := camp + Vector2(cos(a), sin(a)) * 5.5
			if _sand_ok(tp.x, tp.y):
				prop(batch, "tent", Vector3(tp.x, WorldLayout.terrain_height(tp.x, tp.y), tp.y), Util.dir_to_yaw(Vector3(camp.x - tp.x, 0, camp.y - tp.y)), 1.0, "box:2.0:1.3:2.6")
	# promenade vendors (front toward the promenade / Seaview side)
	for v in [["ice_cream_cart", Vector2(-56.0, 158.8)], ["hotdog_stand", Vector2(26.0, 159.0)], ["ice_cream_cart", Vector2(-92.0, 158.8)], ["hotdog_stand", Vector2(60.0, 159.4)]]:
		var vp: Vector2 = v[1]
		if not WorldLayout.is_water(vp.x, vp.y):
			prop(batch, String(v[0]), Vector3(vp.x, WorldLayout.terrain_height(vp.x, vp.y), vp.y), 0.0, 1.0, "box:1.7:2.4:1.4")
	for bx in [-62.0, -38.0, -2.0, 30.0]:
		prop(batch, "trash_can_park", Vector3(bx, WorldLayout.terrain_height(bx, 158.6), 158.6), 0.0, 1.0, "cyl:0.3:0.9")


# ---- parks ------------------------------------------------------------------------------------------------------------------------------------------
static func _park_ok(x: float, z: float, r: float) -> bool:
	if WorldLayout.is_water(x, z):
		return false
	var rd := WorldLayout.road_at(x, z, 40.0)
	if not rd.is_empty() and float(rd["dist"]) < float(rd["half_width"]) + 4.0 + r:
		return false
	return absf(WorldLayout.terrain_height(x, z)) < 0.4


static func _playground(batch: ContentBatch, c: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var y := WorldLayout.terrain_height(c.x, c.y)
	var rot := Basis(Vector3.UP, yaw)
	prop(batch, "swing_set", Vector3(c.x, y, c.y), yaw, 1.0, "box:3.4:2.2:0.3")
	var sp := Vector3(c.x, y, c.y) + rot * Vector3(7.0, 0, 0)
	prop(batch, "slide", sp, yaw + PI * 0.5, 1.0, "box:0.9:2.0:3.0")
	for k in 2:
		var tp := Vector3(c.x, y, c.y) + rot * Vector3(-6.0 + 12.0 * float(k), 0, 7.0)
		prop(batch, "picnic_table", tp, yaw + rng.randf_range(-0.2, 0.2), 1.0, "box:1.9:0.9:1.7")
	var bp := Vector3(c.x, y, c.y) + rot * Vector3(3.5, 0, 5.0)
	prop(batch, "trash_can_park", bp, 0.0, 1.0, "cyl:0.3:0.9")


static func _parks(batch: ContentBatch, rng: RandomNumberGenerator) -> void:
	for spec in [[Vector2(-52.0, -183.0), 0.0], [Vector2(12.0, -105.0), PI], [Vector2(-229.0, -60.0), 0.0]]:
		var c: Vector2 = spec[0]
		if _park_ok(c.x, c.y, 8.0):
			_playground(batch, c, float(spec[1]), rng)
		else:
			push_warning("FillBuilder: playground spot %s rejected" % str(c))
	# picnic tables around the pond + bins along the park paths
	var pc: Vector2 = LayoutTerrain.POND_C
	for k in 5:
		var a := TAU * (float(k) + 0.5) / 5.0 + 0.5
		var p := pc + Vector2(cos(a), sin(a)) * 37.0
		if _park_ok(p.x, p.y, 3.0):
			prop(batch, "picnic_table", Vector3(p.x, WorldLayout.terrain_height(p.x, p.y), p.y), a + PI * 0.5, 1.0, "box:1.9:0.9:1.7")


# ---- industrial yards ----------------------------------------------------------------------------------------------------------------------------
static func _yards(batch: ContentBatch, rng: RandomNumberGenerator) -> void:
	for g in LayoutLots.grounds:
		if String(g["key"]) != "yard":
			continue
		var lot_id := int(g["id"])
		if lot_id >= 0 and WorldLayout.lots[lot_id].has("hero"):
			continue
		var r: Rect2 = g["rect"]
		r = r.grow(-3.0)
		if r.size.x < 8.0 or r.size.y < 8.0:
			continue
		var area := r.size.x * r.size.y
		var n_barrel := clampi(int(area / 60.0), 4, 14)
		for i in n_barrel:
			var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			prop(batch, "barrel", Vector3(p.x, WorldLayout.terrain_height(p.x, p.y), p.y), rng.randf() * TAU, 1.0, "cyl:0.35:0.95")
		for i in clampi(int(area / 120.0), 2, 7):
			var p2 := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			prop(batch, "pallet", Vector3(p2.x, WorldLayout.terrain_height(p2.x, p2.y), p2.y), rng.randf() * TAU)
			prop(batch, "crate", Vector3(p2.x + 1.4, WorldLayout.terrain_height(p2.x, p2.y), p2.y), rng.randf() * TAU, 1.0, "box:1.1:1.1:1.1")
		if area > 400.0:
			var p3 := Vector2(rng.randf_range(r.position.x + 4.0, r.end.x - 4.0), rng.randf_range(r.position.y + 4.0, r.end.y - 4.0))
			var cn: String = ["container", "container_b", "container_c", "container_d"][rng.randi() % 4]
			prop(batch, cn, Vector3(p3.x, WorldLayout.terrain_height(p3.x, p3.y), p3.y), float(rng.randi() % 2) * PI * 0.5, 1.0, "box:2.5:2.6:6.1")


# ---- downtown street life -----------------------------------------------------------------------------------------------------------------------
static func _downtown_life(batch: ContentBatch, rng: RandomNumberGenerator) -> void:
	var placed := 0
	for e in LayoutRoadNet.edges:
		if not (String(e["name"]) in ["Alder Street", "Birch Street", "Cedar Avenue", "Dune Avenue"]):
			continue
		var pts: PackedVector2Array = e["pts"]
		var cum := LayoutGeo.cum_lengths(pts)
		var hw: float = e["hw"]
		var sw: float = e["sw"]
		var s := float(e["trim_a"]) + 11.0
		var s1 := float(e["len"]) - float(e["trim_b"]) - 11.0
		var k := 0
		while s < s1:
			var d := LayoutGeo.dir_at(pts, s, cum)
			var c := LayoutGeo.point_at(pts, s, cum)
			var r := LayoutGeo.right_of(d)
			var side := 1.0 if k % 2 == 0 else -1.0
			var p2 := c + r * side * (hw + sw - 0.7)
			var p3 := Vector3(p2.x, WorldLayout.terrain_height(p2.x, p2.y) + 0.15, p2.y)
			if LayoutFurniture._lane_dist(p3) >= 2.4 and not _near_furniture(p2, 2.0):
				var face := Util.dir_to_yaw(Vector3(-r.x * side, 0, -r.y * side))
				var nm := "newspaper_box" if k % 3 != 2 else "trash_bin"
				if prop(batch, nm, p3, face, 1.0, "cyl:0.35:1.0"):
					placed += 1
			s += 27.0 + rng.randf_range(0.0, 8.0)
			k += 1
	stats["placed"]["street_boxes"] = placed


static func _near_furniture(p: Vector2, r: float) -> bool:
	for f in WorldLayout.furniture:
		var fp: Vector3 = f["pos"]
		if absf(fp.x - p.x) < r and absf(fp.z - p.y) < r:
			return true
	return false
