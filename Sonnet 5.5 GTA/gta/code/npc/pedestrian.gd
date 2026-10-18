class_name Pedestrian
extends CharacterBase
## A civilian on foot (also: taxi / traffic drivers, shop staff and test dummies). Body = CharacterBody3D that is moved kinematically
## by PedManager's central scheduler (no per-ped _process / move_and_slide); visuals = CharacterRig; behaviour = PedBrain.
## Layer GC.L_NPC, groups npc + pedestrian + damageable, faction civilian. Multi-shape hitbox (Head/Torso/Legs) so headshots work.
## Nodes are pooled by PedManager (activate / deactivate); never instantiate them directly - use PedManager.spawn_pedestrian().
## Public API in docs/api/pedestrians.md.

signal phone_call_started
signal phone_call_ended(reported: bool)
signal panicked(threat_pos: Vector3)
signal knocked_down
signal got_up

const PHONE_MAT_COLOR := Color(0.06, 0.07, 0.09)

static var _phone_mesh: BoxMesh = null
static var _phone_mat: StandardMaterial3D = null
static var _screen_mat: StandardMaterial3D = null
static var _towel_mesh: PlaneMesh = null
static var _towel_mats: Dictionary = {}

var manager: PedManager = null
var brain: PedBrain = null
var personality: StringName = &"normal"
var pers: Dictionary = {}
var role: StringName = &"walker"
var look: StringName = &"casual"
var variant: Dictionary = {}
var tier := 0                         # 0 near, 1 mid, 2 far (set by the manager)
var body_height := 1.8                # read by Ballistics.character_zone
var is_crouching := false
var ai_accuracy := 0.3
var is_driver := false
var persistent := false               # exempt from distance despawn
var panic := 0.0                      # 0..1, decays over the personality's calm time
var walk_speed := 1.5
var run_speed := 6.0
var jog_speed := 3.0
var is_female := false
var group_id := -1
var partner: Pedestrian = null
var bench_claim := -1
var spawn_time := 0.0
var death_time := 0.0
var think_at := 0.0
var last_think := 0.0
var hpos := Vector3.ZERO              # position snapshot used by the spatial hash
var voice_pitch := 1.0
var scene_tag: StringName = &""       # what the ped was spawned to do (informational / tests)
var last_threat_kind: StringName = &""
var phone_visible := false

var _active := false
var _call: Dictionary = {}
var _phone_prop: MeshInstance3D = null
var _towel: MeshInstance3D = null
var _fade_alpha := 0.0
var _shadow_on := true
var _driver_vehicle: Node = null
var _driver_exit_at := -1.0
var _sig_vehicle_changed := false


func _init() -> void:
	display_name = "Citizen"
	faction = GC.F_CIVILIAN
	max_health = 80.0
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	safe_margin = 0.01
	_build_collider()
	var r := CharacterRig.new()
	r.name = "Rig"
	add_child(r)
	rig = r
	brain = PedBrain.new(self)


func _build_collider() -> void:
	var legs := CollisionShape3D.new()
	legs.name = "LegsHitbox"
	var cl := CapsuleShape3D.new()
	cl.radius = 0.2
	cl.height = 0.95
	legs.shape = cl
	legs.position = Vector3(0, 0.475, 0)
	legs.set_meta(&"zone", GC.ZONE_LIMB)
	add_child(legs)
	var torso := CollisionShape3D.new()
	torso.name = "TorsoHitbox"
	var ct := CapsuleShape3D.new()
	ct.radius = 0.27
	ct.height = 0.78
	torso.shape = ct
	torso.position = Vector3(0, 1.14, 0)
	torso.set_meta(&"zone", GC.ZONE_TORSO)
	add_child(torso)
	var head := CollisionShape3D.new()
	head.name = "HeadHitbox"
	var ch := SphereShape3D.new()
	ch.radius = 0.15
	head.shape = ch
	head.position = Vector3(0, 1.64, 0)
	head.set_meta(&"zone", GC.ZONE_HEAD)
	add_child(head)


# =====================================================================================================================
# Pool lifecycle (PedManager)
# =====================================================================================================================
## Re-dresses the rig and resets every piece of state. Called by the manager before the node enters the tree.
func dress(v: Dictionary, pers_id: StringName, new_role: StringName, rng: RandomNumberGenerator) -> void:
	variant = v
	personality = pers_id
	pers = PedDefs.PERSONALITIES.get(pers_id, PedDefs.PERSONALITIES[&"normal"])
	role = new_role
	var r = rig
	r.position = Vector3.ZERO
	r.auto_lod = true
	r.lod = 0
	r.setup(v)
	r.set_stance(&"stand")
	r.play_action(&"hands_down")
	r.play_action(&"stop")
	r.set_idle_style(&"relaxed")
	r.set_locomotion(0.0, Vector3(0, 0, -1), false)
	r.set_weapon_pose(&"none")
	r.clear_look()
	r.set_steering(0.0)
	_setup_render_range()
	is_female = String(v.get("body", &"A")) == "B"
	var hp: Array = pers.get("hp", [65.0, 100.0])
	max_health = rng.randf_range(float(hp[0]), float(hp[1]))
	if String(v.get("body", &"A")) == "C":
		max_health *= 1.1
	var w: Array = pers.get("walk", [1.3, 1.7])
	var rn: Array = pers.get("run", [5.8, 6.8])
	walk_speed = rng.randf_range(float(w[0]), float(w[1]))
	run_speed = rng.randf_range(float(rn[0]), float(rn[1]))
	jog_speed = rng.randf_range(2.7, 3.5)
	voice_pitch = rng.randf_range(0.88, 1.14) * (1.12 if is_female else 1.0)
	body_height = 1.8 * float(v.get("scale", 1.0))
	is_crouching = false
	ai_accuracy = rng.randf_range(0.15, 0.5)
	panic = 0.0
	health = max_health
	armor = 0.0
	is_dead = false
	invulnerable = false
	last_attacker = null
	last_damage_info = {}
	velocity = Vector3.ZERO
	partner = null
	group_id = -1
	bench_claim = -1
	scene_tag = &""
	_call = {}
	phone_visible = false
	_fade_alpha = 0.0
	_set_fade(0.0)
	_show_phone(false)
	_show_towel(false)
	brain.reset()


## Joins the physics world (layer NPC) and the gameplay groups. The node must already be in the tree.
func activate() -> void:
	_active = true
	collision_layer = GC.L_NPC
	collision_mask = 0
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	add_to_group(GC.G_NPC)
	add_to_group(GC.G_DAMAGEABLE)
	if is_driver:
		add_to_group(&"driver")
		remove_from_group(GC.G_PED)
	else:
		add_to_group(GC.G_PED)
		remove_from_group(&"driver")
	if not vehicle_changed.is_connected(_on_vehicle_changed):
		vehicle_changed.connect(_on_vehicle_changed)


func deactivate() -> void:
	_active = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group(GC.G_NPC)
	remove_from_group(GC.G_PED)
	remove_from_group(&"driver")
	remove_from_group(GC.G_DAMAGEABLE)
	_abort_call(false)
	_show_phone(false)
	_show_towel(false)
	_driver_vehicle = null
	_driver_exit_at = -1.0
	partner = null
	if brain != null:
		brain.release_claims()
	visible = false


func is_active() -> bool:
	return _active


func _ready() -> void:
	super._ready()
	remove_from_group(GC.G_DAMAGEABLE)       # added again by activate()


# =====================================================================================================================
# Damage contract
# =====================================================================================================================
func apply_damage(amount: float, info: Dictionary = {}) -> void:
	if not _active or is_dead:
		return
	super.apply_damage(amount, info)


func _on_damaged(amount: float, info: Dictionary) -> void:
	if health <= 0.0:
		return
	_abort_call(false)
	brain.on_damaged(amount, info)


func _on_death(info: Dictionary) -> void:
	death_time = manager.now if manager != null else 0.0
	_abort_call(false)
	_show_phone(false)
	_show_towel(false)
	is_crouching = false
	brain.on_death()
	collision_layer = 0
	if current_vehicle == null:
		var kick := _death_kick(info)
		var at: Vector3 = info.get("position", global_position + Vector3(0, 1.0, 0))
		if rig != null:
			rig.set_locomotion(0.0, Vector3(0, 0, -1), false)
			rig.start_ragdoll(kick, at)
	if manager != null:
		manager.on_ped_died(self, info)


## Velocity change (m/s) the body gets when it dies, by damage type.
func _death_kick(info: Dictionary) -> Vector3:
	var t: StringName = info.get("type", GC.DMG_BULLET)
	var d: Vector3 = info.get("direction", Vector3.ZERO)
	d.y = 0.0
	if d.length() < 0.01:
		d = -global_transform.basis.z
	d = d.normalized()
	var imp := float(info.get("impulse", 3.0))
	match t:
		GC.DMG_RUNOVER:
			var veh = info.get("vehicle", null)
			var v := Vector3.ZERO
			if veh != null and is_instance_valid(veh) and veh.get("linear_velocity") != null:
				v = veh.linear_velocity
			v.y = 0.0
			return v * 0.28 + Vector3.UP * 1.2          # VehicleBase.knockback() adds the rest right after
		GC.DMG_EXPLOSION:
			var bc: Vector3 = info.get("blast_center", global_position)
			var away := (global_position + Vector3(0, 0.9, 0)) - bc
			away = away.normalized() if away.length() > 0.05 else Vector3.UP
			return away * clampf(imp * 0.8, 4.0, 14.0) + Vector3.UP * 3.0
		GC.DMG_BULLET:
			return d * clampf(imp, 1.0, 9.0) * 0.9 + Vector3.UP * 0.6
		GC.DMG_MELEE:
			return d * clampf(imp, 2.0, 8.0) + Vector3.UP * 0.8
		GC.DMG_COLLISION:
			return d * 2.0 + Vector3.UP * 1.0
	return d * 1.0


## Vehicle run-over, melee and bullets call this after apply_damage.
func knockback(impulse: Vector3) -> void:
	if not _active:
		return
	if is_dead:
		if rig != null and rig.is_ragdoll():
			rig.start_ragdoll(impulse * 0.9, Vector3.ZERO)
		return
	if current_vehicle != null:
		return
	var flat := Vector2(impulse.x, impulse.z).length()
	if flat > 4.6 or impulse.y > 3.2:
		brain.knock_down(impulse, clampf(1.8 + flat * 0.14, 1.8, 4.2))
	else:
		brain.shove(impulse)


## Knocks the ped to the ground for `duration` seconds (rig ragdoll), then it gets up. Used by weapons (melee / explosions).
func knock_down(impulse: Vector3, duration: float = 2.2) -> void:
	if not _active or is_dead or current_vehicle != null:
		return
	brain.knock_down(impulse, duration)


func teleport_to(pos: Vector3, yaw: float = NAN) -> void:
	super.teleport_to(pos, yaw)
	if not is_nan(yaw):
		brain.heading = yaw
	reset_physics_interpolation()


# =====================================================================================================================
# Events from the world
# =====================================================================================================================
## Something frightening happened: kind = gunshot explosion death violence crash vehicle aimed hit contagion crime bump.
## severity 0..1, `direct` = aimed at / attacked. The personality decides the reaction.
func notify_threat(kind: StringName, pos: Vector3, severity: float, source: Node = null, direct: bool = false) -> void:
	if not _active or is_dead:
		return
	last_threat_kind = kind
	brain.react(kind, pos, severity, source, direct)


## Witness API (ARCHITECTURE 14.1): reacts to the crime and returns true when this ped is going to phone the police. The call lasts
## 4-7 s and then emits Events.crime_reported(crime, pos, perpetrator); it is aborted when the ped is hurt, knocked down or dies.
func witness(crime: StringName, pos: Vector3, perpetrator: Node, severity: float = 1.0) -> bool:
	if not _active or is_dead or current_vehicle != null and not is_driver:
		return false
	var sev := clampf(0.5 + severity * 0.35, 0.4, 1.0)
	brain.react(&"crime", pos, sev, perpetrator, false)
	if not _call.is_empty():
		return true
	var rng: RandomNumberGenerator = manager.rng if manager != null else Game.rng
	var chance := float(pers.get("call", 0.6)) * clampf(0.55 + severity * 0.45, 0.3, 1.0)
	if is_driver:
		chance *= 0.6
	if rng.randf() > chance:
		return false
	_call = {"crime": crime, "pos": pos, "perp": perpetrator, "t": 0.0, "dur": rng.randf_range(4.0, 7.0), "delay": rng.randf_range(0.5, 1.8), "started": false}
	return true


func is_calling() -> bool:
	return not _call.is_empty() and bool(_call.get("started", false))


func has_pending_call() -> bool:
	return not _call.is_empty()


func get_call() -> Dictionary:
	return _call


## Called by the brain every decision tick; returns true while the phone is being used.
func tick_call(dt: float) -> bool:
	if _call.is_empty():
		return false
	if is_dead:
		_abort_call(false)
		return false
	_call["t"] = float(_call["t"]) + dt
	if not bool(_call["started"]):
		if float(_call["t"]) >= float(_call["delay"]) and brain.can_phone():
			_call["started"] = true
			_call["t"] = 0.0
			_show_phone(true)
			rig.set_idle_style(&"phone")
			brain.begin_call()
			phone_call_started.emit()
		return false
	# far away from the scene and out of sight: the witness gives up (nobody to report to)
	if float(_call["t"]) >= float(_call["dur"]):
		_finish_call()
		return false
	return true


func _finish_call() -> void:
	var c := _call
	_call = {}
	_show_phone(false)
	if rig != null and not is_dead:
		rig.set_idle_style(&"relaxed")
	Events.crime_reported.emit(c["crime"], c["pos"], c["perp"])
	phone_call_ended.emit(true)
	brain.end_call()


func _abort_call(emit_end: bool = true) -> void:
	if _call.is_empty():
		return
	var was := bool(_call.get("started", false))
	_call = {}
	_show_phone(false)
	if rig != null and not is_dead and is_instance_valid(rig):
		rig.set_idle_style(&"relaxed")
	if was and emit_end:
		phone_call_ended.emit(false)
	elif was:
		phone_call_ended.emit(false)


# =====================================================================================================================
# Vehicles
# =====================================================================================================================
## Carjack reaction (VehicleBase._carjack calls it right after pulling the driver out): stumble, then flee / fight / surrender.
func on_carjacked(thief: Node) -> void:
	_driver_exit_at = -1.0
	is_driver = false
	_driver_vehicle = null
	add_to_group(GC.G_PED)
	remove_from_group(&"driver")
	if manager != null:
		manager.on_driver_ejected(self)
	brain.on_carjacked(thief)


func _on_vehicle_changed(v: Node) -> void:
	if v != null:
		_driver_vehicle = v
		_driver_exit_at = -1.0
		return
	# left the seat. Drivers that were not carjacked are recycled shortly (vehicle despawned) or become panicked walkers
	# (vehicle destroyed); on_carjacked() runs synchronously right after and cancels this.
	if is_driver and manager != null:
		_driver_exit_at = manager.now + 0.25


func driver_exit_due(now: float) -> bool:
	return is_driver and _driver_exit_at > 0.0 and now >= _driver_exit_at


func get_driver_vehicle() -> Node:
	return _driver_vehicle


# =====================================================================================================================
# Visual helpers
# =====================================================================================================================
func _show_phone(on: bool) -> void:
	phone_visible = on
	if on and _phone_prop == null:
		_phone_prop = _make_phone()
		var sock: Node3D = rig.get_hand_socket(true) if rig != null else null
		if sock != null and sock != rig:
			sock.add_child(_phone_prop)
		else:
			add_child(_phone_prop)
	if _phone_prop != null:
		_phone_prop.visible = on


func _make_phone() -> MeshInstance3D:
	if _phone_mesh == null:
		_phone_mesh = BoxMesh.new()
		_phone_mesh.size = Vector3(0.07, 0.15, 0.014)
		_phone_mat = StandardMaterial3D.new()
		_phone_mat.albedo_color = PHONE_MAT_COLOR
		_phone_mat.roughness = 0.35
		_phone_mat.metallic = 0.3
	var mi := MeshInstance3D.new()
	mi.name = "PhoneProp"
	mi.mesh = _phone_mesh
	mi.material_override = _phone_mat
	mi.position = Vector3(0.0, 0.02, 0.0)
	mi.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _show_towel(on: bool, col: Color = Color(1, 0.4, 0.6)) -> void:
	if on and _towel == null:
		if _towel_mesh == null:
			_towel_mesh = PlaneMesh.new()
			_towel_mesh.size = Vector2(0.95, 2.05)
		_towel = MeshInstance3D.new()
		_towel.name = "Towel"
		_towel.mesh = _towel_mesh
		_towel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_towel.position = Vector3(0, 0.025, -0.12)
		add_child(_towel)
	if _towel != null:
		_towel.visible = on
		if on:
			var key := col.to_rgba32()
			var m: StandardMaterial3D = _towel_mats.get(key, null)
			if m == null:
				m = StandardMaterial3D.new()
				m.albedo_color = col
				m.roughness = 0.95
				_towel_mats[key] = m
			_towel.material_override = m


func show_towel(on: bool, col: Color = Color(1, 0.4, 0.6)) -> void:
	_show_towel(on, col)


## Render budget: peds beyond PedDefs.SHADOW_RANGE do not cast shadows (each ped shadow costs ~3 draw calls per cascade) and nothing is drawn
## beyond PedDefs.VIS_END (dithered fade). Called by PedManager every 0.2 s with the distance to the camera; only touches meshes on change.
func set_shadows(on: bool) -> void:
	if on == _shadow_on or rig == null or rig.model == null:
		return
	_shadow_on = on
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in ModelLib.meshes(rig.model):
		mi.cast_shadow = mode


func _setup_render_range() -> void:
	_shadow_on = true
	if rig == null or rig.model == null:
		return
	for mi in ModelLib.meshes(rig.model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = PedDefs.VIS_END
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## 0 = opaque .. 1 = invisible, dithered per mesh instance (corpses fade out).
func _set_fade(a: float) -> void:
	_fade_alpha = a
	if rig == null or rig.model == null:
		return
	for mi in ModelLib.meshes(rig.model):
		mi.transparency = a


func set_fade(a: float) -> void:
	if absf(a - _fade_alpha) > 0.01 or a == 0.0:
		_set_fade(a)


# =====================================================================================================================
# Queries
# =====================================================================================================================
func get_eye_position() -> Vector3:
	if rig != null and rig.is_built():
		return rig.get_eye_position()
	return global_position + Vector3(0.0, 1.6, 0.0)


func get_state_name() -> String:
	return brain.state_name() if brain != null else ""


func is_fleeing() -> bool:
	return brain != null and brain.state == PedBrain.S.FLEE


func is_panicked() -> bool:
	return panic > 0.3


func is_knocked_down() -> bool:
	return brain != null and (brain.state == PedBrain.S.KNOCKED or brain.state == PedBrain.S.GETUP)


func get_threat_position() -> Vector3:
	return brain.threat_pos if brain != null else global_position


func get_aim_direction() -> Vector3:
	return Util.yaw_to_dir(brain.heading) if brain != null else super.get_aim_direction()


func _exit_tree() -> void:
	pass
