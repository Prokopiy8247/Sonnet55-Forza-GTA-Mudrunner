extends Node
## Dev probe for the Activities module (prints world facts the activities are built on). Not a regression test.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/activity_probe.gd -Seconds 40 -GameArgs "--no-traffic --no-peds"


func run(_main: Node) -> String:
	await get_tree().create_timer(1.0).timeout
	_anchors()
	_roads()
	_stunts()
	_peak()
	_sea()
	return "done"


func _anchors() -> void:
	var loc: Dictionary = WorldLayout.get_location(&"shooting_range")
	print("PROBE range loc ", loc)
	for a in get_tree().get_nodes_in_group("landmark_anchor"):
		if a is Node3D and str(a.get_meta("landmark", "")) == "shooting_range":
			var n3 := a as Node3D
			var f := -n3.global_transform.basis.z
			print("PROBE anchor %s pos=%s fwd(-Z)=%s" % [n3.name, n3.global_position, f])
	for a in get_tree().get_nodes_in_group("location_anchor"):
		if a is Node3D and str(a.get_meta("landmark", "")) == "shooting_range":
			print("PROBE locanchor %s pos=%s" % [a.name, (a as Node3D).global_position])


func _roads() -> void:
	var names := {}
	for r in WorldLayout.roads:
		var nm := str(r["name"])
		if not names.has(nm):
			names[nm] = []
		names[nm].append(r)
	for nm in names:
		var rs: Array = names[nm]
		var first: PackedVector2Array = rs[0]["points"]
		var last: PackedVector2Array = rs[rs.size() - 1]["points"]
		print("PROBE road %s kind=%s segs=%d first=%s last=%s" % [nm, rs[0]["kind"], rs.size(), first[0], last[last.size() - 1]])
	print("PROBE lanes=", WorldLayout.lanes.size())


func _stunts() -> void:
	for id in [&"stunt_jump_1", &"stunt_jump_2", &"stunt_jump_3"]:
		var loc: Dictionary = WorldLayout.get_location(id)
		var pos: Vector3 = loc["pos"]
		var dir := Util.yaw_to_dir(float(loc["yaw"]))
		print("PROBE %s pos=%s dir=%s land=%s" % [id, pos, dir, loc.get("land")])
		# run-up scan: terrain height + first collider every 10 m backwards
		var line := ""
		for i in range(0, 14):
			var p := pos - dir * (float(i) * 10.0)
			var space := get_viewport().world_3d.direct_space_state
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 30, 0), p + Vector3(0, -10, 0), GC.L_WORLD)
			var h := space.intersect_ray(q)
			var hy := "-" if h.is_empty() else "%.2f(%s)" % [(h["position"] as Vector3).y, str((h["collider"] as Node).get_meta("surface", "?"))]
			line += " %d:%s" % [i * 10, hy]
		print("PROBE runup ", id, line)


func _peak() -> void:
	var pk: Dictionary = WorldLayout.get_location(&"parachute_peak")
	var pp: Vector3 = pk["pos"]
	print("PROBE peak ", pp)
	# find flat, low spots within 60..160 m
	var best := []
	for r in [40.0, 70.0, 100.0, 130.0, 160.0]:
		for a in range(0, 360, 30):
			var x: float = pp.x + cos(deg_to_rad(a)) * r
			var z: float = pp.z + sin(deg_to_rad(a)) * r
			var h := WorldLayout.terrain_height(x, z)
			best.append("r%d a%d h=%.1f" % [int(r), a, h])
	print("PROBE peak ring ", " | ".join(best))


func _sea() -> void:
	var line := ""
	for z in range(200, 380, 20):
		var row := ""
		for x in range(-280, 100, 20):
			row += "~" if WorldLayout.is_water(x, z) else "#"
		line += "z%d %s\n" % [z, row]
	print("PROBE sea (x -280..80 step20)\n", line)
