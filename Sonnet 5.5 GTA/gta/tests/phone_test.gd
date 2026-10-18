extends Node
## Phone + photo mode headless tests (no nulls, every app page builds, photo mode saves a file and restores everything).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/phone_test.gd -Seconds 90 -GameArgs "--no-traffic --no-peds --no-intro"

var gs: GarageSystem = null
var passed := 0
var failed := 0
var _photo_events: Array = []


func T(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run(_main: Node) -> String:
	await get_tree().create_timer(2.0).timeout
	gs = Game.sys(&"garage")
	T("phone_garage_booted", gs != null)
	if gs == null:
		return "no garage"
	var ui = Game.ui
	T("phone_menu_registered", ui != null and ui.has_menu(&"phone") and ui.has_menu(&"garage") and ui.has_menu(&"garage_stored"))
	# ---- open / close through the real P key path
	T("phone_available_on_foot", gs.phone_available())
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_P
	ev.keycode = KEY_P
	ev.pressed = true
	gs._input(ev)
	await _frames(5)
	T("phone_opens_on_P", ui.current_menu_id == &"phone" and ui.is_menu_open())
	var ph: PhoneMenu = ui.get_menu(&"phone") as PhoneMenu
	T("phone_does_not_pause", not get_tree().paused)
	T("phone_home_has_all_apps", ph._content.get_child_count() > 2)
	# ---- every app page builds
	for app in ["services", "vehicles", "radio", "settings", "stats"]:
		ph._open_app(StringName(app))
		await _frames(3)
		T("phone_page_%s" % app, ph.page == StringName(app) and ph._content.get_child_count() >= 2, "page=%s children=%d" % [ph.page, ph._content.get_child_count()])
		ph.on_back()
	T("phone_back_to_home", ph.page == &"home")
	# ---- vehicles page lists stored vehicles
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)
	gs.add_record(&"sports", Color.RED, Color.BLACK)
	ph._open_app(&"vehicles")
	await _frames(3)
	T("phone_vehicles_lists_slots", ph._content.get_child_count() >= 3)
	# ---- vehicle service: deliver through the phone path
	var f0 := Engine.get_physics_frames()
	var dv: VehicleBase = await gs.deliver(0, 0.3)
	T("phone_vehicle_service_delivers", dv != null and dv.is_player_owned and dv.def_id == &"sports", "frames=%d" % (Engine.get_physics_frames() - f0))
	# ---- mechanic path (repair through the garage API the phone uses)
	if dv != null:
		dv.health = dv.max_health * 0.3
		gs.unlock_all = false
		Game.cash = 5000
		var cost := gs.repair_cost(dv) + PhoneMenu.MECHANIC_FEE
		T("phone_mechanic_cost_scales", cost > PhoneMenu.MECHANIC_FEE, "cost=%d" % cost)
		T("phone_mechanic_repairs", gs.repair_vehicle(dv, true) and dv.get_health_ratio() > 0.99)
		VehicleFactory.despawn(dv)
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)
	# ---- taxi / map / radio degrade gracefully
	ph._call_taxi()
	await _frames(5)
	T("phone_taxi_no_crash", true)
	var ras = Game.sys(&"audio")
	if ras != null and ras.has_method("get_stations"):
		var st: Array = ras.get_stations()
		T("phone_radio_has_stations", st.size() >= 2, str(st))
	ph._open_app(&"map")
	await _frames(5)
	T("phone_map_opens", ui.current_menu_id == &"map" or not ui.has_menu(&"map"), str(ui.current_menu_id))
	ui.close_menu()
	await _frames(5)
	# ---- settings sliders write Game.settings
	var vol0 = Game.settings.get("master_volume", 1.0)
	ui.open_menu(&"phone")
	await _frames(3)
	ph._open_app(&"settings")
	await _frames(3)
	T("phone_settings_page", ph.page == &"settings")
	ui.close_menu()
	await _frames(10)
	Game.settings["master_volume"] = vol0
	# ---- photo mode
	var ph_m := gs.photo
	T("photo_exists", ph_m != null and not ph_m.active)
	Events.photo_taken.connect(func(p: String): _photo_events.append(p))
	var paused0 := get_tree().paused
	var p = Game.player
	T("photo_can_enter", ph_m.can_enter())
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	f3.keycode = KEY_F3
	f3.pressed = true
	ph_m._input(f3)
	await _frames(5)
	T("photo_enters_on_F3", ph_m.active and ph_m.cam != null and ph_m.cam.current)
	T("photo_pauses_game", get_tree().paused and bool(Game.cheats.get("photo_mode", false)))
	T("photo_locks_player_hides_hud", bool(p.get("input_locked")) and ui.hud_hidden)
	var t0 := Game.time_of_day
	await _frames(30)
	T("photo_time_held", is_equal_approx(Game.time_of_day, t0))
	# camera controls
	var pos0 := ph_m.cam.global_position
	ph_m._yaw += 0.8
	ph_m._dist = 9.0
	ph_m.fov_deg = 40.0
	ph_m.roll_deg = 10.0
	await _frames(3)
	T("photo_camera_moves", ph_m.cam.global_position.distance_to(pos0) > 0.5 and is_equal_approx(ph_m.cam.fov, 40.0))
	# filters
	var seen_sat := {}
	for f in PhotoMode.FILTERS:
		ph_m.filter = f
		ph_m._apply_filter()
		var env: Environment = ph_m._env
		seen_sat[f] = [env.adjustment_saturation, env.adjustment_contrast]
	T("photo_filters_differ", seen_sat[&"noir"][0] < 0.1 and seen_sat[&"vivid"][0] > 1.3 and seen_sat[&"neutral"] != seen_sat[&"vivid"], str(seen_sat))
	ph_m.dof_amount = 0.6
	ph_m._apply_dof()
	T("photo_dof_enabled", ph_m._attrs.dof_blur_far_enabled)
	# take a photo
	var path: String = await ph_m.take_photo()
	T("photo_file_saved", path != "" and FileAccess.file_exists(path), path)
	T("photo_event_emitted", _photo_events.size() == 1 and _photo_events[0] == path)
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	# exit restores everything
	ph_m._input(f3)
	await _frames(5)
	T("photo_exits_on_F3", not ph_m.active and ph_m.cam == null)
	T("photo_restores_state", get_tree().paused == paused0 and not bool(Game.cheats.get("photo_mode", false)) and not bool(p.get("input_locked")) and not ui.hud_hidden)
	T("photo_gameplay_camera_back", Game.gameplay_camera != null and Game.gameplay_camera.current)
	# not allowed while a menu is open
	ui.open_menu(&"phone")
	await _frames(3)
	T("photo_blocked_in_menu", not ph_m.can_enter())
	ui.close_menu()
	await _frames(10)
	# phone camera app starts photo mode
	ui.open_menu(&"phone")
	await _frames(3)
	ph._open_app(&"camera")
	await get_tree().create_timer(0.8, true, false, true).timeout
	T("phone_camera_app_starts_photo_mode", ph_m.active)
	ph_m.exit()
	await _frames(5)
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
	return "done passed=%d failed=%d" % [passed, failed]
