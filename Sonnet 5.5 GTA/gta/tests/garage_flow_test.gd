extends Node
## End-to-end test of the customization garage session in the REAL garage_shop bay: prompt -> E -> lock/fade/studio/menu -> preview ->
## pay / revert -> repair -> store -> exit placement -> control restored.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/garage_flow_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds --no-intro"

var gs: GarageSystem = null
var passed := 0
var failed := 0


func T(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, max_frames: int = 600) -> bool:
	var f := 0
	while not cond.call() and f < max_frames:
		await get_tree().process_frame
		f += 1
	return cond.call()


func run(_main: Node) -> String:
	await get_tree().create_timer(2.0).timeout
	gs = Game.sys(&"garage")
	T("flow_garage_booted", gs != null)
	if gs == null:
		return "no garage"
	var w := 0
	while not gs._sites_ready and w < 400:
		await get_tree().process_frame
		w += 1
	var site: Dictionary = {}
	for s in gs.sites:
		if s["kind"] == &"shop":
			site = s
	T("flow_shop_site_with_two_bays", not site.is_empty() and (site["bays"] as Array).size() == 2, str(site.get("bays", []).size()))
	if site.is_empty():
		return "no site"
	var player = Game.player
	T("flow_player_exists", is_instance_valid(player))
	gs.unlock_all = false
	Game.cheats["unlock_all_mods"] = false
	Game.cash = 100000
	# ---- drive-in: vehicle standing inside bay 0
	var bay: Dictionary = site["bays"][0]
	var e: Vector3 = bay["entry"]
	var inside: Vector3 = bay["inside"]
	var dir := Util.flat(inside - e).normalized()
	var v := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), e + dir * 3.0 + Vector3(0, 0.8, 0)), {"engine_on": true})
	await _frames(40)
	player.enter_vehicle(v)
	await _frames(20)
	T("flow_player_driving", player.is_in_vehicle() and player.current_vehicle == v)
	if v.has_method("set_velocity"):
		v.set_velocity(Vector3.ZERO)
	await _wait_until(func(): return gs._bay_vehicle == v, 120)
	T("flow_bay_prompt", gs._bay_vehicle == v and gs._prompt_text.begins_with("[E] Customize"), gs._prompt_text)
	# ---- damage so the repair page has something to do
	v.health = v.max_health * 0.5
	v.wheels[0].flat = true
	var cash0 := Game.cash
	var base_mods := v.mods.duplicate(true)
	# ---- press E (through the real _input path)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.keycode = KEY_E
	ev.pressed = true
	gs._input(ev)
	T("flow_session_created", gs.session != null)
	var sess: GarageSession = gs.session
	var ok := await _wait_until(func(): return sess.active, 600)
	T("flow_session_active", ok)
	T("flow_player_locked", bool(player.get("input_locked")))
	T("flow_menu_open", Game.ui.current_menu_id == &"garage" and Game.ui.is_menu_open())
	T("flow_vehicle_in_studio", v.global_position.y > 150.0, "y=%.1f" % v.global_position.y)
	T("flow_studio_and_camera", sess.studio != null and sess.cam != null and sess.cam.current)
	T("flow_studio_lights", sess.studio.key != null and sess.studio.rim_a != null and sess.studio.neon_mats.size() > 4)
	T("flow_hud_hidden", Game.ui.hud_hidden)
	var menu: GarageMenu = Game.ui.get_menu(&"garage") as GarageMenu
	T("flow_menu_categories", menu._cats.size() == 10 and menu._cats[0] == &"repair", str(menu._cats))
	# every page builds without trouble
	var built := true
	for i in menu._cats.size():
		menu._show_category(i)
		await _frames(2)
		if menu._opts.get_child_count() == 0:
			built = false
			print("   empty page ", menu._cats[i])
	T("flow_all_pages_build", built)
	# ---- repair costs money
	T("flow_repair_needed", gs.repair_needed(v))
	var rc := gs.repair_cost(v)
	T("flow_repair_via_session", sess.repair_now() and Game.cash == cash0 - rc and v.get_health_ratio() > 0.99 and not v.wheels[0].flat, "cost=%d cash=%d" % [rc, Game.cash])
	cash0 = Game.cash
	# ---- preview does not charge, revert restores
	sess.pending.set_level("engine", 2)
	sess.pending.set_part(&"spoiler", &"gt_wing")
	sess.pending.paint1 = Color("#34e0ff")
	sess.preview()
	await _frames(3)
	T("flow_preview_applies", int(v.mods.get("engine", 0)) == 2 and v.mod_power > 1.1 and v.model.get_node_or_null("ModParts") != null and v.paint_primary.is_equal_approx(Color("#34e0ff")))
	T("flow_preview_free_until_install", Game.cash == cash0 and sess.has_pending() and sess.total_cost() > 0, "total=%d" % sess.total_cost())
	sess.revert_pending()
	await _frames(2)
	T("flow_revert_restores", int(v.mods.get("engine", 0)) == 0 and is_equal_approx(v.mod_power, 1.0) and not sess.has_pending())
	# ---- not enough cash: install refused, nothing changes
	sess.pending.set_level("engine", 4)
	sess.preview()
	var total := sess.total_cost()
	Game.cash = total - 1
	T("flow_install_refused_no_cash", not sess.apply_pending() and Game.cash == total - 1 and sess.committed.level("engine") == 0)
	# ---- install pays exactly the quote
	Game.cash = total + 321
	T("flow_install_pays_quote", sess.apply_pending() and Game.cash == 321 and sess.committed.level("engine") == 4 and not sess.has_pending(), "total=%d cash=%d" % [total, Game.cash])
	T("flow_installed_on_vehicle", int(v.mods.get("engine", 0)) == 4 and is_equal_approx(v.mod_power, 1.35), "power=%.3f" % v.mod_power)
	# unconfirmed change is dropped on exit
	sess.pending.paint1 = Color("#ff3d9a")
	sess.preview()
	# ---- leave through Esc / close
	menu.close()
	ok = await _wait_until(func(): return gs.session == null, 600)
	T("flow_session_ended", ok)
	await _frames(30)
	T("flow_control_restored", not bool(player.get("input_locked")) and not Game.ui.hud_hidden and not Game.ui.is_menu_open())
	var exit_pos := v.global_position
	T("flow_vehicle_back_at_bay_exit", v.global_position.y < 100.0 and Util.dist_xz(exit_pos, e) < 12.0, "pos=%s entry=%s" % [exit_pos, e])
	T("flow_unconfirmed_paint_dropped", not v.paint_primary.is_equal_approx(Color("#ff3d9a")) and int(v.mods.get("engine", 0)) == 4)
	T("flow_player_still_driving", player.is_in_vehicle() and player.current_vehicle == v)
	T("flow_studio_freed", sess == null or not is_instance_valid(sess) or sess.is_queued_for_deletion() or sess.studio == null or not is_instance_valid(sess.studio) or sess.studio.is_queued_for_deletion())
	# ---- second visit + store flow
	await _frames(10)
	var vstore := v
	if vstore.has_method("set_velocity"):
		vstore.set_velocity(Vector3.ZERO)
	vstore.place_at(Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(dir)), e + dir * 3.0 + Vector3(0, 0.6, 0)))
	await _frames(20)
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)
	gs.begin_session(vstore, site, 0)
	T("flow_second_session", await _wait_until(func(): return gs.session != null and gs.session.active, 600))
	var s2: GarageSession = gs.session
	s2.store_vehicle()
	T("flow_store_from_session", gs.get_stored_vehicles().size() == 1 and gs.get_stored_vehicles()[0]["def"] == "sedan" and s2.vehicle == null)
	var rec := gs.get_record(0)
	var rb := GarageBuild.from_dict(rec["build"])
	T("flow_stored_build_has_engine_4", rb.level("engine") == 4)
	menu = Game.ui.get_menu(&"garage") as GarageMenu
	menu.close()
	await _wait_until(func(): return gs.session == null, 600)
	await _frames(20)
	T("flow_after_store_control_ok", not bool(player.get("input_locked")) and not Game.ui.is_menu_open())
	# ---- deliver it back with the full mods
	var dv := gs.deliver_now(0)
	await _frames(10)
	T("flow_deliver_after_store", dv != null and int(dv.mods.get("engine", 0)) == 4 and dv.is_player_owned and is_equal_approx(dv.mod_power, 1.35))
	if dv != null:
		VehicleFactory.despawn(dv)
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)
	Game.cash = 5000
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
	return "done passed=%d failed=%d" % [passed, failed]
