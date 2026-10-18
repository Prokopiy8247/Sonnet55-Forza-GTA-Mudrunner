class_name PhoneMenu
extends MenuBase
## The in-game smartphone (key P, menu id &"phone"). Built with UIKit: rounded device frame, sunset wallpaper, app tiles, animated
## slide-in / slide-out. It does NOT pause the game or slow time (pauses_game = false): the city keeps running behind the phone.
## Apps: Services (taxi / vehicle service / mechanic), Vehicles (stored cars), Camera (photo mode), Map, Quick save, Radio, Settings
## (volume), Stats. Every service degrades gracefully (toast) when the system behind it does not exist yet.

const W := 396.0
const H := 780.0

const APPS: Array = [
	{"id": &"services", "name": "Services", "col": Color(0.12, 0.62, 0.78)},
	{"id": &"vehicles", "name": "Vehicles", "col": Color(0.82, 0.2, 0.52)},
	{"id": &"camera", "name": "Camera", "col": Color(0.9, 0.55, 0.14)},
	{"id": &"map", "name": "Map", "col": Color(0.25, 0.65, 0.4)},
	{"id": &"save", "name": "Quick Save", "col": Color(0.24, 0.42, 0.85)},
	{"id": &"radio", "name": "Radio", "col": Color(0.5, 0.32, 0.85)},
	{"id": &"settings", "name": "Settings", "col": Color(0.4, 0.45, 0.52)},
	{"id": &"stats", "name": "Stats", "col": Color(0.15, 0.6, 0.62)},
]

var page: StringName = &"home"
var slide := 0.0 : set = _set_slide
var _device: PanelContainer = null
var _content: VBoxContainer = null
var _clock: Label = null
var _battery: ProgressBar = null
var _tween: Tween = null
var _closing := false
var _instant_close := false
var _tick := 0.0
var _last_station_label: Label = null


func _init() -> void:
	super._init()
	dim_background = false
	pauses_game = false
	wants_cursor = true
	closes_on_pause = true


func _on_open(_d: Dictionary) -> void:
	_closing = false
	_instant_close = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_build()
	page = &"home"
	_show_home()
	slide = 0.0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ignore_time_scale(true)
	_tween.tween_method(func(v: float): slide = v, 0.0, 1.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if Sfx != null:
		Sfx.play_ui(&"ui_notify", -6.0)


## Animated close; UIRoot treats the menu as closed immediately, `closed` fires when the slide-out has finished.
func close() -> void:
	if _closing or not is_open:
		return
	if _instant_close or _device == null or DisplayServer.get_name() == "headless":
		super.close()
		return
	_closing = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ignore_time_scale(true)
	_tween.tween_method(func(v: float): slide = v, slide, 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _tween.finished
	if _closing:
		_closing = false
		super.close()


func _set_slide(v: float) -> void:
	slide = v
	if _device == null or not is_instance_valid(_device):
		return
	_device.offset_top = lerpf(60.0, -H - 36.0, clampf(v, 0.0, 1.2) if v <= 1.0 else v)
	_device.offset_bottom = _device.offset_top + H
	_device.modulate.a = clampf(v * 2.2, 0.0, 1.0)


func on_back() -> bool:
	if page != &"home":
		_show_home()
		return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_BACKSPACE:
		if page != &"home":
			_show_home()
			get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not is_open:
		return
	_tick -= dt
	if _tick <= 0.0:
		_tick = 0.5
		if _clock != null:
			_clock.text = Util.format_clock(Game.time_of_day)


# =====================================================================================================
# Frame
# =====================================================================================================
func _build() -> void:
	for c in get_children():
		c.queue_free()
	_device = UIKit.panel()
	_device.add_theme_stylebox_override("panel", UITheme.box(46, Color(0.025, 0.032, 0.048, 0.99), 4, Color(0.2, 0.88, 1.0, 0.55), 10, 10, 26))
	_device.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_device.offset_left = -W - 52
	_device.offset_right = -52
	_device.offset_top = -H - 36
	_device.offset_bottom = -36
	_device.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_device)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UITheme.box(36, Color(0.05, 0.04, 0.12, 1.0)))
	screen.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_device.add_child(screen)
	# wallpaper
	var wall := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.05, 0.04, 0.16), Color(0.32, 0.08, 0.38), Color(0.92, 0.32, 0.38), Color(1.0, 0.62, 0.28)])
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.78, 1.0])
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	wall.texture = gt
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(wall)
	var deco := UIKit.IconBox.new()
	deco.draw_cb = _draw_wallpaper
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(deco)
	# page content lives in a clipping holder: a page that is wider than the screen can never stretch the device out of its frame
	var holder := Control.new()
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	screen.add_child(holder)
	var col := UIKit.vbox(0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(col)
	# status bar
	var sb := UIKit.hbox(8)
	sb.custom_minimum_size = Vector2(0, 44)
	var sbm := UIKit.margin(sb, 22, 12, 22, 0)
	col.add_child(sbm)
	_clock = UIKit.label(Util.format_clock(Game.time_of_day), 18, UITheme.C_TEXT, true)
	sb.add_child(_clock)
	var carrier := UIKit.label("HALCYON 5G", 15, UITheme.with_alpha(UITheme.C_TEXT, 0.75), false, HORIZONTAL_ALIGNMENT_CENTER)
	carrier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.add_child(carrier)
	_battery = UIKit.bar(0.82, UITheme.C_OK, 10)
	_battery.custom_minimum_size = Vector2(34, 10)
	sb.add_child(_battery)
	# page area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_content = UIKit.vbox(10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(UIKit.margin(_content, 20, 6, 20, 6))
	scroll.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# home bar
	var home := Button.new()
	home.flat = true
	home.custom_minimum_size = Vector2(0, 38)
	home.focus_mode = Control.FOCUS_NONE
	home.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var pill := ColorRect.new()
	pill.color = Color(1, 1, 1, 0.55)
	pill.custom_minimum_size = Vector2(120, 5)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pill.offset_left = -60
	pill.offset_right = 60
	pill.offset_top = -2
	pill.offset_bottom = 3
	home.add_child(pill)
	home.pressed.connect(func():
		UIKit.click()
		_show_home())
	col.add_child(home)
	set_hints([["P", "Close phone"], ["Backspace", "Back"]])
	_set_slide(slide)


func _draw_wallpaper(ci: Control, rect: Rect2) -> void:
	var sun_c := Vector2(rect.size.x * 0.5, rect.size.y * 0.8)
	ci.draw_circle(sun_c, 70.0, Color(1.0, 0.82, 0.45, 0.9))
	ci.draw_circle(sun_c, 100.0, Color(1.0, 0.7, 0.4, 0.18))
	for i in 7:
		var y := sun_c.y + 6.0 + float(i) * 11.0
		ci.draw_rect(Rect2(Vector2(0, y), Vector2(rect.size.x, 3.0 + float(i) * 0.8)), Color(0.12, 0.05, 0.22, 0.95))
	ci.draw_rect(Rect2(Vector2(0, sun_c.y + 6.0), Vector2(rect.size.x, rect.size.y)), Color(0.12, 0.05, 0.22, 0.55))


func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()


# =====================================================================================================
# Pages
# =====================================================================================================
func _show_home() -> void:
	page = &"home"
	_clear()
	var big := UIKit.label(Util.format_clock(Game.time_of_day), 58, UITheme.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	big.add_theme_font_override("font", UITheme.font_display())
	_content.add_child(UIKit.margin(big, 0, 14, 0, 0))
	var wthr := UIKit.label("%s   -   %s" % [String(Game.weather).capitalize(), Util.format_money(Game.cash)], 18, UITheme.with_alpha(UITheme.C_TEXT, 0.85), false, HORIZONTAL_ALIGNMENT_CENTER)
	_content.add_child(wthr)
	_content.add_child(UIKit.spacer(14))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	for a in APPS:
		grid.add_child(_tile(a))


func _tile(a: Dictionary) -> Control:
	var v := UIKit.vbox(5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 92)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base: Color = a["col"]
	for st in ["normal", "hover", "pressed", "focus"]:
		var sbx := UITheme.box(24, base.lightened(0.18) if st == "hover" else (base.darkened(0.15) if st == "pressed" else base), 3 if st == "focus" else 0, Color(1, 1, 1, 0.9), 0, 0, 8)
		b.add_theme_stylebox_override(st, sbx)
	var icon := UIKit.IconBox.new()
	var aid: StringName = a["id"]
	icon.draw_cb = func(ci: Control, r: Rect2): PhoneIcons.draw(ci, aid, r.grow(-22), Color(1, 1, 1, 0.97))
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(icon)
	b.pressed.connect(func():
		UIKit.click()
		_open_app(aid))
	v.add_child(b)
	var l := UIKit.label(String(a["name"]), 16, UITheme.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(0, 0)
	v.add_child(l)
	return v


func _open_app(id: StringName) -> void:
	match id:
		&"services":
			_page_services()
		&"vehicles":
			_page_vehicles()
		&"camera":
			_close_then(func():
				var gs = Game.sys(&"garage")
				if gs != null:
					gs.start_photo_mode())
		&"map":
			_instant_close = true
			if Game.ui != null:
				Game.ui.open_menu(&"map")
		&"save":
			_quick_save()
		&"radio":
			_page_radio()
		&"settings":
			_page_settings()
		&"stats":
			_page_stats()


func _close_then(cb: Callable) -> void:
	if Game.ui != null:
		Game.ui.close_menu()
	await get_tree().create_timer(0.3, true, false, true).timeout
	cb.call()


func _app_header(title: String) -> void:
	_clear()
	var h := UIKit.hbox(8)
	var back := UIKit.button("<", func(): _show_home())
	back.custom_minimum_size = Vector2(46, 42)
	h.add_child(back)
	h.add_child(UIKit.label(title, 26, UITheme.C_TEXT, true))
	_content.add_child(h)
	_content.add_child(UIKit.separator())


# ---- Services ---------------------------------------------------------------------------------------------------------------
func _page_services() -> void:
	page = &"services"
	_app_header("Services")
	_content.add_child(UIKit.list_row("Taxi", "Call a cab to your location", "", func(): _call_taxi()))
	_content.add_child(UIKit.list_row("Vehicle service", "Deliver one of your stored vehicles", "", func(): _page_vehicles()))
	var v := _target_vehicle()
	var gs = Game.sys(&"garage")
	var sub := "Repair your vehicle on the spot"
	var cost: Variant = ""
	if v != null and gs != null:
		if gs.repair_needed(v):
			sub = "%s - %d %% condition" % [v.display_name, int(round(v.get_health_ratio() * 100.0))]
			cost = 0 if gs.is_free() else gs.repair_cost(v) + MECHANIC_FEE
		else:
			sub = "%s needs no repairs" % v.display_name
	_content.add_child(UIKit.list_row("Mechanic", sub, cost, func(): _call_mechanic()))
	_content.add_child(UIKit.label("Mechanic callout: %s + repair cost." % Util.format_money(MECHANIC_FEE), 15, UITheme.with_alpha(UITheme.C_TEXT, 0.7)))


const MECHANIC_FEE := 40


func _call_taxi() -> void:
	var t = Game.sys(&"transit")
	if t != null and t.has_method("call_taxi"):
		_close_then(func():
			var r = t.call_taxi()
			if r is bool and not r:
				Game.notify("No taxi available right now.", &"warn"))
	else:
		toast("Taxi service is currently unavailable.", &"warn")
		if Sfx != null:
			Sfx.play_ui(&"ui_error")


func _target_vehicle() -> VehicleBase:
	var p = Game.player
	if not is_instance_valid(p):
		return null
	var cur = p.get("current_vehicle")
	if cur is VehicleBase and is_instance_valid(cur):
		return cur
	var vs = Game.sys(&"vehicles")
	if vs != null and vs.has_method("find_nearest_vehicle"):
		var near = vs.find_nearest_vehicle(p.global_position, 9.0)
		if near is VehicleBase and (near as VehicleBase).is_player_owned:
			return near
	return null


func _call_mechanic() -> void:
	var gs = Game.sys(&"garage")
	var v := _target_vehicle()
	if gs == null or v == null:
		toast("Get in (or next to) your vehicle first.", &"warn")
		return
	if not gs.repair_needed(v):
		toast("%s does not need repairs." % v.display_name, &"info")
		return
	var cost: int = 0 if gs.is_free() else gs.repair_cost(v) + MECHANIC_FEE
	if not gs.is_free() and not Game.can_afford(cost):
		toast("Not enough cash: the mechanic wants %s." % Util.format_money(cost), &"bad")
		return
	confirm("Call the mechanic?", "%s will be repaired for %s." % [v.display_name, "FREE" if cost <= 0 else Util.format_money(cost)], func():
		if not gs.is_free():
			if not Game.spend_cash(MECHANIC_FEE):
				return
		Game.notify("Mechanic is on the way...", &"info")
		var tree := get_tree()
		await tree.create_timer(3.5, true, false, true).timeout
		if is_instance_valid(v):
			gs.repair_vehicle(v, true)
			Game.notify("%s repaired by the mechanic." % v.display_name, &"good"), Callable(), "Call", "Cancel")


# ---- Vehicles -----------------------------------------------------------------------------------------------------------------
func _page_vehicles() -> void:
	page = &"vehicles"
	_app_header("Vehicle service")
	var gs = Game.sys(&"garage")
	if gs == null:
		_content.add_child(UIKit.label("Garage service unavailable.", 20, UITheme.C_DIM))
		return
	_content.add_child(UIKit.label("Stored vehicles %d / %d" % [GarageSystem.MAX_SLOTS - gs.free_slot_count(), GarageSystem.MAX_SLOTS], 18, UITheme.C_DIM))
	var list := UIKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(list)
	GarageStoredMenu.build_slot_list(gs, list, false, true)
	if not gs.stored_changed.is_connected(_on_stored_changed):
		gs.stored_changed.connect(_on_stored_changed)


func _on_stored_changed() -> void:
	if is_open and page == &"vehicles":
		_page_vehicles()


# ---- Quick save ---------------------------------------------------------------------------------------------------------------------
func _quick_save() -> void:
	var ok := false
	if SaveSystem != null and SaveSystem.has_method("save_game"):
		ok = bool(SaveSystem.save_game(0))
	if ok:
		toast("Game saved to slot 1.", &"good")
		if Sfx != null:
			Sfx.play_ui(&"ui_confirm")
	else:
		toast("Saving is not available right now.", &"warn")
		if Sfx != null:
			Sfx.play_ui(&"ui_error")


# ---- Radio ----------------------------------------------------------------------------------------------------------------------------
func _page_radio() -> void:
	page = &"radio"
	_app_header("Radio")
	var au = Game.sys(&"audio")
	if au == null or not au.has_method("get_stations"):
		_content.add_child(UIKit.label("Radio is not available.", 20, UITheme.C_DIM))
		return
	var cur: StringName = au.get_station() if au.has_method("get_station") else &""
	_content.add_child(UIKit.label("Plays while you drive.", 16, UITheme.C_DIM))
	for st in au.get_stations():
		var sid: StringName = st
		var nm: String = au.get_station_name(sid) if au.has_method("get_station_name") else String(sid)
		if String(sid).to_lower() == "off" or nm.to_lower() == "radio off":
			continue                      # the explicit "Radio off" row below covers it
		var b := UIKit.list_row(nm, "", "ON AIR" if sid == cur else "", func():
			au.set_station(sid)
			_page_radio())
		if sid == cur:
			b.toggle_mode = true
			b.button_pressed = true
		_content.add_child(b)
	if au.has_method("radio_off"):
		_content.add_child(UIKit.list_row("Radio off", "", "", func():
			au.radio_off()
			_page_radio()))


# ---- Settings ---------------------------------------------------------------------------------------------------------------------------
func _page_settings() -> void:
	page = &"settings"
	_app_header("Settings")
	for pair in [["Master volume", "master_volume"], ["Music", "music_volume"], ["Effects", "sfx_volume"]]:
		var key: String = pair[1]
		_content.add_child(UIKit.label(String(pair[0]), 18, UITheme.C_DIM))
		var row := UIKit.slider_row("", 0.0, 1.0, float(Game.settings.get(key, 1.0)), 0.05, func(v: float):
			Game.settings[key] = v
			Events.settings_changed.emit(), func(v: float): return "%d %%" % int(v * 100.0))
		# shrink the unused label column + the min widths of the shared slider row so it fits the phone screen
		(row.get_child(0) as Control).custom_minimum_size = Vector2(0, 0)
		(row.get_child(1) as Control).custom_minimum_size = Vector2(110, 30)
		(row.get_child(2) as Control).custom_minimum_size = Vector2(64, 0)
		row.add_theme_constant_override("separation", 8)
		_content.add_child(row)
	_content.add_child(UIKit.toggle_row("Camera shake", bool(Game.settings.get("camera_shake", true)), func(on: bool):
		Game.settings["camera_shake"] = on
		Events.settings_changed.emit()))
	_content.add_child(UIKit.toggle_row("FPS counter", bool(Game.cheats.get("show_fps", false)), func(on: bool): Game.cheats["show_fps"] = on))


# ---- Stats -------------------------------------------------------------------------------------------------------------------------------------
func _page_stats() -> void:
	page = &"stats"
	_app_header("Stats")
	var st: Dictionary = Game.ui.stats if Game.ui != null else {}
	var secs := int(float(st.get("time_played", 0.0)))
	var rows := [
		["Time played", "%d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]],
		["Cash", Util.format_money(Game.cash)],
		["Driven", "%.1f km" % (float(st.get("dist_driven", 0.0)) / 1000.0)],
		["On foot", "%.1f km" % (float(st.get("dist_foot", 0.0)) / 1000.0)],
		["Kills", str(int(st.get("kills", 0)))],
		["Money earned", Util.format_money(int(st.get("money_earned", 0)))],
		["Money spent", Util.format_money(int(st.get("money_spent", 0)))],
		["Wanted peak", "%d stars" % int(st.get("wanted_peak", 0))],
		["Vehicles used", str(int(st.get("vehicles", 0)))],
	]
	var gs = Game.sys(&"garage")
	if gs != null:
		rows.append(["Garage", "%d / %d slots" % [GarageSystem.MAX_SLOTS - gs.free_slot_count(), GarageSystem.MAX_SLOTS]])
	for r in rows:
		_content.add_child(UIKit.stat_row(String(r[0]), String(r[1])))
