class_name VehicleDamage
extends RefCounted
## Visual / FX side of vehicle damage: glass cracking + shattering, window tint, engine smoke (< 35 % health), fire (< 15 %),
## explosion look + wreck materials, impact sparks.  Numbers (health, collision damage, fire drain) live in VehicleBase.

var v: VehicleBase = null
var glass_state := 0                   # 0 clean, 1 cracked, 2 shattered
var tint := 0
var _glass_surfs: Array = []
var _engine_pos := Vector3(0, 0.9, -1.4)
var _smoke_t := 0.0
var _fire_light: OmniLight3D = null
var _ratio := 1.0
var _wrecked := false
var _burnt := false
var _burn_left := 0.0


func setup(vehicle: VehicleBase) -> void:
	v = vehicle
	if v.model == null:
		return
	for mi in ModelLib.meshes(v.model):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m != null and m.resource_name == "Glass":
				_glass_surfs.append([mi, i])
	var hood := v.model.find_child("Hood", true, false) as Node3D
	var len_ := float(v.def.get("length", 4.5))
	var h := float(v.def.get("height", 1.45))
	if hood != null:
		_engine_pos = Util._rel_transform(v.model, hood).origin + Vector3(0, 0.12, 0)
	else:
		_engine_pos = Vector3(0, h * 0.55, -len_ * 0.3)
	if v.vclass == GC.VC_BIKE or v.vclass == GC.VC_BICYCLE:
		_engine_pos = Vector3(0, h * 0.45, 0)
	_apply_glass()


func _apply_glass() -> void:
	var mat: Material = VehicleMaterials.glass(glass_state, tint)
	if _wrecked:
		mat = VehicleMaterials.wreck(&"glass")
	for pair in _glass_surfs:
		var mi: MeshInstance3D = pair[0]
		if is_instance_valid(mi):
			mi.set_surface_override_material(pair[1], mat)


func hit_glass() -> void:
	if glass_state < 2:
		glass_state += 1
		_apply_glass()
		if v.audio != null:
			v.audio._snd(&"glass_break", -3.0, randf_range(0.9, 1.15), 40.0)


func set_tint(level: int) -> void:
	tint = clampi(level, 0, 3)
	_apply_glass()


func damage_state_changed(ratio: float) -> void:
	_ratio = ratio


func spark_at(p: Vector3, dir: Vector3) -> void:
	if VehicleFx.inst != null and v.visual_lod == 0:
		VehicleFx.inst.spark(p, dir if dir is Vector3 else Vector3.UP, 4)


func impact_fx(impact: float, _other: Node) -> void:
	if VehicleFx.inst == null or v.visual_lod != 0:
		return
	var n := clampi(int(impact * 0.7), 2, 14)
	VehicleFx.inst.spark(v.global_position + Vector3.UP * 0.5, Vector3.UP, n)
	if impact > 11.0 and glass_state < 2:
		hit_glass()
	elif impact > 6.5 and glass_state == 0:
		hit_glass()


## Called every physics tick: engine smoke + fire emission (cheap early-outs for healthy vehicles).
func tick(dt: float) -> void:
	if v == null or (_wrecked and not v.on_fire and not _burnt and _burn_left < -20.0):
		return
	var fx: VehicleFx = VehicleFx.inst
	if _burnt:
		_burn_left -= dt
		if _burn_left <= 0.0:
			_burnt = false
	var smoking := (_ratio < 0.35 and not v.is_destroyed) or (_wrecked and _burn_left > -20.0)
	var burning := (v.on_fire and not v.is_destroyed) or _burnt
	if not smoking and not burning:
		if _fire_light != null:
			_fire_light.visible = false
		return
	if fx == null or v.visual_lod != 0:
		return
	_smoke_t -= dt
	if _smoke_t <= 0.0:
		_smoke_t = 0.06 if burning else lerpf(0.16, 0.07, clampf(1.0 - _ratio / 0.35, 0.0, 1.0))
		var p: Vector3 = v.global_transform * _engine_pos
		fx.engine_smoke(p, 1.0 if burning else clampf(1.0 - _ratio / 0.35, 0.0, 1.0))
		if burning:
			fx.flame(p + Vector3(0, 0.1, 0))
			fx.flame(p + v.global_transform.basis.x * randf_range(-0.5, 0.5))
	if burning:
		if _fire_light == null:
			_fire_light = OmniLight3D.new()
			_fire_light.omni_range = 9.0
			_fire_light.light_color = Color(1.0, 0.5, 0.15)
			_fire_light.shadow_enabled = false
			_fire_light.position = _engine_pos + Vector3(0, 0.5, 0)
			v.add_child(_fire_light)
		_fire_light.visible = true
		_fire_light.light_energy = 1.6 + sin(Time.get_ticks_msec() * 0.03 + float(v.get_instance_id() % 7)) * 0.5 + randf() * 0.5


func on_explode(burst: bool = true) -> void:
	_wrecked = true
	_burnt = true
	glass_state = 2
	if v.model != null:
		Util.replace_material(v.model, "Paint", VehicleMaterials.wreck(&"paint"))
		Util.replace_material(v.model, "Paint2", VehicleMaterials.wreck(&"paint"))
		Util.replace_material(v.model, "Trim", VehicleMaterials.wreck(&"dark"))
		Util.replace_material(v.model, "Interior", VehicleMaterials.wreck(&"dark"))
		Util.replace_material(v.model, "Chrome", VehicleMaterials.wreck(&"dark"))
	_apply_glass()
	if burst and VehicleFx.inst != null:
		VehicleFx.inst.explosion(v.global_position + Vector3(0, 0.6, 0), 8.0)
	_burn_left = 40.0


func repair() -> void:
	_wrecked = false
	_burnt = false
	_burn_left = 0.0
	glass_state = 0
	_ratio = 1.0
	_apply_glass()
	if _fire_light != null:
		_fire_light.visible = false
