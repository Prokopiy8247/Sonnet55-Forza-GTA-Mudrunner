class_name TaxiMarker
extends Node3D
## World marker for the taxi pickup / drop-off spot: a faint amber light pillar with a pulsing ground ring (no gameplay, purely a cue).
## Fades with distance (visible within `visibility_range`), pulses at 0.8 Hz.

var _pillar: MeshInstance3D
var _ring: MeshInstance3D
var _mat_pillar: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _t := 0.0
var color := Color(1.0, 0.76, 0.22)


func _init() -> void:
	name = "TaxiMarker"
	_mat_pillar = _make_mat(0.16)
	_mat_ring = _make_mat(0.5)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.45
	cyl.height = 24.0
	cyl.radial_segments = 12
	cyl.rings = 1
	_pillar = MeshInstance3D.new()
	_pillar.mesh = cyl
	_pillar.material_override = _mat_pillar
	_pillar.position = Vector3(0, 12.0, 0)
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)
	var torus := TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 1.8
	torus.rings = 20
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _mat_ring
	_ring.position = Vector3(0, 0.12, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _make_mat(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.disable_receive_shadows = true
	return m


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	var pulse := 0.5 + 0.5 * sin(_t * TAU * 0.8)
	_mat_pillar.albedo_color = Color(color.r, color.g, color.b, 0.10 + 0.10 * pulse)
	_mat_ring.albedo_color = Color(color.r, color.g, color.b, 0.35 + 0.35 * pulse)
	var s := 1.0 + 0.12 * pulse
	_ring.scale = Vector3(s, 1.0, s)
