class_name CombatActor
extends RefCounted
## Shared body of every armed on-foot NPC (PoliceOfficer, GangNpc): capsule collider, CharacterRig, WeaponController, CombatMover,
## CombatBrain, distance tiers (physics stride + brain tiers), stance / crouch capsule, damage reactions, knock-down + get-up,
## death ragdoll and corpse clean-up. The owning CharacterBase forwards _physics_process / _on_damaged / _on_death / knock_down.
##
##   var actor := CombatActor.new()
##   actor.build(self, CharacterVariants.make(&"police", rng), [[&"pistol", 60]], {"accuracy": 0.4})
##   func _physics_process(dt): actor.physics(dt)

const RADIUS := 0.32
const HEIGHT := 1.78
const CROUCH_HEIGHT := 1.2
const CORPSE_SECONDS := 24.0
const LOD_NEAR := 70.0
const LOD_MID := 140.0
const STRIDE: Array[int] = [1, 2, 4]

var owner_node: CharacterBase = null
var rig: Node = null
var weapons: Node = null
var brain: CombatBrain = null
var mover: CombatMover = null
var collider: CollisionShape3D = null
var capsule: CapsuleShape3D = null
var crouched := false
var lod := 0
var down := false                   # knocked down (ragdoll) but alive
var down_until := 0.0
var corpse_t := 0.0
var variant: Dictionary = {}

var _acc := 0.0
var _last_floor := Vector3.INF
var _falls := 0
var _frame := 0
var _lod_t := 0.0
var _phase := 0
var _stance: StringName = &"stand"
var _hurt_snd_t := -10.0
var _now := 0.0
var _gone := false


func build(owner_body: CharacterBase, appearance: Dictionary, loadout: Array, cfg: Dictionary = {}) -> void:
	owner_node = owner_body
	variant = appearance
	owner_body.collision_layer = GC.L_NPC
	owner_body.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP | GC.L_NPC | GC.L_PLAYER
	owner_body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	owner_body.up_direction = Vector3.UP
	owner_body.floor_max_angle = deg_to_rad(50.0)
	owner_body.floor_snap_length = 0.4
	owner_body.floor_stop_on_slope = true
	owner_body.floor_block_on_wall = true
	owner_body.max_slides = 4
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	collider = CollisionShape3D.new()
	collider.name = "Collider"
	collider.shape = capsule
	collider.position = Vector3(0, HEIGHT * 0.5, 0)
	owner_body.add_child(collider)
	var r := CharacterRig.new()
	r.name = "Rig"
	owner_body.add_child(r)
	r.setup(appearance)
	rig = r
	owner_body.rig = r
	var wc := WeaponController.new()
	wc.name = "Weapons"
	owner_body.add_child(wc)
	wc.setup(owner_body)
	weapons = wc
	owner_body.weapons = wc
	var first := true
	for entry in loadout:
		var id: StringName = entry[0]
		wc.give_weapon(id, int(entry[1]), first)
		first = false
	mover = CombatMover.new()
	mover.setup(owner_body, r)
	brain = CombatBrain.new()
	brain.setup(owner_body, mover, cfg)
	_phase = int(owner_body.get_instance_id() % 4)
	_lod_t = randf() * 0.4
	if wc.has_method("get_current_def"):
		auto_range()


## Sets the preferred fighting range band from the equipped weapon (pistols mid range, shotguns close, rifles far).
func auto_range(scale: float = 1.0) -> void:
	var wc = weapons
	var d: Dictionary = wc.get_current_def()
	match d.get("category", &"handgun"):
		&"handgun":
			brain.pref_min = 7.0 * scale
			brain.pref_max = 19.0 * scale
			brain.weapon_range = 60.0
		&"smg":
			brain.pref_min = 5.0 * scale
			brain.pref_max = 15.0 * scale
			brain.weapon_range = 50.0
		&"shotgun":
			brain.pref_min = 3.0 * scale
			brain.pref_max = 9.0 * scale
			brain.weapon_range = 32.0
		&"rifle":
			brain.pref_min = 12.0 * scale
			brain.pref_max = 34.0 * scale
			brain.weapon_range = 100.0
		&"sniper":
			brain.pref_min = 40.0
			brain.pref_max = 100.0
			brain.weapon_range = 200.0
		&"melee":
			brain.pref_min = 0.5
			brain.pref_max = 1.8
			brain.weapon_range = 2.5
		_:
			brain.pref_min = 6.0
			brain.pref_max = 18.0
			brain.weapon_range = 50.0


func dispose() -> void:
	if brain != null:
		brain.dispose()
	_gone = true


# =====================================================================================================================
# Tick
# =====================================================================================================================
## Returns true when the owner should run its own order logic this frame (alive, standing, on foot).
func physics(dt: float) -> void:
	_now += dt
	var o := owner_node
	if o.is_dead:
		_tick_dead(dt)
		return
	if down:
		_tick_down(dt)
		return
	_lod_t -= dt
	if _lod_t <= 0.0:
		_lod_t = 0.5
		_refresh_lod()
		_check_fall(o)
	if o.is_in_vehicle():
		brain.lod = lod
		brain.tick_seated(dt)
		return
	_acc += dt
	_frame += 1
	var stride: int = STRIDE[lod]
	if stride > 1 and (_frame + _phase) % stride != 0:
		return
	var step := _acc
	_acc = 0.0
	brain.lod = lod
	brain.tick(step)
	_apply_stance(brain.stance_want)


## Safety net: a unit that dropped through the world (spawned overlapping geometry, a gap in a collider) goes back to its last floor
## position; the second time it is removed (the manager respawns / replaces it).
func _check_fall(o: CharacterBase) -> void:
	if o.is_in_vehicle():
		return
	if o.is_on_floor() or (_last_floor == Vector3.INF and o.global_position.y > -2.0 and o.global_position.y < 60.0):
		_last_floor = o.global_position
	elif o.global_position.y < -25.0:
		_falls += 1
		if _falls >= 2 or _last_floor == Vector3.INF:
			push_warning("CombatActor: %s fell out of the world twice - removed" % o.name)
			o.queue_free()
			return
		o.global_position = _last_floor + Vector3(0, 0.3, 0)
		o.velocity = Vector3.ZERO
		mover.reset_after_teleport()
		o.reset_physics_interpolation()


func _refresh_lod() -> void:
	var o := owner_node
	var cam = Game.gameplay_camera
	var ref: Vector3 = o.global_position
	var d := INF
	if cam != null and is_instance_valid(cam):
		d = (cam as Node3D).global_position.distance_to(ref)
	var pl = Game.player
	if pl != null and is_instance_valid(pl):
		d = minf(d, (pl as Node3D).global_position.distance_to(ref))
	if d == INF:
		d = 0.0
	if brain.in_combat:
		lod = 0 if d < LOD_MID else 1
	else:
		lod = 0 if d < LOD_NEAR else (1 if d < LOD_MID else 2)


# =====================================================================================================================
# Stance
# =====================================================================================================================
func _apply_stance(want: StringName) -> void:
	if want == _stance:
		return
	_stance = want
	var is_low := want == &"cover_low" or want == &"crouch"
	set_crouched(is_low)
	if rig != null and is_instance_valid(rig):
		rig.set_stance(want)


func set_crouched(on: bool) -> void:
	if on == crouched:
		return
	crouched = on
	var h := CROUCH_HEIGHT if on else HEIGHT
	capsule.height = h
	collider.position = Vector3(0, h * 0.5, 0)
	owner_node.set(&"body_height", 1.3 if on else 1.8)
	if weapons != null:
		weapons.crouched = on


# =====================================================================================================================
# Damage / knockdown / death
# =====================================================================================================================
func on_damaged(amount: float, info: Dictionary) -> void:
	var o := owner_node
	brain.on_damaged(amount, info)
	if _now - _hurt_snd_t > 0.7 and not o.is_dead:
		_hurt_snd_t = _now
		Sfx.play_3d(&"hurt_m", o.global_position + Vector3(0, 1.5, 0), -3.0, randf_range(0.92, 1.08), 35.0)
	var t: StringName = info.get("type", GC.DMG_BULLET)
	if (t == GC.DMG_RUNOVER or t == GC.DMG_EXPLOSION or t == GC.DMG_COLLISION) and amount > 10.0 and not o.is_dead:
		var dir: Vector3 = info.get("direction", Vector3.ZERO)
		if dir.length() < 0.1:
			dir = (o.global_position - (info["source"] as Node3D).global_position) if info.get("source") is Node3D else Vector3.FORWARD
		dir.y = 0.0
		dir = dir.normalized()
		knock_down(dir * minf(4.0 + amount * 0.12, 11.0) + Vector3.UP * 2.0, 1.8 + minf(amount * 0.02, 2.0))


func knock_down(impulse: Vector3, duration: float) -> void:
	var o := owner_node
	if o.is_dead or down:
		return
	down = true
	down_until = _now + duration
	collider.set_deferred("disabled", true)
	mover.stop()
	mover.move_vel = Vector3.ZERO
	var wc = weapons
	if wc != null:
		wc.set_trigger(false)
		wc.set_aiming(false)
	if rig != null and is_instance_valid(rig):
		rig.start_ragdoll(impulse.limit_length(12.0), o.global_position + Vector3.UP)
	o.velocity = Vector3.ZERO


func _tick_down(_dt: float) -> void:
	var o := owner_node
	o.velocity = Vector3.ZERO
	if rig != null and is_instance_valid(rig) and rig.has_method("get_ragdoll_position"):
		var rp: Vector3 = rig.get_ragdoll_position()
		var q := PhysicsRayQueryParameters3D.create(rp + Vector3.UP * 0.6, rp + Vector3.DOWN * 3.0, GC.M_GROUND)
		var hit := o.get_world_3d().direct_space_state.intersect_ray(q)
		var gy := rp.y - 0.35
		if not hit.is_empty():
			gy = (hit["position"] as Vector3).y
		o.global_position = Vector3(rp.x, gy + 0.02, rp.z)
	if _now >= down_until:
		down = false
		collider.set_deferred("disabled", false)
		if rig != null and is_instance_valid(rig):
			rig.stop_ragdoll()
		mover.reset_after_teleport()
		_stance = &""
		brain.in_combat = brain.has_target()


func on_death(info: Dictionary) -> void:
	var o := owner_node
	collider.set_deferred("disabled", true)
	brain.enabled = false
	brain.dispose()
	var wc = weapons
	if wc != null:
		wc.set_trigger(false)
		wc.set_aiming(false)
	for g in [GC.G_POLICE, GC.G_HOSTILE]:
		if o.is_in_group(g):
			o.remove_from_group(g)
	var dir: Vector3 = info.get("direction", -o.global_transform.basis.z)
	var imp := float(info.get("impulse", 4.0))
	if rig != null and is_instance_valid(rig):
		var was_down := down
		if was_down:
			rig.start_ragdoll(dir.normalized() * 2.0, info.get("position", o.global_position + Vector3.UP))
		else:
			rig.start_ragdoll(dir.normalized() * clampf(imp * 0.6, 2.0, 11.0), info.get("position", o.global_position + Vector3.UP))
	down = false
	Sfx.play_3d(&"death_m", o.global_position + Vector3.UP, 0.0, randf_range(0.92, 1.05), 40.0)
	corpse_t = 0.0
	o.velocity = Vector3.ZERO


func on_revive() -> void:
	var o := owner_node
	collider.set_deferred("disabled", false)
	brain.enabled = true
	if not CombatBrain.units.has(brain):
		CombatBrain.units.append(brain)
	if rig != null and is_instance_valid(rig):
		rig.stop_ragdoll()
	corpse_t = 0.0
	down = false
	_stance = &""
	mover.reset_after_teleport()
	o.add_to_group(GC.G_DAMAGEABLE)


func _tick_dead(dt: float) -> void:
	corpse_t += dt
	var o := owner_node
	# the body node follows the (settling) ragdoll so interaction / pickup logic sees it where it lies
	if rig != null and is_instance_valid(rig) and rig.has_method("get_ragdoll_position") and corpse_t < 6.0:
		o.global_position = rig.get_ragdoll_position()
	var limit := CORPSE_SECONDS
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and (pl as Node3D).global_position.distance_to(o.global_position) > 90.0:
		limit = 6.0
	if corpse_t > limit and not _gone:
		_gone = true
		o.queue_free()
