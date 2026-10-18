class_name EmergencySystem
extends Node
## Ambulance + fire engine response. Listens to Events.character_died (bodies), Events.explosion / vehicle_destroyed and burning vehicles,
## queues incidents, and sends AT MOST one ambulance and one fire engine at a time (cooldowns, never during a police pursuit):
## the unit spawns at its station (hospital / industrial yard) or out of sight on a connected lane, drives the planned route with siren
## and normal traffic behaviour (traffic yields to sirens), stops at the curb, the crew (EmergencyCrew rigs) gets out and treats the
## body and takes it away / sprays water until the fire is out, climbs back in, drives off and despawns when unseen or far.
## Public: report_incident(kind, pos, node), despawn_all(), get_state(), enabled. Save hooks: nothing is persisted (reset on load).

enum U { ROUTE, WORK, LEAVE }

const DELAY := {&"medical": 7.0, &"fire": 5.0}
const COOLDOWN := {&"medical": 30.0, &"fire": 45.0}
const MAX_DIST := 300.0
const MAX_QUEUE := 4
const TREAT_S := 6.0
const SPRAY_S := 9.0
const STUCK_S := 9.0

var enabled := true
var incidents: Array = []
var units: Dictionary = {}
var cooldown: Dictionary = {&"medical": 0.0, &"fire": 0.0}
var stats := {"medical": 0, "fire": 0, "bodies": 0, "fires_out": 0, "unsticks": 0, "aborted": 0}
var tm: Node = null
var _scan_t := 0.0
var _uid := 950000


func setup(_main: Node) -> void:
	pass


func post_setup() -> void:
	tm = Game.sys(&"traffic")
	Events.character_died.connect(_on_character_died)
	Events.explosion.connect(_on_explosion)
	Events.vehicle_destroyed.connect(_on_vehicle_destroyed)


# =====================================================================================================================
# Incidents
# =====================================================================================================================
func _on_character_died(character: Node, _killer: Node, _info: Dictionary) -> void:
	if not enabled or character == null or not is_instance_valid(character) or not (character is Node3D):
		return
	if character.is_in_group(GC.G_PLAYER):
		return
	var pos := (character as Node3D).global_position
	if pos.y < -1.0:
		return
	report_incident(&"medical", pos, character)


func _on_explosion(pos: Vector3, radius: float, _source: Node) -> void:
	if enabled and radius >= 3.5:
		report_incident(&"fire", pos, null)


func _on_vehicle_destroyed(vehicle: Node, _killer: Node) -> void:
	if enabled and vehicle != null and is_instance_valid(vehicle) and vehicle is Node3D and not vehicle.is_in_group(&"emergency_vehicle"):
		report_incident(&"fire", (vehicle as Node3D).global_position, vehicle)


## kind: &"medical" | &"fire". node: the body / burning vehicle (optional).
func report_incident(kind: StringName, pos: Vector3, node: Node) -> bool:
	if not enabled or bool(Game.cheats.get("no_emergency", false)):
		return false
	var pl = Game.player
	if is_instance_valid(pl) and Util.dist_xz(pl.global_position, pos) > MAX_DIST:
		return false
	for inc in incidents:
		if inc["kind"] == kind and Util.dist_xz(inc["pos"], pos) < 18.0:
			if inc["node"] == null and node != null:
				inc["node"] = node
			return false
	var u: Unit = units.get(kind, null)
	if u != null and Util.dist_xz(u.inc["pos"], pos) < 24.0:
		return false
	if incidents.size() >= MAX_QUEUE:
		return false
	incidents.append({"kind": kind, "pos": pos, "node": node, "age": 0.0, "retry": 0.0})
	return true


func _scan_fires() -> void:
	var pl = Game.player
	if not is_instance_valid(pl):
		return
	for v in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if v is VehicleBase and (v as VehicleBase).on_fire and not (v as VehicleBase).is_destroyed:
			if Util.dist_xz(v.global_position, pl.global_position) < MAX_DIST:
				report_incident(&"fire", v.global_position, v)


# =====================================================================================================================
# Tick
# =====================================================================================================================
func _physics_process(dt: float) -> void:
	if not enabled:
		return
	for k in cooldown:
		cooldown[k] = maxf(float(cooldown[k]) - dt, 0.0)
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 2.0
		_scan_fires()
	for i in range(incidents.size() - 1, -1, -1):
		var inc: Dictionary = incidents[i]
		inc["age"] = float(inc["age"]) + dt
		inc["retry"] = maxf(float(inc["retry"]) - dt, 0.0)
		var n = inc["node"]
		var gone: bool = float(inc["age"]) > 150.0
		if inc["kind"] == &"medical" and (n == null or not is_instance_valid(n) or (n.get("is_dead") == false)):
			gone = true
		if gone:
			incidents.remove_at(i)
	if tm == null:
		tm = Game.sys(&"traffic")
	if tm != null and int(tm.get("state")) == 1 and Game.wanted_state != &"pursuit":
		for kind in [&"medical", &"fire"]:
			if units.has(kind) or float(cooldown[kind]) > 0.0:
				continue
			for inc in incidents:
				if inc["kind"] == kind and float(inc["age"]) >= float(DELAY[kind]) and float(inc["retry"]) <= 0.0:
					if not _dispatch(kind, inc):
						inc["retry"] = 6.0
					else:
						incidents.erase(inc)
					break
	for kind in units.keys():
		var u: Unit = units[kind]
		u.tick(dt)
		if u.done:
			u.cleanup()
			units.erase(kind)
			cooldown[kind] = float(COOLDOWN[kind])


# =====================================================================================================================
# Dispatch
# =====================================================================================================================
func _station_lane(kind: StringName, goal: int) -> int:
	var id: StringName = &"hospital" if kind == &"medical" else (&"district_center_industrial" if WorldLayout.has_location(&"district_center_industrial") else &"hospital")
	if not WorldLayout.has_location(id):
		return -1
	var G := RoutePlanner.graph()
	var spos := WorldLayout.location_pos(id)
	var s := RoutePlanner.find_curb_stop(spos, 60.0)
	if s < 0:
		return -1
	var pl = Game.player
	if is_instance_valid(pl) and Util.dist_xz(pl.global_position, G.positions[s]) < 75.0:
		return -1
	if tm != null and tm.has_method("is_seen") and bool(tm.is_seen(G.positions[s])):
		return -1
	var route := RoutePlanner.plan(PackedInt32Array([s]), PackedInt32Array([goal]))
	if route.is_empty() or RoutePlanner.route_length(route) > 650.0:
		return -1
	return s


func _dispatch(kind: StringName, inc: Dictionary) -> bool:
	var G := RoutePlanner.graph()
	if G == null:
		return false
	var goal := RoutePlanner.find_curb_stop(inc["pos"], 90.0, Vector3.ZERO, false)
	if goal < 0:
		return false
	var start := _station_lane(kind, goal)
	if start < 0:
		var seen_cb := Callable(tm, "is_seen")
		start = RoutePlanner.find_spawn_point(goal, 110.0, 260.0, seen_cb)
		if start < 0:
			start = RoutePlanner.find_spawn_point(goal, 50.0, 320.0, seen_cb)
	if start < 0:
		return false
	var vid: StringName = &"ambulance" if kind == &"medical" else &"firetruck"
	var pos: Vector3 = G.positions[start]
	var dir: Vector3 = G.dirs[start]
	var v := VehicleFactory.spawn(vid, Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), pos), {"ai": true, "engine_on": true, "headlights": true})
	if v == null:
		return false
	var u := Unit.new()
	u.sys = self
	u.kind = kind
	u.inc = inc
	u.vehicle = v
	var peds = Game.sys(&"peds")
	if peds != null and peds.has_method("create_driver"):
		u.npc = peds.create_driver(v)
	_uid += 1
	var d := RouteDriver.new()
	d.uid = _uid
	d.stagger = 0
	d.npc = u.npc
	if not d.setup(v, start, Game.rng, tm.grid, tm.junction, tm.clock):
		u.npc_release()
		VehicleFactory.despawn(v)
		return false
	var route := RoutePlanner.plan(PackedInt32Array([start]), PackedInt32Array([goal]))
	if route.size() < 2 or not d.set_route(route):
		u.npc_release()
		VehicleFactory.despawn(v)
		return false
	u.drv = d
	v.add_to_group(&"emergency_vehicle")
	v.siren_on = true
	v.set_velocity(dir * d.safe_spawn_speed(9.0, tm.clock))
	units[kind] = u
	stats[String(kind) if kind == &"fire" else "medical"] = int(stats[String(kind) if kind == &"fire" else "medical"]) + 1
	Game.notify("Sirens in the distance: %s on its way." % ("an ambulance" if kind == &"medical" else "a fire engine"), &"info")
	return true


## Save loading / debug: removes every unit and incident.
func despawn_all() -> void:
	for kind in units.keys():
		var u: Unit = units[kind]
		u.cleanup(true)
	units.clear()
	incidents.clear()


func reset() -> void:
	despawn_all()


func get_state() -> Dictionary:
	var out := {"incidents": incidents.size(), "stats": stats}
	for k in units:
		out[String(k)] = (units[k] as Unit).state
	return out


# =====================================================================================================================
# One responding unit
# =====================================================================================================================
class Unit:
	extends RefCounted
	var sys: EmergencySystem = null
	var kind: StringName = &"medical"
	var inc: Dictionary = {}
	var vehicle: VehicleBase = null
	var drv: RouteDriver = null
	var npc: Node = null
	var crew: Array[EmergencyCrew] = []
	var state: int = EmergencySystem.U.ROUTE
	var phase := 0
	var t := 0.0
	var age := 0.0
	var done := false
	var released := false
	var spray_pos := Vector3.ZERO
	var _check := 0.0
	var _extinguished := false

	func tick(dt: float) -> void:
		age += dt
		t += dt
		if vehicle == null or not is_instance_valid(vehicle) or vehicle.is_destroyed or drv == null or drv.mode == TrafficDriver.MODE_DEAD:
			sys.stats["aborted"] = int(sys.stats["aborted"]) + 1
			_abandon()
			return
		var clock: float = float(sys.tm.get("clock")) if sys.tm != null else 0.0
		drv.update(dt, clock)
		if kind == &"fire" and state != EmergencySystem.U.LEAVE and not _extinguished:
			# the engine is on its way: the wreck it was called to must not vanish (VehicleBase despawns wrecks after 60 s)
			var wreck = inc["node"]
			if wreck != null and is_instance_valid(wreck) and wreck is VehicleBase and (wreck as VehicleBase).is_destroyed:
				wreck.set("_despawn_timer", maxf(float(wreck.get("_despawn_timer")), 25.0))
		match state:
			EmergencySystem.U.ROUTE:
				if drv.idle_t > EmergencySystem.STUCK_S and not drv.arrived:
					if drv.jump_ahead(28.0):
						sys.stats["unsticks"] = int(sys.stats["unsticks"]) + 1
				if drv.arrived:
					_begin_work()
				elif age > 160.0:
					_begin_leave()
			EmergencySystem.U.WORK:
				_tick_work(dt)
			EmergencySystem.U.LEAVE:
				_tick_leave(dt)

	# ---- work ----------------------------------------------------------------------------------------------------------
	func _begin_work() -> void:
		state = EmergencySystem.U.WORK
		phase = 0
		t = 0.0
		var kinds: StringName = &"paramedic" if kind == &"medical" else &"firefighter"
		for i in 2:
			var c := EmergencyCrew.new()
			sys.add_child(c)
			c.setup(kinds, Game.rng)
			var side := 1.0 if i == 0 else -1.0
			var door: Vector3 = vehicle.get_exit_position(1 if i == 0 else 0)
			c.global_position = door
			c.rotation.y = vehicle.global_rotation.y
			crew.append(c)
		var ipos: Vector3 = inc["pos"]
		var n = inc["node"]
		if n != null and is_instance_valid(n) and n is Node3D:
			ipos = (n as Node3D).global_position
		inc["pos"] = ipos
		var to_veh := Vector3(vehicle.global_position.x - ipos.x, 0.0, vehicle.global_position.z - ipos.z)
		var d_veh := to_veh.length()
		to_veh = to_veh.normalized() if d_veh > 0.5 else Vector3(0, 0, 1)
		var side_v := Vector3(-to_veh.z, 0.0, to_veh.x)
		if kind == &"medical":
			crew[0].walk_to(ipos + side_v * 0.9 + to_veh * 0.3)
			crew[1].walk_to(ipos - side_v * 0.9 + to_veh * 0.3)
		else:
			var stand := minf(d_veh, 8.5)
			spray_pos = ipos + Vector3(0, 0.7, 0)
			crew[0].walk_to(ipos + to_veh * stand + side_v * 1.4)
			crew[1].walk_to(ipos + to_veh * stand - side_v * 1.4)

	## Walking time to the incident (crew speed 2.7 m/s) plus slack, capped.
	func _walk_timeout() -> float:
		var far := 0.0
		for c in crew:
			far = maxf(far, Util.dist_xz(c.global_position, c.target))
		return clampf(far / EmergencyCrew.WALK_SPEED + 8.0, 16.0, 55.0)

	func _crew_there() -> bool:
		for c in crew:
			if c.moving:
				return false
		return true

	func _tick_work(dt: float) -> void:
		if crew.is_empty():
			_begin_leave()
			return
		if kind == &"medical":
			match phase:
				0:
					if _crew_there() or t > _walk_timeout():
						phase = 1
						t = 0.0
						var body = inc["node"]
						for c in crew:
							c.kneel(true)
							if body != null and is_instance_valid(body) and body is Node3D:
								c.face((body as Node3D).global_position)
				1:
					if t > EmergencySystem.TREAT_S:
						phase = 2
						t = 0.0
						var body2 = inc["node"]
						if body2 != null and is_instance_valid(body2):
							var peds = Game.sys(&"peds")
							if peds != null and peds.has_method("release"):
								peds.release(body2)
							elif body2 is Node3D:
								(body2 as Node3D).hide()
							sys.stats["bodies"] = int(sys.stats["bodies"]) + 1
						var rear: Vector3 = vehicle.global_position + vehicle.global_transform.basis.z * 3.6
						for c in crew:
							c.kneel(false)
						crew[0].walk_to(rear + vehicle.global_transform.basis.x * 0.7)
						crew[1].walk_to(rear - vehicle.global_transform.basis.x * 0.7)
				2:
					if _crew_there() or t > 14.0:
						phase = 3
						t = 0.0
						crew[0].walk_to(vehicle.get_exit_position(1))
						crew[1].walk_to(vehicle.get_exit_position(0))
				3:
					if _crew_there() or t > 12.0:
						_begin_leave()
		else:
			match phase:
				0:
					if _crew_there() or t > _walk_timeout():
						phase = 1
						t = 0.0
				1:
					for c in crew:
						c.spray(spray_pos, true)
					if t > EmergencySystem.SPRAY_S * 0.7 and not _extinguished:
						_extinguished = true
						_extinguish()
					if t > EmergencySystem.SPRAY_S:
						phase = 2
						t = 0.0
						for c in crew:
							c.spray(spray_pos, false)
						crew[0].walk_to(vehicle.get_exit_position(1))
						crew[1].walk_to(vehicle.get_exit_position(0))
				2:
					if _crew_there() or t > 14.0:
						_begin_leave()

	func _extinguish() -> void:
		var pos: Vector3 = inc["pos"]
		var n = inc["node"]
		var list: Array = []
		if n != null and is_instance_valid(n) and n is VehicleBase:
			list.append(n)
		for v in sys.get_tree().get_nodes_in_group(GC.G_VEHICLE):
			if v is VehicleBase and v != vehicle and not list.has(v) and Util.dist_xz(v.global_position, pos) < 16.0:
				list.append(v)
		var put_out := 0
		for v in list:
			var vb: VehicleBase = v
			if vb.on_fire and not vb.is_destroyed:
				vb.on_fire = false
				vb.health = maxf(vb.health, vb.max_health * 0.3)
				put_out += 1
			if vb.is_destroyed and vb.dmg != null:
				vb.dmg.set("_burn_left", -25.0)
				vb.dmg.set("_burnt", false)
				put_out += 1
		sys.stats["fires_out"] = int(sys.stats["fires_out"]) + maxi(put_out, 1)

	# ---- leave ---------------------------------------------------------------------------------------------------------
	func _begin_leave() -> void:
		state = EmergencySystem.U.LEAVE
		t = 0.0
		for c in crew:
			if is_instance_valid(c):
				c.queue_free()
		crew.clear()
		if not released:
			released = true
			drv.release_arrival()

	func _tick_leave(dt: float) -> void:
		if t > 7.0 and vehicle.siren_on:
			vehicle.siren_on = false
		_check -= dt
		if _check > 0.0:
			return
		_check = 1.0
		var pl = Game.player
		var d: float = Util.dist_xz(vehicle.global_position, pl.global_position) if is_instance_valid(pl) else 999.0
		var seen: bool = sys.tm != null and sys.tm.has_method("is_seen") and bool(sys.tm.is_seen(vehicle.global_position))
		if (d > 130.0 and not seen) or (t > 100.0 and not seen) or vehicle.global_position.y < -20.0:
			done = true

	# ---- cleanup -------------------------------------------------------------------------------------------------------
	## Vehicle destroyed / stolen / lost: crew leaves, the vehicle (if alive) becomes an ordinary orphan.
	func _abandon() -> void:
		for c in crew:
			if is_instance_valid(c):
				c.queue_free()
		crew.clear()
		if vehicle != null and is_instance_valid(vehicle):
			vehicle.remove_from_group(&"emergency_vehicle")
			if sys.tm != null and sys.tm.has_method("add_orphan") and not vehicle.is_destroyed:
				sys.tm.add_orphan(vehicle)
		vehicle = null
		done = true

	func npc_release() -> void:
		var peds = Game.sys(&"peds")
		if npc != null and is_instance_valid(npc):
			if peds != null and peds.has_method("release"):
				peds.release(npc)
			else:
				npc.queue_free()

	func cleanup(force: bool = false) -> void:
		for c in crew:
			if is_instance_valid(c):
				c.queue_free()
		crew.clear()
		if vehicle != null and is_instance_valid(vehicle):
			if drv != null:
				drv.mode = TrafficDriver.MODE_DEAD
				if drv.junction != null:
					drv.junction.release(drv)
			vehicle.siren_on = false
			npc_release()
			VehicleFactory.despawn(vehicle)
		vehicle = null
