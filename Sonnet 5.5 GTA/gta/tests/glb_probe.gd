extends SceneTree
## Inspect an imported Blender GLB: node tree, transforms, mesh/material names, triangle count, AABB and skeleton.
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/glb_probe.gd -GameArgs "vehicles/sedan [depth]"
## Prints PROBE lines. Orientation check: the FRONT of a vehicle/weapon/character must be on the -Z side.
## Run `tools\gd.ps1 import` first so freshly exported GLBs are imported.
## NOTE: this file is deliberately self-contained (no project class_name references) because main scripts run with
## --script are compiled BEFORE the autoloads exist.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("PROBE usage: -GameArgs \"vehicles/sedan [depth]\"")
		quit(2)
		return
	var rel := String(args[0])
	var max_depth := int(args[1]) if args.size() > 1 else 4
	var p := "res://gta/generated/models/" + rel + ".glb"
	if not ResourceLoader.exists(p):
		print("PROBE FAIL: not found / not imported: ", p)
		quit(1)
		return
	var scene := load(p) as PackedScene
	var n := scene.instantiate() as Node3D
	var tris := 0
	var surfaces := 0
	var mats := {}
	var meshes := _meshes(n)
	var have := false
	var bb := AABB()
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var xf: Transform3D = _rel(n, mi)
		var b: AABB = xf * mi.get_aabb()
		bb = b if not have else bb.merge(b)
		have = true
		for s in mi.mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var idx = arrays[Mesh.ARRAY_INDEX]
			var vtx = arrays[Mesh.ARRAY_VERTEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else vtx.size()) / 3
			var m: Material = mi.mesh.surface_get_material(s)
			mats[m.resource_name if m != null else "<none>"] = true
	print("PROBE ", rel, ": meshes=", meshes.size(), " surfaces=", surfaces, " tris=", tris)
	print("PROBE aabb size=", bb.size, " min=", bb.position, " max=", bb.end)
	print("PROBE front(-Z) extent=", -bb.position.z, "  back(+Z) extent=", bb.end.z, "  right(+X)=", bb.end.x, "  left(-X)=", -bb.position.x, "  height=", bb.end.y, "  below_origin=", -bb.position.y)
	print("PROBE materials=", mats.keys())
	_dump(n, 0, max_depth)
	for sk in _find_class(n, "Skeleton3D"):
		var names := []
		for i in (sk as Skeleton3D).get_bone_count():
			names.append((sk as Skeleton3D).get_bone_name(i))
		print("PROBE skeleton '", sk.name, "' bones=", names.size(), " ", names)
	for ap in _find_class(n, "AnimationPlayer"):
		print("PROBE animations=", (ap as AnimationPlayer).get_animation_list())
	n.free()
	quit(0)


func _meshes(root: Node) -> Array:
	return _find_class(root, "MeshInstance3D")


func _find_class(root: Node, cls: String) -> Array:
	var out := []
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _dump(node: Node, depth: int, max_depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if node is Node3D:
		extra = " pos=" + str((node as Node3D).position.snappedf(0.001))
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		extra += " aabb=" + str((node as MeshInstance3D).get_aabb().size.snappedf(0.01))
	print("PROBE ", pad, node.name, " [", node.get_class(), "]", extra)
	if depth >= max_depth:
		return
	for c in node.get_children():
		_dump(c, depth + 1, max_depth)
