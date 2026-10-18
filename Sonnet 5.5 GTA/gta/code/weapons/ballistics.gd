class_name Ballistics
extends RefCounted
## Hitscan bullet physics used by WeaponController (and anything that wants to fire a bullet: mounted guns, scripted
## events). One call = one bullet / pellet:
##   Ballistics.shoot(space, from, dir, {shooter, weapon, damage, range, ...}) -> result Dictionary
## Resolves the collider to the first "damageable" ancestor, picks the hit zone (head/torso/limb for characters,
## tire/glass/engine/body for vehicles), applies falloff, thin-material penetration, impulse on loose props, and spawns
## surface impact FX (pooled). The damage multipliers per zone are applied by the victim (CharacterBase.ZONE_MULT).

## surface -> [pierce cost, damage kept after passing through]
const PEN_TABLE := {
	&"glass": [1, 0.85], &"window": [1, 0.85], &"wood": [1, 0.62], &"foliage": [1, 0.9], &"leaves": [1, 0.9],
	&"plaster": [2, 0.55], &"drywall": [2, 0.55], &"thin_metal": [2, 0.5],
}
const WATER_LEVEL := GC.WATER_LEVEL

static var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


## p keys: shooter: Node, weapon: StringName, damage: float, range: float, falloff_start, falloff_min, penetration: int,
## impulse: float, exclude: Array[RID], mask: int, type: StringName, spawn_fx: bool, sfx_budget: Array[int] ([n] shared counter)
static func shoot(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, p: Dictionary) -> Dictionary:
	var rng: float = p.get("range", 100.0)
	var result := {
		"hit": false, "pos": from + dir * rng, "normal": -dir, "target": null, "killed": false, "damage": 0.0,
		"zone": &"", "surface": &"", "dist": rng, "damaged": false, "character": false, "water": false,
	}
	var base_damage: float = p.get("damage", 10.0)
	var fs: float = p.get("falloff_start", rng * 0.4)
	var fmin: float = p.get("falloff_min", 0.5)
	var pierce: int = p.get("penetration", 0)
	var mask: int = p.get("mask", GC.M_BULLET)
	var shooter: Node = p.get("shooter", null)
	var excl: Array[RID] = []
	for r in p.get("exclude", []):
		excl.append(r)
	var spawn_fx: bool = p.get("spawn_fx", true)
	var fx: FxManager = CombatSystem.get_fx() if spawn_fx else null
	var budget: Array = p.get("sfx_budget", [])
	var pos := from
	var left := rng
	var travelled := 0.0
	var dmg_mult := 1.0
	for iter in 4:
		_query.from = pos
		_query.to = pos + dir * left
		_query.collision_mask = mask
		_query.exclude = excl
		var hit := space.intersect_ray(_query)
		var seg_len := left if hit.is_empty() else pos.distance_to(hit["position"])
		# --- water surface crossing before the hit point -----------------------------------------
		if dir.y < -0.0001 and pos.y > WATER_LEVEL:
			var tw := (WATER_LEVEL - pos.y) / dir.y
			if tw > 0.0 and tw < seg_len:
				var wp := pos + dir * tw
				if WorldLayout.is_water(wp.x, wp.z):
					result["hit"] = true
					result["pos"] = wp
					result["normal"] = Vector3.UP
					result["surface"] = &"water"
					result["water"] = true
					result["dist"] = travelled + tw
					if fx != null:
						fx.impact(wp, Vector3.UP, &"water", 1.0, false, _take_budget(budget))
					Events.projectile_impact.emit(wp, Vector3.UP, &"water", shooter)
					return result
		if hit.is_empty():
			result["pos"] = pos + dir * left
			result["dist"] = travelled + left
			return result
		var collider: Object = hit["collider"]
		var hp: Vector3 = hit["position"]
		var hn: Vector3 = hit["normal"]
		travelled += seg_len
		var target: Node = resolve_damageable(collider)
		var surface: StringName = surface_of(collider, target)
		var dmg := base_damage * falloff(travelled, fs, fmin, rng) * dmg_mult
		result["hit"] = true
		result["pos"] = hp
		result["normal"] = hn
		result["surface"] = surface
		result["dist"] = travelled
		if target != null and target != shooter:
			var is_char := target is CharacterBody3D or target.is_in_group(GC.G_ANIMAL) or target.has_method("start_ragdoll")
			var zone := GC.ZONE_BODY
			if is_char:
				zone = character_zone(target, collider, hit, hp)
				surface = &"flesh"
			elif target.is_in_group(GC.G_VEHICLE):
				zone = vehicle_zone(target, hp, hn)
				surface = &"glass" if zone == GC.ZONE_GLASS else &"metal"
			result["zone"] = zone
			result["target"] = target
			result["character"] = is_char
			result["damage"] = dmg
			result["surface"] = surface
			var info := {
				"source": shooter, "type": p.get("type", GC.DMG_BULLET), "zone": zone, "position": hp,
				"direction": dir, "weapon": p.get("weapon", &""), "impulse": p.get("impulse", 0.0), "normal": hn,
				"distance": travelled,
			}
			var was_down := is_down(target)
			target.apply_damage(dmg, info)
			var down := is_down(target)
			result["damaged"] = true
			result["killed"] = down and not was_down
			if is_char:
				if fx != null:
					fx.blood(hp, dir, 1.0 if zone != GC.ZONE_HEAD else 1.5)
				if not down and target.has_method("knockback") and float(info["impulse"]) > 0.05:
					target.knockback(Vector3(dir.x, 0.0, dir.z).normalized() * float(info["impulse"]))
				if not down:
					_hit_react(target)
				Events.projectile_impact.emit(hp, hn, &"flesh", shooter)
			else:
				if fx != null:
					fx.impact(hp, hn, surface, 1.0, false, _take_budget(budget))
				Events.projectile_impact.emit(hp, hn, surface, shooter)
				# bullets keep going through breakable window props
				if surface == &"glass" and not target.is_in_group(GC.G_VEHICLE) and pierce >= 1:
					pierce -= 1
					dmg_mult *= 0.85
					pos = hp + dir * 0.05
					left -= seg_len + 0.05
					continue
			return result
		# ---- non-damageable collider: world, loose prop ----------------------------------------------
		var is_static := collider is StaticBody3D
		if collider is RigidBody3D and not (collider as RigidBody3D).freeze:
			var rb := collider as RigidBody3D
			var imp := minf(dmg * 0.22, rb.mass * 5.0)
			rb.apply_impulse(dir * imp, hp - rb.global_position)
		if fx != null:
			fx.impact(hp, hn, surface, 1.0 if dmg > 12.0 else 0.7, is_static, _take_budget(budget))
		Events.projectile_impact.emit(hp, hn, surface, shooter)
		var pen: Array = PEN_TABLE.get(surface, [])
		if not pen.is_empty() and pierce >= int(pen[0]):
			pierce -= int(pen[0])
			dmg_mult *= float(pen[1])
			pos = hp + dir * 0.06
			left -= seg_len + 0.06
			if left > 0.5:
				continue
		return result
	return result


## Flinch animation on the victim's rig (rate limited per victim).
static func _hit_react(target: Node) -> void:
	var rig = target.get("rig")
	if rig == null or not is_instance_valid(rig) or not rig.has_method("play_action"):
		return
	var now := Time.get_ticks_msec()
	var last: int = int(target.get_meta(&"_hit_react_t", -1000))
	if now - last < 280:
		return
	target.set_meta(&"_hit_react_t", now)
	rig.play_action(&"hit_react")


static func _take_budget(budget: Array) -> bool:
	if budget.is_empty():
		return true
	if int(budget[0]) <= 0:
		return false
	budget[0] = int(budget[0]) - 1
	return true


static func falloff(dist: float, fs: float, fmin: float, rng: float) -> float:
	if dist <= fs or rng <= fs:
		return 1.0
	return lerpf(1.0, fmin, clampf((dist - fs) / (rng - fs), 0.0, 1.0))


static func is_down(target: Object) -> bool:
	if not is_instance_valid(target):
		return true
	return target.get("is_dead") == true or target.get("is_destroyed") == true


## First ancestor (or the collider itself) in group "damageable".
static func resolve_damageable(collider: Object) -> Node:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 10:
		if n.is_in_group(GC.G_DAMAGEABLE):
			return n
		n = n.get_parent()
		depth += 1
	return null


## Surface type from meta "surface" on the collider or an ancestor; defaults by victim type, else concrete.
static func surface_of(collider: Object, target: Node) -> StringName:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 6:
		if n.has_meta(&"surface"):
			return StringName(n.get_meta(&"surface"))
		n = n.get_parent()
		depth += 1
	if target != null:
		if target is CharacterBody3D or target.is_in_group(GC.G_ANIMAL):
			return &"flesh"
		if target.is_in_group(GC.G_VEHICLE):
			return &"metal"
	return &"concrete"


## Zone for a character hit: shape/collider meta or node names (rig hitboxes) first, then hit height vs body height.
static func character_zone(target: Node, collider: Object, hit: Dictionary, hp: Vector3) -> StringName:
	var co := collider as CollisionObject3D
	if co != null:
		if co.has_meta(&"zone"):
			return StringName(co.get_meta(&"zone"))
		if hit.has("shape"):
			var owner_id := co.shape_find_owner(int(hit["shape"]))
			if owner_id >= 0:
				var sn := co.shape_owner_get_owner(owner_id) as Node
				if sn != null:
					if sn.has_meta(&"zone"):
						return StringName(sn.get_meta(&"zone"))
					var nm := String(sn.name).to_lower()
					if nm.contains("head") or nm.contains("neck"):
						return GC.ZONE_HEAD
					if nm.contains("leg") or nm.contains("arm") or nm.contains("foot") or nm.contains("hand") or nm.contains("limb"):
						return GC.ZONE_LIMB
					if nm.contains("torso") or nm.contains("chest") or nm.contains("spine") or nm.contains("body"):
						return GC.ZONE_TORSO
		var cn := String(co.name).to_lower()
		if cn.contains("head"):
			return GC.ZONE_HEAD
	var t3 := target as Node3D
	if t3 == null:
		return GC.ZONE_TORSO
	var h := 1.8
	var bh = target.get("body_height")
	if bh != null:
		h = float(bh)
	elif target.get("is_crouching") == true:
		h = 1.3
	var rel := hp.y - t3.global_position.y
	if rel > h * 0.82:
		return GC.ZONE_HEAD
	if rel < h * 0.48:
		return GC.ZONE_LIMB
	return GC.ZONE_TORSO


## Zone for a vehicle hit: tire near a wheel node, glass above the beltline (sides/front/back, not the roof),
## engine in the front third at hood height, otherwise body.
static func vehicle_zone(v: Node, hp: Vector3, hn: Vector3) -> StringName:
	var v3 := v as Node3D
	if v3 == null:
		return GC.ZONE_BODY
	var local := v3.to_local(hp)
	# wheels
	var wheels: Array = []
	if v.has_meta(&"_wheel_nodes"):
		wheels = v.get_meta(&"_wheel_nodes")
	else:
		for c in v.find_children("Wheel*", "Node3D", true, false):
			wheels.append(c)
		v.set_meta(&"_wheel_nodes", wheels)
	for w in wheels:
		if is_instance_valid(w) and (w as Node3D).global_position.distance_to(hp) < 0.52 and hp.y < (w as Node3D).global_position.y + 0.3:
			return GC.ZONE_TIRE
	var bb: AABB
	if v.has_meta(&"_aabb"):
		bb = v.get_meta(&"_aabb")
	else:
		bb = Util.local_aabb(v3)
		v.set_meta(&"_aabb", bb)
	if bb.size.y < 0.1:
		return GC.ZONE_BODY
	var belt := bb.position.y + bb.size.y * 0.5
	if local.y > belt + 0.08 and absf(hn.y) < 0.6:
		return GC.ZONE_GLASS
	if local.y > belt - 0.35 and local.z < bb.position.z + bb.size.z * 0.34 and hn.y > 0.2:
		return GC.ZONE_ENGINE
	return GC.ZONE_BODY
