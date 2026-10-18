class_name CombatBrain
extends RefCounted
## Reusable on-foot combat controller used by police patrol officers, SWAT, snipers and gang NPCs (Police-B).
##
##  * target selection: the player first (when hostile / forced), then hostile factions (`target_groups`)
##  * perception: line-of-sight rays to chest / head, distance, 120 deg field of view (all-round awareness once alerted),
##    hearing through Events.gunshot, memory of the last seen position (`memory`, ~8 s), group alerts within `alert_radius`
##  * movement: approach to a preferred range band, strafe / back-pedal, cover (CoverFinder), peek + burst fire, reload in cover,
##    switch cover when flanked, flank (SWAT), retreat when hurt, melee when adjacent, vehicle dodge, search of the last known position
##  * shooting through WeaponController (aim_at_point + set_trigger / fire_once, burst timing, `accuracy` with distance falloff,
##    friendly-fire / blocked-shot check, grenades)
##  * movement itself is CombatMover (steering + ped-graph routes + stuck detection)
##
## The owner (CombatActor) calls tick(dt) every physics frame (dt may be larger when it skips frames) and forwards on_damaged().
## Cost is tiered by `lod` (0 near / 1 mid / 2 far); the whole police force stays far below 3 ms (see PoliceUnits.stats()).

signal target_sighted(target: Node, pos: Vector3, first_time: bool)
signal target_lost(last_pos: Vector3)
signal state_changed(new_state: int, old_state: int)
signal grenade_thrown()
signal burst_started()
signal heard_shot(source: Node, pos: Vector3, distance: float)       # any gunshot in earshot (even with combat disabled)

enum State { IDLE, SEARCH, APPROACH, ENGAGE, COVER_MOVE, COVER_HIDE, COVER_PEEK, FLANK, RETREAT, MELEE, HOLD }
const STATE_NAMES: Array[String] = ["idle", "search", "approach", "engage", "cover_move", "cover_hide", "cover_peek", "flank",
	"retreat", "melee", "hold"]

const PERC_INTERVAL: Array[float] = [0.18, 0.45, 1.0]
const DECIDE_INTERVAL: Array[float] = [0.1, 0.22, 0.5]

static var units: Array = []
static var stat_usec := 0
static var stat_ticks := 0
static var cover_queries := 0
static var _hooked := false
static var _cover_frame := -1
static var _cover_used := 0

# ---- configuration (owner sets after setup) ------------------------------------------------------------------------------
var enabled := true                 # false: no ticking at all (owner moves the body itself)
var combat_enabled := true          # false: perception only (e.g. patrol officers at 0 stars)
var shoot_allowed := true
var aim_without_fire := false       # arrest "freeze": point the weapon but never pull the trigger
var hold_position := false          # stay where we are (roadblock guards, snipers)
var hold_stance: StringName = &"stand"
var accuracy := 0.5                 # 0..1 base accuracy (WeaponController: spread x lerp(3.2, 0.75, acc))
var sight_range := 70.0
var alert_range := 26.0             # once alerted the all-round awareness radius
var fov_deg := 120.0
var hearing := 1.0                  # multiplier on the gunshot loudness radius
var memory := 8.0
var reaction_time := 0.5
var pref_min := 8.0
var pref_max := 22.0
var weapon_range := 60.0
var use_cover := true
var cover_bias := 0.55
var flank := false
var grenades := false
var can_melee := true
var melee_enter := 2.3
var retreat_hp := 0.0               # health fraction below which the unit may retreat
var retreat_chance := 0.0
var alert_radius := 40.0
var aggression := 0.5
var burst_shots := Vector2i(1, 3)
var burst_time := Vector2(0.35, 0.9)
var burst_pause := Vector2(0.55, 1.5)
var search_time := 14.0
var target_groups: Array[StringName] = []
var forced_target: Node = null
var lod := 0
var dodge_vehicles := true
var seated_fire := false            # may shoot out of a vehicle seat (passengers)

# ---- state ------------------------------------------------------------------------------------------------------------------
var npc: CharacterBase = null
var mover: CombatMover = null
var state: int = State.IDLE
var target: Node = null
var target_visible := false
var last_seen_pos := Vector3.INF
var last_seen_vel := Vector3.ZERO
var last_seen_t := -100.0
var visible_since := -100.0
var shots_fired := 0
var bursts := 0
var in_combat := false              # sighted / tracked a target recently (used by owners to draw weapons)
var cover: Dictionary = {}
var stance_want: StringName = &"stand"

var _now := 0.0
var _perc_t := 0.0
var _decide_t := 0.0
var _scan_t := 0.0
var _state_t := 0.0
var _alert_until := -100.0
var _search_pos := Vector3.INF
var _search_until := -100.0
var _search_yaw := 0.0
var _aim_pt := Vector3.ZERO
var _aim_valid := false
var _aim_err := Vector3.ZERO
var _aim_ready_at := 0.0
var _fire_phase := 0                # 0 rest, 1 burst, 2 pause
var _phase_until := 0.0
var _shots_left := 0
var _next_shot_t := 0.0
var _shot_clear_ok := true
var _clear_t := 0.0
var _last_hurt := -100.0
var _hurt_acc := 0.0
var _hide_until := 0.0
var _peek_until := 0.0
var _peek_reached_t := -1.0
var _cover_cd := 0.0
var _since_cover := 0.0
var _strafe_until := 0.0
var _strafe_dir := 1.0
var _engage_still := false
var _retreat_until := 0.0
var _retreat_done := false
var _flank_pos := Vector3.INF
var _flank_until := 0.0
var _flank_cd := 0.0
var _next_grenade := 0.0
var _busy_until := 0.0
var _dodge_until := 0.0
var _dodge_dir := Vector3.ZERO
var _melee_next := 0.0
var _melee_weapon_swapped := false
var _melee_prev: StringName = &""
var _alerted_group_t := -100.0
var _cands: Array = []
var _q := PhysicsRayQueryParameters3D.new()
var _stagger := 0.0


func setup(owner_npc: CharacterBase, owner_mover: CombatMover, cfg: Dictionary = {}) -> void:
	npc = owner_npc
	mover = owner_mover
	for k in cfg:
		set(k, cfg[k])
	_stagger = float(npc.get_instance_id() % 97) / 97.0
	_perc_t = _stagger * 0.3
	_decide_t = _stagger * 0.2
	units.append(self)
	if not _hooked:
		_hooked = true
		Events.gunshot.connect(CombatBrain._on_gunshot)


func dispose() -> void:
	units.erase(self)
	if npc != null:
		CoverFinder.release(npc.get_instance_id())
	var wc = npc.weapons if npc != null else null
	if wc != null and is_instance_valid(wc):
		wc.set_trigger(false)


# =====================================================================================================================
# Public API
# =====================================================================================================================
func get_state_name() -> String:
	return STATE_NAMES[state]


func is_engaged() -> bool:
	return state != State.IDLE and state != State.SEARCH


func has_target() -> bool:
	return target != null and is_instance_valid(target)


func set_target(t: Node) -> void:
	target = t
	forced_target = t


## Forgets a remembered target when no fight is going on (order changes).
func clear_target_memory_if_idle() -> void:
	if not in_combat and not target_visible:
		target = null
		_search_pos = Vector3.INF
		if state == State.SEARCH:
			_set_state(State.IDLE)


func clear_target() -> void:
	target = null
	forced_target = null
	target_visible = false
	_set_state(State.IDLE)


## Go and look at a position (heard something / ordered search). The unit scans around when it arrives.
func investigate(pos: Vector3, seconds: float = -1.0) -> void:
	_search_pos = pos
	_search_until = _now + (search_time if seconds < 0.0 else seconds)
	_alert_until = maxf(_alert_until, _now + 6.0)
	if not (state in [State.APPROACH, State.ENGAGE, State.COVER_MOVE, State.COVER_HIDE, State.COVER_PEEK, State.FLANK, State.MELEE, State.RETREAT]):
		_set_state(State.SEARCH)


func receive_alert(pos: Vector3, source: Node) -> void:
	if npc.is_dead or not combat_enabled:
		return
	_alert_until = _now + memory
	if source != null and is_instance_valid(source) and (target == null or not target_visible):
		if npc.is_hostile_to(source) or source == forced_target:
			target = source
			if last_seen_pos == Vector3.INF or _now - last_seen_t > 2.0:
				last_seen_pos = pos
				last_seen_t = _now - 3.0
	if state == State.IDLE or state == State.SEARCH:
		investigate(pos, search_time)


func on_damaged(amount: float, info: Dictionary) -> void:
	_last_hurt = _now
	_hurt_acc += amount
	mover.speed_scale = 0.55
	var src: Node = info.get("source", null)
	if src != null and is_instance_valid(src) and src != npc and (npc.is_hostile_to(src) or src == forced_target):
		if target == null or not target_visible or not is_instance_valid(target):
			target = src
			last_seen_pos = (src as Node3D).global_position
			last_seen_t = _now - 1.0
		_alert_until = _now + memory
		if not in_combat:
			_alert_group(target, last_seen_pos)
		in_combat = true
	if state == State.IDLE or state == State.SEARCH:
		_set_state(State.APPROACH if combat_enabled else State.IDLE)
	elif state == State.COVER_PEEK:
		_to_hide()
	elif state == State.HOLD:
		pass


func describe() -> String:
	return "%s tgt=%s vis=%s dist=%.1f cover=%s" % [get_state_name(), str(target.name) if has_target() else "-", str(target_visible),
		_tdist(), str(cover.get("kind", "-"))]


# =====================================================================================================================
# Tick
# =====================================================================================================================
func tick(dt: float) -> void:
	if npc == null or not enabled:
		return
	var t0 := Time.get_ticks_usec()
	_now += dt
	if mover.speed_scale < 1.0:
		mover.speed_scale = minf(mover.speed_scale + dt * 2.2, 1.0)
	_perc_t -= dt
	if _perc_t <= 0.0:
		_perc_t = PERC_INTERVAL[clampi(lod, 0, 2)] * (0.85 + _stagger * 0.3)
		_perceive()
	_decide_t -= dt
	if _decide_t <= 0.0:
		_decide_t = DECIDE_INTERVAL[clampi(lod, 0, 2)]
		_decide()
	_state_t += dt
	_act(dt)
	stat_usec += Time.get_ticks_usec() - t0
	stat_ticks += 1


## Driver / passenger of a vehicle: perception + drive-by shooting from seats that allow it (no walking).
func tick_seated(dt: float) -> void:
	if npc == null or not enabled:
		return
	var t0 := Time.get_ticks_usec()
	_now += dt
	_perc_t -= dt
	if _perc_t <= 0.0:
		_perc_t = PERC_INTERVAL[clampi(lod, 0, 2)] * (0.85 + _stagger * 0.3)
		_perceive()
	var wc = npc.weapons
	var v = npc.current_vehicle
	var dist := _tdist()
	var ok := false
	if wc != null and v != null and is_instance_valid(v) and combat_enabled and shoot_allowed and seated_fire and has_target() and target_visible 			and dist < 42.0 and v.has_method("can_shoot_from_seat") and v.can_shoot_from_seat(npc.seat_index) and wc.can_fire_from_vehicle():
		ok = true
	if ok:
		_update_aim_and_fire(dt, dist)
	elif wc != null and (wc.is_aiming or _fire_phase != 0):
		wc.set_trigger(false)
		wc.clear_ai_aim()
		_fire_phase = 0
		_aim_valid = false
	stat_usec += Time.get_ticks_usec() - t0
	stat_ticks += 1


# =====================================================================================================================
# Perception
# =====================================================================================================================
func _gather() -> void:
	_cands.clear()
	var tree := npc.get_tree()
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and not pl.is_dead:
		if npc.is_hostile_to(pl) or pl == forced_target:
			_cands.append(pl)
	for g in target_groups:
		for n in tree.get_nodes_in_group(g):
			if n == npc or not (n is CharacterBase):
				continue
			var cb: CharacterBase = n
			if cb.is_dead or not npc.is_hostile_to(cb):
				continue
			if cb.global_position.distance_squared_to(npc.global_position) < sight_range * sight_range * 1.5:
				_cands.append(cb)
	if forced_target != null and is_instance_valid(forced_target) and not _cands.has(forced_target) and not (forced_target.get("is_dead") == true):
		_cands.append(forced_target)


func _perceive() -> void:
	if not combat_enabled and forced_target == null and target_groups.is_empty() and not _wants_player_sight():
		return
	_gather()
	var eye := npc.global_position + Vector3(0, 1.6, 0)
	var best: Node = null
	var best_score := INF
	for c in _cands:
		if _can_see(c, eye):
			var d := eye.distance_to(_chest(c))
			var score := d * (0.75 if c == Game.player else 1.0)
			if c == target:
				score *= 0.8            # stick to the current target
			if score < best_score:
				best_score = score
				best = c
	if best != null:
		var first_sight := (not target_visible) or best != target
		if first_sight:
			visible_since = _now
			if _now - last_seen_t > 1.2:
				_aim_ready_at = _now + reaction_time * randf_range(0.7, 1.3)
				_aim_valid = false
		var fresh := _now - last_seen_t > 3.0 or best != target
		target = best
		target_visible = true
		var cp := _chest(best)
		last_seen_vel = _vel_of(best)
		last_seen_pos = Vector3(cp.x, (best as Node3D).global_position.y, cp.z)
		last_seen_t = _now
		_alert_until = _now + memory
		in_combat = true
		if fresh:
			target_sighted.emit(best, last_seen_pos, true)
			_alert_group(best, last_seen_pos)
			_since_cover = maxf(_since_cover, 12.0)      # first contact: look for cover right away instead of walking into the open
		elif first_sight:
			target_sighted.emit(best, last_seen_pos, false)
	else:
		target_visible = false
		if target != null:
			var gone: bool = (not is_instance_valid(target)) or target.get("is_dead") == true
			if gone or _now - last_seen_t > memory:
				_lose_target(gone)


func _wants_player_sight() -> bool:
	var pl = Game.player
	return pl != null and is_instance_valid(pl) and npc.is_hostile_to(pl)


func _lose_target(dead: bool) -> void:
	var lp := last_seen_pos
	target = null
	target_visible = false
	in_combat = false
	CoverFinder.release(npc.get_instance_id())
	cover = {}
	if not dead and lp != Vector3.INF:
		target_lost.emit(lp)
		if combat_enabled:
			investigate(lp, search_time)
			return
	_set_state(State.IDLE)


func _chest(c) -> Vector3:
	# untyped on purpose: a target freed between two ticks must not raise "previously freed" at the call
	if c == null or not is_instance_valid(c):
		return last_seen_pos if last_seen_pos != Vector3.INF else npc.global_position + Vector3(0, 1.2, 0)
	if c.has_method("get_chest_position"):
		return c.get_chest_position()
	return (c as Node3D).global_position + Vector3(0, 1.2, 0)


func _vel_of(c: Node) -> Vector3:
	var v = c.get("current_vehicle")
	if v != null and is_instance_valid(v) and v.get("linear_velocity") != null:
		return v.linear_velocity
	var vel = c.get("velocity")
	if vel is Vector3:
		return vel
	return Vector3.ZERO


func _can_see(c: Node, eye: Vector3) -> bool:
	var cp := _chest(c)
	var to := cp - eye
	var d := to.length()
	var rng := sight_range
	if Game.is_night():
		rng *= 0.7
	if c.get("crouching") == true:
		rng *= 0.7
	if d > rng:
		return false
	var alerted := _now < _alert_until
	if d > 5.0 and not (alerted and d < alert_range):
		var fwd := -npc.global_transform.basis.z
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > 0.1 and fwd.dot(flat.normalized()) < cos(deg_to_rad(fov_deg * 0.5)):
			return false
	var space := npc.get_world_3d().direct_space_state
	_q.collision_mask = GC.M_LOS
	_q.exclude = [npc.get_rid()]
	_q.from = eye
	_q.to = cp
	if space.intersect_ray(_q).is_empty():
		return true
	_q.to = (c as Node3D).global_position + Vector3(0, 1.68, 0)
	return space.intersect_ray(_q).is_empty()


func _on_gunshot_heard(pos: Vector3, _loud: float, source: Node, d: float) -> void:
	heard_shot.emit(source, pos, d)
	if not combat_enabled:
		return
	if not (npc.is_hostile_to(source) or source == forced_target):
		return
	var err := d * 0.06
	var p := pos + Vector3(randf_range(-err, err), 0.0, randf_range(-err, err))
	_alert_until = _now + memory
	if target == null or not target_visible:
		if target == null:
			target = source
		last_seen_pos = Vector3(p.x, (source as Node3D).global_position.y, p.z)
		last_seen_t = _now - 2.5
		if state == State.IDLE or state == State.SEARCH:
			investigate(last_seen_pos, search_time)


static func _on_gunshot(pos: Vector3, loudness: float, source: Node) -> void:
	if source == null or not (source is Node3D):
		return
	for b in units:
		var bb: CombatBrain = b
		if bb.npc == null or not is_instance_valid(bb.npc) or bb.npc == source or bb.npc.is_dead:
			continue
		var d := bb.npc.global_position.distance_to(pos)
		if d > loudness * bb.hearing:
			continue
		bb._on_gunshot_heard(pos, loudness, source, d)


func _alert_group(t: Node, pos: Vector3) -> void:
	if _now - _alerted_group_t < 1.5:
		return
	_alerted_group_t = _now
	var r2 := alert_radius * alert_radius
	for b in units:
		var bb: CombatBrain = b
		if bb == self or bb.npc == null or not is_instance_valid(bb.npc) or bb.npc.is_dead:
			continue
		if bb.npc.faction != npc.faction:
			continue
		if bb.npc.global_position.distance_squared_to(npc.global_position) > r2:
			continue
		bb.receive_alert(pos, t)


func _tdist() -> float:
	var p := _tpos()
	if p == Vector3.INF:
		return INF
	return Util.dist_xz(p, npc.global_position)


## Best known position of the target (live when visible, last seen otherwise).
func _tpos() -> Vector3:
	if has_target() and target_visible:
		return (target as Node3D).global_position
	return last_seen_pos


# =====================================================================================================================
# Decisions
# =====================================================================================================================
func _set_state(s: int) -> void:
	if s == state:
		return
	var old := state
	state = s
	_state_t = 0.0
	if old == State.MELEE:
		_restore_weapon()
	if s in [State.IDLE, State.SEARCH]:
		in_combat = in_combat and has_target()
	state_changed.emit(s, old)


func _decide() -> void:
	if npc.is_dead:
		return
	stance_want = &"stand"
	if _now < _dodge_until:
		return
	if dodge_vehicles and lod == 0 and _check_dodge():
		return
	if not combat_enabled:
		if state != State.IDLE and state != State.SEARCH:
			_set_state(State.IDLE)
		return
	var tracked := has_target() and (_now - last_seen_t) < memory + 1.0
	if not tracked:
		if _search_pos != Vector3.INF and _now < _search_until:
			if state != State.SEARCH:
				_set_state(State.SEARCH)
		else:
			_search_pos = Vector3.INF
			if state != State.IDLE:
				_set_state(State.IDLE)
		return
	_search_pos = Vector3.INF
	var tpos := _tpos()
	var dist := Util.dist_xz(tpos, npc.global_position)
	var hp_frac := npc.health / maxf(npc.max_health, 1.0)
	var wc = npc.weapons
	if _now < _busy_until:
		return
	# ---- retreat when badly hurt
	if retreat_hp > 0.0 and hp_frac < retreat_hp and not _retreat_done and state != State.RETREAT:
		_retreat_done = true                                  # the decision is made once, when the health first drops below the threshold
		if randf() < retreat_chance:
			_retreat_until = _now + randf_range(4.0, 7.5)
			CoverFinder.release(npc.get_instance_id())
			cover = {}
			_set_state(State.RETREAT)
			return
	if state == State.RETREAT:
		if _now > _retreat_until:
			_set_state(State.ENGAGE)
		else:
			return
	# ---- held position (roadblock guard, sniper)
	if hold_position:
		if state != State.HOLD:
			_set_state(State.HOLD)
		stance_want = hold_stance
		_maybe_grenade(dist)
		return
	# ---- melee
	var melee_ok := can_melee and wc != null and (dist < melee_enter or (state == State.MELEE and dist < melee_enter + 1.5))
	if melee_ok and (target_visible or dist < 1.8):
		if state != State.MELEE:
			_set_state(State.MELEE)
			_swap_to_melee()
		return
	if state == State.MELEE and dist >= melee_enter + 1.5:
		_set_state(State.ENGAGE)
	# ---- grenades (SWAT)
	if _maybe_grenade(dist):
		return
	# ---- cover cycle
	if state in [State.COVER_MOVE, State.COVER_HIDE, State.COVER_PEEK]:
		_decide_cover(dist)
		return
	_since_cover += _decide_dt()
	if use_cover and target_visible and dist > 6.0 and dist < weapon_range * 0.9:
		var hurt_recent := _now - _last_hurt < 2.5
		var need_reload: bool = wc != null and wc.is_firearm_equipped() and wc.get_ammo_in_mag() <= maxi(wc.get_mag_capacity() / 5, 1)
		var want: bool = hurt_recent or need_reload or _since_cover > randf_range(5.0, 11.0) * (1.4 - cover_bias)
		if want and randf() < cover_bias + (0.25 if hurt_recent else 0.0):
			if _try_cover():
				_since_cover = 0.0
				_set_state(State.COVER_MOVE)
				return
	# ---- flank (SWAT): when the target is not exposed or we are stuck in a stalemate
	if flank and _now > _flank_cd and dist > 10.0 and dist < weapon_range:
		if (not target_visible and _now - last_seen_t > 1.5) or (state == State.ENGAGE and _state_t > 5.0 and randf() < 0.25):
			if _pick_flank(tpos):
				_flank_cd = _now + randf_range(9.0, 15.0)
				_set_state(State.FLANK)
				return
	if state == State.FLANK:
		if _now > _flank_until or (mover.arrived and _flank_pos != Vector3.INF):
			_set_state(State.ENGAGE)
		else:
			return
	# ---- range band
	if dist > pref_max * 1.1 or not target_visible and dist > 4.0:
		if state != State.APPROACH:
			_set_state(State.APPROACH)
	else:
		if state != State.ENGAGE:
			_set_state(State.ENGAGE)


func _decide_dt() -> float:
	return DECIDE_INTERVAL[clampi(lod, 0, 2)]


func _decide_cover(dist: float) -> void:
	var wc = npc.weapons
	match state:
		State.COVER_MOVE:
			if cover.is_empty():
				_set_state(State.ENGAGE)
				return
			if mover.arrived or Util.dist_xz(cover["pos"], npc.global_position) < 0.8:
				_set_state(State.COVER_HIDE)
				_hide_until = _now + randf_range(0.9, 2.2)
			elif _state_t > 7.0 or mover.fatal_stuck:
				_leave_cover()
				_set_state(State.ENGAGE)
		State.COVER_HIDE:
			if cover.is_empty():
				_set_state(State.ENGAGE)
				return
			stance_want = &"cover_low" if cover["kind"] == &"low" else &"cover_high"
			var reloading: bool = wc != null and wc.is_reloading
			# flanked: the spot no longer protects us from where the target is now
			if _state_t > 0.35 and has_target() and last_seen_pos != Vector3.INF:
				if int(_state_t * 10.0) % 4 == 0 and not CoverFinder.is_protected(npc, cover["pos"], last_seen_pos, [npc], cover["kind"] == &"low"):
					_leave_cover()
					if _try_cover():
						_set_state(State.COVER_MOVE)
					else:
						_set_state(State.ENGAGE)
					return
			if wc != null and wc.is_firearm_equipped() and not reloading and wc.get_ammo_in_mag() < maxi(int(wc.get_mag_capacity() * 0.55), 2) \
					and wc.get_ammo_reserve() > 0 and _state_t > 0.3:
				wc.start_reload()
				_hide_until = maxf(_hide_until, _now + 0.6)
			if _now >= _hide_until and not reloading:
				if not target_visible and _now - last_seen_t > 4.0:
					# nobody to shoot at: stay down a bit then re-evaluate
					if _state_t > 6.0:
						_leave_cover()
						_set_state(State.APPROACH)
					return
				_set_state(State.COVER_PEEK)
				_peek_until = _now + randf_range(1.3, 2.8)
				_peek_reached_t = -1.0
		State.COVER_PEEK:
			if cover.is_empty():
				_set_state(State.ENGAGE)
				return
			var empty: bool = wc != null and wc.is_firearm_equipped() and wc.get_ammo_in_mag() <= 0
			if _now >= _peek_until or empty:
				_to_hide()
			elif not target_visible and _state_t > 1.4:
				_to_hide()


func _to_hide() -> void:
	if cover.is_empty():
		_set_state(State.ENGAGE)
		return
	_set_state(State.COVER_MOVE)       # walk back to the protected spot (arrives immediately when already there)
	_hide_until = _now + randf_range(0.8, 2.0)


func _leave_cover() -> void:
	CoverFinder.release(npc.get_instance_id())
	cover = {}


func _try_cover() -> bool:
	if _now < _cover_cd:
		return false
	_cover_cd = _now + 1.2
	var fr := Engine.get_physics_frames()
	if _cover_frame != fr:
		_cover_frame = fr
		_cover_used = 0
	if _cover_used >= 2:
		_cover_cd = _now + 0.1
		return false
	_cover_used += 1
	cover_queries += 1
	var tp := _tpos()
	if tp == Vector3.INF:
		return false
	var res := CoverFinder.find(npc, npc.global_position, tp, {"radius": 15.0, "range": weapon_range, "id": npc.get_instance_id(),
		"prefer_min": pref_min, "prefer_max": pref_max, "exclude": [npc], "max": 2})
	if res.is_empty():
		return false
	var best: Dictionary = res[0]
	if float(best["score"]) < -19.0:
		return false
	cover = best
	CoverFinder.claim(npc.get_instance_id(), best["pos"])
	return true


func _pick_flank(tpos: Vector3) -> bool:
	var to := npc.global_position - tpos
	to.y = 0.0
	if to.length() < 1.0:
		return false
	var side := 1.0 if (npc.get_instance_id() % 2 == 0) else -1.0
	for attempt in 3:
		var ang := deg_to_rad(randf_range(55.0, 95.0)) * side * (1.0 if attempt < 2 else -1.0)
		var dist := clampf(Util.dist_xz(tpos, npc.global_position) * 0.85, pref_min, pref_max)
		var dir := Util.yaw_to_dir(Util.dir_to_yaw(to.normalized()) + ang)
		var p := tpos + dir * dist
		var gq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 4, 0), p + Vector3(0, -4, 0), GC.L_WORLD)
		var g := npc.get_world_3d().direct_space_state.intersect_ray(gq)
		if g.is_empty():
			continue
		var gp: Vector3 = g["position"]
		if absf(gp.y - npc.global_position.y) > 1.5 or WorldLayout.is_water(gp.x, gp.z):
			continue
		_flank_pos = gp
		_flank_until = _now + 9.0
		return true
	return false


func _maybe_grenade(dist: float) -> bool:
	if not grenades or _now < _next_grenade or not has_target():
		return false
	var wc = npc.weapons
	if wc == null or not wc.has_weapon(&"grenade") or dist < 11.0 or dist > 30.0:
		return false
	if _now - last_seen_t > 3.0:
		return false
	# throw when the target is not directly exposed or after a long exchange
	if target_visible and _state_t < 4.0 and state != State.COVER_HIDE:
		return false
	var tp := _tpos()
	var from := npc.global_position + Vector3(0, 1.6, 0)
	var dir := (tp + Vector3(0, 1.0, 0) - from)
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	_q.collision_mask = GC.L_WORLD
	_q.exclude = [npc.get_rid()]
	_q.from = from
	_q.to = from + flat * 3.5 + Vector3(0, 0.8, 0)
	if not npc.get_world_3d().direct_space_state.intersect_ray(_q).is_empty():
		return false                 # a wall right in front: it would bounce back
	_next_grenade = _now + randf_range(14.0, 24.0)
	_busy_until = _now + 1.1
	mover.stop()
	mover.face(tp)
	wc.aim_at_point(tp + Vector3(0, 0.8, 0), 1.0)
	if wc.throw_grenade_now():
		grenade_thrown.emit()
		return true
	return false


func _swap_to_melee() -> void:
	var wc = npc.weapons
	if wc == null:
		return
	_melee_prev = wc.current_id
	_melee_weapon_swapped = false
	if wc.is_firearm_equipped():
		for id in [&"bat", &"crowbar", &"knife"]:
			if wc.has_weapon(id):
				wc.equip(id)
				_melee_weapon_swapped = true
				break


func _restore_weapon() -> void:
	var wc = npc.weapons
	if wc != null and _melee_weapon_swapped and _melee_prev != &"" and wc.has_weapon(_melee_prev):
		wc.equip(_melee_prev)
	_melee_weapon_swapped = false


func _check_dodge() -> bool:
	var pos := npc.global_position
	var cand: Array = []
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and pl.get("current_vehicle") != null and is_instance_valid(pl.current_vehicle):
		cand.append(pl.current_vehicle)
	for v in npc.get_tree().get_nodes_in_group(GC.G_VEHICLE):
		if not cand.has(v) and v is VehicleBase and (v as VehicleBase).get_speed() > 7.0:
			if (v as Node3D).global_position.distance_squared_to(pos) < 18.0 * 18.0:
				cand.append(v)
	for v in cand:
		var vb: VehicleBase = v
		if vb.get_speed() < 6.5 or vb == npc.current_vehicle:
			continue
		var rel := pos - vb.global_position
		rel.y = 0.0
		var vel := vb.linear_velocity
		vel.y = 0.0
		var sp := vel.length()
		var dist := rel.length()
		if dist > 16.0 or dist < 0.5:
			continue
		var along := rel.dot(vel / sp)
		if along < 0.0 or along > sp * 1.6 + 3.0:
			continue
		var lateral := (rel - (vel / sp) * along).length()
		if lateral > 2.6:
			continue
		var side := (vel / sp).cross(Vector3.UP)
		_dodge_dir = side * (1.0 if side.dot(rel) >= 0.0 else -1.0)
		_dodge_until = _now + 0.9
		mover.sprinting = true
		return true
	return false


# =====================================================================================================================
# Acting (every frame)
# =====================================================================================================================
func _act(dt: float) -> void:
	var pos := npc.global_position
	var wc = npc.weapons
	var tpos := _tpos()
	var dist := Util.dist_xz(tpos, pos) if tpos != Vector3.INF else INF
	if _now < _dodge_until:
		mover.set_goal(pos + _dodge_dir * 4.0, mover.sprint_speed, 0.3)
		mover.clear_face()
		mover.tick(dt)
		return
	mover.sprinting = false
	match state:
		State.IDLE:
			pass
		State.SEARCH:
			_act_search(dt)
		State.APPROACH:
			var sp := mover.run_speed
			if dist > 26.0:
				mover.sprinting = true
				sp = mover.sprint_speed
			var arrive := maxf(pref_max * 0.75, 1.5)
			if last_seen_pos != Vector3.INF:
				mover.set_goal(last_seen_pos, sp, arrive)
			if target_visible and dist < 45.0:
				mover.face(_chest(target))
			else:
				mover.clear_face()
		State.ENGAGE:
			_act_engage(dt, dist)
		State.COVER_MOVE:
			if not cover.is_empty():
				var cp: Vector3 = cover["pos"]
				var dd := Util.dist_xz(cp, pos)
				mover.sprinting = dd > 7.0
				mover.set_goal(cp, mover.sprint_speed if dd > 7.0 else mover.run_speed, 0.45)
				if target_visible:
					mover.face(_chest(target))
				else:
					mover.clear_face()
		State.COVER_HIDE:
			mover.stop()
			if not cover.is_empty():
				mover.face_direction(Util.dir_to_yaw(cover["normal"]))
		State.COVER_PEEK:
			_act_peek(dt)
		State.FLANK:
			if _flank_pos != Vector3.INF:
				mover.sprinting = true
				mover.set_goal(_flank_pos, mover.sprint_speed, 1.5)
			if target_visible and dist < pref_max * 1.3:
				mover.face(_chest(target))
			else:
				mover.clear_face()
		State.RETREAT:
			if tpos != Vector3.INF:
				var away := pos - tpos
				away.y = 0.0
				away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
				mover.sprinting = true
				mover.set_goal(pos + away * 14.0, mover.sprint_speed, 1.0)
				mover.clear_face()
		State.MELEE:
			if tpos != Vector3.INF:
				mover.set_goal(tpos, mover.run_speed, 1.1)
				mover.face(tpos)
				if dist < 2.1 and _now >= _melee_next and wc != null and (target_visible or dist < 1.4):
					_melee_next = _now + randf_range(0.7, 1.2)
					wc.aim_at_point(_chest(target) if has_target() else tpos, 1.0)
					wc.melee_attack(randf() < 0.2)
		State.HOLD:
			mover.stop()
			if target_visible and has_target():
				mover.face(_chest(target))
	_update_aim_and_fire(dt, dist)
	mover.tick(dt)


func _act_search(dt: float) -> void:
	if _search_pos == Vector3.INF:
		return
	# a far search point is reached at a jog / sprint, the last stretch at a cautious walk
	var d_goal := Util.dist_xz(_search_pos, npc.global_position)
	var sp := mover.run_speed * 0.62
	if d_goal > 60.0:
		mover.sprinting = true
		sp = mover.sprint_speed
	elif d_goal > 22.0:
		sp = mover.run_speed
	mover.set_goal(_search_pos, sp, 1.8)
	mover.clear_face()
	if mover.arrived:
		# look around
		_search_yaw += dt * 1.1
		mover.face_direction(npc.rotation.y + sin(_search_yaw) * 1.2)
		if _now > _search_until:
			_search_pos = Vector3.INF
			_set_state(State.IDLE)
			in_combat = false


func _act_engage(dt: float, dist: float) -> void:
	var pos := npc.global_position
	var tpos := _tpos()
	if tpos == Vector3.INF:
		return
	mover.face(_chest(target) if target_visible and has_target() else tpos)
	if _now >= _strafe_until:
		_strafe_until = _now + randf_range(1.2, 2.8)
		_strafe_dir = 1.0 if randf() < 0.5 else -1.0
		_engage_still = randf() < 0.3 + (0.2 if _fire_phase == 1 else 0.0)
	if mover.stuck:
		_strafe_dir = -_strafe_dir
		_engage_still = false
	var to := tpos - pos
	to.y = 0.0
	var tdir := to.normalized() if to.length() > 0.1 else Vector3(0, 0, -1)
	var tang := Vector3(-tdir.z, 0.0, tdir.x) * _strafe_dir
	var goal := pos
	var spd := 2.3
	if dist < pref_min:
		goal = pos - tdir * 4.0 + tang * 1.5
		spd = 3.2
		_engage_still = false
	elif dist > pref_max:
		goal = pos + tdir * 4.0 + tang * 1.0
		spd = mover.run_speed * 0.8
		_engage_still = false
	elif not _engage_still:
		goal = pos + tang * 3.0
	if goal.distance_to(pos) < 0.3:
		mover.stop()
	else:
		mover.set_goal(goal, spd, 0.4)
	if not target_visible and _state_t > 1.0 and last_seen_pos != Vector3.INF:
		mover.set_goal(last_seen_pos, mover.run_speed * 0.8, 2.0)


func _act_peek(_dt: float) -> void:
	if cover.is_empty():
		return
	var peek_pos: Vector3 = cover["peek"]
	if cover["kind"] == &"high" and float(cover["peek_side"]) != 0.0:
		mover.set_goal(peek_pos, 2.4, 0.3)
		if mover.arrived and _peek_reached_t < 0.0:
			_peek_reached_t = _now
	else:
		mover.stop()
		_peek_reached_t = _peek_reached_t if _peek_reached_t >= 0.0 else _now
	if target_visible and has_target():
		mover.face(_chest(target))
	elif last_seen_pos != Vector3.INF:
		mover.face(last_seen_pos)
	# standing up over low cover
	stance_want = &"stand"


# =====================================================================================================================
# Aiming and firing
# =====================================================================================================================
func _can_fire_state() -> bool:
	if npc.is_in_vehicle():
		return true
	match state:
		State.ENGAGE, State.COVER_PEEK, State.HOLD:
			return true
		State.APPROACH, State.FLANK:
			return _tdist() < pref_max * 1.5
		State.COVER_MOVE:
			return target_visible and _tdist() < pref_max * 1.2 and cover.is_empty()
		State.RETREAT:
			return false
	return false


func _update_aim_and_fire(dt: float, dist: float) -> void:
	var wc = npc.weapons
	if wc == null or not is_instance_valid(wc):
		return
	var wants: bool = combat_enabled and has_target() and (target_visible or _now - last_seen_t < 0.7) and _can_fire_state() \
			and _now >= _busy_until and wc.is_firearm_equipped()
	if not wants:
		if _fire_phase != 0:
			wc.set_trigger(false)
			_fire_phase = 0
			_phase_until = _now + 0.2
		if wc.is_aiming and not aim_without_fire:
			wc.clear_ai_aim()
		_aim_valid = false
		return
	# smoothed aim point: lags behind a strafing target a little (reaction), so fast movers get missed more
	var cp := _chest(target)
	if not _aim_valid:
		_aim_pt = cp
		_aim_valid = true
	else:
		_aim_pt = _aim_pt.lerp(cp, 1.0 - exp(-9.0 * dt))
	var acc := accuracy * lerpf(1.0, 0.42, clampf((dist - 8.0) / 55.0, 0.0, 1.0))
	var seen_for := _now - visible_since
	acc *= clampf(0.5 + 0.5 * (seen_for / 1.6), 0.5, 1.0)
	if mover.speed_xz() > 1.5:
		acc *= 0.8
	if last_seen_vel.length() > 9.0:
		acc *= 0.72
	acc *= lerpf(0.85, 1.1, aggression)
	acc = clampf(acc, 0.04, 1.0)
	wc.aim_at_point(_aim_pt + _aim_err, acc)
	if aim_without_fire or not shoot_allowed:
		return
	# clear shot test (friends / walls in the line of fire)
	_clear_t -= dt
	if _clear_t <= 0.0:
		_clear_t = 0.14
		_shot_clear_ok = _shot_clear(cp)
	var eff: Dictionary = wc.get_effective()
	var max_range := minf(weapon_range, float(eff.get("range", weapon_range)) * 0.95)
	var can_fire: bool = _now >= _aim_ready_at and dist < max_range and _shot_clear_ok and not wc.is_reloading
	var def: Dictionary = wc.get_current_def()
	var auto_mode: bool = def.get("mode", &"semi") == &"auto"
	# make sure there are rounds
	if wc.get_ammo_in_mag() <= 0:
		if wc.get_ammo_reserve() <= 0:
			wc.add_ammo(wc.current_id, maxi(wc.get_mag_capacity() * 3, 12))
		if not wc.is_reloading:
			wc.start_reload()
		can_fire = false
	match _fire_phase:
		0:
			if can_fire and _now >= _phase_until:
				_fire_phase = 1
				bursts += 1
				_new_aim_error(cp)
				burst_started.emit()
				if auto_mode:
					_phase_until = _now + randf_range(burst_time.x, burst_time.y)
				else:
					_shots_left = randi_range(burst_shots.x, burst_shots.y)
					_next_shot_t = _now
		1:
			if not can_fire:
				wc.set_trigger(false)
				_fire_phase = 2
				_phase_until = _now + randf_range(0.25, 0.6)
			elif auto_mode:
				wc.set_trigger(true)
				if _now >= _phase_until:
					wc.set_trigger(false)
					_fire_phase = 2
					_phase_until = _now + randf_range(burst_pause.x, burst_pause.y)
			else:
				if _now >= _next_shot_t:
					if wc.fire_once():
						shots_fired += 1
					_shots_left -= 1
					var fr := float(def.get("fire_rate", 4.0))
					_next_shot_t = _now + clampf(1.0 / maxf(fr, 0.2), 0.14, 2.2) * randf_range(1.1, 1.7)
					if _shots_left <= 0:
						_fire_phase = 2
						_phase_until = _now + randf_range(burst_pause.x, burst_pause.y)
		2:
			wc.set_trigger(false)
			if _now >= _phase_until:
				_fire_phase = 0


## Every burst is aimed a little beside the target (a human error of up to ~0.9 m for a poor shot, ~0.1 m for a sniper) on top of the
## weapon spread, so even point-blank fire from a pistol officer is not a laser: rounds crack past the player's ear.
func _new_aim_error(chest: Vector3) -> void:
	var to := chest - npc.global_position
	to.y = 0.0
	if to.length() < 0.1:
		_aim_err = Vector3.ZERO
		return
	var right := to.normalized().cross(Vector3.UP)
	var m := lerpf(0.95, 0.1, clampf(accuracy, 0.0, 1.0)) * (0.35 + 0.65 * sqrt(randf())) * clampf(0.55 + to.length() / 45.0, 0.55, 1.5)
	_aim_err = right * (m * randf_range(-1.0, 1.0)) + Vector3.UP * (m * 0.55 * randf_range(-1.0, 0.8))


## A friendly walking through the line of fire (within ~0.9 m of it, which also covers the aim error and weapon spread) holds the trigger.
func _friend_near_line(eye: Vector3, to: Vector3) -> bool:
	var seg := to - eye
	var len2 := seg.length_squared()
	if len2 < 1.0:
		return false
	for u in units:
		var b: CombatBrain = u
		if b == self or b.npc == null or not is_instance_valid(b.npc) or b.npc.is_dead or b.npc.faction != npc.faction:
			continue
		var c := b.npc.global_position + Vector3(0, 1.1, 0)
		var t := (c - eye).dot(seg) / len2
		if t < 0.03 or t > 0.97:
			continue
		var closest := eye + seg * t
		if closest.distance_squared_to(c) < 0.85 * 0.85:
			return true
	return false


func _shot_clear(target_chest: Vector3) -> bool:
	var eye := npc.global_position + Vector3(0, 1.6, 0)
	var space := npc.get_world_3d().direct_space_state
	_q.collision_mask = GC.L_WORLD | GC.L_NPC | GC.L_PLAYER | GC.L_VEHICLE | GC.L_PROP
	var ex: Array[RID] = [npc.get_rid()]
	if npc.is_in_vehicle() and npc.current_vehicle is CollisionObject3D:
		ex.append((npc.current_vehicle as CollisionObject3D).get_rid())
	_q.exclude = ex
	if _friend_near_line(eye, target_chest):
		return false
	_q.from = eye
	_q.to = eye + (target_chest - eye) * 1.02
	var hit := space.intersect_ray(_q)
	if hit.is_empty():
		return true
	var col: Object = hit["collider"]
	var who: Node = Ballistics.resolve_damageable(col)
	if who == null:
		return false
	if who == target:
		return true
	var tv = target.get("current_vehicle")
	if tv != null and who == tv:
		return true
	if who is CharacterBase and (who as CharacterBase).faction == npc.faction:
		return false
	return true            # an enemy or a neutral thing is in the way: shooting it is fine (cars, civilians are the player's problem)
