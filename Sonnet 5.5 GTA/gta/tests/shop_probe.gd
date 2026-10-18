extends SceneTree
## Dev probe (Shops/Interiors agent): compact summary of every interiors/*.glb (AABB, triangles, empties, materials).
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/shop_probe.gd -GameArgs "interiors"
## Self-contained (no project class_name references, see glb_probe.gd).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var cat := String(args[0]) if args.size() > 0 else "interiors"
	var filt := String(args[1]) if args.size() > 1 else ""
	var dir := DirAccess.open("res://gta/generated/models/" + cat)
	if dir == null:
		print("PROBE no dir")
		quit(1)
		return
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".glb") and (filt == "" or f.contains(filt)):
			names.append(f.get_basename())
	names.sort()
	for nm in names:
		var scene := load("res://gta/generated/models/%s/%s.glb" % [cat, nm]) as PackedScene
		if scene == null:
			print("PROBE ", nm, " LOAD FAIL")
			continue
		var n := scene.instantiate() as Node3D
		var tris := 0
		var bb := AABB()
		var have := false
		var mats := {}
		var empties: Array[String] = []
		var stack: Array = [n]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
				var mi := x as MeshInstance3D
				var xf := Transform3D.IDENTITY
				var p: Node = mi
				while p != null and p != n:
					if p is Node3D:
						xf = (p as Node3D).transform * xf
					p = p.get_parent()
				var b := xf * mi.get_aabb()
				bb = b if not have else bb.merge(b)
				have = true
				for s in mi.mesh.get_surface_count():
					var arrays: Array = mi.mesh.surface_get_arrays(s)
					var idx = arrays[Mesh.ARRAY_INDEX]
					var vtx = arrays[Mesh.ARRAY_VERTEX]
					tris += (idx.size() if idx != null and idx.size() > 0 else vtx.size()) / 3
					var m: Material = mi.mesh.surface_get_material(s)
					mats[m.resource_name if m != null else "<none>"] = true
			elif x != n and x is Node3D and x.get_child_count() == 0:
				empties.append("%s@%s" % [x.name, str((x as Node3D).position.snappedf(0.01))])
			for c in x.get_children():
				stack.append(c)
		print("PROBE ", nm, " tris=", tris, " size=", bb.size.snappedf(0.01), " min=", bb.position.snappedf(0.01), " max=", bb.end.snappedf(0.01))
		print("PROBE    mats=", mats.keys(), " empties=", empties)
		var top: Array[String] = []
		for c in n.get_children():
			top.append(String(c.name))
		print("PROBE    children=", top)
		n.free()
	quit(0)
