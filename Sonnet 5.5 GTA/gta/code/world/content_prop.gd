class_name ContentProp
extends RigidBody3D
## A smashable street prop (cone / bin / barrier): sleeping rigid body on GC.L_PROP, group "damageable".
## No _process / _physics_process: the single ContentManager freezes far props and wakes near ones.

var kind: StringName = &"cone"
var hp := 20.0


func apply_damage(amount: float, info: Dictionary) -> void:
	sleeping = false
	freeze = false
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var from: Vector3 = info.get("position", global_position)
	var imp := float(info.get("impulse", 0.0))
	if dir.length_squared() < 0.0001:
		dir = (global_position - from)
		dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	# target launch speed (m/s) independent of mass: bullets ~4.5, vehicles / explosions much more
	var dv := clampf(1.8 + amount * 0.1 + imp * 0.01, 2.2, 16.0)
	dir.y = maxf(dir.y, 0.0) + 0.35
	var impulse := dir.normalized() * dv * mass
	apply_impulse(impulse, from - global_position)
	apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * dv * mass * 0.12)
