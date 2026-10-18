class_name Animal
extends CharacterBody3D
## One wildlife individual (land animal, bird, shark, dolphin, turtle). A kinematic hit body on GC.L_ANIMAL (bullets, melee, explosions and
## run-over checks find it), group "animal" + "damageable", implements the damage contract. It has NO per-node process: WildlifeSystem ticks
## every animal from one loop (movement every physics tick, decisions staggered by tier) and AnimalAnim poses the limbs.
## Death is "ragdoll-lite": land animals topple onto their side (stiff legs), birds drop, swimmers roll belly-up and float; corpses sink after a while.

signal died(animal: Animal, killer: Node)
signal damaged(animal: Animal, amount: float, info: Dictionary)

# ---- identity -----------------------------------------------------------------------------------------------------------
var sp: StringName = &""
var def: Dictionary = {}
var kind: StringName = &"land"
var display_name := "Animal"
var faction: StringName = GC.F_ANIMAL
var uid := 0
var sys: Node = null                  # owning WildlifeSystem

# ---- health / damage ------------------------------------------------------------------------------------------------------
var health := 50.0
var max_health := 50.0
var is_dead := false
var invulnerable := false
var body_height := 1.0
var last_attacker: Node = null
var death_time := 0.0
var killed_by_player := false

# ---- visuals --------------------------------------------------------------------------------------------------------------
var vroot: Node3D = null              # pitch / roll / bob container (child of the body)
var model: Node3D = null              # the active GLB instance
var parts: Dictionary = {}            # active model: part name -> Node3D
var rest_pos: Dictionary = {}         # part name -> rest position (model space / parent space)
var models: Array = []                # birds keep [flying model, perched model] and toggle visibility
var parts_all: Array = []             # per-model part dictionaries (same indices as `models`)
var rest_all: Array = []
var mesh_list: Array = []             # every MeshInstance3D of every model (shadow toggling)
var model_scale := 1.0
var coat := 0
var shadows_on := true
var shape_node: CollisionShape3D = null

# ---- simulation state (driven by WildlifeBrain / MarineBrain) ----------------------------------------------------------------
var region: StringName = &""
var state := 0
var prev_state := 0
var state_t := 0.0
var think_t := 0.0
var think_every := 0.12
var tier := 0                         # 0 near, 1 mid
var pos := Vector3.ZERO               # authoritative world position (the body transform is written from it)
var ground_off := 0.0                 # extra height above the terrain height (roads, pier decks, curbs) from the last ground ray
var xf_dirty := true
var yaw := 0.0                        # body heading (Util.yaw convention: 0 faces -Z)
var heading := 0.0                    # desired heading
var speed := 0.0
var want_speed := 0.0
var goal := Vector3.INF
var home := Vector3.ZERO
var vy := 0.0                         # vertical velocity (flight, fling, dives)
var airborne := false
var ground_y := 0.0
var gy_t := 0.0                       # time until the next ground ray
var gy_hit := NAN
var slope_pitch := 0.0
var slope_roll := 0.0
var roll_visual := 0.0                # banking / death roll
var pitch_visual := 0.0
var turn_rate := 5.0

var group_id := -1
var leader: Animal = null
var follow_off := Vector2.ZERO
var herd: Array = []                  # members (shared array) when part of a herd

var threat_pos := Vector3.INF
var threat_t := 0.0                   # time since the last threat
var alert_t := 0.0
var flee_t := 0.0
var react_delay := 0.0
var target: Node = null               # prey / attack target
var fight_until := 0.0
var bite_cd := 0.0
var bites_left := 0
var next_voice := 0.0
var eat_t := 0.0
var perch_pos := Vector3.INF
var fly_alt := 0.0
var flap_phase := 0.0
var flap_amp := 0.0
var circle_dir := 1.0
var circle_r := 10.0
var dur := 0.0                        # planned duration of the current state
var last_scare := 0                   # id of the last gunshot / explosion this animal reacted to
var move_acc := 0.0                   # time accumulated since the last movement step (mid tier moves at a lower rate)
var depth_goal := 0.0                 # swimmers: wanted world y
var aux := 0.0                        # species specific scratch values
var aux2 := 0.0
var wander_cd := 0.0
var think_acc := 0.0                  # time since the last think()
var anim_n := 0
var anim_acc := 0.0

# ---- animation ----------------------------------------------------------------------------------------------------------------
var gait_phase := 0.0
var gait_amp := 0.0
var head_pitch := 0.0
var head_yaw := 0.0
var neck_pitch := 0.0
var tail_wag := 0.0
var ear_flick := 0.0
var jaw_open := 0.0
var anim_skip := 0
var anim_t := 0.0
var bob := 0.0
var swim_phase := 0.0
var dead_pose_done := false
var rng_seed := 0.0

var _fling := Vector3.ZERO


func setup_species(species: StringName, d: Dictionary) -> void:
	sp = species
	def = d
	kind = d.get("kind", &"land")
	display_name = String(d.get("name", String(species).capitalize()))
	max_health = float(d.get("health", 50.0))
	health = max_health
	add_to_group(GC.G_ANIMAL)
	add_to_group(GC.G_DAMAGEABLE)
	collision_layer = GC.L_ANIMAL
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	rng_seed = randf() * 100.0


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, body_height * 0.9, 0.0)


func get_chest_position() -> Vector3:
	return global_position + Vector3(0.0, body_height * 0.55, 0.0)


func get_speed_xz() -> float:
	return speed


func is_prey() -> bool:
	return sp == &"rabbit" or sp == &"crow"


# ---- damage contract ------------------------------------------------------------------------------------------------------------
func apply_damage(amount: float, info: Dictionary = {}) -> void:
	if is_dead or invulnerable or amount <= 0.0:
		return
	var m := 1.0
	var zone: StringName = info.get("zone", GC.ZONE_TORSO)
	if zone == GC.ZONE_HEAD:
		m = 2.2
	elif zone == GC.ZONE_LIMB:
		m = 0.7
	health -= amount * m
	var src: Variant = info.get("source", null)
	if src is Node and is_instance_valid(src):
		last_attacker = src
	damaged.emit(self, amount * m, info)
	if sys != null and is_instance_valid(sys) and sys.has_method("_on_animal_damaged"):
		sys._on_animal_damaged(self, amount * m, info)
	if health <= 0.0:
		die(info)
	else:
		_hurt_react(info)


func die(info: Dictionary = {}) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	var killer: Node = null
	var src: Variant = info.get("source", null)
	if src is Node and is_instance_valid(src):
		killer = src
	last_attacker = killer
	killed_by_player = killer != null and killer.is_in_group(GC.G_PLAYER)
	state_t = 0.0
	death_time = 0.0
	want_speed = 0.0
	collision_layer = GC.L_ANIMAL      # corpses stay hittable (bullets, run-over) but are no longer reacted to
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var imp := float(info.get("impulse", 0.0))
	if dir.length() > 0.01 and imp > 0.0:
		_fling = Vector3(dir.x, 0.0, dir.z).normalized() * clampf(imp * 0.5, 0.0, 9.0)
		if kind != &"swim":
			vy = clampf(imp * 0.18, 1.5, 6.0)
			airborne = true
	elif info.get("type", &"") == GC.DMG_RUNOVER:
		_fling = Vector3(dir.x, 0.0, dir.z).normalized() * 3.0
		vy = 3.0
		airborne = true
	died.emit(self, killer)
	if sys != null and is_instance_valid(sys) and sys.has_method("_on_animal_died"):
		sys._on_animal_died(self, killer, info)


func knockback(impulse: Vector3) -> void:
	if kind == &"swim":
		return
	if is_dead:
		_fling += Vector3(impulse.x, 0.0, impulse.z) * 0.5
		vy = maxf(vy, impulse.y * 0.5)
		airborne = true
		return
	# a live animal gets shoved and bolts
	speed = clampf(speed + Vector2(impulse.x, impulse.z).length() * 0.3, 0.0, 9.0)


func take_fling() -> Vector3:
	var f := _fling
	_fling = Vector3.ZERO
	return f


func peek_fling() -> Vector3:
	return _fling


func set_fling(v: Vector3) -> void:
	_fling = v


func _hurt_react(info: Dictionary) -> void:
	if sys != null and is_instance_valid(sys) and sys.has_method("_react_hurt"):
		sys._react_hurt(self, info)


# ---- visuals helpers ---------------------------------------------------------------------------------------------------------------
func set_shadows(on: bool) -> void:
	if shadows_on == on:
		return
	shadows_on = on
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in mesh_list:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).cast_shadow = mode


func set_model_variant(index: int) -> void:
	## birds: 0 = wings spread (flying), 1 = folded (standing); other animals only have index 0
	if models.is_empty():
		return
	index = clampi(index, 0, models.size() - 1)
	for i in models.size():
		(models[i] as Node3D).visible = (i == index)
	model = models[index]
	parts = parts_all[index]
	rest_pos = rest_all[index]


func current_variant() -> int:
	return models.find(model) if models.size() > 1 else 0


func set_active(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if shape_node != null:
		shape_node.disabled = not on


func place(p: Vector3, y_rot: float) -> void:
	yaw = y_rot
	heading = y_rot
	pos = p
	global_transform = Transform3D(Basis(Vector3.UP, y_rot), p)
	ground_y = p.y
	velocity = Vector3.ZERO
	speed = 0.0
	want_speed = 0.0
	xf_dirty = false


func write_transform() -> void:
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	xf_dirty = false


## Brings a pooled animal back to a clean spawn state (called by the system before re-use).
func reset_state() -> void:
	is_dead = false
	health = max_health
	invulnerable = false
	last_attacker = null
	killed_by_player = false
	death_time = 0.0
	state = 0
	prev_state = 0
	state_t = 0.0
	dur = 0.0
	think_t = randf() * 0.2
	think_acc = 0.0
	tier = 0
	speed = 0.0
	want_speed = 0.0
	goal = Vector3.INF
	vy = 0.0
	airborne = false
	ground_off = 0.0
	gy_t = 0.0
	slope_pitch = 0.0
	slope_roll = 0.0
	roll_visual = 0.0
	pitch_visual = 0.0
	turn_rate = 3.2
	group_id = -1
	leader = null
	follow_off = Vector2.ZERO
	herd = []
	threat_pos = Vector3.INF
	threat_t = 0.0
	alert_t = 0.0
	flee_t = 0.0
	react_delay = 0.0
	target = null
	fight_until = 0.0
	bite_cd = 0.0
	bites_left = 0
	next_voice = 0.0
	eat_t = 0.0
	perch_pos = Vector3.INF
	fly_alt = 0.0
	flap_phase = randf() * TAU
	flap_amp = 0.0
	depth_goal = 0.0
	aux = 0.0
	aux2 = 0.0
	wander_cd = 0.0
	gait_phase = randf() * TAU
	gait_amp = 0.0
	head_pitch = 0.0
	head_yaw = 0.0
	neck_pitch = 0.0
	tail_wag = 0.0
	ear_flick = 0.0
	jaw_open = 0.0
	anim_skip = 0
	anim_n = 0
	anim_acc = 0.0
	anim_t = randf() * 10.0
	bob = 0.0
	swim_phase = randf() * TAU
	dead_pose_done = false
	rng_seed = randf() * 100.0
	_fling = Vector3.ZERO
	velocity = Vector3.ZERO
	xf_dirty = true
	collision_layer = GC.L_ANIMAL
	if vroot != null:
		vroot.position = Vector3.ZERO
		vroot.rotation = Vector3.ZERO
	for pd in parts_all:
		for n in (pd as Dictionary).values():
			(n as Node3D).rotation = Vector3.ZERO
