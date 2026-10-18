class_name AirFx
extends Node3D
## Shared pooled effects of the air / sea vehicles (ONE instance, created lazily under the vehicle container):
##   * dust / sand / spray / mist puff pools (MultiMesh billboards, same pool code as VehicleFx) for rotor downwash, prop wash,
##     bow spray and engine mist;
##   * a ring buffer of flat foam patches lying on the sea (wake + bow wave + prop churn).
## Draw calls: 3 for everything. No node allocation while emitting.

static var inst: AirFx = null

const FOAM_MAX := 220

var dust: VehicleFx.Pool
var spray: VehicleFx.Pool
var mist: VehicleFx.Pool
var _foam_mm: MultiMesh
var _foam_node: MultiMeshInstance3D
var _foam_head := 0
var _foam_live := 0
var _foam_pos := PackedVector3Array()
var _foam_yaw := PackedFloat32Array()
var _foam_w0 := PackedFloat32Array()
var _foam_w1 := PackedFloat32Array()
var _foam_len := PackedFloat32Array()
var _foam_age := PackedFloat32Array()
var _foam_life := PackedFloat32Array()
var _foam_alpha := PackedFloat32Array()
var _foam_acc := 0.0
var _foam_dirty := false

const SURFACE_DUST := {
	&"sand": Color(0.90, 0.82, 0.62, 0.55),
	&"concrete": Color(0.78, 0.78, 0.80, 0.34),
	&"asphalt": Color(0.74, 0.74, 0.76, 0.30),
	&"road": Color(0.74, 0.74, 0.76, 0.30),
	&"grass": Color(0.58, 0.68, 0.42, 0.34),
	&"dirt": Color(0.66, 0.55, 0.42, 0.45),
	&"rock": Color(0.70, 0.66, 0.60, 0.34),
	&"wood": Color(0.80, 0.74, 0.64, 0.28),
	&"metal": Color(0.80, 0.80, 0.82, 0.26),
}


static func get_fx() -> AirFx:
	if inst != null and is_instance_valid(inst):
		return inst
	var parent: Node = null
	var vs = Game.sys(&"vehicles")
	if vs != null and vs.has_method("get_container"):
		parent = vs.get_container()
	if parent == null:
		parent = Game.world if Game.world != null else Game.main
	if parent == null:
		return null
	var fx := AirFx.new()
	parent.add_child(fx)
	return fx


func _ready() -> void:
	inst = self
	name = "AirFx"
	top_level = true
	var soft := VehicleFx._soft_texture()
	var base := StandardMaterial3D.new()
	base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base.albedo_texture = soft
	base.vertex_color_use_as_albedo = true
	base.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	base.billboard_keep_scale = true
	base.cull_mode = BaseMaterial3D.CULL_DISABLED
	base.disable_receive_shadows = true
	dust = VehicleFx.Pool.new(260, base, 0.15, 1.1, self)
	spray = VehicleFx.Pool.new(260, base, -7.5, 0.5, self)
	mist = VehicleFx.Pool.new(160, base, 0.6, 1.6, self)
	# ---- foam patches
	_foam_pos.resize(FOAM_MAX)
	_foam_yaw.resize(FOAM_MAX)
	_foam_w0.resize(FOAM_MAX)
	_foam_w1.resize(FOAM_MAX)
	_foam_len.resize(FOAM_MAX)
	_foam_age.resize(FOAM_MAX)
	_foam_life.resize(FOAM_MAX)
	_foam_alpha.resize(FOAM_MAX)
	for i in FOAM_MAX:
		_foam_age[i] = 99.0
		_foam_life[i] = 1.0
	_foam_mm = MultiMesh.new()
	_foam_mm.transform_format = MultiMesh.TRANSFORM_3D
	_foam_mm.use_colors = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_texture = _foam_texture()
	fm.vertex_color_use_as_albedo = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.disable_receive_shadows = true
	fm.render_priority = 3
	pm.material = fm
	_foam_mm.mesh = pm
	_foam_mm.instance_count = FOAM_MAX
	_foam_mm.visible_instance_count = FOAM_MAX
	var zero := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -500, 0))
	for i in FOAM_MAX:
		_foam_mm.set_instance_transform(i, zero)
		_foam_mm.set_instance_color(i, Color(1, 1, 1, 0))
	_foam_node = MultiMeshInstance3D.new()
	_foam_node.multimesh = _foam_mm
	_foam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_foam_node.custom_aabb = AABB(Vector3(-6000, -50, -6000), Vector3(12000, 100, 12000))
	add_child(_foam_node)


func _exit_tree() -> void:
	if inst == self:
		inst = null


## Streaky foam texture: soft ellipse with a noisy core (no image files).
static func _foam_texture() -> Texture2D:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for y in sz:
		for x in sz:
			var u := (float(x) / (sz - 1)) * 2.0 - 1.0
			var w := (float(y) / (sz - 1)) * 2.0 - 1.0
			var r := sqrt(u * u + w * w * 0.55)
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = pow(a, 0.8)
			var n := rng.randf()
			a *= lerpf(0.55, 1.0, n)
			if n > 0.8:
				a = minf(a * 1.25, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _process(dt: float) -> void:
	dust.step(dt)
	spray.step(dt)
	mist.step(dt)
	if _foam_live > 0:
		_foam_acc += dt
		for i in FOAM_MAX:
			if _foam_age[i] < _foam_life[i]:
				_foam_age[i] += dt
		if _foam_acc >= 0.05:
			_foam_acc = 0.0
			_update_foam()


func _update_foam() -> void:
	var live := 0
	for i in FOAM_MAX:
		var a: float = _foam_age[i]
		var lf: float = _foam_life[i]
		if a >= lf:
			if _foam_dirty and a < 90.0:
				_foam_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -500, 0)))
				_foam_mm.set_instance_color(i, Color(1, 1, 1, 0))
				_foam_age[i] = 99.0
			continue
		live += 1
		var t := a / lf
		var wd := lerpf(_foam_w0[i], _foam_w1[i], t)
		var al: float = _foam_alpha[i] * (1.0 - t) * minf(t * 12.0, 1.0)
		var b := Basis(Vector3.UP, _foam_yaw[i]).scaled(Vector3(wd, 1.0, _foam_len[i]))
		_foam_mm.set_instance_transform(i, Transform3D(b, _foam_pos[i]))
		_foam_mm.set_instance_color(i, Color(1, 1, 1, al))
	_foam_live = live
	_foam_dirty = true


# =====================================================================================================
# API
# =====================================================================================================
## Rotor / prop downwash puffs on a surface: `strength` 0..1, `radius` the blast radius (m), `n` puffs this call.
func downwash(ground: Vector3, surface: StringName, strength: float, radius: float, n: int) -> void:
	if strength <= 0.02:
		return
	var is_water := surface == &"water"
	var col: Color = SURFACE_DUST.get(surface, SURFACE_DUST[&"concrete"])
	for i in n:
		var a := randf() * TAU
		var r0 := randf_range(0.4, radius * 0.45)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var p := ground + dir * r0 + Vector3(0, 0.12, 0)
		var out_speed := randf_range(5.0, 9.5) * (0.5 + strength * 0.7)
		var v := dir * out_speed + Vector3(0, randf_range(0.3, 1.4), 0)
		if is_water:
			var c := Color(0.92, 0.97, 1.0, 0.5 * strength)
			spray.emit(p, v * 0.9 + Vector3(0, randf_range(0.8, 2.4), 0), randf_range(0.5, 1.0), randf_range(0.25, 0.5), randf_range(0.9, 1.7), c)
			if i % 2 == 0:
				mist.emit(p, v * 0.6, randf_range(0.9, 1.6), 0.8, randf_range(2.2, 3.6), Color(0.88, 0.95, 1.0, 0.3 * strength))
		else:
			var c2 := col
			c2.a *= clampf(strength * 1.15, 0.2, 1.0)
			dust.emit(p, v, randf_range(0.8, 1.5), randf_range(0.6, 1.0), randf_range(2.4, 4.2), c2)


## Spray droplets (bow spray, landing splash): world position + velocity of the first drop.
func spray_burst(p: Vector3, v: Vector3, n: int, spread: float = 1.4, size: float = 0.45) -> void:
	for i in n:
		var vv := v + Vector3(randf_range(-spread, spread), randf_range(0.0, spread * 1.6), randf_range(-spread, spread))
		spray.emit(p + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2)), vv, randf_range(0.45, 0.95), size * randf_range(0.5, 0.9), size * randf_range(1.8, 3.0), Color(0.94, 0.98, 1.0, 0.62))


func mist_puff(p: Vector3, v: Vector3, size: float = 1.5, alpha: float = 0.25, life: float = 1.2) -> void:
	mist.emit(p, v, life, size * 0.5, size * 1.8, Color(0.9, 0.96, 1.0, alpha))


## One flat foam patch on the sea. dir = travel direction (XZ), width start / end, length, life, alpha.
func wake_patch(p: Vector3, dir: Vector3, w0: float, w1: float, length: float, life: float, alpha: float) -> void:
	var i := _foam_head
	_foam_head = (_foam_head + 1) % FOAM_MAX
	_foam_pos[i] = p
	_foam_yaw[i] = atan2(-dir.x, -dir.z)
	_foam_w0[i] = w0
	_foam_w1[i] = w1
	_foam_len[i] = length
	_foam_age[i] = 0.0
	_foam_life[i] = life
	_foam_alpha[i] = alpha
	_foam_live = maxi(_foam_live, 1)


func exhaust_smoke(p: Vector3, v: Vector3, size: float, alpha: float) -> void:
	dust.emit(p, v, randf_range(0.7, 1.3), size * 0.5, size * 2.0, Color(0.36, 0.36, 0.38, alpha))
