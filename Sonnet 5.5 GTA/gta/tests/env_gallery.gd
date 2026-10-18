extends Node
## Real-renderer screenshot gallery for the Environment agent. Run with a window (NOT headless):
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\env\_last.png -Seconds 200 -GameArgs "--exec=res://gta/tests/env_gallery.gd --delay=2 --no-traffic --no-peds"
## Optional filter through the environment variable ENV_GALLERY_SET (times | weather | night | all, default all).
## Writes screenshots\env\*.png plus contact sheets (sheet_*.png).

const OUT_DIR := "res://screenshots/env/"
const SHOT_W := 480
const SHOT_H := 270
const SHEET_COLS := 3

var _env: EnvironmentSystem
var _cam: Camera3D
var _sheet_images: Dictionary = {}


func run(main: Node) -> String:
	_env = Game.sys(&"environment") as EnvironmentSystem
	if _env == null:
		print("TEST gallery FAIL no environment system")
		return "no env"
	var scene_script = load("res://gta/tests/env_test_scene.gd")
	var rig: Dictionary = scene_script.build(main)
	_cam = rig["cam"]
	Game.time_frozen = true
	if Game.ui is CanvasLayer:
		(Game.ui as CanvasLayer).visible = false
	if is_instance_valid(Game.player):
		Game.player.visible = false
	Game.cheats["invulnerable"] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var which := OS.get_environment("ENV_GALLERY_SET")
	if which == "":
		which = "all"
	await get_tree().create_timer(0.5).timeout

	if _want(which, "times"):
		for t in [[6.0, "dawn"], [8.0, "morning"], [12.0, "noon"], [16.5, "afternoon"], [18.5, "sunset"], [19.4, "dusk"], [21.0, "night21"], [0.0, "midnight"]]:
			_env.set_weather(&"clear", true)
			for view in ["street", "sun", "away"]:
				await _shoot("t_%s_%s" % [t[1], view], t[0], view, "sheet_times")
	if _want(which, "weather"):
		for w in [&"clear", &"cloudy", &"rain", &"fog", &"storm"]:
			_env.set_weather(w, true)
			await _shoot("w_%s" % w, 14.0, "street", "sheet_weather", 1.6 if w in [&"rain", &"storm"] else 0.8)
		_env.set_weather(&"storm", true)
		await _shoot("w_storm_sky", 14.0, "sky", "sheet_weather", 1.2)
		_place_camera("sky")
		var sd := _env.get_sun_direction()
		var look_az := atan2(sd.x, -sd.z) + PI
		_env.trigger_lightning(250.0, look_az)
		await get_tree().create_timer(0.05).timeout
		await _shoot("w_storm_flash", 14.0, "sky", "sheet_weather", 0.0)
	if _want(which, "night"):
		for w in [&"clear", &"rain", &"fog"]:
			_env.set_weather(w, true)
			await _shoot("n_%s_street" % w, 22.0, "street", "sheet_night", 1.6 if w == &"rain" else 0.8)
			await _shoot("n_%s_low" % w, 22.0, "lamps", "sheet_night", 0.6)
		_env.set_weather(&"clear", true)
		await _shoot("n_lamp_close", 22.0, "lamp_close", "sheet_night", 0.6)
		_env.set_weather(&"rain", true)
		await _shoot("n_lamp_close_rain", 22.0, "lamp_close", "sheet_night", 1.8)
	if _want(which, "cars"):
		_env.set_weather(&"clear", true)
		for h in [13.0, 18.6, 22.0]:
			await _shoot("c_cars_%d" % int(h), h, "cars", "sheet_cars", 0.8)
		_env.set_weather(&"rain", true)
		await _shoot("c_cars_rain", 14.0, "cars", "sheet_cars", 1.5)
		_env.probe.visible = false
		_env.set_weather(&"clear", true)
		await _shoot("c_cars_noprobe", 13.0, "cars", "sheet_cars", 0.8)
		_env.probe.visible = true
	if _want(which, "underwater"):
		_env.set_weather(&"clear", true)
		_env.set_underwater_override(1)
		await _shoot("u_underwater_day", 13.0, "under", "sheet_under", 1.0)
		await _shoot("u_underwater_dusk", 18.8, "under", "sheet_under", 1.0)
		_env.set_underwater_override(-1)
	_save_sheets()
	print("TEST gallery PASS shots written to ", OUT_DIR)
	return "ok"


func _want(which: String, key: String) -> bool:
	return which == "all" or ("," + which + ",").contains("," + key + ",")


func _shoot(shot_name: String, hour: float, view: String, sheet: String, settle: float = 0.8) -> void:
	_env.set_time(hour)
	_cam.make_current()
	_place_camera(view)
	await get_tree().create_timer(settle).timeout
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("TEST gallery_noimage for ", shot_name)
		return
	var path := ProjectSettings.globalize_path(OUT_DIR + shot_name + ".png")
	img.save_png(path)
	var small := img.duplicate() as Image
	small.resize(SHOT_W, SHOT_H, Image.INTERPOLATE_BILINEAR)
	if not _sheet_images.has(sheet):
		_sheet_images[sheet] = []
	_sheet_images[sheet].append(small)
	print("TEST gallery_shot ", shot_name, " hour=", hour, " weather=", _env.get_weather(), " el=%.1f night=%.2f rain_fx=%s lamps=%s" % [_env.get_sun_elevation_deg(), _env.get_night_amount(), _env.weather_fx.get_stats(), _env.lamps.get_stats()])


func _place_camera(view: String) -> void:
	var sd := _env.get_sun_direction()
	var flat := Vector3(sd.x, 0.0, sd.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, 1)
	match view:
		"street":
			_cam.global_position = Vector3(30, 2.6, 165)
			_cam.look_at(Vector3(30, 9, -80), Vector3.UP)
			_env.set_underwater_override(-1)
		"sun":
			_cam.global_position = Vector3(0, 55, 232)
			var pitch := clampf(_env.get_sun_elevation_deg() * 0.8, 4.0, 22.0)
			_cam.look_at(_cam.global_position + flat * 200.0 + Vector3(0, 200.0 * tan(deg_to_rad(pitch)), 0), Vector3.UP)
		"away":
			_cam.global_position = Vector3(0, 55, 232)
			_cam.look_at(_cam.global_position - flat * 200.0 + Vector3(0, 30.0, 0), Vector3.UP)
		"sky":
			_cam.global_position = Vector3(0, 30, 232)
			_cam.look_at(_cam.global_position - flat * 80.0 + Vector3(0, 70, 0), Vector3.UP)
		"lamps":
			_cam.global_position = Vector3(30, 1.8, 156)
			_cam.look_at(Vector3(24, 4.0, 100), Vector3.UP)
		"lamp_close":
			_cam.global_position = Vector3(33, 1.7, 152)
			_cam.look_at(Vector3(24, 3.5, 136), Vector3.UP)
		"cars":
			_cam.global_position = Vector3(-4, 1.7, 14)
			_cam.look_at(Vector3(2, 0.9, 7), Vector3.UP)
		"under":
			_cam.global_position = Vector3(0, -6.0, 245)
			_cam.look_at(Vector3(0, -5.0, 150), Vector3.UP)


func _save_sheets() -> void:
	for sheet in _sheet_images:
		var imgs: Array = _sheet_images[sheet]
		if imgs.is_empty():
			continue
		var cols := SHEET_COLS
		var rows := int(ceil(float(imgs.size()) / float(cols)))
		var out := Image.create_empty(SHOT_W * cols, SHOT_H * rows, false, Image.FORMAT_RGBA8)
		for i in imgs.size():
			var im: Image = imgs[i]
			im.convert(Image.FORMAT_RGBA8)
			out.blit_rect(im, Rect2i(0, 0, SHOT_W, SHOT_H), Vector2i((i % cols) * SHOT_W, (i / cols) * SHOT_H))
		out.save_png(ProjectSettings.globalize_path(OUT_DIR + sheet + ".png"))
		print("TEST gallery_sheet ", sheet, " images=", imgs.size())
