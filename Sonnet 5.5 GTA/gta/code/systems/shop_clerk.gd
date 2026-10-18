class_name ShopClerk
extends CharacterBase
## Shop staff NPC standing behind a counter inside an interior (built with CharacterRig directly - the pedestrian system
## lives in the street world and despawns far from the player). Static body, idle pose, watches the player, raises both hands
## when threatened (ShopSystem decides: player aiming a firearm at the clerk), can be hurt / killed (damage contract) and
## is rebuilt by ShopSystem when the player re-enters after a while.
##
## Public: raise_hands() / lower_hands() / hands_up / state (&"idle" &"hands_up" &"robbed" &"dead") / shop_id / respawn()

signal state_changed(new_state: StringName)

const RESPAWN_AFTER_S := 90.0

var shop_id: StringName = &""
var state: StringName = &"idle"
var hands_up := false
var variant: Dictionary = {}
var idle_style: StringName = &"hands_pockets"
var home_pos := Vector3.ZERO
var home_yaw := 0.0
var died_at_ms := 0

var _look_timer := 0.0
var _hands_until := 0.0
var _collider: CollisionShape3D = null


## Creates a clerk as a child of `parent` (an InteriorRoom) at a local position, facing `yaw` (Util convention: 0 faces -Z).
static func create(parent: Node3D, local_pos: Vector3, yaw: float, shop: StringName, p_variant: Dictionary, style: StringName = &"hands_pockets") -> ShopClerk:
	var c := ShopClerk.new()
	c.name = "Clerk_" + String(shop)
	c.shop_id = shop
	c.variant = p_variant
	c.idle_style = style
	c.position = local_pos
	c.rotation.y = yaw
	c.home_yaw = yaw
	parent.add_child(c)
	c.home_pos = c.position
	return c


func _ready() -> void:
	super._ready()
	display_name = "Clerk"
	faction = GC.F_CIVILIAN
	max_health = 60.0
	health = max_health
	collision_layer = GC.L_NPC
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	_collider = CollisionShape3D.new()
	_collider.name = "Collider"
	_collider.shape = cap
	_collider.position = Vector3(0, 0.875, 0)
	add_child(_collider)
	add_to_group(&"shop_clerk")
	var rig_script: Script = load("res://gta/code/player/character_rig.gd")
	if rig_script != null and rig_script.can_instantiate():
		rig = rig_script.new()
		rig.name = "Rig"
		add_child(rig)
		rig.setup(variant)
		if rig.has_method("set_idle_style"):
			rig.set_idle_style(idle_style)
	else:
		push_warning("ShopClerk: CharacterRig unavailable - clerk has no model")


func _process(dt: float) -> void:
	if is_dead or rig == null:
		return
	_look_timer -= dt
	if _look_timer > 0.0:
		if hands_up and Time.get_ticks_msec() * 0.001 > _hands_until and state == &"hands_up":
			pass
		return
	_look_timer = 0.12
	var p = Game.player
	if is_instance_valid(p):
		var to: Vector3 = p.global_position - global_position
		var dist := Vector2(to.x, to.z).length()
		if dist < 7.5:
			rig.look_at_point(p.global_position + Vector3(0, 1.55, 0))
			# turn the body towards the player within +-50 degrees of the home pose
			var want := Util.dir_to_yaw(Util.flat(to).normalized()) if dist > 0.3 else home_yaw
			var diff := clampf(Util.angle_diff(home_yaw, want), -0.87, 0.87)
			rotation.y = lerp_angle(rotation.y, home_yaw + diff, 0.2)
		else:
			rotation.y = lerp_angle(rotation.y, home_yaw, 0.1)
	if hands_up and state == &"hands_up" and Time.get_ticks_msec() * 0.001 > _hands_until:
		lower_hands()


func raise_hands(seconds: float = 6.0) -> void:
	if is_dead:
		return
	_hands_until = Time.get_ticks_msec() * 0.001 + seconds
	if hands_up:
		if rig != null:
			rig.play_action(&"hands_up")      # renews the hold
		return
	hands_up = true
	_set_state(&"hands_up")
	if rig != null:
		rig.play_action(&"hands_up")
	Sfx.play_3d(&"gasp", global_position + Vector3(0, 1.5, 0), -2.0, 1.0, 20.0)


func lower_hands() -> void:
	if not hands_up:
		return
	hands_up = false
	if rig != null:
		rig.play_action(&"hands_down")
	if not is_dead:
		_set_state(&"idle")


func mark_robbed() -> void:
	_set_state(&"robbed")


func _set_state(s: StringName) -> void:
	if state != s:
		state = s
		state_changed.emit(s)


func _on_damaged(_amount: float, _info: Dictionary) -> void:
	if rig != null:
		rig.play_action(&"hit_react")
	if not is_dead:
		_hands_until = Time.get_ticks_msec() * 0.001 + 8.0
		hands_up = false
		raise_hands(8.0)


func _on_death(info: Dictionary) -> void:
	hands_up = false
	died_at_ms = Time.get_ticks_msec()
	_set_state(&"dead")
	if _collider != null:
		_collider.set_deferred("disabled", true)
	if rig != null:
		var dir: Vector3 = info.get("direction", -global_transform.basis.z)
		rig.start_ragdoll(dir.normalized() * 4.0, info.get("position", global_position + Vector3.UP))
	Sfx.play_3d(&"death_m", global_position + Vector3.UP, 0.0, 1.0, 30.0)


## Back to the counter, alive (ShopSystem calls this when the player re-enters a long time after killing the clerk).
func respawn() -> void:
	if not is_dead and state != &"dead":
		return
	revive()
	position = home_pos
	rotation.y = home_yaw
	hands_up = false
	if rig != null:
		rig.stop_ragdoll()
		rig.setup(variant)
		if rig.has_method("set_idle_style"):
			rig.set_idle_style(idle_style)
	if _collider != null:
		_collider.set_deferred("disabled", false)
	_set_state(&"idle")


func can_respawn() -> bool:
	return is_dead and (Time.get_ticks_msec() - died_at_ms) * 0.001 >= RESPAWN_AFTER_S
