extends Node
## Dev probe for the wildlife module (not a test): dumps terrain/road info used to place the pasture, seabed stats and the animal GLB trees.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/wildlife_probe.gd -Seconds 40 -GameArgs "--no-traffic --no-peds"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run(_main: Node) -> Variant:
	await _frames(20)
	# ---- pasture search: flat, road-free 60 x 44 m rects in the NE foothills / north ------------------------------------
	var best: Array = []
	for cx in range(30, 300, 10):
		for cz in range(-290, -100, 10):
			var ok := true
			var hmin := 1e9
			var hmax := -1e9
			for dx in range(-30, 31, 10):
				for dz in range(-22, 23, 11):
					var x := float(cx + dx)
					var z := float(cz + dz)
					var h := WorldLayout.terrain_height(x, z)
					hmin = minf(hmin, h)
					hmax = maxf(hmax, h)
					var r := WorldLayout.road_at(x, z, 10.0)
					if not r.is_empty():
						ok = false
			if ok and hmax - hmin < 1.6 and hmin > -0.5:
				best.append([cx, cz, snappedf(hmax - hmin, 0.01), snappedf(hmin, 0.01)])
	print("PROBE pasture candidates: ", best.size())
	for i in mini(best.size(), 40):
		print("PROBE   ", best[i])
	# ---- seabed ---------------------------------------------------------------------------------------------------------
	for z in [170, 180, 190, 200, 220, 240, 260, 268, 280, 300, 330]:
		print("PROBE seabed x=-22 z=%d h=%.2f | x=0 h=%.2f | x=-180 h=%.2f | x=150 h=%.2f" % [z, WorldLayout.terrain_height(-22, z), WorldLayout.terrain_height(0, z), WorldLayout.terrain_height(-180, z), WorldLayout.terrain_height(150, z)])
	print("PROBE diving_wreck=", WorldLayout.get_location(&"diving_wreck"))
	print("PROBE marina_pier=", WorldLayout.get_location(&"marina_pier"), " beach_spawn=", WorldLayout.get_location(&"beach_spawn"))
	print("PROBE piers=", WorldLayout.piers.size())
	for p in WorldLayout.piers:
		print("PROBE   pier ", p["name"], " ", p["rect"], " h=", p["height"])
	# ---- models ---------------------------------------------------------------------------------------------------------
	for id in ["shipwreck", "shipwreck_hero", "wreck", "coral_a", "coral_b", "coral_c", "kelp_a", "kelp_b", "anchor", "sunken_crates", "sea_rock_a", "sea_rock_b", "seaweed_clump", "seaweed", "vending_machine", "atm", "helipad_pad"]:
		for cat in ["props", "nature", "underwater"]:
			if ModelLib.exists(cat + "/" + id):
				print("PROBE model exists: ", cat, "/", id)
	for id in ["deer", "dog", "seagull", "fish_a", "shark", "dolphin", "sea_turtle", "cow", "boar"]:
		var m := ModelLib.instance("animals/" + id)
		if m == null:
			print("PROBE animals/", id, " missing")
			continue
		print("PROBE animals/", id)
		_dump(m, 1)
		m.free()
	return true


func _dump(n: Node, depth: int) -> void:
	for c in n.get_children():
		var s := "  ".repeat(depth) + c.name + " [" + c.get_class() + "]"
		if c is Node3D:
			s += " pos=" + str((c as Node3D).position)
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var ms := []
			for i in mi.mesh.get_surface_count():
				var mt := mi.mesh.surface_get_material(i)
				ms.append(mt.resource_name if mt != null else "-")
			s += " surf=" + str(ms)
		print("PROBE ", s)
		_dump(c, depth + 1)
