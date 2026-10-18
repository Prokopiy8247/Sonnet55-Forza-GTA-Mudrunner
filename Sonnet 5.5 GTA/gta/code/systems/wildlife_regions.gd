class_name WildlifeRegions
extends RefCounted
## Region classification for the wildlife system: which kind of habitat is at (x, z), tree grid for steering, the pasture rectangle
## (found at boot on tree-free flat ground, fenced by WildlifeSystem) and bird perches (pier decks, bollards, benches).
## Pure data + static queries; build() is idempotent and called once the world exists.

const TREE_CELL := 8.0

static var built := false
static var zone_rects: Array = []          # [{rect: Rect2, kind: StringName}]
static var pasture: Rect2 = Rect2()
static var has_pasture := false
static var perches: Array[Vector3] = []     # world positions (feet) where gulls / crows may stand
static var _trees: Dictionary = {}          # Vector2i -> PackedVector2Array of tree xz
static var _species_regions: Dictionary = {}   # species -> {region: true}
static var _tree_count := 0


static func build() -> void:
	if built:
		return
	built = true
	zone_rects.clear()
	for z in WorldLayout.nature_zones:
		var poly: PackedVector2Array = z["poly"]
		if poly.size() < 3:
			continue
		var mn := poly[0]
		var mx := poly[0]
		for p in poly:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		zone_rects.append({"rect": Rect2(mn, mx - mn), "kind": z["kind"]})
	# which species may live in which region (from the spawn tables)
	_species_regions.clear()
	for region in WildlifeDefs.REGION_TABLE:
		for row in WildlifeDefs.REGION_TABLE[region]["rows"]:
			var sp: StringName = row["sp"]
			if not _species_regions.has(sp):
				_species_regions[sp] = {}
			_species_regions[sp][region] = true
	if _species_regions.has(&"deer"):
		_species_regions[&"deer_buck"] = _species_regions[&"deer"]
	_build_tree_grid()
	_find_pasture()
	_build_perches()


static func _build_tree_grid() -> void:
	_trees.clear()
	_tree_count = 0
	var arr: PackedVector3Array = NatureBuilder.placed_trees
	for t in arr:
		var key := Vector2i(int(floor(t.x / TREE_CELL)), int(floor(t.z / TREE_CELL)))
		if not _trees.has(key):
			_trees[key] = PackedVector2Array()
		(_trees[key] as PackedVector2Array).append(Vector2(t.x, t.z))
		_tree_count += 1


static func tree_count() -> int:
	return _tree_count


## True when a tree trunk is within r metres of (x, z).
static func tree_near(x: float, z: float, r: float) -> bool:
	var cx := int(floor(x / TREE_CELL))
	var cz := int(floor(z / TREE_CELL))
	var r2 := r * r
	for ix in range(cx - 1, cx + 2):
		for iz in range(cz - 1, cz + 2):
			var arr = _trees.get(Vector2i(ix, iz), null)
			if arr == null:
				continue
			for t in (arr as PackedVector2Array):
				var dx := t.x - x
				var dz := t.y - z
				if dx * dx + dz * dz < r2:
					return true
	return false


static func trees_in_rect(r: Rect2) -> int:
	var n := 0
	var cx0 := int(floor(r.position.x / TREE_CELL))
	var cx1 := int(floor(r.end.x / TREE_CELL))
	var cz0 := int(floor(r.position.y / TREE_CELL))
	var cz1 := int(floor(r.end.y / TREE_CELL))
	for ix in range(cx0, cx1 + 1):
		for iz in range(cz0, cz1 + 1):
			var arr = _trees.get(Vector2i(ix, iz), null)
			if arr == null:
				continue
			for t in (arr as PackedVector2Array):
				if r.has_point(t):
					n += 1
	return n


# ---- classification ------------------------------------------------------------------------------------------------
## Habitat id at (x, z): &"pasture" &"hills" &"woods" &"park" &"beach" &"harbour" &"industrial" &"residential" or &"" (water, downtown, airport).
static func classify(x: float, z: float) -> StringName:
	if has_pasture and pasture.has_point(Vector2(x, z)):
		return &"pasture"
	var h := WorldLayout.terrain_height(x, z)
	if h < GC.WATER_LEVEL:
		if WorldLayout.on_pier(x, z):
			return &"harbour" if x < -100.0 else &"beach"
		return &""
	var best_kind := &""
	for zr in zone_rects:
		if (zr["rect"] as Rect2).has_point(Vector2(x, z)):
			var k: StringName = zr["kind"]
			# hills win over forests / parks where they overlap
			if best_kind == &"" or k == &"hills":
				best_kind = k
	match best_kind:
		&"park":
			return &"park"
		&"hills":
			return &"hills"
		&"forest":
			return &"woods"
		&"beach_palms":
			return &"beach"
		&"roadside":
			return &"industrial"
	var d := WorldLayout.district_at(x, z)
	match d:
		GC.D_BEACH:
			return &"beach"
		GC.D_WATERFRONT:
			return &"harbour"
		GC.D_INDUSTRIAL:
			return &"industrial"
		GC.D_RESIDENTIAL:
			return &"residential"
		GC.D_PARK:
			return &"hills" if x > 55.0 and z < -100.0 else &"woods"
		GC.D_SEA:
			return &""
	return &""


## May a species of this id live in the habitat? (derived from the region spawn tables)
static func species_ok(sp: StringName, region: StringName) -> bool:
	if region == &"":
		return false
	var m = _species_regions.get(sp, null)
	return m != null and m.has(region)


## Species that keep off roads when wandering (cats / dogs / birds do not mind).
static func is_wild(sp: StringName) -> bool:
	return sp == &"deer" or sp == &"deer_buck" or sp == &"boar" or sp == &"coyote" or sp == &"rabbit" or sp == &"cow" or sp == &"horse"


static func is_natural(region: StringName) -> bool:
	return region == &"hills" or region == &"woods" or region == &"park" or region == &"pasture"


# ---- pasture ------------------------------------------------------------------------------------------------------------
static func _find_pasture() -> void:
	has_pasture = false
	var sizes: Array[Vector2] = [Vector2(46.0, 34.0), Vector2(38.0, 28.0), Vector2(30.0, 24.0)]
	for size in sizes:
		var best_score := 1e9
		var best := Rect2()
		var gx := -96.0
		while gx < 296.0 - size.x:
			var gz := -296.0
			while gz < -100.0 - size.y:
				var r := Rect2(gx, gz, size.x, size.y)
				var s := _pasture_score(r)
				if s < best_score:
					best_score = s
					best = r
				gz += 6.0
			gx += 6.0
		if best_score < 1e8:
			pasture = best
			has_pasture = true
			print("[Wildlife] pasture %s (score %.1f, %d trees nearby)" % [str(pasture), best_score, trees_in_rect(pasture.grow(6.0))])
			return
	print("[Wildlife] no tree-free flat ground for a pasture - cows skipped")


static func _pasture_score(r: Rect2) -> float:
	# must be free of trees (incl. a 5 m margin), roads, water, steep ground, and far from landmarks
	if trees_in_rect(r.grow(2.5)) > 1:
		return 1e9
	var hmin := 1e9
	var hmax := -1e9
	var sx := 6
	var sz := 5
	for ix in sx + 1:
		for iz in sz + 1:
			var x := r.position.x + r.size.x * float(ix) / float(sx)
			var z := r.position.y + r.size.y * float(iz) / float(sz)
			var h := WorldLayout.terrain_height(x, z)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			if not WorldLayout.road_at(x, z, 7.0).is_empty():
				return 1e9
	if hmin < -0.3 or hmax - hmin > 2.2:
		return 1e9
	var c := r.get_center()
	for loc_id in WorldLayout.locations:
		var loc: Dictionary = WorldLayout.locations[loc_id]
		var lp: Vector3 = loc["pos"]
		if Vector2(lp.x, lp.z).distance_to(c) < float(loc.get("radius", 6.0)) + maxf(r.size.x, r.size.y) * 0.7 and loc_id != &"park_center":
			return 1e9
	for lot in WorldLayout.lots:
		var lr: Rect2 = lot["rect"]
		if lot["kind"] != &"park" and lot["kind"] != &"empty" and lr.grow(4.0).intersects(r):
			return 1e9
	# prefer the NE foothills (close to x 110, z -140), a flat ground and few trees around
	return c.distance_to(Vector2(110.0, -140.0)) + (hmax - hmin) * 8.0 + float(trees_in_rect(r.grow(14.0))) * 0.5


# ---- perches --------------------------------------------------------------------------------------------------------------
static func _build_perches() -> void:
	perches.clear()
	for f in WorldLayout.furniture:
		var k: StringName = f["kind"]
		if k == &"bollard" and f["pos"].z > 150.0:
			perches.append((f["pos"] as Vector3) + Vector3(0.0, 0.62, 0.0))
		elif k == &"bench" and f["pos"].z > 130.0:
			perches.append((f["pos"] as Vector3) + Vector3(0.0, 0.55, 0.0))
	# pier decks: points along both long edges and on the tip
	for p in WorldLayout.piers:
		if bool(p.get("finger", false)):
			continue
		var r: Rect2 = p["rect"]
		var y: float = float(p["height"]) + 0.05
		var n := int(maxf(r.size.y, r.size.x) / 5.0)
		for i in n + 1:
			var t := float(i) / float(maxi(n, 1))
			perches.append(Vector3(r.position.x + 0.7, y, r.position.y + r.size.y * t))
			perches.append(Vector3(r.end.x - 0.7, y, r.position.y + r.size.y * t))
		perches.append(Vector3(r.get_center().x, y, r.end.y - 0.5))
	# beach sand patches
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 16:
		var x := rng.randf_range(-90.0, 70.0)
		var z := rng.randf_range(160.0, 172.0)
		var h := WorldLayout.terrain_height(x, z)
		if h > 0.1:
			perches.append(Vector3(x, h, z))


static func nearest_perch(pos: Vector3, max_d: float, rng: RandomNumberGenerator, avoid: Array = []) -> Vector3:
	var cands: Array[Vector3] = []
	for p in perches:
		var d := Util.dist_xz(p, pos)
		if d < max_d and d > 4.0:
			cands.append(p)
	if cands.is_empty():
		return Vector3.INF
	for tries in 6:
		var c: Vector3 = cands[rng.randi() % cands.size()]
		var ok := true
		for a in avoid:
			if Util.dist_xz(a, c) < 1.0:
				ok = false
				break
		if ok:
			return c
	return Vector3.INF
