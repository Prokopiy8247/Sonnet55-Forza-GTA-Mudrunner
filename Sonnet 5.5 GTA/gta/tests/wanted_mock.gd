extends RefCounted
## Mock police units / pedestrians / unit factory for the wanted + director tests (Police-A). No class_name on purpose (no import needed):
##   const Mock = preload("res://gta/tests/wanted_mock.gd");  var f = Mock.Factory.new(parent_node)

class Officer extends CharacterBase:
	var kind: StringName = &"patrol"
	var weapon_drawn := true
	var last_order: Dictionary = {}
	var order_count := 0

	func _ready() -> void:
		super()
		faction = GC.F_POLICE
		add_to_group(GC.G_POLICE)
		add_to_group(GC.G_NPC)

	func set_order(o: Dictionary) -> void:
		last_order = o
		order_count += 1


class Car extends Node3D:
	var kind: StringName = &"car"
	var is_destroyed := false
	var driver: Node = null
	var vclass: StringName = GC.VC_CAR
	var faction: StringName = GC.F_POLICE
	var is_ai_controlled := true
	var engine_on := true
	var last_order: Dictionary = {}
	var order_count := 0
	var speed := 0.0

	func _ready() -> void:
		add_to_group(GC.G_POLICE)
		add_to_group(GC.G_VEHICLE)
		set_meta(&"police_kind", kind)

	func set_order(o: Dictionary) -> void:
		last_order = o
		order_count += 1

	func get_speed() -> float:
		return speed


class CivCar extends Node3D:
	var is_destroyed := false
	var driver: Node = null
	var is_ai_controlled := true
	var faction: StringName = GC.F_CIVILIAN

	func _ready() -> void:
		add_to_group(GC.G_VEHICLE)
		add_to_group(GC.G_TRAFFIC)


class Ped extends CharacterBase:
	var phone_time := 0.6
	var will_phone := true
	var calls := 0

	func _ready() -> void:
		super()
		faction = GC.F_CIVILIAN
		add_to_group(GC.G_PED)
		add_to_group(GC.G_NPC)

	func witness(crime: StringName, pos: Vector3, perp: Node, _severity: float) -> bool:
		if not will_phone:
			return false
		calls += 1
		_call(crime, pos, perp)
		return true

	func _call(crime: StringName, pos: Vector3, perp: Node) -> void:
		await get_tree().create_timer(phone_time).timeout
		if is_inside_tree() and not is_dead:
			Events.crime_reported.emit(crime, pos, perp)


## Stand-in for PedManager (only get_witnesses).
class PedMgr extends Node:
	var peds: Array = []

	func get_witnesses(pos: Vector3, _perp: Node, radius: float = 45.0) -> Array:
		var out: Array = []
		for p in peds:
			if is_instance_valid(p) and not p.is_dead and (p as Node3D).global_position.distance_to(pos) <= radius:
				out.append(p)
		return out


class Block extends Node3D:
	var kind: StringName = &"roadblock"
	var last_order: Dictionary = {}
	var order_count := 0

	func _ready() -> void:
		set_meta(&"police_kind", kind)

	func set_order(o: Dictionary) -> void:
		last_order = o
		order_count += 1


## Swappable PoliceUnits replacement used by PoliceManager.set_factory().
class Factory extends RefCounted:
	var parent: Node3D
	var seat_officers := true
	var n_cars := 0
	var n_vans := 0
	var n_foot := 0
	var n_blocks := 0
	var n_despawn := 0
	var refuse := false
	var spawn_log: Array = []      # [{kind, pos}] where every unit appeared

	func _init(p: Node3D) -> void:
		parent = p

	func _car(xf: Transform3D, officers: int, kind: StringName) -> Car:
		var c := Car.new()
		c.kind = kind
		parent.add_child(c)
		c.global_transform = xf
		spawn_log.append({"kind": kind, "pos": xf.origin})
		if seat_officers:
			for i in officers:
				var o := Officer.new()
				c.add_child(o)
				o.current_vehicle = c
		return c

	func spawn_patrol_car(xf: Transform3D, officers: int = 2) -> Variant:
		if refuse:
			return null
		n_cars += 1
		return _car(xf, officers, &"car")

	func spawn_tactical_van(xf: Transform3D) -> Variant:
		if refuse:
			return null
		n_vans += 1
		return _car(xf, 3, &"van")

	func spawn_officer(kind: StringName, xf: Transform3D) -> Variant:
		if refuse:
			return null
		n_foot += 1
		var o := Officer.new()
		o.kind = kind
		parent.add_child(o)
		o.global_transform = xf
		spawn_log.append({"kind": &"foot", "pos": xf.origin})
		return o

	func spawn_roadblock(center: Vector3, dir: Vector3, _level: int) -> Variant:
		if refuse:
			return null
		n_blocks += 1
		var b := Block.new()
		parent.add_child(b)
		b.global_position = center
		spawn_log.append({"kind": &"roadblock", "pos": center})
		var side := Vector3(dir.z, 0, -dir.x)
		for i in 2:
			var c := Car.new()
			b.add_child(c)
			c.global_position = center + side * (3.0 if i == 0 else -3.0)
			if seat_officers:
				var o := Officer.new()
				c.add_child(o)
				o.current_vehicle = c
		return b

	func despawn(n: Node) -> void:
		if is_instance_valid(n):
			n_despawn += 1
			n.queue_free()

	func spawn_heli(pos: Vector3) -> Variant:
		if refuse:
			return null
		var c := Car.new()
		c.kind = &"heli"
		c.vclass = GC.VC_HELI
		parent.add_child(c)
		c.global_position = pos
		spawn_log.append({"kind": &"heli", "pos": pos})
		return c
