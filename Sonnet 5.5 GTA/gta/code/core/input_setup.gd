class_name InputSetup
extends RefCounted
## Registers every gameplay InputMap action in code (single source of truth, see docs/ARCHITECTURE.md §6).
## Call InputSetup.register() once at boot (Main does this). Safe to call repeatedly.

static func register() -> void:
	# ---- On foot / shared movement (also used for driving: forward=throttle, back=brake/reverse) ----
	_keys(&"move_forward", [KEY_W, KEY_UP])
	_keys(&"move_back", [KEY_S, KEY_DOWN])
	_keys(&"move_left", [KEY_A, KEY_LEFT])
	_keys(&"move_right", [KEY_D, KEY_RIGHT])
	_keys(&"sprint", [KEY_SHIFT])
	_keys(&"jump", [KEY_SPACE])
	_keys(&"handbrake", [KEY_SPACE])
	_keys(&"crouch", [KEY_C, KEY_CTRL])          # crouch / stealth toggle
	_keys(&"cover", [KEY_Q])
	_keys(&"melee", [KEY_X])
	_keys(&"grenade", [KEY_G])
	_keys(&"interact", [KEY_E])
	_keys(&"enter_exit", [KEY_F])
	_keys(&"reload", [KEY_R])
	_keys(&"flashlight", [KEY_T])
	_keys(&"weapon_wheel", [KEY_TAB])
	_keys(&"camera_toggle", [KEY_V])
	_keys(&"map", [KEY_M])
	_keys(&"pause", [KEY_ESCAPE])
	_keys(&"phone", [KEY_P])
	_keys(&"horn", [KEY_H])
	_keys(&"headlights", [KEY_L])
	_keys(&"siren", [KEY_N])
	_keys(&"radio_next", [KEY_PERIOD])
	_keys(&"radio_prev", [KEY_COMMA])
	_keys(&"look_back", [KEY_B])
	_mouse(&"fire", MOUSE_BUTTON_LEFT)
	_mouse(&"aim", MOUSE_BUTTON_RIGHT)
	_mouse(&"weapon_next", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse(&"weapon_prev", MOUSE_BUTTON_WHEEL_UP)
	for i in 9:
		_keys(StringName("weapon_slot_%d" % (i + 1)), [KEY_1 + i])
	# ---- Aircraft (planes: pitch/roll/yaw/throttle; helicopters: collective via throttle up/down) -------
	_keys(&"air_pitch_down", [KEY_W, KEY_UP])    # nose down / heli forward
	_keys(&"air_pitch_up", [KEY_S, KEY_DOWN])    # nose up / heli backward
	_keys(&"air_roll_left", [KEY_A, KEY_LEFT])
	_keys(&"air_roll_right", [KEY_D, KEY_RIGHT])
	_keys(&"air_yaw_left", [KEY_Q])
	_keys(&"air_yaw_right", [KEY_E])
	_keys(&"air_throttle_up", [KEY_SHIFT, KEY_SPACE])   # plane throttle up / heli collective up
	_keys(&"air_throttle_down", [KEY_CTRL])             # plane throttle down / heli collective down
	_keys(&"air_gear", [KEY_G])
	# ---- Debug / utility ----------------------------------------------------------------------------------
	_keys(&"debug_menu", [KEY_F1, KEY_QUOTELEFT])
	_keys(&"debug_overlay", [KEY_F2])
	_keys(&"photo_mode", [KEY_F3])
	_keys(&"quick_save", [KEY_F5])
	_keys(&"quick_load", [KEY_F9])
	_keys(&"parachute", [KEY_SPACE])


static func _keys(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for kc in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = kc as Key
		if not _has_event(action, ev):
			InputMap.action_add_event(action, ev)


static func _mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	if not _has_event(action, ev):
		InputMap.action_add_event(action, ev)


static func _has_event(action: StringName, ev: InputEvent) -> bool:
	for e in InputMap.action_get_events(action):
		if e.is_match(ev, true) and e.get_class() == ev.get_class():
			return true
	return false
