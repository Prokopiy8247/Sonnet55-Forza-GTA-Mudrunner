class_name PoliceUnits
extends RefCounted
## Static factory for police units (Police-B). Used by the PoliceManager director (Police-A, docs/ARCHITECTURE.md section 14.2).
## Every spawn adds the node under `Game.world/PoliceUnits` (or the vehicle container for cars) and returns it. Orders go through
## `unit.set_order(order)` on officers; cars carry a PoliceCarAI (meta `police_ai`) - use PoliceUnits.set_order(unit, order) for both.
##
##   var car := PoliceUnits.spawn_patrol_car(xform, 2)            # cruiser with a driver + passenger already seated
##   PoliceUnits.set_order(car, {"mode": &"pursue", "target": Game.player, "aggression": 0.6, "lethal": false})
##   var o := PoliceUnits.spawn_officer(&"swat", xform)
##   PoliceUnits.spawn_roadblock(center, travel_dir, level)
##   PoliceUnits.despawn(node)
##
## Caps: MAX_CARS police ground vehicles (cruisers + vans) and MAX_OFFICERS officers on foot/seated at once (spawn returns null above).
## HostileManager (gang NPCs) is created lazily the first time any PoliceUnits function runs and by a deferred hook once the game booted.

const MAX_CARS := 10
const MAX_OFFICERS := 44
const KINDS: Array[StringName] = [&"patrol", &"swat", &"sniper"]

static var autostart_hostiles := true
static var _container: Node3D = null
static var _boot_tries := 0
static var _warned: Dictionary = {}
static var spawned_officers := 0
static var spawned_cars := 0
static var rejected := 0


static func _static_init() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		(ml as SceneTree).process_frame.connect(PoliceUnits._lazy_boot, CONNECT_ONE_SHOT)


## Deferred autostart of the gang / hostile NPC manager (no change to main.gd needed).
static func _lazy_boot() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if not autostart_hostiles or OS.get_cmdline_user_args().has("--no-hostiles"):
		return
	if Game.world == null or not is_instance_valid(Game.world) or Game.sys(&"player") == null:
		_boot_tries += 1
		if _boot_tries < 900:
			tree.process_frame.connect(PoliceUnits._lazy_boot, CONNECT_ONE_SHOT)
		return
	ensure_hostile_manager()


## Creates the HostileManager (gang NPCs) under Game.world when it does not exist yet. Safe to call any time.
static func ensure_hostile_manager() -> Node:
	if Game.world == null or not is_instance_valid(Game.world):
		return null
	var existing := Game.world.get_node_or_null("HostileManager")
	if existing != null:
		return existing
	var m := HostileManager.new()
	m.name = "HostileManager"
	Game.world.add_child(m)
	return m


static func _ready_world() -> bool:
	if Game.world == null or not is_instance_valid(Game.world):
		if not _warned.has("world"):
			_warned["world"] = true
			push_warning("PoliceUnits: no Game.world yet - nothing spawned")
		return false
	if autostart_hostiles:
		ensure_hostile_manager()
	return true


static func container() -> Node3D:
	if _container != null and is_instance_valid(_container) and _container.is_inside_tree():
		return _container
	if Game.world == null:
		return null
	_container = Game.world.get_node_or_null("PoliceUnits") as Node3D
	if _container == null:
		_container = Node3D.new()
		_container.name = "PoliceUnits"
		Game.world.add_child(_container)
	return _container


# =====================================================================================================================
# Counting
# =====================================================================================================================
static func officers() -> Array:
	var out: Array = []
	if Game.world == null or not Game.world.is_inside_tree():
		return out
	for n in Game.world.get_tree().get_nodes_in_group(GC.G_POLICE):
		if n is PoliceOfficer and not (n as PoliceOfficer).is_dead:
			out.append(n)
	return out


static func police_cars() -> Array:
	var out: Array = []
	if Game.world == null or not Game.world.is_inside_tree():
		return out
	for n in Game.world.get_tree().get_nodes_in_group(GC.G_POLICE):
		if n is VehicleBase and (n as VehicleBase).vclass == GC.VC_CAR and not (n as VehicleBase).is_destroyed and n.has_meta(&"police_ai"):
			out.append(n)
	return out


static func count_officers() -> int:
	return officers().size()


static func count_cars() -> int:
	return police_cars().size()


## Frame-cost statistics of the whole force (microseconds accumulated since the last call to reset_stats()).
static func stats() -> Dictionary:
	return {"brain_usec": CombatBrain.stat_usec, "brain_ticks": CombatBrain.stat_ticks, "car_usec": PoliceCarAI.stat_usec,
		"car_ticks": PoliceCarAI.stat_ticks, "paths": CombatMover.paths_planned, "path_usec": CombatMover.path_usec,
		"cover_queries": CoverFinder.queries, "officers": count_officers(), "cars": count_cars()}


static func reset_stats() -> void:
	CombatBrain.stat_usec = 0
	CombatBrain.stat_ticks = 0
	PoliceCarAI.stat_usec = 0
	PoliceCarAI.stat_ticks = 0
	CombatMover.path_usec = 0
	CombatMover.paths_planned = 0


# =====================================================================================================================
# Factory
# =====================================================================================================================
static func spawn_officer(kind: StringName, xform: Transform3D) -> CharacterBase:
	if not _ready_world():
		return null
	if not KINDS.has(kind):
		push_warning("PoliceUnits.spawn_officer: unknown kind '%s' - using patrol" % kind)
		kind = &"patrol"
	if count_officers() >= MAX_OFFICERS:
		rejected += 1
		return null
	var cont := container()
	if cont == null:
		return null
	var o := PoliceOfficer.new()
	o.kind = kind
	o.name = "Officer_%s_%d" % [kind, spawned_officers]
	cont.add_child(o)
	o.global_transform = snap_to_ground(xform)
	o.reset_physics_interpolation()
	spawned_officers += 1
	return o


static func spawn_patrol_car(xform: Transform3D, officers_n: int = 2) -> VehicleBase:
	if not _ready_world():
		return null
	if count_cars() >= MAX_CARS:
		rejected += 1
		return null
	var car := VehicleFactory.spawn(&"police_cruiser", xform, {"faction": GC.F_POLICE, "ai": true, "keep_engine_on": true,
		"abandoned": false, "name": "Patrol Cruiser"})
	if car == null:
		return null
	_finish_car(car, &"patrol", officers_n)
	return car


static func spawn_tactical_van(xform: Transform3D) -> VehicleBase:
	if not _ready_world():
		return null
	if count_cars() >= MAX_CARS:
		rejected += 1
		return null
	var van := VehicleFactory.spawn(&"police_tactical", xform, {"faction": GC.F_POLICE, "ai": true, "keep_engine_on": true,
		"abandoned": false, "name": "Tactical Van"})
	if van == null:
		return null
	_finish_car(van, &"swat", 4)
	return van


static func _finish_car(car: VehicleBase, kind: StringName, n: int) -> void:
	car.faction = GC.F_POLICE
	if not car.is_in_group(GC.G_POLICE):
		car.add_to_group(GC.G_POLICE)
	car.siren_on = false
	car.set_ai_controlled(true)
	car.set_engine(true)
	car.keep_engine_on = true
	var seats_n := mini(n, car.get_seat_count())
	for i in seats_n:
		if count_officers() >= MAX_OFFICERS:
			break
		var o := spawn_officer(kind, car.global_transform) as PoliceOfficer
		if o == null:
			break
		o.home_vehicle = car
		o.home_seat = i
		car.enter(o, i, false)
	PoliceCarAI.attach(car)
	spawned_cars += 1


static func spawn_roadblock(center: Vector3, dir: Vector3, level: int) -> Node3D:
	if not _ready_world():
		return null
	var rb := PoliceRoadblock.build(center, dir, level)
	return rb


static func spawn_spike_strip(center: Vector3, dir: Vector3, width: float = 8.0) -> Node3D:
	if not _ready_world():
		return null
	var cont := container()
	var s := SpikeStrip.new()
	s.name = "SpikeStrip"
	s.width = width
	cont.add_child(s)
	s.global_transform = snap_to_ground(Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), center))      # local X (the strip's width) is across the road
	return s


## Forwards an order to whatever the unit is: PoliceOfficer.set_order or the PoliceCarAI of a police vehicle.
static func set_order(unit: Node, order: Dictionary) -> void:
	if not is_instance_valid(unit):
		return
	if unit.has_method("set_order"):
		unit.set_order(order)
	elif unit.has_meta(&"police_ai"):
		var ai = unit.get_meta(&"police_ai")
		if is_instance_valid(ai):
			ai.set_order(order)


## Removes a unit: officers vanish (their car is left alone), cars take their occupants with them, roadblocks dismantle everything.
static func despawn(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is PoliceRoadblock:
		(node as PoliceRoadblock).dismantle()
		return
	if node is VehicleBase:
		var v := node as VehicleBase
		for c in v.get_occupants():
			if c is PoliceOfficer:
				# leave the seat by being removed from the tree (VehicleBase clears the seat on tree_exiting) - no fall damage / sounds
				var par: Node = c.get_parent()
				if par != null:
					par.remove_child(c)
				c.queue_free()
		PoliceCarAI.detach(v)
		VehicleFactory.despawn(v)
		return
	node.queue_free()


# =====================================================================================================================
# Helpers
# =====================================================================================================================
## Drops the transform onto the ground below it (world / props), keeping its rotation.
static func snap_to_ground(xf: Transform3D) -> Transform3D:
	if Game.world == null or not Game.world.is_inside_tree():
		return xf
	var space := (Game.world as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3(0, 3.0, 0), xf.origin + Vector3(0, -8.0, 0), GC.M_GROUND)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		xf.origin.y = (hit["position"] as Vector3).y + 0.04
	return xf
