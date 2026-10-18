class_name TaxiService
extends Node
## Taxi passenger service. call_taxi() spawns a City Cab out of sight on a lane connected to the player, drives it (RouteDriver =
## TrafficDriver on a RoutePlanner route) to the curb next to the player, hazards + horn beep; F boards the rear seat, the destination menu
## (TaxiMenu) lists named locations / the map waypoint with fares, the cab drives there with normal traffic behaviour, charges the fare
## (Game.spend_cash, free with Game.cheats["free_taxi"]), F gets out at the curb and the cab drives off and despawns out of sight.
## Hold interact (E) during the ride to skip it (fade, arrive instantly). Cancelled by wanted level, the player taking another vehicle, or time.

enum S { IDLE, APPROACH, WAITING, CHOOSE, RIDE, ARRIVED, LEAVING }

const FARE_BASE := 6
const FARE_PER_M := 0.022
const HAIL_RANGE := 7.5
const SKIP_HOLD := 0.9
const STUCK_S := 9.0
const DEST_IDS: Array[StringName] = [&"hospital", &"police_station", &"player_spawn", &"train_station_a", &"train_station_b", &"garage_shop",
	&"weapon_shop", &"clothing_store", &"barber", &"safehouse", &"gas_station", &"dealer_lot", &"airport_hangar", &"marina_office", &"beach_spawn",
	&"park_center", &"shooting_range", &"viewpoint"]

var state: int = S.IDLE
var taxi: VehicleBase = null
var drv: RouteDriver = null
var npc: Node = null
var tm: Node = null
var target := Vector3.ZERO
var dest: Dictionary = {}
var fare := 0
var trips := 0
var unsticks := 0
var total_fares := 0
var last_note := ""
var _t := 0.0
var _check := 0.0
var _skip_hold := 0.0
var _skipping := false
var _menu_delay := 0.0
var _honk_t := 0.0
var _released := false
var _skip_hint := false
var _uid := 900000
var debug := false
var _dbg_t := 0.0


func post_setup() -> void:
	tm = Game.sys(&"traffic")
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.vehicle_exited.connect(_on_vehicle_exited)


func is_free() -> bool:
	return bool(Game.cheats.get("free_taxi", false)) or bool(Game.cheats.get("unlock_all_mods", false))


func fare_for(len_m: float) -> int:
	return FARE_BASE + int(len_m * FARE_PER_M)


# =====================================================================================================================
# Call / spawn
# =====================================================================================================================
func call_taxi() -> bool:
	if state != S.IDLE:
		if state == S.APPROACH or state == S.WAITING:
			Game.notify("Your cab is already on its way.", &"info")
			return true
		Game.notify("The cab service is busy, try again in a moment.", &"warn")
		return false
	var pl = Game.player
	if not is_instance_valid(pl) or bool(pl.get("is_dead")):
		return false
	tm = Game.sys(&"traffic")
	if tm == null or int(tm.get("state")) != 1 or RoutePlanner.graph() == null:
		Game.notify("No cab available right now.", &"warn")
		return false
	if Game.wanted_level > 0:
		Game.notify("Dispatch: no cab will come while the police are after you.", &"warn")
		return false
	if pl.is_in_vehicle():
		Game.notify("Step out of your vehicle to call a cab.", &"warn")
		return false
	var G := RoutePlanner.graph()
	var stop := RoutePlanner.find_curb_stop(pl.global_position, 80.0)
	if stop < 0:
		Game.notify("No cab can reach this spot.", &"warn")
		return false
	var seen_cb := Callable(tm, "is_seen")
	var sp := RoutePlanner.find_spawn_point(stop, 110.0, 260.0, seen_cb)
	if sp < 0:
		sp = RoutePlanner.find_spawn_point(stop, 50.0, 320.0, seen_cb)
	if sp < 0:
		Game.notify("No cab available right now.", &"warn")
		return false
	if not _spawn(sp):
		Game.notify("No cab available right now.", &"warn")
		return false
	var route := RoutePlanner.plan(PackedInt32Array([sp]), PackedInt32Array([stop]))
	if route.size() < 2 or not drv.set_route(route):
		_despawn()
		Game.notify("No cab available right now.", &"warn")
		return false
	target = G.positions[stop]
	state = S.APPROACH
	_t = 0.0
	_check = 1.0
	_released = false
	taxi.set_meta(&"taxi_prompt", "Hail the cab (wait for it to stop)")
	Game.notify("A cab is on its way (about %d s). Wait by the curb." % int(RoutePlanner.route_time(route) * 1.4), &"info")
	return true


func _spawn(idx: int) -> bool:
	var G := RoutePlanner.graph()
	var pos: Vector3 = G.positions[idx]
	var dir: Vector3 = G.dirs[idx]
	var opts := {"ai": true, "engine_on": true, "headlights": Game.is_night()}
	taxi = VehicleFactory.spawn(&"taxi", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), pos), opts)
	if taxi == null:
		return false
	var peds = Game.sys(&"peds")
	if peds != null and peds.has_method("create_driver"):
		npc = peds.create_driver(taxi)
	_uid += 1
	drv = RouteDriver.new()
	drv.uid = _uid
	drv.stagger = 0
	drv.npc = npc
	if not drv.setup(taxi, idx, Game.rng, tm.grid, tm.junction, tm.clock):
		_despawn()
		return false
	taxi.display_name = "City Cab"
	taxi.set_meta(&"taxi_service", true)
	taxi.set_velocity(dir * drv.safe_spawn_speed(8.0, tm.clock))
	return true


# =====================================================================================================================
# Tick
# =====================================================================================================================
func _taxi_ok() -> bool:
	return taxi != null and is_instance_valid(taxi) and taxi.is_inside_tree() and not taxi.is_destroyed and drv != null


func _physics_process(dt: float) -> void:
	if state == S.IDLE:
		return
	if not _taxi_ok():
		_lost()
		return
	if drv.mode == TrafficDriver.MODE_DEAD:
		_lost()
		return
	if _honk_t > 0.0:
		_honk_t -= dt
		if _honk_t <= 0.0:
			taxi.honk(false)
	var clock: float = float(tm.get("clock")) if tm != null else 0.0
	if not _skipping:
		drv.update(dt, clock)
		if drv.idle_t > STUCK_S and (state == S.APPROACH or state == S.RIDE) and not drv.arrived:
			_unstick()
	_t += dt
	if debug:
		_dbg_t -= dt
		if _dbg_t <= 0.0:
			_dbg_t = 3.0
			print("TAXIDBG s=%d t=%.0f %s" % [state, _t, drv.debug_string()])
	var pl = Game.player
	var pl_in: bool = is_instance_valid(pl) and pl.current_vehicle == taxi
	match state:
		S.APPROACH:
			_tick_approach(dt, pl)
		S.WAITING:
			_tick_waiting(pl)
		S.CHOOSE:
			if not pl_in:
				_leave("")
			elif _menu_delay > 0.0:
				_menu_delay -= dt
				if _menu_delay <= 0.0:
					open_menu()
		S.RIDE:
			if not pl_in:
				_leave("")
			elif drv.arrived and not _skipping:
				_arrive()
			else:
				_tick_skip(dt)
		S.ARRIVED:
			pass
		S.LEAVING:
			_tick_leaving(dt, pl_in)


func _tick_approach(dt: float, pl) -> void:
	if drv.arrived:
		state = S.WAITING
		_t = 0.0
		taxi.set_meta(&"taxi_prompt", "Get in the cab")
		taxi.honk(true)
		_honk_t = 0.45
		Game.notify("Your cab is here. Press F next to it to get in.", &"good")
		if Sfx != null:
			Sfx.play_ui(&"ui_notify")
		return
	_check -= dt
	if _check > 0.0:
		return
	_check = 1.0
	if Game.wanted_level > 0:
		_leave("The cab driver bails: police everywhere.")
		return
	if is_instance_valid(pl) and pl.is_in_vehicle():
		_leave("Cab cancelled.")
		return
	if _t > 170.0:
		_leave("The cab gave up looking for you.")
		return
	if is_instance_valid(pl) and Util.dist_xz(pl.global_position, target) > 35.0 and Util.dist_xz(taxi.global_position, target) > 45.0:
		var stop := RoutePlanner.find_curb_stop(pl.global_position, 80.0)
		if stop >= 0:
			var G := RoutePlanner.graph()
			var xf := taxi.global_transform
			var route := RoutePlanner.plan_positions(xf.origin, G.positions[stop], Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized())
			if route.size() >= 2 and drv.set_route(route):
				target = G.positions[stop]


func _tick_waiting(pl) -> void:
	if Game.wanted_level > 0:
		_leave("The cab driver bails: police everywhere.")
		return
	if _t > 90.0:
		_leave("The cab did not wait any longer.")
		return
	if _t > 14.0 and not _skip_hint and is_instance_valid(pl) and Util.dist_xz(pl.global_position, taxi.global_position) < 40.0:
		_skip_hint = true
		taxi.honk(true)
		_honk_t = 0.3


func _tick_skip(dt: float) -> void:
	var menu_open: bool = Game.ui != null and Game.ui.has_method("is_menu_open") and Game.ui.is_menu_open()
	if not menu_open and Input.is_action_pressed(&"interact"):
		_skip_hold += dt
		if _skip_hold >= SKIP_HOLD:
			_skip_hold = 0.0
			_skip()
	else:
		_skip_hold = 0.0


func _tick_leaving(dt: float, pl_in: bool) -> void:
	if pl_in:
		return
	if _t > 2.2 and not _released:
		_released = true
		taxi.remove_meta(&"taxi_prompt")
		drv.release_arrival()
		taxi.honk(false)
	_check -= dt
	if _check > 0.0:
		return
	_check = 1.0
	var pl = Game.player
	var d: float = Util.dist_xz(taxi.global_position, pl.global_position) if is_instance_valid(pl) else 999.0
	var seen: bool = tm != null and tm.has_method("is_seen") and bool(tm.is_seen(taxi.global_position))
	if (d > 130.0 and not seen) or (_t > 110.0 and not seen) or taxi.global_position.y < -20.0:
		_despawn()


## Blocked by a parked car / pole / jam for too long: the driver finds a gap and the cab jumps ~28 m further along its route.
func _unstick() -> void:
	if drv.jump_ahead(28.0):
		unsticks += 1


# =====================================================================================================================
# Boarding / menu / trip
# =====================================================================================================================
func _input(event: InputEvent) -> void:
	if state == S.IDLE or not event.is_action_pressed(&"enter_exit", false, true):
		return
	if not _taxi_ok():
		return
	var pl = Game.player
	if not is_instance_valid(pl) or bool(pl.get("is_dead")):
		return
	if Game.ui != null and Game.ui.has_method("is_menu_open") and Game.ui.is_menu_open():
		return
	if pl.current_vehicle == taxi:
		get_viewport().set_input_as_handled()
		if taxi.get_speed() < 2.5:
			_exit_player()
		else:
			Game.notify("Wait until the cab has stopped.", &"info")
		return
	if pl.is_in_vehicle():
		return
	if Util.dist_xz(pl.global_position, taxi.global_position) > HAIL_RANGE:
		return
	if state == S.WAITING:
		get_viewport().set_input_as_handled()
		_board(pl)
	elif state == S.APPROACH:
		get_viewport().set_input_as_handled()
		Game.notify("Wait for the cab to pull over.", &"info")


func _board(pl) -> void:
	var seat: int = 3 if taxi.seats.size() > 3 else (2 if taxi.seats.size() > 2 else 1)
	var ok: bool = pl.enter_vehicle(taxi, seat)
	if not ok:
		ok = pl.enter_vehicle(taxi, 1)
	if not ok:
		Game.notify("The cab is full.", &"warn")
		return
	state = S.CHOOSE
	_t = 0.0
	_menu_delay = 0.85
	taxi.set_meta(&"taxi_prompt", "Get out of the cab")


func open_menu() -> void:
	if Game.ui == null or not Game.ui.has_method("open_menu"):
		return
	Game.ui.open_menu(&"taxi", {"destinations": _build_destinations(), "on_pick": Callable(self, "_start_trip"), "free": is_free()})


## [{name, sub, pos, fare, len, route}] reachable destinations from the cab's current lane.
func _build_destinations() -> Array:
	var out: Array = []
	var G := RoutePlanner.graph()
	if G == null or not _taxi_ok():
		return out
	var xf := taxi.global_transform
	var from := xf.origin
	var fwd := Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized()
	var cands: Array = []
	if Game.waypoint != Vector3.INF:
		cands.append({"name": "Map waypoint", "pos": Game.waypoint})
	for id in DEST_IDS:
		if WorldLayout.has_location(id):
			var loc: Dictionary = WorldLayout.get_location(id)
			cands.append({"name": str(loc.get("name", String(id))).split(" (")[0], "pos": WorldLayout.location_pos(id)})
	for c in cands:
		var stop := RoutePlanner.find_curb_stop(c["pos"], 90.0)
		if stop < 0:
			continue
		var route := RoutePlanner.plan_positions(from, G.positions[stop], fwd)
		if route.size() < 2:
			continue
		var len_m := RoutePlanner.route_length(route)
		if len_m < 25.0:
			continue
		c["route"] = route
		c["len"] = len_m
		c["fare"] = fare_for(len_m)
		c["sub"] = "%.2f km, about %d s" % [len_m / 1000.0, int(RoutePlanner.route_time(route) * 1.3)]
		out.append(c)
	return out


func _start_trip(d: Dictionary) -> void:
	if state != S.CHOOSE or not _taxi_ok():
		return
	var cost: int = 0 if is_free() else int(d.get("fare", 0))
	if Game.cash < cost:
		Game.notify("You cannot afford that fare (%s)." % Util.format_money(cost), &"warn")
		open_menu()
		return
	dest = d
	fare = cost
	var route: PackedInt32Array = d["route"]
	if not drv.set_route(route):
		Game.notify("The driver cannot find a way there.", &"warn")
		open_menu()
		return
	drv.pull_over = true
	drv.set_hazard(false)
	state = S.RIDE
	_t = 0.0
	_skip_hold = 0.0
	taxi.set_meta(&"taxi_prompt", "Get out of the cab")
	Game.notify("Off to %s. Fare %s. Hold E to skip the ride." % [str(d.get("name", "")), "FREE" if cost == 0 else Util.format_money(cost)], &"info")


func _arrive() -> void:
	state = S.ARRIVED
	_t = 0.0
	trips += 1
	if fare > 0:
		var paid := fare
		if not Game.spend_cash(fare):
			paid = Game.cash
			Game.cash = 0
		total_fares += paid
		Game.notify("Arrived at %s. Fare paid: %s. Press F to get out." % [str(dest.get("name", "")), Util.format_money(paid)], &"good")
		if Sfx != null:
			Sfx.play_ui(&"ui_cash")
	else:
		Game.notify("Arrived at %s. Press F to get out." % str(dest.get("name", "")), &"good")


func _skip() -> void:
	if _skipping or not _taxi_ok() or state != S.RIDE:
		return
	_skipping = true
	if Game.ui != null and Game.ui.has_method("fade"):
		await Game.ui.fade(true, 0.45)
	if _taxi_ok() and drv.goal_lane >= 0:
		var G := RoutePlanner.graph()
		var gl: int = drv.goal_lane
		var nx: PackedInt32Array = G.next[gl]
		taxi.place_at(Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(G.dirs[gl])), G.positions[gl] + Vector3(0.0, 0.3, 0.0)))
		taxi.set_velocity(Vector3.ZERO)
		if not nx.is_empty():
			drv.set_route(PackedInt32Array([gl, nx[0]]))
			drv.goal_lane = gl
	await get_tree().create_timer(0.35).timeout
	if Game.ui != null and Game.ui.has_method("fade"):
		Game.ui.fade(false, 0.55)
	_skipping = false


func _exit_player() -> void:
	var pl = Game.player
	if is_instance_valid(pl) and pl.current_vehicle == taxi:
		taxi.exit(pl)


# =====================================================================================================================
# Cancel / leave / cleanup
# =====================================================================================================================
func _on_vehicle_entered(vehicle: Node, character: Node, seat: int) -> void:
	if state == S.IDLE or not is_instance_valid(character) or not character.is_in_group(GC.G_PLAYER):
		return
	if vehicle == taxi:
		if seat == 0:
			_lost()
		return
	if state == S.APPROACH or state == S.WAITING:
		_leave("Cab cancelled.")


func _on_vehicle_exited(vehicle: Node, character: Node) -> void:
	if state == S.IDLE or vehicle != taxi or not is_instance_valid(character) or not character.is_in_group(GC.G_PLAYER):
		return
	if state == S.CHOOSE or state == S.RIDE or state == S.ARRIVED:
		state = S.LEAVING
		_t = 0.0
		_check = 1.0
		_released = false


func _leave(msg: String) -> void:
	if msg != "":
		Game.notify(msg, &"warn")
	if state == S.IDLE or state == S.LEAVING:
		return
	state = S.LEAVING
	_t = 0.0
	_check = 1.0
	_released = false
	if _taxi_ok():
		taxi.remove_meta(&"taxi_prompt")


## The cab is no longer ours (driver killed / car taken by the player / destroyed): forget it, TrafficManager cleans up orphans.
func _lost() -> void:
	if taxi != null and is_instance_valid(taxi):
		taxi.remove_meta(&"taxi_prompt")
		if tm != null and tm.has_method("add_orphan") and not taxi.is_destroyed:
			tm.add_orphan(taxi)
	_clear_refs()


func _despawn() -> void:
	var peds = Game.sys(&"peds")
	if npc != null and is_instance_valid(npc):
		if peds != null and peds.has_method("release"):
			peds.release(npc)
		else:
			npc.queue_free()
	if taxi != null and is_instance_valid(taxi):
		if drv != null:
			drv.mode = TrafficDriver.MODE_DEAD
			if drv.junction != null:
				drv.junction.release(drv)
		VehicleFactory.despawn(taxi)
	_clear_refs()


func _clear_refs() -> void:
	taxi = null
	drv = null
	npc = null
	state = S.IDLE
	dest = {}
	fare = 0
	_skipping = false
	_skip_hint = false


## Save loading / debug: removes the cab immediately.
func reset() -> void:
	if state != S.IDLE:
		_despawn()
