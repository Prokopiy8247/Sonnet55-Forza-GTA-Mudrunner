class_name WeatherFx
extends Node3D
## Rain presentation that follows the camera (all GPU, zero cost when it is dry):
##  - RainStreaks: GPUParticles3D box around the camera, camera-facing ribbons aligned to the fall direction
##  - Splashes: flat ring/droplet sprites on the ground below the camera
##  - RainSheet: open cylinder with scrolling streak noise = distant rain curtain
## Rain is thinned out when the camera is under a roof and hidden while underwater.

const STREAK_SHADER := "res://gta/generated/shaders/weather_rain_streak.gdshader"
const SPLASH_SHADER := "res://gta/generated/shaders/weather_rain_splash.gdshader"
const SHEET_SHADER := "res://gta/generated/shaders/weather_rain_sheet.gdshader"

const STREAK_AMOUNT := 4600
const SPLASH_AMOUNT := 1300
const BOX_HALF := 20.0
const SPLASH_HALF := 11.0

var quality := 1.0                   # 0.4 .. 1.0 scales particle counts (EnvironmentSystem sets it from the settings)
var light_scale := 1.0               # 0.3 .. 1.0 brightness of the (unshaded) rain, lowered at night so it is not self-lit
var rain_visible := 0.0              # last applied rain strength (0..1) after shelter / underwater scaling
var ground_y := 0.0
var sheltered := 0.0                 # 0 open sky .. 1 roof overhead

var _streaks: GPUParticles3D
var _splashes: GPUParticles3D
var _sheet: MeshInstance3D
var _streak_mat: ShaderMaterial
var _splash_mat: ShaderMaterial
var _sheet_mat: ShaderMaterial
var _streak_proc: ParticleProcessMaterial
var _ray_timer := 0.0
var _shelter_target := 0.0
var _prev_cam := Vector3.ZERO
var _cam_vel := Vector3.ZERO
var _have_prev := false
var _last_dir := Vector3.DOWN
var _ready_ok := false


func setup() -> void:
	top_level = true
	name = "WeatherFx"
	_streak_mat = _make_mat(STREAK_SHADER)
	_splash_mat = _make_mat(SPLASH_SHADER)
	_sheet_mat = _make_mat(SHEET_SHADER)
	if _streak_mat == null or _splash_mat == null or _sheet_mat == null:
		push_warning("WeatherFx: weather shaders missing - rain will not be drawn")
		return

	# streaks
	_streaks = GPUParticles3D.new()
	_streaks.name = "RainStreaks"
	_streaks.amount = STREAK_AMOUNT
	_streaks.lifetime = 1.15
	_streaks.local_coords = false
	_streaks.fixed_fps = 0
	_streaks.interpolate = false
	_streaks.visibility_aabb = AABB(Vector3(-48, -36, -48), Vector3(96, 44, 96))
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streaks.emitting = false
	_streak_proc = ParticleProcessMaterial.new()
	_streak_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_streak_proc.emission_box_extents = Vector3(BOX_HALF, 0.1, BOX_HALF)
	_streak_proc.direction = Vector3.DOWN
	_streak_proc.spread = 0.0
	_streak_proc.initial_velocity_min = 21.0
	_streak_proc.initial_velocity_max = 27.0
	_streak_proc.gravity = Vector3.ZERO
	_streak_proc.particle_flag_align_y = true
	_streak_proc.scale_min = 0.55
	_streak_proc.scale_max = 1.05
	_streaks.process_material = _streak_proc
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_streaks.draw_pass_1 = q
	_streaks.material_override = _streak_mat
	add_child(_streaks)

	# splashes
	_splashes = GPUParticles3D.new()
	_splashes.name = "RainSplashes"
	_splashes.amount = SPLASH_AMOUNT
	_splashes.lifetime = 0.36
	_splashes.local_coords = false
	_splashes.fixed_fps = 0
	_splashes.interpolate = false
	_splashes.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 6, 40))
	_splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splashes.emitting = false
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(SPLASH_HALF, 0.01, SPLASH_HALF)
	sp.direction = Vector3.UP
	sp.spread = 0.0
	sp.initial_velocity_min = 0.0
	sp.initial_velocity_max = 0.0
	sp.gravity = Vector3.ZERO
	sp.angle_min = 0.0
	sp.angle_max = 360.0
	sp.scale_min = 0.10
	sp.scale_max = 0.24
	_splashes.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(1, 1)
	sq.orientation = PlaneMesh.FACE_Y
	_splashes.draw_pass_1 = sq
	_splashes.material_override = _splash_mat
	add_child(_splashes)

	# rain curtain
	_sheet = MeshInstance3D.new()
	_sheet.name = "RainSheet"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 34.0
	cyl.bottom_radius = 34.0
	cyl.height = 46.0
	cyl.radial_segments = 28
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_sheet.mesh = cyl
	_sheet.material_override = _sheet_mat
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.extra_cull_margin = 16384.0
	_sheet.visible = false
	add_child(_sheet)
	visible = false
	_ready_ok = true


func _make_mat(path: String) -> ShaderMaterial:
	var sh := load(path) as Shader
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## rain01: current rain intensity; wind: world wind vector (m/s); underwater01: 0..1; cam: active camera (may be null)
func update_fx(delta: float, cam: Camera3D, rain01: float, wind: Vector3, underwater01: float, storm01: float) -> void:
	if not _ready_ok:
		return
	var active := rain01 > 0.015 and underwater01 < 0.6 and cam != null
	if not active:
		if _streaks.emitting or visible:
			_streaks.emitting = false
			_splashes.emitting = false
			_sheet.visible = false
			rain_visible = 0.0
			# keep node visible for a moment so leftover particles fade, then hide
			_hide_timer_tick(delta)
		else:
			rain_visible = 0.0
		return
	visible = true
	_hide_left = 1.6
	var cam_pos := cam.global_position
	if _have_prev:
		_cam_vel = _cam_vel.lerp((cam_pos - _prev_cam) / maxf(delta, 0.0001), minf(delta * 4.0, 1.0))
	_prev_cam = cam_pos
	_have_prev = true

	_ray_timer -= delta
	if _ray_timer <= 0.0:
		_ray_timer = 0.35
		_probe_environment(cam_pos)
	sheltered = lerpf(sheltered, _shelter_target, minf(delta * 3.0, 1.0))

	var open := 1.0 - sheltered * 0.9
	var vis := clampf(pow(rain01, 0.7), 0.0, 1.0) * open
	rain_visible = vis
	var lead := Vector3(_cam_vel.x, 0.0, _cam_vel.z) * 0.45
	lead = lead.limit_length(11.0)
	global_position = Vector3(cam_pos.x, cam_pos.y + 14.0, cam_pos.z) + lead
	global_rotation = Vector3.ZERO

	# slant from wind
	var slant := Vector3(wind.x, 0.0, wind.z) * 0.055
	var dir := (Vector3.DOWN + slant).normalized()
	if dir.distance_to(_last_dir) > 0.01:
		_last_dir = dir
		_streak_proc.direction = dir
	_streaks.emitting = vis > 0.02
	_streaks.amount_ratio = clampf(vis * quality, 0.0, 1.0)
	_streak_mat.set_shader_parameter("intensity", clampf(0.55 + rain01 * 0.45, 0.0, 1.0))
	_streak_mat.set_shader_parameter("width", 0.016 + 0.007 * storm01)
	_streak_mat.set_shader_parameter("brightness", light_scale)
	_splash_mat.set_shader_parameter("brightness", light_scale)
	_sheet_mat.set_shader_parameter("brightness", light_scale)

	# splashes lie on the ground below the camera
	var sp_vis := vis * (1.0 - sheltered * 0.7)
	_splashes.global_position = Vector3(cam_pos.x + lead.x * 0.5, ground_y + 0.04, cam_pos.z + lead.z * 0.5)
	_splashes.global_rotation = Vector3.ZERO
	_splashes.emitting = sp_vis > 0.03
	_splashes.amount_ratio = clampf(sp_vis * quality, 0.0, 1.0)

	# curtain
	_sheet.visible = quality > 0.55 and vis > 0.05
	if _sheet.visible:
		_sheet.global_position = Vector3(cam_pos.x, cam_pos.y + 8.0, cam_pos.z)
		_sheet.global_rotation = Vector3.ZERO
		_sheet_mat.set_shader_parameter("intensity", clampf(vis * 0.9 * (1.0 - sheltered * 0.6), 0.0, 1.0))
		_sheet_mat.set_shader_parameter("slant", Vector2(slant.x, slant.z))


var _hide_left := 0.0


func _hide_timer_tick(delta: float) -> void:
	_hide_left -= delta
	if _hide_left <= 0.0:
		visible = false


func _probe_environment(cam_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	# ground below
	var from := cam_pos + Vector3(0.0, 1.0, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -80.0, 0.0), GC.L_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		ground_y = GC.WATER_LEVEL if WorldLayout.is_water(cam_pos.x, cam_pos.z) else WorldLayout.terrain_height(cam_pos.x, cam_pos.z)
	else:
		ground_y = (hit["position"] as Vector3).y
	# roof above
	var up_from := cam_pos + Vector3(0.0, 0.6, 0.0)
	var uq := PhysicsRayQueryParameters3D.create(up_from, up_from + Vector3(0.0, 28.0, 0.0), GC.L_WORLD)
	var uhit := space.intersect_ray(uq)
	_shelter_target = 1.0 if not uhit.is_empty() else 0.0


func get_stats() -> Dictionary:
	return {
		"streaks_emitting": _streaks != null and _streaks.emitting,
		"streak_ratio": _streaks.amount_ratio if _streaks != null else 0.0,
		"splash_ratio": _splashes.amount_ratio if _splashes != null else 0.0,
		"sheet": _sheet != null and _sheet.visible,
		"sheltered": sheltered,
		"ground_y": ground_y,
	}
