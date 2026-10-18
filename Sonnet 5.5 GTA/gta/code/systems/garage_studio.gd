class_name GarageStudio
extends Node3D
## The temporary photo-studio the customization garage moves the car into: a closed dark room (so the world sun / sky cannot
## interfere, ceiling + walls also stop the directional shadow) with a turntable, neon strips, a key spot light, rim lights and an
## Environment override for the garage camera (own sky for paint reflections, glow for the neon). Built per session, freed after it.
## Placed far above the garage (see GarageSession.STUDIO_LIFT) - nothing else lives there, and the tree is paused while it is open.

const ROOM_W := 26.0
const ROOM_D := 26.0
const ROOM_H := 9.0
const REFLECT_LAYER := 1 << 19                  # visual layer 20: studio meshes only (the reflection probe captures just these)
const STUDIO_LAYERS := 1 | (1 << 19)

var accent_a := GC.COL_ACCENT
var accent_b := GC.COL_ACCENT2
var rim_a: SpotLight3D
var rim_b: SpotLight3D
var key: SpotLight3D
var fill: OmniLight3D
var neon_mats: Array[StandardMaterial3D] = []
var title_text := "FOUNDRY GARAGE"
var _t := 0.0


func build(title: String = "FOUNDRY GARAGE") -> void:
	title_text = title
	name = "GarageStudio"
	# ---- room shell (closed boxes: inner faces visible, outer faces cast the shadow that blocks the sun)
	var wall := _std(Color(0.10, 0.115, 0.15), 0.85, 0.05)
	var floor_m := _std(Color(0.05, 0.056, 0.07), 0.34, 0.55)
	_slab(Vector3(0, -0.25, 0), Vector3(ROOM_W, 0.5, ROOM_D), floor_m)
	_slab(Vector3(0, ROOM_H + 0.25, 0), Vector3(ROOM_W + 1, 0.5, ROOM_D + 1), wall)
	_slab(Vector3(0, ROOM_H * 0.5, -ROOM_D * 0.5 - 0.25), Vector3(ROOM_W + 1, ROOM_H, 0.5), wall)
	_slab(Vector3(0, ROOM_H * 0.5, ROOM_D * 0.5 + 0.25), Vector3(ROOM_W + 1, ROOM_H, 0.5), wall)
	_slab(Vector3(-ROOM_W * 0.5 - 0.25, ROOM_H * 0.5, 0), Vector3(0.5, ROOM_H, ROOM_D), wall)
	_slab(Vector3(ROOM_W * 0.5 + 0.25, ROOM_H * 0.5, 0), Vector3(0.5, ROOM_H, ROOM_D), wall)
	# ---- turntable
	var plat := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.1
	cm.bottom_radius = 4.2
	cm.height = 0.14
	cm.radial_segments = 48
	plat.mesh = cm
	plat.material_override = _std(Color(0.07, 0.08, 0.1), 0.2, 0.7)
	plat.layers = STUDIO_LAYERS
	plat.position = Vector3(0, 0.07, 0)
	add_child(plat)
	_ring(4.2, 0.05, accent_a, 0.15)
	_ring(5.6, 0.035, accent_b, 0.02)
	_ring(3.2, 0.02, Color(1, 1, 1), 0.145, 0.6)
	# ---- neon strips on the walls
	for i in 3:
		var y := 1.2 + float(i) * 2.3
		var col := accent_a if i % 2 == 0 else accent_b
		_strip(Vector3(0, y, -ROOM_D * 0.5 + 0.02), Vector3(ROOM_W - 3.0, 0.12, 0.05), col, 2.2)
		_strip(Vector3(-ROOM_W * 0.5 + 0.02, y, 0), Vector3(0.05, 0.12, ROOM_D - 3.0), col, 1.8)
		_strip(Vector3(ROOM_W * 0.5 - 0.02, y, 0), Vector3(0.05, 0.12, ROOM_D - 3.0), col, 1.8)
		_strip(Vector3(0, y, ROOM_D * 0.5 - 0.02), Vector3(ROOM_W - 3.0, 0.12, 0.05), col, 1.8)
	# ceiling light panels + side softboxes (they show up as long highlights in the paint through the reflection probe)
	for sx in [-6.5, 6.5]:
		_strip(Vector3(sx, ROOM_H - 0.02, 0), Vector3(1.2, 0.04, 14.0), Color(0.9, 0.95, 1.0), 1.5)
	_strip(Vector3(0, ROOM_H - 0.02, 0), Vector3(1.0, 0.04, 14.0), Color(0.9, 0.95, 1.0), 1.5, true)      # centre panel: reflections only (no floor glare)
	for sx2 in [-1.0, 1.0]:
		_strip(Vector3(sx2 * (ROOM_W * 0.5 - 0.5), 2.6, 0.0), Vector3(0.08, 2.4, 11.0), Color(0.92, 0.96, 1.0), 2.2, true)
	_strip(Vector3(0, 3.4, ROOM_D * 0.5 - 0.5), Vector3(9.0, 1.6, 0.08), Color(1.0, 0.95, 0.9), 2.0, true)
	_strip(Vector3(0, 3.4, -ROOM_D * 0.5 + 0.5), Vector3(9.0, 1.6, 0.08), Color(1.0, 0.95, 0.9), 1.6, true)
	# title sign on the back wall
	var lbl := Label3D.new()
	lbl.text = title_text
	lbl.font_size = 140
	lbl.pixel_size = 0.012
	lbl.modulate = accent_a
	lbl.outline_modulate = Color(0.0, 0.2, 0.3)
	lbl.outline_size = 10
	lbl.shaded = false
	lbl.double_sided = false
	lbl.no_depth_test = false
	lbl.layers = STUDIO_LAYERS
	lbl.position = Vector3(0, 5.6, -ROOM_D * 0.5 + 0.06)
	add_child(lbl)
	# ---- lights
	key = SpotLight3D.new()
	key.name = "KeyLight"
	key.position = Vector3(4.5, 7.2, -7.0)
	key.spot_range = 26.0
	key.spot_angle = 34.0
	key.spot_angle_attenuation = 0.8
	key.light_energy = 16.0
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = true
	key.shadow_blur = 1.6
	add_child(key)
	key.look_at_from_position(key.position, Vector3(0, 0.6, 0), Vector3.UP)
	fill = OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(-6.0, 4.5, -4.0)
	fill.omni_range = 18.0
	fill.light_energy = 2.6
	fill.light_color = Color(0.82, 0.9, 1.0)
	add_child(fill)
	var fill2 := OmniLight3D.new()
	fill2.name = "FillLightB"
	fill2.position = Vector3(6.5, 3.5, 5.5)
	fill2.omni_range = 16.0
	fill2.light_energy = 1.8
	fill2.light_color = Color(1.0, 0.9, 0.85)
	add_child(fill2)
	# one-shot reflection capture of the room: paint / chrome / glass reflect the neon + softboxes. Only studio meshes (layer 20) are
	# captured, so the car itself never appears in its own reflections.
	var probe := ReflectionProbe.new()
	probe.name = "StudioProbe"
	probe.position = Vector3(0, 2.2, 0)
	probe.size = Vector3(ROOM_W - 0.2, ROOM_H - 0.2, ROOM_D - 0.2)
	probe.interior = true
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = REFLECT_LAYER
	probe.intensity = 1.0
	probe.enable_shadows = false
	add_child(probe)
	rim_a = _rim(Vector3(-5.5, 3.2, 7.0), accent_a)
	rim_b = _rim(Vector3(5.5, 3.2, 7.0), accent_b)
	var front_rim := OmniLight3D.new()
	front_rim.name = "FloorBounce"
	front_rim.position = Vector3(0, 0.5, 0)
	front_rim.omni_range = 8.0
	front_rim.light_energy = 0.8
	front_rim.light_color = Color(0.55, 0.7, 1.0)
	front_rim.shadow_enabled = false
	add_child(front_rim)


func _rim(pos: Vector3, col: Color) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.position = pos
	s.spot_range = 20.0
	s.spot_angle = 38.0
	s.light_energy = 7.5
	s.light_color = col
	s.shadow_enabled = false
	add_child(s)
	s.look_at_from_position(pos, Vector3(0, 0.8, 0), Vector3.UP)
	return s


func _std(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _slab(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.layers = STUDIO_LAYERS
	mi.position = pos
	add_child(mi)


## Emissive box. `reflect_only` = visible only to the reflection probe (layer 20), never to the garage camera: a softbox for the paint highlights.
func _strip(pos: Vector3, size: Vector3, col: Color, energy: float, reflect_only: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.layers = REFLECT_LAYER if reflect_only else STUDIO_LAYERS
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if not reflect_only:
		neon_mats.append(m)


func _ring(radius: float, thick: float, col: Color, y: float, energy: float = 2.5) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - thick
	tm.outer_radius = radius + thick
	tm.rings = 48
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.5 if energy >= 1.0 else 2.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.scale = Vector3(1, 0.35, 1)
	mi.layers = STUDIO_LAYERS
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	neon_mats.append(m)


## Environment used by the garage camera instead of the world one.
func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.018)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.07, 0.09, 0.15)
	sm.sky_horizon_color = Color(0.62, 0.68, 0.82)
	sm.ground_horizon_color = Color(0.32, 0.36, 0.46)
	sm.ground_bottom_color = Color(0.03, 0.035, 0.05)
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	return env


func _process(dt: float) -> void:
	_t += dt
	# gentle neon "breathing"
	var k := 0.88 + 0.12 * sin(_t * 1.6)
	for i in neon_mats.size():
		if i % 2 == 0:
			neon_mats[i].emission_energy_multiplier = lerpf(1.8, 2.8, k)
