class_name PlayerSystem
extends Node
## Player agent entry point. Spawns the Player (CharacterBody3D, see player.gd) and the PlayerCamera, sets Game.player /
## Game.gameplay_camera, registers the player-specific InputMap actions, owns the death/busted fade overlay and exposes
## respawn helpers.
##
## Lifecycle: Main calls setup(main) once (boot order: after world/vehicles/combat), then post_setup() after all systems exist.

const STARTER_WEAPONS := {&"pistol": 36}
const FADE_LAYER := 90

var player: Player = null
var camera: PlayerCamera = null

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _fade_tween: Tween


func setup(_main: Node) -> void:
	_register_actions()
	_build_fade()
	camera = PlayerCamera.new()
	camera.name = "PlayerCamera"
	add_child(camera)

	player = Player.new()
	player.name = "Player"
	var spawn := _spawn_transform()
	player.position = spawn[0]
	player.rotation.y = spawn[1]
	add_child(player)
	player.camera = camera
	camera.setup(player)
	camera.make_current()
	player.fade_requested.connect(_on_fade_requested)
	player.teleport_to(spawn[0], spawn[1])    # also arms the "wait for ground" guard while the world is still empty

	Game.player = player
	Game.gameplay_camera = camera
	print("[Player] spawned at %s (rig fallback: %s)" % [str(player.global_position), str(player._rig_is_fallback)])


func post_setup() -> void:
	# a modest starter loadout so a fresh sandbox is immediately playable; saves override this on load
	var w = player.weapons
	if w != null and w.has_method("give_weapon"):
		var armed := false
		for id in w.get_weapon_ids():
			if id != &"fists":
				armed = true
		if not armed:
			for id in STARTER_WEAPONS:
				w.give_weapon(id, STARTER_WEAPONS[id])
			if w.has_method("equip") and not w.get_weapon_ids().is_empty():
				w.equip(STARTER_WEAPONS.keys()[0])


# ---- Public API --------------------------------------------------------------------------------------------------------
func get_player() -> Player:
	return player


func get_camera() -> PlayerCamera:
	return camera


## Teleport to a named WorldLayout location and revive. opts: see Player.respawn_at.
func respawn_at(location_id: StringName, opts: Dictionary = {}) -> void:
	if player != null:
		player.respawn_at(location_id, opts)


func teleport(pos: Vector3, yaw: float = NAN) -> void:
	if player != null:
		player.teleport_to(pos, yaw)


func serialize() -> Dictionary:
	return {"player": player.serialize()} if player != null else {}


func deserialize(data: Dictionary) -> void:
	if player != null and data.has("player"):
		player.deserialize(data["player"])


# ---- Internals --------------------------------------------------------------------------------------------------------
func _spawn_transform() -> Array:
	var loc: Dictionary = WorldLayout.get_location(&"player_spawn")
	if loc.is_empty():
		push_warning("[Player] WorldLayout has no 'player_spawn' - using (0, 2, 0)")
		return [Vector3(0, 2, 0), 0.0]
	return [(loc.get("pos", Vector3(0, 2, 0)) as Vector3) + Vector3(0, 0.2, 0), float(loc.get("yaw", 0.0))]


func _register_actions() -> void:
	# extra actions beyond InputSetup (additive, idempotent)
	_ensure_key(&"walk", KEY_ALT)
	_ensure_key(&"shoulder_swap", KEY_Z)


func _ensure_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == keycode:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "PlayerFade"
	_fade_layer.layer = FADE_LAYER
	_fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)


func _on_fade_requested(to_black: bool, seconds: float) -> void:
	if _fade_rect == null:
		return
	# the UI's DeathScreen owns the real fade; our overlay is the fallback when no UI fade exists
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("fade"):
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var target := 1.0 if to_black else 0.0
	if seconds <= 0.01:
		_fade_rect.modulate.a = target
		return
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade_rect, "modulate:a", target, seconds)
