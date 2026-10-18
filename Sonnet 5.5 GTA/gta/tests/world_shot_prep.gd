extends Node
## Screenshot preparation for the World agent: hides the HUD, optionally disables fog / glow so wide top-down views are readable.
## Use together with --shot:   --exec=res://gta/tests/world_shot_prep.gd  (options: --nofog, --nohud via GameArgs "hud=0 fog=0")


func run(main: Node) -> bool:
	var args := OS.get_cmdline_user_args()
	var hide_hud := true
	var fog_off := true
	for a in args:
		if String(a) == "--hud=1":
			hide_hud = false
		if String(a) == "--fog=1":
			fog_off = false
	if hide_hud and is_instance_valid(Game.ui):
		if Game.ui is CanvasLayer:
			(Game.ui as CanvasLayer).visible = false
		else:
			for c in Game.ui.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	for l in main.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if hide_hud:
			(l as CanvasLayer).visible = false
	if fog_off:
		for we in main.get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var env: Environment = (we as WorldEnvironment).environment
			if env != null:
				env.fog_enabled = false
				env.volumetric_fog_enabled = false
	if is_instance_valid(Game.player):
		Game.player.visible = false
	for a in args:
		if String(a) == "--lanes=1":
			_draw_lanes(main)
		if String(a) == "--peds=1":
			_draw_peds(main)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	await main.get_tree().create_timer(0.8).timeout
	return true


func _line_mesh(main: Node, name_: String, verts: PackedVector3Array, cols: PackedColorArray) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 100
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	main.add_child(mi)


func _draw_lanes(main: Node) -> void:
	var g: LaneGraph = WorldLayout.lanes
	var v := PackedVector3Array()
	var c := PackedColorArray()
	for i in g.size():
		var p: Vector3 = g.positions[i] + Vector3(0, 0.4, 0)
		for n in (g.next[i] as PackedInt32Array):
			var q: Vector3 = g.positions[n] + Vector3(0, 0.4, 0)
			v.append(p)
			v.append(q)
			var col := Color(0.2, 0.7, 1.0)
			if g.kind[n] == LaneGraph.KIND_CONNECTOR:
				col = Color(1.0, 0.85, 0.2)
			elif g.kind[n] == LaneGraph.KIND_HIGHWAY:
				col = Color(0.4, 1.0, 0.5)
			c.append(col)
			c.append(col.lerp(Color(1, 1, 1), 0.6))
		if g.signal_id[i] >= 0:
			var col2 := Color(1, 0.1, 0.1) if g.signal_phase[i] == 0 else Color(1, 0.3, 1)
			v.append(p)
			v.append(p + Vector3(0, 3.0, 0))
			c.append(col2)
			c.append(col2)
	_line_mesh(main, "DebugLanes", v, c)


func _draw_peds(main: Node) -> void:
	var g: PedGraph = WorldLayout.ped_graph
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var zc := [Color(0.9, 0.9, 0.9), Color(1, 0.2, 0.2), Color(0.3, 1, 0.3), Color(1, 1, 0.2), Color(1, 0.6, 0.2), Color(0.3, 0.8, 1), Color(0.5, 0.5, 0.5)]
	for i in g.size():
		var p: Vector3 = g.positions[i] + Vector3(0, 0.5, 0)
		for n in (g.links[i] as PackedInt32Array):
			if n < i:
				continue
			var q: Vector3 = g.positions[n] + Vector3(0, 0.5, 0)
			v.append(p)
			v.append(q)
			c.append(zc[g.zone[i]])
			c.append(zc[g.zone[n]])
	_line_mesh(main, "DebugPeds", v, c)
