extends SceneTree
## Lists every mesh of characters/human.glb with its surface material names + skeleton rest data (positions / bone axes).
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/rig_probe.gd

func _initialize() -> void:
	var scene := load("res://gta/generated/models/characters/human.glb") as PackedScene
	if scene == null:
		print("RIGPROBE FAIL: no human.glb")
		quit(1)
		return
	var root := scene.instantiate() as Node3D
	var sk: Skeleton3D = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			sk = n
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mats: Array[String] = []
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				var arrs: Array = mi.mesh.surface_get_arrays(i)
				var idx_arr: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
				var tri: int = idx_arr.size() / 3
				mats.append("%s(%dt)" % [m.resource_name if m != null else "-", tri])
			print("RIGPROBE mesh ", mi.name, " ", mats)
		for c in n.get_children():
			stack.append(c)
	if sk != null:
		print("RIGPROBE skeleton node transform=", sk.transform, " global=", sk.global_transform)
		for i in sk.get_bone_count():
			var g := sk.get_bone_global_rest(i)
			print("RIGPROBE bone %-12s parent=%-12s head=%s y_axis=%s" % [sk.get_bone_name(i), sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else "-", g.origin, g.basis.y])
	quit(0)
