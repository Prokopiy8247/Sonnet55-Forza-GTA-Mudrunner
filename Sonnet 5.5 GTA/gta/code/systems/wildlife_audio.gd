class_name WildlifeAudio
extends Node
## Creature sounds. Ids that exist in the shared bank (`gull`, `bird`, `splash`, `splash_big`, `hit_flesh`) are played through Sfx; the few that
## the bank does not have (dog bark, cow moo, coyote growl, shark sting, dolphin whistles, bubble blub) are synthesised here on first use with
## the project's own Synth toolkit (no samples) and played from a small pool of 3D players on the SFX bus. The audio bank itself is untouched.

const Synth = preload("res://gta/code/audio/synth.gd")
const POOL := 10

static var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _last_played: Dictionary = {}


func setup(parent: Node) -> void:
	name = "WildlifeAudio"
	parent.add_child(self)
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_players.append(p)


func has(id: StringName) -> bool:
	return Sfx.has_sound(id) or _make(id) != null


## Plays `id` at `pos`. Rate limited per id (0.12 s) so a panicking herd does not stack voices.
func play(id: StringName, pos: Vector3, db: float = 0.0, pitch: float = 1.0, max_dist: float = 60.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -1000)) < 120:
		return
	_last_played[id] = now
	if Sfx.has_sound(id):
		Sfx.play_3d(id, pos, db, pitch, max_dist)
		return
	var stream := _make(id)
	if stream == null or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.global_position = pos
	p.volume_db = db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.play()


static func _make(id: StringName) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var buf := PackedFloat32Array()
	match id:
		&"dog_bark":
			buf = _dog_bark()
		&"cow_moo":
			buf = _moo()
		&"coyote_growl":
			buf = _growl()
		&"shark_sting":
			buf = _sting()
		&"dolphin":
			buf = _dolphin()
		&"bubble":
			buf = _bubble(0)
		&"bubble_big":
			buf = _bubble(1)
		_:
			_cache[id] = null
			return null
	var wav := Synth.to_wav(Synth.sanitize(Synth.normalize(buf, 0.85)))
	_cache[id] = wav
	return wav


static func _dog_bark() -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.62))
	for k in 2:
		var n := Synth.secs(0.17)
		var f0 := 520.0 - 70.0 * k
		var tone := Synth.harmonics(n, f0, 6, 0.75)
		var sweep := Synth.osc_sweep(Synth.Wave.SAW, n, f0 * 1.15, f0 * 0.72)
		var body := Synth.add(tone, sweep, 0.6)
		body = Synth.formants(body, [[700.0, 160.0, 1.0], [1350.0, 200.0, 0.7], [2400.0, 260.0, 0.3]])
		var grit := Synth.noise_hit(0.17, 0.05, 900.0, 3200.0, 7 + k, Synth.SR, 0.3)
		body = Synth.add(body, grit, 1.0)
		body = Synth.mul(body, Synth.env_decay(n, 0.06, Synth.SR, 0.004))
		Synth.mix_into(out, body, Synth.secs(0.02 + 0.27 * k), 1.0)
	return out


static func _moo() -> PackedFloat32Array:
	var n := Synth.secs(1.5)
	var vib := Synth.lfo(n, 4.6, 1.0, 0.025)
	var f := Synth.expramp(n, 128.0, 104.0)
	var fv := PackedFloat32Array()
	fv.resize(n)
	for i in n:
		fv[i] = f[i] * vib[i]
	var s := Synth.osc_f(Synth.Wave.SAW, fv)
	s = Synth.formants(s, [[480.0, 120.0, 1.0], [980.0, 160.0, 0.6], [2100.0, 260.0, 0.18]])
	return Synth.mul(s, Synth.env_swell(n, 0.35, 1.0))


static func _growl() -> PackedFloat32Array:
	var n := Synth.secs(1.1)
	var rumble := Synth.osc(Synth.Wave.SAW, n, 74.0)
	var am := Synth.lfo(n, 23.0, 0.65, 0.35)
	var s := Synth.mul(rumble, am)
	s = Synth.add(s, Synth.lowpass(Synth.noise(n, 3), 700.0), 0.35)
	s = Synth.formants(s, [[320.0, 100.0, 1.0], [900.0, 180.0, 0.5]])
	return Synth.mul(s, Synth.env_swell(n, 0.4, 1.0))


static func _sting() -> PackedFloat32Array:
	var n := Synth.secs(1.9)
	var a := Synth.osc(Synth.Wave.TRI, n, 82.4)
	var b := Synth.osc(Synth.Wave.TRI, n, 87.3)
	var s := Synth.add(a, b, 1.0)
	s = Synth.add(s, Synth.osc(Synth.Wave.SINE, n, 41.2), 0.8)
	var trem := Synth.lfo(n, 5.5, 0.75, 0.25)
	s = Synth.mul(s, trem)
	return Synth.mul(s, Synth.env_swell(n, 0.5, 1.4))


static func _dolphin() -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.9))
	for k in 3:
		var n := Synth.secs(0.2)
		var up := Synth.osc_sweep(Synth.Wave.SINE, n, 2200.0 + 300.0 * k, 5200.0 - 400.0 * k)
		up = Synth.mul(up, Synth.env_swell(n, 0.4, 1.0))
		Synth.mix_into(out, up, Synth.secs(0.05 + 0.26 * k), 0.7)
	for c in 6:
		Synth.mix_into(out, Synth.blip(Synth.Wave.SINE, 6200.0, 0.01, 0.003), Synth.secs(0.02 * c), 0.25)
	return out


static func _bubble(variant: int) -> PackedFloat32Array:
	var dur := 0.09 if variant == 0 else 0.16
	var n := Synth.secs(dur)
	var f0 := 260.0 if variant == 0 else 150.0
	var s := Synth.osc_sweep(Synth.Wave.SINE, n, f0, f0 * 3.2)
	return Synth.mul(s, Synth.env_decay(n, dur * 0.35, Synth.SR, 0.003))
