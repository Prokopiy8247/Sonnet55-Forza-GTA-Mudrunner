class_name SkillsSystem
extends Node
## Use-based character skills (docs/ARCHITECTURE.md 14.7): stamina, shooting, strength, stealth, driving, flying, lung.
## Booted by Main as Game.sys(&"skills"). Every skill is 0..100 and grows only by DOING the activity.
##
##   get_skill01(id) -> 0..1      get_skill(id) -> 0..100      record(id, amount)      get_modifier(name) -> float multiplier
##   set_skill / set_all / max_all / reset_all (debug menu)      serialize() / deserialize()
##
## `amount` of record() is in "use units": roughly one second of sustained use of the activity (sprinting, swimming under water,
## drifting, flying) or one clean action (a landed hit = 1, a kill = 3, a takedown = 2). XP_MAX says how many units reach 100.
## Growth is front loaded (CURVE): the first minutes are visible, the last points are slow.
## The consumers (player, weapons, vehicles, aircraft) apply the benefits themselves through get_skill01() / get_modifier().

signal skill_levelled(skill: StringName, value: float)

const IDS: Array[StringName] = [&"stamina", &"shooting", &"strength", &"stealth", &"driving", &"flying", &"lung"]
const NAMES := {&"stamina": "Stamina", &"shooting": "Shooting", &"strength": "Strength", &"stealth": "Stealth",
	&"driving": "Driving", &"flying": "Flying", &"lung": "Lung capacity"}

## Starting values (a fresh character is not zero everywhere, but benefits at these values are tiny).
const DEFAULTS := {&"stamina": 12.0, &"shooting": 10.0, &"strength": 10.0, &"stealth": 8.0, &"driving": 12.0, &"flying": 0.0, &"lung": 6.0}
## Use units needed to reach 100.
const XP_MAX := {&"stamina": 900.0, &"shooting": 450.0, &"strength": 160.0, &"stealth": 90.0, &"driving": 800.0, &"flying": 600.0, &"lung": 320.0}
const CURVE := 1.7                       # value = 100 * (1 - (1 - xp/xp_max)^CURVE)

## Benefit at skill 100 (linear in the skill): see get_modifier().
const BENEFIT := {
	&"recoil": 0.25,            # weapon recoil -25 %
	&"spread": 0.15,            # accuracy cone -15 %
	&"reload_time": 0.20,       # reload -20 %
	&"melee_damage": 0.40,      # melee damage +40 %
	&"fall_damage": 0.35,       # fall damage -35 %
	&"noise": 0.45,             # crouched foot noise -45 %
	&"stamina_drain": 1.2,      # sprint / swim fast drain divided by (1 + 1.2 * skill)
	&"lung_capacity": 2.0,      # 20 s -> 60 s of breath
	&"vehicle_grip": 0.07,      # tyre grip +7 %
	&"vehicle_recovery": 0.12,  # drift grip floor +0.12 (spin recovery)
	&"aircraft_stability": 0.35 # turbulence / handling penalties -35 % (Air agent reads this)
}
const ANNOUNCE_STEP := 10               # toast every N points
const NEAR_MISS_MIN := 1.7              # metres between hulls' centres for a near miss (closer = collision, no reward)
const NEAR_MISS_MAX := 3.9

## Live values 0..100 (UI may read `skills` directly).
var skills: Dictionary = {}
var xp: Dictionary = {}
var announce := true                    # toasts at every ANNOUNCE_STEP points (tests switch it off)
var sampling := true                    # activity sampler (driving / flying / stealth); tests switch it off

var _emitted: Dictionary = {}
var _acc := 0.0
var _player_connected: Node = null
var _air_time := 0.0
var _air_paid := 0.0
var _near: Dictionary = {}              # vehicle instance id -> min distance while close
var _near_cd := 0.0
var _vehicle_applied: Node = null


func _init() -> void:
	for id in IDS:
		xp[id] = _xp_for_value(id, float(DEFAULTS[id]))
		skills[id] = float(DEFAULTS[id])
		_emitted[id] = -99.0


func setup(_main: Node) -> void:
	name = "Skills"
	process_mode = Node.PROCESS_MODE_PAUSABLE


func post_setup() -> void:
	Events.hit_marker.connect(_on_hit_marker)
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.vehicle_exited.connect(_on_vehicle_exited)
	Events.player_respawned.connect(func(_p: Vector3) -> void: _near.clear())
	_connect_player()
	for id in IDS:                                   # UI cache + first values
		_emit(id, true)


# ======================================================================================================== public API
func has_skill(id: StringName) -> bool:
	return xp.has(id)


## 0..1
func get_skill01(id: StringName) -> float:
	return clampf(float(skills.get(id, 0.0)) / 100.0, 0.0, 1.0)


## 0..100. Values in (0, 1] are reported as 0 (the UI treats values <= 1 as ratios).
func get_skill(id: StringName) -> float:
	var v := float(skills.get(id, 0.0))
	return 0.0 if v < 1.0 else maxf(v, 1.001)


func get_value(id: StringName) -> float:
	return get_skill(id)


func get_level01(id: StringName) -> float:
	return get_skill01(id)


## Integer percent for HUD text.
func get_percent(id: StringName) -> int:
	return int(floor(float(skills.get(id, 0.0)) + 0.5))


## Use-based progress. `amount` in use units (see the header). Returns the new value (0..100).
func record(id: StringName, amount: float) -> float:
	if amount <= 0.0 or not xp.has(id):
		return float(skills.get(id, 0.0))
	if bool(Game.cheats.get("freeze_skills", false)):
		return float(skills[id])
	xp[id] = minf(float(xp[id]) + amount, float(XP_MAX[id]))
	_refresh(id)
	return float(skills[id])


# aliases (the Player agent probes these names, see docs/api/player.md)
func train(id: StringName, amount: float) -> void:
	record(id, amount)


func add_xp(id: StringName, amount: float) -> void:
	record(id, amount)


func record_use(id: StringName, amount: float) -> void:
	record(id, amount)


func add_progress(id: StringName, amount: float) -> void:
	record(id, amount)


func use_skill(id: StringName, amount: float) -> void:
	record(id, amount)


## Multiplier / factor for a benefit (see BENEFIT). Unknown names return 1.0.
func get_modifier(modifier: StringName) -> float:
	var s01: float
	match modifier:
		&"recoil", &"spread", &"reload_time":
			s01 = get_skill01(&"shooting")
			return 1.0 - float(BENEFIT[modifier]) * s01
		&"melee_damage":
			return 1.0 + float(BENEFIT[modifier]) * get_skill01(&"strength")
		&"fall_damage":
			return 1.0 - float(BENEFIT[modifier]) * get_skill01(&"strength")
		&"noise":
			return 1.0 - float(BENEFIT[modifier]) * get_skill01(&"stealth")
		&"stamina_drain":
			return 1.0 / (1.0 + float(BENEFIT[modifier]) * get_skill01(&"stamina"))
		&"lung_capacity":
			return 1.0 + float(BENEFIT[modifier]) * get_skill01(&"lung")
		&"vehicle_grip":
			return 1.0 + float(BENEFIT[modifier]) * get_skill01(&"driving")
		&"vehicle_recovery":
			return float(BENEFIT[modifier]) * get_skill01(&"driving")
		&"aircraft_stability":
			return 1.0 - float(BENEFIT[modifier]) * get_skill01(&"flying")
	return 1.0


# ---- debug menu -------------------------------------------------------------------------------------------------
func set_skill(id: StringName, value: float) -> void:
	if not xp.has(id):
		return
	xp[id] = _xp_for_value(id, clampf(value, 0.0, 100.0))
	_refresh(id, true, false)


## Sets every skill to the same value (0..100).
func set_all(value: float) -> void:
	for id in IDS:
		set_skill(id, value)


func max_all() -> void:
	set_all(100.0)


func reset_all() -> void:
	for id in IDS:
		set_skill(id, float(DEFAULTS[id]))


func get_all() -> Dictionary:
	return skills.duplicate()


# ---- persistence -----------------------------------------------------------------------------------------------
func serialize() -> Dictionary:
	var out := {}
	for id in IDS:
		out[String(id)] = snappedf(float(xp[id]), 0.001)
	return {"version": 1, "xp": out}


func deserialize(data: Dictionary) -> void:
	var src = data.get("xp", {})
	if not (src is Dictionary):
		return
	for id in IDS:
		if src.has(String(id)):
			xp[id] = clampf(float(src[String(id)]), 0.0, float(XP_MAX[id]))
		else:
			xp[id] = _xp_for_value(id, float(DEFAULTS[id]))
	for id in IDS:
		_refresh(id, true, false)
	_apply_vehicle_skill(_vehicle_applied)


# ======================================================================================================== growth model
static func value_for_xp(id: StringName, units: float) -> float:
	var t := clampf(units / float(XP_MAX.get(id, 100.0)), 0.0, 1.0)
	return 100.0 * (1.0 - pow(1.0 - t, CURVE))


static func _xp_for_value(id: StringName, value: float) -> float:
	var f := clampf(value / 100.0, 0.0, 1.0)
	var t := 1.0 - pow(1.0 - f, 1.0 / CURVE)
	return t * float(XP_MAX.get(id, 100.0))


func _refresh(id: StringName, force_emit := false, allow_announce := true) -> void:
	var before := float(skills.get(id, 0.0))
	var v := value_for_xp(id, float(xp[id]))
	skills[id] = v
	if allow_announce and announce and v > before and int(v / ANNOUNCE_STEP) > int(before / ANNOUNCE_STEP) and v >= ANNOUNCE_STEP:
		Game.notify("%s increased to %d%%" % [NAMES[id], int(v / ANNOUNCE_STEP) * ANNOUNCE_STEP], &"good")
		skill_levelled.emit(id, v)
	if id == &"driving":
		_apply_vehicle_skill(_vehicle_applied)
	_emit(id, force_emit)


func _emit(id: StringName, force: bool) -> void:
	var v := float(skills[id])
	if force or absf(v - float(_emitted[id])) >= 0.25:
		_emitted[id] = v
		Events.skill_changed.emit(id, v)


# ======================================================================================================== event hooks
func _connect_player() -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p) or p == _player_connected:
		return
	_player_connected = p
	if p.has_signal("landed"):
		p.landed.connect(_on_player_landed)


func _on_player_landed(drop: float, damage: float) -> void:
	# surviving a fall makes the body tougher (strength); the damage itself is reduced by get_modifier(&"fall_damage")
	if drop > 3.0 and damage < float(Game.player.max_health):
		record(&"strength", clampf(drop * 0.12, 0.2, 2.0))


func _on_hit_marker(kill: bool) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	var w = p.get("weapons")
	var melee := true
	var headshot := false
	if w != null:
		var cur: StringName = w.get("current_id") if w.get("current_id") != null else &"fists"
		melee = WeaponDefs.is_melee(cur) if WeaponDefs.has(cur) else true
		var tgt = w.get("last_target")
		if tgt != null and is_instance_valid(tgt):
			var info = tgt.get("last_damage_info")
			if info is Dictionary and info.get("zone", &"") == GC.ZONE_HEAD:
				headshot = true
	if melee:
		record(&"strength", 3.0 if kill else 1.0)
	else:
		record(&"shooting", (3.0 if kill else 1.0) + (1.0 if headshot else 0.0))


func _on_vehicle_entered(vehicle: Node, character: Node, _seat: int) -> void:
	if character == Game.player:
		_apply_vehicle_skill(vehicle)


func _on_vehicle_exited(vehicle: Node, character: Node) -> void:
	if character == Game.player:
		_apply_vehicle_skill(null)
		if is_instance_valid(vehicle):
			_set_vehicle_skill(vehicle, 1.0, 0.0)
		_air_time = 0.0
		_air_paid = 0.0


## Driving benefit: the car model reads `skill_grip` (tyre grip multiplier) and `skill_recovery` (drift grip floor); tiny
## fields on CarVehicle (additive hook, see docs/api/systems_a.md).
func _apply_vehicle_skill(vehicle: Node) -> void:
	_vehicle_applied = vehicle
	if vehicle == null or not is_instance_valid(vehicle):
		return
	_set_vehicle_skill(vehicle, get_modifier(&"vehicle_grip"), get_modifier(&"vehicle_recovery"))


func _set_vehicle_skill(vehicle: Node, grip: float, recovery: float) -> void:
	if vehicle.get("skill_grip") != null:
		vehicle.set("skill_grip", grip)
		vehicle.set("skill_recovery", recovery)


# ======================================================================================================== activity sampler
func _process(delta: float) -> void:
	if not sampling:
		return
	_acc += delta
	if _acc < 0.1:
		return
	var dt := _acc
	_acc = 0.0
	if _player_connected == null or not is_instance_valid(_player_connected):
		_connect_player()
	var p = Game.player
	if p == null or not is_instance_valid(p) or p.is_dead:
		return
	var veh = p.current_vehicle if p.is_in_vehicle() else null
	if veh != null and is_instance_valid(veh):
		_sample_vehicle(p, veh, dt)
	else:
		_air_time = 0.0
		_air_paid = 0.0
		_sample_on_foot(p, dt)


func _sample_on_foot(p: Node, dt: float) -> void:
	# stealth: moving crouched near people who could notice you
	if p.get("crouching") == true and p.get_speed_xz() > 0.5:
		var near := false
		for n in get_tree().get_nodes_in_group(GC.G_NPC):
			if n is Node3D and (n as Node3D).global_position.distance_squared_to(p.global_position) < 22.0 * 22.0 and n.get("is_dead") != true:
				near = true
				break
		if near:
			record(&"stealth", dt * 0.14)


func _sample_vehicle(p: Node, v: Node, dt: float) -> void:
	var vclass: StringName = v.get("vclass") if v.get("vclass") != null else GC.VC_CAR
	var speed := 0.0
	if v is RigidBody3D:
		speed = (v as RigidBody3D).linear_velocity.length()
	match vclass:
		GC.VC_CAR, GC.VC_BIKE:
			_sample_driving(v, speed, dt)
		GC.VC_BICYCLE:
			if speed > 3.0:
				record(&"stamina", dt * 0.45)
		GC.VC_HELI, GC.VC_PLANE:
			var agl: float = (v as Node3D).global_position.y - WorldLayout.terrain_height(v.global_position.x, v.global_position.z)
			if agl > 4.0 and speed > 5.0:
				record(&"flying", dt * 0.5)
		_:
			pass


func _sample_driving(v: Node, speed: float, dt: float) -> void:
	if v.get("is_ai_controlled") == true:
		return
	if speed > 10.0:
		record(&"driving", dt * 0.06)
	var steer := absf(float(v.get("input_steer") if v.get("input_steer") != null else 0.0))
	if speed > 14.0 and steer > 0.45:
		record(&"driving", dt * 0.6)                       # hard turns at speed
	if speed > 7.0 and v.has_method("get_slip_angle"):
		if absf(float(v.get_slip_angle())) > 0.28:
			record(&"driving", dt * 1.0)                   # drifting
	# airtime: all wheels off the ground
	var grounded = v.get("grounded_count")
	if grounded != null and int(grounded) == 0 and speed > 7.0:
		_air_time += dt
		if _air_time > 0.35 and _air_paid < 12.0:
			var pay := dt * 1.5
			_air_paid += pay
			record(&"driving", pay)
	else:
		_air_time = 0.0
		_air_paid = 0.0
	# near misses with other vehicles at speed
	_near_cd = maxf(_near_cd - dt, 0.0)
	if speed > 11.0:
		_track_near_misses(v, speed)


func _track_near_misses(me: Node, speed: float) -> void:
	var mp: Vector3 = (me as Node3D).global_position
	var seen: Dictionary = {}
	for o in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if o == me or not (o is Node3D):
			continue
		var d := Vector2((o as Node3D).global_position.x - mp.x, (o as Node3D).global_position.z - mp.z).length()
		var id := o.get_instance_id()
		if d < 7.0:
			seen[id] = true
			_near[id] = minf(float(_near.get(id, 99.0)), d)
	for id in _near.keys():
		if seen.has(id):
			continue
		var best := float(_near[id])
		_near.erase(id)
		if best >= NEAR_MISS_MIN and best <= NEAR_MISS_MAX and _near_cd <= 0.0 and speed > 11.0:
			_near_cd = 2.0
			record(&"driving", 3.0)
