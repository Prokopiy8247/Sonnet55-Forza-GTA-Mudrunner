extends SceneTree
## Prints per-part AABB (min/max in the part's own space), tri counts and material names of a GLB (for kit adaptation).
##   tools\gd.ps1 script -Script res://gta/tests/content_kit_probe.gd -GameArgs "buildings/kit_office"
## Self-contained (compiled before autoloads exist).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for rel in args:
		var p := "res://gta/generated/models/" + String(rel) + ".glb"
		if not ResourceLoader.exists(p):
			print("KP missing ", p)
			continue
		var root := (load(p) as PackedScene).instantiate() as Node3D
		print("KP ==== ", rel)
		_walk(root, root)
		root.free()
	quit(0)


func _walk(root: Node, n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var bb := mi.get_aabb()
		var tris := 0
		var mats := []
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var idx = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			var m := mi.get_active_material(s)
			mats.append(m.resource_name if m != null else "<none>")
		print("KP %s pos=%s min=%s max=%s tris=%d mats=%s" % [mi.name, str(mi.position.snappedf(0.01)), str(bb.position.snappedf(0.01)), str(bb.end.snappedf(0.01)), tris, str(mats)])
	elif n != root and n is Node3D:
		print("KP [empty] %s pos=%s" % [n.name, str((n as Node3D).position.snappedf(0.01))])
	for c in n.get_children():
		_walk(root, c)
