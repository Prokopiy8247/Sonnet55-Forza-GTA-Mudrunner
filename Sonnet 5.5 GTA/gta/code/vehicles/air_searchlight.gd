class_name AirSearchlight
extends Node3D
## Helicopter searchlight (Air&Sea agent): a SpotLight3D, a faceted volumetric cone (additive, fades with length and at the rim)
## and a lit circle on whatever the beam hits (ground / building / car / water). Used by HeliVehicle (player: key L, beam follows the
## camera) and PoliceHeliAI (sweeps / tracks the suspect). The node sits under the helicopter at the lamp position; the beam direction
## is slewed in WORLD space and written as a LOCAL basis so physics interpolation keeps the beam glued to the airframe.
##   var sl := AirSearchlight.create(heli)          # null when the model has no `Searchlight` node
##   sl.set_enabled(true); sl.aim_at(point)         # every frame (or aim_dir(dir)); the beam turns at `slew_deg` deg/s
##   sl.covers(point)                               # is the point inside the lit cone (angle test)
##   sl.hit_pos / hit_normal / hit_dist             # where the beam ends (10 Hz ray)

var heli: VehicleBase = null
var lamp: Node3D = null                      # the model's `Searchlight` housing (it is rotated to point along the beam)
var spot: SpotLight3D = null
var cone: MeshInstance3D = null
var disc: MeshInstance3D = null
var enabled := false
var external_control := false                # true: PoliceHeliAI drives it, HeliVehicle only calls update()
var half_angle_deg := 6.5
var range_m := 200.0
var slew_deg := 48.0
var energy := 16.0
var shadows := false

var dir := Vector3(0, -0.55, -0.83).normalized()      # current world beam direction
var want_dir := Vector3(0, -0.55, -0.83).normalized()
var hit_pos := Vector3.ZERO
var hit_normal := Vector3.UP
var hit_dist := 90.0
var hit_node: Object = null
var fade := 0.0                               # 0..1 beam brightness (fades in / out)

var _local_pos := Vector3.ZERO
var _lamp_rest := Basis.IDENTITY
var _cone_mat: ShaderMaterial = null
var _disc_mat: ShaderMaterial = null
var _ray_t := 0.0
var _query: PhysicsRayQueryParameters3D = null
var _built := false
var _smoothed_dist := 90.0
var _cone_vis := 1.0                          # 0..1 visibility of the volumetric cone (fades out when the camera is inside / near it)

## The camera may sit INSIDE the cone (the beam ends on the player) or the helicopter may hover right above it: the additive faces
## then veil the whole screen. The cone fades out inside its volume (+ margin) and when the camera is closer than NEAR_HELI_FADE_END (75 m) to the lamp.
const NEAR_HELI_FADE_START := 40.0
const NEAR_HELI_FADE_END := 75.0
const INSIDE_MARGIN := 7.0

const CONE_SHADER := "
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint = vec3(1.0, 0.96, 0.82);
uniform float strength = 0.2;
void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float a = mix(1.0, 0.16, along) * smoothstep(0.0, 0.05, along) * (1.0 - smoothstep(0.82, 1.0, along));
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	a *= smoothstep(0.0, 0.9, f);
	a *= smoothstep(4.0, 30.0, length(VERTEX));
	ALBEDO = tint * a * strength;
	ALPHA = 1.0;
}
"

const DISC_SHADER := "
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint = vec3(1.0, 0.95, 0.8);
uniform float strength = 0.5;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = (1.0 - smoothstep(0.35, 1.0, r)) * 0.85 + (1.0 - smoothstep(0.0, 0.45, r)) * 0.4;
	ALBEDO = tint * a * strength;
	ALPHA = 1.0;
}
"


static func create(vehicle: VehicleBase) -> AirSearchlight:
	if vehicle == null or vehicle.model == null:
		return null
	var lamp_node := vehicle.model.find_child("Searchlight", true, false) as Node3D
	if lamp_node == null:
		return null
	var sl := AirSearchlight.new()
	sl.name = "AirSearchlight"
	sl.heli = vehicle
	sl.lamp = lamp_node
	vehicle.add_child(sl)
	sl._build()
	return sl


func _build() -> void:
	if _built:
		return
	_built = true
	_local_pos = Util._rel_transform(heli, lamp).origin
	_lamp_rest = lamp.transform.basis
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP | GC.L_PLAYER | GC.L_NPC
	_query.exclude = [heli.get_rid()]
	transform = Transform3D(Basis.IDENTITY, _local_pos)
	spot = SpotLight3D.new()
	spot.name = "BeamLight"
	spot.spot_range = range_m
	spot.spot_angle = half_angle_deg
	spot.spot_attenuation = 0.7
	spot.light_energy = 0.0
	spot.light_color = Color(1.0, 0.95, 0.84)
	spot.light_specular = 0.8
	spot.shadow_enabled = false
	spot.visible = false
	add_child(spot)
	# ---- faceted cone ------------------------------------------------------------------------------------------------
	_cone_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CONE_SHADER
	_cone_mat.shader = sh
	cone = MeshInstance3D.new()
	cone.name = "BeamCone"
	cone.mesh = _cone_mesh(8)
	cone.material_override = _cone_mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.visible = false
	add_child(cone)
	# ---- ground circle ------------------------------------------------------------------------------------------------
	_disc_mat = ShaderMaterial.new()
	var sh2 := Shader.new()
	sh2.code = DISC_SHADER
	_disc_mat.shader = sh2
	disc = MeshInstance3D.new()
	disc.name = "BeamSpot"
	disc.mesh = _disc_mesh(14)
	disc.material_override = _disc_mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.top_level = true
	disc.visible = false
	add_child(disc)


func _exit_tree() -> void:
	if is_instance_valid(lamp):
		lamp.transform.basis = _lamp_rest


static func _cone_mesh(n: int) -> ArrayMesh:
	# apex at y = +0.5 (UV.y 0), base circle radius 1 at y = -0.5 (UV.y 1); flat shaded (one normal per facet)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0), -0.5, sin(a0))
		var p1 := Vector3(cos(a1), -0.5, sin(a1))
		var apex := Vector3(0, 0.5, 0)
		# silhouette is faceted (8 sides) but the normals are radial so the fresnel fade in the shader softens the rim
		var n0 := Vector3(cos(a0), 0.25, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.25, sin(a1)).normalized()
		var nm := Vector3(cos((a0 + a1) * 0.5), 0.25, sin((a0 + a1) * 0.5)).normalized()
		verts.append_array([apex, p1, p0])
		norms.append_array([nm, n1, n0])
		uvs.append_array([Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(0.5, 1.0)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _disc_mesh(n: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		verts.append_array([Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))])
		norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2(0.5, 0.5), Vector2(cos(a1) * 0.5 + 0.5, sin(a1) * 0.5 + 0.5), Vector2(cos(a0) * 0.5 + 0.5, sin(a0) * 0.5 + 0.5)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# =====================================================================================================
# API
# =====================================================================================================
func set_enabled(on: bool) -> void:
	enabled = on


## World-space point to light (the beam turns towards it at `slew_deg`).
func aim_at(point: Vector3) -> void:
	var o := global_position
	var d := point - o
	if d.length_squared() > 1.0:
		want_dir = d.normalized()


func aim_dir(d: Vector3) -> void:
	if d.length_squared() > 0.0001:
		want_dir = d.normalized()


## Snap the beam (spawn / teleport).
func snap_to_target() -> void:
	dir = want_dir


func origin() -> Vector3:
	return global_position


## Is the point inside the lit cone (with a small tolerance), within range?
func covers(point: Vector3, tolerance_deg: float = 1.5) -> bool:
	if not enabled or fade < 0.5:
		return false
	var o := global_position
	var d := point - o
	var dist := d.length()
	if dist < 2.0 or dist > range_m:
		return false
	return rad_to_deg(dir.angle_to(d / dist)) < half_angle_deg + tolerance_deg


# =====================================================================================================
# Per-frame (the owner calls this from its physics tick)
# =====================================================================================================
func update(dt: float) -> void:
	if not _built or heli == null or not is_instance_valid(heli):
		return
	fade = move_toward(fade, 1.0 if (enabled and not heli.is_destroyed) else 0.0, dt * 2.2)
	var lit := fade > 0.01
	if spot.visible != lit:
		spot.visible = lit
		cone.visible = lit
		disc.visible = lit
		if not lit and is_instance_valid(lamp):
			lamp.transform.basis = _lamp_rest
	if not lit:
		return
	# ---- turn the beam ----------------------------------------------------------------------------------------------
	var ang := dir.angle_to(want_dir)
	if ang > 0.0001:
		var step := deg_to_rad(slew_deg) * dt
		dir = want_dir if ang <= step else dir.slerp(want_dir, step / ang).normalized()
	var hb := heli.global_transform.basis
	var ld := hb.inverse() * dir
	var up_hint := Vector3.UP if absf(ld.y) < 0.95 else Vector3.RIGHT
	transform = Transform3D(Basis.looking_at(ld, up_hint), _local_pos)
	if is_instance_valid(lamp):
		# the lamp housing follows the beam (its own pivot): express the direction in the model frame
		var mb: Basis = heli.model.global_transform.basis if heli.model != null else hb
		var md := mb.inverse() * dir
		lamp.transform.basis = Basis.looking_at(md, Vector3.UP if absf(md.y) < 0.95 else Vector3.RIGHT) * _lamp_rest
	# ---- where does the beam end (10 Hz) -----------------------------------------------------------------------------
	_ray_t -= dt
	if _ray_t <= 0.0:
		_ray_t = 0.1
		_cast()
	_smoothed_dist = lerpf(_smoothed_dist, hit_dist, minf(1.0, dt * 14.0))
	# ---- visuals ------------------------------------------------------------------------------------------------------
	var night := 1.0 - clampf(Game.daylight(), 0.0, 1.0)
	var tan_h := tan(deg_to_rad(half_angle_deg))
	var l := maxf(_smoothed_dist, 2.0)
	var r := l * tan_h
	cone.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(r, l, r)), Vector3(0, 0, -l * 0.5))
	_cone_vis = Util.damp(_cone_vis, _camera_cone_visibility(l, tan_h), 7.0, dt)
	cone.visible = _cone_vis > 0.01
	_cone_mat.set_shader_parameter("strength", lerpf(0.07, 0.17, night) * fade * _cone_vis)
	spot.light_energy = energy * fade * lerpf(0.55, 1.0, night)
	spot.shadow_enabled = shadows and fade > 0.8 and night > 0.3
	_disc_mat.set_shader_parameter("strength", lerpf(0.16, 0.42, night) * fade)
	var n := hit_normal
	var fwd_flat := dir - n * dir.dot(n)
	if fwd_flat.length_squared() < 0.0004:
		fwd_flat = Vector3.FORWARD.slide(n)
	fwd_flat = fwd_flat.normalized()
	var side := n.cross(fwd_flat).normalized()
	var inc := clampf(absf(dir.dot(n)), 0.3, 1.0)
	var rr := maxf(r, 0.6)
	var b := Basis(side * rr, n, fwd_flat * (rr / inc))
	disc.global_transform = Transform3D(b, hit_pos + n * 0.1)


## 1 = cone fully visible, 0 = hidden: the camera is inside the beam volume (or within a margin of it) or the lamp is close to the camera.
func _camera_cone_visibility(length_m: float, tan_h: float) -> float:
	var cam: Camera3D = Game.gameplay_camera if is_instance_valid(Game.gameplay_camera) else get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return 1.0
	var o := global_position
	var rel := cam.global_position - o
	var near_lamp := 1.0 - smoothstep(NEAR_HELI_FADE_START, NEAR_HELI_FADE_END, rel.length())
	var t := rel.dot(dir)
	var inside := 0.0
	if t > -INSIDE_MARGIN and t < length_m + INSIDE_MARGIN:
		var perp := (rel - dir * t).length()
		var rad := maxf(t, 0.0) * tan_h + INSIDE_MARGIN
		inside = 1.0 - smoothstep(rad * 0.55, rad, perp)
	return 1.0 - maxf(near_lamp, inside)


func _cast() -> void:
	var o := global_position
	_query.from = o
	_query.to = o + dir * range_m
	var space := heli.get_world_3d().direct_space_state
	var hit := space.intersect_ray(_query)
	var end := o + dir * range_m
	var nrm := Vector3.UP
	hit_node = null
	if not hit.is_empty():
		end = hit.position
		nrm = hit.normal
		hit_node = hit.collider
	# the sea: the beam ends on the water surface when it dives below GC.WATER_LEVEL over the sea
	if dir.y < -0.01 and o.y > GC.WATER_LEVEL:
		var tw := (GC.WATER_LEVEL - o.y) / dir.y
		if tw > 0.0 and tw < o.distance_to(end) - 0.01:
			var wp := o + dir * tw
			if WorldLayout.is_water(wp.x, wp.z):
				end = wp
				nrm = Vector3.UP
				hit_node = null
	hit_pos = end
	hit_normal = nrm
	hit_dist = o.distance_to(end)
