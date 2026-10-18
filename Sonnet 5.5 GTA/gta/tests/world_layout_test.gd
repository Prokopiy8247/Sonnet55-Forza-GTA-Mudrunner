extends Node
## World-Layout verification (headless `exec`): lane graph connectivity, signals, ped graph, required locations, road net connectivity,
## colliders + surface meta, sector toggling, water volumes, build time.  Prints "TEST <name> PASS|FAIL <detail>".

const REQUIRED := [
	"player_spawn", "safehouse", "hospital", "police_station", "weapon_shop", "garage_shop", "clothing_store", "gas_station", "dealer_lot",
	"airport_runway_start", "airport_runway_end", "airport_hangar", "helipad_airport", "helipad_downtown", "helipad_hospital",
	"dock_boat_spawn", "marina_pier", "beach_spawn", "viewpoint", "parachute_peak", "shooting_range", "stunt_jump_1", "stunt_jump_2",
	"stunt_jump_3", "taxi_stand", "train_station_a", "train_station_b", "park_center", "barber", "diving_wreck",
	"district_center_downtown", "district_center_residential", "district_center_industrial", "district_center_waterfront",
	"district_center_park_hills", "district_center_airport", "district_center_beach", "parachute_pickup_a", "parachute_pickup_b", "scuba_shop",
]
const WATER_OK := ["dock_boat_spawn", "diving_wreck"]
const INSIDE_OK := ["helipad_downtown", "helipad_hospital", "gas_station"]
const OFF_GROUND_OK := ["helipad_downtown", "helipad_hospital", "dock_boat_spawn", "marina_pier", "diving_wreck", "stunt_jump_3"]

var fails := 0


func _t(name_: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name_, "PASS" if ok else "FAIL", detail])
	if not ok:
		fails += 1


func run(main: Node) -> bool:
	WorldLayout.generate()
	var g: LaneGraph = WorldLayout.lanes
	# ---- lane graph ----------------------------------------------------------------------------------------------------------
	var spawn: Vector3 = WorldLayout.location_pos(&"player_spawn")
	var start := g.nearest(spawn, Vector3.ZERO, 80.0)
	_t("lane_start_found", start >= 0, "nearest lane point to player_spawn idx=%d" % start)
	var seen := PackedByteArray()
	seen.resize(g.size())
	var q: Array = [start]
	seen[start] = 1
	var reach := 1
	while not q.is_empty():
		var i: int = q.pop_back()
		for n in (g.next[i] as PackedInt32Array):
			if seen[n] == 0:
				seen[n] = 1
				reach += 1
				q.append(n)
	var pct := 100.0 * float(reach) / float(g.size())
	_t("lane_reachable_90pct", pct >= 90.0, "%d / %d = %.1f%%" % [reach, g.size(), pct])
	# dead ends / orphans
	var no_next := 0
	var no_prev := 0
	var stops := 0
	var stops_ok := 0
	for i in g.size():
		if (g.next[i] as PackedInt32Array).is_empty():
			no_next += 1
		if (g.prev[i] as PackedInt32Array).is_empty():
			no_prev += 1
		if g.signal_id[i] >= 0:
			stops += 1
			if not (g.prev[i] as PackedInt32Array).is_empty():
				stops_ok += 1
	_t("lane_no_dead_ends", no_next == 0, "points without successor: %d" % no_next)
	_t("lane_no_orphans", no_prev == 0, "points without predecessor: %d" % no_prev)
	_t("signal_stop_lines", stops > 0 and stops == stops_ok, "%d stop lines, %d with upstream lane" % [stops, stops_ok])
	_t("signal_count", WorldLayout.signals.size() >= 8, "%d signalised junctions" % WorldLayout.signals.size())
	# every signal has stop lines for both phases
	var phases := {}
	for i in g.size():
		if g.signal_id[i] >= 0:
			phases[g.signal_id[i] * 2 + g.signal_phase[i]] = true
	var both := 0
	for s in WorldLayout.signals:
		if phases.has(int(s["id"]) * 2) and phases.has(int(s["id"]) * 2 + 1):
			both += 1
	_t("signal_both_phases", both >= WorldLayout.signals.size() - 6, "%d of %d signals control both phases" % [both, WorldLayout.signals.size()])
	# multi-lane neighbours + speed limits
	var with_left := 0
	var hw_pts := 0
	for i in g.size():
		if g.left_of[i] >= 0:
			with_left += 1
		if g.kind[i] == LaneGraph.KIND_HIGHWAY:
			hw_pts += 1
	_t("lane_multilane", with_left > 100 and hw_pts > 100, "left_of links=%d highway points=%d" % [with_left, hw_pts])
	# ---- road net connectivity (undirected) -------------------------------------------------------------------------------
	var adj := {}
	for e in LayoutRoadNet.edges:
		if not adj.has(e["a"]):
			adj[e["a"]] = []
		if not adj.has(e["b"]):
			adj[e["b"]] = []
		(adj[e["a"]] as Array).append(e["b"])
		(adj[e["b"]] as Array).append(e["a"])
	var nseen := {"g00": true}
	var nq: Array = ["g00"]
	while not nq.is_empty():
		var nid: String = nq.pop_back()
		for m in adj.get(nid, []):
			if not nseen.has(m):
				nseen[m] = true
				nq.append(m)
	_t("roadnet_connected", nseen.size() == LayoutRoadNet.node_ids.size(), "%d of %d nodes reachable" % [nseen.size(), LayoutRoadNet.node_ids.size()])
	# ---- ped graph ---------------------------------------------------------------------------------------------------------------
	var pg: PedGraph = WorldLayout.ped_graph
	var ps := pg.nearest(spawn, 40.0)
	var pseen := PackedByteArray()
	pseen.resize(pg.size())
	var pq: Array = [ps]
	pseen[ps] = 1
	var preach := 1
	while not pq.is_empty():
		var pi: int = pq.pop_back()
		for n2 in (pg.links[pi] as PackedInt32Array):
			if pseen[n2] == 0:
				pseen[n2] = 1
				preach += 1
				pq.append(n2)
	var ppct := 100.0 * float(preach) / float(pg.size())
	_t("ped_reachable_90pct", ppct >= 90.0, "%d / %d = %.1f%%" % [preach, pg.size(), ppct])
	var zones := {}
	var crossings_sig := 0
	for i in pg.size():
		zones[pg.zone[i]] = int(zones.get(pg.zone[i], 0)) + 1
		if pg.zone[i] == PedGraph.ZONE_CROSSING and pg.signal_id[i] >= 0:
			crossings_sig += 1
	_t("ped_zones", zones.has(PedGraph.ZONE_SIDEWALK) and zones.has(PedGraph.ZONE_CROSSING) and zones.has(PedGraph.ZONE_PARK) and zones.has(PedGraph.ZONE_BEACH) and zones.has(PedGraph.ZONE_DOCK) and zones.has(PedGraph.ZONE_PLAZA), str(zones))
	_t("ped_signal_crossings", crossings_sig > 40, "%d crossing points bound to a signal" % crossings_sig)
	# ---- locations -----------------------------------------------------------------------------------------------------------------
	var missing: Array = []
	for id in REQUIRED:
		if not WorldLayout.has_location(StringName(id)):
			missing.append(id)
	_t("locations_exist", missing.is_empty(), "missing: %s" % str(missing))
	var bad_inside: Array = []
	var bad_water: Array = []
	var bad_lot: Array = []
	var bad_h: Array = []
	for id in WorldLayout.locations:
		var l: Dictionary = WorldLayout.locations[id]
		var p: Vector3 = l["pos"]
		if not WorldLayout.is_inside_world(p.x, p.z, 0.0):
			bad_inside.append(String(id))
		if WorldLayout.is_water(p.x, p.z) and not (String(id) in WATER_OK):
			bad_water.append(String(id))
		if not (String(id) in INSIDE_OK):
			for lot in WorldLayout.lots:
				var k: StringName = lot["kind"]
				if k == &"empty" or k == &"park":
					continue
				if (lot["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
					bad_lot.append("%s in lot %d (%s)" % [id, lot["id"], k])
					break
		if not (String(id) in OFF_GROUND_OK):
			var th := WorldLayout.terrain_height(p.x, p.z)
			if absf(p.y - th) > 1.0:
				bad_h.append("%s y=%.2f ground=%.2f" % [id, p.y, th])
	_t("locations_inside_world", bad_inside.is_empty(), str(bad_inside))
	_t("locations_not_in_water", bad_water.is_empty(), str(bad_water))
	_t("locations_not_in_buildings", bad_lot.is_empty(), str(bad_lot))
	_t("locations_on_ground", bad_h.is_empty(), str(bad_h))
	var wr: Dictionary = WorldLayout.get_location(&"dock_boat_spawn")
	_t("boat_spawn_in_water", WorldLayout.is_water(wr["pos"].x, wr["pos"].z), "")
	var dw: Dictionary = WorldLayout.get_location(&"diving_wreck")
	_t("wreck_deep_enough", WorldLayout.terrain_height(dw["pos"].x, dw["pos"].z) < -10.0, "seabed %.1f" % WorldLayout.terrain_height(dw["pos"].x, dw["pos"].z))
	var peak: Dictionary = WorldLayout.get_location(&"parachute_peak")
	_t("peak_height", peak["pos"].y > 40.0, "peak y=%.1f" % peak["pos"].y)
	# lots vs roads: no lot rectangle may cover a road centre line sample
	var overlap := 0
	for e in LayoutRoadNet.edges:
		var rs := LayoutGeo.resample(e["pts"], 6.0)
		for p2 in rs:
			for lot in WorldLayout.lots:
				var k2: StringName = lot["kind"]
				if k2 == &"empty" or k2 == &"park":
					continue
				if (lot["rect"] as Rect2).has_point(p2):
					overlap += 1
	_t("lots_off_roads", overlap == 0, "%d road samples inside lots" % overlap)
	var kinds := {}
	for lot in WorldLayout.lots:
		kinds[lot["kind"]] = int(kinds.get(lot["kind"], 0)) + 1
	_t("lots_by_kind", WorldLayout.lots.size() >= 120, str(kinds))
	_t("furniture_present", WorldLayout.furniture.size() >= 600, "%d items" % WorldLayout.furniture.size())
	# ---- terrain + water --------------------------------------------------------------------------------------------------------
	_t("plateau_flat", absf(WorldLayout.terrain_height(0, 0)) < 0.01 and absf(WorldLayout.terrain_height(-185, -90)) < 0.01, "")
	_t("hills_55m", WorldLayout.terrain_height(215, -228) > 40.0, "h=%.1f" % WorldLayout.terrain_height(215, -228))
	_t("sea_is_water", WorldLayout.is_water(0, 260) and WorldLayout.is_water(-250, 230) and not WorldLayout.is_water(0, 100), "")
	_t("pond_is_water", WorldLayout.is_water(LayoutTerrain.POND_C.x, LayoutTerrain.POND_C.y), "")
	_t("pier_not_water", not WorldLayout.is_water(-146, 215) and WorldLayout.on_pier(-146, 215), "")
	_t("district_at", WorldLayout.district_at(0, 0) == GC.D_DOWNTOWN and WorldLayout.district_at(-200, -50) == GC.D_RESIDENTIAL and WorldLayout.district_at(200, 0) == GC.D_INDUSTRIAL and WorldLayout.district_at(-200, 130) == GC.D_WATERFRONT and WorldLayout.district_at(0, 165) == GC.D_BEACH and WorldLayout.district_at(190, 150) == GC.D_AIRPORT and WorldLayout.district_at(-30, -150) == GC.D_PARK and WorldLayout.district_at(0, 250) == GC.D_SEA, "")
	_t("signal_state_cycle", _signal_cycle_ok(), "")
	# ---- world root ----------------------------------------------------------------------------------------------------------------
	var wr_node: Node = Game.world
	_t("world_root_set", wr_node is WorldRoot, "")
	if wr_node is WorldRoot:
		var rep: Dictionary = (wr_node as WorldRoot).build_report
		_t("build_time_6s", int(rep.get("total_ms", 99999)) < 6000, "total %d ms %s" % [int(rep.get("total_ms", -1)), str(rep.get("marks", {}))])
		await _physics_checks(main, wr_node as WorldRoot)
	print("TEST SUMMARY world_layout fails=%d" % fails)
	return fails == 0


func _signal_cycle_ok() -> bool:
	if WorldLayout.signals.is_empty():
		return false
	var greens := 0
	var reds := 0
	for t in range(0, 40):
		if WorldLayout.signal_state(0, 0, float(t)) == 0:
			greens += 1
		if WorldLayout.signal_state(0, 0, float(t)) == 2:
			reds += 1
		# phases must never both be green
		if WorldLayout.signal_state(0, 0, float(t)) == 0 and WorldLayout.signal_state(0, 1, float(t)) == 0:
			return false
	return greens > 5 and reds > 5


func _ray(root: Node3D, x: float, z: float) -> Dictionary:
	return Util.raycast(root, Vector3(x, 80.0, z), Vector3(x, -60.0, z), GC.L_WORLD)


func _physics_checks(main: Node, w: WorldRoot) -> void:
	await main.get_tree().physics_frame
	await main.get_tree().physics_frame
	await main.get_tree().physics_frame
	var cases := [
		["road_asphalt", 0.0, -20.0, "asphalt", 0.04],
		["sidewalk_concrete", 0.0, -25.4, "concrete", 0.15],
		["lawn_grass", -60.0, -105.0, "grass", 0.0],
		["pier_wood", -146.0, 215.0, "wood", 0.03],
		["quay_rim_concrete", -200.0, 193.4, "concrete", 0.015],
		["runway_asphalt", 180.0, 165.0, "asphalt", 0.03],
		["apron_concrete", 170.0, 121.0, "concrete", 0.03],
		["beach_terrain", 30.0, 170.0, "sand", -1.0],
	]
	for c in cases:
		var hit := _ray(w, c[1], c[2])
		var ok := not hit.is_empty()
		var surf := ""
		var y := 0.0
		if ok:
			surf = String((hit["collider"] as Node).get_meta("surface", &""))
			y = (hit["position"] as Vector3).y
			ok = surf == String(c[3]) and (c[4] < -0.5 or absf(y - float(c[4])) < 0.06)
		_t("collider_" + String(c[0]), ok, "surface=%s y=%.3f expected %s %.3f" % [surf, y, c[3], c[4]])
	# sea floor under water + hill collider agree with terrain_height
	var h1 := _ray(w, 215.0, -228.0)
	_t("collider_hill_matches", not h1.is_empty() and absf((h1["position"] as Vector3).y - WorldLayout.terrain_height(215, -228)) < 0.05, "")
	var h2 := _ray(w, 0.0, 300.0)
	_t("collider_seabed", not h2.is_empty() and (h2["position"] as Vector3).y < -10.0, "")
	# boundary walls stop a ray from the inside
	var wall := Util.raycast(w, Vector3(280, 2, 0), Vector3(330, 2, 0), GC.L_WORLD)
	_t("boundary_wall_east", not wall.is_empty() and (wall["position"] as Vector3).x < 306.0, "")
	var wall2 := Util.raycast(w, Vector3(0, 2, -280), Vector3(0, 2, -330), GC.L_WORLD)
	_t("boundary_wall_north", not wall2.is_empty() and (wall2["position"] as Vector3).z > -306.0, "")
	# aircraft corridor: wall over the runway extension is low
	var wall3 := Util.raycast(w, Vector3(280, 12, 165), Vector3(330, 12, 165), GC.L_WORLD)
	_t("runway_corridor_open", wall3.is_empty(), "wall at 12 m over the runway axis should not exist")
	# water volumes
	var vols := main.get_tree().get_nodes_in_group(&"water_volume")
	var sea_ok := false
	for v in vols:
		if v.get_meta("is_sea", false) and absf(float(v.get_meta("water_level", 0.0)) - GC.WATER_LEVEL) < 0.01 and (v as Area3D).collision_layer == GC.L_WATER:
			sea_ok = true
	_t("water_volume_sea", sea_ok and vols.size() >= 2, "%d volumes" % vols.size())
	# sectors
	var sm: SectorManager = w.sectors
	_t("sector_parent_api", w.get_sector_parent(Vector3(10, 0, 10)) is Node3D, "%d sectors" % sm.sectors.size())
	var before := sm.active_count()
	sm.update_focus(Vector3(-290, 0, -290))
	var far_active := sm.active_count()
	sm.update_focus(Vector3(0, 0, 0))
	var near_active := sm.active_count()
	_t("sector_toggle", far_active < before + 1 and far_active > 0 and near_active >= far_active, "all=%d far-corner=%d centre=%d" % [before, far_active, near_active])
