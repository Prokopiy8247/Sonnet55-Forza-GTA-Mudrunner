class_name GangNpc
extends CharacterBase
## Gang member ("Neon Vipers"): faction GC.F_GANG, groups `hostile` + `npc`, driven by the shared CombatBrain.
## A gang hangs around its turf (idle styles, short strolls) with weapons holstered until the player comes within ~35 m armed or gets
## within ~11 m, shoots nearby, or hurts one of them. Then the whole group within 60 m attacks (cover, bursts, melee for bat carriers),
## some run away when badly hurt, and everybody calms down and walks back to the turf once the player is gone.

signal provoked_changed(is_provoked: bool)

const PROVOKE_ARMED_RANGE := 35.0
const PROVOKE_CLOSE_RANGE := 11.0
const FRIEND_RADIUS := 60.0
const CALM_AFTER := 25.0
const THINK_INTERVAL: Array[float] = [0.3, 0.5, 1.0]

static var _hooked := false

var ai_accuracy := 0.35
var body_height := 1.8
var is_crouching := false
var actor: CombatActor = null
var brain: CombatBrain = null
var mover: CombatMover = null
var turf := Vector3.ZERO
var turf_radius := 6.0
var group_id := -1
var group_members: Array = []                 # shared Array (all GangNpc of the group, set by HostileManager)
var provoked := false
var primary: StringName = &"pistol"
var holstered := true
var weapon_kind: StringName = &"pistol"       # pistol | smg | bat
var forced_weapon: StringName = &""           # set BEFORE adding to the tree: &"pistol" | &"smg" | &"bat" (default: random mix 50/28/22 %)

var _think_t := 0.0
var _think_dt := 0.5
var _wander_t := 2.0
var _calm_t := 0.0
var _heard_t := 0.0
var _clock := 0.0
var _last_provoked_time := -100.0


func _ready() -> void:
	max_health = 92.0
	display_name = "Gang Member"
	super._ready()
	faction = GC.F_GANG
	add_to_group(GC.G_HOSTILE)
	add_to_group(GC.G_NPC)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) * 104729 + Time.get_ticks_usec()
	var appearance := CharacterVariants.make(&"gang", rng)
	var r := rng.randf()
	match forced_weapon:                # tests / scripted encounters can pick the weapon
		&"pistol":
			r = 0.1
		&"smg":
			r = 0.6
		&"bat":
			r = 0.9
	var loadout: Array = []
	var cfg := {"target_groups": [GC.G_POLICE] as Array[StringName], "alert_radius": FRIEND_RADIUS, "sight_range": 55.0, "cover_bias": 0.45,
		"retreat_hp": 0.3, "retreat_chance": 0.35, "reaction_time": 0.65}
	if r < 0.5:
		weapon_kind = &"pistol"
		primary = &"pistol"
		loadout = [[&"pistol", 90]]
		ai_accuracy = rng.randf_range(0.28, 0.45)
	elif r < 0.78:
		weapon_kind = &"smg"
		primary = &"smg"
		loadout = [[&"smg", 180], [&"pistol", 30]]
		ai_accuracy = rng.randf_range(0.25, 0.4)
		cfg["burst_time"] = Vector2(0.35, 0.8)
	else:
		weapon_kind = &"bat"
		primary = &"bat"
		loadout = [[&"bat", 0], [&"pistol", 30]]
		ai_accuracy = rng.randf_range(0.3, 0.45)
		cfg["can_melee"] = true
	cfg["accuracy"] = ai_accuracy
	actor = CombatActor.new()
	actor.build(self, appearance, loadout, cfg)
	brain = actor.brain
	mover = actor.mover
	mover.run_speed = 5.0
	mover.sprint_speed = 6.4
	mover.walk_speed = 1.7
	brain.combat_enabled = false
	brain.alert_radius = FRIEND_RADIUS
	brain.retreat_hp = 0.3
	brain.retreat_chance = 0.35
	actor.weapons.equip(&"fists")
	holstered = true
	if weapon_kind == &"bat":
		# melee carriers: close in, no firearm range band
		actor.brain.can_melee = true
	brain.heard_shot.connect(_on_heard_shot)
	_wander_t = randf_range(1.0, 5.0)
	var styles := [&"relaxed", &"arms_crossed", &"hands_pockets"]
	actor.rig.set_idle_style(styles[randi() % styles.size()])


func _exit_tree() -> void:
	if actor != null:
		actor.dispose()
	if group_members.has(self):
		group_members.erase(self)


# =====================================================================================================================
func _physics_process(dt: float) -> void:
	_clock += dt
	if is_dead or actor.down:
		actor.physics(dt)
		return
	_think_t -= dt
	if _think_t <= 0.0:
		_think_dt = THINK_INTERVAL[clampi(actor.lod, 0, 2)]
		_think_t = _think_dt
		_think()
	actor.physics(dt)


func _think() -> void:
	var pl = Game.player
	if provoked:
		_think_provoked(pl)
	else:
		_think_calm(pl)


func _player_armed(pl) -> bool:
	if pl.weapons == null:
		return false
	var wc = pl.weapons
	if wc.is_aiming and wc.is_firearm_equipped():
		return true
	return wc.current_id != &"fists" and wc.is_armed()


func _think_calm(pl) -> void:
	# idle life
	_wander_t -= _think_dt
	if _wander_t <= 0.0 and not brain.is_engaged():
		_wander_t = randf_range(6.0, 13.0)
		if randf() < 0.45:
			var a := randf() * TAU
			var goal := turf + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, turf_radius)
			mover.set_goal(goal, mover.walk_speed, 0.8)
		else:
			mover.stop()
			mover.face_direction(randf() * TAU)
			var styles := [&"relaxed", &"arms_crossed", &"hands_pockets"]
			actor.rig.set_idle_style(styles[randi() % styles.size()])
	elif mover.arrived and brain.state == CombatBrain.State.IDLE and not mover.has_goal:
		pass
	if pl == null or not is_instance_valid(pl) or pl.get("is_dead") == true:
		return
	var d: float = (pl as Node3D).global_position.distance_to(global_position)
	if d > PROVOKE_ARMED_RANGE + 8.0:
		return
	if d < PROVOKE_CLOSE_RANGE or (d < PROVOKE_ARMED_RANGE and _player_armed(pl)):
		# they need to actually see the player (a wall in between does not provoke anybody)
		if Util.has_line_of_sight(self, global_position + Vector3(0, 1.6, 0), (pl as Node3D).global_position + Vector3(0, 1.3, 0), GC.M_LOS, [self]):
			provoke(pl)


func _think_provoked(pl) -> void:
	if brain.in_combat or brain.is_engaged():
		_calm_t = 0.0
		return
	_calm_t += _think_dt
	var far := true
	if pl != null and is_instance_valid(pl):
		far = (pl as Node3D).global_position.distance_to(global_position) > 60.0
	if _calm_t > CALM_AFTER and far:
		calm_down()


## Starts the fight: draws the weapon, targets `source` (the player or a police officer) and calls friends within 60 m.
func provoke(source: Node, propagate: bool = true) -> void:
	if is_dead:
		return
	if not provoked:
		provoked = true
		_calm_t = 0.0
		_last_provoked_time = _clock
		brain.combat_enabled = true
		if source != null and is_instance_valid(source):
			brain.forced_target = source
		if holstered:
			holstered = false
			actor.weapons.equip(primary)
		_apply_weapon_profile()
		provoked_changed.emit(true)
	if propagate:
		for m in group_members:
			var g := m as GangNpc
			if g != null and g != self and is_instance_valid(g) and not g.is_dead and not g.provoked:
				if g.global_position.distance_to(global_position) <= FRIEND_RADIUS:
					g.provoke(source, false)
	if source != null and is_instance_valid(source) and brain.target == null:
		brain.target = source
		brain.last_seen_pos = (source as Node3D).global_position
		brain.last_seen_t = brain._now - 1.0
		brain.investigate((source as Node3D).global_position, 12.0)


func _apply_weapon_profile() -> void:
	actor.auto_range(1.0)
	if weapon_kind == &"bat":
		brain.pref_min = 0.5
		brain.pref_max = 1.8
	brain.use_cover = weapon_kind != &"bat"
	brain.shoot_allowed = true


func calm_down() -> void:
	provoked = false
	brain.combat_enabled = false
	brain.forced_target = null
	brain.clear_target_memory_if_idle()
	if not holstered:
		holstered = true
		actor.weapons.equip(&"fists")
	mover.set_goal(turf, mover.walk_speed * 1.6, 1.5)
	provoked_changed.emit(false)


func _on_heard_shot(source: Node, pos: Vector3, d: float) -> void:
	if provoked or source == null:
		return
	if source == Game.player and d < 55.0:
		provoke(source)
	elif source is PoliceOfficer and (source as PoliceOfficer).faction == GC.F_POLICE and d < 45.0:
		provoke(source)


func _on_damaged(amount: float, info: Dictionary) -> void:
	var src: Node = info.get("source", null)
	if not provoked and src != null and is_instance_valid(src):
		provoke(src)
	actor.on_damaged(amount, info)


func _on_death(info: Dictionary) -> void:
	actor.on_death(info)
	group_members.erase(self)


func _on_revive() -> void:
	actor.on_revive()


func knock_down(impulse: Vector3, duration: float) -> void:
	if not provoked:
		var pl = Game.player
		if pl != null and is_instance_valid(pl):
			provoke(pl)
	actor.knock_down(impulse, duration)


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.45 if actor != null and actor.crouched else 1.6, 0.0)
