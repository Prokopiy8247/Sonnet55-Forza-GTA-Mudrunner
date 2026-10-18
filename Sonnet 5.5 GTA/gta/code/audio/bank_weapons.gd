extends RefCounted
## Sound recipes: gunshots, reloads, melee, bullet/body impacts, explosions. Original procedural synthesis.

const Synth = preload("res://gta/code/audio/synth.gd")
const SR := 22050
const SR_LO := 16000   # dark / low heavy sounds are rendered at a lower rate (cheaper, nothing audible is lost)

const IDS := {
	&"shot_pistol": {"cat": &"weapon", "var": 3, "peak": 0.9, "unit": 18.0},
	&"shot_revolver": {"cat": &"weapon", "var": 2, "peak": 0.95, "unit": 22.0},
	&"shot_smg": {"cat": &"weapon", "var": 3, "peak": 0.85, "unit": 16.0, "poly": 6},
	&"shot_shotgun": {"cat": &"weapon", "var": 2, "peak": 0.97, "unit": 26.0},
	&"shot_rifle": {"cat": &"weapon", "var": 3, "peak": 0.95, "unit": 28.0, "poly": 6},
	&"shot_sniper": {"cat": &"weapon", "var": 2, "peak": 1.0, "unit": 45.0, "range": 320.0},
	&"shot_suppressed": {"cat": &"weapon", "var": 3, "peak": 0.6, "unit": 7.0, "range": 60.0},
	&"shot_rocket": {"cat": &"weapon", "var": 1, "peak": 0.97, "unit": 40.0, "range": 260.0},
	&"reload_start": {"cat": &"weapon_mech", "var": 2, "peak": 0.5},
	&"reload_end": {"cat": &"weapon_mech", "var": 2, "peak": 0.6},
	&"dry_fire": {"cat": &"weapon_mech", "var": 2, "peak": 0.45},
	&"melee_swing": {"cat": &"melee", "var": 3, "peak": 0.5},
	&"melee_hit": {"cat": &"melee", "var": 3, "peak": 0.8},
	&"punch": {"cat": &"melee", "var": 3, "peak": 0.75},
	&"hit_flesh": {"cat": &"impact", "var": 3, "peak": 0.7},
	&"hit_headshot": {"cat": &"impact", "var": 2, "peak": 0.85},
	&"hit_metal": {"cat": &"impact", "var": 3, "peak": 0.7},
	&"hit_concrete": {"cat": &"impact", "var": 3, "peak": 0.65},
	&"hit_glass": {"cat": &"impact", "var": 2, "peak": 0.6},
	&"hit_dirt": {"cat": &"impact", "var": 3, "peak": 0.55},
	&"hit_water": {"cat": &"impact", "var": 3, "peak": 0.5},
	&"explosion_small": {"cat": &"explosion", "var": 2, "peak": 0.98, "unit": 60.0},
	&"explosion_big": {"cat": &"explosion", "var": 2, "peak": 1.0, "unit": 110.0},
	&"grenade_bounce": {"cat": &"impact", "var": 2, "peak": 0.55},
	&"glass_break": {"cat": &"impact", "var": 2, "peak": 0.8, "unit": 18.0, "range": 80.0},
}


static func build(id: StringName, v: int, rng: RandomNumberGenerator) -> Dictionary:
	var b: PackedFloat32Array
	var sr: int = SR
	match id:
		&"shot_pistol":
			b = _gun(rng, {"dur": 0.5, "crack_tau": 0.005, "crack_hp": 1300.0, "crack_lp": 9500.0, "crack_gain": 0.9, "f0": 230.0, "f1": 95.0, "body_tau": 0.045, "body_gain": 0.8, "boom_tau": 0.07, "boom_lp": 800.0, "boom_gain": 0.5, "taps": [[0.07, 0.22], [0.16, 0.13], [0.3, 0.06]], "rev": 0.25})
		&"shot_revolver":
			b = _gun(rng, {"dur": 0.8, "crack_tau": 0.007, "crack_hp": 900.0, "crack_lp": 8500.0, "crack_gain": 1.0, "f0": 180.0, "f1": 62.0, "body_tau": 0.085, "body_gain": 1.0, "boom_tau": 0.14, "boom_lp": 600.0, "boom_gain": 0.7, "taps": [[0.09, 0.28], [0.21, 0.17], [0.38, 0.1], [0.55, 0.05]], "rev": 0.35})
		&"shot_smg":
			b = _gun(rng, {"dur": 0.3, "crack_tau": 0.0035, "crack_hp": 1800.0, "crack_lp": 10000.0, "crack_gain": 0.85, "f0": 320.0, "f1": 150.0, "body_tau": 0.028, "body_gain": 0.7, "boom_tau": 0.04, "boom_lp": 1100.0, "boom_gain": 0.4, "taps": [[0.05, 0.18], [0.12, 0.08]], "rev": 0.15})
		&"shot_shotgun":
			b = _gun(rng, {"dur": 1.1, "crack_tau": 0.013, "crack_hp": 500.0, "crack_lp": 7500.0, "crack_gain": 1.1, "f0": 130.0, "f1": 42.0, "body_tau": 0.13, "body_gain": 1.1, "boom_tau": 0.26, "boom_lp": 700.0, "boom_gain": 0.9, "taps": [[0.1, 0.3], [0.24, 0.2], [0.42, 0.12], [0.65, 0.07]], "rev": 0.45})
		&"shot_rifle":
			b = _gun(rng, {"dur": 0.9, "crack_tau": 0.007, "crack_hp": 1000.0, "crack_lp": 9000.0, "crack_gain": 1.0, "f0": 210.0, "f1": 72.0, "body_tau": 0.07, "body_gain": 0.9, "boom_tau": 0.12, "boom_lp": 900.0, "boom_gain": 0.6, "taps": [[0.1, 0.28], [0.23, 0.18], [0.38, 0.1], [0.58, 0.05]], "rev": 0.4})
		&"shot_sniper":
			b = _gun(rng, {"dur": 2.4, "crack_tau": 0.01, "crack_hp": 700.0, "crack_lp": 9000.0, "crack_gain": 1.1, "f0": 110.0, "f1": 34.0, "body_tau": 0.2, "body_gain": 1.3, "boom_tau": 0.42, "boom_lp": 450.0, "boom_gain": 1.0, "taps": [[0.14, 0.34], [0.31, 0.26], [0.55, 0.18], [0.88, 0.12], [1.3, 0.07]], "rev": 0.7})
		&"shot_suppressed":
			b = _suppressed(rng)
		&"shot_rocket":
			b = _rocket(rng)
			sr = SR_LO
		&"reload_start":
			b = _reload(rng, true)
		&"reload_end":
			b = _reload(rng, false)
		&"dry_fire":
			b = _dry_fire(rng)
		&"melee_swing":
			b = _swing(rng)
		&"melee_hit":
			b = _melee_hit(rng)
		&"punch":
			b = _punch(rng)
		&"hit_flesh":
			b = _hit_flesh(rng)
		&"hit_headshot":
			b = _hit_headshot(rng)
		&"hit_metal":
			b = _hit_metal(rng)
		&"hit_concrete":
			b = _hit_concrete(rng)
		&"hit_glass":
			b = _hit_glass(rng)
		&"hit_dirt":
			b = _hit_dirt(rng)
		&"hit_water":
			b = _hit_water(rng)
		&"explosion_small":
			b = _explosion(rng, false)
			sr = SR_LO
		&"explosion_big":
			b = _explosion(rng, true)
			sr = SR_LO
		&"grenade_bounce":
			b = _grenade_bounce(rng)
		&"glass_break":
			b = _glass_break(rng)
		_:
			return {}
	return {"buf": b, "sr": sr, "loop": false}


static func _place(dst: PackedFloat32Array, src: PackedFloat32Array, t: float, gain: float = 1.0, sr: int = SR) -> void:
	Synth.mix_into(dst, src, int(t * sr), gain)


## Generic firearm: crack (HF noise burst) + body thump + low "boom" noise + slap-back echoes + short reverb.
static func _gun(rng: RandomNumberGenerator, p: Dictionary) -> PackedFloat32Array:
	var dur: float = p["dur"]
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	var jitter: float = rng.randf_range(0.94, 1.06)
	# 1) supersonic-style crack: bright broadband burst
	_place(out, Synth.noise_hit(minf(dur, 0.25), float(p["crack_tau"]), float(p["crack_hp"]), float(p["crack_lp"]), rng.randi()), 0.0, float(p["crack_gain"]) * 1.15)
	# 2) muzzle blast: mid-band noise body (not tonal)
	_place(out, Synth.noise_hit(minf(dur, 0.4), float(p["body_tau"]) * 0.8, 180.0, 3600.0, rng.randi()), 0.0, 0.85)
	# 3) low thump (kept small so the shot does not sound like a sine)
	_place(out, Synth.thump(minf(dur, 0.6), float(p["f0"]) * jitter, float(p["f1"]), float(p["body_tau"])), 0.0, float(p["body_gain"]) * 0.4)
	# 4) low boom tail
	var boom := Synth.noise_hit(dur, float(p["boom_tau"]), 60.0, float(p["boom_lp"]), rng.randi())
	_place(out, boom, 0.0, float(p["boom_gain"]) * 0.8)
	# mechanical metallic ring of the action right after the shot
	_place(out, Synth.modal(Synth.secs(0.08), [[rng.randf_range(2600.0, 3400.0), 0.012, 1.0], [rng.randf_range(5200.0, 6300.0), 0.008, 0.5]]), 0.004, 0.12)
	out = Synth.echoes(out, p["taps"])
	out = Synth.reverb(out, 0.4, 0.55, float(p["rev"]) * 0.5, SR, 0.25)
	return Synth.soft_clip(out, 1.3)


static func _suppressed(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := Synth.secs(0.32)
	var out := Synth.zeros(n)
	_place(out, Synth.noise_hit(0.2, 0.022, 350.0, 2600.0, rng.randi()), 0.0, 0.9)
	_place(out, Synth.thump(0.15, 170.0, 95.0, 0.03), 0.0, 0.8)
	# bolt / action clack stays audible on a suppressed weapon
	_place(out, Synth.modal(Synth.secs(0.1), [[2200.0, 0.014, 1.0], [4100.0, 0.008, 0.5], [900.0, 0.02, 0.6]]), 0.045, 0.35)
	_place(out, Synth.noise_hit(0.04, 0.008, 1800.0, 6000.0, rng.randi()), 0.045, 0.2)
	return Synth.reverb(out, 0.25, 0.7, 0.1, SR, 0.15)


static func _rocket(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sr := SR_LO
	var dur := 1.9
	var n := Synth.secs(dur, sr)
	var out := Synth.zeros(n)
	# ignition whump
	_place(out, Synth.thump(0.5, 140.0, 38.0, 0.12, sr), 0.0, 1.0, sr)
	_place(out, Synth.noise_hit(0.12, 0.02, 400.0, 6000.0, rng.randi(), sr), 0.0, 0.8, sr)
	# motor roar: noise through a falling/rising band-pass with swell
	var roar := Synth.noise(n, rng.randi())
	roar = Synth.biquad_sweep(roar, Synth.Filt.BP, Synth.expramp(n, 1800.0, 650.0), 0.9, sr)
	roar = Synth.mul(roar, Synth.env_points(n, [[0.0, 0.0], [0.05, 0.9], [0.6, 0.7], [dur, 0.0]], sr))
	_place(out, roar, 0.0, 0.9, sr)
	# sub rumble
	var rum := Synth.lowpass(Synth.noise(n, rng.randi()), 160.0, 0.8, sr)
	rum = Synth.mul(rum, Synth.env_points(n, [[0.0, 1.0], [0.8, 0.7], [dur, 0.0]], sr))
	_place(out, rum, 0.0, 2.5, sr)
	return Synth.reverb(Synth.soft_clip(Synth.normalize(out, 0.7), 1.2), 0.5, 0.6, 0.2, sr, 0.4)


static func _reload(rng: RandomNumberGenerator, start: bool) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.42))
	var f: float = rng.randf_range(0.94, 1.06)
	if start:
		# magazine release button + mag slides out
		_place(out, Synth.modal(Synth.secs(0.1), [[1900.0 * f, 0.012, 1.0], [3300.0 * f, 0.007, 0.6], [700.0 * f, 0.02, 0.5]]), 0.0, 0.8)
		_place(out, Synth.thump(0.08, 210.0, 120.0, 0.02), 0.012, 0.5)
		_place(out, Synth.band(Synth.mul(Synth.noise(Synth.secs(0.1), rng.randi()), Synth.env_swell(Synth.secs(0.1), 0.3)), 1800.0, 5000.0), 0.03, 0.35)
	else:
		# magazine insert thunk then slide/charging clack
		_place(out, Synth.thump(0.1, 180.0, 90.0, 0.03), 0.0, 0.8)
		_place(out, Synth.modal(Synth.secs(0.1), [[1500.0 * f, 0.014, 1.0], [2700.0 * f, 0.009, 0.7], [4200.0 * f, 0.006, 0.4]]), 0.004, 0.6)
		_place(out, Synth.band(Synth.mul(Synth.noise(Synth.secs(0.1), rng.randi()), Synth.env_swell(Synth.secs(0.1), 0.6)), 1500.0, 4500.0), 0.14, 0.3)
		_place(out, Synth.modal(Synth.secs(0.12), [[2300.0 * f, 0.016, 1.0], [3900.0 * f, 0.01, 0.6], [1100.0 * f, 0.02, 0.5]]), 0.22, 0.85)
		_place(out, Synth.thump(0.08, 260.0, 140.0, 0.02), 0.22, 0.5)
	return out


static func _dry_fire(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.14))
	var f: float = rng.randf_range(0.93, 1.07)
	_place(out, Synth.modal(Synth.secs(0.12), [[950.0 * f, 0.016, 1.0], [2400.0 * f, 0.009, 0.7], [4300.0 * f, 0.005, 0.3]]), 0.0, 1.0)
	_place(out, Synth.thump(0.05, 240.0, 150.0, 0.012), 0.0, 0.5)
	return out


static func _swing(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.32
	var n := Synth.secs(dur)
	var s := Synth.noise(n, rng.randi())
	var f0: float = rng.randf_range(350.0, 500.0)
	s = Synth.biquad_sweep(s, Synth.Filt.BP, Synth.expramp(n, f0, f0 * 5.0), 1.3)
	s = Synth.mul(s, Synth.env_swell(n, 0.4, 1.4))
	return s


static func _melee_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.35))
	_place(out, Synth.thump(0.25, rng.randf_range(130.0, 170.0), 55.0, 0.06), 0.0, 0.9)
	_place(out, Synth.noise_hit(0.12, 0.022, 300.0, 3000.0, rng.randi()), 0.0, 0.8)
	_place(out, Synth.noise_hit(0.04, 0.008, 2000.0, 7000.0, rng.randi()), 0.0, 0.35)
	return out


static func _punch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.3))
	_place(out, Synth.thump(0.2, rng.randf_range(190.0, 240.0), 80.0, 0.045), 0.0, 0.9)
	_place(out, Synth.noise_hit(0.1, 0.016, 500.0, 3800.0, rng.randi()), 0.0, 0.7)
	_place(out, Synth.noise_hit(0.025, 0.005, 2500.0, 8000.0, rng.randi()), 0.0, 0.3)
	return out


static func _hit_flesh(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.3))
	_place(out, Synth.thump(0.2, rng.randf_range(100.0, 130.0), 55.0, 0.05), 0.0, 0.85)
	_place(out, Synth.noise_hit(0.15, 0.03, 200.0, 1500.0, rng.randi()), 0.005, 0.7)
	# wet squelch
	var sq := Synth.noise(Synth.secs(0.12), rng.randi())
	sq = Synth.biquad_sweep(sq, Synth.Filt.BP, Synth.expramp(sq.size(), 900.0, 350.0), 3.0)
	_place(out, Synth.mul(sq, Synth.env_decay(sq.size(), 0.04)), 0.02, 0.5)
	return out


static func _hit_headshot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.35))
	_place(out, Synth.noise_hit(0.05, 0.006, 1800.0, 9000.0, rng.randi()), 0.0, 0.9)
	_place(out, Synth.thump(0.2, 190.0, 70.0, 0.05), 0.0, 0.8)
	_place(out, Synth.noise_hit(0.2, 0.04, 250.0, 1800.0, rng.randi()), 0.006, 0.6)
	_place(out, Synth.modal(Synth.secs(0.15), [[3300.0, 0.03, 0.7], [5200.0, 0.02, 0.4]]), 0.0, 0.35)
	return out


static func _hit_metal(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var f: float = rng.randf_range(0.85, 1.25)
	var parts: Array = [[1250.0 * f, 0.14, 1.0], [2310.0 * f, 0.1, 0.7], [3780.0 * f, 0.07, 0.5], [5230.0 * f, 0.05, 0.3], [800.0 * f, 0.18, 0.5]]
	var out := Synth.modal(Synth.secs(0.6), parts)
	_place(out, Synth.noise_hit(0.015, 0.003, 2500.0, 0.0, rng.randi()), 0.0, 1.0)
	_place(out, Synth.thump(0.05, 400.0, 250.0, 0.01), 0.0, 0.6)
	return out


static func _hit_concrete(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.4))
	_place(out, Synth.noise_hit(0.05, 0.007, 1800.0, 9000.0, rng.randi()), 0.0, 0.9)
	_place(out, Synth.thump(0.08, 320.0, 160.0, 0.014), 0.0, 0.6)
	_place(out, Synth.mul(Synth.band(Synth.crackle(Synth.secs(0.25), 400.0, SR, rng.randi(), 0.004), 900.0, 6500.0), Synth.env_decay(Synth.secs(0.25), 0.07)), 0.01, 1.2)
	return out


static func _hit_glass(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.55))
	_place(out, Synth.noise_hit(0.06, 0.012, 4000.0, 0.0, rng.randi()), 0.0, 0.8)
	for k in 5:
		var f: float = rng.randf_range(3000.0, 8000.0)
		_place(out, Synth.modal(Synth.secs(0.2), [[f, 0.05, 1.0], [f * 1.47, 0.03, 0.5]]), float(k) * 0.025 + rng.randf() * 0.01, 0.35)
	return out


static func _hit_dirt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.3))
	_place(out, Synth.noise_hit(0.2, 0.045, 150.0, 1100.0, rng.randi()), 0.0, 0.9)
	_place(out, Synth.thump(0.12, 130.0, 70.0, 0.03), 0.0, 0.5)
	_place(out, Synth.mul(Synth.band(Synth.crackle(Synth.secs(0.2), 300.0, SR, rng.randi(), 0.003), 600.0, 3500.0), Synth.env_decay(Synth.secs(0.2), 0.06)), 0.02, 0.6)
	return out


static func _hit_water(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.35))
	var n := Synth.secs(0.12)
	var chirp := Synth.osc_sweep(Synth.Wave.SINE, n, 420.0, 1500.0)
	_place(out, Synth.mul(chirp, Synth.env_decay(n, 0.035, SR, 0.002)), 0.0, 0.7)
	_place(out, Synth.noise_hit(0.25, 0.05, 700.0, 4500.0, rng.randi()), 0.0, 0.5)
	for k in 3:
		var nn := Synth.secs(0.08)
		_place(out, Synth.mul(Synth.osc_sweep(Synth.Wave.SINE, nn, 600.0 + 400.0 * float(k), 1700.0 + 300.0 * float(k)), Synth.env_decay(nn, 0.02)), 0.05 + 0.04 * float(k), 0.25)
	return out


static func _grenade_bounce(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := Synth.zeros(Synth.secs(0.5))
	var f: float = rng.randf_range(0.9, 1.15)
	for k in 2:
		var g: float = 1.0 if k == 0 else 0.55
		var t: float = 0.0 if k == 0 else 0.17
		_place(out, Synth.modal(Synth.secs(0.2), [[2800.0 * f, 0.04, 1.0], [1900.0 * f, 0.05, 0.7], [4100.0 * f, 0.02, 0.4], [1200.0 * f, 0.06, 0.4]]), t, 0.5 * g)
		_place(out, Synth.thump(0.1, 180.0, 90.0, 0.03), t, 0.7 * g)
		_place(out, Synth.noise_hit(0.02, 0.004, 2500.0, 0.0, rng.randi()), t, 0.3 * g)
	return out


static func _glass_break(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 1.0
	var n := Synth.secs(dur)
	var out := Synth.zeros(n)
	# initial crash
	var crash := Synth.highpass(Synth.noise(Synth.secs(0.35), rng.randi()), 2800.0)
	crash = Synth.mul(crash, Synth.env_decay(crash.size(), 0.09, SR, 0.001))
	_place(out, crash, 0.0, 0.9)
	_place(out, Synth.thump(0.1, 420.0, 250.0, 0.015), 0.0, 0.4)
	# tinkling shards
	for k in 26:
		var t: float = pow(rng.randf(), 1.6) * 0.8
		var f: float = rng.randf_range(2400.0, 9000.0)
		var tau: float = rng.randf_range(0.015, 0.06)
		_place(out, Synth.modal(Synth.secs(0.18), [[f, tau, 1.0], [f * 1.53, tau * 0.6, 0.45]]), 0.02 + t, rng.randf_range(0.12, 0.35) * (1.0 - t))
	return Synth.reverb(out, 0.3, 0.3, 0.1, SR, 0.2)


static func _explosion(rng: RandomNumberGenerator, big: bool) -> PackedFloat32Array:
	var sr := SR_LO
	var dur: float = 4.2 if big else 2.3
	var n := Synth.secs(dur, sr)
	var out := Synth.zeros(n)
	var s: float = 1.0 if big else 0.6
	# initial blast crack (HF)
	_place(out, Synth.noise_hit(0.12, 0.018 * (1.0 + s * 0.3), 500.0, 7500.0, rng.randi(), sr), 0.0, 0.9, sr)
	# main boom: huge pitched-down thump
	_place(out, Synth.thump(1.4 * s + 0.4, 130.0 * (1.1 - 0.1 * s), 44.0 + 8.0 * (1.0 - s), 0.3 * s + 0.1, sr), 0.0, 1.2, sr)
	# audible mid "body" of the blast so it also reads on small speakers
	var bd := Synth.noise(n, rng.randi())
	bd = Synth.biquad_sweep(bd, Synth.Filt.BP, Synth.expramp(n, 1100.0, 190.0), 0.7, sr)
	bd = Synth.mul(bd, Synth.env_points(n, [[0.0, 0.0], [0.02, 1.0], [0.4 * s + 0.15, 0.5], [dur * 0.6, 0.0]], sr))
	_place(out, bd, 0.0, 1.0, sr)
	# fireball roar: swept low-pass noise
	var rn := Synth.noise(n, rng.randi())
	rn = Synth.biquad_sweep(rn, Synth.Filt.LP, Synth.expramp(n, 5200.0, 140.0), 0.9, sr)
	rn = Synth.mul(rn, Synth.env_points(n, [[0.0, 0.0], [0.02, 1.0], [0.25 * s + 0.1, 0.6], [dur * 0.55, 0.15], [dur, 0.0]], sr))
	_place(out, rn, 0.0, 1.1, sr)
	# rolling sub-bass rumble tail (brown noise, long)
	var rb := Synth.lowpass(Synth.brown(n, rng.randi()), 110.0, 0.8, sr)
	rb = Synth.mul(rb, Synth.env_points(n, [[0.0, 0.0], [0.08, 1.0], [dur * 0.5, 0.55], [dur, 0.0]], sr))
	_place(out, rb, 0.0, 3.0 if big else 2.0, sr)
	# sustained sub sine for the tail (+ harmonic via soft clip so it is audible on small speakers)
	var sub := Synth.osc_sweep(Synth.Wave.SINE, n, 62.0 if big else 74.0, 36.0 if big else 46.0, sr)
	sub = Synth.mul(sub, Synth.env_points(n, [[0.0, 0.0], [0.05, 1.0], [dur * 0.6, 0.3], [dur, 0.0]], sr))
	_place(out, sub, 0.0, 0.45, sr)
	# debris: falling crackle
	var deb := Synth.crackle(n, 70.0 if big else 45.0, sr, rng.randi(), 0.006, 0.9)
	deb = Synth.band(deb, 500.0, 5000.0, sr)
	deb = Synth.mul(deb, Synth.env_points(n, [[0.0, 0.0], [0.35, 0.9], [dur * 0.8, 0.0]], sr))
	_place(out, deb, 0.0, 0.7, sr)
	# keep the heavy low end from slamming into the soft clipper (that made the sub-bass chatter into spikes)
	out = Synth.normalize(out, 0.62)
	out = Synth.reverb(out, 0.85 if big else 0.6, 0.6, 0.3 if big else 0.2, sr, 0.5)
	return Synth.soft_clip(Synth.normalize(out, 0.75), 1.15)
