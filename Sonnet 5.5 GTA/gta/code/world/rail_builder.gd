class_name RailBuilder
extends RefCounted
## Elevated light-rail viaduct (WorldLayout.rail): concrete deck over the street centre line, portal pillars on the sidewalks,
## two rails + sleepers, platform slabs at the stations. The train itself belongs to the Systems agent (transit).


static func build(rb: RoadBuilder) -> void:
	var rail: Dictionary = WorldLayout.rail
	if rail.is_empty():
		return
	var pts: PackedVector3Array = rail["points"]
	var deck_y: float = rail["deck_y"]
	var z: float = rail["z"]
	var x0 := pts[0].x - 6.0
	var x1 := pts[pts.size() - 1].x + 6.0
	# deck beam (3.4 wide, 0.8 thick) split into 16 m pieces so each lands in its sector
	var x := x0
	while x < x1:
		var xe := minf(x + 16.0, x1)
		rb.add_box("viaduct", Vector3((x + xe) * 0.5, deck_y - 0.4, z), Vector3(xe - x, 0.8, 3.4))
		# rails + sleepers
		for sgn in [-1.0, 1.0]:
			rb.add_box("rail", Vector3((x + xe) * 0.5, deck_y + 0.09, z + float(sgn) * 0.75), Vector3(xe - x, 0.18, 0.12))
		var sx := x + 0.5
		while sx < xe:
			rb.add_box("rail", Vector3(sx, deck_y + 0.03, z), Vector3(0.28, 0.06, 2.0))
			sx += 1.0
		x = xe
	# parapets
	x = x0
	while x < x1:
		var xe2 := minf(x + 16.0, x1)
		for sgn in [-1.0, 1.0]:
			rb.add_box("viaduct", Vector3((x + xe2) * 0.5, deck_y + 0.3, z + float(sgn) * 1.65), Vector3(xe2 - x, 0.6, 0.12))
		x = xe2
	# pillars every 24 m on both sidewalks (skip junction areas)
	var node_xs: Array = []
	for id in LayoutRoadNet.node_ids:
		var np: Vector2 = LayoutRoadNet.nodes[id]["pos"]
		if absf(np.y - z) < 3.0:
			node_xs.append(np.x)
	var px := x0 + 10.0
	while px < x1 - 6.0:
		var ok := true
		for nx in node_xs:
			if absf(px - float(nx)) < 19.0:
				ok = false
		if ok:
			var lat := 5.3
			for sgn in [-1.0, 1.0]:
				var gy := LayoutTerrain.height(px, z + float(sgn) * lat) + 0.15
				var top := deck_y - 0.8
				rb.add_box("viaduct", Vector3(px, (gy + top) * 0.5, z + float(sgn) * lat), Vector3(0.9, top - gy, 0.9))
			rb.add_box("viaduct", Vector3(px, deck_y - 1.1, z), Vector3(1.0, 0.6, 2.0 * lat + 0.9))
		px += 24.0
	# platforms
	for key in ["platform_a", "platform_b"]:
		var pp: Vector3 = rail[key]
		rb.add_box("viaduct", Vector3(pp.x, deck_y - 0.25, z - 2.7), Vector3(24.0, 0.5, 2.0))
		rb.add_box("rail", Vector3(pp.x, deck_y + 0.05, z - 2.7), Vector3(24.0, 0.1, 1.8))
		for k in 5:
			rb.add_box("viaduct", Vector3(pp.x - 9.0 + k * 4.5, deck_y - 4.2, z - 2.7), Vector3(0.5, 8.0, 0.5))
