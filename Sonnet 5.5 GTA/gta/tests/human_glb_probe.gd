extends SceneTree
## Verifies res://gta/generated/models/characters/human.glb (Blender "characters" lane):
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/human_glb_probe.gd
## Checks the 21 deform bones (ARCHITECTURE s12 table), that every mesh is skinned (skin + bone indices/weights), triangle budgets,
## material slot names and the HandSocket empties. Prints HUMAN lines + a final HUMAN RESULT PASS|FAIL.
## Self-contained (no project class_name references) because --script runs before autoloads exist.

const BONES := ["Hips", "Spine", "Chest", "Neck", "Head", "Shoulder_R", "UpperArm_R", "LowerArm_R", "Hand_R", "UpperLeg_R", "LowerLeg_R", "Foot_R", "Toe_R",
	"Shoulder_L", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperLeg_L", "LowerLeg_L", "Foot_L", "Toe_L"]
const MESHES := ["Body_A", "Body_B", "Body_C", "Hair_1", "Hair_2", "Hair_3", "Hair_4", "Hair_5", "Hair_6", "Beard_1", "Beard_2", "Hat_Cap", "Hat_Beanie",
	"Hat_Police", "Helmet_Tactical", "Glasses_Round", "Glasses_Shades", "Vest_Armor", "Vest_Tactical", "Jacket_Short", "Jacket_Long", "Backpack"]


func _initialize() -> void:
	var fails := 0
	var p := "res://gta/generated/models/characters/human.glb"
	if not ResourceLoader.exists(p):
		print("HUMAN FAIL: missing ", p)
		quit(1)
		return
	var root := (load(p) as PackedScene).instantiate() as Node3D
	var skels := _find(root, "Skeleton3D")
	if skels.size() != 1:
		print("HUMAN FAIL: expected 1 Skeleton3D, got ", skels.size())
		fails += 1
	var sk: Skeleton3D = skels[0] if skels.size() > 0 else null
	if sk != null:
		print("HUMAN skeleton node '", sk.name, "' path=", root.get_path_to(sk), " bones=", sk.get_bone_count())
		if sk.get_bone_count() != BONES.size():
			print("HUMAN FAIL: bone count ", sk.get_bone_count(), " != ", BONES.size())
			fails += 1
		for b in BONES:
			if sk.find_bone(b) < 0:
				print("HUMAN FAIL: missing bone ", b)
				fails += 1
		for i in sk.get_bone_count():
			var bn := sk.get_bone_name(i)
			if not BONES.has(bn):
				print("HUMAN FAIL: unexpected bone ", bn)
				fails += 1
		# rest positions (model space) of a few bones for orientation sanity: Godot Y up, front = -Z
		for b in ["Hips", "Head", "UpperArm_R", "Hand_R", "Foot_R", "Toe_R"]:
			var idx := sk.find_bone(b)
			if idx >= 0:
				var rp := sk.get_bone_global_rest(idx).origin
				print("HUMAN rest ", b, " = ", snappedf(rp.x, 0.001), ", ", snappedf(rp.y, 0.001), ", ", snappedf(rp.z, 0.001))
	var total_tris := 0
	var found := {}
	for mi: MeshInstance3D in _find(root, "MeshInstance3D"):
		if mi.mesh == null:
			continue
		found[String(mi.name)] = true
		var tris := 0
		var mats := []
		var skinned := true
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var idx = arrays[Mesh.ARRAY_INDEX]
			var vtx = arrays[Mesh.ARRAY_VERTEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else vtx.size()) / 3
			var bones = arrays[Mesh.ARRAY_BONES]
			var wts = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or bones.size() == 0 or wts == null or wts.size() == 0:
				skinned = false
			var m: Material = mi.mesh.surface_get_material(s)
			mats.append(m.resource_name if m != null else "<none>")
		var has_skin := mi.skin != null
		var budget := 4500 if String(mi.name).begins_with("Body_") else 400
		var ok := skinned and has_skin and tris <= budget
		if not ok:
			fails += 1
		total_tris += tris
		print("HUMAN mesh ", mi.name, " tris=", tris, "/", budget, " skin=", has_skin, " weights=", skinned, " skeleton=", mi.get_skeleton_path(), " mats=", mats, " ", "OK" if ok else "FAIL")
	for m in MESHES:
		if not found.has(m):
			print("HUMAN FAIL: mesh missing ", m)
			fails += 1
	for n in ["HandSocket_R", "HandSocket_L"]:
		var node := root.find_child(n, true, false)
		if node == null:
			print("HUMAN FAIL: missing ", n)
			fails += 1
		else:
			var xf := _rel(root, node as Node3D)
			print("HUMAN ", n, " model pos=", xf.origin.snappedf(0.001))
	print("HUMAN total_tris(all meshes)=", total_tris)
	print("HUMAN RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	root.free()
	quit(0 if fails == 0 else 1)


func _find(root: Node, cls: String) -> Array:
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
