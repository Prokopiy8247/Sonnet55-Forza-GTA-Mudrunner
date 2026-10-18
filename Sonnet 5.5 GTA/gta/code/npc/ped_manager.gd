class_name PedManager
extends Node
## NPC population (Game.sys(&"peds")): pooled Pedestrian nodes, spawn ring outside the view, tiers, ONE central scheduler that ticks
## every brain (movement every physics tick, decisions staggered by tier under a time budget), spatial hash for neighbours / witnesses,
## reaction to gunfire / explosions / deaths / crashes, drivers for vehicles, cash drops, corpse clean-up.
## Booted by Main: setup(main) then post_setup(). Public API summary at the bottom of docs/api/pedestrians.md.

signal ped_spawned(ped: Pedestrian)
signal ped_despawned(ped: Pedestrian)
signal ped_killed(ped: Pedestrian, killer: Node)

const HASH_CELL := 4.0
const MAX_POOL := 64

var rng := RandomNumberGenerator.new()
var now := 0.0
var enabled := true
var auto_population := true             # false: no automatic spawn / despawn (tests, cut-scenes); reactions keep working
var rig_lod_override := -1              # >= 0 forces every ped rig to this animation LOD (profiling / tests)
var instant_fill := true                # populate the area at once (also in view) at boot and after a teleport > 90 m (false: tests)
var _instant_until := -1.0
var signal_clock := Callable()           # optional override of the clock used for crossing decisions (tests)
var container: Node3D = null
var spawner: PedSpawner = null

var peds: Array[Pedestrian] = []        # living walkers (pedestrian group)
var drivers: Array[Pedestrian] = []     # living occupants created by create_driver / create_passenger
var dead: Array[Pedestrian] = []        # corpses waiting to fade out
var pool: Array[Pedestrian] = []
var benches: Array = []                 # [{pos: Vector3, yaw: float, ground: float, taken: [false, false]}]
var bus_stops: Array[Vector3] = []

# ---- snapshots used by the brains --------------------------------------------------------------------------------------
var player: Node = null
var player_pos := Vector3.ZERO
var player_vel := Vector3.ZERO
var aim_active := false
var aim_dir := Vector3(0, 0, -1)
var veh := PackedFloat32Array()         # moving vehicles: stride 7 = px pz vx vz speed half_length half_width

var stats := {"spawned": 0, "despawned": 0, "killed": 0, "tick_us": 0.0, "think_us": 0.0, "move_us": 0.0, "thinks": 0,
	"voices": 0, "target": 0, "visible_rejects": 0, "pool": 0, "created": 0}

var _hash: Dictionary = {}
var _t_hash := 0.0
var _t_tier := 0.0
var _t_veh := 0.0
var _t_pop := 0.0
var _t_steps := 0.0
var _t_driver := 0.0
var _rr := 0
var _pending_dead: Array[Pedestrian] = []
var _boot_frames := 0
var _burst_until := 0.0
var _last_pop_player := Vector3.INF
var _voice_last: Dictionary = {}
var _content_mgr: Node = null
var _prof_acc_tick := 0.0
var _prof_n := 0
var _cam_cache: Camera3D = null
var _cam_t := 0.0
var _step_ped := 0
var _combat_patched := false
var _paused_spawns := false


# =====================================================================================================================
# Boot
# =====================================================================================================================
func setup(_main: Node) -> void:
	rng.randomize()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	container = Node3D.new()
	container.name = "Pedestrians"
	if Game.world != null and is_instance_valid(Game.world):
		Game.world.add_child(container)
	else:
		add_child(container)
	spawner = PedSpawner.new(self)
	Events.gunshot.connect(_on_gunshot)
	Events.explosion.connect(_on_explosion)
	Events.character_died.connect(_on_character_died)
	Events.character_damaged.connect(_on_character_damaged)
	Events.vehicle_collision.connect(_on_vehicle_collision)
	Events.vehicle_removed.connect(_on_vehicle_removed)
	Events.vehicle_destroyed.connect(_on_vehicle_destroyed)


func post_setup() -> void:
	# PedManager owns the cash drop of civilians (CashPickup, 20-120 $, 60 %); CombatSystem's generic 30 % civilian drop is switched off
	var combat = Game.sys(&"combat")
	if combat != null and combat.get("drop_cash_chance") is Dictionary:
		(combat.drop_cash_chance as Dictionary)[GC.F_CIVILIAN] = 0.0
		_combat_patched = true
	_boot_frames = 0
	if WorldLayout.built:
		_prepare_world_data()


## Corrects the walking height of ped graph nodes that carry the terrain height instead of the surface above it (piers over the water).
func fix_graph_heights() -> int:
	if container == null or not container.is_inside_tree():
		return 0
	var n := PedNav.fix_heights(container.get_world_3d().direct_space_state)
	if n > 0:
		print("[Peds] corrected the walking height of %d ped graph nodes (pier decks)" % n)
	return n


func _prepare_world_data() -> void:
	PedNav.ensure_obstacles()
	benches.clear()
	bus_stops.clear()
	for f in WorldLayout.furniture:
		var kind: StringName = f.get("kind", &"")
		if kind == &"bench":
			var p: Vector3 = f["pos"]
			benches.append({"pos": p, "yaw": float(f.get("yaw", 0.0)), "ground": p.y, "taken": [false, false]})
		elif kind == &"bus_stop":
			bus_stops.append(f["pos"])


# =====================================================================================================================
# Public API
# =====================================================================================================================
func get_peds() -> Array[Pedestrian]:
	return peds


func active_count() -> int:
	return peds.size()


func get_target_count() -> int:
	return int(stats["target"])


## Living civilian pedestrians (incl. drivers) within `radius` that can see `pos` (field of view + line of sight against the static
## world). Sorted by distance. The perpetrator is never a witness.
func get_witnesses(pos: Vector3, perpetrator: Node = null, radius: float = 45.0) -> Array:
	var out: Array = []
	var cand := query_radius(pos, radius)
	var scored: Array = []
	for c in cand:
		var ped: Pedestrian = c
		if ped == perpetrator or ped.is_dead or not ped.is_active() or ped.is_knocked_down():
			continue
		if ped.faction != GC.F_CIVILIAN:
			continue
		var d := Util.dist_xz(ped.global_position, pos)
		scored.append([d, ped])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var rays := 0
	for e in scored:
		var ped2: Pedestrian = e[1]
		var d2: float = e[0]
		var eye := ped2.get_eye_position()
		# field of view: a ped does not see what is happening behind its back farther than a few metres
		if d2 > 9.0 and not ped2.is_driver:
			var fwd := Util.yaw_to_dir(ped2.brain.heading)
			var to := Vector3(pos.x - eye.x, 0.0, pos.z - eye.z).normalized()
			if fwd.dot(to) < -0.35:
				continue
		if d2 > 11.0 and rays < 14 and ped2.is_inside_tree():
			rays += 1
			if not Util.has_line_of_sight(ped2, eye, pos + Vector3(0, 1.2, 0), GC.M_LOS):
				continue
		out.append(ped2)
	return out


func get_peds_in_radius(pos: Vector3, radius: float) -> Array:
	return query_radius(pos, radius)


func find_nearest_ped(pos: Vector3, max_dist: float = 20.0) -> Pedestrian:
	var best: Pedestrian = null
	var best_d := max_dist
	for c in query_radius(pos, max_dist):
		var ped: Pedestrian = c
		if ped.is_dead:
			continue
		var d := Util.dist_xz(ped.global_position, pos)
		if d < best_d:
			best_d = d
			best = ped
	return best


## Public spawn for other systems (shop staff, test dummies, taxi passengers, gang look-alikes ...).
## kind: &"civilian" (look by district) | a look name (business casual worker beach jogger tourist elder) | &"shop" | &"dummy".
## opts: yaw, role, personality, persistent (never recycled by distance), stationary, variant (Dictionary), node (ped graph index).
func spawn_pedestrian(pos: Vector3, kind: StringName = &"civilian", opts: Dictionary = {}) -> Pedestrian:
	if peds.size() >= PedDefs.CAP_HARD and not bool(opts.get("force", false)):
		return null
	var look := kind
	var role: StringName = opts.get("role", &"walker")
	if kind == &"civilian":
		var d := WorldLayout.district_at(pos.x, pos.z)
		look = spawner.look_for_district(d, -1)
	elif kind == &"shop":
		role = opts.get("role", &"shopkeeper")
	elif kind == &"dummy":
		look = &"casual"
		role = &"dummy"
	var yaw: float = float(opts.get("yaw", rng.randf() * TAU))
	var ped := _spawn(look, role, pos, yaw, opts)
	return ped


## Fills an area with ambient strollers regardless of visibility (screenshots, cut-scenes, stress tests). Returns the new peds.
func spawn_crowd(center: Vector3, radius: float, count: int, look: StringName = &"") -> Array:
	var out: Array = []
	var pg := WorldLayout.ped_graph
	for t in count * 12:
		if out.size() >= count or peds.size() >= PedDefs.CAP_HARD:
			break
		var idx := pg.random_point_in_ring(center, 0.0, radius, rng, 4)
		if idx < 0:
			continue
		var pos := PedNav.node_pos(idx)
		var zone: int = pg.zone[idx]
		if zone == PedGraph.ZONE_CROSSING or PedNav.blocked(pos.x, pos.z, 0.35) or spawner._crowded(pos, 1.4):
			continue
		var d := WorldLayout.district_at(pos.x, pos.z)
		var lk := look if look != &"" else spawner.look_for_district(d, zone)
		var role: StringName = &"jogger" if lk == &"jogger" else &"walker"
		var ped := _spawn(lk, role, pos, rng.randf() * TAU, {"node": idx})
		if ped != null:
			out.append(ped)
	return out


func release(ped: Pedestrian) -> void:
	if ped == null or not is_instance_valid(ped):
		return
	peds.erase(ped)
	drivers.erase(ped)
	dead.erase(ped)
	_pending_dead.erase(ped)
	var was_active := ped.is_active()
	if ped.rig != null and ped.rig.is_ragdoll():
		ped.rig.stop_ragdoll()
	# deactivate FIRST: an inactive ped ignores damage, so leaving a moving car (VehicleBase.exit applies fall damage) is harmless
	ped.deactivate()
	if ped.current_vehicle != null and is_instance_valid(ped.current_vehicle) and ped.current_vehicle.has_method("exit"):
		ped.current_vehicle.exit(ped, false)
	ped.collision_layer = 0
	ped.collision_mask = 0
	ped._driver_exit_at = -1.0
	ped.set_fade(0.0)
	if ped.get_parent() != null:
		ped.get_parent().remove_child(ped)
	if pool.size() < MAX_POOL:
		pool.append(ped)
	else:
		# other systems (traffic grid, audio coroutines ...) may still hold the reference for a frame or two: free it late
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if is_instance_valid(ped) and not ped.is_inside_tree():
				ped.queue_free())
	if was_active:
		stats["despawned"] += 1
		ped_despawned.emit(ped)


func clear_all(include_persistent: bool = true) -> void:
	for ped in peds.duplicate():
		if include_persistent or not ped.persistent:
			release(ped)
	for ped in drivers.duplicate():
		release(ped)
	for ped in dead.duplicate():
		release(ped)


func set_enabled(on: bool) -> void:
	enabled = on


## Creates a pedestrian driver and seats him in the driver seat of `vehicle` (VehicleBase.enter(driver, 0)). Look by vehicle type
## (taxi driver outfit for the taxi, workers for trucks / vans ...). Returns null when the rig cannot be built.
func create_driver(vehicle: Node) -> CharacterBase:
	return create_occupant(vehicle, 0)


## Passenger / rider for any seat (taxi fares, ...). `look` &"" = by vehicle.
func create_occupant(vehicle: Node, seat: int = 0, look: StringName = &"") -> CharacterBase:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.has_method("enter"):
		return null
	var l := look
	if l == &"":
		var did: StringName = vehicle.get("def_id") if vehicle.get("def_id") != null else &""
		var vc: StringName = vehicle.get("vclass") if vehicle.get("vclass") != null else GC.VC_CAR
		l = PedVariants.look_for_vehicle(did, vc, rng) if seat == 0 else (&"casual" if rng.randf() < 0.6 else &"tourist")
	var ped := _acquire()
	var v := PedVariants.make(l, rng)
	ped.manager = self
	ped.is_driver = true
	ped.dress(v, PedDefs.pick_personality(rng, l), &"driver", rng)
	ped.look = l
	container.add_child(ped)
	ped.activate()
	ped.global_transform = (vehicle as Node3D).global_transform
	if not bool(vehicle.enter(ped, seat)):
		ped.is_driver = false
		release(ped)
		return null
	ped.brain.begin_driving()
	ped.spawn_time = now
	drivers.append(ped)
	ped.reset_physics_interpolation()
	stats["created"] += 1
	return ped


## Another module reports something frightening (a crash, a fire ...): every ped within `radius` that can notice it reacts.
func notify_event(kind: StringName, pos: Vector3, radius: float, severity: float, source: Node = null) -> void:
	for c in query_radius(pos, radius):
		var ped: Pedestrian = c
		var d := Util.dist_xz(ped.global_position, pos)
		ped.notify_threat(kind, pos, severity * (1.0 - 0.6 * d / maxf(radius, 1.0)), source, false)


func notify_neighbors(src: Pedestrian, pos: Vector3, radius: float, kind: StringName, sev: float, source: Node) -> void:
	for c in query_radius(pos, radius):
		var ped: Pedestrian = c
		if ped == src or ped.is_dead or ped.is_driver:
			continue
		var d := Util.dist_xz(ped.global_position, pos)
		ped.notify_threat(kind, pos, sev * (1.0 - 0.5 * d / maxf(radius, 1.0)), source, false)


## Panic spreads to the neighbours (attenuated per hop, stops below 0.28).
func spread_panic(src: Pedestrian, pos: Vector3, sev: float) -> void:
	var s := sev * 0.75
	if s < 0.28:
		return
	for c in query_radius(src.global_position, 11.0):
		var ped: Pedestrian = c
		if ped == src or ped.is_dead or ped.is_driver:
			continue
		var st: int = ped.brain.state
		if st == PedBrain.S.FLEE or st == PedBrain.S.COWER or st == PedBrain.S.KNOCKED or st == PedBrain.S.GETUP:
			continue
		ped.notify_threat(&"contagion", pos, s, src, false)


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


# =====================================================================================================================
# Pool / spawning
# =====================================================================================================================
func _acquire() -> Pedestrian:
	var ped: Pedestrian = null
	while not pool.is_empty():
		ped = pool.pop_back()
		if is_instance_valid(ped):
			break
		ped = null
	if ped == null:
		ped = Pedestrian.new()
		ped.name = "Ped"
		stats["created"] += 1
	return ped


## Dresses + places a walker. look = outfit style, role = initial behaviour tag (spawner decides the actual scene).
func _spawn(look: StringName, role: StringName, pos: Vector3, yaw: float, opts: Dictionary = {}) -> Pedestrian:
	var ped := _acquire()
	var v: Dictionary = opts.get("variant", {})
	if v.is_empty():
		v = PedVariants.make(look, rng)
	var pers_id: StringName = opts.get("personality", PedDefs.pick_personality(rng, look))
	ped.manager = self
	ped.is_driver = false
	ped.persistent = bool(opts.get("persistent", false))
	ped.dress(v, pers_id, role, rng)
	ped.look = look
	ped.spawn_time = now
	ped.think_at = now + rng.randf() * 0.2
	ped.last_think = now
	container.add_child(ped)
	ped.activate()
	ped.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	ped.reset_physics_interpolation()
	var b: PedBrain = ped.brain
	b.heading = yaw
	b.px = pos.x
	b.pz = pos.z
	b.ground_y = pos.y
	if role == &"jogger":
		b.cross_w = 0.12
	if bool(opts.get("stationary", false)) or role == &"shopkeeper" or role == &"dummy":
		b.begin_static(yaw)
	else:
		var node: int = int(opts.get("node", -1))
		if node < 0:
			node = PedNav.nearest_node(pos, 12.0)
		if node >= 0:
			b.begin_walk(node, -1, yaw)
			if not opts.has("node"):
				pass
		else:
			b.begin_static(yaw)
	if role == &"jogger":
		b.speed_goal = ped.jog_speed
	# automatic spawns: the FINAL position (lane offset, scene offsets) must be out of sight too, else the ped is dropped before anyone saw it
	if bool(opts.get("require_hidden", false)) and is_ped_visible(ped.global_position):
		stats["visible_rejects"] += 1
		ped.deactivate()
		release(ped)
		return null
	peds.append(ped)
	stats["spawned"] += 1
	ped_spawned.emit(ped)
	return ped


# =====================================================================================================================
# Per-tick scheduler
# =====================================================================================================================
func _physics_process(dt: float) -> void:
	if not WorldLayout.built:
		return
	var t0 := Time.get_ticks_usec()
	now += dt
	if _boot_frames < 40:
		_boot_frames += 1
		if _boot_frames == 2 and benches.is_empty():
			_prepare_world_data()
		if _boot_frames == 30:
			fix_graph_heights()
		return
	_update_player()
	# ---- movement (every tick, cheap) ----
	var tm := Time.get_ticks_usec()
	for ped in peds:
		ped.brain.move(dt)
	stats["move_us"] = lerpf(float(stats["move_us"]), float(Time.get_ticks_usec() - tm), 0.05)
	# ---- slow services ----
	_t_hash += dt
	if _t_hash >= 0.1:
		_t_hash = 0.0
		_rebuild_hash()
	_t_veh += dt
	if _t_veh >= 0.1:
		_t_veh = 0.0
		_snapshot_vehicles()
	_t_tier += dt
	if _t_tier >= 0.2:
		_t_tier = 0.0
		_update_tiers()
	var tt := Time.get_ticks_usec()
	_run_thinks()
	stats["think_us"] = lerpf(float(stats["think_us"]), float(Time.get_ticks_usec() - tt), 0.05)
	_t_driver += dt
	if _t_driver >= 0.05:
		_tick_drivers(_t_driver)
		_t_driver = 0.0
	_t_pop += dt
	if _t_pop >= 0.4:
		_t_pop = 0.0
		_population_tick()
	_t_steps += dt
	if _t_steps >= 0.066:
		_tick_footsteps(_t_steps)
		_t_steps = 0.0
	_tick_dead()
	if not _pending_dead.is_empty():
		_process_deaths()
	# profiling (rolling average, microseconds)
	var us := float(Time.get_ticks_usec() - t0)
	_prof_acc_tick += us
	_prof_n += 1
	if _prof_n >= 30:
		stats["tick_us"] = _prof_acc_tick / float(_prof_n)
		_prof_acc_tick = 0.0
		_prof_n = 0


func _update_player() -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		player = null
		aim_active = false
		return
	player = pl
	var pp: Vector3 = (pl as Node3D).global_position
	player_pos = pp
	var vel := Vector3.ZERO
	if pl.get("current_vehicle") != null and is_instance_valid(pl.current_vehicle):
		var lv = pl.current_vehicle.get("linear_velocity")
		if lv != null:
			vel = lv
	elif pl.get("velocity") != null:
		vel = pl.velocity
	player_vel = vel
	aim_active = false
	if pl.get("current_vehicle") == null or not is_instance_valid(pl.current_vehicle):
		var w = pl.get("weapons")
		var aiming := false
		if pl.get("aiming") != null:
			aiming = bool(pl.aiming)
		if not aiming and w != null and w.get("is_aiming") != null:
			aiming = bool(w.is_aiming)
		if aiming and w != null and w.has_method("is_firearm_equipped") and w.is_firearm_equipped():
			aim_active = true
			var cam: Camera3D = _camera()
			if cam != null:
				aim_dir = cam.get_aim_forward() if cam.has_method("get_aim_forward") else -cam.global_transform.basis.z
			else:
				aim_dir = -(pl as Node3D).global_transform.basis.z


func _camera() -> Camera3D:
	if Game.gameplay_camera != null and is_instance_valid(Game.gameplay_camera):
		return Game.gameplay_camera
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _rebuild_hash() -> void:
	_hash.clear()
	for ped in peds:
		_hash_add(ped)
	for ped in drivers:
		_hash_add(ped)


func _hash_add(ped: Pedestrian) -> void:
	var p := ped.global_position
	ped.hpos = p
	var key := Vector2i(int(floor(p.x / HASH_CELL)), int(floor(p.z / HASH_CELL)))
	var arr = _hash.get(key, null)
	if arr == null:
		_hash[key] = [ped]
	else:
		arr.append(ped)


## Pedestrians (walkers + drivers) within r metres (xz) of pos, from the spatial hash (positions are at most 0.1 s old).
func query_radius(pos: Vector3, r: float) -> Array:
	var out: Array = []
	var x0 := int(floor((pos.x - r) / HASH_CELL))
	var x1 := int(floor((pos.x + r) / HASH_CELL))
	var z0 := int(floor((pos.z - r) / HASH_CELL))
	var z1 := int(floor((pos.z + r) / HASH_CELL))
	var r2 := r * r
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var arr = _hash.get(Vector2i(cx, cz), null)
			if arr == null:
				continue
			for o in arr:
				if not is_instance_valid(o) or not o._active:        # released since the last hash rebuild
					continue
				var dx: float = o.hpos.x - pos.x
				var dz: float = o.hpos.z - pos.z
				if dx * dx + dz * dz <= r2:
					out.append(o)
	return out


func _snapshot_vehicles() -> void:
	veh.resize(0)
	if player == null:
		return
	for n in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		var v := n as RigidBody3D
		if v == null or not v.is_inside_tree():
			continue
		var lv := v.linear_velocity
		var spd := Vector2(lv.x, lv.z).length()
		if spd < 2.2:
			continue
		var gp := v.global_position
		if absf(gp.x - player_pos.x) > 140.0 or absf(gp.z - player_pos.z) > 140.0:
			continue
		var d = v.get("def")
		var hl := 2.2
		var hw := 0.95
		if d is Dictionary:
			hl = float(d.get("length", 4.4)) * 0.5
			hw = float(d.get("width", 1.9)) * 0.5
		veh.append(gp.x)
		veh.append(gp.z)
		veh.append(lv.x)
		veh.append(lv.z)
		veh.append(spd)
		veh.append(hl)
		veh.append(hw)


## True when a moving vehicle is about to pass through / near `pos` (uncontrolled crossings, jaywalking).
func vehicle_threat_near(pos: Vector3, radius: float) -> bool:
	var i := 0
	var n := veh.size()
	while i < n:
		var dx := pos.x - veh[i]
		var dz := pos.z - veh[i + 1]
		var d2 := dx * dx + dz * dz
		if d2 < radius * radius:
			var spd := veh[i + 4]
			var ux := veh[i + 2] / spd
			var uz := veh[i + 3] / spd
			var along := dx * ux + dz * uz
			var lat := absf(-dx * uz + dz * ux)
			# coming towards the point (or already beside it) on a lane that passes within ~6 m
			if along > -4.0 and lat < 6.5 and along < radius:
				return true
		i += 7
	return false


func bus_stop_near(pos: Vector3, r: float) -> bool:
	for b in bus_stops:
		if Util.dist_xz(b, pos) < r:
			return true
	return false


func signal_time() -> float:
	if signal_clock.is_valid():
		return float(signal_clock.call())
	if _content_mgr == null or not is_instance_valid(_content_mgr):
		_content_mgr = null
		if Game.world != null:
			_content_mgr = Game.world.find_child("ContentManager", true, false)
	if _content_mgr != null and _content_mgr.has_method("_signal_time"):
		return float(_content_mgr._signal_time())
	return Time.get_ticks_msec() / 1000.0


func release_bench(idx: int) -> void:
	var b := idx >> 1
	var s := idx & 1
	if b >= 0 and b < benches.size():
		(benches[b]["taken"] as Array)[s] = false


## True when `p` is (about to be) on the player's screen: inside the camera frustum widened by a margin, and not hidden behind the
## static world (line of sight to the camera). Used for spawn / despawn decisions so nobody pops in or out in plain view.
func is_visible_to_player(p: Vector3, check_los: bool = true) -> bool:
	var cam := _camera()
	if cam == null:
		return false
	if cam.is_position_behind(p):
		return false
	var vp := cam.get_viewport()
	if vp == null:
		return false
	var size := vp.get_visible_rect().size
	var sp := cam.unproject_position(p)
	var mx := size.x * 0.16
	var my := size.y * 0.16
	if sp.x < -mx or sp.x > size.x + mx or sp.y < -my or sp.y > size.y + my:
		return false
	if not check_los:
		return true
	var from := cam.global_position
	if from.distance_to(p) > 135.0:
		return false
	return Util.has_line_of_sight(container, from, p, GC.M_LOS)


## True when a pedestrian standing at `p` (feet) could be seen by the player: frustum test (with margin) and line of sight to the feet,
## the hips or the head (a low wall must not hide a ped completely). Used for spawning.
func is_ped_visible(p: Vector3) -> bool:
	var cam := _camera()
	if cam == null:
		return false
	var mid := p + Vector3(0, 1.0, 0)
	if cam.is_position_behind(mid):
		return false
	var vp := cam.get_viewport()
	if vp == null:
		return false
	var size := vp.get_visible_rect().size
	var sp := cam.unproject_position(mid)
	var mx := size.x * 0.16
	var my := size.y * 0.16
	if sp.x < -mx or sp.x > size.x + mx or sp.y < -my or sp.y > size.y + my:
		return false
	var from := cam.global_position
	if from.distance_to(mid) > 135.0:
		return false
	for h in [1.0, 1.75, 0.2]:
		if Util.has_line_of_sight(container, from, p + Vector3(0.0, h, 0.0), GC.M_LOS):
			return true
	return false


# ---- decisions under a time budget --------------------------------------------------------------------------------------
func _update_tiers() -> void:
	var cam := _camera()
	for ped in peds:
		var d := Util.dist_xz(ped.global_position, player_pos)
		ped.tier = 0 if d < PedDefs.NEAR else (1 if d < PedDefs.MID else 2)
		_set_rig_lod(ped, cam)
	for ped in drivers:
		var d2 := Util.dist_xz(ped.global_position, player_pos)
		ped.tier = 0 if d2 < PedDefs.NEAR else (1 if d2 < PedDefs.MID else 2)
		_set_rig_lod(ped, cam)
	for ped in dead:
		if ped.rig != null and ped.rig.is_ragdoll():
			continue


## Animation level of detail: full rate when close and on screen, ~15 Hz mid range, frozen when off screen / far.
func _set_rig_lod(ped: Pedestrian, cam: Camera3D) -> void:
	var r = ped.rig
	if r == null:
		return
	r.auto_lod = false
	if rig_lod_override >= 0:                # tests / profiling
		r.lod = rig_lod_override
		return
	if cam == null:
		r.lod = 0 if ped.tier == 0 else 1
		return
	var cp := cam.global_position
	var gp := ped.global_position
	var d := cp.distance_to(gp)
	ped.set_shadows(d < PedDefs.SHADOW_RANGE and not ped.is_driver)
	if d < 6.0:
		r.lod = 0
	elif not cam.is_position_in_frustum(gp + Vector3(0, 0.9, 0)):
		r.lod = 2
	elif d < 18.0:
		r.lod = 0
	elif d < 60.0:
		r.lod = 1
	else:
		r.lod = 2


func _run_thinks() -> void:
	var n := peds.size()
	if n == 0:
		return
	var end_us := Time.get_ticks_usec() + PedDefs.TICK_BUDGET_US
	var start := _rr % n
	var count := 0
	for k in n:
		var ped := peds[(start + k) % n]
		if ped.think_at > now:
			continue
		var interval := PedDefs.THINK_NEAR if ped.tier == 0 else (PedDefs.THINK_MID if ped.tier == 1 else PedDefs.THINK_FAR)
		var dt := now - ped.last_think
		ped.last_think = now
		ped.think_at = now + interval * rng.randf_range(0.85, 1.15)
		ped.brain.think(dt, now)
		count += 1
		if (count & 3) == 0 and Time.get_ticks_usec() > end_us:
			_rr = (start + k + 1) % n
			break
	stats["thinks"] = count


# ---- drivers --------------------------------------------------------------------------------------------------------------
func _tick_drivers(_dt: float) -> void:
	var i := drivers.size() - 1
	while i >= 0:
		var ped := drivers[i]
		i -= 1
		if not is_instance_valid(ped):
			drivers.erase(ped)
			continue
		if ped.is_dead:
			continue
		var vehicle = ped.current_vehicle
		if vehicle != null and is_instance_valid(vehicle):
			if ped.tier == 0 or ped.tier == 1:
				var st = vehicle.get("input_steer")
				if st != null:
					ped.rig.set_steering(float(st))
		elif ped.driver_exit_due(now):
			_resolve_driver_exit(ped)


func _resolve_driver_exit(ped: Pedestrian) -> void:
	ped._driver_exit_at = -1.0
	if ped.current_vehicle != null:
		return
	var veh_node = ped.get_driver_vehicle()
	var gone: bool = bool(ped.get_meta(&"despawn_with_vehicle", false)) or veh_node == null or not is_instance_valid(veh_node) or not veh_node.is_inside_tree()
	if gone:
		release(ped)
		return
	# ejected (wreck, water ...) or the vehicle was handed over: becomes a scared walker
	on_driver_ejected(ped)
	ped.brain.on_ejected((veh_node as Node3D).global_position)


## A driver turned into a plain pedestrian (carjacked or ejected).
func on_driver_ejected(ped: Pedestrian) -> void:
	drivers.erase(ped)
	if not peds.has(ped):
		peds.append(ped)
	ped.is_driver = false
	ped.add_to_group(GC.G_PED)
	ped.remove_from_group(&"driver")
	ped.role = &"walker"
	ped.think_at = now
	ped.last_think = now


# ---- population ------------------------------------------------------------------------------------------------------------
func _density_target() -> int:
	var d: StringName = WorldLayout.district_at(player_pos.x, player_pos.z)
	if d == GC.D_SEA:
		d = GC.D_BEACH
	var k := PedDefs.density(d, Game.time_of_day)
	# a little bleed from the neighbourhood: never fully empty in the daytime
	k = maxf(k, 0.12 * Game.daylight())
	var setting := float(Game.settings.get("ped_density", 1.0))
	return clampi(int(round(float(PedDefs.CAP_ACTIVE) * k * setting)), 0, PedDefs.CAP_HARD)


func _population_tick() -> void:
	if player == null or not auto_population:
		return
	var on: bool = enabled and bool(Game.cheats.get("pedestrians", true))
	var target := _density_target() if on else 0
	stats["target"] = target
	stats["pool"] = pool.size()
	# boot / a teleport / respawn: the whole area appears at once (also in view), then the ring keeps it filled
	if _last_pop_player == Vector3.INF or _last_pop_player.distance_to(player_pos) > 90.0:
		_burst_until = now + 3.5
		if instant_fill:
			_instant_until = now + PedDefs.INSTANT_FILL_TIME
	_last_pop_player = player_pos
	# ---- despawn ----
	var removed := 0
	var living := peds.size()
	var i := peds.size() - 1
	while i >= 0 and removed < 6:
		var ped := peds[i]
		i -= 1
		if ped.persistent:
			continue
		var d := Util.dist_xz(ped.global_position, player_pos)
		var vis := false
		var must := false
		if not on:
			must = true
		elif d > PedDefs.DESPAWN_FAR:
			must = true
		elif d > PedDefs.DESPAWN_BEHIND:
			must = true
		elif living > target + 6 and d > PedDefs.RING_MIN * 1.25:
			must = true
		if not must:
			continue
		var st: int = ped.brain.state
		if st == PedBrain.S.KNOCKED or st == PedBrain.S.GETUP:
			continue
		vis = on and d < 135.0 and is_visible_to_player(ped.global_position + Vector3(0, 1.0, 0), false)
		if vis and d < PedDefs.DESPAWN_FAR * 1.35:
			continue
		release(ped)
		living -= 1
		removed += 1
	# ---- spawn ----
	if not on or _paused_spawns:
		return
	var have := peds.size()
	if have >= target:
		return
	var instant := now < _instant_until
	var budget := 8 if now < _burst_until or now < 5.0 else PedDefs.MAX_SPAWNS_PER_TICK
	if instant:
		budget = 22
	budget = mini(budget, target - have)
	spawner.fill(budget, instant)


# ---- events ---------------------------------------------------------------------------------------------------------------------
func _on_gunshot(pos: Vector3, loudness: float, source: Node) -> void:
	if not enabled:
		return
	for ped in peds:
		var d := Util.dist_xz(ped.global_position, pos)
		var reach := minf(loudness, 130.0) * float(ped.pers.get("alert", 1.0))
		if d > reach:
			continue
		var sev := 1.0 - 0.75 * d / maxf(reach, 1.0)
		if ped.tier == 2:
			sev *= 0.7
		if d < 12.0:
			sev = maxf(sev, 0.9)
		ped.notify_threat(&"gunshot", pos, sev, source, false)
	for ped in drivers:
		var d2 := Util.dist_xz(ped.global_position, pos)
		if d2 < minf(loudness, 90.0):
			ped.notify_threat(&"gunshot", pos, 0.8, source, false)


func _on_explosion(pos: Vector3, radius: float, source: Node) -> void:
	if not enabled:
		return
	var reach := maxf(radius * 7.0, 70.0)
	for ped in peds:
		var d := Util.dist_xz(ped.global_position, pos)
		if d > reach:
			continue
		var sev := clampf(1.0 - 0.6 * d / reach, 0.5, 1.0)
		if d < radius * 2.0:
			sev = 1.0
		ped.notify_threat(&"explosion", pos, sev, source, d < radius * 1.5)
	for ped in drivers:
		if Util.dist_xz(ped.global_position, pos) < reach:
			ped.notify_threat(&"explosion", pos, 0.9, source, false)


func _on_character_died(character: Node, killer: Node, _info: Dictionary) -> void:
	if not enabled or not (character is Node3D):
		return
	var pos: Vector3 = (character as Node3D).global_position
	var by_player: bool = killer != null and killer.is_in_group(GC.G_PLAYER)
	for c in query_radius(pos, 32.0):
		var ped: Pedestrian = c
		if ped == character or ped.is_dead:
			continue
		var d := Util.dist_xz(ped.global_position, pos)
		var sev := (0.95 if by_player else 0.7) * (1.0 - 0.55 * d / 32.0)
		if d > 14.0 and ped.is_inside_tree() and not Util.has_line_of_sight(ped, ped.get_eye_position(), pos + Vector3(0, 1.0, 0), GC.M_LOS):
			sev *= 0.35
		ped.notify_threat(&"death", pos, sev, killer, false)


func _on_character_damaged(character: Node, amount: float, info: Dictionary) -> void:
	if not enabled or amount < 3.0 or not (character is Node3D) or character is Pedestrian:
		return
	# violence against someone else (the player, police, gang): bystanders get worried
	var src = info.get("source", null)
	var t: StringName = info.get("type", &"")
	if t == GC.DMG_FALL or t == GC.DMG_DROWN or t == GC.DMG_FIRE:
		return
	var pos: Vector3 = (character as Node3D).global_position
	var key := character.get_instance_id()
	var last: float = _voice_last.get(key, -10.0)
	if now - last < 1.2:
		return
	_voice_last[key] = now
	if _voice_last.size() > 160:
		_voice_last.clear()
	for c in query_radius(pos, 18.0):
		var ped: Pedestrian = c
		if ped.is_dead:
			continue
		ped.notify_threat(&"violence", pos, 0.6, src, false)


func _on_vehicle_collision(vehicle: Node, other: Node, _impulse: float) -> void:
	if not enabled or not (vehicle is Node3D):
		return
	var pos: Vector3 = (vehicle as Node3D).global_position
	var sev := 0.5
	if other is Pedestrian:
		sev = 0.85                         # someone was run over
	elif other != null and other is CharacterBase:
		sev = 0.8
	var key := vehicle.get_instance_id() + 7
	var last: float = _voice_last.get(key, -10.0)
	if now - last < 1.5:
		return
	_voice_last[key] = now
	for c in query_radius(pos, 22.0):
		var ped: Pedestrian = c
		if ped.is_dead or ped == other:
			continue
		ped.notify_threat(&"crash", pos, sev, vehicle.get("driver") if vehicle.get("driver") != null else null, false)


func _on_vehicle_removed(vehicle: Node) -> void:
	if vehicle == null or not vehicle.has_method("get_occupants"):
		return
	for o in vehicle.get_occupants():
		if o is Pedestrian:
			(o as Pedestrian).set_meta(&"despawn_with_vehicle", true)


func _on_vehicle_destroyed(vehicle: Node, killer: Node) -> void:
	if not enabled or not (vehicle is Node3D):
		return
	var pos: Vector3 = (vehicle as Node3D).global_position
	for c in query_radius(pos, 30.0):
		var ped: Pedestrian = c
		if not ped.is_dead:
			ped.notify_threat(&"explosion", pos, 0.8, killer, false)


# ---- deaths / corpses ----------------------------------------------------------------------------------------------------------------
func on_ped_died(ped: Pedestrian, info: Dictionary) -> void:
	if not _pending_dead.has(ped):
		_pending_dead.append(ped)
	stats["killed"] += 1
	ped_killed.emit(ped, info.get("source", null))


func _process_deaths() -> void:
	for ped in _pending_dead:
		if not is_instance_valid(ped):
			continue
		peds.erase(ped)
		drivers.erase(ped)
		if not dead.has(ped):
			dead.append(ped)
		ped.death_time = now
		_schedule_cash_drop(ped)
	_pending_dead.clear()
	var excess := dead.size() - PedDefs.MAX_DEAD_BODIES
	if excess > 0:
		# too many corpses: the oldest ones start fading right away
		var sorted := dead.duplicate()
		sorted.sort_custom(func(a: Pedestrian, b: Pedestrian) -> bool: return a.death_time < b.death_time)
		for k in excess:
			var d: Pedestrian = sorted[k]
			d.death_time = minf(d.death_time, now - PedDefs.BODY_LIFETIME)


func _schedule_cash_drop(ped: Pedestrian) -> void:
	if rng.randf() > 0.6:
		return
	var amount := int(round(rng.randf_range(20.0, 120.0)))
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not is_instance_valid(ped):
			return
		var combat = Game.sys(&"combat")
		if combat == null or not combat.has_method("spawn_pickup"):
			return
		var at: Vector3 = ped.rig.get_ragdoll_position() if ped.rig != null else ped.global_position
		at.y = ped.global_position.y
		combat.spawn_pickup(&"cash", at + Vector3(0, 0.15, 0), amount, {"lifetime": 90.0}))


func _tick_dead() -> void:
	if dead.is_empty():
		return
	var i := dead.size() - 1
	while i >= 0:
		var ped := dead[i]
		i -= 1
		if not is_instance_valid(ped):
			dead.erase(ped)
			continue
		var age := now - ped.death_time
		var d := Util.dist_xz(ped.global_position, player_pos)
		if age > PedDefs.BODY_LIFETIME:
			var a := clampf((age - PedDefs.BODY_LIFETIME) / PedDefs.BODY_FADE, 0.0, 1.0)
			ped.set_fade(a)
			if a >= 1.0:
				release(ped)
		elif d > 170.0 and age > 4.0:
			release(ped)


# ---- footsteps --------------------------------------------------------------------------------------------------------------------------
func _tick_footsteps(dt: float) -> void:
	if peds.is_empty() or not Sfx.enabled:
		return
	var played := 0
	var n := peds.size()
	for k in n:
		var ped := peds[(_step_ped + k) % n]
		var b: PedBrain = ped.brain
		if b.speed < 0.7 or ped.tier != 0:
			continue
		var dx := ped.global_position.x - player_pos.x
		var dz := ped.global_position.z - player_pos.z
		if dx * dx + dz * dz > 196.0:
			continue
		b.step_acc += b.speed * dt
		var stride := 1.25 + b.speed * 0.18
		if b.step_acc >= stride:
			b.step_acc -= stride
			if played < 3:
				played += 1
				Sfx.play_3d(_step_sound(b), ped.global_position, -9.0 if b.speed < 3.0 else -5.0, rng.randf_range(0.9, 1.1), 20.0)
	_step_ped = (_step_ped + 7) % maxi(n, 1)


func _step_sound(b: PedBrain) -> StringName:
	if b.n_cur >= 0 and b.n_cur < WorldLayout.ped_graph.size():
		match WorldLayout.ped_graph.zone[b.n_cur]:
			PedGraph.ZONE_PARK:
				return &"step_grass"
			PedGraph.ZONE_BEACH:
				return &"step_sand"
			PedGraph.ZONE_DOCK:
				return &"step_wood"
	return &"step_concrete"


# ---- voices ---------------------------------------------------------------------------------------------------------------------------------
## Rate limited non-verbal voice (scream / gasp / cough) at a ped. Hurt / death voices come from the AudioSystem safety net.
func voice(ped: Pedestrian, id: StringName, vol: float = 1.0) -> void:
	if not Sfx.enabled:
		return
	if Util.dist_xz(ped.global_position, player_pos) > 60.0:
		return
	var last: float = _voice_last.get(id, -10.0)
	if now - last < 0.18:
		return
	_voice_last[id] = now
	var pid := ped.get_instance_id()
	if now - float(_voice_last.get(pid, -10.0)) < 1.3:
		return
	_voice_last[pid] = now
	if _voice_last.size() > 220:
		_voice_last.clear()
	stats["voices"] += 1
	var db := linear_to_db(clampf(vol, 0.05, 1.5)) - 2.0
	Sfx.play_3d(id, ped.global_position + Vector3(0, 1.55, 0), db, ped.voice_pitch, 80.0)
