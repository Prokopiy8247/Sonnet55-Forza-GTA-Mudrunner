extends Node
## GPU/CPU cost of the environment pieces, measured with RenderingServer's per-viewport render timers.
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\env\_perf.png -Resolution 1920x1080 -Seconds 300 -GameArgs "--exec=res://gta/tests/env_perf.gd --delay=2 --no-traffic --no-peds"
## Prints "TEST perf_<name> INFO gpu_ms=.. cpu_ms=.." lines. The test city is light, so the shadow numbers are optimistic.

const WARMUP := 60
const SAMPLES := 150

var _env: EnvironmentSystem
var _cam: Camera3D
var _vp: RID


func run(main: Node) -> String:
	_env = Game.sys(&"environment") as EnvironmentSystem
	if _env == null:
		return "no env"
	var rig: Dictionary = load("res://gta/tests/env_test_scene.gd").build(main)
	_cam = rig["cam"]
	if Game.ui is CanvasLayer:
		(Game.ui as CanvasLayer).visible = false
	if is_instance_valid(Game.player):
		Game.player.visible = false
	Game.cheats["invulnerable"] = true
	Game.time_frozen = true
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	print("TEST perf_info INFO resolution=", get_viewport().get_visible_rect().size, " window=", DisplayServer.window_get_size())

	# --- daytime breakdown (view over the city with plenty of sky) ---
	_env.set_weather(&"clear", true)
	_env.set_time(13.0)
	_view_city()
	var env := _env.environment
	var base := await _measure("day_all_on")
	_env.sun.shadow_enabled = false
	_env._shadows_on = false
	var no_shadow := await _measure("day_no_shadows")
	_env._shadows_on = true
	_env.sun.shadow_enabled = true
	env.ssao_enabled = false
	_env._ssao_on = false
	var no_ssao := await _measure("day_no_ssao")
	_env._ssao_on = true
	env.ssao_enabled = true
	env.glow_enabled = false
	_env._glow_on = false
	var no_glow := await _measure("day_no_glow")
	_env._glow_on = true
	env.glow_enabled = true
	env.fog_enabled = false
	var no_fog := await _measure("day_no_fog")
	env.fog_enabled = true
	# flat colour sky instead of the procedural sky
	var sky_res := env.sky
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#5aa0e0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8fb4e0")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var flat_sky := await _measure("day_flat_sky_color")
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# probe
	_env.probe.visible = false
	var no_probe := await _measure("day_no_probe")
	_env.probe.visible = true
	# everything minimal
	env.ssao_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	_env.sun.shadow_enabled = false
	_env._shadows_on = false
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.probe.visible = false
	env.adjustment_enabled = false
	var minimal := await _measure("day_minimal_everything_off")
	env.ssao_enabled = true
	env.glow_enabled = true
	env.fog_enabled = true
	env.adjustment_enabled = true
	_env._shadows_on = true
	_env.sun.shadow_enabled = true
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.probe.visible = true
	print("TEST perf_summary_day INFO full=%.2f shadows=%.2f ssao=%.2f glow=%.2f fog=%.2f sky_shader_vs_flat=%.2f probe=%.2f total_vs_minimal=%.2f ms (gpu)" % [
			base.x, base.x - no_shadow.x, base.x - no_ssao.x, base.x - no_glow.x, base.x - no_fog.x, base.x - flat_sky.x, base.x - no_probe.x, base.x - minimal.x])
	var env_cost_wo_shadows := (base.x - minimal.x) - (base.x - no_shadow.x)
	print("TEST perf_env_without_shadows INFO %.2f ms gpu (sky+ssao+glow+fog+tonemap/adjust)" % env_cost_wo_shadows)

	# --- night with street lamps ---
	_env.set_time(22.0)
	_view_street()
	_env.refresh_lamps()
	await get_tree().create_timer(2.0).timeout
	var night := await _measure("night_lamps_on")
	print("TEST perf_lamps INFO ", _env.lamps.get_stats())
	_env.lamps.pool_size = 0
	await get_tree().create_timer(1.5).timeout
	var night_nolights := await _measure("night_lamps_pool_0")
	_env.lamps.pool_size = LampManager.POOL_SIZE
	print("TEST perf_summary_night INFO lamps (28 spot lights + halos) = %.2f ms gpu" % (night.x - night_nolights.x))

	# --- weather ---
	_env.set_time(14.0)
	_view_street()
	_env.set_weather(&"clear", true)
	await get_tree().create_timer(1.0).timeout
	var dry := await _measure("weather_clear")
	_env.set_weather(&"rain", true)
	await get_tree().create_timer(2.5).timeout
	var rain := await _measure("weather_rain")
	_env.set_weather(&"storm", true)
	await get_tree().create_timer(2.5).timeout
	var storm := await _measure("weather_storm")
	_env.set_weather(&"fog", true)
	await get_tree().create_timer(1.0).timeout
	var fog := await _measure("weather_fog")
	print("TEST perf_summary_weather INFO rain=+%.2f storm=+%.2f fog=+%.2f ms gpu (clear = %.2f)" % [rain.x - dry.x, storm.x - dry.x, fog.x - dry.x, dry.x])
	# SSR for wet roads
	_env.set_weather(&"rain", true)
	_env._ssr_pref = false
	await get_tree().create_timer(0.5).timeout
	var no_ssr := await _measure("rain_ssr_off")
	_env._ssr_pref = true
	await get_tree().create_timer(0.5).timeout
	var ssr := await _measure("rain_ssr_on")
	print("TEST perf_summary_ssr INFO SSR adds %.2f ms gpu while it rains" % (ssr.x - no_ssr.x))
	_env._ssr_pref = false
	# underwater overlay
	_env.set_weather(&"clear", true)
	_env.set_time(13.0)
	_cam.global_position = Vector3(0, -6.0, 245)
	_cam.look_at(Vector3(0, -5.0, 150), Vector3.UP)
	_env.set_underwater_override(1)
	await get_tree().create_timer(1.0).timeout
	var uw := await _measure("underwater")
	_env.set_underwater_override(-1)
	print("TEST perf_summary_underwater INFO %.2f ms gpu total underwater frame" % uw.x)
	# reflection probe re-capture hitch
	_env.set_time(13.0)
	_view_city()
	await get_tree().create_timer(1.0).timeout
	var worst_static := 0.0
	for i in 90:
		await RenderingServer.frame_post_draw
		worst_static = maxf(worst_static, RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	var worst_move := 0.0
	var worst_cpu := 0.0
	_env.probe.global_position += Vector3(70, 0, 0)
	for i in 40:
		await RenderingServer.frame_post_draw
		worst_move = maxf(worst_move, RenderingServer.viewport_get_measured_render_time_gpu(_vp))
		worst_cpu = maxf(worst_cpu, RenderingServer.viewport_get_measured_render_time_cpu(_vp))
	print("TEST perf_probe_move INFO worst frame gpu: static=%.2f ms, in the 40 frames after moving the probe=%.2f ms (cpu %.2f)" % [worst_static, worst_move, worst_cpu])
	print("TEST perf_script_cost INFO EnvironmentSystem script %.3f ms/frame" % _env.get_cpu_cost_ms())
	return "ok"


func _view_city() -> void:
	_cam.global_position = Vector3(0, 55, 232)
	_cam.look_at(Vector3(0, 40, 0), Vector3.UP)
	_cam.make_current()


func _view_street() -> void:
	_cam.global_position = Vector3(30, 2.6, 165)
	_cam.look_at(Vector3(30, 9, -80), Vector3.UP)
	_cam.make_current()


## returns Vector2(gpu_ms, cpu_ms)
func _measure(label: String) -> Vector2:
	for i in WARMUP:
		await RenderingServer.frame_post_draw
	var gpu := 0.0
	var cpu := 0.0
	for i in SAMPLES:
		await RenderingServer.frame_post_draw
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
	var r := Vector2(gpu / SAMPLES, cpu / SAMPLES)
	print("TEST perf_%s INFO gpu_ms=%.2f cpu_ms=%.2f fps=%d" % [label, r.x, r.y, Engine.get_frames_per_second()])
	return r
