extends RefCounted
## RadioMusic - original generative music for the in-car radio stations (pure synthesis, no samples).
##
## A station is a data spec (tempo, key, chord progressions, drum / bass / chord / lead styles, mix chain). compose() turns
## it into note events for one 4-bar phrase using seeded randomness (chord progressions, bass / arp patterns, motifs with
## repetition + mutation, fills), render() synthesises the instruments (with a per-station note cache), sequences them with
## swing, applies sidechain pumping / delay / reverb and returns a stereo phrase plus the reverb tail to carry into the next
## phrase. Phrases chain endlessly and never repeat exactly. All functions are static and thread-safe (no engine state).

const Synth = preload("res://gta/code/audio/synth.gd")
const SR := 22050
const STEPS_PER_BAR := 16
const PHRASE_BARS := 4
const TAIL_S := 1.8

const CHORDS := {
	"m": [0, 3, 7], "m7": [0, 3, 7, 10], "m9": [0, 3, 7, 10, 14], "maj": [0, 4, 7], "maj7": [0, 4, 7, 11],
	"maj9": [0, 4, 7, 11, 14], "7": [0, 4, 7, 10], "9": [0, 4, 7, 10, 14], "sus": [0, 5, 7, 10], "m11": [0, 3, 7, 10, 17],
	"13": [0, 4, 7, 10, 14, 21], "add9": [0, 4, 7, 14],
}

## Station specs. Progression entry = [semitones above the key root, chord type].
const STATIONS := {
	&"halcyon_fm": {
		"name": "Halcyon FM", "tag": "Chill synthwave for the coast road", "style": "synthwave", "seed": 1984,
		"bpm": 98.0, "swing": 0.0, "root": 45, "scale": [0, 2, 3, 5, 7, 8, 10],
		"progs": [
			[[0, "m9"], [8, "maj9"], [3, "maj7"], [10, "9"]],
			[[0, "m7"], [5, "m7"], [8, "maj7"], [7, "7"]],
			[[8, "maj9"], [10, "9"], [0, "m9"], [0, "m7"]],
			[[0, "m7"], [10, "maj7"], [8, "maj7"], [10, "9"]],
		],
		"jingle": [69, 76, 72, 81], "gain": 1.0,
	},
	&"lofi_harbor": {
		"name": "Lo-Fi Harbor", "tag": "Slow beats for sleepless docks", "style": "lofi", "seed": 7621,
		"bpm": 76.0, "swing": 0.6, "swing_grid": 4, "root": 50, "scale": [0, 2, 4, 7, 9],
		"progs": [
			[[0, "m9"], [5, "9"], [10, "maj9"], [3, "maj7"]],
			[[0, "m7"], [7, "m9"], [10, "maj7"], [5, "9"]],
			[[10, "maj9"], [0, "m9"], [5, "13"], [0, "m7"]],
			[[3, "maj9"], [0, "m9"], [7, "9"], [10, "maj7"]],
		],
		"jingle": [74, 71, 67, 62], "gain": 1.0,
	},
	&"calle_funk": {
		"name": "Calle Funk 99.1", "tag": "Latin funk and good vibes, all night", "style": "funk", "seed": 9910,
		"bpm": 108.0, "swing": 0.3, "swing_grid": 2, "root": 50, "scale": [0, 2, 3, 5, 7, 9, 10],
		"progs": [
			[[0, "m7"], [5, "9"], [0, "m7"], [7, "9"]],
			[[0, "m9"], [0, "m7"], [5, "9"], [5, "9"]],
			[[0, "m7"], [10, "9"], [5, "9"], [7, "7"]],
		],
		"jingle": [62, 65, 69, 72], "gain": 1.0,
	},
	&"neon_static": {
		"name": "Neon Static", "tag": "Night-drive electro, no commercials", "style": "electro", "seed": 2077,
		"bpm": 122.0, "swing": 0.0, "root": 42, "scale": [0, 2, 3, 5, 7, 8, 10],
		"progs": [
			[[0, "m"], [8, "maj"], [3, "maj"], [10, "maj"]],
			[[0, "m"], [0, "m"], [5, "m"], [7, "maj"]],
			[[8, "maj"], [10, "maj"], [0, "m"], [0, "m"]],
		],
		"jingle": [66, 73, 78, 85], "gain": 1.0,
	},
}

const SECTIONS := [
	{"name": "intro", "drums": 0.3, "bass": 0.0, "chords": 1.0, "arp": 0.5, "lead": 0.0, "perc": 0.2},
	{"name": "A", "drums": 1.0, "bass": 1.0, "chords": 1.0, "arp": 1.0, "lead": 0.0, "perc": 1.0},
	{"name": "A2", "drums": 1.0, "bass": 1.0, "chords": 1.0, "arp": 1.0, "lead": 0.6, "perc": 1.0},
	{"name": "B", "drums": 1.0, "bass": 1.0, "chords": 1.0, "arp": 0.6, "lead": 1.0, "perc": 1.0},
	{"name": "A3", "drums": 1.0, "bass": 1.0, "chords": 1.0, "arp": 1.0, "lead": 0.3, "perc": 1.0},
	{"name": "B2", "drums": 1.0, "bass": 1.0, "chords": 1.0, "arp": 0.5, "lead": 1.0, "perc": 1.0},
	{"name": "break", "drums": 0.0, "bass": 0.0, "chords": 1.0, "arp": 0.4, "lead": 0.8, "perc": 0.0},
	{"name": "build", "drums": 0.8, "bass": 0.7, "chords": 1.0, "arp": 1.0, "lead": 0.0, "perc": 0.6},
]


static func station_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in STATIONS:
		out.append(k)
	return out


static func step_seconds(spec: Dictionary) -> float:
	return 60.0 / float(spec["bpm"]) / 4.0


static func phrase_samples(spec: Dictionary) -> int:
	return int(round(step_seconds(spec) * float(STEPS_PER_BAR * PHRASE_BARS) * float(SR)))


# =========================================================================================================
# Composition (events)
# =========================================================================================================
## event = [inst: String, midi: int, step: float, dur_steps: float, vel: float, pan: float, stem: int]
## stems: 0 drums, 1 bass, 2 chords/pads, 3 lead + arp, 4 percussion / fx
static func compose(spec: Dictionary, phrase_index: int, rng: RandomNumberGenerator, motif_state: Dictionary) -> Array:
	var sec: Dictionary = SECTIONS[phrase_index % SECTIONS.size()]
	var ev: Array = []
	var progs: Array = spec["progs"]
	var prog: Array = progs[(phrase_index / 2 + (1 if sec["name"].begins_with("B") else 0)) % progs.size()]
	if rng.randf() < 0.18:
		prog = progs[rng.randi() % progs.size()]
	match String(spec["style"]):
		"synthwave":
			_compose_synthwave(spec, sec, prog, rng, motif_state, ev, phrase_index)
		"lofi":
			_compose_lofi(spec, sec, prog, rng, motif_state, ev, phrase_index)
		"funk":
			_compose_funk(spec, sec, prog, rng, motif_state, ev, phrase_index)
		_:
			_compose_electro(spec, sec, prog, rng, motif_state, ev, phrase_index)
	return ev


static func _chord_notes(root: int, chord: Array, octave_shift: int = 0) -> Array:
	var type: String = chord[1]
	var r: int = root + int(chord[0]) + 12 * octave_shift
	var out: Array = []
	for iv in CHORDS[type]:
		out.append(r + int(iv))
	return out


static func _drum_events(ev: Array, pattern: String, inst: String, bar: int, vel: float, pan: float, stem: int = 0, ghost_vel: float = 0.45) -> void:
	for i in pattern.length():
		var c := pattern[i]
		if c == ".":
			continue
		var v: float = vel
		if c == "o":
			v = vel * 0.65
		elif c == "g":
			v = vel * ghost_vel
		ev.append([inst, -1, float(bar * STEPS_PER_BAR + i), 1.0, v, pan, stem])


## Scale tone nearest to `target` midi (scale defined by semitone offsets from root).
static func _snap(target: int, root: int, scale: Array) -> int:
	var best: int = target
	var bd := 99
	for oct in range(-2, 3):
		for s in scale:
			var m: int = root + 12 * (target - root) / 12 + int(s) + 12 * oct
			var d := absi(m - target)
			if d < bd:
				bd = d
				best = m
	return best


## Melody motif: array of [step_in_2_bars, scale_degree_offset_from_start, dur_steps]
static func _make_motif(rng: RandomNumberGenerator, density: float, rhythm_pool: Array) -> Array:
	var rhythm: Array = rhythm_pool[rng.randi() % rhythm_pool.size()]
	var motif: Array = []
	var deg: int = rng.randi_range(0, 4)
	for r in rhythm:
		if rng.randf() > density:
			continue
		var move: int = [-2, -1, -1, 0, 1, 1, 2, 3][rng.randi() % 8]
		deg = clampi(deg + move, -2, 9)
		motif.append([float(r[0]), deg, float(r[1])])
	return motif


static func _place_motif(ev: Array, motif: Array, spec: Dictionary, chord_root: int, bar_start: int, inst: String, base_midi: int, pan: float, vel: float, transpose_deg: int = 0, step_offset: float = 0.0) -> void:
	var scale: Array = spec["scale"]
	var root: int = int(spec["root"])
	for n in motif:
		var deg: int = int(n[1]) + transpose_deg
		var oct: int = deg / scale.size() if deg >= 0 else -((-deg + scale.size() - 1) / scale.size())
		var idx: int = posmod(deg, scale.size())
		var midi: int = base_midi + int(scale[idx]) + 12 * oct
		ev.append([inst, midi, float(bar_start * STEPS_PER_BAR) + float(n[0]) + step_offset, float(n[2]), vel, pan, 3])


static func _compose_synthwave(spec: Dictionary, sec: Dictionary, prog: Array, rng: RandomNumberGenerator, ms: Dictionary, ev: Array, pi: int) -> void:
	var root: int = int(spec["root"])
	var swing_rhythms: Array = [
		[[0, 3], [3, 3], [6, 2], [8, 4], [12, 4]], [[0, 6], [6, 2], [8, 3], [11, 5]], [[2, 2], [4, 4], [10, 2], [12, 4]],
		[[0, 2], [2, 2], [4, 6], [10, 6]],
	]
	if not ms.has("motif") or rng.randf() < 0.4:
		ms["motif"] = _make_motif(rng, 0.9, swing_rhythms)
	for bar in PHRASE_BARS:
		var chord: Array = prog[bar]
		var tones: Array = _chord_notes(root + 12, chord)
		# pad: whole-bar chord
		if float(sec["chords"]) > 0.0:
			ev.append(["pad", tones[0], float(bar * 16), 16.0, 0.8, 0.0, 2])
			ev[ev.size() - 1].append(tones)
		# drums
		if float(sec["drums"]) > 0.0:
			var dv: float = float(sec["drums"])
			_drum_events(ev, "x...x...x...x...", "kick_sw", bar, dv, 0.0)
			_drum_events(ev, "....x.......x...", "clap_sw", bar, dv, 0.05)
			_drum_events(ev, "..o...o...o...o.", "hat_o_sw", bar, dv * 0.6, 0.3)
			_drum_events(ev, "x.x.x.x.x.x.x.x.", "hat_c_sw", bar, dv * 0.7, -0.2)
			if bar == 3 and pi % 4 == 3:
				_drum_events(ev, "............xxxx", "snare_sw", bar, dv, 0.0)
		# bass: driving eighths
		if float(sec["bass"]) > 0.0:
			var br: int = root - 12 + int(chord[0])
			for i in 8:
				var note: int = br
				if i == 3 or i == 7:
					note = br + 12
				elif i == 5 and rng.randf() < 0.5:
					note = br + 7
				ev.append(["bass_sw", note, float(bar * 16 + i * 2), 1.7, 0.9 if i % 4 == 0 else 0.7, 0.0, 1])
		# arp
		if float(sec["arp"]) > 0.0:
			var arp_tones: Array = _chord_notes(root + 24, chord) + _chord_notes(root + 36, chord)
			var order: Array = [0, 1, 2, 3, 2, 1] if rng.randf() < 0.5 else [0, 2, 1, 3, 2, 4]
			var every: int = 1 if float(sec["arp"]) >= 0.9 else 2
			for i in range(0, 16, every):
				var tone: int = arp_tones[int(order[(i / every) % order.size()]) % arp_tones.size()]
				ev.append(["arp_sw", tone, float(bar * 16 + i), 1.5, 0.55 if i % 4 else 0.8, -0.45 if (i / every) % 2 == 0 else 0.45, 3])
	# lead
	if float(sec["lead"]) > 0.0:
		var motif: Array = ms["motif"]
		for half in 2:
			var tr: int = 0 if half == 0 else int([0, 1, -1, 2][rng.randi() % 4])
			if rng.randf() < 1.0 - float(sec["lead"]):
				continue
			_place_motif(ev, motif, spec, root, half * 2, "lead_sw", root + 36, 0.15, 0.7, tr)


static func _compose_lofi(spec: Dictionary, sec: Dictionary, prog: Array, rng: RandomNumberGenerator, ms: Dictionary, ev: Array, pi: int) -> void:
	var root: int = int(spec["root"])
	var comp_patterns: Array = [[0.0], [0.0, 6.0], [0.0, 3.0, 8.0], [0.0, 10.0], [0.0, 6.0, 11.0]]
	var melody_rhythms: Array = [[[2, 3], [6, 4], [11, 3]], [[0, 4], [5, 3], [9, 5]], [[3, 2], [7, 3], [12, 4]]]
	if not ms.has("motif") or rng.randf() < 0.5:
		ms["motif"] = _make_motif(rng, 0.85, melody_rhythms)
	var comp: Array = comp_patterns[rng.randi() % comp_patterns.size()]
	for bar in PHRASE_BARS:
		var chord: Array = prog[bar]
		var tones: Array = _chord_notes(root + 12, chord)
		if float(sec["chords"]) > 0.0:
			for ci in comp.size():
				var st: float = float(comp[ci])
				for k in tones.size():
					# slow strum
					ev.append(["epiano", tones[k], float(bar * 16) + st + float(k) * 0.28, 6.0 if ci == 0 else 3.0, (0.7 if ci == 0 else 0.5) * (0.85 + rng.randf() * 0.25), -0.15 + float(k) * 0.07, 2])
		if float(sec["drums"]) > 0.0:
			var dv: float = float(sec["drums"])
			_drum_events(ev, "x.....x..x......" if bar % 2 == 0 else "x.....x...x.....", "kick_lo", bar, dv, 0.0)
			_drum_events(ev, "....x.......x...", "snare_lo", bar, dv, 0.0)
			_drum_events(ev, "x.x.x.x.x.x.x.x.", "hat_lo", bar, dv * (0.5 + rng.randf() * 0.2), 0.2, 0, 0.6)
			if rng.randf() < 0.35:
				_drum_events(ev, "...............g", "snare_lo", bar, dv, 0.0)
		if float(sec["bass"]) > 0.0:
			var br: int = root - 12 + int(chord[0])
			ev.append(["bass_lo", br, float(bar * 16), 7.0, 0.85, 0.0, 1])
			if rng.randf() < 0.65:
				ev.append(["bass_lo", br + 7, float(bar * 16 + 8), 4.0, 0.65, 0.0, 1])
			if rng.randf() < 0.4:
				ev.append(["bass_lo", br + 12, float(bar * 16 + 12), 3.0, 0.55, 0.0, 1])
		# sparse bell / rhodes melody
		if float(sec["lead"]) > 0.0 and rng.randf() < 0.55 + 0.3 * float(sec["lead"]):
			var motif: Array = ms["motif"]
			var one_bar: Array = []
			for n in motif:
				if float(n[0]) < 16.0:
					one_bar.append(n)
			_place_motif(ev, one_bar, spec, root, bar, "bell_lo", root + 36, 0.3, 0.55, 0)
	# vinyl texture marker (rendered in the mix stage)
	ev.append(["vinyl", -1, 0.0, 64.0, 1.0, 0.0, 4])


static func _compose_funk(spec: Dictionary, sec: Dictionary, prog: Array, rng: RandomNumberGenerator, ms: Dictionary, ev: Array, pi: int) -> void:
	var root: int = int(spec["root"])
	var bass_lines: Array = ["x..x.xx..x.x..xx", "x.xx..x.x..xx.x.", "x..xx.x...x.xx.x", "x.x..x.xx.x..xx."]
	var stab_patterns: Array = [[2, 6, 10, 14], [3, 7, 11, 14], [2, 5, 10, 13], [6, 10, 11, 14]]
	var riffs: Array = [[[0, 2], [3, 1], [6, 2], [8, 2], [11, 1], [12, 3]], [[2, 2], [6, 1], [7, 1], [10, 2], [14, 2]], [[0, 1], [2, 1], [4, 3], [10, 3]]]
	if not ms.has("bass") or rng.randf() < 0.25:
		ms["bass"] = bass_lines[rng.randi() % bass_lines.size()]
		ms["stab"] = stab_patterns[rng.randi() % stab_patterns.size()]
	if not ms.has("motif") or rng.randf() < 0.45:
		ms["motif"] = _make_motif(rng, 0.95, riffs)
	var bl: String = ms["bass"]
	for bar in PHRASE_BARS:
		var chord: Array = prog[bar]
		var tones: Array = _chord_notes(root + 12, chord)
		var br: int = root - 12 + int(chord[0])
		if float(sec["drums"]) > 0.0:
			var dv: float = float(sec["drums"])
			_drum_events(ev, "x..x..x...x..x..", "kick_fk", bar, dv, 0.0)
			_drum_events(ev, "....x..g.g..x..g", "snare_fk", bar, dv, 0.0)
			_drum_events(ev, "xoxgxoxgxoxgxoxg", "hat_fk", bar, dv * 0.55, -0.25, 0, 0.5)
			if bar == 3:
				_drum_events(ev, "............xxxx" if pi % 2 == 1 else "..............xx", "snare_fk", bar, dv, 0.0)
		if float(sec["perc"]) > 0.0:
			var pv: float = float(sec["perc"])
			_drum_events(ev, "x..x..x...x.x...", "clave", bar, pv * 0.6, -0.4, 4)
			_drum_events(ev, "x...x...x...x...", "cowbell", bar, pv * 0.35, 0.4, 4)
			_drum_events(ev, "..x...xo..x..xo.", "conga_hi", bar, pv * 0.6, 0.5, 4, 0.5)
			_drum_events(ev, "o..x....o..x..x.", "conga_lo", bar, pv * 0.6, -0.5, 4, 0.5)
			_drum_events(ev, "xxxxxxxxxxxxxxxx", "shaker", bar, pv * 0.4, 0.2, 4, 0.5)
		if float(sec["bass"]) > 0.0:
			for i in 16:
				if bl[i] != "x":
					continue
				var note: int = br
				var r: float = rng.randf()
				if i % 8 != 0:
					if r < 0.25:
						note = br + 12
					elif r < 0.42:
						note = br + 7
					elif r < 0.52:
						note = br + 10
				ev.append(["bass_fk", note, float(bar * 16 + i), 1.5, 0.95 if i % 4 == 0 else 0.7, 0.0, 1])
		if float(sec["chords"]) > 0.0:
			for st in ms["stab"]:
				if rng.randf() < 0.85:
					for k in 3:
						ev.append(["clav", tones[(k + 1) % tones.size()] + 12, float(bar * 16 + int(st)), 1.2, 0.5, -0.2 + 0.2 * float(k), 2])
		# horn stabs on the B sections
		if float(sec["lead"]) > 0.6 and bar % 2 == 1:
			for hs in [6, 14]:
				for k in 3:
					ev.append(["horn", tones[k % tones.size()] + 12 + (12 if k == 2 else 0), float(bar * 16 + hs), 1.6, 0.7, 0.2 + 0.1 * float(k), 3])
	if float(sec["arp"]) > 0.0 and float(sec["lead"]) < 0.6:
		pass
	# short brass / synth riff over the first two bars of A2/A3
	if float(sec["lead"]) > 0.0 and float(sec["lead"]) <= 0.6:
		_place_motif(ev, ms["motif"], spec, root, 0, "horn", root + 36, 0.25, 0.6, 0)
		_place_motif(ev, ms["motif"], spec, root, 2, "horn", root + 36, 0.25, 0.6, int([0, 2][rng.randi() % 2]))


static func _compose_electro(spec: Dictionary, sec: Dictionary, prog: Array, rng: RandomNumberGenerator, ms: Dictionary, ev: Array, pi: int) -> void:
	var root: int = int(spec["root"])
	var riffs: Array = [[[0, 2], [4, 2], [8, 3], [12, 2]], [[0, 3], [3, 1], [8, 4], [14, 2]], [[2, 2], [6, 2], [10, 2], [14, 2]]]
	if not ms.has("motif") or rng.randf() < 0.4:
		ms["motif"] = _make_motif(rng, 0.9, riffs)
	for bar in PHRASE_BARS:
		var chord: Array = prog[bar]
		var tones: Array = _chord_notes(root + 12, chord)
		var br: int = root - 12 + int(chord[0])
		if float(sec["chords"]) > 0.0:
			ev.append(["pad", tones[0], float(bar * 16), 16.0, 0.6, 0.0, 2])
			ev[ev.size() - 1].append(tones)
		if float(sec["drums"]) > 0.0:
			var dv: float = float(sec["drums"])
			_drum_events(ev, "x...x...x...x...", "kick_el", bar, dv, 0.0)
			_drum_events(ev, "....x.......x...", "clap_sw", bar, dv * 0.9, 0.0)
			_drum_events(ev, "..x...x...x...x.", "hat_c_sw", bar, dv * 0.8, 0.25)
			_drum_events(ev, "x.xxx.xxx.xxx.xx", "hat_c_sw", bar, dv * 0.25, -0.3, 0, 0.5)
		if float(sec["bass"]) > 0.0:
			for i in 16:
				if i % 2 == 1 and not (i == 7 or i == 15):
					ev.append(["bass_el", br + (12 if i % 4 == 3 else 0), float(bar * 16 + i), 0.9, 0.8, 0.0, 1])
				elif i % 2 == 0:
					ev.append(["bass_el", br, float(bar * 16 + i), 0.9, 0.85, 0.0, 1])
		if float(sec["arp"]) > 0.0:
			var arp_tones: Array = _chord_notes(root + 24, chord) + _chord_notes(root + 36, chord)
			for i in range(0, 16, 1 if float(sec["arp"]) >= 0.9 else 2):
				ev.append(["arp_sw", arp_tones[(i * 2) % arp_tones.size()], float(bar * 16 + i), 1.3, 0.45, -0.5 if i % 2 == 0 else 0.5, 3])
	if float(sec["lead"]) > 0.0:
		_place_motif(ev, ms["motif"], spec, root, 0, "lead_sw", root + 36, 0.1, 0.65, 0)
		_place_motif(ev, ms["motif"], spec, root, 2, "lead_sw", root + 36, 0.1, 0.65, int([0, 1, 2][rng.randi() % 3]))


# =========================================================================================================
# Instruments
# =========================================================================================================
static func _hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


static func instrument(inst: String, midi: int, dur_s: float, extra: Array, seed_value: int) -> PackedFloat32Array:
	var f: float = _hz(float(midi))
	match inst:
		"kick_sw", "kick_el":
			var k := Synth.thump(0.38, 150.0, 46.0, 0.12 if inst == "kick_sw" else 0.1)
			k = Synth.add(k, Synth.noise_hit(0.012, 0.0025, 1500.0, 0.0, seed_value), 0.28)
			return Synth.soft_clip(k, 1.7)
		"kick_lo":
			return Synth.lowpass(Synth.soft_clip(Synth.thump(0.45, 105.0, 42.0, 0.17), 1.3), 1400.0)
		"kick_fk":
			var kf := Synth.thump(0.3, 165.0, 52.0, 0.085)
			return Synth.add(kf, Synth.noise_hit(0.01, 0.0025, 1800.0, 0.0, seed_value), 0.3)
		"snare_sw":
			var sn := Synth.noise_hit(0.3, 0.075, 900.0, 0.0, seed_value)
			sn = Synth.add(sn, Synth.thump(0.15, 230.0, 160.0, 0.05), 0.7)
			return Synth.reverb(sn, 0.4, 0.5, 0.18, SR, 0.2)
		"clap_sw":
			var cl := Synth.zeros(Synth.secs(0.45))
			for t in [0.0, 0.011, 0.023]:
				Synth.mix_into(cl, Synth.noise_hit(0.05, 0.012, 1000.0, 4500.0, seed_value + int(t * 1000.0)), int(float(t) * SR), 0.8)
			Synth.mix_into(cl, Synth.noise_hit(0.4, 0.09, 1100.0, 4000.0, seed_value + 7), int(0.03 * SR), 0.55)
			return Synth.reverb(cl, 0.5, 0.45, 0.35, SR, 0.3)
		"snare_lo":
			var sl := Synth.noise_hit(0.25, 0.07, 450.0, 5200.0, seed_value)
			sl = Synth.add(sl, Synth.thump(0.15, 190.0, 140.0, 0.05), 0.8)
			return Synth.crush(Synth.lowpass(sl, 5200.0), 10, 2)
		"snare_fk":
			var sf := Synth.noise_hit(0.16, 0.05, 1200.0, 9000.0, seed_value)
			return Synth.add(sf, Synth.thump(0.1, 250.0, 170.0, 0.035), 0.8)
		"hat_c_sw":
			return Synth.noise_hit(0.07, 0.017, 7500.0, 0.0, seed_value)
		"hat_o_sw":
			return Synth.noise_hit(0.32, 0.11, 6800.0, 0.0, seed_value)
		"hat_lo":
			return Synth.noise_hit(0.08, 0.02, 6000.0, 9500.0, seed_value)
		"hat_fk":
			return Synth.noise_hit(0.07, 0.016, 8000.0, 0.0, seed_value)
		"clave":
			return Synth.modal(Synth.secs(0.15), [[2450.0, 0.03, 1.0], [3300.0, 0.02, 0.5]])
		"cowbell":
			var cb := Synth.add(Synth.osc(Synth.Wave.SQUARE, Synth.secs(0.3), 587.0), Synth.osc(Synth.Wave.SQUARE, Synth.secs(0.3), 845.0), 1.0)
			cb = Synth.band(cb, 700.0, 4200.0)
			return Synth.mul(cb, Synth.env_decay(cb.size(), 0.09))
		"conga_hi":
			var ch := Synth.thump(0.25, 380.0, 290.0, 0.075)
			return Synth.add(ch, Synth.noise_hit(0.03, 0.006, 1500.0, 5000.0, seed_value), 0.25)
		"conga_lo":
			var cg := Synth.thump(0.3, 260.0, 190.0, 0.1)
			return Synth.add(cg, Synth.noise_hit(0.03, 0.006, 900.0, 4000.0, seed_value), 0.25)
		"shaker":
			var sk := Synth.band(Synth.noise(Synth.secs(0.07), seed_value), 5200.0, 10500.0)
			return Synth.mul(sk, Synth.env_swell(sk.size(), 0.35, 1.0))
		"bass_sw", "bass_el":
			var n := Synth.secs(maxf(dur_s, 0.1))
			var b := Synth.osc(Synth.Wave.SAW, n, f)
			b = Synth.add(b, Synth.osc(Synth.Wave.SAW, n, f * 1.006), 0.8)
			var low := Synth.lowpass(b, 520.0 if inst == "bass_sw" else 700.0, 1.2)
			var bright := Synth.mul(Synth.lowpass(b, 2600.0, 0.9), Synth.env_decay(n, 0.07, SR, 0.002))
			var out := Synth.add(low, bright, 0.7)
			out = Synth.add(out, Synth.osc(Synth.Wave.SINE, n, f * 0.5), 0.6)
			return Synth.mul(out, Synth.env_adsr(n, 0.004, 0.06, 0.75, 0.04))
		"bass_lo":
			var nl := Synth.secs(maxf(dur_s, 0.15))
			var bl := Synth.osc(Synth.Wave.SINE, nl, f)
			bl = Synth.add(bl, Synth.osc(Synth.Wave.SINE, nl, f * 2.0), 0.18)
			bl = Synth.soft_clip(bl, 1.5)
			return Synth.mul(bl, Synth.env_adsr(nl, 0.012, 0.1, 0.7, 0.12))
		"bass_fk":
			var nf := Synth.secs(maxf(dur_s, 0.08))
			var bf := Synth.osc(Synth.Wave.SQUARE, nf, f, SR, 0.0, 0.32)
			bf = Synth.add(bf, Synth.osc(Synth.Wave.SAW, nf, f), 0.5)
			bf = Synth.lowpass(bf, 900.0, 1.4)
			bf = Synth.mul(bf, Synth.env_decay(nf, 0.16, SR, 0.002))
			return Synth.add(bf, Synth.noise_hit(0.012, 0.003, 800.0, 3200.0, seed_value), 0.22)
		"pad":
			var np := Synth.secs(maxf(dur_s, 0.5))
			var pad := Synth.zeros(np)
			var tones: Array = extra
			for t in tones:
				var ft: float = _hz(float(t))
				for dt in [0.995, 1.0, 1.005]:
					pad = Synth.add(pad, Synth.osc(Synth.Wave.SAW, np, ft * float(dt)), 0.1)
			pad = Synth.lowpass(pad, 1700.0, 0.9)
			return Synth.mul(pad, Synth.env_adsr(np, 0.35, 0.3, 0.85, 0.5))
		"arp_sw":
			var na := Synth.secs(maxf(dur_s, 0.1))
			var a := Synth.osc(Synth.Wave.SAW, na, f)
			a = Synth.add(a, Synth.osc(Synth.Wave.SQUARE, na, f * 1.004, SR, 0.0, 0.4), 0.6)
			var alow := Synth.lowpass(a, 1100.0, 1.0)
			var abri := Synth.mul(Synth.lowpass(a, 4200.0, 0.8), Synth.env_decay(na, 0.06, SR, 0.002))
			return Synth.mul(Synth.add(alow, abri, 0.9), Synth.env_decay(na, 0.14, SR, 0.002))
		"lead_sw":
			var nlead := Synth.secs(maxf(dur_s, 0.15))
			var vib := Synth.lfo(nlead, 5.5, 0.0, 0.0045)
			var fb := PackedFloat32Array()
			fb.resize(nlead)
			for i in nlead:
				var onset: float = clampf(float(i) / float(SR) / 0.25 - 0.4, 0.0, 1.0)
				fb[i] = f * (1.0 + vib[i] * onset)
			var l := Synth.osc_f(Synth.Wave.SAW, fb)
			l = Synth.add(l, Synth.osc_f(Synth.Wave.SAW, Synth.scale(fb, 1.007)), 0.7)
			l = Synth.add(l, Synth.osc_f(Synth.Wave.TRI, Synth.scale(fb, 0.5)), 0.5)
			l = Synth.lowpass(l, 3000.0, 1.0)
			return Synth.mul(l, Synth.env_adsr(nlead, 0.02, 0.12, 0.7, 0.18))
		"epiano":
			var ne := Synth.secs(maxf(dur_s, 0.3))
			var idx := Synth.add(Synth.scale(Synth.env_decay(ne, 0.28, SR, 0.001), 1.7), Synth.filled(ne, 0.12))
			var e := Synth.fm(ne, f, f, 1.0, SR, idx)
			e = Synth.add(e, Synth.ring(ne, f * 7.0, 0.05, SR, 0.5), 0.12)
			e = Synth.mul(e, Synth.env_decay(ne, 0.55 + dur_s * 0.12, SR, 0.003))
			e = Synth.mul(e, Synth.lfo(ne, 4.6, 0.92, 0.08))
			return Synth.lowpass(e, 3800.0, 0.7)
		"bell_lo":
			var nb := Synth.secs(0.9)
			var bi := Synth.scale(Synth.env_decay(nb, 0.25), 2.0)
			var bell := Synth.fm(nb, f, f * 3.5, 1.0, SR, bi)
			bell = Synth.mul(bell, Synth.env_decay(nb, 0.38, SR, 0.002))
			return Synth.lowpass(bell, 5000.0)
		"clav":
			var nc := Synth.secs(0.2)
			var c := Synth.osc(Synth.Wave.SQUARE, nc, f, SR, 0.0, 0.14)
			c = Synth.band(c, 450.0, 5200.0)
			return Synth.mul(c, Synth.env_decay(nc, 0.07, SR, 0.001))
		"horn":
			var nh := Synth.secs(maxf(dur_s, 0.14))
			var fh := Synth.expramp(nh, f * 0.98, f)
			var h := Synth.osc_f(Synth.Wave.SAW, fh)
			h = Synth.add(h, Synth.osc_f(Synth.Wave.SAW, Synth.scale(fh, 1.006)), 0.8)
			h = Synth.add(h, Synth.osc_f(Synth.Wave.SAW, Synth.scale(fh, 0.994)), 0.8)
			h = Synth.lowpass(h, 2600.0, 0.9)
			return Synth.mul(h, Synth.env_adsr(nh, 0.015, 0.06, 0.65, 0.07))
	return Synth.zeros(32)


# =========================================================================================================
# Rendering
# =========================================================================================================
const STEM_GAIN := {
	"synthwave": [0.9, 0.85, 0.6, 0.5, 0.5],
	"electro": [0.95, 0.9, 0.45, 0.5, 0.5],
	"lofi": [0.8, 0.8, 0.75, 0.55, 0.5],
	"funk": [0.8, 0.9, 0.55, 0.6, 0.7],
}


## Renders one phrase. Returns {"frames": PackedVector2Array (exactly phrase length), "carry": PackedVector2Array tail}.
static func render(spec: Dictionary, events: Array, carry_in: PackedVector2Array, cache: Dictionary, seed_value: int) -> Dictionary:
	var step_s: float = step_seconds(spec)
	var swing: float = float(spec["swing"])
	var grid: int = int(spec.get("swing_grid", 2))
	var n_phrase: int = phrase_samples(spec)
	var tail_n: int = int(TAIL_S * SR)
	var total: int = n_phrase + tail_n
	var style: String = String(spec["style"])
	var stems: Array = []
	for i in 5:
		var b := PackedFloat32Array()
		b.resize(total)
		stems.append(b)
	var stereo: Array = []
	for i in 5:
		var l := PackedFloat32Array()
		l.resize(total)
		var r := PackedFloat32Array()
		r.resize(total)
		stereo.append([l, r])
	var kick_samples: Array = []
	var rng_seed := seed_value
	for e in events:
		var inst: String = e[0]
		var midi: int = e[1]
		var step: float = e[2]
		var dur_steps: float = e[3]
		var vel: float = e[4]
		var pan: float = e[5]
		var stem: int = e[6]
		if inst == "vinyl":
			continue
		# swing: delay every odd 8th-note-grid 16th... (steps 2,6,10,14 odd eighths) by swing * step
		var st: float = step
		var si: int = int(floor(st))
		if swing > 0.0 and si == int(st) and si % grid == grid / 2:
			st += swing * 0.667 * (float(grid) / 4.0)
		var t_samples: int = int(st * step_s * float(SR))
		var dur_s: float = dur_steps * step_s
		var key: String = "%s|%d|%d" % [inst, midi, int(dur_steps * 4.0)]
		var extra: Array = []
		if e.size() > 7:
			extra = e[7]
			key += "|" + str(extra)
		var drum: bool = midi < 0
		if drum:
			# percussion hits get a few noise variants so repeated hits do not machine-gun
			key = "%s|v%d" % [inst, int(floor(step)) % 3]
		var buf: PackedFloat32Array
		if cache.has(key):
			buf = cache[key]
		else:
			rng_seed += 17
			buf = instrument(inst, midi, dur_s, extra, rng_seed)
			if cache.size() > 220:
				cache.clear()
			cache[key] = buf
		# stereo placement with equal-power pan
		var ang: float = (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
		var gl: float = cos(ang) * vel
		var gr: float = sin(ang) * vel
		var pair: Array = stereo[stem]
		Synth.mix_into(pair[0], buf, t_samples, gl)
		Synth.mix_into(pair[1], buf, t_samples, gr)
		if inst.begins_with("kick"):
			kick_samples.append(t_samples)
	# ---- sidechain pump (synthwave / electro): bass, chords and lead duck on every kick
	if style == "synthwave" or style == "electro":
		var duck := PackedFloat32Array()
		duck.resize(total)
		duck.fill(1.0)
		var rel: int = int(0.22 * SR)
		for ks in kick_samples:
			for i in rel:
				var idx: int = int(ks) + i
				if idx >= total:
					break
				var g: float = 1.0 - 0.55 * exp(-float(i) / (0.07 * float(SR)))
				if g < duck[idx]:
					duck[idx] = g
		for s in [1, 2, 3]:
			var pair2: Array = stereo[s]
			for ch in 2:
				var bb: PackedFloat32Array = pair2[ch]
				for i in total:
					bb[i] *= duck[i]
	# ---- vinyl crackle bed for lo-fi
	var gains: Array = STEM_GAIN[style]
	var left := PackedFloat32Array()
	left.resize(total)
	var right := PackedFloat32Array()
	right.resize(total)
	for s in 5:
		var pl3: PackedFloat32Array = stereo[s][0]
		var pr3: PackedFloat32Array = stereo[s][1]
		var gs: float = float(gains[s])
		for i in total:
			left[i] += pl3[i] * gs
			right[i] += pr3[i] * gs
	if style == "lofi":
		var cr := Synth.band(Synth.crackle(total, 16.0, SR, seed_value + 3, 0.0018, 0.9), 1500.0, 9500.0)
		var hiss := Synth.scale(Synth.band(Synth.noise(total, seed_value + 9), 3000.0, 9000.0), 0.012)
		for i in total:
			left[i] += cr[i] * 0.07 + hiss[i]
			right[i] += cr[i] * 0.06 + hiss[i] * 0.9
	# ---- delay on lead/arp stem (dotted eighth feel) + reverb send
	var send := PackedFloat32Array()
	send.resize(total)
	var ll: PackedFloat32Array = stereo[3][0]
	var lr: PackedFloat32Array = stereo[3][1]
	var cl: PackedFloat32Array = stereo[2][0]
	var cr_: PackedFloat32Array = stereo[2][1]
	var dl: PackedFloat32Array = stereo[0][0]
	var dr: PackedFloat32Array = stereo[0][1]
	var g_lead: float = 0.55 * float(gains[3])
	var g_chord: float = 0.4 * float(gains[2])
	var g_drum: float = 0.12 * float(gains[0])
	for i in total:
		send[i] = (ll[i] + lr[i]) * g_lead + (cl[i] + cr_[i]) * g_chord + (dl[i] + dr[i]) * g_drum
	var dly_t: float = step_s * 3.0
	var echo := Synth.delay(send.slice(0, n_phrase), dly_t, 0.36, 1.0, SR, TAIL_S, 0.45)
	# echo already contains the dry copy; keep only the repeats by subtracting it
	var echo_only := PackedFloat32Array()
	echo_only.resize(total)
	for i in mini(total, echo.size()):
		echo_only[i] = echo[i] - (send[i] if i < n_phrase else 0.0)
	var delay_amount: float = 0.0
	var rev_amount: float = 0.0
	match style:
		"synthwave":
			delay_amount = 0.5
			rev_amount = 0.3
		"electro":
			delay_amount = 0.38
			rev_amount = 0.22
		"lofi":
			delay_amount = 0.22
			rev_amount = 0.33
		_:
			delay_amount = 0.16
			rev_amount = 0.16
	var rev_in := Synth.add(send, echo_only, 0.5)
	var wet := Synth.reverb(rev_in.slice(0, total), 0.62, 0.5, 1.0, SR, 0.0)
	var wet_len: int = mini(wet.size(), total)
	var haas: int = int(0.0165 * SR)
	var da: float = delay_amount * 0.9
	var db_: float = delay_amount * 0.6
	for i in total:
		var w: float = 0.0
		if i < wet_len:
			w = wet[i] - rev_in[i]   # reverb() adds the dry signal, so subtract it again to get the wet part only
		var wr: float = 0.0
		if i >= haas and i - haas < wet_len:
			wr = wet[i - haas] - rev_in[i - haas]
		left[i] += echo_only[i] * da + w * rev_amount
		right[i] += echo_only[i] * db_ + wr * rev_amount
	# ---- master: gentle tone shaping, soft clip, fixed headroom
	if style == "lofi":
		left = Synth.lowpass(left, 6200.0, 0.7)
		right = Synth.lowpass(right, 6200.0, 0.7)
	elif style == "funk":
		left = Synth.highpass(left, 40.0)
		right = Synth.highpass(right, 40.0)
	var out := PackedVector2Array()
	out.resize(n_phrase)
	var carry := PackedVector2Array()
	carry.resize(tail_n)
	var master: float = 0.62 * 1.25
	var ncarry: int = mini(carry_in.size(), n_phrase)
	for i in n_phrase:
		var l2: float = tanh(left[i] * master) * 0.82
		var r2: float = tanh(right[i] * master) * 0.82
		if i < ncarry:
			var ci: Vector2 = carry_in[i]
			l2 += ci.x
			r2 += ci.y
		out[i] = Vector2(l2, r2)
	for i in tail_n:
		carry[i] = Vector2(tanh(left[n_phrase + i] * master) * 0.82, tanh(right[n_phrase + i] * master) * 0.82)
	return {"frames": out, "carry": carry}


## Short station ident (1.6 s): the jingle notes as a bell/synth arpeggio, mixed on top of the first phrase.
static func jingle(spec: Dictionary) -> PackedVector2Array:
	var notes: Array = spec["jingle"]
	var n := Synth.secs(2.0)
	var buf := Synth.zeros(n)
	var style: String = String(spec["style"])
	for i in notes.size():
		var f: float = _hz(float(notes[i]))
		var nn := Synth.secs(1.1)
		var tone: PackedFloat32Array
		if style == "lofi":
			tone = instrument("bell_lo", int(notes[i]), 1.0, [], 11 + i)
		elif style == "funk":
			tone = instrument("horn", int(notes[i]), 0.25, [], 11 + i)
		else:
			var sq := Synth.osc(Synth.Wave.SAW, nn, f)
			sq = Synth.add(sq, Synth.osc(Synth.Wave.SAW, nn, f * 1.005), 0.8)
			sq = Synth.lowpass(sq, 3600.0, 1.0)
			tone = Synth.mul(sq, Synth.env_decay(nn, 0.28, SR, 0.004))
		Synth.mix_into(buf, tone, int(float(i) * 0.14 * SR), 0.5)
	buf = Synth.reverb(buf, 0.7, 0.4, 0.35, SR, 0.5)
	var out := PackedVector2Array()
	out.resize(buf.size())
	for i in buf.size():
		var v: float = tanh(buf[i] * 1.2)
		out[i] = Vector2(v, v)
	return out
