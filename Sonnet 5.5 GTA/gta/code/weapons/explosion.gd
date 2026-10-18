class_name Explosion
extends RefCounted
## Radial blast: damage with falloff (line of sight reduces it), impulses on rigid bodies (vehicles, props), knockback /
## knockdown for characters, camera shake, FX and sound. Chain reactions (vehicles, barrels) come for free: victims that
## explode call back into CombatSystem.explode() from their own apply_damage().
##   Explosion.detonate(world_node, pos, radius, damage, source, opts) -> {"targets": n, "killed": n, "damaged": [...]}

const FALLOFF_POW := 1.2
const LOS_FACTOR := 0.3
const MAX_DEPTH := 3

static var _shape: SphereShape3D = SphereShape3D.new()
static var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
static var _depth := 0
static var _deferred: Array = []


## opts: weapon: StringName, force: float (peak delta-v m/s), shake: float (scale), fx: bool, scorch: bool, fire: bool,
## ignore: Array[Node], vehicle_mult: float, big: bool (sound/fx override)
static func detonate(anchor: Node3D, pos: Vector3, radius: float, damage: float, source: Node, opts: Dictionary = {}) -> Dictionary:
	var result := {"targets": 0, "killed": 0, "damaged": []}
	if anchor == null or not anchor.is_inside_tree():
		return result
	if _depth >= MAX_DEPTH:
		_deferred.append([anchor, pos, radius, damage, source, opts])
		anchor.get_tree().process_frame.connect(_flush_deferred, CONNECT_ONE_SHOT)
		return result
	_depth += 1
	if source != null and not is_instance_valid(source):
		source = null
	var weapon: StringName = opts.get("weapon", &"explosive")
	var force: float = opts.get("force", radius * 1.7)
	var ignore: Array = opts.get("ignore", [])
	var fx: FxManager = CombatSystem.get_fx()
	var big: bool = opts.get("big", radius >= 5.5)
	# ---- announce ------------------------------------------------------------------------------
	Events.explosion.emit(pos, radius, source)
	if opts.get("fx", true) and fx != null:
		fx.explosion(pos, radius, opts)
	Sfx.play_3d(&"explosion_big" if big else &"explosion_small", pos, 5.0 if big else 1.0, randf_range(0.93, 1.05), 260.0 if big else 160.0)
	CombatUtil.shake_camera(clampf(radius / 9.0, 0.25, 1.0) * float(opts.get("shake", 1.0)), 0.35 + radius * 0.05, pos, radius * 7.0)
	# ---- victims ------------------------------------------------------------------------------------
	var space := anchor.get_world_3d().direct_space_state
	_shape.radius = radius
	_query.shape = _shape
	_query.transform = Transform3D(Basis.IDENTITY, pos)
	_query.collision_mask = GC.M_EXPLOSION
	_query.collide_with_areas = false
	_query.exclude = []
	var found := space.intersect_shape(_query, 128)
	var seen: Dictionary = {}
	var list: Array = []
	for f in found:
		var col: Object = f["collider"]
		var tgt: Node = Ballistics.resolve_damageable(col)
		var loose := false
		if tgt == null:
			if col is RigidBody3D:
				tgt = col as Node
				loose = true
			else:
				continue
		var id := tgt.get_instance_id()
		if seen.has(id) or ignore.has(tgt):
			continue
		seen[id] = true
		list.append([tgt, loose])
	var lift := pos + Vector3(0, 0.45, 0)
	for entry in list:
		var tgt: Node = entry[0]
		if not is_instance_valid(tgt):
			continue
		var loose: bool = entry[1]
		var t3 := tgt as Node3D
		if t3 == null:
			continue
		var is_char: bool = tgt is CharacterBody3D or tgt.is_in_group(GC.G_ANIMAL)
		var is_veh: bool = tgt.is_in_group(GC.G_VEHICLE)
		var center := t3.global_position + (Vector3(0, 0.95, 0) if is_char else Vector3(0, 0.5, 0))
		var dist := _distance(pos, t3, center, is_veh)
		if dist > radius:
			continue
		var f := pow(clampf(1.0 - dist / radius, 0.0, 1.0), FALLOFF_POW)
		var blocked := not Util.has_line_of_sight(anchor, lift, center, GC.L_WORLD)
		if blocked:
			f *= LOS_FACTOR
		if f <= 0.01:
			continue
		var dir := center - pos
		if dir.length_squared() < 0.01:
			dir = Vector3.UP
		dir = dir.normalized()
		var push_dir := Vector3(dir.x, maxf(dir.y, 0.0) + 0.55, dir.z).normalized()
		var dv := force * f
		if not loose:
			var amount := damage * f * (float(opts.get("vehicle_mult", 1.0)) if is_veh else 1.0)
			var info := {
				"source": source, "type": GC.DMG_EXPLOSION, "zone": GC.ZONE_BODY, "position": center, "direction": dir,
				"weapon": weapon, "impulse": dv, "blast_center": pos, "blast_factor": f,
			}
			var was_down := Ballistics.is_down(tgt)
			tgt.apply_damage(amount, info)
			var down := Ballistics.is_down(tgt)
			result["targets"] += 1
			if down and not was_down:
				result["killed"] += 1
			(result["damaged"] as Array).append(tgt)
			if is_char and not down:
				if tgt.has_method("knockback"):
					tgt.knockback(push_dir * dv * 0.8)
				if f > 0.3:
					CombatUtil.knock_down(tgt, push_dir * dv, center, 1.6 + 2.0 * f)
		# physical impulse for rigid bodies (vehicles, props, barrels)
		if tgt is RigidBody3D:
			var rb := tgt as RigidBody3D
			if not rb.freeze:
				var mult := 1.0 if loose else (0.9 if is_veh else 1.0)
				var imp := push_dir * dv * mult * rb.mass
				rb.apply_central_impulse(imp)
				var tq := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)).normalized() * dv * rb.mass * 0.35
				rb.apply_torque_impulse(tq)
	if opts.get("fire", false):
		var cs := CombatSystem.get_instance()
		if cs != null:
			cs.spawn_fire(pos, radius * 0.45, 7.0, source)
	_depth -= 1
	return result


## Distance from the blast centre to the victim's surface (vehicles use their bounding box).
static func _distance(pos: Vector3, t3: Node3D, center: Vector3, is_veh: bool) -> float:
	if is_veh:
		var bb: AABB
		if t3.has_meta(&"_aabb"):
			bb = t3.get_meta(&"_aabb")
		else:
			bb = Util.local_aabb(t3)
			t3.set_meta(&"_aabb", bb)
		if bb.size.length() > 0.5:
			var local := t3.to_local(pos)
			var clamped := Vector3(
				clampf(local.x, bb.position.x, bb.end.x),
				clampf(local.y, bb.position.y, bb.end.y),
				clampf(local.z, bb.position.z, bb.end.z))
			return local.distance_to(clamped)
		return maxf(pos.distance_to(center) - 2.0, 0.0)
	return maxf(pos.distance_to(center) - 0.35, 0.0)


static func _flush_deferred() -> void:
	var items := _deferred.duplicate()
	_deferred.clear()
	for it in items:
		if is_instance_valid(it[0]):
			detonate(it[0], it[1], it[2], it[3], it[4], it[5])
