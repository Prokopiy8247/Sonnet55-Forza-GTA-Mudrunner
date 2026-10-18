extends SceneTree
## Developer probe for the air / sea GLBs: lowest vertices (skids, gear, hull), wing / tail extents.
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/air_probe.gd -GameArgs "heli_civil"
## Self-contained on purpose (scripts run with --script are compiled before the autoloads exist).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := String(args[0]) if args.size() > 0 else "heli_civil"
	var p := "res://gta/generated/models/vehicles/" + id + ".glb"
	var scene := load(p) as PackedScene
	if scene == null:
		print("PROBE FAIL ", p)
		quit(1)
		return
	var root := scene.instantiate() as Node3D
	var low := []
	var all_mn := Vector3(1e9, 1e9, 1e9)
	var all_mx := Vector3(-1e9, -1e9, -1e9)
	var by_node := {}
	for mi in _meshes(root):
		if mi.mesh == null:
			continue
		var xf := _rel(root, mi)
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vv:
				var w := xf * v
				mn = mn.min(w)
				mx = mx.max(w)
				all_mn = all_mn.min(w)
				all_mx = all_mx.max(w)
				if w.y < 0.16 and mi.name == &"Body":
					low.append(w)
		by_node[String(mi.name)] = [mn, mx]
	for k in by_node:
		print("PROBE node ", k, " min=", by_node[k][0], " max=", by_node[k][1])
	print("PROBE all min=", all_mn, " max=", all_mx)
	# cluster the low vertices by (sign x, z bucket)
	var buckets := {}
	for w in low:
		var key := "%s_%d" % ["L" if w.x < 0 else "R", int(round(w.z / 0.5))]
		if not buckets.has(key):
			buckets[key] = [w, w, 0]
		var b: Array = buckets[key]
		b[0] = (b[0] as Vector3).min(w)
		b[1] = (b[1] as Vector3).max(w)
		b[2] += 1
	var keys := buckets.keys()
	keys.sort()
	for k in keys:
		print("PROBE low ", k, " n=", buckets[k][2], " min=", buckets[k][0], " max=", buckets[k][1])
	quit(0)


func _meshes(n: Node) -> Array:
	var out := []
	var st := [n]
	while not st.is_empty():
		var c = st.pop_back()
		if c is MeshInstance3D:
			out.append(c)
		for ch in c.get_children():
			st.append(ch)
	return out


func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
