extends Node
## RoutePlanner test (headless): the lane graph is connected between all key locations and routes are sane.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/transit_route_test.gd -Seconds 60 -GameArgs "--no-traffic --no-peds"

const KEYS: Array[StringName] = [&"player_spawn", &"hospital", &"police_station", &"weapon_shop", &"garage_shop", &"gas_station", &"dealer_lot",
	&"taxi_stand", &"train_station_a", &"train_station_b", &"safehouse", &"barber", &"clothing_store", &"shooting_range", &"airport_hangar",
	&"marina_office", &"scuba_shop", &"park_center", &"beach_spawn", &"viewpoint", &"district_center_industrial", &"district_center_residential",
	&"district_center_waterfront", &"district_center_airport"]


func report(test_name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func run(_main: Node) -> void:
	var waited := 0
	while not WorldLayout.built and waited < 600:
		await get_tree().physics_frame
		waited += 1
	report("route_world_built", WorldLayout.built and WorldLayout.lanes != null, "lane points=%d" % (WorldLayout.lanes.size() if WorldLayout.lanes != null else 0))
	var g: LaneGraph = RoutePlanner.graph()
	report("route_graph", g != null)
	if g == null:
		return
	var locs: Array[StringName] = []
	for k in KEYS:
		if WorldLayout.has_location(k):
			locs.append(k)
	report("route_locations_present", locs.size() >= 18, "%d of %d key locations exist" % [locs.size(), KEYS.size()])
	# every ordered pair must be routable and sane
	var t0 := Time.get_ticks_usec()
	var pairs := 0
	var missing: Array[String] = []
	var insane: Array[String] = []
	var longest := 0.0
	var worst_ratio := 0.0
	var worst_pair := ""
	for a in locs:
		for b in locs:
			if a == b:
				continue
			var pa := WorldLayout.location_pos(a)
			var pb := WorldLayout.location_pos(b)
			var route := RoutePlanner.plan_positions(pa, pb)
			pairs += 1
			if route.is_empty():
				missing.append("%s->%s" % [a, b])
				continue
			var len_m := RoutePlanner.route_length(route)
			var straight := Util.dist_xz(pa, pb)
			longest = maxf(longest, len_m)
			if straight > 40.0:
				var ratio := len_m / straight
				if ratio > worst_ratio:
					worst_ratio = ratio
					worst_pair = "%s->%s %.0f/%.0f" % [a, b, len_m, straight]
				if len_m > maxf(straight * 8.0, 450.0) or len_m < straight - 35.0:
					insane.append("%s->%s len=%.0f straight=%.0f" % [a, b, len_m, straight])
			# continuity: each hop is a real successor
			for k in range(1, route.size()):
				if not (g.next[route[k - 1]] as PackedInt32Array).has(route[k]):
					insane.append("%s->%s broken link at %d" % [a, b, k])
					break
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	report("route_all_pairs_exist", missing.is_empty(), "%d pairs, missing=%s" % [pairs, str(missing.slice(0, 6))])
	report("route_all_pairs_sane", insane.is_empty(), "longest=%.0f m worst length/straight=%.2f (%s) %s" % [longest, worst_ratio, worst_pair, str(insane.slice(0, 4))])
	report("route_perf", ms / maxf(float(pairs), 1.0) < 8.0, "%d plans in %.0f ms = %.2f ms each (cache hits %d expansions %d)" % [pairs, ms, ms / maxf(float(pairs), 1.0), RoutePlanner.stats["cache_hits"], RoutePlanner.stats["expansions"]])
	# cache: second run of the same plan must be a hit
	RoutePlanner.plan_positions(WorldLayout.location_pos(locs[0]), WorldLayout.location_pos(locs[1]))
	var h0: int = RoutePlanner.stats["cache_hits"]
	RoutePlanner.plan_positions(WorldLayout.location_pos(locs[0]), WorldLayout.location_pos(locs[1]))
	report("route_cache", int(RoutePlanner.stats["cache_hits"]) == h0 + 1, "hits %d -> %d" % [h0, RoutePlanner.stats["cache_hits"]])
	# route points for the UI
	var pts := RoutePlanner.get_route_points(WorldLayout.location_pos(&"player_spawn"), WorldLayout.location_pos(&"hospital"))
	report("route_points_ui", pts.size() > 6 and pts[0].distance_to(WorldLayout.location_pos(&"player_spawn")) < 0.01, "%d points" % pts.size())
	# time estimate sane: spawn -> hospital ~ 100-400 m at 14 m/s
	var r2 := RoutePlanner.plan_positions(WorldLayout.location_pos(&"player_spawn"), WorldLayout.location_pos(&"hospital"))
	var tt := RoutePlanner.route_time(r2)
	report("route_time", tt > 5.0 and tt < 120.0, "spawn->hospital %.0f m, %.1f s" % [RoutePlanner.route_length(r2), tt])
	# curb stop + spawn selection
	var stop := RoutePlanner.find_curb_stop(WorldLayout.location_pos(&"player_spawn"))
	report("route_curb_stop", stop >= 0 and RoutePlanner.is_stoppable(stop), "stop lane idx %d at %s" % [stop, str(g.positions[stop]) if stop >= 0 else "-"])
	var sp := RoutePlanner.find_spawn_point(stop, 120.0, 260.0)
	var rr := RoutePlanner.plan(PackedInt32Array([sp]), PackedInt32Array([stop])) if sp >= 0 else PackedInt32Array()
	report("route_spawn_connected", sp >= 0 and not rr.is_empty(), "spawn idx %d, route %.0f m" % [sp, RoutePlanner.route_length(rr)])
	# a weird query: sea position -> should not crash
	var far := RoutePlanner.plan_positions(Vector3(0, 0, 0), Vector3(5000, 0, 5000))
	report("route_far_target_no_crash", true, "route size %d" % far.size())
	print("ROUTE TEST DONE")
