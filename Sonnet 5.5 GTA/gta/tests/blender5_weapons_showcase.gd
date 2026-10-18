extends Node
## Lane-5 weapon GLB showcase (visual QA of the Blender weapon models). Spawns the GLBs on a private stage high above the world.
##   tools\gd.ps1 shot -Out screenshots\wpn_a.png -GameArgs "--exec=res://gta/tests/blender5_weapons_showcase.gd --delay=3 --time=12"
## Env vars: WPN_SHOW (comma separated ids, default = all weapons), WPN_ATT (comma list of att ids to mount on every weapon that has the mounts),
##           WPN_CAM ("x,y,z,tx,ty,tz"), WPN_YAW (degrees, default 90 = right side towards the camera), WPN_COLS (columns, default 5).

const WEAPONS: Array[String] = ["pistol", "revolver", "smg", "carbine", "rifle_assault", "rifle_marksman", "shotgun_pump", "shotgun_auto",
	"sniper", "rocket_launcher", "grenade_launcher", "knife", "bat", "crowbar", "grenade"]
const ATTS: Array[String] = ["att_suppressor", "att_scope", "att_flashlight", "att_grip", "att_magazine_ext"]
var _cam: Camera3D

const MOUNT_OF := {"att_suppressor": "AttMuzzle", "att_scope": "AttOptic", "att_flashlight": "AttRail", "att_grip": "AttGrip", "att_magazine_ext": "AttMag"}


func _load(id: String) -> Node3D:
	var path := "res://gta/generated/models/weapons/%s.glb" % id
	if not ResourceLoader.exists(path):
		push_warning("showcase: missing " + path)
		return null
	return (load(path) as PackedScene).instantiate() as Node3D


func run(main: Node) -> Variant:
	var root := Node3D.new()
	root.name = "WeaponShowcase"
	main.add_child(root)
	root.global_position = Vector3(0, 500, 0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root.add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sm.ground_bottom_color = Color(0.25, 0.26, 0.3)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.66)
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)
	# backdrop so silhouettes read
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(60, 30)
	back.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.55, 0.6, 0.66)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.material_override = bm
	back.position = Vector3(0, 3, -1.5)
	root.add_child(back)

	var ids: Array[String] = WEAPONS
	var sel := OS.get_environment("WPN_SHOW")
	if sel != "":
		ids = []
		for s in sel.split(","):
			ids.append(s)
	var att_sel: Array[String] = []
	var as_ := OS.get_environment("WPN_ATT")
	if as_ != "":
		for s in as_.split(","):
			att_sel.append(s)
	var yaw := 90.0
	if OS.get_environment("WPN_YAW") != "":
		yaw = float(OS.get_environment("WPN_YAW"))
	var cols := 5
	if OS.get_environment("WPN_COLS") != "":
		cols = int(OS.get_environment("WPN_COLS"))
	var count := 0
	for id in ids:
		var inst := _load(id)
		if inst == null:
			continue
		var col := count % cols
		var row := count / cols
		inst.position = Vector3((col - (cols - 1) * 0.5) * 1.55, -row * 0.62, 0.0)
		inst.rotation_degrees.y = -yaw
		root.add_child(inst)
		for a in att_sel:
			var mount := inst.find_child(MOUNT_OF.get(a, ""), true, false) as Node3D
			if mount == null:
				continue
			var att := _load(a)
			if att != null:
				mount.add_child(att)
		count += 1
	# attachments on their own row when no weapon filter says otherwise
	if sel == "" and att_sel.is_empty():
		var x0 := -2.2
		var row_y := -(((count - 1) / cols) + 1) * 0.62
		for i in ATTS.size():
			var a_inst := _load(ATTS[i])
			if a_inst == null:
				continue
			a_inst.position = Vector3(x0 + i * 0.9, row_y + 0.1, 0)
			a_inst.rotation_degrees.y = -yaw
			a_inst.scale = Vector3.ONE * 1.6
			root.add_child(a_inst)
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	_cam = cam
	var cs := OS.get_environment("WPN_CAM")
	if cs != "":
		var p := cs.split(",")
		cam.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		cam.look_at(root.global_position + Vector3(float(p[3]), float(p[4]), float(p[5])))
	else:
		var rows := ((count - 1) / cols) + 1 + (1 if sel == "" and att_sel.is_empty() else 0)
		cam.position = Vector3(0, -(rows - 1) * 0.31 + 0.1, 7.2 + rows * 0.7)
		cam.look_at(root.global_position + Vector3(0, -(rows - 1) * 0.31, 0))
	cam.current = true
	_hide_ui(main)
	for i in 10:
		await get_tree().process_frame
	print("SHOWCASE weapons=", count, " cam_current=", cam.current)
	return true


func _hide_ui(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		else:
			_hide_ui(c)


func _process(_dt: float) -> void:
	if _cam != null and is_instance_valid(_cam) and not _cam.current:
		_cam.current = true
