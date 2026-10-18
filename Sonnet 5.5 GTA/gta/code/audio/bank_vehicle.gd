extends RefCounted
## Sound recipes: horns, tyre squeal, crashes, sirens (wail / yelp / two-tone / fire), vehicle doors, ignition, engine-off,
## turbo whistle, exhaust burble/pops and gear-shift thunk (the one-shot engine accents used by EngineSound).

const Synth = preload("res://gta/code/audio/synth.gd")
const SR := 22050

const IDS := {
	&"horn_car": {"cat": &"horn", "var": 1, "peak": 0.75, "oneshot": 0.7},
	&"horn_truck": {"cat": &"horn", "var": 1, "peak": 0.85, "oneshot": 1.0, "unit": 32.0},
	&"horn_bike": {"cat": &"horn", "var": 1, "peak": 0.65, "oneshot": 0.45, "unit": 16.0},
	&"horn_fire": {"cat": &"horn", "var": 1, "peak": 0.9, "oneshot": 1.6, "unit": 45.0},
	&"skid": {"cat": &"vehicle", "var": 2, "peak": 0.55, "unit": 14.0, "oneshot": 1.0},
	&"crash_light": {"cat": &"vehicle", "var": 3, "peak": 0.8, "unit": 18.0},
	&"crash_heavy": {"cat": &"vehicle", "var": 2, "peak": 1.0, "unit": 35.0, "range": 170.0},
	&"siren_police": {"cat": &"siren", "var": 1, "peak": 0.7, "oneshot": 6.4},
	&"siren_police_yelp": {"cat": &"siren", "var": 1, "peak": 0.7, "oneshot": 4.5},
	&"siren_ambulance": {"cat": &"siren", "var": 1, "peak": 0.7, "oneshot": 6.0},
	&"siren_fire": {"cat": &"siren", "var": 1, "peak": 0.75, "oneshot": 8.8},
	&"door_vehicle_open": {"cat": &"vehicle", "var": 2, "peak": 0.65, "unit": 8.0},
	&"door_vehicle_close": {"cat": &"vehicle", "var": 2, "peak": 0.8, "unit": 10.0},
	&"ignition": {"cat": &"vehicle", "var": 2, "peak": 0.7, "unit": 10.0},
	&"engine_off": {"cat": &"vehicle", "var": 1, "peak": 0.6, "unit": 9.0},
	&"turbo_whistle": {"cat": &"engine_fx", "var": 1, "peak": 0.5, "unit": 10.0},
	&"engine_burble": {"cat": &"engine_fx", "var": 4, "peak": 0.7, "unit": 16.0},
	&"engine_shift": {"cat": &"engine_fx", "var": 2, "peak": 0.5, "unit": 8.0},
}


static func build(id: StringName, v: int, rng: RandomNumberGenerator) -> Dictionary:
	match id:
		&"horn_car":
			return _horn([[420.0, 1.0], [540.0, 0.85]], 0.5, 0.35, 3400.0, 1)
		&"horn_truck":
			return _horn([[196.0, 1.0], [246.0, 0.9], [392.0, 0.35]], 0.5, 0.3, 2200.0, 1)
		&"horn_bike":
			return _horn([[600.0, 1.0], [900.0, 0.4]], 0.5, 0.4, 4200.0, 1)
		&"horn_fire":
			return _horn([[174.0, 1.0], [220.0, 0.9], [348.0, 0.5], [440.0, 0.4]], 0.5, 0.28, 2600.0, 1)
		&"skid":
			return _skid(rng, v)
		&"crash_light":
			return {"buf": _crash(rng, false), "sr": SR, "loop": false}
		&"crash_heavy":
			return {"buf": _crash(rng, true), "sr": SR, "loop": false}
		&"siren_police":
			return _siren_sweep(3.2, 640.0, 1480.0, 0.0)
		&"siren_police_yelp":
			return _siren_sweep(1.12, 620.0, 1420.0, 0.0, 4)
		&"siren_ambulance":
			return _siren_two_tone(960.0, 770.0, 0.5, 2)
		&"siren_fire":
			return _siren_sweep(4.4, 430.0, 960.0, 0.4)
		&"door_vehicle_open":
			return {"buf": _door(rng, true), "sr": SR, "loop": false}
		&"door_vehicle_close":
			return {"buf": _door(rng, false), "sr": SR, "loop": false}
		&"ignition":
			return {"buf": _ignition(rng, v), "sr": SR, "loop": false}
		&"engine_off":
			return {"buf": _engine_off(rng), "sr": SR, "loop": false}
		&"turbo_whistle":
			return {"buf": _turbo(rng), "sr": SR, "loop": false}
		&"engine_burble":
			return {"buf": _burble(rng, v), "sr": SR, "loop": false}
		&"engine_shift":
			return {"buf": _shift(rng, v), "sr": SR, "loop": false}
	return {}


static func _place(dst: PackedFloat32Array, src: PackedFloat32Array, t: float, gain: float = 1.0) -> void:
	Synth.mix_into(dst, src, int(t * SR), gain)


## Sustained horn: a short attack segment followed by a seamless loop region. All tone frequencies are chosen so
## they complete an integer number of cycles inside the 0.5 s loop (frequencies are multiples of 2 Hz).
static func _horn(tones: Array, loop_s: float, pw: float, lp_hz: float, _unused: int) -> Dictionary:
	var attack_s := 0.07
	var n_loop := Synth.secs(loop_s)
	var n_att := Synth.secs(attack_s)
	var n := n_att + n_loop
	var out := Synth.zeros(n)
	for t in tones:
		var f: float = t[0]
		var g: float = t[1]
		var s := Synth.osc(Synth.Wave.SQUARE, n, f, SR, 0.0, pw)
		out = Synth.add(out, s, g * 0.5)
	# reed buzz + diaphragm body resonance
	out = Synth.lowpass(out, lp_hz, 0.9)
	out = Synth.biquad(out, Synth.Filt.PEAK, 1400.0, 1.2, SR, 5.0)
	# attack ramp only over the first segment (the loop region itself stays at full level)
	for i in n_att:
		out[i] *= float(i) / float(n_att)
	return {"buf": out, "sr": SR, "loop": true, "loop_begin": n_att, "loop_end": n}


static func _skid(rng: RandomNumberGenerator, v: int) -> Dictionary:
	var n := Synth.secs(1.2)
	var wob := Synth.smooth_random(n, 7.0, SR, rng.randi())
	var fc := PackedFloat32Array()
	fc.resize(n)
	var center: float = 2100.0 + 260.0 * float(v)
	for i in n:
		fc[i] = center * (0.88 + 0.28 * wob[i])
	var s := Synth.noise(n, rng.randi())
	s = Synth.biquad_sweep(s, Synth.Filt.BP, fc, 7.0)
	var tone := Synth.osc_f(Synth.Wave.SAW, Synth.scale(fc, 0.5))
	tone = Synth.lowpass(tone, 3500.0)
	var amp := Synth.smooth_random(n, 11.0, SR, rng.randi())
	var out := Synth.zeros(n)
	for i in n:
		out[i] = (s[i] * 2.2 + tone[i] * 0.25) * (0.7 + 0.3 * amp[i])
	out = Synth.add(out, Synth.band(Synth.noise(n, rng.randi()), 900.0, 4200.0), 0.12)
	out = Synth.make_loop(out, 0.12)
	return {"buf": out, "sr": SR, "loop": true}


static func _crash(rng: RandomNumberGenerator, heavy: bool) -> PackedFloat32Array:
	var dur: float = 1.7 if heavy else 0.8
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	var s: float = 1.0 if heavy else 0.55
	_place(out, Synth.thump(0.5 * s + 0.15, 120.0, 40.0, 0.12 * s + 0.04), 0.0, 1.0)
	# crunching metal: broadband noise with swept lowpass
	var cn := Synth.noise(n, rng.randi())
	cn = Synth.biquad_sweep(cn, Synth.Filt.LP, Synth.expramp(n, 6500.0, 500.0), 0.9)
	cn = Synth.mul(cn, Synth.env_decay(n, 0.2 * s + 0.07, SR, 0.001))
	_place(out, cn, 0.0, 0.9)
	# detuned metal modes
	var f: float = rng.randf_range(0.85, 1.2)
	_place(out, Synth.modal(Synth.secs(0.6 * s + 0.2), [[170.0 * f, 0.1, 0.9], [420.0 * f, 0.08, 0.7], [870.0 * f, 0.06, 0.55], [1430.0 * f, 0.045, 0.4], [2300.0 * f, 0.03, 0.3]]), 0.0, 0.5)
	# rattle / debris
	var deb := Synth.band(Synth.crackle(n, 120.0 * s + 40.0, SR, rng.randi(), 0.005), 700.0, 6000.0)
	_place(out, Synth.mul(deb, Synth.env_decay(n, 0.5 * s + 0.15)), 0.05, 0.8)
	# glass tinkle (heavy only)
	if heavy:
		for k in 16:
			var ff: float = rng.randf_range(3000.0, 8500.0)
			_place(out, Synth.modal(Synth.secs(0.15), [[ff, 0.035, 1.0]]), 0.08 + rng.randf() * 0.7, rng.randf_range(0.1, 0.3))
	return Synth.reverb(Synth.soft_clip(out, 1.4), 0.4, 0.5, 0.14, SR, 0.3)


## Looping wail: the instantaneous frequency follows an exponential cosine sweep lo <-> hi over `period` seconds. The
## total phase advance is rescaled to an integer number of cycles so the loop seam is perfectly continuous.
static func _siren_sweep(period: float, lo: float, hi: float, rough: float, cycles: int = 1) -> Dictionary:
	var n := Synth.secs(period)
	var f := PackedFloat32Array()
	f.resize(n)
	var ratio: float = hi / lo
	var total_ph: float = 0.0
	for i in n:
		var u: float = float(i) / float(n) * float(cycles)
		var shape: float = 0.5 - 0.5 * cos(u * TAU)
		var hz: float = lo * pow(ratio, shape)
		f[i] = hz
		total_ph += hz / float(SR)
	var target_ph: float = round(total_ph)
	if rough > 0.0 and int(target_ph) % 2 == 1:
		target_ph += 1.0   # the sub-octave layer needs an even number of cycles to stay seamless
	var k: float = target_ph / total_ph
	for i in n:
		f[i] *= k
	var s := Synth.osc_f(Synth.Wave.SAW, f)
	var s2 := Synth.osc_f(Synth.Wave.SQUARE, Synth.scale(f, 1.0), SR, 0.0, 0.4)
	var out := Synth.add(s, s2, 0.7)
	if rough > 0.0:
		var f3 := Synth.scale(f, 0.5)
		out = Synth.add(out, Synth.osc_f(Synth.Wave.SAW, f3), rough)
	# horn-driver / cone resonance and a little grit (circular so the loop seam stays clean)
	out = Synth.circular(out, _siren_filter)
	out = Synth.soft_clip(out, 1.6)
	return {"buf": out, "sr": SR, "loop": true}


static func _siren_filter(b: PackedFloat32Array) -> PackedFloat32Array:
	var o := Synth.biquad(b, Synth.Filt.PEAK, 1100.0, 0.8, SR, 6.0)
	return Synth.lowpass(o, 4200.0, 0.8)


static func _two_tone_filter(b: PackedFloat32Array) -> PackedFloat32Array:
	var o := Synth.lowpass(b, 3600.0, 0.8)
	return Synth.biquad(o, Synth.Filt.PEAK, 1500.0, 0.9, SR, 4.0)


static func _siren_two_tone(f_hi: float, f_lo: float, each: float, repeats: int) -> Dictionary:
	# frequency track with short cosine glides between the two tones; scaled so the loop has an integer number of cycles
	var n_each := Synth.secs(each)
	var n := n_each * 2 * repeats
	var f := PackedFloat32Array()
	f.resize(n)
	var glide: int = int(0.018 * float(SR))
	var total_ph: float = 0.0
	for i in n:
		var seg: int = (i / n_each) % 2
		var cur: float = f_hi if seg == 0 else f_lo
		var prev: float = f_lo if seg == 0 else f_hi
		var pos: int = i % n_each
		var hz: float = cur
		if pos < glide:
			var u: float = 0.5 - 0.5 * cos(float(pos) / float(glide) * PI)
			hz = lerpf(prev, cur, u)
		f[i] = hz
		total_ph += hz / float(SR)
	var k: float = round(total_ph) / total_ph
	for i in n:
		f[i] *= k
	var buf := Synth.osc_f(Synth.Wave.SQUARE, f, SR, 0.0, 0.45)
	buf = Synth.add(buf, Synth.osc_f(Synth.Wave.SAW, Synth.scale(f, 2.0)), 0.25)
	buf = Synth.circular(buf, _two_tone_filter)
	buf = Synth.soft_clip(buf, 1.4)
	return {"buf": buf, "sr": SR, "loop": true}


static func _door(rng: RandomNumberGenerator, open: bool) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.55))
	var f: float = rng.randf_range(0.92, 1.1)
	if open:
		_place(out, Synth.modal(Synth.secs(0.12), [[900.0 * f, 0.014, 1.0], [1800.0 * f, 0.01, 0.6], [3100.0 * f, 0.006, 0.3]]), 0.0, 0.8)
		_place(out, Synth.thump(0.15, 180.0 * f, 90.0, 0.03), 0.01, 0.6)
		_place(out, Synth.mul(Synth.band(Synth.noise(Synth.secs(0.12), rng.randi()), 300.0, 2500.0), Synth.env_swell(Synth.secs(0.12), 0.3)), 0.0, 0.3)
	else:
		_place(out, Synth.thump(0.3, 125.0 * f, 50.0, 0.07), 0.0, 1.0)
		_place(out, Synth.noise_hit(0.14, 0.03, 180.0, 2400.0, rng.randi()), 0.0, 0.7)
		_place(out, Synth.modal(Synth.secs(0.12), [[1100.0 * f, 0.012, 1.0], [2400.0 * f, 0.008, 0.6]]), 0.05, 0.55)
		_place(out, Synth.modal(Synth.secs(0.4), [[240.0 * f, 0.1, 0.5], [540.0 * f, 0.07, 0.3]]), 0.0, 0.4)
	return out


static func _ignition(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur := 1.9
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	var crank_len: float = 0.85 + 0.2 * float(v)
	# starter motor: whirring saw pulsed by the cylinders' compression strokes
	var nc := Synth.secs(crank_len)
	var starter := Synth.osc_sweep(Synth.Wave.SAW, nc, 70.0, 105.0)
	starter = Synth.add(starter, Synth.osc_sweep(Synth.Wave.SAW, nc, 280.0, 420.0), 0.25)
	starter = Synth.lowpass(starter, 1500.0, 1.0)
	var chug := Synth.lfo(nc, 8.5 + float(v), 0.55, 0.45)
	starter = Synth.mul(starter, chug)
	starter = Synth.mul(starter, Synth.env_adsr(nc, 0.08, 0.1, 0.9, 0.06))
	_place(out, starter, 0.0, 0.5)
	# the engine catches: a few uneven firing thumps that settle into an idle burble
	var t: float = crank_len - 0.1
	for k in 6:
		var gap: float = 0.16 - 0.015 * float(k)
		_place(out, Synth.thump(0.14, 120.0 - 4.0 * float(k), 52.0, 0.04 + 0.004 * float(k)), t, 0.85 - 0.04 * float(k))
		_place(out, Synth.noise_hit(0.08, 0.015, 150.0, 1800.0, rng.randi()), t, 0.35)
		t += gap
	# settling idle rumble tail
	var tail_n := Synth.secs(1.0)
	var tail := Synth.lowpass(Synth.osc(Synth.Wave.SAW, tail_n, 27.0), 240.0)
	tail = Synth.mul(Synth.add(tail, Synth.lowpass(Synth.noise(tail_n, rng.randi()), 180.0), 0.5), Synth.env_points(tail_n, [[0.0, 0.0], [0.15, 0.9], [1.0, 0.3]]))
	_place(out, tail, t - 0.1, 0.55)
	return Synth.soft_clip(out, 1.3)


static func _engine_off(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.9
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	# decaying firing pulses: rate falls from ~28 Hz to ~6 Hz
	var t: float = 0.0
	var rate: float = 28.0
	while t < 0.55:
		var amp: float = 0.9 * (1.0 - t / 0.7)
		_place(out, Synth.thump(0.1, 90.0 * (rate / 28.0) + 30.0, 40.0, 0.03), t, amp)
		t += 1.0 / rate
		rate = maxf(rate * 0.955, 5.0)
	# rumble fading
	var rn := Synth.lowpass(Synth.noise(n, rng.randi()), 200.0)
	_place(out, Synth.mul(rn, Synth.env_decay(n, 0.2)), 0.0, 0.7)
	# relay clunk + metal ticking as it cools
	_place(out, Synth.modal(Synth.secs(0.1), [[1200.0, 0.01, 1.0], [2600.0, 0.006, 0.5]]), 0.58, 0.4)
	for k in 3:
		_place(out, Synth.modal(Synth.secs(0.1), [[3300.0 + 300.0 * float(k), 0.025, 1.0]]), 0.65 + 0.07 * float(k), 0.1)
	return out


static func _turbo(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.2
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	var wn := Synth.secs(0.7)
	var f := Synth.expramp(wn, 2300.0, 5600.0)
	var tone := Synth.osc_f(Synth.Wave.SINE, f)
	tone = Synth.add(tone, Synth.osc_f(Synth.Wave.SINE, Synth.scale(f, 2.0)), 0.2)
	var flutter := Synth.lfo(wn, 38.0, 0.85, 0.15)
	tone = Synth.mul(tone, flutter)
	tone = Synth.mul(tone, Synth.env_points(wn, [[0.0, 0.0], [0.4, 0.8], [0.62, 1.0], [0.7, 0.0]]))
	_place(out, tone, 0.0, 0.5)
	# air hiss riding with the whistle
	var hn := Synth.band(Synth.noise(wn, rng.randi()), 3000.0, 7500.0)
	_place(out, Synth.mul(hn, Synth.env_points(wn, [[0.0, 0.0], [0.5, 0.4], [0.68, 0.6], [0.7, 0.0]])), 0.0, 0.5)
	# blow-off valve "pssshh" when the throttle closes
	var pn := Synth.secs(0.5)
	var ps := Synth.band(Synth.noise(pn, rng.randi()), 1800.0, 9000.0)
	ps = Synth.mul(ps, Synth.env_decay(pn, 0.12, SR, 0.004))
	_place(out, ps, 0.7, 0.9)
	_place(out, Synth.mul(Synth.osc_sweep(Synth.Wave.SINE, pn, 3200.0, 1500.0), Synth.env_decay(pn, 0.05)), 0.7, 0.18)
	return out


static func _burble(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur := 0.7
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	var count: int = 4 + v
	var t: float = 0.0
	for k in count:
		var amp: float = rng.randf_range(0.4, 1.0)
		var f: float = rng.randf_range(0.8, 1.3)
		# one backfire pop: bandpassed crack + low thump
		_place(out, Synth.noise_hit(0.05, 0.009, 400.0, 3800.0, rng.randi()), t, 0.8 * amp)
		_place(out, Synth.thump(0.09, 160.0 * f, 70.0, 0.025), t, 0.9 * amp)
		t += rng.randf_range(0.04, 0.16)
		if t > dur - 0.12:
			break
	return Synth.reverb(out, 0.25, 0.6, 0.1, SR, 0.15)


static func _shift(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.22))
	_place(out, Synth.thump(0.1, 150.0 + 20.0 * float(v), 80.0, 0.025), 0.0, 0.8)
	_place(out, Synth.noise_hit(0.05, 0.01, 600.0, 4500.0, rng.randi()), 0.0, 0.45)
	_place(out, Synth.band(Synth.mul(Synth.noise(Synth.secs(0.12), rng.randi()), Synth.env_swell(Synth.secs(0.12), 0.2)), 1500.0, 6000.0), 0.02, 0.25)
	return out
