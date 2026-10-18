class_name LayoutLots
extends RefCounted
## Fills every city block with building lots (WorldLayout.lots) and ground pieces (WorldLayout lot["ground"] / LayoutLots.grounds).
## Downtown / industrial / airport / harbour are laid out explicitly block by block (hero landmark lots included), the residential
## streets are filled by a frontage algorithm. Lots are axis aligned; `yaw` (Util convention, multiples of 90 deg) points the front
## at the street.

static var grounds: Array = []        # [{"key": "parking"|"plaza"|"yard"|"lawn", "rect": Rect2, "id": lot id}]
static var _next_id := 0
static var _rects: Array = []         # placed lot rects (Rect2) for overlap tests
static var _rects_grid: Dictionary = {}
static var _road_pts: Array = []      # [Vector2 pos, float clearance]
static var _road_grid: Dictionary = {}
static var _rng := RandomNumberGenerator.new()
static var landmark_lots: Dictionary = {}   # landmark id -> lot dict
static var reject: Dictionary = {}
static var _cur_edge := ""

const DX := [-105.0, -35.0, 35.0, 105.0]
const DZ := [-90.0, -20.0, 50.0, 120.0]


static func face_yaw(face: Vector2) -> float:
	return Util.dir_to_yaw(Vector3(face.x, 0.0, face.y))


static func _face_for(side: String) -> Vector2:
	match side:
		"n":
			return Vector2(0, -1)
		"s":
			return Vector2(0, 1)
		"e":
			return Vector2(1, 0)
	return Vector2(-1, 0)


static func build() -> void:
	WorldLayout.lots = []
	WorldLayout.building_footprints = []
	grounds = []
	landmark_lots = {}
	reject = {}
	_next_id = 0
	_rects = []
	_rects_grid = {}
	_rng.seed = 424242
	_build_road_clearance()
	_downtown()
	_industrial()
	_airport()
	_harbor()
	_residential()
	_park_lots()
	_footprints()
	print("[LayoutLots] lots=", WorldLayout.lots.size())


# ---- low level ------------------------------------------------------------------------------------------------------------
## World-fill: tags lot `id` as the site of a complete hero building (buildings/<hero>.glb, placed by FillBuilder; kit building when the GLB is missing).
static func _hero(id: int, hero: String, height: float = -1.0) -> void:
	var lot: Dictionary = WorldLayout.lots[id]
	lot["hero"] = hero
	if height > 0.0:
		lot["height"] = height


static func _floors_height(kind: StringName, floors: int) -> float:
	match kind:
		&"office", &"apartment", &"shop":
			return float(floors) * 3.6 + 1.6
		&"house":
			return float(floors) * 3.0 + 3.0
		&"warehouse", &"factory":
			return float(floors) * 4.5 + 1.0
		&"hangar":
			return 10.5
	return float(floors) * 3.6


static func _add(rect: Rect2, side: String, kind: StringName, district: StringName, floors: int = 1, landmark: StringName = &"", ground: String = "", palette: int = -1) -> int:
	var face := _face_for(side)
	var id := _next_id
	_next_id += 1
	var pal := palette if palette >= 0 else _rng.randi_range(0, 3)
	var lot := {
		"id": id, "rect": rect, "yaw": face_yaw(face), "district": district, "kind": kind, "landmark": landmark,
		"floors": floors, "height": _floors_height(kind, floors), "palette": pal, "side": side, "ground": ground,
	}
	WorldLayout.lots.append(lot)
	_rects.append(rect)
	_hash_rect(rect, _rects.size() - 1)
	if landmark != &"":
		landmark_lots[landmark] = lot
	if ground != "":
		grounds.append({"key": ground, "rect": rect, "id": id})
	return id


static func _hash_rect(r: Rect2, idx: int) -> void:
	for gx in range(int(floor(r.position.x / 20.0)), int(floor(r.end.x / 20.0)) + 1):
		for gz in range(int(floor(r.position.y / 20.0)), int(floor(r.end.y / 20.0)) + 1):
			var k := Vector2i(gx, gz)
			if not _rects_grid.has(k):
				_rects_grid[k] = []
			(_rects_grid[k] as Array).append(idx)


static func _overlaps_lots(r: Rect2, margin: float) -> bool:
	var g := r.grow(margin)
	for gx in range(int(floor(g.position.x / 20.0)), int(floor(g.end.x / 20.0)) + 1):
		for gz in range(int(floor(g.position.y / 20.0)), int(floor(g.end.y / 20.0)) + 1):
			for idx in _rects_grid.get(Vector2i(gx, gz), []):
				if (_rects[idx] as Rect2).intersects(g):
					return true
	return false


static func _build_road_clearance() -> void:
	_road_pts = []
	_road_grid = {}
	for e in LayoutRoadNet.edges:
		var rs := LayoutGeo.resample(e["pts"], 3.0)
		var clear := float(e["hw"]) + float(e["sw"]) + 0.3
		for p in rs:
			_road_add(p, clear)
	for id in LayoutRoadNet.node_ids:
		var n: Dictionary = LayoutRoadNet.nodes[id]
		var m := 0.0
		for a in n["arms"]:
			m = maxf(m, float(a["trim"]) + 1.0)
			m = maxf(m, float(a["hw"]) + float(a["sw"]))
		_road_add(n["pos"], m + 3.5)


static func _road_add(p: Vector2, clear: float) -> void:
	var idx := _road_pts.size()
	_road_pts.append([p, clear])
	var k := Vector2i(int(floor(p.x / 16.0)), int(floor(p.y / 16.0)))
	if not _road_grid.has(k):
		_road_grid[k] = []
	(_road_grid[k] as Array).append(idx)


static func _hits_road(r: Rect2) -> bool:
	var g := r.grow(24.0)
	for gx in range(int(floor(g.position.x / 16.0)), int(floor(g.end.x / 16.0)) + 1):
		for gz in range(int(floor(g.position.y / 16.0)), int(floor(g.end.y / 16.0)) + 1):
			for idx in _road_grid.get(Vector2i(gx, gz), []):
				var rp: Array = _road_pts[idx]
				var p: Vector2 = rp[0]
				var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
				var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
				if dx * dx + dz * dz < float(rp[1]) * float(rp[1]):
					return true
	return false


# ---- downtown -----------------------------------------------------------------------------------------------------------------
static func _off(line_idx: int) -> float:
	return 10.8 if (line_idx == 0 or line_idx == 3) else 7.3


static func _block(c: int, r: int) -> Rect2:
	var x0: float = DX[c] + _off(c)
	var x1: float = DX[c + 1] - _off(c + 1)
	var z0: float = DZ[r] + _off(r)
	var z1: float = DZ[r + 1] - _off(r + 1)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


static func _downtown() -> void:
	var D := GC.D_DOWNTOWN
	# (0,0) police station + parking
	var b := _block(0, 0)
	_add(Rect2(b.position.x, b.position.y, b.size.x, 30.0), "n", &"landmark", D, 4, &"police_station")
	_add(Rect2(b.position.x, b.position.y + 31.0, b.size.x, b.size.y - 31.0), "s", &"empty", D, 1, &"", "parking")
	# (1,0) gas station + shops (alley Gull at z=-55 splits the block)
	b = _block(1, 0)
	_add(Rect2(b.position.x, b.position.y, 32.0, 21.7), "n", &"landmark", D, 1, &"gas_station")
	_add(Rect2(b.position.x + 32.5, b.position.y, b.size.x - 32.5, 21.7), "n", &"shop", D, 3)
	_add(Rect2(b.position.x, -52.4, 27.4, 25.1), "s", &"shop", D, 4)
	_add(Rect2(b.position.x + 27.9, -52.4, b.size.x - 27.9, 25.1), "s", &"shop", D, 3)
	# (2,0) office towers
	b = _block(2, 0)
	var hw := b.size.x * 0.5
	var hh := b.size.y * 0.5
	_hero(_add(Rect2(b.position.x, b.position.y, b.size.x, 28.0), "n", &"office", D, 22), "tower_b", 90.0)
	_add(Rect2(b.position.x, b.position.y + 28.4, hw - 0.4, b.size.y - 28.4), "w", &"office", D, 11)
	_add(Rect2(b.position.x + hw + 0.4, b.position.y + 28.4, hw - 0.4, b.size.y - 28.4), "e", &"office", D, 9)
	# (0,1) shop row either side of alley Lantern (x=-70)
	b = _block(0, 1)
	var wx0 := b.position.x
	var wx1 := -72.55
	var ex0 := -67.45
	var ex1 := b.end.x
	_add(Rect2(wx0, b.position.y, wx1 - wx0, 18.0), "n", &"landmark", D, 2, &"weapon_shop")
	_add(Rect2(wx0, b.position.y + 18.5, wx1 - wx0, 17.5), "w", &"landmark", D, 2, &"barber")
	_add(Rect2(wx0, b.position.y + 36.5, wx1 - wx0, b.size.y - 36.5), "w", &"apartment", D, 6)
	_add(Rect2(ex0, b.position.y, ex1 - ex0, 18.0), "n", &"landmark", D, 2, &"clothing_store")
	_add(Rect2(ex0, b.position.y + 18.5, ex1 - ex0, 18.5), "e", &"shop", D, 3)
	_add(Rect2(ex0, b.position.y + 37.5, ex1 - ex0, b.size.y - 37.5), "e", &"apartment", D, 7)
	# (1,1) central plaza + tower (helipad_downtown on the tower)
	b = _block(1, 1)
	_hero(_add(Rect2(b.position.x + 9.0, b.position.y, b.size.x - 18.0, 34.0), "n", &"office", D, 28, &"", "", 1), "tower_a", 110.2)
	grounds.append({"key": "plaza", "rect": b, "id": -1})
	# (2,1) apartments + shops, taxi stand on the ring side
	b = _block(2, 1)
	hw = b.size.x * 0.5
	hh = b.size.y * 0.5
	_add(Rect2(b.position.x, b.position.y, hw - 0.4, hh - 0.4), "n", &"shop", D, 4)
	_hero(_add(Rect2(b.position.x + hw + 0.4, b.position.y, hw - 0.4, hh - 0.4), "n", &"office", D, 15), "tower_c", 75.3)
	_add(Rect2(b.position.x, b.position.y + hh + 0.4, hw - 0.4, hh - 0.4), "s", &"apartment", D, 6)
	_add(Rect2(b.position.x + hw + 0.4, b.position.y + hh + 0.4, hw - 0.4, hh - 0.4), "e", &"office", D, 10)
	# (0,2) train station A + apartments
	b = _block(0, 2)
	_add(Rect2(b.position.x, b.position.y, b.size.x, 24.0), "n", &"landmark", D, 2, &"train_station_a")
	hw = b.size.x * 0.5
	_hero(_add(Rect2(b.position.x, b.position.y + 24.5, hw - 0.4, b.size.y - 24.5), "s", &"office", D, 14), "hotel", 59.8)
	_add(Rect2(b.position.x + hw + 0.4, b.position.y + 24.5, hw - 0.4, b.size.y - 24.5), "s", &"shop", D, 3)
	# (1,2) dealership (north half) + shops south of alley Anchor (z=85)
	b = _block(1, 2)
	_add(Rect2(b.position.x, b.position.y, b.size.x, 12.0), "n", &"empty", D, 1, &"", "parking")
	_add(Rect2(b.position.x, b.position.y + 12.5, b.size.x, 12.6), "n", &"landmark", D, 2, &"dealer_lot")
	_add(Rect2(b.position.x, 87.6, 27.4, b.end.y - 87.6), "s", &"shop", D, 3)
	_add(Rect2(b.position.x + 27.9, 87.6, b.size.x - 27.9, b.end.y - 87.6), "s", &"apartment", D, 5)
	# (2,2) hospital
	b = _block(2, 2)
	_add(Rect2(b.position.x, b.position.y, b.size.x, 40.0), "e", &"landmark", D, 6, &"hospital")
	_add(Rect2(b.position.x, b.position.y + 40.5, b.size.x, b.size.y - 40.5), "e", &"empty", D, 1, &"", "parking")


# ---- industrial ---------------------------------------------------------------------------------------------------------------
static func _industrial() -> void:
	var I := GC.D_INDUSTRIAL
	# x columns: ring side .. Eastern Link (190), Link .. Depot Street (250), east of Depot
	var c1 := Vector2(115.8, 179.2)
	var c2 := Vector2(200.8, 243.5)
	var c3 := Vector2(256.5, 295.5)
	# z rows: north (Ridge Rd z=-90 .. Foundry z=-20), middle (Foundry .. Industrial Ave z=50), south (Ind Ave .. Terminal Rd z=85)
	var r0 := Vector2(-79.2, -26.5)
	var r1 := Vector2(-13.5, 43.5)
	var r2 := Vector2(56.5, 77.7)
	# north row
	_hero(_add(Rect2(c1.x, r0.x, 34.0, 52.7), "s", &"warehouse", I, 2), "warehouse_b", 9.4)
	_add(Rect2(c1.x + 34.5, r0.x, c1.y - c1.x - 34.5, 52.7), "s", &"factory", I, 2)
	_hero(_add(Rect2(c2.x, r0.x, c2.y - c2.x, 52.7), "w", &"warehouse", I, 2), "warehouse_a", 11.5)
	_hero(_add(Rect2(c3.x, r0.x, c3.y - c3.x, 52.7), "w", &"factory", I, 2), "factory", 36.2)
	# middle row
	_add(Rect2(c1.x, r1.x, 38.0, 24.0), "n", &"landmark", I, 1, &"garage_shop")
	_add(Rect2(c1.x, r1.x + 24.5, 38.0, r1.y - r1.x - 24.5), "s", &"warehouse", I, 1)
	_add(Rect2(c1.x + 38.5, r1.x, c1.y - c1.x - 38.5, r1.y - r1.x), "s", &"factory", I, 2)
	_add(Rect2(c2.x, r1.x, c2.y - c2.x, 30.0), "n", &"warehouse", I, 2)
	_hero(_add(Rect2(c2.x, r1.x + 30.5, c2.y - c2.x, r1.y - r1.x - 30.5), "s", &"empty", I, 1, &"", "yard"), "silo_cluster", 42.3)
	_add(Rect2(c3.x, r1.x, c3.y - c3.x, 34.0), "w", &"landmark", I, 1, &"shooting_range")
	_add(Rect2(c3.x, r1.x + 34.5, c3.y - c3.x, r1.y - r1.x - 34.5), "w", &"warehouse", I, 1)
	# south row (airport car park + service)
	_add(Rect2(c1.x, r2.x, c1.y - c1.x, r2.y - r2.x), "s", &"empty", I, 1, &"", "parking")
	_add(Rect2(c2.x, r2.x, c2.y - c2.x, r2.y - r2.x), "n", &"landmark", I, 1, &"train_station_b")
	_add(Rect2(c3.x, r2.x, c3.y - c3.x, r2.y - r2.x), "s", &"empty", I, 1, &"", "yard")


# ---- airport ---------------------------------------------------------------------------------------------------------------------
static func _airport() -> void:
	var A := GC.D_AIRPORT
	var z0 := 92.4
	# hero hangars: front edge at z = 115.9 (the stunt ramp of jump 2 starts at z = 122.5)
	_hero(_add(Rect2(128.0, z0, 38.0, 23.5), "s", &"hangar", A, 1), "hangar_a", 12.4)
	_hero(_add(Rect2(168.0, z0, 32.0, 23.5), "s", &"hangar", A, 1), "hangar_b", 12.0)
	_add(Rect2(204.0, z0, 24.0, 17.0), "s", &"hangar", A, 1)
	_add(Rect2(231.0, z0, 38.0, 17.0), "s", &"landmark", A, 3, &"airport_terminal")
	_add(Rect2(273.0, z0, 15.0, 15.0), "s", &"landmark", A, 1, &"airport_tower")


# ---- harbour -----------------------------------------------------------------------------------------------------------------------
static func _harbor() -> void:
	var W := GC.D_WATERFRONT
	# north row between Harbor Road (z=120) and Elm Street: warehouses for z >= 90, residential apartments above
	_add(Rect2(-254.7, 92.0, 62.4, 20.0), "s", &"warehouse", W, 2)
	_add(Rect2(-177.7, 92.0, 61.0, 20.0), "s", &"warehouse", W, 2)
	# narrow strip between Harbor Road and Seaview Drive
	var xs := [Vector2(-254.7, -232.2), Vector2(-217.8, -192.3), Vector2(-177.7, -153.2), Vector2(-138.8, -116.0)]
	for sp in xs:
		var s: Vector2 = sp
		_add(Rect2(s.x, 128.0, s.y - s.x, 12.5), "n", &"warehouse", W, 1)
	# quay row south of Seaview Drive
	_add(Rect2(-254.7, 155.8, 23.0, 30.0), "n", &"warehouse", W, 1)
	_add(Rect2(-217.8, 155.8, 25.5, 30.0), "n", &"empty", W, 1)   # crane yard (FillBuilder: dock crane + containers)
	_add(Rect2(-177.7, 155.8, 24.5, 30.0), "n", &"landmark", W, 2, &"marina_office")
	_add(Rect2(-138.8, 155.8, 22.0, 18.0), "n", &"landmark", W, 2, &"scuba_shop")
	_add(Rect2(-138.8, 174.2, 22.0, 12.0), "n", &"empty", W, 1, &"", "yard")


# ---- residential (frontage filler) ------------------------------------------------------------------------------------------
static func _residential() -> void:
	var R := GC.D_RESIDENTIAL
	# reserved rects (parks, safehouse) first
	_add(Rect2(-252.0, -80.0, 56.0, 50.0), "n", &"park", R, 1, &"", "lawn", 0)
	_add(Rect2(-220.0, -12.7, 24.0, 22.0), "n", &"landmark", R, 4, &"safehouse")
	# frontage
	for e in LayoutRoadNet.edges:
		var cls: StringName = e["cls"]
		if cls != &"residential" and cls != &"street":
			continue
		var mid := LayoutGeo.point_at(e["pts"], float(e["len"]) * 0.5)
		if WorldLayout.district_at(mid.x, mid.y) != R:
			continue
		var name_s: String = e["name"]
		if name_s == "Parkway" or name_s == "Greenway":
			continue
		_frontage(e, R)
	# second pass: block interiors (back rows) on a jittered lattice, each lot facing its nearest street
	var gz := -240.0
	while gz < 84.0:
		var gx := -294.0
		while gx < -112.0:
			if _rng.randf() < 0.72:
				var w := _rng.randf_range(11.0, 15.0)
				var d := _rng.randf_range(13.0, 17.0)
				var r := Rect2(gx + _rng.randf_range(0.0, 4.0), gz + _rng.randf_range(0.0, 4.0), w, d)
				if _lot_ok(r, R):
					var face := _nearest_road_face(r.get_center())
					var apt := _rng.randf() < 0.1
					if apt:
						_add(r, face, &"apartment", R, _rng.randi_range(3, 4))
					else:
						_add(r, face, &"house", R, _rng.randi_range(1, 2))
			gx += 17.0
		gz += 19.0


## Axis-snapped side ("n","s","e","w") pointing from p toward the nearest road sample.
static func _nearest_road_face(p: Vector2) -> String:
	var best := 1e9
	var bp := p + Vector2(0, -1)
	for gx in range(int(floor((p.x - 48.0) / 16.0)), int(floor((p.x + 48.0) / 16.0)) + 1):
		for gz in range(int(floor((p.y - 48.0) / 16.0)), int(floor((p.y + 48.0) / 16.0)) + 1):
			for idx in _road_grid.get(Vector2i(gx, gz), []):
				var rp: Array = _road_pts[idx]
				var q: Vector2 = rp[0]
				var dd := q.distance_squared_to(p) - float(rp[1]) * float(rp[1]) * 0.5
				if dd < best:
					best = dd
					bp = q
	var d := bp - p
	if absf(d.x) > absf(d.y):
		return "e" if d.x > 0.0 else "w"
	return "s" if d.y > 0.0 else "n"


static func _frontage(e: Dictionary, district: StringName) -> void:
	_cur_edge = String(e["name"]) + "#" + str(e["id"])
	var pts: PackedVector2Array = e["pts"]
	var hw: float = e["hw"]
	var sw: float = e["sw"]
	var s := float(e["trim_a"]) + 3.0
	var s_end := float(e["len"]) - float(e["trim_b"]) - 3.0
	var cum := LayoutGeo.cum_lengths(pts)
	var collector: bool = (e["cls"] == &"street")
	while s < s_end:
		var d := LayoutGeo.dir_at(pts, s, cum)
		var axis_x := absf(d.x) > 0.98
		var axis_z := absf(d.y) > 0.98
		if not (axis_x or axis_z):
			s += 6.0
			continue
		var apt: bool = collector and _rng.randf() < 0.28
		var w := _rng.randf_range(16.0, 22.0) if apt else _rng.randf_range(11.0, 15.0)
		var c := LayoutGeo.point_at(pts, s + w * 0.5, cum)
		var placed := false
		for side_i in 2:
			var side := 1.0 if side_i == 0 else -1.0
			var nrm := LayoutGeo.right_of(d) * side
			var depth := _rng.randf_range(19.0, 24.0) if apt else _rng.randf_range(15.0, 19.0)
			for dep in [depth, depth * 0.75, depth * 0.55]:
				var off: float = hw + sw + 0.4 + dep * 0.5
				var ctr: Vector2 = c + nrm * off
				var rect: Rect2
				if axis_x:
					rect = Rect2(ctr.x - w * 0.5, ctr.y - dep * 0.5, w, dep)
				else:
					rect = Rect2(ctr.x - dep * 0.5, ctr.y - w * 0.5, dep, w)
				if not _lot_ok(rect, district):
					continue
				var face := -nrm
				var side_s := "n"
				if absf(face.x) > absf(face.y):
					side_s = "e" if face.x > 0.0 else "w"
				else:
					side_s = "s" if face.y > 0.0 else "n"
				if apt:
					_add(rect, side_s, &"apartment", district, _rng.randi_range(3, 5))
				else:
					_add(rect, side_s, &"house", district, _rng.randi_range(1, 2))
				placed = true
				break
		s += w + _rng.randf_range(1.2, 3.2)
		if not placed:
			s += 2.0


static func _lot_ok(r: Rect2, district: StringName) -> bool:
	if absf(r.position.x) > 286.0 or absf(r.end.x) > 286.0 or r.position.y < -286.0 or r.end.y > 186.0:
		reject["bounds:" + _cur_edge] = int(reject.get("bounds:" + _cur_edge, 0)) + 1
		return false
	if _overlaps_lots(r, 0.35):
		reject["lots:" + _cur_edge] = int(reject.get("lots:" + _cur_edge, 0)) + 1
		return false
	if _hits_road(r):
		reject["road:" + _cur_edge] = int(reject.get("road:" + _cur_edge, 0)) + 1
		return false
	var cen := r.get_center()
	if WorldLayout.district_at(cen.x, cen.y) != district:
		reject["district:" + _cur_edge] = int(reject.get("district:" + _cur_edge, 0)) + 1
		return false
	for p in [r.position, r.end, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), cen]:
		var pp: Vector2 = p
		if absf(LayoutTerrain.height(pp.x, pp.y)) > 0.35:
			reject["height"] = int(reject.get("height", 0)) + 1
			return false
	reject["ok:" + _cur_edge] = int(reject.get("ok:" + _cur_edge, 0)) + 1
	return true


# ---- park + hills lots ----------------------------------------------------------------------------------------------------------
static func _park_lots() -> void:
	var P := GC.D_PARK
	_add(Rect2(-99.0, -199.0, 58.0, 103.0), "e", &"park", P, 1, &"", "lawn", 0)
	_add(Rect2(-28.0, -208.0, 66.0, 112.0), "w", &"park", P, 1, &"", "lawn", 0)


static func _footprints() -> void:
	var out: Array = []
	for lot in WorldLayout.lots:
		var k: StringName = lot["kind"]
		if (k == &"empty" or k == &"park") and not lot.has("hero"):
			continue
		out.append({"rect": lot["rect"], "height": lot["height"], "kind": k})
	WorldLayout.building_footprints = out
