class_name ActivityMarker
extends Node3D
## Subtle start marker of an activity point: a flat neon ring on the ground, a small spinning ring above it and a faint additive pillar.
## Not a "mission marker": it only exists where the player can deliberately interact, and it is hidden beyond SHOW_DIST (fades from FADE_DIST).

const SHOW_DIST := 60.0
const FADE_DIST := 42.0
const PILLAR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float strength = 0.5;
uniform float height = 4.0;
varying float hk;
void vertex() { hk = clamp(VERTEX.y / height + 0.5, 0.0, 1.0); }
void fragment() {
	float a = pow(1.0 - hk, 1.7) * strength;
	ALBEDO = col.rgb;
	ALPHA = a;
}
"""

static var _pillar_shader: Shader = null

var color: Color = GC.COL_ACCENT
var radius := 1.5
var fade := 0.0
var ring_a: MeshInstance3D
var ring_b: MeshInstance3D
var pillar: MeshInstance3D
var _mat_ring: StandardMaterial3D
var _mat_pillar: ShaderMaterial
var _t := 0.0


func setup(col: Color, r: float = 1.5, tall: float = 4.0) -> void:
	color = col
	radius = r
	_mat_ring = StandardMaterial3D.new()
	_mat_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_ring.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ring.albedo_color = Color(col.r, col.g, col.b, 0.9)
	_mat_ring.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_ring.no_depth_test = false
	if _pillar_shader == null:
		_pillar_shader = Shader.new()
		_pillar_shader.code = PILLAR_SHADER
	_mat_pillar = ShaderMaterial.new()
	_mat_pillar.shader = _pillar_shader
	_mat_pillar.set_shader_parameter("col", col)
	_mat_pillar.set_shader_parameter("height", tall)
	_mat_pillar.set_shader_parameter("strength", 0.38)
	ring_a = _torus(r, 0.07)
	ring_a.position = Vector3(0, 0.12, 0)
	add_child(ring_a)
	ring_b = _torus(r * 0.62, 0.05)
	ring_b.position = Vector3(0, 1.0, 0)
	add_child(ring_b)
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.92
	cyl.bottom_radius = r * 0.92
	cyl.height = tall
	cyl.radial_segments = 20
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	pillar = MeshInstance3D.new()
	pillar.mesh = cyl
	pillar.material_override = _mat_pillar
	pillar.position = Vector3(0, tall * 0.5, 0)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pillar)
	visible = false
	set_process(false)


func _torus(r: float, thick: float) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(r - thick, 0.05)
	tm.outer_radius = r + thick
	tm.rings = 28
	tm.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = _mat_ring
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Called by ActivitySystem (about 8 Hz) with the horizontal distance to the player.
func update_distance(d: float) -> void:
	var want := d < SHOW_DIST
	if want != visible:
		visible = want
		set_process(want)
	if want:
		fade = 1.0 - smoothstep(FADE_DIST, SHOW_DIST, d)
		if _mat_ring != null:
			_mat_ring.albedo_color = Color(color.r, color.g, color.b, 0.9 * fade)
		if _mat_pillar != null:
			_mat_pillar.set_shader_parameter("strength", 0.38 * fade)


func set_enabled(on: bool) -> void:
	if not on:
		visible = false
		set_process(false)


func _process(delta: float) -> void:
	_t += delta
	if ring_b != null:
		ring_b.rotation.y = _t * 1.4
		ring_b.position.y = 1.0 + sin(_t * 2.0) * 0.12
		ring_b.rotation.x = sin(_t * 1.1) * 0.25
	if ring_a != null:
		var s := 1.0 + sin(_t * 3.0) * 0.035
		ring_a.scale = Vector3(s, 1.0, s)
