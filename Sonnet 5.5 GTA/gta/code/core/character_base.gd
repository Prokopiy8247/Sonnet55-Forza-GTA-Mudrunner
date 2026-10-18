class_name CharacterBase
extends CharacterBody3D
## Shared base for the player, pedestrians, police officers and hostile NPCs.
## Implements the damage contract (group "damageable" -> apply_damage(amount, info)).
## Subclasses override _on_damaged / _on_death and add their own movement. Additive changes only.

signal damaged(amount: float, info: Dictionary)
signal died(killer: Node, info: Dictionary)
signal vehicle_changed(vehicle: Node)

## Damage multipliers by hit zone (info["zone"]).
const ZONE_MULT := {&"head": 3.0, &"torso": 1.0, &"limb": 0.7}
const ARMOR_ABSORB := 0.7

@export var display_name := "Citizen"
@export var max_health := 100.0
@export var max_armor := 100.0

var health := 100.0
var armor := 0.0
var faction: StringName = GC.F_CIVILIAN
var is_dead := false
var invulnerable := false

var rig = null                  # CharacterRig (visual + procedural animation), set by the subclass
var weapons = null              # WeaponController component, set by the subclass
var current_vehicle = null      # VehicleBase while seated, else null
var seat_index := -1
var last_damage_info: Dictionary = {}
var last_attacker: Node = null


func _ready() -> void:
	health = max_health
	add_to_group(GC.G_DAMAGEABLE)


# ---- Queries -------------------------------------------------------------------------------
func is_player() -> bool:
	return is_in_group(GC.G_PLAYER)


func is_in_vehicle() -> bool:
	return current_vehicle != null and is_instance_valid(current_vehicle)


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.6, 0.0)


func get_chest_position() -> Vector3:
	return global_position + Vector3(0.0, 1.25, 0.0)


## World-space direction the character is facing / aiming. Subclasses refine this.
func get_aim_direction() -> Vector3:
	return -global_transform.basis.z


func get_speed_xz() -> float:
	return Vector2(velocity.x, velocity.z).length()


## True when `other` should be treated as an enemy by this character's AI.
func is_hostile_to(other: Node) -> bool:
	if other == null or other == self:
		return false
	var of = other.get("faction")
	if of == null:
		return false
	if faction == of:
		return false
	if faction == GC.F_POLICE:
		return of == GC.F_PLAYER and Game.wanted_level > 0 or of == GC.F_GANG
	if faction == GC.F_GANG:
		return of == GC.F_PLAYER or of == GC.F_POLICE
	return false


# ---- Damage contract ----------------------------------------------------------------------------
## info keys: source: Node, type: StringName (GC.DMG_*), zone: StringName (GC.ZONE_*), position: Vector3,
## direction: Vector3 (travel direction of the hit), weapon: StringName, impulse: float.
func apply_damage(amount: float, info: Dictionary = {}) -> void:
	if is_dead or amount <= 0.0:
		return
	if invulnerable or (is_player() and Game.cheats.get("invulnerable", false)):
		return
	amount *= ZONE_MULT.get(info.get("zone", GC.ZONE_TORSO), 1.0)
	if armor > 0.0:
		var absorbed := minf(armor, amount * ARMOR_ABSORB)
		armor -= absorbed
		amount -= absorbed
	health = maxf(health - amount, 0.0)
	last_damage_info = info
	last_attacker = info.get("source", null)
	damaged.emit(amount, info)
	Events.character_damaged.emit(self, amount, info)
	if is_player():
		Events.player_hurt.emit(amount, info)
	_on_damaged(amount, info)
	if health <= 0.0:
		die(info)


func heal(amount: float) -> void:
	if not is_dead:
		health = minf(health + amount, max_health)


func add_armor(amount: float) -> void:
	armor = minf(armor + amount, max_armor)


func die(info: Dictionary = {}) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	var killer: Node = info.get("source", null)
	died.emit(killer, info)
	Events.character_died.emit(self, killer, info)
	_on_death(info)


## Brings the character back to life at full health (respawn). Subclasses restore their state.
func revive() -> void:
	is_dead = false
	health = max_health
	_on_revive()


func knockback(impulse: Vector3) -> void:
	velocity += impulse


func teleport_to(pos: Vector3, yaw: float = NAN) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	if not is_nan(yaw):
		rotation.y = yaw


# ---- Vehicle helpers (the vehicle owns the real logic) --------------------------------------------------
func enter_vehicle(vehicle: Node, seat: int = -1) -> bool:
	if vehicle == null or not vehicle.has_method("request_enter"):
		return false
	return vehicle.request_enter(self, seat)


func exit_vehicle(forced: bool = false) -> void:
	if is_in_vehicle():
		current_vehicle.exit(self, forced)


## Called by VehicleBase when this character is seated / released.
func set_vehicle(vehicle: Node, seat: int) -> void:
	current_vehicle = vehicle
	seat_index = seat
	vehicle_changed.emit(vehicle)


# ---- Overridables -----------------------------------------------------------------------------------------
func _on_damaged(_amount: float, _info: Dictionary) -> void:
	pass


func _on_death(_info: Dictionary) -> void:
	pass


func _on_revive() -> void:
	pass
