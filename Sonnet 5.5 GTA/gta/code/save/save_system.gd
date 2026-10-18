extends Node
## Autoload "SaveSystem": JSON saves in user://saves/slot_N.json + user://settings.json (docs/ARCHITECTURE.md 14.6, docs/api/systems_a.md).
##
##   save_game(slot := 0) -> bool          load_game(slot := 0) -> bool  (validates synchronously, restores asynchronously with a fade)
##   await load_game_async(slot) -> bool   has_save(slot)   list_saves()   delete_save(slot)   get_slot_info(slot)
##   save_settings() / load_settings()     set_flag(key, value) / get_flag(key, default)     autosave (setting "autosave")
##
## Every system node in Game.systems that implements `serialize() -> Dictionary` / `deserialize(data)` is saved under
## "systems/<key>"; the player (position, health, armor, stamina, weapons, parachute/scuba, appearance), cash, time of day, weather,
## the last / current player vehicle and a generic `flags` dictionary are saved explicitly. Missing keys are tolerated on read, unknown
## keys are ignored, a damaged file never crashes the game (toast + keep playing). Files are written atomically (tmp + rename) and the
## previous file is kept as slot_N.json.bak.

signal save_finished(slot: int, ok: bool)
signal load_finished(slot: int, ok: bool)

const VERSION := 1
const SAVE_DIR := "user://saves"
const SETTINGS_PATH := "user://settings.json"
const MAX_SLOTS := 10
const AUTOSAVE_SLOT := 1
const AUTOSAVE_INTERVAL := 300.0
const FADE_OUT := 0.45
const FADE_IN := 0.6
const SYSTEM_SKIP: Array[StringName] = [&"player", &"world", &"environment", &"audio"]

## Settings keys added to Game.settings when the file or the code does not provide them.
const EXTRA_SETTINGS := {"autosave": true, "restore_wanted": false}

var flags: Dictionary = {}               # generic persistent flags for modules without a system node
var is_loading := false
var last_error := ""
var last_slot := -1
var save_count := 0
var verbose := false

var _autosave_clock := 0.0
var _settings_timer := -1.0
var _settings_loaded := false
var _quiet_settings := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_dir()
	load_settings()
	Events.settings_changed.connect(_on_settings_changed)
	Events.save_requested.connect(_on_save_requested)
	Events.game_ready.connect(_on_game_ready)
	if FileAccess.file_exists(SETTINGS_PATH):
		broadcast_settings.call_deferred()          # Sfx (loaded before this autoload) picks up the stored volumes


func _process(delta: float) -> void:
	if _settings_timer >= 0.0:
		_settings_timer -= delta
		if _settings_timer < 0.0:
			save_settings()
	if is_loading or Game.paused or not bool(Game.settings.get("autosave", true)):
		return
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	_autosave_clock += delta
	if _autosave_clock >= AUTOSAVE_INTERVAL:
		if p.get("is_dead") == true or Game.wanted_level > 0 or not p.has_method("is_on_foot"):
			_autosave_clock = AUTOSAVE_INTERVAL - 20.0       # retry soon, not mid-crisis
			return
		_autosave_clock = 0.0
		if save_game(AUTOSAVE_SLOT):
			Game.notify("Autosaved", &"info")


## The UI owns F5 / F9 (it calls save_game(0) / load_game(0)); return true only to take the keys over.
func handles_quick_keys() -> bool:
	return false


# ====================================================================================================== paths / info
static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SAVE_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func delete_save(slot: int = 0) -> bool:
	var ok := false
	for ext in ["", ".bak", ".tmp"]:
		var p: String = slot_path(slot) + String(ext)
		if FileAccess.file_exists(p):
			ok = DirAccess.remove_absolute(ProjectSettings.globalize_path(p)) == OK or ok
	return ok


## [{slot, exists, ok, saved_text, saved_unix, money, district, hour, play_time, version}] for every slot that has a file.
func list_saves() -> Array:
	var out: Array = []
	for s in MAX_SLOTS:
		if has_save(s):
			out.append(get_slot_info(s))
	return out


func get_slot_info(slot: int) -> Dictionary:
	var info := {"slot": slot, "exists": has_save(slot), "ok": false}
	if not info["exists"]:
		return info
	var res := _read_file(slot_path(slot))
	if not bool(res["ok"]):
		info["error"] = res["error"]
		return info
	var d: Dictionary = res["data"]
	info["ok"] = true
	info["version"] = int(d.get("version", 0))
	info["saved_text"] = String(d.get("saved_text", ""))
	info["saved_unix"] = int(d.get("saved_unix", 0))
	var meta = d.get("meta", {})
	if meta is Dictionary:
		for k in meta:
			info[k] = meta[k]
	return info


# ====================================================================================================== flags
func set_flag(key: String, value: Variant) -> void:
	flags[key] = value


func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)


# ====================================================================================================== save
func save_game(slot: int = 0) -> bool:
	last_error = ""
	if is_loading:
		last_error = "busy loading"
		return false
	if slot < 0 or slot >= MAX_SLOTS:
		last_error = "bad slot"
		return false
	if Game.player == null or not is_instance_valid(Game.player):
		last_error = "no player"
		return false
	_ensure_dir()
	var data := gather(slot)
	var text := JSON.stringify(SaveCodec.encode(data), "\t")
	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
		push_warning("[SaveSystem] " + last_error)
		save_finished.emit(slot, false)
		return false
	f.store_string(text)
	f.close()
	# keep the previous file as .bak, then move the new one into place
	var abs_path := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(abs_path, abs_path + ".bak")
		DirAccess.remove_absolute(abs_path)
	var err := DirAccess.rename_absolute(abs_tmp, abs_path)
	if err != OK:
		last_error = "rename failed (%s)" % error_string(err)
		push_warning("[SaveSystem] " + last_error)
		save_finished.emit(slot, false)
		return false
	last_slot = slot
	save_count += 1
	if verbose:
		print("[SaveSystem] saved slot %d (%d bytes)" % [slot, text.length()])
	save_finished.emit(slot, true)
	return true


## The whole save dictionary (also used by tests).
func gather(slot: int = 0) -> Dictionary:
	var p = Game.player
	var d := {
		"version": VERSION, "game": GC.GAME_NAME,
		"saved_unix": int(Time.get_unix_time_from_system()), "saved_text": Time.get_datetime_string_from_system(false, true),
	}
	var pos: Vector3 = p.global_position
	var play_time := 0.0
	if Game.ui != null and is_instance_valid(Game.ui):
		var st = Game.ui.get("stats")
		if st is Dictionary:
			play_time = float(st.get("time_played", 0.0))
	d["meta"] = {"money": Game.cash, "hour": snappedf(Game.time_of_day, 0.01), "district": String(WorldLayout.district_at(pos.x, pos.z)),
		"play_time": snappedf(play_time, 1.0), "weather": String(Game.weather)}
	d["world"] = {"cash": Game.cash, "time_of_day": Game.time_of_day, "weather": String(Game.weather),
		"wanted_level": Game.wanted_level, "rain": Game.rain_intensity}
	d["player"] = p.serialize() if p.has_method("serialize") else {}
	var extra := {}
	if p.get("has_scuba") != null:
		extra["has_scuba"] = bool(p.get("has_scuba"))
	if p.get("rig") != null and p.rig.get("variant") is Dictionary and not (p.rig.variant as Dictionary).is_empty():
		extra["appearance"] = (p.rig.variant as Dictionary).duplicate()
	d["player_extra"] = extra
	d["vehicle"] = _gather_vehicle(p)
	var systems := {}
	for key in Game.systems:
		if key in SYSTEM_SKIP:
			continue
		var node = Game.systems[key]
		if is_instance_valid(node) and node.has_method("serialize"):
			var s = node.serialize()
			if s is Dictionary and not (s as Dictionary).is_empty():
				systems[String(key)] = s
	d["systems"] = systems
	d["flags"] = flags
	d["settings"] = _settings_snapshot()
	return d


func _gather_vehicle(p: Node) -> Dictionary:
	var v = p.current_vehicle if p.is_in_vehicle() else p.get("last_vehicle")
	if v == null or not is_instance_valid(v) or not (v is Node3D) or not (v as Node3D).is_inside_tree() or v.get("def_id") == null:
		return {}                                   # (a vehicle recycled into the factory pool is valid but not in the tree)
	var inside: bool = p.is_in_vehicle()
	if v.get("is_destroyed") == true:
		return {}
	if v.get("faction") == GC.F_POLICE or v.is_in_group(GC.G_POLICE):
		return {}
	if not inside:
		if v.get("is_ai_controlled") == true or v.is_in_group(GC.G_TRAFFIC):
			return {}
		if (v as Node3D).global_position.distance_to(p.global_position) > 160.0:
			return {}
	var t := (v as Node3D).global_transform
	return {"id": String(v.def_id), "inside": inside, "xf": t, "paint": v.paint_primary, "paint2": v.paint_secondary,
		"finish": String(v.get("paint_finish") if v.get("paint_finish") != null else &"gloss"),
		"mods": (v.mods as Dictionary).duplicate() if v.get("mods") is Dictionary else {},
		"health_ratio": clampf(float(v.health) / maxf(float(v.max_health), 1.0), 0.02, 1.0),
		"owned": bool(v.get("is_player_owned")), "headlights": bool(v.get("headlights_on"))}


func _settings_snapshot() -> Dictionary:
	var out := {}
	for k in Game.settings:
		var val = Game.settings[k]
		if val is bool or val is int or val is float or val is String:
			out[String(k)] = val
	return out


# ====================================================================================================== load
## Validates the file synchronously (returns false + toast when missing or damaged) and then restores asynchronously:
## fade out, reset dynamic content, restore, fade in. Listen to load_finished / Events.load_completed or use load_game_async().
func load_game(slot: int = 0) -> bool:
	last_error = ""
	if is_loading:
		last_error = "busy loading"
		return false
	if Game.player == null or not is_instance_valid(Game.player):
		last_error = "no player"
		return false
	var res := _read_file(slot_path(slot))
	if not bool(res["ok"]) and has_save(slot) and FileAccess.file_exists(slot_path(slot) + ".bak"):
		# fall back to the previous good save
		var alt := _read_file(slot_path(slot) + ".bak")
		if bool(alt["ok"]):
			push_warning("[SaveSystem] slot %d damaged (%s) - using the backup copy" % [slot, res["error"]])
			Game.notify("Save file damaged - loaded the backup copy.", &"warn")
			res = alt
	if not bool(res["ok"]):
		last_error = String(res["error"])
		push_warning("[SaveSystem] cannot load slot %d: %s" % [slot, last_error])
		if has_save(slot):
			Game.notify("Save file is damaged and could not be loaded (%s)." % last_error, &"bad")
		else:
			Game.notify("No saved game in this slot.", &"warn")
		load_finished.emit(slot, false)
		return false
	is_loading = true
	_apply_load.call_deferred(slot, res["data"])
	return true


## Awaitable version: `var ok: bool = await SaveSystem.load_game_async(0)`
func load_game_async(slot: int = 0) -> bool:
	if not load_game(slot):
		return false
	var result: Array = await load_finished
	return bool(result[1]) if result.size() > 1 else false


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found", "data": {}}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot open (%s)" % error_string(FileAccess.get_open_error()), "data": {}}
	var text := f.get_as_text()
	f.close()
	if text.strip_edges().is_empty():
		return {"ok": false, "error": "file is empty", "data": {}}
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {"ok": false, "error": "invalid JSON at line %d (%s)" % [json.get_error_line(), json.get_error_message()], "data": {}}
	if not (json.data is Dictionary):
		return {"ok": false, "error": "not a save file", "data": {}}
	var d: Dictionary = SaveCodec.decode(json.data)
	if not d.has("version") or not d.has("player"):
		return {"ok": false, "error": "missing save header", "data": {}}
	if int(d["version"]) > VERSION:
		push_warning("[SaveSystem] save version %d is newer than this build (%d) - trying anyway" % [int(d["version"]), VERSION])
	return {"ok": true, "error": "", "data": d}


func _apply_load(slot: int, d: Dictionary) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("fade"):
		await ui.fade(true, FADE_OUT)
	_reset_dynamic_world()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_restore(d)
	# the world may have to stream / settle around the new position; give the systems two frames (14.6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _restore_vehicle(d.get("vehicle", {}))
	last_slot = slot
	is_loading = false
	Events.load_completed.emit()
	load_finished.emit(slot, true)
	if ui != null and is_instance_valid(ui) and ui.has_method("fade"):
		ui.fade(false, FADE_IN)


## Despawns / clears everything that is not part of the save: traffic, pedestrians, police, dropped pickups, the previous player vehicle.
func _reset_dynamic_world() -> void:
	var p = Game.player
	if p != null and is_instance_valid(p):
		if p.is_in_vehicle():
			var cv = p.current_vehicle
			if cv != null and cv.has_method("exit"):
				cv.exit(p, true)
		if p.get("traversal") != null:
			p.traversal.cancel()
		if p.get("is_dead") == true or p.get("move_mode") == Player.Move.BUSTED:
			if p.has_method("respawn_at"):
				p.respawn_at(&"player_spawn", {"silent": true, "penalty": 0})       # resets the death screen / time scale too
			elif p.has_method("revive"):
				p.revive()
	for key in [&"police", &"traffic", &"peds", &"wildlife", &"emergency"]:
		var s = Game.sys(key)
		if s == null:
			continue
		for m in ["despawn_all", "clear_all", "reset"]:
			if s.has_method(m):
				s.call(m)
				break
	var wanted = Game.sys(&"wanted")
	if wanted != null and wanted.has_method("clear"):
		wanted.clear()
	for n in get_tree().get_nodes_in_group(GC.G_PICKUP):     # loot dropped by NPCs
		if n.get("lifetime") != null and float(n.get("lifetime")) > 0.0:
			n.queue_free()
	for v in get_tree().get_nodes_in_group(GC.G_VEHICLE):    # the player's own vehicles are re-created from the save
		if is_instance_valid(v) and (v.get("is_player_owned") == true or v == p.get("last_vehicle") or v.has_meta(&"save_restored")):
			VehicleFactory.despawn(v)
	if p != null and p.get("last_vehicle") != null:
		p.last_vehicle = null


func _restore(d: Dictionary) -> void:
	var w = d.get("world", {})
	if w is Dictionary:
		Game.cash = int(w.get("cash", Game.cash))
		var env = Game.sys(&"environment")
		var hour := float(w.get("time_of_day", Game.time_of_day))
		if env != null and env.has_method("set_time"):
			env.set_time(hour)
		else:
			Game.time_of_day = hour
		var weather := StringName(String(w.get("weather", "clear")))
		if env != null and env.has_method("set_weather"):
			env.set_weather(weather, true)
		else:
			Game.weather = weather
		var wanted = Game.sys(&"wanted")
		if wanted != null:
			if bool(Game.settings.get("restore_wanted", false)) and int(w.get("wanted_level", 0)) > 0 and wanted.has_method("set_level"):
				wanted.set_level(int(w["wanted_level"]))
			elif wanted.has_method("clear"):
				wanted.clear()
	var flag_data = d.get("flags", {})
	if flag_data is Dictionary:
		flags = (flag_data as Dictionary).duplicate(true)
	var systems = d.get("systems", {})
	if systems is Dictionary:
		for key in systems:
			var node = Game.systems.get(StringName(key), null)
			if node != null and is_instance_valid(node) and node.has_method("deserialize") and systems[key] is Dictionary:
				node.deserialize(systems[key])
	var p = Game.player
	var pd = d.get("player", {})
	if p != null and pd is Dictionary and not (pd as Dictionary).is_empty():
		p.deserialize(pd)
		var ex = d.get("player_extra", {})
		if ex is Dictionary:
			if (ex as Dictionary).has("has_scuba") and p.get("has_scuba") != null:
				p.set("has_scuba", bool(ex["has_scuba"]))
			var look = ex.get("appearance", null)
			if look is Dictionary and p.get("rig") != null and p.rig.has_method("setup"):
				p.rig.setup(look)
		if is_instance_valid(p.get("camera")):
			p.camera.snap_behind(p.rotation.y)
		p.spawn_protection = 1.5


func _restore_vehicle(vd: Variant) -> void:
	if not (vd is Dictionary) or (vd as Dictionary).is_empty():
		return
	var p = Game.player
	if p == null or not is_instance_valid(p) or not (vd.get("xf") is Transform3D):
		return
	var id := StringName(String(vd.get("id", "")))
	if not VehicleDefs.has(id):
		return
	var xf: Transform3D = vd["xf"]
	var opts := {"abandoned": true, "snap_ground": false, "health_ratio": float(vd.get("health_ratio", 1.0)),
		"engine_on": false, "owned": bool(vd.get("owned", false))}
	if vd.get("paint") is Color:
		opts["paint"] = vd["paint"]
	if vd.get("paint2") is Color:
		opts["paint2"] = vd["paint2"]
	if String(vd.get("finish", "")) != "":
		opts["finish"] = StringName(String(vd["finish"]))
	if vd.get("mods") is Dictionary and not (vd["mods"] as Dictionary).is_empty():
		opts["mods"] = vd["mods"]
	# the Garage may already have re-created the vehicle: reuse a matching one at the same spot
	var veh: Node = null
	for o in get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if is_instance_valid(o) and o.get("def_id") == id and (o as Node3D).global_position.distance_to(xf.origin) < 4.0:
			veh = o
			break
	if veh == null:
		veh = VehicleFactory.spawn(id, xf, opts)
	if veh == null:
		return
	veh.set_meta(&"save_restored", true)
	if bool(vd.get("inside", false)):
		await get_tree().physics_frame
		await get_tree().physics_frame
		p.enter_vehicle(veh, 0)


# ====================================================================================================== settings
func load_settings() -> void:
	for k in EXTRA_SETTINGS:
		if not Game.settings.has(k):
			Game.settings[k] = EXTRA_SETTINGS[k]
	_settings_loaded = true
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_warning("[SaveSystem] settings.json is damaged - using defaults")
		return
	var src: Dictionary = json.data
	for k in src:
		var val = src[k]
		if not (val is bool or val is int or val is float or val is String):
			continue
		if Game.settings.has(k):
			var cur = Game.settings[k]
			if cur is bool:
				Game.settings[k] = bool(val)
			elif cur is int:
				Game.settings[k] = int(val)
			elif cur is float:
				Game.settings[k] = float(val)
			elif cur is String:
				Game.settings[k] = str(val)
			else:
				Game.settings[k] = val
		else:
			Game.settings[k] = val


func save_settings() -> void:
	_settings_timer = -1.0
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveSystem] cannot write settings.json")
		return
	f.store_string(JSON.stringify(_settings_snapshot(), "\t"))
	f.close()


func _on_settings_changed() -> void:
	if _settings_loaded and not _quiet_settings:
		_settings_timer = 1.5               # debounce: sliders emit on every step


## Tells Sfx / EnvironmentSystem / UI that the stored settings are now in Game.settings (they applied the defaults at their own boot).
func broadcast_settings() -> void:
	_quiet_settings = true
	Events.settings_changed.emit()
	_quiet_settings = false


func _on_save_requested() -> void:
	if not is_loading:
		save_game(0)


func _on_game_ready() -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("apply_settings"):
		ui.apply_settings()
	broadcast_settings()
