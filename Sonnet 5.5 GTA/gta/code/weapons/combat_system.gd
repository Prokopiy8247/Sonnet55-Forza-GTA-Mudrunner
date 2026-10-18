class_name CombatSystem
extends Node
## Weapons & combat hub (Main system key "combat" -> Game.sys(&"combat")). Owns:
##   * fx        - FxManager: pooled tracers / shells / impacts / decals / explosions
##   * explode() - radial damage + impulse + FX + sound (also usable by vehicles, barrels, scripted events)
##   * projectiles container, spawn_projectile()
##   * pickups   - WeaponPickup / AmmoPickup / HealthPickup / ArmorPickup / CashPickup spawning, drops from dead NPCs,
##                 a few world pickups at hospital / police station / range
##   * fire patches (burning ground after fuel explosions)
## Static shortcuts work even from code that has no reference to Main: CombatSystem.get_instance(), CombatSystem.get_fx().

static var instance: CombatSystem = null

var fx: FxManager = null
var projectiles_root: Node3D = null
var pickups_root: Node3D = null
var fx_root: Node3D = null

## Dropped-weapon / cash tuning (per faction: chance of dropping the carried firearm, chance of dropping cash).
var drop_weapon_chance := {GC.F_POLICE: 0.55, GC.F_GANG: 0.8, GC.F_CIVILIAN: 0.5, GC.F_MILITARY: 0.8}
var drop_cash_chance := {GC.F_POLICE: 0.0, GC.F_GANG: 0.45, GC.F_CIVILIAN: 0.3, GC.F_MILITARY: 0.0}
var max_dropped := 24
var world_pickups_enabled := true
var debug_log := false

var _pickups: Array[PickupBase] = []
var _clock := 0.0
var _sweep := 0.0
var _fires: Array = []                    # [{pos, radius, until, tick, emitters, light, source}]


static func get_instance() -> CombatSystem:
	return instance if is_instance_valid(instance) else null


static func get_fx() -> FxManager:
	var cs := instance
	if cs != null and is_instance_valid(cs):
		return cs.fx
	return null


func setup(_main: Node) -> void:
	instance = self
	name = "Combat"
	fx_root = Node3D.new()
	fx_root.name = "FxRoot"
	add_child(fx_root)
	fx = FxManager.new()
	fx_root.add_child(fx)
	projectiles_root = Node3D.new()
	projectiles_root.name = "Projectiles"
	add_child(projectiles_root)
	pickups_root = Node3D.new()
	pickups_root.name = "Pickups"
	add_child(pickups_root)
	Events.character_died.connect(_on_character_died)
	set_process(true)


func post_setup() -> void:
	if world_pickups_enabled:
		_scatter_world_pickups.call_deferred()


func _exit_tree() -> void:
	if instance == self:
		instance = null


# =========================================================================================== explosions
## Radial blast. opts: weapon: StringName, force: float (delta-v at the centre, m/s), shake: float, fx: bool, scorch: bool,
## fire: bool (leave a burning patch), ignore: Array[Node], vehicle_mult: float, big: bool.
func explode(pos: Vector3, radius: float, damage: float, source: Node = null, opts: Dictionary = {}) -> Dictionary:
	return Explosion.detonate(self_anchor(), pos, radius, damage, source, opts)


## A Node3D that is inside the world (for physics queries).
func self_anchor() -> Node3D:
	return fx_root


# =========================================================================================== projectiles
## Spawns a projectile node under the projectiles container and returns it.
func spawn_projectile(kind: StringName, def: Dictionary, origin: Vector3, velocity: Vector3, source: Node, opts: Dictionary = {}) -> Projectile:
	var p := Projectile.create(kind, def, origin, velocity, source, opts)
	projectiles_root.add_child(p)
	p.global_position = origin
	return p


# =========================================================================================== pickups
## kind: &"weapon" (opts.weapon), &"ammo" (opts.weapon optional), &"health", &"armor", &"cash".
## opts: respawn: float seconds (world pickups), lifetime: float (dropped), snap: bool (default true: snap to ground).
func spawn_pickup(kind: StringName, pos: Vector3, amount: int = 0, opts: Dictionary = {}) -> PickupBase:
	var p: PickupBase = null
	match kind:
		&"weapon":
			var wp := WeaponPickup.new()
			wp.weapon_id = opts.get("weapon", &"pistol")
			p = wp
			if amount <= 0:
				amount = WeaponDefs.get_def(wp.weapon_id).get("mag_size", 0) * 2
		&"ammo":
			var ap := AmmoPickup.new()
			ap.weapon_id = opts.get("weapon", &"")
			p = ap
		&"health":
			p = HealthPickup.new()
		&"armor":
			p = ArmorPickup.new()
		&"cash":
			p = CashPickup.new()
		_:
			push_warning("CombatSystem.spawn_pickup: unknown kind '%s'" % kind)
			return null
	if amount > 0:
		p.amount = amount
	p.respawn_time = float(opts.get("respawn", 0.0))
	p.lifetime = float(opts.get("lifetime", 0.0))
	pickups_root.add_child(p)
	var gp := pos
	if bool(opts.get("snap", true)):
		gp = _ground_snap(pos)
	p.global_position = gp
	_pickups.append(p)
	p.tree_exiting.connect(_on_pickup_removed.bind(p))
	return p


func spawn_weapon_pickup(weapon_id: StringName, pos: Vector3, ammo: int = -1, opts: Dictionary = {}) -> PickupBase:
	var o := opts.duplicate()
	o["weapon"] = weapon_id
	if ammo < 0:
		ammo = int(WeaponDefs.get_def(weapon_id).get("mag_size", 0)) * 2
	return spawn_pickup(&"weapon", pos, ammo, o)


func _on_pickup_removed(p: PickupBase) -> void:
	_pickups.erase(p)


func _ground_snap(pos: Vector3) -> Vector3:
	if fx_root == null or not fx_root.is_inside_tree():
		return pos
	var space := fx_root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2.0, 0), pos + Vector3(0, -6.0, 0), GC.L_WORLD | GC.L_PROP)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return pos
	return hit["position"]


## Drop of the firearm a dead NPC was carrying (+ some cash). Called from the character_died listener.
func drop_loot(victim, _killer = null) -> void:
	if not is_instance_valid(victim) or victim.is_in_group(GC.G_PLAYER) or not (victim is Node3D):
		return
	if _dropped_count() >= max_dropped:
		_expire_oldest_dropped()
	var origin: Vector3 = (victim as Node3D).global_position
	var faction: StringName = victim.get("faction") if victim.get("faction") != null else GC.F_CIVILIAN
	var w = victim.get("weapons")
	if w != null and randf() < float(drop_weapon_chance.get(faction, 0.4)):
		var best: StringName = &""
		var cur: StringName = w.current_id
		if WeaponDefs.is_firearm(cur) and w.has_weapon(cur) and WeaponDefs.get_def(cur).get("category", &"") != &"thrown":
			best = cur
		else:
			for id in w.get_weapon_ids():
				if WeaponDefs.is_firearm(id) and WeaponDefs.get_def(id).get("category", &"") != &"thrown":
					best = id
					break
		if best != &"":
			var entry: Dictionary = w.inventory.get(best, {})
			var rounds: int = int(entry.get("mag", 0)) + mini(int(entry.get("reserve", 0)), int(WeaponDefs.get_def(best).get("mag_size", 10)))
			rounds = maxi(rounds, int(WeaponDefs.get_def(best).get("mag_size", 10)) / 2)
			w.remove_weapon(best)
			var off := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
			spawn_weapon_pickup(best, origin + off, rounds, {"lifetime": 120.0})
	if randf() < float(drop_cash_chance.get(faction, 0.0)):
		var amt := int(randf_range(12.0, 70.0)) if faction != GC.F_GANG else int(randf_range(40.0, 180.0))
		spawn_pickup(&"cash", origin + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)), amt, {"lifetime": 90.0})


func _on_character_died(character: Node, killer: Node, _info: Dictionary) -> void:
	if character == null or character.is_in_group(GC.G_PLAYER):
		return
	# let the body fall first; the pickup then appears next to it
	get_tree().create_timer(0.6).timeout.connect(drop_loot.bind(character, killer))


func _dropped_count() -> int:
	var n := 0
	for p in _pickups:
		if is_instance_valid(p) and p.lifetime > 0.0:
			n += 1
	return n


func _expire_oldest_dropped() -> void:
	var oldest: PickupBase = null
	for p in _pickups:
		if is_instance_valid(p) and p.lifetime > 0.0 and (oldest == null or p.born_msec < oldest.born_msec):
			oldest = p
	if oldest != null:
		oldest.queue_free()


func _scatter_world_pickups() -> void:
	# wait until the world colliders exist so the ground snap works
	for i in 4:
		await get_tree().physics_frame
	var spots := [
		[&"hospital", &"health", 50, Vector3(6, 0, 4)],
		[&"hospital", &"health", 50, Vector3(-6, 0, 6)],
		[&"police_station", &"armor", 60, Vector3(5, 0, 5)],
		[&"shooting_range", &"ammo", 60, Vector3(3, 0, 2)],
		[&"shooting_range", &"weapon", 0, Vector3(-3, 0, 2), &"pistol"],
		[&"park_center", &"health", 35, Vector3(4, 0, 3)],
		[&"viewpoint", &"armor", 40, Vector3(2, 0, 2)],
		[&"safehouse", &"health", 40, Vector3(4, 0, 6)],
	]
	var count := 0
	for s in spots:
		var id: StringName = s[0]
		if not WorldLayout.has_location(id):
			continue
		var base: Vector3 = WorldLayout.location_pos(id)
		var o := {"respawn": 90.0}
		if s.size() > 4:
			o["weapon"] = s[4]
		var p := spawn_pickup(s[1], base + (s[3] as Vector3), int(s[2]), o)
		if p != null:
			count += 1
	if debug_log:
		print("[Combat] placed %d world pickups" % count)


# =========================================================================================== fire patches
## Burning ground: flames + smoke + damage over time to anything inside (characters, vehicles).
func spawn_fire(pos: Vector3, radius: float, duration: float, source: Node = null) -> void:
	if fx == null:
		return
	if _fires.size() >= 6:
		_end_fire(_fires.pop_front())
	var e1 := fx.acquire_emitter("fire_flame")
	var e2 := fx.acquire_emitter("fire_smoke")
	for e in [e1, e2]:
		if e != null:
			e.global_position = pos + Vector3(0, 0.1, 0)
			e.emission_sphere_radius = radius
			e.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = radius * 4.0 + 3.0
	light.light_energy = 2.5
	light.shadow_enabled = false
	fx_root.add_child(light)
	light.global_position = pos + Vector3(0, 0.8, 0)
	_fires.append({"pos": pos, "radius": radius, "until": _clock + duration, "tick": 0.0, "e1": e1, "e2": e2, "light": light, "source": source})


func _end_fire(f: Dictionary) -> void:
	if fx != null:
		fx.release_emitter(f["e1"])
		fx.release_emitter(f["e2"])
	if is_instance_valid(f["light"]):
		(f["light"] as Node).queue_free()


func _update_fires(delta: float) -> void:
	for i in range(_fires.size() - 1, -1, -1):
		var f: Dictionary = _fires[i]
		if _clock >= float(f["until"]):
			_end_fire(f)
			_fires.remove_at(i)
			continue
		(f["light"] as OmniLight3D).light_energy = 2.0 + sin(_clock * 17.0 + i) * 0.6 + randf() * 0.5
		f["tick"] = float(f["tick"]) - delta
		if float(f["tick"]) <= 0.0:
			f["tick"] = 0.5
			_burn(f)


func _burn(f: Dictionary) -> void:
	var space := fx_root.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = float(f["radius"])
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, (f["pos"] as Vector3) + Vector3(0, 0.6, 0))
	q.collision_mask = GC.M_EXPLOSION
	var seen: Dictionary = {}
	var src: Node = f["source"] if is_instance_valid(f["source"]) else null
	for h in space.intersect_shape(q, 24):
		var tgt := Ballistics.resolve_damageable(h["collider"])
		if tgt == null or seen.has(tgt.get_instance_id()):
			continue
		seen[tgt.get_instance_id()] = true
		var is_veh := tgt.is_in_group(GC.G_VEHICLE)
		tgt.apply_damage(14.0 if is_veh else 7.0, {"source": src, "type": GC.DMG_FIRE, "zone": GC.ZONE_BODY, "position": (tgt as Node3D).global_position,
			"direction": Vector3.UP, "weapon": &"fire", "impulse": 0.0})


# =========================================================================================== per-frame
func _process(delta: float) -> void:
	_clock += delta
	if not _fires.is_empty():
		_update_fires(delta)
	if _pickups.is_empty():
		return
	var pp := Game.get_player_position()
	var has_player := is_instance_valid(Game.player)
	_sweep -= delta
	var do_sweep := _sweep <= 0.0
	if do_sweep:
		_sweep = 2.0
	for p in _pickups:
		if not is_instance_valid(p):
			continue
		if do_sweep and p.is_expired():
			p.queue_free()
			continue
		if has_player and p.global_position.distance_squared_to(pp) < 2025.0:
			p.animate(_clock, delta)
		elif not p.active:
			p.animate(_clock, delta)
