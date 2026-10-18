class_name EnvironmentSystem
extends Node
## Environment agent: sky, sun / moon, lighting, day-night cycle, weather, post-processing, street lamps, underwater look.
## Booted by Main (key "environment"). Public API is summarised in docs/api/environment.md.
##
## Time:     Game.time_of_day (hours) advances by Game.time_scale game-seconds per real second unless Game.time_frozen.
##           Events.time_changed ~1/s, Events.hour_changed on the hour. set_time(hour), get_sun_direction(), is_night().
## Weather:  set_weather(name, instant := false) with 10 s blends; writes Game.weather / rain_intensity / wetness /
##           fog_amount / wind; Events.weather_changed on change.
## Globals:  gta_night, gta_sun_energy, gta_wetness, gta_rain, gta_fog, gta_time via Game.set_global().
## Lamps:    nodes in group "street_lamp" (meta lamp_height) get pooled lights + halos (LampManager).
## Never crashes the game: every optional dependency (camera, player, audio) is null-checked.

signal underwater_changed(is_underwater: bool)
signal lightning_struck(distance: float, azimuth: float)

const SKY_SHADER := "res://gta/generated/shaders/sky_procedural.gdshader"
const PALETTE_INTERVAL := 1.0 / 15.0
const SSAO_DAY_INTENSITY := 1.5            # contact shadows by day ...
const SSAO_NIGHT_INTENSITY := 0.7          # ... softer at night, so thin curb faces and window recesses do not go black
const NIGHT_AMBIENT_COLOR := Color(0.085, 0.125, 0.27)   # flat moonlit fill blended in at night (the night sky radiance alone leaves grass / asphalt pitch black)
const NIGHT_SKY_CONTRIB := 0.55
const DAY_SKY_CONTRIB := 0.34              # the rest of the daytime ambient is a soft lavender-grey (warm at sunrise / sunset), see _refresh_palette
const DAY_AMBIENT_TINT_GAIN := 0.74
const UW_FOG_COLOR := Color("#0e7a88")
const UW_DEEP_COLOR := Color("#052a40")

# ---- public nodes (read-only for others) ----
var world_environment: WorldEnvironment
var environment: Environment
var camera_attributes: CameraAttributesPractical
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var flash_light: DirectionalLight3D
var probe: ReflectionProbe
var lamps: LampManager
var weather_fx: WeatherFx
var underwater_fx: EnvironmentUnderwater
var weather: WeatherController

# ---- public state ----
var palette: Dictionary = {}
var night_amount := 0.0              # 0 day .. 1 night (= gta_night)
var lamp_on_amount := 0.0            # lamps / headlights demand: night or storm gloom (0..1)
var underwater_amount := 0.0         # smoothed 0..1
var sun_dir := Vector3.UP            # unit vector toward the sun
var moon_dir := Vector3.DOWN         # unit vector toward the moon
var sun_elevation_deg := 45.0
var cpu_cost_ms := 0.0               # smoothed script cost of this system per frame

var _root: Node3D
var _main: Node
var _age := 0.0
var _palette_accum := 1.0
var _force_refresh := true
var _time_event_accum := 0.0
var _last_hour := -1
var _uw_override := -1               # -1 auto, 0 off, 1 on
var _uw_state := false
var _uw_depth01 := 0.0
var _cloud_offset := Vector2.ZERO
var _sky_time := 0.0
var _gta_time_last := -1.0
var _globals_cache: Dictionary = {}
var _quality := 2
var _shadows_on := true
var _ssao_on := true
var _glow_on := true
var _probe_on := true
var _ssr_pref := true
var _settings_poll := 0.0
var _probe_last_pos := Vector3(1e9, 0.0, 1e9)
var _probe_timer := 0.0
var _probe_refresh_s := 30.0
var _pending_thunder: Array = []
var _rain_player: AudioStreamPlayer
var _rain_sound_id: StringName = &""
var _rain_audio_timer := 0.0
var _ff_remaining := 0.0             # hours left to fast-forward
var _ff_speed := 0.0                 # hours per real second
var _fallback_thunder_warned := false
var _camera_cache: Camera3D


# =====================================================================================================
# Lifecycle
# =====================================================================================================
func setup(main: Node) -> void:
	_main = main
	name = "EnvironmentSystem"
	_read_settings()
	_root = Node3D.new()
	_root.name = "EnvironmentRoot"
	add_child(_root)

	weather = WeatherController.new()
	weather.auto_drift = bool(Game.settings.get("dynamic_weather", false))
	weather.lightning.connect(_on_lightning)
	weather.set_state(Game.weather if Game.weather in GC.WEATHERS else GC.W_CLEAR, true)
	weather.state_changed.connect(_on_weather_state_changed)

	_build_environment()
	_build_lights()
	_build_probe()

	lamps = LampManager.new()
	_root.add_child(lamps)
	lamps.setup(Callable(self, "_get_camera"))

	weather_fx = WeatherFx.new()
	_root.add_child(weather_fx)
	weather_fx.setup()

	underwater_fx = EnvironmentUnderwater.new()
	add_child(underwater_fx)
	underwater_fx.setup()

	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	if not Events.load_completed.is_connected(_on_load_completed):
		Events.load_completed.connect(_on_load_completed)

	_apply_quality()
	var vp := get_viewport()
	if vp != null:
		vp.use_debanding = true          # kills the 8-bit banding of smooth sky gradients (sunset!)
	_update_sun_moon_dirs()
	_refresh_palette()
	_publish_game_state()
	_last_hour = int(floor(Game.time_of_day))


func post_setup() -> void:
	# another WorldEnvironment would fight with ours - report it once, do not touch it
	var others := 0
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		if n != world_environment:
			others += 1
	if others > 0:
		push_warning("EnvironmentSystem: %d other WorldEnvironment node(s) found - only EnvironmentSystem should own it" % others)
	_pick_rain_sound()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_age += delta
	_advance_time(delta)
	weather.update(delta)
	_sky_time += delta
	_cloud_offset += Vector2(weather.wind.x, weather.wind.z).normalized() * (0.004 * float(weather.params.get("cloud_speed", 1.0)) * delta)
	_update_sun_moon_dirs()

	var cam := _get_camera()
	_update_underwater(delta, cam)

	_palette_accum += delta
	var fast_time := absf(Game.time_scale) > 300.0
	if _force_refresh or _palette_accum >= PALETTE_INTERVAL or fast_time or weather.flash > 0.001 or underwater_amount > 0.001:
		_palette_accum = 0.0
		_force_refresh = false
		_refresh_palette()
		_publish_game_state()
	_update_light_transforms()

	lamps.on_amount = lamp_on_amount
	lamps.enabled = true
	weather_fx.light_scale = lerpf(1.0, 0.38, night_amount) * lerpf(1.0, 0.8, float(palette.get("overcast", 0.0)))
	weather_fx.update_fx(delta, cam, weather.rain, weather.wind, underwater_amount,
			clampf(float(weather.params.get("lightning", 0.0)), 0.0, 1.0))
	underwater_fx.set_state(underwater_amount, _uw_depth01, _viewport_aspect())

	_update_probe(delta, cam)
	_update_thunder(delta)
	_update_rain_audio(delta)
	_emit_time_events(delta)

	_settings_poll -= delta
	if _settings_poll <= 0.0:
		_settings_poll = 1.0
		_poll_settings()

	var dt_us := float(Time.get_ticks_usec() - t0)
	cpu_cost_ms = lerpf(cpu_cost_ms, dt_us / 1000.0, 0.05)


# =====================================================================================================
# Public API
# =====================================================================================================
## Jumps the clock to `hour` (0..24). Events.time_changed / hour_changed fire immediately.
func set_time(hour: float, _instant: bool = true) -> void:
	Game.time_of_day = fposmod(hour, 24.0)
	_ff_remaining = 0.0
	_force_refresh = true
	_update_sun_moon_dirs()
	_refresh_palette()
	_publish_game_state()
	_time_event_accum = 0.0
	Events.time_changed.emit(Game.time_of_day)
	var h := int(floor(Game.time_of_day))
	if h != _last_hour:
		_last_hour = h
		Events.hour_changed.emit(h)


func get_time() -> float:
	return Game.time_of_day


## Fast-forwards the clock to `hour` (always moving forward, wrapping midnight) in `seconds` of real time (sleep / wait).
func fast_forward_to(hour: float, seconds: float = 2.0) -> void:
	var dist := fposmod(fposmod(hour, 24.0) - Game.time_of_day, 24.0)
	_ff_remaining = dist
	_ff_speed = dist / maxf(seconds, 0.05)


## Unit vector from the world TOWARD the sun (also valid below the horizon).
func get_sun_direction() -> Vector3:
	return sun_dir


## Direction the sunlight travels (= -get_sun_direction()).
func get_light_direction() -> Vector3:
	return -sun_dir


func get_moon_direction() -> Vector3:
	return moon_dir


func get_sun_elevation_deg() -> float:
	return sun_elevation_deg


func is_night() -> bool:
	return night_amount > 0.5


func get_night_amount() -> float:
	return night_amount


## True when vehicles (traffic / police / player auto-lights) should have their headlights on: night, heavy rain, fog.
func headlights_wanted() -> bool:
	return lamp_on_amount > 0.4 or weather.fog_amount > 0.45 or weather.rain > 0.55


## 0 bright .. 1 dark (night or storm gloom) - drives street lamps.
func get_gloom() -> float:
	return lamp_on_amount


## Changes the weather. `instant` snaps all parameters (and wetness). During the first seconds after boot a request is
## always instant so DevHarness --weather shots are not mid-transition.
func set_weather(weather_name: StringName, instant: bool = false) -> bool:
	if not (weather_name in GC.WEATHERS):
		push_warning("EnvironmentSystem.set_weather: unknown weather '%s'" % weather_name)
		return false
	if _age < 6.0:
		instant = true
	weather.set_state(weather_name, instant)    # -> state_changed -> Game.weather + Events.weather_changed
	_force_refresh = true
	if instant:
		_publish_game_state()
		_refresh_palette()
	return true


func _on_weather_state_changed(weather_name: StringName) -> void:
	Game.weather = weather_name
	Events.weather_changed.emit(weather_name)


func get_weather() -> StringName:
	return weather.state


## 0..1 progress of the running weather transition (1 = settled).
func get_weather_transition() -> float:
	return weather.transition


func is_raining() -> bool:
	return weather.rain > 0.08


func get_rain_intensity() -> float:
	return weather.rain


func get_wetness() -> float:
	return weather.wetness


func get_wind() -> Vector3:
	return weather.wind


## Approximate distance (m) at which fog hides 95% of the scene.
func get_visibility_distance() -> float:
	var d := float(palette.get("fog_density", 0.001))
	return clampf(3.0 / maxf(d, 0.00005), 25.0, 5000.0)


## Fires a strike now. distance in metres (< 0 = random), azimuth in radians from north clockwise (NAN = random).
func trigger_lightning(distance: float = -1.0, azimuth: float = NAN) -> void:
	weather.trigger_lightning(distance, azimuth)


func set_dynamic_weather(on: bool) -> void:
	weather.auto_drift = on
	Game.settings["dynamic_weather"] = on


## -1 automatic (camera / player), 0 force off, 1 force on. Mainly for tests and cutscenes.
func set_underwater_override(mode: int) -> void:
	_uw_override = clampi(mode, -1, 1)


func is_underwater() -> bool:
	return underwater_amount > 0.5


func get_underwater_amount() -> float:
	return underwater_amount


func get_sun_light() -> DirectionalLight3D:
	return sun


func get_environment() -> Environment:
	return environment


## Last value written to a global shader parameter (gta_night, gta_wetness, ...), or -1 when unknown. Cheap, works headless.
func get_shader_global(gname: StringName) -> float:
	if gname == &"gta_time":
		return _gta_time_last
	return float(_globals_cache.get(gname, -1.0))


func get_palette() -> Dictionary:
	return palette.duplicate()


## Call when street lamps were added / removed in bulk.
func refresh_lamps() -> void:
	if lamps != null:
		lamps.invalidate()


func get_cpu_cost_ms() -> float:
	return cpu_cost_ms


func get_stats() -> Dictionary:
	var s := {"hour": Game.time_of_day, "sun_el": sun_elevation_deg, "night": night_amount, "lamp_on": lamp_on_amount,
			"weather": weather.state, "rain": weather.rain, "wetness": weather.wetness, "fog": weather.fog_amount,
			"underwater": underwater_amount, "cpu_ms": cpu_cost_ms}
	if lamps != null:
		s.merge(lamps.get_stats(), true)
	if weather_fx != null:
		s["rain_fx"] = weather_fx.get_stats()
	return s


## Re-reads Game.settings (shadows, env_quality, ssao, glow, reflections, ssr, dynamic_weather) and applies them.
func apply_quality() -> void:
	_read_settings()
	_apply_quality()


# =====================================================================================================
# Construction
# =====================================================================================================
func _build_environment() -> void:
	var shader := load(SKY_SHADER) as Shader
	var sky := Sky.new()
	if shader != null:
		sky_material = ShaderMaterial.new()
		sky_material.shader = shader
		sky.sky_material = sky_material
	else:
		push_error("EnvironmentSystem: sky shader missing (%s) - falling back to a procedural sky material" % SKY_SHADER)
		var psm := ProceduralSkyMaterial.new()
		sky.sky_material = psm
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0

	environment.ssao_enabled = true
	environment.ssao_radius = 1.3
	environment.ssao_intensity = SSAO_DAY_INTENSITY
	environment.ssao_power = 1.35
	environment.ssao_detail = 0.35
	environment.ssao_horizon = 0.10
	environment.ssao_sharpness = 0.98
	environment.ssao_light_affect = 0.22
	environment.ssao_ao_channel_affect = 0.0
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false

	environment.glow_enabled = true
	environment.glow_normalized = false
	environment.glow_intensity = 0.4
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.glow_hdr_threshold = 1.1
	environment.glow_hdr_scale = 1.5
	environment.glow_hdr_luminance_cap = 12.0
	for i in 7:
		environment.set_glow_level(i, 0.0)
	environment.set_glow_level(1, 0.7)
	environment.set_glow_level(2, 1.0)
	environment.set_glow_level(3, 0.5)
	environment.set_glow_level(4, 0.4)

	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.001
	environment.fog_aerial_perspective = 0.85
	environment.fog_sky_affect = 0.0
	environment.fog_sun_scatter = 0.1
	environment.fog_height = 8.0
	environment.fog_height_density = 0.0

	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.1

	camera_attributes = CameraAttributesPractical.new()
	camera_attributes.auto_exposure_enabled = false

	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	world_environment.camera_attributes = camera_attributes
	add_child(world_environment)

	# cheap SSAO: half resolution, low quality (global RenderingServer setting)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 2.0
	sun.light_specular = 0.8
	sun.light_angular_distance = 0.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.17
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_pancake_size = 24.0
	_root.add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.58, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.light_specular = 0.4
	moon.shadow_enabled = false
	moon.shadow_bias = 0.05
	moon.shadow_normal_bias = 1.6
	moon.shadow_blur = 1.4
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_split_1 = 0.18
	moon.directional_shadow_max_distance = 140.0
	moon.visible = false
	_root.add_child(moon)

	flash_light = DirectionalLight3D.new()
	flash_light.name = "LightningFlash"
	flash_light.light_color = Color(0.72, 0.80, 1.0)
	flash_light.light_energy = 0.0
	flash_light.shadow_enabled = false
	flash_light.light_specular = 0.5
	flash_light.visible = false
	_root.add_child(flash_light)


func _build_probe() -> void:
	probe = ReflectionProbe.new()
	probe.name = "SkyReflectionProbe"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(180.0, 56.0, 180.0)
	probe.blend_distance = 36.0
	probe.max_distance = 220.0
	probe.intensity = 0.9
	probe.box_projection = false
	probe.interior = false
	probe.enable_shadows = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.mesh_lod_threshold = 4.0
	probe.top_level = true
	probe.position = Vector3(0.0, 8.0, 0.0)
	_root.add_child(probe)


# =====================================================================================================
# Settings / quality
# =====================================================================================================
func _read_settings() -> void:
	var st: Dictionary = Game.settings
	_quality = clampi(int(st.get("env_quality", 2)), 0, 2)
	_shadows_on = bool(st.get("shadows", true))
	_ssao_on = bool(st.get("ssao", _quality >= 1))
	_glow_on = bool(st.get("glow", true))
	_probe_on = bool(st.get("reflections", _quality >= 1))
	_ssr_pref = bool(st.get("ssr", _quality >= 2))
	if weather != null:
		weather.auto_drift = bool(st.get("dynamic_weather", false))


func _apply_quality() -> void:
	if environment == null:
		return
	environment.ssao_enabled = _ssao_on and underwater_amount < 0.99
	environment.glow_enabled = _glow_on
	sun.shadow_enabled = _shadows_on
	match _quality:
		0:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_split_1 = 0.25
			sun.directional_shadow_max_distance = 110.0
			lamps.pool_size = 12
			weather_fx.quality = 0.5
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_split_1 = 0.08
			sun.directional_shadow_split_2 = 0.22
			sun.directional_shadow_split_3 = 0.50
			sun.directional_shadow_max_distance = 170.0
			lamps.pool_size = 20
			weather_fx.quality = 0.75
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_split_1 = 0.06
			sun.directional_shadow_split_2 = 0.17
			sun.directional_shadow_split_3 = 0.42
			sun.directional_shadow_max_distance = 220.0
			lamps.pool_size = LampManager.POOL_SIZE
			weather_fx.quality = 1.0
	probe.visible = _probe_on
	_force_refresh = true


func _poll_settings() -> void:
	var st: Dictionary = Game.settings
	if bool(st.get("shadows", true)) != _shadows_on or int(st.get("env_quality", 2)) != _quality \
			or bool(st.get("glow", true)) != _glow_on or bool(st.get("dynamic_weather", false)) != weather.auto_drift:
		apply_quality()


func _on_settings_changed() -> void:
	apply_quality()


func _on_load_completed() -> void:
	# SaveSystem restored Game.time_of_day / Game.weather: re-sync everything instantly
	if Game.weather in GC.WEATHERS:
		weather.set_state(Game.weather, true)    # emits weather_changed through state_changed
	_force_refresh = true
	_last_hour = int(floor(Game.time_of_day))


# =====================================================================================================
# Time
# =====================================================================================================
func _advance_time(delta: float) -> void:
	if _ff_remaining > 0.0:
		var step := minf(_ff_speed * delta, _ff_remaining)
		_ff_remaining -= step
		Game.time_of_day = fposmod(Game.time_of_day + step, 24.0)
		return
	if Game.time_frozen:
		return
	Game.time_of_day = fposmod(Game.time_of_day + delta * Game.time_scale / 3600.0, 24.0)


func _emit_time_events(delta: float) -> void:
	var h := int(floor(Game.time_of_day))
	if h != _last_hour:
		_last_hour = h
		Events.hour_changed.emit(h)
	if Game.time_frozen and _ff_remaining <= 0.0:
		return
	_time_event_accum += delta
	if _time_event_accum >= 1.0:
		_time_event_accum = 0.0
		Events.time_changed.emit(Game.time_of_day)


func _update_sun_moon_dirs() -> void:
	var hour := Game.time_of_day
	var ang := DayNightCycle.sun_angles(hour)
	sun_dir = DayNightCycle.dir_from_angles(ang.x, ang.y)
	sun_elevation_deg = rad_to_deg(ang.x)
	moon_dir = (-sun_dir + Vector3(0.12, 0.0, -0.08)).normalized()


# =====================================================================================================
# Palette -> engine
# =====================================================================================================
func _refresh_palette() -> void:
	var evening := DayNightCycle.is_evening(Game.time_of_day)
	palette = DayNightCycle.compose(sun_elevation_deg, evening, weather.params)
	night_amount = float(palette["night"])
	lamp_on_amount = float(palette["gloom"])

	var uw := underwater_amount
	var flash := weather.flash
	var p := palette

	# ---- sky shader ----
	if sky_material != null:
		var m := sky_material
		m.set_shader_parameter("sky_zenith", p["zenith"])
		m.set_shader_parameter("sky_mid", p["mid"])
		m.set_shader_parameter("sky_horizon", p["horizon"])
		m.set_shader_parameter("sky_ground", p["ground"])
		m.set_shader_parameter("glow_color", p["glow"])
		m.set_shader_parameter("glow_amount", float(p["glow_amount"]))
		m.set_shader_parameter("band_color", p["band"])
		m.set_shader_parameter("band_amount", float(p["band_amount"]))
		m.set_shader_parameter("haze", float(p["haze_amt"]))
		m.set_shader_parameter("overcast", float(p["overcast"]))
		m.set_shader_parameter("overcast_dark", float(p["cloud_dark"]))
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("sun_color", p["sun_color"])
		m.set_shader_parameter("sun_vis", float(p["sun_disc_vis"]))
		m.set_shader_parameter("moon_dir", moon_dir)
		var moon_vis := float(p["moon_night"]) * smoothstep(-0.02, 0.06, moon_dir.y)
		m.set_shader_parameter("moon_vis", moon_vis)
		m.set_shader_parameter("stars_amt", float(p["stars_amt"]))
		m.set_shader_parameter("cloud_cover", float(p["cloud_cover"]))
		m.set_shader_parameter("cloud_dark", float(p["cloud_dark"]))
		m.set_shader_parameter("cloud_lit", p["cloud_lit"])
		m.set_shader_parameter("cloud_shade", p["cloud_shade"])
		m.set_shader_parameter("flash", flash)
		m.set_shader_parameter("sky_time", _sky_time)
		var bolt_az := weather.bolt_azimuth
		m.set_shader_parameter("bolt", Vector4(sin(bolt_az), -cos(bolt_az), weather.bolt_seed, weather.bolt_strength))
		m.set_shader_parameter("cloud_offset", _cloud_offset)
		_update_water(p, moon_vis)

	# ---- environment ----
	var env := environment
	var ambient: float = float(p["ambient_energy"])
	ambient *= 1.0 + flash * 2.2
	ambient *= lerpf(1.0, 0.55, uw)
	env.ambient_light_energy = ambient
	# daytime fill: ~55% sky radiance + the rest a soft lavender-grey (horizon-warm at golden hour), so shadows are cool but never cobalt
	var warm_k := 1.0 - smoothstep(0.0, 16.0, sun_elevation_deg)      # 1 at sunrise / sunset, 0 with the sun high
	var day_amb: Color = Color(0.68, 0.70, 0.78).lerp(p["horizon"] as Color, 0.6 * warm_k) * DAY_AMBIENT_TINT_GAIN
	var amb_t := clampf(night_amount, 0.0, 1.0)
	env.ambient_light_color = day_amb.lerp(NIGHT_AMBIENT_COLOR, amb_t)
	env.ambient_light_sky_contribution = lerpf(DAY_SKY_CONTRIB, NIGHT_SKY_CONTRIB, amb_t)
	env.tonemap_exposure = float(p["exposure"])
	env.adjustment_saturation = lerpf(float(p["saturation"]), float(p["saturation"]) * 0.8, uw)
	env.adjustment_contrast = float(p["contrast"])
	env.glow_intensity = float(p["glow_i"]) + flash * 0.4
	env.glow_hdr_threshold = float(p["glow_th"])
	env.ssao_intensity = lerpf(SSAO_DAY_INTENSITY, SSAO_NIGHT_INTENSITY, night_amount)

	var fog_col: Color = p["fog_color"]
	var fog_density: float = float(p["fog_density"])
	var aerial: float = float(p["fog_aerial"])
	var sky_affect: float = float(p["fog_sky_affect"])
	var scatter: float = float(p["fog_sun_scatter"])
	var fog_h_den: float = float(p["fog_height_density"])
	if uw > 0.001:
		var uw_col := UW_FOG_COLOR.lerp(UW_DEEP_COLOR, _uw_depth01 * 0.85)
		fog_col = fog_col.lerp(uw_col, uw)
		fog_density = lerpf(fog_density, 0.055 + _uw_depth01 * 0.05, uw)
		aerial = lerpf(aerial, 0.0, uw)
		sky_affect = lerpf(sky_affect, 1.0, uw)
		scatter = lerpf(scatter, 0.0, uw)
		fog_h_den = lerpf(fog_h_den, 0.0, uw)
	env.fog_light_color = fog_col
	env.fog_density = fog_density
	env.fog_aerial_perspective = aerial
	env.fog_sky_affect = sky_affect
	env.fog_sun_scatter = scatter
	env.fog_height = float(p["fog_height"])
	env.fog_height_density = fog_h_den
	env.ssao_enabled = _ssao_on and uw < 0.9

	# SSR only while the ground is wet (puddle reflections), if the player opted in
	var want_ssr := _ssr_pref and weather.wetness > 0.25 and _quality >= 2 and uw < 0.5
	if env.ssr_enabled != want_ssr:
		env.ssr_enabled = want_ssr
		if want_ssr:
			env.ssr_max_steps = 32
			env.ssr_fade_in = 0.1
			env.ssr_fade_out = 2.0
			env.ssr_depth_tolerance = 0.25

	# ---- lights ----
	var sun_e: float = float(p["sun_energy"]) * lerpf(1.0, 0.7, uw)
	if uw > 0.001:
		# gentle caustic-like breathing of the light under the surface
		var t := _sky_time
		sun_e *= 1.0 + uw * 0.22 * (sin(t * 2.1) * 0.5 + sin(t * 3.7 + 1.3) * 0.3 + sin(t * 5.3) * 0.2)
	sun.light_energy = sun_e
	sun.light_color = (p["sun_color"] as Color).lerp(Color(0.55, 0.95, 1.0), uw * 0.7)
	sun.visible = sun_e > 0.003
	sun.shadow_enabled = _shadows_on and sun_e > 0.02
	sun.light_angular_distance = lerpf(0.3, 2.2, float(p["overcast"]))

	var moon_e: float = 0.9 * float(p["moon_night"]) * smoothstep(0.0, 0.3, moon_dir.y) * (1.0 - float(p["overcast"]) * 0.55)
	moon_e *= lerpf(1.0, 0.5, uw)
	moon.light_energy = moon_e
	moon.visible = moon_e > 0.003
	moon.shadow_enabled = _shadows_on and moon_e > 0.04 and sun_e < 0.05

	if flash > 0.002:
		flash_light.visible = true
		flash_light.light_energy = flash * 3.2
		var az := weather.bolt_azimuth
		var from := Vector3(sin(az), 0.0, -cos(az))
		var to_dir := -(from * 0.8 + Vector3.UP * 0.6).normalized()
		flash_light.basis = Basis.looking_at(to_dir, Vector3.UP)
	elif flash_light.visible:
		flash_light.visible = false
		flash_light.light_energy = 0.0


## Sun / moon glitter and the sky tint for the sea shader (WaterBuilder's shared material).
func _update_water(p: Dictionary, moon_vis: float) -> void:
	var wm := WaterBuilder.material
	if wm == null:
		return
	wm.set_shader_parameter("sun_dir", sun_dir)
	wm.set_shader_parameter("sun_tint", p["sun_color"])
	wm.set_shader_parameter("moon_dir", moon_dir)
	wm.set_shader_parameter("moon_vis", moon_vis)
	wm.set_shader_parameter("sky_tint", (p["horizon"] as Color).lerp(p["mid"], 0.35))


func _update_light_transforms() -> void:
	sun.basis = _light_basis(-sun_dir)
	moon.basis = _light_basis(-moon_dir)


func _light_basis(travel_dir: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(travel_dir.dot(up)) > 0.985:
		up = Vector3.FORWARD
	return Basis.looking_at(travel_dir, up)


func _publish_game_state() -> void:
	Game.weather = weather.state
	Game.rain_intensity = weather.rain
	Game.wetness = weather.wetness
	Game.fog_amount = weather.fog_amount
	Game.wind = weather.wind
	_set_global_cached(&"gta_night", night_amount)
	_set_global_cached(&"gta_sun_energy", clampf(float(palette.get("sun_energy", 1.0)) / 1.7, 0.0, 1.0))
	_set_global_cached(&"gta_wetness", weather.wetness)
	_set_global_cached(&"gta_rain", weather.rain)
	_set_global_cached(&"gta_fog", weather.fog_amount)
	var gt := Game.time_of_day * 3600.0
	if absf(gt - _gta_time_last) > 0.5:
		_gta_time_last = gt
		Game.set_global(&"gta_time", gt)


func _set_global_cached(gname: StringName, value: float) -> void:
	if absf(float(_globals_cache.get(gname, -999.0)) - value) > 0.0005:
		_globals_cache[gname] = value
		Game.set_global(gname, value)


# =====================================================================================================
# Camera, underwater, reflection probe
# =====================================================================================================
func _get_camera() -> Camera3D:
	var vp := get_viewport()
	if vp != null:
		var c := vp.get_camera_3d()
		if c != null:
			return c
	var gc: Camera3D = Game.gameplay_camera
	if is_instance_valid(gc):
		return gc
	return null


func _viewport_aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.7778
	var s := vp.get_visible_rect().size
	return s.x / maxf(s.y, 1.0)


func _update_underwater(delta: float, cam: Camera3D) -> void:
	var target := 0.0
	var depth := 0.0
	if _uw_override >= 0:
		target = float(_uw_override)
		if cam != null:
			depth = maxf(GC.WATER_LEVEL - cam.global_position.y, 0.0)
	elif cam != null:
		var cp := cam.global_position
		if cp.y < GC.WATER_LEVEL - 0.02 and WorldLayout.is_water(cp.x, cp.z):
			target = 1.0
			depth = GC.WATER_LEVEL - cp.y
		else:
			var pl = Game.player
			if is_instance_valid(pl) and pl.get("is_underwater") == true and cp.y < GC.WATER_LEVEL + 0.5:
				target = 1.0
				depth = maxf(GC.WATER_LEVEL - cp.y, 0.0)
	_uw_depth01 = lerpf(_uw_depth01, clampf(depth / 24.0, 0.0, 1.0), minf(delta * 3.0, 1.0))
	var rate := 10.0 if target > underwater_amount else 4.5
	underwater_amount = Util.damp(underwater_amount, target, rate, delta)
	if absf(underwater_amount - target) < 0.004:
		underwater_amount = target
	var now := underwater_amount > 0.5
	if now != _uw_state:
		_uw_state = now
		underwater_changed.emit(now)


func _update_probe(delta: float, cam: Camera3D) -> void:
	if not _probe_on or probe == null:
		return
	_probe_timer += delta
	var focus: Vector3
	var pl = Game.player
	if is_instance_valid(pl):
		focus = pl.global_position
	elif cam != null:
		focus = cam.global_position
	else:
		return
	var moved := Vector2(focus.x - _probe_last_pos.x, focus.z - _probe_last_pos.z).length()
	if (moved > 60.0 and _probe_timer >= 4.0) or _probe_timer >= _probe_refresh_s or _probe_last_pos.x > 1e8:
		_probe_timer = 0.0
		_probe_last_pos = focus
		probe.global_position = Vector3(focus.x, maxf(focus.y, 0.0) + 8.0, focus.z)
		# re-capture once at the new spot (UPDATE_ONCE re-renders when the probe is dirtied by the move)


# =====================================================================================================
# Lightning / thunder / rain audio
# =====================================================================================================
func _on_lightning(distance: float, azimuth: float) -> void:
	lightning_struck.emit(distance, azimuth)
	_pending_thunder.append([minf(distance / 343.0, 9.0), distance])


func _update_thunder(delta: float) -> void:
	if _pending_thunder.is_empty():
		return
	var i := _pending_thunder.size() - 1
	while i >= 0:
		var e: Array = _pending_thunder[i]
		e[0] = float(e[0]) - delta
		if float(e[0]) <= 0.0:
			_play_thunder(float(e[1]))
			_pending_thunder.remove_at(i)
		i -= 1


func _play_thunder(distance: float) -> void:
	var k := clampf(distance / 2600.0, 0.0, 1.0)
	var db := lerpf(-1.0, -17.0, k)
	if Sfx.has_sound(&"thunder"):
		Sfx.play_2d(&"thunder", db, lerpf(1.0, 0.8, k))
	elif Sfx.has_sound(&"explosion_big"):
		if not _fallback_thunder_warned:
			_fallback_thunder_warned = true
			push_warning("EnvironmentSystem: Sfx 'thunder' missing - using a pitched-down 'explosion_big' as fallback")
		Sfx.play_2d(&"explosion_big", db - 9.0, 0.38)


func _pick_rain_sound() -> void:
	_rain_sound_id = &""
	for id in [&"rain_loop", &"ambient_rain", &"rain"]:
		if Sfx.has_sound(id):
			_rain_sound_id = id
			break


func _update_rain_audio(delta: float) -> void:
	# Optional: only used when the audio bank provides a rain loop and AudioSystem does not run its own weather ambience.
	_rain_audio_timer -= delta
	if _rain_audio_timer > 0.0:
		return
	_rain_audio_timer = 0.25
	if _rain_sound_id == &"":
		if _age < 30.0 or int(_age) % 10 == 0:
			_pick_rain_sound()
		return
	var audio = Game.sys(&"audio")
	if audio != null and audio.has_method("handles_weather_audio") and audio.handles_weather_audio():
		return
	var level := weather.rain * (1.0 - underwater_amount)
	if level > 0.02:
		if _rain_player == null:
			_rain_player = AudioStreamPlayer.new()
			_rain_player.name = "RainLoop"
			_rain_player.stream = Sfx.get_stream(_rain_sound_id)
			add_child(_rain_player)
			_rain_player.finished.connect(_on_rain_finished)
		_rain_player.volume_db = lerpf(-30.0, -8.0, clampf(level, 0.0, 1.0))
		if not _rain_player.playing and _rain_player.stream != null:
			_rain_player.play()
	elif _rain_player != null and _rain_player.playing:
		_rain_player.stop()


func _on_rain_finished() -> void:
	if weather.rain * (1.0 - underwater_amount) > 0.02 and _rain_player != null:
		_rain_player.play()
