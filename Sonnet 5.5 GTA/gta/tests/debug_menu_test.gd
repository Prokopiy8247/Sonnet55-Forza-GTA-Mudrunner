extends Node
## Headless action test of the benchmark menu (no UI clicks, every action function is called and its effect verified).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/debug_menu_test.gd -Seconds 120 -GameArgs "--no-intro"
## Prints "TEST <name> PASS|FAIL <detail>".

var _fails := 0


func _t(name: String, ok: bool, detail: String = "") -> void:
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run(main: Node) -> String:
	await _frames(20)
	var p = Game.player
	_t("boot", p != null and Game.sys(&"debug") != null and Game.ui != null and Game.ui.has_menu(&"debug"), "debug system + menu registered")
	if p == null:
		return "no player"
	Game.ui.capture_when_idle = false
	Game.cheats["never_wanted"] = false

	# ---- teleport: every location, snapped, not underground -------------------------------------------------
	var bad: Array = []
	var n := 0
	for g in DebugCatalog.location_groups():
		for e in g[1]:
			n += 1
			var before: Vector3 = p.global_position
			var r := DebugCmds.teleport_to_location(e["id"])
			await _frames(2)
			var pos: Vector3 = p.global_position
			var under: bool = pos.y < WorldLayout.terrain_height(pos.x, pos.z) - 0.6 and not WorldLayout.is_water(pos.x, pos.z)
			if not r["ok"] or under or (pos.distance_to(before) < 0.5 and before.distance_to(e["pos"]) > 3.0):
				bad.append("%s%s" % [e["id"], (" UNDERGROUND y=%.1f loc=%s terrain=%.2f resolved=%s" % [pos.y, str(e["pos"]), WorldLayout.terrain_height(pos.x, pos.z), str(r.get("pos"))]) if under else ""])
	_t("teleport_all_locations", bad.is_empty() and n >= 40, "%d locations, bad=%s" % [n, str(bad)])
	DebugCmds.teleport_to_location(&"player_spawn")
	await _frames(30)

	# ---- every vehicle id spawns, is enterable, gets removed ------------------------------------------------------
	var vbad: Array = []
	var ids := DebugCatalog.all_vehicle_ids()
	for id in ids:
		var r := DebugCmds.spawn_vehicle(id, {"enter": false})
		await _frames(3)
		var v = r.get("vehicle", null)
		if not r["ok"] or not is_instance_valid(v):
			vbad.append("%s spawn: %s" % [id, r.get("msg", "")])
			continue
		var seat_ok: bool = v.get_free_seat() >= 0
		var entered: bool = DebugCmds.enter_vehicle(v)
		await _frames(2)
		var in_it: bool = p.get("current_vehicle") == v
		if not (seat_ok and entered and in_it):
			vbad.append("%s enter(seat=%s entered=%s in=%s)" % [id, seat_ok, entered, in_it])
		p.exit_vehicle(true)
		await _frames(2)
		DebugCmds.remove_vehicle(v)
		await _frames(1)
	_t("spawn_every_vehicle_enterable", vbad.is_empty() and ids.size() == 20, "%d ids, bad=%s" % [ids.size(), str(vbad)])
	DebugCmds.teleport_to_location(&"player_spawn")
	await _frames(30)

	# ---- vehicle tools ---------------------------------------------------------------------------------------------------------
	var rs := DebugCmds.spawn_vehicle(&"sedan", {"enter": true, "paint": Color("#ff3d9a")})
	await _frames(20)
	var sedan: VehicleBase = rs.get("vehicle", null)
	_t("spawn_and_drive", rs["ok"] and DebugCmds.player_vehicle() == sedan, rs["msg"])
	if sedan != null:
		sedan.health = sedan.max_health * 0.3
		var rr := DebugCmds.repair_current()
		_t("repair_vehicle", rr["ok"] and sedan.health >= sedan.max_health - 0.1, "hp %d" % int(sedan.health))
		sedan.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), sedan.global_position + Vector3.UP * 0.5)
		var rf := DebugCmds.flip_current()
		await _frames(3)
		_t("flip_vehicle", rf["ok"] and not sedan.is_flipped_over(), "")
		DebugCmds.set_vehicle_god(true)
		sedan.apply_damage(400.0, {"type": GC.DMG_BULLET})
		_t("vehicle_god", sedan.health >= sedan.max_health - 0.1, "hp %d" % int(sedan.health))
		DebugCmds.set_vehicle_god(false)
		var p0 := sedan.mod_power
		DebugCmds.set_speed_boost(2.0)
		_t("speed_boost", sedan.mod_power > p0 * 1.9, "mod_power %.2f" % sedan.mod_power)
		DebugCmds.set_speed_boost(1.0)
		_t("speed_boost_off", absf(sedan.mod_power - p0) < 0.01, "")
		var g = Game.sys(&"garage")
		_t("customize_available", g != null and g.can_customize(sedan), "can_customize(sedan)")
		DebugCmds.set_unlock_all_mods(true)
		_t("unlock_all_mods", bool(Game.cheats["unlock_all_mods"]) and g.is_free(), "")
		DebugCmds.set_unlock_all_mods(false)
		p.exit_vehicle(true)
		await _frames(5)
		var spawned: Array = []
		for i in 3:
			var rv := DebugCmds.spawn_vehicle(&"compact", {"enter": false})
			spawned.append(rv.get("vehicle", null))
			await _frames(2)
		var rd := DebugCmds.delete_nearby_vehicles(60.0)
		await _frames(3)
		var alive := 0
		for v in spawned:
			if is_instance_valid(v) and v.is_inside_tree():
				alive += 1
		_t("delete_nearby_vehicles", rd["ok"] and alive == 0, "deleted %d, %d of my 3 still alive" % [int(rd.get("count", 0)), alive])
		if is_instance_valid(sedan):
			DebugCmds.remove_vehicle(sedan)

	# ---- weapons ------------------------------------------------------------------------------------------------------------
	var wc = p.weapons
	var wbad: Array = []
	DebugCmds.remove_all_weapons()
	for id in WeaponDefs.ids():
		var r := DebugCmds.give_weapon(id)
		if not r["ok"] or not wc.has_weapon(id):
			wbad.append(String(id))
		elif WeaponDefs.get_def(id)["mag_size"] > 0 and int(wc.inventory[id]["mag"]) + int(wc.inventory[id]["reserve"]) <= 0:
			wbad.append(String(id) + "(no ammo)")
	_t("give_each_weapon", wbad.is_empty() and WeaponDefs.ids().size() == 16, "%d weapons, bad=%s" % [WeaponDefs.ids().size(), str(wbad)])
	DebugCmds.remove_all_weapons()
	_t("remove_all_weapons", wc.get_weapon_ids().size() == 1, str(wc.get_weapon_ids()))
	DebugCmds.give_all_weapons()
	_t("give_all_weapons", wc.get_weapon_ids().size() == 16, "%d" % wc.get_weapon_ids().size())
	wc.inventory[&"pistol"]["mag"] = 0
	wc.inventory[&"pistol"]["reserve"] = 0
	DebugCmds.refill_ammo()
	_t("refill_ammo", int(wc.inventory[&"pistol"]["mag"]) > 0 and int(wc.inventory[&"pistol"]["reserve"]) > 0, "")
	DebugCmds.give_weapon(&"pistol")
	var ra := DebugCmds.set_attachment(&"suppressor", true)
	_t("attachment_toggle", ra["ok"] and wc.has_mod(&"pistol", &"suppressor"), ra["msg"])
	DebugCmds.set_attachment(&"suppressor", false)
	DebugCmds.set_infinite_ammo(true)
	_t("infinite_ammo_flag", bool(Game.cheats["infinite_ammo"]), "")
	DebugCmds.set_infinite_ammo(false)
	p.has_parachute = false
	DebugCmds.give_parachute(true)
	_t("parachute", p.has_parachute, "")
	DebugCmds.set_scuba(true)
	_t("scuba_on", p.has_scuba and bool(Game.cheats["scuba"]), "")
	DebugCmds.set_scuba(false)
	p.lungs = 1.0
	DebugCmds.refill_lungs()
	_t("lungs_refill", p.lungs >= p.lung_capacity() - 0.01, "%.1f" % p.lungs)
	DebugCmds.set_health(40)
	DebugCmds.set_armor(55)
	_t("health_armor", int(p.health) == 40 and int(p.armor) == 55, "%d/%d" % [p.health, p.armor])
	DebugCmds.heal_full()
	_t("heal_full", p.health >= p.max_health and p.armor >= p.max_armor, "")

	# ---- player: money, cheats, wanted, skills, time, weather -----------------------------------------------------------------
	DebugCmds.set_money(1234)
	_t("set_money", Game.cash == 1234, str(Game.cash))
	DebugCmds.add_money(10000)
	_t("add_money", Game.cash == 11234, str(Game.cash))
	DebugCmds.set_money(0)
	_t("money_zero", Game.cash == 0, "")
	DebugCmds.set_invulnerable(true)
	var hp: float = p.health
	p.apply_damage(30.0, {"type": GC.DMG_BULLET})
	_t("invulnerable", p.health == hp, "")
	DebugCmds.set_invulnerable(false)
	var wbad2: Array = []
	for lvl in [1, 2, 3, 4, 5, 0]:
		DebugCmds.set_wanted(lvl)
		if Game.wanted_level != lvl:
			wbad2.append("%d->%d" % [lvl, Game.wanted_level])
	_t("wanted_levels_0_5", wbad2.is_empty(), str(wbad2))
	DebugCmds.set_wanted(4)
	DebugCmds.clear_wanted()
	_t("clear_wanted", Game.wanted_level == 0, "")
	DebugCmds.set_never_wanted(true)
	var rn := DebugCmds.set_wanted(3)
	_t("never_wanted", not rn["ok"] and Game.wanted_level == 0, rn["msg"])
	DebugCmds.set_never_wanted(false)
	DebugCmds.skills_max()
	var sk = Game.sys(&"skills")
	_t("skills_max", sk.get_skill01(&"driving") > 0.99 and sk.get_skill01(&"lung") > 0.99, "")
	DebugCmds.set_skill(&"flying", 50)
	_t("skill_slider", absf(sk.get_skill01(&"flying") - 0.5) < 0.05, "%.2f" % sk.get_skill01(&"flying"))
	DebugCmds.skills_reset()
	_t("skills_reset", sk.get_skill01(&"driving") < 0.99, "")
	DebugCmds.set_time(18.5)
	_t("set_time", absf(Game.time_of_day - 18.5) < 0.1, "%.2f" % Game.time_of_day)
	DebugCmds.set_time_frozen(true)
	_t("time_freeze", Game.time_frozen, "")
	DebugCmds.set_clock_speed(120.0)
	_t("clock_speed", Game.time_scale == 120.0, "")
	DebugCmds.set_clock_speed(60.0)
	var env = Game.sys(&"environment")
	var wxbad: Array = []
	for w in GC.WEATHERS:
		DebugCmds.set_weather(w)
		if env.get_weather() != w:
			wxbad.append(String(w))
	_t("weather_all", wxbad.is_empty(), str(wxbad))
	DebugCmds.set_weather(&"clear")

	# ---- world / spawn ----------------------------------------------------------------------------------------------------------
	DebugCmds.teleport_to_location(&"player_spawn")
	await _frames(30)
	var pol0 := get_tree().get_nodes_in_group(GC.G_POLICE).size()
	var rc := DebugCmds.spawn_police(&"car")
	await _frames(5)
	var ro := DebugCmds.spawn_police(&"officer")
	var rw := DebugCmds.spawn_police(&"swat")
	await _frames(5)
	_t("spawn_police", rc["ok"] and ro["ok"] and rw["ok"] and get_tree().get_nodes_in_group(GC.G_POLICE).size() >= pol0 + 4, "car=%s officer=%s swat=%s" % [rc["msg"], ro["msg"], rw["msg"]])
	var rh := DebugCmds.spawn_police(&"heli")
	_t("spawn_police_heli", rh["ok"], rh["msg"])
	var rg := DebugCmds.spawn_gang(false)
	await _frames(3)
	var gang_ok := 0
	for m in DebugCmds.debug_gang:
		if is_instance_valid(m) and m.is_in_group(GC.G_HOSTILE):
			gang_ok += 1
	_t("spawn_gang", rg["ok"] and gang_ok == 3, "%d hostile" % gang_ok)
	var rp := DebugCmds.spawn_pedestrians(6)
	_t("spawn_pedestrians", rp["ok"] and int(rp.get("count", 0)) > 0, rp["msg"])
	var re := DebugCmds.explode_at_crosshair()
	_t("explosion", re["ok"], re["msg"])
	var ra2 := DebugCmds.spawn_service(&"ambulance")
	var rf2 := DebugCmds.spawn_service(&"firetruck")
	_t("spawn_ambulance_firetruck", ra2["ok"] and rf2["ok"], "%s / %s" % [ra2["msg"], rf2["msg"]])
	var rt := DebugCmds.call_taxi()
	_t("call_taxi_graceful", rt.has("ok") and (rt["ok"] or DebugCmds.taxi_available() == false), "ok=%s %s" % [rt["ok"], rt["msg"]])
	DebugCmds.set_wildlife(false)
	_t("wildlife_flag", not bool(Game.cheats["wildlife"]), "")
	DebugCmds.set_wildlife(true)
	DebugCmds.set_slowmo(true)
	_t("slowmo", Engine.time_scale < 0.5, "")
	DebugCmds.set_slowmo(false)
	_t("slowmo_off", Engine.time_scale == 1.0, "")
	DebugCmds.set_density("traffic_density", 0.5)
	_t("density", float(Game.settings["traffic_density"]) == 0.5, "")
	DebugCmds.set_density("traffic_density", 1.0)

	# ---- traffic / pedestrian toggles (counts really drop) ------------------------------------------------------------------------
	DebugCmds.teleport_to_location(&"district_center_downtown")
	var traffic = Game.sys(&"traffic")
	var peds = Game.sys(&"peds")
	var waited := 0
	while waited < 900 and (traffic.get_active_count() == 0 or peds.active_count() == 0):
		await _frames(30)
		waited += 30
	var t_before: int = traffic.get_active_count()
	var p_before: int = peds.active_count()
	DebugCmds.set_traffic(false)
	DebugCmds.set_pedestrians(false)
	await _frames(10)
	_t("toggle_traffic_counts_drop", t_before > 0 and traffic.get_active_count() == 0, "%d -> %d" % [t_before, traffic.get_active_count()])
	_t("toggle_pedestrians_counts_drop", p_before > 0 and peds.active_count() < p_before, "%d -> %d" % [p_before, peds.active_count()])
	DebugCmds.set_traffic(true)
	DebugCmds.set_pedestrians(true)
	var rk := DebugCmds.kill_nearby_npcs(0.5)
	_t("kill_nearby_npcs_runs", rk["ok"], rk["msg"])

	# ---- overlays / info -------------------------------------------------------------------------------------------------------
	for key in ["show_fps", "show_coords", "dbg_stats", "dbg_wanted", "dbg_lanes", "dbg_peds"]:
		DebugCmds.set_cheat(key, true)
	var dm = Game.sys(&"debug")
	dm.refresh_state()
	await _frames(30)
	_t("overlay_flags", dm.gizmos.active and dm._overlay_label != null and DebugCmds.stats_text().length() > 40, DebugCmds.stats_text().replace("\n", " | "))
	for key in ["show_fps", "show_coords", "dbg_stats", "dbg_wanted", "dbg_lanes", "dbg_peds"]:
		DebugCmds.set_cheat(key, false)
	dm.refresh_state()
	_t("overlay_idle_no_process", not dm.is_processing() and not dm.gizmos.is_processing(), "menu process off when nothing is enabled")
	DebugCmds.set_render_mode(1)
	_t("render_mode", get_tree().root.debug_draw == Viewport.DEBUG_DRAW_UNSHADED, "")
	DebugCmds.set_render_mode(0)
	DebugCmds.set_hud_visible(false)
	_t("hud_toggle", Game.ui.hud_hidden, "")
	DebugCmds.set_hud_visible(true)

	# ---- system ---------------------------------------------------------------------------------------------------------------------------
	var rsv := DebugCmds.save_slot(3)
	_t("save_slot", rsv["ok"] and SaveSystem.has_save(3), rsv["msg"])
	_t("load_empty_slot_graceful", not DebugCmds.load_slot(9)["ok"], "")
	var dump := DebugCmds.state_dump()
	_t("state_dump", dump.length() > 100, "%d chars" % dump.length())
	var checks := DebugCmds.run_self_checks()
	var cfail: Array = []
	for c in checks:
		if not c[1]:
			cfail.append("%s (%s)" % [c[0], c[2]])
	_t("self_checks", checks.size() >= 10 and cfail.is_empty(), "%d checks, failing: %s" % [checks.size(), str(cfail)])
	_t("version_info", DebugCmds.version_info().size() >= 5, "")
	DebugCmds.reset_to_spawn()
	await _frames(10)
	var sp: Vector3 = WorldLayout.location_pos(&"player_spawn")
	_t("reset_to_spawn", Util.dist_xz(p.global_position, sp) < 3.0, "")
	var rcl := DebugCmds.clear_all_dynamic()
	_t("clear_all_dynamic", rcl["ok"], rcl["msg"])

	# ---- the real UI: open every tab through the menu host, F1 action path ------------------------------------------------------------------------------
	var ui = Game.ui
	_t("menu_opens", dm.open(0) and ui.current_menu_id == &"debug", "")
	var tab_ok: Array = []
	for i in DebugMenuUI.TAB_NAMES.size():
		dm.menu.show_tab(i)
		await _frames(2)
		tab_ok.append(dm.menu._page.get_child_count() > 2)
	_t("all_tabs_build", not tab_ok.has(false), str(tab_ok))
	dm.menu.show_tab(1)
	dm.menu._on_search("jet")
	var visible_n := 0
	for r in dm.menu._vehicle_rows:
		if (r[0] as Control).visible:
			visible_n += 1
	_t("vehicle_search_filters", visible_n == 1, "%d match 'jet'" % visible_n)
	dm.close()
	_t("menu_closes", ui.current_menu_id == &"", "")
	dm._input(_key_event(KEY_F1))
	_t("f1_toggles_menu", ui.current_menu_id == &"debug", "")
	dm._input(_key_event(KEY_F1))
	_t("f1_closes_menu", ui.current_menu_id == &"", "")
	dm._input(_key_event(KEY_3, true))
	_t("hotkey_alt3_wanted", Game.wanted_level == 3, "wanted %d" % Game.wanted_level)
	DebugCmds.clear_wanted()
	print("TEST debug_menu_summary %s %d failure(s)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	return "fails=%d" % _fails


func _key_event(code: Key, alt: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.alt_pressed = alt
	return e
