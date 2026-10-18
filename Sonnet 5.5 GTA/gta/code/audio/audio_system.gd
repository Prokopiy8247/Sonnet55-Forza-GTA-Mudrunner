class_name AudioSystem
extends Node
## Audio system: ambience beds (crossfaded by district / weather / time / altitude), scheduled ambient one-shots (gulls,
## birds, industrial clanks, ship horn, thunder, distant sirens), bus effects (underwater low-pass, menu / weapon-wheel /
## pause ducking, district reverb), the generative car radio and a few listener helpers. The sound bank and the pooled
## one-shot player live in the Sfx autoload; engine loops in EngineSound.
## Booted by Main: setup(main) once in boot order, post_setup() after all systems exist (kept signatures).
##
## Safety nets: when gameplay modules forget to play a sound, the matching Events (weapon_fired, explosion, collisions,
## deaths, vehicle doors, wanted changes ...) trigger it after a short check against Sfx.was_played_recently(), so nothing is
## doubled. Disable with `safety_net = false`.

const RadioPlayer = preload("res://gta/code/audio/radio_player.gd")

class Bed:
	extends RefCounted
	var key := ""
	var sound: StringName = &""
	var player: AudioStreamPlayer = null
	var vol := 0.0
	var target := 0.0
	var trim := 1.0
	var rate := 0.7


## [district weights] city traffic hum / industrial / crowd / crickets / leaves / reverb wet.
const DISTRICTS := {
	&"downtown": {"city": 1.0, "industrial": 0.0, "crowd": 1.0, "crickets": 0.1, "leaves": 0.05, "airport": 0.0, "wind": 0.0, "reverb": 0.15, "birds": 0.1},
	&"residential": {"city": 0.5, "industrial": 0.0, "crowd": 0.45, "crickets": 0.6, "leaves": 0.35, "airport": 0.0, "wind": 0.0, "reverb": 0.07, "birds": 0.7},
	&"industrial": {"city": 0.35, "industrial": 1.0, "crowd": 0.1, "crickets": 0.2, "leaves": 0.0, "airport": 0.1, "wind": 0.05, "reverb": 0.12, "birds": 0.05},
	&"waterfront": {"city": 0.3, "industrial": 0.45, "crowd": 0.25, "crickets": 0.3, "leaves": 0.0, "airport": 0.0, "wind": 0.15, "reverb": 0.07, "birds": 0.1},
	&"park_hills": {"city": 0.1, "industrial": 0.0, "crowd": 0.15, "crickets": 0.9, "leaves": 0.9, "airport": 0.0, "wind": 0.2, "reverb": 0.03, "birds": 1.0},
	&"airport": {"city": 0.2, "industrial": 0.1, "crowd": 0.1, "crickets": 0.2, "leaves": 0.0, "airport": 1.0, "wind": 0.2, "reverb": 0.05, "birds": 0.05},
	&"beach": {"city": 0.2, "industrial": 0.0, "crowd": 0.7, "crickets": 0.5, "leaves": 0.0, "airport": 0.0, "wind": 0.1, "reverb": 0.03, "birds": 0.15},
	&"sea": {"city": 0.0, "industrial": 0.0, "crowd": 0.0, "crickets": 0.0, "leaves": 0.0, "airport": 0.0, "wind": 0.25, "reverb": 0.02, "birds": 0.0},
}
const DEFAULT_DISTRICT := {"city": 0.4, "industrial": 0.0, "crowd": 0.3, "crickets": 0.4, "leaves": 0.2, "airport": 0.0, "wind": 0.1, "reverb": 0.06, "birds": 0.4}

## Bed key -> [sound id, trim (linear), fade rate per second]
const BEDS := {
	"city": [&"amb_city", 0.85, 0.5],
	"wind": [&"amb_wind", 0.75, 0.6],
	"sea": [&"amb_sea", 0.95, 0.45],
	"rain_light": [&"amb_rain_light", 0.8, 0.5],
	"rain_heavy": [&"amb_rain_heavy", 0.9, 0.5],
	"industrial": [&"amb_industrial", 0.8, 0.5],
	"leaves": [&"amb_leaves", 0.7, 0.5],
	"crickets": [&"amb_crickets", 0.6, 0.4],
	"crowd": [&"amb_crowd", 0.8, 0.5],
	"airport": [&"amb_airport", 0.7, 0.4],
	"underwater": [&"amb_underwater", 0.9, 2.5],
}
const WEAPON_SOUNDS := {
	&"pistol": &"shot_pistol", &"revolver": &"shot_revolver", &"smg": &"shot_smg", &"shotgun_pump": &"shot_shotgun",
	&"shotgun_auto": &"shot_shotgun", &"rifle_assault": &"shot_rifle", &"carbine": &"shot_rifle", &"rifle_marksman": &"shot_rifle",
	&"sniper": &"shot_sniper", &"rocket_launcher": &"shot_rocket", &"grenade_launcher": &"shot_rocket",
	&"fists": &"melee_swing", &"knife": &"melee_swing", &"bat": &"melee_swing", &"crowbar": &"melee_swing",
}
## Buses that follow the underwater / menu / pause / weapon-wheel processing.
const FX_BUSES := ["SFX", "Engine", "Voice", "Ambience", "Music"]

var safety_net := true
var auto_engine_sounds := true
var radio: Node = null

var _beds: Dictionary = {}
var _think_t := 0.0
var _ctx := {"district": &"", "sea": 0.0, "night": 0.0, "peds": 0, "cabin": 0.0, "altitude": 0.0, "rain": 0.0, "storm": false, "wanted": 0}
var _underwater_manual := false
var _underwater_cam := false
var _uw := 0.0
var _menus: Dictionary = {}
var _wheel_open := false
var _paused := false
var _duck_keys: Dictionary = {}
var _duck_cur: Dictionary = {}
var _cut_cur: Dictionary = {}
var _space: StringName = &"auto"
var _reverb_wet := 0.07
var _reverb_room := 0.35
var _next_t: Dictionary = {}
var _last_wanted := 0
var _main: Node = null
var _siren_players: Dictionary = {}     # vehicle instance id -> AudioStreamPlayer3D
var _siren_seen: Dictionary = {}        # vehicle instance id -> time siren_on was first seen
var _clock := 0.0
var _engines: Dictionary = {}           # vehicle instance id -> EngineSound created by us
var _scan_t := 0.0
var _foreign_engine_seen := false
var _t0 := 0.0
var _distant_nodes: Array = []


func setup(main: Node) -> void:
	_main = main
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "Audio"
	for k in BEDS:
		var def: Array = BEDS[k]
		var b := Bed.new()
		b.key = k
		b.sound = def[0]
		b.trim = float(def[1])
		b.rate = float(def[2])
		_beds[k] = b
	for bus in FX_BUSES:
		_duck_cur[bus] = 0.0
		_cut_cur[bus] = 20000.0
	var rp := RadioPlayer.new()
	rp.name = "Radio"
	add_child(rp)
	rp.setup()
	radio = rp
	_t0 = Time.get_ticks_msec() / 1000.0
	Events.menu_opened.connect(func(id: StringName) -> void: _menus[id] = true)
	Events.menu_closed.connect(func(id: StringName) -> void: _menus.erase(id))
	Events.game_paused.connect(func(p: bool) -> void: _paused = p)
	Events.wanted_changed.connect(_on_wanted_changed)
	Events.explosion.connect(_on_explosion)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.vehicle_collision.connect(_on_vehicle_collision)
	Events.character_died.connect(_on_character_died)
	Events.character_damaged.connect(_on_character_damaged)
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.vehicle_exited.connect(_on_vehicle_exited)
	Events.vehicle_horn.connect(_on_vehicle_horn)
	Events.player_busted.connect(func() -> void: _safety_ui(&"ui_busted"))
	Events.player_died.connect(func() -> void: _safety_ui(&"ui_wasted"))
	Events.pickup_collected.connect(func(_k: StringName, _a: int) -> void: _safety_flat(&"pickup"))


func post_setup() -> void:
	_last_wanted = int(Game.wanted_level)


# =========================================================================================================
# Public helpers
# =========================================================================================================
func get_listener_position() -> Vector3:
	return Sfx.listener_pos


func get_listener_forward() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return -cam.global_transform.basis.z
	return Vector3(0, 0, -1)


## Random point around the listener (distance min_d..max_d on the ground plane, plus a height range) - handy for
## ambient one-shots and off-screen sounds.
func position_around_listener(min_d: float, max_d: float, height_min: float = 0.0, height_max: float = 0.0) -> Vector3:
	var a := randf() * TAU
	var d := lerpf(min_d, max_d, randf())
	return Sfx.listener_pos + Vector3(cos(a) * d, lerpf(height_min, height_max, randf()), sin(a) * d)


## EnvironmentSystem asks this to decide whether it must run its own rain loop: AudioSystem owns all weather ambience.
func handles_weather_audio() -> bool:
	return true


## Muffles the whole world (swimming below the surface). Also detected automatically when the camera is below sea level.
func set_underwater(on: bool) -> void:
	_underwater_manual = on


func is_underwater() -> bool:
	return _underwater_manual or _underwater_cam


## Acoustic space of the listener: &"auto" (district based), &"open", &"street", &"interior", &"garage", &"tunnel".
func set_space(space: StringName) -> void:
	_space = space


func get_space() -> StringName:
	return _space


## Generic ducking hook for other modules: strength 0..1 pulls SFX/engine/ambience down and darkens them (0 = release).
func set_duck(key: StringName, strength: float) -> void:
	if strength <= 0.001:
		_duck_keys.erase(key)
	else:
		_duck_keys[key] = clampf(strength, 0.0, 1.0)


# ---- radio API ---------------------------------------------------------------------------------------------------------
func radio_next() -> void:
	if radio != null:
		radio.next_station()


func radio_prev() -> void:
	if radio != null:
		radio.prev_station()


func set_station(station: Variant) -> bool:
	return radio != null and radio.set_station(StringName(station))


func get_station() -> StringName:
	return radio.current if radio != null else &"off"


func get_station_name(station: StringName = &"") -> String:
	if radio == null:
		return ""
	return radio.get_display_name(radio.current if station == &"" else station)


func get_stations() -> Array[StringName]:
	return radio.get_station_ids() if radio != null else ([] as Array[StringName])


func radio_off() -> void:
	if radio != null:
		radio.radio_off()


func is_radio_playing() -> bool:
	return radio != null and radio.is_playing()


## {station, name, tagline, playing, stations: [{id, name, tagline}]} for HUD / radio wheel widgets.
func get_radio_info() -> Dictionary:
	var list: Array = []
	if radio != null:
		for sid in radio.get_station_ids():
			list.append({"id": sid, "name": radio.get_display_name(sid), "tagline": radio.get_tagline(sid)})
	return {"station": get_station(), "name": get_station_name(), "tagline": radio.get_tagline(get_station()) if radio != null else "", "playing": is_radio_playing(), "stations": list}


# ---- one-shot helpers -------------------------------------------------------------------------------------------------
## Attaches a procedural EngineSound to a vehicle (profile guessed from vehicle.def_id) and returns it.
func attach_engine_sound(vehicle: Node3D, profile: StringName = &"") -> EngineSound:
	var prof := profile if profile != &"" else EngineSound.profile_for(StringName(vehicle.get("def_id")))
	var snd := EngineSound.create(prof)
	snd.name = "EngineSound"
	vehicle.add_child(snd)
	return snd


## A siren source passing by at a distance (sweeps 70 m past the listener over ~6 s). kind: police | ambulance | fire.
func play_distant_siren(kind: StringName = &"police") -> void:
	var sid := &"siren_police"
	match String(kind):
		"ambulance":
			sid = &"siren_ambulance"
		"fire":
			sid = &"siren_fire"
	var a := randf() * TAU
	var d := randf_range(110.0, 210.0)
	var dir := Vector3(cos(a), 0.0, sin(a))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var start := Sfx.listener_pos + dir * d - side * 50.0 + Vector3(0, 1.5, 0)
	var marker := Node3D.new()
	marker.name = "DistantSiren"
	add_child(marker)
	marker.global_position = start
	var tw := create_tween()
	tw.tween_property(marker, "global_position", start + side * 100.0, 6.5)
	tw.tween_callback(marker.queue_free)
	Sfx.play_3d(sid, start, -2.0, 1.0, 380.0, marker)


## Distant thunder (random direction). `close` makes it loud and nearby.
func trigger_thunder(close: bool = false) -> void:
	var d := randf_range(40.0, 120.0) if close else randf_range(250.0, 600.0)
	var pos := position_around_listener(d, d, 40.0, 120.0)
	Sfx.play_3d(&"thunder", pos, 0.0 if close else -3.0, randf_range(0.9, 1.05), 900.0)


func get_status() -> Dictionary:
	var beds := {}
	for k in _beds:
		beds[k] = snappedf((_beds[k] as Bed).vol, 0.01)
	return {"district": _ctx["district"], "sea": _ctx["sea"], "night": _ctx["night"], "underwater": is_underwater(), "beds": beds,
		"radio": get_station(), "radio_playing": is_radio_playing(), "reverb_wet": _reverb_wet, "sfx": Sfx.stats()}


# =========================================================================================================
# Frame update
# =========================================================================================================
func _process(delta: float) -> void:
	_clock += delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.35
		_think()
	_update_beds(delta)
	_update_buses(delta)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.6
		_scan_vehicles()
		_ambient_events()
	if auto_engine_sounds and not _engines.is_empty():
		_drive_auto_engines()


func _player_pos() -> Vector3:
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return Sfx.listener_pos


func _think() -> void:
	var pp := _player_pos()
	var district: StringName = Game.get_district(pp)
	_ctx["district"] = district
	# coast proximity from water queries on 3 rings x 8 directions
	var sea := 0.0
	var rings := [[22.0, 0.6], [55.0, 0.5], [110.0, 0.35]]
	for r in rings:
		var cnt := 0
		for k in 8:
			var a := float(k) * TAU / 8.0
			if WorldLayout.is_water(pp.x + cos(a) * float(r[0]), pp.z + sin(a) * float(r[0])):
				cnt += 1
		sea += float(cnt) / 8.0 * float(r[1])
	sea = clampf(sea * 1.3, 0.0, 1.0)
	if district == GC.D_SEA:
		sea = 1.0
	_ctx["sea"] = lerpf(float(_ctx["sea"]), sea, 0.6)
	_ctx["night"] = 1.0 - Game.daylight()
	_ctx["rain"] = clampf(float(Game.rain_intensity), 0.0, 1.0)
	if Game.weather == GC.W_RAIN:
		_ctx["rain"] = maxf(float(_ctx["rain"]), 0.45)
	elif Game.weather == GC.W_STORM:
		_ctx["rain"] = maxf(float(_ctx["rain"]), 0.9)
	_ctx["storm"] = Game.weather == GC.W_STORM
	_ctx["wanted"] = int(Game.wanted_level)
	_ctx["altitude"] = clampf((Sfx.listener_pos.y - 14.0) / 70.0, 0.0, 1.0) if Sfx.listener_valid else 0.0
	var cabin := 0.0
	if is_instance_valid(Game.player):
		var cv = Game.player.get("current_vehicle")
		if cv != null and is_instance_valid(cv):
			cabin = 1.0
	_ctx["cabin"] = cabin
	# pedestrians nearby (crowd murmur)
	var peds := 0
	for n in get_tree().get_nodes_in_group(GC.G_PED):
		if n is Node3D and (n as Node3D).global_position.distance_squared_to(pp) < 26.0 * 26.0:
			peds += 1
	_ctx["peds"] = peds
	# camera below the sea surface?
	_underwater_cam = false
	if Sfx.listener_valid and Sfx.listener_pos.y < GC.WATER_LEVEL - 0.1:
		_underwater_cam = WorldLayout.is_water(Sfx.listener_pos.x, Sfx.listener_pos.z)
	_weapon_wheel_check()
	_compute_bed_targets()
	_compute_reverb_target()


func _weapon_wheel_check() -> void:
	_wheel_open = InputMap.has_action(&"weapon_wheel") and Input.is_action_pressed(&"weapon_wheel") and is_instance_valid(Game.player)
	# the menu_opened / menu_closed events are the primary signal; ask the UI too in case a menu skipped them
	var ui_open: bool = is_instance_valid(Game.ui) and Game.ui.has_method("is_menu_open") and bool(Game.ui.is_menu_open())
	if ui_open:
		_menus[&"__ui"] = true
	else:
		_menus.erase(&"__ui")


func _district_w(key: String) -> float:
	var d: Dictionary = DISTRICTS.get(_ctx["district"], DEFAULT_DISTRICT)
	return float(d.get(key, 0.0))


func _compute_bed_targets() -> void:
	var uw: float = 1.0 if is_underwater() else 0.0
	var surface: float = 1.0 - uw
	var cabin: float = float(_ctx["cabin"])
	var night: float = float(_ctx["night"])
	var rain: float = float(_ctx["rain"])
	var sea: float = float(_ctx["sea"])
	var day_gain: float = 1.0 - 0.5 * night
	var cabin_gain: float = 1.0 - 0.5 * cabin
	var traffic_on: float = 1.0 if Game.cheats.get("traffic", true) else 0.6
	var city: float = _district_w("city") * traffic_on * (1.0 - 0.55 * sea) * day_gain
	var wind: float = 0.12 + _district_w("wind") + 0.28 * sea + float(_ctx["altitude"]) * 0.9
	match String(Game.weather):
		"cloudy":
			wind += 0.12
		"rain":
			wind += 0.18
		"storm":
			wind += 0.55
		"fog":
			wind += 0.04
	var leaves: float = _district_w("leaves") * (0.4 + clampf(wind, 0.0, 1.0)) * (1.0 - rain * 0.6)
	var crickets: float = _district_w("crickets") * clampf((night - 0.45) * 2.2, 0.0, 1.0) * (1.0 - rain * 0.8)
	var crowd: float = clampf(float(_ctx["peds"]) / 12.0, 0.0, 1.0) * _district_w("crowd") * (1.0 - 0.5 * night)
	var rain_l: float = clampf(rain * 3.0, 0.0, 1.0) * clampf(1.6 - rain * 1.5, 0.0, 1.0)
	var rain_h: float = clampf((rain - 0.35) * 2.2, 0.0, 1.0)
	var rain_gain: float = 1.0 - 0.35 * cabin
	_set_target("city", city * surface * cabin_gain)
	_set_target("wind", clampf(wind, 0.0, 1.0) * surface * (1.0 - 0.45 * cabin))
	_set_target("sea", clampf(sea * 1.2, 0.0, 1.0) * surface * cabin_gain)
	_set_target("rain_light", rain_l * surface * rain_gain)
	_set_target("rain_heavy", rain_h * surface * rain_gain)
	_set_target("industrial", _district_w("industrial") * surface * cabin_gain)
	_set_target("leaves", leaves * surface * cabin_gain)
	_set_target("crickets", crickets * surface * cabin_gain)
	_set_target("crowd", crowd * surface * cabin_gain)
	_set_target("airport", _district_w("airport") * surface * cabin_gain)
	_set_target("underwater", uw)


func _set_target(key: String, value: float) -> void:
	(_beds[key] as Bed).target = clampf(value, 0.0, 1.0)


func _update_beds(delta: float) -> void:
	for k in _beds:
		var b: Bed = _beds[k]
		var rate: float = b.rate * (1.0 if b.target >= b.vol else 1.3)
		b.vol = move_toward(b.vol, b.target, delta * rate)
		if b.vol > 0.004:
			if b.player == null:
				if not Sfx.is_sound_ready(b.sound):
					continue
				var w := Sfx.get_wav(b.sound, 0)
				if w == null:
					b.vol = 0.0
					continue
				b.player = AudioStreamPlayer.new()
				b.player.name = "Bed_" + b.key
				b.player.stream = w
				b.player.bus = "Ambience"
				add_child(b.player)
			if not b.player.playing:
				var len_s: float = (b.player.stream as AudioStreamWAV).get_length()
				b.player.play(randf() * len_s)
			b.player.volume_db = linear_to_db(b.vol * b.trim)
		elif b.player != null and b.player.playing:
			b.player.stop()


# ---- bus processing: underwater, menus, pause, weapon wheel, reverb ----------------------------------------------------
func _update_buses(delta: float) -> void:
	_uw = move_toward(_uw, 1.0 if is_underwater() else 0.0, delta * 4.0)
	var menu: float = 1.0 if not _menus.is_empty() else 0.0
	var wheel: float = 1.0 if _wheel_open else 0.0
	var pause: float = 1.0 if _paused else 0.0
	var extra := 0.0
	for k in _duck_keys:
		extra = maxf(extra, float(_duck_keys[k]))
	for bus in FX_BUSES:
		var db := 0.0
		var cut := 20000.0
		# every contribution is "the strongest wins" (not summed) so stacked states never over-duck
		var d_menu := 0.0
		var c_menu := 20000.0
		match bus:
			"SFX":
				d_menu = -6.0
				c_menu = 3200.0
			"Engine":
				d_menu = -10.0
				c_menu = 2600.0
			"Voice":
				d_menu = -3.0
				c_menu = 6000.0
			"Ambience":
				d_menu = -9.0
				c_menu = 2400.0
			"Music":
				d_menu = -2.0
				c_menu = 7000.0
		db = minf(db, d_menu * menu)
		db = minf(db, d_menu * 0.5 * wheel)
		db = minf(db, d_menu * 1.6 * pause)
		db = minf(db, d_menu * extra)
		if menu > 0.5:
			cut = minf(cut, c_menu)
		if wheel > 0.5:
			cut = minf(cut, c_menu * 1.8)
		if pause > 0.5:
			cut = minf(cut, 1800.0)
		if extra > 0.3:
			cut = minf(cut, lerpf(20000.0, c_menu, extra))
		# underwater
		var uw_db: float = -4.0 if bus != "Ambience" else 0.0
		db = minf(db, uw_db * _uw)
		cut = minf(cut, 20000.0 * pow(680.0 / 20000.0, _uw))
		_duck_cur[bus] = Util.damp(float(_duck_cur[bus]), db, 6.0, delta)
		Sfx.set_bus_duck(bus, float(_duck_cur[bus]))
		var lc: float = exp(Util.damp(log(float(_cut_cur[bus])), log(cut), 7.0, delta))
		_cut_cur[bus] = lc
		var fx: Dictionary = Sfx.get_bus_fx(bus)
		if fx.has("lp"):
			var idx := AudioServer.get_bus_index(bus)
			var eidx: int = int(fx["lp_idx"])
			var on: bool = lc < 18500.0
			if on:
				(fx["lp"] as AudioEffectLowPassFilter).cutoff_hz = lc
			if AudioServer.is_bus_effect_enabled(idx, eidx) != on:
				AudioServer.set_bus_effect_enabled(idx, eidx, on)
	# reverb send follows the acoustic space
	var fx2: Dictionary = Sfx.get_bus_fx("SFX")
	if fx2.has("reverb"):
		var rv: AudioEffectReverb = fx2["reverb"]
		_reverb_wet = Util.damp(_reverb_wet, _target_wet, 2.0, delta)
		_reverb_room = Util.damp(_reverb_room, _target_room, 2.0, delta)
		rv.wet = _reverb_wet
		rv.room_size = _reverb_room


var _target_wet := 0.07
var _target_room := 0.35


func _compute_reverb_target() -> void:
	match String(_space):
		"interior":
			_target_wet = 0.22
			_target_room = 0.55
		"garage":
			_target_wet = 0.3
			_target_room = 0.75
		"tunnel":
			_target_wet = 0.38
			_target_room = 0.85
		"street":
			_target_wet = 0.14
			_target_room = 0.5
		"open":
			_target_wet = 0.03
			_target_room = 0.3
		_:
			_target_wet = _district_w("reverb")
			_target_room = 0.3 + _district_w("reverb") * 2.0
	if is_instance_valid(Game.player):
		var cv = Game.player.get("current_vehicle")
		if cv != null and is_instance_valid(cv):
			_target_wet *= 0.4
	_target_wet *= 1.0 + float(_ctx["rain"]) * 0.4


# ---- scheduled ambient one-shots ----------------------------------------------------------------------------------------
func _due(key: String, lo: float, hi: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if not _next_t.has(key):
		_next_t[key] = now + randf_range(lo * 0.3, hi * 0.6)
		return false
	if now < float(_next_t[key]):
		return false
	_next_t[key] = now + randf_range(lo, hi)
	return true


func _ambient_events() -> void:
	if not Sfx.listener_valid or is_underwater() or _paused:
		return
	var hour: float = Game.time_of_day
	var day: bool = hour > 5.8 and hour < 20.2
	var rain: float = float(_ctx["rain"])
	var sea: float = float(_ctx["sea"])
	var cabin_db: float = -6.0 * float(_ctx["cabin"])
	if day and sea > 0.25 and rain < 0.6 and _due("gull", 7.0, 20.0):
		Sfx.play_3d(&"gull", position_around_listener(25.0, 85.0, 8.0, 28.0), -3.0 + cabin_db, randf_range(0.9, 1.15), 170.0)
	var birds_w: float = _district_w("birds")
	if day and birds_w > 0.3 and rain < 0.5 and _due("bird", 2.5 / birds_w, 9.0 / birds_w):
		Sfx.play_3d(&"bird", position_around_listener(10.0, 42.0, 3.0, 14.0), -4.0 + cabin_db, randf_range(0.85, 1.25), 90.0)
	if _district_w("industrial") > 0.4 and _due("clank", 4.0, 13.0):
		Sfx.play_3d(&"clank", position_around_listener(30.0, 90.0, 0.0, 6.0), -5.0 + cabin_db, randf_range(0.8, 1.2), 160.0)
	if (sea > 0.2 or _district_w("industrial") > 0.3) and _due("ship", 70.0, 160.0):
		var away := Vector3(randf_range(-0.6, 0.6), 0.0, 1.0).normalized()
		Sfx.play_3d(&"ship_horn", Sfx.listener_pos + away * randf_range(150.0, 260.0), -2.0 + cabin_db, randf_range(0.9, 1.1), 420.0)
	# lightning + thunder belong to EnvironmentSystem (it plays 'thunder' in sync with the flash); only fill in when it cannot
	var env = Game.sys(&"environment")
	var env_handles_thunder: bool = env != null and env.has_signal("lightning_struck")
	if not env_handles_thunder:
		if bool(_ctx["storm"]) and _due("thunder_storm", 9.0, 26.0):
			trigger_thunder(randf() < 0.18)
		elif rain > 0.65 and _due("thunder_rain", 35.0, 80.0):
			trigger_thunder(false)
	# distant sirens: rare ambience in the city, frequent while the player is wanted
	var wanted: int = int(_ctx["wanted"])
	var cityish: float = maxf(_district_w("city"), _district_w("crowd"))
	if wanted > 0 and _due("siren_w", 11.0, 26.0):
		play_distant_siren(&"police")
	elif wanted == 0 and cityish > 0.3 and _due("siren_r", 80.0, 190.0):
		var r := randf()
		play_distant_siren(&"police" if r < 0.55 else (&"ambulance" if r < 0.85 else &"fire"))


# ---- vehicle scanning (sirens, fallback engine sounds) ------------------------------------------------------------------
func _scan_vehicles() -> void:
	if not Sfx.listener_valid:
		return
	var vehicles := get_tree().get_nodes_in_group(GC.G_VEHICLE)
	var seen := {}
	for v in vehicles:
		if not (v is Node3D) or not is_instance_valid(v):
			continue
		var vid: int = (v as Node).get_instance_id()
		seen[vid] = true
		var d2: float = (v as Node3D).global_position.distance_squared_to(Sfx.listener_pos)
		var siren_on = v.get("siren_on")
		if siren_on != null and bool(siren_on) and d2 < 260.0 * 260.0 and not bool(v.get("is_destroyed")):
			# give the vehicle module time to attach its own siren first (it does so the frame siren_on turns true)
			if not _siren_seen.has(vid):
				_siren_seen[vid] = _clock
			elif _clock - float(_siren_seen[vid]) > 1.2 and not _siren_players.has(vid) and not _has_siren_player(v):
				_start_siren(v, vid)
		else:
			_siren_seen.erase(vid)
			if _siren_players.has(vid):
				_stop_siren(vid)
		if auto_engine_sounds and not _foreign_engine_seen:
			_maybe_attach_engine(v, vid, d2)
	for vid in _siren_players.keys():
		if not seen.has(vid):
			_stop_siren(vid)
	for vid in _siren_seen.keys():
		if not seen.has(vid):
			_siren_seen.erase(vid)
	for vid in _engines.keys():
		if not seen.has(vid) or not is_instance_valid(_engines[vid]):
			_engines.erase(vid)


func _has_siren_player(v: Node) -> bool:
	for c in v.get_children():
		if c is AudioStreamPlayer3D and c.stream != null and String((c.stream as AudioStream).resource_name).begins_with("siren"):
			return true
	return false


func _start_siren(v: Node, vid: int) -> void:
	var sid := &"siren_police"
	var def: String = String(v.get("def_id"))
	var fac = v.get("faction")
	if def.contains("ambulance"):
		sid = &"siren_ambulance"
	elif def.contains("fire"):
		sid = &"siren_fire"
	elif fac != null and StringName(fac) == GC.F_POLICE and Game.wanted_state == &"pursuit" and randf() < 0.45:
		sid = &"siren_police_yelp"
	var p := Sfx.create_player_3d(sid, v, -3.0, 320.0, true)
	if p != null:
		p.name = "SirenAudio"
		p.unit_size = 40.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p.play(randf() * (p.stream as AudioStreamWAV).get_length())
		_siren_players[vid] = p


func _stop_siren(vid: int) -> void:
	var p = _siren_players.get(vid)
	_siren_players.erase(vid)
	if p != null and is_instance_valid(p):
		p.stop()
		p.queue_free()


func _vehicle_has_engine_sound(v: Node) -> bool:
	for c in v.get_children():
		if c is EngineSound:
			return true
		for g in c.get_children():
			if g is EngineSound:
				return true
	return false


func _maybe_attach_engine(v: Node, vid: int, d2: float) -> void:
	if _engines.has(vid):
		return
	var eo = v.get("engine_on")
	if eo == null or not bool(eo) or d2 > 110.0 * 110.0:
		return
	if _vehicle_has_engine_sound(v):
		# another module drives engine sounds: stand down for good once the world has been running a while
		for ov in _engines.values():
			if is_instance_valid(ov):
				ov.queue_free()
		_engines.clear()
		_foreign_engine_seen = true
		return
	var vc = v.get("vclass")
	if vc != null and StringName(vc) == GC.VC_BICYCLE:
		return
	var snd := attach_engine_sound(v as Node3D)
	snd.set_meta("auto_engine", true)
	_engines[vid] = snd


func _drive_auto_engines() -> void:
	for vid in _engines:
		var snd: EngineSound = _engines[vid]
		if not is_instance_valid(snd):
			continue
		var v := snd.get_parent()
		if v == null:
			continue
		var eo = v.get("engine_on")
		if eo == null or not bool(eo):
			if snd.running:
				snd.stop()
			continue
		var speed: float = 0.0
		var gs = v.call("get_speed") if v.has_method("get_speed") else 0.0
		speed = float(gs) * 3.6
		var thr: float = float(v.get("input_throttle")) if v.get("input_throttle") != null else 0.0
		var vclass := StringName(v.get("vclass")) if v.get("vclass") != null else GC.VC_CAR
		var rpm := 0.0
		if vclass == GC.VC_HELI:
			rpm = 0.55 + 0.4 * clampf(absf(float(v.get("input_collective")) if v.get("input_collective") != null else 0.0), 0.0, 1.0)
			thr = clampf(0.4 + 0.6 * float(v.get("input_collective") if v.get("input_collective") != null else 0.0), 0.0, 1.0)
		elif vclass == GC.VC_PLANE:
			rpm = clampf(0.3 + 0.7 * thr, 0.0, 1.0)
		else:
			# crude gearbox: rpm saw-tooths between gears so the pitch rises and falls like a real car
			var gear_w: float = 34.0
			var gear: float = clampf(floorf(speed / gear_w), 0.0, 4.0)
			var in_gear: float = (speed - gear * gear_w) / gear_w
			rpm = 0.1 + 0.18 * thr + 0.6 * clampf(in_gear, 0.0, 1.0) * (0.55 + 0.45 * thr)
			if gear >= 4.0:
				rpm = 0.45 + 0.35 * clampf((speed - 4.0 * gear_w) / 80.0, 0.0, 1.0)
		snd.update(clampf(rpm, 0.0, 1.0), clampf(thr, 0.0, 1.0))


# =========================================================================================================
# Safety-net event handlers (play a sound only if gameplay code has not already)
# =========================================================================================================
func _safety_ui(sound: StringName) -> void:
	if not safety_net:
		return
	await get_tree().process_frame
	if not Sfx.was_played_recently(sound, Vector3.ZERO, 0.5, 0.0):
		Sfx.play_ui(sound)


func _safety_flat(sound: StringName) -> void:
	if not safety_net:
		return
	await get_tree().process_frame
	if not Sfx.was_played_recently(sound, Vector3.ZERO, 0.3, 0.0):
		Sfx.play_2d(sound)


func _on_wanted_changed(level: int, _state: StringName) -> void:
	var prev := _last_wanted
	_last_wanted = level
	if not safety_net or level == prev:
		return
	var sid := &"ui_wanted_up" if level > prev else &"ui_wanted_down"
	await get_tree().process_frame
	if not Sfx.was_played_recently(&"ui_wanted_up", Vector3.ZERO, 0.6, 0.0) and not Sfx.was_played_recently(&"ui_wanted_down", Vector3.ZERO, 0.6, 0.0):
		Sfx.play_ui(sid)


func _on_explosion(pos: Vector3, radius: float, _source: Node) -> void:
	if not safety_net:
		return
	await get_tree().process_frame
	if Sfx.was_played_recently(&"explosion", pos, 0.4, 60.0):
		return
	Sfx.play_3d(&"explosion_big" if radius > 7.0 else &"explosion_small", pos, 0.0, 1.0, 450.0)


func _on_weapon_fired(character: Node, weapon_id: StringName) -> void:
	if not safety_net or not is_instance_valid(character) or not (character is Node3D):
		return
	var sid: StringName = WEAPON_SOUNDS.get(weapon_id, &"")
	if sid == &"":
		return
	var pos: Vector3 = (character as Node3D).global_position + Vector3(0, 1.4, 0)
	await get_tree().process_frame
	if sid == &"melee_swing":
		if not Sfx.was_played_recently(&"melee", pos, 0.2, 6.0):
			Sfx.play_3d(sid, pos, 0.0, 1.0, 40.0)
		return
	if Sfx.was_played_recently(&"weapon", pos, 0.12, 14.0):
		return
	Sfx.play_3d(sid, pos, 0.0, 1.0, 260.0)


func _on_vehicle_collision(vehicle: Node, _other: Node, impulse: float) -> void:
	if not safety_net or not is_instance_valid(vehicle) or not (vehicle is Node3D) or impulse < 2500.0:
		return
	var pos: Vector3 = (vehicle as Node3D).global_position
	await get_tree().process_frame
	if Sfx.was_played_recently(&"crash_light", pos, 0.3, 14.0) or Sfx.was_played_recently(&"crash_heavy", pos, 0.3, 14.0):
		return
	Sfx.play_3d(&"crash_heavy" if impulse > 9000.0 else &"crash_light", pos, 0.0 if impulse > 9000.0 else -2.0, 1.0, 150.0)


func _is_female(character: Node) -> bool:
	var v = character.get("variant")
	if v is Dictionary:
		return StringName(v.get("body", &"A")) == &"B"
	var rig = character.get("rig")
	if rig != null and is_instance_valid(rig):
		var rv = rig.get("variant")
		if rv is Dictionary:
			return StringName(rv.get("body", &"A")) == &"B"
	return (character.get_instance_id() % 3) == 0


func _on_character_died(character: Node, _killer: Node, info: Dictionary) -> void:
	if not safety_net or not is_instance_valid(character) or not (character is Node3D):
		return
	var pos: Vector3 = (character as Node3D).global_position + Vector3(0, 1.2, 0)
	var female := _is_female(character)          # read BEFORE the await: the node may be freed a frame later
	await get_tree().process_frame
	if Sfx.was_played_recently(&"voice", pos, 0.5, 6.0):
		return
	var dt: StringName = StringName(info.get("type", &""))
	if dt == GC.DMG_DROWN:
		return
	Sfx.play_3d(&"death_f" if female else &"death_m", pos, 0.0, 1.0, 70.0)


func _on_character_damaged(character: Node, amount: float, info: Dictionary) -> void:
	if not safety_net or amount < 2.0 or not is_instance_valid(character) or not (character is Node3D):
		return
	if bool(character.get("is_dead")):
		return
	var pos: Vector3 = (character as Node3D).global_position + Vector3(0, 1.2, 0)
	var dt: StringName = StringName(info.get("type", &""))
	var female := _is_female(character)          # read BEFORE the await: the node may be freed a frame later
	await get_tree().process_frame
	if not Sfx.was_played_recently(&"impact", pos, 0.15, 5.0) and (dt == GC.DMG_BULLET or dt == GC.DMG_MELEE):
		Sfx.play_3d(&"hit_headshot" if StringName(info.get("zone", &"")) == GC.ZONE_HEAD else &"hit_flesh", pos, 0.0, 1.0, 60.0)
	if dt == GC.DMG_FALL or dt == GC.DMG_DROWN or dt == GC.DMG_FIRE:
		pass
	if not Sfx.was_played_recently(&"voice", pos, 0.45, 5.0) and randf() < 0.85:
		Sfx.play_3d(&"hurt_f" if female else &"hurt_m", pos, 0.0, 1.0, 55.0)


func _on_vehicle_entered(vehicle: Node, character: Node, _seat: int) -> void:
	if not safety_net or character != Game.player or not is_instance_valid(vehicle) or not (vehicle is Node3D):
		return
	var pos: Vector3 = (vehicle as Node3D).global_position
	await get_tree().process_frame
	if not is_instance_valid(vehicle):
		return
	if not Sfx.was_played_recently(&"door_vehicle_close", pos, 0.8, 10.0) and not Sfx.was_played_recently(&"door_vehicle_open", pos, 0.8, 10.0):
		Sfx.play_3d(&"door_vehicle_close", pos, 0.0, 1.0, 40.0, vehicle as Node3D)


func _on_vehicle_exited(vehicle: Node, character: Node) -> void:
	if not safety_net or character != Game.player or not is_instance_valid(vehicle) or not (vehicle is Node3D):
		return
	var pos: Vector3 = (vehicle as Node3D).global_position
	await get_tree().process_frame
	if not is_instance_valid(vehicle):
		return
	if not Sfx.was_played_recently(&"door_vehicle_close", pos, 0.8, 10.0) and not Sfx.was_played_recently(&"door_vehicle_open", pos, 0.8, 10.0):
		Sfx.play_3d(&"door_vehicle_open", pos, 0.0, 1.0, 40.0, vehicle as Node3D)


func _on_vehicle_horn(vehicle: Node) -> void:
	if not safety_net or not is_instance_valid(vehicle) or not (vehicle is Node3D):
		return
	var pos: Vector3 = (vehicle as Node3D).global_position
	await get_tree().process_frame
	if not is_instance_valid(vehicle) or Sfx.was_played_recently(&"horn", pos, 0.25, 8.0):
		return
	var def: String = String(vehicle.get("def_id"))
	var sid := &"horn_car"
	if def.contains("truck") or def.contains("fire") or def == "van":
		sid = &"horn_truck"
	elif def.contains("motor") or def.contains("bike"):
		sid = &"horn_bike"
	Sfx.play_3d(sid, pos, 0.0, 1.0, 140.0, vehicle as Node3D)
