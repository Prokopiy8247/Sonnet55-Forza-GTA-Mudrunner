extends Node
## Autoload "Sfx": the procedural sound bank + pooled one-shot playback + audio bus layout.
##
## Contract (docs/ARCHITECTURE.md section 8, all sound ids are listed in docs/api/audio.md):
##   Sfx.play_ui(id, db)                          non-positional UI / HUD sound (bus UI)
##   Sfx.play_2d(id, db, pitch)                   non-positional world sound (player-only feedback)
##   Sfx.play_3d(id, pos, db, pitch, max_dist)    positional one-shot, pooled AudioStreamPlayer3D, distance culled
##   Sfx.has_sound(id) / Sfx.get_stream(id)       registry / raw AudioStream for modules that run their own players
## All callers tolerate a missing sound (nothing plays, a warning is logged once per unknown id).
##
## Sounds are synthesised procedurally (synth.gd / bank_*.gd), loaded from baked res://gta/generated/audio/*.res when a
## matching bake exists (see audio_bake.gd) and otherwise generated on WorkerThreadPool threads right after boot.
## Playback: polyphony caps per id and per category, distance + priority based voice stealing, small random pitch/volume
## variation, doppler-free pooled 3D players that can optionally follow a Node3D.

const SoundBank = preload("res://gta/code/audio/sound_bank.gd")

signal bank_ready()

## Audio bus layout [name, send, base trim in dB]. Created at boot if missing (the project has no bus layout file).
const BUSES := [
	["SFX", "Master", 0.0],
	["Engine", "Master", -2.0],
	["Voice", "Master", 0.0],
	["Ambience", "Master", -3.0],
	["Music", "Master", -4.0],
	["Radio", "Music", 0.0],
	["UI", "Master", -2.0],
]
## Buses that get an underwater / muffling low-pass effect at index 0 (kept disabled until needed).
const LP_BUSES := ["SFX", "Engine", "Voice", "Ambience", "Music", "Radio"]
const POOL_3D := 32
const POOL_2D := 14
const DEFAULT_LOOP_ONESHOT := 4.0
## Alternative ids other modules might use -> the bank id that sounds right.
const ALIASES := {
	&"shot_carbine": &"shot_rifle", &"shot_rifle_assault": &"shot_rifle", &"shot_rifle_marksman": &"shot_rifle",
	&"shot_shotgun_pump": &"shot_shotgun", &"shot_shotgun_auto": &"shot_shotgun", &"shot_grenade_launcher": &"shot_rocket",
	&"shot_rocket_launcher": &"shot_rocket", &"shot_silenced": &"shot_suppressed", &"shot_sniper_rifle": &"shot_sniper",
	&"explosion": &"explosion_big", &"explosion_medium": &"explosion_small", &"grenade_explosion": &"explosion_small",
	&"horn": &"horn_car", &"siren": &"siren_police", &"hit_wood": &"hit_concrete", &"hit_body": &"hit_flesh",
	&"hit_head": &"hit_headshot", &"hit_car": &"hit_metal", &"hit_sand": &"hit_dirt", &"hit_grass": &"hit_dirt",
	&"step_gravel": &"step_sand", &"step_tile": &"step_concrete", &"step_asphalt": &"step_concrete", &"step_dirt": &"step_grass",
	&"step_carpet": &"step_grass", &"step_stone": &"step_concrete", &"step_snow": &"step_sand",
	&"hurt": &"hurt_m", &"death": &"death_m", &"grunt": &"hurt_m", &"scream_f": &"scream", &"scream_m": &"scream",
	&"vehicle_door_open": &"door_vehicle_open", &"vehicle_door_close": &"door_vehicle_close", &"car_door_open": &"door_vehicle_open",
	&"car_door_close": &"door_vehicle_close", &"engine_start": &"ignition", &"engine_stop": &"engine_off", &"crash": &"crash_light",
	&"tire_screech": &"skid", &"tyre_screech": &"skid", &"ui_money": &"ui_cash", &"ui_select": &"ui_click", &"ui_open": &"ui_click",
	&"ui_close": &"ui_back", &"ui_cancel": &"ui_back", &"ui_warning": &"ui_error", &"ui_wanted": &"ui_wanted_up",
	&"reload": &"reload_end", &"empty_click": &"dry_fire", &"water_splash": &"splash", &"cash": &"ui_cash",
}

class Voice:
	extends RefCounted
	var p3: AudioStreamPlayer3D = null
	var p2: AudioStreamPlayer = null
	var is_3d := false
	var id: StringName = &""
	var cat: StringName = &""
	var prio := 0.0                  # category priority (1..10)
	var score := 0.0                 # prio * 100 - distance (higher = more important)
	var start_t := 0.0
	var stop_t := 0.0                # 0 = play until the stream ends
	var follow: Node3D = null

	func is_active() -> bool:
		return p3.playing if is_3d else p2.playing

	func stop() -> void:
		if is_3d:
			p3.stop()
		else:
			p2.stop()


var listener_pos := Vector3.ZERO
var listener_valid := false
var enabled := true
var _clock := 0.0
var _stop_gen := false

var _wavs: Dictionary = {}           # "id#variant" -> AudioStreamWAV
var _slots: Dictionary = {}          # "id#variant" -> 1 building, 2 done
var _mutex := Mutex.new()
var _group_id := -1
var _items: Array = []               # [id, variant] pairs generated at boot
var _bank_done := false
var _use_baked := true
var _gen_ms := 0.0
var _gen_started_us := 0
var _gen_end_us := 0
var _randomizers: Dictionary = {}
var _last_variant: Dictionary = {}
var _last_start: Dictionary = {}     # id -> seconds
var _recent: Array = []              # [t, id, cat, pos] ring of the last plays (safety-net checks)
var _warned: Dictionary = {}

var _voices3d: Array[Voice] = []
var _voices2d: Array[Voice] = []
var _bus_fx: Dictionary = {}         # bus name -> {"lp": AudioEffectLowPassFilter, "lp_idx": int, "reverb": ..., "reverb_idx": int}
var _duck_db: Dictionary = {}        # bus name -> dB offset applied by AudioSystem (menus, pause, underwater)
var _stat := {"played": 0, "culled": 0, "stolen": 0, "dropped_poly": 0, "dropped_unready": 0, "missing": 0, "gap": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SoundBank.init_registry()
	_setup_buses()
	_make_pools()
	apply_settings()
	Events.settings_changed.connect(apply_settings)
	_start_generation()


func _process(delta: float) -> void:
	# audio clock in real (unscaled) game seconds: stays correct in slow motion and in fixed-fps headless runs
	_clock += delta / maxf(Engine.time_scale, 0.05)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		listener_pos = cam.global_position
		listener_valid = true
	_service_voices()
	if not _bank_done and _group_id >= 0 and WorkerThreadPool.is_group_task_completed(_group_id):
		WorkerThreadPool.wait_for_group_task_completion(_group_id)
		_group_id = -1
		_bank_done = true
		_gen_ms = float(_gen_end_us - _gen_started_us) / 1000.0
		bank_ready.emit()


# =========================================================================================================
# Public API
# =========================================================================================================
func has_sound(sound: StringName) -> bool:
	return SoundBank.has(_resolve(sound))


## Non-positional UI / HUD sound on the UI bus.
func play_ui(sound: StringName, volume_db: float = 0.0) -> void:
	_play_flat(sound, volume_db, 1.0, true)


## Non-positional world sound (player-only feedback: pickups, hit markers, own heartbeat ...).
func play_2d(sound: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	return _play_flat(sound, volume_db, pitch_scale, false)


## Positional one-shot (pooled AudioStreamPlayer3D, culled beyond max_distance). `follow` makes the voice track a moving
## node. Returns the player (or null when culled/dropped); pooled players are reused after they finish, so only keep the
## reference while it is playing - for long-running loops use play_loop_3d / create_player_3d instead.
func play_3d(sound: StringName, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0, max_distance: float = 80.0, follow: Node3D = null) -> AudioStreamPlayer3D:
	if not enabled:
		return null
	var id := _resolve(sound)
	var m := SoundBank.meta(id)
	if m.is_empty():
		_note_missing(sound)
		return null
	if is_equal_approx(max_distance, 80.0):
		max_distance = maxf(float(m.get("range", 80.0)), 8.0)   # default argument: use the sound's natural audible range
	var dist: float = listener_pos.distance_to(position) if listener_valid else 0.0
	if dist > max_distance:
		_stat["culled"] += 1
		return null
	var now := _now()
	if _too_soon(id, m, now):
		return null
	var cat: StringName = m["cat"]
	var prio: float = float(m["prio"])
	var score: float = prio * 100.0 - dist
	if not _count_ok(_voices3d, id, cat, int(m["poly"]), int(m["cat_poly"]), score):
		return null
	var wav := _pick_wav(id, m)
	if wav == null:
		return null
	var v := _acquire(_voices3d, score)
	if v == null:
		_stat["dropped_poly"] += 1
		return null
	var p := v.p3
	p.stop()
	p.stream = wav
	p.bus = String(m["bus"])
	p.volume_db = volume_db + randf_range(-1.0, 1.0) * float(m["vvar"])
	p.pitch_scale = maxf(pitch_scale * (1.0 + randf_range(-1.0, 1.0) * float(m["pvar"])), 0.05)
	p.unit_size = float(m["unit"]) * clampf(db_to_linear(volume_db), 0.5, 3.0)
	p.max_distance = max_distance
	p.global_position = position
	_begin(v, id, cat, prio, score, now, wav, m, follow)
	p.play()
	return p


## Creates a NON-pooled looping positional player attached to `parent` (horns, sirens, skids ...). The caller owns it:
## call play() / stop() or queue_free() it. Returns null for unknown ids.
func create_player_3d(sound: StringName, parent: Node, volume_db: float = 0.0, max_distance: float = 120.0, autoplay: bool = false) -> AudioStreamPlayer3D:
	var id := _resolve(sound)
	var m := SoundBank.meta(id)
	if m.is_empty():
		_note_missing(sound)
		return null
	var wav := get_wav(id, 0)
	if wav == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = wav
	p.bus = String(m["bus"])
	p.volume_db = volume_db
	p.unit_size = float(m["unit"])
	p.max_distance = max_distance
	p.max_polyphony = 1
	if parent != null:
		parent.add_child(p)
	if autoplay:
		p.play()
	return p


## Returns the generated stream. Multi-variant one-shots come back as an AudioStreamRandomizer (random variant + slight pitch
## / volume variation on every play), looping and single-variant sounds as the AudioStreamWAV itself. Blocks until the sound
## is generated (normally already done at boot).
func get_stream(sound: StringName) -> AudioStream:
	var id := _resolve(sound)
	var m := SoundBank.meta(id)
	if m.is_empty():
		_note_missing(sound)
		return null
	var n: int = int(m["var"])
	var first := get_wav(id, 0)
	if first == null:
		return null
	if n <= 1 or first.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return first
	if _randomizers.has(id):
		return _randomizers[id]
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = 1.0 + float(m["pvar"])
	r.random_volume_offset_db = float(m["vvar"])
	for v in n:
		var w := get_wav(id, v)
		if w != null:
			r.add_stream(-1, w, 1.0)
	_randomizers[id] = r
	return r


## One concrete AudioStreamWAV variant (blocks until generated). Used by tests / tools.
func get_wav(sound: StringName, variant: int = 0) -> AudioStreamWAV:
	var id := _resolve(sound)
	if not SoundBank.has(id):
		return null
	return _ensure(id, clampi(variant, 0, SoundBank.variant_count(id) - 1), true)


## True when variant 0 of the sound is already generated (non-blocking check, e.g. before creating a looping bed).
func is_sound_ready(sound: StringName) -> bool:
	if _mutex == null:
		return false
	var id := _resolve(sound)
	_mutex.lock()
	var ok := _wavs.has("%s#0" % id)
	_mutex.unlock()
	return ok


## Name of the audio bus the sound belongs on (for modules that run their own players): SFX, Voice, Ambience, UI, Engine.
func get_bus(sound: StringName) -> String:
	var m := SoundBank.meta(_resolve(sound))
	return String(m.get("bus", "SFX"))


## Natural audible range in metres (what play_3d uses when called with the default max_distance).
func get_range(sound: StringName) -> float:
	var m := SoundBank.meta(_resolve(sound))
	return float(m.get("range", 80.0))


func get_variant_count(sound: StringName) -> int:
	return SoundBank.variant_count(_resolve(sound))


func is_loop(sound: StringName) -> bool:
	var w := get_wav(sound, 0)
	return w != null and w.loop_mode != AudioStreamWAV.LOOP_DISABLED


## All registered sound ids.
func sound_ids() -> Array[StringName]:
	return SoundBank.ids()


## True once every sound of the bank has been generated/loaded (background generation finished).
func is_bank_ready() -> bool:
	return _bank_done


## Blocks until the whole bank is generated (tests, tools). Returns total generation wall time in ms.
func wait_ready() -> float:
	if _group_id >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_group_id)
		_group_id = -1
		_bank_done = true
		_gen_ms = float(_gen_end_us - _gen_started_us) / 1000.0
		bank_ready.emit()
	return _gen_ms


## Stops a voice returned by play_3d / play_2d with an optional fade (seconds).
func stop_voice(player: Node, fade: float = 0.0) -> void:
	if player == null or not is_instance_valid(player):
		return
	if fade <= 0.0:
		player.call("stop")
		return
	var tw := create_tween()
	tw.tween_property(player, "volume_db", -60.0, fade)
	tw.tween_callback(player.call.bind("stop"))


## Was a sound of this category/id started within `within` seconds near `pos`? (safety-net modules use it to avoid doubling
## sounds that gameplay code already played.)
func was_played_recently(cat_or_id: StringName, pos: Vector3, within: float = 0.15, radius: float = 12.0) -> bool:
	var now := _now()
	for e in _recent:
		if now - float(e[0]) > within:
			continue
		if e[1] == cat_or_id or e[2] == cat_or_id:
			if float(radius) <= 0.0 or (e[3] as Vector3).distance_to(pos) <= radius:
				return true
	return false


func stats() -> Dictionary:
	var a3 := 0
	for v in _voices3d:
		if v.is_active():
			a3 += 1
	var a2 := 0
	for v in _voices2d:
		if v.is_active():
			a2 += 1
	var s := _stat.duplicate()
	s["active_3d"] = a3
	s["active_2d"] = a2
	s["bank_ready"] = _bank_done
	s["bank_gen_ms"] = _gen_ms
	s["sounds"] = SoundBank.ids().size()
	s["buffers"] = _wavs.size()
	return s


## Stops every pooled voice (scene changes, tests).
func stop_all() -> void:
	for v in _voices3d:
		v.stop()
	for v in _voices2d:
		v.stop()


# ---- buses -----------------------------------------------------------------------------------------------------------
func get_bus_fx(bus_name: String) -> Dictionary:
	return _bus_fx.get(bus_name, {})


## Offsets a bus' volume (menus ducking, pause, underwater trims) on top of the user settings. 0 = no change.
func set_bus_duck(bus_name: String, db: float) -> void:
	if absf(float(_duck_db.get(bus_name, 0.0)) - db) < 0.01:
		return
	_duck_db[bus_name] = db
	_apply_bus_volume(bus_name)


func apply_settings() -> void:
	for spec in BUSES:
		_apply_bus_volume(String(spec[0]))
	_apply_bus_volume("Master")


## Game.settings keys read: master_volume, sfx_volume, music_volume (0..1) and optionally ambience_volume, voice_volume,
## ui_volume, radio_volume (default 1.0).
func _setting_for(bus_name: String) -> float:
	var s: Dictionary = Game.settings
	match bus_name:
		"Master":
			return float(s.get("master_volume", 0.8))
		"SFX", "Engine":
			return float(s.get("sfx_volume", 1.0))
		"Voice":
			return float(s.get("sfx_volume", 1.0)) * float(s.get("voice_volume", 1.0))
		"Ambience":
			return float(s.get("sfx_volume", 1.0)) * float(s.get("ambience_volume", 1.0))
		"Music":
			return float(s.get("music_volume", 0.6))
		"Radio":
			return float(s.get("radio_volume", 1.0))
		"UI":
			return float(s.get("sfx_volume", 1.0)) * float(s.get("ui_volume", 1.0))
	return 1.0


func _apply_bus_volume(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var lin: float = clampf(_setting_for(bus_name), 0.0, 1.5)
	var trim := 0.0
	for spec in BUSES:
		if spec[0] == bus_name:
			trim = float(spec[2])
	var db: float = -80.0 if lin <= 0.001 else linear_to_db(lin) + trim + float(_duck_db.get(bus_name, 0.0))
	AudioServer.set_bus_volume_db(idx, maxf(db, -80.0))
	AudioServer.set_bus_mute(idx, lin <= 0.001)


func _setup_buses() -> void:
	# master limiter so stacked explosions never clip
	var mi := AudioServer.get_bus_index("Master")
	if mi >= 0 and AudioServer.get_bus_effect_count(mi) == 0:
		if ClassDB.class_exists("AudioEffectHardLimiter"):
			var hl = ClassDB.instantiate("AudioEffectHardLimiter")
			hl.set("pre_gain_db", 0.0)
			hl.set("ceiling_db", -0.6)
			AudioServer.add_bus_effect(mi, hl)
		else:
			var lim := AudioEffectLimiter.new()
			lim.ceiling_db = -0.6
			AudioServer.add_bus_effect(mi, lim)
	for spec in BUSES:
		var bn: String = spec[0]
		var idx := AudioServer.get_bus_index(bn)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bn)
		AudioServer.set_bus_send(idx, String(spec[1]))
		var fx := {}
		if AudioServer.get_bus_effect_count(idx) == 0:
			if bn in LP_BUSES:
				var lp := AudioEffectLowPassFilter.new()
				lp.cutoff_hz = 20000.0
				lp.resonance = 0.6
				AudioServer.add_bus_effect(idx, lp)
				AudioServer.set_bus_effect_enabled(idx, 0, false)
				fx["lp"] = lp
				fx["lp_idx"] = 0
			if bn == "SFX":
				var rv := AudioEffectReverb.new()
				rv.room_size = 0.35
				rv.damping = 0.65
				rv.spread = 1.0
				rv.dry = 1.0
				rv.wet = 0.07
				rv.hipass = 0.15
				AudioServer.add_bus_effect(idx, rv)
				fx["reverb"] = rv
				fx["reverb_idx"] = 1
		else:
			for ei in AudioServer.get_bus_effect_count(idx):
				var e := AudioServer.get_bus_effect(idx, ei)
				if e is AudioEffectLowPassFilter:
					fx["lp"] = e
					fx["lp_idx"] = ei
				elif e is AudioEffectReverb:
					fx["reverb"] = e
					fx["reverb_idx"] = ei
		_bus_fx[bn] = fx
		_duck_db[bn] = 0.0


# =========================================================================================================
# Internals
# =========================================================================================================
func _now() -> float:
	return _clock


func _resolve(sound: StringName) -> StringName:
	if SoundBank.has(sound):
		return sound
	return ALIASES.get(sound, sound)


func _note_missing(sound: StringName) -> void:
	_stat["missing"] += 1
	if not _warned.has(sound):
		_warned[sound] = true
		push_warning("Sfx: unknown sound id '%s' (silent)" % sound)


func _make_pools() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_polyphony = 1
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.name = "V3D_%d" % i
		add_child(p)
		var v := Voice.new()
		v.p3 = p
		v.is_3d = true
		_voices3d.append(v)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.max_polyphony = 1
		p2.name = "V2D_%d" % i
		add_child(p2)
		var v2 := Voice.new()
		v2.p2 = p2
		_voices2d.append(v2)


func _too_soon(id: StringName, m: Dictionary, now: float) -> bool:
	var gap: float = float(m["gap"])
	if gap <= 0.0:
		return false
	var last: float = float(_last_start.get(id, -10.0))
	if now - last < gap:
		_stat["gap"] += 1
		return true
	return false


## Checks the per-id and per-category polyphony caps. When a cap is reached the least important active voice of that
## id/category is stopped if the new voice outranks it; otherwise the new voice is rejected (returns false).
func _count_ok(pool: Array[Voice], id: StringName, cat: StringName, poly_id: int, poly_cat: int, score: float) -> bool:
	var same_id := 0
	var same_cat := 0
	var worst_id: Voice = null
	var worst_cat: Voice = null
	for v in pool:
		if not _voice_active(v):
			continue
		if v.id == id:
			same_id += 1
			if worst_id == null or v.score < worst_id.score or (v.score == worst_id.score and v.start_t < worst_id.start_t):
				worst_id = v
		if v.cat == cat:
			same_cat += 1
			if worst_cat == null or v.score < worst_cat.score or (v.score == worst_cat.score and v.start_t < worst_cat.start_t):
				worst_cat = v
	if same_id >= poly_id:
		if worst_id != null and (score >= worst_id.score):
			_kill(worst_id)
			_stat["stolen"] += 1
		else:
			_stat["dropped_poly"] += 1
			return false
	if same_cat >= poly_cat:
		if worst_cat != null and _voice_active(worst_cat) and score >= worst_cat.score:
			_kill(worst_cat)
			_stat["stolen"] += 1
		elif worst_cat != null and _voice_active(worst_cat):
			_stat["dropped_poly"] += 1
			return false
	return true


func _voice_active(v: Voice) -> bool:
	return v.is_active()


func _kill(v: Voice) -> void:
	v.stop()
	v.follow = null
	v.id = &""
	v.cat = &""


## Free voice, or the least important active one if the new sound outranks it.
func _acquire(pool: Array[Voice], score: float) -> Voice:
	var worst: Voice = null
	for v in pool:
		if not _voice_active(v):
			return v
		if worst == null or v.score < worst.score:
			worst = v
	if worst != null and score > worst.score:
		_kill(worst)
		_stat["stolen"] += 1
		return worst
	return null


func _begin(v: Voice, id: StringName, cat: StringName, prio: float, score: float, now: float, wav: AudioStreamWAV, m: Dictionary, follow: Node3D) -> void:
	v.id = id
	v.cat = cat
	v.prio = prio
	v.score = score
	v.start_t = now
	v.follow = follow
	v.stop_t = 0.0
	if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		v.stop_t = now + float(m.get("oneshot", DEFAULT_LOOP_ONESHOT))
	_last_start[id] = now
	_stat["played"] += 1
	var pos := Vector3.ZERO
	if v.is_3d:
		pos = v.p3.global_position
	_recent.append([now, id, cat, pos])
	if _recent.size() > 28:
		_recent.pop_front()


func _service_voices() -> void:
	var now := _now()
	for v in _voices3d:
		if v.follow != null:
			if is_instance_valid(v.follow):
				v.p3.global_position = v.follow.global_position
			else:
				v.follow = null
		if v.stop_t > 0.0 and now >= v.stop_t:
			v.stop_t = 0.0
			v.p3.stop()
	for v in _voices2d:
		if v.stop_t > 0.0 and now >= v.stop_t:
			v.stop_t = 0.0
			v.p2.stop()


func _play_flat(sound: StringName, volume_db: float, pitch_scale: float, force_ui: bool) -> AudioStreamPlayer:
	if not enabled:
		return null
	var id := _resolve(sound)
	var m := SoundBank.meta(id)
	if m.is_empty():
		_note_missing(sound)
		return null
	var now := _now()
	if _too_soon(id, m, now):
		return null
	var cat: StringName = m["cat"]
	var prio: float = float(m["prio"])
	var score: float = prio * 100.0 + (50.0 if force_ui else 0.0)
	if not _count_ok(_voices2d, id, cat, int(m["poly"]), int(m["cat_poly"]), score):
		return null
	var wav := _pick_wav(id, m)
	if wav == null:
		return null
	var v := _acquire(_voices2d, score)
	if v == null:
		_stat["dropped_poly"] += 1
		return null
	var p := v.p2
	p.stop()
	p.stream = wav
	p.bus = "UI" if (force_ui or cat == &"ui") else String(m["bus"])
	p.volume_db = volume_db + randf_range(-1.0, 1.0) * float(m["vvar"])
	p.pitch_scale = maxf(pitch_scale * (1.0 + randf_range(-1.0, 1.0) * float(m["pvar"])), 0.05)
	_begin(v, id, cat, prio, score, now, wav, m, null)
	p.play()
	return p


func _pick_wav(id: StringName, m: Dictionary) -> AudioStreamWAV:
	var n: int = int(m["var"])
	var vi := 0
	if n > 1:
		vi = randi() % n
		if vi == int(_last_variant.get(id, -1)):
			vi = (vi + 1 + randi() % (n - 1)) % n
		_last_variant[id] = vi
	return _ensure(id, vi, false)


## Returns the buffer for (id, variant). wait = true blocks while another thread builds it; wait = false returns null in that
## case (the voice is dropped instead of stalling the frame) but generates inline if nobody started it yet.
func _ensure(id: StringName, v: int, wait: bool) -> AudioStreamWAV:
	if _mutex == null:
		return null            # autoload is being torn down (a worker task or a late caller at exit)
	var key := "%s#%d" % [id, v]
	_mutex.lock()
	var w = _wavs.get(key, null)
	if w != null:
		_mutex.unlock()
		return w
	var state: int = int(_slots.get(key, 0))
	if state == 0:
		_slots[key] = 1
		_mutex.unlock()
		var made := SoundBank.load_or_generate(id, v, _use_baked)
		_mutex.lock()
		if made != null:
			_wavs[key] = made
		_slots[key] = 2
		_mutex.unlock()
		return made
	_mutex.unlock()
	if not wait:
		_stat["dropped_unready"] += 1
		return null
	for i in 4000:
		OS.delay_msec(2)
		_mutex.lock()
		w = _wavs.get(key, null)
		var st: int = int(_slots.get(key, 0))
		_mutex.unlock()
		if w != null:
			return w
		if st == 2:
			break
	return null


func _start_generation() -> void:
	var order: Dictionary = {
		&"ui": 0, &"weapon": 1, &"weapon_mech": 2, &"melee": 2, &"impact": 2, &"step": 1, &"foley": 3, &"voice": 3,
		&"vehicle": 2, &"horn": 3, &"siren": 4, &"explosion": 1, &"engine_fx": 5, &"ambient_shot": 6, &"amb_loop": 7,
	}
	var buckets: Array = []
	for i in 9:
		buckets.append([])
	for id in SoundBank.ids():
		var m := SoundBank.meta(id)
		var b: int = int(order.get(m["cat"], 6))
		if String(id).begins_with("eng_"):
			b = 8
		for v in int(m["var"]):
			(buckets[b] as Array).append([id, v])
	for b in buckets:
		_items.append_array(b)
	_gen_started_us = Time.get_ticks_usec()
	_group_id = WorkerThreadPool.add_group_task(_gen_item, _items.size(), 5, false, "Sfx bank synthesis")


func _gen_item(i: int) -> void:
	if _stop_gen or _mutex == null:
		return
	var it: Array = _items[i]
	_ensure(it[0], it[1], false)
	if _mutex == null:
		return
	_mutex.lock()
	_gen_end_us = Time.get_ticks_usec()
	_mutex.unlock()


func _exit_tree() -> void:
	# let background synthesis finish quickly (remaining items are skipped) so no worker touches a freed node at shutdown
	_stop_gen = true
	if _group_id >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_group_id)
		_group_id = -1
