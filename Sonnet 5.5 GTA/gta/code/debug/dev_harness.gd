class_name DevHarness
extends Node
## Command-line test harness for automated QA. Active only when user args follow `--` on the command line:
##   godot --path . -- --shot=shot.png --delay=5 --teleport=0,2,0 --time=20 --weather=rain
## Options (all optional, combine freely):
##   --shot=<file.png>        save the viewport after --delay seconds (needs a real renderer, not --headless), then quit
##   --delay=<sec>            seconds after boot before the shot / exec (default 3)
##   --teleport=x,y,z[,yaw_deg]  move the player
##   --cam=x,y,z,tx,ty,tz     use a free dev camera looking from (x,y,z) at (tx,ty,tz); --fov=<deg>
##   --time=<hour>            Game.time_of_day (also freezes time unless --unfreeze)
##   --weather=<name>         clear|cloudy|rain|fog|storm
##   --vehicle=<id>           spawn that vehicle in front of the player and enter it
##   --give=<weapon_id>       give + equip a weapon
##   --wanted=<0..5>          set the wanted level
##   --no-traffic / --no-peds disable traffic / pedestrians
##   --exec=<res://script.gd> load the script, call run(main: Node) (may await), then quit unless --keep
##   --quit-after=<sec>       quit after N seconds (default: never, or right after --shot / --exec)
##   --keep                   do not quit after --shot / --exec
##   --perf                   print PERF line (fps, draw calls, objects, physics) every 2 s
## Prints lines starting with HARNESS: so wrappers can grep them.

var main: Node
var opts: Dictionary = {}
var _cam: Camera3D = null


func start(main_node: Node, args: PackedStringArray) -> void:
	main = main_node
	for a in args:
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			opts[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			opts[s] = "true"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if opts.has("no-traffic"):
		Game.cheats["traffic"] = false
	if opts.has("no-peds"):
		Game.cheats["pedestrians"] = false
	if opts.has("time"):
		Game.time_of_day = float(opts["time"])
		if not opts.has("unfreeze"):
			Game.time_frozen = true
	if opts.has("weather"):
		var env = Game.sys(&"environment")
		if env != null and env.has_method("set_weather"):
			env.set_weather(StringName(opts["weather"]))
		else:
			Game.weather = StringName(opts["weather"])
	if opts.has("teleport") and is_instance_valid(Game.player):
		var p := String(opts["teleport"]).split(",")
		if p.size() >= 3:
			var yaw := deg_to_rad(float(p[3])) if p.size() >= 4 else NAN
			Game.player.teleport_to(Vector3(float(p[0]), float(p[1]), float(p[2])), yaw)
	if opts.has("give") and is_instance_valid(Game.player) and Game.player.weapons != null:
		Game.player.weapons.give_weapon(StringName(opts["give"]), 999)
		Game.player.weapons.equip(StringName(opts["give"]))
	if opts.has("wanted"):
		var w = Game.sys(&"wanted")
		if w != null and w.has_method("set_level"):
			w.set_level(int(opts["wanted"]))
	if opts.has("vehicle") and is_instance_valid(Game.player):
		var fwd: Vector3 = -Game.player.global_transform.basis.z
		var xf := Transform3D(Game.player.global_transform.basis, Game.player.global_position + fwd * 5.0 + Vector3(0, 1.0, 0))
		var v = VehicleFactory.spawn(StringName(opts["vehicle"]), xf, {})
		if v != null:
			await get_tree().create_timer(0.5).timeout
			Game.player.enter_vehicle(v)
	if opts.has("perf"):
		_perf_loop()
	if opts.has("cam"):
		_setup_cam()
	print("HARNESS: ready opts=", opts)

	var delay := float(opts.get("delay", 3.0))
	if opts.has("quit-after") and not opts.has("shot") and not opts.has("exec"):
		await get_tree().create_timer(float(opts["quit-after"])).timeout
		print("HARNESS: quit-after reached")
		get_tree().quit(0)
		return
	await get_tree().create_timer(delay).timeout
	if opts.has("exec"):
		await _do_exec(String(opts["exec"]))
	if opts.has("shot"):
		await _do_shot(String(opts["shot"]))
	if opts.has("quit-after"):
		await get_tree().create_timer(float(opts["quit-after"])).timeout
	if (opts.has("shot") or opts.has("exec")) and not opts.has("keep"):
		get_tree().quit(0)


func _setup_cam() -> void:
	var p := String(opts["cam"]).split(",")
	if p.size() < 6:
		return
	_cam = Camera3D.new()
	_cam.name = "DevCamera"
	_cam.fov = float(opts.get("fov", 70.0))
	_cam.far = 1500.0
	main.add_child(_cam)
	_cam.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_cam.look_at(Vector3(float(p[3]), float(p[4]), float(p[5])), Vector3.UP)
	_cam.make_current()


func _do_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("HARNESS: SHOT FAILED (no image - are you running --headless?)")
		return
	var abs_path := path
	if path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	print("HARNESS: SHOT ", abs_path, " err=", err, " size=", img.get_size())


func _do_exec(script_path: String) -> void:
	var scr = load(script_path)
	if scr == null:
		print("HARNESS: EXEC FAILED to load ", script_path)
		return
	var obj = scr.new()
	if obj is Node:
		add_child(obj)
	if obj.has_method("run"):
		var result = await obj.run(main)
		print("HARNESS: EXEC DONE ", script_path, " result=", result)
	else:
		print("HARNESS: EXEC script has no run(main)")


func _perf_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(2.0).timeout
		print("PERF fps=%d draw_calls=%d objects=%d prims=%d phys_active=%d nodes=%d mem_mb=%.0f" % [
			Engine.get_frames_per_second(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
