class_name VehicleFx
extends Node3D
## Shared, pooled vehicle effects (ONE instance owned by VehicleSystem): skid marks (ring-buffer MultiMesh of ground quads),
## and three billboard puff pools (smoke / fire / sparks) rendered as MultiMeshes - 4 draw calls total regardless of vehicle count.
## Static access: VehicleFx.inst (null when the vehicle system is absent -> callers skip).

static var inst: VehicleFx = null

const SKID_MAX := 640
const SKID_LIFE := 45.0

# ---- skid marks --------------------------------------------------------------------------------------------------
var _skid_mm: MultiMesh
var _skid_node: MultiMeshInstance3D
var _skid_head := 0
var _skid_count := 0
var _skid_born := PackedFloat32Array()
var _skid_alpha := PackedFloat32Array()
var _fade_t := 0.0
var enabled := true

# ---- puff pools ----------------------------------------------------------------------------------------------------
var smoke: Pool
var fire: Pool
var sparks: Pool
var _flash: OmniLight3D = null
var _flash_t := 0.0
var _clock := 0.0


class Pool:
	var mm: MultiMesh
	var node: MultiMeshInstance3D
	var n := 0
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var s0 := PackedFloat32Array()
	var s1 := PackedFloat32Array()
	var col := PackedColorArray()
	var buf := PackedFloat32Array()
	var head := 0
	var alive := 0
	var gravity := 0.0
	var drag := 1.0
	var dirty_clear := false

	func _init(count: int, material: Material, grav: float, drg: float, parent: Node3D) -> void:
		n = count
		gravity = grav
		drag = drg
		pos.resize(n)
		vel.resize(n)
		age.resize(n)
		life.resize(n)
		s0.resize(n)
		s1.resize(n)
		col.resize(n)
		buf.resize(n * 16)
		for i in n:
			age[i] = 99.0
			life[i] = 1.0
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.material = material
		mm.mesh = q
		mm.instance_count = n
		mm.visible_instance_count = 0
		node = MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-6000, -200, -6000), Vector3(12000, 600, 12000))
		parent.add_child(node)

	func emit(p: Vector3, v: Vector3, lifetime: float, size_start: float, size_end: float, color: Color) -> void:
		var i := head
		head = (head + 1) % n
		pos[i] = p
		vel[i] = v
		age[i] = 0.0
		life[i] = lifetime
		s0[i] = size_start
		s1[i] = size_end
		col[i] = color
		alive = maxi(alive, 1)

	func step(dt: float) -> void:
		if alive == 0:
			if dirty_clear:
				mm.visible_instance_count = 0
				dirty_clear = false
			return
		var live := 0
		var last := 0
		var damp := exp(-drag * dt)
		for i in n:
			var a: float = age[i]
			var o := i * 16
			if a >= life[i]:
				if buf[o + 15] != 0.0 or buf[o] != 0.0:
					buf[o] = 0.0
					buf[o + 5] = 0.0
					buf[o + 10] = 0.0
					buf[o + 15] = 0.0
				continue
			a += dt
			age[i] = a
			if a >= life[i]:
				buf[o] = 0.0
				buf[o + 5] = 0.0
				buf[o + 10] = 0.0
				buf[o + 15] = 0.0
				continue
			live += 1
			last = i
			var v: Vector3 = vel[i]
			v.y += gravity * dt
			v *= damp
			vel[i] = v
			var p: Vector3 = pos[i] + v * dt
			pos[i] = p
			var t := a / life[i]
			var sz := lerpf(s0[i], s1[i], t)
			var c: Color = col[i]
			var al := c.a * (1.0 - t) * minf(t * 8.0, 1.0)
			buf[o] = sz
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 3] = p.x
			buf[o + 4] = 0.0
			buf[o + 5] = sz
			buf[o + 6] = 0.0
			buf[o + 7] = p.y
			buf[o + 8] = 0.0
			buf[o + 9] = 0.0
			buf[o + 10] = sz
			buf[o + 11] = p.z
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = al
		alive = live
		mm.visible_instance_count = n
		mm.buffer = buf
		if live == 0:
			dirty_clear = true


func _ready() -> void:
	inst = self
	name = "VehicleFx"
	top_level = true
	# ---- skid marks
	_skid_mm = MultiMesh.new()
	_skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	_skid_mm.use_colors = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.02, 0.02, 0.02, 1.0)
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.render_priority = -2
	pm.material = sm
	_skid_mm.mesh = pm
	_skid_mm.instance_count = SKID_MAX
	_skid_mm.visible_instance_count = 0
	_skid_node = MultiMeshInstance3D.new()
	_skid_node.multimesh = _skid_mm
	_skid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skid_node.custom_aabb = AABB(Vector3(-6000, -200, -6000), Vector3(12000, 600, 12000))
	add_child(_skid_node)
	_skid_born.resize(SKID_MAX)
	_skid_alpha.resize(SKID_MAX)
	# ---- puff pools
	var soft := _soft_texture()
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.albedo_texture = soft
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.billboard_keep_scale = true
	smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke_mat.disable_receive_shadows = true
	var fire_mat: StandardMaterial3D = smoke_mat.duplicate()
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var spark_mat: StandardMaterial3D = fire_mat.duplicate()
	smoke = Pool.new(220, smoke_mat, 0.9, 0.9, self)
	fire = Pool.new(160, fire_mat, 1.8, 1.4, self)
	sparks = Pool.new(96, spark_mat, -7.0, 0.4, self)
	_flash = OmniLight3D.new()
	_flash.omni_range = 26.0
	_flash.light_energy = 0.0
	_flash.light_color = Color(1.0, 0.6, 0.25)
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func _soft_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _process(dt: float) -> void:
	_clock += dt
	smoke.step(dt)
	fire.step(dt)
	sparks.step(dt)
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash.light_energy = maxf(_flash_t, 0.0) * 14.0
		if _flash_t <= 0.0:
			_flash.visible = false
	_fade_t -= dt
	if _fade_t <= 0.0:
		_fade_t = 2.0
		_fade_skids()


# ---- API --------------------------------------------------------------------------------------------------------------
## Adds one skid-mark quad between two ground points.
func skid_segment(a: Vector3, b: Vector3, normal: Vector3, width: float, strength: float) -> void:
	if not enabled:
		return
	var d := b - a
	var len_ := d.length()
	if len_ < 0.05 or len_ > 3.0:
		return
	var z := d / len_
	var y := normal.normalized()
	var x := y.cross(z).normalized()
	var xf := Transform3D(Basis(x * width, y, z * (len_ + 0.06)), (a + b) * 0.5)
	var i := _skid_head
	_skid_head = (_skid_head + 1) % SKID_MAX
	_skid_count = mini(_skid_count + 1, SKID_MAX)
	_skid_mm.set_instance_transform(i, xf)
	_skid_alpha[i] = 0.62 * strength
	_skid_born[i] = _clock
	_skid_mm.set_instance_color(i, Color(1, 1, 1, _skid_alpha[i]))
	_skid_mm.visible_instance_count = _skid_count if _skid_count < SKID_MAX else SKID_MAX


func _fade_skids() -> void:
	for i in _skid_count:
		var age := _clock - _skid_born[i]
		if age > SKID_LIFE * 0.4:
			var k := clampf(1.0 - (age - SKID_LIFE * 0.4) / (SKID_LIFE * 0.6), 0.0, 1.0)
			_skid_mm.set_instance_color(i, Color(1, 1, 1, _skid_alpha[i] * k))


func clear_skids() -> void:
	_skid_count = 0
	_skid_head = 0
	_skid_mm.visible_instance_count = 0


func tire_smoke(p: Vector3, v: Vector3, strength: float) -> void:
	var g := randf_range(0.82, 0.95)
	smoke.emit(p + Vector3(0, 0.1, 0), v, randf_range(0.8, 1.5), 0.35, randf_range(1.4, 2.2) * (0.7 + strength * 0.5), Color(g, g, g, 0.5 * strength))


func dust(p: Vector3, v: Vector3, surface: StringName = &"dirt") -> void:
	var c := Color(0.66, 0.58, 0.44, 0.42) if surface != &"grass" else Color(0.45, 0.55, 0.32, 0.3)
	if surface == &"sand":
		c = Color(0.85, 0.77, 0.58, 0.45)
	smoke.emit(p + Vector3(0, 0.1, 0), v, randf_range(0.6, 1.2), 0.3, randf_range(1.0, 1.7), c)


func engine_smoke(p: Vector3, heavy: float) -> void:
	var g := randf_range(0.12, 0.3) if heavy > 0.6 else randf_range(0.45, 0.65)
	smoke.emit(p, Vector3(randf_range(-0.3, 0.3), randf_range(1.3, 2.2), randf_range(-0.3, 0.3)), randf_range(1.2, 2.3), 0.4, randf_range(1.5, 2.6), Color(g, g, g, 0.55))


func flame(p: Vector3) -> void:
	var c := Color(1.0, randf_range(0.35, 0.6), 0.08, 0.9)
	fire.emit(p + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), Vector3(randf_range(-0.3, 0.3), randf_range(1.8, 3.2), randf_range(-0.3, 0.3)), randf_range(0.35, 0.7), 0.9, 0.2, c)


func spark(p: Vector3, dir: Vector3, count: int = 6) -> void:
	for i in count:
		var v := dir * randf_range(1.0, 5.0) + Vector3(randf_range(-3, 3), randf_range(0.5, 4), randf_range(-3, 3))
		sparks.emit(p, v, randf_range(0.15, 0.4), 0.09, 0.03, Color(1.0, 0.8, 0.35, 1.0))


## Vehicle explosion: fireball + smoke column + sparks + short light flash.
func explosion(p: Vector3, radius: float) -> void:
	for i in 30:
		var d := Vector3(randf_range(-1, 1), randf_range(0.1, 1.2), randf_range(-1, 1)).normalized()
		fire.emit(p + d * 0.4, d * randf_range(2.0, 7.0), randf_range(0.5, 1.1), randf_range(1.6, 2.6), 0.5, Color(1.0, randf_range(0.4, 0.75), 0.1, 0.95))
	for i in 24:
		var d2 := Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)).normalized()
		var g := randf_range(0.08, 0.25)
		smoke.emit(p + d2 * 0.6, d2 * randf_range(1.0, 4.5) + Vector3(0, 2.0, 0), randf_range(1.8, 3.6), 1.2, randf_range(3.5, 6.0), Color(g, g, g, 0.7))
	spark(p, Vector3.UP, 24)
	_flash.global_position = p + Vector3.UP * 1.0
	_flash.omni_range = maxf(radius * 2.5, 18.0)
	_flash.visible = true
	_flash_t = 0.45
