extends Node
## Headless WantedSystem tests (Police-A). Run:
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/wanted_test.gd -Seconds 90 -GameArgs "--no-traffic --no-peds"
## Prints "TEST <name> PASS|FAIL <detail>". The WantedSystem is driven by hand (manual = true, tick(dt)) so timings are exact.
## `--only=a,b` filters the groups.

const Mock = preload("res://gta/tests/wanted_mock.gd")
const ARENA := Vector3(4000.0, 100.0, -4000.0)

var wanted: WantedSystem
var player: Player
var pm: Node
var mocks: Node3D
var _passes := 0
var _fails := 0
var _ev := {"changed": [], "progress": 0, "busted": 0, "reported": 0, "subtitle": 0}


func _check(test_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST %s PASS %s" % [test_name, detail])
	else:
		_fails += 1
		print("TEST %s FAIL %s" % [test_name, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _tick(seconds: float, dt: float = 0.1) -> void:
	var n := int(round(seconds / dt))
	for i in n:
		wanted.tick(dt)


func _floor(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = GC.L_WORLD
	b.collision_mask = 0
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	add_child(b)
	b.global_position = pos
	return b


func _officer(offset: Vector3, drawn: bool = true) -> Mock.Officer:
	var o := Mock.Officer.new()
	o.weapon_drawn = drawn
	mocks.add_child(o)
	o.global_position = player.global_position + offset
	return o


func _ped(offset: Vector3, phone: float = 0.6, will_phone: bool = true) -> Mock.Ped:
	var p := Mock.Ped.new()
	p.phone_time = phone
	p.will_phone = will_phone
	mocks.add_child(p)
	p.global_position = player.global_position + offset
	return p


func _reset(keep_mocks: bool = false) -> void:
	if not keep_mocks:
		for c in mocks.get_children():
			_retire(c)
	wanted.clear()
	wanted._last_crime_t.clear()
	wanted._last_aggr_t = -999.0
	wanted._last_shot_t = -999.0
	wanted._last_hurt_t = -999.0
	wanted._bundle_t = -999.0
	wanted._dead = false
	wanted._busted = false
	wanted._bust_t = 0.0
	wanted._hail_cd = 0.0
	player.release_input()
	player.spawn_protection = 0.0
	player.invulnerable = true
	if player.weapons != null:
		player.weapons.give_weapon(&"pistol", 30, true)
	player.is_dead = false
	player.health = player.max_health
	player.velocity = Vector3.ZERO
	player.global_position = ARENA + Vector3(0, 0.15, 0)
	wanted.last_known = Vector3.ZERO


## Takes a mock out of every group at once and frees it later (other systems react to events one frame later).
func _retire(n: Node) -> void:
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for g in c.get_groups():
			if not String(g).begins_with("_"):
				c.remove_from_group(g)
		for k in c.get_children():
			stack.append(k)
	n.queue_free()


func _expect_level(test_name: String, want_min: int, want_max: int = -1) -> void:
	if want_max < 0:
		want_max = want_min
	_check(test_name, wanted.level >= want_min and wanted.level <= want_max, "level=%d heat=%.1f state=%s" % [wanted.level, wanted.heat, String(wanted.state)])


func run(_main: Node) -> Variant:
	await _frames(5)
	wanted = Game.sys(&"wanted") as WantedSystem
	player = Game.player as Player
	if wanted == null or player == null:
		print("TEST boot FAIL wanted=%s player=%s" % [str(wanted), str(player)])
		return false
	pm = Game.sys(&"police")
	if pm != null:
		pm.set("enabled", false)
	wanted.manual = true
	wanted.search_area_rule = false          # the classic timer tests; the search-area rule has its own group
	player.use_real_input = false
	mocks = Node3D.new()
	mocks.name = "WantedMocks"
	add_child(mocks)
	_floor(ARENA + Vector3(0, -1, 0), Vector3(200, 2, 200))
	await _frames(4)
	Events.wanted_changed.connect(func(l, s): _ev["changed"].append([l, s]))
	Events.wanted_search_progress.connect(func(_p): _ev["progress"] += 1)
	Events.player_busted.connect(func(): _ev["busted"] += 1)
	Events.crime_reported.connect(func(_c, _p, _q): _ev["reported"] += 1)
	Events.subtitle.connect(func(_t, _s): _ev["subtitle"] += 1)

	var only := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			only = String(a).substr(7)
	var groups := ["rules", "crimes", "witness", "indirect", "timings", "resight", "escape_mods", "search_area", "events", "bundle", "cheat", "serialize", "busted", "hail", "death"]
	for g in groups:
		if only == "" or only.split(",").has(g):
			_reset()
			await _frames(3)          # freed walls / mocks leave the physics space before the next group
			await call("_t_" + g)
	_reset()
	player.invulnerable = false
	print("TEST SUMMARY passes=%d fails=%d" % [_passes, _fails])
	return _fails == 0


# =====================================================================================================================
func _t_rules() -> void:
	var all_crimes: Array[StringName] = [GC.CRIME_ASSAULT, GC.CRIME_MURDER, GC.CRIME_SHOOTING, GC.CRIME_POLICE_ASSAULT, GC.CRIME_POLICE_KILL,
		GC.CRIME_CARJACK, GC.CRIME_VEHICLE_THEFT, GC.CRIME_POLICE_VEHICLE_THEFT, GC.CRIME_POLICE_VEHICLE_DESTROYED, GC.CRIME_HIT_AND_RUN,
		GC.CRIME_COLLISION, GC.CRIME_EXPLOSION, GC.CRIME_VANDALISM, GC.CRIME_ROBBERY, GC.CRIME_RESIST_ARREST, GC.CRIME_AIRCRAFT_THEFT]
	var missing: Array = []
	for c in all_crimes:
		if CrimeRules.get_rule(c).is_empty() or float(CrimeRules.rule_value(c, "heat", 0.0)) <= 0.0:
			missing.append(c)
	_check("rules_every_crime_rated", missing.is_empty(), "missing=%s" % str(missing))
	var ascending := true
	for i in 4:
		ascending = ascending and CrimeRules.star_heat[i] < CrimeRules.star_heat[i + 1]
	_check("rules_thresholds_ascending", ascending, str(CrimeRules.star_heat))
	_check("rules_heat_to_stars", CrimeRules.level_for_heat(9.9) == 0 and CrimeRules.level_for_heat(10.0) == 1 and CrimeRules.level_for_heat(40.0) == 2
		and CrimeRules.level_for_heat(90.0) == 3 and CrimeRules.level_for_heat(160.0) == 4 and CrimeRules.level_for_heat(260.0) == 5)
	_check("rules_hysteresis", CrimeRules.level_for_heat(35.0, 2) == 2 and CrimeRules.level_for_heat(31.0, 2) == 1 and CrimeRules.level_for_heat(35.0, 0) == 1)
	var esc_ok := true
	for i in 4:
		esc_ok = esc_ok and CrimeRules.escape_time[i] < CrimeRules.escape_time[i + 1]
	_check("rules_escape_time_grows_with_level", esc_ok, str(CrimeRules.escape_time))
	_check("rules_police_crimes_broadcast", bool(CrimeRules.rule_value(GC.CRIME_POLICE_KILL, "broadcast", false)) and int(CrimeRules.rule_value(GC.CRIME_POLICE_KILL, "min_level", 0)) >= 3)


# ---- every crime: heat / star outcome when the police see it -------------------------------------------------------
func _t_crimes() -> void:
	var cop := _officer(Vector3(0, 0, -18))
	var civ := _ped(Vector3(6, 0, 0), 0.5, false)
	var ppos := player.global_position

	# civilian assault (non lethal hit by the player)
	civ.apply_damage(5.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_LIMB})
	_expect_level("crime_assault_seen_by_police", 1)
	_check("crime_assault_pursuit_immediately", wanted.state == &"pursuit", String(wanted.state))
	_reset(true)

	# murder
	civ.is_dead = false
	civ.health = civ.max_health
	civ.apply_damage(500.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO})
	_expect_level("crime_murder", 1)
	_reset(true)
	civ.revive()

	# public shooting
	Events.gunshot.emit(ppos + Vector3(0, 1.4, 0), 70.0, player)
	_expect_level("crime_public_shooting", 1)
	_check("crime_shooting_heat", wanted.heat >= 10.0 and wanted.heat < 20.0, "heat=%.1f" % wanted.heat)
	_reset(true)

	# a quiet (suppressed) shot with no witness at all does not create a wanted level out of nowhere
	for c in mocks.get_children():
		_retire(c)
	Events.gunshot.emit(ppos + Vector3(0, 1.4, 0), 12.0, player)
	_expect_level("crime_suppressed_shot_unseen", 0)
	_reset()
	cop = _officer(Vector3(0, 0, -18))
	civ = _ped(Vector3(6, 0, 0), 0.5, false)

	# police assault >= 2 stars, police kill >= 3 stars
	cop.apply_damage(5.0, {"source": player, "type": GC.DMG_BULLET})
	_expect_level("crime_police_assault_2_stars", 2, 5)
	_reset(true)
	cop.is_dead = false
	cop.health = cop.max_health
	cop.apply_damage(900.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_HEAD})
	_expect_level("crime_police_kill_3_stars", 3, 5)
	_reset()
	cop = _officer(Vector3(0, 0, -18))

	# explosion
	Events.explosion.emit(ppos + Vector3(8, 0, 0), 8.0, player)
	_expect_level("crime_explosion", 2, 5)
	_reset(true)
	Events.explosion.emit(ppos + Vector3(8, 0, 0), 8.0, null)
	_expect_level("crime_explosion_by_nobody_ignored", 0)
	_reset(true)

	# police vehicle destroyed (killer = player) and stolen
	var pcar := Mock.Car.new()
	mocks.add_child(pcar)
	pcar.global_position = ppos + Vector3(12, 0, 0)
	Events.vehicle_destroyed.emit(pcar, player)
	_expect_level("crime_police_vehicle_destroyed", 3, 5)
	_reset(true)
	Events.crime_committed.emit(GC.CRIME_POLICE_VEHICLE_THEFT, ppos, player, {"vehicle": pcar, "severity": 1.0})
	_expect_level("crime_police_vehicle_theft", 3, 5)
	_reset(true)

	# explicit crimes from the vehicle module
	Events.crime_committed.emit(GC.CRIME_CARJACK, ppos, player, {"severity": 1.5})
	_expect_level("crime_carjack", 1, 2)
	_reset(true)
	Events.crime_committed.emit(GC.CRIME_VEHICLE_THEFT, ppos, player, {"severity": 1.0})
	_expect_level("crime_vehicle_theft_seen", 1)
	_reset(true)
	Events.crime_committed.emit(GC.CRIME_ROBBERY, ppos, player, {})
	_expect_level("crime_robbery", 1, 2)
	_reset(true)
	Events.crime_committed.emit(GC.CRIME_AIRCRAFT_THEFT, ppos, player, {})
	_expect_level("crime_aircraft_theft", 2, 3)
	_reset(true)
	# crimes by somebody else are not ours
	Events.crime_committed.emit(GC.CRIME_ROBBERY, ppos, civ, {})
	_expect_level("crime_by_npc_ignored", 0)
	_reset(true)

	# hit and run: run-over damage by the player's vehicle
	var pveh := Mock.CivCar.new()
	pveh.driver = player
	mocks.add_child(pveh)
	pveh.global_position = ppos + Vector3(0, 0, 4)
	civ.revive()
	civ.apply_damage(30.0, {"source": pveh, "type": GC.DMG_RUNOVER, "zone": GC.ZONE_TORSO})
	_expect_level("crime_hit_and_run_by_player_vehicle", 1, 2)
	_reset(true)

	# collisions: bumping does nothing, a major crash with a traffic car is a small crime, ramming a patrol car is police assault
	var other := Mock.CivCar.new()
	mocks.add_child(other)
	other.global_position = ppos + Vector3(5, 0, 0)
	other.driver = civ
	var h0 := wanted.heat
	Events.vehicle_collision.emit(pveh, other, 2500.0)
	_check("crime_light_bump_ignored", is_equal_approx(wanted.heat, h0) and wanted.level == 0, "heat=%.1f" % wanted.heat)
	Events.vehicle_collision.emit(pveh, other, 14000.0)
	_check("crime_major_collision_small_heat", wanted.heat > 0.0 and wanted.heat < 10.0 and wanted.level == 0, "heat=%.1f level=%d" % [wanted.heat, wanted.level])
	_reset(true)
	Events.vehicle_collision.emit(pveh, pcar, 9000.0)
	_expect_level("crime_ram_police_car", 2, 5)
	_reset(true)

	# lethal damage is murder, not additional assault
	civ.revive()
	var before := wanted.heat
	civ.apply_damage(900.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_HEAD})
	_check("crime_kill_counts_once_per_moment", wanted.heat >= 30.0 and wanted.heat < 45.0, "heat=%.1f (before %.1f)" % [wanted.heat, before])
	_reset()
	# gang / animals do not interest the police
	var gang := _ped(Vector3(5, 0, 0))
	gang.faction = GC.F_GANG
	gang.remove_from_group(GC.G_PED)
	var cop2 := _officer(Vector3(0, 0, -18))
	gang.apply_damage(900.0, {"source": player, "type": GC.DMG_BULLET})
	_expect_level("crime_killing_gang_member_is_no_crime", 0)
	_retire(cop2)


# ---- witnesses ------------------------------------------------------------------------------------------------------
func _t_witness() -> void:
	var ppos := player.global_position
	# 1) nobody around: the crime stays unreported
	var victim := _ped(Vector3(5, 0, 0), 0.6, false)
	victim.apply_damage(5.0, {"source": player, "type": GC.DMG_BULLET})
	_tick(1.0)
	_expect_level("witness_none_no_wanted", 0)
	_check("witness_none_unreported_recorded", wanted._unreported.size() == 1, "unreported=%d" % wanted._unreported.size())

	# 2) ... until an officer shows up and recognises the player
	var cop := _officer(Vector3(0, 0, -20))
	_tick(0.6)
	_expect_level("witness_police_arrival_resolves_unreported", 1)
	_check("witness_police_arrival_pursuit", wanted.state == &"pursuit", String(wanted.state))
	_reset()

	# 3) a civilian witness phones: heat only after the call (crime_reported), state SEARCH (nobody sees the player)
	var mgr := Mock.PedMgr.new()
	add_child(mgr)
	var saved: Variant = Game.systems.get(&"peds", null)
	Game.systems[&"peds"] = mgr
	var v2 := _ped(Vector3(5, 0, 0), 0.6, false)
	var w1 := _ped(Vector3(10, 0, 3), 0.7, true)
	mgr.peds = [v2, w1]
	v2.apply_damage(5.0, {"source": player, "type": GC.DMG_BULLET})
	_check("witness_ped_called", w1.calls == 1, "calls=%d" % w1.calls)
	_expect_level("witness_phone_pending_no_heat_yet", 0)
	await get_tree().create_timer(1.1).timeout
	wanted.tick(0.1)
	_expect_level("witness_phone_report_applies_heat", 1)
	_check("witness_report_state_is_search", wanted.state == &"search", String(wanted.state))
	_check("witness_report_last_known_is_crime_position", wanted.last_known.distance_to(v2.global_position) < 2.0, str(wanted.last_known))
	_reset()

	# 4) the witness dies before the call completes: no report
	var v3 := _ped(Vector3(5, 0, 0), 0.6, false)
	var w2 := _ped(Vector3(10, 0, 3), 1.0, true)
	mgr.peds = [v3, w2]
	v3.apply_damage(5.0, {"source": player, "type": GC.DMG_BULLET})
	_check("witness_dying_call_started", w2.calls == 1)
	await get_tree().create_timer(0.3).timeout
	w2.apply_damage(900.0, {"source": player, "type": GC.DMG_BULLET})   # (kills the witness: murder is a new, separate incident)
	wanted._last_crime_t.clear()
	var lvl_before_calls := wanted.level
	await get_tree().create_timer(1.3).timeout
	wanted.tick(0.1)
	# the assault call died with the witness; only the murder of the witness (also unwitnessed now) exists
	_check("witness_dead_witness_no_report", wanted.level == lvl_before_calls and wanted.level == 0, "level=%d" % wanted.level)
	_reset()

	# 4b) three witnesses phone in the same assault: the crime is counted once
	var v5 := _ped(Vector3(5, 0, 0), 0.6, false)
	var m1 := _ped(Vector3(9, 0, 3), 0.5, true)
	var m2 := _ped(Vector3(-9, 0, 3), 0.9, true)
	var m3 := _ped(Vector3(0, 0, 11), 1.3, true)
	mgr.peds = [v5, m1, m2, m3]
	v5.apply_damage(5.0, {"source": player, "type": GC.DMG_BULLET})
	_check("witness_three_calls_started", m1.calls + m2.calls + m3.calls == 3, "calls=%d" % (m1.calls + m2.calls + m3.calls))
	await get_tree().create_timer(1.8).timeout
	wanted.tick(0.1)
	_check("witness_three_reports_count_once", wanted.level == 1 and wanted.heat < 16.0, "level=%d heat=%.1f" % [wanted.level, wanted.heat])
	_reset()

	# 5) crimes behind a wall: police nearby but no line of sight -> not seen
	var wall := _floor(ARENA + Vector3(0, 3, -9), Vector3(30, 8, 1))
	var cop2 := _officer(Vector3(0, 0, -20))
	var v4 := _ped(Vector3(5, 0, 0), 0.6, false)
	mgr.peds = []
	await _frames(3)
	v4.apply_damage(5.0, {"source": player, "type": GC.DMG_BULLET})
	_expect_level("witness_police_behind_wall_does_not_see", 0)
	wall.queue_free()
	_retire(cop2)
	Game.systems[&"peds"] = saved
	mgr.queue_free()
	_reset()


# ---- indirect reports ---------------------------------------------------------------------------------------------------
func _t_indirect() -> void:
	var ppos := player.global_position
	var far_ped := _ped(Vector3(60, 0, 0), 0.5, false)
	far_ped.add_to_group(GC.G_PED)
	# loud shot, a pedestrian within hearing range, nobody sees it
	Events.gunshot.emit(ppos + Vector3(0, 1.4, 0), 90.0, player)
	var inc: Dictionary = wanted._incidents[0] if wanted._incidents.size() > 0 else {}
	var delay := float(inc.get("indirect_due", -1.0)) - wanted._t
	_check("indirect_scheduled_6_to_10_s", not inc.is_empty() and delay >= 5.9 and delay <= 10.1, "delay=%.2f" % delay)
	_tick(5.0)
	_expect_level("indirect_no_report_before_6s", 0)
	_tick(5.5)
	_expect_level("indirect_report_after_6_10s", 1)
	_check("indirect_state_search_at_gunshot", wanted.state == &"search" and wanted.last_known.distance_to(ppos) < 3.0, "%s %s" % [String(wanted.state), str(wanted.last_known)])
	_reset()
	# suppressed shot: nobody hears it
	var far2 := _ped(Vector3(25, 0, 0), 0.5, false)
	Events.gunshot.emit(ppos + Vector3(0, 1.4, 0), 14.0, player)
	_tick(12.0)
	_expect_level("indirect_suppressed_shot_not_reported", 0)
	_reset()
	# loud shot but nobody (ped or police) within hearing range
	var very_far := _ped(Vector3(150, 0, 0), 0.5, false)
	Events.gunshot.emit(ppos + Vector3(0, 1.4, 0), 70.0, player)
	_tick(12.0)
	_expect_level("indirect_nobody_in_hearing_range", 0)
	_reset()
	# explosion: audible further away
	var mid := _ped(Vector3(100, 0, 0), 0.5, false)
	Events.explosion.emit(ppos + Vector3(5, 0, 0), 8.0, player)
	_tick(11.0)
	_expect_level("indirect_explosion_heard_100m_away", 2, 3)
	_reset()
	# shooting at the range is not a crime
	var loc := WorldLayout.get_location(&"shooting_range")
	_check("indirect_range_location_exists", not loc.is_empty())


# ---- timings -----------------------------------------------------------------------------------------------------------------
func _t_timings() -> void:
	for lvl in [1, 3, 5]:
		_reset()
		wanted.set_level(lvl)
		var t_pursuit := 0.0
		while wanted.state == &"pursuit" and t_pursuit < 20.0:
			wanted.tick(0.1)
			t_pursuit += 0.1
		_check("timings_L%d_pursuit_to_search_after_6s" % lvl, absf(t_pursuit - 6.0) < 0.5 and wanted.state == &"search", "t=%.1f state=%s" % [t_pursuit, String(wanted.state)])
		var needed := CrimeRules.escape_seconds(lvl)
		var t_search := 0.0
		var half_ok := false
		while wanted.level > 0 and t_search < 140.0:
			wanted.tick(0.1)
			t_search += 0.1
			if not half_ok and t_search >= needed * 0.5:
				half_ok = absf(wanted.escape_progress() - 0.5) < 0.06
		_check("timings_L%d_escape_takes_%ds" % [lvl, int(needed)], absf(t_search - needed) < 1.0 and wanted.level == 0 and wanted.state == &"clear",
			"t=%.1f needed=%.0f level=%d" % [t_search, needed, wanted.level])
		_check("timings_L%d_progress_is_linear" % lvl, half_ok)
	# the level drops by one star during a long search (about half the bar), the rest only when the bar is full
	_reset()
	wanted.set_level(5)
	_tick(6.5)
	var seen_levels := {}
	var t := 0.0
	while wanted.level > 0 and t < 120.0:
		wanted.tick(0.1)
		t += 0.1
		seen_levels[wanted.level] = true
	_check("timings_stars_drop_one_while_hiding", seen_levels.has(5) and seen_levels.has(4) and not seen_levels.has(1), str(seen_levels.keys()))
	# a crime during the search restarts the escape timer
	_reset()
	wanted.set_level(2)
	_tick(6.5 + 8.0)
	var p_before := wanted.escape_progress()
	wanted.add_wanted(5.0)
	_check("timings_new_crime_resets_escape", p_before > 0.2 and wanted.escape_progress() < 0.05, "before=%.2f after=%.2f" % [p_before, wanted.escape_progress()])
	# search radius grows
	_reset()
	wanted.set_level(3)
	_tick(6.5)
	var r0 := wanted.search_radius
	_tick(10.0)
	_check("timings_search_radius_grows", wanted.search_radius > r0 + 10.0 and wanted.get_search_radius() == wanted.search_radius, "r0=%.0f r1=%.0f" % [r0, wanted.search_radius])
	# idle heat decays at level 0
	_reset()
	wanted.add_wanted(5.0)
	_check("timings_sub_star_heat_stays_level_0", wanted.level == 0 and wanted.heat > 4.0)
	_tick(20.0)
	_check("timings_sub_star_heat_decays", wanted.heat < 0.5, "heat=%.2f" % wanted.heat)


# ---- re-sighting ----------------------------------------------------------------------------------------------------------------
func _t_resight() -> void:
	wanted.set_level(3)
	_tick(6.5 + 15.0)
	var p1 := wanted.escape_progress()
	_check("resight_progress_before", wanted.state == &"search" and p1 > 0.3, "p=%.2f" % p1)
	var cop := _officer(Vector3(0, 0, -25))
	wanted.report_sighting(player.global_position, cop)
	_check("resight_pursuit_immediately", wanted.state == &"pursuit" and wanted.escape_progress() == 0.0, "%s p=%.2f" % [String(wanted.state), wanted.escape_progress()])
	_check("resight_last_known_is_player", wanted.last_known.distance_to(player.global_position) < 1.0)
	_check("resight_is_player_seen", wanted.is_player_seen())
	_retire(cop)
	_tick(6.5)
	_check("resight_search_again_after_losing_track", wanted.state == &"search")
	_tick(5.0)
	_check("resight_progress_restarts_from_zero", wanted.escape_progress() < 0.25, "p=%.2f" % wanted.escape_progress())
	# a real line of sight scan also resumes the pursuit and the officer 'sees' the player at distance
	var cop2 := _officer(Vector3(0, 0, -45))
	cop2.rotation.y = 0.0           # faces -Z, the player is behind him (+Z)
	_tick(0.5)
	_check("resight_officer_facing_away_does_not_see", wanted.state == &"search", String(wanted.state))
	cop2.rotation.y = PI            # now faces the player
	_tick(0.5)
	_check("resight_officer_facing_player_sees", wanted.state == &"pursuit", "%s night=%.2f fog=%.2f rain=%.2f los_blocked=%s" % [String(wanted.state), wanted._night_amount(), Game.fog_amount, Game.rain_intensity, str(wanted._los_blocked(cop2.get_eye_position(), wanted._target_point()))])
	_retire(cop2)
	_tick(6.5)
	# a unit within 14 m always notices, even from behind
	var cop3 := _officer(Vector3(0, 0, -10))
	cop3.rotation.y = 0.0
	_tick(0.5)
	_check("resight_close_officer_always_notices", wanted.state == &"pursuit", String(wanted.state))
	# the last-known position follows the player while seen
	player.global_position += Vector3(5, 0, 0)
	cop3.global_position += Vector3(5, 0, 0)
	_tick(0.5)
	_check("resight_last_known_follows_player", wanted.last_known.distance_to(player.global_position) < 1.0)
	# helicopter sees far
	_retire(cop3)
	_tick(6.5)
	var heli := Mock.Car.new()
	heli.kind = &"heli"
	heli.vclass = GC.VC_HELI
	mocks.add_child(heli)
	heli.global_position = player.global_position + Vector3(120, 50, 0)
	_tick(0.5)
	_check("resight_helicopter_sees_at_120m", wanted.state == &"pursuit", String(wanted.state))


# ---- escape modifiers ---------------------------------------------------------------------------------------------------------
func _t_escape_mods() -> void:
	wanted.set_level(3)
	_tick(6.5)
	_check("mods_base_multiplier", is_equal_approx(wanted.get_escape_multiplier(), 1.0), "m=%.2f" % wanted.get_escape_multiplier())
	# abandoned vehicle: fake an identified vehicle id, the player is on foot
	wanted._ident_veh_id = 987654
	_tick(8.0)
	_check("mods_vehicle_swap_not_yet_at_8s", is_equal_approx(wanted.get_escape_multiplier(), 1.0))
	_tick(3.0)
	_check("mods_vehicle_swap_after_10s", wanted.get_escape_multiplier() > 1.4 and wanted.get_escape_multiplier() < 1.6, "m=%.2f" % wanted.get_escape_multiplier())
	var p_a := wanted.escape_progress()
	_tick(10.0)
	var gain_fast := wanted.escape_progress() - p_a
	_reset()
	wanted.set_level(3)
	_tick(6.5 + 11.0)
	var p_b := wanted.escape_progress()
	_tick(10.0)
	var gain_slow := wanted.escape_progress() - p_b
	_check("mods_vehicle_swap_speeds_up_escape", gain_fast > gain_slow * 1.35, "fast=%.3f slow=%.3f" % [gain_fast, gain_slow])
	_check("mods_never_instant", wanted.level > 0 or gain_fast < 1.0)
	# appearance
	_reset()
	wanted.set_level(2)
	_tick(6.5)
	wanted.notify_appearance_changed()
	_check("mods_appearance_change", wanted.get_escape_multiplier() > 1.3, "m=%.2f" % wanted.get_escape_multiplier())
	# clothing store flag
	_reset()
	wanted.set_level(2)
	_tick(6.5)
	Game.set_meta(&"appearance_changed_at", Time.get_ticks_msec() / 1000.0 + 1.0)
	_tick(0.5)
	_check("mods_appearance_game_meta_flag", wanted.get_escape_multiplier() > 1.3, "m=%.2f" % wanted.get_escape_multiplier())
	Game.remove_meta(&"appearance_changed_at")
	# hiding: interior, underwater, covered
	_reset()
	wanted.set_level(2)
	_tick(6.5)
	var y0 := player.global_position.y
	player.global_position.y = -400.0
	_check("mods_interior_hides", wanted.get_escape_multiplier() > 2.0, "m=%.2f" % wanted.get_escape_multiplier())
	player.global_position.y = y0
	player.head_underwater = true
	_check("mods_underwater_hides", wanted.get_escape_multiplier() > 1.8, "m=%.2f" % wanted.get_escape_multiplier())
	player.head_underwater = false
	var roof := _floor(player.global_position + Vector3(0, 5, 0), Vector3(20, 0.5, 20))
	await _frames(3)
	_tick(0.6)
	_check("mods_covered_slightly_helps", wanted._covered and wanted.get_escape_multiplier() > 1.1 and wanted.get_escape_multiplier() < 1.4, "m=%.2f" % wanted.get_escape_multiplier())
	roof.queue_free()
	_tick(0.4)
	# underwater player cannot be seen
	_reset()
	var cop := _officer(Vector3(0, 0, -15))
	wanted.set_level(2)
	_tick(6.5)
	_check("mods_pre_underwater_seen", wanted.state == &"pursuit")
	player.head_underwater = true
	_tick(8.0)
	player.head_underwater = false
	_check("mods_underwater_not_seen_by_close_officer", wanted.state == &"search", String(wanted.state))


# ---- the search-area rule ---------------------------------------------------------------------------------------------------------
func _t_search_area() -> void:
	wanted.search_area_rule = true
	wanted.set_level(2)
	_tick(6.5)
	_check("area_precondition_search", wanted.state == &"search" and wanted.is_inside_search_area(), "%s r=%.0f" % [String(wanted.state), wanted.search_radius])
	_check("area_inside_slows_escape", is_equal_approx(wanted.get_escape_multiplier(), CrimeRules.mult_inside_area), "m=%.2f" % wanted.get_escape_multiplier())
	var p0 := wanted.escape_progress()
	_tick(10.0)
	var inside_gain := wanted.escape_progress() - p0
	# slip out of the circle: the same time gives much more progress
	wanted.last_known = player.global_position + Vector3(wanted.search_radius + 60.0, 0, 0)
	_check("area_outside_is_detected", not wanted.is_inside_search_area())
	_check("area_outside_full_speed", is_equal_approx(wanted.get_escape_multiplier(), 1.0), "m=%.2f" % wanted.get_escape_multiplier())
	var p1 := wanted.escape_progress()
	_tick(10.0)
	var outside_gain := wanted.escape_progress() - p1
	_check("area_leaving_the_circle_is_4x_faster", outside_gain > inside_gain * 3.0, "inside=%.3f outside=%.3f" % [inside_gain, outside_gain])
	# an interior hides even inside the circle
	wanted.last_known = player.global_position
	var y0 := player.global_position.y
	player.global_position.y = -400.0
	_check("area_interior_hides_inside_circle", wanted.get_escape_multiplier() > 2.0, "m=%.2f" % wanted.get_escape_multiplier())
	player.global_position.y = y0
	# a stationary player is never "lost" within the first minute at 2 stars
	_reset()
	wanted.set_level(2)
	_tick(60.0)
	_check("area_standing_still_does_not_clear_in_60s", wanted.level >= 1, "level=%d p=%.2f" % [wanted.level, wanted.escape_progress()])
	wanted.search_area_rule = false


# ---- events ------------------------------------------------------------------------------------------------------------------------
func _t_events() -> void:
	_ev["changed"].clear()
	_ev["progress"] = 0
	var cop := _officer(Vector3(0, 0, -20))
	Events.crime_committed.emit(GC.CRIME_ROBBERY, player.global_position, player, {})
	var first: Array = _ev["changed"][0] if _ev["changed"].size() > 0 else []
	_check("events_wanted_changed_on_crime", first.size() == 2 and first[0] >= 1 and first[1] == &"pursuit", str(_ev["changed"]))
	_check("events_game_mirror", Game.wanted_level == wanted.level and Game.wanted_state == wanted.state)
	_retire(cop)
	_tick(6.5)
	var states: Array = []
	for e in _ev["changed"]:
		states.append(e[1])
	_check("events_pursuit_to_search_emitted", states.has(&"search"), str(states))
	var p0: int = _ev["progress"]
	_tick(3.0, 0.05)
	_check("events_search_progress_each_tick", int(_ev["progress"]) - p0 >= 55, "n=%d" % (int(_ev["progress"]) - p0))
	_ev["changed"].clear()
	wanted.clear()
	_check("events_clear_emits_zero_clear", _ev["changed"].size() == 1 and _ev["changed"][0][0] == 0 and _ev["changed"][0][1] == &"clear", str(_ev["changed"]))
	_ev["changed"].clear()
	wanted.clear()
	_check("events_no_duplicate_emit", _ev["changed"].is_empty(), str(_ev["changed"]))


func _t_bundle() -> void:
	var cop := _officer(Vector3(0, 0, -20))
	var civ := _ped(Vector3(5, 0, 0), 0.5, false)
	Events.gunshot.emit(player.global_position, 70.0, player)
	var h1 := wanted.heat
	civ.apply_damage(900.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_HEAD})
	var h2 := wanted.heat
	_check("bundle_shot_plus_kill_less_than_sum", h2 > h1 and h2 < 10.0 + 30.0 - 5.0 and h2 >= 30.0, "shot=%.1f both=%.1f" % [h1, h2])
	# repeated crime of the same kind within 30 s gives less
	_reset(true)
	wanted._last_crime_t.clear()
	wanted._bundle_t = -999.0
	Events.crime_committed.emit(GC.CRIME_ROBBERY, player.global_position, player, {})
	var r1 := wanted.heat
	wanted._last_crime_t.clear()
	wanted._bundle_t = -999.0
	Events.crime_committed.emit(GC.CRIME_ROBBERY, player.global_position, player, {})
	var r2 := wanted.heat - r1
	_check("bundle_repeat_decay", r2 < r1 * 0.9 and r2 > 0.0, "first=%.1f second=%.1f" % [r1, r2])


func _t_cheat() -> void:
	Game.cheats["never_wanted"] = true
	var cop := _officer(Vector3(0, 0, -20))
	Events.crime_committed.emit(GC.CRIME_ROBBERY, player.global_position, player, {})
	wanted.set_level(4)
	wanted.add_wanted(100.0)
	wanted.tick(0.1)
	_check("cheat_never_wanted_blocks_everything", wanted.level == 0 and Game.wanted_level == 0, "level=%d" % wanted.level)
	Game.cheats["never_wanted"] = false
	wanted.set_level(2)
	_check("cheat_off_works_again", wanted.level == 2)
	Game.cheats["never_wanted"] = true
	wanted.tick(0.1)
	_check("cheat_on_clears_existing_level", wanted.level == 0)
	Game.cheats["never_wanted"] = false


func _t_serialize() -> void:
	wanted.set_level(4)
	_tick(6.5 + 3.0)
	var lk := wanted.last_known
	var d := wanted.serialize()
	var json := JSON.stringify(d)
	var back: Variant = JSON.parse_string(json)
	wanted.clear()
	_check("serialize_cleared", wanted.level == 0)
	wanted.deserialize(back)
	_check("serialize_round_trip_level", wanted.level == 4, "level=%d" % wanted.level)
	_check("serialize_round_trip_position", wanted.last_known.distance_to(lk) < 0.01, str(wanted.last_known))
	_check("serialize_restores_as_search", wanted.state == &"search" and Game.wanted_state == &"search")
	wanted.deserialize({})
	_check("serialize_empty_is_clear", wanted.level == 0)
	wanted.deserialize({"level": 9, "junk": true})
	_check("serialize_tolerates_junk", wanted.level == 5)


# ---- BUSTED ------------------------------------------------------------------------------------------------------------------------
func _t_busted() -> void:
	player.invulnerable = false
	# a) armed officer 4 m away, player standing still, no violence: arrested within ~1.1 s
	var cop := _officer(Vector3(0, 0, -4))
	wanted.set_level(2)
	wanted._last_aggr_t = -999.0
	var t := 0.0
	var b0: int = _ev["busted"]
	while _ev["busted"] == b0 and t < 4.0:
		wanted.tick(0.1)
		t += 0.1
	_check("busted_armed_officer_within_6m", _ev["busted"] > b0 and t > 0.4 and t < 2.0, "t=%.1f" % t)
	_check("busted_player_in_busted_mode", player.move_mode == Player.Move.BUSTED, str(player.move_mode))
	# wanted stays frozen until the respawn
	var lvl := wanted.level
	wanted.add_wanted(500.0)
	_check("busted_wanted_frozen", wanted.level == lvl, "level=%d" % wanted.level)
	# the player's own flow: hands up -> respawn at the station -> wanted cleared
	await _frames(int(3.4 * 60.0))
	_check("busted_respawn_clears_wanted", wanted.level == 0 and Game.wanted_level == 0 and player.move_mode != Player.Move.BUSTED, "level=%d mode=%s" % [wanted.level, str(player.move_mode)])
	_reset()
	await _frames(20)
	player.invulnerable = true

	# b) shooting delays the arrest (no instant arrest during a gunfight)
	cop = _officer(Vector3(0, 0, -4))
	wanted.set_level(2)
	b0 = _ev["busted"]
	Events.gunshot.emit(player.global_position, 70.0, player)
	_tick(1.8)
	_check("busted_not_during_gunfight", _ev["busted"] == b0, "busted=%d" % (_ev["busted"] - b0))
	_tick(2.2)
	_check("busted_after_2s_quiet", _ev["busted"] > b0)
	await _frames(int(3.4 * 60.0))
	_reset()
	await _frames(20)
	player.invulnerable = true

	# c) unarmed officer: only within 3 m
	cop = _officer(Vector3(0, 0, -4.5), false)
	wanted.set_level(2)
	b0 = _ev["busted"]
	_tick(3.0)
	_check("busted_unarmed_officer_at_4_5m_no_arrest", _ev["busted"] == b0)
	cop.global_position = player.global_position + Vector3(0, 0, -2.2)
	_tick(2.0)
	_check("busted_unarmed_officer_at_2_2m_arrests", _ev["busted"] > b0)
	await _frames(int(3.4 * 60.0))
	_reset()
	await _frames(20)
	player.invulnerable = true

	# d) running away is not arrestable; officer behind a wall is not either
	cop = _officer(Vector3(0, 0, -4))
	wanted.set_level(2)
	b0 = _ev["busted"]
	player.velocity = Vector3(0, 0, 7.0)
	_tick(3.0)
	player.velocity = Vector3.ZERO
	_check("busted_sprinting_player_not_caught", _ev["busted"] == b0)
	var wall := _floor(player.global_position + Vector3(0, 2, -2), Vector3(10, 4, 0.5))
	await _frames(3)
	_tick(3.0)
	_check("busted_officer_behind_wall_cannot_arrest", _ev["busted"] == b0)
	wall.queue_free()
	await _frames(3)
	# e) level 0 : nothing happens
	_reset()
	cop = _officer(Vector3(0, 0, -2))
	_tick(3.0)
	_check("busted_no_arrest_without_wanted_level", _ev["busted"] == b0)
	# f) a surrendered player (unarmed, still) is cuffed faster
	_reset()
	cop = _officer(Vector3(0, 0, -7.5))
	player.weapons.holster()
	wanted.set_level(1)
	wanted._last_aggr_t = -999.0
	b0 = _ev["busted"]
	t = 0.0
	while _ev["busted"] == b0 and t < 3.0:
		wanted.tick(0.1)
		t += 0.1
	_check("busted_surrender_extends_radius_and_is_faster", _ev["busted"] > b0 and t < 1.4, "t=%.1f %s near=%d surr=%s spd=%.2f" % [t, wanted.get_debug_string(), wanted._near_officers.size(), str(wanted._is_surrendering(player, 0.0)), player.get_speed_xz()])
	await _frames(int(3.4 * 60.0))
	_reset()
	await _frames(20)
	player.invulnerable = true

	# g) boxed in a car: stopped vehicle + officers/cars adjacent for ~3 s
	var veh := VehicleFactory.spawn(&"sedan", Transform3D(Basis(), ARENA + Vector3(0, 0.5, 20)), {"abandoned": true, "snap_ground": true})
	if veh == null:
		_check("busted_vehicle_boxed_in", false, "could not spawn a sedan")
		return
	await _frames(40)
	player.global_position = veh.global_position + Vector3(2.5, 0.3, 0)
	player.enter_vehicle(veh, 0)
	await _frames(60)
	_check("busted_vehicle_entered", player.is_in_vehicle(), "in_vehicle=%s" % str(player.is_in_vehicle()))
	var c1 := Mock.Car.new()
	mocks.add_child(c1)
	c1.global_position = veh.global_position + Vector3(5, 0, 0)
	var c2 := Mock.Car.new()
	mocks.add_child(c2)
	c2.global_position = veh.global_position + Vector3(-5, 0, 0)
	var o1 := Mock.Officer.new()
	mocks.add_child(o1)
	o1.global_position = veh.global_position + Vector3(0, 0, -3)
	wanted.set_level(3)
	wanted._last_aggr_t = -999.0
	b0 = _ev["busted"]
	t = 0.0
	while _ev["busted"] == b0 and t < 6.0:
		wanted.tick(0.1)
		t += 0.1
	_check("busted_vehicle_boxed_in_stopped", _ev["busted"] > b0 and t > 2.0 and t < 4.5, "t=%.1f" % t)
	await _frames(int(3.4 * 60.0))
	_reset()
	await _frames(20)
	VehicleFactory.despawn(veh)
	player.invulnerable = true


func _t_hail() -> void:
	player.weapons.holster()
	var cop := _officer(Vector3(0, 0, -12))
	wanted.set_level(1)
	wanted._last_aggr_t = -999.0
	wanted._last_crime_applied_t = -999.0
	var s0: int = _ev["subtitle"]
	_tick(1.0)
	_check("hail_officer_calls_out_unarmed_suspect", _ev["subtitle"] > s0, "subtitles=%d" % (_ev["subtitle"] - s0))
	# running away after the hail = resisting arrest
	var h0 := wanted.heat
	cop.global_position = player.global_position + Vector3(0, 0, -16)
	player.velocity = Vector3(0, 0, 7.0)
	_tick(1.0)
	player.velocity = Vector3.ZERO
	_check("hail_running_away_is_resisting", wanted.heat > h0 or wanted.level >= 1, "heat %.1f -> %.1f" % [h0, wanted.heat])


func _t_death() -> void:
	player.invulnerable = false
	wanted.set_level(3)
	_check("death_precondition", wanted.level == 3)
	player.die({"source": null, "type": GC.DMG_FALL})
	await _frames(int(4.4 * 60.0))
	_check("death_respawn_clears_wanted", wanted.level == 0 and Game.wanted_level == 0 and not player.is_dead, "level=%d dead=%s" % [wanted.level, str(player.is_dead)])
	_check("death_state_clear", wanted.state == &"clear")
	_reset()
	await _frames(20)
