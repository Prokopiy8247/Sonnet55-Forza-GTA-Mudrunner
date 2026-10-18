class_name EngineSound
extends Node3D
## Procedural looping engine / rotor / propeller / jet sound attached to a vehicle (positional, doppler-capable):
##     var snd := EngineSound.create(&"car_v6"); vehicle.add_child(snd)
##     each physics frame while the engine runs:  snd.update(rpm01, load01)   # rpm01 0..1 (idle..redline), load01 0..1
##     snd.start() / snd.stop()                                              # optional (update() auto-starts)
## profiles: car_small car_v6 car_v8 sports truck bike boat heli_rotor prop_plane jet
##
## How it works: every profile has 3-4 seamless loops rendered at log-spaced firing frequencies between idle and redline
## (bank_engine.gd). update() maps rpm to a target firing frequency, cross-fades the two neighbouring loops with equal-power
## weights and pitch-shifts each with pitch_scale; load biases the cross-fade towards the brighter loop and sets the level.
## Extras: tonal whine/turbo/turbine layer, exhaust burble on lift-off (v8/sports/bike), gear-shift dips (rpm drops while
## accelerating) and distance LOD (far engines use one loop; beyond max_distance everything is paused).
## update() only does arithmetic and a few property writes - cheap enough for dozens of vehicles.

const BankEngine = preload("res://gta/code/audio/bank_engine.gd")
const NEAR_FULL := 38.0          # inside this distance (m) every layer runs; beyond it only the dominant loop
const LN2_INV := 1.4426950408889634

## Public tunables (set after create()).
var running := false
var volume_db := 0.0             # per-vehicle balance trim (player car slightly louder than traffic, ...)
var max_distance := 95.0
var doppler := true              # doppler is only enabled while the source is not right next to the camera
var profile: StringName = &"car_small": set = set_profile

var _info: Dictionary = {}
var _layers: Array[AudioStreamPlayer3D] = []
var _whine: AudioStreamPlayer3D = null
var _anchors: PackedFloat32Array = PackedFloat32Array()
var _n := 0
var _built := false
var _rpm := 0.0                  # smoothed rpm
var _load := 0.0                 # smoothed load
var _boost := 0.0                # turbo spool 0..1
var _prev_rpm := 0.0
var _prev_load := 0.0
var _dip := 0.0                  # gear-shift dip 0..1
var _fade := 0.0
var _fade_target := 0.0
var _last_us := 0
var _tick := 0
var _audible := true
var _far := false
var _doppler_on := false
var _last_fx := -10.0
var _whine_mode := "none"
var _unit := 12.0


static func create(engine_profile: StringName) -> EngineSound:
	var s := EngineSound.new()
	s.profile = engine_profile
	return s


## Suggested engine profile for a VehicleDefs id (compact, sedan, sports, muscle, suv, pickup, van, police_cruiser, taxi,
## ambulance, firetruck, truck, police_tactical, motorcycle, speedboat, heli_civil, heli_police, plane_prop, plane_jet ...).
static func profile_for(vehicle_def_id: StringName) -> StringName:
	match String(vehicle_def_id):
		"compact", "taxi":
			return &"car_small"
		"sedan", "suv", "van", "ambulance":
			return &"car_v6"
		"muscle", "pickup", "police_cruiser":
			return &"car_v8"
		"sports":
			return &"sports"
		"truck", "firetruck", "police_tactical":
			return &"truck"
		"motorcycle", "bike":
			return &"bike"
		"speedboat", "boat":
			return &"boat"
		"heli_civil", "heli_police", "helicopter":
			return &"heli_rotor"
		"plane_prop":
			return &"prop_plane"
		"plane_jet":
			return &"jet"
	return &"car_v6"


func _ready() -> void:
	_build()
	set_process(false)


func set_profile(p: StringName) -> void:
	profile = p if BankEngine.PROFILES.has(p) else &"car_small"
	if _built:
		_teardown()
		_build()


## Starts (fades in) the engine loops. with_ignition also plays the starter/ignition one-shot.
func start(with_ignition: bool = false) -> void:
	if not _built and is_inside_tree():
		_build()
	running = true
	_fade_target = 1.0
	set_process(false)
	if with_ignition and is_inside_tree():
		Sfx.play_3d(&"ignition", global_position, -2.0, 1.0, 50.0, get_parent() as Node3D)


## Fades the engine out (and pauses the layers when finished). with_shutdown plays the engine-off wind-down.
func stop(with_shutdown: bool = false) -> void:
	if running and with_shutdown and is_inside_tree():
		Sfx.play_3d(&"engine_off", global_position, -3.0, 1.0, 40.0, get_parent() as Node3D)
	running = false
	_fade_target = 0.0
	set_process(true)


func is_running() -> bool:
	return running


func _process(delta: float) -> void:
	# only enabled while fading out after stop()
	_fade = move_toward(_fade, 0.0, delta * 4.0)
	if _fade <= 0.001:
		_pause_all(true)
		set_process(false)
		return
	_apply(delta, true)


## rpm01: 0 = idle .. 1 = redline (rotor / propeller speed for aircraft). load01: throttle load (collective for helis).
func update(rpm01: float, load01: float) -> void:
	if not running:
		if rpm01 <= 0.001 and load01 <= 0.001:
			return
		start()
	if not _built:
		_build()
		if not _built:
			return
	var now := Time.get_ticks_usec()
	var dt: float = clampf(float(now - _last_us) / 1000000.0, 0.001, 0.1)
	if _last_us == 0:
		dt = 0.016
		_rpm = rpm01
		_load = load01
		_prev_rpm = rpm01
	_last_us = now
	# smoothing: rpm follows quickly, load a bit slower
	var a_r: float = 1.0 - exp(-16.0 * dt)
	var a_l: float = 1.0 - exp(-10.0 * dt)
	_prev_rpm = _rpm
	_prev_load = _load
	_rpm += (clampf(rpm01, 0.0, 1.2) - _rpm) * a_r
	_load += (clampf(load01, 0.0, 1.0) - _load) * a_l
	_fade = move_toward(_fade, _fade_target, dt * 3.0)
	# gear shift: rpm falls fast while the throttle is still open
	var drop: float = _prev_rpm - _rpm
	if drop > 0.012 and rpm01 < _prev_rpm and _load > 0.3 and (Time.get_ticks_msec() / 1000.0 - _last_fx) > 0.35:
		_dip = 1.0
		_last_fx = Time.get_ticks_msec() / 1000.0
		if _info.get("burble", false) and _rpm > 0.35:
			Sfx.play_3d(&"engine_burble", global_position, -11.0, 1.0, 60.0, get_parent() as Node3D)
		else:
			Sfx.play_3d(&"engine_shift", global_position, -13.0, 1.0, 40.0, get_parent() as Node3D)
	_dip = maxf(_dip - dt * 7.0, 0.0)
	# lift-off burble / blow-off
	if _prev_load > 0.55 and _load < _prev_load - 0.03 and load01 < 0.12 and _rpm > 0.42 and (Time.get_ticks_msec() / 1000.0 - _last_fx) > 0.9:
		_last_fx = Time.get_ticks_msec() / 1000.0
		if _info.get("burble", false):
			Sfx.play_3d(&"engine_burble", global_position, -7.0, 1.0, 70.0, get_parent() as Node3D)
		if _info.get("turbo", false) and _boost > 0.45:
			Sfx.play_3d(&"turbo_whistle", global_position, -10.0, 1.0, 60.0, get_parent() as Node3D)
	_tick += 1
	if (_tick & 3) == 1:
		_update_lod()
	if _audible:
		_apply(dt, false)


# ---------------------------------------------------------------------------------------------------------------------
func _update_lod() -> void:
	if not Sfx.listener_valid:
		return
	var d2: float = Sfx.listener_pos.distance_squared_to(global_position)
	var cull: float = max_distance * 1.04
	var was_audible := _audible
	if _audible and d2 > cull * cull:
		_audible = false
		_pause_all(true)
	elif not _audible and d2 < (cull * 0.94) * (cull * 0.94):
		_audible = true
	_far = d2 > NEAR_FULL * NEAR_FULL
	if _audible and not was_audible:
		_pause_all(false)
	# doppler only for sources that are not riding with the camera
	var want_doppler: bool = doppler and d2 > 14.0 * 14.0
	if want_doppler != _doppler_on:
		_doppler_on = want_doppler
		var mode := AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP if want_doppler else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		for p in _layers:
			p.doppler_tracking = mode
		if _whine != null:
			_whine.doppler_tracking = mode


func _apply(dt: float, fading: bool) -> void:
	if not _built:
		return
	var f_idle: float = float(_info["f_idle"])
	var f_red: float = float(_info["f_red"])
	var rpm: float = clampf(_rpm, 0.0, 1.15)
	var f_t: float = f_idle + (f_red - f_idle) * rpm
	# load makes the timbre brighter: bias the cross-fade towards the next higher loop
	var bias: float = (_load - 0.45) * 0.3
	var fw: float = f_t * pow(2.0, bias)
	var weights := [0.0, 0.0, 0.0, 0.0]
	var sum_sq := 0.0
	var best := 0
	var best_w := -1.0
	for i in _n:
		var d_oct: float = log(fw / _anchors[i]) * LN2_INV
		var w: float = maxf(0.0, 1.0 - absf(d_oct) / 1.15)
		w *= w
		weights[i] = w
		sum_sq += w * w
		if w > best_w:
			best_w = w
			best = i
	if sum_sq < 1e-6:
		# outside the rendered range: use the nearest loop at full level
		best = 0 if fw < _anchors[0] else _n - 1
		weights[best] = 1.0
		sum_sq = 1.0
	var norm: float = 1.0 / sqrt(sum_sq)
	# overall level: quieter off-throttle, louder near redline, dip during a gear change, fades
	var load_db: float = lerpf(-5.5, 0.0, pow(_load, 0.7))
	var rpm_db: float = 2.5 * rpm
	var level_db: float = volume_db + load_db + rpm_db - 3.5 * _dip + linear_to_db(maxf(_fade, 0.0001))
	var lod_db: float = -2.5 if _far else 0.0
	for i in _n:
		var p: AudioStreamPlayer3D = _layers[i]
		var w2: float = weights[i] * norm
		var skip: bool = w2 < 0.05 or (_far and i != best)
		if skip:
			if not p.stream_paused:
				p.stream_paused = true
			continue
		if p.stream_paused:
			p.stream_paused = false
		p.volume_db = level_db + lod_db + linear_to_db(w2)
		p.pitch_scale = clampf(f_t / _anchors[i], 0.5, 2.6)
	_update_whine(dt, rpm, level_db)


func _update_whine(dt: float, rpm: float, level_db: float) -> void:
	if _whine == null:
		return
	var g := 0.0
	match _whine_mode:
		"turbine":
			g = 0.18 + 0.82 * pow(rpm, 0.8)
			_boost = rpm
		"turbo":
			# spool follows load slowly and decays slower than it builds, like a real turbo
			var target: float = _load * pow(rpm, 1.2)
			var rate: float = 1.4 if target > _boost else 2.2
			_boost = move_toward(_boost, target, dt * rate)
			g = pow(_boost, 1.6)
		"gear":
			_boost = _load * rpm
			g = 0.25 * _boost * _boost
	if g < 0.02 or _far or not _audible:
		if not _whine.stream_paused:
			_whine.stream_paused = true
		return
	if _whine.stream_paused:
		_whine.stream_paused = false
	_whine.volume_db = level_db + linear_to_db(g) - 3.0
	_whine.pitch_scale = lerpf(0.55, 1.75, clampf(rpm, 0.0, 1.0)) if _whine_mode != "turbo" else lerpf(0.7, 1.6, clampf(_boost, 0.0, 1.0))


func _pause_all(paused: bool) -> void:
	for p in _layers:
		p.stream_paused = paused
	if _whine != null:
		_whine.stream_paused = paused


func _teardown() -> void:
	for p in _layers:
		if is_instance_valid(p):
			p.queue_free()
	_layers.clear()
	if _whine != null and is_instance_valid(_whine):
		_whine.queue_free()
	_whine = null
	_built = false


func _build() -> void:
	if _built:
		return
	if not BankEngine.PROFILES.has(profile):
		profile = &"car_small"
	_info = BankEngine.PROFILES[profile]
	_n = int(_info["layers"])
	_anchors.resize(_n)
	var range_m := 95.0
	match String(profile):
		"heli_rotor", "jet":
			range_m = 260.0
			_unit = 34.0
		"prop_plane":
			range_m = 170.0
			_unit = 22.0
		"truck":
			range_m = 110.0
			_unit = 16.0
		"sports", "car_v8":
			range_m = 105.0
			_unit = 14.0
		"bike":
			range_m = 85.0
			_unit = 11.0
		_:
			_unit = 12.0
	max_distance = maxf(max_distance, range_m) if max_distance != 95.0 else range_m
	for i in _n:
		_anchors[i] = BankEngine.anchor_hz(profile, i)
		var w: AudioStreamWAV = Sfx.get_wav(StringName("eng_%s_%d" % [profile, i]), 0)
		if w == null:
			push_warning("EngineSound: missing loop layer %d of profile '%s' (silent)" % [i, profile])
			continue
		var p := _make_player(w)
		_layers.append(p)
	if _layers.size() != _n:
		# partial failure: keep going with whatever exists but never index out of range
		_n = _layers.size()
	var wid := StringName("eng_%s_whine" % profile)
	if Sfx.has_sound(wid):
		var ww: AudioStreamWAV = Sfx.get_wav(wid, 0)
		if ww != null:
			_whine = _make_player(ww)
	_whine_mode = "none"
	match String(profile):
		"jet", "heli_rotor":
			_whine_mode = "turbine"
		"sports", "truck":
			_whine_mode = "turbo"
		"bike":
			_whine_mode = "gear"
	if _whine_mode == "none" and _whine != null:
		_whine.queue_free()
		_whine = null
	_built = _n > 0
	_pause_all(true)
	for p in _layers:
		p.play()
	if _whine != null:
		_whine.play()
	_pause_all(true)
	_doppler_on = false
	_audible = true


func _make_player(w: AudioStreamWAV) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = w
	p.bus = "Engine"
	p.unit_size = _unit
	p.max_distance = max_distance
	p.max_polyphony = 1
	p.attenuation_filter_cutoff_hz = 7000.0
	p.volume_db = -20.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p
