class_name DebugMenuUI
extends MenuBase
## The tabbed benchmark / admin menu (F1 / `). Registered as UIRoot menu &"debug". The game keeps running behind it
## (pauses_game = false) unless "Pause while open" is switched on. Every button calls a DebugCmds function.

const TAB_NAMES: Array = ["Teleport", "Vehicles", "Weapons", "Player", "World", "Overlays", "System"]

var tab := 0
var close_after := true                  # close the menu after teleport / spawn-and-enter so the result is visible
var enter_after_spawn := true
var paint_index := 0
var owner_menu: Node = null              # DebugMenu

var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _page: VBoxContainer
var _vehicle_rows: Array = []            # [Button, search text, group index]
var _vehicle_groups: Array = []          # [header, grid]
var _check_box: VBoxContainer = null
var _search_text := ""


func _init() -> void:
	super._init()
	pauses_game = false
	dim_background = false
	var b := build_frame("Benchmark menu", "admin / QA tool - not a mission system", 1560, 900)
	_tabs = UIKit.tab_bar(TAB_NAMES, _on_tab)
	b.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 640)
	b.add_child(_scroll)
	_page = UIKit.vbox(10)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page)
	set_hints([["F1", "Close"], ["PgUp/PgDn", "Switch tab"], ["Tab", "Move focus"], ["Enter", "Press"], ["Alt+keys", "Hotkeys (System tab)"]])


func _on_open(d: Dictionary) -> void:
	if d.has("tab"):
		tab = clampi(int(d["tab"]), 0, TAB_NAMES.size() - 1)
	UIKit.tab_select(_tabs, tab)
	_build_page()


func show_tab(i: int) -> void:
	tab = clampi(i, 0, TAB_NAMES.size() - 1)
	UIKit.tab_select(_tabs, tab)
	_build_page()


func _on_tab(i: int) -> void:
	tab = i
	_build_page()


func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_PAGEDOWN or k == KEY_PAGEUP:
		show_tab((tab + (1 if k == KEY_PAGEDOWN else -1) + TAB_NAMES.size()) % TAB_NAMES.size())
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var sv := _scroll.scroll_vertical
	_build_page()
	_scroll.set_deferred("scroll_vertical", sv)


# ---- helpers ---------------------------------------------------------------------------------------------------------
func _clear_page() -> void:
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	_vehicle_rows.clear()
	_vehicle_groups.clear()
	_check_box = null


func _section(t: String) -> void:
	_page.add_child(UIKit.margin(UIKit.caption(t), 0, 12, 0, 0))


func _note(t: String, col: Color = UITheme.C_DIM) -> void:
	var l := UIKit.label(t, 17, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_child(l)


func _grid(cols: int = 4) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_child(g)
	return g


func _b(parent: Control, text: String, cb: Callable, variation: StringName = &"", reason: String = "") -> Button:
	var btn := UIKit.button(text, cb, variation)
	btn.custom_minimum_size = Vector2(0, 54)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	if reason != "":
		btn.disabled = true
		btn.tooltip_text = reason
		btn.text = text + "  (n/a)"
	parent.add_child(btn)
	return btn


func _do(res: Dictionary) -> void:
	var good: bool = res.get("ok", false)
	Events.notification.emit(String(res.get("msg", "")), &"good" if good else &"warn")
	if good and bool(res.get("close", false)) and close_after and Game.ui != null:
		if res.get("defer", "") == "photo":
			Game.ui.close_menu()
			var g = Game.sys(&"garage")
			if g != null:
				g.call_deferred("start_photo_mode")
		elif Game.ui.current_menu_id == &"debug":
			Game.ui.close_menu()
	elif good and res.get("defer", "") == "photo":
		var g2 = Game.sys(&"garage")
		if g2 != null:
			g2.call_deferred("start_photo_mode")


func _dor(res: Dictionary) -> void:
	_do(res)
	refresh()


func _dump() -> void:
	DebugCmds.state_dump()
	_do(DebugCmds.ok("State dump printed to the log"))


func _toggle(parent: Control, text: String, value: bool, cb: Callable) -> void:
	var row := UIKit.toggle_row(text, value, func(on: bool):
		cb.call(on)
		if owner_menu != null:
			owner_menu.refresh_state())
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, step: float, cb: Callable, fmt: Callable = Callable()) -> void:
	var row := UIKit.slider_row(text, lo, hi, value, step, cb, fmt)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)


func _cheat(key: String, default: bool = false) -> bool:
	return bool(Game.cheats.get(key, default))


func _build_page() -> void:
	_clear_page()
	match tab:
		0: _page_teleport()
		1: _page_vehicles()
		2: _page_weapons()
		3: _page_player()
		4: _page_world()
		5: _page_overlays()
		6: _page_system()
	focus_first()


# ===================================================================================================================
# TELEPORT
# ===================================================================================================================
func _page_teleport() -> void:
	var top := _grid(3)
	_toggle(top, "Close menu after teleport / spawn", close_after, func(on: bool): close_after = on)
	var has_wp: bool = Game.ui != null and bool(Game.ui.get("has_waypoint"))
	_b(top, "Teleport to map waypoint", func(): _do(DebugCmds.teleport_to_waypoint()), &"AccentButton", "" if has_wp else "Set a waypoint on the map (M) first")
	_note("Teleports snap to the ground (physics ray). When you are driving, the vehicle comes along.")
	for g in DebugCatalog.location_groups():
		_section(g[0])
		var grid := _grid(4)
		for e in g[1]:
			var id: StringName = e["id"]
			_b(grid, String(e["name"]), func(): _do(DebugCmds.teleport_to_location(id)))


# ===================================================================================================================
# VEHICLES
# ===================================================================================================================
func _page_vehicles() -> void:
	var top := _grid(2)
	var search := LineEdit.new()
	search.placeholder_text = "Search vehicles (name / id / class)..."
	search.text = _search_text
	search.custom_minimum_size = Vector2(0, 54)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	search.text_changed.connect(_on_search)
	top.add_child(search)
	var names: Array = []
	for pnt in DebugCatalog.PAINTS:
		names.append(pnt[0])
	var prow := UIKit.option_row("Paint colour", names, paint_index, func(i: int): paint_index = i)
	prow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(prow)
	_toggle(top, "Get in after spawning", enter_after_spawn, func(on: bool): enter_after_spawn = on)

	_section("Current vehicle")
	var act := _grid(4)
	_b(act, "Repair", func(): _do(DebugCmds.repair_current()), &"AccentButton")
	_b(act, "Flip upright", func(): _do(DebugCmds.flip_current()))
	_b(act, "Delete nearby (80 m)", func(): _do(DebugCmds.delete_nearby_vehicles(80.0)), &"DangerButton")
	_b(act, "Open customization garage", func(): _do(DebugCmds.open_customization()), &"AccentButton")
	var tog := _grid(2)
	_toggle(tog, "Vehicle god mode", _cheat("vehicle_god"), func(on: bool): _do(DebugCmds.set_vehicle_god(on)))
	_toggle(tog, "Unlock ALL vehicle mod options (free)", _cheat("unlock_all_mods"), func(on: bool): _do(DebugCmds.set_unlock_all_mods(on)))
	_slider(tog, "Engine / speed boost", 1.0, 4.0, float(Game.cheats.get("vehicle_boost", 1.0)), 0.25,
		func(v: float): DebugCmds.set_speed_boost(v), func(v: float): return "x%.2f" % v)

	var groups := DebugCatalog.vehicle_groups()
	for gi in groups.size():
		var g: Array = groups[gi]
		if g[1].is_empty():
			continue
		var header := UIKit.margin(UIKit.caption(String(g[0])), 0, 12, 0, 0)
		_page.add_child(header)
		var grid := _grid(4)
		_vehicle_groups.append([header, grid])
		for id in g[1]:
			var vid: StringName = id
			var def := VehicleDefs.get_def(vid)
			var btn := _b(grid, "%s" % def.get("name", vid), func(): _spawn(vid))
			btn.tooltip_text = "%s  (%s, %d seats, %d km/h)" % [vid, def.get("class", ""), int(def.get("seats", 1)), int(def.get("top_speed_kmh", 0))]
			_vehicle_rows.append([btn, ("%s %s %s %s" % [def.get("name", ""), vid, def.get("class", ""), g[0]]).to_lower(), _vehicle_groups.size() - 1])
	if _search_text != "":
		_on_search(_search_text)


func _spawn(id: StringName) -> void:
	var col: Color = DebugCatalog.PAINTS[paint_index][1]
	_do(DebugCmds.spawn_vehicle(id, {"paint": col, "enter": enter_after_spawn}))


func _on_search(text: String) -> void:
	_search_text = text
	var q := text.strip_edges().to_lower()
	var shown: Dictionary = {}
	for r in _vehicle_rows:
		var vis: bool = q == "" or String(r[1]).contains(q)
		(r[0] as Control).visible = vis
		if vis:
			shown[r[2]] = true
	for i in _vehicle_groups.size():
		var v: bool = shown.has(i)
		(_vehicle_groups[i][0] as Control).visible = v
		(_vehicle_groups[i][1] as Control).visible = v


# ===================================================================================================================
# WEAPONS
# ===================================================================================================================
func _page_weapons() -> void:
	var act := _grid(4)
	_b(act, "Give ALL weapons (full ammo)", func(): _dor(DebugCmds.give_all_weapons()), &"AccentButton")
	_b(act, "Remove all weapons", func(): _dor(DebugCmds.remove_all_weapons()), &"DangerButton")
	_b(act, "Refill ammo", func(): _do(DebugCmds.refill_ammo()))
	_b(act, "Give parachute", func(): _do(DebugCmds.give_parachute(true)))
	var tog := _grid(2)
	_toggle(tog, "Infinite ammo", _cheat("infinite_ammo"), func(on: bool): _do(DebugCmds.set_infinite_ammo(on)))
	var p = Game.player
	_toggle(tog, "Scuba gear (unlimited air)", _cheat("scuba"), func(on: bool): _do(DebugCmds.set_scuba(on)))
	_b(tog, "Refill lungs", func(): _do(DebugCmds.refill_lungs()))
	_b(tog, "Heal: health + armor + lungs", func(): _do(DebugCmds.heal_full()))
	if p != null:
		_slider(tog, "Health", 1, p.max_health, p.health, 1, func(v: float): DebugCmds.set_health(v), func(v: float): return "%d" % int(v))
		_slider(tog, "Armor", 0, p.max_armor, p.armor, 1, func(v: float): DebugCmds.set_armor(v), func(v: float): return "%d" % int(v))

	var wc = p.get("weapons") if p != null else null
	var cur: StringName = wc.current_id if wc != null else &""
	var compat: Array = WeaponMods.compatible_mods(cur) if cur != &"" else []
	_section("Attachments on the equipped weapon (%s)" % (DebugCatalog.weapon_name(cur) if cur != &"" else "none"))
	if compat.is_empty():
		_note("This weapon has no attachment slots - equip a firearm first.")
	else:
		var ag := _grid(3)
		for m in compat:
			var mid: StringName = m
			_toggle(ag, String(WeaponMods.get_mod(mid).get("name", mid)), wc.has_mod(cur, mid), func(on: bool): _do(DebugCmds.set_attachment(mid, on)))
	_section("Give weapon (full ammo)")
	var grid := _grid(4)
	for id in DebugCatalog.weapon_ids():
		var wid: StringName = id
		var owned: bool = wc != null and wc.has_weapon(wid)
		_b(grid, ("%s%s" % ["* " if owned else "", DebugCatalog.weapon_name(wid)]), func(): _dor(DebugCmds.give_weapon(wid)))


# ===================================================================================================================
# PLAYER
# ===================================================================================================================
func _page_player() -> void:
	_section("Money (now %s)" % Util.format_money(Game.cash))
	var mg := _grid(5)
	for mp in DebugCatalog.MONEY_PRESETS:
		var amount: int = mp[1]
		_b(mg, String(mp[0]), func(): _dor(DebugCmds.set_money(0) if amount == 0 else DebugCmds.add_money(amount)))
	var edit := LineEdit.new()
	edit.placeholder_text = "exact amount"
	edit.custom_minimum_size = Vector2(0, 54)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var apply := func(t: String):
		if t.strip_edges().is_valid_int():
			_do(DebugCmds.set_money(int(t.strip_edges())))
			refresh()
		else:
			_do(DebugCmds.fail("Type a whole number"))
	edit.text_submitted.connect(apply)
	mg.add_child(edit)
	_b(mg, "Set exact", func(): apply.call(edit.text), &"AccentButton")

	_section("Health, status")
	var hg := _grid(2)
	var p = Game.player
	if p != null:
		_slider(hg, "Health", 1, p.max_health, p.health, 1, func(v: float): DebugCmds.set_health(v), func(v: float): return "%d" % int(v))
		_slider(hg, "Armor", 0, p.max_armor, p.armor, 1, func(v: float): DebugCmds.set_armor(v), func(v: float): return "%d" % int(v))
	_toggle(hg, "Invulnerable", _cheat("invulnerable"), func(on: bool): _do(DebugCmds.set_invulnerable(on)))
	_toggle(hg, "Never wanted", _cheat("never_wanted"), func(on: bool): _do(DebugCmds.set_never_wanted(on)))

	_section("Wanted level")
	var wg := _grid(7)
	for n in range(0, 6):
		var lvl: int = n
		_b(wg, ("%d star%s" % [lvl, "" if lvl == 1 else "s"]) if lvl > 0 else "0 (clear)", func(): _do(DebugCmds.set_wanted(lvl)), &"DangerButton" if lvl >= 4 else &"")
	_b(wg, "Clear wanted", func(): _do(DebugCmds.clear_wanted()), &"AccentButton")

	_section("Skills")
	var sg := _grid(4)
	_b(sg, "Max all skills", func(): _dor(DebugCmds.skills_max()), &"AccentButton")
	_b(sg, "Reset all skills", func(): _dor(DebugCmds.skills_reset()))
	var sk = Game.sys(&"skills")
	if sk != null:
		var sl := _grid(2)
		for id in SkillsSystem.IDS:
			var sid: StringName = id
			_slider(sl, String(DebugCatalog.SKILL_LABELS.get(String(sid), sid)), 0, 100, float(sk.get_all().get(sid, 0.0)), 1, func(v: float): DebugCmds.set_skill(sid, v), func(v: float): return "%d" % int(v))

	_section("Time of day")
	var tg := _grid(2)
	_slider(tg, "Hour", 0, 24, Game.time_of_day, 0.25, func(v: float): DebugCmds.set_time(v), func(v: float): return Util.format_clock(v))
	_slider(tg, "Clock speed (60 = normal)", 0, 600, Game.time_scale, 10, func(v: float): DebugCmds.set_clock_speed(v), func(v: float): return "x%d" % int(v))
	var tp := _grid(5)
	for t in DebugCatalog.TIME_PRESETS:
		var hour: float = t[1]
		_b(tp, String(t[0]), func(): _dor(DebugCmds.set_time(hour)))
	_toggle(tp, "Freeze time", Game.time_frozen, func(on: bool): _do(DebugCmds.set_time_frozen(on)))

	_section("Weather")
	var wxg := _grid(5)
	for w in GC.WEATHERS:
		var wname: StringName = w
		_b(wxg, String(DebugCatalog.WEATHER_LABELS.get(String(wname), wname)), func(): _do(DebugCmds.set_weather(wname)))


# ===================================================================================================================
# WORLD / SPAWN
# ===================================================================================================================
func _page_world() -> void:
	var at_cross: bool = bool(owner_menu.get("spawn_at_crosshair")) if owner_menu != null else false
	var top := _grid(2)
	_toggle(top, "Spawn at crosshair (off = 16 m ahead of you)", at_cross, func(on: bool): owner_menu.set("spawn_at_crosshair", on))
	_section("Police")
	var pg := _grid(4)
	for e in [["Patrol car", &"car"], ["Officer", &"officer"], ["SWAT officer", &"swat"], ["Sniper", &"sniper"], ["Tactical van", &"van"], ["Police helicopter", &"heli"], ["Roadblock", &"roadblock"]]:
		var kind: StringName = e[1]
		_b(pg, String(e[0]), func(): _do(DebugCmds.spawn_police(kind, bool(owner_menu.get("spawn_at_crosshair")))))
	_section("Gangs, people, services")
	var sg := _grid(4)
	_b(sg, "Gang group (3)", func(): _do(DebugCmds.spawn_gang(bool(owner_menu.get("spawn_at_crosshair")))), &"DangerButton")
	_b(sg, "Wake all gang turfs", func(): _do(DebugCmds.activate_gang_turfs()))
	_b(sg, "Pedestrians x10", func(): _do(DebugCmds.spawn_pedestrians(10)))
	_b(sg, "Call taxi", func(): _do(DebugCmds.call_taxi()), &"AccentButton", "" if DebugCmds.taxi_available() else "Transit system has no call_taxi() yet")
	_b(sg, "Ambulance", func(): _do(DebugCmds.spawn_service(&"ambulance")))
	_b(sg, "Fire truck", func(): _do(DebugCmds.spawn_service(&"firetruck")))
	_b(sg, "Explosion at crosshair", func(): _do(DebugCmds.explode_at_crosshair()), &"DangerButton")
	_b(sg, "Slow motion (toggle)", func(): _do(DebugCmds.set_slowmo(not _cheat("slowmo"))))
	_section("Population")
	var tg := _grid(2)
	_toggle(tg, "Traffic", _cheat("traffic", true), func(on: bool): _do(DebugCmds.set_traffic(on)))
	_toggle(tg, "Pedestrians", _cheat("pedestrians", true), func(on: bool): _do(DebugCmds.set_pedestrians(on)))
	_toggle(tg, "Wildlife", _cheat("wildlife", true), func(on: bool): _do(DebugCmds.set_wildlife(on)))
	_toggle(tg, "Never wanted", _cheat("never_wanted"), func(on: bool): _do(DebugCmds.set_never_wanted(on)))
	_slider(tg, "Traffic density", 0.0, 1.5, float(Game.settings.get("traffic_density", 1.0)), 0.1, func(v: float): DebugCmds.set_density("traffic_density", v), func(v: float): return "x%.1f" % v)
	_slider(tg, "Pedestrian density", 0.0, 1.5, float(Game.settings.get("ped_density", 1.0)), 0.1, func(v: float): DebugCmds.set_density("ped_density", v), func(v: float): return "x%.1f" % v)
	_section("Careful")
	var kg := _grid(4)
	_b(kg, "Knock out NPCs within 40 m", func(): confirm("Knock out nearby NPCs?", "Every pedestrian, officer and gang member within 40 m is knocked out.", func(): _do(DebugCmds.kill_nearby_npcs(40.0))), &"DangerButton")


# ===================================================================================================================
# OVERLAYS / INFO
# ===================================================================================================================
func _page_overlays() -> void:
	var tg := _grid(2)
	_toggle(tg, "FPS counter (HUD, same as F2)", _cheat("show_fps"), func(on: bool): _do(DebugCmds.set_cheat("show_fps", on)))
	_toggle(tg, "Coordinates / district / heading (HUD)", _cheat("show_coords"), func(on: bool): _do(DebugCmds.set_cheat("show_coords", on)))
	_toggle(tg, "Benchmark stats panel (draw calls, nodes, bodies, sector, speed)", _cheat("dbg_stats"), func(on: bool): _do(DebugCmds.set_cheat("dbg_stats", on)))
	_toggle(tg, "Wanted debug (last known position, search circle, police cones)", _cheat("dbg_wanted"), func(on: bool): _do(DebugCmds.set_cheat("dbg_wanted", on)))
	_toggle(tg, "Lane graph lines (70 m around you)", _cheat("dbg_lanes"), func(on: bool): _do(DebugCmds.set_cheat("dbg_lanes", on)))
	_toggle(tg, "Pedestrian graph lines (70 m around you)", _cheat("dbg_peds"), func(on: bool): _do(DebugCmds.set_cheat("dbg_peds", on)))
	var hud_on: bool = not (Game.ui != null and bool(Game.ui.get("hud_hidden")))
	_toggle(tg, "HUD visible", hud_on, func(on: bool): _do(DebugCmds.set_hud_visible(on)))
	var names: Array = []
	for m in DebugCatalog.RENDER_MODES:
		names.append(m[0])
	var cur := 0
	for i in DebugCatalog.RENDER_MODES.size():
		if get_tree().root.debug_draw == DebugCatalog.RENDER_MODES[i][1]:
			cur = i
	var ro := UIKit.option_row("Viewport render mode", names, cur, func(i: int): _do(DebugCmds.set_render_mode(i)))
	ro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tg.add_child(ro)
	_note("Wireframe is not offered: Godot only builds wireframe data for meshes uploaded after it is switched on, so the already-built city would stay solid.")
	_section("Live numbers")
	var live := UIKit.label(DebugCmds.stats_text(), 20, UITheme.C_TEXT)
	_page.add_child(live)


# ===================================================================================================================
# SYSTEM
# ===================================================================================================================
func _page_system() -> void:
	_section("Save slots (slot 0 = F5 quick save)")
	var sg := _grid(4)
	for s in [0] + DebugCatalog.SAVE_SLOTS:
		var slot: int = s
		var info: Dictionary = SaveSystem.get_slot_info(slot) if SaveSystem != null else {}
		var sub := String(info.get("saved_text", "empty")) if info.get("exists", false) else "empty"
		_b(sg, "Save %d  (%s)" % [slot, sub], func(): _dor(DebugCmds.save_slot(slot)))
	for s in [0] + DebugCatalog.SAVE_SLOTS:
		var slot2: int = s
		_b(sg, "Load %d" % slot2, func(): _do(DebugCmds.load_slot(slot2)), &"AccentButton", "" if SaveSystem != null and SaveSystem.has_save(slot2) else "Slot is empty")
	_section("Player & world")
	var ag := _grid(4)
	_b(ag, "Photo mode", func(): _do(DebugCmds.open_photo_mode()), &"AccentButton")
	_b(ag, "Reset to spawn plaza", func(): _do(DebugCmds.reset_to_spawn()))
	_b(ag, "Respawn at hospital", func(): _do(DebugCmds.respawn_hospital()))
	_b(ag, "Regenerate traffic", func(): _do(DebugCmds.regenerate_traffic()))
	_b(ag, "Clear all dynamic entities", func(): _do(DebugCmds.clear_all_dynamic()), &"DangerButton")
	_b(ag, "Print state dump to log", func(): _dump())
	_b(ag, "Run self checks", func(): _run_checks(), &"AccentButton")
	var tog := _grid(2)
	_toggle(tog, "Pause the game while this menu is open", pauses_game, func(on: bool):
		pauses_game = on
		if Game.ui != null and Game.ui.current_menu_id == &"debug":
			Game.set_paused(on)
			Game.ui.set("_menu_paused", on))
	_check_box = UIKit.vbox(4)
	_page.add_child(_check_box)
	_section("Version / build")
	for row in DebugCmds.version_info():
		_page.add_child(UIKit.stat_row(String(row[0]), String(row[1])))
	_section("Hotkeys (work with the menu closed; Alt is only the slow-walk key)")
	for h in DebugCatalog.HOTKEYS:
		_page.add_child(UIKit.stat_row(String(h[0]), String(h[1]), UITheme.C_ACCENT))


func _run_checks() -> void:
	if _check_box == null:
		return
	for c in _check_box.get_children():
		_check_box.remove_child(c)
		c.queue_free()
	var results := DebugCmds.run_self_checks()
	var passed := 0
	for r in results:
		if r[1]:
			passed += 1
		var row := UIKit.stat_row(("PASS  " if r[1] else "FAIL  ") + String(r[0]), String(r[2]), UITheme.C_OK if r[1] else UITheme.C_DANGER)
		_check_box.add_child(row)
	_check_box.move_child(_check_box.get_child(0), 0)
	var head := UIKit.label("Self checks: %d / %d passed" % [passed, results.size()], 22, UITheme.C_OK if passed == results.size() else UITheme.C_WARN, true)
	_check_box.add_child(head)
	_check_box.move_child(head, 0)
	_do(DebugCmds.ok("Self checks: %d / %d passed" % [passed, results.size()]) if passed == results.size() else DebugCmds.fail("Self checks: %d / %d passed" % [passed, results.size()]))
