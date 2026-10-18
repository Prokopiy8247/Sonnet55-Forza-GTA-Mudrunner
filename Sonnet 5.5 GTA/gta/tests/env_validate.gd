extends SceneTree
## Loads only the Environment-agent scripts + shader files so parse errors are visible even while other agents' files are broken.
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/env_validate.gd
const FILES := [
	"res://gta/code/world/day_night_cycle.gd",
	"res://gta/code/world/weather_controller.gd",
	"res://gta/code/world/weather_fx.gd",
	"res://gta/code/world/lamp_manager.gd",
	"res://gta/code/world/environment_underwater.gd",
	"res://gta/code/world/environment_system.gd",
	"res://gta/tests/env_test.gd",
	"res://gta/tests/env_gallery.gd",
	"res://gta/tests/env_perf.gd",
	"res://gta/tests/env_test_scene.gd",
	"res://gta/tests/env_boot.gd",
	"res://gta/tests/env_test_standalone.gd",
]
const SHADERS := [
	"res://gta/generated/shaders/sky_procedural.gdshader",
	"res://gta/generated/shaders/weather_rain_streak.gdshader",
	"res://gta/generated/shaders/weather_rain_splash.gdshader",
	"res://gta/generated/shaders/weather_rain_sheet.gdshader",
	"res://gta/generated/vfx/lamp_halo.gdshader",
	"res://gta/generated/vfx/underwater_overlay.gdshader",
]
func _initialize() -> void:
	var fails := 0
	for f in FILES:
		if not ResourceLoader.exists(f):
			continue
		var res = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res == null or (res is GDScript and not (res as GDScript).can_instantiate()):
			print("ENVVALIDATE FAIL ", f)
			fails += 1
		else:
			print("ENVVALIDATE ok ", f)
	for f in SHADERS:
		var sh = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_REPLACE)
		print("ENVVALIDATE shader ", f, " ", "ok" if sh != null else "FAIL")
		if sh == null:
			fails += 1
	print("ENVVALIDATE done fails=", fails)
	quit(1 if fails > 0 else 0)
