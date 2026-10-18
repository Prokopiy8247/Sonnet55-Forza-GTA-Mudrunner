class_name MeleeResolver
extends RefCounted
## Arc-cast melee: finds targets in front of the attacker (reach + arc + line of sight), applies damage, knockback,
## direction-based hit reactions and knockdowns. Used by WeaponController.melee_attack().

static var _shape: SphereShape3D = SphereShape3D.new()
static var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
const MASK := GC.L_NPC | GC.L_PLAYER | GC.L_VEHICLE | GC.L_PROP | GC.L_ANIMAL | GC.L_RAGDOLL


## params: heavy: bool, combo: int, weapon: StringName, damage_mult: float, max_targets: int, forward: Vector3 (optional),
## knockdown: bool. Returns {"any": bool, "killed": bool, "hits": Array[{target, damage, killed, pos}]}.
static func strike(attacker: CharacterBody3D, def: Dictionary, params: Dictionary) -> Dictionary:
	var result := {"any": false, "killed": false, "hits": []}
	if not is_instance_valid(attacker) or not attacker.is_inside_tree():
		return result
	var heavy: bool = params.get("heavy", false)
	var combo: int = params.get("combo", 1)
	var weapon: StringName = params.get("weapon", &"fists")
	var reach: float = float(def.get("reach", 1.6)) * (1.12 if heavy else 1.0)
	var arc: float = deg_to_rad(float(def.get("arc", 80.0)) * 0.5) * (1.1 if heavy else 1.0)
	var fwd: Vector3 = params.get("forward", Vector3.ZERO)
	if fwd.length_squared() < 0.01:
		fwd = -attacker.global_transform.basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var chest := attacker.global_position + Vector3(0, 1.2, 0)
	var space := attacker.get_world_3d().direct_space_state
	_shape.radius = reach * 0.75 + 0.45
	_query.shape = _shape
	_query.transform = Transform3D(Basis.IDENTITY, chest + fwd * reach * 0.4)
	_query.collision_mask = MASK
	var excl: Array[RID] = [attacker.get_rid()]
	var veh = attacker.get("current_vehicle")
	if veh is CollisionObject3D:
		excl.append(veh.get_rid())
	_query.exclude = excl
	var found := space.intersect_shape(_query, 32)
	var seen: Dictionary = {}
	var cands: Array = []
	for f in found:
		var col: Object = f["collider"]
		var tgt: Node = Ballistics.resolve_damageable(col)
		var is_prop := false
		if tgt == null:
			if col is RigidBody3D:
				tgt = col as Node
				is_prop = true
			else:
				continue
		if tgt == attacker or seen.has(tgt.get_instance_id()):
			continue
		if Ballistics.is_down(tgt) and not is_prop:
			continue
		seen[tgt.get_instance_id()] = true
		var t3 := tgt as Node3D
		if t3 == null:
			continue
		var is_char: bool = tgt is CharacterBody3D or tgt.is_in_group(GC.G_ANIMAL)
		var center := t3.global_position + (Vector3(0, 1.0, 0) if is_char else Vector3(0, 0.4, 0))
		var to := center - chest
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		var slack := 0.45 if is_char else (1.6 if tgt.is_in_group(GC.G_VEHICLE) else 0.6)
		if dist > reach + slack:
			continue
		if dist > 0.35:
			var ang := fwd.angle_to(flat / dist)
			if ang > arc:
				continue
		# line of sight (world geometry only)
		if not Util.has_line_of_sight(attacker, chest, center, GC.L_WORLD, [attacker]):
			continue
		var score := dist - (0.6 if is_char else 0.0)
		cands.append({"t": tgt, "score": score, "pos": center, "char": is_char, "prop": is_prop, "dist": dist})
	cands.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	var max_t: int = params.get("max_targets", 1)
	var dmg_base: float = float(def.get("damage", 10.0)) * float(params.get("damage_mult", 1.0))
	if heavy:
		dmg_base *= float(def.get("heavy_mult", 1.6))
	var kb: float = float(def.get("knockback", 3.0)) * (1.6 if heavy else 1.0)
	var fx: FxManager = CombatSystem.get_fx()
	for i in mini(max_t, cands.size()):
		var c: Dictionary = cands[i]
		var tgt: Node = c["t"]
		var t3 := tgt as Node3D
		var pos: Vector3 = c["pos"]
		var dir := (Vector3(pos.x - chest.x, 0.0, pos.z - chest.z)).normalized()
		if dir.length_squared() < 0.01:
			dir = fwd
		var hit_info := {"target": tgt, "damage": 0.0, "killed": false, "pos": pos}
		if bool(c["prop"]):
			var rb := tgt as RigidBody3D
			if rb != null and not rb.freeze:
				rb.apply_impulse((dir * kb + Vector3.UP * 0.6) * minf(rb.mass, 30.0), pos - rb.global_position)
			hit_info["damage"] = 0.0
			result["hits"].append(hit_info)
			result["any"] = true
			continue
		var dmg := dmg_base
		var side: StringName = &"front"
		var is_char: bool = bool(c["char"])
		if is_char:
			side = CombatUtil.hit_side(t3, dir)
			# from behind (victim facing away from us): backstab bonus
			var vfwd := -t3.global_transform.basis.z
			var behind := Vector3(vfwd.x, 0.0, vfwd.z).normalized().dot(dir) > 0.55
			if behind and bool(params.get("backstab", true)):
				dmg *= 4.0 if weapon == &"knife" else 1.35
		elif tgt.is_in_group(GC.G_VEHICLE):
			dmg *= 0.3
		var knockdown: bool = bool(params.get("knockdown", false)) or heavy and (weapon == &"bat" or weapon == &"crowbar")
		var info := {
			"source": attacker, "type": GC.DMG_MELEE, "zone": GC.ZONE_TORSO if is_char else GC.ZONE_BODY, "position": pos,
			"direction": dir, "weapon": weapon, "impulse": kb, "hit_side": side, "heavy": heavy, "combo": combo, "knockdown": knockdown,
		}
		var was_down := Ballistics.is_down(tgt)
		tgt.apply_damage(dmg, info)
		var down := Ballistics.is_down(tgt)
		hit_info["damage"] = dmg
		hit_info["killed"] = down and not was_down
		result["any"] = true
		if down and not was_down:
			result["killed"] = true
		if is_char and not down:
			var push := dir * kb + Vector3.UP * (2.0 if knockdown else 0.6)
			if knockdown:
				CombatUtil.knock_down(tgt, push * 1.4, pos, 2.2 if heavy else 1.8)
			elif tgt.has_method("knockback"):
				tgt.knockback(push)
			var rig = tgt.get("rig")
			if rig != null and is_instance_valid(rig) and rig.has_method("play_action") and not knockdown:
				rig.play_action(&"hit_react")
		elif is_char and tgt.has_method("knockback"):
			tgt.knockback(dir * kb * 0.6)
		if fx != null:
			if is_char and weapon != &"fists":
				fx.blood(pos, -dir, 0.7)
			elif is_char:
				fx.smoke_puff(pos, Vector3.UP, 0.6)
			else:
				fx.impact(pos, -dir, &"metal", 0.7, false, false)
		result["hits"].append(hit_info)
	return result
