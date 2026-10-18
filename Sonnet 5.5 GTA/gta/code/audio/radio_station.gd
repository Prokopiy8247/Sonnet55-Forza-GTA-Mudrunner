extends RefCounted
## RadioStation - state of one generative station: seeded composer state + a thread-safe queue of rendered phrases.
## render_phrase() runs on a WorkerThreadPool thread (request_fill) and never touches the scene tree.

const Music = preload("res://gta/code/audio/radio_music.gd")

var id: StringName
var spec: Dictionary
var display_name := ""
var tagline := ""
var phrase_index := 0
var phrases_rendered := 0
var last_render_ms := 0.0

var _rng := RandomNumberGenerator.new()
var _motif_state: Dictionary = {}
var _cache: Dictionary = {}
var _carry := PackedVector2Array()
var _queue: Array = []
var _mutex := Mutex.new()
var _busy := false
var _jingle: PackedVector2Array = PackedVector2Array()


func _init(station_id: StringName) -> void:
	id = station_id
	spec = Music.STATIONS[station_id]
	display_name = String(spec["name"])
	tagline = String(spec["tag"])
	_rng.seed = int(spec["seed"])
	# every session starts at a different point of the 8-phrase song form (never the sparse intro / break)
	phrase_index = 1 + int(Time.get_ticks_usec() % 5)


func queued() -> int:
	_mutex.lock()
	var n := _queue.size()
	_mutex.unlock()
	return n


func is_busy() -> bool:
	return _busy


## Pops the next rendered phrase (stereo frames) or an empty array when none is ready.
func pop_phrase() -> PackedVector2Array:
	_mutex.lock()
	var out := PackedVector2Array()
	if not _queue.is_empty():
		out = _queue.pop_front()
	_mutex.unlock()
	return out


## Schedules one background render if fewer than `target` phrases are queued and no render is running.
func request_fill(target: int = 2) -> void:
	if _busy:
		return
	if queued() >= target:
		return
	_busy = true
	WorkerThreadPool.add_task(_task, false, "Radio " + String(id))


func jingle() -> PackedVector2Array:
	if _jingle.is_empty():
		_jingle = Music.jingle(spec)
	return _jingle


func _task() -> void:
	var t0 := Time.get_ticks_usec()
	var frames := render_phrase()
	_mutex.lock()
	_queue.append(frames)
	_mutex.unlock()
	last_render_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	phrases_rendered += 1
	_busy = false


## Synchronously composes and renders the next phrase (also used by tests / the bake tool).
func render_phrase() -> PackedVector2Array:
	var idx := phrase_index
	phrase_index += 1
	_rng.seed = int(spec["seed"]) * 1009 + idx * 7919
	var events := Music.compose(spec, idx, _rng, _motif_state)
	var res := Music.render(spec, events, _carry, _cache, int(spec["seed"]) + idx * 131)
	_carry = res["carry"]
	return res["frames"]
