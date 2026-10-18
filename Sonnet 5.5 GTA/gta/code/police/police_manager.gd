class_name PoliceManager
extends Node
## Police DIRECTOR (Police-A). Boot key `police` (Game.sys(&"police")).
## Reads the wanted state (WantedSystem mirrors it in Game.wanted_level / wanted_state), decides how big the response is
## (PoliceDirector.force_table), spawns units through the swappable factory (default: PoliceUnits, Police-B), gives them orders
## (unit.set_order), plans roadblocks ahead of the player (RoadblockPlanner), brings helicopters (PoliceHeliAI, duck-typed) and recycles
## units that are far, idle or no longer needed. Hard caps: <= 10 police vehicles, <= 20 officers, <= 2 helicopters (counted on the
## real `police` group). Nothing here ever spawns inside the camera frustum or closer than 80 m.
##
## Order dictionary handed to unit.set_order():
##   {mode: &"pursue"|&"search"|&"hold"|&"patrol"|&"leave", target: Node, pos: Vector3, radius: float, aggression: 0..1, lethal: bool,
##    role: &"tail"|&"intercept"|&"flank"|&"block"|..., tactic: &"tail"|&"pit"|&"box"|&"intercept"|&"flank"|&"block"|&"close_in"|&"overwatch"}

const THINK_INTERVAL := 0.25
const ORDER_INTERVAL := 1.0
const HOUSE_INTERVAL := 0.5
const SPAWN_STAGGER := 1.4          # seconds between two spawns
const WAVE_INTERVAL := 20.0         # reinforcement waves while the target is known
const SURGE_TIME := 26.0            # after a level change units are topped up without waiting for a wave
const IDLE_RECYCLE := 20.0          # a unit standing still this long out of sight is recycled
const BLOCK_LIFETIME := 80.0
const VAN_CREW := 4                 # PoliceUnits seats up to four officers in a tactical van
const ROADBLOCK_SEARCH_WINDOW := 25.0   # seconds into a SEARCH during which a roadblock may still be built
const BLOCK_CREW := 3               # officers a roadblock brings (2-4)

var director := PoliceDirector.new()
var factory: Variant = null                    # object with the PoliceUnits factory methods; null = PoliceUnits statics
var heli_spawner: Callable = Callable()        # test hook: func(pos: Vector3) -> Node
var manual := false                            # tests: tick(dt) by hand
var units: Dictionary = {}                     # instance id -> record
var enabled := true

var _t := 0.0
var _think_acc := 0.0
var _order_acc := 0.0
var _house_acc := 0.0
var _house_dt := 0.0
var _dirty := true
var _snap: Dictionary = {}
var _last_level := 0
var _response_ready_t := 0.0
var _surge_until := 0.0
var _next_wave_t := 0.0
var _wave_spawned := 0
var _spawn_cd := 0.0
var _block_cd := 0.0
var _heli_cd := 0.0
var _excess_cd := 0.0
var _site_fails := 0
var _first_response := false
var _stand_down := false
var _veh_world := 0
var _off_world := 0
var _heli_world := 0
var _fail_until: Dictionary = {}
var _warned: Dictionary = {}
var _adopt_acc := 0.0
var _investigate_cd := 0.0

var stats := {"spawned_cars": 0, "spawned_vans": 0, "spawned_foot": 0, "spawned_helis": 0, "spawned_blocks": 0, "despawned": 0,
	"orders": 0, "peak_vehicles": 0, "peak_officers": 0, "peak_helis": 0, "waves": 0, "spawn_ms_max": {}}

static var _class_cache: Dictionary = {}


# =====================================================================================================================================
#  Lifecycle
# =====================================================================================================================================
func setup(_main: Node) -> void:
	Events.wanted_changed.connect(_on_wanted_changed)
	Events.player_busted.connect(_on_busted)
	Events.player_respawned.connect(_on_respawned)


func post_setup() -> void:
	# compile the factory scripts at boot instead of in the middle of the first chase (resolving PoliceUnits loads Police-B's classes)
	call_deferred("_prewarm")


func _prewarm() -> void:
	_resolve_script(&"PoliceUnits")
	_resolve_script(&"PoliceHeliAI")


func _physics_process(dt: float) -> void:
	if manual or not enabled:
		return
	tick(dt)


func tick(dt: float) -> void:
	_t += dt
	_spawn_cd = maxf(_spawn_cd - dt, 0.0)
	_house_dt += dt
	_think_acc += dt
	if _think_acc >= THINK_INTERVAL or _dirty:
		_think_acc = 0.0
		_dirty = false
		_think()
	_order_acc += dt
	if _order_acc >= ORDER_INTERVAL:
		_order_acc = 0.0
		_refresh_orders()
	_house_acc += dt
	if _house_acc >= HOUSE_INTERVAL:
		_house_acc = 0.0
		_housekeeping(_house_dt)
		_house_dt = 0.0


func _on_wanted_changed(_level: int, _state: StringName) -> void:
	_dirty = true
	if Game.wanted_level <= 0:
		_stand_down = false


func _on_busted() -> void:
	_stand_down = true
	_dirty = true


func _on_respawned(_pos: Vector3) -> void:
	_stand_down = false
	_dirty = true


# =====================================================================================================================================
#  Public API
# =====================================================================================================================================
## Swap the unit factory (tests / alternative police module). Needs spawn_officer, spawn_patrol_car, spawn_tactical_van,
## spawn_roadblock, despawn. null = PoliceUnits.
func set_factory(obj: Variant) -> void:
	factory = obj
	_fail_until.clear()


## Debug: spawn `count` patrol cars around a point (legal spawn sites only), pinned (not recycled until despawn_all). Returns the nodes.
func spawn_units(count: int, around: Vector3) -> Array:
	var out: Array = []
	_refresh_snapshot()
	for i in count:
		_count_world()
		if _veh_world >= PoliceDirector.MAX_VEHICLES or _off_world + 2 > PoliceDirector.MAX_OFFICERS:
			break
		var req := _site_req(&"flank", false)
		req["center"] = around
		var site := director.find_road_site(req)
		if site.is_empty():
			continue
		var xf := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(site["dir"])), site["pos"])
		var node: Variant = _f_car(xf, 2)
		if node != null:
			var rec := _register(node, &"car", &"debug")
			rec["pinned"] = true
			out.append(node)
	return out


## Removes every unit this manager knows (roadblocks and helicopters included).
func despawn_all() -> void:
	for id in units.keys():
		var rec: Dictionary = units[id]
		var n: Variant = rec.get("node", null)
		if n != null and is_instance_valid(n):
			_f_despawn(n)
			stats["despawned"] = int(stats["despawned"]) + 1
	units.clear()


## Level-0 gunshots / explosions: the nearest free units go and look (no stars involved).
func investigate(pos: Vector3, radius: float = 35.0) -> void:
	if Game.wanted_level > 0 or _t < _investigate_cd:
		return
	_investigate_cd = _t + 4.0
	var best: Array = []
	for id in units:
		var rec: Dictionary = units[id]
		var n: Variant = rec["node"]
		if not is_instance_valid(n) or rec["kind"] in [&"heli", &"roadblock"]:
			continue
		best.append(rec)
	best.sort_custom(func(a, b): return (a["node"] as Node3D).global_position.distance_squared_to(pos) < (b["node"] as Node3D).global_position.distance_squared_to(pos))
	for i in mini(best.size(), 2):
		var n2: Node3D = best[i]["node"]
		if n2.has_method("set_order"):
			n2.call("set_order", {"mode": &"search", "target": null, "pos": pos, "radius": radius, "aggression": 0.2, "lethal": false})


## Registers a police node spawned elsewhere (ambient patrol, Emergency module) so the director can order it.
func register_unit(node: Node, role: StringName = &"external", kind: StringName = &"") -> void:
	if node == null or not is_instance_valid(node):
		return
	var k := kind if kind != &"" else _kind_of(node)
	_register(node, k, role)


func get_units() -> Array:
	var out: Array = []
	for id in units:
		var n: Variant = units[id]["node"]
		if is_instance_valid(n):
			out.append(n)
	return out


func get_records() -> Array:
	return units.values()


## Live counts on the real `police` group plus the registry (caps are enforced on the world counts).
func get_stats() -> Dictionary:
	_count_world()
	var d := stats.duplicate()
	d["vehicles"] = _veh_world
	d["officers"] = _off_world
	d["helis"] = _heli_world
	d["registered"] = units.size()
	d["roadblocks"] = _active_count([&"roadblock"])
	d["site"] = director.stats
	return d


func force_for_level(level: int) -> Dictionary:
	return director.force_for(level, &"pursuit")


# =====================================================================================================================================
#  Thinking: counts, spawning, roadblocks, helicopters
# =====================================================================================================================================
func _refresh_snapshot() -> void:
	var p: Variant = Game.player
	var ppos := Vector3.ZERO
	var pvel := Vector3.ZERO
	var pnode: Node = null
	if p != null and is_instance_valid(p):
		pnode = p
		ppos = (p as Node3D).global_position
		pvel = _velocity_of(p)
	var level := Game.wanted_level
	var state: StringName = Game.wanted_state
	var lk := ppos
	var radius := 80.0
	var w: Variant = Game.sys(&"wanted")
	if w != null:
		if w.has_method("get_last_known_position"):
			lk = w.get_last_known_position()
		if w.has_method("get_search_radius"):
			radius = maxf(float(w.get_search_radius()), 40.0)
	var search_age := 0.0
	if w != null and w.has_method("get_search_age"):
		search_age = float(w.get_search_age())
	_snap = {"level": level, "state": state, "player": pnode, "ppos": ppos, "pvel": pvel, "last_known": lk, "search_radius": radius, "search_age": search_age,
		"stand_down": _stand_down, "force": director.force_for(level, state)}


func _velocity_of(p: Node) -> Vector3:
	var cv: Variant = p.get("current_vehicle")
	if cv != null and is_instance_valid(cv):
		var lv: Variant = cv.get("linear_velocity")
		if lv is Vector3:
			return lv
	var v: Variant = p.get("velocity")
	return v if v is Vector3 else Vector3.ZERO


func _think() -> void:
	if not enabled:
		return
	_refresh_snapshot()
	_count_world()
	stats["peak_vehicles"] = maxi(int(stats["peak_vehicles"]), _veh_world)
	stats["peak_officers"] = maxi(int(stats["peak_officers"]), _off_world)
	stats["peak_helis"] = maxi(int(stats["peak_helis"]), _heli_world)
	var level := int(_snap["level"])
	if level != _last_level:
		_on_level_change(_last_level, level)
		_last_level = level
	if level <= 0:
		_calm_down()
		return
	if _snap["player"] == null:
		return
	var force: Dictionary = _snap["force"]
	_flag_excess(force)
	if _stand_down:
		return
	_spawn_step(force)
	_roadblock_step(force)
	_heli_step(force)


func _on_level_change(old: int, new: int) -> void:
	_dirty = true
	if new > old:
		_surge_until = _t + SURGE_TIME
		_next_wave_t = _t
		_wave_spawned = 0
		_site_fails = 0
		stats["waves"] = int(stats["waves"]) + 1
	if old == 0 and new > 0:
		var lk: Vector3 = _snap["last_known"]
		var station := WorldLayout.get_location(&"police_station")
		var dist := 140.0
		if not station.is_empty():
			dist = Util.dist_xz(station.get("pos", lk), lk)
		var delay := lerpf(2.0, 8.5, clampf(dist / 350.0, 0.0, 1.0)) * (0.7 if new >= 3 else 1.0)
		_response_ready_t = _t + delay
		_first_response = dist >= 100.0 and dist <= 450.0
	if new < old:
		_excess_cd = 0.0


## Counts the real police on the map (caps are enforced on these numbers, whoever spawned the units).
func _count_world() -> void:
	var veh := 0
	var off := 0
	var heli := 0
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if not is_instance_valid(n) or not (n is Node3D) or n.is_queued_for_deletion() or _dead(n):
			continue
		match _kind_of(n):
			&"heli":
				if _counts_as_police_vehicle(n):    # the parked showroom helicopter is no part of the response
					heli += 1
			&"car", &"van":
				if _counts_as_police_vehicle(n):
					veh += 1
			&"foot", &"swat":
				off += 1
	_veh_world = veh
	_off_world = off
	_heli_world = maxi(heli, _active_count([&"heli"], true))


func _spawn_step(force: Dictionary) -> void:
	if _t < _response_ready_t or _spawn_cd > 0.0:
		return
	var surge := _t < _surge_until
	if not surge and _t < _next_wave_t:
		return
	var cars := _active_count([&"car"])
	var vans := _active_count([&"van"])
	var foot := _active_count([&"foot", &"swat"])
	var swat := _active_count([&"swat"])
	var spawned := false
	var attempted := false
	if cars < int(force["cars"]) and _veh_world < PoliceDirector.MAX_VEHICLES and _off_world + 1 <= PoliceDirector.MAX_OFFICERS:
		attempted = true
		spawned = _spawn_car(_next_role())
	elif vans < int(force["vans"]) and _veh_world < PoliceDirector.MAX_VEHICLES and _off_world + VAN_CREW <= PoliceDirector.MAX_OFFICERS:
		attempted = true
		spawned = _spawn_van()
	elif foot < int(force["foot"]) and _off_world < PoliceDirector.MAX_OFFICERS:
		attempted = true
		spawned = _spawn_foot(swat < int(force["swat"]))
	if spawned:
		_spawn_cd = SPAWN_STAGGER
		_site_fails = 0
		if not surge:
			_wave_spawned += 1
			if _wave_spawned >= 2:
				_wave_spawned = 0
				_next_wave_t = _t + WAVE_INTERVAL
				stats["waves"] = int(stats["waves"]) + 1
	elif attempted:
		_spawn_cd = 2.0
	elif not surge and _wave_spawned > 0:
		_wave_spawned = 0
		_next_wave_t = _t + WAVE_INTERVAL


func _next_role() -> StringName:
	var by_role: Dictionary = {}
	for id in units:
		var rec: Dictionary = units[id]
		if rec["kind"] == &"car" and not rec["leaving"] and is_instance_valid(rec["node"]):
			by_role[rec["role"]] = int(by_role.get(rec["role"], 0)) + 1
	return director.pick_role(int(_snap["level"]), by_role)


func _heading() -> Vector3:
	var v: Vector3 = Util.flat(_snap.get("pvel", Vector3.ZERO))
	if v.length() > 3.0:
		return v.normalized()
	var cam := _camera()
	if cam != null:
		var f := Util.flat(-cam.global_transform.basis.z)
		if f.length() > 0.1:
			return f.normalized()
	return Vector3.ZERO


func _camera() -> Camera3D:
	var c: Variant = Game.gameplay_camera
	if c != null and is_instance_valid(c) and c is Camera3D and (c as Camera3D).is_inside_tree():
		return c
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _space() -> PhysicsDirectSpaceState3D:
	var vp := get_viewport()
	if vp == null:
		return null
	var w := vp.find_world_3d()
	return w.direct_space_state if w != null else null


func _unit_positions() -> Array:
	var out: Array = []
	for id in units:
		var n: Variant = units[id]["node"]
		if is_instance_valid(n) and n is Node3D:
			out.append((n as Node3D).global_position)
	return out


func _site_req(role: StringName, allow_station: bool) -> Dictionary:
	var state: StringName = _snap["state"]
	var ppos: Vector3 = _snap["ppos"]
	var center: Vector3 = ppos if state == &"pursuit" else _snap["last_known"]
	var want: StringName = &"any"
	var pref := 130.0
	match role:
		&"tail":
			want = &"behind"
			pref = 115.0
		&"intercept":
			want = &"ahead"
			pref = 190.0
		&"flank":
			want = &"side"
			pref = 140.0
		&"block":
			want = &"ahead"
			pref = 210.0
	return {"center": center, "player": ppos, "camera": _camera(), "space": _space(), "min_dist": PoliceDirector.MIN_SPAWN_DIST,
		"max_dist": 260.0 + 70.0 * float(mini(_site_fails, 3)), "pref_dist": pref, "want": want, "heading": _heading(),
		"avoid": _unit_positions(), "station": allow_station and _first_response}


func _spawn_car(role: StringName) -> bool:
	var req := _site_req(role, true)
	var used_station := bool(req["station"])
	var site := director.find_road_site(req)
	if site.is_empty():
		_site_fails += 1
		return false
	var xf := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(site["dir"])), site["pos"])
	# officer budget (hard cap 20): a car takes two officers unless that would starve the roadblock / foot team reserve, then one
	var crew := 2 if _off_world + 2 + _officer_reserve() <= PoliceDirector.MAX_OFFICERS else 1
	var node: Variant = _f_car(xf, crew)
	if node == null:
		return false
	if used_station:
		_first_response = false
	var rec := _register(node, &"car", role)
	rec["source"] = site.get("source", &"ring")
	stats["spawned_cars"] = int(stats["spawned_cars"]) + 1
	_issue(rec)
	return true


## Officers kept free for the pieces of the response that have not arrived yet: a wanted roadblock (player driving) and the foot team.
func _officer_reserve() -> int:
	var force: Dictionary = _snap.get("force", {})
	var reserve := 0
	var want_blocks := int(force.get("blocks", 0)) - _active_count([&"roadblock"])
	var p: Variant = _snap.get("player", null)
	if want_blocks > 0 and p != null and p.has_method("is_in_vehicle") and p.is_in_vehicle() and _snap.get("state", &"") == &"pursuit":
		reserve += BLOCK_CREW
	var foot_missing := int(force.get("foot", 0)) - _active_count([&"foot", &"swat"])
	reserve += clampi(foot_missing, 0, 3)
	return reserve


func _spawn_van() -> bool:
	var req := _site_req(&"intercept", false)
	var site := director.find_road_site(req)
	if site.is_empty():
		_site_fails += 1
		return false
	var xf := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(site["dir"])), site["pos"])
	var node: Variant = _f_van(xf)
	if node == null:
		return false
	var rec := _register(node, &"van", &"intercept")
	stats["spawned_vans"] = int(stats["spawned_vans"]) + 1
	_issue(rec)
	return true


const FIRST_FOOT_MIN := 45.0
const FIRST_FOOT_MAX := 72.0


func _spawn_foot(heavy: bool) -> bool:
	var req := _site_req(&"any", false)
	req["max_dist"] = 170.0 + 50.0 * float(mini(_site_fails, 3))
	req["center"] = _snap["last_known"]
	var site := {}
	# QA: at 1-2 stars the first officer on foot appears close (45-72 m, still out of view) so he reaches a standing suspect before the
	# wanted level can run out; later units, and every unit when no such site exists, use the normal ring
	if int(_snap["level"]) <= 2 and _active_count([&"foot", &"swat"]) == 0:
		var near_req := req.duplicate()
		near_req["min_dist"] = FIRST_FOOT_MIN
		near_req["max_dist"] = FIRST_FOOT_MAX
		near_req["center"] = _snap["ppos"]
		site = director.find_foot_site(near_req)
	if site.is_empty():
		site = director.find_foot_site(req)
	if site.is_empty():
		_site_fails += 1
		return false
	var xf := Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(site["dir"])), site["pos"])
	var kind: StringName = &"swat" if heavy else &"patrol"
	var node: Variant = _f_officer(kind, xf)
	if node == null:
		return false
	var rec := _register(node, &"swat" if heavy else &"foot", &"foot")
	stats["spawned_foot"] = int(stats["spawned_foot"]) + 1
	_issue(rec)
	return true


func _roadblock_step(force: Dictionary) -> void:
	# roadblocks belong to the hunt, not to a quiet search: the pursuit table decides, and they may still be built during the first
	# seconds of a search (the radio knows where the fast car was heading)
	var want := int(director.force_for(int(_snap["level"]), &"pursuit")["blocks"])
	var hunting: bool = _snap["state"] == &"pursuit" or (_snap["state"] == &"search" and float(_snap.get("search_age", 99.0)) < ROADBLOCK_SEARCH_WINDOW)
	if want <= 0 or not hunting or _t < _block_cd or _t < _response_ready_t + 6.0:
		return
	if _active_count([&"roadblock"]) >= want or _veh_world + 2 > PoliceDirector.MAX_VEHICLES or _off_world + 2 > PoliceDirector.MAX_OFFICERS:
		return
	var pvel: Vector3 = _snap["pvel"]
	var p: Variant = _snap["player"]
	var driving: bool = p != null and p.has_method("is_in_vehicle") and p.is_in_vehicle()
	if not driving or Util.flat(pvel).length() < 6.5:
		return
	var taken: Array = []
	for id in units:
		var rec0: Dictionary = units[id]
		if rec0["kind"] == &"roadblock":
			taken.append(rec0["block_pos"])
	var plan := RoadblockPlanner.plan(WorldLayout.lanes, _snap["ppos"], Util.flat(pvel).normalized(), _camera(), director.rng, _space(), taken)
	if plan.is_empty():
		_block_cd = _t + 4.0
		return
	var node: Variant = _f_roadblock(plan["road_center"], plan["dir"], int(_snap["level"]))
	if node == null:
		_block_cd = _t + 25.0
		return
	var rec := _register(node, &"roadblock", &"block")
	rec["block_pos"] = plan["road_center"]
	rec["block_dir"] = plan["dir"]
	stats["spawned_blocks"] = int(stats["spawned_blocks"]) + 1
	_block_cd = _t + 22.0
	_issue(rec)


func _heli_step(force: Dictionary) -> void:
	var want := int(force["heli"])
	if want <= 0 or _t < _heli_cd or _t < _response_ready_t + 5.0:
		return
	if _active_count([&"heli"]) >= want or _heli_world >= PoliceDirector.MAX_HELIS:
		return
	var ppos: Vector3 = _snap["ppos"]
	var cam := _camera()
	var pos := Vector3.ZERO
	var found := false
	for i in 8:
		var a := director.rng.randf() * TAU
		var cand := ppos + Vector3(cos(a), 0.0, sin(a)) * director.rng.randf_range(230.0, 300.0)
		cand.y = ppos.y + 55.0
		if cam != null and director.visible_to_camera(cam, cand, Vector3(0, 0, -1), null) and i < 7:
			continue
		pos = cand
		found = true
		break
	if not found:
		_heli_cd = _t + 3.0
		return
	var node: Variant = _f_heli(pos)
	if node == null:
		_heli_cd = _t + 30.0
		return
	var rec := _register(node, &"heli", &"air")
	stats["spawned_helis"] = int(stats["spawned_helis"]) + 1
	_heli_cd = _t + 20.0
	_issue(rec)


# =====================================================================================================================================
#  Orders
# =====================================================================================================================================
func _refresh_orders() -> void:
	if _snap.is_empty():
		_refresh_snapshot()
	for id in units.keys():
		var rec: Dictionary = units[id]
		var n: Variant = rec["node"]
		if not is_instance_valid(n):
			continue
		var order := director.make_order(rec, _snap)
		# an order is re-sent when it really changed; search orders restart a unit's route, so they get a long keep-alive
		var keep := 15.0 if order["mode"] == &"search" else 6.0
		var moved := (order["pos"] as Vector3).distance_to(rec["order_pos"]) > 9.0
		var area := absf(float(order.get("radius", 0.0)) - float(rec.get("order_radius", 0.0))) > 14.0
		var lvl_changed := int(order.get("level", 0)) != int(rec.get("order_level", 0))
		var changed: bool = order["mode"] != rec["mode"] or moved or area or lvl_changed or _t - float(rec["order_t"]) > keep
		if changed:
			_send(rec, order)


func _issue(rec: Dictionary) -> void:
	if _snap.is_empty():
		_refresh_snapshot()
	_send(rec, director.make_order(rec, _snap))


func _send(rec: Dictionary, order: Dictionary) -> void:
	var n: Variant = rec["node"]
	if not is_instance_valid(n):
		return
	rec["mode"] = order["mode"]
	rec["order_pos"] = order["pos"]
	rec["order_radius"] = float(order.get("radius", 0.0))
	rec["order_level"] = int(order.get("level", 0))
	rec["order_t"] = _t
	rec["last_order"] = order
	stats["orders"] = int(stats["orders"]) + 1
	if rec["kind"] == &"heli":
		_heli_apply(n, order)
		return
	if (n is CharacterBase) and (n as CharacterBase).is_in_vehicle():
		return    # a seated officer follows his car
	_deliver(n, order)


## unit.set_order (officers, mocks) or the PoliceCarAI the vehicle carries (meta `police_ai`, Police-B: VehicleBase has no set_order).
func _deliver(n: Node, order: Dictionary) -> void:
	if n.has_method("set_order"):
		n.call("set_order", order)
	elif n.has_meta(&"police_ai"):
		var ai: Variant = n.get_meta(&"police_ai")
		if ai != null and is_instance_valid(ai) and ai.has_method("set_order"):
			ai.call("set_order", order)


## PoliceHeliAI.set_mode / set_target live either on the vehicle or on its AI child (Air agent); try both.
func _heli_apply(n: Node, order: Dictionary) -> void:
	var mode: StringName = order["mode"]
	var heli_mode: StringName = &"pursue" if mode == &"pursue" else (&"search" if mode == &"search" else &"patrol")
	var tgt: Variant = order.get("target", null)
	var holders: Array = [n]
	for c in n.get_children():
		holders.append(c)
	var did_mode := false
	var did_target := false
	for h in holders:
		if not did_mode and h.has_method("set_mode"):
			h.call("set_mode", heli_mode)
			did_mode = true
		if not did_target and h.has_method("set_target"):
			h.call("set_target", tgt if tgt != null else _snap.get("player", null))
			did_target = true
	_deliver(n, order)


# =====================================================================================================================================
#  Registry, housekeeping, despawn
# =====================================================================================================================================
func _register(node: Node, kind: StringName, role: StringName) -> Dictionary:
	var id := node.get_instance_id()
	var pos := (node as Node3D).global_position if node is Node3D else Vector3.ZERO
	var rec := {"node": node, "kind": kind, "role": role, "born": _t, "idle": 0.0, "last_pos": pos, "leaving": false, "leave_t": 0.0,
		"mode": &"", "order_t": -99.0, "order_pos": Vector3.ZERO, "pinned": false, "owned": true, "block_pos": pos, "block_dir": Vector3.ZERO,
		"dead_t": -1.0, "source": &""}
	units[id] = rec
	node.set_meta(&"police_director", true)
	return rec


func _active_count(kinds: Array, include_leaving: bool = false) -> int:
	var c := 0
	for id in units:
		var rec: Dictionary = units[id]
		if not (rec["kind"] in kinds):
			continue
		if rec["leaving"] and not include_leaving:
			continue
		var n: Variant = rec["node"]
		if is_instance_valid(n) and not _dead(n):
			c += 1
	return c


func _housekeeping(dt: float) -> void:
	if _snap.is_empty():
		_refresh_snapshot()
	var ppos: Vector3 = _snap["ppos"]
	var level := int(_snap["level"])
	var cam := _camera()
	var space := _space()
	_adopt_acc += dt
	if _adopt_acc >= 1.0:
		_adopt_acc = 0.0
		_adopt_external(level)
	for id in units.keys():
		var rec: Dictionary = units[id]
		var n: Variant = rec["node"]
		if not is_instance_valid(n):
			units.erase(id)
			continue
		var node := n as Node3D
		if node == null:
			units.erase(id)
			continue
		var pos := node.global_position
		var kind: StringName = rec["kind"]
		# dead units: forget them and clean the body later
		if _dead(node):
			if float(rec["dead_t"]) < 0.0:
				rec["dead_t"] = _t
			var age := _t - float(rec["dead_t"])
			var dd := Util.dist_xz(pos, ppos)
			var seen := director.visible_to_camera(cam, pos, -node.global_transform.basis.z, space)
			if bool(rec["owned"]) and ((age > 30.0 and dd > 50.0 and not seen) or (age > 120.0 and dd > 90.0)):
				_f_despawn(node)
				stats["despawned"] = int(stats["despawned"]) + 1
				units.erase(id)
			continue
		var d := Util.dist_xz(pos, ppos)
		# idle tracking
		var moved := pos.distance_to(rec["last_pos"])
		if moved < 1.2 * dt + 0.15:
			rec["idle"] = float(rec["idle"]) + dt
		else:
			rec["idle"] = 0.0
		rec["last_pos"] = pos
		if rec["leaving"]:
			rec["leave_t"] = float(rec["leave_t"]) + dt
		if not bool(rec["owned"]) or bool(rec["pinned"]):
			continue
		if kind == &"roadblock":
			_house_roadblock(id, rec, level, d, cam, space)
			continue
		var seen_now := director.visible_to_camera(cam, pos, -node.global_transform.basis.z, space)
		var remove := false
		if kind == &"heli":
			remove = rec["leaving"] and (d > 330.0 or float(rec["leave_t"]) > 35.0)
		elif rec["leaving"]:
			remove = (not seen_now and d > 60.0) or d > 380.0 or (float(rec["leave_t"]) > 60.0 and not seen_now and d > 30.0)
		elif level > 0:
			# idle recycle and far recycle while the hunt is on
			if float(rec["idle"]) > IDLE_RECYCLE and not seen_now and d > 60.0 and rec["mode"] != &"hold":
				remove = true
			elif d > 300.0 and not seen_now and _t - float(rec["born"]) > 45.0:
				remove = true    # (a station response legitimately starts > 300 m away: it gets 45 s to arrive)
		if remove:
			_f_despawn(node)
			stats["despawned"] = int(stats["despawned"]) + 1
			units.erase(id)


func _house_roadblock(id: int, rec: Dictionary, level: int, d: float, cam: Camera3D, space: PhysicsDirectSpaceState3D) -> void:
	var node := rec["node"] as Node3D
	var bpos: Vector3 = rec["block_pos"]
	var age := _t - float(rec["born"])
	var dist_p := Util.dist_xz(bpos, _snap["ppos"])
	var done: bool = level < 3 or age > BLOCK_LIFETIME or (dist_p > 170.0 and age > 25.0 and _passed(rec))
	if done and not rec["leaving"]:
		rec["leaving"] = true
		_send(rec, director.make_order(rec, _snap))
	if rec["leaving"]:
		rec["leave_t"] = float(rec["leave_t"]) + HOUSE_INTERVAL
		var seen := director.visible_to_camera(cam, bpos, rec["block_dir"], space)
		if (not seen and dist_p > 90.0) or dist_p > 300.0 or float(rec["leave_t"]) > 60.0 and not seen:
			_f_despawn(node)
			stats["despawned"] = int(stats["despawned"]) + 1
			units.erase(id)


## The player is past the roadblock when he is on the far side of it relative to where he came from.
func _passed(rec: Dictionary) -> bool:
	var dirb: Vector3 = rec["block_dir"]
	var rel: Vector3 = _snap["ppos"] - (rec["block_pos"] as Vector3)
	var pv: Vector3 = Util.flat(_snap["pvel"])
	return dirb.length() > 0.1 and pv.length() > 1.0 and rel.dot(pv.normalized()) > 0.0


func _calm_down() -> void:
	for id in units.keys():
		var rec: Dictionary = units[id]
		if bool(rec["pinned"]):
			continue
		var n: Variant = rec["node"]
		if not is_instance_valid(n):
			units.erase(id)
			continue
		if not bool(rec["owned"]):
			if rec["mode"] != &"patrol" and (n as Object).has_method("set_order"):
				rec["mode"] = &"patrol"
				n.call("set_order", {"mode": &"patrol", "target": null, "pos": (n as Node3D).global_position, "radius": 60.0, "aggression": 0.0, "lethal": false})
			continue
		if not rec["leaving"]:
			rec["leaving"] = true
			_send(rec, director.make_order(rec, _snap))
	_stand_down = false


## The level dropped: surplus units start leaving (one every ~2 s, furthest first) so the response fades out instead of vanishing.
func _flag_excess(force: Dictionary) -> void:
	if _t < _excess_cd:
		return
	var plan := {&"car": int(force["cars"]), &"van": int(force["vans"]), &"heli": int(force["heli"]),
		&"roadblock": int(director.force_for(int(_snap["level"]), &"pursuit")["blocks"])}
	var foot_allowed := int(force["foot"])
	var ppos: Vector3 = _snap["ppos"]
	for kind in [&"car", &"van", &"heli", &"roadblock", &"foot"]:
		var allowed: int = foot_allowed if kind == &"foot" else int(plan[kind])
		var list: Array = []
		for id in units:
			var rec: Dictionary = units[id]
			var kinds := [kind] if kind != &"foot" else [&"foot", &"swat"]
			if not (rec["kind"] in kinds) or rec["leaving"] or not bool(rec["owned"]) or bool(rec["pinned"]):
				continue
			if is_instance_valid(rec["node"]) and not _dead(rec["node"]):
				list.append(rec)
		if list.size() <= allowed:
			continue
		list.sort_custom(func(a, b): return Util.dist_xz((a["node"] as Node3D).global_position, ppos) > Util.dist_xz((b["node"] as Node3D).global_position, ppos))
		var victim: Dictionary = list[0]
		victim["leaving"] = true
		_send(victim, director.make_order(victim, _snap))
		_excess_cd = _t + 2.0
		return


func _adopt_external(level: int) -> void:
	if level <= 0:
		return
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if not is_instance_valid(n) or not (n is Node3D) or n.is_queued_for_deletion() or _dead(n):
			continue
		if units.has(n.get_instance_id()) or not (n.has_method("set_order") or n.has_meta(&"police_ai")):
			continue
		if n.has_meta(&"roadblock"):
			continue    # roadblock cars / officers belong to their PoliceRoadblock
		if n is CharacterBase and (n as CharacterBase).is_in_vehicle():
			continue
		var rec := _register(n, _kind_of(n), &"adopted")
		rec["owned"] = false
		_issue(rec)


# =====================================================================================================================================
#  Helpers
# =====================================================================================================================================
## Police vehicles that really take part in the response (not the parked showroom cruiser / a stolen patrol car): ours, driven by the police AI,
## occupied by an officer, or part of a roadblock.
func _counts_as_police_vehicle(n: Node) -> bool:
	if units.has(n.get_instance_id()) or n.has_meta(&"police_ai") or n.has_meta(&"roadblock") or n.has_meta(&"police_kind"):
		return true
	if n.get("is_ai_controlled") == true:
		return true
	var drv: Variant = n.get("driver")
	return drv != null and is_instance_valid(drv) and drv != Game.player


func _dead(n: Variant) -> bool:
	if n == null or not is_instance_valid(n):
		return true
	return n.get("is_dead") == true or n.get("is_destroyed") == true


## &"car" &"van" &"foot" &"swat" &"heli" &"roadblock" &"other" - meta `police_kind` wins (mock units / external spawners).
func _kind_of(n: Node) -> StringName:
	if n.has_meta(&"police_kind"):
		return StringName(n.get_meta(&"police_kind"))
	if n is VehicleBase:
		var vb := n as VehicleBase
		if vb.vclass == GC.VC_HELI:
			return &"heli"
		return &"van" if vb.def_id == &"police_tactical" else &"car"
	if n is CharacterBase:
		return &"foot"
	return &"other"


# ---- factory wrappers (swappable) ----------------------------------------------------------------------------------------------------
func _note_fail(kind: StringName) -> void:
	_fail_until[kind] = _t + 20.0
	if not _warned.has(kind):
		_warned[kind] = true
		print("[Police] factory returned nothing for '%s' (PoliceUnits not implemented yet?) - retrying in 20 s" % kind)


func _blocked(kind: StringName) -> bool:
	return _t < float(_fail_until.get(kind, -1.0))


func _f_car(xf: Transform3D, officers: int) -> Variant:
	if _blocked(&"car"):
		return null
	var r: Variant = _call_units(&"spawn_patrol_car", [xf, officers])
	if r == null:
		_note_fail(&"car")
	return r


func _f_van(xf: Transform3D) -> Variant:
	if _blocked(&"van"):
		return null
	var r: Variant = _call_units(&"spawn_tactical_van", [xf])
	if r == null:
		_note_fail(&"van")
	return r


func _f_officer(kind: StringName, xf: Transform3D) -> Variant:
	if _blocked(&"foot"):
		return null
	var r: Variant = _call_units(&"spawn_officer", [kind, xf])
	if r == null:
		_note_fail(&"foot")
	return r


func _f_roadblock(center: Vector3, dir: Vector3, level: int) -> Variant:
	if _blocked(&"roadblock"):
		return null
	var r: Variant = _call_units(&"spawn_roadblock", [center, dir, level])
	if r == null:
		_note_fail(&"roadblock")
	return r


func _f_despawn(n: Variant) -> void:
	if n == null or not is_instance_valid(n):
		return
	if factory != null:
		factory.despawn(n)
		return
	var scr := _resolve_script(&"PoliceUnits")
	if scr != null:
		scr.call("despawn", n)
	else:
		(n as Node).queue_free()


## Calls a PoliceUnits factory function (Police-B) or the swapped factory. PoliceUnits is resolved by class name at run time so that
## a broken Police-B file can never stop this director from compiling.
func _call_units(fn: StringName, args: Array) -> Variant:
	var t0 := Time.get_ticks_usec()
	var res: Variant = null
	if factory != null:
		res = factory.callv(fn, args)
	else:
		var scr := _resolve_script(&"PoliceUnits")
		if scr != null:
			res = scr.callv(fn, args)
	_note_spawn_cost(fn, Time.get_ticks_usec() - t0)
	return res


## Slowest factory call per kind in milliseconds (stats["spawn_ms_max"]): spawning is the only hitch the director can cause.
func _note_spawn_cost(kind: StringName, usec: int) -> void:
	var d: Dictionary = stats["spawn_ms_max"]
	d[kind] = maxf(float(d.get(kind, 0.0)), float(usec) / 1000.0)


func _f_heli(pos: Vector3) -> Variant:
	if _blocked(&"heli"):
		return null
	var r: Variant = null
	if heli_spawner.is_valid():
		r = heli_spawner.call(pos)
	else:
		var scr := _resolve_script(&"PoliceHeliAI")
		if scr != null:
			var h0 := Time.get_ticks_usec()
			r = scr.call("spawn", pos)
			_note_spawn_cost(&"spawn_heli", Time.get_ticks_usec() - h0)
		elif not _warned.has(&"heli_missing"):
			_warned[&"heli_missing"] = true
			print("[Police] PoliceHeliAI (Air agent) not available: no helicopter support")
	if r == null:
		_note_fail(&"heli")
	return r


## Finds a global script class (class_name) without a static reference, so a missing module never breaks parsing.
static func _resolve_script(cname: StringName) -> Script:
	if _class_cache.has(cname):
		return _class_cache[cname]
	var found: Script = null
	for gc in ProjectSettings.get_global_class_list():
		if String(gc.get("class", "")) == String(cname):
			found = load(String(gc.get("path", ""))) as Script
			if found != null and not found.can_instantiate():
				found = null
			break
	_class_cache[cname] = found
	return found
