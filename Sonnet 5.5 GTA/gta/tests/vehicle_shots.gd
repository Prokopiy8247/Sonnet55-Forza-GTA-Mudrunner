extends Node
## Visual QA: one 3/4 daylight shot per ground vehicle on a private studio floor (far from the city) + a contact sheet,
## then (optionally) a shot of the real dealer lot.  Needs a real renderer:
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\veh_sheet.png -GameArgs "--exec=res://gta/tests/vehicle_shots.gd --time=12 --no-traffic --no-peds --no-vehicles --delay=2"
## Args (user args after --): --veh=id1,id2  --sheet=<path>  --lot (dealer lot closeup shot instead)  --night

var cam: Camera3D
var out_dir := "res://screenshots/"


func run(main: Node) -> String:
	var args := OS.get_cmdline_user_args()
	var ids: Array = VehicleDefs.implemented_ids()
	var lot := false
	var night := false
	var extra: Array = []
	for a in args:
		var s := String(a)
		if s.begins_with("--veh="):
			ids = []
			for p in s.substr(6).split(","):
				ids.append(StringName(p))
		elif s == "--lot":
			lot = true
		elif s == "--night":
			night = true
		elif s.begins_with("--also="):
			extra = s.substr(7).split(",")
	if lot:
		return await _lot_shots(main)
	var floor_root := Node3D.new()
	floor_root.name = "StudioFloor"
	main.add_child(floor_root)
	floor_root.global_position = Vector3(3000, 0, 3000)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.38, 0.4)
	mat.roughness = 0.9
	pm.material = mat
	mi.mesh = pm
	floor_root.add_child(mi)
	var sb := StaticBody3D.new()
	sb.collision_layer = GC.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	floor_root.add_child(sb)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.far = 800.0
	main.add_child(cam)
	cam.make_current()
	if night:
		Game.time_of_day = 22.0
	await get_tree().create_timer(1.0).timeout
	var tiles: Array = []
	var origin := Vector3(3000, 0, 3000)
	for id in ids:
		var v := VehicleFactory.spawn(id, Transform3D(Basis(Vector3.UP, deg_to_rad(0)), origin + Vector3(0, 0.3, 0)), {"parked": true, "paint": _paint_for(id), "finish": &"metallic", "engine_on": false})
		if v == null:
			print("TEST shot_%s FAIL spawn returned null" % id)
			continue
		if night:
			v.headlights_on = true
			v.engine_on = true
			if v.def.get("siren", "") != "":
				v.siren_on = true
		v.set_meta("keep_awake", true)
		await T_frames(40)
		var d: Dictionary = v.def
		var size := maxf(float(d["length"]), 3.0)
		var c := origin + Vector3(0, float(d["height"]) * 0.45, 0)
		var dir := Vector3(-0.78, 0.33, -1.0).normalized()
		cam.global_position = c + dir * size * 1.9
		cam.look_at(c, Vector3.UP)
		await T_frames(8)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var path := ProjectSettings.globalize_path(out_dir + "veh_%s.png" % id)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			tiles.append([id, img])
			print("TEST shot_%s PASS saved %s fallback=%s" % [id, path, VehicleFactory.fallback_used.has(id)])
		# rear 3/4 view for the lights
		if extra.has(String(id)):
			cam.global_position = c + Vector3(0.78, 0.33, 1.0).normalized() * size * 1.9
			cam.look_at(c, Vector3.UP)
			await T_frames(6)
			await RenderingServer.frame_post_draw
			var img2 := get_viewport().get_texture().get_image()
			img2.save_png(ProjectSettings.globalize_path(out_dir + "veh_%s_rear.png" % id))
		VehicleFactory.despawn(v)
		await T_frames(3)
	# contact sheet
	if tiles.size() > 0:
		var cols := 4
		var tw := 480
		var th := 270
		var rows := int(ceil(float(tiles.size()) / cols))
		var sheet := Image.create(cols * tw, rows * th, false, Image.FORMAT_RGB8)
		sheet.fill(Color.BLACK)
		for i in tiles.size():
			var im: Image = (tiles[i][1] as Image).duplicate()
			im.convert(Image.FORMAT_RGB8)
			im.resize(tw, th, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
		var sp := ProjectSettings.globalize_path(out_dir + "veh_sheet.png")
		sheet.save_png(sp)
		print("TEST shot_sheet PASS saved %s tiles=%d" % [sp, tiles.size()])
	return "ok"


func _paint_for(id: StringName) -> Color:
	match id:
		&"taxi": return Color("#ffb347")
		&"police_cruiser", &"police_tactical": return Color("#14171d")
		&"ambulance": return Color("#f2f2ee")
		&"firetruck": return Color("#c92a2a")
		&"sports": return Color("#34e0ff")
		&"muscle": return Color("#c43a3a")
		&"suv": return Color("#4b8a5f")
		&"pickup": return Color("#d9a441")
		&"van": return Color("#e8e4da")
		_: return Color("#2f6fb5")


func T_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _lot_shots(main: Node) -> String:
	var sys = Game.sys(&"vehicles")
	if sys == null:
		return "no vehicle system"
	var loc: Dictionary = WorldLayout.get_location(&"dealer_lot")
	var origin: Vector3 = loc.get("pos", Vector3(20, 1, 20))
	await get_tree().create_timer(3.0).timeout
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 1500.0
	main.add_child(cam)
	cam.make_current()
	var yaw: float = float(loc.get("yaw", 0.0))
	var b := Basis(Vector3.UP, yaw)
	cam.global_position = origin + b * Vector3(-14, 11, -12)
	cam.look_at(origin + b * Vector3(0, 0.5, 14), Vector3.UP)
	await T_frames(10)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := ProjectSettings.globalize_path(out_dir + "veh_dealer_lot.png")
	img.save_png(p)
	print("TEST shot_dealer_lot PASS saved %s vehicles=%d" % [p, sys.dealer_vehicles.size()])
	return "ok"
