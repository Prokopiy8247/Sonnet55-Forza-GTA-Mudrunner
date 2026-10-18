extends RefCounted
## SoundBank - registry + renderer for every procedurally synthesised one-shot / loop sound.
##
## Each bank_*.gd file declares IDS (id -> metadata) and build(id, variant, rng) -> {"buf", "sr", "loop", ...}.
## This class merges the metadata with the category defaults, renders deterministic buffers (seeded per id+variant),
## post-processes them (NaN guard, DC block, peak normalise, de-click) and converts them to AudioStreamWAV.
##
## No autoload / scene-tree access in here: all of it is safe to run on WorkerThreadPool threads and from the
## headless bake tool. Call init_registry() once on the main thread before using it from threads.

const Synth = preload("res://gta/code/audio/synth.gd")
const BankUi = preload("res://gta/code/audio/bank_ui.gd")
const BankWeapons = preload("res://gta/code/audio/bank_weapons.gd")
const BankCharacter = preload("res://gta/code/audio/bank_character.gd")
const BankVehicle = preload("res://gta/code/audio/bank_vehicle.gd")
const BankWorld = preload("res://gta/code/audio/bank_world.gd")
const BankEngine = preload("res://gta/code/audio/bank_engine.gd")

## Bump when a recipe changes so stale baked files are ignored (the source fingerprint also guards this).
const VERSION := 1
const BAKE_DIR := "res://gta/generated/audio/"

## Category defaults: bus, 3D unit_size (m of full-volume radius), polyphony per id / per category, priority 1..10,
## random pitch (+-fraction) and volume (+-dB) variation, minimum seconds between two starts of the same id, "range" = natural
## audible distance (m) used when a caller passes the default max_distance.
const CATS := {
	&"ui": {"bus": "UI", "range": 0.0, "unit": 10.0, "poly": 2, "cat_poly": 6, "prio": 10, "pvar": 0.0, "vvar": 0.0, "gap": 0.0},
	&"weapon": {"bus": "SFX", "range": 170.0, "unit": 16.0, "poly": 4, "cat_poly": 14, "prio": 7, "pvar": 0.025, "vvar": 1.0, "gap": 0.0},
	&"weapon_mech": {"bus": "SFX", "range": 26.0, "unit": 6.0, "poly": 3, "cat_poly": 6, "prio": 5, "pvar": 0.05, "vvar": 1.0, "gap": 0.04},
	&"melee": {"bus": "SFX", "range": 32.0, "unit": 6.0, "poly": 3, "cat_poly": 6, "prio": 5, "pvar": 0.06, "vvar": 1.0, "gap": 0.03},
	&"impact": {"bus": "SFX", "range": 48.0, "unit": 6.0, "poly": 4, "cat_poly": 10, "prio": 3, "pvar": 0.07, "vvar": 1.5, "gap": 0.02},
	&"explosion": {"bus": "SFX", "range": 420.0, "unit": 45.0, "poly": 3, "cat_poly": 5, "prio": 10, "pvar": 0.04, "vvar": 0.5, "gap": 0.0},
	&"step": {"bus": "SFX", "range": 28.0, "unit": 3.5, "poly": 3, "cat_poly": 10, "prio": 1, "pvar": 0.07, "vvar": 2.0, "gap": 0.07},
	&"foley": {"bus": "SFX", "range": 45.0, "unit": 5.0, "poly": 3, "cat_poly": 8, "prio": 3, "pvar": 0.05, "vvar": 1.0, "gap": 0.03},
	&"voice": {"bus": "Voice", "range": 55.0, "unit": 7.0, "poly": 3, "cat_poly": 8, "prio": 6, "pvar": 0.05, "vvar": 1.0, "gap": 0.0},
	&"vehicle": {"bus": "SFX", "range": 95.0, "unit": 12.0, "poly": 4, "cat_poly": 10, "prio": 5, "pvar": 0.04, "vvar": 1.0, "gap": 0.0},
	&"horn": {"bus": "SFX", "range": 150.0, "unit": 22.0, "poly": 3, "cat_poly": 6, "prio": 6, "pvar": 0.0, "vvar": 0.0, "gap": 0.0},
	&"siren": {"bus": "SFX", "range": 260.0, "unit": 40.0, "poly": 4, "cat_poly": 6, "prio": 6, "pvar": 0.0, "vvar": 0.0, "gap": 0.0},
	&"engine_fx": {"bus": "Engine", "range": 75.0, "unit": 14.0, "poly": 3, "cat_poly": 8, "prio": 4, "pvar": 0.05, "vvar": 1.0, "gap": 0.05},
	&"ambient_shot": {"bus": "Ambience", "range": 140.0, "unit": 35.0, "poly": 2, "cat_poly": 6, "prio": 2, "pvar": 0.08, "vvar": 1.5, "gap": 0.0},
	&"amb_loop": {"bus": "Ambience", "range": 100.0, "unit": 20.0, "poly": 1, "cat_poly": 12, "prio": 2, "pvar": 0.0, "vvar": 0.0, "gap": 0.0},
}

static var _meta: Dictionary = {}     # id -> merged metadata
static var _owner: Dictionary = {}    # id -> bank script
static var _ids: Array[StringName] = []
static var _fingerprint: String = ""
static var _ready_flag := false


static func banks() -> Array:
	return [BankUi, BankWeapons, BankCharacter, BankVehicle, BankWorld, BankEngine]


## Idempotent; builds the id -> metadata table. Call from the main thread before threads use the bank.
static func init_registry() -> void:
	if _ready_flag:
		return
	for bank in banks():
		var table: Dictionary = bank.IDS
		for id in table:
			var m: Dictionary = (table[id] as Dictionary).duplicate()
			var cat: StringName = m.get("cat", &"vehicle")
			var d: Dictionary = CATS.get(cat, CATS[&"vehicle"])
			for k in d:
				if not m.has(k):
					m[k] = d[k]
			if not m.has("var"):
				m["var"] = 1
			if not m.has("peak"):
				m["peak"] = 0.85
			m["cat"] = cat
			_meta[id] = m
			_owner[id] = bank
			_ids.append(id)
	fingerprint()   # compute once on the calling (main) thread so worker threads do not all re-read the sources
	_ready_flag = true


static func ids() -> Array[StringName]:
	init_registry()
	return _ids


static func has(id: StringName) -> bool:
	init_registry()
	return _meta.has(id)


static func meta(id: StringName) -> Dictionary:
	init_registry()
	return _meta.get(id, {})


static func variant_count(id: StringName) -> int:
	init_registry()
	return int(_meta.get(id, {}).get("var", 1))


## Hash of the recipe sources: baked files carry it in resource_name and are ignored when it differs (stale bake).
## Returns "" when the sources are not readable (exported project) - then any baked file is trusted.
static func fingerprint() -> String:
	if _fingerprint != "":
		return _fingerprint
	var parts: PackedStringArray = []
	for p in ["synth", "sound_bank", "bank_ui", "bank_weapons", "bank_character", "bank_vehicle", "bank_world", "bank_engine"]:
		var path := "res://gta/code/audio/%s.gd" % p
		if not FileAccess.file_exists(path):
			continue
		var txt := FileAccess.get_file_as_string(path).replace("\r", "")
		if txt == "":
			continue
		parts.append(txt.md5_text().substr(0, 6))
	_fingerprint = ("v%d-" % VERSION) + "".join(parts) if parts.size() == 8 else ""
	return _fingerprint


static func bake_path(id: StringName, v: int) -> String:
	return BAKE_DIR + String(id) + ("_%d" % v) + ".res"


## Raw synthesis result: {"buf": PackedFloat32Array (post-processed), "sr": int, "loop": bool, "loop_begin": int,
## "loop_end": int}. Deterministic for (id, variant). Empty dictionary for unknown ids.
static func render(id: StringName, v: int = 0) -> Dictionary:
	init_registry()
	var bank = _owner.get(id)
	if bank == null:
		return {}
	var m: Dictionary = _meta[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(String(id).hash()) * 31 + v * 7919 + 1013
	var r: Dictionary = bank.build(id, v, rng)
	if r.is_empty() or not r.has("buf"):
		return {}
	var looped: bool = r.get("loop", false)
	var buf: PackedFloat32Array = r["buf"]
	buf = Synth.sanitize(buf, not looped)
	if r.has("rms"):
		# loops that must have matched loudness across layers: scale to a target RMS then soft-limit
		var cur := Synth.rms(buf)
		if cur > 1e-9:
			buf = Synth.scale(buf, float(r["rms"]) / cur)
		buf = Synth.limit(buf, 0.8)
	else:
		buf = Synth.normalize(buf, float(m["peak"]))
	var sr: int = r.get("sr", Synth.SR)
	if not looped:
		buf = Synth.fade_in(buf, 0.0008, sr)
		buf = Synth.fade_out(buf, 0.006, sr)
	else:
		# loops: remove the constant DC offset of the loop region (pulse waves / rectified noise); a constant keeps the seam intact
		var lb: int = int(r.get("loop_begin", 0))
		var le: int = int(r.get("loop_end", buf.size()))
		var mean: float = 0.0
		for i in range(lb, le):
			mean += buf[i]
		mean /= float(maxi(le - lb, 1))
		for i in buf.size():
			buf[i] -= mean
		if lb > 0:
			buf = Synth.fade_in(buf, 0.0008, sr)
	r["buf"] = buf
	r["sr"] = sr
	r["loop"] = looped
	r["loop_begin"] = int(r.get("loop_begin", 0))
	r["loop_end"] = int(r.get("loop_end", buf.size()))
	return r


## Synthesises one variant straight to an AudioStreamWAV (no cache involved).
static func generate(id: StringName, v: int = 0) -> AudioStreamWAV:
	var r := render(id, v)
	if r.is_empty():
		return null
	var w := Synth.to_wav(r["buf"], r["sr"], r["loop"], r["loop_begin"], r["loop_end"])
	w.resource_name = String(id) if v == 0 else "%s_%d" % [id, v]
	return w


## Tries the baked file first (fast), falls back to synthesis. Thread-safe.
static func load_or_generate(id: StringName, v: int = 0, use_baked: bool = true) -> AudioStreamWAV:
	if use_baked:
		var p := bake_path(id, v)
		if ResourceLoader.exists(p):
			var res = ResourceLoader.load(p, "AudioStreamWAV", ResourceLoader.CACHE_MODE_IGNORE)
			if res is AudioStreamWAV:
				var fp := fingerprint()
				if fp == "" or (res as AudioStreamWAV).get_meta("fp", "") == fp:
					return res
	return generate(id, v)


## Writes the baked .res for one variant. Returns OK or an error code.
static func bake(id: StringName, v: int = 0) -> int:
	var w := generate(id, v)
	if w == null:
		return ERR_DOES_NOT_EXIST
	w.set_meta("fp", fingerprint())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
	return ResourceSaver.save(w, bake_path(id, v), ResourceSaver.FLAG_COMPRESS)
