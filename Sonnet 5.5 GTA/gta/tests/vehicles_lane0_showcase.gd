extends Node
## Lane-0 car GLB showcase (visual QA of the Blender cars sedan/compact/sports/muscle). Renders into a private SubViewport with its OWN
## World3D (own light / sky / camera, independent of the game world) and saves PNGs itself (needs a real renderer, so run via `shot`):
##   tools\gd.ps1 shot -Out screenshots\l0_main.png -GameArgs "--exec=res://gta/tests/vehicles_lane0_showcase.gd --delay=3 --time=12 --no-traffic --no-peds"
## Writes screenshots\lane0_<view>.png for the views in VEH_VIEWS (default: front3q,rear3q,side,doors). Environment variables (optional):
##   VEH_SHOW="sedan,compact,..."  VEH_VIEWS="front3q,rear3q,side,doors,top,front"  VEH_SPACING=5.0  VEH_PREFIX=lane0_

const IDS: Array[String] = ["sedan", "compact", "sports", "muscle"]
const OUT_DIR := "res://screenshots/"
const PAINTS: Array[String] = ["#c43a3a", "#2f6fb5", "#e8e4da", "#d9a441"]


func run(main: Node) -> Variant:
	var sub := SubViewport.new()
	sub.size = Vector2i(1400, 700)
	sub.own_world_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_4X
	main.add_child(sub)
	var root := Node3D.new()
	sub.add_child(root)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.40, 0.42, 0.45)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	root.add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.84)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)

	var ids: Array[String] = IDS
	var sel := OS.get_environment("VEH_SHOW")
	if sel != "":
		ids = []
		for s in sel.split(","):
			ids.append(s)
	var spacing := 5.0
	if OS.get_environment("VEH_SPACING") != "":
		spacing = float(OS.get_environment("VEH_SPACING"))
	var views: PackedStringArray = "front3q,rear3q,side,doors".split(",")
	if OS.get_environment("VEH_VIEWS") != "":
		views = OS.get_environment("VEH_VIEWS").split(",")
	var prefix := "lane0_"
	if OS.get_environment("VEH_PREFIX") != "":
		prefix = OS.get_environment("VEH_PREFIX")

	var cars: Array[Node3D] = []
	var x0 := -float(ids.size() - 1) * spacing * 0.5
	var n := 0
	for id in ids:
		var path := "res://gta/generated/models/vehicles/%s.glb" % id
		if not ResourceLoader.exists(path):
			push_warning("showcase: missing " + path)
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		inst.position = Vector3(x0 + n * spacing, 0, 0)
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(PAINTS[n % PAINTS.size()])
		paint.metallic = 0.25
		paint.roughness = 0.35
		_swap(inst, "Paint", paint)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.1, 0.16, 0.22, 0.5)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.1
		_swap(inst, "Glass", glass)
		cars.append(inst)
		n += 1
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	for v in views:
		var yaw := 180.0
		var open_doors := false
		var cpos := Vector3(0, 4.6, 15.5)
		var look := Vector3(0, 0.7, 0)
		match v:
			"front3q":
				yaw = 218.0
			"rear3q":
				yaw = 38.0
			"side":
				yaw = 90.0
				cpos = Vector3(0, 2.2, 17.0)
			"doors":
				yaw = 218.0
				open_doors = true
			"top":
				yaw = 180.0
				cpos = Vector3(0, 15.0, 2.5)
			"front":
				yaw = 180.0
				cpos = Vector3(0, 1.6, 17.0)
		cam.position = cpos
		cam.look_at(look)
		for c in cars:
			c.rotation_degrees.y = yaw
			_doors(c, open_doors)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := sub.get_texture().get_image()
		var out := ProjectSettings.globalize_path(OUT_DIR + prefix + v + ".png")
		var err := img.save_png(out)
		print("SHOWCASE0 view=", v, " err=", err, " -> ", out)
	print("SHOWCASE0 done cars=", cars.size())
	sub.queue_free()
	return true


func _doors(car: Node3D, open: bool) -> void:
	var a := deg_to_rad(62.0) if open else 0.0
	for dn in ["DoorL", "DoorRearL"]:
		var d := car.find_child(dn, true, false) as Node3D
		if d != null:
			d.rotation.y = -a
	for dn in ["DoorR", "DoorRearR"]:
		var d2 := car.find_child(dn, true, false) as Node3D
		if d2 != null:
			d2.rotation.y = a


func _swap(node: Node, mat_name: String, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(s)
				if m != null and m.resource_name == mat_name:
					mi.set_surface_override_material(s, mat)
	for c in node.get_children():
		_swap(c, mat_name, mat)
