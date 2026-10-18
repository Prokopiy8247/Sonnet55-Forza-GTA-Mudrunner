extends Node
## RadioPlayer - in-car radio: station list/selection, vehicle-aware activation and the AudioStreamGenerator feeder.
##
## Stations are generative (radio_music.gd): a worker thread renders 4-bar stereo phrases ahead of time into a queue and
## this node streams them gap-free through an AudioStreamGenerator on the "Radio" bus (child of "Music").
## The radio is audible only while the player sits in a vehicle whose engine is on (full quality); right after leaving it,
## the radio of that vehicle keeps playing low-pass filtered and quiet, fading with distance, as long as its engine runs.
## Selection API (also exposed through AudioSystem): next_station() prev_station() set_station(id) get_station() radio_off().
## Emits Events.radio_station_changed(station_id) and remembers the choice in Game.settings["radio_station"].

const Music = preload("res://gta/code/audio/radio_music.gd")
const Station = preload("res://gta/code/audio/radio_station.gd")

signal station_changed(station: StringName)

const OFF := &"off"
const MIX_RATE := 22050.0
const OUTSIDE_RANGE := 32.0

var enabled := true
var order: Array[StringName] = []
var current: StringName = &"halcyon_fm"
var gain := 0.0                      # smoothed 0..1 level of the radio (vehicle logic)
var muffle := 0.0                    # smoothed 0..1 (1 = heard from outside the car)
var vehicle: Node = null             # vehicle whose radio is playing (last one the player used)
var last_error := ""

var _stations: Dictionary = {}
var _player: AudioStreamPlayer = null
var _pb: AudioStreamGeneratorPlayback = null
var _cur := PackedVector2Array()
var _cur_pos := 0
var _fresh_station := true           # next phrase gets the station jingle mixed in
var _warm_list: Array[StringName] = []
var _warm_delay := 2.5
var _last_switch := -10.0
var _prev_target_muffle := 0.0
var _announce_on_entry := true
var _clock := 0.0


func setup() -> void:
	for sid in Music.station_ids():
		_stations[sid] = Station.new(sid)
		order.append(sid)
	order.append(OFF)
	var saved := String(Game.settings.get("radio_station", ""))
	if saved != "" and (_stations.has(StringName(saved)) or saved == String(OFF)):
		current = StringName(saved)
	else:
		current = order[0]
	_player = AudioStreamPlayer.new()
	_player.name = "RadioGenerator"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.6
	_player.stream = gen
	_player.bus = "Radio"
	_player.volume_db = -3.0
	add_child(_player)
	_warm_list = order.duplicate()
	_warm_list.erase(OFF)
	# warm the active station first so the very first entry into a car already has music
	if _warm_list.has(current):
		_warm_list.erase(current)
		_warm_list.push_front(current)
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.vehicle_destroyed.connect(_on_vehicle_destroyed)


func get_station_ids() -> Array[StringName]:
	return order


func get_display_name(station_id: StringName) -> String:
	if station_id == OFF:
		return "Radio Off"
	var st: Station = _stations.get(station_id)
	return st.display_name if st != null else String(station_id)


func get_tagline(station_id: StringName) -> String:
	var st: Station = _stations.get(station_id)
	return st.tagline if st != null else ""


func is_playing() -> bool:
	return _player != null and _player.playing and gain > 0.02 and current != OFF


func next_station() -> void:
	_step(1)


func prev_station() -> void:
	_step(-1)


func _step(dir: int) -> void:
	var now := _clock
	if now - _last_switch < 0.12:
		return    # debounce (UI + vehicle code may both react to the same key press)
	var i := order.find(current)
	set_station(order[posmod(i + dir, order.size())])


func radio_off() -> void:
	set_station(OFF)


func set_station(station_id: StringName) -> bool:
	if not order.has(station_id):
		return false
	var changed := station_id != current
	current = station_id
	_last_switch = _clock
	Game.settings["radio_station"] = String(current)
	_cur = PackedVector2Array()
	_cur_pos = 0
	_fresh_station = true
	if _player != null and _player.playing:
		# AudioStreamGeneratorPlayback.clear_buffer() is only legal while stopped: restart the stream (picked up in _process)
		_player.stop()
		_pb = null
	if changed:
		if gain > 0.05:
			Sfx.play_ui(&"radio_tune", -4.0)
		station_changed.emit(current)
		Events.radio_station_changed.emit(current)
	if current != OFF:
		(_stations[current] as Station).request_fill(2)
	return true


func _process(delta: float) -> void:
	if _player == null:
		return
	_clock += delta
	# background warm-up of every station's first phrase (one at a time, after the boot rush)
	if _warm_delay > 0.0:
		_warm_delay -= delta
	elif not _warm_list.is_empty():
		var ws: Station = _stations[_warm_list[0]]
		if ws.queued() >= 1:
			_warm_list.pop_front()
		else:
			ws.request_fill(1)
	_update_activation(delta)
	if gain > 0.01 and current != OFF and enabled:
		if not _player.playing:
			_player.play()
			_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _pb != null:
			_feed()
		(_stations[current] as Station).request_fill(2)
	elif _player.playing:
		_player.stop()
		_pb = null


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not _in_vehicle():
		return
	if event.is_action_pressed(&"radio_next"):
		next_station()
	elif event.is_action_pressed(&"radio_prev"):
		prev_station()


# ---- vehicle logic ---------------------------------------------------------------------------------------------------
func _in_vehicle() -> bool:
	var p = Game.player
	if not is_instance_valid(p):
		return false
	var cv = p.get("current_vehicle")
	return cv != null and is_instance_valid(cv)


func _on_vehicle_entered(veh: Node, character: Node, _seat: int) -> void:
	if character != Game.player or not is_instance_valid(veh):
		return
	vehicle = veh
	if _announce_on_entry and current != OFF and _radio_allowed(veh):
		Events.radio_station_changed.emit(current)


func _on_vehicle_destroyed(veh: Node, _killer: Node) -> void:
	if veh == vehicle:
		vehicle = null


func _radio_allowed(veh: Node) -> bool:
	var vc = veh.get("vclass")
	if vc != null and StringName(vc) == GC.VC_BICYCLE:
		return false
	var eo = veh.get("engine_on")
	return eo == null or bool(eo)


func _update_activation(delta: float) -> void:
	var target := 0.0
	var target_muffle := 0.0
	if enabled and current != OFF:
		var p = Game.player
		if is_instance_valid(p):
			var cv = p.get("current_vehicle")
			if cv != null and is_instance_valid(cv):
				vehicle = cv
				if _radio_allowed(cv):
					target = 1.0
			elif vehicle != null and is_instance_valid(vehicle) and _radio_allowed(vehicle) and not bool(vehicle.get("is_destroyed")):
				var d: float = (vehicle as Node3D).global_position.distance_to((p as Node3D).global_position)
				if d < OUTSIDE_RANGE:
					target = pow(1.0 - d / OUTSIDE_RANGE, 1.4) * 0.5
					target_muffle = 1.0
	var rate: float = 2.6 if target > gain else 3.5
	gain = move_toward(gain, target, delta * rate)
	muffle = move_toward(muffle, target_muffle, delta * 3.0)
	# bus: level + muffling low-pass when heard from outside
	var db: float = -80.0 if gain <= 0.001 else linear_to_db(gain) - 9.0 * muffle
	Sfx.set_bus_duck("Radio", db)
	var fx: Dictionary = Sfx.get_bus_fx("Radio")
	if fx.has("lp"):
		var lp: AudioEffectLowPassFilter = fx["lp"]
		var idx := AudioServer.get_bus_index("Radio")
		if muffle > 0.02:
			lp.cutoff_hz = 20000.0 * pow(650.0 / 20000.0, muffle)
			if not AudioServer.is_bus_effect_enabled(idx, int(fx["lp_idx"])):
				AudioServer.set_bus_effect_enabled(idx, int(fx["lp_idx"]), true)
		elif AudioServer.is_bus_effect_enabled(idx, int(fx["lp_idx"])):
			AudioServer.set_bus_effect_enabled(idx, int(fx["lp_idx"]), false)


# ---- generator feeding -----------------------------------------------------------------------------------------------
func _feed() -> void:
	var avail := _pb.get_frames_available()
	var budget := 9000
	while avail > 512 and budget > 0:
		if _cur_pos >= _cur.size():
			if not _next_phrase():
				break
		var n := mini(mini(avail, _cur.size() - _cur_pos), 4096)
		_pb.push_buffer(_cur.slice(_cur_pos, _cur_pos + n))
		_cur_pos += n
		avail -= n
		budget -= n


func _next_phrase() -> bool:
	var st: Station = _stations[current]
	var ph := st.pop_phrase()
	if ph.is_empty():
		return false
	if _fresh_station:
		_fresh_station = false
		var j := st.jingle()
		ph = ph.duplicate()
		var m := mini(j.size(), ph.size())
		for i in m:
			ph[i] += j[i] * 0.55
	_cur = ph
	_cur_pos = 0
	return true


## Test hook: seconds of audio ready in the active station queue.
func buffered_seconds() -> float:
	if current == OFF:
		return 0.0
	var st: Station = _stations[current]
	return float(st.queued()) * float(Music.phrase_samples(st.spec)) / MIX_RATE


func get_station_object(station_id: StringName) -> Station:
	return _stations.get(station_id)
