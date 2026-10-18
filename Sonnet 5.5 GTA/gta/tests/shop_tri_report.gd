extends Node
## Dev: triangle breakdown per interior (boxes / props / other). exec: tools\gd.ps1 exec -Script res://gta/tests/shop_tri_report.gd
func _tris(n: Node) -> int:
	var t := 0
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			t += (x as MeshInstance3D).mesh.get_faces().size() / 3
		for c in x.get_children():
			stack.append(c)
	return t

func run(_main: Node) -> void:
	for i in 40:
		await get_tree().process_frame
	var it = Game.sys(&"interiors")
	for id in it.list_interiors():
		var room: InteriorRoom = it.get_room(id)
		var box_t := 0
		var box_n := 0
		var prop_t := 0
		var props: Array = []
		var other_t := 0
		for c in room.get_children():
			if c == room.clerk:
				continue
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
				box_t += 12
				box_n += 1
			elif c is MeshInstance3D:
				other_t += _tris(c)
			elif c is Node3D and room.props.has(c):
				var t := _tris(c)
				prop_t += t
				props.append("%s=%d" % [c.name, t])
			elif c is Node3D:
				other_t += _tris(c)
		print("TEST tri_report ", id, " boxes=", box_n, "(", box_t, " tris) props=", prop_t, " other=", other_t, " :: ", ", ".join(props))
