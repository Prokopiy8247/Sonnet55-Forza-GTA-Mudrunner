extends Node
## Dev dump (Systems-A): lists every placed pickup / ladder / booth and probes the spots that could not be resolved.
##   tools\gd.ps1 exec -Script res://gta/tests/economy_dump.gd -Seconds 40 -GameArgs "--no-traffic --no-peds"


func run(_main: Node) -> Variant:
	for i in 40:
		await get_tree().physics_frame
	var eco = Game.sys(&"economy")
	if eco == null:
		print("DUMP no economy")
		return false
	for s in eco.spots:
		var p: Vector3 = s["pos"]
		print("DUMP SPOT %-22s %-12s %-8s (%.1f, %.1f, %.1f) amt=%d" % [s["id"], str(s["kind"]), s["group"], p.x, p.y, p.z, int(s["amount"])])
	var im = Game.sys(&"interactions")
	for r in im.ladders:
		var b: Vector3 = r["bottom"]
		print("DUMP LADDER %s lot=%d %s bottom=(%.1f, %.1f, %.1f) roof_y=%.1f n=%s reward=%s" % [r["id"], int(r["lot"]), str(r["district"]), b.x, b.y, b.z, float(r["roof_y"]), str(r["normal"]), str(r.get("reward", {}).get("amount", -1))])
	for b in im.booths:
		print("DUMP BOOTH %s near=%s pos=%s" % [b["id"], str(b["near"]), str(b["pos"])])
	if not im.elevator.is_empty():
		print("DUMP ELEVATOR ground=%s roof=%s" % [str(im.elevator["ground"]["pos"]), str(im.elevator["roof"]["pos"])])
	# probes for the usual suspects
	for id in [&"shooting_range", &"helipad_hospital", &"airport_terminal", &"park_center", &"district_center_park_hills"]:
		var c: Vector3 = WorldLayout.location_pos(id)
		var th := WorldLayout.terrain_height(c.x, c.z)
		var down := InteractionUtil.ray(Vector3(c.x, c.y + 60.0, c.z), Vector3(c.x, c.y - 20.0, c.z), GC.L_WORLD)
		print("DUMP PROBE %s loc=%s terrain=%.2f topray=%s" % [id, str(c), th, str(down.get("position", "none"))])
	return true
