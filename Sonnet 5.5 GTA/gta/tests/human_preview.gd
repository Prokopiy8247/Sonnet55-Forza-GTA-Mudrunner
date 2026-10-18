extends Node
## In-engine visual check of characters/human.glb: a lineup of recoloured variants + one posed in Godot (proves skinning/rest data).
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\human_godot.png -Seconds 90 -GameArgs "--exec=res://gta/tests/human_preview.gd --delay=5 --time=14"
## Not a regression test: it only builds the scene the harness photographs. Self-contained (colours by material NAME, like the Rig agent will).

const PATH := "res://gta/generated/models/characters/human.glb"
const ALL := ["Body_A", "Body_B", "Body_C", "Hair_1", "Hair_2", "Hair_3", "Hair_4", "Hair_5", "Hair_6", "Beard_1", "Beard_2", "Hat_Cap", "Hat_Beanie",
	"Hat_Police", "Helmet_Tactical", "Glasses_Round", "Glasses_Shades", "Vest_Armor", "Vest_Tactical", "Jacket_Short", "Jacket_Long", "Backpack"]

# [parts shown, colours by material name]
const CAST := [
	[["Body_A", "Hair_1", "Hat_Cap", "Glasses_Round"], {"Skin": "#d9a77c", "Hair": "#4a3022", "Shirt": "#e8795f", "Pants": "#25324d", "Shoes": "#f2f0ea", "Accent": "#34e0ff"}],
	[["Body_B", "Hair_4", "Jacket_Short"], {"Skin": "#8a5a3c", "Hair": "#1a1512", "Shirt": "#2f9c95", "Pants": "#2a2d33", "Shoes": "#a4553f", "Accent": "#e0b04a"}],
	[["Body_C", "Hair_6", "Beard_1", "Vest_Tactical"], {"Skin": "#f1c9a5", "Hair": "#a8482a", "Shirt": "#7ea286", "Pants": "#4b525b", "Shoes": "#15171a", "Accent": "#2a2d33"}],
	[["Body_A", "Hat_Police", "Vest_Armor", "Beard_2"], {"Skin": "#b57e57", "Hair": "#1a1512", "Shirt": "#5b7fa6", "Pants": "#25324d", "Shoes": "#15171a", "Accent": "#25324d"}],
	[["Body_B", "Hair_3", "Glasses_Shades", "Backpack"], {"Skin": "#f1c9a5", "Hair": "#d6b46a", "Shirt": "#7b4b7a", "Pants": "#5b7fa6", "Shoes": "#f2cf3a", "Accent": "#ff3d9a"}],
	[["Body_C", "Hair_5", "Jacket_Long", "Glasses_Round"], {"Skin": "#5e3b27", "Hair": "#1a1512", "Shirt": "#25324d", "Pants": "#25324d", "Shoes": "#f2f0ea", "Accent": "#34e0ff"}],
]


func _mode() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--hp="):
			return String(a).substr(5)
	return "all"


func run(main: Node) -> void:
	var mode := _mode()
	var origin := Vector3.ZERO
	var gp = Game.get("player")
	if gp != null and is_instance_valid(gp):
		origin = (gp as Node3D).global_position + Vector3(0, 0, 0)
		(gp as Node3D).visible = false
	var scene := load(PATH) as PackedScene
	var root := Node3D.new()
	root.name = "HumanPreview"
	main.add_child(root)
	root.global_position = origin + Vector3(0, 0.02, 4.0)
	var n := (CAST.size() + 1) if mode == "all" else 1
	for i in (CAST.size() if mode == "all" else 0):
		var inst := scene.instantiate() as Node3D
		root.add_child(inst)
		inst.position = Vector3((i - (n - 1) * 0.5) * 1.05, 0, 0)
		_setup(inst, CAST[i][0], CAST[i][1])
	# last figure: posed in Godot (arm raised, elbow bent, knee bent, torso bent, head down) to prove skinning + rest data
	var posed := scene.instantiate() as Node3D
	root.add_child(posed)
	posed.position = Vector3((n - 1 - (n - 1) * 0.5) * 1.05, 0, 0)
	_setup(posed, ["Body_A", "Hair_2", "Jacket_Short"], {"Skin": "#d9a77c", "Hair": "#4a3022", "Shirt": "#e0b04a", "Pants": "#25324d", "Shoes": "#1b1c1f", "Accent": "#ff3d9a"})
	var sk := _find_skeleton(posed)
	if sk != null:
		if mode in ["all", "arms"]:
			_pose(sk, "UpperArm_R", 80.0)
			_pose(sk, "LowerArm_R", 90.0)
			_pose(sk, "UpperArm_L", 35.0)
		if mode in ["all", "legs"]:
			_pose(sk, "UpperLeg_R", 55.0)
			_pose(sk, "LowerLeg_R", -80.0)
			_pose(sk, "UpperLeg_L", -20.0)
		if mode in ["all", "spine"]:
			_pose(sk, "Spine", -15.0)
		if mode in ["all", "head"]:
			_pose(sk, "Head", -12.0)
	# camera on the -Z side looking +Z; the characters face -Z (towards the camera)
	var cam := Camera3D.new()
	cam.name = "HumanPreviewCam"
	cam.fov = 38.0
	main.add_child(cam)
	cam.global_position = root.global_position + Vector3(0.0, 1.25, -7.5 if mode == "all" else -3.2)
	cam.look_at(root.global_position + Vector3(0.0, 0.95, 0.0), Vector3.UP)
	cam.make_current()
	await get_tree().create_timer(1.0).timeout


func _setup(inst: Node3D, shown: Array, colours: Dictionary) -> void:
	var mats := {}
	for k in colours:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(colours[k])
		m.roughness = 0.85
		m.resource_name = k
		mats[k] = m
	for mi in _meshes(inst):
		var vis := shown.has(String(mi.name))
		mi.visible = vis
		if not vis or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			var nm := src.resource_name if src != null else ""
			if mats.has(nm):
				mi.set_surface_override_material(s, mats[nm])


func _pose(sk: Skeleton3D, bone: String, deg_x: float) -> void:
	## Godot 4 bone pose = absolute LOCAL transform (not an offset from rest). Rotate the bone about the model-space +X axis by deg_x
	## (forward = -Z, so + swings a hanging limb forward) on top of the rest pose, assuming the parent chain is at rest or only X-rotated.
	var idx := sk.find_bone(bone)
	if idx < 0:
		return
	var par := sk.get_bone_parent(idx)
	var pg := sk.get_bone_global_rest(par).basis if par >= 0 else Basis.IDENTITY
	var r := Basis(Vector3.RIGHT, deg_to_rad(deg_x))
	var local := pg.inverse() * r * pg * sk.get_bone_rest(idx).basis
	sk.set_bone_pose_rotation(idx, local.get_rotation_quaternion())


func _meshes(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
