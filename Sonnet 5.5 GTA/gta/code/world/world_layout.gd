class_name WorldLayout
extends RefCounted
## Static, data-only description of the 600 x 600 m map "Halcyon Bay" (generated deterministically by `generate()`; WorldRoot calls it
## at boot, anybody may call it earlier - it is idempotent). Every other module reads the world only through this API.
## Coordinates: X east(+) / west(-), Z south(+) / north(-), Y up. Playable ground spans [-300, 300] on X and Z (sea continues to z=400).
## Sea surface is GC.WATER_LEVEL; urban plateau is at GC.GROUND_Y. See docs/api/world.md for the map description.

static var lanes: LaneGraph = LaneGraph.new()
static var ped_graph: PedGraph = PedGraph.new()

## Traffic signals: [{"id": int, "pos": Vector3, "cycle": float (s), "yellow": float, "offset": float, "node": String}]
## Phase 0 is green during the first half of the cycle, phase 1 during the second half.
static var signals: Array = []

## Named locations. Required ids are listed in docs/ARCHITECTURE.md section 5.
## id -> {"pos": Vector3, "yaw": float, "radius": float, "kind": StringName, "name": String}
static var locations: Dictionary = {}

## Districts: [{"id": StringName, "name": String, "rect": Rect2 (x,z), "color": Color}]
static var districts: Array = []

## Road polylines for the minimap / map screen: [{"points": PackedVector2Array (x,z), "width": float, "kind": StringName, "name": String}]
static var roads: Array = []

## Static footprint list for the minimap: [{"rect": Rect2 (x,z), "height": float, "kind": StringName}]
static var building_footprints: Array = []

## Building lots (produced by the World-Layout agent, consumed by the City-Builder agent):
## {"id": int, "rect": Rect2 (x,z; position = min corner), "yaw": float (facing the street, Util.yaw convention),
##  "district": StringName, "kind": StringName (&"office" &"apartment" &"shop" &"house" &"warehouse" &"factory" &"hangar"
##  &"parking" &"park" &"landmark" &"empty"), "landmark": StringName (id of a hero building when kind == &"landmark"),
##  "floors": int, "height": float (m), "palette": int (0..3 wall colour set)}
static var lots: Array = []

## Street furniture spots (Layout produces, City-Builder instantiates):
## {"kind": StringName (&"lamp" &"signal" &"sign_stop" &"sign_speed" &"hydrant" &"bench" &"bin" &"bollard" &"bus_stop"
##  &"cone" &"barrier" &"fence" &"utility_box" &"mailbox" &"parking_meter" &"billboard" &"palm" &"tree_street"),
##  "pos": Vector3, "yaw": float, "signal_id": int (-1 if none), "phase": int (signals only: traffic phase this head controls)}
static var furniture: Array = []

## Vegetation zones: {"poly": PackedVector2Array (x,z), "kind": StringName (&"forest" &"park" &"hills" &"beach_palms" &"roadside"),
##  "density": float (trees per 100 m^2 scale 0..1)}
static var nature_zones: Array = []

## Airport data: {"runway_start": Vector3, "runway_end": Vector3, "runway_width": float, "taxiway": Array[Vector3], "apron": Rect2, ...}
static var airport: Dictionary = {}

## Piers / docks (box-ish walkable structures over water): [{"rect": Rect2, "height": float, "name": String}]
static var piers: Array = []

## Water polygons (x,z) for the minimap: Array[PackedVector2Array]
static var water_polys: Array = []

## Rail route for the transit system (additive): {"points": PackedVector3Array, "stations": {&"train_station_a": idx, ...}}
static var rail: Dictionary = {}

## Extra volumes (additive): [{"id": StringName, "rect": Rect2, "kind": &"sea"|&"pond"}] swim/boat areas, see WorldRoot.
static var water_volumes: Array = []

static var built := false
static var build_ms := 0
static var _road_grid: Dictionary = {}


# ---- generation ---------------------------------------------------------------------------------------------------
static func generate(force: bool = false) -> void:
	if built and not force:
		return
	var t0 := Time.get_ticks_msec()
	built = false
	lanes = LaneGraph.new()
	ped_graph = PedGraph.new()
	signals = []
	locations = {}
	lots = []
	furniture = []
	LayoutRoadNet.define()
	LayoutRoadNet.compute_junctions()
	LayoutTerrain.bake(LayoutHills.carve_paths())
	var t1 := Time.get_ticks_msec()
	districts = LayoutPlaces.districts()
	airport = LayoutPlaces.airport()
	piers = LayoutPlaces.piers()
	nature_zones = LayoutPlaces.nature_zones()
	water_polys = LayoutPlaces.water_polys()
	water_volumes = LayoutPlaces.water_volumes()
	rail = LayoutPlaces.rail()
	LayoutLanes.build(lanes, signals)
	var t2 := Time.get_ticks_msec()
	LayoutPeds.build(ped_graph, piers, LayoutPlaces.ped_paths())
	var t3 := Time.get_ticks_msec()
	LayoutLots.build()
	LayoutFurniture.build()
	LayoutLocations.build()
	_build_roads_minimap()
	_build_road_grid()
	var t4 := Time.get_ticks_msec()
	built = true
	build_ms = Time.get_ticks_msec() - t0
	print("[WorldLayout] generated in %d ms (terrain %d, lanes %d, peds %d, lots/furniture/locations %d): %d lane pts, %d ped pts, %d signals, %d lots, %d furniture, %d locations" % [
		build_ms, t1 - t0, t2 - t1, t3 - t2, t4 - t3, lanes.size(), ped_graph.size(), signals.size(), lots.size(), furniture.size(), locations.size()])


static func _build_roads_minimap() -> void:
	roads = []
	for e in LayoutRoadNet.edges:
		var w := float(e["hw"]) * 2.0
		roads.append({"points": LayoutGeo.resample(e["pts"], 8.0), "width": w, "kind": e["cls"], "name": e["name"]})


# ---- terrain queries ---------------------------------------------------------------------------------------------
## Ground height at (x,z). Sea floor is lower than WATER_LEVEL; the urban plateau is GROUND_Y. Piers are NOT included (see pier_height).
static func terrain_height(x: float, z: float) -> float:
	return LayoutTerrain.height(x, z)


## True when (x,z) is open water (sea, pond) - the terrain is below the water surface and no pier deck covers the point.
static func is_water(x: float, z: float) -> bool:
	if LayoutTerrain.height(x, z) >= GC.WATER_LEVEL:
		return false
	return not on_pier(x, z)


static func on_pier(x: float, z: float) -> bool:
	if z < 160.0:
		return false
	return LayoutPlaces.pier_contains(x, z, piers)


## Height of a pier deck at (x,z) or -INF when no pier is there.
static func pier_height(x: float, z: float) -> float:
	if z < 160.0:
		return -INF
	for p in piers:
		var r: Rect2 = p["rect"]
		if x >= r.position.x and x <= r.end.x and z >= r.position.y and z <= r.end.y:
			return float(p["height"])
	return -INF


static func district_at(x: float, z: float) -> StringName:
	if LayoutTerrain.height(x, z) < GC.WATER_LEVEL:
		return GC.D_WATERFRONT if on_pier(x, z) else GC.D_SEA
	if x >= 76.0 and z >= 138.0:
		return GC.D_AIRPORT
	if x >= 108.0 and z >= 86.0:
		return GC.D_AIRPORT
	if z >= 134.0 and x >= -100.0 and x < 76.0:
		return GC.D_BEACH
	if z >= 90.0 and x < -100.0:
		return GC.D_WATERFRONT
	if x >= 108.0 and z >= -62.0:
		return GC.D_INDUSTRIAL
	if x >= -108.0 and x <= 108.0 and z >= -92.0:
		return GC.D_DOWNTOWN
	if x < -108.0 and z < 90.0 and z > -250.0:
		return GC.D_RESIDENTIAL
	return GC.D_PARK


## Footstep / impact surface for the open terrain at (x,z): &"grass" &"sand" &"concrete" &"rock" &"dirt" &"water" &"wood".
## (Road, sidewalk, pier and building colliders carry their own meta "surface"; this is for the bare ground.)
static func surface_at(x: float, z: float) -> StringName:
	var h := LayoutTerrain.height(x, z)
	if h < GC.WATER_LEVEL:
		return &"wood" if on_pier(x, z) else &"water"
	if on_pier(x, z):
		return &"wood"
	if z > 150.0 and x > -100.0 and x < 76.0 and h < 0.9:
		return &"sand"
	var n := LayoutTerrain.normal_at(x, z)
	if n.y < 0.80 or h > 36.0:
		return &"rock"
	var d := district_at(x, z)
	if d == GC.D_DOWNTOWN or d == GC.D_INDUSTRIAL or d == GC.D_AIRPORT or d == GC.D_WATERFRONT:
		return &"concrete"
	return &"grass"


## Distance to the nearest road centre line and that road's data (cheap, grid accelerated). {} when no road within `max_d`.
static func road_at(x: float, z: float, max_d: float = 14.0) -> Dictionary:
	var best := {}
	var best_d := max_d
	var cx := int(floor(x / 20.0))
	var cz := int(floor(z / 20.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr: Array = _road_grid.get(Vector2i(cx + dx, cz + dz), [])
			for seg in arr:
				var a: Vector2 = seg[1]
				var b: Vector2 = seg[2]
				var ab := b - a
				var l2 := ab.length_squared()
				var t := 0.0 if l2 < 0.0001 else clampf((Vector2(x, z) - a).dot(ab) / l2, 0.0, 1.0)
				var d := (a + ab * t).distance_to(Vector2(x, z))
				if d < best_d:
					best_d = d
					best = {"edge": seg[0], "dist": d, "dir": ab.normalized()}
	if best.is_empty():
		return best
	var e: Dictionary = LayoutRoadNet.edges[best["edge"]]
	best["name"] = e["name"]
	best["class"] = e["cls"]
	best["half_width"] = e["hw"]
	best["on_road"] = best["dist"] <= float(e["hw"])
	best["on_sidewalk"] = not best["on_road"] and best["dist"] <= float(e["hw"]) + float(e["sw"])
	return best


static func _build_road_grid() -> void:
	_road_grid.clear()
	for e in LayoutRoadNet.edges:
		var pts: PackedVector2Array = e["pts"]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var x0 := int(floor(minf(a.x, b.x) / 20.0))
			var x1 := int(floor(maxf(a.x, b.x) / 20.0))
			var z0 := int(floor(minf(a.y, b.y) / 20.0))
			var z1 := int(floor(maxf(a.y, b.y) / 20.0))
			for gx in range(x0, x1 + 1):
				for gz in range(z0, z1 + 1):
					var key := Vector2i(gx, gz)
					if not _road_grid.has(key):
						_road_grid[key] = []
					(_road_grid[key] as Array).append([e["id"], a, b])


# ---- locations ---------------------------------------------------------------------------------------------------
static func has_location(id: StringName) -> bool:
	return locations.has(id)


static func get_location(id: StringName) -> Dictionary:
	return locations.get(id, {})


static func location_pos(id: StringName, fallback: Vector3 = Vector3(0, 1, 0)) -> Vector3:
	var l: Dictionary = locations.get(id, {})
	return l.get("pos", fallback)


static func locations_of_kind(kind: StringName) -> Array:
	var out: Array = []
	for id in locations:
		if locations[id].get("kind", &"") == kind:
			out.append(locations[id])
	return out


static func is_inside_world(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= GC.WORLD_HALF - margin and absf(z) <= GC.WORLD_HALF - margin


# ---- signals -----------------------------------------------------------------------------------------------------
## Signal state helper shared by traffic + pedestrians. phase 0 green for first half cycle, phase 1 second half.
## Returns 0 = green, 1 = yellow, 2 = red for traffic of the given phase at the given game time (seconds).
static func signal_state(sig_id: int, phase: int, time_s: float) -> int:
	if sig_id < 0 or sig_id >= signals.size():
		return 0
	var s: Dictionary = signals[sig_id]
	var cycle: float = s.get("cycle", 24.0)
	var yellow: float = s.get("yellow", 2.0)
	var t := fposmod(time_s + float(s.get("offset", 0.0)), cycle)
	var half := cycle * 0.5
	var in_phase0 := t < half
	var active := (phase == 0) == in_phase0
	if not active:
		return 2
	var t_in := t if in_phase0 else t - half
	return 1 if t_in > half - yellow else 0


## Seconds until traffic of `phase` turns green (0 if it is green/yellow now... returns remaining red time otherwise).
static func red_time_left(sig_id: int, phase: int, time_s: float) -> float:
	if sig_id < 0 or sig_id >= signals.size():
		return 0.0
	var s: Dictionary = signals[sig_id]
	var cycle: float = s.get("cycle", 24.0)
	var t := fposmod(time_s + float(s.get("offset", 0.0)), cycle)
	return _red_left(t, cycle * 0.5, cycle, phase)


static func _red_left(t: float, half: float, cycle: float, phase: int) -> float:
	# phase 0 is red during [half, cycle), phase 1 during [0, half)
	if phase == 0:
		return cycle - t if t >= half else 0.0
	return half - t if t < half else 0.0


## True when a pedestrian crossing point (ped_graph index) may be entered now: its signal holds the crossed traffic on red
## for at least `min_left` more seconds. Uncontrolled crossings (signal_id < 0) always return true.
static func crossing_open(point_idx: int, time_s: float, min_left: float = 4.0) -> bool:
	var sid := ped_graph.signal_id[point_idx]
	if sid < 0:
		return true
	var ph := ped_graph.walk_phase[point_idx]
	return signal_state(sid, ph, time_s) == 2 and red_time_left(sid, ph, time_s) >= min_left
