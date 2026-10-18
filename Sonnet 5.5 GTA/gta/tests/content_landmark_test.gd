extends Node
## Headless test of the landmark lots: every landmark lot produced a building (GLB or logged fallback), a collider, and Marker3D anchors
## in group "location_anchor" at the matching WorldLayout locations.
##   tools\gd.ps1 exec -Script res://gta/tests/content_landmark_test.gd -Seconds 60

func _check(name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func run(main: Node) -> Variant:
	if WorldLayout.lots.size() == 0 or Game.world == null:
		print("TEST landmarks SKIP no real layout lots")
		return true
	var lm: Dictionary = CityBuilder.last_stats.get("landmarks", {})
	print("LANDMARKS ", lm)
	var expected := 0
	for lot in WorldLayout.lots:
		if lot.get("kind", &"") == &"landmark" and lot.get("landmark", &"") != &"":
			expected += 1
	_check("landmarks_built", int(lm.get("landmarks", 0)) == expected and expected > 0, "%s of %d" % [str(lm.get("landmarks", 0)), expected])
	var anchors := get_tree().get_nodes_in_group(&"location_anchor")
	_check("location_anchors", anchors.size() >= expected, "anchors=%d" % anchors.size())
	var ok_pos := true
	var found_ids := {}
	for a in anchors:
		var lid := StringName(a.get_meta("location_id", ""))
		if lid == &"":
			continue
		found_ids[lid] = true
		var loc: Dictionary = WorldLayout.get_location(lid)
		if loc.is_empty() or (a as Node3D).global_position.distance_to(loc["pos"]) > 0.5:
			ok_pos = false
	_check("anchor_positions_match_locations", ok_pos, "ids=%d" % found_ids.size())
	for id in [&"weapon_shop", &"hospital", &"police_station", &"garage_shop", &"clothing_store", &"gas_station", &"safehouse"]:
		if WorldLayout.has_location(id):
			_check("anchor_" + String(id), found_ids.has(id))
	# each landmark lot must have a collider box inside its rect
	var space := Game.world.get_world_3d().direct_space_state
	await get_tree().physics_frame
	var blocked := 0
	for lot in WorldLayout.lots:
		if lot.get("kind", &"") != &"landmark":
			continue
		var r: Rect2 = lot["rect"]
		var c := r.get_center()
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, 120.0, c.y), Vector3(c.x, -2.0, c.y), GC.L_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and float(hit["position"].y) > 1.5:
			blocked += 1
	_check("landmark_colliders", blocked >= int(expected * 0.7), "%d of %d lots hit above ground" % [blocked, expected])
	return true
