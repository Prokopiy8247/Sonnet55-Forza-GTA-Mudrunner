extends Node
## Prints the location table + road list as markdown (used to write docs/api/world.md).


func run(_main: Node) -> bool:
	WorldLayout.generate()
	var ids: Array = WorldLayout.locations.keys()
	ids.sort()
	for id in ids:
		var l: Dictionary = WorldLayout.locations[id]
		var p: Vector3 = l["pos"]
		print("LOC| `%s` | (%.1f, %.1f, %.1f) | %.0f | %s | %s" % [id, p.x, p.y, p.z, rad_to_deg(float(l["yaw"])), l["kind"], l["name"]])
	var names := {}
	for e in LayoutRoadNet.edges:
		var k: String = "%s|%s" % [e["name"], e["cls"]]
		names[k] = float(names.get(k, 0.0)) + float(e["len"])
	for k in names:
		print("ROAD| %s | %.0f m" % [k, names[k]])
	for lot in WorldLayout.lots:
		if lot["kind"] == &"landmark":
			var r: Rect2 = lot["rect"]
			print("LM| %s | rect(%.1f,%.1f,%.1f,%.1f) | face %s" % [lot["landmark"], r.position.x, r.position.y, r.size.x, r.size.y, lot["side"]])
	for s in WorldLayout.signals:
		print("SIG| %d %s (%.0f, %.0f)" % [s["id"], s["node"], s["pos"].x, s["pos"].z])
	return true
