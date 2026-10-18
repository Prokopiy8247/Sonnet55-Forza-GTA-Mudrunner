extends Node
## Places a free camera in front of the nearest WorldLayout.furniture item of a kind (or a lot kind) for close-up screenshots.
##   tools\gd.ps1 shot -Out screenshots\x.png -GameArgs "--exec=res://gta/tests/content_closeup.gd --look=signal --dist=7 --height=3 --time=15"
## options: --look=<furniture kind | lot:<kind>>  --dist=<m>  --height=<m>  --skip=<n>  --near=x,z (origin for 'nearest')

func run(main: Node) -> Variant:
	var harness = main.get_node_or_null("DevHarness")
	var opts: Dictionary = harness.opts if harness != null else {}
	var what := String(opts.get("look", "signal"))
	var dist := float(opts.get("dist", 7.0))
	var height := float(opts.get("height", 3.0))
	var skip := int(opts.get("skip", 0))
	var near := Vector2.ZERO
	if opts.has("near"):
		var p := String(opts["near"]).split(",")
		near = Vector2(float(p[0]), float(p[1]))
	var cands: Array = []
	if what.begins_with("lot:"):
		var k := StringName(what.substr(4))
		for lot in WorldLayout.lots:
			if lot.get("kind", &"") == k:
				var r: Rect2 = lot["rect"]
				cands.append({"pos": Vector3(r.get_center().x, 0, r.get_center().y), "yaw": lot["yaw"]})
	else:
		for f in WorldLayout.furniture:
			if f.get("kind", &"") == StringName(what):
				cands.append(f)
	if cands.is_empty():
		print("CLOSEUP none for ", what)
		return false
	cands.sort_custom(func(a, b): return Vector2(a["pos"].x, a["pos"].z).distance_to(near) < Vector2(b["pos"].x, b["pos"].z).distance_to(near))
	var item: Dictionary = cands[mini(skip, cands.size() - 1)]
	var pos: Vector3 = item["pos"]
	var fwd := Util.yaw_to_dir(float(item.get("yaw", 0.0)))
	var cam := Camera3D.new()
	cam.fov = float(opts.get("fov", 60.0))
	cam.far = 800.0
	main.add_child(cam)
	cam.global_position = pos + fwd * dist + Vector3(0, height, 0) + Vector3(-fwd.z, 0, fwd.x) * dist * 0.35
	cam.look_at(pos + Vector3(0, height * 0.8, 0), Vector3.UP)
	cam.make_current()
	print("CLOSEUP ", what, " at ", pos, " yaw=", item.get("yaw"))
	for i in 20:
		await get_tree().process_frame
	return true
