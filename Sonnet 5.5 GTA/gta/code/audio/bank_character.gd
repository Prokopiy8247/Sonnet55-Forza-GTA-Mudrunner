extends RefCounted
## Sound recipes: footsteps per surface, water splashes, movement foley, NON-VERBAL vocalisations (glottal source through
## formant filters - hurt/death grunts for male and female voices, breathing, gasp, scream, cough), doors, pickups.

const Synth = preload("res://gta/code/audio/synth.gd")
const SR := 22050
const SR_LO := 16000

const IDS := {
	&"step_concrete": {"cat": &"step", "var": 4, "peak": 0.55},
	&"step_grass": {"cat": &"step", "var": 4, "peak": 0.4},
	&"step_sand": {"cat": &"step", "var": 4, "peak": 0.42},
	&"step_wood": {"cat": &"step", "var": 4, "peak": 0.55},
	&"step_water": {"cat": &"step", "var": 3, "peak": 0.55},
	&"step_metal": {"cat": &"step", "var": 3, "peak": 0.5},
	&"splash": {"cat": &"foley", "var": 3, "peak": 0.7, "unit": 8.0},
	&"splash_big": {"cat": &"foley", "var": 2, "peak": 0.9, "unit": 18.0, "range": 80.0},
	&"jump": {"cat": &"foley", "var": 3, "peak": 0.4},
	&"land": {"cat": &"foley", "var": 3, "peak": 0.6},
	&"hurt_m": {"cat": &"voice", "var": 4, "peak": 0.75},
	&"hurt_f": {"cat": &"voice", "var": 4, "peak": 0.75},
	&"death_m": {"cat": &"voice", "var": 3, "peak": 0.8},
	&"death_f": {"cat": &"voice", "var": 3, "peak": 0.8},
	&"breath_hard": {"cat": &"voice", "var": 2, "peak": 0.5, "unit": 3.5},
	&"gasp": {"cat": &"voice", "var": 2, "peak": 0.55, "unit": 4.0},
	&"scream": {"cat": &"voice", "var": 3, "peak": 0.9, "unit": 20.0, "range": 110.0},
	&"cough": {"cat": &"voice", "var": 2, "peak": 0.6},
	&"door_open": {"cat": &"foley", "var": 2, "peak": 0.55, "unit": 8.0},
	&"door_close": {"cat": &"foley", "var": 2, "peak": 0.7, "unit": 8.0},
	&"pickup": {"cat": &"foley", "var": 1, "peak": 0.6, "unit": 6.0},
}

## Vowel formant sets for a ~17 cm adult male vocal tract: [freq Hz, bandwidth Hz, gain].
const VOWELS := {
	"a": [[730.0, 90.0, 1.0], [1090.0, 110.0, 0.55], [2440.0, 160.0, 0.3], [3400.0, 220.0, 0.12]],
	"o": [[570.0, 80.0, 1.0], [840.0, 90.0, 0.6], [2410.0, 150.0, 0.2], [3300.0, 200.0, 0.08]],
	"e": [[530.0, 80.0, 1.0], [1840.0, 120.0, 0.5], [2480.0, 160.0, 0.35], [3400.0, 220.0, 0.1]],
	"i": [[270.0, 60.0, 1.0], [2290.0, 120.0, 0.45], [3010.0, 160.0, 0.3], [3500.0, 220.0, 0.1]],
	"u": [[300.0, 60.0, 1.0], [870.0, 90.0, 0.5], [2240.0, 150.0, 0.15], [3300.0, 200.0, 0.06]],
	"ae": [[660.0, 90.0, 1.0], [1720.0, 110.0, 0.55], [2410.0, 160.0, 0.3], [3400.0, 220.0, 0.1]],
	"uh": [[640.0, 90.0, 1.0], [1190.0, 110.0, 0.5], [2390.0, 160.0, 0.25], [3400.0, 220.0, 0.1]],
}


static func build(id: StringName, v: int, rng: RandomNumberGenerator) -> Dictionary:
	var b: PackedFloat32Array
	var sr: int = SR
	match id:
		&"step_concrete":
			b = _step_concrete(rng, v)
		&"step_grass":
			b = _step_grass(rng, v)
		&"step_sand":
			b = _step_sand(rng, v)
		&"step_wood":
			b = _step_wood(rng, v)
		&"step_water":
			b = _step_water(rng, v)
		&"step_metal":
			b = _step_metal(rng, v)
		&"splash":
			b = _splash(rng, false)
		&"splash_big":
			b = _splash(rng, true)
			sr = SR_LO
		&"jump":
			b = _jump(rng)
		&"land":
			b = _land(rng)
		&"hurt_m":
			b = _hurt(rng, v, false)
		&"hurt_f":
			b = _hurt(rng, v, true)
		&"death_m":
			b = _death(rng, v, false)
		&"death_f":
			b = _death(rng, v, true)
		&"breath_hard":
			b = _breath(rng)
		&"gasp":
			b = _gasp(rng)
		&"scream":
			b = _scream(rng, v)
		&"cough":
			b = _cough(rng)
		&"door_open":
			b = _door_open(rng)
		&"door_close":
			b = _door_close(rng)
		&"pickup":
			b = _pickup()
		_:
			return {}
	return {"buf": b, "sr": sr, "loop": false}


static func _place(dst: PackedFloat32Array, src: PackedFloat32Array, t: float, gain: float = 1.0, sr: int = SR) -> void:
	Synth.mix_into(dst, src, int(t * sr), gain)


# ---- footsteps ------------------------------------------------------------------------------------------------------
static func _step_concrete(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.2))
	var f: float = rng.randf_range(0.9, 1.15)
	_place(out, Synth.noise_hit(0.08, 0.012, 700.0 * f, 5200.0 * f, rng.randi()), 0.0, 0.8)
	_place(out, Synth.thump(0.08, 160.0 * f, 95.0, 0.022), 0.0, 0.8)
	_place(out, Synth.noise_hit(0.02, 0.003, 2500.0, 8000.0, rng.randi()), 0.0, 0.4)
	# heel-then-toe double tap
	_place(out, Synth.noise_hit(0.05, 0.01, 600.0, 3500.0, rng.randi()), 0.075 + 0.01 * float(v % 2), 0.4)
	_place(out, Synth.thump(0.05, 130.0, 90.0, 0.015), 0.075, 0.35)
	return out


static func _step_grass(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var n := Synth.secs(0.24)
	var s := Synth.noise(n, rng.randi())
	s = Synth.band(s, 250.0 + 60.0 * float(v), 3300.0)
	s = Synth.mul(s, Synth.env_swell(n, 0.25, 1.3))
	var out := Synth.scale(s, 0.7)
	_place(out, Synth.mul(Synth.band(Synth.crackle(n, 700.0, SR, rng.randi(), 0.002), 1500.0, 7000.0), Synth.env_swell(n, 0.3)), 0.0, 0.45)
	_place(out, Synth.thump(0.06, 110.0, 70.0, 0.02), 0.01, 0.35)
	return out


static func _step_sand(rng: RandomNumberGenerator, _v: int) -> PackedFloat32Array:
	var n := Synth.secs(0.26)
	var cr := Synth.crackle(n, 1500.0, SR, rng.randi(), 0.0018, 0.6)
	cr = Synth.band(cr, 1200.0, 6000.0)
	cr = Synth.mul(cr, Synth.env_swell(n, 0.22, 1.1))
	var soft := Synth.mul(Synth.band(Synth.noise(n, rng.randi()), 300.0, 1800.0), Synth.env_swell(n, 0.2, 1.4))
	var out := Synth.add(Synth.scale(cr, 1.0), soft, 0.4)
	_place(out, Synth.thump(0.05, 100.0, 65.0, 0.018), 0.005, 0.25)
	return out


static func _step_wood(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var f: float = rng.randf_range(0.88, 1.2)
	var out := Synth.modal(Synth.secs(0.28), [[185.0 * f, 0.05, 0.9], [350.0 * f, 0.035, 0.6], [560.0 * f, 0.025, 0.4], [118.0 * f, 0.07, 0.7]])
	_place(out, Synth.noise_hit(0.04, 0.007, 800.0, 4500.0, rng.randi()), 0.0, 0.7)
	_place(out, Synth.thump(0.06, 220.0, 120.0, 0.015), 0.0, 0.6)
	_place(out, Synth.modal(Synth.secs(0.18), [[240.0 * f, 0.04, 0.5], [460.0 * f, 0.03, 0.3]]), 0.08 + 0.005 * float(v), 0.5)
	return out


static func _step_water(rng: RandomNumberGenerator, _v: int) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.36))
	_place(out, Synth.noise_hit(0.22, 0.05, 500.0, 4200.0, rng.randi()), 0.0, 0.65)
	_place(out, Synth.thump(0.07, 150.0, 90.0, 0.02), 0.0, 0.4)
	for k in 3:
		var nn := Synth.secs(0.07)
		var f0: float = rng.randf_range(500.0, 900.0)
		_place(out, Synth.mul(Synth.osc_sweep(Synth.Wave.SINE, nn, f0, f0 * 2.4), Synth.env_decay(nn, 0.018, SR, 0.002)), 0.02 + 0.045 * float(k) + rng.randf() * 0.02, 0.35)
	return out


static func _step_metal(rng: RandomNumberGenerator, _v: int) -> PackedFloat32Array:
	var f: float = rng.randf_range(0.85, 1.25)
	var out := Synth.modal(Synth.secs(0.3), [[420.0 * f, 0.07, 0.8], [910.0 * f, 0.05, 0.7], [1700.0 * f, 0.03, 0.5], [2650.0 * f, 0.02, 0.3]])
	_place(out, Synth.noise_hit(0.03, 0.005, 900.0, 6000.0, rng.randi()), 0.0, 0.8)
	_place(out, Synth.thump(0.06, 200.0, 110.0, 0.015), 0.0, 0.6)
	return out


# ---- water -----------------------------------------------------------------------------------------------------------
static func _splash(rng: RandomNumberGenerator, big: bool) -> PackedFloat32Array:
	var sr: int = SR_LO if big else SR
	var dur: float = 1.5 if big else 0.8
	var n := Synth.secs(dur, sr)
	var out := Synth.zeros(n)
	var body := Synth.noise(n, rng.randi())
	body = Synth.biquad_sweep(body, Synth.Filt.BP, Synth.expramp(n, 3500.0, 600.0 if big else 900.0), 0.8, sr)
	body = Synth.mul(body, Synth.env_points(n, [[0.0, 0.0], [0.015, 1.0], [dur * 0.25, 0.5], [dur, 0.0]], sr))
	_place(out, body, 0.0, 0.9, sr)
	if big:
		_place(out, Synth.thump(0.5, 95.0, 36.0, 0.14, sr), 0.0, 1.0, sr)
	else:
		_place(out, Synth.thump(0.15, 150.0, 70.0, 0.04, sr), 0.0, 0.5, sr)
	# bubbles: rising chirps
	var count: int = 14 if big else 7
	for k in count:
		var nn := Synth.secs(0.09, sr)
		var f0: float = rng.randf_range(300.0, 900.0)
		var t: float = rng.randf() * dur * 0.7
		_place(out, Synth.mul(Synth.osc_sweep(Synth.Wave.SINE, nn, f0, f0 * rng.randf_range(1.8, 3.0), sr), Synth.env_decay(nn, 0.022, sr, 0.002)), t, rng.randf_range(0.15, 0.4), sr)
	return out


# ---- foley -----------------------------------------------------------------------------------------------------------
static func _jump(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := Synth.secs(0.26)
	var cloth := Synth.band(Synth.noise(n, rng.randi()), 500.0, 3200.0)
	cloth = Synth.mul(cloth, Synth.env_swell(n, 0.35, 1.5))
	var out := Synth.scale(cloth, 0.7)
	_place(out, Synth.thump(0.06, 140.0, 80.0, 0.02), 0.0, 0.3)
	return out


static func _land(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.3))
	_place(out, Synth.thump(0.2, rng.randf_range(115.0, 145.0), 55.0, 0.055), 0.0, 0.9)
	_place(out, Synth.noise_hit(0.12, 0.025, 200.0, 1800.0, rng.randi()), 0.0, 0.6)
	_place(out, Synth.mul(Synth.band(Synth.noise(Synth.secs(0.15), rng.randi()), 500.0, 3000.0), Synth.env_swell(Synth.secs(0.15), 0.2)), 0.0, 0.3)
	return out


static func _door_open(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.7))
	# latch click
	_place(out, Synth.modal(Synth.secs(0.1), [[1100.0, 0.012, 1.0], [2300.0, 0.008, 0.6], [3800.0, 0.005, 0.3]]), 0.0, 0.7)
	_place(out, Synth.thump(0.05, 200.0, 120.0, 0.012), 0.0, 0.4)
	# hinge creak: saw whose pitch drifts, through two resonances
	var n := Synth.secs(0.45)
	var f0: float = rng.randf_range(150.0, 210.0)
	var pitch := Synth.mul(Synth.expramp(n, f0, f0 * 1.45), Synth.lfo(n, 11.0, 1.0, 0.06))
	var cr := Synth.osc_f(Synth.Wave.SAW, pitch)
	cr = Synth.formants(cr, [[700.0, 120.0, 1.0], [1350.0, 150.0, 0.6]])
	cr = Synth.mul(cr, Synth.env_adsr(n, 0.05, 0.1, 0.7, 0.15))
	_place(out, cr, 0.06, 0.22)
	return out


static func _door_close(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.5))
	_place(out, Synth.thump(0.3, 135.0, 55.0, 0.07), 0.0, 0.9)
	_place(out, Synth.noise_hit(0.12, 0.025, 200.0, 2200.0, rng.randi()), 0.0, 0.6)
	_place(out, Synth.modal(Synth.secs(0.12), [[1000.0, 0.014, 1.0], [2100.0, 0.009, 0.6]]), 0.06, 0.45)
	_place(out, Synth.modal(Synth.secs(0.3), [[220.0, 0.09, 0.6], [440.0, 0.05, 0.3]]), 0.0, 0.35)
	return out


static func _pickup() -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.6))
	var notes: Array = [1046.5, 1318.5, 1568.0, 2093.0]
	for k in notes.size():
		var n := Synth.secs(0.3)
		var f: float = notes[k]
		var s := Synth.osc(Synth.Wave.SINE, n, f)
		s = Synth.add(s, Synth.osc(Synth.Wave.SINE, n, f * 2.0), 0.18)
		s = Synth.mul(s, Synth.env_decay(n, 0.07, SR, 0.002))
		_place(out, s, float(k) * 0.055, 0.5)
	return Synth.reverb(out, 0.3, 0.35, 0.15, SR, 0.15)


# ---- vocal synthesis -------------------------------------------------------------------------------------------------
static func _vowel(name: String, tract: float) -> Array:
	var src: Array = VOWELS[name]
	var out: Array = []
	for f in src:
		out.append([float(f[0]) * tract, float(f[1]) * (0.8 + 0.2 * tract), float(f[2])])
	return out


## f0 contour from [[t, hz], ...] with vibrato and slow random jitter (fractions of f0).
static func _contour(rng: RandomNumberGenerator, n: int, pts: Array, vib_hz: float, vib_depth: float, jitter: float) -> PackedFloat32Array:
	var f := Synth.env_points(n, pts)
	var jit := Synth.smooth_random(n, 38.0, SR, rng.randi())
	var vib := Synth.lfo(n, vib_hz, 0.0, vib_depth, SR, rng.randf())
	for i in n:
		f[i] = f[i] * (1.0 + vib[i] + (jit[i] - 0.5) * jitter)
	return f


static func _voice(rng: RandomNumberGenerator, f0: PackedFloat32Array, vow_a: Array, vow_b: Array, morph: PackedFloat32Array, breath: float, open_q: float, close_q: float, env: PackedFloat32Array) -> PackedFloat32Array:
	var n := f0.size()
	# spectral tilt: two one-pole low-passes soften the glottal derivative so the voice rolls off like a real throat
	var src := Synth.lp1(Synth.lp1(Synth.glottal(f0, SR, open_q, close_q), 2200.0), 4200.0)
	var a := Synth.formants(src, vow_a)
	var b := Synth.formants(src, vow_b)
	var out := Synth.zeros(n)
	var nz: PackedFloat32Array = PackedFloat32Array()
	if breath > 0.0:
		nz = Synth.formants(Synth.noise(n, rng.randi()), vow_a)
	for i in n:
		var m: float = morph[i]
		var s: float = a[i] * (1.0 - m) + b[i] * m
		if breath > 0.0:
			s += nz[i] * breath * 3.0
		out[i] = s * env[i]
	return Synth.lowpass(out, 5200.0, 0.6)


static func _hurt(rng: RandomNumberGenerator, v: int, female: bool) -> PackedFloat32Array:
	var dur: float = rng.randf_range(0.34, 0.5)
	var n := Synth.secs(dur)
	var base: float = (255.0 if female else 128.0) * rng.randf_range(0.9, 1.12)
	var tract: float = 1.17 if female else 1.0
	var f0 := _contour(rng, n, [[0.0, base * 0.95], [0.05, base * 1.18], [dur * 0.5, base * 1.0], [dur, base * 0.72]], 5.5, 0.012, 0.05)
	var va := _vowel(["o", "uh", "a", "ae"][v % 4], tract)
	var vb := _vowel(["a", "o", "e", "uh"][v % 4], tract)
	var morph := Synth.ramp(n, 0.0, 1.0)
	var env := Synth.env_points(n, [[0.0, 0.0], [0.018, 1.0], [dur * 0.35, 0.85], [dur, 0.0]])
	var out := _voice(rng, f0, va, vb, morph, 0.09, 0.5, 0.12 if female else 0.15, env)
	return Synth.soft_clip(out, 1.3 + 0.1 * float(v % 3))


static func _death(rng: RandomNumberGenerator, v: int, female: bool) -> PackedFloat32Array:
	var dur: float = 1.35 if not female else 1.25
	var n := Synth.secs(dur)
	var base: float = (300.0 if female else 140.0) * rng.randf_range(0.92, 1.08)
	var tract: float = 1.17 if female else 1.0
	var pts: Array = [[0.0, base * 1.1], [0.2, base * 1.15], [dur * 0.6, base * 0.65], [dur, base * 0.35]]
	var f0 := _contour(rng, n, pts, 4.5, 0.02, 0.1)
	# vocal-fry like roughness grows towards the end: extra random jitter weighted by time
	var jit2 := Synth.smooth_random(n, 60.0, SR, rng.randi())
	for i in n:
		var u: float = float(i) / float(n)
		f0[i] *= 1.0 + (jit2[i] - 0.5) * 0.35 * u * u
	var va := _vowel("a", tract)
	var vb := _vowel(["u", "o", "uh"][v % 3], tract)
	var morph := Synth.ramp(n, 0.0, 1.0)
	var env := Synth.env_points(n, [[0.0, 0.0], [0.03, 1.0], [dur * 0.4, 0.9], [dur * 0.8, 0.4], [dur, 0.0]])
	var out := _voice(rng, f0, va, vb, morph, 0.2, 0.55, 0.14, env)
	# gurgling / rattling exhale at the end
	var rattle := Synth.mul(Synth.formants(Synth.noise(n, rng.randi()), _vowel("uh", tract)), Synth.env_points(n, [[0.0, 0.0], [dur * 0.55, 0.0], [dur * 0.8, 0.5], [dur, 0.0]]))
	var rmod := Synth.lfo(n, 21.0, 0.6, 0.4)
	for i in n:
		out[i] += rattle[i] * rmod[i] * 0.9
	return Synth.soft_clip(out, 1.5)


static func _breath(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.3
	var n := Synth.secs(dur)
	var src := Synth.noise(n, rng.randi())
	var inh := Synth.formants(src, [[550.0, 250.0, 1.0], [1500.0, 350.0, 0.6], [3200.0, 500.0, 0.35]])
	var exh := Synth.formants(src, [[480.0, 220.0, 1.0], [1100.0, 300.0, 0.5], [2600.0, 500.0, 0.25]])
	var env_i := Synth.env_points(n, [[0.0, 0.0], [0.12, 0.45], [0.38, 0.9], [0.55, 0.5], [0.6, 0.0], [dur, 0.0]])
	var env_e := Synth.env_points(n, [[0.0, 0.0], [0.62, 0.0], [0.72, 0.8], [0.9, 1.0], [1.15, 0.35], [dur, 0.0]])
	var out := Synth.zeros(n)
	for i in n:
		out[i] = inh[i] * env_i[i] + exh[i] * env_e[i] * 0.8
	return out


static func _gasp(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.55
	var n := Synth.secs(dur)
	var src := Synth.noise(n, rng.randi())
	var s := Synth.formants(src, [[350.0, 150.0, 0.6], [2200.0, 300.0, 1.0], [3300.0, 450.0, 0.6]])
	s = Synth.mul(s, Synth.env_points(n, [[0.0, 0.0], [0.035, 1.0], [0.18, 0.55], [dur, 0.0]]))
	# short voiced catch at the end
	var f0 := _contour(rng, n, [[0.0, 190.0], [dur, 150.0]], 5.0, 0.01, 0.06)
	var vo := _voice(rng, f0, _vowel("i", 1.0), _vowel("e", 1.0), Synth.ramp(n, 0.0, 1.0), 0.0, 0.5, 0.15, Synth.env_points(n, [[0.0, 0.0], [0.2, 0.0], [0.3, 0.35], [dur, 0.0]]))
	return Synth.add(s, vo, 0.22)


static func _scream(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur := 1.45
	var n := Synth.secs(dur)
	var base: float = 420.0 * rng.randf_range(0.85, 1.2) * (1.0 if v != 2 else 0.5)
	var f0 := _contour(rng, n, [[0.0, base * 0.8], [0.12, base * 1.2], [0.3, base * 1.5], [0.9, base * 1.45], [dur, base * 1.0]], 6.2, 0.03, 0.07)
	var tract: float = 1.1 if v != 2 else 0.92
	var morph := Synth.ramp(n, 0.0, 1.0)
	var env := Synth.env_points(n, [[0.0, 0.0], [0.03, 1.0], [1.0, 0.9], [dur, 0.0]])
	var out := _voice(rng, f0, _vowel("a", tract), _vowel("ae", tract), morph, 0.16, 0.42, 0.05, env)
	return Synth.soft_clip(out, 2.2)


static func _cough(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.7))
	for k in 2:
		var dur: float = 0.16 if k == 0 else 0.22
		var n := Synth.secs(dur)
		var f0 := _contour(rng, n, [[0.0, 145.0], [dur, 105.0]], 0.0, 0.0, 0.2)
		var env := Synth.env_points(n, [[0.0, 0.0], [0.008, 1.0], [dur * 0.4, 0.5], [dur, 0.0]])
		var voc := _voice(rng, f0, _vowel("e", 1.0), _vowel("uh", 1.0), Synth.ramp(n, 0.0, 1.0), 0.8, 0.5, 0.1, env)
		_place(out, voc, 0.0 if k == 0 else 0.24, 1.0)
	return Synth.soft_clip(out, 1.2)
