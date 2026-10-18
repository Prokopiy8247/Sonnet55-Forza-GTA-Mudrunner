class_name ActivityRange
extends ActivityBase
## The shooting range at the `shooting_range` landmark (Blender lanes Lane_1..5 / Target_1..5). 3 timed rounds of pop-up targets (hostile
## silhouettes, bullseye plates, civilian no-shoot silhouettes), real bullets through the WeaponController hitscan, head / body / ring scoring,
## accuracy and time bonus, medals, small cash and Shooting skill use. Weapons are loaned (pistol / SMG / rifle / shotgun or your own
## firearm with unlimited range ammo) and restored afterwards; explosives are impossible because only the loan is in the inventory.
## No police response: WantedSystem ignores gunshots near the range and Game meta `gun_range_zone` is true while the player is there.

const ROWS_ON_LANE := [15.0, 25.0]          ## stands centred on the lanes
const ROWS_OFFSET := [10.0, 20.0]           ## stands between the lanes (4 each); the 20 m row holds the bullseye plates
const FAR_ROW := 25.0
const ROUNDS := [
	{"name": "ROUND 1 - WARM-UP", "short": "Warm-up", "waves": 8, "per": [1, 1], "dur": 3.4, "gap": 0.55, "civ": 0, "rows": [10.0, 15.0, 20.0], "slide": 0.0},
	{"name": "ROUND 2 - QUALIFIER", "short": "Qualifier", "waves": 10, "per": [1, 2], "dur": 2.6, "gap": 0.45, "civ": 3, "rows": [10.0, 15.0, 20.0, 25.0], "slide": 0.0},
	{"name": "ROUND 3 - MARKSMAN", "short": "Marksman", "waves": 12, "per": [2, 3], "dur": 2.15, "gap": 0.38, "civ": 5, "rows": [15.0, 20.0, 25.0], "slide": 1.3},
]
const SETS := {
	"pistol": {"name": "Pistol", "desc": "Precise handgun, 15-round magazines. The classic.", "weapon": &"pistol", "mult": 1.0},
	"smg": {"name": "Submachine gun", "desc": "Fast and forgiving - watch the recoil.", "weapon": &"smg", "mult": 0.95},
	"rifle": {"name": "Assault rifle", "desc": "Accurate at every distance, steady rate of fire.", "weapon": &"rifle_assault", "mult": 0.95},
	"shotgun": {"name": "Pump shotgun", "desc": "One pellet pattern per shot - the best pellet scores.", "weapon": &"shotgun_pump", "mult": 0.88},
}
const MEDAL_SCORES := [3700.0, 2700.0, 1500.0]      ## gold, silver, bronze (x set multiplier)
const CASH := [50, 110, 190, 300]                   ## none, bronze, silver, gold
const CIV_PENALTY := 150
const TIME_BONUS_PER_S := 9.0
const ZONE_RADIUS := 60.0
const FIRE_FORWARD := 1.25                   ## m in front of the Lane_n empty (the counter front is at ~0.7 m)

enum Phase { INTRO, GAP, WAVE, ROUND_END, DONE }

var stands: Array[ActivityTarget] = []
var lane_xf: Array[Transform3D] = []         ## index 1..5 (0 unused); -Z = down range
var target_xf: Array[Transform3D] = []
var down_dir := Vector3.RIGHT
var lat_dir := Vector3.BACK
var anchors_found := false
var set_id := "pistol"
var phase: int = Phase.INTRO
var round_i := 0
var wave_i := 0
var score_targets := 0
var penalties := 0
var time_bonus := 0
var hits := 0
var misses := 0
var civ_hits := 0
var heads := 0
var bulls := 0
var shots := 0
var run_time := 0.0
var rounds_done := 0
var per_round: Array = []                    ## [{hits, targets, bonus}]
var result_preview: Dictionary = {}

var _wave_targets: Array[ActivityTarget] = []
var _resolved: Dictionary = {}               ## ActivityTarget -> true
var _wave_plan: Array = []
var _wave_t := 0.0
var _phase_t := 0.0
var _round_t := 0.0
var _round_hits := 0
var _round_targets := 0
var _saved_weapons: Dictionary = {}
var _loaned := false
var _rng := RandomNumberGenerator.new()
var _zone_t := 0.0
var _announced_far := false


func _init() -> void:
	id = &"shooting_range"
	title = "Shooting Range"
	kind = Kind.RANGE
	accent = Color("#ffb347")
	location_id = &"shooting_range"
	countdown_seconds = 3
	description = "Three timed rounds of pop-up targets. Hit the silhouettes - head and bullseye score most - and keep your fire off the cyan civilians. Weapons are provided; the officer keeps the range safe, nobody calls the police here."
	menu_hint = "You will be moved to lane 3. Hold E at any time to quit."
	interact_range = 3.4
	marker_radius = 1.5
	for sid in ["pistol", "smg", "rifle", "shotgun"]:
		var s: Dictionary = SETS[sid]
		options.append({"id": sid, "name": s["name"], "desc": s["desc"]})
	options.append({"id": "own", "name": "Your own weapon", "desc": "Uses your equipped firearm (range ammo, yours is untouched).", "enabled": true})


func prompt_text(_player: Node) -> String:
	return "Shooting Range"


func setup_activity() -> void:
	var loc: Dictionary = WorldLayout.get_location(&"shooting_range")
	if not loc.is_empty():
		point_pos = loc["pos"]
		point_yaw = float(loc.get("yaw", 0.0))
	_find_lanes()
	_build_stands()
	set_physics_process(true)


func _physics_process(dt: float) -> void:
	# Game meta read by anybody who wants to know that gunfire here is sanctioned
	_zone_t -= dt
	if _zone_t <= 0.0:
		_zone_t = 0.3
		var p = player()
		var inside := false
		if p != null and lane_xf.size() > 3:
			inside = Util.dist_xz(p.global_position, lane_xf[3].origin) < ZONE_RADIUS
		if inside != bool(Game.get_meta(&"gun_range_zone", false)):
			Game.set_meta(&"gun_range_zone", inside)


# ================================================================================================= world data
func _find_lanes() -> void:
	lane_xf.clear()
	target_xf.clear()
	for i in 6:
		lane_xf.append(Transform3D.IDENTITY)
		target_xf.append(Transform3D.IDENTITY)
	var found := 0
	for a in get_tree().get_nodes_in_group("landmark_anchor"):
		if not (a is Node3D) or str(a.get_meta("landmark", "")) != "shooting_range":
			continue
		var nm := String(a.name)
		if nm.begins_with("Lane_") or nm.begins_with("Target_"):
			var n := int(nm.substr(nm.find("_") + 1))
			if n >= 1 and n <= 5:
				if nm.begins_with("Lane_"):
					lane_xf[n] = (a as Node3D).global_transform
				else:
					target_xf[n] = (a as Node3D).global_transform
				found += 1
	anchors_found = found >= 10
	if not anchors_found:
		push_warning("[Activities] shooting range: Lane/Target anchors not found - using offsets from the location (FALLBACK)")
		var loc: Dictionary = WorldLayout.get_location(&"shooting_range")
		var lp: Vector3 = loc.get("pos", Vector3(254.5, 0.16, 3.5))
		var out := Util.yaw_to_dir(float(loc.get("yaw", PI * 0.5)))
		var dn := -out
		var perp := Vector3(-dn.z, 0.0, dn.x)
		for n in range(1, 6):
			var lp_n := lp + dn * 7.2 + perp * (-0.725 + 3.2 * float(5 - n))
			var basis_ := Basis.looking_at(dn, Vector3.UP)
			lane_xf[n] = Transform3D(basis_, Vector3(lp_n.x, 0.1, lp_n.z))
			var tb := Basis.looking_at(-dn, Vector3.UP)
			target_xf[n] = Transform3D(tb, Vector3(lp_n.x, 0.05, lp_n.z) + dn * 25.0)
	down_dir = Util.flat(-lane_xf[3].basis.z).normalized()
	lat_dir = Util.flat(lane_xf[5].origin - lane_xf[1].origin).normalized()


## World position of a stand at lane coordinate c (1..5, fractions allowed) and distance d from the firing line.
func stand_xf(c: float, d: float) -> Transform3D:
	var lo := clampi(int(floor(c)), 1, 4)
	var f := c - float(lo)
	var base1 := target_xf[lo]
	var base2 := target_xf[lo + 1]
	var pos := base1.origin.lerp(base2.origin, f) - down_dir * (FAR_ROW - d)
	var xf := Transform3D(base1.basis, pos)
	return xf


func _build_stands() -> void:
	for s in stands:
		if is_instance_valid(s) and is_instance_valid(s.root):
			s.root.queue_free()
	stands.clear()
	var parent: Node3D = null
	var gw = Game.world
	if gw != null and is_instance_valid(gw) and gw.has_method("get_sector_parent"):
		parent = gw.get_sector_parent(target_xf[3].origin)
	if parent == null:
		parent = self.get_parent() as Node3D if get_parent() is Node3D else null
	if parent == null:
		parent = Node3D.new()
		parent.name = "RangeTargets"
		add_child(parent)
	for d in ROWS_ON_LANE:
		for c in range(1, 6):
			_add_stand(parent, float(c), float(d))
	for d in ROWS_OFFSET:
		for c in range(1, 5):
			_add_stand(parent, float(c) + 0.5, float(d))


func _add_stand(parent: Node3D, c: float, d: float) -> void:
	var xf := stand_xf(c, d)
	var round_row := is_equal_approx(d, 20.0)
	var t := ActivityTarget.create(&"round" if round_row else &"silhouette", xf, parent)
	t.column = int(round(c * 2.0))
	t.row_m = d
	t.scored.connect(_on_scored)
	stands.append(t)


# ================================================================================================= start / loadout
func can_start(p: Node, opts: Dictionary) -> String:
	if p == null:
		return "No player."
	if p.has_method("is_in_vehicle") and p.is_in_vehicle():
		return "Get out of the vehicle first."
	if p.get("is_swimming") == true:
		return "Not while swimming."
	if stands.is_empty():
		return "The range is closed."
	if String(opts.get("option", "")) == "own":
		var w = p.get("weapons")
		if w == null or not _is_range_firearm(w.current_id):
			return "Equip a firearm first (no explosives or melee)."
	return ""


func _is_range_firearm(wid: StringName) -> bool:
	if wid == &"fists" or not WeaponDefs.has(wid):
		return false
	return WeaponDefs.is_firearm(wid) and not WeaponDefs.is_projectile_weapon(wid)


func begin(opts: Dictionary) -> bool:
	var p = player()
	if p == null or p.weapons == null:
		return false
	set_id = String(opts.get("option", "pistol"))
	if set_id != "own" and not SETS.has(set_id):
		set_id = "pistol"
	if not _loan_weapons(p, set_id):
		toast("The range officer has no weapon for you.", &"warn")
		return false
	_reset_stats()
	_rng.randomize()
	# walk to lane 3 (fade), face down range
	var lane := lane_xf[3]
	var yaw := Util.dir_to_yaw(down_dir)
	var ui = Game.ui
	var fade := not bool(opts.get("instant", false)) and ui != null and is_instance_valid(ui) and ui.has_method("fade")
	if fade:
		ui.fade(true, 0.0)                        # cut to black, move, fade back in (begin() must stay synchronous)
	p.teleport_to(lane.origin + down_dir * FIRE_FORWARD + Vector3(0, 0.12, 0), yaw)   # in front of the 1.07 m counter so its collider never blocks the muzzle
	var cam = p.get("camera")
	if cam != null and is_instance_valid(cam) and cam.has_method("snap_behind"):
		cam.snap_behind(yaw)
	if fade:
		ui.fade(false, 0.7)
	for s in stands:
		s.live = false
		s.stop_sliding()
		s.set_civilian(false)
		s.pop_down()
	if not Events.weapon_fired.is_connected(_on_weapon_fired):
		Events.weapon_fired.connect(_on_weapon_fired)
	hud().begin(title, "%s - hold E to quit" % _set_name(), accent)
	_refresh_hud()
	say("Range officer: Lane three is hot. Load and make ready.", 3.0)
	phase = Phase.INTRO
	return true


func _set_name() -> String:
	if set_id == "own":
		return "Own weapon"
	return String(SETS[set_id]["name"])


func _loan_weapons(p: Node, sid: String) -> bool:
	var w = p.weapons
	_saved_weapons = w.serialize()
	var wid: StringName
	var mods: Dictionary = {}
	var tint := ""
	if sid == "own":
		wid = w.current_id
		if not _is_range_firearm(wid):
			return false
		var e: Dictionary = (_saved_weapons.get("inventory", {}) as Dictionary).get(String(wid), {})
		mods = e.get("mods", {})
		tint = String(e.get("tint", ""))
	else:
		wid = SETS[sid]["weapon"]
	var cap := WeaponDefs.mag_capacity(wid, {})
	var entry := {"mag": cap, "reserve": 999, "mods": mods}
	if tint != "":
		entry["tint"] = tint
	w.set_trigger(false)
	w.set_aiming(false)
	w.deserialize({"current": String(wid), "inventory": {String(wid): entry}})
	w.refill_all_ammo()
	_loaned = true
	return true


func _restore_weapons() -> void:
	if not _loaned:
		return
	_loaned = false
	var p = player()
	if p != null and p.weapons != null and not _saved_weapons.is_empty():
		p.weapons.set_trigger(false)
		p.weapons.deserialize(_saved_weapons)
	_saved_weapons = {}


func _reset_stats() -> void:
	phase = Phase.INTRO
	round_i = 0
	wave_i = 0
	score_targets = 0
	penalties = 0
	time_bonus = 0
	hits = 0
	misses = 0
	civ_hits = 0
	heads = 0
	bulls = 0
	shots = 0
	run_time = 0.0
	rounds_done = 0
	per_round = []
	_wave_targets.clear()
	_resolved.clear()
	_announced_far = false


# ================================================================================================= run
func on_go() -> void:
	for s in stands:
		s.live = true
	_start_round(0)


func tick(dt: float, sys_state: int) -> void:
	if sys_state != ActivitySystem.State.RUNNING:
		return
	run_time += dt
	_round_t += dt
	match phase:
		Phase.INTRO:
			_phase_t -= dt
			if _phase_t <= 0.0:
				_next_wave()
		Phase.GAP:
			_phase_t -= dt
			if _phase_t <= 0.0:
				_next_wave()
		Phase.WAVE:
			_wave_t += dt
			var rd: Dictionary = ROUNDS[round_i]
			var dur := float(rd["dur"])
			var open := 0
			for t in _wave_targets:
				if _resolved.has(t):
					continue
				if _wave_t >= dur:
					_resolved[t] = true
					if not t.civilian:
						misses += 1
					t.pop_down()
					if t.civilian:
						pass
				elif not t.civilian:
					open += 1
			# a wave ends when every hostile target is resolved (civilians fold with the rest at the time limit)
			if open == 0:
				for t in _wave_targets:
					if not _resolved.has(t):
						_resolved[t] = true
						t.pop_down()
				_end_wave()
		Phase.ROUND_END:
			_phase_t -= dt
			if _phase_t <= 0.0:
				if round_i + 1 < ROUNDS.size():
					_start_round(round_i + 1)
				else:
					_finish()
		Phase.DONE:
			pass
	_refresh_hud()


func check_abort() -> String:
	var p = player()
	if p == null:
		return ""
	if p.has_method("is_in_vehicle") and p.is_in_vehicle():
		return "Cease fire - you left the firing line."
	if lane_xf.size() > 3 and Util.dist_xz(p.global_position, lane_xf[3].origin) > 15.0:
		return "Cease fire - you left the firing line."
	return ""


func on_abort(_reason: String) -> void:
	say("Range officer: Cease fire! Unload and clear.", 3.0)


func cleanup() -> void:
	if Events.weapon_fired.is_connected(_on_weapon_fired):
		Events.weapon_fired.disconnect(_on_weapon_fired)
	_restore_weapons()
	for s in stands:
		if is_instance_valid(s):
			s.live = false
			s.stop_sliding()
			s.set_civilian(false)
			s.expire_at = -1.0
			s.pop_up()
	_wave_targets.clear()
	_resolved.clear()


func _start_round(i: int) -> void:
	round_i = i
	wave_i = 0
	_round_t = 0.0
	_round_hits = 0
	_round_targets = 0
	var rd: Dictionary = ROUNDS[i]
	hud().banner(String(rd["name"]), 2.2, accent)
	play_sfx(&"chime")
	var lines := ["Range officer: Round one - warm-up. Weapons free.", "Range officer: Round two. Cyan silhouettes are civilians - do not shoot.", "Range officer: Final round. Targets move and hide fast."]
	say(lines[i], 3.2)
	for s in stands:
		s.pop_down()
		s.set_civilian(false)
		s.stop_sliding()
	# plan the waves: [{count, civ}]
	_wave_plan = []
	var civ_left := int(rd["civ"])
	var waves := int(rd["waves"])
	for w in waves:
		var per: Array = rd["per"]
		var cnt := _rng.randi_range(int(per[0]), int(per[1]))
		var civ := 0
		if civ_left > 0 and cnt >= 1 and (_rng.randf() < float(civ_left) / float(maxi(waves - w, 1)) + 0.1):
			civ = 1
			civ_left -= 1
		_wave_plan.append({"count": cnt, "civ": civ})
	if civ_left > 0:       # make sure the planned civilians appear
		for k in range(_wave_plan.size() - 1, -1, -1):
			if civ_left <= 0:
				break
			if int(_wave_plan[k]["civ"]) == 0:
				_wave_plan[k]["civ"] = 1
				civ_left -= 1
	phase = Phase.INTRO
	_phase_t = 2.2


func _next_wave() -> void:
	if wave_i >= _wave_plan.size():
		_end_round()
		return
	var rd: Dictionary = ROUNDS[round_i]
	var plan: Dictionary = _wave_plan[wave_i]
	wave_i += 1
	var rows: Array = rd["rows"]
	var chosen: Array[ActivityTarget] = []
	var candidates: Array[ActivityTarget] = []
	for s in stands:
		if rows.has(s.row_m) and not _wave_targets.has(s):
			candidates.append(s)
	if candidates.is_empty():
		candidates = stands.duplicate()
	candidates.shuffle()
	var need := int(plan["count"])
	var p = player()
	var eye: Vector3 = (p.global_position if p != null else lane_xf[3].origin)
	for t in candidates:
		if chosen.size() >= need:
			break
		var blocked := false
		for o in chosen:
			if _occludes(eye, o, t) or _occludes(eye, t, o):
				blocked = true
				break
		if not blocked:
			chosen.append(t)
	if chosen.is_empty() and not candidates.is_empty():
		chosen.append(candidates[0])
	_wave_targets = chosen
	_resolved.clear()
	_wave_t = 0.0
	var civ_n := int(plan["civ"])
	for idx in chosen.size():
		var t := chosen[idx]
		var is_civ := civ_n > 0 and idx == chosen.size() - 1 and chosen.size() > 1 or (civ_n > 0 and chosen.size() == 1 and false)
		if is_civ:
			civ_n -= 1
		t.set_civilian(is_civ)
		t.live = true
		var sl := float(rd["slide"])
		if sl > 0.0 and not is_civ and _rng.randf() < 0.5:
			t.set_sliding(sl, 1.0 + _rng.randf() * 0.9)
		else:
			t.stop_sliding()
		t.pop_up()
		if not is_civ:
			_round_targets += 1
	phase = Phase.WAVE


func _occludes(eye: Vector3, near_t: ActivityTarget, far_t: ActivityTarget) -> bool:
	if near_t.row_m >= far_t.row_m:
		return false
	var a := near_t.root.global_position - eye
	var b := far_t.root.global_position - eye
	var ta := a.dot(lat_dir) / maxf(a.dot(down_dir), 1.0)
	var tb := b.dot(lat_dir) / maxf(b.dot(down_dir), 1.0)
	return absf(ta - tb) < 0.075


func _end_wave() -> void:
	phase = Phase.GAP
	_phase_t = float(ROUNDS[round_i]["gap"])
	for t in _wave_targets:
		t.stop_sliding()


func _end_round() -> void:
	rounds_done += 1
	var rd: Dictionary = ROUNDS[round_i]
	var par := float(rd["waves"]) * (float(rd["dur"]) * 0.50 + float(rd["gap"]))
	var bonus := 0
	if _round_hits >= int(float(_round_targets) * 0.6):
		bonus = int(clampf(par - _round_t, 0.0, 40.0) * TIME_BONUS_PER_S)
	time_bonus += bonus
	per_round.append({"hits": _round_hits, "targets": _round_targets, "bonus": bonus})
	for s in stands:
		s.stop_sliding()
		s.pop_down()
		s.set_civilian(false)
	var msg := "%s complete: %d/%d" % [String(rd["short"]), _round_hits, _round_targets]
	if bonus > 0:
		msg += "  +%d time bonus" % bonus
	hud().banner(msg, 2.4, GC.COL_OK)
	play_sfx(&"chime")
	phase = Phase.ROUND_END
	_phase_t = 2.8 if round_i + 1 < ROUNDS.size() else 1.2


func _finish() -> void:
	phase = Phase.DONE
	var res := compute_result()
	say("Range officer: Cease fire. Clear and safe your weapon.", 3.0)
	finish_activity(res)


func accuracy() -> float:
	return clampf(float(hits) / float(maxi(shots, 1)), 0.0, 1.0)


func compute_result() -> Dictionary:
	var acc := accuracy()
	var acc_bonus := int(acc * 400.0) if shots >= 10 else 0
	var total := maxi(score_targets - penalties + time_bonus + acc_bonus, 0)
	var mult := 1.0
	if set_id != "own":
		mult = float(SETS[set_id]["mult"])
	else:
		mult = 0.95
	var medal := ActivityBase.medal_for(float(total), MEDAL_SCORES[0] * mult, MEDAL_SCORES[1] * mult, MEDAL_SCORES[2] * mult)
	var total_targets := 0
	for r in per_round:
		total_targets += int(r["targets"])
	var rows := [
		["Targets hit", "%d / %d" % [hits, total_targets]],
		["Headshots / bullseyes", "%d / %d" % [heads, bulls]],
		["Accuracy", "%d%%  (%d shots)" % [int(round(acc * 100.0)), shots]],
		["Time bonus", "+%d" % time_bonus],
	]
	if civ_hits > 0:
		rows.append(["Civilians hit", "-%d" % penalties, GC.COL_DANGER])
	elif penalties == 0:
		rows.append(["Civilians hit", "none  (+0)", GC.COL_OK])
	var skill_amt := 6.0 + float(hits) * 0.22 + acc * 6.0 + float(heads) * 0.3
	return {
		"key": "range:" + set_id, "value": float(total), "higher_better": true, "medal": medal, "cash": ActivityBase.cash_for(medal, CASH),
		"skill": {"shooting": skill_amt}, "title": title, "subtitle": "%s - 3 rounds" % _set_name(), "main": "%s pts" % ActivityHud.group(total),
		"rows": rows, "hint": "Hold E to leave", "score": total, "accuracy": acc, "hits": hits, "shots": shots,
	}


# ================================================================================================= events
func _on_weapon_fired(character: Node, _wid: StringName) -> void:
	if running and character == Game.player and phase != Phase.DONE:
		shots += 1


func _on_scored(t: ActivityTarget, info: Dictionary) -> void:
	if not running or phase != Phase.WAVE or not _wave_targets.has(t) or _resolved.has(t):
		return
	_resolved[t] = true
	var pts := int(info["points"])
	var zone: StringName = info["zone"]
	var h := hud()
	if t.civilian:
		civ_hits += 1
		penalties += CIV_PENALTY
		h.popup("-%d  CIVILIAN" % CIV_PENALTY, GC.COL_DANGER)
		h.banner("DON'T SHOOT THE CIVILIANS", 1.4, GC.COL_DANGER)
		play_sfx(&"buzz")
		say("Range officer: Civilian hit! Watch your target.", 2.0)
		return
	hits += 1
	_round_hits += 1
	score_targets += pts
	if zone == &"head":
		heads += 1
	if zone == &"bull":
		bulls += 1
	var col := GC.COL_OK
	if zone == &"head" or zone == &"bull":
		col = Color("#ffd35a")
	elif pts < 60:
		col = GC.COL_TEXT
	h.popup("+%d  %s" % [pts, String(info["label"])], col)
	play_sfx(&"bull" if (zone == &"head" or zone == &"bull") else &"ping")


func _refresh_hud() -> void:
	var h := hud()
	if h == null:
		return
	var tot := ROUNDS.size()
	var live_score := maxi(score_targets - penalties + time_bonus, 0)
	h.set_cell(0, "Round", "%d / %d" % [mini(round_i + 1, tot), tot], GC.COL_TEXT)
	h.set_cell(1, "Time", ActivityHud.format_time(run_time), GC.COL_TEXT)
	h.set_cell(2, "Score", ActivityHud.group(live_score), Color("#ffd35a"))
	h.set_cell(3, "Accuracy", "%d%%" % int(round(accuracy() * 100.0)) if shots > 0 else "--", GC.COL_OK if accuracy() >= 0.6 or shots == 0 else GC.COL_WARN)
	if round_i < ROUNDS.size() and _wave_plan.size() > 0:
		h.set_progress(float(wave_i) / float(_wave_plan.size()), accent)
