extends Node
## Dev probe (Systems-A): dumps tall lots, landmark anchors and locations so the ladder / pickup tables can be authored.
##   tools\gd.ps1 exec -Script res://gta/tests/interactions_probe.gd -Seconds 30 -GameArgs "--no-traffic --no-peds"


func run(_main: Node) -> Variant:
	for i in 10:
		await get_tree().physics_frame
	var tall: Array = []
	for lot in WorldLayout.lots:
		var h: float = float(lot.get("height", 0.0))
		if h >= 12.0 or lot.get("kind", &"") == &"landmark":
			tall.append(lot)
	print("PROBE lots total=", WorldLayout.lots.size(), " tall/landmark=", tall.size())
	for lot in tall:
		var r: Rect2 = lot["rect"]
		print("PROBE LOT id=%d kind=%s lm=%s dist=%s floors=%d h=%.1f side=%s rect=(%.1f,%.1f %.1fx%.1f)" % [
			int(lot["id"]), str(lot["kind"]), str(lot["landmark"]), str(lot["district"]), int(lot["floors"]), float(lot["height"]),
			str(lot["side"]), r.position.x, r.position.y, r.size.x, r.size.y])
	for id in WorldLayout.locations:
		var loc: Dictionary = WorldLayout.locations[id]
		var p: Vector3 = loc["pos"]
		print("PROBE LOC %s pos=(%.1f,%.1f,%.1f) yaw=%.0f kind=%s" % [str(id), p.x, p.y, p.z, rad_to_deg(float(loc.get("yaw", 0.0))), str(loc.get("kind", ""))])
	var anchors := get_tree().get_nodes_in_group("landmark_anchor")
	print("PROBE landmark_anchor count=", anchors.size())
	for a in anchors:
		if a is Node3D:
			print("PROBE ANCHOR %s lm=%s pos=%s" % [a.name, str(a.get_meta("landmark", "")), str((a as Node3D).global_position)])
	var la := get_tree().get_nodes_in_group("location_anchor")
	print("PROBE location_anchor count=", la.size())
	return true
