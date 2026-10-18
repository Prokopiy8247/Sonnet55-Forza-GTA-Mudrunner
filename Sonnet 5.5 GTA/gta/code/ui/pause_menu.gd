class_name PauseMenu
extends MenuBase
## Pause menu (Esc): GAME (resume, map, save / load, quit), STATUS (skills + stats), SETTINGS (audio, mouse, FOV, shadows,
## fullscreen ...), CONTROLS (live key reference from the InputMap).

const CONTROLS := [
	["On foot", [
		["Move", ["move_forward", "move_left", "move_back", "move_right"]], ["Sprint", ["sprint"]], ["Jump", ["jump"]],
		["Crouch / stealth", ["crouch"]], ["Take cover", ["cover"]], ["Interact", ["interact"]], ["Enter / exit vehicle", ["enter_exit"]],
		["Camera view", ["camera_toggle"]], ["Flashlight", ["flashlight"]], ["Phone", ["phone"]], ["Map", ["map"]]]],
	["Combat", [
		["Fire", ["fire"]], ["Aim", ["aim"]], ["Reload", ["reload"]], ["Melee", ["melee"]], ["Grenade", ["grenade"]],
		["Weapon wheel (hold)", ["weapon_wheel"]], ["Next / previous weapon", ["weapon_next", "weapon_prev"]], ["Weapon slots", ["weapon_slot_1", "weapon_slot_9"]]]],
	["Driving", [
		["Accelerate / brake / steer", ["move_forward", "move_back", "move_left", "move_right"]], ["Handbrake", ["handbrake"]], ["Horn", ["horn"]],
		["Headlights", ["headlights"]], ["Siren", ["siren"]], ["Radio next / previous", ["radio_next", "radio_prev"]], ["Look back", ["look_back"]]]],
	["Aircraft", [
		["Pitch", ["air_pitch_down", "air_pitch_up"]], ["Roll", ["air_roll_left", "air_roll_right"]], ["Yaw", ["air_yaw_left", "air_yaw_right"]],
		["Throttle / collective", ["air_throttle_up", "air_throttle_down"]], ["Landing gear", ["air_gear"]], ["Parachute", ["parachute"]]]],
	["System", [
		["Pause", ["pause"]], ["Quick save / load", ["quick_save", "quick_load"]], ["Debug menu", ["debug_menu"]], ["FPS overlay", ["debug_overlay"]], ["Photo mode", ["photo_mode"]]]],
]

var _tabs: HBoxContainer
var _pages: Array[Control] = []
var _stack: Control
var _status_page: StatusScreen.Page
var _game_stats: VBoxContainer
var _tab_index := 0
var _acc := 0.0
var _save_row_label: Label


func _init() -> void:
	super._init()
	pauses_game = true
	var b := build_frame("Paused", GC.GAME_NAME, 1240, 760)
	_tabs = UIKit.tab_bar(["Game", "Status", "Settings", "Controls"], _select_tab)
	b.add_child(_tabs)
	_stack = Control.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.custom_minimum_size = Vector2(0, 520)
	b.add_child(_stack)
	_pages = [_build_game_page(), _build_status_page(), _build_settings_page(), _build_controls_page()]
	for p in _pages:
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_stack.add_child(p)
	_select_tab(0)
	set_hints([["Esc", "Resume"], ["Tab", "Next page"]])


func _on_open(d: Dictionary) -> void:
	var start := int(d.get("tab", 0))
	UIKit.tab_select(_tabs, start)
	_select_tab(start)
	_refresh_game_stats()


func _on_close() -> void:
	if SaveSystem != null and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()


func _select_tab(i: int) -> void:
	_tab_index = i
	for k in _pages.size():
		_pages[k].visible = (k == i)
	if i == 1 and _status_page != null:
		_status_page.refresh()
	if i == 0:
		_refresh_game_stats()
	if visible:
		call_deferred("_focus_page")


func _focus_page() -> void:
	if _tab_index == 0 or _tab_index == 2:
		var f := _first_focusable(_pages[_tab_index])
		if f != null:
			f.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.pressed and not k.echo and k.physical_keycode == KEY_TAB:
		var step := -1 if k.shift_pressed else 1
		var nxt := posmod(_tab_index + step, _pages.size())
		UIKit.tab_select(_tabs, nxt)
		_select_tab(nxt)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_acc += delta
	if _acc > 0.5:
		_acc = 0.0
		if _tab_index == 0:
			_refresh_game_stats()
	if _tab_index == 1 and _status_page != null:
		_status_page.tick()


# ---- GAME page ------------------------------------------------------------------------------------------------------------
func _build_game_page() -> Control:
	var h := UIKit.hbox(28)
	var left := UIKit.vbox(12)
	left.custom_minimum_size = Vector2(420, 0)
	h.add_child(left)
	left.add_child(UIKit.button("Resume", func(): _resume(), &"AccentButton"))
	left.add_child(UIKit.button("Open Map", _open_map))
	left.add_child(UIKit.button("Save Game", _do_save))
	left.add_child(UIKit.button("Load Game", _do_load))
	left.add_child(UIKit.spacer(10))
	left.add_child(UIKit.button("Quit to Desktop", _ask_quit, &"DangerButton"))
	_save_row_label = UIKit.label("", 17, UITheme.C_DIM)
	left.add_child(_save_row_label)
	var right := UIKit.panel(&"PanelDeep")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_game_stats = UIKit.vbox(10)
	right.add_child(_game_stats)
	return h


func _refresh_game_stats() -> void:
	if _game_stats == null:
		return
	for c in _game_stats.get_children():
		c.queue_free()
	_game_stats.add_child(UIKit.caption("Current situation"))
	var pp := Game.get_player_position()
	var wtxt := "None" if Game.wanted_level <= 0 else "%d star%s - %s" % [Game.wanted_level, "" if Game.wanted_level == 1 else "s", String(Game.wanted_state).capitalize()]
	var wcol := UITheme.C_TEXT if Game.wanted_level <= 0 else UITheme.C_GOLD
	var p = Game.player
	var hp := ""
	if is_instance_valid(p) and p.get("health") != null:
		hp = "%d / %d" % [int(ceil(float(p.get("health")))), int(p.get("max_health")) if p.get("max_health") != null else 100]
	var weapon_txt := "-"
	if is_instance_valid(p) and p.get("weapons") != null:
		weapon_txt = str(UIIcons.weapon_info(p.weapons.current_id)["name"])
	var st: Dictionary = Game.ui.get("stats") if Game.ui != null and Game.ui.get("stats") != null else {}
	for row in [["Cash", Util.format_money(Game.cash), UITheme.C_OK], ["Health", hp, UITheme.C_TEXT], ["Wanted", wtxt, wcol],
			["Weapon", weapon_txt, UITheme.C_TEXT], ["Time", Util.format_clock(Game.time_of_day), UITheme.C_TEXT],
			["Weather", String(Game.weather).capitalize(), UITheme.C_TEXT],
			["District", Hud.district_name(WorldLayout.district_at(pp.x, pp.z)), UITheme.C_ACCENT]]:
		_game_stats.add_child(UIKit.stat_row(row[0], row[1], row[2]))
	_game_stats.add_child(UIKit.spacer(10))
	_game_stats.add_child(UIKit.caption("This session"))
	_game_stats.add_child(UIKit.stat_row("Time played", StatusScreen.format_time(float(st.get("time_played", 0.0)))))
	_game_stats.add_child(UIKit.stat_row("Distance travelled", StatusScreen.format_dist(float(st.get("dist_foot", 0.0)) + float(st.get("dist_driven", 0.0)))))
	_game_stats.add_child(UIKit.stat_row("Kills", str(int(st.get("kills", 0)))))
	var has_save: bool = SaveSystem != null and SaveSystem.has_method("has_save") and SaveSystem.has_save(0)
	if _save_row_label != null:
		_save_row_label.text = "A save exists in slot 1." if has_save else "No save in slot 1 yet."


func _resume() -> void:
	if Game.ui != null:
		Game.ui.close_menu()


func _do_save() -> void:
	var ok: bool = SaveSystem != null and SaveSystem.has_method("save_game") and SaveSystem.save_game(0)
	toast("Game saved." if ok else "Saving is not available yet.", &"good" if ok else &"warn")
	_refresh_game_stats()


func _do_load() -> void:
	if SaveSystem == null or not SaveSystem.has_method("has_save") or not SaveSystem.has_save(0):
		toast("No saved game found.", &"warn")
		return
	confirm("Load game", "Unsaved progress will be replaced by your last save.", _load_now, Callable(), "Load", "Cancel")


func _load_now() -> void:
	var ok: bool = SaveSystem.load_game(0)
	toast("Game loaded." if ok else "Loading failed.", &"good" if ok else &"bad")
	if ok and Game.ui != null:
		Game.ui.close_menu()


func _open_map() -> void:
	var ui = Game.ui
	if ui != null:
		ui.close_menu()
		ui.open_menu(&"map")


func _ask_quit() -> void:
	confirm("Quit to desktop", "Unsaved progress will be lost.", _quit_now, Callable(), "Quit", "Stay")


func _quit_now() -> void:
	get_tree().quit()


# ---- STATUS page -------------------------------------------------------------------------------------------------------------
func _build_status_page() -> Control:
	_status_page = StatusScreen.Page.new()
	return _status_page


# ---- SETTINGS page ---------------------------------------------------------------------------------------------------------------
func _build_settings_page() -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UIKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(UIKit.margin(v, 0, 0, 24, 0))
	var s: Dictionary = Game.settings
	var pct := func(x: float) -> String: return "%d%%" % int(round(x * 100.0))
	v.add_child(UIKit.caption("Audio"))
	v.add_child(UIKit.slider_row("Master volume", 0.0, 1.0, float(s.get("master_volume", 0.8)), 0.01, func(x): _set_setting("master_volume", x), pct))
	v.add_child(UIKit.slider_row("Music volume", 0.0, 1.0, float(s.get("music_volume", 0.6)), 0.01, func(x): _set_setting("music_volume", x), pct))
	v.add_child(UIKit.slider_row("Effects volume", 0.0, 1.0, float(s.get("sfx_volume", 1.0)), 0.01, func(x): _set_setting("sfx_volume", x), pct))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.caption("Controls and camera"))
	v.add_child(UIKit.slider_row("Mouse sensitivity", 0.2, 3.0, float(s.get("mouse_sensitivity", 1.0)), 0.05, func(x): _set_setting("mouse_sensitivity", x), func(x: float) -> String: return "%.2fx" % x))
	v.add_child(UIKit.toggle_row("Invert Y axis", bool(s.get("invert_y", false)), func(on): _set_setting("invert_y", on)))
	v.add_child(UIKit.slider_row("Field of view", 55.0, 110.0, float(s.get("fov", 75.0)), 1.0, func(x): _set_setting("fov", x), func(x: float) -> String: return "%d deg" % int(x)))
	v.add_child(UIKit.toggle_row("Camera shake", bool(s.get("camera_shake", true)), func(on): _set_setting("camera_shake", on)))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.caption("Display"))
	v.add_child(UIKit.toggle_row("Shadows", bool(s.get("shadows", true)), func(on): _set_setting("shadows", on)))
	v.add_child(UIKit.toggle_row("Fullscreen", bool(s.get("fullscreen", false)), func(on): _set_setting("fullscreen", on)))
	v.add_child(UIKit.toggle_row("Round minimap", bool(s.get("minimap_round", true)), func(on): _set_setting("minimap_round", on)))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.caption("World"))
	v.add_child(UIKit.slider_row("Traffic density", 0.0, 1.5, float(s.get("traffic_density", 1.0)), 0.05, func(x): _set_setting("traffic_density", x), pct))
	v.add_child(UIKit.slider_row("Pedestrian density", 0.0, 1.5, float(s.get("ped_density", 1.0)), 0.05, func(x): _set_setting("ped_density", x), pct))
	return sc


func _set_setting(key: String, value: Variant) -> void:
	Game.settings[key] = value
	if Game.ui != null and Game.ui.has_method("apply_settings"):
		Game.ui.apply_settings()
	Events.settings_changed.emit()


# ---- CONTROLS page ----------------------------------------------------------------------------------------------------------------
func _build_controls_page() -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	for section in CONTROLS:
		var p := UIKit.panel(&"PanelDeep")
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var v := UIKit.vbox(8)
		p.add_child(v)
		v.add_child(UIKit.caption(section[0]))
		for row in section[1]:
			var r := UIKit.hbox(10)
			var l := UIKit.label(row[0], 19, UITheme.C_TEXT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(l)
			var keys := UIKit.hbox(5)
			var actions: Array = row[1]
			if row[0] == "Weapon slots":
				keys.add_child(UIKit.keycap("1"))
				keys.add_child(UIKit.label("-", 17, UITheme.C_DIM))
				keys.add_child(UIKit.keycap("9"))
			else:
				var seen: Array[String] = []
				for a in actions:
					var kt := UIKit.action_key(StringName(a))
					if not seen.has(kt):
						seen.append(kt)
						keys.add_child(UIKit.keycap(kt))
			r.add_child(keys)
			v.add_child(r)
		grid.add_child(p)
	return sc
