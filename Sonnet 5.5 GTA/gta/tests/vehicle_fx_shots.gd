extends Node
## Visual QA of the dynamic effects: handbrake slide (tyre smoke + skid marks), burning car (smoke + flames + light), night lights + siren.
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\veh_fx_last.png -GameArgs "--exec=res://gta/tests/vehicle_fx_shots.gd --time=12 --no-traffic --no-peds --no-vehicles --delay=2"

var T := VehicleTestUtil
var cam: Camera3D


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path("res://screenshots/" + path))
		print("TEST fxshot_%s PASS saved" % path)


func run(main: Node) -> String:
	var fl := T.make_floor(main, 400.0)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(800, 800)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.23, 0.25)
	mat.roughness = 0.95
	pm.material = mat
	mi.mesh = pm
	fl.add_child(mi)
	Game.wetness = 0.0
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 600.0
	main.add_child(cam)
	cam.make_current()
	await T.frames(get_tree(), 20)
	# ---- 1. handbrake slide
	var v := T.spawn(&"sports", Vector3(0, 0.3, 40.0), 0.0, {"paint": Color("#34e0ff"), "finish": &"metallic"})
	await T.frames(get_tree(), 40)
	v.set_velocity(Vector3(0, 0, -26.0))
	for i in 55:
		v.input_throttle = 0.6
		await get_tree().physics_frame
	for i in 42:
		v.input_throttle = 0.8
		v.input_steer = 0.7
		v.input_handbrake = true
		await get_tree().physics_frame
		cam.global_position = v.global_position + Vector3(7.0, 2.6, 8.0)
		cam.look_at(v.global_position + Vector3(0, 0.5, -1.0), Vector3.UP)
	await T.frames(get_tree(), 1)
	await _save("veh_fx_slide.png")
	for i in 100:
		v.input_handbrake = false
		v.input_throttle = 0.0
		v.input_brake = 0.4
		await get_tree().physics_frame
	cam.global_position = v.global_position + Vector3(10.0, 7.0, 18.0)
	cam.look_at(v.global_position + Vector3(0, 0, -6.0), Vector3.UP)
	await T.frames(get_tree(), 3)
	await _save("veh_fx_skidmarks.png")
	VehicleFactory.despawn(v)
	# ---- 2. burning car
	var b := T.spawn(&"sedan", Vector3(30, 0.3, 0), 0.0, {"paint": Color("#c43a3a"), "ai": false, "engine_on": false})
	await T.frames(get_tree(), 30)
	b.apply_damage(b.max_health * 0.86, {"type": GC.DMG_COLLISION})
	b.dmg.hit_glass()
	b.dmg.hit_glass()
	await T.frames(get_tree(), 80)
	cam.global_position = b.global_position + Vector3(-5.0, 2.8, -6.5)
	cam.look_at(b.global_position + Vector3(0, 0.8, 0), Vector3.UP)
	await T.frames(get_tree(), 4)
	await _save("veh_fx_burning.png")
	# ---- 3. night: headlights + siren
	Game.time_of_day = 22.0
	var p := T.spawn(&"police_cruiser", Vector3(60, 0.3, 0), 0.0, {"ai": true, "engine_on": true})
	var t := T.spawn(&"taxi", Vector3(60, 0.3, -9.0), 0.0, {"ai": true, "engine_on": true})
	p.headlights_on = true
	t.headlights_on = true
	p.siren_on = true
	await T.frames(get_tree(), 60)
	p.set_velocity(Vector3(0, 0, -6.0))
	t.set_velocity(Vector3(0, 0, -6.0))
	for i in 20:
		p.input_throttle = 0.3
		t.input_throttle = 0.3
		p.input_brake = 0.0
		await get_tree().physics_frame
	cam.global_position = p.global_position + Vector3(6.0, 1.8, 7.0)
	cam.look_at(p.global_position + Vector3(0, 0.8, -5.0), Vector3.UP)
	await T.frames(get_tree(), 2)
	await _save("veh_fx_night.png")
	return "ok"
