extends Node
## Lane-9 in-world check: parks a free camera next to the N-th WorldLayout.furniture item of a kind so the real placed GLB can be judged.
##   tools\gd.ps1 shot -Out screenshots\peek_signal.png -GameArgs "--exec=res://gta/tests/lane9_world_peek.gd --delay=6 --time=17"
## Env: PEEK_KIND (signal|lamp|bench|bus_stop|hydrant|bin|cone|barrier|fence|billboard ...), PEEK_IDX (default 0), PEEK_DIST (default 9), PEEK_H (look height, default 2)


func run(main: Node) -> Variant:
	var kind := StringName(OS.get_environment("PEEK_KIND") if OS.get_environment("PEEK_KIND") != "" else "signal")
	var idx := int(OS.get_environment("PEEK_IDX")) if OS.get_environment("PEEK_IDX") != "" else 0
	var dist := float(OS.get_environment("PEEK_DIST")) if OS.get_environment("PEEK_DIST") != "" else 9.0
	var h := float(OS.get_environment("PEEK_H")) if OS.get_environment("PEEK_H") != "" else 2.0
	var found: Array = []
	for it in WorldLayout.furniture:
		if StringName(it.get("kind", &"")) == kind:
			found.append(it)
	print("PEEK kind=", kind, " count=", found.size(), " of ", WorldLayout.furniture.size())
	if found.is_empty():
		return "none"
	var item: Dictionary = found[mini(idx, found.size() - 1)]
	var pos: Vector3 = item.get("pos", Vector3.ZERO)
	var yaw := float(item.get("yaw", 0.0))
	print("PEEK item pos=", pos, " yaw=", yaw)
	if is_instance_valid(Game.player):
		Game.player.teleport_to(pos + Vector3(0, 0.5, 6.0), 0.0)
	await get_tree().create_timer(2.0).timeout
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var side := fwd.cross(Vector3.UP)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 800.0
	main.add_child(cam)
	var cp := pos + fwd * dist * 0.8 + side * dist * 0.5 + Vector3(0, h + 1.0, 0)
	cam.look_at_from_position(cp, pos + Vector3(0, h, 0), Vector3.UP)
	cam.make_current()
	for i in 20:
		await get_tree().process_frame
	return "ok"
