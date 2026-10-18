extends Node
## Probe: are the naturally spawned peds there and rendered? (real renderer, run through `shot` with --exec)


func run(_main: Node) -> Variant:
	var pm: PedManager = Game.sys(&"peds")
	var cam := Game.gameplay_camera
	print("PROBE peds=%d target=%s pool=%d cheat=%s enabled=%s auto=%s tod=%.1f density_setting=%s" % [pm.peds.size(), pm.stats["target"], pm.pool.size(), Game.cheats.get("pedestrians"), pm.enabled, pm.auto_population, Game.time_of_day, Game.settings.get("ped_density", "none")])
	var hist := {"<20": 0, "20-40": 0, "40-60": 0, "60-90": 0, "90+": 0}
	var infrustum := 0
	for p in pm.peds:
		var dd := Util.dist_xz(p.global_position, pm.player_pos)
		if dd < 20.0:
			hist["<20"] += 1
		elif dd < 40.0:
			hist["20-40"] += 1
		elif dd < 60.0:
			hist["40-60"] += 1
		elif dd < 90.0:
			hist["60-90"] += 1
		else:
			hist["90+"] += 1
		if cam.is_position_in_frustum(p.global_position + Vector3(0, 1, 0)):
			infrustum += 1
	print("PROBE distance histogram (from player): ", hist, " in frustum: ", infrustum, " player=", pm.player_pos, " spawn stats=", pm.stats, " scenes=", pm.spawner.scenes)
	var shown := 0
	var i := 0
	for p in pm.peds:
		var d := cam.global_position.distance_to(p.global_position)
		var meshes := 0
		var vis := 0
		var sh := 0
		for mi in ModelLib.meshes(p.rig.model):
			meshes += 1
			if mi.is_visible_in_tree():
				vis += 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				sh += 1
		var infr := cam.is_position_in_frustum(p.global_position + Vector3(0, 1, 0))
		if i < 12:
			print("PROBE ped %d d=%.0f frustum=%s meshes=%d visible=%d shadow=%d lod=%d tier=%d state=%s vis_end=%.0f" % [i, d, infr, meshes, vis, sh, p.rig.lod, p.tier, p.get_state_name(), (ModelLib.meshes(p.rig.model)[0] as MeshInstance3D).visibility_range_end])
		i += 1
	return null
