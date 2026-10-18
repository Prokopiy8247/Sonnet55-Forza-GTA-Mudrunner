extends RefCounted
## Sound recipes: seamless looping ENGINE layers for every EngineSound profile.
##
## Each profile is rendered as N loops ("eng_<profile>_<i>") anchored at log-spaced firing frequencies between idle and
## redline, plus an optional tonal "whine" loop ("eng_<profile>_whine": intake / turbine / gear whine). At run time
## EngineSound cross-fades the two layers nearest to the current RPM and pitch-shifts each with pitch_scale.
##
## Piston engines are built physically-inspired: every firing event is an exhaust "pop" (two damped pipe resonances plus
## a noise burst) written into a CIRCULAR buffer, so every loop is perfectly seamless; the firing-order amplitude pattern
## and timing jitter give each engine its character (v8 burble, diesel knock, twin lope ...).

const Synth = preload("res://gta/code/audio/synth.gd")
const SR_E := 16000

## kind: piston | rotor | jet.  f_idle / f_red = firing (or blade-pass) frequency in Hz at idle / redline.
const PROFILES := {
	&"car_small": {"kind": "piston", "f_idle": 27.0, "f_red": 215.0, "layers": 4, "pattern": [1.0, 0.9, 0.95, 0.85], "timing": 0.05, "res1": 150.0, "tau1": 0.016, "res2": 430.0, "tau2": 0.008, "noise": 0.4, "bright": 15.0, "drive": 1.7, "knock": 0.0, "whine": 0.0, "rms": 0.2, "turbo": false, "burble": false, "doppler": true},
	&"car_v6": {"kind": "piston", "f_idle": 35.0, "f_red": 300.0, "layers": 4, "pattern": [1.0, 0.9, 0.96, 0.88, 0.98, 0.9], "timing": 0.05, "res1": 118.0, "tau1": 0.02, "res2": 330.0, "tau2": 0.01, "noise": 0.3, "bright": 13.0, "drive": 1.6, "knock": 0.0, "whine": 0.0, "rms": 0.2, "turbo": false, "burble": false, "doppler": true},
	&"car_v8": {"kind": "piston", "f_idle": 43.0, "f_red": 380.0, "layers": 4, "pattern": [1.0, 0.68, 0.95, 0.6, 1.0, 0.74, 0.9, 0.64], "timing": 0.14, "res1": 84.0, "tau1": 0.032, "res2": 215.0, "tau2": 0.015, "noise": 0.25, "bright": 11.0, "drive": 2.0, "knock": 0.0, "whine": 0.0, "rms": 0.22, "turbo": false, "burble": true, "doppler": true},
	&"sports": {"kind": "piston", "f_idle": 60.0, "f_red": 560.0, "layers": 4, "pattern": [1.0, 0.97, 1.0, 0.96, 1.0, 0.97, 1.0, 0.96], "timing": 0.03, "res1": 190.0, "tau1": 0.012, "res2": 540.0, "tau2": 0.006, "noise": 0.22, "bright": 14.0, "drive": 1.8, "knock": 0.0, "whine": 3000.0, "rms": 0.2, "turbo": true, "burble": true, "doppler": true},
	&"truck": {"kind": "piston", "f_idle": 30.0, "f_red": 140.0, "layers": 4, "pattern": [1.0, 0.8, 1.0, 0.85, 0.95, 0.8], "timing": 0.09, "res1": 95.0, "tau1": 0.03, "res2": 260.0, "tau2": 0.012, "noise": 0.3, "bright": 11.0, "drive": 2.2, "knock": 0.9, "whine": 2400.0, "rms": 0.24, "turbo": true, "burble": false, "doppler": true},
	&"bike": {"kind": "piston", "f_idle": 22.0, "f_red": 170.0, "layers": 4, "pattern": [1.0, 0.8], "offsets": [0.0, 0.25], "timing": 0.06, "res1": 270.0, "tau1": 0.011, "res2": 720.0, "tau2": 0.005, "noise": 0.3, "bright": 18.0, "drive": 1.7, "knock": 0.0, "whine": 2600.0, "rms": 0.2, "turbo": false, "burble": true, "doppler": true},
	&"boat": {"kind": "piston", "f_idle": 45.0, "f_red": 270.0, "layers": 3, "pattern": [1.0, 0.92, 0.96], "timing": 0.07, "res1": 170.0, "tau1": 0.014, "res2": 460.0, "tau2": 0.007, "noise": 0.5, "bright": 12.0, "drive": 1.6, "knock": 0.0, "whine": 0.0, "rms": 0.22, "turbo": false, "burble": false, "water": 0.5, "doppler": true},
	&"heli_rotor": {"kind": "rotor", "f_idle": 5.0, "f_red": 14.5, "layers": 3, "pattern": [1.0, 0.9], "timing": 0.02, "res1": 95.0, "tau1": 0.035, "res2": 240.0, "tau2": 0.02, "noise": 0.45, "bright": 90.0, "drive": 1.5, "knock": 0.0, "whine": 2700.0, "rms": 0.24, "turbo": false, "burble": false, "doppler": true},
	&"prop_plane": {"kind": "piston", "f_idle": 24.0, "f_red": 82.0, "layers": 3, "pattern": [1.0, 0.95, 1.0, 0.9], "timing": 0.03, "res1": 125.0, "tau1": 0.022, "res2": 280.0, "tau2": 0.011, "noise": 0.75, "bright": 24.0, "drive": 1.9, "knock": 0.0, "whine": 0.0, "rms": 0.24, "turbo": false, "burble": false, "prop": true, "doppler": true},
	&"jet": {"kind": "jet", "f_idle": 80.0, "f_red": 360.0, "layers": 3, "pattern": [1.0], "timing": 0.0, "res1": 0.0, "tau1": 0.01, "res2": 0.0, "tau2": 0.01, "noise": 1.0, "bright": 0.0, "drive": 1.4, "knock": 0.0, "whine": 3200.0, "rms": 0.24, "turbo": false, "burble": false, "doppler": true},
}

static var _INFO: Dictionary = {}
static var IDS: Dictionary = _build_ids()


static func _build_ids() -> Dictionary:
	var out := {}
	for p in PROFILES:
		var prof: Dictionary = PROFILES[p]
		for i in int(prof["layers"]):
			var id := StringName("eng_%s_%d" % [p, i])
			out[id] = {"cat": &"amb_loop", "var": 1, "peak": 0.85, "bus": "Engine"}
			_INFO[id] = [p, i]
		if float(prof["whine"]) > 0.0:
			var wid := StringName("eng_%s_whine" % p)
			out[wid] = {"cat": &"amb_loop", "var": 1, "peak": 0.5, "bus": "Engine"}
			_INFO[wid] = [p, -1]
	return out


## Firing / blade-pass frequency (Hz) of layer `i` of a profile (the frequency it was rendered at).
static func anchor_hz(profile: StringName, i: int) -> float:
	var p: Dictionary = PROFILES[profile]
	var n: int = int(p["layers"])
	var lo: float = float(p["f_idle"]) * 1.05
	var hi: float = float(p["f_red"]) * 0.92
	return lo * pow(hi / lo, float(i) / float(maxi(n - 1, 1)))


static func build(id: StringName, _v: int, rng: RandomNumberGenerator) -> Dictionary:
	if not _INFO.has(id):
		return {}
	var info: Array = _INFO[id]
	var profile: StringName = info[0]
	var layer: int = info[1]
	var P: Dictionary = PROFILES[profile]
	var buf: PackedFloat32Array
	if layer < 0:
		buf = _whine(P, profile, rng)
		return {"buf": buf, "sr": SR_E, "loop": true, "rms": 0.1}
	match String(P["kind"]):
		"jet":
			buf = _jet_layer(P, layer, rng)
		"rotor":
			buf = _piston_layer(P, anchor_hz(profile, layer), rng, true)
		_:
			buf = _piston_layer(P, anchor_hz(profile, layer), rng, false)
	return {"buf": buf, "sr": SR_E, "loop": true, "rms": float(P["rms"])}


static func _pulse(P: Dictionary, n_p: int, rotor: bool, rng: RandomNumberGenerator, variant_gain: float) -> PackedFloat32Array:
	var sr := SR_E
	var res1: float = float(P["res1"]) * rng.randf_range(0.92, 1.08)
	var res2: float = float(P["res2"]) * rng.randf_range(0.92, 1.08)
	# one-sided exhaust "puff": its exponential edge is what gives the firing train its rich harmonic series
	var puff_tau: float = (0.0045 if rotor else clampf(0.17 / res1, 0.0007, 0.0028)) * rng.randf_range(0.85, 1.2)
	var p := Synth.env_decay(n_p, puff_tau, sr, 0.0002)
	# pipe reflection: a delayed, inverted echo of the puff
	var d: int = maxi(int(float(sr) * 0.5 / res1), 2)
	var puff := p.duplicate()
	for i in range(d, n_p):
		p[i] -= 0.4 * puff[i - d]
	# body resonances of the exhaust / cabin
	p = Synth.add(p, Synth.ring(n_p, res1, float(P["tau1"]), sr, 0.4))
	p = Synth.add(p, Synth.ring(n_p, res2, float(P["tau2"]), sr, 0.22))
	if rotor:
		# blade slap: low pressure thump plus a short broadband "chop"
		p = Synth.add(p, Synth.noise_hit(float(n_p) / float(sr), 0.012, 220.0, 2200.0, rng.randi(), sr), 1.4)
		p = Synth.add(p, Synth.noise_hit(float(n_p) / float(sr), 0.005, 1200.0, 4800.0, rng.randi(), sr), 0.8)
	else:
		# combustion bang: short noise transient
		p = Synth.add(p, Synth.noise_hit(minf(float(n_p) / float(sr), 0.03), 0.003 + 0.0015 * variant_gain, 150.0, 3200.0, rng.randi(), sr), 0.4)
		if float(P["knock"]) > 0.0:
			# diesel combustion knock
			p = Synth.add(p, Synth.noise_hit(0.02, 0.003, 1500.0, 5000.0, rng.randi(), sr), float(P["knock"]) * 0.8)
	return p


static func _piston_layer(P: Dictionary, fa: float, rng: RandomNumberGenerator, rotor: bool) -> PackedFloat32Array:
	var sr := SR_E
	var pattern: Array = P["pattern"]
	var ncyl: int = pattern.size()
	var offsets: Array = P.get("offsets", [])
	var cycle_len: int = maxi(int(round(float(sr) * float(ncyl) / fa)), 16)
	var k: int = maxi(int(ceil(0.95 * float(sr) / float(cycle_len))), 1)
	var total: int = cycle_len * k
	var spacing: float = float(cycle_len) / float(ncyl)
	var out := Synth.zeros(total)
	var max_pulse: float = 0.1 if rotor else 0.07
	var n_p: int = clampi(int(2.4 * float(sr) / fa), int(0.025 * float(sr)), int(max_pulse * float(sr)))
	var variants: Array = []
	for vi in 3:
		variants.append(_pulse(P, n_p, rotor, rng, float(vi)))
	var timing: float = float(P["timing"])
	for c in k:
		for e in ncyl:
			var off: float = float(offsets[e]) if offsets.size() > e else 0.0
			var t: float = (float(c * ncyl + e) + off) * spacing + (rng.randf() - 0.5) * spacing * timing
			var amp: float = float(pattern[e]) * rng.randf_range(0.9, 1.1)
			Synth.mix_wrap(out, variants[rng.randi() % 3], int(t), amp)
	# intake / mechanical noise, amplitude-modulated at the (exactly periodic) firing rate
	var fire_hz: float = float(k * ncyl) * float(sr) / float(total)
	var nz := Synth.noise(total, rng.randi())
	nz = Synth.circular(nz, func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.band(b, fa * 2.0 + 60.0, minf(fa * 18.0 + 400.0, 5200.0), sr))
	var mod := Synth.lfo(total, fire_hz, 0.6, 0.4, sr, 0.25)
	var noise_amt: float = float(P["noise"]) * (0.7 if rotor else 1.0)
	for i in total:
		out[i] += nz[i] * mod[i] * noise_amt * 0.8
	# boats: water churn
	if float(P.get("water", 0.0)) > 0.0:
		var wn := Synth.circular(Synth.noise(total, rng.randi()), func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.band(b, 120.0, 900.0, sr))
		var wm := Synth.smooth_random(total, 9.0, sr, rng.randi())
		for i in total:
			out[i] += wn[i] * (0.4 + 0.6 * wm[i]) * float(P["water"]) * 1.2
	# propeller blade whoosh
	if P.get("prop", false):
		var pw := Synth.circular(Synth.noise(total, rng.randi()), func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.band(b, 300.0, 1800.0, sr))
		var pm := Synth.lfo(total, fire_hz * 0.5, 0.55, 0.45, sr, 0.0)
		for i in total:
			out[i] += pw[i] * pm[i] * 0.6
	# rotor: tail-rotor buzz and turbine rumble
	if rotor:
		var tail_hz: float = round(fa * 4.3 * float(total) / float(sr)) * float(sr) / float(total)
		var tail := Synth.osc(Synth.Wave.SAW, total, tail_hz, sr)
		tail = Synth.circular(tail, func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.band(b, 200.0, 1800.0, sr))
		Synth.mix_into(out, tail, 0, 0.1)
		var rum := Synth.circular(Synth.brown(total, rng.randi()), func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.lowpass(b, 140.0, 0.7, sr))
		Synth.mix_into(out, rum, 0, 0.12)
		var hiss := Synth.circular(Synth.noise(total, rng.randi()), func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.band(b, 700.0, 3200.0, sr))
		Synth.mix_into(out, hiss, 0, 0.16)
	# warmth: low-pass that opens with rpm (circular so the seam is clean)
	var cutoff: float = clampf(fa * float(P["bright"]), 650.0, 7000.0)
	out = Synth.circular(out, func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.lowpass(b, cutoff, 0.8, sr))
	# the one-sided puffs leave a DC offset: remove it (a constant, so loops stay seamless)
	var mean: float = 0.0
	for i in total:
		mean += out[i]
	mean /= float(total)
	for i in total:
		out[i] -= mean
	return Synth.soft_clip(out, maxf(float(P["drive"]) * 0.7, 1.1))


static func _jet_filter(b: PackedFloat32Array, c1: float, c2: float, c3: float, spool: float, sr: int) -> PackedFloat32Array:
	var a := Synth.biquad(b, Synth.Filt.BP, c1, 0.7, sr)
	var m := Synth.biquad(b, Synth.Filt.BP, c2, 0.9, sr)
	var h := Synth.biquad(b, Synth.Filt.BP, c3, 1.2, sr)
	var o := Synth.scale(a, 1.0)
	o = Synth.add(o, m, 0.8)
	o = Synth.add(o, h, 0.35 + 0.4 * spool)
	return o


static func _jet_layer(P: Dictionary, layer: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sr := SR_E
	var total: int = Synth.secs(1.0, sr)
	var spool: float = float(layer) / 2.0   # 0 idle .. 1 full thrust
	var src := Synth.pink(total, rng.randi())
	var c1: float = 280.0 + 300.0 * spool
	var c2: float = 900.0 + 1500.0 * spool
	var c3: float = 2600.0 + 2200.0 * spool
	var body := Synth.circular(src, _jet_filter.bind(c1, c2, c3, spool, sr))
	# turbine flutter (integer Hz => seamless over exactly 1 s)
	var flut := Synth.lfo(total, 23.0 + 17.0 * spool, 0.82, 0.18, sr)
	flut = Synth.add(flut, Synth.lfo(total, 7.0, 0.0, 0.07, sr), 1.0)
	var out := Synth.mul(body, flut)
	# low rumble
	var rum := Synth.circular(Synth.brown(total, rng.randi()), func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.lowpass(b, 180.0, 0.7, sr))
	Synth.mix_into(out, rum, 0, 0.3 - 0.12 * spool)
	return Synth.soft_clip(out, float(P["drive"]))


## Tonal whine loop: integer-Hz partials over exactly 1.0 s so it loops perfectly. Base frequency P["whine"].
static func _whine(P: Dictionary, profile: StringName, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sr := SR_E
	var n: int = sr
	var f: float = round(float(P["whine"]))
	var out := Synth.osc(Synth.Wave.SINE, n, f, sr)
	out = Synth.add(out, Synth.osc(Synth.Wave.SINE, n, f * 2.0, sr), 0.32)
	out = Synth.add(out, Synth.osc(Synth.Wave.SINE, n, f * 3.0, sr), 0.1)
	# two close partials -> slow beating like spinning vanes / gear mesh
	out = Synth.add(out, Synth.osc(Synth.Wave.SINE, n, f + 6.0, sr), 0.4)
	var am := Synth.lfo(n, 5.0, 0.85, 0.15, sr)
	out = Synth.mul(out, am)
	if profile == &"jet" or profile == &"heli_rotor":
		var sh := Synth.circular(Synth.noise(n, rng.randi()), func(b: PackedFloat32Array) -> PackedFloat32Array: return Synth.band(b, f * 0.7, f * 1.4, sr))
		Synth.mix_into(out, sh, 0, 0.35)
	return out
