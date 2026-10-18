extends RefCounted
## Sound recipes: world ambience beds (seamless loops) and ambient one-shots (gulls, birds, industrial clanks, ship horn,
## thunder). Loops are made seamless either with circular filtering of noise over a periodic envelope or an equal-power
## cross-fade of the tail into the head. Everything is original synthesis.

const Synth = preload("res://gta/code/audio/synth.gd")
const SR := 22050
const SR_MID := 16000
const SR_LO := 11025

const IDS := {
	&"amb_city": {"cat": &"amb_loop", "var": 1, "peak": 0.6},
	&"amb_wind": {"cat": &"amb_loop", "var": 1, "peak": 0.6},
	&"amb_sea": {"cat": &"amb_loop", "var": 1, "peak": 0.65},
	&"amb_rain_light": {"cat": &"amb_loop", "var": 1, "peak": 0.55},
	&"amb_rain_heavy": {"cat": &"amb_loop", "var": 1, "peak": 0.65},
	&"amb_industrial": {"cat": &"amb_loop", "var": 1, "peak": 0.6},
	&"amb_leaves": {"cat": &"amb_loop", "var": 1, "peak": 0.5},
	&"amb_crickets": {"cat": &"amb_loop", "var": 1, "peak": 0.45},
	&"amb_crowd": {"cat": &"amb_loop", "var": 1, "peak": 0.5},
	&"amb_underwater": {"cat": &"amb_loop", "var": 1, "peak": 0.6},
	&"amb_airport": {"cat": &"amb_loop", "var": 1, "peak": 0.55},
	&"gull": {"cat": &"ambient_shot", "var": 4, "peak": 0.6, "unit": 30.0},
	&"bird": {"cat": &"ambient_shot", "var": 5, "peak": 0.5, "unit": 22.0},
	&"clank": {"cat": &"ambient_shot", "var": 4, "peak": 0.7, "unit": 35.0},
	&"ship_horn": {"cat": &"ambient_shot", "var": 2, "peak": 0.75, "unit": 120.0, "range": 450.0},
	&"thunder": {"cat": &"ambient_shot", "var": 3, "peak": 1.0, "unit": 400.0, "range": 1000.0},
}


static func build(id: StringName, v: int, rng: RandomNumberGenerator) -> Dictionary:
	match id:
		&"amb_city":
			return _city(rng)
		&"amb_wind":
			return _wind(rng)
		&"amb_sea":
			return _sea(rng)
		&"amb_rain_light":
			return _rain(rng, false)
		&"amb_rain_heavy":
			return _rain(rng, true)
		&"amb_industrial":
			return _industrial(rng)
		&"amb_leaves":
			return _leaves(rng)
		&"amb_crickets":
			return _crickets(rng)
		&"amb_crowd":
			return _crowd(rng)
		&"amb_underwater":
			return _underwater(rng)
		&"amb_airport":
			return _airport(rng)
		&"gull":
			return {"buf": _gull(rng, v), "sr": SR, "loop": false}
		&"bird":
			return {"buf": _bird(rng, v), "sr": SR, "loop": false}
		&"clank":
			return {"buf": _clank(rng, v), "sr": SR_MID, "loop": false}
		&"ship_horn":
			return {"buf": _ship_horn(rng, v), "sr": SR_MID, "loop": false}
		&"thunder":
			return {"buf": _thunder(rng, v), "sr": SR_LO, "loop": false}
	return {}


static func _place(dst: PackedFloat32Array, src: PackedFloat32Array, t: float, gain: float = 1.0, sr: int = SR) -> void:
	Synth.mix_into(dst, src, int(t * sr), gain)


static func _lp_circ(a: PackedFloat32Array, fc: float, sr: int, q: float = 0.707) -> PackedFloat32Array:
	return Synth.circular(a, func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.lowpass(b, fc, q, sr))


static func _band_circ(a: PackedFloat32Array, lo: float, hi: float, sr: int) -> PackedFloat32Array:
	return Synth.circular(a, func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.band(b, lo, hi, sr))


# ---- beds ------------------------------------------------------------------------------------------------------------
static func _city(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var dur := 12.0
	var n := Synth.secs(dur, sr)
	var out := Synth.zeros(n)
	# low urban rumble + mains hum
	var rum := _lp_circ(Synth.brown(n, rng.randi()), 160.0, sr)
	_place(out, rum, 0.0, 1.4, sr)
	for h in [60.0, 120.0, 180.0]:
		var hum := Synth.osc(Synth.Wave.SINE, n, h, sr)
		_place(out, hum, 0.0, 0.035 / (h / 60.0), sr)
	# distant traffic wash with slow swells
	var wash := _band_circ(Synth.pink(n, rng.randi()), 90.0, 1100.0, sr)
	var swell := Synth.smooth_random(n, 0.33, sr, rng.randi())
	for i in n:
		out[i] += wash[i] * (0.35 + 0.65 * swell[i]) * 0.9
	# individual far vehicle pass-bys: band-limited noise swells
	for k in 7:
		var d: float = rng.randf_range(1.2, 3.2)
		var nn := Synth.secs(d, sr)
		var fc: float = rng.randf_range(260.0, 700.0)
		var pass_n := Synth.band(Synth.noise(nn, rng.randi()), fc, fc * 2.6, sr)
		pass_n = Synth.mul(pass_n, Synth.env_swell(nn, rng.randf_range(0.35, 0.6), 1.6))
		Synth.mix_wrap(out, pass_n, int(rng.randf() * float(n)), rng.randf_range(0.4, 0.9))
	# faint high air / ventilation
	var air := _band_circ(Synth.noise(n, rng.randi()), 2500.0, 6500.0, sr)
	_place(out, air, 0.0, 0.06, sr)
	return {"buf": out, "sr": sr, "loop": true}


static func _wind(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var dur := 14.0
	var n := Synth.secs(dur, sr)
	var gust := Synth.smooth_random(n, 0.28, sr, rng.randi())
	var gust2 := Synth.smooth_random(n, 0.9, sr, rng.randi())
	var fc := PackedFloat32Array()
	fc.resize(n)
	for i in n:
		fc[i] = 250.0 + 1500.0 * gust[i] * gust[i]
	var src := Synth.pink(n, rng.randi())
	var dbl := src.duplicate()
	dbl.append_array(src)
	var fc2 := fc.duplicate()
	fc2.append_array(fc)
	var f := Synth.biquad_sweep(dbl, Synth.Filt.BP, fc2, 0.9, sr)
	f = f.slice(n, n * 2)
	var out := Synth.zeros(n)
	for i in n:
		out[i] = f[i] * (0.25 + 0.9 * gust[i]) * (0.85 + 0.3 * gust2[i]) * 2.2
	# thin whistling through gaps
	var wf := PackedFloat32Array()
	wf.resize(n)
	for i in n:
		wf[i] = 620.0 + 380.0 * gust2[i]
	var whistle := Synth.biquad_sweep(Synth.noise(n, rng.randi()), Synth.Filt.BP, wf, 14.0, sr)
	for i in n:
		out[i] += whistle[i] * 0.4 * gust[i] * gust[i]
	return {"buf": Synth.make_loop(out, 0.5, sr), "sr": sr, "loop": true}


static func _sea(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var period := 7.0
	var waves := 2
	var n := Synth.secs(period * float(waves), sr)
	# periodic wave envelope: slow rise to the crest, longer fall-off
	var env := PackedFloat32Array()
	env.resize(n)
	for i in n:
		var u: float = fposmod(float(i) / float(n) * float(waves), 1.0)
		var e: float
		if u < 0.36:
			e = sin(u / 0.36 * PI * 0.5)
			e *= e
		else:
			e = pow(0.5 + 0.5 * cos((u - 0.36) / 0.64 * PI), 1.4)
		env[i] = e
	var low := _lp_circ(Synth.brown(n, rng.randi()), 300.0, sr)
	var roar := _band_circ(Synth.pink(n, rng.randi()), 150.0, 1200.0, sr)
	var foam := _band_circ(Synth.noise(n, rng.randi()), 1500.0, 6500.0, sr)
	var swash := _band_circ(Synth.noise(n, rng.randi()), 600.0, 3200.0, sr)
	var out := Synth.zeros(n)
	var jit := Synth.smooth_random(n, 2.5, sr, rng.randi())
	for i in n:
		var e: float = env[i]
		var lag: int = (i + int(0.9 * float(sr))) % n
		var e_lag: float = env[lag]
		out[i] = low[i] * (0.25 + 0.9 * e) * 1.6 + roar[i] * e * 1.1 + foam[i] * e_lag * e_lag * 0.35 * (0.7 + 0.3 * jit[i]) + swash[i] * e_lag * 0.25
	return {"buf": out, "sr": sr, "loop": true}


static func _rain(rng: RandomNumberGenerator, heavy: bool) -> Dictionary:
	var sr := SR
	var n := Synth.secs(8.0, sr)
	var out := Synth.zeros(n)
	var rate: float = 2600.0 if heavy else 360.0
	var drops := Synth.crackle(n, rate, sr, rng.randi(), 0.0016, 0.7)
	drops = Synth.band(drops, 1800.0, 9000.0, sr)
	_place(out, drops, 0.0, 1.6 if heavy else 1.8, sr)
	# surface thumps (bigger drops on ground / roofs)
	var big := Synth.crackle(n, 55.0 if heavy else 9.0, sr, rng.randi(), 0.007, 0.5)
	big = Synth.band(big, 250.0, 2400.0, sr)
	_place(out, big, 0.0, 1.2, sr)
	# continuous hiss wash
	var hiss := Synth.band(Synth.pink(n, rng.randi()), 1500.0, 7500.0, sr)
	_place(out, hiss, 0.0, 0.7 if heavy else 0.18, sr)
	if heavy:
		var rum := Synth.lowpass(Synth.pink(n, rng.randi()), 500.0, 0.7, sr)
		_place(out, rum, 0.0, 0.5, sr)
	return {"buf": Synth.make_loop(out, 0.3, sr), "sr": sr, "loop": true}


static func _industrial(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var n := Synth.secs(10.0, sr)
	var out := Synth.zeros(n)
	# 50 Hz transformer hum and harmonics (integer Hz => periodic over 10 s)
	for h in range(1, 7):
		var amp: float = 0.5 / float(h)
		_place(out, Synth.osc(Synth.Wave.SINE, n, 50.0 * float(h), sr, rng.randf()), 0.0, amp * 0.22, sr)
	# machinery whirr: slowly modulated band noise
	var mach := _band_circ(Synth.noise(n, rng.randi()), 220.0, 700.0, sr)
	var mod := Synth.lfo(n, 0.5, 0.7, 0.3, sr)
	for i in n:
		out[i] += mach[i] * mod[i] * 0.55
	# compressor-like rhythmic chugging
	var chug := _lp_circ(Synth.noise(n, rng.randi()), 400.0, sr)
	var chug_env := Synth.lfo(n, 2.0, 0.5, 0.5, sr)
	for i in n:
		out[i] += chug[i] * pow(chug_env[i], 2.0) * 0.5
	# pneumatic hisses
	for t in [2.4, 6.7]:
		var hn := Synth.secs(1.1, sr)
		var h := Synth.band(Synth.noise(hn, rng.randi()), 2400.0, 6500.0, sr)
		_place(out, Synth.mul(h, Synth.env_decay(hn, 0.3, sr, 0.02)), float(t), 0.35, sr)
	# distant metallic thumps
	for t in [1.0, 4.4, 8.1]:
		_place(out, Synth.thump(0.4, 90.0, 40.0, 0.09, sr), float(t), 0.7, sr)
		_place(out, Synth.modal(Synth.secs(0.6, sr), [[610.0, 0.12, 1.0], [1370.0, 0.07, 0.5]], sr), float(t), 0.05, sr)
	return {"buf": out, "sr": sr, "loop": true}


static func _leaves(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var n := Synth.secs(9.0, sr)
	var rustle := _band_circ(Synth.noise(n, rng.randi()), 1800.0, 6800.0, sr)
	var m1 := Synth.smooth_random(n, 1.7, sr, rng.randi())
	var m2 := Synth.smooth_random(n, 0.4, sr, rng.randi())
	var out := Synth.zeros(n)
	for i in n:
		out[i] = rustle[i] * m1[i] * m1[i] * (0.4 + 0.8 * m2[i]) * 1.6
	var soft := _band_circ(Synth.pink(n, rng.randi()), 120.0, 900.0, sr)
	_place(out, soft, 0.0, 0.5, sr)
	return {"buf": Synth.make_loop(out, 0.4, sr), "sr": sr, "loop": true}


static func _crickets(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var dur := 8.0
	var n := Synth.secs(dur, sr)
	var out := Synth.zeros(n)
	for voice in 4:
		var carrier: float = rng.randf_range(4200.0, 5100.0)
		var chirp_period: float = rng.randf_range(0.55, 0.95)
		var pulses: int = 3 + voice % 2
		var pulse_rate: float = rng.randf_range(26.0, 34.0)
		var t0: float = rng.randf() * 0.5
		var gain: float = rng.randf_range(0.5, 1.0)
		var t: float = t0
		while t < dur - 0.2:
			# one chirp = a short train of pulses
			for p in pulses:
				var pn := Synth.secs(0.022, sr)
				var tone := Synth.osc(Synth.Wave.SINE, pn, carrier * (1.0 + 0.004 * float(p)), sr)
				tone = Synth.mul(tone, Synth.env_swell(pn, 0.35, 1.0))
				_place(out, tone, t + float(p) / pulse_rate, gain * 0.5, sr)
			t += chirp_period * rng.randf_range(0.96, 1.05)
		# some voices pause periodically
	var out2 := Synth.make_loop(out, 0.35, sr)
	return {"buf": out2, "sr": sr, "loop": true}


static func _crowd(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var dur := 12.0
	var n := Synth.secs(dur, sr)
	var out := Synth.zeros(n)
	# a handful of whispered "speakers": gated noise through moving formants
	for sp in 6:
		var src := Synth.noise(n, rng.randi())
		var tract: float = rng.randf_range(0.9, 1.25)
		# formant 1 and 2 centre tracks wander between vowel targets
		var f1 := Synth.smooth_random(n, rng.randf_range(2.5, 4.5), sr, rng.randi())
		var f2 := Synth.smooth_random(n, rng.randf_range(2.5, 4.5), sr, rng.randi())
		var fc1 := PackedFloat32Array()
		var fc2 := PackedFloat32Array()
		fc1.resize(n)
		fc2.resize(n)
		for i in n:
			fc1[i] = (300.0 + 500.0 * f1[i]) * tract
			fc2[i] = (900.0 + 1500.0 * f2[i]) * tract
		var a := Synth.biquad_sweep(src, Synth.Filt.BP, fc1, 4.0, sr)
		var b := Synth.biquad_sweep(src, Synth.Filt.BP, fc2, 4.0, sr)
		# syllable gating: phrases of speech and pauses
		var syl := Synth.smooth_random(n, rng.randf_range(3.2, 5.0), sr, rng.randi())
		var phr := Synth.smooth_random(n, rng.randf_range(0.25, 0.5), sr, rng.randi())
		for i in n:
			var gate: float = clampf((phr[i] - 0.35) * 3.0, 0.0, 1.0) * (0.35 + 0.65 * syl[i])
			out[i] += (a[i] + b[i] * 0.6) * gate * 0.7
	out = Synth.lowpass(out, 3200.0, 0.7, sr)
	var rumble := _band_circ(Synth.pink(n, rng.randi()), 100.0, 600.0, sr)
	_place(out, rumble, 0.0, 0.25, sr)
	return {"buf": Synth.make_loop(out, 0.5, sr), "sr": sr, "loop": true}


static func _underwater(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_LO
	var n := Synth.secs(8.0, sr)
	var out := _lp_circ(Synth.brown(n, rng.randi()), 220.0, sr)
	out = Synth.scale(out, 2.2)
	var mid := _band_circ(Synth.pink(n, rng.randi()), 120.0, 900.0, sr)
	var m := Synth.smooth_random(n, 0.4, sr, rng.randi())
	for i in n:
		out[i] += mid[i] * (0.2 + 0.5 * m[i])
	# rising bubbles
	for k in 14:
		var bn := Synth.secs(0.25, sr)
		var f0: float = rng.randf_range(250.0, 700.0)
		var bub := Synth.mul(Synth.osc_sweep(Synth.Wave.SINE, bn, f0, f0 * 2.2, sr), Synth.env_decay(bn, 0.04, sr, 0.003))
		Synth.mix_wrap(out, bub, int(rng.randf() * float(n)), rng.randf_range(0.1, 0.3))
	return {"buf": Synth.make_loop(out, 0.4, sr), "sr": sr, "loop": true}


static func _airport(rng: RandomNumberGenerator) -> Dictionary:
	var sr := SR_MID
	var n := Synth.secs(12.0, sr)
	var out := Synth.zeros(n)
	var rum := _lp_circ(Synth.brown(n, rng.randi()), 200.0, sr)
	_place(out, rum, 0.0, 1.0, sr)
	# a distant aircraft: swelling band-limited roar plus whine; second one later (periodic wrap)
	for k in 2:
		var d: float = 7.0 if k == 0 else 5.0
		var nn := Synth.secs(d, sr)
		var roar := Synth.band(Synth.noise(nn, rng.randi()), 350.0, 1800.0, sr)
		roar = Synth.mul(roar, Synth.env_swell(nn, 0.45, 1.8))
		Synth.mix_wrap(out, roar, int(float(k) * 0.55 * float(n)), 0.9)
		var whine_f: float = 2400.0 if k == 0 else 3100.0
		var whine := Synth.osc_sweep(Synth.Wave.SINE, nn, whine_f * 0.9, whine_f * 1.1, sr)
		whine = Synth.mul(whine, Synth.env_swell(nn, 0.45, 2.5))
		Synth.mix_wrap(out, whine, int(float(k) * 0.55 * float(n)), 0.035)
	var air := _band_circ(Synth.pink(n, rng.randi()), 400.0, 2500.0, sr)
	_place(out, air, 0.0, 0.25, sr)
	return {"buf": out, "sr": sr, "loop": true}


# ---- one-shots -------------------------------------------------------------------------------------------------------
static func _gull(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var syll: int = 2 + v % 3
	var dur: float = 0.42 * float(syll) + 0.2
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	var base: float = rng.randf_range(1250.0, 1650.0)
	for s in syll:
		var d: float = rng.randf_range(0.3, 0.42)
		var sn := Synth.secs(d)
		var f := PackedFloat32Array()
		f.resize(sn)
		for i in sn:
			var u: float = float(i) / float(sn)
			# fast rise, slow fall: the typical "kee-yaaw"
			var arch: float = sin(minf(u * 3.0, 1.0) * PI * 0.5) * (1.0 - 0.45 * u)
			f[i] = base * (0.8 + 1.1 * arch) * (1.0 + 0.02 * sin(float(i) * 0.09))
		var src := Synth.osc_f(Synth.Wave.SAW, f)
		src = Synth.formants(src, [[1500.0, 400.0, 1.0], [2800.0, 600.0, 0.8], [4300.0, 800.0, 0.35]])
		src = Synth.mul(src, Synth.env_points(sn, [[0.0, 0.0], [0.02, 1.0], [d * 0.7, 0.8], [d, 0.0]]))
		_place(out, src, float(s) * 0.4 + rng.randf() * 0.03, 0.8 - 0.1 * float(s))
	return Synth.reverb(Synth.soft_clip(out, 1.3), 0.5, 0.4, 0.2, SR, 0.4)


static func _bird(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var n := Synth.secs(0.9)
	var out := Synth.zeros(n)
	var t: float = 0.0
	var motif: int = v % 3
	var chirps: int = 3 + (v % 4)
	for k in chirps:
		var d: float = rng.randf_range(0.035, 0.09)
		var cn := Synth.secs(d)
		var f0: float = rng.randf_range(2800.0, 5200.0)
		var up: bool = (k + motif) % 2 == 0
		var f1: float = f0 * (rng.randf_range(1.25, 1.7) if up else rng.randf_range(0.6, 0.8))
		var c := Synth.osc_sweep(Synth.Wave.SINE, cn, f0, f1)
		var trem := Synth.lfo(cn, rng.randf_range(30.0, 60.0), 0.8, 0.2)
		c = Synth.mul(Synth.mul(c, trem), Synth.env_swell(cn, 0.3, 0.8))
		_place(out, c, t, 0.8)
		_place(out, Synth.scale(c, 0.25), t + 0.012, 1.0)
		t += d + rng.randf_range(0.03, 0.14)
		if t > 0.75:
			break
	return Synth.reverb(out, 0.4, 0.3, 0.12, SR, 0.2)


static func _clank(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var sr := SR_MID
	var n := Synth.secs(1.4, sr)
	var out := Synth.zeros(n)
	var base: float = rng.randf_range(180.0, 520.0)
	var parts: Array = []
	for r in [1.0, 2.76, 5.4, 8.93, 13.34]:
		parts.append([base * float(r), rng.randf_range(0.12, 0.35) / pow(float(r), 0.4), 1.0 / pow(float(r), 0.5)])
	_place(out, Synth.modal(n, parts, sr), 0.0, 0.9, sr)
	_place(out, Synth.noise_hit(0.04, 0.007, 600.0, 5500.0, rng.randi(), sr), 0.0, 0.9, sr)
	_place(out, Synth.thump(0.12, 150.0, 70.0, 0.03, sr), 0.0, 0.6, sr)
	if v % 2 == 1:
		# a second, softer hit
		_place(out, Synth.modal(n, parts, sr), 0.34, 0.35, sr)
	return Synth.reverb(out, 0.75, 0.5, 0.3, sr, 0.5)


static func _ship_horn(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var sr := SR_MID
	var dur: float = 3.6 + float(v) * 0.6
	var n := Synth.secs(dur, sr)
	var f: float = 98.0 * rng.randf_range(0.95, 1.08)
	var tone := Synth.osc(Synth.Wave.SAW, n, f, sr)
	tone = Synth.add(tone, Synth.osc(Synth.Wave.SAW, n, f * 1.256, sr), 0.8)
	tone = Synth.add(tone, Synth.osc(Synth.Wave.SQUARE, n, f * 2.0, sr, 0.0, 0.5), 0.25)
	tone = Synth.lowpass(tone, 900.0, 1.1, sr)
	tone = Synth.mul(tone, Synth.env_points(n, [[0.0, 0.0], [0.35, 0.95], [dur - 1.0, 1.0], [dur, 0.0]], sr))
	return Synth.reverb(tone, 0.8, 0.5, 0.35, sr, 1.0)


static func _thunder(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var sr := SR_LO
	var dur: float = 5.5 + float(v) * 0.7
	var n := Synth.secs(dur, sr)
	var out := Synth.zeros(n)
	# sharp initial crack (the lightning channel)
	var crack := Synth.noise_hit(0.35, 0.05, 250.0, 5000.0, rng.randi(), sr)
	_place(out, crack, 0.0, 0.9, sr)
	# rolling, rumbling body: brown noise with a stuttering decaying envelope (reflections)
	var body := Synth.lowpass(Synth.brown(n, rng.randi()), 330.0, 0.8, sr)
	var stutter := Synth.smooth_random(n, 2.8, sr, rng.randi())
	var env := Synth.env_points(n, [[0.0, 0.0], [0.15, 1.0], [dur * 0.35, 0.75], [dur, 0.0]], sr)
	for i in n:
		out[i] += body[i] * env[i] * (0.35 + 0.9 * stutter[i]) * 3.2
	# deep sub rumble
	var sub := Synth.lowpass(Synth.brown(n, rng.randi()), 80.0, 0.8, sr)
	_place(out, Synth.mul(sub, Synth.env_points(n, [[0.0, 0.0], [0.3, 1.0], [dur * 0.6, 0.5], [dur, 0.0]], sr)), 0.0, 3.0, sr)
	return Synth.reverb(Synth.soft_clip(Synth.normalize(out, 0.7), 1.1), 0.9, 0.7, 0.3, sr, 0.8)
