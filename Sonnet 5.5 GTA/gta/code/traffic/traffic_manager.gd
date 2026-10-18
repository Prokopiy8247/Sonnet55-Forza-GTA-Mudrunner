class_name TrafficManager
extends Node
## Civilian traffic (Game.sys(&"traffic")): lane-graph cars with a single _physics_process that ticks every TrafficDriver in
## distance tiers (near < 60 m every frame, mid 60-140 m every 3rd, far every 6th), a spawn ring around the player, recycling,
## ~56 parked cars, signal clock, crash / flee / carjack reactions and the shared obstacle registry (TrafficGrid).
## Booted by Main: setup(main) once in boot order, post_setup() after ALL systems exist (keep both signatures).
## Full documentation: docs/api/traffic.md

const HARD_CAP := 28                 # active full-physics traffic cars (absolute ceiling 40)
const ABS_CAP := 40
const SPAWN_MIN := 90.0              # spawn ring (m from the player)
const SPAWN_MAX := 170.0
const INITIAL_MIN := 45.0
const DESPAWN_DIST := 205.0
const TIER_NEAR := 60.0
const TIER_MID := 140.0
const SEEN_FAR := 260.0              # beyond this a car is never considered "seen" (can always be recycled)
const WRECK_CLEAR_S := 90.0

enum State { WAIT_WORLD, RUNNING }

var enabled := true
var state := State.WAIT_WORLD
var drivers: Array[TrafficDriver] = []
var driver_of: Dictionary = {}          # VehicleBase instance id -> TrafficDriver
var grid := TrafficGrid.new()
var junction := IntersectionManager.new()
var spawner := TrafficSpawner.new()
var parked := ParkedCars.new()
var rng := RandomNumberGenerator.new()
var clock := 0.0                        # traffic / signal clock (seconds of simulated time)
var frame := 0
var orphans: Array = []                 # [{v, t}] vehicles we created but no longer drive (stolen traffic cars, displaced parked cars)
var density_override := -1.0            # >= 0 replaces the computed target (tests / debug)
var cap_override := -1
var ref_pos := Vector3.ZERO             # the player (or camera) position the ring is centred on
var spawn_enabled := true
var stats := {
	"spawned": 0, "recycled": 0, "released": 0, "wrecks_cleared": 0, "stuck_recycled": 0, "tt_collisions": 0, "crashes": 0, "flee": 0,
	"honks": 0, "red_runs": 0, "junction_blocks": 0, "reverse_recoveries": 0, "breakdowns": 0, "parked_live": 0,
	"tick_us_avg": 0.0, "tick_us_max": 0.0, "tick_samples": 0, "active": 0, "target": 0, "avg_speed": 0.0, "drivers_updated": 0,
}

var _main: Node = null
var _next_uid := 1
var _boot_wait := 0
var _spawn_t := 0.0
var _house_t := 0.0
var _orphan_t := 0.0
var _slow_t := 0.0
var _content_mgr: Node = null
var _cam_cached: Camera3D = null
var _seen_q: PhysicsRayQueryParameters3D = null
var _prev_ref := Vector3.ZERO
var _initial_fill := true
var _tick_acc := 0.0
var _breakdown_cd := 90.0
var _last_density_setting := 1.0
var _want_lights := false
var _drv_acc := 0.0
var _retired_reds := 0
var _retired_honks := 0
var _pair_seen: Dictionary = {}
var spike_log: Array[String] = []        # the first ticks that took more than 8 ms (phase breakdown), for tests / profiling


func setup(main: Node) -> void:
	_main = main
	rng.seed = 24681
	add_to_group(GC.G_SYSTEM)
	set_physics_process(true)
	Events.vehicle_collision.connect(_on_vehicle_collision)
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.vehicle_exited.connect(_on_vehicle_exited)
	Events.vehicle_damaged.connect(_on_vehicle_damaged)
	Events.gunshot.connect(_on_gunshot)
	Events.explosion.connect(_on_explosion)


func post_setup() -> void:
	parked.mgr = self
	if OS.get_cmdline_user_args().has("--no-traffic"):
		Game.cheats["traffic"] = false


# =====================================================================================================================
# Main loop
# =====================================================================================================================
func _physics_process(dt: float) -> void:
	if state == State.WAIT_WORLD:
		_boot_wait += 1
		if WorldLayout.built and _boot_wait > 14 and Game.world != null and Game.sys(&"vehicles") != null and is_instance_valid(Game.player):
			_begin()
		return
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	clock += dt
	frame += 1
	_refresh_context(dt)
	var t1 := Time.get_ticks_usec()
	if (frame & 1) == 0:
		_rebuild_grid()
	var t2 := Time.get_ticks_usec()
	_tick_drivers(dt)
	junction.tick(dt, clock)
	var t3 := Time.get_ticks_usec()
	_house_t -= dt
	if _house_t <= 0.0:
		_house_t = 0.25
		_housekeeping(0.25)
	var t4 := Time.get_ticks_usec()
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_tick_spawning()
	var t5 := Time.get_ticks_usec()
	var us := float(t5 - t0)
	if us > 8000.0:
		stats["spikes"] = int(stats.get("spikes", 0)) + 1
		if spike_log.size() < 12:
			spike_log.append("t=%.1f %.1f ms: ctx %d grid %d drivers %d house %d spawn %d" % [clock, us / 1000.0, t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4])
	if us > float(stats["tick_us_max"]):
		stats["tick_us_max"] = us
		stats["worst_phase"] = "ctx %d grid %d drivers %d house %d spawn %d" % [t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4]
	_tick_acc += us
	_drv_acc += float(t3 - t2)
	stats["tick_samples"] += 1
	stats["tick_us_avg"] = _tick_acc / float(stats["tick_samples"])
	stats["drivers_us_avg"] = _drv_acc / float(stats["tick_samples"])


func _begin() -> void:
	if not TrafficNet.ensure():
		return
	state = State.RUNNING
	ref_pos = Game.player.global_position
	_prev_ref = ref_pos
	parked.build(spawner)
	_hook_signal_clock()
	# first fill: parked cars around the start position immediately, traffic over the first second
	parked.populate_all(ref_pos, clock, 40)
	_rebuild_grid()
	print("[Traffic] ready: %d lane points, %d junction chains, %d parked slots" % [WorldLayout.lanes.size(), TrafficNet.chains.size(), parked.slots.size()])


func _hook_signal_clock() -> void:
	if is_instance_valid(_content_mgr):
		return
	var root = CityBuilder.last_root
	if root != null:
		_content_mgr = root.get_node_or_null("ContentManager")
	if _content_mgr != null and _content_mgr.has_method("set_signal_clock"):
		_content_mgr.set_signal_clock(Callable(self, "get_signal_time"))


func get_signal_time() -> float:
	return clock


# ---- context ---------------------------------------------------------------------------------------------------------------
func _refresh_context(dt: float) -> void:
	if is_instance_valid(Game.player):
		ref_pos = Game.player.global_position
	if ref_pos.distance_squared_to(_prev_ref) > 120.0 * 120.0:
		_initial_fill = true           # teleport / respawn: refill quickly
	_prev_ref = ref_pos
	TrafficDriver.g_player_pos = ref_pos
	_slow_t -= dt
	if _slow_t <= 0.0:
		_slow_t = 0.5
		var env = Game.sys(&"environment")
		var lights := false
		if env != null and env.has_method("headlights_wanted"):
			lights = env.headlights_wanted()
		else:
			lights = Game.is_night()
		_want_lights = lights
		TrafficDriver.g_want_lights = lights
		var wet := clampf(Game.wetness, 0.0, 1.0)
		var scale := 1.0 - 0.14 * wet - 0.08 * clampf(Game.rain_intensity, 0.0, 1.0) - 0.16 * clampf(Game.fog_amount, 0.0, 1.0)
		TrafficDriver.g_speed_scale = clampf(scale, 0.68, 1.0)
		TrafficDriver.g_headway_scale = 1.0 + 0.35 * wet + 0.3 * clampf(Game.fog_amount, 0.0, 1.0)
		_last_density_setting = float(Game.settings.get("traffic_density", 1.0))
		_hook_signal_clock()


func _get_cam() -> Camera3D:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null and is_instance_valid(Game.gameplay_camera):
		cam = Game.gameplay_camera
	return cam


## True when the world position can currently be seen by the camera (inside the frustum and not hidden behind world geometry).
func is_seen(p: Vector3) -> bool:
	var cam := _get_cam()
	if cam == null or not cam.is_inside_tree():
		return false
	var q := p + Vector3(0.0, 1.0, 0.0)
	if cam.global_position.distance_squared_to(q) > SEEN_FAR * SEEN_FAR:
		return false
	if not cam.is_position_in_frustum(q):
		return false
	var space := cam.get_world_3d().direct_space_state
	if _seen_q == null:
		_seen_q = PhysicsRayQueryParameters3D.new()
		_seen_q.collision_mask = GC.L_WORLD
	_seen_q.from = cam.global_position
	_seen_q.to = q
	return space.intersect_ray(_seen_q).is_empty()


# ---- registry ---------------------------------------------------------------------------------------------------------------
func _rebuild_grid() -> void:
	grid.clear()
	var rp := ref_pos
	for n in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if not (n is VehicleBase) or not (n as Node).is_inside_tree():
			continue
		var vb := n as VehicleBase
		var p := vb.global_position
		if absf(p.x - rp.x) > 240.0 or absf(p.z - rp.z) > 240.0 or p.y < -30.0:
			continue
		grid.add_vehicle(vb, driver_of.has(vb.get_instance_id()))
	for n in get_tree().get_nodes_in_group(GC.G_PED):
		if not (n is Node3D):
			continue
		var p2 := (n as Node3D).global_position
		if absf(p2.x - rp.x) > 150.0 or absf(p2.z - rp.z) > 150.0:
			continue
		if n.get("is_dead") == true:
			continue
		if n.get("current_vehicle") != null:
			continue
		var vel = n.get("velocity")
		grid.add_ped(n, vel if vel is Vector3 else Vector3.ZERO)
	var pl = Game.player
	if is_instance_valid(pl) and pl.get("current_vehicle") == null:
		var pv = pl.get("velocity")
		grid.add_ped(pl, pv if pv is Vector3 else Vector3.ZERO)
	TrafficDriver.g_siren_idx = grid.sirens


# ---- ticking drivers --------------------------------------------------------------------------------------------------------
func _tick_drivers(_dt: float) -> void:
	var dead := false
	var n := 0
	for d in drivers:
		if d.mode == TrafficDriver.MODE_DEAD:
			dead = true
			continue
		var every := 1
		if d.tier == 1:
			every = 3
		elif d.tier >= 2:
			every = 6
		if every == 1 or (frame + d.stagger) % every == 0:
			var ddt := clock - d.last_update
			d.last_update = clock
			d.update(ddt, clock)
			n += 1
			if d.mode == TrafficDriver.MODE_DEAD:
				dead = true
	stats["drivers_updated"] = n
	if dead:
		for i in range(drivers.size() - 1, -1, -1):
			var d2 := drivers[i]
			if d2.mode == TrafficDriver.MODE_DEAD:
				_retire(d2)


## Removes a dead driver from the books. Cars that someone else drives are forgotten (orphans are cleaned up when far away).
func _retire(d: TrafficDriver) -> void:
	drivers.erase(d)
	_retired_reds += d.red_runs
	_retired_honks += d.honks
	if is_instance_valid(d.v):
		driver_of.erase(d.v.get_instance_id())
	var reason := d.released_reason
	if d.v == null or not is_instance_valid(d.v):
		return
	var v: VehicleBase = d.v
	if reason == "destroyed":
		_free_npc(d)                    # VehicleSystem clears the wreck itself (60 s)
		return
	stats["released"] += 1
	if reason == "recycle" or reason == "far":
		_free_npc(d)
		VehicleFactory.despawn(v)
		return
	add_orphan(v)                       # taken by the player / police / a script, or the driver left


func _free_npc(d: TrafficDriver) -> void:
	var npc := d.npc
	d.npc = null
	if npc == null or not is_instance_valid(npc):
		return
	var v := d.v
	var peds = Game.sys(&"peds")
	if peds != null and peds.has_method("release") and npc.has_method("deactivate"):
		peds.release(npc)               # PedManager: leaves the seat, hides and pools the pedestrian
		return
	if is_instance_valid(v):
		var si := v.get_seat_of(npc)
		if si >= 0:
			v.seats[si]["character"] = null
		if si == 0:
			v.driver = null
	npc.queue_free()


## Recycles a car: frees its driver NPC and returns the vehicle to the pool.
func recycle_driver(d: TrafficDriver, reason: String = "recycle") -> void:
	if d.mode == TrafficDriver.MODE_DEAD:
		return
	d.released_reason = reason
	d.mode = TrafficDriver.MODE_DEAD
	junction.release(d)
	stats["recycled"] += 1
	_retire(d)


# =====================================================================================================================
# Housekeeping (4 Hz): tiers, recycling, wrecks, orphans, breakdowns, parked cars
# =====================================================================================================================
func _housekeeping(dt: float) -> void:
	var cam := _get_cam()
	var cam_pos := cam.global_position if cam != null else ref_pos
	var cheat_off: bool = not bool(Game.cheats.get("traffic", true))
	var speed_sum := 0.0
	var speed_n := 0
	for i in range(drivers.size() - 1, -1, -1):
		var d := drivers[i]
		if d.mode == TrafficDriver.MODE_DEAD or not is_instance_valid(d.v):
			continue
		var p := d.v.global_position
		var dp := Vector2(p.x - ref_pos.x, p.z - ref_pos.z).length()
		var dc := Vector2(p.x - cam_pos.x, p.z - cam_pos.z).length()
		var dist := minf(dp, dc)
		d.tier = 0 if dist < TIER_NEAR else (1 if dist < TIER_MID else 2)
		speed_sum += d.v.get_speed()
		speed_n += 1
		var seen := dist < SEEN_FAR and is_seen(p)
		if cheat_off:
			if not seen or dist > 30.0:
				recycle_driver(d, "recycle")
			continue
		if dist > DESPAWN_DIST and not seen:
			recycle_driver(d, "far")
			continue
		if d.want_recycle:
			if not seen or d.idle_t > 60.0:
				stats["stuck_recycled"] += 1
				recycle_driver(d, "recycle")
				continue
		if d.mode == TrafficDriver.MODE_CRASHED and clock - d.crashed_at > WRECK_CLEAR_S and not seen:
			stats["wrecks_cleared"] += 1
			recycle_driver(d, "recycle")
			continue
		if d.v.global_position.y < -20.0:
			recycle_driver(d, "recycle")
			continue
		if d.box_stall_t > 4.0 and not d.box_block_counted and d.mode == TrafficDriver.MODE_DRIVE and d.stop_reason == TrafficDriver.R_FREE:
			d.box_block_counted = true
			stats["junction_blocks"] += 1
	stats["active"] = drivers.size()
	stats["avg_speed"] = speed_sum / maxf(float(speed_n), 1.0)
	# parked cars
	if parked.mgr == null:
		parked.mgr = self
	var budget := 6 if _initial_fill else 1
	parked.update(ref_pos, clock, budget, true)
	stats["parked_live"] = int(parked.stats["live"])
	# orphans
	_orphan_t -= dt
	if _orphan_t <= 0.0:
		_orphan_t = 2.0
		_clean_orphans()
	# occasional breakdown
	_breakdown_cd -= dt
	if _breakdown_cd <= 0.0:
		_breakdown_cd = rng.randf_range(100.0, 200.0)
		_try_breakdown()
	# aggregate counters that live inside drivers (retired drivers are folded into _retired_*)
	var reds := _retired_reds
	var honks := _retired_honks
	for d3 in drivers:
		reds += d3.red_runs
		honks += d3.honks
	stats["red_runs"] = reds
	stats["honks"] = honks


func add_orphan(v: VehicleBase) -> void:
	if v == null or not is_instance_valid(v):
		return
	for o in orphans:
		if o["v"] == v:
			return
	orphans.append({"v": v, "t": clock})


func _clean_orphans() -> void:
	for i in range(orphans.size() - 1, -1, -1):
		var o: Dictionary = orphans[i]
		var vv = o["v"]
		if vv == null or not is_instance_valid(vv) or not vv.is_inside_tree():
			orphans.remove_at(i)
			continue
		var v: VehicleBase = vv
		if driver_of.has(v.get_instance_id()):
			orphans.remove_at(i)               # a driver picked it up again
			continue
		if v.driver != null or v.is_player_owned or v.is_ai_controlled:
			if v.is_ai_controlled and v.faction == GC.F_POLICE:
				orphans.remove_at(i)
			continue
		if v.has_meta("dealer"):
			orphans.remove_at(i)
			continue
		var d := Vector2(v.global_position.x - ref_pos.x, v.global_position.z - ref_pos.z).length()
		if d > 280.0 and clock - float(o["t"]) > 20.0 and not is_seen(v.global_position):
			orphans.remove_at(i)
			VehicleFactory.despawn(v)


func _try_breakdown() -> void:
	var cands: Array[TrafficDriver] = []
	for d in drivers:
		if d.mode != TrafficDriver.MODE_DRIVE or d.breakdown_t > 0.0 or d.flee_t > 0.0:
			continue
		if d.v == null or not is_instance_valid(d.v):
			continue
		var dist := Vector2(d.v.global_position.x - ref_pos.x, d.v.global_position.z - ref_pos.z).length()
		if dist < 60.0 or dist > 170.0:
			continue
		if d.jn_jid >= 0 or d.stop_reason != TrafficDriver.R_FREE:
			continue
		var cur: int = d.P[d.seg + 1] if d.P.size() > d.seg + 1 else -1
		if cur < 0 or TrafficNet.near_junction[cur] != 0:
			continue
		cands.append(d)
	if cands.is_empty():
		return
	var pick := cands[rng.randi() % cands.size()]
	pick.begin_breakdown(rng.randf_range(45.0, 90.0))
	stats["breakdowns"] += 1


# =====================================================================================================================
# Spawning
# =====================================================================================================================
func get_target_count() -> int:
	if not Game.cheats.get("traffic", true):
		return 0
	if density_override >= 0.0:
		return clampi(int(density_override), 0, ABS_CAP)
	var cap := HARD_CAP if cap_override < 0 else cap_override
	return spawner.target_count(cap, ref_pos, Game.time_of_day, _last_density_setting)


func _tick_spawning() -> void:
	var target := get_target_count()
	stats["target"] = target
	var active := 0
	for d in drivers:
		if d.mode != TrafficDriver.MODE_DEAD:
			active += 1
	if _initial_fill and active >= target:
		_initial_fill = false
	_spawn_t = 0.05 if _initial_fill else (0.12 if active < target * 0.6 else 0.35)
	if not spawn_enabled or active >= target or active >= ABS_CAP:
		return
	var budget := 3 if _initial_fill else 1
	var t_start := Time.get_ticks_usec()
	for k in budget:
		var made := false
		for attempt in 8:
			var idx := _find_spawn_point()
			if idx >= 0:
				made = spawn_at_lane(idx) != null
				if made:
					break
		if not made:
			break
		if Time.get_ticks_usec() - t_start > 7000:
			break                               # spread heavy spawns over frames


func _find_spawn_point() -> int:
	var G: LaneGraph = WorldLayout.lanes
	var rmin := INITIAL_MIN if _initial_fill else SPAWN_MIN
	var travel := Vector3.ZERO
	var pl = Game.player
	if is_instance_valid(pl):
		var pv: Vector3 = Vector3.ZERO
		var cv = pl.get("current_vehicle")
		if cv != null and is_instance_valid(cv):
			pv = (cv as VehicleBase).linear_velocity
		elif pl.get("velocity") is Vector3:
			pv = pl.velocity
		pv.y = 0.0
		if pv.length() > 7.0:
			travel = pv.normalized()
	for tries in 10:
		var cand: Vector3
		if travel != Vector3.ZERO and rng.randf() < 0.5:
			var base_ang := atan2(travel.z, travel.x) + rng.randf_range(-1.1, 1.1)
			var rr := rng.randf_range(maxf(rmin, 100.0), SPAWN_MAX)
			cand = ref_pos + Vector3(cos(base_ang) * rr, 0.0, sin(base_ang) * rr)
		else:
			cand = Util.rand_in_ring(ref_pos, rmin, SPAWN_MAX, rng)
		var idx := G.nearest(cand, Vector3.ZERO, 18.0)
		if idx < 0:
			continue
		if G.kind[idx] == LaneGraph.KIND_CONNECTOR or (G.next[idx] as PackedInt32Array).is_empty():
			continue
		var p: Vector3 = G.positions[idx]
		var dist := Vector2(p.x - ref_pos.x, p.z - ref_pos.z).length()
		if dist < rmin or dist > SPAWN_MAX + 10.0:
			continue
		if G.speed_limit[idx] < 8.0:
			continue                           # alleys
		if TrafficNet.dead_lane[idx] != 0:
			continue                           # cul-de-sac bulbs: the tight U-turn clips fences
		if LaneClearance.get_state(idx) == LaneClearance.BLOCKED:
			continue
		if WorldLayout.is_water(p.x, p.z):
			continue
		var dname: StringName = WorldLayout.district_at(p.x, p.z)
		if rng.randf() > 0.3 + 0.7 * TrafficSpawner.district_factor(dname):
			continue
		if _spawn_blocked(p, G.dirs[idx]):
			continue
		if is_seen(p):
			continue
		return idx
	return -1


## Another vehicle within 20 m of the lane point (ahead / behind / beside) or a recent spawn nearby.
func _spawn_blocked(p: Vector3, dir: Vector3) -> bool:
	for i in grid.count:
		var q: Vector3 = grid.pos[i]
		var dx := q.x - p.x
		var dz := q.z - p.z
		var d2 := dx * dx + dz * dz
		if d2 > 24.0 * 24.0:
			continue
		if grid.kind[i] == TrafficGrid.KIND_PED:
			if d2 < 8.0 * 8.0:
				return true
			continue
		var along := dx * dir.x + dz * dir.z
		var lat := absf(-dx * dir.z + dz * dir.x)
		if lat < 3.0 and along > -22.0 and along < 26.0:
			return true
		if d2 < 12.0 * 12.0:
			return true
	for d in drivers:
		if d.mode != TrafficDriver.MODE_DEAD and clock - d.spawn_time < 2.0 and is_instance_valid(d.v):
			if d.v.global_position.distance_squared_to(p) < 30.0 * 30.0:
				return true
	return false


## Spawns one traffic car at lane point `idx` (public: tests / debug menu / police "get out of the way" hooks).
func spawn_at_lane(idx: int, vehicle_id: StringName = &"") -> VehicleBase:
	var G: LaneGraph = WorldLayout.lanes
	var pos: Vector3 = G.positions[idx]
	var dir: Vector3 = G.dirs[idx]
	var id := vehicle_id
	if id == &"" or not VehicleDefs.has(id):
		id = spawner.pick_vehicle(pos, G.kind[idx], rng)
	var opts := spawner.pick_paint(id, rng)
	opts["ai"] = true
	opts["engine_on"] = true
	opts["headlights"] = _want_lights
	var yaw := Util.dir_to_yaw(dir)
	var _t0 := Time.get_ticks_usec()
	var v := VehicleFactory.spawn(id, Transform3D(Basis(Vector3.UP, yaw), pos), opts)
	var _t1 := Time.get_ticks_usec()
	if v == null:
		return null
	var npc: Node = null
	var peds = Game.sys(&"peds")
	if peds != null and peds.has_method("create_driver"):
		npc = peds.create_driver(v)
		if npc != null and is_instance_valid(npc) and v.driver != npc:
			v.enter(npc, 0)
	var _t2 := Time.get_ticks_usec()
	stats["spawn_factory_us"] = float(stats.get("spawn_factory_us", 0.0)) + float(_t1 - _t0)
	stats["spawn_ped_us"] = float(stats.get("spawn_ped_us", 0.0)) + float(_t2 - _t1)
	stats["spawn_max_us"] = maxf(float(stats.get("spawn_max_us", 0.0)), float(_t2 - _t0))
	var d := TrafficDriver.new()
	d.uid = _next_uid
	_next_uid += 1
	d.stagger = d.uid % 6
	d.npc = npc if (npc != null and is_instance_valid(npc)) else null
	if not d.setup(v, idx, rng, grid, junction, clock):
		if d.npc != null:
			_free_npc(d)
		VehicleFactory.despawn(v)
		return null
	d.last_update = clock
	var sp := d.safe_spawn_speed(minf(float(G.speed_limit[idx]) * d.spd_factor * 0.75, 15.0), clock)
	v.set_velocity(dir * sp)
	drivers.append(d)
	driver_of[v.get_instance_id()] = d
	stats["spawned"] += 1
	return v


# =====================================================================================================================
# Events
# =====================================================================================================================
func _on_vehicle_collision(vehicle: Node, other: Node, impulse: float) -> void:
	if vehicle == null:
		return
	var d: TrafficDriver = driver_of.get(vehicle.get_instance_id(), null)
	if d == null:
		return
	if other is CharacterBase:
		# hit a pedestrian: stop for a moment or drive away in panic
		if impulse > 120.0:
			if rng.randf() < 0.5:
				d.begin_flee(9.0)
				stats["flee"] += 1
			else:
				d.brief_stop(3.0)
		return
	if other == vehicle or other == null:
		if impulse > 3600.0:
			stats["crashes"] += 1
			d.on_collision(other, impulse)
		return
	if impulse > 2800.0:
		stats["crashes"] += 1
		d.on_collision(other, impulse)
		if other is VehicleBase and driver_of.has(other.get_instance_id()):
			var a := mini(vehicle.get_instance_id(), other.get_instance_id())
			var b := maxi(vehicle.get_instance_id(), other.get_instance_id())
			var key := a * 31 + b
			if not _pair_seen.has(key) or clock - float(_pair_seen[key]) > 2.0:
				_pair_seen[key] = clock
				stats["tt_collisions"] += 1
				if _pair_seen.size() > 64:
					_pair_seen.clear()


func _on_vehicle_entered(vehicle: Node, character: Node, _seat: int) -> void:
	if vehicle == null:
		return
	var d: TrafficDriver = driver_of.get(vehicle.get_instance_id(), null)
	if d == null:
		return
	if character == d.npc:
		return
	# the player (or any other non-AI character) took the car: forget it, driver reaction is the vehicle's carjack logic
	d.release_control()


func _on_vehicle_exited(vehicle: Node, character: Node) -> void:
	if vehicle == null:
		return
	var d: TrafficDriver = driver_of.get(vehicle.get_instance_id(), null)
	if d == null or character != d.npc:
		return
	# the AI driver was pulled out / killed / ejected: the car is no longer ours
	d.npc = null
	d.release_control()


func _on_vehicle_damaged(vehicle: Node, amount: float, info: Dictionary) -> void:
	if vehicle == null or amount < 1.0:
		return
	var d: TrafficDriver = driver_of.get(vehicle.get_instance_id(), null)
	if d == null:
		return
	var t: StringName = info.get("type", &"")
	if t == GC.DMG_BULLET or t == GC.DMG_EXPLOSION:
		var src: Node = info.get("source", null)
		if src != null and d.flee_t <= 0.0:
			d.begin_flee(18.0)
			stats["flee"] += 1


func _on_gunshot(position: Vector3, loudness: float, source: Node) -> void:
	if drivers.is_empty():
		return
	var r := minf(maxf(loudness, 20.0), 60.0)
	var r2 := r * r
	for d in drivers:
		if d.mode == TrafficDriver.MODE_DEAD or not is_instance_valid(d.v):
			continue
		if d.v.global_position.distance_squared_to(position) > r2:
			continue
		if d.flee_t > 0.0:
			continue
		# the shooter's own car (drive-by) is not ours; others panic with some probability
		if source != null and d.v.driver == source:
			continue
		if rng.randf() < 0.65:
			d.begin_flee(rng.randf_range(10.0, 16.0))
			stats["flee"] += 1


func _on_explosion(position: Vector3, radius: float, _source: Node) -> void:
	var r := maxf(radius * 2.0, 45.0)
	for d in drivers:
		if d.mode == TrafficDriver.MODE_DEAD or not is_instance_valid(d.v):
			continue
		if d.v.global_position.distance_squared_to(position) < r * r and d.flee_t <= 0.0:
			d.begin_flee(14.0)
			stats["flee"] += 1


# =====================================================================================================================
# Public API
# =====================================================================================================================
func get_driver(v: Node) -> TrafficDriver:
	return driver_of.get(v.get_instance_id(), null) if v != null else null


func is_traffic_vehicle(v: Node) -> bool:
	return v != null and driver_of.has(v.get_instance_id())


func get_active_count() -> int:
	return drivers.size()


func get_stats() -> Dictionary:
	var s := stats.duplicate()
	s["junction_grants"] = junction.stats["grants"]
	s["junction_denied"] = junction.stats["denied"]
	s["junction_timeouts"] = junction.stats["timeouts"]
	s["junction_holders"] = junction.holder_count()
	s["orphans"] = orphans.size()
	s["parked_slots"] = parked.slots.size()
	return s


## Makes the traffic car flee for `seconds` (police chases, scripted events).
func make_flee(v: Node, seconds: float = 15.0) -> void:
	var d := get_driver(v)
	if d != null:
		d.begin_flee(seconds)


## Gives up the control of a traffic car without despawning it (police take over, cutscenes ...).
func release_vehicle(v: Node) -> void:
	var d := get_driver(v)
	if d != null:
		d.release_control()


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		clear_traffic()


## Recycles every traffic car (parked cars stay). Used by tests, the debug menu and save loading.
func clear_traffic() -> void:
	for i in range(drivers.size() - 1, -1, -1):
		recycle_driver(drivers[i], "recycle")


func get_parked_vehicles() -> Array[VehicleBase]:
	return parked.live_vehicles()


func get_traffic_vehicles() -> Array[VehicleBase]:
	var out: Array[VehicleBase] = []
	for d in drivers:
		if d.mode != TrafficDriver.MODE_DEAD and is_instance_valid(d.v):
			out.append(d.v)
	return out
