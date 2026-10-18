class_name EmergencyCrew
extends Node3D
## A paramedic / firefighter on foot: a bare CharacterRig that walks to targets, kneels and (firefighters) sprays a water hose.
## Not a CharacterBase: no collision, no AI, driven entirely by the EmergencySystem unit that owns it.

const WALK_SPEED := 2.7

var kind: StringName = &"paramedic"
var rig: CharacterRig = null
var target := Vector3.ZERO
var moving := false
var _hose: CPUParticles3D = null
var _ground_t := 0.0
var _ground_y := 0.0
var spraying := false


func setup(k: StringName, rng: RandomNumberGenerator = null) -> void:
	kind = k
	rig = CharacterRig.new()
	add_child(rig)
	var v: Dictionary = CharacterVariants.make(&"pedestrian", rng)
	if k == &"paramedic":
		v["shirt"] = Color("#f2f0ea")
		v["pants"] = Color("#2f9c95")
		v["accent"] = Color("#d93a3a")
		v["shoes"] = Color("#15171a")
		v["hat"] = &"Hat_Cap"
		v["hat_color"] = Color("#f2f0ea")
		v["jacket"] = &""
	else:
		v["shirt"] = Color("#c92a2a")
		v["pants"] = Color("#2a2d33")
		v["accent"] = Color("#f2cf3a")
		v["shoes"] = Color("#15171a")
		v["hat"] = &"Helmet_Tactical"
		v["hat_color"] = Color("#f2cf3a")
		v["vest"] = &"Vest_Tactical"
		v["vest_color"] = Color("#ee8a2b")
	rig.setup(v)


func walk_to(p: Vector3) -> void:
	target = p
	moving = true
	_ground_t = 0.0


func is_there() -> bool:
	return not moving


func kneel(on: bool) -> void:
	if rig != null:
		rig.set_stance(&"crouch" if on else &"stand")


func face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		rotation.y = Util.dir_to_yaw(d.normalized())


## Water spray towards a world point (firefighters).
func spray(at: Vector3, on: bool) -> void:
	spraying = on
	if _hose == null:
		_hose = _make_hose()
		add_child(_hose)
		_hose.position = Vector3(0.0, 1.15, -0.5)
	_hose.emitting = on
	if on:
		face(at)
		var dir := at - _hose.global_position
		var flat := Vector2(dir.x, dir.z).length()
		# ballistic aim: raise the nozzle so the stream lands near the target
		var pitch := clampf(atan2(dir.y + 0.5 * 9.8 * pow(flat / 11.0, 2.0), maxf(flat, 0.1)), 0.0, 1.0)
		_hose.rotation = Vector3(pitch, 0.0, 0.0)
		_hose.initial_velocity_min = 10.5
		_hose.initial_velocity_max = 11.5


func _make_hose() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Hose"
	p.amount = 70
	p.lifetime = 0.95
	p.one_shot = false
	p.explosiveness = 0.0
	p.direction = Vector3(0, 0, -1)
	p.spread = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = 10.5
	p.initial_velocity_max = 11.5
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.5
	p.emitting = false
	var m := SphereMesh.new()
	m.radius = 0.07
	m.height = 0.14
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.88, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _physics_process(dt: float) -> void:
	if rig == null:
		return
	_ground_t -= dt
	if _ground_t <= 0.0:
		_ground_t = 0.25
		var hit := Util.raycast(self, global_position + Vector3(0, 2.0, 0), global_position + Vector3(0, -3.0, 0), GC.L_WORLD)
		if not hit.is_empty():
			_ground_y = (hit["position"] as Vector3).y
	global_position.y = lerpf(global_position.y, _ground_y, minf(10.0 * dt, 1.0))
	if not moving:
		rig.set_locomotion(0.0, Vector3(0, 0, -1), false)
		return
	var d := target - global_position
	d.y = 0.0
	var dist := d.length()
	if dist < 0.2:
		moving = false
		rig.set_locomotion(0.0, Vector3(0, 0, -1), false)
		return
	var step := minf(WALK_SPEED * dt, dist)
	var dir := d / dist
	global_position += dir * step
	rotation.y = lerp_angle(rotation.y, Util.dir_to_yaw(dir), minf(9.0 * dt, 1.0))
	rig.set_locomotion(WALK_SPEED, Vector3(0, 0, -1), false)
