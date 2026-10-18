class_name CombatUtil
extends RefCounted
## Small shared combat helpers: knockdown / ragdoll recovery, camera feedback, ownership checks.

const MAX_KNOCKED := 8
static var _knocked: Array = []          # [{node: WeakRef, until: msec}]


## Knocks a character to the ground for `duration` seconds. Uses victim.knock_down(impulse, duration) when the
## character implements it (NPC / police brains), else drives the rig ragdoll directly and recovers it later.
static func knock_down(victim: Node, impulse: Vector3, hit_pos: Vector3, duration: float = 2.2) -> bool:
	if not is_instance_valid(victim) or Ballistics.is_down(victim):
		return false
	if victim.has_method("knock_down"):
		victim.knock_down(impulse, duration)
		return true
	var rig = victim.get("rig")
	if rig == null or not is_instance_valid(rig) or not rig.has_method("start_ragdoll"):
		if victim.has_method("knockback"):
			victim.knockback(impulse)
		return false
	_enforce_cap()
	rig.start_ragdoll(impulse, hit_pos)
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	_knocked.append({"node": weakref(victim), "until": until})
	var tree := victim.get_tree()
	if tree != null:
		var timer := tree.create_timer(duration)
		timer.timeout.connect(_recover.bind(weakref(victim)))
	return true


static func _enforce_cap() -> void:
	var alive: Array = []
	for e in _knocked:
		var n = (e["node"] as WeakRef).get_ref()
		if n != null and Time.get_ticks_msec() < int(e["until"]):
			alive.append(e)
	_knocked = alive
	while _knocked.size() >= MAX_KNOCKED:
		var oldest = _knocked.pop_front()
		_recover(oldest["node"])


static func _recover(ref: WeakRef) -> void:
	var v = ref.get_ref()
	if v == null or not is_instance_valid(v) or Ballistics.is_down(v):
		return
	var rig = v.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("stop_ragdoll"):
		rig.stop_ragdoll()


## Camera feedback for the local player (distance attenuated). strength 0..1.
static func shake_camera(strength: float, duration: float, at: Vector3 = Vector3.INF, max_dist: float = 60.0) -> void:
	var cam = Game.gameplay_camera
	if cam == null or not is_instance_valid(cam) or not cam.has_method("add_shake"):
		return
	var s := strength
	if at != Vector3.INF:
		var d: float = (cam as Node3D).global_position.distance_to(at)
		s *= clampf(1.0 - d / max_dist, 0.0, 1.0)
	if s > 0.01:
		cam.add_shake(s, duration)


static func is_player_character(c: Node) -> bool:
	return c != null and is_instance_valid(c) and c.is_in_group(GC.G_PLAYER)


## Direction label of a hit relative to the victim's facing: &"front" &"back" &"left" &"right".
static func hit_side(victim: Node3D, hit_dir: Vector3) -> StringName:
	var fwd := -victim.global_transform.basis.z
	var local := victim.global_transform.basis.inverse() * (-hit_dir)   # vector from the victim toward the attacker
	if absf(local.x) > absf(local.z):
		return &"right" if local.x > 0.0 else &"left"
	return &"front" if local.z < 0.0 else &"back"
