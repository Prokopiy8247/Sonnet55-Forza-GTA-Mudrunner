extends RefCounted
## Sound recipes: UI / HUD feedback and wanted/busted/wasted stingers. All original, procedural (see synth.gd).
## build(id, variant, rng) returns {"buf": PackedFloat32Array, "sr": int, "loop": bool, "peak": float}.

const Synth = preload("res://gta/code/audio/synth.gd")
const SR := 22050

const IDS := {
	&"ui_click": {"cat": &"ui", "peak": 0.55},
	&"ui_back": {"cat": &"ui", "peak": 0.5},
	&"ui_error": {"cat": &"ui", "peak": 0.55},
	&"ui_confirm": {"cat": &"ui", "peak": 0.6},
	&"ui_cash": {"cat": &"ui", "peak": 0.7},
	&"ui_notify": {"cat": &"ui", "peak": 0.6},
	&"ui_wanted_up": {"cat": &"ui", "peak": 0.8},
	&"ui_wanted_down": {"cat": &"ui", "peak": 0.6},
	&"ui_busted": {"cat": &"ui", "peak": 0.9},
	&"ui_wasted": {"cat": &"ui", "peak": 0.9},
	&"radio_tune": {"cat": &"ui", "peak": 0.5},
}


static func build(id: StringName, v: int, rng: RandomNumberGenerator) -> Dictionary:
	var b: PackedFloat32Array
	match id:
		&"ui_click":
			b = _click(rng)
		&"ui_back":
			b = _back(rng)
		&"ui_error":
			b = _error()
		&"ui_confirm":
			b = _confirm()
		&"ui_cash":
			b = _cash(rng)
		&"ui_notify":
			b = _notify()
		&"ui_wanted_up":
			b = _wanted_up(rng)
		&"ui_wanted_down":
			b = _wanted_down()
		&"ui_busted":
			b = _busted(rng)
		&"ui_wasted":
			b = _wasted(rng)
		&"radio_tune":
			b = _radio_tune(rng)
		_:
			return {}
	return {"buf": b, "sr": SR, "loop": false}


static func _place(dst: PackedFloat32Array, src: PackedFloat32Array, t: float, gain: float = 1.0) -> void:
	Synth.mix_into(dst, src, int(t * SR), gain)


static func _click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.07))
	_place(out, Synth.blip(Synth.Wave.SINE, 2300.0, 0.06, 0.007), 0.0, 0.9)
	_place(out, Synth.blip(Synth.Wave.TRI, 1150.0, 0.05, 0.006), 0.0, 0.4)
	_place(out, Synth.noise_hit(0.012, 0.002, 3500.0, 0.0, rng.randi()), 0.0, 0.25)
	return out


static func _back(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.09))
	_place(out, Synth.blip(Synth.Wave.SINE, 1500.0, 0.05, 0.01), 0.0, 0.7)
	_place(out, Synth.blip(Synth.Wave.SINE, 1000.0, 0.07, 0.014), 0.025, 0.8)
	_place(out, Synth.noise_hit(0.01, 0.002, 2500.0, 0.0, rng.randi()), 0.0, 0.15)
	return out


static func _error() -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.34))
	for k in 2:
		var f: float = 205.0 if k == 0 else 155.0
		var n := Synth.secs(0.12)
		var s := Synth.osc(Synth.Wave.SQUARE, n, f, SR, 0.0, 0.42)
		s = Synth.lowpass(s, 1300.0, 1.2)
		s = Synth.mul(s, Synth.env_adsr(n, 0.004, 0.02, 0.8, 0.03))
		_place(out, s, 0.0 + float(k) * 0.15, 0.7)
	return Synth.reverb(out, 0.2, 0.5, 0.12, SR, 0.1)


static func _confirm() -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.55))
	var notes: Array = [659.25, 987.77]
	for k in notes.size():
		var f: float = notes[k]
		var n := Synth.secs(0.4)
		var s := Synth.osc(Synth.Wave.SINE, n, f)
		s = Synth.add(s, Synth.osc(Synth.Wave.SINE, n, f * 2.0), 0.28)
		s = Synth.add(s, Synth.osc(Synth.Wave.TRI, n, f * 0.5), 0.2)
		s = Synth.mul(s, Synth.env_decay(n, 0.11, SR, 0.004))
		_place(out, s, float(k) * 0.085, 0.6)
	return Synth.reverb(out, 0.35, 0.4, 0.2, SR, 0.2)


static func _cash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.8))
	var parts_a: Array = [[2093.0, 0.14, 1.0], [2637.0, 0.1, 0.55], [3136.0, 0.16, 0.8], [5274.0, 0.05, 0.3], [4186.0, 0.06, 0.25]]
	var ping_a := Synth.modal(Synth.secs(0.5), parts_a)
	_place(out, ping_a, 0.0, 0.5)
	var parts_b: Array = [[3136.0, 0.2, 1.0], [3951.0, 0.14, 0.6], [4699.0, 0.1, 0.45], [6272.0, 0.05, 0.3], [7902.0, 0.03, 0.2]]
	var ping_b := Synth.modal(Synth.secs(0.6), parts_b)
	_place(out, ping_b, 0.07, 0.6)
	# coin shimmer: a few quick metallic ticks
	for k in 6:
		var t: float = 0.1 + float(k) * 0.035 + rng.randf() * 0.01
		var f: float = rng.randf_range(4200.0, 7800.0)
		_place(out, Synth.modal(Synth.secs(0.08), [[f, 0.018, 1.0], [f * 1.51, 0.012, 0.5]]), t, 0.22)
	_place(out, Synth.noise_hit(0.02, 0.004, 5000.0, 0.0, rng.randi()), 0.0, 0.3)
	return Synth.reverb(out, 0.3, 0.3, 0.12, SR, 0.2)


static func _notify() -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.9))
	var a: Array = [[880.0, 0.28, 1.0], [2112.0, 0.1, 0.4], [3510.0, 0.06, 0.2], [1320.0, 0.2, 0.2]]
	_place(out, Synth.modal(Synth.secs(0.7), a), 0.0, 0.55)
	var b: Array = [[1318.5, 0.3, 1.0], [3165.0, 0.1, 0.4], [4800.0, 0.05, 0.2]]
	_place(out, Synth.modal(Synth.secs(0.7), b), 0.13, 0.5)
	return Synth.reverb(out, 0.5, 0.35, 0.25, SR, 0.3)


static func _wanted_up(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(1.4))
	for k in 2:
		var n := Synth.secs(0.34)
		var f0: float = 330.0 if k == 0 else 440.0
		var s := Synth.osc_sweep(Synth.Wave.SAW, n, f0, f0 * 2.0)
		s = Synth.add(s, Synth.osc_sweep(Synth.Wave.SAW, n, f0 * 1.007, f0 * 2.014), 0.8)
		s = Synth.lowpass(s, 2600.0, 1.0)
		s = Synth.mul(s, Synth.env_adsr(n, 0.01, 0.1, 0.65, 0.12))
		_place(out, s, float(k) * 0.3, 0.55)
	_place(out, Synth.thump(0.9, 90.0, 38.0, 0.28), 0.0, 0.9)
	var riser := Synth.mul(Synth.noise(Synth.secs(0.9), rng.randi()), Synth.env_swell(Synth.secs(0.9), 0.85, 2.0))
	_place(out, Synth.band(riser, 900.0, 4500.0), 0.0, 0.35)
	return Synth.reverb(Synth.soft_clip(out, 1.4), 0.55, 0.4, 0.22, SR, 0.5)


static func _wanted_down() -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(1.2))
	var notes: Array = [1046.5, 783.99, 659.25, 523.25]
	for k in notes.size():
		var f: float = notes[k]
		var n := Synth.secs(0.5)
		var s := Synth.osc(Synth.Wave.SINE, n, f)
		s = Synth.add(s, Synth.osc(Synth.Wave.TRI, n, f * 2.0), 0.1)
		s = Synth.mul(s, Synth.env_decay(n, 0.17, SR, 0.005))
		_place(out, s, float(k) * 0.14, 0.55 - float(k) * 0.04)
	return Synth.reverb(out, 0.6, 0.4, 0.25, SR, 0.4)


static func _busted(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(2.0))
	_place(out, Synth.thump(1.3, 85.0, 32.0, 0.38), 0.0, 1.0)
	# descending brass-like saw chord
	var n := Synth.secs(1.3)
	var chord := Synth.zeros(n)
	for f0 in [196.0, 233.1, 293.7]:
		var s := Synth.osc_sweep(Synth.Wave.SAW, n, f0, f0 * 0.72)
		s = Synth.add(s, Synth.osc_sweep(Synth.Wave.SAW, n, f0 * 1.006, f0 * 0.725), 0.7)
		chord = Synth.add(chord, s, 0.35)
	chord = Synth.biquad_sweep(chord, Synth.Filt.LP, Synth.expramp(n, 2400.0, 380.0), 1.4)
	chord = Synth.mul(chord, Synth.env_adsr(n, 0.015, 0.3, 0.6, 0.5))
	_place(out, chord, 0.0, 0.7)
	# handcuff clink
	var clink: Array = [[3100.0, 0.05, 1.0], [4300.0, 0.04, 0.6], [5900.0, 0.03, 0.4], [2200.0, 0.06, 0.5]]
	_place(out, Synth.modal(Synth.secs(0.3), clink), 0.42, 0.4)
	_place(out, Synth.modal(Synth.secs(0.3), clink), 0.52, 0.28)
	_place(out, Synth.noise_hit(0.05, 0.01, 1500.0, 6000.0, rng.randi()), 0.0, 0.6)
	return Synth.reverb(out, 0.7, 0.5, 0.3, SR, 0.6)


static func _wasted(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var total := 2.6
	var n := Synth.secs(total)
	var out := Synth.zeros(n)
	# reversed swell (cymbal-ish) leading into the hit
	var sw := Synth.mul(Synth.highpass(Synth.noise(Synth.secs(1.0), rng.randi()), 2200.0), Synth.env_swell(Synth.secs(1.0), 0.97, 2.5))
	_place(out, sw, 0.0, 0.4)
	# low drone dropping in pitch (slow-motion death)
	var dn := Synth.secs(2.4)
	var drone := Synth.osc_sweep(Synth.Wave.SAW, dn, 110.0, 38.0)
	drone = Synth.add(drone, Synth.osc_sweep(Synth.Wave.SAW, dn, 111.5, 38.4), 0.8)
	drone = Synth.biquad_sweep(drone, Synth.Filt.LP, Synth.expramp(dn, 1500.0, 140.0), 1.2)
	drone = Synth.mul(drone, Synth.env_adsr(dn, 0.9, 0.3, 0.8, 1.0))
	_place(out, drone, 0.2, 0.5)
	# heartbeat-like thuds that slow down
	var beats: Array = [0.95, 1.35, 1.9]
	for k in beats.size():
		_place(out, Synth.thump(0.4, 75.0, 38.0, 0.1), float(beats[k]), 0.85 - float(k) * 0.2)
		_place(out, Synth.thump(0.3, 95.0, 50.0, 0.06), float(beats[k]) + 0.17, 0.5 - float(k) * 0.12)
	return Synth.reverb(out, 0.8, 0.5, 0.3, SR, 0.8)


## Dial-twiddling radio static: band-passed noise whose centre sweeps across the "band" with faint carrier whistles.
static func _radio_tune(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := Synth.secs(0.42)
	var src := Synth.noise(n, rng.randi())
	var fc := Synth.expramp(n, 500.0, 3800.0)
	var hiss := Synth.biquad_sweep(src, Synth.Filt.BP, fc, 1.4)
	var gate := Synth.smooth_random(n, 24.0, SR, rng.randi())
	var out := Synth.zeros(n)
	for i in n:
		out[i] = hiss[i] * (0.4 + 0.9 * gate[i])
	var whistle := Synth.osc_sweep(Synth.Wave.SINE, n, 1900.0, 700.0)
	whistle = Synth.mul(whistle, Synth.env_points(n, [[0.0, 0.0], [0.05, 0.5], [0.2, 0.2], [0.42, 0.0]]))
	out = Synth.add(out, whistle, 0.25)
	return Synth.mul(out, Synth.env_points(n, [[0.0, 0.0], [0.02, 1.0], [0.3, 0.7], [0.42, 0.0]]))
