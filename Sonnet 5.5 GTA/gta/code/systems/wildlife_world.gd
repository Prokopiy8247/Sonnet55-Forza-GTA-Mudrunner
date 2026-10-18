class_name WildlifeWorld
extends RefCounted
## Shared per-frame knowledge for the animal brains (filled by WildlifeSystem once per physics tick / every 0.2 s): where the player is and
## what he is doing, moving vehicles, recent gunshots and explosions, the physics space for obstacle rays, the clock and a voice helper.
## Keeping it in a plain object lets WildlifeBrain / MarineBrain stay free of references to the system node.

var rng := RandomNumberGenerator.new()
var now := 0.0
var night := false
var space: PhysicsDirectSpaceState3D = null
var ray := PhysicsRayQueryParameters3D.new()

# ---- player ---------------------------------------------------------------------------------------------------------------
var player: Node3D = null
var player_pos := Vector3.ZERO
var player_vel := Vector3.ZERO
var player_speed := 0.0
var player_in_vehicle := false
var player_crouch := false
var player_aiming := false
var player_swimming := false
var player_underwater := false
var player_vehicle: Node3D = null
var player_has_scuba := false

# ---- threats -----------------------------------------------------------------------------------------------------------------
var scares: Array = []            # [{pos: Vector3, r: float, t: float}] recent gunshots / explosions
var vehicles: Array = []          # [{pos: Vector3, vel: Vector3, speed: float, node: Node3D, boat: bool}] moving vehicles
var animals: Array = []           # every active Animal (read only for brains)

# ---- callbacks into the system (set by WildlifeSystem) --------------------------------------------------------------------------
var on_player_bitten := Callable()       # (animal, damage)  -> camera shake / notification handled by the system
var on_voice := Callable()               # (animal, id, db)


func _init() -> void:
	rng.randomize()
	ray.collision_mask = GC.L_WORLD
	ray.hit_from_inside = false
	ray.collide_with_areas = false


func raycast(from: Vector3, to: Vector3, mask: int = GC.L_WORLD) -> Dictionary:
	if space == null:
		return {}
	ray.from = from
	ray.to = to
	ray.collision_mask = mask
	return space.intersect_ray(ray)


func voice(a: Animal, id: StringName, db: float = 0.0) -> void:
	if on_voice.is_valid():
		on_voice.call(a, id, db)
