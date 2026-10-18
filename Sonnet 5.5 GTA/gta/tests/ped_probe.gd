extends Node
## Probe (peds): prints facts needed to debug the pedestrian module. Not a test.
##   tools\gd.ps1 exec -Script res://gta/tests/ped_probe.gd -Seconds 30 -GameArgs "--no-traffic"


func run(_main: Node) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pm: PedManager = Game.sys(&"peds")
	pm.auto_population = false
	pm.clear_all(true)
	var pg: PedGraph = WorldLayout.ped_graph
	var space := get_viewport().world_3d.direct_space_state
	print("PROBE heights fixed: %d" % PedNav.heights_fixed)
	for i in pg.size():
		if pg.zone[i] != PedGraph.ZONE_DOCK:
			continue
		var np := PedNav.node_pos(i)
		if np.y >= -0.6:
			continue
		var p: Vector3 = pg.positions[i]
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 14.0, 0), p + Vector3(0, -6.0, 0), GC.M_GROUND)
		var hit := space.intersect_ray(q)
		var links := []
		for n in pg.links[i]:
			links.append("%d(y=%.2f)" % [n, PedNav.node_y(n)])
		print("PROBE low dock node %d pos=%s fixed_y=%.2f hit=%s links=%s" % [i, p, np.y, (hit["collider"].name + "@%.2f" % hit["position"].y) if not hit.is_empty() else "none", links])
