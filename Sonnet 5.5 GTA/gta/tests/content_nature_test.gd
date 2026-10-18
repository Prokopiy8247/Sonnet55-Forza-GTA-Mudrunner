extends Node
const _NB := preload("res://gta/code/world/nature_builder.gd")
## Headless test of the vegetation: counts, LOD pairs, no trees on roads or inside lots, trunk colliders only near roads.
##   tools\gd.ps1 exec -Script res://gta/tests/content_nature_test.gd -Seconds 60

func _check(name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func run(main: Node) -> Variant:
	var world: Node3D = Game.world
	if WorldLayout.lots.size() == 0 or world == null:
		ContentMock.fill(true)
		world = ContentMock.make_world(main, false)
		Game.world = world
		CityBuilder.build(world)
	var ns: Dictionary = CityBuilder.last_stats.get("nature", {})
	print("NATURE ", ns)
	_check("trees", int(ns.get("trees", 0)) >= 100, str(ns.get("trees", 0)))
	_check("tufts", int(ns.get("tufts", 0)) >= 100, str(ns.get("tufts", 0)))
	_check("trunk_colliders", int(ns.get("colliders", 0)) > 0 and int(ns.get("colliders", 0)) <= _NB.MAX_TRUNK_COLLIDERS, str(ns.get("colliders", 0)))
	# LOD pair: near mesh ends where the far mesh begins (overlap)
	var near_ok := false
	var far_ok := false
	var idx := _NB.AvoidIndex.new()
	var tree_nodes: Array = []
	for n in Util.find_all(world, func(x): return x is MultiMeshInstance3D and String(x.name).begins_with("MM_nat_")):
		var mmi := n as MultiMeshInstance3D
		var nm := String(mmi.name)
		if nm.begins_with("MM_nat_oak_") and mmi.visibility_range_end > 100.0 and mmi.visibility_range_end <= _NB.NEAR_END + 1.0:
			near_ok = true
		if nm == "MM_nat_oak_far" and mmi.visibility_range_begin > 80.0 and mmi.visibility_range_begin < mmi.visibility_range_end:
			far_ok = true
		if nm.begins_with("MM_nat_oak_") or nm.begins_with("MM_nat_pine_") or nm.begins_with("MM_nat_birch_"):
			if not nm.ends_with("_far"):
				tree_nodes.append(mmi)
	_check("near_lod_range", near_ok)
	_check("far_lod_range", far_ok)
	# no tree inside a road corridor or a building lot (mock roads are axis aligned)
	for r in WorldLayout.roads:
		var pts: PackedVector2Array = r["points"]
		for i in range(pts.size() - 1):
			idx.add_road(pts[i], pts[i + 1], float(r["width"]) * 0.5)
	for lot in WorldLayout.lots:
		if lot["kind"] != &"park":
			idx.add_rect(lot["rect"])
	var bad := 0
	for p in _NB.placed_trees:
		var rd := idx.road_edge_dist(Vector2(p.x, p.z))
		var inr := idx.in_rect(Vector2(p.x, p.z), 0.0)
		if rd < 0.5 or inr:
			bad += 1
			if bad <= 4:
				print("TEST nat_debug bad tree p=%s road_edge=%s in_rect=%s" % [str(p), str(rd), str(inr)])
	_check("zone_trees_clear_of_roads_and_lots", bad == 0, "bad=%d of %d" % [bad, _NB.placed_trees.size()])
	var bad_street := 0
	for p in _NB.placed_street_trees:
		if idx.road_edge_dist(Vector2(p.x, p.z)) < -0.2:
			bad_street += 1
	_check("street_trees_off_the_roadway", bad_street == 0, "bad=%d of %d" % [bad_street, _NB.placed_street_trees.size()])
	return true
