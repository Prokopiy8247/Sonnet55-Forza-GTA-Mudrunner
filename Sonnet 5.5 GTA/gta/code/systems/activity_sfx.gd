class_name ActivitySfx
extends RefCounted
## Procedural activity sounds (countdown beeps, checkpoint chime, target ping, finish arpeggio). Generated once into AudioStreamWAV
## (16 bit mono) - no files. ActivitySystem plays them through a few pooled AudioStreamPlayers on the UI bus.

const RATE := 22050
static var _cache: Dictionary = {}


## ids: beep (countdown tick), go, chime (checkpoint), ping (target hit), bull (bullseye), buzz (penalty), finish, warn, tick
static func get_stream(id: StringName) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var s: AudioStreamWAV = null
	match id:
		&"beep":
			s = _make([[620.0, 620.0, 0.16, 0.5, 5.0]])
		&"go":
			s = _make([[880.0, 1320.0, 0.50, 0.55, 3.0]])
		&"chime":
			s = _make([[880.0, 880.0, 0.09, 0.45, 3.0], [1320.0, 1320.0, 0.20, 0.45, 5.0]])
		&"ping":
			s = _make([[2300.0, 1500.0, 0.10, 0.4, 7.0]])
		&"bull":
			s = _make([[1800.0, 1800.0, 0.06, 0.45, 4.0], [2700.0, 2700.0, 0.18, 0.45, 6.0]])
		&"buzz":
			s = _make([[170.0, 110.0, 0.30, 0.6, 3.0]], 0.5)
		&"finish":
			s = _make([[523.0, 523.0, 0.11, 0.45, 3.0], [659.0, 659.0, 0.11, 0.45, 3.0], [784.0, 784.0, 0.11, 0.45, 3.0], [1047.0, 1047.0, 0.45, 0.5, 4.0]])
		&"warn":
			s = _make([[440.0, 440.0, 0.10, 0.5, 2.0], [330.0, 330.0, 0.16, 0.5, 3.0]], 0.3)
		&"tick":
			s = _make([[1400.0, 1400.0, 0.03, 0.35, 8.0]])
		_:
			return null
	_cache[id] = s
	return s


## segments: [freq_start, freq_end, duration, volume, decay]; noise: 0..1 grit mixed into the tone (buzzers).
static func _make(segments: Array, noise: float = 0.0) -> AudioStreamWAV:
	var total := 0
	for seg in segments:
		total += int(float(seg[2]) * RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	var pos := 0
	var phase := 0.0
	for seg in segments:
		var f0: float = seg[0]
		var f1: float = seg[1]
		var dur: float = seg[2]
		var vol: float = seg[3]
		var decay: float = seg[4]
		var n := int(dur * RATE)
		for i in n:
			var t := float(i) / RATE
			var k := t / dur
			phase += TAU * lerpf(f0, f1, k) / RATE
			var env := minf(t / 0.004, 1.0) * exp(-decay * k) * minf((dur - t) / 0.01, 1.0)
			var v := sin(phase) + 0.32 * sin(phase * 2.0) + 0.12 * sin(phase * 3.0)
			if noise > 0.0:
				v = lerpf(v, signf(sin(phase * 0.5)) * 0.8, noise)
			data.encode_s16((pos + i) * 2, int(clampf(v * env * vol * 0.55, -1.0, 1.0) * 32000.0))
		pos += n
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
