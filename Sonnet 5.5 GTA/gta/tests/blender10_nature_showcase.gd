extends Node
## Lane-10 nature / pickup GLB showcase (visual QA of the Blender models). Spawns the GLBs in a row on a private stage high above the world.
##   $env:L10_SHOW="nature/palm_a,nature/tree_oak_a"; tools\gd.ps1 shot -Out screenshots\l10_a.png -GameArgs "--exec=res://gta/tests/blender10_nature_showcase.gd --delay=3 --time=12"
## Env vars: L10_SHOW (comma list of "<category>/<id>"), L10_GAP (extra gap between items, default 0.6 x height/5), L10_YAW (degrees, default 35),
##           L10_ZOOM (camera distance multiplier, default 1.0), L10_EMIT (set to 1 to render in "night": dark sun, emissive materials pop)

var _cam: Camera3D


func _load(rel: String) -> Node3D:
	var path := "res://gta/generated/models/%s.glb" % rel
	if not ResourceLoader.exists(path):
		push_warning("showcase: missing " + path)
		return null
	return (load(path) as PackedScene).instantiate() as Node3D


func _aabb(n: Node3D) -> AABB:
	var have := false
	var bb := AABB()
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var p: Node = mi
			while p != null and p != n:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var b: AABB = xf * mi.get_aabb()
			bb = b if not have else bb.merge(b)
			have = true
		for k in c.get_children():
			stack.append(k)
	return bb


func run(main: Node) -> Variant:
	var root := Node3D.new()
	root.name = "L10Showcase"
	main.add_child(root)
	root.global_position = Vector3(0, 700, 0)
	var night := OS.get_environment("L10_EMIT") == "1"
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 0.15 if night else 1.5
	sun.shadow_enabled = true
	root.add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.03, 0.04, 0.09) if night else Color(0.36, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.08, 0.09, 0.15) if night else Color(0.78, 0.84, 0.9)
	sm.ground_bottom_color = Color(0.05, 0.05, 0.07) if night else Color(0.3, 0.32, 0.3)
	sm.ground_horizon_color = Color(0.1, 0.1, 0.14) if night else Color(0.6, 0.62, 0.66)
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.4 if night else 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	we.environment = env
	root.add_child(we)

	var ids: PackedStringArray = OS.get_environment("L10_SHOW").split(",", false)
	if ids.is_empty():
		ids = PackedStringArray(["nature/palm_a", "nature/tree_oak_a", "nature/tree_pine_a", "nature/bush_a", "nature/rock_a", "nature/grass_tuft"])
	var yaw := 35.0
	if OS.get_environment("L10_YAW") != "":
		yaw = float(OS.get_environment("L10_YAW"))
	var zoom := 1.0
	if OS.get_environment("L10_ZOOM") != "":
		zoom = float(OS.get_environment("L10_ZOOM"))
	var items: Array[Node3D] = []
	var widths: Array[float] = []
	var max_h := 0.1
	var total := 0.0
	for id in ids:
		var inst := _load(id)
		if inst == null:
			continue
		inst.rotation_degrees.y = yaw
		root.add_child(inst)
		var bb := _aabb(inst)
		var w: float = maxf(bb.size.x, bb.size.z)
		items.append(inst)
		widths.append(w)
		max_h = maxf(max_h, bb.end.y)
		total += w
	var gap := float(OS.get_environment("L10_GAP")) if OS.get_environment("L10_GAP") != "" else max_h * 0.12
	total += gap * maxf(0.0, items.size() - 1.0)
	var x := -total * 0.5
	for i in items.size():
		items[i].position = Vector3(x + widths[i] * 0.5, 0, 0)
		x += widths[i] + gap
	# ground
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(total * 2.0 + 20.0, 40.0 + max_h * 2.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.55, 0.38) if not night else Color(0.12, 0.14, 0.12)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.002
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	_cam = cam
	var dist: float = maxf(total * 0.9, max_h * 1.6) * zoom + max_h * 0.4
	cam.position = Vector3(0, max_h * 0.5 + dist * 0.12, dist)
	cam.look_at(root.global_position + Vector3(0, max_h * 0.45, 0))
	cam.make_current()
	for i in 6:
		await get_tree().process_frame
	return "ok " + str(items.size())
