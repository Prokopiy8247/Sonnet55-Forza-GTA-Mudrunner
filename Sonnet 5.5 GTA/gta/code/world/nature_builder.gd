class_name NatureBuilder
extends RefCounted
## Vegetation for WorldLayout.nature_zones + street trees (furniture kinds palm / tree_street): oak, pine, birch, palm, bushes, rocks,
## grass tufts and reeds. One MultiMesh per (sector, species) with a detailed mesh near the camera and a cheap mesh far away
## (visibility ranges), wind sway in the foliage shader, trunk colliders only where trees stand near roads or paths.
## Meshes come from Blender nature GLBs (nature/*) when present, else from the code-built fallbacks below (logged).

const NEAR_END := 150.0
const FAR_BEGIN := 120.0
const FAR_END := 420.0
const MAX_TRUNK_COLLIDERS := 420
const MAX_TUFTS := 9000
const MAX_TREES := 3200

const SPECIES := [&"oak", &"pine", &"birch", &"palm", &"bush", &"rock", &"grass", &"reed"]

static var stats := {"trees": 0, "bushes": 0, "rocks": 0, "tufts": 0, "reeds": 0, "colliders": 0, "street": 0}
static var _glb_names: PackedStringArray = PackedStringArray()
static var placed_trees := PackedVector3Array()          # zone trees (for tests / other systems)
static var placed_street_trees := PackedVector3Array()   # furniture palms / street trees

# ---- spatial index of roads / lots (rejection tests) ------------------------------------------------------------------
class AvoidIndex extends RefCounted:
	const CELL := 24.0
	var segs: Dictionary = {}    # Vector2i -> Array[[a: Vector2, b: Vector2, half_w: float]]
	var rects: Array[Rect2] = []
	var rect_grid: Dictionary = {}

	func add_road(a: Vector2, b: Vector2, half_w: float) -> void:
		var steps := maxi(1, int(ceil(a.distance_to(b) / (CELL * 0.5))))
		var seen := {}
		for i in steps + 1:
			var p := a.lerp(b, float(i) / float(steps))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var k := Vector2i(int(floor(p.x / CELL)) + dx, int(floor(p.y / CELL)) + dz)
					if seen.has(k):
						continue
					seen[k] = true
					if not segs.has(k):
						segs[k] = []
					segs[k].append([a, b, half_w])

	func add_rect(r: Rect2) -> void:
		rects.append(r)
		var k0 := Vector2i(int(floor(r.position.x / CELL)), int(floor(r.position.y / CELL)))
		var k1 := Vector2i(int(floor(r.end.x / CELL)), int(floor(r.end.y / CELL)))
		for x in range(k0.x, k1.x + 1):
			for z in range(k0.y, k1.y + 1):
				var k := Vector2i(x, z)
				if not rect_grid.has(k):
					rect_grid[k] = []
				rect_grid[k].append(r)

	## Distance from p to the nearest road edge (negative = on the road). INF when no road is near.
	func road_edge_dist(p: Vector2) -> float:
		var k := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
		var best := INF
		if segs.has(k):
			for s in segs[k]:
				var a: Vector2 = s[0]
				var b: Vector2 = s[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var d := p.distance_to(a + ab * t) - float(s[2])
				best = minf(best, d)
		return best

	func in_rect(p: Vector2, margin: float) -> bool:
		var k := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
		if rect_grid.has(k):
			for r in rect_grid[k]:
				if (r as Rect2).grow(margin).has_point(p):
					return true
		return false


static func reset() -> void:
	stats = {"trees": 0, "bushes": 0, "rocks": 0, "tufts": 0, "reeds": 0, "colliders": 0, "street": 0}
	_glb_names = PackedStringArray()
	placed_trees = PackedVector3Array()
	placed_street_trees = PackedVector3Array()


# ---- meshes -------------------------------------------------------------------------------------------------------------------------
static func _list_glbs() -> void:
	if not _glb_names.is_empty():
		return
	var dir := DirAccess.open(ModelLib.ROOT + "nature")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".glb"):
				_glb_names.append(f.get_basename())
	if _glb_names.is_empty():
		_glb_names.append("")


const GLB_TOKENS := {
	&"oak": ["tree_oak", "oak"], &"pine": ["tree_pine", "pine"], &"birch": ["tree_birch", "birch"], &"palm": ["tree_palm", "palm"],
	&"bush": ["bush", "shrub"], &"rock": ["rock", "boulder"], &"grass": ["grass", "tuft"], &"reed": ["reed", "cattail"],
}


static func _find_glb(species: StringName) -> String:
	_list_glbs()
	for c in GLB_TOKENS[species]:
		if _glb_names.has(String(c)):
			return "nature/" + String(c)
	for c in GLB_TOKENS[species]:
		for n in _glb_names:
			if n != "" and n.contains(String(c)):
				return "nature/" + n
	return ""


static func _mats() -> Dictionary:
	return ContentLib._default_materials()


static func mesh_oak(variant: int) -> ContentMesh:
	var m := ContentMesh.new()
	var bark := Color("#5f4330")
	var l1 := Color("#4f8a4a")
	var l2 := Color("#86b04f")
	var seed_v := 100 + variant * 17
	m.cyl(&"Foliage", Vector3.ZERO, 0.36, 0.2, 3.2, 7, bark, false, false, true, 0.0, 0.1)
	m.cyl(&"Foliage", Vector3(0.0, 2.4, 0.0), 0.16, 0.08, 1.6, 5, bark, false, false, true, 0.1, 0.3, Color(0, 0, 0, 0), 0.4)
	m.blob(&"Foliage", Vector3(0, 4.6, 0), Vector3(2.3, 1.9, 2.3), l1, seed_v, 0.2, 1, l2, 0.45, 1.0)
	m.blob(&"Foliage", Vector3(1.2, 3.7, 0.5), Vector3(1.5, 1.2, 1.5), l1.darkened(0.08), seed_v + 1, 0.22, 1, l2.darkened(0.1), 0.4, 0.9)
	m.blob(&"Foliage", Vector3(-1.1, 3.9, -0.6), Vector3(1.6, 1.3, 1.5), l1.lightened(0.05), seed_v + 2, 0.22, 1, l2, 0.4, 0.9)
	m.blob(&"Foliage", Vector3(0.1, 6.0, 0.2), Vector3(1.3, 1.0, 1.3), l2, seed_v + 3, 0.18, 0, l2.lightened(0.1), 0.7, 1.0)
	return m


static func mesh_pine(variant: int) -> ContentMesh:
	var m := ContentMesh.new()
	var bark := Color("#4a3426")
	m.cyl(&"Foliage", Vector3.ZERO, 0.28, 0.14, 5.0, 6, bark, false, false, true, 0.0, 0.1)
	var greens: Array[Color] = [Color("#2f6a42"), Color("#3a7a48"), Color("#2c6040"), Color("#427f4c")]
	for i in 5:
		var r := 2.1 - 0.36 * i
		m.cyl(&"Foliage", Vector3(0, 1.4 + i * 1.35, 0), r, 0.02, 2.3 - 0.1 * i, 8, greens[(i + variant) % 4], false, true, false, 0.4 + 0.12 * i, 0.9 + 0.02 * i, Color(0, 0, 0, 0), float(i) * 0.4)
	return m


static func mesh_birch(variant: int) -> ContentMesh:
	var m := ContentMesh.new()
	var white := Color("#e6e2d6")
	m.cyl(&"Foliage", Vector3.ZERO, 0.2, 0.12, 4.2, 6, white, false, false, true, 0.0, 0.15)
	for i in 5:
		m.cyl(&"Foliage", Vector3(0, 0.5 + i * 0.7, 0), 0.205 - 0.012 * i, 0.205 - 0.012 * i, 0.08, 6, Color("#2a2d33"), false, false, false, 0.0, 0.1)
	var l1 := Color("#86b04f")
	var l2 := Color("#b8cf62")
	var s := 200 + variant * 11
	m.blob(&"Foliage", Vector3(0, 5.0, 0), Vector3(1.7, 1.8, 1.7), l1, s, 0.2, 1, l2, 0.45, 1.0)
	m.blob(&"Foliage", Vector3(0.7, 4.0, 0.3), Vector3(1.1, 1.0, 1.1), l1.darkened(0.08), s + 1, 0.2, 0, l2.darkened(0.05), 0.4, 0.9)
	m.blob(&"Foliage", Vector3(-0.6, 4.2, -0.4), Vector3(1.0, 1.0, 1.0), l1.lightened(0.05), s + 2, 0.2, 0, l2, 0.4, 0.9)
	return m


static func mesh_palm(variant: int) -> ContentMesh:
	var m := ContentMesh.new()
	var bark := Color("#8a6a4a")
	var ring := Color("#6b4f36")
	var lean := 0.9 + 0.25 * variant
	var segs := 8
	var seg_h := 0.95
	var top := Vector3.ZERO
	for i in segs:
		var t := float(i) / float(segs)
		var off := Vector3(lean * t * t, 0, 0)
		var base := Vector3(0, i * seg_h, 0) + off
		var r0 := 0.26 - 0.02 * i
		m.cyl(&"Palm", base, r0, r0 - 0.018, seg_h + 0.04, 7, bark if i % 2 == 0 else bark.darkened(0.06), false, false, true, 0.0 + 0.02 * i, 0.02 * (i + 1))
		m.cyl(&"Palm", base, r0 + 0.012, r0 + 0.012, 0.07, 7, ring, false, false, false, 0.0, 0.0)
		top = base + Vector3(0, seg_h, 0)
	var fronds := 11
	for i in fronds:
		var a := TAU * float(i) / float(fronds) + variant * 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := 2.9 + 0.5 * sin(i * 2.3)
		var up0 := 0.9 + 0.35 * sin(i * 1.7)
		var prev_c := top
		var prev_w := 0.05
		for k in range(1, 6):
			var t := float(k) / 5.0
			var c := top + dir * (length * t) + Vector3(0, up0 * sin(t * PI * 0.62) * 1.1 - t * t * 1.55, 0)
			var w := 0.62 * pow(sin(minf(t, 0.98) * PI), 0.55) + 0.03
			var g0 := Color("#2e6a3c").lerp(Color("#79ad4a"), t)
			var a0 := prev_c - side * prev_w
			var b0 := prev_c + side * prev_w
			var a1 := c - side * w
			var b1 := c + side * w
			var wt0 := 0.45 + 0.5 * (float(k - 1) / 5.0)
			var wt1 := 0.45 + 0.5 * t
			var nrm := (b0 - a0).cross(a1 - a0).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			m.quad(&"Palm", a0, b0, b1, a1, nrm, g0, Vector2.ZERO, Vector2.ONE, wt0)
			m.quad(&"Palm", a0, b0, b1, a1, -nrm, g0.darkened(0.15), Vector2.ZERO, Vector2.ONE, wt1)
			prev_c = c
			prev_w = w
	for i in 3:
		var ca := TAU * float(i) / 3.0
		m.blob(&"Palm", top + Vector3(cos(ca) * 0.22, -0.25, sin(ca) * 0.22), Vector3(0.14, 0.16, 0.14), Color("#6b4f36"), 300 + i, 0.1, 0, Color(0, 0, 0, 0), 0.6, 0.7)
	return m


static func mesh_tree_far(species: StringName) -> ContentMesh:
	var m := ContentMesh.new()
	match species:
		&"pine":
			m.cyl(&"Foliage", Vector3.ZERO, 0.25, 0.12, 4.0, 5, Color("#4a3426"), false, false, true, 0.0, 0.0)
			m.cyl(&"Foliage", Vector3(0, 1.4, 0), 2.0, 0.02, 7.0, 6, Color("#2f6a42"), false, true, false, 0.4, 1.0)
		&"palm":
			m.cyl(&"Palm", Vector3.ZERO, 0.24, 0.12, 7.6, 5, Color("#8a6a4a"), false, false, true, 0.0, 0.2)
			m.blob(&"Palm", Vector3(0.9, 7.6, 0), Vector3(2.6, 0.7, 2.6), Color("#3f8a46"), 7, 0.15, 0, Color("#79ad4a"), 0.6, 0.9)
		_:
			var leaf := Color("#4f8a4a") if species != &"birch" else Color("#86b04f")
			m.cyl(&"Foliage", Vector3.ZERO, 0.3, 0.18, 3.6, 5, Color("#5f4330") if species != &"birch" else Color("#e6e2d6"), false, false, true, 0.0, 0.0)
			m.blob(&"Foliage", Vector3(0, 4.8, 0), Vector3(2.6, 2.4, 2.6), leaf, 11, 0.2, 0, leaf.lightened(0.15), 0.5, 1.0)
	return m


static func mesh_bush(variant: int) -> ContentMesh:
	var m := ContentMesh.new()
	var l := Color("#3f7a46") if variant % 2 == 0 else Color("#5b8f3e")
	m.blob(&"Foliage", Vector3(0, 0.55, 0), Vector3(0.95, 0.7, 0.9), l, 400 + variant, 0.22, 1, l.lightened(0.14), 0.3, 0.8)
	m.blob(&"Foliage", Vector3(0.55, 0.4, 0.2), Vector3(0.6, 0.5, 0.6), l.darkened(0.08), 410 + variant, 0.22, 0, l.lightened(0.08), 0.3, 0.8)
	m.blob(&"Foliage", Vector3(-0.5, 0.38, -0.2), Vector3(0.55, 0.45, 0.55), l.lightened(0.04), 420 + variant, 0.22, 0, l.lightened(0.1), 0.3, 0.8)
	if variant % 3 == 1:
		for i in 5:
			m.blob(&"V", Vector3(sin(i * 2.4) * 0.6, 0.7 + 0.1 * float(i % 3), cos(i * 2.4) * 0.55), Vector3(0.07, 0.07, 0.07), Color("#e8795f"), 430 + i, 0.0, 0)
	return m


static func mesh_rock(variant: int) -> ContentMesh:
	var m := ContentMesh.new()
	var c := Color("#8a8579").lerp(Color("#6f6b62"), 0.25 * variant)
	m.blob(&"V", Vector3(0, 0.5, 0), Vector3(1.1, 0.75, 0.95), c, 500 + variant * 7, 0.26, 1, c.lightened(0.12), 0.0, 0.0)
	m.blob(&"V", Vector3(0.9, 0.25, 0.35), Vector3(0.5, 0.38, 0.45), c.darkened(0.06), 510 + variant, 0.25, 0)
	if variant == 2:
		m.blob(&"V", Vector3(-0.8, 0.3, -0.4), Vector3(0.55, 0.42, 0.5), c.lightened(0.05), 520, 0.25, 0)
	return m


static func mesh_grass() -> ContentMesh:
	var m := ContentMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 8:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.18
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(0.28, 0.6)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var tip := base + Vector3(0, h, 0) + lean
		var side := Vector3(-sin(a), 0, cos(a)) * 0.035
		var col := Color("#5d9a43").lerp(Color("#9cc15a"), rng.randf())
		var n := (side.cross(tip - base)).normalized()
		m.tri(&"Grass", base - side, base + side, tip, n, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.0)
		m.tri(&"Grass", base - side, base + side, tip, -n, col.darkened(0.1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.0)
		# alpha (sway weight) of the tip vertex cannot differ per vertex with tri(): the whole blade sways by its height weight
	return m


static func mesh_reed() -> ContentMesh:
	var m := ContentMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.3
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(1.1, 1.9)
		var lean := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var tip := base + Vector3(0, h, 0) + lean
		var side := Vector3(-sin(a), 0, cos(a)) * 0.03
		var col := Color("#8a9a5b").lerp(Color("#b2bf74"), rng.randf())
		var n := (side.cross(tip - base)).normalized()
		m.tri(&"Reed", base - side, base + side, tip, n, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.8)
		m.tri(&"Reed", base - side, base + side, tip, -n, col.darkened(0.1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.8)
		if i % 3 == 0:
			m.box(&"Reed", tip + Vector3(0, -0.1, 0), Vector3(0.05, 0.22, 0.05), Color("#6b4a2e"), 8, 0.9)
	return m


const GLB_VARIANTS := {
	&"oak": ["tree_oak_a", "tree_oak_b"], &"pine": ["tree_pine_a", "tree_pine_b"], &"birch": ["tree_birch"],
	&"palm": ["palm_a", "palm_b"], &"bush": ["bush_a", "bush_b", "bush_c"], &"rock": ["rock_a", "rock_b", "rock_c", "rock_d"],
}
const FOLIAGE_KIND := {&"oak": &"tree", &"pine": &"tree", &"birch": &"tree", &"palm": &"palm", &"bush": &"tree", &"rock": &""}

static var variant_count: Dictionary = {}     # species -> number of registered variants (nat_<sp>_0 .. n-1)


## Registers meshes for all species (+ variants + far LOD + extras). Blender GLBs when present, else code-built fallback (logged).
static func ensure_meshes(batch: ContentBatch) -> void:
	if ContentLib.has_mesh(&"nat_oak_0"):
		return
	var mats := _mats()
	var builders := {
		&"oak": mesh_oak, &"pine": mesh_pine, &"birch": mesh_birch, &"palm": mesh_palm, &"bush": mesh_bush, &"rock": mesh_rock,
	}
	variant_count.clear()
	for sp in builders:
		var n_glb := 0
		for file in GLB_VARIANTS[sp]:
			var key := StringName("nat_%s_%d" % [sp, n_glb])
			if ContentLib.register_glb_optional(key, "nature/" + String(file), [], FOLIAGE_KIND[sp]):
				n_glb += 1
		if n_glb > 0:
			variant_count[sp] = n_glb
			continue
		push_warning("NatureBuilder: no nature GLB for '%s' - using code-built FALLBACK mesh" % sp)
		var fb: Callable = builders[sp]
		for v in 3:
			var cm: ContentMesh = fb.call(v)
			ContentLib.put(StringName("nat_%s_%d" % [sp, v]), cm.to_mesh(mats), "fallback")
		variant_count[sp] = 3
	# far LOD per tree species: <first file>_lod.glb when present
	for sp in [&"oak", &"pine", &"birch", &"palm"]:
		var key := StringName("nat_%s_far" % sp)
		var first: String = String(GLB_VARIANTS[sp][0])
		if not ContentLib.register_glb_optional(key, "nature/" + first + "_lod", [], FOLIAGE_KIND[sp]):
			ContentLib.put(key, mesh_tree_far(sp).to_mesh(mats), "fallback")
	if not ContentLib.register_glb_optional(&"nat_grass", "nature/grass_tuft", [], &"grass"):
		ContentLib.put(&"nat_grass", mesh_grass().to_mesh(mats), "fallback")
	if not ContentLib.register_glb_optional(&"nat_reed", "nature/reeds", [], &"reed"):
		ContentLib.put(&"nat_reed", mesh_reed().to_mesh(mats), "fallback")
	# extras (optional, no fallback): flowers, logs, stumps, beach debris
	for ex in [[&"nat_flower", "flower_patch", &"grass"], [&"nat_log", "log", &"grass"], [&"nat_stump", "stump", &""], [&"nat_driftwood", "driftwood", &""], [&"nat_shell", "shell", &""]]:
		ContentLib.register_glb_optional(ex[0], "nature/" + String(ex[1]), [], ex[2])
	# LOD ranges
	for key in ContentLib.meshes:
		var s := String(key)
		if not s.begins_with("nat_"):
			continue
		if s.ends_with("_far"):
			batch.set_lod(key, FAR_BEGIN, FAR_END, 20.0, false)
		elif s.begins_with("nat_grass") or s.begins_with("nat_flower") or s.begins_with("nat_shell"):
			batch.set_lod(key, 0.0, 55.0, 10.0, false)
		elif s.begins_with("nat_reed"):
			batch.set_lod(key, 0.0, 110.0, 15.0, false)
		elif s.begins_with("nat_bush") or s.begins_with("nat_log") or s.begins_with("nat_stump") or s.begins_with("nat_driftwood"):
			batch.set_lod(key, 0.0, 110.0, 15.0, true)
		elif s.begins_with("nat_rock"):
			batch.set_lod(key, 0.0, 260.0, 20.0, true)
		else:
			batch.set_lod(key, 0.0, NEAR_END, 20.0, true)


# ---- placement ---------------------------------------------------------------------------------------------------------------------
static func _polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func _build_index(sidewalk := 3.0) -> AvoidIndex:
	var idx := AvoidIndex.new()
	for r in WorldLayout.roads:
		var pts: PackedVector2Array = r.get("points", PackedVector2Array())
		var half := float(r.get("width", 8.0)) * 0.5 + sidewalk   # + sidewalk
		for i in range(pts.size() - 1):
			idx.add_road(pts[i], pts[i + 1], half)
	for lot in WorldLayout.lots:
		var kind: StringName = lot.get("kind", &"empty")
		if kind in [&"park", &"empty"]:
			continue
		idx.add_rect(lot["rect"])
	for p in WorldLayout.piers:
		idx.add_rect((p as Dictionary)["rect"])
	return idx


static func _add_tree(batch: ContentBatch, idx: AvoidIndex, species: StringName, pos: Vector3, rng: RandomNumberGenerator, scale_mul := 1.0, is_street := false) -> void:
	var v := rng.randi() % int(variant_count.get(species, 3))
	var key := StringName("nat_%s_%d" % [species, v])
	var s := rng.randf_range(0.8, 1.3) * scale_mul
	var yaw := rng.randf() * TAU
	var tilt := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
	if species == &"palm":
		tilt = Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
	var b := Basis(Vector3.UP, yaw) * Basis.from_euler(tilt) * Basis.from_scale(Vector3(s, s * rng.randf_range(0.92, 1.12), s))
	var xf := Transform3D(b, pos)
	var custom := Color(rng.randf(), rng.randf(), 0.0, 0.0)
	batch.add(key, xf, custom)
	var far_key := StringName("nat_%s_far" % species)
	if ContentLib.has_mesh(far_key):
		batch.add(far_key, xf, custom)
	stats["trees"] += 1
	if is_street:
		stats["street"] += 1
		placed_street_trees.append(pos)
	else:
		placed_trees.append(pos)
	# trunk collider only close to roads / paths (or street trees)
	if stats["colliders"] < MAX_TRUNK_COLLIDERS:
		var near_road := is_street or idx.road_edge_dist(Vector2(pos.x, pos.z)) < 12.0
		if near_road:
			var r := (0.22 if species == &"palm" else (0.3 if species != &"birch" else 0.2)) * s
			batch.add_cyl_collider(pos, r, 3.2 * s, &"wood")
			stats["colliders"] += 1


static func _zone_species(kind: StringName, rng: RandomNumberGenerator) -> StringName:
	var r := rng.randf()
	match kind:
		&"forest":
			return &"pine" if r < 0.55 else (&"oak" if r < 0.8 else &"birch")
		&"hills":
			return &"pine" if r < 0.6 else (&"oak" if r < 0.85 else &"birch")
		&"beach_palms":
			return &"palm"
		&"roadside":
			return &"oak" if r < 0.5 else (&"birch" if r < 0.8 else &"pine")
		_:   # park
			return &"oak" if r < 0.5 else (&"birch" if r < 0.8 else &"pine")


static func build(batch: ContentBatch) -> void:
	ensure_meshes(batch)
	var idx := _build_index()
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654
	var tufts_left := MAX_TUFTS
	# --- zones
	for zone in WorldLayout.nature_zones:
		var poly: PackedVector2Array = zone.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var kind: StringName = zone.get("kind", &"park")
		var density := clampf(float(zone.get("density", 0.4)), 0.02, 1.0)
		var kind_mul := 1.0
		match kind:
			&"forest":
				kind_mul = 1.6
			&"hills":
				kind_mul = 0.9
			&"beach_palms":
				kind_mul = 0.5
			&"roadside":
				kind_mul = 0.7
			_:
				kind_mul = 0.55
		var spacing := sqrt(100.0 / maxf(density * kind_mul, 0.02))
		spacing = clampf(spacing, 4.5, 40.0)
		var bb := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			bb = bb.expand(p)
		var x := bb.position.x
		while x < bb.end.x:
			var z := bb.position.y
			while z < bb.end.y:
				if int(stats["trees"]) >= MAX_TREES:
					break
				var jp := Vector2(x + rng.randf_range(-0.45, 0.45) * spacing, z + rng.randf_range(-0.45, 0.45) * spacing)
				z += spacing
				if not Geometry2D.is_point_in_polygon(jp, poly):
					continue
				if WorldLayout.is_water(jp.x, jp.y):
					continue
				var ed := idx.road_edge_dist(jp)
				if ed < 1.5 or idx.in_rect(jp, 1.5):
					continue
				var y := WorldLayout.terrain_height(jp.x, jp.y)
				var pos := Vector3(jp.x, y - 0.05, jp.y)
				var roll := rng.randf()
				if roll < 0.62:
					_add_tree(batch, idx, _zone_species(kind, rng), pos, rng)
				elif roll < 0.82:
					var bk := StringName("nat_bush_%d" % (rng.randi() % int(variant_count.get(&"bush", 3))))
					var bs := rng.randf_range(0.8, 1.5)
					batch.add(bk, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(bs, bs, bs)), pos), Color(rng.randf(), rng.randf(), 0, 0))
					stats["bushes"] += 1
				elif roll < 0.9 and kind in [&"hills", &"forest"]:
					var rk := StringName("nat_rock_%d" % (rng.randi() % int(variant_count.get(&"rock", 3))))
					var rs := rng.randf_range(0.7, 2.2)
					batch.add(rk, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(rs, rs * rng.randf_range(0.7, 1.1), rs)), pos - Vector3(0, 0.1, 0)), Color(rng.randf(), 0, 0, 0))
					stats["rocks"] += 1
					if rs > 1.1 and ed < 14.0:
						batch.add_cyl_collider(pos, 0.9 * rs, 1.2 * rs, &"concrete")
				# tufts around every cell (cheap, short range)
				if tufts_left > 0 and kind != &"beach_palms":
					var n := 2 + (rng.randi() % 3)
					for t in n:
						var tp := Vector2(jp.x + rng.randf_range(-spacing * 0.5, spacing * 0.5), jp.y + rng.randf_range(-spacing * 0.5, spacing * 0.5))
						if not Geometry2D.is_point_in_polygon(tp, poly) or WorldLayout.is_water(tp.x, tp.y) or idx.road_edge_dist(tp) < 0.8 or idx.in_rect(tp, 1.0):
							continue
						var ts := rng.randf_range(0.8, 1.6)
						batch.add(&"nat_grass", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(ts, ts, ts)), Vector3(tp.x, WorldLayout.terrain_height(tp.x, tp.y) - 0.02, tp.y)), Color(rng.randf(), rng.randf(), 0, 0))
						tufts_left -= 1
						stats["tufts"] += 1
				# occasional scenery: flower patches (parks / roadsides), logs + stumps (forest / hills), driftwood + shells (beach)
				var er := rng.randf()
				if er < 0.07:
					var ek: StringName = &""
					match kind:
						&"park", &"roadside":
							ek = &"nat_flower"
						&"forest", &"hills":
							ek = &"nat_log" if rng.randf() < 0.5 else &"nat_stump"
						&"beach_palms":
							ek = &"nat_driftwood" if rng.randf() < 0.4 else &"nat_shell"
					if ek != &"" and ContentLib.has_mesh(ek):
						var es := rng.randf_range(0.8, 1.4)
						batch.add(ek, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(es, es, es)), pos + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))), Color(rng.randf(), rng.randf(), 0, 0))
						stats["extras"] = int(stats.get("extras", 0)) + 1
			x += spacing
	# --- street trees from the furniture list (never on the roadway itself)
	var roadway := _build_index(0.0)
	for item in WorldLayout.furniture:
		var kind: StringName = item.get("kind", &"")
		if kind != &"palm" and kind != &"tree_street":
			continue
		var pos: Vector3 = item.get("pos", Vector3.ZERO)
		if roadway.road_edge_dist(Vector2(pos.x, pos.z)) < 0.2:
			continue
		rng.seed = hash(Vector3i(int(pos.x * 10), int(pos.y * 10), int(pos.z * 10))) + 5
		if kind == &"palm":
			_add_tree(batch, idx, &"palm", pos, rng, 1.0, true)
		else:
			_add_tree(batch, idx, &"oak" if rng.randf() < 0.65 else &"birch", pos, rng, 0.8, true)
	# --- shoreline reeds
	_scatter_reeds(batch, idx, rng)


static func _scatter_reeds(batch: ContentBatch, idx: AvoidIndex, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 220 and tries < 6000:
		tries += 1
		var x := rng.randf_range(-GC.WORLD_HALF, GC.WORLD_HALF)
		var z := rng.randf_range(-GC.WORLD_HALF, GC.WORLD_HALF)
		if WorldLayout.is_water(x, z):
			continue
		var wet := false
		for d in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
			if WorldLayout.is_water(x + d.x, z + d.y):
				wet = true
				break
		if not wet or idx.road_edge_dist(Vector2(x, z)) < 2.0 or idx.in_rect(Vector2(x, z), 1.5):
			continue
		var y := WorldLayout.terrain_height(x, z)
		var s := rng.randf_range(0.8, 1.5)
		batch.add(&"nat_reed", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s, s)), Vector3(x, y - 0.05, z)), Color(rng.randf(), rng.randf(), 0, 0))
		placed += 1
		stats["reeds"] += 1
