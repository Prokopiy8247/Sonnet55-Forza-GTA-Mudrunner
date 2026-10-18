extends Node
## Headless logic tests for the Environment agent (deterministic: steps EnvironmentSystem / LampManager by hand).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/env_test.gd -Seconds 90
## or, without booting Main (works while other modules are broken):
##   powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/tests/env_test_standalone.gd
## Prints "TEST <name> PASS|FAIL <detail>" lines.

const DT := 1.0 / 60.0

var _env: EnvironmentSystem
var _fails := 0
var _passes := 0
var _time_events := 0
var _hour_events: Array = []
var _weather_events: Array = []
var _uw_events: Array = []
var _lightning_events := 0


func run(parent: Node) -> String:
	_env = Game.sys(&"environment") as EnvironmentSystem
	if _env == null:
		print("TEST env_boot FAIL environment system not registered")
		return "FAIL"
	_env.set_process(false)
	_env.lamps.set_process(false)
	Game.time_frozen = false
	Game.time_scale = 60.0
	Events.time_changed.connect(func(_h): _time_events += 1)
	Events.hour_changed.connect(func(h): _hour_events.append(h))
	Events.weather_changed.connect(func(w): _weather_events.append(w))
	_env.underwater_changed.connect(func(b): _uw_events.append(b))
	_env.lightning_struck.connect(func(_d, _a): _lightning_events += 1)

	_test_nodes()
	_test_sun_path()
	_test_globals_exist()
	_test_night_curve()
	_test_time_advance()
	_test_time_events()
	_test_api_helpers()
	_test_palette_sanity()
	_test_weather()
	_test_storm_lightning()
	_test_lamps(parent)
	_test_underwater()
	_test_quality()
	_test_dynamic_weather()
	_test_load_resync()
	_test_cost()
	print("TEST env_summary %s passes=%d fails=%d" % ["PASS" if _fails == 0 else "FAIL", _passes, _fails])
	return "PASS" if _fails == 0 else "FAIL"


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
	else:
		_fails += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _step(seconds: float, cam_node: Node = null) -> void:
	var n := int(round(seconds / DT))
	for i in n:
		_env._process(DT)
		_env.lamps._process(DT)


func _gparam(gname: String) -> float:
	# value last pushed by EnvironmentSystem (RenderingServer returns nothing in headless runs)
	return _env.get_shader_global(StringName(gname))


# ---------------------------------------------------------------------------------------------------
func _test_nodes() -> void:
	_check("env_nodes", _env.world_environment != null and _env.environment != null and _env.sun != null and _env.moon != null
			and _env.lamps != null and _env.weather_fx != null and _env.probe != null,
			"WorldEnvironment/Sun/Moon/Lamps/RainFx/Probe built")
	_check("env_sky_material", _env.sky_material != null and _env.sky_material.shader != null, "procedural sky shader assigned")
	_check("env_shadow_cfg", _env.sun.directional_shadow_max_distance == 220.0 and _env.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
			"PSSM 4 splits, 220 m")
	_check("env_tonemap_glow_ssao_fog", _env.environment.glow_enabled and _env.environment.ssao_enabled and _env.environment.fog_enabled
			and _env.environment.tonemap_mode == Environment.TONE_MAPPER_AGX, "AgX + glow + ssao + fog on")


func _test_sun_path() -> void:
	var ok := true
	var detail := ""
	_env.set_time(12.0)
	var noon_el := _env.get_sun_elevation_deg()
	var noon_dir := _env.get_sun_direction()
	ok = ok and noon_el > 45.0 and noon_el < 70.0 and is_equal_approx(noon_dir.length(), 1.0) and noon_dir.z > 0.0
	detail += "noon_el=%.1f " % noon_el
	_env.set_time(6.0)
	var rise_el := _env.get_sun_elevation_deg()
	ok = ok and absf(rise_el) < 1.5
	detail += "rise_el=%.2f " % rise_el
	_env.set_time(19.0)
	var set_el := _env.get_sun_elevation_deg()
	ok = ok and absf(set_el) < 1.5
	detail += "set_el=%.2f " % set_el
	_env.set_time(8.0)
	var morning_x := _env.get_sun_direction().x
	_env.set_time(17.0)
	var evening_x := _env.get_sun_direction().x
	ok = ok and morning_x > 0.2 and evening_x < -0.2
	detail += "x(8h)=%.2f x(17h)=%.2f " % [morning_x, evening_x]
	_env.set_time(0.0)
	var mid_el := _env.get_sun_elevation_deg()
	var moon_el := _env.get_moon_direction().y
	ok = ok and mid_el < -25.0 and moon_el > 0.3
	detail += "midnight_el=%.1f moon_y=%.2f" % [mid_el, moon_el]
	_check("env_sun_path", ok, detail)
	_check("env_light_direction", _env.get_light_direction().is_equal_approx(-_env.get_sun_direction()), "light travels opposite to sun dir")


func _test_globals_exist() -> void:
	var missing: Array = []
	for g in ["gta_night", "gta_wetness", "gta_rain", "gta_fog", "gta_time", "gta_sun_energy"]:
		if not Game.SHADER_GLOBALS.has(g) or _gparam(g) < -0.5:
			missing.append(g)
	_check("env_globals_registered", missing.is_empty(), "missing=%s" % [missing])
	var rs_val = RenderingServer.global_shader_parameter_get("gta_night")
	print("TEST env_globals_rs_info INFO RenderingServer value=", rs_val, " (null is normal in headless)")


func _test_night_curve() -> void:
	var samples := {}
	for h in [12.0, 17.0, 18.5, 19.0, 19.5, 20.0, 20.5, 21.0, 0.0, 4.0, 5.0, 5.5, 6.0, 6.5, 8.0]:
		_env.set_time(h)
		samples[h] = _gparam("gta_night")
	var mono_dusk: bool = samples[17.0] <= samples[18.5] and samples[18.5] <= samples[19.0] and samples[19.0] <= samples[19.5] \
			and samples[19.5] <= samples[20.0] and samples[20.0] <= samples[20.5] and samples[20.5] <= samples[21.0]
	var mono_dawn: bool = samples[4.0] >= samples[5.0] and samples[5.0] >= samples[5.5] and samples[5.5] >= samples[6.0] and samples[6.0] >= samples[6.5]
	_check("env_gta_night_curve", samples[12.0] < 0.01 and samples[0.0] > 0.99 and mono_dusk and mono_dawn and samples[19.0] > 0.05 and samples[19.0] < 0.5,
			"noon=%.2f 18:30=%.2f 19:00=%.2f 19:30=%.2f 20:00=%.2f 21:00=%.2f midnight=%.2f 06:00=%.2f 08:00=%.2f" % [
			samples[12.0], samples[18.5], samples[19.0], samples[19.5], samples[20.0], samples[21.0], samples[0.0], samples[6.0], samples[8.0]])
	_env.set_time(12.0)
	_check("env_sun_energy_global", _gparam("gta_sun_energy") > 0.7, "gta_sun_energy at noon=%.2f" % _gparam("gta_sun_energy"))
	_env.set_time(0.0)
	_check("env_sun_energy_night", _gparam("gta_sun_energy") < 0.01, "gta_sun_energy at midnight=%.3f" % _gparam("gta_sun_energy"))


func _test_time_advance() -> void:
	Game.time_frozen = false
	Game.time_scale = 60.0
	_env.set_time(10.0)
	_step(10.0)
	var advanced := Game.time_of_day - 10.0
	_check("env_time_advance", absf(advanced - 600.0 / 3600.0) < 0.002, "10 s real at 60x -> +%.4f h (expected 0.1667)" % advanced)
	Game.time_frozen = true
	var t0 := Game.time_of_day
	_step(3.0)
	_check("env_time_frozen", Game.time_of_day == t0, "time_frozen keeps the clock")
	Game.time_frozen = false
	_env.set_time(23.99)
	_step(2.0)
	_check("env_time_wraps", Game.time_of_day >= 0.0 and Game.time_of_day < 1.0, "wrapped past midnight -> %.3f" % Game.time_of_day)
	# fast forward
	_env.set_time(22.0)
	_env.fast_forward_to(7.0, 2.0)
	_step(2.2)
	_check("env_fast_forward", absf(fposmod(Game.time_of_day - 7.0, 24.0)) < 0.05 or absf(fposmod(Game.time_of_day - 7.0, 24.0) - 24.0) < 0.05,
			"22:00 -> 07:00 in 2 s, now %.3f" % Game.time_of_day)


func _test_time_events() -> void:
	Game.time_frozen = false
	_env.set_time(9.0)
	_time_events = 0
	_hour_events.clear()
	_step(5.05)
	_check("env_time_changed_event", _time_events >= 4 and _time_events <= 6, "events in 5 s: %d (about 1/s)" % _time_events)
	_env.set_time(9.995)
	_hour_events.clear()
	_step(1.0)
	_check("env_hour_changed_event", _hour_events.has(10), "hour events=%s" % [_hour_events])
	_time_events = 0
	_env.set_time(15.0)
	_check("env_set_time_emits", _time_events >= 1, "set_time emits time_changed immediately")


func _test_api_helpers() -> void:
	Game.time_frozen = true
	_env.set_weather(&"clear", true)
	_env.set_time(13.0)
	_step(0.2)
	var day_night := _env.is_night()
	var day_lights := _env.headlights_wanted()
	_env.set_time(1.0)
	_step(0.2)
	var night_night := _env.is_night()
	var night_lights := _env.headlights_wanted()
	_check("env_is_night", (not day_night) and night_night, "13:00 -> %s, 01:00 -> %s" % [day_night, night_night])
	_check("env_headlights_wanted", (not day_lights) and night_lights, "day=%s night=%s" % [day_lights, night_lights])
	_env.set_time(13.0)
	_env.set_weather(&"fog", true)
	_step(0.2)
	_check("env_headlights_fog", _env.headlights_wanted(), "fog in daytime wants headlights")
	_env.set_weather(&"clear", true)
	_check("env_visibility_distance", _env.get_visibility_distance() > 1500.0, "clear visibility=%.0f m" % _env.get_visibility_distance())
	_env.set_weather(&"fog", true)
	_step(0.2)
	var fog_vis := _env.get_visibility_distance()
	_check("env_fog_visibility", fog_vis < 260.0 and fog_vis > 60.0, "fog visibility=%.0f m" % fog_vis)
	_env.set_weather(&"clear", true)


func _test_palette_sanity() -> void:
	var bad := 0
	var worst := ""
	var prev_day := -1.0
	var monotonic := true
	for el in range(-40, 71, 2):
		var p := DayNightCycle.compose(float(el), true, DayNightCycle.weather_params(&"clear"))
		for k in ["zenith", "mid", "horizon", "ground", "fog_color", "cloud_lit", "cloud_shade", "sun_color", "glow", "band"]:
			var c: Color = p[k]
			if is_nan(c.r) or is_nan(c.g) or is_nan(c.b) or c.r < -0.001 or c.r > 1.5 or c.g < -0.001 or c.g > 1.5 or c.b < -0.001 or c.b > 1.5:
				bad += 1
				worst = "%s@%d=%s" % [k, el, c]
		for k in ["sun_energy", "ambient_energy", "exposure", "fog_density", "saturation", "night"]:
			var v: float = float(p[k])
			if is_nan(v) or v < 0.0:
				bad += 1
				worst = "%s@%d=%f" % [k, el, v]
		if el >= -2 and el <= 30:
			var se: float = float(p["sun_energy"])
			if se + 0.001 < prev_day:
				monotonic = false
			prev_day = se
	_check("env_palette_sane", bad == 0, "bad entries=%d %s" % [bad, worst])
	_check("env_sun_energy_monotonic", monotonic, "sun energy rises with elevation through sunrise")
	for w in GC.WEATHERS:
		var wp := DayNightCycle.weather_params(w)
		var p2 := DayNightCycle.compose(30.0, true, wp)
		bad += 0 if (float(p2["sun_energy"]) >= 0.0 and float(p2["fog_density"]) > 0.0) else 1
	_check("env_weather_compose", bad == 0, "all %d weather states compose" % GC.WEATHERS.size())


func _test_weather() -> void:
	Game.time_frozen = true
	_env.set_time(14.0)
	_env.set_weather(&"clear", true)
	_step(0.5)
	_weather_events.clear()
	var ok_unknown := not _env.set_weather(&"hail", false)
	_check("env_weather_unknown", ok_unknown, "unknown weather rejected")
	# age gate: force a non-boot-instant transition
	_env._age = 100.0
	_check("env_weather_set_rain", _env.set_weather(&"rain", false) and Game.weather == &"rain", "Game.weather=rain immediately")
	_check("env_weather_event", _weather_events.has(&"rain"), "Events.weather_changed(rain)")
	_step(2.0)
	var mid_rain := Game.rain_intensity
	_check("env_weather_transition_smooth", mid_rain > 0.0 and mid_rain < 0.5 and _env.get_weather_transition() < 0.5, "2 s into the blend: rain=%.2f transition=%.2f" % [mid_rain, _env.get_weather_transition()])
	_step(9.0)
	_check("env_rain_settled", absf(Game.rain_intensity - 0.7) < 0.02 and _env.get_weather_transition() >= 1.0, "rain=%.2f after 11 s" % Game.rain_intensity)
	_check("env_gta_rain_global", absf(_gparam("gta_rain") - Game.rain_intensity) < 0.02, "gta_rain=%.2f" % _gparam("gta_rain"))
	_check("env_wet_rising", Game.wetness > 0.35 and Game.wetness < 0.95, "wetness after 11 s of rain=%.2f" % Game.wetness)
	_step(15.0)
	var soaked := Game.wetness
	_check("env_wet_soaked", soaked > 0.75, "wetness after 26 s of rain=%.2f" % soaked)
	_check("env_gta_wetness_global", absf(_gparam("gta_wetness") - Game.wetness) < 0.01, "gta_wetness=%.2f" % _gparam("gta_wetness"))
	_check("env_is_raining", _env.is_raining(), "is_raining() true")
	# stop the rain: intensity falls in ~10 s, wetness lags
	_env.set_weather(&"clear", false)
	_step(11.0)
	var wet_after_stop := Game.wetness
	_check("env_rain_stops", Game.rain_intensity < 0.02 and not _env.is_raining(), "rain=%.3f" % Game.rain_intensity)
	_check("env_wet_lags", wet_after_stop > soaked - 0.1, "wetness right after the rain stopped=%.2f (was %.2f)" % [wet_after_stop, soaked])
	_step(120.0)
	var wet_2min := Game.wetness
	_check("env_wet_dries_slowly", wet_2min < wet_after_stop - 0.2 and wet_2min > 0.2, "wetness 2 min later=%.2f" % wet_2min)
	_step(240.0)
	_check("env_wet_dry_again", Game.wetness < 0.02, "wetness 6 min later=%.3f" % Game.wetness)
	# fog
	_env.set_weather(&"fog", false)
	_step(11.0)
	_check("env_fog_state", Game.fog_amount > 0.95 and Game.weather == &"fog", "fog_amount=%.2f" % Game.fog_amount)
	_check("env_gta_fog_global", _gparam("gta_fog") > 0.95, "gta_fog=%.2f" % _gparam("gta_fog"))
	_env.set_weather(&"cloudy", true)
	_step(0.3)
	var cloudy_sun := _env.sun.light_energy
	_env.set_weather(&"clear", true)
	_step(0.3)
	var clear_sun := _env.sun.light_energy
	_check("env_cloudy_dimmer", cloudy_sun < clear_sun * 0.7 and cloudy_sun > 0.1, "sun energy clear=%.2f cloudy=%.2f" % [clear_sun, cloudy_sun])
	_env.set_weather(&"rain", true)
	_step(0.3)
	_check("env_instant_wetness", Game.wetness > 0.8, "instant rain sets wet roads (%.2f)" % Game.wetness)
	_env.set_weather(&"clear", true)


func _test_storm_lightning() -> void:
	Game.time_frozen = true
	_env.set_time(15.0)
	_env.set_weather(&"storm", true)
	_lightning_events = 0
	var max_flash := 0.0
	var saw_light := false
	for i in int(120.0 / DT):
		_env._process(DT)
		max_flash = maxf(max_flash, _env.weather.flash)
		if _env.flash_light.visible and _env.flash_light.light_energy > 0.5:
			saw_light = true
	_check("env_storm_lightning_events", _lightning_events >= 3, "strikes in 120 s: %d" % _lightning_events)
	_check("env_storm_flash_envelope", max_flash > 0.5 and saw_light, "max flash=%.2f flash light used=%s" % [max_flash, saw_light])
	_env.trigger_lightning(343.0 * 2.0)
	_check("env_thunder_scheduled", not _env._pending_thunder.is_empty(), "thunder delayed by distance")
	var delay := float((_env._pending_thunder.back() as Array)[0])
	_check("env_thunder_delay", absf(delay - 2.0) < 0.05, "thunder delay %.2f s for 686 m" % delay)
	_env._pending_thunder.clear()
	var wind_sum := 0.0
	for i in 60:
		_step(0.5)
		wind_sum += _env.get_wind().length()
	_check("env_storm_wind", wind_sum / 60.0 > 5.0, "mean wind=%.1f m/s" % (wind_sum / 60.0))
	_env.set_weather(&"clear", true)
	_step(3.0)
	_check("env_flash_resets", _env.weather.flash < 0.01, "flash after the storm=%.4f" % _env.weather.flash)


func _test_lamps(parent: Node) -> void:
	Game.time_frozen = true
	_env.set_weather(&"clear", true)
	var holder := Node3D.new()
	holder.name = "EnvTestLamps"
	parent.add_child(holder)
	var count := 0
	for i in 12:
		for j in 6:
			var lamp := Node3D.new()
			lamp.position = Vector3(-110.0 + i * 20.0, 0.0, -50.0 + j * 20.0)
			lamp.set_meta("lamp_height", 6.0)
			lamp.add_to_group("street_lamp")
			holder.add_child(lamp)
			count += 1
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.global_position = Vector3(0.0, 2.0, 0.0)
	cam.current = true
	_env.refresh_lamps()
	_env.set_time(13.0)
	_step(3.0)
	var day := _env.lamps.get_stats()
	_check("env_lamps_off_by_day", int(day["lights_active"]) == 0 and int(day["halos"]) == 0, "day stats=%s" % [day])
	_env.set_time(0.0)
	_step(4.0)
	var night := _env.lamps.get_stats()
	_check("env_lamps_pool_cap", int(night["lights_active"]) <= LampManager.POOL_SIZE and int(night["lights_active"]) >= 12, "lights_active=%d (cap %d) of %d lamps" % [night["lights_active"], LampManager.POOL_SIZE, count])
	_check("env_lamps_halos", int(night["halos"]) > 20 and int(night["halos"]) <= LampManager.HALO_MAX, "halos=%d" % night["halos"])
	var near_ok := true
	var spot_count := 0
	for l in _env.lamps.get_children():
		if l is SpotLight3D and l.visible:
			spot_count += 1
			if Vector2(l.global_position.x, l.global_position.z).length() > LampManager.LIGHT_RADIUS + 25.0:
				near_ok = false
			if l.global_position.y < 2.5 or l.global_position.y > 14.0:
				near_ok = false
	_check("env_lamps_lights_near_camera", near_ok and spot_count > 0, "%d active spot lights, all within radius, at lamp-head height" % spot_count)
	# move the camera far away: lights migrate
	cam.global_position = Vector3(110.0, 2.0, 50.0)
	_step(3.0)
	var moved_ok := true
	for l in _env.lamps.get_children():
		if l is SpotLight3D and l.visible and Vector3(l.global_position.x - 110.0, 0.0, l.global_position.z - 50.0).length() > LampManager.LIGHT_RADIUS + 25.0:
			moved_ok = false
	_check("env_lamps_reassign", moved_ok, "lights follow the camera")
	# storm gloom turns lamps on in the daytime
	_env.set_time(13.0)
	_env.set_weather(&"storm", true)
	_step(4.0)
	var gloom := _env.lamps.get_stats()
	_check("env_lamps_storm_gloom", int(gloom["lights_active"]) > 0, "storm daytime lamps on: %s" % [gloom])
	_env.set_weather(&"clear", true)
	_env.set_time(13.0)
	_step(5.0)
	_check("env_lamps_sleep", int(_env.lamps.get_stats()["lights_active"]) == 0, "all pooled lights off again by day")
	# frame cost of the lamp update at night
	_env.set_time(0.0)
	_step(3.0)
	var t0 := Time.get_ticks_usec()
	for i in 600:
		_env.lamps._process(DT)
	var us := float(Time.get_ticks_usec() - t0) / 600.0
	_check("env_lamps_cost", us < 400.0, "LampManager average %.0f us/frame (incl. 0.5 s assignment ticks)" % us)
	holder.queue_free()
	_env.refresh_lamps()


func _test_underwater() -> void:
	Game.time_frozen = true
	_env.set_time(13.0)
	_env.set_weather(&"clear", true)
	_step(0.5)
	var dry_density := _env.environment.fog_density
	var dry_color := _env.environment.fog_light_color
	_uw_events.clear()
	_env.set_underwater_override(1)
	_step(1.5)
	var wet_density := _env.environment.fog_density
	var wet_color := _env.environment.fog_light_color
	_check("env_underwater_amount", _env.get_underwater_amount() > 0.98 and _env.is_underwater(), "underwater_amount=%.2f" % _env.get_underwater_amount())
	_check("env_underwater_fog", wet_density > dry_density * 20.0 and wet_density > 0.04, "fog density %.4f -> %.4f" % [dry_density, wet_density])
	_check("env_underwater_tint", wet_color.b > wet_color.r + 0.15 and wet_color.g > wet_color.r, "fog colour %s" % [wet_color])
	_check("env_underwater_signal", _uw_events == [true], "signals=%s" % [_uw_events])
	var sun_a := _env.sun.light_energy
	_step(0.3)
	var sun_b := _env.sun.light_energy
	_check("env_underwater_caustic_light", absf(sun_a - sun_b) > 0.001, "sun energy breathes underwater (%.3f vs %.3f)" % [sun_a, sun_b])
	_env.set_underwater_override(0)
	_step(2.5)
	_check("env_underwater_surface", _env.get_underwater_amount() < 0.01 and absf(_env.environment.fog_density - dry_density) < 0.0004, "cross-faded out, fog %.4f" % _env.environment.fog_density)
	_check("env_underwater_signal_out", _uw_events == [true, false], "signals=%s" % [_uw_events])
	# camera based detection
	_env.set_underwater_override(-1)
	var holder := Node3D.new()
	_env.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0.0, -4.0, 260.0)
	_step(1.5)
	_check("env_underwater_camera", _env.is_underwater() and WorldLayout.is_water(0.0, 260.0), "camera at y=-4 over water -> underwater (is_water=%s)" % WorldLayout.is_water(0.0, 260.0))
	cam.global_position = Vector3(0.0, 1.5, 260.0)
	_step(2.0)
	_check("env_underwater_camera_out", not _env.is_underwater(), "camera above the surface -> clear")
	holder.queue_free()
	_step(0.1)


func _test_quality() -> void:
	Game.time_frozen = true
	_env.set_time(13.0)
	_env.set_weather(&"clear", true)
	_step(0.3)
	var shadows_before := _env.sun.shadow_enabled
	Game.settings["shadows"] = false
	Events.settings_changed.emit()
	_step(0.3)
	var shadows_off := _env.sun.shadow_enabled
	Game.settings["shadows"] = true
	Events.settings_changed.emit()
	_step(0.3)
	_check("env_quality_shadows", shadows_before and (not shadows_off) and _env.sun.shadow_enabled, "shadows toggle: %s -> %s -> %s" % [shadows_before, shadows_off, _env.sun.shadow_enabled])
	Game.settings["env_quality"] = 0
	_env.apply_quality()
	_check("env_quality_low", _env.lamps.pool_size == 12 and _env.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "low preset applied")
	Game.settings["env_quality"] = 2
	_env.apply_quality()
	_check("env_quality_high", _env.lamps.pool_size == LampManager.POOL_SIZE and _env.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "high preset restored")


func _test_dynamic_weather() -> void:
	Game.time_frozen = true
	_env.set_weather(&"clear", true)
	_env.set_dynamic_weather(true)
	_weather_events.clear()
	for i in 600:
		_env._process(2.0)
	_check("env_dynamic_weather", _weather_events.size() >= 2, "weather drifted %d times in 20 simulated minutes" % _weather_events.size())
	_env.set_dynamic_weather(false)
	_env.set_weather(&"clear", true)


func _test_load_resync() -> void:
	Game.time_frozen = true
	_env.set_weather(&"clear", true)
	Game.weather = &"fog"
	Events.load_completed.emit()
	_step(0.3)
	_check("env_load_resync", _env.get_weather() == &"fog" and Game.fog_amount > 0.9, "load_completed re-syncs weather (fog_amount=%.2f)" % Game.fog_amount)
	_env.set_weather(&"clear", true)


func _test_cost() -> void:
	Game.time_frozen = false
	_env.set_weather(&"storm", true)
	_env.set_time(19.0)
	_step(2.0)
	var t0 := Time.get_ticks_usec()
	var n := 1200
	for i in n:
		_env._process(DT)
		_env.lamps._process(DT)
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	_check("env_cpu_cost_storm", us < 900.0, "EnvironmentSystem + LampManager storm/dusk worst case %.0f us per frame (script)" % us)
	_env.set_weather(&"clear", true)
	t0 = Time.get_ticks_usec()
	for i in n:
		_env._process(DT)
	us = float(Time.get_ticks_usec() - t0) / float(n)
	_check("env_cpu_cost_clear", us < 700.0, "clear weather %.0f us per frame (script; headless on a busy machine - in-game cost is ~0.06-0.09 ms)" % us)
	Game.time_frozen = true
