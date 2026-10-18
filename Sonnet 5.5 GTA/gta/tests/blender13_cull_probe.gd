extends SceneTree
## Lane 13 helper: print cull mode / transparency of every material in a GLB.
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/blender13_cull_probe.gd -GameArgs "buildings/shooting_range"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var p := "res://gta/generated/models/" + String(args[0]) + ".glb"
	var scene := load(p) as PackedScene
	var n := scene.instantiate()
	var seen := {}
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			var mi := x as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m is BaseMaterial3D and not seen.has(m.resource_name):
					var bm := m as BaseMaterial3D
					seen[m.resource_name] = true
					print("CULL ", m.resource_name, " cull=", bm.cull_mode, " transp=", bm.transparency, " emis=", bm.emission_enabled, " alpha=", bm.albedo_color.a)
		for c in x.get_children():
			stack.append(c)
	n.free()
	quit(0)
