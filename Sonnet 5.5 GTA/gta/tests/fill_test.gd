extends Node
## World-fill checks (headless exec): hero buildings placed, locations still resolve, furniture clear of lanes, no building rect over a lane point.
##   tools\gd.ps1 exec -Script res://gta/tests/fill_test.gd -Seconds 60 -GameArgs "--no-traffic --no-peds"

const REQUIRED := [&"player_spawn", &"safehouse", &"hospital", &"police_station", &"weapon_shop", &"garage_shop", &"clothing_store", &"gas_station",
	&"dealer_lot", &"airport_runway_start", &"airport_runway_end", &"airport_hangar", &"helipad_airport", &"helipad_downtown", &"helipad_hospital",
	&"dock_boat_spawn", &"marina_pier", &"beach_spawn", &"viewpoint", &"parachute_peak", &"shooting_range", &"stunt_jump_1", &"stunt_jump_2",
	&"stunt_jump_3", &"taxi_stand", &"train_station_a", &"train_station_b", &"park_center", &"barber", &"diving_wreck", &"scuba_shop"]


func _t(name: String, ok: bool, detail := "") -> void:
	print("TEST fill_%s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func run(_main: Node) -> bool:
	var st: Dictionary = CityBuilder.last_stats
	_t("city_build_ms", int(st.get("ms", 99999)) <= 5000, str(st.get("ms", -1)))
	var placed: Dictionary = FillBuilder.stats["placed"]
	for hero in ["tower_a", "tower_b", "tower_c", "hotel", "hangar_a", "hangar_b", "warehouse_a", "warehouse_b", "factory", "silo_cluster", "crane_dock", "container_stack", "lighthouse", "ferris_wheel"]:
		_t("hero_" + hero, int(placed.get(hero, 0)) >= 1, str(placed.get(hero, 0)))
	_t("no_missing_hero", (FillBuilder.stats["missing"] as Array).is_empty(), str(FillBuilder.stats["missing"]))
	_t("props", int(FillBuilder.stats["props"]) >= 60, str(FillBuilder.stats["props"]))
	var miss: Array = []
	for id in REQUIRED:
		if not WorldLayout.has_location(id):
			miss.append(id)
	_t("locations", miss.is_empty(), str(miss))
	# helipads: downtown on the podium (anchor), hospital on its roof anchor
	var hd: Vector3 = WorldLayout.location_pos(&"helipad_downtown")
	_t("helipad_downtown", hd.y > 10.0 and hd.y < 40.0, str(hd))
	var hh: Vector3 = WorldLayout.location_pos(&"helipad_hospital")
	_t("helipad_hospital", hh.y > 5.0 and hh.y < 30.0, str(hh))
	# furniture vs lane graph
	var bad := 0
	for f in WorldLayout.furniture:
		if (f["kind"] in LayoutFurniture.LANE_CHECKED) and LayoutFurniture._lane_dist(f["pos"]) < LayoutFurniture.LANE_CLEAR - 0.01:
			bad += 1
	_t("furniture_lane_clear", bad == 0, "bad=%d removed=%s" % [bad, str(LayoutFurniture.lane_removed)])
	# hero lot rects must not contain lane points
	var overlaps: Array = []
	for lot in WorldLayout.lots:
		if not lot.has("hero"):
			continue
		var r: Rect2 = lot["rect"]
		for i in WorldLayout.lanes.size():
			var p: Vector3 = WorldLayout.lanes.positions[i]
			if r.has_point(Vector2(p.x, p.z)):
				overlaps.append("%s@%d" % [lot["hero"], i])
				break
	_t("hero_lots_off_lanes", overlaps.is_empty(), str(overlaps))
	# crane boom points seaward: placed with yaw PI (front -Z -> +Z)
	var crane_ok := false
	for h in FillBuilder.placed_heroes:
		if h["id"] == "crane_dock":
			crane_ok = absf(absf(float(h["yaw"])) - PI) < 0.01
	_t("crane_seaward", crane_ok)
	_t("ferris_animator", is_instance_valid(FillBuilder.animator) and (FillBuilder.animator as FillAnimator).wheels.size() == 1)
	# ped pier nodes sit on the deck (not on the sea floor)
	var deep := 0
	for i in WorldLayout.ped_graph.size():
		var pp: Vector3 = WorldLayout.ped_graph.positions[i]
		if WorldLayout.on_pier(pp.x, pp.z) and pp.y < -0.3:
			deep += 1
	_t("ped_pier_heights", deep == 0, "below_deck=%d" % deep)
	return true
