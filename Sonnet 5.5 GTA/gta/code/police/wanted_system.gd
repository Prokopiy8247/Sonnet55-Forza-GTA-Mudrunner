class_name WantedSystem
extends Node
## 0-5 star wanted / pursuit / search state machine (Police-A). Boot key `wanted` (Game.sys(&"wanted")).
##
## What it does (docs/api/wanted.md has the full contract):
##  * DERIVES the player's crimes from Events (character_damaged / character_died / gunshot / explosion / vehicle_damaged /
##    vehicle_destroyed / vehicle_collision) and takes explicit Events.crime_committed from the vehicle module.
##  * Decides who KNOWS about a crime: police with line of sight (<= witness_police_range) -> immediate heat + PURSUIT;
##    civilian witnesses phone it in (PedManager.get_witnesses / Pedestrian.witness, then Events.crime_reported); gunshots and
##    explosions create an indirect report 6-10 s later when a pedestrian / officer is in hearing range; otherwise the crime stays
##    "unreported" and only counts if an officer later recognises the player.
##  * Rates crimes into heat (CrimeRules), heat into stars (hysteresis), runs PURSUIT / SEARCH / CLEAR, escape timers that only advance
##    while the player is truly unseen, hide / disguise bonuses, BUSTED (arrest) rules, the optional 1-star hail.
## All time is the internal clock `_t` (sum of physics deltas) so tests can drive it with tick(dt) and `manual = true`.

const S_CLEAR := &"clear"
const S_PURSUIT := &"pursuit"
const S_SEARCH := &"search"

# ---- public state (HUD / minimap / director read these) --------------------------------------------------------------------------
var level := 0
var state: StringName = S_CLEAR
var heat := 0.0
var search_radius := 0.0                     # metres, read by HUD / minimap through get("search_radius")
var last_known := Vector3.ZERO

# ---- tunables (see docs/api/wanted.md) ----------------------------------------------------------------------------------------------
var lose_track_time := 6.0                   # seconds without a sighting before PURSUIT turns into SEARCH
var scan_interval := 0.2                     # police LOS scan period
var sight_range_day := 95.0
var sight_range_night := 62.0
var heli_sight_day := 170.0
var heli_sight_night := 125.0
var track_radius := 35.0                     # any unit this close (with LOS) keeps tracking the player
var blind_radius := 14.0                     # ... and this close even without LOS (they hear you)
var foot_cone_cos := 0.34                    # officers on foot see +-70 deg; vehicles +-90 deg; helicopters everywhere
var vehicle_cone_cos := 0.0
var witness_police_range := 60.0             # a crime is "seen" by police inside this range with LOS
var witness_radius := 45.0                   # civilian witness search radius
var phone_min := 4.0                         # fallback witness phone call seconds (used only when the Peds module cannot do it)
var phone_max := 7.0
var indirect_delay_min := 6.0
var indirect_delay_max := 10.0
var unreported_ttl := 45.0
var dedupe_window := 25.0                    # further witness reports of an already applied incident inside this window are ignored
var bust_quiet_time := 2.0                   # no shooting / violence for this long before an arrest can happen
var bust_time_foot := 1.1
var bust_time_surrender := 0.5
var bust_time_vehicle := 2.8
var bust_radius_armed := 6.0                 # officer with a drawn weapon / cuffs
var bust_radius_unarmed := 3.0
var bust_radius_default := 5.0               # officer whose state we cannot read
var bundle_window := 3.0                     # crimes inside this window merge into one heat gain ...
var bundle_rest := 0.35                      # ... strongest crime + this fraction of the others
var heat_decay_idle := 0.35                  # heat points per second that evaporate while the level is 0
var hail_enabled := true
var search_area_rule := true                 # escaping needs the player OUTSIDE the search circle (or hidden); false = old pure-timer rule (tests)
var manual := false                          # true: _physics_process does nothing (tests call tick(dt))
var debug_clear := false                     # prints the call stack whenever a wanted level is cleared

# ---- internals ------------------------------------------------------------------------------------------------------------------------
var _t := 0.0
var _scan_acc := 0.0
var _seen_now := false
var _seer: Node = null
var _last_seen_t := -999.0
var _progress := 0.0
var _unseen_acc := 0.0
var _escape_needed := 15.0
var _search_t := 0.0
var _heat_at_search := 0.0
var _dead := false
var _busted := false
var _pub_level := 0
var _pub_state: StringName = S_CLEAR
var _rq := PhysicsRayQueryParameters3D.new()

var _incidents: Array[Dictionary] = []       # waiting for a phone call / indirect report
var _unreported: Array[Dictionary] = []      # known to nobody; counts when an officer recognises the player in time
var _phone_calls: Array[Dictionary] = []     # fallback witness calls (when PedManager cannot run them)
var _last_crime_t: Dictionary = {}
var _recent_applied: Array[Dictionary] = []   # {crime, pos, t} of incidents already on the books (several witnesses report one crime once)
var _crime_apply_log: Dictionary = {}        # crime -> Array[float] application times (repeat decay)
var _in_reported_emit := false
var _vehicle_attackers: Dictionary = {}      # police vehicle instance id -> time the player last damaged it

# identification (what the police saw at the last sighting)
var _ident_veh_id := 0
var _ident_paint := Color.BLACK
var _ident_real_t := 0.0
var _swap_t := 0.0
var _veh_swapped := false
var _appearance_changed := false
var _covered := false
var _hidden_mult := 1.0

# player activity memory
var _last_shot_t := -999.0
var _last_aggr_t := -999.0
var _last_hurt_t := -999.0
var _last_crime_applied_t := -999.0
var _near_officers: Array[Dictionary] = []   # [{node, armed}] on-foot officers within 16 m (refreshed by the scan)
var _near_cars: Array[Node] = []             # police vehicles within 11 m
var _bust_t := 0.0
var _hail_cd := 0.0
var _hail_until := -1.0
var _hail_officer: Node = null
var _warned_ped_api := false
var _bundle_t := -999.0
var _bundle_sum := 0.0
var _bundle_max := 0.0

var stats := {"crimes": 0, "reports": 0, "busts": 0, "escapes": 0, "sightings": 0}


# =====================================================================================================================================
#  Lifecycle
# =====================================================================================================================================
func setup(_main: Node) -> void:
	_rq.collision_mask = GC.M_LOS
	Events.character_damaged.connect(_on_character_damaged)
	Events.character_died.connect(_on_character_died)
	Events.gunshot.connect(_on_gunshot)
	Events.explosion.connect(_on_explosion)
	Events.vehicle_damaged.connect(_on_vehicle_damaged)
	Events.vehicle_destroyed.connect(_on_vehicle_destroyed)
	Events.vehicle_collision.connect(_on_vehicle_collision)
	Events.crime_committed.connect(_on_crime_committed)
	Events.crime_reported.connect(_on_crime_reported)
	Events.player_died.connect(_on_player_died)
	Events.player_busted.connect(_on_player_busted)
	Events.player_respawned.connect(_on_player_respawned)


func post_setup() -> void:
	pass


func _physics_process(dt: float) -> void:
	if manual:
		return
	tick(dt)


## One simulation step (also called by tests with manual = true).
func tick(dt: float) -> void:
	_t += dt
	if bool(Game.cheats.get("never_wanted", false)):
		if level > 0 or heat > 0.0:
			clear()
		return
	var p := _player()
	if p == null:
		return
	if _dead or _busted:
		return
	_tick_incidents(dt)
	_scan_acc += dt
	if _scan_acc >= scan_interval:
		_scan_acc = 0.0
		_scan_police()
	if level > 0:
		_tick_state(dt)
	elif heat > 0.0:
		heat = maxf(heat - heat_decay_idle * dt, 0.0)
	_tick_bust(dt)
	_tick_hail(dt)
	_sync()


# =====================================================================================================================================
#  Public API (docs/ARCHITECTURE.md 14.1)
# =====================================================================================================================================
func get_last_known_position() -> Vector3:
	return last_known


func get_search_radius() -> float:
	return search_radius


func is_player_seen() -> bool:
	return level > 0 and _seen_now


## 0..1 escape progress while unseen in SEARCH.
func escape_progress() -> float:
	return _progress


## True while the player is inside the circle the police are searching (last known position, `search_radius`).
func is_inside_search_area() -> bool:
	var p := _player()
	return p != null and state == S_SEARCH and Util.dist_xz(p.global_position, last_known) < search_radius


## Seconds the current SEARCH has been running (0 outside of SEARCH).
func get_search_age() -> float:
	return _search_t if state == S_SEARCH else 0.0


func get_escape_time_needed() -> float:
	return _escape_needed


func get_state() -> StringName:
	return state


## Debug / cheat: instantly set the star level (pursuit state, police are told where the player is).
func set_level(n: int) -> void:
	n = clampi(n, 0, 5)
	if n == 0 or bool(Game.cheats.get("never_wanted", false)):
		clear()
		return
	heat = CrimeRules.heat_for_level(n) + 0.5
	level = n
	var p := _player()
	last_known = p.global_position if p != null else last_known
	_enter_pursuit(true)
	_last_seen_t = _t
	_sync()


## Wanted level lost / player died / arrested: everything back to zero.
func clear() -> void:
	var had := level > 0
	if debug_clear and had:
		print("[Wanted] clear() at t=%.1f from:" % _t)
		print_stack()
	level = 0
	heat = 0.0
	state = S_CLEAR
	search_radius = 0.0
	_progress = 0.0
	_unseen_acc = 0.0
	_seen_now = false
	_seer = null
	_bust_t = 0.0
	_veh_swapped = false
	_appearance_changed = false
	_swap_t = 0.0
	_ident_veh_id = 0
	_hail_until = -1.0
	_incidents.clear()
	_phone_calls.clear()
	_unreported.clear()
	_crime_apply_log.clear()
	_recent_applied.clear()
	_sync()
	if had:
		Events.wanted_search_progress.emit(0.0)


## Adds heat directly (no witness logic): other modules / debug. The police are told the player's current position.
func add_wanted(points: float) -> void:
	if points <= 0.0 or not _can_accumulate():
		return
	_add_heat(points, 0)
	if level > 0:
		var p := _player()
		_register_report(p.global_position if p != null else last_known)
	_sync()


## Runs the full pipeline (police sight -> immediate; witnesses -> phone call; loud -> indirect report) for one crime of the player.
## `seen_by_police` forces the "police saw it" path. Returns false when ignored (cooldown, not the player, dead...).
func report_crime(crime: StringName, pos: Vector3, perpetrator: Node = null, seen_by_police: bool = false, severity: float = 1.0, loudness: float = -1.0) -> bool:
	if not _can_accumulate():
		return false
	if perpetrator != null and not _is_player(perpetrator):
		return false
	var rule := CrimeRules.get_rule(crime)
	if rule.is_empty() or float(rule.get("heat", 0.0)) <= 0.0:
		return false
	if _t - float(_last_crime_t.get(crime, -999.0)) < float(rule.get("cooldown", 5.0)):
		return false
	_last_crime_t[crime] = _t
	stats["crimes"] = int(stats["crimes"]) + 1
	var inc := {"crime": crime, "pos": pos, "severity": severity, "t": _t, "rule": rule, "calls": 0,
		"indirect_due": -1.0, "hear": 0.0, "done": false, "loud": loudness}
	var instant := seen_by_police or _police_witness(pos)
	if instant:
		_apply_incident(inc, true)
		_sync()
		return true
	if bool(rule.get("broadcast", false)):
		_apply_incident(inc, false)
		_sync()
		return true
	var calls := 0
	if bool(rule.get("phone", true)):
		calls = _dispatch_witnesses(inc)
	inc["calls"] = calls
	var is_loud: bool = bool(rule.get("loud", false)) and (loudness < 0.0 or loudness >= CrimeRules.quiet_loudness)
	if is_loud:
		var hear := clampf(loudness if loudness > 0.0 else 110.0, 40.0, 180.0)
		inc["hear"] = hear
		if _count_hearers(pos, hear) > 0:
			inc["indirect_due"] = _t + randf_range(indirect_delay_min, indirect_delay_max)
	if calls > 0 or float(inc["indirect_due"]) >= 0.0:
		_incidents.append(inc)
	else:
		_add_unreported(inc)
	return true


## Police units that SEE the player call this (position of the player, the officer that saw him). Pursuit resumes immediately.
func report_sighting(pos: Vector3, officer: Node = null) -> void:
	if _dead or _busted:
		return
	stats["sightings"] = int(stats["sightings"]) + 1
	_seer = officer
	_register_sighting(pos)
	_sync()


## Clothes changed / vehicle repainted (clothing store, garage): helps the escape while the police are searching.
func notify_appearance_changed() -> void:
	if level > 0:
		_appearance_changed = true


func is_busted_pending() -> bool:
	return _bust_t > 0.0


func get_bust_progress() -> float:
	return clampf(_bust_t / bust_time_foot, 0.0, 1.0)


func get_escape_multiplier() -> float:
	return _escape_multiplier()


func get_recent_crime_age() -> float:
	return _t - _last_crime_applied_t


func get_debug_string() -> String:
	return "L%d %s heat=%.1f seen=%s prog=%.2f/%.0fs radius=%.0f mult=%.2f bust=%.2f" % [level, String(state), heat, str(_seen_now), _progress, _escape_needed, search_radius, _escape_multiplier(), _bust_t]


func serialize() -> Dictionary:
	return {"level": level, "heat": heat, "state": String(state), "last_known": [last_known.x, last_known.y, last_known.z],
		"search_radius": search_radius, "progress": _progress}


func deserialize(data: Dictionary) -> void:
	clear()
	var lvl := clampi(int(data.get("level", 0)), 0, 5)
	if lvl <= 0:
		return
	level = lvl
	heat = maxf(float(data.get("heat", CrimeRules.heat_for_level(lvl))), CrimeRules.heat_for_level(lvl))
	var lk: Variant = data.get("last_known", null)
	if lk is Array and (lk as Array).size() >= 3:
		last_known = Vector3(float(lk[0]), float(lk[1]), float(lk[2]))
	else:
		var p := _player()
		last_known = p.global_position if p != null else Vector3.ZERO
	# a restored wanted level always resumes as SEARCH around the saved position (the police have to find the player again)
	_enter_search(false)
	search_radius = maxf(float(data.get("search_radius", search_radius)), search_radius)
	_unseen_acc = clampf(float(data.get("progress", 0.0)), 0.0, 0.9) * _escape_needed
	_progress = _unseen_acc / _escape_needed
	_sync()


# =====================================================================================================================================
#  State machine
# =====================================================================================================================================
func _can_accumulate() -> bool:
	if _dead or _busted or bool(Game.cheats.get("never_wanted", false)):
		return false
	return _player() != null


func _sync() -> void:
	if level != _pub_level or state != _pub_state:
		_pub_level = level
		_pub_state = state
		Game.wanted_level = level
		Game.wanted_state = state
		Events.wanted_changed.emit(level, state)


func _add_heat(points: float, min_level: int) -> void:
	heat = clampf(heat + points, 0.0, CrimeRules.heat_max)
	if min_level > 0:
		heat = maxf(heat, CrimeRules.heat_for_level(min_level))
	var nl := CrimeRules.level_for_heat(heat, level)
	if nl > level:
		level = nl
		# the escape timer restarts on any escalation
		_unseen_acc = 0.0
		_progress = 0.0
		_escape_needed = CrimeRules.escape_seconds(level)


func _enter_pursuit(reset_ident: bool = true) -> void:
	if state != S_PURSUIT:
		state = S_PURSUIT
		Events.wanted_search_progress.emit(0.0)
	_progress = 0.0
	_unseen_acc = 0.0
	_search_t = 0.0
	search_radius = CrimeRules.search_start_radius(maxi(level, 1))
	_escape_needed = CrimeRules.escape_seconds(maxi(level, 1))
	if reset_ident:
		_capture_identification()


func _enter_search(restart: bool) -> void:
	state = S_SEARCH
	_search_t = 0.0
	_progress = 0.0
	_unseen_acc = 0.0
	_heat_at_search = heat
	search_radius = CrimeRules.search_start_radius(maxi(level, 1))
	_escape_needed = CrimeRules.escape_seconds(maxi(level, 1))
	if restart:
		_swap_t = 0.0


## Police know where the crime happened (witness report / radio) but nobody sees the player.
func _register_report(pos: Vector3) -> void:
	if level <= 0:
		return
	stats["reports"] = int(stats["reports"]) + 1
	last_known = pos
	if state == S_CLEAR:
		_enter_search(true)
	elif state == S_SEARCH:
		# fresh information: the search re-centres on the report and the escape timer restarts
		_search_t = 0.0
		_progress = 0.0
		_unseen_acc = 0.0
		_heat_at_search = heat
		search_radius = CrimeRules.search_start_radius(level)
		_escape_needed = CrimeRules.escape_seconds(level)
	# in PURSUIT the tracking keeps running by itself


## An officer (or the scan) sees the player: PURSUIT, last known position = the player.
func _register_sighting(pos: Vector3) -> void:
	_last_seen_t = _t
	last_known = pos
	_seen_now = true
	if level <= 0:
		_resolve_unreported()
		return
	if state != S_PURSUIT:
		_enter_pursuit(true)
	else:
		_capture_identification()


func _tick_state(dt: float) -> void:
	var p := _player()
	if p == null:
		return
	if _seen_now:
		# last-known follows the player continuously while the police track him
		last_known = p.global_position
		_last_seen_t = _t
		_clear_hold_t = 0.0
		if state == S_SEARCH:
			_enter_pursuit(true)
		return
	if state == S_PURSUIT:
		if _t - _last_seen_t > lose_track_time:
			_enter_search(true)
		return
	if state == S_SEARCH:
		_search_t += dt
		search_radius = minf(search_radius + CrimeRules.search_growth * dt, CrimeRules.search_radius_max)
		_tick_disguise(dt)
		var mult := _escape_multiplier()
		_unseen_acc += dt * mult
		_progress = clampf(_unseen_acc / maxf(_escape_needed, 1.0), 0.0, 1.0)
		var decay := _heat_at_search * CrimeRules.search_decay_fraction / maxf(_escape_needed, 1.0)
		heat = maxf(heat - decay * dt * mult, 0.0)
		var nl := maxi(CrimeRules.level_for_heat(heat, level), 1)
		if nl < level:
			level = nl
		Events.wanted_search_progress.emit(_progress)
		if _progress >= 1.0:
			stats["escapes"] = int(stats["escapes"]) + 1
			clear()
			Game.notify("Wanted level lost", &"good")


const CLEAR_HOLD_MAX := 30.0            # max extra seconds the clear is postponed while a foot officer is still closing in
var _clear_hold_t := 0.0


## A living police officer on foot within 110 m of the suspect that is still working the case (not leaving).
func _foot_unit_en_route(p: Node) -> bool:
	if p == null or not is_instance_valid(p) or not (p is Node3D):
		return false
	var pp := (p as Node3D).global_position
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if not (n is CharacterBase) or not is_instance_valid(n):
			continue
		var cb := n as CharacterBase
		if cb.is_dead or cb.is_in_vehicle() or cb.get("mode") == &"leave":
			continue
		if Util.dist_xz(cb.global_position, pp) < 110.0:
			return true
	return false


func _escape_multiplier() -> float:
	var m := 1.0
	var p := _player()
	if p == null:
		return m
	var hidden := false
	if p.global_position.y < -150.0 or _flag(p, "in_interior") or _meta_flag(&"in_interior"):
		m *= CrimeRules.mult_interior
		hidden = true
	elif _flag(p, "head_underwater"):
		m *= CrimeRules.mult_underwater
		hidden = true
	elif _flag(p, "is_swimming"):
		m *= CrimeRules.mult_swimming
	elif _covered:
		m *= CrimeRules.mult_covered
	# staying inside the area the police are combing barely helps: the player has to get out of the circle (or out of sight for real)
	if search_area_rule and not hidden and is_inside_search_area():
		m *= CrimeRules.mult_inside_area
	if _veh_swapped:
		m *= CrimeRules.mult_vehicle_swap
	if _appearance_changed:
		m *= CrimeRules.mult_appearance
	return minf(m, CrimeRules.mult_max)


func _capture_identification() -> void:
	var p := _player()
	_veh_swapped = false
	_appearance_changed = false
	_swap_t = 0.0
	_ident_veh_id = 0
	_ident_real_t = Time.get_ticks_msec() / 1000.0
	if p != null and p.has_method("is_in_vehicle") and p.is_in_vehicle():
		var v: Node = p.current_vehicle
		if v != null and is_instance_valid(v):
			_ident_veh_id = v.get_instance_id()
			var col: Variant = v.get("paint_primary")
			_ident_paint = col if col is Color else Color.BLACK


## Vehicle swap (abandoned the identified vehicle for > 10 s), repaint, clothes: the escape gets faster, never instant.
func _tick_disguise(dt: float) -> void:
	var p := _player()
	if p == null:
		return
	var cur_id := 0
	if p.has_method("is_in_vehicle") and p.is_in_vehicle():
		var cv: Node = p.current_vehicle
		if cv != null and is_instance_valid(cv):
			cur_id = cv.get_instance_id()
	if cur_id != _ident_veh_id:
		_swap_t += dt
		if _swap_t >= CrimeRules.vehicle_abandon_time:
			_veh_swapped = true
	else:
		_swap_t = 0.0
	if _ident_veh_id != 0 and not _appearance_changed:
		var iv: Object = instance_from_id(_ident_veh_id)
		if iv != null and is_instance_valid(iv):
			var col: Variant = iv.get("paint_primary")
			if col is Color and not (col as Color).is_equal_approx(_ident_paint):
				_appearance_changed = true
	if not _appearance_changed:
		var stamp: Variant = Game.get_meta(&"appearance_changed_at", -1.0)
		if (stamp is float or stamp is int) and float(stamp) > _ident_real_t:
			_appearance_changed = true


# =====================================================================================================================================
#  Police scan (line of sight, hearing, hiding)
# =====================================================================================================================================
func _scan_police() -> void:
	var p := _player()
	if p == null:
		return
	if level <= 0 and _unreported.is_empty():
		_seen_now = false
		_near_officers.clear()
		_near_cars.clear()
		return
	var ppos := p.global_position
	var target := _target_point()
	var invisible := _flag(p, "head_underwater") or ppos.y < -150.0
	var night := _night_amount()
	var weather_mult := 1.0 - 0.45 * clampf(Game.fog_amount, 0.0, 1.0) - 0.18 * clampf(Game.rain_intensity, 0.0, 1.0)
	var stealth := 0.82 if _flag(p, "crouching") else 1.0
	var seen := false
	var seer: Node = null
	_near_officers.clear()
	_near_cars.clear()
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var u := n as Node3D
		if not _unit_active(u):
			continue
		var is_char := u is CharacterBase
		var is_heli: bool = u.get("vclass") == GC.VC_HELI
		var upos := u.global_position
		var d := upos.distance_to(ppos)
		var eye := _unit_eye(u, is_char, is_heli)
		if is_char and d <= 16.0:
			_near_officers.append({"node": u, "armed": _officer_armed(u), "los": not _los_blocked(eye, target), "d": d})
		elif not is_char and not is_heli and d <= 11.0:
			_near_cars.append(u)
		if invisible:
			continue
		var rng_m := (lerpf(heli_sight_day, heli_sight_night, night) if is_heli else lerpf(sight_range_day, sight_range_night, night)) * weather_mult
		if d > maxf(rng_m, track_radius):
			continue
		if seen and seer != null:
			continue    # already seen by someone; the loop only continues to fill the near caches
		var detected := false
		if d <= blind_radius:
			detected = true
		else:
			var clear_los := not _los_blocked(eye, target)
			if clear_los:
				if d <= track_radius:
					detected = true
				elif d <= rng_m * stealth:
					if is_heli:
						detected = true
					else:
						var fwd := -u.global_transform.basis.z
						fwd.y = 0.0
						var to_p := target - eye
						to_p.y = 0.0
						if fwd.length_squared() > 0.001 and to_p.length_squared() > 0.001:
							var cos_lim := vehicle_cone_cos if not is_char else foot_cone_cos
							detected = fwd.normalized().dot(to_p.normalized()) >= cos_lim
		if detected:
			seen = true
			seer = u
	# overhead cover (garage / parking deck / bridge): helps hiding
	_covered = _ray_hit(p.global_position + Vector3.UP * 1.0, p.global_position + Vector3.UP * 8.0)
	_seen_now = seen
	_seer = seer
	if seen:
		_register_sighting(ppos)


## Duck-typed property reads that never fail on a missing property (Object.get returns null, bool(null) is an error).
func _flag(o: Object, prop: String) -> bool:
	var v: Variant = o.get(prop)
	return v is bool and v


func _num(o: Object, prop: String) -> float:
	var v: Variant = o.get(prop)
	return float(v) if (v is float or v is int) else 0.0


func _meta_flag(key: StringName) -> bool:
	var v: Variant = Game.get_meta(key, false)
	return v is bool and v


func _unit_dead(u: Node) -> bool:
	if u.get("is_dead") == true or u.get("is_destroyed") == true:
		return true
	return false


## A police node that can actually watch: an officer on foot, a vehicle driven by the police AI / an officer, a running helicopter.
## Empty parked cruisers (showroom, stolen and abandoned patrol cars) never see anything.
func _unit_active(u: Node) -> bool:
	if _unit_dead(u):
		return false
	if u is CharacterBase:
		return not (u as CharacterBase).is_in_vehicle()
	var drv: Variant = u.get("driver")
	if drv != null and is_instance_valid(drv) and _is_player(drv):
		return false
	if _flag(u, "is_ai_controlled") or (drv != null and is_instance_valid(drv)):
		return true
	return u.get("vclass") == GC.VC_HELI and _flag(u, "engine_on")


func _unit_eye(u: Node3D, is_char: bool, is_heli: bool) -> Vector3:
	if is_char and u.has_method("get_eye_position"):
		return u.call("get_eye_position")
	if is_heli:
		return u.global_position + Vector3.UP * 0.3
	return u.global_position + Vector3.UP * (1.6 if is_char else 1.4)


func _officer_armed(o: Node) -> bool:
	var drawn: Variant = o.get("weapon_drawn")
	if drawn is bool:
		return drawn
	var w: Variant = o.get("weapons")
	if w != null and is_instance_valid(w) and w.has_method("is_armed"):
		return bool(w.is_armed())
	return true


func _target_point() -> Vector3:
	var p := _player()
	if p == null:
		return Vector3.ZERO
	if p.has_method("is_in_vehicle") and p.is_in_vehicle():
		var v: Node = p.current_vehicle
		if v != null and is_instance_valid(v) and v is Node3D:
			return (v as Node3D).global_position + Vector3.UP * 1.0
	if _flag(p, "is_swimming"):
		return p.global_position + Vector3.UP * 1.1
	return p.global_position + Vector3.UP * 1.15


func _night_amount() -> float:
	var env: Variant = Game.sys(&"environment")
	if env != null and env.has_method("get_night_amount"):
		return clampf(float(env.get_night_amount()), 0.0, 1.0)
	return 1.0 if Game.is_night() else 0.0


func _world_space() -> PhysicsDirectSpaceState3D:
	var vp := get_viewport()
	if vp == null:
		return null
	var w := vp.find_world_3d()
	return w.direct_space_state if w != null else null


func _ray_hit(from: Vector3, to: Vector3) -> bool:
	var space := _world_space()
	if space == null:
		return false
	_rq.from = from
	_rq.to = to
	_rq.collision_mask = GC.M_LOS
	return not space.intersect_ray(_rq).is_empty()


func _los_blocked(from: Vector3, to: Vector3) -> bool:
	return _ray_hit(from, to)


## True when any living officer / patrol car within witness_police_range of `pos` (or of the player) has a clear line to it.
func _police_witness(pos: Vector3) -> bool:
	var p := _player()
	if p == null:
		return false
	var ppos := p.global_position
	var target := _target_point()
	var cpos := pos + Vector3.UP * 1.0
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var u := n as Node3D
		if not _unit_active(u):
			continue
		var is_char := u is CharacterBase
		var upos := u.global_position
		var near_crime := upos.distance_to(pos) <= witness_police_range
		var near_player := upos.distance_to(ppos) <= witness_police_range
		if not near_crime and not near_player:
			continue
		var is_heli: bool = u.get("vclass") == GC.VC_HELI
		var eye := _unit_eye(u, is_char, is_heli)
		if near_crime and not _los_blocked(eye, cpos):
			return true
		if near_player and not _los_blocked(eye, target):
			return true
	return false


# =====================================================================================================================================
#  Witnesses, incidents, reports
# =====================================================================================================================================
func _dispatch_witnesses(inc: Dictionary) -> int:
	var crime: StringName = inc["crime"]
	var pos: Vector3 = inc["pos"]
	var sev: float = inc["severity"]
	var perp: Node = _player()
	var calls := 0
	var witnesses: Array = []
	var pm: Variant = Game.sys(&"peds")
	if pm != null and pm.has_method("get_witnesses"):
		var res: Variant = pm.get_witnesses(pos, perp, witness_radius)
		if res is Array:
			witnesses = res
	else:
		if not _warned_ped_api:
			_warned_ped_api = true
			print("[Wanted] PedManager.get_witnesses not available: using the built-in group scan for civilian witnesses")
		witnesses = _fallback_witnesses(pos)
	for w in witnesses:
		if not is_instance_valid(w):
			continue
		if w.has_method("witness"):
			if bool(w.witness(crime, pos, perp, sev)):
				calls += 1
		elif w is Node3D:
			_phone_calls.append({"ped": w, "due": _t + randf_range(phone_min, phone_max), "inc": inc})
			calls += 1
	return calls


func _fallback_witnesses(pos: Vector3) -> Array:
	var out: Array = []
	var eye_to := pos + Vector3.UP * 1.0
	for n in get_tree().get_nodes_in_group(GC.G_PED):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if _unit_dead(n):
			continue
		var f: Variant = n.get("faction")
		if f != null and f != GC.F_CIVILIAN:
			continue
		var np := (n as Node3D).global_position
		if np.distance_to(pos) > witness_radius:
			continue
		if _los_blocked(np + Vector3.UP * 1.6, eye_to):
			continue
		out.append(n)
		if out.size() >= 6:
			break
	return out


## Number of living civilians / officers able to hear a sound at pos with the given audible radius.
func _count_hearers(pos: Vector3, radius: float) -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group(GC.G_PED):
		if n is Node3D and is_instance_valid(n) and not _unit_dead(n) and (n as Node3D).global_position.distance_to(pos) <= radius:
			c += 1
			if c >= 3:
				return c
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if n is Node3D and is_instance_valid(n) and _unit_active(n) and (n as Node3D).global_position.distance_to(pos) <= radius:
			c += 1
			if c >= 3:
				return c
	return c


func _count_civilian_hearers(pos: Vector3, radius: float) -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group(GC.G_PED):
		if n is Node3D and is_instance_valid(n) and not _unit_dead(n) and (n as Node3D).global_position.distance_to(pos) <= radius:
			c += 1
	return c


func _nearest_police_hearers(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(GC.G_POLICE):
		if n is Node3D and is_instance_valid(n) and _unit_active(n) and (n as Node3D).global_position.distance_to(pos) <= radius:
			out.append(n)
	return out


func _add_unreported(inc: Dictionary) -> void:
	inc["expires"] = _t + unreported_ttl
	_unreported.append(inc)
	if _unreported.size() > 12:
		_unreported.pop_front()


func _tick_incidents(_dt: float) -> void:
	# fallback witness phone calls
	var i := _phone_calls.size() - 1
	while i >= 0:
		var call: Dictionary = _phone_calls[i]
		var ped: Variant = call["ped"]
		var inc: Dictionary = call["inc"]
		if not is_instance_valid(ped) or _unit_dead(ped as Node):
			_phone_calls.remove_at(i)
			inc["calls"] = int(inc["calls"]) - 1
		elif _t >= float(call["due"]):
			_phone_calls.remove_at(i)
			if not bool(inc["done"]):
				_emit_reported(inc["crime"], inc["pos"])
				_apply_incident(inc, false)
		i -= 1
	# pending incidents: indirect reports and expiry
	i = _incidents.size() - 1
	while i >= 0:
		var inc2: Dictionary = _incidents[i]
		if bool(inc2["done"]):
			_incidents.remove_at(i)
		else:
			var due := float(inc2["indirect_due"])
			if due >= 0.0 and _t >= due:
				inc2["indirect_due"] = -1.0
				var pos: Vector3 = inc2["pos"]
				var hear := float(inc2["hear"])
				if _count_civilian_hearers(pos, hear) > 0:
					_emit_reported(inc2["crime"], pos)
					_apply_incident(inc2, false)
				else:
					var cops := _nearest_police_hearers(pos, hear)
					if not cops.is_empty():
						var pol: Variant = Game.sys(&"police")
						if pol != null and pol.has_method("investigate"):
							pol.investigate(pos, 40.0)
					_add_unreported(inc2)
					inc2["done_pending"] = true
			if not bool(inc2["done"]) and _t - float(inc2["t"]) > 20.0 and int(inc2["calls"]) <= 0 and float(inc2["indirect_due"]) < 0.0:
				_incidents.remove_at(i)
				if not inc2.has("done_pending"):
					_add_unreported(inc2)
			elif not bool(inc2["done"]) and _t - float(inc2["t"]) > 30.0:
				_incidents.remove_at(i)
				if not inc2.has("done_pending"):
					_add_unreported(inc2)
		i -= 1
	# unreported crimes expire
	i = _unreported.size() - 1
	while i >= 0:
		if bool(_unreported[i]["done"]) or _t > float(_unreported[i].get("expires", 0.0)):
			_unreported.remove_at(i)
		i -= 1


## The heat of an incident becomes real.
func _apply_incident(inc: Dictionary, seen_by_police: bool) -> void:
	if bool(inc["done"]):
		return
	inc["done"] = true
	var crime: StringName = inc["crime"]
	var rule: Dictionary = inc["rule"]
	_recent_applied.append({"crime": crime, "pos": inc["pos"], "t": _t})
	while _recent_applied.size() > 12 or (not _recent_applied.is_empty() and _t - float(_recent_applied[0]["t"]) > dedupe_window):
		_recent_applied.pop_front()
	var raw := float(rule.get("heat", 0.0)) * float(inc["severity"]) * _repeat_mult(crime, float(rule.get("repeat_decay", 0.7)))
	_note_applied(crime)
	# crimes of one violent moment (shot + hit + kill within a few seconds) merge: strongest + 35 % of the rest
	if _t - _bundle_t > bundle_window:
		_bundle_sum = 0.0
		_bundle_max = 0.0
	var prev_total := _bundle_max + bundle_rest * (_bundle_sum - _bundle_max)
	_bundle_sum += raw
	_bundle_max = maxf(_bundle_max, raw)
	_bundle_t = _t
	var pts := maxf((_bundle_max + bundle_rest * (_bundle_sum - _bundle_max)) - prev_total, 0.0)
	_add_heat(pts, int(rule.get("min_level", 0)))
	_last_crime_applied_t = _t
	if level > 0:
		var p := _player()
		if seen_by_police and p != null:
			_register_sighting(p.global_position)
		else:
			_register_report(inc["pos"])
	if seen_by_police or bool(rule.get("broadcast", false)):
		_emit_reported(crime, inc["pos"])


func _repeat_mult(crime: StringName, decay: float) -> float:
	var log: Array = _crime_apply_log.get(crime, [])
	var n := 0
	for tt in log:
		if _t - float(tt) <= CrimeRules.repeat_window:
			n += 1
	return maxf(pow(decay, float(n)), CrimeRules.repeat_floor)


func _note_applied(crime: StringName) -> void:
	var log: Array = _crime_apply_log.get(crime, [])
	log.append(_t)
	while log.size() > 8:
		log.pop_front()
	_crime_apply_log[crime] = log


func _resolve_unreported() -> void:
	if _unreported.is_empty():
		return
	var p := _player()
	if p == null:
		return
	var list := _unreported.duplicate()
	_unreported.clear()
	for inc in list:
		if bool(inc["done"]) or _t > float(inc.get("expires", 0.0)):
			continue
		_apply_incident(inc, true)


func _emit_reported(crime: StringName, pos: Vector3) -> void:
	_in_reported_emit = true
	Events.crime_reported.emit(crime, pos, _player())
	_in_reported_emit = false


# =====================================================================================================================================
#  Event handlers (crime derivation)
# =====================================================================================================================================
func _player() -> CharacterBase:
	var p: Variant = Game.player
	if p != null and is_instance_valid(p):
		return p as CharacterBase
	return null


## The player, or a vehicle / projectile owner that resolves to the player.
func _is_player(n: Variant) -> bool:
	if n == null or not (n is Node) or not is_instance_valid(n):
		return false
	var node := n as Node
	var pl: Variant = Game.player
	if pl != null and node == pl:
		return true
	if node.is_in_group(GC.G_PLAYER):
		return true
	var d: Variant = node.get("driver")
	return d != null and pl != null and d == pl


func _is_police_node(n: Node) -> bool:
	if n.is_in_group(GC.G_POLICE):
		return true
	return n.get("faction") == GC.F_POLICE


func _is_civilian_node(n: Node) -> bool:
	if n.is_in_group(GC.G_PED):
		return true
	return n.get("faction") == GC.F_CIVILIAN and n is CharacterBase


func _on_character_damaged(ch: Node, amount: float, info: Dictionary) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	var src: Variant = info.get("source", null)
	var p := _player()
	if p != null and ch == p:
		if not _is_player(src):
			_last_hurt_t = _t
		return
	if not _is_player(src) or amount < 0.5:
		return
	_note_aggression()
	if not _can_accumulate():
		return
	# lethal hits are reported by character_died (murder / officer down)
	var hp: Variant = ch.get("health")
	if (hp is float or hp is int) and float(hp) <= 0.0:
		return
	var t: StringName = info.get("type", GC.DMG_BULLET)
	if t == GC.DMG_EXPLOSION or t == GC.DMG_FIRE:
		if _is_police_node(ch):
			report_crime(GC.CRIME_POLICE_ASSAULT, (ch as Node3D).global_position, p)
		return
	var cpos := (ch as Node3D).global_position if ch is Node3D else p.global_position
	if _is_police_node(ch):
		report_crime(GC.CRIME_POLICE_ASSAULT, cpos, p)
	elif _is_civilian_node(ch):
		if t == GC.DMG_RUNOVER:
			report_crime(GC.CRIME_HIT_AND_RUN, cpos, p)
		else:
			report_crime(GC.CRIME_ASSAULT, cpos, p)


func _on_character_died(ch: Node, killer: Node, info: Dictionary) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	var src: Variant = killer if killer != null else info.get("source", null)
	if not _is_player(src):
		return
	var p := _player()
	if p == null or ch == p:
		return
	_note_aggression()
	if not _can_accumulate():
		return
	var cpos := (ch as Node3D).global_position if ch is Node3D else p.global_position
	if _is_police_node(ch):
		report_crime(GC.CRIME_POLICE_KILL, cpos, p)
	elif _is_civilian_node(ch):
		var t: StringName = info.get("type", GC.DMG_BULLET)
		if t == GC.DMG_RUNOVER:
			# the hit-and-run itself is heat; running someone over to death is murder as well
			report_crime(GC.CRIME_HIT_AND_RUN, cpos, p)
		report_crime(GC.CRIME_MURDER, cpos, p)


func _on_gunshot(pos: Vector3, loudness: float, source: Node) -> void:
	if not _is_player(source):
		return
	_last_shot_t = _t
	_note_aggression()
	if not _can_accumulate():
		return
	if _at_shooting_range():
		return
	report_crime(GC.CRIME_SHOOTING, pos, _player(), false, 1.0, loudness)


func _on_explosion(pos: Vector3, _radius: float, source: Node) -> void:
	if not _is_player(source):
		return
	_note_aggression()
	if not _can_accumulate():
		return
	report_crime(GC.CRIME_EXPLOSION, pos, _player(), false, 1.0, 160.0)


func _on_vehicle_damaged(vehicle: Node, amount: float, info: Dictionary) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not _is_player(info.get("source", null)):
		return
	if vehicle.is_in_group(GC.G_POLICE) and not _is_player(vehicle):
		_vehicle_attackers[vehicle.get_instance_id()] = _t
		if amount >= 5.0 and _can_accumulate():
			_note_aggression()
			report_crime(GC.CRIME_POLICE_ASSAULT, (vehicle as Node3D).global_position, _player())


func _on_vehicle_destroyed(vehicle: Node, killer: Node) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not _can_accumulate():
		return
	if _is_player(vehicle):
		return
	var by_player := _is_player(killer)
	if not by_player and vehicle.is_in_group(GC.G_POLICE):
		var tt := float(_vehicle_attackers.get(vehicle.get_instance_id(), -999.0))
		by_player = _t - tt < 12.0
	if not by_player:
		return
	var vpos := (vehicle as Node3D).global_position if vehicle is Node3D else Vector3.ZERO
	if vehicle.is_in_group(GC.G_POLICE):
		report_crime(GC.CRIME_POLICE_VEHICLE_DESTROYED, vpos, _player())
	elif vehicle.is_in_group(GC.G_TRAFFIC) or vehicle.get("is_ai_controlled") == true:
		report_crime(GC.CRIME_VANDALISM, vpos, _player())


func _on_vehicle_collision(vehicle: Node, other: Node, impulse: float) -> void:
	if vehicle == null or other == null or not is_instance_valid(vehicle) or not is_instance_valid(other):
		return
	if not _is_player(vehicle) or not _can_accumulate():
		return
	if other is CharacterBase:
		return    # run-over damage arrives through character_damaged (DMG_RUNOVER)
	if not other.is_in_group(GC.G_VEHICLE):
		return
	var vpos := (vehicle as Node3D).global_position if vehicle is Node3D else Vector3.ZERO
	if other.is_in_group(GC.G_POLICE):
		if impulse >= 5500.0:
			_note_aggression()
			report_crime(GC.CRIME_POLICE_ASSAULT, vpos, _player())
	elif impulse >= 9000.0 and (other.is_in_group(GC.G_TRAFFIC) or other.get("is_ai_controlled") == true):
		report_crime(GC.CRIME_COLLISION, vpos, _player(), false, clampf(impulse / 20000.0, 0.7, 2.0))


func _on_crime_committed(crime: StringName, pos: Vector3, perpetrator: Node, info: Dictionary) -> void:
	if not _is_player(perpetrator):
		return
	var sev := float(info.get("severity", 1.0))
	report_crime(crime, pos, _player(), bool(info.get("seen_by_police", false)), clampf(sev, 0.25, 3.0))


## A witness (Pedestrian phone call) or somebody else reported a crime: the heat becomes real now.
func _on_crime_reported(crime: StringName, pos: Vector3, perpetrator: Node) -> void:
	if _in_reported_emit:
		return
	if perpetrator != null and not _is_player(perpetrator):
		return
	if not _can_accumulate():
		return
	for inc in _incidents:
		if bool(inc["done"]) or inc["crime"] != crime:
			continue
		if (inc["pos"] as Vector3).distance_to(pos) <= 60.0:
			_apply_incident(inc, false)
			_sync()
			return
	# a second / third witness of a crime that is already on the books reports the same incident: never count it twice
	for ra in _recent_applied:
		if ra["crime"] == crime and _t - float(ra["t"]) < dedupe_window and (ra["pos"] as Vector3).distance_to(pos) <= 70.0:
			return
	# a report nobody here knows about (another module's witness): rate it by the crime table
	var rule := CrimeRules.get_rule(crime)
	if rule.is_empty() or perpetrator == null:
		return
	if _t - float(_last_crime_t.get(crime, -999.0)) < 1.0:
		return
	_last_crime_t[crime] = _t
	_apply_incident({"crime": crime, "pos": pos, "severity": 1.0, "t": _t, "rule": rule, "calls": 0, "indirect_due": -1.0, "hear": 0.0, "done": false, "loud": -1.0}, false)
	_sync()


func _on_player_died() -> void:
	_dead = true
	_bust_t = 0.0


func _on_player_busted() -> void:
	_busted = true
	_bust_t = 0.0
	stats["busts"] = int(stats["busts"]) + 1


func _on_player_respawned(_pos: Vector3) -> void:
	_dead = false
	_busted = false
	_bust_t = 0.0
	clear()


func _note_aggression() -> void:
	_last_aggr_t = _t
	# attacking while an arrest is imminent counts as resisting
	if _bust_t >= 0.35 and level > 0:
		var p := _player()
		report_crime(GC.CRIME_RESIST_ARREST, p.global_position if p != null else Vector3.ZERO, p, true)


func _at_shooting_range() -> bool:
	var loc := WorldLayout.get_location(&"shooting_range")
	if loc.is_empty():
		return false
	var p := _player()
	if p == null:
		return false
	var lp: Vector3 = loc.get("pos", Vector3.ZERO)
	return Util.dist_xz(lp, p.global_position) <= 28.0


# =====================================================================================================================================
#  BUSTED (arrest) rules
# =====================================================================================================================================
func _tick_bust(dt: float) -> void:
	if level <= 0:
		_bust_t = 0.0
		return
	var p := _player()
	if p == null or _flag(p, "is_dead") or _num(p, "spawn_protection") > 0.0:
		_bust_t = 0.0
		return
	var since_aggr := _t - _last_aggr_t
	var hurt_recent := _t - _last_hurt_t < 2.5
	var cond := false
	var need := bust_time_foot
	var by: Node = null
	if since_aggr > bust_quiet_time and not hurt_recent:
		var in_veh: bool = p.has_method("is_in_vehicle") and p.is_in_vehicle()
		if not in_veh:
			var spd: float = p.get_speed_xz() if p.has_method("get_speed_xz") else 0.0
			var surrender := _is_surrendering(p, spd)
			for rec in _near_officers:
				var o: Variant = rec["node"]
				if not is_instance_valid(o) or _unit_dead(o as Node):
					continue
				var d := Util.dist_xz((o as Node3D).global_position, p.global_position)
				var rad := bust_radius_armed if bool(rec["armed"]) else bust_radius_unarmed
				if surrender:
					rad += 2.5
				if d <= rad and (spd < 4.2 or d < 2.4) and bool(rec["los"]):
					cond = true
					by = o
					break
			if cond and surrender:
				need = bust_time_surrender
		else:
			var veh: Node = p.current_vehicle
			var vspd := 99.0
			if veh != null and is_instance_valid(veh) and veh.has_method("get_speed"):
				vspd = float(veh.call("get_speed"))
			if vspd < 2.2:
				var adj_foot := 0
				var first: Node = null
				for rec in _near_officers:
					var o2: Variant = rec["node"]
					if is_instance_valid(o2) and not _unit_dead(o2 as Node) and Util.dist_xz((o2 as Node3D).global_position, p.global_position) <= 4.8:
						adj_foot += 1
						if first == null:
							first = o2
				var adj_veh := 0
				for c in _near_cars:
					if is_instance_valid(c) and c != veh and not _unit_dead(c) and Util.dist_xz((c as Node3D).global_position, p.global_position) <= 7.5:
						adj_veh += 1
						if first == null:
							first = c
				if (adj_foot >= 1 and (adj_veh >= 1 or adj_foot >= 2)) or adj_veh >= 3:
					cond = true
					by = first
					need = bust_time_vehicle
	if cond:
		_bust_t += dt
		if _bust_t >= need:
			_do_arrest(by)
	else:
		_bust_t = maxf(_bust_t - dt * 1.5, 0.0)


func _is_surrendering(p: Node, spd: float) -> bool:
	if spd > 0.7 or _flag(p, "aiming"):
		return false
	if _t - _last_aggr_t < 4.0:
		return false
	var w: Variant = p.get("weapons")
	if w != null and is_instance_valid(w) and w.has_method("is_armed") and bool(w.is_armed()):
		return false
	return true


func _do_arrest(by: Node) -> void:
	if _busted or _dead:
		return
	var p := _player()
	if p == null:
		return
	_busted = true
	_bust_t = 0.0
	if p.has_method("arrest"):
		p.call("arrest", by)
	else:
		Events.player_busted.emit()


# =====================================================================================================================================
#  Optional: officer hails an unarmed 1-star suspect
# =====================================================================================================================================
func _tick_hail(dt: float) -> void:
	_hail_cd = maxf(_hail_cd - dt, 0.0)
	if not hail_enabled or level != 1 or state == S_CLEAR:
		_hail_until = -1.0
		return
	var p := _player()
	if p == null or (p.has_method("is_in_vehicle") and p.is_in_vehicle()):
		return
	var spd: float = p.get_speed_xz() if p.has_method("get_speed_xz") else 0.0
	# running away after a hail = resisting
	if _hail_until > _t:
		if spd > 5.5 and is_instance_valid(_hail_officer):
			var hd := Util.dist_xz((_hail_officer as Node3D).global_position, p.global_position)
			if hd > 14.0:
				_hail_until = -1.0
				report_crime(GC.CRIME_RESIST_ARREST, p.global_position, p, true)
		return
	if _hail_cd > 0.0 or _t - _last_aggr_t < 5.0 or _t - _last_crime_applied_t < 5.0:
		return
	var w: Variant = p.get("weapons")
	if w != null and is_instance_valid(w) and w.has_method("is_armed") and bool(w.is_armed()):
		return
	for rec in _near_officers:
		var o: Variant = rec["node"]
		if is_instance_valid(o) and bool(rec["los"]) and float(rec["d"]) <= 16.0:
			_hail_cd = 18.0
			_hail_until = _t + 10.0
			_hail_officer = o
			Events.subtitle.emit("Officer: Freeze! Hands where I can see them!", 3.2)
			return
