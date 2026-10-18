extends Node
## Headless UI tests:  powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/ui_test.gd -Seconds 40
## Prints "TEST <name> PASS|FAIL <detail>" lines. Uses UiFakes (fake player / vehicle / world) so it works with stub modules.

var _fails := 0


func _t(name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _key(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func run(main: Node) -> String:
	var ui = Game.ui
	_t("ui_boot", ui != null and ui is UIRoot, "Game.ui=%s" % ui)
	if ui == null:
		return "no ui"
	ui.capture_when_idle = false
	_t("ui_parts", ui.hud != null and ui.wheel != null and ui.map_screen != null and ui.pause_menu != null and ui.status_screen != null and ui.death != null,
		"hud/wheel/map/pause/status/death")
	_t("ui_builtin_menus", ui.has_menu(&"pause") and ui.has_menu(&"map") and ui.has_menu(&"status") and ui.has_menu(&"ui_showcase"), "registered")
	_t("theme", ui.root.theme != null and ui.root.theme.has_stylebox("panel", "PanelContainer") and ui.root.theme.has_stylebox("normal", "Button"), "theme styleboxes")

	# ---- icons ----
	var bad: Array[String] = []
	for id in UIIcons.WEAPON_OPS:
		if UIIcons._ops(UIIcons.WEAPON_OPS, id, false).is_empty():
			bad.append(String(id))
	for id in UIIcons.LOC:
		var g: StringName = UIIcons.LOC[id][0]
		if not UIIcons.GLYPH_OPS.has(g):
			bad.append("glyph:" + String(g))
	_t("icons_complete", bad.is_empty(), str(bad))
	var polys_ok := true
	for table in [UIIcons.WEAPON_OPS, UIIcons.GLYPH_OPS]:
		for id in table:
			for op in UIIcons._ops(table, id, table == UIIcons.GLYPH_OPS):
				if op["t"] == "p" and Geometry2D.triangulate_polygon(op["pts"]).size() < 3:
					polys_ok = false
					print("  bad polygon in ", id)
	_t("icon_polygons_valid", polys_ok, "all icon polygons triangulate")

	# ---- kit ----
	var made := [UIKit.button("x"), UIKit.slider_row("a", 0, 1, 0.5, 0.1, Callable()), UIKit.toggle_row("a", true, Callable()),
		UIKit.option_row("a", ["x", "y"], 0, Callable()), UIKit.list_row("t", "s", 100), UIKit.card("c", "s", 5), UIKit.price_tag(10), UIKit.keycap("E"),
		UIKit.tab_bar(["a", "b"], Callable()), UIKit.stat_row("a", "b"), UIKit.bar(0.5), UIKit.header("h", "s"), UIKit.card_grid(3), UIKit.scroll_list()]
	var kit_ok := true
	for m in made:
		if m == null:
			kit_ok = false
	_t("kit_widgets", kit_ok, "%d widgets" % made.size())
	for m in made:
		if m is Node and (m as Node).get_parent() == null:
			(m as Node).free()

	# ---- menu host ----
	var test_menu := MenuBase.new()
	test_menu.build_frame("Test menu", "host test")
	ui.register_menu(&"test_menu", test_menu)
	var opened: Array = []
	var closed: Array = []
	Events.menu_opened.connect(func(id): opened.append(id))
	Events.menu_closed.connect(func(id): closed.append(id))
	_t("menu_initial", not ui.is_menu_open() and not get_tree().paused, "no menu, tree running")
	var ok: bool = ui.open_menu(&"test_menu", {"x": 1})
	await _frames(2)
	_t("menu_open", ok and ui.is_menu_open() and test_menu.visible and test_menu.data.get("x") == 1, "opened")
	_t("menu_pauses_tree", get_tree().paused and Game.paused, "tree paused while a pausing menu is open")
	_t("menu_cursor", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE or DisplayServer.get_name() == "headless", "mouse visible")
	_t("menu_event_opened", opened.has(&"test_menu"), str(opened))
	ui.close_menu()
	await _frames(2)
	_t("menu_close", not ui.is_menu_open() and not test_menu.visible and not get_tree().paused, "closed + unpaused")
	_t("menu_event_closed", closed.has(&"test_menu"), str(closed))
	test_menu.pauses_game = false
	ui.open_menu(&"test_menu")
	_t("menu_nonpausing", not get_tree().paused, "non-pausing menu leaves the tree running")
	test_menu.close()
	await _frames(1)
	_t("menu_close_direct", not ui.is_menu_open(), "menu.close() directly updates the host")
	_t("menu_unknown", not ui.open_menu(&"does_not_exist"), "unknown id returns false")

	# ---- pause key ----
	ui.death.state = DeathScreen.State.IDLE
	_key(&"pause", true)
	_key(&"pause", false)
	await _frames(3)
	_t("pause_key_opens", ui.current_menu_id == &"pause" and get_tree().paused, "Esc opens pause (id=%s)" % ui.current_menu_id)
	_key(&"pause", true)
	_key(&"pause", false)
	await _frames(3)
	_t("pause_key_closes", not ui.is_menu_open() and not get_tree().paused, "Esc closes pause")
	# map key
	_key(&"map", true)
	_key(&"map", false)
	await _frames(3)
	_t("map_key_opens", ui.current_menu_id == &"map", "M opens the map")
	_key(&"map", true)
	_key(&"map", false)
	await _frames(3)
	_t("map_key_closes", not ui.is_menu_open(), "M closes the map")

	# ---- HUD data ----
	var holder := Node3D.new()
	main.add_child(holder)
	var pl := UiFakes.make_player(holder, Vector3(0, 0, 20))
	await _frames(3)
	pl.health = 40.0
	pl.armor = 25.0
	await _frames(4)
	_t("hud_health", absf(ui.hud.bars.health - 0.4) < 0.01 and ui.hud.bars.health_val == 40, "health=%.2f" % ui.hud.bars.health)
	_t("hud_armor", absf(ui.hud.bars.armor - 0.25) < 0.01, "armor=%.2f" % ui.hud.bars.armor)
	var cash0: int = Game.cash
	Game.cash = cash0 + 250
	await _frames(2)
	_t("hud_cash_target", ui.hud.cash.target == cash0 + 250 and ui.hud.cash.floaters.size() > 0, "target=%d floaters=%d" % [ui.hud.cash.target, ui.hud.cash.floaters.size()])
	var shown0: float = ui.hud.cash.shown
	await _frames(20)
	_t("hud_cash_animates", ui.hud.cash.shown > shown0 or absf(ui.hud.cash.shown - float(Game.cash)) < 1.0, "shown %.0f -> %.0f" % [shown0, ui.hud.cash.shown])
	Game.wanted_level = 3
	Game.wanted_state = &"search"
	Events.wanted_changed.emit(3, &"search")
	Events.wanted_search_progress.emit(0.6)
	await _frames(3)
	_t("hud_wanted", ui.hud.wanted.level == 3 and ui.hud.wanted.state == &"search" and absf(ui.hud.wanted.progress - 0.6) < 0.01, "level=%d state=%s" % [ui.hud.wanted.level, ui.hud.wanted.state])
	_t("stats_wanted_peak", int(ui.stats["wanted_peak"]) >= 3, "peak=%d" % int(ui.stats["wanted_peak"]))
	Game.wanted_level = 0
	Game.wanted_state = &"clear"
	Events.interaction_prompt.emit("[F] Enter vehicle")
	await _frames(3)
	_t("hud_prompt", ui.hud.prompt.text == "Enter vehicle" and ui.hud.prompt.key == "F", "text='%s' key=%s" % [ui.hud.prompt.text, ui.hud.prompt.key])
	Events.interaction_prompt.emit("")
	await _frames(40)
	_t("hud_prompt_hides", ui.hud.prompt.shown < 0.05, "shown=%.2f" % ui.hud.prompt.shown)
	Events.notification.emit("Test toast A", &"good")
	Events.notification.emit("Test toast B", &"bad")
	await _frames(2)
	_t("toast_queue", ui.hud.notifications._toasts.size() == 2, "%d toasts" % ui.hud.notifications._toasts.size())
	ui.toast("Test toast A", &"good")
	await _frames(1)
	_t("toast_dedupe", ui.hud.notifications._toasts.size() == 2 and int(ui.hud.notifications._toasts[0]["count"]) == 2, "duplicate merged")
	for i in 8:
		Events.notification.emit("Overflow %d" % i, &"info")
	await _frames(1)
	_t("toast_cap", ui.hud.notifications._toasts.size() <= Notifications.MAX_VISIBLE and ui.hud.notifications._pending.size() > 0, "visible=%d pending=%d" % [ui.hud.notifications._toasts.size(), ui.hud.notifications._pending.size()])
	Events.subtitle.emit("Hello world", 2.0)
	await _frames(1)
	_t("subtitle", ui.hud.notifications._subs.size() == 1, "subtitle queued")
	Events.district_changed.emit(GC.D_BEACH)
	await _frames(2)
	_t("hud_district", ui.hud.district.text != "" and ui.hud.district.t < 1.0, "banner '%s'" % ui.hud.district.text)
	Events.hit_marker.emit(true)
	await _frames(1)
	_t("hud_hit_marker", ui.hud.crosshair.hit > 0.5 and ui.hud.crosshair.kill > 0.5, "hit+kill flash")
	_t("hud_weapon", ui.hud.weapon.weapon_id == &"pistol" and ui.hud.weapon.mag == 12 and ui.hud.weapon.reserve == 84 and ui.hud.weapon.shows_ammo, "pistol 12/84")
	pl.weapons.is_aiming = true
	await _frames(3)
	_t("hud_crosshair_modes", ui.hud.crosshair.mode == 2, "aiming => full reticle (mode=%d)" % ui.hud.crosshair.mode)
	pl.weapons.scope_active = true
	await _frames(3)
	_t("hud_scope", ui.hud.scope.visible and ui.hud.crosshair.mode == 0, "scope overlay visible")
	pl.weapons.scope_active = false
	pl.weapons.is_aiming = false
	pl.weapons.current_id = &"knife"
	await _frames(3)
	_t("hud_melee_no_ammo", not ui.hud.weapon.shows_ammo and ui.hud.crosshair.mode == 0, "knife: no ammo, no crosshair")
	pl.weapons.current_id = &"pistol"

	# ---- vehicle HUD ----
	var v := UiFakes.FakeVehicle.new()
	holder.add_child(v)
	v.global_position = Vector3(0, 0, 20)
	pl.current_vehicle = v
	v.kmh = 100.0
	await _frames(30)
	_t("vehicle_hud_ground", ui.hud.vehicle_hud.mode == VehicleHud.Mode.GROUND and absf(ui.hud.vehicle_hud.speed_kmh - 100.0) < 3.0, "speed=%.1f" % ui.hud.vehicle_hud.speed_kmh)
	v.vclass = GC.VC_HELI
	await _frames(3)
	_t("vehicle_hud_air", ui.hud.vehicle_hud.mode == VehicleHud.Mode.AIR, "heli => air instruments")
	v.vclass = GC.VC_BOAT
	await _frames(3)
	_t("vehicle_hud_boat", ui.hud.vehicle_hud.mode == VehicleHud.Mode.BOAT, "boat")
	pl.current_vehicle = null
	await _frames(40)
	_t("vehicle_hud_hides", ui.hud.vehicle_hud.mode == VehicleHud.Mode.HIDDEN and not ui.hud.vehicle_hud.visible, "hidden on foot")

	# ---- stats ----
	var kills0: int = int(ui.stats["kills"])
	Events.character_died.emit(pl, null, {})
	_t("stats_ignore_self_death", int(ui.stats["kills"]) == kills0, "player death is not a kill")
	var victim := Node3D.new()
	holder.add_child(victim)
	Events.character_died.emit(victim, pl, {})
	_t("stats_kills", int(ui.stats["kills"]) == kills0 + 1, "kills=%d" % int(ui.stats["kills"]))
	var earned0: int = int(ui.stats["money_earned"])
	Game.cash += 100
	_t("stats_money", int(ui.stats["money_earned"]) == earned0 + 100, "earned")

	# ---- weapon wheel ----
	var ts0 := Engine.time_scale
	_t("wheel_opens", ui.wheel.open_wheel() and ui.wheel.is_open, "wheel opened from the player inventory")
	_t("wheel_slowmo", absf(Engine.time_scale - WeaponWheel.SLOWMO) < 0.001, "time_scale=%.2f" % Engine.time_scale)
	_t("wheel_menu_flag", ui.is_menu_open() and ui.is_input_blocked(), "wheel counts as a UI block")
	var cats: Array = ui.wheel._cats
	_t("wheel_categories", cats.size() >= 6, "%d categories" % cats.size())
	var only_owned := true
	for c in cats:
		for w in c["weapons"]:
			if not pl.weapons.inventory.has(w) and w != &"fists":
				only_owned = false
	_t("wheel_only_owned", only_owned, "only owned weapons")
	# direction picking: top = first category, right = third, bottom = fifth
	ui.wheel._update_from_vector(Vector2(0, -120), true)
	var top_cat: StringName = ui.wheel._cats[ui.wheel._sel_cat]["key"]
	ui.wheel._update_from_vector(Vector2(120, 0), true)
	var right_cat: StringName = ui.wheel._cats[ui.wheel._sel_cat]["key"]
	ui.wheel._update_from_vector(Vector2(0, 120), true)
	var bottom_cat: StringName = ui.wheel._cats[ui.wheel._sel_cat]["key"]
	_t("wheel_direction_pick", top_cat == &"melee" and right_cat == &"smg" and bottom_cat == &"rifle", "top=%s right=%s bottom=%s" % [top_cat, right_cat, bottom_cat])
	ui.wheel._update_from_vector(Vector2(10, -10), true)       # inside the dead zone: selection unchanged
	_t("wheel_deadzone", ui.wheel._cats[ui.wheel._sel_cat]["key"] == &"rifle", "dead zone keeps the selection")
	ui.wheel._update_from_vector(Vector2(0, 300), true)        # outer ring below = rifles, pick by angle within the sector
	_t("wheel_outer_ring", ui.wheel._cats[ui.wheel._sel_cat]["key"] == &"rifle" and ui.wheel.selected != &"", "outer ring picks '%s'" % ui.wheel.selected)
	ui.wheel._set_selection(2, 0)
	var picked: StringName = ui.wheel.selected
	ui.wheel.close_wheel(true)
	_t("wheel_equips", pl.weapons.current_id == picked and picked != &"", "equipped '%s'" % picked)
	_t("wheel_restores_time", absf(Engine.time_scale - ts0) < 0.001 and not ui.wheel.is_open, "time_scale restored")
	ui.wheel.open_wheel()
	var keep: StringName = pl.weapons.current_id
	ui.wheel._set_selection(0, 0)
	ui.wheel.close_wheel(false)
	_t("wheel_cancel", pl.weapons.current_id == keep, "cancel keeps '%s'" % keep)
	# wheel via the action key
	_key(&"weapon_wheel", true)
	await _frames(2)
	_t("wheel_key_press", ui.wheel.is_open, "Tab opens")
	_key(&"weapon_wheel", false)
	await _frames(2)
	_t("wheel_key_release", not ui.wheel.is_open and absf(Engine.time_scale - 1.0) < 0.001, "Tab release closes")

	# ---- fade ----
	ui.fade(true, 0.15)
	await get_tree().create_timer(0.35, true, false, true).timeout
	_t("fade_to_black", ui.is_faded_out(), "alpha=%.2f" % ui._fade.color.a)
	ui.fade(false, 0.15)
	await get_tree().create_timer(0.35, true, false, true).timeout
	_t("fade_in", ui._fade.color.a < 0.02, "alpha=%.2f" % ui._fade.color.a)

	# ---- waypoint / route ----
	UiFakes.fill_world()
	ui.set_waypoint(Vector3(120, 0, 80))
	_t("waypoint_set", ui.has_waypoint and Game.has_meta(&"waypoint") and ui.route != null and ui.route.points.size() >= 2, "route points=%d approx=%s" % [ui.route.points.size() if ui.route else 0, ui.route.approx if ui.route else "-"])
	_t("waypoint_get", ui.get_waypoint() == Vector3(120, 0, 80), "get_waypoint")
	ui.clear_waypoint()
	_t("waypoint_clear", not ui.has_waypoint and ui.get_waypoint() == null and not Game.has_meta(&"waypoint"), "cleared")
	var g := LaneGraph.new()
	for i in 6:
		g.add_point(Vector3(i * 20.0, 0, 0), Vector3.RIGHT, 14.0)
	for i in 5:
		g.link(i, i + 1)
	g.build_index()
	var saved: LaneGraph = WorldLayout.lanes
	WorldLayout.lanes = g
	var rt := UIRoute.find(Vector3(0, 0, 2), Vector3(100, 0, 3))
	WorldLayout.lanes = saved
	_t("route_lane_graph", not rt.approx and rt.points.size() == 8 and rt.length > 95.0, "A* route points=%d len=%.0f" % [rt.points.size(), rt.length])

	# ---- map raster ----
	_t("raster_uv", MapRaster.world_to_uv(0, 0).is_equal_approx(Vector2(0.5, 0.5)) and MapRaster.world_to_uv(-320, -320).is_equal_approx(Vector2.ZERO), "uv mapping")
	_t("raster_texture", ui.hud.raster.texture != null, "placeholder or real texture present (real=%s)" % ui.hud.raster.is_real)

	# ---- settings ----
	Game.settings["master_volume"] = 0.5
	ui.apply_settings()
	var bus := AudioServer.get_bus_index("Master")
	_t("settings_master_volume", bus >= 0 and absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.1, "master bus %.1f dB" % AudioServer.get_bus_volume_db(bus))
	Game.settings["master_volume"] = 0.8
	ui.apply_settings()

	# ---- death / busted ----
	ui.death.state = DeathScreen.State.IDLE
	Events.player_died.emit()
	await _frames(3)
	_t("death_knocked", ui.death.state == DeathScreen.State.KNOCKED and Engine.time_scale < 0.5, "slow-mo=%.2f" % Engine.time_scale)
	Events.player_respawned.emit(Vector3.ZERO)
	await _frames(3)
	_t("death_respawn_restores", ui.death.state == DeathScreen.State.IDLE and absf(Engine.time_scale - 1.0) < 0.001, "state idle, time normal")
	Events.player_busted.emit()
	await _frames(3)
	_t("busted_state", ui.death.state == DeathScreen.State.BUSTED, "busted")
	Events.player_respawned.emit(Vector3.ZERO)
	await _frames(3)
	_t("stats_deaths", int(ui.stats["deaths"]) >= 1 and int(ui.stats["busted"]) >= 1, "deaths=%d busted=%d" % [int(ui.stats["deaths"]), int(ui.stats["busted"])])
	# menus cannot open while dead
	ui.death.state = DeathScreen.State.IDLE
	pl.is_dead = true
	_key(&"pause", true)
	_key(&"pause", false)
	await _frames(3)
	_t("pause_blocked_when_dead", not ui.is_menu_open(), "no pause menu while dead")
	pl.is_dead = false

	# ---- serialize ----
	var data: Dictionary = ui.serialize()
	_t("serialize", data.has("stats") and int(data["stats"]["kills"]) >= 1, "stats serialised")

	# ---- showcase builds ----
	ui.open_menu(&"ui_showcase", {"tab": 1})
	await _frames(3)
	_t("showcase_opens", ui.current_menu_id == &"ui_showcase", "showcase menu")
	ui.close_menu()

	ui.hud.test_mode = false
	holder.queue_free()
	Game.player = null
	await _frames(2)
	print("TEST ui_summary %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	return "fails=%d" % _fails
