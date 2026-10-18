extends Node
## Minimal stand-alone bootstrap for the Environment agent (does NOT boot Main, so it keeps working while other
## modules are mid-edit). Starts only EnvironmentSystem + the test city and runs an exec script.
## Launch through the wrapper by passing the scene as an extra engine argument:
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\env\_x.png -Resolution "1280x720 res://gta/tests/env_boot.tscn" -Seconds 200 -GameArgs "--exec=res://gta/tests/env_gallery.gd"
## Options (after --): --exec=<script> (run(main) may await), --keep, --time=<h>, --weather=<name>, --delay=<s>, --scene (build the test city)

var opts: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			opts[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			opts[s] = "true"
	Game.main = self
	var env_script = load("res://gta/code/world/environment_system.gd")
	var env: Node = env_script.new()
	env.name = "Environment"
	add_child(env)
	Game.systems[&"environment"] = env
	env.setup(self)
	env.post_setup()
	print("[EnvBoot] environment system up")
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var env = Game.sys(&"environment")
	if opts.has("time"):
		Game.time_of_day = float(opts["time"])
		Game.time_frozen = true
	if opts.has("weather") and env != null:
		env.set_weather(StringName(opts["weather"]), true)
	if opts.has("scene"):
		load("res://gta/tests/env_test_scene.gd").build(self)
	await get_tree().create_timer(float(opts.get("delay", 1.0))).timeout
	if opts.has("exec"):
		var scr = load(String(opts["exec"]))
		var obj = scr.new()
		if obj is Node:
			add_child(obj)
		var result = await obj.run(self)
		print("HARNESS: EXEC DONE ", opts["exec"], " result=", result)
	if opts.has("shot") and not opts.has("exec"):
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			DirAccess.make_dir_recursive_absolute(String(opts["shot"]).get_base_dir())
			var err := img.save_png(String(opts["shot"]))
			print("HARNESS: SHOT ", opts["shot"], " err=", err, " size=", img.get_size())
		else:
			print("HARNESS: SHOT FAILED no image")
	if not opts.has("keep"):
		get_tree().quit(0)
