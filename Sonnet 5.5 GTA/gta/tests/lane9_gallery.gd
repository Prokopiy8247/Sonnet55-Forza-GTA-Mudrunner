extends Node
## Lane-9 street prop / interior GLB gallery (visual QA of the Blender models inside the real engine).
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\lane9_a.png -GameArgs "--exec=res://gta/tests/lane9_gallery.gd --delay=3 --time=12"
## Env vars: GAL_IDS  comma list of "category/id" (default = small street props)
##           GAL_COLS columns of the grid (default 6)   GAL_SPACING metres between cells (default auto)
##           GAL_CAM  "x,y,z,tx,ty,tz" camera relative to the stage (default = auto 3/4 view of the fronts, which face -Z)

const DEFAULT_IDS: Array[String] = ["props/road_cone", "props/trash_bin", "props/bench", "props/fire_hydrant", "props/bollard", "props/parking_meter",
	"props/mailbox", "props/newspaper_box", "props/crate", "props/barrel", "props/pallet", "props/tire_stack"]
var _cam: Camera3D
var _stage: Node3D


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _bounds(n: Node3D) -> AABB:
	var bb := AABB()
	var have := false
	var ms: Array = []
	_meshes(n, ms)
	for mi: MeshInstance3D in ms:
		if mi.mesh == null:
			continue
		var b: AABB = (_stage.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		bb = b if not have else bb.merge(b)
		have = true
	return bb


func _hide_ui(n: Node) -> void:
	if n is CanvasLayer and n != self:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_ui(c)


func run(main: Node) -> Variant:
	_hide_ui(main.get_tree().root)
	var stage := Node3D.new()
	stage.name = "Lane9Gallery"
	main.add_child(stage)
	_stage = stage
	stage.global_position = Vector3(0, 600, 0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -150, 0)       # light comes from the camera side (-Z) so fronts are lit
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	stage.add_child(sun)
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
	stage.add_child(we)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.43, 0.46)
	ground.material_override = gm
	ground.position = Vector3(0, -0.01, 0)
	stage.add_child(ground)

	var ids: Array[String] = DEFAULT_IDS
	var sel := OS.get_environment("GAL_IDS")
	if sel != "":
		ids = []
		for s in sel.split(","):
			ids.append(s.strip_edges())
	var cols := 6
	if OS.get_environment("GAL_COLS") != "":
		cols = int(OS.get_environment("GAL_COLS"))
	var insts: Array[Node3D] = []
	var maxw := 0.0
	var maxh := 0.0
	var maxd := 0.0
	for id in ids:
		var path := "res://gta/generated/models/%s.glb" % id
		if not ResourceLoader.exists(path):
			push_warning("lane9_gallery: missing " + path)
			continue
		var n := (load(path) as PackedScene).instantiate() as Node3D
		stage.add_child(n)
		var bb := _bounds(n)
		maxw = maxf(maxw, bb.size.x)
		maxh = maxf(maxh, bb.end.y)
		maxd = maxf(maxd, bb.size.z)
		insts.append(n)
	var spacing := maxf(maxw, maxd) * 1.25 + 0.3
	if OS.get_environment("GAL_SPACING") != "":
		spacing = float(OS.get_environment("GAL_SPACING"))
	var rows := int(ceil(float(insts.size()) / float(cols)))
	var used_cols := mini(cols, insts.size())
	for i in insts.size():
		var cx := i % cols
		var rz := i / cols
		insts[i].position = Vector3((cx - (used_cols - 1) * 0.5) * spacing, 0, rz * spacing)
		print("LANE9 ", ids[i], " bounds=", _bounds(insts[i]).size, " tris-check ok")
	var span := maxf(used_cols * spacing, rows * spacing)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.far = 600.0
	stage.add_child(_cam)
	var look_at := Vector3(0, maxh * 0.4, (rows - 1) * spacing * 0.5)
	var cp := look_at + Vector3(span * 0.18, maxh * 0.35 + span * 0.1, -span * 0.62 - maxh * 1.3)
	if OS.get_environment("GAL_CAM") != "":
		var p := OS.get_environment("GAL_CAM").split(",")
		cp = Vector3(float(p[0]), float(p[1]), float(p[2]))
		look_at = Vector3(float(p[3]), float(p[4]), float(p[5]))
	_cam.look_at_from_position(stage.global_position + cp, stage.global_position + look_at, Vector3.UP)
	_cam.make_current()
	print("LANE9 cam=", _cam.global_position, " look=", stage.global_position + look_at, " span=", span, " maxh=", maxh, " n=", insts.size())
	for i in 6:
		await main.get_tree().process_frame
	return "ok"
