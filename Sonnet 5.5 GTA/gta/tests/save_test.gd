extends Node
## Systems-A: SaveSystem tests (round trips, vehicle restore, corrupted / missing files, settings, tolerant reading, codec).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/save_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds"
## Uses slots 8 and 9 only and restores user://settings.json afterwards.

const SLOT := 9
const SLOT2 := 8

var _fails := 0
var _passes := 0
var player: Player = null
var _settings_backup := ""
var _had_settings := false


func _check(test_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST %s PASS %s" % [test_name, detail])
	else:
		_fails += 1
		print("TEST %s FAIL %s" % [test_name, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func run(_main: Node) -> Variant:
	await _frames(30)
	player = Game.player as Player
	_check("save_boot", player != null and SaveSystem != null, "player + autoload")
	if player == null:
		return false
	var sk: SkillsSystem = Game.sys(&"skills") as SkillsSystem
	if sk != null:
		sk.announce = false
	if FileAccess.file_exists(SaveSystem.SETTINGS_PATH):
		_had_settings = true
		_settings_backup = FileAccess.get_file_as_string(SaveSystem.SETTINGS_PATH)
	SaveSystem.delete_save(SLOT)
	SaveSystem.delete_save(SLOT2)
	var eco = Game.sys(&"economy")
	var env = Game.sys(&"environment")

	# ---- codec --------------------------------------------------------------------------------------------------
	var sample := {"v": Vector3(1.5, -2.0, 3.25), "c": Color(0.2, 0.4, 0.6, 1.0), "t": Transform3D(Basis(Vector3.UP, 0.7), Vector3(4, 5, 6)),
		"i": 7, "f": 0.25, "s": &"abc", "n": [1, 2.5, {"q": Vector2(3, 4)}], "b": true, "nan": NAN}
	var enc := JSON.stringify(SaveCodec.encode(sample))
	var dec: Dictionary = SaveCodec.decode(JSON.parse_string(enc))
	_check("save_codec_roundtrip", dec["v"] == Vector3(1.5, -2.0, 3.25) and (dec["c"] as Color).is_equal_approx(Color(0.2, 0.4, 0.6)) and (dec["t"] as Transform3D).is_equal_approx(sample["t"])
		and int(dec["i"]) == 7 and typeof(dec["i"]) == TYPE_INT and is_equal_approx(dec["f"], 0.25) and String(dec["s"]) == "abc" and dec["n"][2]["q"] == Vector2(3, 4) and is_nan(dec["nan"]), "Vector3/Color/Transform3D/int/nested")

	# ---- mutate the game into a recognisable state -------------------------------------------------------------------
	var pos := Vector3(22.0, 0.3, 41.0)
	player.teleport_to(pos, 1.2)
	await _frames(40)
	Game.cash = 12345
	player.health = 66.0
	player.armor = 33.0
	player.has_parachute = true
	player.has_scuba = true
	var w = player.weapons
	w.give_weapon(&"smg", 90, true)
	w.give_weapon(&"shotgun_pump", 28, false)
	w.set_mod(&"smg", &"suppressor", true)
	if env != null:
		env.set_time(17.25)
		env.set_weather(&"rain", true)
	if sk != null:
		sk.set_skill(&"driving", 64.0)
		sk.set_skill(&"lung", 33.0)
	SaveSystem.set_flag("test_flag", {"unlocked": ["a", "b"], "n": 3})
	var spot_id := "cash_beach_b"
	var pk = null
	if eco != null:
		pk = eco.get_pickup(spot_id)
		if pk != null:
			pk.set_active(false)
			pk.set("_respawn_at", Time.get_ticks_msec() + 300000)
	var smg_mag: int = w.get_ammo_in_mag() if w.current_id == &"smg" else -1
	var smg_res: int = w.get_ammo_reserve() if w.current_id == &"smg" else -1
	var look_before: Dictionary = (player.rig.variant as Dictionary).duplicate() if player.rig != null else {}

	# ---- save -----------------------------------------------------------------------------------------------------------------
	var ok_save := SaveSystem.save_game(SLOT)
	_check("save_writes_file", ok_save and SaveSystem.has_save(SLOT) and FileAccess.file_exists(SaveSystem.slot_path(SLOT)), SaveSystem.slot_path(SLOT))
	var raw := FileAccess.get_file_as_string(SaveSystem.slot_path(SLOT))
	var parsed = JSON.parse_string(raw)
	_check("save_is_json_with_version", parsed is Dictionary and int(parsed.get("version", 0)) == SaveSystem.VERSION and parsed.has("player") and parsed.has("systems") and parsed.has("world"), "%d bytes" % raw.length())
	var infos := SaveSystem.list_saves()
	var listed := false
	for i in infos:
		if int(i["slot"]) == SLOT and int(i.get("money", 0)) == 12345:
			listed = true
	_check("save_list_saves_info", listed, "list_saves has slot %d with money" % SLOT)
	var sections: Array = (parsed["systems"] as Dictionary).keys() if parsed is Dictionary else []
	_check("save_gathers_systems", sections.has("skills") and sections.has("economy") and sections.has("ui"), "systems: %s" % str(sections))

	# ---- mutate ---------------------------------------------------------------------------------------------------------------
	Game.cash = 7
	player.teleport_to(Vector3(-150.0, 0.3, 80.0), -0.5)
	player.health = 12.0
	player.armor = 0.0
	player.has_parachute = false
	player.has_scuba = false
	w.remove_weapon(&"shotgun_pump")
	w.remove_weapon(&"smg")
	if env != null:
		env.set_time(4.0)
		env.set_weather(&"clear", true)
	if sk != null:
		sk.reset_all()
	SaveSystem.flags.clear()
	if pk != null:
		pk.set_active(true)
	await _frames(20)

	# ---- load (async: fade, reset, restore, fade) ------------------------------------------------------------------------
	var t0 := Time.get_ticks_msec()
	var ok_load: bool = await SaveSystem.load_game_async(SLOT)
	_check("save_load_returns_true", ok_load, "%d ms" % (Time.get_ticks_msec() - t0))
	await _frames(40)
	_check("save_restores_cash", Game.cash == 12345, "cash %d" % Game.cash)
	_check("save_restores_position", player.global_position.distance_to(pos) < 3.0, "pos %s" % str(player.global_position))
	_check("save_restores_yaw", absf(wrapf(player.rotation.y - 1.2, -PI, PI)) < 0.05, "yaw %.2f" % player.rotation.y)
	_check("save_restores_health_armor", absf(player.health - 66.0) < 1.0 and absf(player.armor - 33.0) < 1.0, "hp %.0f armor %.0f" % [player.health, player.armor])
	_check("save_restores_gear_flags", player.has_parachute and player.has_scuba, "parachute=%s scuba=%s" % [str(player.has_parachute), str(player.has_scuba)])
	_check("save_restores_weapons", w.has_weapon(&"smg") and w.has_weapon(&"shotgun_pump") and w.current_id == &"smg", "current=%s smg=%s shotgun=%s" % [str(w.current_id), str(w.has_weapon(&"smg")), str(w.has_weapon(&"shotgun_pump"))])
	if w.has_weapon(&"smg"):
		_check("save_restores_ammo_and_mods", int(w.inventory[&"smg"]["mag"]) + int(w.inventory[&"smg"]["reserve"]) >= 85 and w.inventory[&"smg"]["mods"].has(&"suppressor"), "mag %d reserve %d mods %s" % [int(w.inventory[&"smg"]["mag"]), int(w.inventory[&"smg"]["reserve"]), str(w.inventory[&"smg"]["mods"])])
	if env != null:
		_check("save_restores_time_weather", absf(Game.time_of_day - 17.25) < 0.2 and Game.weather == &"rain", "time %.2f weather %s" % [Game.time_of_day, str(Game.weather)])
	if sk != null:
		_check("save_restores_skills", absf(sk.get_skill(&"driving") - 64.0) < 0.3 and absf(sk.get_skill(&"lung") - 33.0) < 0.3, "driving %.1f lung %.1f" % [sk.get_skill(&"driving"), sk.get_skill(&"lung")])
	_check("save_restores_flags", SaveSystem.get_flag("test_flag", {}) is Dictionary and SaveSystem.get_flag("test_flag")["n"] == 3, str(SaveSystem.get_flag("test_flag")))
	if pk != null:
		_check("save_restores_collected_pickup", not pk.active, "stored data: collected pickup stays collected")
		pk.set_active(true)
		pk.set("_respawn_at", 0)
	_check("save_restores_appearance", player.rig != null and (player.rig.variant as Dictionary).get("shirt") is Color and ((player.rig.variant as Dictionary)["shirt"] as Color).is_equal_approx(look_before.get("shirt", Color.WHITE)), "variant colours survive")
	_check("save_load_clears_wanted", Game.wanted_level == 0, "wanted %d" % Game.wanted_level)
	_check("save_not_loading_after", not SaveSystem.is_loading, "is_loading false")

	# ---- vehicle: current vehicle is saved and re-created --------------------------------------------------------------------
	player.teleport_to(Vector3(40.0, 0.3, 18.0), 0.0)
	await _frames(40)
	var car := VehicleFactory.spawn(&"muscle", Transform3D(Basis(Vector3.UP, 0.4), player.global_position + Vector3(0, 1.0, -5.0)), {"abandoned": true, "paint": Color(0.9, 0.1, 0.5)})
	await _frames(50)
	player.enter_vehicle(car, 0)
	await _frames(40)
	var in_car := player.is_in_vehicle()
	car.health = car.max_health * 0.6
	var car_pos := car.global_position
	SaveSystem.save_game(SLOT2)
	var vd = (JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.slot_path(SLOT2))) as Dictionary).get("vehicle", {})
	_check("save_gathers_vehicle", in_car and vd is Dictionary and String(vd.get("id", "")) == "muscle" and bool(vd.get("inside", false)), "vehicle block %s" % str(vd.get("id", "-")))
	player.exit_vehicle(true)
	await _frames(20)
	VehicleFactory.despawn(car)
	player.teleport_to(Vector3(-100.0, 0.3, 20.0), 0.0)
	await _frames(30)
	var ok2: bool = await SaveSystem.load_game_async(SLOT2)
	await _frames(90)
	var restored: Node = null
	for v in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if is_instance_valid(v) and v.get("def_id") == &"muscle" and (v as Node3D).global_position.distance_to(car_pos) < 8.0:
			restored = v
	_check("save_restores_vehicle", ok2 and restored != null, "vehicle near %s" % str(car_pos))
	if restored != null:
		_check("save_restores_vehicle_state", absf(restored.health / restored.max_health - 0.6) < 0.08 and absf((restored.paint_primary as Color).r - 0.9) < 0.01 and absf((restored.paint_primary as Color).b - 0.5) < 0.01, "health %.2f paint %s" % [restored.health / restored.max_health, str(restored.paint_primary)])
		_check("save_restores_player_in_vehicle", player.is_in_vehicle() and player.current_vehicle == restored, "seated again")
		player.exit_vehicle(true)
		await _frames(20)
		VehicleFactory.despawn(restored)

	# ---- missing / corrupted / old files -----------------------------------------------------------------------------------------
	player.teleport_to(pos, 0.0)
	await _frames(30)
	var cash_before := Game.cash
	_check("save_missing_slot_false", not SaveSystem.load_game(7) and not SaveSystem.is_loading, "no file -> false, game untouched")
	_write(SaveSystem.slot_path(6), "{ this is not json at all ]")
	_check("save_corrupt_garbage_false", not SaveSystem.load_game(6) and not SaveSystem.is_loading and SaveSystem.last_error != "", "error: %s" % SaveSystem.last_error)
	_write(SaveSystem.slot_path(6), "")
	_check("save_corrupt_empty_false", not SaveSystem.load_game(6), "empty file")
	_write(SaveSystem.slot_path(6), "[1,2,3]")
	_check("save_corrupt_wrong_shape_false", not SaveSystem.load_game(6), "array instead of object")
	_write(SaveSystem.slot_path(6), JSON.stringify({"version": 1, "world": {"cash": 99999999}}))
	_check("save_corrupt_no_player_false", not SaveSystem.load_game(6), "missing player section")
	await _frames(10)
	_check("save_corruption_keeps_playing", Game.cash == cash_before and is_instance_valid(Game.player) and not Game.player.is_dead, "cash unchanged %d, player alive" % Game.cash)
	SaveSystem.delete_save(6)
	# backup fallback: second save makes .bak, corrupting the main file falls back to it
	SaveSystem.save_game(SLOT)
	SaveSystem.save_game(SLOT)
	_check("save_keeps_backup", FileAccess.file_exists(SaveSystem.slot_path(SLOT) + ".bak"), "slot_%d.json.bak" % SLOT)
	_write(SaveSystem.slot_path(SLOT), "garbage")
	Game.cash = 5
	var ok_bak: bool = await SaveSystem.load_game_async(SLOT)
	await _frames(30)
	_check("save_backup_fallback_loads", ok_bak and Game.cash != 5, "loaded from .bak, cash %d" % Game.cash)
	# tolerant reading: old / partial file with unknown keys and missing sections
	var minimal := {"version": 1, "unknown_future_key": {"x": 1}, "player": {"pos": [30.0, 0.3, 12.0], "yaw": 0.3, "health": 80.0}, "world": {"cash": 321},
		"systems": {"nonexistent_system": {"a": 1}, "skills": {"xp": {"stamina": 10.0}}}}
	_write(SaveSystem.slot_path(SLOT2), JSON.stringify(minimal))
	var ok_min: bool = await SaveSystem.load_game_async(SLOT2)
	await _frames(40)
	_check("save_tolerant_partial_file", ok_min and Game.cash == 321 and player.global_position.distance_to(Vector3(30, 0.3, 12)) < 3.0, "cash %d pos %s" % [Game.cash, str(player.global_position)])
	_check("save_tolerant_unknown_keys", not SaveSystem.is_loading and absf(player.health - 80.0) < 1.0, "health %.0f" % player.health)

	# ---- player dead while loading ---------------------------------------------------------------------------------------------------
	SaveSystem.save_game(SLOT)
	player.spawn_protection = 0.0
	player.invulnerable = false
	player.apply_damage(9999.0, {"type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO})
	await _frames(10)
	_check("save_dead_player_precondition", player.is_dead, "player is dead")
	var ok_dead: bool = await SaveSystem.load_game_async(SLOT)
	await _frames(60)
	_check("save_load_revives_dead_player", ok_dead and not player.is_dead and player.health > 0.0, "alive again, hp %.0f" % player.health)

	# ---- settings -----------------------------------------------------------------------------------------------------------------------
	var old_fov = Game.settings.get("fov", 75.0)
	var old_vol = Game.settings.get("master_volume", 0.8)
	Game.settings["fov"] = 88.0
	Game.settings["master_volume"] = 0.33
	Game.settings["invert_y"] = true
	SaveSystem.save_settings()
	_check("save_settings_file", FileAccess.file_exists(SaveSystem.SETTINGS_PATH), SaveSystem.SETTINGS_PATH)
	Game.settings["fov"] = 60.0
	Game.settings["master_volume"] = 1.0
	Game.settings["invert_y"] = false
	SaveSystem.load_settings()
	_check("save_settings_roundtrip", is_equal_approx(float(Game.settings["fov"]), 88.0) and is_equal_approx(float(Game.settings["master_volume"]), 0.33) and Game.settings["invert_y"] == true, "fov %s vol %s invert %s" % [str(Game.settings["fov"]), str(Game.settings["master_volume"]), str(Game.settings["invert_y"])])
	# the stored settings are announced to Sfx / Environment / UI (they applied the defaults at their own boot) without re-saving
	var got_bc := [0]
	var bc := func() -> void: got_bc[0] += 1
	Events.settings_changed.connect(bc)
	SaveSystem._settings_timer = -1.0
	SaveSystem.broadcast_settings()
	Events.settings_changed.disconnect(bc)
	_check("save_settings_broadcast", got_bc[0] == 1 and SaveSystem._settings_timer < 0.0, "settings_changed emitted once, no re-save scheduled")
	_write(SaveSystem.SETTINGS_PATH, "{broken")
	Game.settings["fov"] = 70.0
	SaveSystem.load_settings()
	_check("save_settings_corrupt_survives", is_equal_approx(float(Game.settings["fov"]), 70.0), "damaged settings.json ignored")
	Game.settings["fov"] = old_fov
	Game.settings["master_volume"] = old_vol
	Game.settings["invert_y"] = false
	if _had_settings:
		_write(SaveSystem.SETTINGS_PATH, _settings_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.SETTINGS_PATH))

	# ---- misc --------------------------------------------------------------------------------------------------------------------------------
	_check("save_quick_keys_left_to_ui", SaveSystem.handles_quick_keys() == false, "F5 / F9 stay with the UI")
	_check("save_delete", SaveSystem.delete_save(SLOT) and not SaveSystem.has_save(SLOT), "delete_save")
	SaveSystem.delete_save(SLOT2)
	SaveSystem.flags.clear()
	if sk != null:
		sk.announce = true
		sk.reset_all()
	print("TEST SUMMARY save pass=%d fail=%d" % [_passes, _fails])
	return _fails == 0
