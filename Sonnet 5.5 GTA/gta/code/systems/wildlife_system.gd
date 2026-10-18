class_name WildlifeSystem
extends Node
## Wildlife: region based land / air animals (deer herds, boar, coyotes, rabbits, crows, gulls, cats, dogs, cows), fish schools (MultiMesh),
## sharks and the sea-floor dressing (UnderwaterWorld). Registered as Game.sys(&"wildlife"); Game.cheats["wildlife"] switches it off live.
## Docs: docs/api/wildlife_underwater.md. One loop ticks everything (no per-animal _process); tiers: near < 58 m full limbs + obstacle rays,
## mid < 112 m reduced rates and no limb animation, far = despawned (pooled).

signal animal_spawned(animal: Animal)
signal animal_killed(animal: Animal, killer: Node)

const WILD_TICK_BUDGET_US := 1500

var enabled := true
var auto_population := true
var w := WildlifeWorld.new()
var root: Node3D = null
var animals: Array[Animal] = []
var pool: Dictionary = {}
var fish: UnderwaterFish = null
var uw: UnderwaterWorld = null
var instant_fill := 0.0
var land_cap := WildlifeDefs.CAP_LAND
var stats := {"spawned": 0, "despawned": 0, "killed": 0, "tick_us": 0.0, "land": 0, "birds": 0, "sharks": 0, "fish": 0, "created": 0}

var _frames := 0
var _scare_id := 0
var _t_pop := 0.0
var _t_tier := 0.0
var _t_veh := 0.0
var _t_marine := 0.0
var _t_fish := 0.0
var _last_player := Vector3.INF
var _prof_acc := 0.0
var _prof_n := 0
var _treasure_done := false
var _herd_id := 0
var _cheat_off_applied := false


func setup(_main: Node) -> void:
	add_to_group(GC.G_SYSTEM)
	var holder: Node = Game.world if Game.world != null else self
	root = Node3D.new()
	root.name = "Wildlife"
	holder.add_child(root)
	w.on_voice = Callable(self, "_play_voice")
	Events.gunshot.connect(_on_gunshot)
	Events.explosion.connect(_on_explosion)


func post_setup() -> void:
	pass


# =====================================================================================================================
# public API
# =====================================================================================================================
func get_animals() -> Array[Animal]:
	return animals


func active_count() -> int:
	var n := 0
	for a in animals:
		if not a.is_dead and a.kind != &"swim":
			n += 1
	return n


func count_species(sp: StringName, alive_only: bool = true) -> int:
	var n := 0
	for a in animals:
		if a.sp == sp and (not alive_only or not a.is_dead):
			n += 1
	return n


func despawn_all() -> void:
	for a in animals.duplicate():
		release(a)
	if fish != null:
		fish.clear()


func reset() -> void:
	despawn_all()


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		despawn_all()


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	despawn_all()
	instant_fill = 1.6


## Spawns one animal (opts: yaw, variant, perched, flying, herd Array, home). Returns null when the species is unknown.
func spawn_animal(sp: StringName, pos: Vector3, opts: Dictionary = {}) -> Animal:
	var a := _acquire(sp, int(opts.get("variant", randi())))
	if a == null:
		return null
	var yaw := float(opts.get("yaw", w.rng.randf() * TAU))
	a.place(pos, yaw)
	a.region = WildlifeRegions.classify(pos.x, pos.z)
	a.home = pos
	a.tier = 0
	a.ground_off = 0.0
	if a.kind == &"land":
		a.ground_off = 0.0
		a.pos.y = WorldLayout.terrain_height(pos.x, pos.z) + 0.02 if not opts.has("keep_y") else pos.y
		if w.space != null:
			WildlifeBrain.refresh_ground(a, w)
		WildlifeBrain.set_state(a, WildlifeBrain.S_IDLE, w.rng.randf_range(0.5, 4.0))
	elif a.kind == &"bird":
		if bool(opts.get("flying", false)):
			a.set_model_variant(0)
			a.fly_alt = w.rng.randf_range(7.0, 16.0)
			a.pos.y = maxf(WorldLayout.terrain_height(pos.x, pos.z), GC.WATER_LEVEL) + a.fly_alt
			WildlifeBrain.set_state(a, WildlifeBrain.S_FLY, w.rng.randf_range(10.0, 30.0))
			a.speed = float(a.def.get("fly", 8.0))
			a.want_speed = a.speed
			a.goal = WildlifeBrain._bird_goal(a, w)
			a.flap_amp = 0.3
		else:
			WildlifeBrain.land_bird_on(a, pos)
			a.dur = w.rng.randf_range(1.0, 6.0)
	elif a.kind == &"swim":
		a.pos.y = pos.y
		a.aux = pos.y
		WildlifeBrain.set_state(a, WildlifeBrain.S_SWIM, w.rng.randf_range(8.0, 20.0))
		a.goal = Vector3.INF
		a.turn_rate = 1.2
		a.speed = float(a.def["walk"])
		a.want_speed = a.speed
	a.write_transform()
	a.think_t = w.rng.randf() * 0.3
	if opts.has("herd"):
		a.herd = opts["herd"]
	a.next_voice = w.now + w.rng.randf_range(4.0, 25.0)
	animals.append(a)
	a.set_active(true)
	stats["spawned"] += 1
	animal_spawned.emit(a)
	return a


func spawn_group(sp: StringName, center: Vector3, n: int, opts: Dictionary = {}) -> Array:
	var members: Array = []
	var herd: Array = []
	var d := WildlifeDefs.get_def(sp)
	var herdy: bool = bool(d.get("herd", false)) and n > 1
	for i in n:
		var p := center
		if i > 0:
			for k in 6:
				var ang := w.rng.randf() * TAU
				var rr := w.rng.randf_range(1.8, 5.5)
				var q := center + Vector3(cos(ang) * rr, 0.0, sin(ang) * rr)
				if WildlifeBrain.walkable_xz(q.x, q.z) and not WildlifeRegions.tree_near(q.x, q.z, 1.0):
					p = q
					break
		var species := sp
		if sp == &"deer" and i == 0 and bool(opts.get("buck", false)):
			species = &"deer_buck"
		var o := opts.duplicate()
		if herdy:
			o["herd"] = herd
		var a := spawn_animal(species, p, o)
		if a == null:
			continue
		if herdy:
			herd.append(a)
			a.follow_off = Vector2(w.rng.randf_range(-4.0, 4.0), w.rng.randf_range(-4.0, 4.0))
		members.append(a)
	if herdy and members.size() > 0:
		for m in members:
			var an: Animal = m
			an.leader = members[0] if an != members[0] else null
	return members


func spawn_shark(pos: Vector3) -> Animal:
	var a := spawn_animal(&"shark", Vector3(pos.x, minf(pos.y, GC.WATER_LEVEL - 0.4), pos.z))
	if a != null:
		a.home = pos
	return a


func release(a: Animal) -> void:
	if a == null or not is_instance_valid(a):
		return
	animals.erase(a)
	if not a.herd.is_empty():
		a.herd.erase(a)
	for o in animals:
		if o.leader == a:
			o.leader = null
	a.herd = []
	a.leader = null
	a.target = null
	a.set_active(false)
	stats["despawned"] += 1
	var arr: Array = pool.get(a.sp, [])
	if arr.size() < 6:
		arr.append(a)
		pool[a.sp] = arr
	else:
		a.queue_free()


func _acquire(sp: StringName, variant: int) -> Animal:
	var arr: Array = pool.get(sp, [])
	var a: Animal = null
	while not arr.is_empty():
		a = arr.pop_back()
		if is_instance_valid(a):
			break
		a = null
	if a == null:
		a = AnimalModel.create(sp, variant)
		if a == null:
			return null
		stats["created"] += 1
		a.sys = self
		a.set_active(false)
		root.add_child(a)
	_reset(a)
	return a


func _reset(a: Animal) -> void:
	a.is_dead = false
	a.health = a.max_health
	a.collision_layer = GC.L_ANIMAL
	a.state = 0
	a.state_t = 0.0
	a.speed = 0.0
	a.want_speed = 0.0
	a.vy = 0.0
	a.airborne = false
	a.roll_visual = 0.0
	a.pitch_visual = 0.0
	a.slope_pitch = 0.0
	a.gait_amp = 0.0
	a.dead_pose_done = false
	a.death_time = 0.0
	a.killed_by_player = false
	a.target = null
	a.threat_pos = Vector3.INF
	a.goal = Vector3.INF
	a.perch_pos = Vector3.INF
	a.last_scare = _scare_id
	a.leader = null
	a.herd = []
	a.turn_rate = 4.0
	a.bites_left = 2
	a.jaw_open = 0.0
	a.head_pitch = 0.0
	a.neck_pitch = 0.0
	a.head_yaw = 0.0
	a.last_attacker = null
	a.set_fling(Vector3.ZERO)
	a.vroot.position = Vector3.ZERO
	a.vroot.rotation = Vector3.ZERO
	for pd in a.parts_all:
		for n in (pd as Dictionary).values():
			(n as Node3D).rotation = Vector3.ZERO
	if a.kind == &"bird":
		a.set_model_variant(1)


# =====================================================================================================================
# main loop
# =====================================================================================================================
func _physics_process(dt: float) -> void:
	if not WorldLayout.built or Game.world == null or root == null:
		return
	_frames += 1
	if _frames < 45:
		return
	if _frames == 45:
		_late_init()
	var on: bool = enabled and bool(Game.cheats.get("wildlife", true))
	if not on:
		if not _cheat_off_applied:
			_cheat_off_applied = true
			despawn_all()
			if fish != null:
				fish.enabled = false
				fish.visible = false
			if uw != null:
				uw.visible = false
		return
	if _cheat_off_applied:
		_cheat_off_applied = false
		instant_fill = 1.2
		if fish != null:
			fish.enabled = true
			fish.visible = true
		if uw != null:
			uw.visible = true
	var t0 := Time.get_ticks_usec()
	w.now += dt
	w.space = root.get_world_3d().direct_space_state
	_update_world(dt)
	if w.player == null:
		return
	# teleport / respawn => refill instantly around the new position
	if _last_player != Vector3.INF and _last_player.distance_to(w.player_pos) > 90.0:
		instant_fill = 1.6
	_last_player = w.player_pos
	if instant_fill > 0.0:
		instant_fill -= dt
	_t_tier += dt
	if _t_tier >= 0.3:
		_t_tier = 0.0
		_update_tiers()
	_tick_animals(dt)
	_t_pop += dt
	if _t_pop >= (0.12 if instant_fill > 0.0 else 0.5):
		_t_pop = 0.0
		_population_tick()
	_t_marine += dt
	if _t_marine >= 1.0:
		_t_marine = 0.0
		_marine_tick()
	if fish != null:
		fish.update(dt, w)
		_t_fish += dt
		if _t_fish >= (0.3 if instant_fill > 0.0 else 1.4):
			_t_fish = 0.0
			fish.populate(w, instant_fill > 0.0)
		stats["fish"] = fish.visible_fish
	if uw != null:
		uw.update_bubbles(dt, w)
		if not _treasure_done and _frames > 52:
			_treasure_done = true
			uw.place_treasure()
	var us := float(Time.get_ticks_usec() - t0)
	_prof_acc += us
	_prof_n += 1
	if _prof_n >= 30:
		stats["tick_us"] = _prof_acc / float(_prof_n)
		_prof_acc = 0.0
		_prof_n = 0


func _late_init() -> void:
	var t0 := Time.get_ticks_msec()
	WildlifeRegions.build()
	fish = UnderwaterFish.new()
	root.add_child(fish)
	fish.setup()
	uw = UnderwaterWorld.new()
	root.add_child(uw)
	uw.build()
	instant_fill = 2.0
	print("[Wildlife] ready in %d ms: pasture=%s trees=%d perches=%d | seabed %s | fallbacks=%s" % [Time.get_ticks_msec() - t0,
		str(WildlifeRegions.pasture) if WildlifeRegions.has_pasture else "none", WildlifeRegions.tree_count(), WildlifeRegions.perches.size(), str(uw.stats), str(AnimalModel.fallbacks)])


func _update_world(dt: float) -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		w.player = null
		return
	w.player = pl as Node3D
	w.player_pos = (pl as Node3D).global_position
	w.player_in_vehicle = pl.has_method("is_in_vehicle") and pl.is_in_vehicle()
	w.player_vehicle = pl.current_vehicle if w.player_in_vehicle else null
	var vel := Vector3.ZERO
	if w.player_in_vehicle and w.player_vehicle != null and w.player_vehicle.get("linear_velocity") != null:
		vel = w.player_vehicle.linear_velocity
	elif pl.get("velocity") != null:
		vel = pl.velocity
	w.player_vel = vel
	w.player_speed = Vector2(vel.x, vel.z).length()
	w.player_crouch = pl.get("crouching") == true
	w.player_aiming = pl.get("aiming") == true
	w.player_swimming = pl.get("is_swimming") == true
	w.player_underwater = pl.get("head_underwater") == true
	w.player_has_scuba = pl.get("has_scuba") == true
	w.night = Game.is_night()
	w.animals = animals
	# moving vehicles (animals flee fast ones)
	_t_veh += dt
	if _t_veh >= 0.25:
		_t_veh = 0.0
		w.vehicles.clear()
		for v in get_tree().get_nodes_in_group(GC.G_VEHICLE):
			var v3 := v as Node3D
			if v3 == null or not is_instance_valid(v3):
				continue
			var lv = v.get("linear_velocity")
			if lv == null:
				continue
			var spd := Vector2(lv.x, lv.z).length()
			if spd < 1.5 or Util.dist_xz(v3.global_position, w.player_pos) > 150.0:
				continue
			w.vehicles.append({"pos": v3.global_position, "vel": lv, "speed": spd, "node": v3, "boat": v.get("vclass") == GC.VC_BOAT})
		var i := w.scares.size() - 1
		while i >= 0:
			if w.now - float(w.scares[i]["t"]) > 3.0:
				w.scares.remove_at(i)
			i -= 1


func _update_tiers() -> void:
	for a in animals:
		var d := Util.dist_xz(a.pos, w.player_pos)
		a.tier = 0 if d < WildlifeDefs.NEAR else 1
		a.think_every = 0.12 if a.tier == 0 else 0.45
		a.set_shadows(d < 45.0)


func _tick_animals(dt: float) -> void:
	var i := animals.size() - 1
	var budget_end := Time.get_ticks_usec() + 2400
	while i >= 0:
		var a: Animal = animals[i]
		i -= 1
		if not is_instance_valid(a):
			animals.remove_at(i + 1)
			continue
		a.anim_t += dt
		# --- movement ---
		a.move_acc += dt
		var step_ok := a.tier == 0 or a.is_dead and a.airborne or (Engine.get_physics_frames() + a.get_instance_id()) % 3 == 0
		if step_ok:
			var mdt := a.move_acc
			a.move_acc = 0.0
			match a.kind:
				&"land":
					WildlifeBrain.move_land(a, w, mdt)
				&"bird":
					WildlifeBrain.move_bird(a, w, mdt)
				&"swim":
					MarineBrain.move(a, w, mdt)
			if a.xf_dirty:
				a.write_transform()
		# --- decisions ---
		a.think_acc += dt
		a.think_t -= dt
		if a.think_t <= 0.0 and not a.is_dead:
			var tdt := a.think_acc
			a.think_acc = 0.0
			a.think_t = a.think_every * w.rng.randf_range(0.8, 1.25)
			match a.kind:
				&"land":
					WildlifeBrain.think_land(a, w, tdt)
				&"bird":
					WildlifeBrain.think_bird(a, w, tdt)
				&"swim":
					MarineBrain.think(a, w, tdt)
		# --- limbs (near only; the budget protects the frame when many animals are close) ---
		if a.tier == 0 or a.is_dead and not a.dead_pose_done:
			a.anim_acc += dt
			var d := Util.dist_xz(a.pos, w.player_pos)
			var every := 1 if d < 22.0 else 2
			a.anim_skip += 1
			if a.anim_skip >= every and Time.get_ticks_usec() < budget_end:
				a.anim_skip = 0
				AnimalAnim.update(a, a.anim_acc)
				a.anim_acc = 0.0


# =====================================================================================================================
# population
# =====================================================================================================================
func _in_view(p: Vector3) -> bool:
	var cam: Camera3D = Game.gameplay_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return false
	var mid := p + Vector3(0.0, 0.8, 0.0)
	if cam.is_position_behind(mid):
		return false
	var vp := cam.get_viewport()
	var size := vp.get_visible_rect().size
	var sp := cam.unproject_position(mid)
	var mx := size.x * 0.12
	var my := size.y * 0.12
	return not (sp.x < -mx or sp.x > size.x + mx or sp.y < -my or sp.y > size.y + my)


func _population_tick() -> void:
	# ---- despawn ----
	var land := 0
	var birds := 0
	var sharks := 0
	var i := animals.size() - 1
	while i >= 0:
		var a: Animal = animals[i]
		i -= 1
		if not is_instance_valid(a):
			animals.remove_at(i + 1)
			continue
		var d := Util.dist_xz(a.pos, w.player_pos)
		var gone := d > WildlifeDefs.DESPAWN_FAR
		if not gone and d > WildlifeDefs.DESPAWN_HIDDEN and not _in_view(a.pos):
			gone = true
		if a.is_dead and a.death_time > WildlifeDefs.BODY_LIFETIME + 4.0:
			gone = true
		if a.kind == &"swim" and d > 200.0:
			gone = true
		if gone:
			release(a)
			continue
		if not a.is_dead:
			if a.kind == &"land":
				land += 1
			elif a.kind == &"bird":
				birds += 1
			elif a.sp == &"shark":
				sharks += 1
	stats["land"] = land
	stats["birds"] = birds
	stats["sharks"] = sharks
	if not auto_population or w.player == null:
		return
	if land + birds >= land_cap:
		return
	var instant := instant_fill > 0.0
	var rmin := WildlifeDefs.RING_INSTANT_MIN if instant else WildlifeDefs.RING_MIN
	for tries in (8 if instant else 5):
		var p := Util.rand_in_ring(w.player_pos, rmin, WildlifeDefs.RING_MAX, w.rng)
		p.y = WorldLayout.terrain_height(p.x, p.z)
		var region := WildlifeRegions.classify(p.x, p.z)
		if region == &"" or not WildlifeDefs.REGION_TABLE.has(region):
			continue
		var table: Dictionary = WildlifeDefs.REGION_TABLE[region]
		var in_region := 0
		for a2 in animals:
			if a2.region == region and not a2.is_dead:
				in_region += 1
		if in_region >= int(table["target"]):
			continue
		var row := _pick_row(table["rows"])
		if row.is_empty():
			continue
		var sp: StringName = row["sp"]
		if count_species(sp) >= int(row.get("cap", 6)):
			continue
		var n := w.rng.randi_range(int(row["min"]), int(row["max"]))
		n = mini(n, land_cap - land - birds)
		if n <= 0:
			continue
		var d_def := WildlifeDefs.get_def(sp)
		var spawn_pos := p
		var perched := false
		var flying := false
		if d_def.get("kind", &"land") == &"bird":
			var perch := Vector3.INF
			if bool(row.get("perch", false)) and w.rng.randf() < 0.6:
				perch = _perch_in_ring(rmin)
			if perch != Vector3.INF:
				spawn_pos = perch
				perched = true
			else:
				if region == &"beach" or region == &"harbour" or w.rng.randf() < 0.4:
					flying = true
				else:
					# ground bird: stands on the terrain
					pass
			if not perched and not flying and (not WildlifeBrain.walkable_xz(p.x, p.z)):
				continue
		else:
			if not WildlifeBrain.walkable_xz(p.x, p.z) or WildlifeRegions.tree_near(p.x, p.z, 1.2):
				continue
		if not instant and _in_view(spawn_pos if not flying else spawn_pos + Vector3(0.0, 10.0, 0.0)):
			continue
		if d_def.get("kind", &"land") == &"bird":
			for k in n:
				var q := spawn_pos + (Vector3(w.rng.randf_range(-2.5, 2.5), 0.0, w.rng.randf_range(-2.5, 2.5)) if (k > 0 and not perched) else Vector3.ZERO)
				if perched and k > 0:
					var pp := _perch_in_ring(rmin)
					if pp == Vector3.INF:
						break
					q = pp
				spawn_animal(sp, q, {"flying": flying})
		else:
			spawn_group(sp, spawn_pos, n, {"buck": bool(row.get("buck", false))})
		return


func _pick_row(rows: Array) -> Dictionary:
	var total := 0.0
	for r in rows:
		total += float(r["w"]) * (0.4 if w.night and (r["sp"] == &"seagull" or r["sp"] == &"crow") else 1.0)
	var x := w.rng.randf() * total
	for r in rows:
		x -= float(r["w"]) * (0.4 if w.night and (r["sp"] == &"seagull" or r["sp"] == &"crow") else 1.0)
		if x <= 0.0:
			return r
	return rows[rows.size() - 1] if not rows.is_empty() else {}


func _perch_in_ring(rmin: float) -> Vector3:
	var cands: Array[Vector3] = []
	for p in WildlifeRegions.perches:
		var d := Util.dist_xz(p, w.player_pos)
		if d >= rmin and d <= WildlifeDefs.RING_MAX:
			cands.append(p)
	if cands.is_empty():
		return Vector3.INF
	for tries in 4:
		var c: Vector3 = cands[w.rng.randi() % cands.size()]
		var free := true
		for a in animals:
			if a.kind == &"bird" and a.state == WildlifeBrain.S_PERCH and Util.dist_xz(a.pos, c) < 1.0:
				free = false
				break
		if free:
			return c
	return Vector3.INF


func _marine_tick() -> void:
	if w.player == null or not bool(Game.cheats.get("sharks", true)):
		return
	var sharks := 0
	for a in animals:
		if a.sp == &"shark" and not a.is_dead:
			sharks += 1
	var want := 2 if w.player_pos.z > 215.0 else 1
	if sharks >= want or w.player_pos.z < 130.0:
		return
	var p := MarineBrain.pick_spawn(w.player_pos, w.rng, 55.0 if instant_fill <= 0.0 else 30.0, 130.0)
	if p == Vector3.INF:
		return
	if instant_fill <= 0.0 and _in_view(p):
		return
	spawn_shark(p)


# =====================================================================================================================
# events / reactions
# =====================================================================================================================
func _on_gunshot(pos: Vector3, loudness: float, _source: Node) -> void:
	if loudness < 8.0:
		return
	_scare_id += 1
	w.scares.append({"id": _scare_id, "pos": pos, "r": minf(loudness * 0.8, 130.0), "t": w.now})
	if w.scares.size() > 16:
		w.scares.pop_front()


func _on_explosion(pos: Vector3, radius: float, _source: Node) -> void:
	_scare_id += 1
	w.scares.append({"id": _scare_id, "pos": pos, "r": clampf(radius * 7.0, 60.0, 150.0), "t": w.now})


func _on_animal_damaged(a: Animal, _amount: float, info: Dictionary) -> void:
	pass


func _react_hurt(a: Animal, info: Dictionary) -> void:
	var src = info.get("source", null)
	var from: Vector3 = (src as Node3D).global_position if src is Node3D else a.pos - Util.yaw_to_dir(a.yaw)
	a.threat_pos = from
	match a.kind:
		&"land":
			var bite := float(a.def.get("bite", 0.0))
			if bite > 0.0 and src is Node3D and w.rng.randf() < float(a.def.get("bold", 0.0)):
				WildlifeBrain.set_state(a, WildlifeBrain.S_FIGHT, 0.0)
				a.target = src
				a.fight_until = w.now + 9.0
				a.bites_left = 3
				a.bite_cd = 0.3
			else:
				WildlifeBrain.begin_flee(a, w, from, 0.0)
		&"bird":
			WildlifeBrain.take_off(a, w, from)
		&"swim":
			if a.sp == &"shark":
				WildlifeBrain.set_state(a, WildlifeBrain.S_RETREAT, 3.0)
				a.bites_left = maxi(a.bites_left, 1)


func _on_animal_died(a: Animal, killer: Node, _info: Dictionary) -> void:
	stats["killed"] += 1
	animal_killed.emit(a, killer)
	# nearby animals panic
	for o in animals:
		if o != a and not o.is_dead and o.kind == &"land" and Util.dist_xz(o.pos, a.pos) < 35.0:
			WildlifeBrain.begin_flee(o, w, a.pos, w.rng.randf_range(0.1, 0.5), false)
		elif o != a and not o.is_dead and o.kind == &"bird" and Util.dist_xz(o.pos, a.pos) < 25.0 and o.state != WildlifeBrain.S_FLY:
			WildlifeBrain.take_off(o, w, a.pos)
	if a.kind == &"bird":
		a.airborne = true
		a.vy = 0.5
	elif a.kind == &"swim":
		pass


func _play_voice(a: Animal, id: StringName, db: float) -> void:
	if Sfx.has_sound(id):
		Sfx.play_3d(id, a.pos + Vector3(0.0, 1.0, 0.0), db, w.rng.randf_range(0.92, 1.12), 70.0)
