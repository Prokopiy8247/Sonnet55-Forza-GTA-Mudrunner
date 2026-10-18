class_name DebugMenu
extends Node
## Benchmark / admin menu system (Game.sys(&"debug")). F1 or ` opens the tabbed DebugMenuUI (UIRoot menu &"debug"),
## Alt / numpad hotkeys run the common demo actions, and the stats panel + diagnostic gizmos live here.
## Cost when idle: two event callbacks (_input); _process only runs while the god-mode / boost / stats panel features are on.
## All real work is in DebugCmds (UI-free statics, used by the headless test).

const HOTKEY_TIMES: Array[float] = [5.9, 12.0, 19.2, 0.0]

var menu: DebugMenuUI = null
var gizmos: DebugGizmos = null
var spawn_at_crosshair := false

var _overlay_layer: CanvasLayer = null
var _overlay_label: Label = null
var _acc := 0.0
var _ft_max := 0.0
var _time_idx := 0
var _weather_idx := 0


func setup(_main: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func post_setup() -> void:
	if Game.ui != null:
		menu = DebugMenuUI.new()
		menu.owner_menu = self
		Game.ui.register_menu(&"debug", menu)
	gizmos = DebugGizmos.new()
	var parent: Node = Game.world if Game.world != null else get_parent()
	parent.add_child(gizmos)
	refresh_state()


# ---- menu control ---------------------------------------------------------------------------------------------------
func is_open() -> bool:
	return Game.ui != null and Game.ui.current_menu_id == &"debug"


func open(tab: int = -1) -> bool:
	if menu == null or Game.ui == null:
		return false
	if is_open():
		if tab >= 0:
			menu.show_tab(tab)
		return true
	if Game.ui.is_input_blocked() or (is_instance_valid(Game.player) and bool(Game.player.get("is_dead"))):
		return false
	return Game.ui.open_menu(&"debug", {"tab": tab} if tab >= 0 else {})


func close() -> void:
	if is_open():
		Game.ui.close_menu()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


# ---- input: F1 / backquote + hotkey layer ------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var ke := event as InputEventKey
	if event.is_action_pressed(&"debug_menu"):
		var fo := get_viewport().gui_get_focus_owner()
		if ke.physical_keycode == KEY_QUOTELEFT and fo is LineEdit:
			return                                           # typing a backquote in a text field
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _hotkey(ke):
		get_viewport().set_input_as_handled()


func _hotkey(ke: InputEventKey) -> bool:
	if Game.ui != null and Game.ui.is_input_blocked() and not is_open():
		return false
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return false                                         # typing into a text field (numpad digits, Alt combos)
	var k: Key = ke.physical_keycode
	var alt := ke.alt_pressed and not ke.ctrl_pressed
	var res: Dictionary = {}
	# numpad (not bound by the game) - works without Alt
	match k:
		KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5:
			res = DebugCmds.set_wanted(int(k - KEY_KP_0))
		KEY_KP_MULTIPLY:
			res = _cycle_time()
		KEY_KP_ADD:
			res = DebugCmds.set_time(Game.time_of_day + 1.0)
		KEY_KP_SUBTRACT:
			res = DebugCmds.set_time(Game.time_of_day - 1.0)
		KEY_KP_DIVIDE:
			res = _cycle_weather()
		KEY_KP_ENTER:
			res = DebugCmds.spawn_last_vehicle()
		KEY_KP_PERIOD:
			res = DebugCmds.repair_current()
		KEY_KP_6:
			res = DebugCmds.give_all_weapons()
		KEY_KP_7:
			res = DebugCmds.heal_full()
		KEY_KP_8:
			res = DebugCmds.add_money(10000)
		KEY_KP_9:
			res = _toggle_god()
	if res.is_empty() and alt:
		match k:
			KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				res = DebugCmds.set_wanted(int(k - KEY_0))
			KEY_T:
				res = _cycle_time()
			KEY_W:
				res = _cycle_weather()
			KEY_V:
				res = DebugCmds.spawn_last_vehicle()
			KEY_R:
				res = DebugCmds.repair_current()
			KEY_H:
				res = DebugCmds.heal_full()
			KEY_M:
				res = DebugCmds.add_money(1000000 if ke.shift_pressed else 10000)
			KEY_G:
				res = _toggle_god()
			KEY_K:
				res = DebugCmds.give_all_weapons()
			KEY_B:
				res = DebugCmds.teleport_to_waypoint()
			KEY_X:
				res = DebugCmds.delete_nearby_vehicles(80.0)
			KEY_Z:
				res = DebugCmds.set_slowmo(not bool(Game.cheats.get("slowmo", false)))
			KEY_P:
				res = DebugCmds.spawn_police(&"car", false)
			KEY_E:
				res = DebugCmds.explode_at_crosshair()
			KEY_F:
				res = DebugCmds.set_cheat("dbg_stats", not bool(Game.cheats.get("dbg_stats", false)))
				refresh_state()
	if res.is_empty():
		return false
	Events.notification.emit(String(res.get("msg", "")), &"good" if res.get("ok", false) else &"warn")
	if menu != null and is_open():
		menu.refresh()
	return true


func _cycle_time() -> Dictionary:
	_time_idx = (_time_idx + 1) % HOTKEY_TIMES.size()
	return DebugCmds.set_time(HOTKEY_TIMES[_time_idx])


func _cycle_weather() -> Dictionary:
	_weather_idx = (_weather_idx + 1) % GC.WEATHERS.size()
	return DebugCmds.set_weather(GC.WEATHERS[_weather_idx])


func _toggle_god() -> Dictionary:
	var on := not bool(Game.cheats.get("invulnerable", false))
	DebugCmds.set_invulnerable(on)
	var r := DebugCmds.set_vehicle_god(on)
	r["msg"] = "God mode %s (player + vehicle)" % ("ON" if on else "OFF")
	refresh_state()
	return r


# ---- per-feature process gating --------------------------------------------------------------------------------------------------
## Call after a cheat flag changed: switches the tick / gizmos / stats panel on or off so an idle menu costs nothing.
func refresh_state() -> void:
	if gizmos != null:
		gizmos.refresh_state()
	var stats_on := bool(Game.cheats.get("dbg_stats", false))
	if stats_on and _overlay_label == null:
		_build_overlay()
	if _overlay_layer != null:
		_overlay_layer.visible = stats_on
	var needs := stats_on or bool(Game.cheats.get("vehicle_god", false)) or float(Game.cheats.get("vehicle_boost", 1.0)) > 1.001
	set_process(needs)
	_acc = 1.0


func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 12
	_overlay_layer.name = "DebugStatsLayer"
	add_child(_overlay_layer)
	_overlay_label = Label.new()
	_overlay_label.theme = UITheme.build()
	_overlay_label.position = Vector2(24, 300)
	_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_label.add_theme_font_size_override("font_size", 19)
	_overlay_label.add_theme_color_override("font_color", UITheme.C_TEXT)
	_overlay_label.add_theme_stylebox_override("normal", UITheme.box(10, Color(0.03, 0.05, 0.08, 0.78), 1, UITheme.C_BORDER_HI, 14, 10))
	_overlay_layer.add_child(_overlay_label)


func _process(dt: float) -> void:
	_ft_max = maxf(_ft_max * (1.0 - dt * 0.4), dt * 1000.0)
	_acc += dt
	if _acc < 0.25:
		return
	_acc = 0.0
	if bool(Game.cheats.get("vehicle_god", false)):
		DebugCmds.apply_vehicle_god()
	if float(Game.cheats.get("vehicle_boost", 1.0)) > 1.001 or DebugCmds._boost_prev != null:
		DebugCmds.apply_speed_boost()
	if _overlay_label != null and _overlay_layer.visible:
		var hidden: bool = Game.ui != null and bool(Game.ui.get("hud_hidden"))
		_overlay_label.visible = not hidden and not bool(Game.cheats.get("photo_mode", false))
		if _overlay_label.visible:
			_overlay_label.text = DebugCmds.stats_text(_ft_max)
