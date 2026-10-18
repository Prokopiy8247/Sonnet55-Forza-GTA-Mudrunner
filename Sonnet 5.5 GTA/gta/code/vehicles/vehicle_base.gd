class_name VehicleBase
extends RigidBody3D
## Base of every drivable vehicle (Vehicles agent). Public members of the original stub contract are all kept.
## Orientation: local -Z is forward, +X right, +Y up (Blender +Y forward after GLB export). Origin = ground point under the
## wheelbase centre. Controls (input_*) are written by whoever drives (player / traffic / police AI) every physics frame.
##
## Subclasses implement the physics: CarVehicle (4/6 wheel raycast suspension), BikeVehicle (motorcycle + bicycle).
## Later waves add BoatVehicle / HeliVehicle / PlaneVehicle by subclassing and overriding _simulate().
## Created exclusively through VehicleFactory.spawn(); components: VehicleLights, VehicleAudio, VehicleDamage.

signal occupant_entered(character: Node, seat: int)
signal occupant_exited(character: Node, seat: int)
signal destroyed(killer: Node)
signal health_changed(health: float, max_health: float)
signal collided(other: Node, impact: float)       # additive: any impact above ~3 m/s
signal tire_punctured(wheel_index: int)           # additive

const G := 9.81
const SEAT_SPECS := [
	[&"SeatDriver", &"driver"], [&"SeatPassenger", &"passenger"], [&"SeatPilot", &"driver"], [&"SeatCopilot", &"passenger"],
	[&"SeatRearL", &"rear_l"], [&"SeatRearR", &"rear_r"],
]
const IMPACT_MIN := 3.0              # m/s velocity change counted as a crash
const SIT_HIP_DROP := 0.085         # Seat* empties are PELVIS points; the seated character origin sits this far below (CharacterRig sit pose)

# ---- Identity (filled by VehicleFactory.spawn) -----------------------------------------------------
var def_id: StringName = &""
var def: Dictionary = {}
var vclass: StringName = GC.VC_CAR
var faction: StringName = GC.F_CIVILIAN        # GC.F_POLICE for police cruisers / helicopters
var display_name := "Vehicle"

# ---- Controls (driver writes, vehicle reads) ----------------------------------------------------------
var input_throttle := 0.0        # 0..1 accelerator (planes: target throttle)
var input_brake := 0.0           # 0..1 brake (acts as reverse when almost stopped)
var input_steer := 0.0           # -1 left .. +1 right
var input_handbrake := false
var input_pitch := 0.0           # air/bike: -1..1, +1 = nose up
var input_roll := 0.0            # air: -1..1, +1 = roll right
var input_yaw := 0.0             # air: -1..1, +1 = yaw right
var input_collective := 0.0      # helicopter: -1 descend .. +1 climb
var input_horn := false

# ---- State ------------------------------------------------------------------------------------------------
var max_health := 1000.0
var health := 1000.0
var is_destroyed := false
var on_fire := false
var engine_on := false
var headlights_on := false
var siren_on := false
var seats: Array = []            # [{"name": &"driver", "character": null, "entry": Vector3, "exit": Vector3, "can_shoot": false, ...}]
var driver: Node = null
var is_player_owned := false     # bought / stored in the player's garage
var is_stolen := false           # taken from an NPC (police interest)
var paint_primary := Color(0.8, 0.1, 0.1)
var paint_secondary := Color(0.1, 0.1, 0.1)
var mods: Dictionary = {}        # applied customization (see VehicleDefs.MOD_EFFECTS)
var is_ai_controlled := false    # true while TrafficManager / PoliceManager drives it

# ---- Additive public state ---------------------------------------------------------------------------------
var paint_finish: StringName = &"gloss"
var abandoned := false           # free to take: entering it is never a crime (spawned for the player)
var keep_engine_on := false      # AI parking: do not switch the engine off when the driver leaves
var run_over_enabled := true     # vehicle hurts pedestrians it drives into (disable if the NPC module handles it)
var water_depth := 0.0           # metres the body centre is below the sea surface (0 = dry)
var gear := 1                    # -1 reverse, 0 neutral, 1..n
var rpm := 0.0
var damage_taken_mult := 1.0     # armour mods
var bulletproof_tires := false
var visual_lod := 0              # 0 full, 1 reduced (far from camera: no wheel/particle visuals), set by VehicleSystem
var sim_stride := 1              # OPTIONAL cost hook (default 1 = every tick). 2/3 re-applies the last forces on the in-between ticks - cheap but only safe for far, slow AI cars; unused by default (a vehicle tick costs ~35 us)
var last_collision_time := -100.0
var last_driver: Node = null

# ---- Internals -----------------------------------------------------------------------------------------------
var model: Node3D = null
var minfo: Dictionary = {}
var wheels: Array[VehicleWheel] = []
var lights: VehicleLights = null
var audio: VehicleAudio = null
var dmg: VehicleDamage = null

var _seat_nodes: Array[Node3D] = []
var _door_nodes: Array[Node3D] = [null, null, null, null]      # front left, front right, rear left, rear right
var _door_rest: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY]
var _door_open: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _door_target: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _door_close_timer: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _enter_blend: Dictionary = {}                      # character -> {t, dur, from: Transform3D}
var _orig_parent: Dictionary = {}                      # character -> Node
var _saved_layers: Dictionary = {}                     # character -> Vector2i(layer, mask)
var _prev_vel := Vector3.ZERO
var _skip_dv := 3
var _impact_acc := 0.0
var _impact_timer := 0.0
var _last_contact: Node = null
var _last_contact_t := -10.0
var _runover_cd: Dictionary = {}
var _idle_time := 0.0
var _pending_sleep := false
var _frozen_until_ground := false
var _flip_time := 0.0
var _engine_off_timer := -1.0
var _submerged_time := 0.0
var _tick := 0
var _stagger := 0
var _fire_dot_t := 0.0
var _despawn_timer := -1.0
var _killer: Node = null
var _steer_bias := 0.0                                # damaged alignment pull
var _horn_cd := 0.0
var _auto_lights_t := 0.0
var auto_headlights := true          # AI vehicles switch their lights on at night / rain / fog by themselves (never forces them off by day)
var _auto_lights_on := false
var _acc_light := 0.0
var _acc_dmg := 0.0
var _acc_audio := 0.0
var _run_query: PhysicsShapeQueryParameters3D = null
var _scene_time := 0.0
var _query_ray: PhysicsRayQueryParameters3D = null
var _static_hold := false
var power_scale := 1.0                                # damage / mods multiplier on engine power
var mod_power := 1.0
var mod_brake := 1.0
var mod_grip := 1.0
var mod_shift := 1.0
var mod_downforce := 0.0
var mod_susp := 1.0
# ---- garage / customization additions (Garage agent, additive) ----
var mod_turbo_boost := 0.0            # extra power fraction at full turbo boost (CarVehicle spools it up under throttle)
var mod_turbo_spool := 1.0            # seconds-ish factor of the spool-up (higher = slower)
var mod_tire_hits := 1                # hits needed to puncture a tyre (1 = stock, 99 = bullet-resistant)
var mod_topspeed := 1.0               # >1: engine upgrades lengthen the gearing (CarVehicle divides the gear ratios by it)
var _tire_hit_count: Dictionary = {}  # wheel index -> hits taken
## Set by the GarageSystem: Callable(vehicle) that (re)builds the cosmetic parts / livery / plates / underglow from `mods`.
static var visual_mods_hook: Callable = Callable()
static var _extra_fx: Dictionary = {}
static var _extra_fx_loaded := false

static var prof_on := false              # tests: accumulate the cost of _physics_process (microseconds)
static var prof_usec := 0
static var prof_calls := 0
static var _exit_capsule: CapsuleShape3D = null
static var _run_box: BoxShape3D = null


func _ready() -> void:
	add_to_group(GC.G_VEHICLE)
	add_to_group(GC.G_DAMAGEABLE)
	if faction == GC.F_POLICE:
		add_to_group(GC.G_POLICE)
	body_entered.connect(_on_body_entered)


# =====================================================================================================
# Speed
# =====================================================================================================
func get_speed() -> float:
	return linear_velocity.length()


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func get_forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z)


func get_rpm01() -> float:
	var idle: float = def.get("rpm_idle", 900.0)
	var red: float = def.get("rpm_red", 6500.0)
	return clampf((rpm - idle) / maxf(red - idle, 1.0), 0.0, 1.0)


func get_gear() -> int:
	return gear


func get_health_ratio() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


# =====================================================================================================
# Occupants
# =====================================================================================================
func is_occupied() -> bool:
	return driver != null


func get_driver() -> Node:
	return driver


## Index of a free seat, or -1.
func get_free_seat() -> int:
	for i in seats.size():
		if seats[i]["character"] == null:
			return i
	return -1


func get_seat_count() -> int:
	return seats.size()


func get_occupants() -> Array:
	var out: Array = []
	for s in seats:
		if s["character"] != null and is_instance_valid(s["character"]):
			out.append(s["character"])
	return out


func can_be_entered_by(_character: Node) -> bool:
	return not is_destroyed and (not is_flipped_over())


func is_flipped_over() -> bool:
	return global_transform.basis.y.y < 0.1


func get_seat_of(character: Node) -> int:
	for i in seats.size():
		if seats[i]["character"] == character:
			return i
	return -1


func _is_player_char(c: Node) -> bool:
	return c != null and c.has_method("is_player") and c.is_player()


## Picks the seat whose door is closest to the character (free seats, plus the driver seat for carjacking).
func _pick_seat_for(character: Node) -> int:
	var pos: Vector3 = (character as Node3D).global_position if character is Node3D else global_position
	var best := -1
	var best_d := INF
	for i in seats.size():
		var occ = seats[i]["character"]
		if occ != null and (i != 0 or not is_instance_valid(occ)):
			if occ != null and is_instance_valid(occ):
				continue
		var d := get_entry_position(i).distance_squared_to(pos)
		# small bias so that a free driver seat wins ties with the passenger door
		if i == 0:
			d *= 0.8
		if d < best_d:
			best_d = d
			best = i
	return best


## Full entry logic used by the player and AI: free seat -> enter; occupied driver -> carjack
## (pull the driver out, crime events, fight-or-flee reaction); includes the enter transition (character glides
## from where it stands through the opening door into the seat).  Returns true if the character is seated.
func request_enter(character: Node, seat: int = -1) -> bool:
	if character == null or not is_instance_valid(character) or not can_be_entered_by(character):
		return false
	if character.has_method("is_in_vehicle") and character.is_in_vehicle():
		return false
	var s := seat if seat >= 0 else _pick_seat_for(character)
	if s < 0 or s >= seats.size():
		return false
	var occ = seats[s]["character"]
	var player_char := _is_player_char(character)
	if occ != null and is_instance_valid(occ):
		if s != 0 or occ == character:
			return false
		_carjack(character, occ, player_char)
	elif s == 0 and player_char:
		_report_theft(character)
	return enter(character, s, true)


func _report_theft(character: Node) -> void:
	if is_stolen or abandoned or is_player_owned:
		return
	var crime := GC.CRIME_POLICE_VEHICLE_THEFT if faction == GC.F_POLICE else GC.CRIME_VEHICLE_THEFT
	is_stolen = true
	Events.crime_committed.emit(crime, global_position, character, {"vehicle": self, "witnessed_by_npc": false, "severity": 1.0})


func _carjack(thief: Node, victim: Node, player_char: bool) -> void:
	_set_door_seat(0, 1.0)
	exit(victim, true, true)
	if victim.has_method("on_carjacked"):
		victim.on_carjacked(thief)
	else:
		_default_carjack_reaction(victim, thief)
	if player_char:
		var crime := GC.CRIME_POLICE_VEHICLE_THEFT if faction == GC.F_POLICE else GC.CRIME_CARJACK
		is_stolen = true
		Events.crime_committed.emit(crime, global_position, thief, {"vehicle": self, "victim": victim, "severity": 1.5})
	if victim is Node3D and thief is Node3D:
		var away: Vector3 = ((victim as Node3D).global_position - (thief as Node3D).global_position)
		away.y = 0.0
		if away.length() < 0.1:
			away = global_transform.basis.x * seats[0].get("side", -1.0)
		if victim.has_method("knockback"):
			victim.knockback(away.normalized() * 3.5 + Vector3.UP * 1.0)
	if victim.get("rig") != null and victim.rig.has_method("play_action"):
		victim.rig.play_action(&"hands_up")


func _default_carjack_reaction(_victim: Node, _thief: Node) -> void:
	pass


## Immediate seating. `animated` blends the character from where it stands into the seat (used by request_enter).
func enter(character: Node, seat: int = 0, animated: bool = false) -> bool:
	if character == null or not is_instance_valid(character) or not (character is Node3D):
		return false
	if seat < 0 or seat >= seats.size():
		return false
	var occ = seats[seat]["character"]
	if occ != null and is_instance_valid(occ):
		return false
	var c3 := character as Node3D
	seats[seat]["character"] = character
	if seat == 0:
		driver = character
		last_driver = character
		_engine_off_timer = -1.0
		if _is_player_char(character):
			is_ai_controlled = false
			reset_controls()
	_orig_parent[character] = character.get_parent()
	_saved_layers[character] = Vector2i(character.collision_layer, character.collision_mask) if character is CollisionObject3D else Vector2i.ZERO
	var from_xf := c3.global_transform
	if character is CollisionObject3D:
		character.collision_layer = 0
		character.collision_mask = 0
	var anchor: Node3D = _seat_nodes[seat]
	if character.get_parent() != null:
		character.reparent(anchor, false)
	else:
		anchor.add_child(character)
	if animated and is_inside_tree() and seat < _seat_nodes.size():
		c3.global_transform = from_xf
		_enter_blend[character] = {"t": 0.0, "dur": 0.55 if vclass == GC.VC_CAR else 0.45, "from": c3.transform}
		_set_door_seat(seat, 1.0)
	else:
		c3.transform = Transform3D.IDENTITY
	if character.has_method("set_vehicle"):
		character.set_vehicle(self, seat)
	_apply_sit_stance(character, true)
	if character.has_signal("died") and not character.died.is_connected(_on_occupant_died):
		character.died.connect(_on_occupant_died.bind(character))
	if not character.tree_exiting.is_connected(_on_occupant_freed):
		character.tree_exiting.connect(_on_occupant_freed.bind(character))
	if seat == 0:
		_start_engine_sequence()
	occupant_entered.emit(character, seat)
	Events.vehicle_entered.emit(self, character, seat)
	if audio != null:
		audio.play_door(true)
	return true


func _apply_sit_stance(character: Node, sit: bool) -> void:
	var rig = character.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("set_stance"):
		var stance: StringName = &"stand"
		if sit and rig.has_method("set_seat"):
			rig.set_seat(&"driver" if get_seat_of(character) == 0 else &"passenger", Vector3.ZERO)
		if sit:
			stance = &"sit_bike" if vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE else &"sit_car"
		rig.set_stance(stance)
		if sit and rig.has_method("play_action"):
			rig.play_action(&"enter_vehicle")


func _start_engine_sequence() -> void:
	if engine_on or is_destroyed:
		return
	if audio != null:
		audio.play_ignition()
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_instance_valid(self) and driver != null and not is_destroyed and water_depth < 0.6:
			set_engine(true))


## Releases a character from its seat. `forced`: carjacked / ejected (damage + knockback when moving fast).
func exit(character: Node, forced: bool = false, _carjack_exit: bool = false) -> void:
	var idx := get_seat_of(character)
	if idx < 0:
		return
	seats[idx]["character"] = null
	_enter_blend.erase(character)
	if idx == 0:
		driver = null
		reset_controls()
		if not keep_engine_on and not is_ai_controlled and not forced:
			_engine_off_timer = 0.7
		elif forced and not is_ai_controlled:
			_engine_off_timer = 4.0 if not is_destroyed else 0.0
	if not is_instance_valid(character):
		return
	if character.has_signal("died") and character.died.is_connected(_on_occupant_died):
		character.died.disconnect(_on_occupant_died)
	if character.tree_exiting.is_connected(_on_occupant_freed):
		character.tree_exiting.disconnect(_on_occupant_freed)
	var c3 := character as Node3D
	var place: Vector3 = _find_exit_position(idx, forced)
	var parent: Node = _orig_parent.get(character, null)
	_orig_parent.erase(character)
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		parent = Game.world if Game.world != null else Game.main
	if c3 != null:
		var yaw := global_transform.basis.get_euler().y
		if c3.get_parent() != null:
			c3.reparent(parent, false)
		else:
			parent.add_child(c3)
		c3.global_transform = Transform3D(Basis(Vector3.UP, yaw), place)
	var saved: Vector2i = _saved_layers.get(character, Vector2i(-1, -1))
	_saved_layers.erase(character)
	if character is CollisionObject3D:
		if saved.x >= 0:
			character.collision_layer = saved.x
			character.collision_mask = saved.y
	if character.get("velocity") != null:
		var v: Vector3 = linear_velocity
		v.y = maxf(v.y, 0.0)
		character.velocity = v * (0.85 if forced else 0.55)
	if character.has_method("set_vehicle"):
		character.set_vehicle(null, -1)
	_apply_sit_stance(character, false)
	var speed := linear_velocity.length()
	if speed > 7.5 and character.has_method("apply_damage"):
		var dmg_amt := (speed - 7.5) * (2.2 if forced else 1.2)
		character.apply_damage(dmg_amt, {"source": self, "type": GC.DMG_FALL, "zone": GC.ZONE_TORSO, "position": place, "impulse": speed})
		if forced and character.has_method("knockback"):
			character.knockback(linear_velocity * 0.6 + Vector3.UP * 3.0)
		var rig = character.get("rig")
		if rig != null and is_instance_valid(rig) and rig.has_method("play_action"):
			rig.play_action(&"hit_react")
	_set_door_seat(idx, 1.0)
	if audio != null:
		audio.play_door(false)
	occupant_exited.emit(character, idx)
	Events.vehicle_exited.emit(self, character)


func _on_occupant_died(_killer_node: Node, _info: Dictionary, character: Node) -> void:
	exit(character, true)


func _on_occupant_freed(character: Node) -> void:
	var idx := get_seat_of(character)
	if idx < 0:
		return
	seats[idx]["character"] = null
	_enter_blend.erase(character)
	_orig_parent.erase(character)
	_saved_layers.erase(character)
	if idx == 0:
		driver = null
		reset_controls()


func get_entry_position(seat: int = 0) -> Vector3:
	if seat >= 0 and seat < seats.size():
		return global_transform * (seats[seat]["entry"] as Vector3)
	return global_position


func get_exit_position(seat: int = 0) -> Vector3:
	if seat >= 0 and seat < seats.size():
		return global_transform * (seats[seat]["exit"] as Vector3)
	return global_position + global_transform.basis.x * 2.0


func get_seat_transform(seat: int = 0) -> Transform3D:
	return get_seat_world_transform(seat)


func get_seat_world_transform(seat: int = 0) -> Transform3D:
	if seat >= 0 and seat < _seat_nodes.size():
		return _seat_nodes[seat].global_transform
	return global_transform


## World transform of the hand/weapon socket for drive-by shooting from a seat (near the window on the seat's side).
## -Z of the returned basis points to the side the occupant is aiming; the Player agent re-aims it.
func get_weapon_socket(seat: int = 0) -> Transform3D:
	if seat < 0 or seat >= seats.size():
		return global_transform
	var side: float = float(seats[seat].get("side", -1.0))
	var local: Vector3 = (seats[seat]["pos"] as Vector3) + Vector3(side * 0.42, 0.95, -0.15)
	if vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE:
		local = (seats[seat]["pos"] as Vector3) + Vector3(side * 0.30, 0.98, -0.30)
	var b := global_transform.basis
	var aim := b * Vector3(side, 0.0, -0.2).normalized()
	return Transform3D(Basis.looking_at(aim, Vector3.UP), global_transform * local)


func can_shoot_from_seat(seat: int) -> bool:
	return seat >= 0 and seat < seats.size() and bool(seats[seat].get("can_shoot", false))


# ---- Exit placement ------------------------------------------------------------------------------------------
func _find_exit_position(seat_idx: int, forced: bool) -> Vector3:
	var xf := global_transform
	var cands: Array[Vector3] = []
	cands.append(xf * (seats[seat_idx]["exit"] as Vector3))
	var other := -float(seats[seat_idx].get("side", -1.0))
	var half_w: float = float(def.get("width", 1.8)) * 0.5
	cands.append(xf * Vector3(other * (half_w + 0.75), 0.0, (seats[seat_idx]["pos"] as Vector3).z))
	cands.append(xf * (seats[seat_idx]["exit"] as Vector3 + Vector3(0, 0, 1.4)))
	cands.append(xf * Vector3(0, 0, float(def.get("length", 4.5)) * 0.5 + 1.0))
	cands.append(xf * Vector3(0, 0, -float(def.get("length", 4.5)) * 0.5 - 1.0))
	var space := get_world_3d().direct_space_state
	if _exit_capsule == null:
		_exit_capsule = CapsuleShape3D.new()
		_exit_capsule.radius = 0.32
		_exit_capsule.height = 1.7
	var first_ground := Vector3.ZERO
	for i in cands.size():
		var p: Vector3 = cands[i]
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.6, p + Vector3.DOWN * 3.0, GC.M_GROUND)
		ray.exclude = [get_rid()]
		var hit := space.intersect_ray(ray)
		var ground: Vector3 = p
		if not hit.is_empty():
			ground = hit.position
		ground.y += 0.04
		if i == 0:
			first_ground = ground
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _exit_capsule
		q.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.92)
		q.collision_mask = GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
		q.exclude = [get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return ground
	# nothing free: forced exits go on top of the roof edge, normal exits stay at the door
	return first_ground + (Vector3.UP * (1.0 if forced else 0.0))


## Vertical slice of the "get out" prompt for the Player module.
func get_interaction(character: Node) -> Dictionary:
	if is_destroyed:
		return {"text": "", "key": "F", "enabled": false}
	if has_meta(&"taxi_prompt"):      # Transit service (additive): taxi hailed by the player shows its own prompt instead of "Carjack"
		return {"text": String(get_meta(&"taxi_prompt")), "key": "F", "enabled": true}
	var occ = driver
	var text := "Enter " + display_name
	if occ != null and is_instance_valid(occ) and occ != character:
		text = "Carjack " + display_name
	elif faction == GC.F_POLICE and not abandoned:
		text = "Steal " + display_name
	return {"text": text, "key": "F", "enabled": can_be_entered_by(character)}


func interact(character: Node) -> void:
	request_enter(character)


# =====================================================================================================
# Damage / state
# =====================================================================================================
## Damage contract: info keys as in CharacterBase.apply_damage plus "zone" may be GC.ZONE_TIRE / GLASS / ENGINE.
func apply_damage(amount: float, info: Dictionary = {}) -> void:
	if is_destroyed or amount <= 0.0:
		return
	if has_meta("invulnerable") and get_meta("invulnerable"):
		return
	var t: StringName = info.get("type", GC.DMG_BULLET)
	var zone: StringName = info.get("zone", GC.ZONE_BODY)
	var wpos: Vector3 = info.get("position", global_position)
	wake()
	# bullets: classify the hit area from the impact point when the shooter did not
	if t == GC.DMG_BULLET and (not info.has("zone") or zone == GC.ZONE_TORSO or zone == GC.ZONE_LIMB or zone == GC.ZONE_HEAD):
		zone = _classify_hit(to_local(wpos))
	var real := amount
	match t:
		GC.DMG_BULLET:
			real *= float(def.get("bullet_mult", 1.0)) * damage_taken_mult
		GC.DMG_EXPLOSION:
			real *= float(def.get("explosion_mult", 1.0)) * damage_taken_mult
		GC.DMG_COLLISION, GC.DMG_RUNOVER:
			real *= damage_taken_mult
		GC.DMG_FIRE:
			pass
		_:
			real *= damage_taken_mult
	if t == GC.DMG_BULLET:
		match zone:
			GC.ZONE_TIRE:
				var wi := _nearest_wheel(to_local(wpos))
				if wi >= 0 and not bulletproof_tires:
					_tire_hit_count[wi] = int(_tire_hit_count.get(wi, 0)) + 1
					if int(_tire_hit_count[wi]) >= mod_tire_hits:
						puncture_wheel(wi)
				real *= 0.1
			GC.ZONE_GLASS:
				if dmg != null:
					dmg.hit_glass()
				real *= 0.3
				_hit_occupant(amount, info, wpos)
			GC.ZONE_ENGINE:
				real *= 1.6
	var killer: Node = info.get("source", null)
	_apply_health_loss(real, killer, info)
	if t == GC.DMG_BULLET and dmg != null:
		dmg.spark_at(wpos, info.get("direction", Vector3.UP))


func _apply_health_loss(amount: float, killer: Node, info: Dictionary = {}) -> void:
	if is_destroyed or amount <= 0.0:
		return
	if killer != null:
		_killer = killer
	health = maxf(health - amount, 0.0)
	_update_damage_state()
	health_changed.emit(health, max_health)
	Events.vehicle_damaged.emit(self, amount, info)
	if health <= 0.0:
		explode(_killer)


func _update_damage_state() -> void:
	var r := get_health_ratio()
	power_scale = lerpf(0.45, 1.0, clampf(r / 0.55, 0.0, 1.0))
	_steer_bias = 0.0 if r > 0.6 else (1.0 - r / 0.6) * 0.1 * signf(float(get_instance_id() % 2) - 0.5)
	if not is_destroyed and r < 0.15 and not on_fire:
		on_fire = true
	if dmg != null:
		dmg.damage_state_changed(r)


func _classify_hit(local: Vector3) -> StringName:
	var h := float(def.get("height", 1.45))
	var len_ := float(def.get("length", 4.5))
	# near a wheel -> tyre
	if _nearest_wheel(local, 1.15) >= 0 and local.y < float(def.get("wheel_radius", 0.33)) * 2.1:
		return GC.ZONE_TIRE
	if local.y > h * 0.62 and local.z > -len_ * 0.28:
		return GC.ZONE_GLASS
	if local.z < -len_ * 0.25 and local.y > h * 0.35 and local.y < h * 0.75:
		return GC.ZONE_ENGINE
	return GC.ZONE_BODY


func _nearest_wheel(local: Vector3, radius_mult: float = 2.5) -> int:
	var best := -1
	var best_d := INF
	for i in wheels.size():
		var w := wheels[i]
		var d := Vector2(local.x - w.rest.x, local.z - w.rest.z).length()
		if d < best_d and d < w.radius * radius_mult + 0.1:
			best_d = d
			best = i
	return best


func _hit_occupant(amount: float, info: Dictionary, wpos: Vector3) -> void:
	if randf() > 0.4:
		return
	var best: Node = null
	var best_d := INF
	for c in get_occupants():
		var d: float = (c as Node3D).global_position.distance_squared_to(wpos)
		if d < best_d:
			best_d = d
			best = c
	if best != null and best.has_method("apply_damage"):
		var i2 := info.duplicate()
		i2["zone"] = GC.ZONE_TORSO if randf() < 0.7 else GC.ZONE_HEAD
		best.apply_damage(amount * 0.8 * damage_taken_mult, i2)


func puncture_wheel(index: int) -> void:
	if index < 0 or index >= wheels.size() or wheels[index].flat:
		return
	wheels[index].flat = true
	tire_punctured.emit(index)
	if audio != null:
		audio.play_burst()


func repair_tires() -> void:
	_tire_hit_count.clear()
	for w in wheels:
		w.flat = false


func wake() -> void:
	if sleeping:
		sleeping = false
	_idle_time = 0.0
	_pending_sleep = false


## Blows the vehicle up: big hop, occupants thrown out and hurt, area damage (chain reaction), wreck look, despawn timer.
func explode(killer: Node = null) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	on_fire = false
	health = 0.0
	engine_on = false
	siren_on = false
	headlights_on = false
	reset_controls()
	_despawn_timer = 60.0
	wake()
	var pos := global_position + Vector3.UP * 0.6
	var radius := clampf(float(def.get("length", 4.5)) * 1.5, 6.0, 12.0)
	# occupants are thrown out and hurt (explosion kills anyone without armour in most cases)
	for c in get_occupants():
		exit(c, true)
		if c.has_method("apply_damage"):
			c.apply_damage(95.0, {"source": killer if killer != null else self, "type": GC.DMG_EXPLOSION, "zone": GC.ZONE_TORSO, "position": pos})
		if c.has_method("knockback"):
			c.knockback(Vector3(randf_range(-4, 4), 7.0, randf_range(-4, 4)))
	# hop + tumble
	apply_central_impulse(Vector3(randf_range(-0.4, 0.4), 1.0, randf_range(-0.4, 0.4)) * mass * 5.5)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * mass * 1.8)
	if lights != null:
		lights.set_wrecked()
	if audio != null:
		audio.on_destroyed()
	# the Weapons module owns the blast (damage falloff, impulses, fireball, sound, camera shake, chain reactions)
	var used_combat := false
	var cs = Game.sys(&"combat")
	if cs != null and cs.has_method("explode") and is_inside_tree():
		cs.explode(pos, radius, 150.0, killer, {"weapon": &"vehicle_explosion", "ignore": [self], "vehicle_mult": 6.0, "force": 9.0, "big": true})
		used_combat = true
	else:
		_blast_nearby(pos, radius, killer)
		Events.explosion.emit(pos, radius, self)
	if dmg != null:
		dmg.on_explode(not used_combat)
	destroyed.emit(killer)
	Events.vehicle_destroyed.emit(self, killer)


func _blast_nearby(pos: Vector3, radius: float, killer: Node) -> void:
	var src: Node = killer if killer != null else self
	var info := {"source": src, "type": GC.DMG_EXPLOSION, "zone": GC.ZONE_BODY, "position": pos, "from_vehicle_explosion": true}
	for n in get_tree().get_nodes_in_group(GC.G_DAMAGEABLE):
		if n == self or not (n is Node3D) or not is_instance_valid(n):
			continue
		var d := (n as Node3D).global_position.distance_to(pos)
		if d > radius:
			continue
		var f := 1.0 - d / radius
		if n is VehicleBase:
			if (n as VehicleBase).is_destroyed:
				continue
			var i2 := info.duplicate()
			i2["direction"] = ((n as Node3D).global_position - pos).normalized()
			(n as VehicleBase).apply_damage(950.0 * f * f + 120.0 * f, i2)
			(n as VehicleBase).apply_central_impulse(((n as Node3D).global_position - pos).normalized() * (n as VehicleBase).mass * 4.0 * f + Vector3.UP * (n as VehicleBase).mass * 2.0 * f)
		elif n.has_method("apply_damage"):
			if n is CharacterBase and n.current_vehicle == self:
				continue
			var i3 := info.duplicate()
			i3["direction"] = ((n as Node3D).global_position - pos).normalized()
			n.apply_damage(140.0 * f * f + 15.0 * f, i3)
			if n.has_method("knockback"):
				n.knockback(i3["direction"] * 11.0 * f + Vector3.UP * 5.0 * f)


func repair() -> void:
	health = max_health
	is_destroyed = false
	on_fire = false
	power_scale = 1.0
	_steer_bias = 0.0
	_despawn_timer = -1.0
	repair_tires()
	if dmg != null:
		dmg.repair()
	if lights != null:
		lights.repair()
	set_paint(paint_primary, paint_secondary, paint_finish)
	health_changed.emit(health, max_health)


## Returns the vehicle to a factory-fresh state so VehicleSystem can recycle it (only undamaged, unoccupied vehicles are pooled).
func reset_for_reuse() -> void:
	reset_controls()
	sim_stride = 1
	health = max_health
	is_destroyed = false
	on_fire = false
	engine_on = false
	headlights_on = false
	siren_on = false
	is_stolen = false
	abandoned = false
	is_player_owned = false
	keep_engine_on = false
	set_ai_controlled(false)
	faction = def.get("faction", GC.F_CIVILIAN)
	if faction != GC.F_POLICE and is_in_group(GC.G_POLICE):
		remove_from_group(GC.G_POLICE)
	if not mods.is_empty():
		apply_mods({})
	mods = {}
	damage_taken_mult = 1.0
	driver = null
	last_driver = null
	rpm = 0.0
	gear = 1
	power_scale = 1.0
	_steer_bias = 0.0
	freeze = false
	_frozen_until_ground = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_idle_time = 0.0
	_pending_sleep = false
	if has_meta("parked"):
		remove_meta("parked")
	if has_meta("dealer"):
		remove_meta("dealer")
	water_depth = 0.0
	_submerged_time = 0.0
	_flip_time = 0.0
	_despawn_timer = -1.0
	_engine_off_timer = -1.0
	_enter_blend.clear()
	_orig_parent.clear()
	_saved_layers.clear()
	_runover_cd.clear()
	_impact_acc = 0.0
	_skip_dv = 3
	visual_lod = 0
	for i in 4:
		_door_open[i] = 0.0
		_door_target[i] = 0.0
		_door_close_timer[i] = 0.0
		if _door_nodes[i] != null:
			_door_nodes[i].transform.basis = _door_rest[i]
	for s in seats:
		s["character"] = null
	for w in wheels:
		w.flat = false
		w.length = w.eq_len
		w.prev_length = w.eq_len
		w.w = 0.0
		w.spin = 0.0
		w.slip = 0.0
		w.grounded = false
		w.skid_active = false
		w.collider_id = 0
	if dmg != null:
		dmg.repair()
	if lights != null:
		lights.repair()
	if audio != null:
		audio.release()
	_reset_extra()
	set_paint(paint_primary, paint_secondary, paint_finish)


func _reset_extra() -> void:
	pass


func set_engine(on: bool) -> void:
	if on and (is_destroyed or water_depth > 0.6):
		return
	if engine_on == on:
		return
	engine_on = on
	if not on:
		rpm = 0.0
		if audio != null:
			audio.play_engine_off()


func toggle_headlights() -> void:
	headlights_on = not headlights_on


func toggle_siren() -> void:
	if String(def.get("siren", "")) == "" and not has_meta("has_siren"):
		return
	siren_on = not siren_on


func honk(hold: bool = true) -> void:
	input_horn = hold


func set_paint(primary: Color, secondary: Color = Color(-1, 0, 0), finish: StringName = &"gloss") -> void:
	paint_primary = primary
	if secondary.r >= 0.0:
		paint_secondary = secondary
	paint_finish = finish
	if model == null or is_destroyed:
		return
	Util.replace_material(model, "Paint", VehicleMaterials.paint(paint_primary, finish, false))
	var sec := paint_secondary if secondary.r >= 0.0 or paint_secondary != Color(0.1, 0.1, 0.1) else paint_secondary
	Util.replace_material(model, "Paint2", VehicleMaterials.paint(sec, finish, true))


func set_rim_color(color: Color) -> void:
	if model == null:
		return
	var m := StandardMaterial3D.new()
	m.resource_name = "Rim"
	m.albedo_color = color
	m.metallic = 0.7
	m.roughness = 0.3
	Util.replace_material(model, "Rim", m)


func set_window_tint(level: int) -> void:
	if dmg != null:
		dmg.set_tint(level)


## Applies customization levels (see VehicleDefs.MOD_EFFECTS). Unknown keys are ignored; safe to call repeatedly.
func apply_mods(new_mods: Dictionary) -> void:
	mods = new_mods
	var fx: Dictionary = _merged_mod_effects()
	mod_power = 1.0
	mod_brake = 1.0
	mod_grip = 1.0
	mod_shift = 1.0
	mod_downforce = 0.0
	mod_susp = 1.0
	mod_turbo_boost = 0.0
	mod_turbo_spool = 1.0
	mod_tire_hits = 1
	damage_taken_mult = 1.0
	bulletproof_tires = false
	var mass_mult := 1.0
	var health_mult := 1.0
	for key in new_mods:
		if not fx.has(key):
			continue
		var lvl := clampi(int(new_mods[key]), 0, 9)
		var table: Dictionary = fx[key]
		for stat in table:
			var arr: Array = table[stat]
			var v: float = arr[mini(lvl, arr.size() - 1)]
			match stat:
				"power": mod_power *= v
				"brake": mod_brake *= v
				"grip": mod_grip *= v
				"shift_time": mod_shift *= v
				"damage_taken": damage_taken_mult *= v
				"downforce": mod_downforce += v
				"susp_freq": mod_susp *= v
				"mass": mass_mult *= v
				"health": health_mult *= v
				"turbo_boost": mod_turbo_boost = maxf(mod_turbo_boost, v)
				"turbo_spool": mod_turbo_spool = maxf(mod_turbo_spool, v)
				"tire_hits": mod_tire_hits = maxi(mod_tire_hits, int(v))
	if int(new_mods.get("tires", 0)) >= 3:
		bulletproof_tires = true
	mass = float(def.get("mass", mass)) * mass_mult
	if not is_destroyed:
		var hr := get_health_ratio()
		max_health = float(def.get("health", max_health)) * health_mult
		health = max_health * hr
	# taller final drive with more power: the rev-limited top speed grows with the cube root of the extra power (damped)
	mod_topspeed = 1.0 + 0.45 * (pow(mod_power * (1.0 + mod_turbo_boost * 0.5), 1.0 / 3.0) - 1.0)
	if dmg != null:
		dmg.set_tint(int(new_mods.get("window_tint", 0)))
	if new_mods.has("rim_color") and new_mods["rim_color"] is Color:
		set_rim_color(new_mods["rim_color"])
	if new_mods.has("headlight_color") and lights != null:
		lights.set_xenon(new_mods["headlight_color"] == &"xenon" or new_mods["headlight_color"] == "xenon")
	_on_mods_changed()
	if visual_mods_hook.is_valid():
		visual_mods_hook.call(self)


func _on_mods_changed() -> void:
	pass


## VehicleDefs.MOD_EFFECTS plus the garage data table (gta/resources/data/vehicle_mods.gd wins). Loaded lazily, duck typed.
static func _merged_mod_effects() -> Dictionary:
	if not _extra_fx_loaded:
		_extra_fx_loaded = true
		var merged: Dictionary = VehicleDefs.MOD_EFFECTS.duplicate(true)
		var scr = load("res://gta/resources/data/vehicle_mods.gd")
		if scr is Script:
			var extra = scr.call("effects")
			if extra is Dictionary:
				for k in extra:
					merged[k] = extra[k]
		_extra_fx = merged
	return _extra_fx


func reset_controls() -> void:
	input_throttle = 0.0
	input_brake = 0.0
	input_steer = 0.0
	input_handbrake = false
	input_pitch = 0.0
	input_roll = 0.0
	input_yaw = 0.0
	input_collective = 0.0
	input_horn = false


## Hints for the chase camera: {"distance": 6.0, "height": 2.2, "look_ahead": 3.0, "fov": 75.0}
func get_camera_hints() -> Dictionary:
	var sp := clampf(get_speed() / 45.0, 0.0, 1.0)
	return {
		"distance": float(def.get("cam_distance", 6.2)) * (1.0 + sp * 0.12),
		"height": float(def.get("cam_height", 2.2)),
		"look_ahead": float(def.get("cam_look_ahead", 3.0)) * (0.6 + sp * 0.9),
		"fov": float(def.get("cam_fov", 75.0)) + sp * 12.0,
		"shake": sp * 0.3,
		"speed_kmh": get_speed_kmh(),
		"first_person_offset": (seats[0]["pos"] as Vector3) + Vector3(0, 1.15, -0.1) if seats.size() > 0 else Vector3(0, 1.3, 0),
	}


## Rights an overturned vehicle in place (also used by auto-recovery and the debug menu).
func unflip() -> void:
	var yaw := global_transform.basis.get_euler().y
	var p := global_position + Vector3.UP * 1.0
	global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_skip_dv = 3
	_flip_time = 0.0
	wake()


## Sets the velocity without it being mistaken for a crash (AI spawning / teleports / tests).
func set_velocity(vel: Vector3) -> void:
	linear_velocity = vel
	_prev_vel = vel
	_skip_dv = 2
	var fwd := -global_transform.basis.z
	var fs := vel.dot(fwd)
	for w in wheels:
		w.w = fs / maxf(w.radius, 0.1)


## Teleport helper that keeps the physics state clean (zero velocity, no fake crash detection).
func place_at(xf: Transform3D) -> void:
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_skip_dv = 3
	wake()


func set_ai_controlled(value: bool) -> void:
	is_ai_controlled = value
	if value:
		if not is_in_group(GC.G_TRAFFIC) and faction == GC.F_CIVILIAN:
			add_to_group(GC.G_TRAFFIC)
	else:
		if is_in_group(GC.G_TRAFFIC):
			remove_from_group(GC.G_TRAFFIC)


func is_submerged() -> bool:
	return water_depth > 0.6


# =====================================================================================================
# Simulation loop (subclasses implement _simulate)
# =====================================================================================================
func _physics_process(dt: float) -> void:
	_tick += 1
	_scene_time += dt
	if _frozen_until_ground:
		_check_ground_ready()
		return
	if sleeping and driver == null and not is_ai_controlled and not _has_input() and not _pending_sleep and _enter_blend.is_empty() and not on_fire:
		_sleep_tick(dt)
		return
	var t0 := Time.get_ticks_usec() if prof_on else 0
	_simulate(dt)
	_post_sim(dt)
	if prof_on:
		prof_usec += Time.get_ticks_usec() - t0
		prof_calls += 1


func _has_input() -> bool:
	return input_throttle > 0.01 or input_brake > 0.01 or absf(input_steer) > 0.01 or input_handbrake


func _simulate(_dt: float) -> void:
	pass


func _sleep_tick(dt: float) -> void:
	# asleep: only light bookkeeping (doors, timers, despawn)
	_tick_timers(dt)


func _check_ground_ready() -> void:
	if _tick % 20 != 0:
		return
	var from := global_position + Vector3.UP * 4.0
	var hit := Util.raycast(self, from, from + Vector3.DOWN * 40.0, GC.M_GROUND, [self])
	if not hit.is_empty():
		_frozen_until_ground = false
		freeze = false
		global_position = Vector3(global_position.x, hit.position.y + 0.12, global_position.z)
		linear_velocity = Vector3.ZERO
		_skip_dv = 3
		_pending_sleep = bool(has_meta("parked"))


func _tick_timers(dt: float) -> void:
	# doors
	for i in 4:
		if _door_nodes[i] != null and (absf(_door_open[i] - _door_target[i]) > 0.002):
			_door_open[i] = move_toward(_door_open[i], _door_target[i], dt * 3.2)
			var ang: float = (-1.0 if (i & 1) == 0 else 1.0) * _door_open[i] * deg_to_rad(62.0)
			_door_nodes[i].transform.basis = Basis(Vector3.UP, ang) * _door_rest[i]
		if _door_close_timer[i] > 0.0:
			_door_close_timer[i] -= dt
			if _door_close_timer[i] <= 0.0:
				_door_target[i] = 0.0
	# horn
	if _horn_cd > 0.0:
		_horn_cd -= dt
	if input_horn and _horn_cd <= 0.0 and not is_destroyed:
		_horn_cd = 0.55
		if audio != null:
			audio.play_horn()
		Events.vehicle_horn.emit(self)
	# engine auto-off after the driver left
	if _engine_off_timer >= 0.0:
		_engine_off_timer -= dt
		if _engine_off_timer < 0.0 and driver == null and not keep_engine_on:
			set_engine(false)
	# wreck despawn
	if _despawn_timer > 0.0:
		_despawn_timer -= dt
		if _despawn_timer <= 0.0:
			VehicleFactory.despawn(self)
			return
	# occupants glide into their seats
	if not _enter_blend.is_empty():
		_update_enter_blend(dt)


func _post_sim(dt: float) -> void:
	_tick_timers(dt)
	_detect_impacts(dt)
	if run_over_enabled and (_tick & 1) == 0 and absf(get_forward_speed()) > 3.2:
		_run_over_check(dt)
	_acc_light += dt
	_acc_dmg += dt
	_acc_audio += dt
	var phase := _tick + _stagger
	if water_depth > 0.0 or phase % 6 == 0:
		_tick_water(dt)
	if phase % 4 == 0:
		_tick_flip(dt * 4.0)
	if on_fire:
		_tick_fire(dt)
	if phase % 30 == 0:
		_tick_auto_lights()
	# components (lights 20 Hz, damage fx 30 Hz, audio 20 Hz)
	if lights != null and phase % 3 == 0:
		lights.update(_acc_light)
		_acc_light = 0.0
	if dmg != null and (phase & 1) == 0:
		dmg.tick(_acc_dmg)
		_acc_dmg = 0.0
	if audio != null and visual_lod == 0 and phase % 3 == 1:
		audio.update(_acc_audio)
		_acc_audio = 0.0
	# keep seated characters glued (their own scripts may have moved them this tick)
	if driver != null or (phase & 1) == 0:
		for i in seats.size():
			var c = seats[i]["character"]
			if c != null and is_instance_valid(c) and not _enter_blend.has(c):
				(c as Node3D).transform = Transform3D.IDENTITY
				if c.get("velocity") != null:
					c.velocity = Vector3.ZERO
	# auto-sleep of settled, unoccupied vehicles
	if driver == null and not is_ai_controlled and not on_fire:
		if linear_velocity.length_squared() < 0.012 and angular_velocity.length_squared() < 0.02 and _is_settled():
			_idle_time += dt
			if _idle_time > 0.9 or _pending_sleep:
				sleeping = true
				_pending_sleep = false
		else:
			_idle_time = 0.0
	else:
		_idle_time = 0.0
	_prev_vel = linear_velocity


func _is_settled() -> bool:
	return true


func _update_enter_blend(dt: float) -> void:
	var done: Array = []
	for c in _enter_blend:
		if not is_instance_valid(c):
			done.append(c)
			continue
		var e: Dictionary = _enter_blend[c]
		e["t"] = float(e["t"]) + dt / float(e["dur"])
		var t := clampf(float(e["t"]), 0.0, 1.0)
		var k := t * t * (3.0 - 2.0 * t)
		var from: Transform3D = e["from"]
		var tr := Transform3D(from.basis.slerp(Basis.IDENTITY, k), from.origin.lerp(Vector3.ZERO, k) + Vector3(0, sin(t * PI) * 0.12, 0))
		(c as Node3D).transform = tr
		if t >= 1.0:
			done.append(c)
			var s := get_seat_of(c)
			if s >= 0:
				_close_door_later(s, 0.25)
	for c in done:
		_enter_blend.erase(c)


# ---- doors -----------------------------------------------------------------------------------------------------------
func _door_index(seat: int) -> int:
	if seat < 0 or seat >= seats.size():
		return 0
	var side_i := 0 if float(seats[seat].get("side", -1.0)) < 0.0 else 1
	var rear: bool = seats[seat]["name"] == &"rear_l" or seats[seat]["name"] == &"rear_r"
	var i := side_i + (2 if rear else 0)
	if _door_nodes[i] == null:
		i = side_i
	return i


func _set_door_seat(seat: int, open: float) -> void:
	var i := _door_index(seat)
	if _door_nodes[i] == null:
		return
	_door_target[i] = open
	_door_close_timer[i] = 1.6 if open > 0.5 else 0.0


func _close_door_later(seat: int, delay: float) -> void:
	var i := _door_index(seat)
	if _door_nodes[i] != null:
		_door_close_timer[i] = delay


# ---- impacts -------------------------------------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	_last_contact = body
	_last_contact_t = _scene_time


func _detect_impacts(dt: float) -> void:
	if _skip_dv > 0:
		_skip_dv -= 1
		_impact_acc = 0.0
		return
	var dv := linear_velocity - _prev_vel
	var horiz := Vector2(dv.x, dv.z).length()
	var vert := (maxf(dv.y - 12.0, 0.0) + maxf(-dv.y - 16.0, 0.0)) * 0.5
	var impact := horiz + vert
	_impact_timer -= dt
	if impact > IMPACT_MIN:
		_impact_acc = maxf(_impact_acc, impact)
		if _impact_timer <= 0.0:
			_impact_timer = 0.2
			_on_impact(_impact_acc)
			_impact_acc = 0.0


func _on_impact(impact: float) -> void:
	var other: Node = _last_contact if (_scene_time - _last_contact_t) < 0.3 and is_instance_valid(_last_contact) else null
	last_collision_time = _scene_time
	if is_destroyed:
		return
	var excess := impact - IMPACT_MIN
	var amount := excess * 21.0 * float(def.get("collision_mult", 1.0)) * damage_taken_mult
	# heavier opponent = bigger dv for us already; light props barely scratch
	if other is RigidBody3D and not (other is VehicleBase) and (other as RigidBody3D).mass < 80.0:
		amount *= 0.25
	if amount > 0.5:
		_apply_health_loss(amount, other if other is VehicleBase and (other as VehicleBase).driver != null else null, {"type": GC.DMG_COLLISION, "position": global_position, "impulse": impact * mass})
	if audio != null:
		audio.play_impact(impact)
	if dmg != null:
		dmg.impact_fx(impact, other)
	if impact > 9.0:
		for c in get_occupants():
			if c.has_method("apply_damage"):
				c.apply_damage((impact - 9.0) * 2.4 * damage_taken_mult, {"source": other if other != null else self, "type": GC.DMG_COLLISION, "zone": GC.ZONE_TORSO, "position": global_position, "impulse": impact})
	collided.emit(other, impact)
	Events.vehicle_collision.emit(self, other if other != null else self, impact * mass)
	_on_crash(impact)


func _on_crash(_impact: float) -> void:
	pass


# ---- run over pedestrians ------------------------------------------------------------------------------------------
func _run_over_check(dt: float) -> void:
	var fwd := get_forward_speed()
	var spd := absf(fwd)
	if spd < 3.2 or is_destroyed:
		return
	var space := get_world_3d().direct_space_state
	if _run_box == null:
		_run_box = BoxShape3D.new()
	var len_ := float(def.get("length", 4.5))
	var wid := float(def.get("width", 1.8))
	var look := maxf(0.7, spd * dt * 2.5 + 0.4)
	_run_box.size = Vector3(wid * 0.96, 1.5, look)
	var dir := -1.0 if fwd >= 0.0 else 1.0
	if _run_query == null:
		_run_query = PhysicsShapeQueryParameters3D.new()
		_run_query.collision_mask = GC.L_NPC | GC.L_PLAYER | GC.L_ANIMAL
	var q := _run_query
	q.shape = _run_box
	q.transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.95, dir * (len_ * 0.5 + look * 0.5 - 0.35)))
	var res := space.intersect_shape(q, 4)
	for r in res:
		var col = r.get("collider", null)
		if col == null or not (col is Node3D) or not col.has_method("apply_damage"):
			continue
		var cid: int = col.get_instance_id()
		if _runover_cd.has(cid) and _scene_time - float(_runover_cd[cid]) < 0.6:
			continue
		if col is CharacterBase and (col.is_dead or col.current_vehicle != null):
			continue
		var rel: Vector3 = linear_velocity - (col.velocity if col.get("velocity") != null else Vector3.ZERO)
		var rs := rel.length()
		if rs < 3.0:
			continue
		_runover_cd[cid] = _scene_time
		if _runover_cd.size() > 24:
			_runover_cd.clear()
		var amount := clampf((rs - 2.0) * 11.0, 8.0, 260.0) * float(def.get("runover_mult", 1.0))
		var dirv := rel.normalized()
		col.apply_damage(amount, {"source": driver if driver != null else self, "type": GC.DMG_RUNOVER, "zone": GC.ZONE_TORSO,
			"position": (col as Node3D).global_position + Vector3.UP, "direction": dirv, "impulse": rs * mass * 0.1, "vehicle": self})
		if col.has_method("knockback"):
			col.knockback(dirv * minf(rs * 0.8, 18.0) + Vector3.UP * minf(rs * 0.18, 5.0) + global_transform.basis.x * randf_range(-1.5, 1.5))
		apply_central_impulse(-linear_velocity * mass * 0.035)
		Events.vehicle_collision.emit(self, col, rs * mass * 0.1)
		if audio != null:
			audio.play_thud()


# ---- water -------------------------------------------------------------------------------------------------------------
func _tick_water(dt: float) -> void:
	var p := global_position
	var wet := p.y < GC.WATER_LEVEL + 1.0 and WorldLayout.is_water(p.x, p.z)
	if not wet:
		if water_depth != 0.0:
			water_depth = 0.0
			_submerged_time = 0.0
		return
	var depth := GC.WATER_LEVEL - (p.y - 0.15)
	water_depth = maxf(depth, 0.0)
	if water_depth <= 0.0:
		return
	var sub := clampf(water_depth / 1.3, 0.0, 1.0)
	# buoyancy slightly below weight so the car drifts / sinks slowly, strong drag
	apply_central_force(Vector3.UP * mass * G * gravity_scale * (0.55 + 0.4 * sub) * sub)
	apply_central_force(-linear_velocity * mass * (1.4 + 2.2 * sub) * sub)
	apply_torque(-angular_velocity * mass * 2.0 * sub)
	if water_depth > 0.55 and engine_on:
		set_engine(false)
		if audio != null:
			audio.play_splash(true)
	if water_depth > 0.6:
		_submerged_time += dt
		if _submerged_time > 1.2 and driver != null:
			for c in get_occupants():
				exit(c, true)


func _tick_flip(dt: float) -> void:
	if global_transform.basis.y.y < 0.3 and linear_velocity.length_squared() < 9.0 and not is_destroyed:
		_flip_time += dt
		if _flip_time > 4.5 and (driver != null or is_ai_controlled):
			unflip()
	else:
		_flip_time = 0.0


func _tick_fire(dt: float) -> void:
	if not on_fire or is_destroyed:
		return
	# burning: health drains until the tank blows
	var drain := max_health * 0.045 * dt
	health = maxf(health - drain, 0.0)
	health_changed.emit(health, max_health)
	_fire_dot_t -= dt
	if _fire_dot_t <= 0.0:
		_fire_dot_t = 0.5
		for c in get_occupants():
			if c.has_method("apply_damage"):
				c.apply_damage(4.0, {"source": self, "type": GC.DMG_FIRE, "zone": GC.ZONE_TORSO, "position": global_position})
	if health <= 0.0:
		explode(_killer)


func _tick_auto_lights() -> void:
	# AI vehicles switch their headlights on at night, off in daylight (staggered)
	if is_ai_controlled and auto_headlights:
		var night := Game.is_night() or Game.weather == GC.W_RAIN or Game.weather == GC.W_STORM or Game.weather == GC.W_FOG
		if night and not headlights_on:
			headlights_on = true
			_auto_lights_on = true
		elif not night and _auto_lights_on:
			headlights_on = false
			_auto_lights_on = false


func take_for_player(garage_owned := false) -> void:
	is_player_owned = garage_owned
	abandoned = true


# =====================================================================================================
# Binding the visual model (called by VehicleFactory)
# =====================================================================================================
func _bind_model(m: Node3D, info: Dictionary) -> void:
	model = m
	minfo = info
	m.name = "Model"
	add_child(m)
	# seats
	var half_w: float = float(def.get("width", 1.8)) * 0.5
	var exit_l: Node3D = m.find_child("ExitL", true, false) as Node3D
	var exit_r: Node3D = m.find_child("ExitR", true, false) as Node3D
	for spec in SEAT_SPECS:
		var sn: Node3D = m.find_child(String(spec[0]), true, false) as Node3D
		if sn == null:
			continue
		var p := _rel_pos(m, sn)
		if _seat_name_used(spec[1]):
			continue
		_add_seat(spec[1], p, exit_l, exit_r, half_w)
	if seats.is_empty():
		push_warning("VehicleBase[%s]: model has no Seat* empties - synthesising seats from the def" % def_id)
		var n := int(def.get("seats", 2))
		var wb := float(def.get("wheelbase", 2.7))
		var layout := [[-0.4, 0.56, wb * 0.05], [0.4, 0.56, wb * 0.05], [-0.4, 0.56, wb * 0.45], [0.4, 0.56, wb * 0.45]]
		if vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE:
			layout = [[0.0, 0.8, wb * 0.1], [0.0, 0.8, wb * 0.45]]
		var names := [&"driver", &"passenger", &"rear_l", &"rear_r"]
		for i in mini(n, layout.size()):
			_add_seat(names[i], Vector3(layout[i][0], layout[i][1], layout[i][2]), exit_l, exit_r, half_w)
	# seat anchors
	for i in seats.size():
		var anchor := Node3D.new()
		anchor.name = "SeatAnchor%d" % i
		anchor.position = seats[i]["pos"]
		add_child(anchor)
		_seat_nodes.append(anchor)
	# doors
	var door_names := ["DoorL", "DoorR", "DoorRearL", "DoorRearR"]
	for i in 4:
		var dn := m.find_child(door_names[i], true, false) as Node3D
		_door_nodes[i] = dn
		_door_rest[i] = dn.transform.basis if dn != null else Basis.IDENTITY


func _seat_name_used(n: StringName) -> bool:
	for s in seats:
		if s["name"] == n:
			return true
	return false


func _add_seat(sname: StringName, p: Vector3, exit_l: Node3D, exit_r: Node3D, half_w: float) -> void:
	var side: float = -1.0 if p.x < -0.05 else (1.0 if p.x > 0.05 else -1.0)
	var origin := p - Vector3(0.0, SIT_HIP_DROP, 0.0)
	var ex: Vector3
	var en: Vector3
	var ex_node: Node3D = exit_l if side < 0.0 else exit_r
	if ex_node != null:
		var ep := _rel_pos(model, ex_node)
		ex = Vector3(ep.x, 0.0, ep.z)
		en = Vector3(ep.x, 0.0, ep.z)
		# rear seats use the same door side but their own longitudinal position
		if sname == &"rear_l" or sname == &"rear_r":
			ex.z = p.z
			en.z = p.z
	else:
		ex = Vector3(side * (half_w + 0.75), 0.0, p.z)
		en = Vector3(side * (half_w + 0.45), 0.0, p.z)
	var can_shoot := true
	if vclass == GC.VC_CAR and sname == &"driver":
		can_shoot = true
	seats.append({"name": sname, "character": null, "entry": en, "exit": ex, "can_shoot": can_shoot, "pos": origin, "side": side})


static func _rel_pos(root: Node3D, node: Node3D) -> Vector3:
	return Util._rel_transform(root, node).origin
