extends Node
## Art-pass reference set in ONE Godot session (windowed, real renderer). Each view sets time / weather / camera, waits for the
## sky radiance, shadows, sectors, lamps and the reflection probe to settle, then saves a PNG.
##
##   powershell -NoProfile -File tools\art_shots.ps1 -Tag after [-Only spawn_1200,car_night]
## which runs:  tools\gd.ps1 game -GameArgs "--exec=res://gta/tests/art_batch.gd --no-traffic --no-peds --tag=after --views=a,b --nohud"
## Options: --tag=<prefix>  --views=<comma list>  --hud (keep the HUD)  --list  --settle=<sec>  --out=<dir under res://screenshots>
## Output: screenshots/art/<tag>_<view>.png (1600x900 when the window is that size).

const VIEWS := {
	# name: {t: hour, w: weather, cam: [x,y,z, tx,ty,tz], fov, tp: [x,y,z] (player teleport for streaming), veh: id, hide: bool}
	"spawn_0930": {"t": 9.5, "w": "clear", "tp": [14.0, 0.1, 38.0], "yaw": 0.0, "third": true},
	"spawn_1200": {"t": 12.0, "w": "clear", "tp": [14.0, 0.1, 38.0], "yaw": 0.0, "third": true},
	"downtown_1745": {"t": 17.75, "w": "clear", "cam": [-35, 3.4, 90, -35, 14, 10], "tp": [-35, 0.1, 90]},
	"downtown_2100": {"t": 21.0, "w": "clear", "cam": [-35, 3.4, 90, -35, 14, 10], "tp": [-35, 0.1, 90]},
	"resid_1500": {"t": 15.0, "w": "clear", "cam": [-185, 3.5, 40, -190, 5, -30], "tp": [-185, 0.1, 30]},
	"pier_sunset": {"t": 18.6, "w": "clear", "cam": [-108, 4, 186, -178, 2, 204], "tp": [-146, 0.1, 190]},
	"beach_noon": {"t": 12.0, "w": "clear", "cam": [-45, 4, 150, 25, 1, 172], "tp": [0, 0.1, 160]},
	"industrial_1000": {"t": 10.0, "w": "clear", "cam": [165, 5, 12, 205, 3, -35], "tp": [190, 0.1, -20]},
	"airport_1400": {"t": 14.0, "w": "clear", "cam": [95, 6, 150, 175, 2, 128], "tp": [150, 0.1, 140]},
	"hills_1830": {"t": 18.5, "w": "clear", "cam": [196, 66, -206, 10, 4, 30], "fov": 66.0, "tp": [205, 39.4, -224]},
	"air_noon": {"t": 12.0, "w": "clear", "cam": [70, 190, 340, 0, 0, 10], "fov": 62.0, "tp": [0, 0.1, 40]},
	"rain_dusk": {"t": 18.5, "w": "rain", "cam": [-35, 3.4, 90, -35, 14, 10], "tp": [-35, 0.1, 90]},
	"fog_dawn": {"t": 6.3, "w": "fog", "cam": [-62, 3, -100, -25, 3, -175], "tp": [-50, 0.1, -110]},
	"storm": {"t": 15.0, "w": "storm", "cam": [-35, 3.4, 90, -35, 14, 10], "tp": [-35, 0.1, 90]},
	"night_neon": {"t": 22.0, "w": "clear", "cam": [-60, 3.5, -124, -60, 9, -97], "tp": [-60, 0.1, -115]},
	"underwater": {"t": 12.0, "w": "clear", "cam": [-45, -2.6, 186, -10, -3.9, 216], "tp": [-45, 0.1, 160]},
	"car_day": {"t": 15.0, "w": "clear", "cam": [19.5, 1.5, 25.5, 14, 0.8, 31], "tp": [14, 0.1, 38], "veh": "sports"},
	"car_night": {"t": 22.0, "w": "clear", "cam": [19.5, 1.5, 25.5, 14, 0.8, 31], "tp": [14, 0.1, 38], "veh": "sedan"},
	# extras used while tuning (not in the default reference set; run with --views=...)
	"x_plaza_far": {"t": 12.0, "w": "clear", "cam": [14, 6, 70, 14, 2, 0], "tp": [14, 0.1, 38]},
	"x_downtown_up": {"t": 12.0, "w": "clear", "cam": [-60, 40, 140, 0, 20, 0], "tp": [0, 0.1, 40]},
	"x_resid_wide": {"t": 11.0, "w": "clear", "cam": [-150, 25, 60, -220, 5, -40], "tp": [-185, 0.1, 30]},
	"x_night_air": {"t": 22.0, "w": "clear", "cam": [70, 190, 340, 0, 0, 10], "fov": 62.0, "tp": [0, 0.1, 40]},
	"x_sunset_air": {"t": 18.7, "w": "clear", "cam": [70, 190, 340, 0, 0, 10], "fov": 62.0, "tp": [0, 0.1, 40]},
	"x_cloudy": {"t": 13.0, "w": "cloudy", "cam": [-31, 2.6, 108, -35, 14, 10], "tp": [-31, 0.1, 100]},
	"x_dawn_city": {"t": 6.6, "w": "clear", "cam": [-31, 2.6, 108, -35, 14, 10], "tp": [-31, 0.1, 100]},
	"x_rain_night": {"t": 22.0, "w": "rain", "cam": [-31, 2.6, 108, -35, 14, 10], "tp": [-31, 0.1, 100]},
	"x_beach_sunset": {"t": 18.7, "w": "clear", "cam": [-45, 4, 150, 25, 1, 190], "tp": [0, 0.1, 160]},
	"x_sea_night": {"t": 22.0, "w": "clear", "cam": [-40, 2.6, 150, 24, 4, 209], "tp": [0, 0.1, 160]},
	"x_beach_top": {"t": 12.0, "w": "clear", "cam": [0, 30, 140, 0, 0, 178], "tp": [0, 0.1, 160]},
	"x_park": {"t": 11.0, "w": "clear", "cam": [-70, 3, -110, -20, 4, -150], "tp": [-50, 0.1, -110]},
	"x_hill_road": {"t": 11.0, "w": "clear", "cam": [140, 22, -150, 215, 30, -225], "tp": [180, 5, -190]},
	"x_underwater_deep": {"t": 12.0, "w": "clear", "cam": [-22, -7.5, 244, -22, -11.5, 268], "tp": [-22, 0.1, 200]},
	"x_swim_surface": {"t": 12.0, "w": "clear", "cam": [-45, -1.95, 184, 5, -1.3, 216], "tp": [-45, 0.1, 160]},
	"x_downtown_sunset": {"t": 18.7, "w": "clear", "cam": [-31, 2.6, 108, -35, 14, 10], "tp": [-31, 0.1, 100]},
	"x_plaza_night": {"t": 22.0, "w": "clear", "tp": [14.0, 0.1, 38.0], "yaw": 0.0, "third": true},
	"x_street_walk": {"t": 14.0, "w": "clear", "cam": [-12, 2.2, 90, -30, 3, 10], "tp": [-12, 0.1, 90]},
	"x_storm_night": {"t": 22.0, "w": "storm", "cam": [-31, 2.6, 108, -35, 14, 10], "tp": [-31, 0.1, 100]},
}

var _cam: Camera3D = null
var _veh: Node = null


func run(main: Node) -> bool:
	var args := OS.get_cmdline_user_args()
	var tag := "after"
	var only: PackedStringArray = []
	var hide_hud := true
	var settle := 2.2
	var env_over := ""
	var no_shadow := false
	for a in args:
		var s := String(a)
		if s.begins_with("--tag="):
			tag = s.substr(6)
		elif s.begins_with("--views="):
			only = s.substr(8).split(",", false)
		elif s == "--hud":
			hide_hud = false
		elif s.begins_with("--settle="):
			settle = float(s.substr(9))
		elif s.begins_with("--env="):
			env_over = s.substr(6)
		elif s == "--noshadow":
			no_shadow = true
		elif s == "--list":
			print("TEST art VIEWS ", ", ".join(VIEWS.keys()))
			return true
	var names: Array = []
	if only.is_empty():
		for k in VIEWS.keys():
			if not String(k).begins_with("x_"):
				names.append(k)
	else:
		names = Array(only)

	var env = Game.sys(&"environment")
	if env == null:
		print("TEST art FAIL no environment system")
		return false
	Game.time_frozen = true
	if no_shadow:
		env._shadows_on = false
	# --env=tonemap_mode:3,tonemap_white:5.5  -> numeric Environment property overrides (tuning experiments only)
	if env_over != "" and env.environment != null:
		for kv in env_over.split(",", false):
			var pr := kv.split(":")
			if pr.size() == 2:
				env.environment.set(pr[0], float(pr[1]) if not pr[0].ends_with("_mode") else int(pr[1]))
	if hide_hud:
		_set_hud(false)
	var dir := ProjectSettings.globalize_path("res://screenshots/art")
	DirAccess.make_dir_recursive_absolute(dir)

	for n in names:
		var nm := String(n)
		if not VIEWS.has(nm):
			print("TEST art FAIL unknown view ", nm)
			continue
		var v: Dictionary = VIEWS[nm]
		await _shoot(main, env, nm, v, "%s/%s_%s.png" % [dir, tag, nm], settle)
	if is_instance_valid(_veh):
		_veh.queue_free()
	return true


func _set_hud(on: bool) -> void:
	for l in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := l as CanvasLayer
		if cl.layer >= 0:
			cl.visible = on


func _shoot(main: Node, env, nm: String, v: Dictionary, path: String, settle: float) -> void:
	var tp: Array = v.get("tp", [14.0, 0.1, 38.0])
	var third := bool(v.get("third", false))
	# player placement (streams sectors around the camera; hidden unless this is a third-person view)
	var pl = Game.player
	if is_instance_valid(pl):
		pl.teleport_to(Vector3(float(tp[0]), float(tp[1]), float(tp[2])), deg_to_rad(float(v.get("yaw", 0.0))))
		pl.visible = third or v.has("veh")
	# vehicle
	if is_instance_valid(_veh):
		_veh.queue_free()
		_veh = null
	if v.has("veh"):
		var fwd := Vector3(0, 0, -1)
		var xf := Transform3D(Basis.IDENTITY, Vector3(float(tp[0]), 1.0, float(tp[2]) - 6.0))
		var vv = VehicleFactory.spawn(StringName(v["veh"]), xf, {})
		if vv != null:
			_veh = vv
			await get_tree().create_timer(0.4).timeout
			if is_instance_valid(pl):
				pl.enter_vehicle(vv)
	# camera
	if v.has("cam"):
		var c: Array = v["cam"]
		if _cam == null:
			_cam = Camera3D.new()
			_cam.name = "ArtCamera"
			_cam.far = 1500.0
			main.add_child(_cam)
		_cam.fov = float(v.get("fov", 70.0))
		_cam.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		_cam.look_at(Vector3(float(c[3]), float(c[4]), float(c[5])), Vector3.UP)
		_cam.make_current()
	elif _cam != null:
		_cam.clear_current(true)
	# weather + time
	env.set_weather(StringName(v.get("w", "clear")), true)
	env.set_time(float(v.get("t", 12.0)))
	Game.time_frozen = true
	await get_tree().create_timer(0.3).timeout
	# nudge the reflection probe so it re-captures the sky of the new time of day
	if env.probe != null:
		env.probe.global_position = env.probe.global_position + Vector3(0.05, 0.0, 0.0)
	env.set_time(float(v.get("t", 12.0)))
	await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("TEST art FAIL no image for ", nm)
		return
	var err := img.save_png(path)
	print("TEST art ", nm, " PASS err=", err)
