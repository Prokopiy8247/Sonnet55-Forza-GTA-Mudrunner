extends Node
## Lane-1 car GLB showcase (visual QA of Blender cars). Spawns the GLBs in a row on a private floor high above the world.
##   tools\gd.ps1 shot -Out screenshots\cars_a.png -GameArgs "--exec=res://gta/tests/vehicles_lane1_showcase.gd --delay=3 --time=12"
## Camera: pass --cam=0,406.5,24,0,400.9,0 (the showcase floor is at y=400). Env VEH_SHOW = comma separated ids.

const IDS: Array[String] = ["police_cruiser", "suv", "pickup", "van", "taxi"]


func run(main: Node) -> Variant:
	var root := Node3D.new()
	root.name = "Lane1Showcase"
	main.add_child(root)
	var base := Vector3(0, 400, 0)
	root.global_position = base
	# floor
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.47, 0.5)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.7
	we.environment = env
	root.add_child(we)
	var ids: Array[String] = IDS
	var sel := OS.get_environment("VEH_SHOW")
	if sel != "":
		ids = []
		for s in sel.split(","):
			ids.append(s)
	var x := -float(ids.size() - 1) * 3.2
	var count := 0
	for id in ids:
		var path := "res://gta/generated/models/vehicles/%s.glb" % id
		if not ResourceLoader.exists(path):
			push_warning("showcase: missing " + path)
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		inst.position = Vector3(x + count * 6.4, 0, 0)
		var yaw := 218.0                           # three-quarter view of the front (-Z is forward); env VEH_YAW overrides
		if OS.get_environment("VEH_YAW") != "":
			yaw = float(OS.get_environment("VEH_YAW"))
		inst.rotation_degrees.y = yaw
		count += 1
	for i in 8:
		await get_tree().process_frame
	print("SHOWCASE lane1 vehicles=", count)
	return true
