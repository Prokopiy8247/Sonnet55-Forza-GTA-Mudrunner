extends Node
## Lane-3 vehicle GLB showcase (heli_civil, speedboat, plane_prop, heli_police, plane_jet) on a private floor at y=400.
##   tools\gd.ps1 shot -Out screenshots\lane3_a.png -GameArgs "--exec=res://gta/tests/vehicles_lane3_showcase.gd --delay=3 --time=12 --cam=0,408,40,0,401,0"
## Env VEH_SHOW = comma separated ids, VEH_YAW = yaw in degrees (default 218 = three-quarter front view), VEH_GAP = spacing,
##     VEH_POSE = 1 -> rotate the animated nodes (rotors, prop, wheels, control surfaces) to verify pivots/axes the way gameplay code will.

const IDS: Array[String] = ["heli_civil", "speedboat", "plane_prop", "heli_police", "plane_jet"]


func _find(n: Node, nm: String) -> Node3D:
	return n.find_child(nm, true, false) as Node3D


func _pose(inst: Node3D) -> void:
	var rm := _find(inst, "RotorMain")
	if rm:
		rm.rotation.y = deg_to_rad(35.0)            # main rotor: spins about local Y (= Blender Z, up)
	var rt := _find(inst, "RotorTail")
	if rt:
		rt.rotation.x = deg_to_rad(40.0)            # tail rotor: about X
	var pr := _find(inst, "Prop")
	if pr:
		pr.rotation.z = deg_to_rad(50.0)            # prop: about the forward axis (Godot Z)
	for wn in ["Wheel_F", "Wheel_RL", "Wheel_RR"]:
		var w := _find(inst, wn)
		if w:
			w.rotation.x = deg_to_rad(40.0)
	var al := _find(inst, "Aileron_L")
	if al:
		al.rotation.x = deg_to_rad(28.0)
	var ar := _find(inst, "Aileron_R")
	if ar:
		ar.rotation.x = deg_to_rad(-28.0)
	var el := _find(inst, "Elevator")
	if el:
		el.rotation.x = deg_to_rad(-22.0)
	var ru := _find(inst, "Rudder")
	if ru:
		ru.rotation.y = deg_to_rad(28.0)


func run(main: Node) -> Variant:
	var root := Node3D.new()
	root.name = "Lane3Showcase"
	main.add_child(root)
	root.global_position = Vector3(0, 400, 0)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 120)
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
	var gap := 16.0
	if OS.get_environment("VEH_GAP") != "":
		gap = float(OS.get_environment("VEH_GAP"))
	var yaw := 218.0
	if OS.get_environment("VEH_YAW") != "":
		yaw = float(OS.get_environment("VEH_YAW"))
	var pose := OS.get_environment("VEH_POSE") == "1"
	var count := 0
	for id in ids:
		var path := "res://gta/generated/models/vehicles/%s.glb" % id
		if not ResourceLoader.exists(path):
			push_warning("showcase: missing " + path)
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		inst.position = Vector3(-float(ids.size() - 1) * gap * 0.5 + count * gap, 0.0 if id != "speedboat" else 0.3, 0)
		inst.rotation_degrees.y = yaw
		if pose:
			_pose(inst)
		count += 1
	for i in 8:
		await get_tree().process_frame
	print("SHOWCASE lane3 vehicles=", count)
	return true
