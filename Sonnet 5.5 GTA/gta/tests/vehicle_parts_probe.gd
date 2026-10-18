extends SceneTree
## Batch probe for the lane-11 vehicle customisation parts (res://gta/generated/models/vehicle_parts/*.glb).
##   powershell -NoProfile -File tools\gd.ps1 import
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/vehicle_parts_probe.gd [-GameArgs "wheel_stock"]
## Prints one VPART line per file (tris, node names, material names, AABB in Godot axes) and a summary; checks the contract:
## node `Body` (+ `Mount`) for parts, `Tire` + `Rim` (+ `Mount`) for wheel_*, tri budgets (<=400 parts, <=500 wheels), forward = -Z for parts.
## Self-contained on purpose (scripts run with --script are compiled before the autoloads exist).

const DIR := "res://gta/generated/models/vehicle_parts/"


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
	var files: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		print("VPART FAIL: cannot open ", DIR)
		quit(1)
		return
	for f in d.get_files():
		if f.ends_with(".glb"):
			files.append(f.get_basename())
	files.sort()
	var fails := 0
	var total_tris := 0
	for id: String in files:
		if only.size() > 0 and not only.has(id):
			continue
		var res := load(DIR + id + ".glb")
		if res == null or not (res is PackedScene):
			print("VPART FAIL ", id, " cannot load (run tools\\gd.ps1 import first)")
			fails += 1
			continue
		var n := (res as PackedScene).instantiate() as Node3D
		var tris := 0
		var mats := {}
		var bb := AABB()
		var have := false
		var names := []
		for c in n.get_children():
			names.append(c.name)
		for mi in _meshes(n):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var b: AABB = _rel(n, m) * m.get_aabb()
			bb = b if not have else bb.merge(b)
			have = true
			for s in m.mesh.get_surface_count():
				var arr: Array = m.mesh.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				var vtx = arr[Mesh.ARRAY_VERTEX]
				tris += (idx.size() if idx != null and idx.size() > 0 else vtx.size()) / 3
				var mt: Material = m.mesh.surface_get_material(s)
				mats[mt.resource_name if mt != null else "<none>"] = true
		total_tris += tris
		var is_wheel := id.begins_with("wheel_")
		var ok := true
		var why := []
		if is_wheel:
			for need in ["Tire", "Rim", "Mount"]:
				if n.find_child(need, true, false) == null:
					ok = false
					why.append("missing " + need)
			if tris > 500:
				ok = false
				why.append("tris>500")
		else:
			for need in ["Body", "Mount"]:
				if n.find_child(need, true, false) == null:
					ok = false
					why.append("missing " + need)
			if tris > 400:
				ok = false
				why.append("tris>400")
		if not have:
			ok = false
			why.append("no mesh")
		if not ok:
			fails += 1
		print("VPART ", "OK  " if ok else "FAIL", " ", id, " tris=", tris, " nodes=", names, " mats=", mats.keys(), " size=", bb.size.snappedf(0.001), " min=", bb.position.snappedf(0.001), " max=", bb.end.snappedf(0.001), " ", why)
		n.free()
	print("VPART SUMMARY files=", files.size(), " fails=", fails, " total_tris=", total_tris)
	quit(1 if fails > 0 else 0)


func _meshes(root: Node) -> Array:
	var out := []
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
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
