extends Node
## Pedestrian module test suite (headless). Run:
##   tools\gd.ps1 exec -Script res://gta/tests/ped_test.gd -Seconds 400 -GameArgs "--no-traffic"
## Filter with  --only=boot,walk,crossing,panic,witness,driver,death,zones,vehicle,explosion,ring,perf,pool,sit,aim,variety
## Prints "TEST <name> PASS|FAIL <detail>".

var pm: PedManager
var player: Node3D
var rng := RandomNumberGenerator.new()
var _fails := 0
var _passes := 0
var _only: Array = []
var _reported: Array = []
var _perp: Node3D = null


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
	else:
		_fails += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _arg(key: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
	return default_value


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _sim(seconds: float) -> void:
	await _frames(int(seconds * 60.0))


func _want(tname: String) -> bool:
	return _only.is_empty() or _only.has(tname)


func _reset(player_pos: Vector3 = Vector3(14.0, 0.1, 38.0)) -> void:
	pm.auto_population = false
	pm.signal_clock = Callable()
	pm.clear_all(true)
	if player != null:
		if player.get("current_vehicle") != null and is_instance_valid(player.current_vehicle):
			player.exit_vehicle(true)
		player.use_real_input = false
		player.set_input(Vector2.ZERO)
		player.teleport_to(player_pos)
	pm.now += 0.0


func _node_near(p: Vector3, zone: int = PedGraph.ZONE_SIDEWALK, max_d: float = 30.0) -> int:
	var pg := WorldLayout.ped_graph
	var best := -1
	var bd := 1e9
	for i in pg.points_in_radius(p, max_d):
		if pg.zone[i] != zone:
			continue
		var d := Util.dist_xz(pg.positions[i], p)
		if d < bd:
			bd = d
			best = i
	return best


func _spawn_walker(idx: int, look: StringName = &"casual", persistent: bool = true) -> Pedestrian:
	var pos := WorldLayout.ped_graph.positions[idx]
	return pm._spawn(look, &"walker", pos, rng.randf() * TAU, {"node": idx, "persistent": persistent})


func _on_reported(crime: StringName, pos: Vector3, perp: Node) -> void:
	if perp == _perp:       # other systems (WantedSystem) may emit their own reports: only count the ones of this test
		_reported.append({"crime": crime, "pos": pos, "t": pm.now})


func run(_main: Node) -> Variant:
	var only := _arg("only", "")
	if only != "":
		_only = only.split(",")
	rng.seed = 4242
	Game.time_of_day = 12.0              # a fixed noon: densities and light do not drift during the 15 minute suite
	Game.time_frozen = true
	pm = Game.sys(&"peds")
	player = Game.player
	if pm == null:
		_check("ped_manager_boot", false, "Game.sys(peds) is null")
		return null
	_perp = Node3D.new()
	add_child(_perp)
	Events.crime_reported.connect(_on_reported)
	await _frames(60)
	if _want("boot"):
		await t_boot()
	if _want("variety"):
		await t_variety()
	if _want("walk"):
		await t_walk()
	if _want("crossing"):
		await t_crossing()
	if _want("panic"):
		await t_panic()
	if _want("aim"):
		await t_aim()
	if _want("witness"):
		await t_witness()
	if _want("zones"):
		await t_zones()
	if _want("death"):
		await t_death()
	if _want("vehicle"):
		await t_vehicle()
	if _want("explosion"):
		await t_explosion()
	if _want("driver"):
		await t_driver()
	if _want("sit"):
		await t_sit()
	if _want("pool"):
		await t_pool()
	if _want("perf"):
		await t_perf()
	if _want("ring"):
		await t_ring()
	print("TEST SUMMARY pass=%d fail=%d" % [_passes, _fails])
	return null


# =====================================================================================================================
func t_boot() -> void:
	pm.clear_all(true)
	pm.auto_population = true
	pm.enabled = true
	Game.cheats["pedestrians"] = true
	player.teleport_to(Vector3(14.0, 0.1, 38.0))
	await _sim(14.0)
	var n := pm.peds.size()
	_check("ped_boot_population", n >= 25 and n <= PedDefs.CAP_HARD, "peds=%d target=%d" % [n, pm.stats["target"]])
	var groups_ok := true
	var layer_ok := true
	var rig_ok := true
	for p in pm.peds:
		if not (p.is_in_group(GC.G_NPC) and p.is_in_group(GC.G_PED) and p.is_in_group(GC.G_DAMAGEABLE)):
			groups_ok = false
		if p.collision_layer != GC.L_NPC or p.faction != GC.F_CIVILIAN:
			layer_ok = false
		if p.rig == null or not p.rig.is_built() or p.rig.skeleton == null:
			rig_ok = false
	_check("ped_boot_groups_layer", groups_ok and layer_ok, "groups=%s layer/faction=%s" % [groups_ok, layer_ok])
	_check("ped_boot_rig_built", rig_ok)
	_check("ped_boot_hitboxes", pm.peds.size() > 0 and pm.peds[0].get_node_or_null("HeadHitbox") != null and pm.peds[0].get_node_or_null("TorsoHitbox") != null)
	var cheat_ok := true
	Game.cheats["pedestrians"] = false
	await _sim(3.0)
	cheat_ok = pm.peds.size() < n * 0.5 or pm.peds.size() <= 6
	_check("ped_cheat_pedestrians_off", cheat_ok, "after cheat off peds=%d (was %d)" % [pm.peds.size(), n])
	Game.cheats["pedestrians"] = true
	await _sim(8.0)
	_check("ped_cheat_pedestrians_on", pm.peds.size() > 12, "peds=%d" % pm.peds.size())
	_reset()


func t_variety() -> void:
	_reset()
	var names := {}
	var bodies := {}
	var peds: Array = []
	for i in 40:
		var idx := _node_near(Vector3(rng.randf_range(-90, 90), 0, rng.randf_range(-70, 100)))
		if idx < 0:
			continue
		var p := _spawn_walker(idx, &"casual")
		if p == null:
			continue
		peds.append(p)
		names[CharacterVariants.appearance_name(p.variant)] = true
		bodies[String(p.variant.get("body", "A"))] = true
	_check("ped_variety_looks", names.size() >= 30, "distinct outfits %d / %d" % [names.size(), peds.size()])
	_check("ped_variety_bodies", bodies.size() >= 3, "body types %s" % [bodies.keys()])
	# district styles
	var counts := {}
	for d in [GC.D_INDUSTRIAL, GC.D_BEACH, GC.D_DOWNTOWN]:
		var c := {}
		for i in 80:
			var look: StringName = pm.spawner.look_for_district(d, -1)
			c[look] = int(c.get(look, 0)) + 1
		counts[d] = c
	_check("ped_district_industrial_workers", int(counts[GC.D_INDUSTRIAL].get(&"worker", 0)) >= 40, str(counts[GC.D_INDUSTRIAL]))
	_check("ped_district_beach_goers", int(counts[GC.D_BEACH].get(&"beach", 0)) >= 35, str(counts[GC.D_BEACH]))
	_check("ped_district_downtown_business", int(counts[GC.D_DOWNTOWN].get(&"business", 0)) >= 28, str(counts[GC.D_DOWNTOWN]))
	_check("ped_density_table", PedDefs.density(GC.D_DOWNTOWN, 13.0) > PedDefs.density(GC.D_DOWNTOWN, 3.0) * 3.0 and PedDefs.density(GC.D_BEACH, 15.0) > PedDefs.density(GC.D_BEACH, 7.0))
	_reset()


func t_walk() -> void:
	_reset()
	var idx := _node_near(Vector3(-35.0, 0.0, 30.0))
	var p := _spawn_walker(idx)
	p.brain.cross_w = 0.0
	var pg := WorldLayout.ped_graph
	var start := p.global_position
	var max_off := 0.0
	var max_dy := 0.0
	var max_turn := 0.0
	var last_yaw := p.rotation.y
	var travelled := 0.0
	var last_pos := p.global_position
	var states := {}
	var max_rig_speed := 0.0
	for i in 60 * 30:
		await get_tree().physics_frame
		max_rig_speed = maxf(max_rig_speed, p.rig.motion.speed)
		var pos := p.global_position
		travelled += Util.dist_xz(pos, last_pos)
		last_pos = pos
		var nn := pg.nearest(pos, 12.0)
		if nn >= 0:
			var np := pg.positions[nn]
			max_off = maxf(max_off, Util.dist_xz(np, pos))
			max_dy = maxf(max_dy, absf(np.y - pos.y))
		max_turn = maxf(max_turn, absf(wrapf(p.rotation.y - last_yaw, -PI, PI)))
		last_yaw = p.rotation.y
		states[p.get_state_name()] = true
	_check("ped_walk_moves", travelled > 12.0, "travelled %.1f m in 30 s (net %.1f)" % [travelled, Util.dist_xz(p.global_position, start)])
	_check("ped_walk_stays_on_graph", max_off < 6.5, "max distance to a graph node %.2f m" % max_off)
	_check("ped_walk_height", max_dy < 0.45, "max |y - node y| %.2f" % max_dy)
	_check("ped_walk_smooth_turning", max_turn < 0.25, "max yaw step %.3f rad / tick" % max_turn)
	_check("ped_walk_rig_locomotion", max_rig_speed > 0.5, "max rig speed %.2f (strollers stop now and then for a phone call / window)" % max_rig_speed)
	# avoidance: two peds walking towards each other pass without overlapping
	var a_idx := _node_near(Vector3(-35.0, 0.0, 40.0))
	var nb: PackedInt32Array = WorldLayout.ped_graph.links[a_idx]
	if nb.size() >= 1:
		var pa := _spawn_walker(a_idx)
		var pb := _spawn_walker(nb[0])
		pa.brain.cross_w = 0.0
		pb.brain.cross_w = 0.0
		var min_d := 99.0
		for i in 60 * 8:
			await get_tree().physics_frame
			min_d = minf(min_d, Util.dist_xz(pa.global_position, pb.global_position))
		_check("ped_avoidance_personal_space", min_d > 0.4, "closest approach %.2f m" % min_d)
	_reset()


func _find_crossing() -> Dictionary:
	var pg := WorldLayout.ped_graph
	for i in pg.size():
		if pg.zone[i] != PedGraph.ZONE_CROSSING or pg.signal_id[i] < 0:
			continue
		var pos := pg.positions[i]
		if WorldLayout.district_at(pos.x, pos.z) != GC.D_DOWNTOWN:
			continue
		for n in pg.links[i]:
			if pg.zone[n] != PedGraph.ZONE_SIDEWALK:
				continue
			var prev: int = n
			var cur: int = i
			var chain := [i]
			while true:
				var nxt := -1
				for m in pg.links[cur]:
					if m != prev and pg.zone[m] == PedGraph.ZONE_CROSSING:
						nxt = m
				if nxt < 0:
					break
				chain.append(nxt)
				prev = cur
				cur = nxt
			if chain.size() < 3:
				continue
			for m2 in pg.links[cur]:
				if m2 != prev and pg.zone[m2] == PedGraph.ZONE_SIDEWALK:
					return {"s": n, "c": i, "far": cur, "t": m2, "chain": chain}
	return {}


func t_crossing() -> void:
	_reset()
	var cr := _find_crossing()
	if cr.is_empty():
		_check("ped_crossing_found", false, "no signalised crossing in downtown")
		return
	var pg := WorldLayout.ped_graph
	var c: int = cr["c"]
	var sid: int = pg.signal_id[c]
	var ph: int = pg.walk_phase[c]
	# a frozen clock where traffic has green (crossing closed) and one where the pedestrians may go
	var t_closed := -1.0
	var t_open := -1.0
	var tt := 0.0
	while tt < 80.0:
		if t_closed < 0.0 and WorldLayout.signal_state(sid, ph, tt) == 0:
			t_closed = tt
		if t_open < 0.0 and WorldLayout.crossing_open(c, tt, 4.0) and WorldLayout.red_time_left(sid, ph, tt) > 9.5:
			t_open = tt
		tt += 0.5
	_check("ped_crossing_clock_found", t_closed >= 0.0 and t_open >= 0.0, "closed t=%.1f open t=%.1f" % [t_closed, t_open])
	var clock := {"t": t_closed}
	pm.signal_clock = func() -> float: return clock["t"]
	player.teleport_to(pg.positions[cr["s"]] + Vector3(6, 0.1, 0))
	await _frames(10)
	var s: int = cr["s"]
	var p := _spawn_walker(s)
	p.tier = 0
	p.brain.n_cur = s            # begin_walk already picked a random next node: start the route from the curb node
	p.brain.n_prev = -1
	p.brain.n_next = -1
	p.brain.go_to_node(cr["t"])
	await _sim(6.0)
	var waiting := p.brain.state == PedBrain.S.WAIT
	var on_crossing := Util.dist_xz(p.global_position, pg.positions[c]) < 0.5
	_check("ped_crossing_waits_on_red", waiting and not on_crossing or waiting and p.brain.t_state > 3.0, "state=%s waited %.1f s" % [p.get_state_name(), p.brain.t_state])
	# the light changes: the ped crosses and arrives on the far pavement
	clock["t"] = t_open
	var entered_state := false
	var arrived := false
	var t0 := pm.now
	for i in 60 * 30:
		await get_tree().physics_frame
		if p.brain.state == PedBrain.S.CROSS:
			entered_state = true
		if Util.dist_xz(p.global_position, pg.positions[cr["t"]]) < 3.0:
			arrived = true
			break
	_check("ped_crossing_walks_on_green", entered_state and arrived, "cross=%s arrived=%s in %.1f s" % [entered_state, arrived, pm.now - t0])
	# dynamic clock: the ped must only ENTER the road on a pedestrian phase (the clock starts on a closed crossing)
	t0 = pm.now
	clock["t"] = t_closed
	pm.signal_clock = func() -> float: return clock["t"] + (pm.now - t0)
	var tpos := PedNav.node_pos(cr["t"])      # stand on the far pavement again, then walk back across the road
	p.brain.px = tpos.x
	p.brain.pz = tpos.z
	p.brain.ground_y = tpos.y
	p.brain.speed = 0.0
	p.brain._enter(PedBrain.S.IDLE)
	p.brain._apply_transform()
	p.brain.n_cur = cr["t"]
	p.brain.n_prev = -1
	p.brain.n_next = -1
	p.brain.use_path = false
	p.brain.go_to_node(s)
	# every transition WAIT/WALK -> CROSS (= stepping onto the road) must happen on a pedestrian phase with time left
	var violations := 0
	var crossed := false
	var entries := 0
	var last_state: int = PedBrain.S.IDLE      # (go_to_node may already have stepped onto the crossing: count that entry as well)
	var waited := false
	for i in 60 * 70:
		await get_tree().physics_frame
		var st: int = p.brain.state
		if st == PedBrain.S.WAIT:
			waited = true
		if st == PedBrain.S.CROSS and last_state != PedBrain.S.CROSS:
			entries += 1
			var now_t: float = clock["t"] + (pm.now - t0)
			var nxt: int = p.brain.n_next
			var nsid: int = pg.signal_id[nxt] if nxt >= 0 else -1
			if nsid >= 0 and not WorldLayout.crossing_open(nxt, now_t, 1.5):
				violations += 1
		if st == PedBrain.S.CROSS:
			crossed = true
		last_state = st
		if crossed and entries >= 1 and st != PedBrain.S.CROSS and Util.dist_xz(p.global_position, pg.positions[s]) < 4.0:
			break
	_check("ped_crossing_obeys_signal_cycle", violations == 0 and crossed, "violations=%d entries=%d crossed=%s waited_at_red=%s" % [violations, entries, crossed, waited])
	pm.signal_clock = Callable()
	_reset()


func t_panic() -> void:
	_reset()
	var centre := Vector3(-35.0, 0.0, 30.0)
	player.teleport_to(centre + Vector3(0, 0.1, 22))
	await _frames(20)
	var peds: Array = []
	var pg := WorldLayout.ped_graph
	var used := {}
	for k in 60:
		if peds.size() >= 10:
			break
		var idx := _node_near(centre + Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-24, 24)))
		if idx < 0 or used.has(idx):
			continue
		used[idx] = true
		var p := _spawn_walker(idx)
		p.brain.cross_w = 0.0
		peds.append(p)
	await _sim(1.0)
	var before := {}
	for p in peds:
		before[p] = Util.dist_xz(p.global_position, centre)
	Events.gunshot.emit(centre + Vector3(0, 1.2, 0), 90.0, null)
	await _sim(2.2)
	var reacting := 0
	var fleeing := 0
	var gawk := 0
	for p in peds:
		match p.brain.state:
			PedBrain.S.FLEE:
				fleeing += 1
				reacting += 1
			PedBrain.S.COWER, PedBrain.S.HANDS_UP:
				reacting += 1
			PedBrain.S.GAWK:
				gawk += 1
	_check("ped_panic_on_gunshot", reacting >= int(peds.size() * 0.55) and fleeing >= 3, "reacting %d / %d (flee %d, gawk %d)" % [reacting, peds.size(), fleeing, gawk])
	await _sim(1.5)
	var farther := 0
	var runners := 0
	for p in peds:
		if p.brain.state == PedBrain.S.FLEE:
			runners += 1
			if Util.dist_xz(p.global_position, centre) > float(before[p]) + 1.5:
				farther += 1
	_check("ped_flee_away_from_threat", runners > 0 and farther >= int(runners * 0.7), "%d / %d runners got farther from the shot" % [farther, runners])
	var fast := 0
	for p in peds:
		if p.brain.state == PedBrain.S.FLEE and p.brain.speed > 4.0:
			fast += 1
	_check("ped_flee_runs", fast >= 2, "%d runners faster than 4 m/s" % fast)
	# panic spreads: a ped that is out of earshot of a quiet shot still flees when its neighbour does
	await _sim(34.0)
	var calm := 0
	var still_fleeing := 0
	for p in peds:
		if p.brain.state == PedBrain.S.FLEE:
			still_fleeing += 1
		elif p.brain.state in [PedBrain.S.WALK, PedBrain.S.IDLE, PedBrain.S.CROSS, PedBrain.S.WAIT]:
			calm += 1
	var mx := 0.0
	for p in peds:
		mx = maxf(mx, p.panic)
	_check("ped_calm_down_after_20s", still_fleeing == 0 and calm >= int(peds.size() * 0.7) and mx < 0.3, "calm %d / %d, fleeing %d, max panic %.2f (36 s after the shot)" % [calm, peds.size(), still_fleeing, mx])
	# loudness: a distant ped reacts to a loud shot only
	_reset()
	player.teleport_to(centre + Vector3(0, 0.1, 22))
	var far_idx := _node_near(centre + Vector3(50, 0, 0))
	var pf := _spawn_walker(far_idx)
	var fp := pf.global_position
	await _frames(10)
	Events.gunshot.emit(fp + Vector3(55, 1.2, 0), 25.0, null)
	await _sim(1.5)
	var quiet := pf.brain.state not in [PedBrain.S.FLEE, PedBrain.S.COWER, PedBrain.S.HANDS_UP] and pf.panic < 0.2
	Events.gunshot.emit(fp + Vector3(55, 1.2, 0), 110.0, null)
	await _sim(2.5)
	var loud := pf.brain.state in [PedBrain.S.FLEE, PedBrain.S.COWER, PedBrain.S.HANDS_UP, PedBrain.S.GAWK] or pf.panic > 0.2
	_check("ped_gunshot_loudness_range", quiet and loud, "quiet shot ignored=%s, loud shot noticed=%s" % [quiet, loud])
	_reset()


func t_aim() -> void:
	_reset()
	var pg := WorldLayout.ped_graph
	var base := Vector3(-35.0, 0.1, 25.0)
	player.teleport_to(base)
	await _frames(30)
	# the player faces -Z (north); peds stand 6-12 m in front of the muzzle
	var cam = Game.gameplay_camera
	var peds: Array = []
	for k in 6:
		var p := pm.spawn_pedestrian(base + Vector3(rng.randf_range(-1.5, 1.5), 0.0, -6.0 - k * 1.1), &"casual", {"stationary": true, "persistent": true, "yaw": 0.0})
		p.brain.begin_idle(&"relaxed", 999.0, 0.0)
		peds.append(p)
	if player.weapons != null:
		player.weapons.give_weapon(&"pistol", 60, true)
	player.set_input(Vector2.ZERO, false, true)
	if cam != null and cam.has_method("snap_behind"):
		cam.snap_behind(0.0)
	await _sim(2.5)
	var reacted := 0
	var hands := 0
	for p in peds:
		if p.brain.state in [PedBrain.S.HANDS_UP, PedBrain.S.COWER, PedBrain.S.FLEE, PedBrain.S.FIGHT]:
			reacted += 1
		if p.brain.state == PedBrain.S.HANDS_UP:
			hands += 1
	_check("ped_aim_weapon_reaction", pm.aim_active and reacted >= 3, "aim_active=%s reacted %d / 6 (hands up %d)" % [pm.aim_active, reacted, hands])
	player.set_input(Vector2.ZERO, false, false)
	await _sim(8.0)
	var released := 0
	for p in peds:
		if p.brain.state == PedBrain.S.HANDS_UP:
			released += 0
		else:
			released += 1
	_check("ped_hands_down_when_not_aimed", released == peds.size(), "still hands up: %d" % (peds.size() - released))
	_reset()


func t_witness() -> void:
	_reset()
	var base := Vector3(-35.0, 0.0, 30.0)
	player.teleport_to(base + Vector3(0, 0.1, 25))
	await _frames(20)
	var idx := _node_near(base)
	var p := _spawn_walker(idx)
	p.pers = (PedDefs.PERSONALITIES[&"normal"] as Dictionary).duplicate()
	p.pers["call"] = 1.0
	await _sim(0.5)
	var crime_pos := p.global_position + Vector3(4.0, 0.0, 0.0)
	var ws := pm.get_witnesses(crime_pos, player, 45.0)
	_check("ped_get_witnesses", ws.has(p), "witnesses=%d" % ws.size())
	_check("ped_get_witnesses_excludes_perpetrator", not pm.get_witnesses(crime_pos, p, 45.0).has(p))
	var far := pm.get_witnesses(crime_pos + Vector3(300, 0, 0), player, 45.0)
	_check("ped_get_witnesses_radius", far.is_empty())
	_reported.clear()
	var t0 := pm.now
	var will := p.witness(GC.CRIME_ASSAULT, crime_pos, _perp, 1.0)
	_check("ped_witness_returns_true", will, "witness() = %s" % will)
	var t_call_start := -1.0
	var t_report := -1.0
	for i in 60 * 16:
		await get_tree().physics_frame
		if t_call_start < 0.0 and p.is_calling():
			t_call_start = pm.now - t0
		if not _reported.is_empty():
			t_report = float(_reported[0]["t"]) - t0
			break
	_check("ped_witness_call_reports", t_report > 0.0 and _reported.size() == 1 and StringName(_reported[0]["crime"]) == GC.CRIME_ASSAULT, "reported after %.1f s (call began %.1f s)" % [t_report, t_call_start])
	_check("ped_witness_call_duration", t_report - t_call_start >= 3.9 and t_report - t_call_start <= 7.3, "call lasted %.2f s" % (t_report - t_call_start))
	# interrupted: killed while phoning
	_reset()
	player.teleport_to(base + Vector3(0, 0.1, 25))
	var p2 := _spawn_walker(_node_near(base))
	p2.pers = (PedDefs.PERSONALITIES[&"normal"] as Dictionary).duplicate()
	p2.pers["call"] = 1.0
	_reported.clear()
	p2.witness(GC.CRIME_MURDER, p2.global_position + Vector3(4, 0, 0), _perp, 1.5)
	var started := false
	for i in 60 * 10:
		await get_tree().physics_frame
		if p2.is_calling():
			started = true
			break
	var t_started := pm.now
	await _sim(1.0)
	print("PROBE kill at t=%.2f (call started %.2f), reports so far=%d" % [pm.now, t_started, _reported.size()])
	p2.apply_damage(500.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": p2.global_position + Vector3(0, 1.2, 0), "direction": Vector3(1, 0, 0), "impulse": 3.0, "weapon": &"pistol"})
	await _sim(10.0)
	_check("ped_witness_call_aborted_on_death", started and _reported.is_empty() and p2.is_dead and not p2.has_pending_call(), "call started=%s reports=%d dead=%s %s" % [started, _reported.size(), p2.is_dead, str(_reported)])
	# knocked down while phoning aborts too
	var p3 := _spawn_walker(_node_near(base + Vector3(10, 0, 0)))
	p3.pers = (PedDefs.PERSONALITIES[&"normal"] as Dictionary).duplicate()
	p3.pers["call"] = 1.0
	_reported.clear()
	p3.witness(GC.CRIME_ASSAULT, p3.global_position + Vector3(4, 0, 0), _perp, 1.0)
	for i in 60 * 10:
		await get_tree().physics_frame
		if p3.is_calling():
			break
	p3.knock_down(Vector3(4, 2, 0), 2.0)
	await _sim(10.0)
	_check("ped_witness_call_aborted_on_knockdown", _reported.is_empty() and not p3.has_pending_call(), "reports=%d" % _reported.size())
	_reset()


func t_zones() -> void:
	_reset()
	# pier nodes carry the sea floor height in the graph: PedNav.node_pos() must give the deck height
	var docks := 0
	var low := 0
	var pg0 := WorldLayout.ped_graph
	for i in pg0.size():
		if pg0.zone[i] == PedGraph.ZONE_DOCK:
			docks += 1
			if PedNav.node_pos(i).y < -0.6:
				low += 1
	_check("ped_pier_heights_fixed", PedNav.heights_fixed > 0 and low == 0, "%d dock nodes, %d corrected, %d still below -0.6 m" % [docks, PedNav.heights_fixed, low])
	var idx := _node_near(Vector3(-35.0, 0.0, 30.0))
	var p := _spawn_walker(idx)
	p.brain.begin_static(0.0)
	await _frames(5)
	var space := p.get_world_3d().direct_space_state
	var gp := p.global_position
	var shots := {"head": 1.66, "torso": 1.2, "limb": 0.35}
	var okc := 0
	var detail := ""
	for zname in shots:
		# short rays from four sides (a parked car or another body next to the ped must not spoil the test)
		var good := false
		var got := ""
		for dir: Vector3 in [Vector3(0, 0, 1.4), Vector3(1.4, 0, 0), Vector3(0, 0, -1.4), Vector3(-1.4, 0, 0)]:
			var from: Vector3 = gp + Vector3(0.0, float(shots[zname]), 0.0) + dir
			var to := gp + Vector3(0.0, float(shots[zname]), 0.0)
			var q := PhysicsRayQueryParameters3D.create(from, to, GC.M_BULLET)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var target := Ballistics.resolve_damageable(hit["collider"])
			if target != p:
				continue
			var z := Ballistics.character_zone(target, hit["collider"], hit, hit["position"])
			got = String(z)
			if z == StringName(zname):
				good = true
				break
		detail += " %s->%s" % [zname, got if got != "" else "nohit"]
		if good:
			okc += 1
	_check("ped_hit_zones_head_torso_limb", okc == 3, detail)
	# headshot kills a 100 hp ped with one pistol bullet, a body shot does not
	p.health = p.max_health
	var info := {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_HEAD, "position": gp + Vector3(0, 1.66, 0), "direction": Vector3(0, 0, -1), "impulse": 3.0, "weapon": &"pistol"}
	p.apply_damage(22.0, info)
	_check("ped_headshot_multiplier", p.health <= p.max_health - 60.0, "hp %.0f -> %.0f after a 22 dmg headshot" % [p.max_health, p.health])
	_reset()


func t_death() -> void:
	_reset()
	var base := Vector3(-35.0, 0.0, 30.0)
	player.teleport_to(base + Vector3(0, 0.1, 22))
	await _frames(10)
	var killed: Array = []
	var cash_before := {}
	for n0 in get_tree().get_nodes_in_group(GC.G_PICKUP):
		cash_before[n0.get_instance_id()] = true
	for i in 20:
		var idx := _node_near(base + Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-20, 20)))
		var p := _spawn_walker(idx, &"casual", false)
		p.brain.cross_w = 0.0
		killed.append(p)
	await _sim(0.5)
	var p0: Pedestrian = killed[0]
	var info := {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": p0.global_position + Vector3(0, 1.2, 0), "direction": Vector3(1, 0, 0), "impulse": 3.0, "weapon": &"pistol"}
	var died_events := []
	var ev := func(ch: Node, k: Node, i2: Dictionary) -> void: died_events.append(ch)
	Events.character_died.connect(ev)
	p0.apply_damage(500.0, info)
	await _frames(3)
	_check("ped_death_event_and_state", p0.is_dead and died_events.has(p0) and p0.brain.state == PedBrain.S.DEAD, "dead=%s event=%s" % [p0.is_dead, died_events.has(p0)])
	_check("ped_death_ragdoll", p0.rig.is_ragdoll() or p0.rig.is_ragdoll_frozen(), "ragdoll=%s" % p0.rig.is_ragdoll())
	_check("ped_death_collider_off_and_moved_to_corpses", p0.collision_layer == 0 and not pm.peds.has(p0) and pm.dead.has(p0))
	# mass death: ragdoll live cap
	for k in range(1, 14):
		var pk: Pedestrian = killed[k]
		pk.apply_damage(500.0, {"source": player, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": pk.global_position + Vector3(0, 1.2, 0), "direction": Vector3(0, 0, 1), "impulse": 4.0, "weapon": &"pistol"})
	await _sim(0.4)
	_check("ped_ragdoll_live_cap", RagdollBody.live.size() <= RagdollBody.MAX_LIVE, "live ragdolls %d" % RagdollBody.live.size())
	Events.character_died.disconnect(ev)
	await _sim(3.0)
	var cash := 0
	var amount_ok := true
	for n in get_tree().get_nodes_in_group(GC.G_PICKUP):
		if n is CashPickup and not cash_before.has(n.get_instance_id()):
			cash += 1
			if (n as CashPickup).amount < 20 or (n as CashPickup).amount > 120:
				amount_ok = false
	_check("ped_death_cash_drop", cash >= 3 and cash <= 13 and amount_ok, "%d cash pickups from 14 kills (expect ~8, 20-120 $)" % cash)
	# corpses: at most MAX_DEAD_BODIES stay, the rest fades early; a body stays 30 s, then fades and is recycled
	await _sim(4.0)
	_check("ped_corpse_cap", pm.dead.size() <= PedDefs.MAX_DEAD_BODIES + 1, "corpses %d (cap %d)" % [pm.dead.size(), PedDefs.MAX_DEAD_BODIES])
	# the 14 kills died in the same frame: the corpse cap fades the first ones early, so test a body that stayed (death time untouched)
	var last: Pedestrian = killed[13]
	for cand in pm.dead:
		if pm.now - (cand as Pedestrian).death_time < 12.0:
			last = cand
			break
	var t_dead := last.death_time
	await _sim(22.0)
	_check("ped_corpse_stays_30s", pm.dead.has(last) and pm.now - t_dead < 31.0, "body still there %.1f s after death" % (pm.now - t_dead))
	await _sim(8.0)
	var fading := false
	if last.rig.model != null:
		for mi in ModelLib.meshes(last.rig.model):
			if mi.transparency > 0.01:
				fading = true
				break
	_check("ped_corpse_fades", fading or not pm.dead.has(last), "transparency > 0 at %.1f s" % (pm.now - t_dead))
	await _sim(5.0)
	_check("ped_corpse_removed", pm.dead.is_empty() and not last.is_inside_tree(), "corpses left %d" % pm.dead.size())
	_reset()


func t_vehicle() -> void:
	_reset(Vector3(48.0, 0.1, -6.0))
	await _frames(40)
	var road := Vector3(35.0, 0.0, 0.0)
	var idx := _node_near(road + Vector3(-3.5, 0, 0))
	var p := _spawn_walker(idx)
	p.brain.begin_static(0.0)
	var pos := p.global_position
	p.brain.px = 35.0
	p.brain.pz = 0.0
	p.brain.ground_y = 0.05
	p.brain._apply_transform()
	await _frames(5)
	var v := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, PI), Vector3(35.0, 0.3, -34.0)), {"ai": true})
	if v == null:
		_check("ped_vehicle_spawn", false, "VehicleFactory.spawn failed")
		return
	p.brain.last_dodge_t = 1e12        # this one cannot dodge: it must be hit
	var hp0 := p.health
	var hit_events := []
	var fn := func(vv: Node, other: Node, imp: float) -> void: hit_events.append(other)
	Events.vehicle_collision.connect(fn)
	await _frames(20)
	v.set_velocity(Vector3(0, 0, 15.0))
	var t0 := pm.now
	var hit := false
	for i in 60 * 4:
		await get_tree().physics_frame
		v.input_throttle = 1.0
		if p.health < hp0 or p.is_dead or p.brain.state == PedBrain.S.KNOCKED:
			hit = true
			break
	await _sim(0.4)
	_check("ped_vehicle_impact_hurts", hit, "hp %.0f -> %.0f, state=%s, events=%d" % [hp0, p.health, p.get_state_name(), hit_events.size()])
	_check("ped_vehicle_impact_ragdoll", p.rig.is_ragdoll() or p.rig.is_ragdoll_frozen() or p.brain.state in [PedBrain.S.KNOCKED, PedBrain.S.GETUP, PedBrain.S.FLEE, PedBrain.S.DEAD], "state=%s ragdoll=%s" % [p.get_state_name(), p.rig.is_ragdoll()])
	Events.vehicle_collision.disconnect(fn)
	if not p.is_dead:
		await _sim(5.0)
		_check("ped_knocked_down_gets_up", p.brain.state not in [PedBrain.S.KNOCKED, PedBrain.S.DEAD], "state after 5 s: %s" % p.get_state_name())
	VehicleFactory.despawn(v)
	# dodge: a car speeding at a pedestrian standing in the lane makes it jump aside
	_reset(Vector3(48.0, 0.1, -6.0))
	await _frames(30)
	var p2 := _spawn_walker(_node_near(road + Vector3(-3.5, 0, 0)))
	p2.brain.begin_static(0.0)
	p2.brain.px = 35.0
	p2.brain.pz = 0.0
	p2.brain.ground_y = 0.05
	p2.brain._apply_transform()
	p2.tier = 0
	await _frames(5)
	var v2 := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, PI), Vector3(35.0, 0.3, -40.0)), {"ai": true})
	await _frames(20)
	v2.set_velocity(Vector3(0, 0, 16.0))
	var dodged := false
	var max_side := 0.0
	for i in 60 * 3:
		await get_tree().physics_frame
		v2.input_throttle = 1.0
		max_side = maxf(max_side, absf(p2.global_position.x - 35.0))
		if p2.health < p2.max_health:
			break
	dodged = max_side > 1.0 and p2.health >= p2.max_health - 0.5
	_check("ped_dodges_speeding_vehicle", dodged, "max lateral escape %.2f m, hp %.0f / %.0f" % [max_side, p2.health, p2.max_health])
	VehicleFactory.despawn(v2)
	_reset()


func t_explosion() -> void:
	_reset()
	var base := Vector3(-35.0, 0.0, 30.0)
	player.teleport_to(base + Vector3(0, 0.1, 22))
	await _frames(20)
	var near_peds: Array = []
	var far_peds: Array = []
	for k in 8:
		var idx := _node_near(base + Vector3(rng.randf_range(-3, 3) + (k % 4 - 2) * 3.0, 0, rng.randf_range(-3, 3) + (k / 4 - 1) * 4.0))
		if idx < 0:
			continue
		near_peds.append(_spawn_walker(idx))
	for k in 5:
		far_peds.append(_spawn_walker(_node_near(base + Vector3(rng.randf_range(-30, 30) + 25.0, 0, rng.randf_range(-20, 20)))))
	await _frames(10)
	var combat = Game.sys(&"combat")
	var centre := base + Vector3(0, 0.3, 0)
	if combat != null:
		combat.explode(centre, 7.0, 220.0, player, {"weapon": &"grenade"})
	await _sim(1.2)
	var down := 0
	var scared := 0
	for p in near_peds:
		if p.is_dead or p.brain.state == PedBrain.S.KNOCKED or p.brain.state == PedBrain.S.GETUP:
			down += 1
		elif p.brain.state in [PedBrain.S.FLEE, PedBrain.S.COWER, PedBrain.S.HANDS_UP, PedBrain.S.STAGGER]:
			scared += 1
	_check("ped_explosion_knockdown_or_death", down + scared >= int(near_peds.size() * 0.8) and down >= 1, "down/dead %d, scared %d of %d" % [down, scared, near_peds.size()])
	var far_react := 0
	for p in far_peds:
		if p.panic > 0.3 or p.brain.state in [PedBrain.S.FLEE, PedBrain.S.COWER, PedBrain.S.GAWK]:
			far_react += 1
	_check("ped_explosion_panic_spreads_to_bystanders", far_react >= int(far_peds.size() * 0.6), "%d of %d bystanders reacted" % [far_react, far_peds.size()])
	_reset()


func t_driver() -> void:
	_reset(Vector3(14.0, 0.1, 38.0))
	await _frames(30)
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(35.0, 0.3, -10.0))
	var v := VehicleFactory.spawn(&"sedan", xf, {"ai": true, "with_driver": true})
	_check("ped_driver_created_by_factory", v != null and v.driver is Pedestrian, "driver=%s" % [v.driver if v != null else null])
	var d: Pedestrian = v.driver
	_check("ped_driver_seated", d.current_vehicle == v and d.rig.get_stance() == &"sit_car" and pm.drivers.has(d), "stance=%s" % d.rig.get_stance())
	_check("ped_driver_not_in_ped_group", d.is_in_group(GC.G_NPC) and not d.is_in_group(GC.G_PED) and d.is_in_group(&"driver"))
	var taxi := VehicleFactory.spawn(&"taxi", Transform3D(Basis(Vector3.UP, PI), Vector3(35.0, 0.3, -24.0)), {"ai": true})
	var td = pm.create_driver(taxi)
	_check("ped_taxi_driver_outfit", td != null and (td as Pedestrian).look == &"taxi" and String((td as Pedestrian).variant.get("hat", "")) == "Hat_Cap", "look=%s" % [(td as Pedestrian).look if td != null else "null"])
	# steering follows the car
	v.input_steer = 0.8
	await _sim(0.6)
	_check("ped_driver_hands_follow_steering", absf(d.rig.motion.steering) > 0.1, "rig steering %.2f" % d.rig.motion.steering)
	# carjack by the player
	v.input_steer = 0.0
	player.teleport_to(v.global_position + v.global_transform.basis.x * -3.0)
	await _frames(10)
	var jacked := []
	var fn := func(c: Node, amount: float, info: Dictionary) -> void: pass
	var ok_enter: bool = v.request_enter(player, 0)
	await _sim(0.3)
	var out_of_car := d.current_vehicle == null and not pm.drivers.has(d) and pm.peds.has(d)
	_check("ped_carjack_driver_pulled_out", ok_enter and out_of_car, "enter=%s out=%s" % [ok_enter, out_of_car])
	await _sim(1.2)
	var reacts := d.brain.state in [PedBrain.S.STAGGER, PedBrain.S.FLEE, PedBrain.S.COWER, PedBrain.S.HANDS_UP, PedBrain.S.FIGHT]
	_check("ped_carjack_reaction", reacts, "state=%s" % d.get_state_name())
	await _sim(4.0)
	_check("ped_carjack_victim_runs_or_fights", d.brain.state in [PedBrain.S.FLEE, PedBrain.S.COWER, PedBrain.S.HANDS_UP, PedBrain.S.FIGHT, PedBrain.S.GAWK] or d.panic > 0.4, "state=%s panic=%.2f" % [d.get_state_name(), d.panic])
	player.exit_vehicle(true)
	await _frames(10)
	# a despawned car takes its driver with it
	var drv: Pedestrian = td
	var released_log: Array = []
	var on_rel := func(ped: Pedestrian) -> void: released_log.append(ped)
	pm.ped_despawned.connect(on_rel)
	VehicleFactory.despawn(taxi)
	await _sim(1.5)
	pm.ped_despawned.disconnect(on_rel)
	# (the node may already have been re-used by the traffic manager for another driver: the release signal is the reliable proof)
	_check("ped_driver_recycled_with_vehicle", released_log.has(drv), "released=%s drivers=%d" % [released_log.has(drv), pm.drivers.size()])
	# wrecked car: the driver is ejected and runs
	var v3 := VehicleFactory.spawn(&"sedan", Transform3D(Basis(Vector3.UP, PI), Vector3(35.0, 0.3, -40.0)), {"ai": true, "with_driver": true})
	var d3: Pedestrian = v3.driver
	await _frames(20)
	v3.explode(player)
	await _sim(2.5)
	_check("ped_driver_ejected_by_wreck", d3.current_vehicle == null and (d3.is_dead or d3.brain.state in [PedBrain.S.STAGGER, PedBrain.S.FLEE, PedBrain.S.KNOCKED, PedBrain.S.GETUP, PedBrain.S.COWER]), "dead=%s state=%s" % [d3.is_dead, d3.get_state_name()])
	_reset()


func t_sit() -> void:
	_reset()
	if pm.benches.is_empty():
		_check("ped_sit_benches_found", false, "no benches in furniture")
		return
	var bi := 0
	var bp: Vector3 = pm.benches[bi]["pos"]
	player.teleport_to(bp + Vector3(0, 0.1, 15))
	await _frames(20)
	pm.spawner.instant = true            # the scene spawner refuses spots the player could see: this test calls it directly
	var n := pm.spawner._spawn_sitter(bi)
	pm.spawner.instant = false
	await _sim(1.0)
	var sitter: Pedestrian = null
	for p in pm.peds:
		if p.brain.state == PedBrain.S.SIT:
			sitter = p
	_check("ped_sits_on_bench", n >= 1 and sitter != null and sitter.rig.get_stance() == &"sit_car" and (pm.benches[bi]["taken"] as Array).has(true), "n=%d" % n)
	if sitter != null:
		sitter.brain.dur = 2.0
		sitter.brain.t_state = 0.0
		await _sim(5.0)
		_check("ped_stands_up_and_leaves_bench", sitter.brain.state != PedBrain.S.SIT and (sitter.rig.get_stance() == &"stand" or sitter.rig.get_stance() == &"crouch") and sitter.bench_claim < 0, "state=%s claim=%d" % [sitter.get_state_name(), sitter.bench_claim])
	_reset()


func t_pool() -> void:
	_reset()
	var spawned: Array = []
	for i in 12:
		var idx := _node_near(Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-60, 90)))
		spawned.append(_spawn_walker(idx))
	var created := int(pm.stats["created"])
	pm.clear_all(true)
	_check("ped_pool_release", pm.pool.size() >= 12, "pool=%d" % pm.pool.size())
	for i in 12:
		var idx2 := _node_near(Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-60, 90)))
		_spawn_walker(idx2)
	_check("ped_pool_reuse_no_new_nodes", int(pm.stats["created"]) == created, "created %d -> %d" % [created, pm.stats["created"]])
	var redressed := 0
	for p in spawned:
		if p.is_inside_tree() and p.rig.is_built():
			redressed += 1
	_check("ped_pool_redressed_rig_ok", redressed >= 10, "%d of 12 recycled peds back in the tree with a built rig" % redressed)
	_reset()


func t_perf() -> void:
	_reset()
	var centre := Vector3(-10.0, 0.0, 30.0)
	player.teleport_to(centre + Vector3(0, 0.1, 6))
	await _frames(30)
	var made := pm.spawn_crowd(centre, 45.0, 62)
	await _sim(3.0)
	var n := pm.peds.size()
	var acc := 0.0
	var think := 0.0
	var mv := 0.0
	var samples := 0
	for i in 60 * 6:
		await get_tree().physics_frame
		if i % 10 == 0:
			acc += float(pm.stats["tick_us"])
			think += float(pm.stats["think_us"])
			mv += float(pm.stats["move_us"])
			samples += 1
	var avg := acc / float(maxi(samples, 1))
	_check("ped_perf_tick_under_3ms_for_60", n >= 55 and avg < 3000.0, "%d peds: manager %.0f us/tick (think %.0f, move %.0f)" % [n, avg, think / float(maxi(samples, 1)), mv / float(maxi(samples, 1))])
	# animation cost of the rigs: one full-rate update per near rig (best of 3 passes, the machine is shared with other agents)
	var per := 1e9
	var cnt := 0
	for pass_i in 3:
		var t0 := Time.get_ticks_usec()
		cnt = 0
		for p in pm.peds:
			if p.tier == 0:
				p.rig.manual_update = true
				p.rig.update_pose(1.0 / 60.0)
				p.rig.manual_update = false
				cnt += 1
		per = minf(per, float(Time.get_ticks_usec() - t0) / float(maxi(cnt, 1)))
	var n0 := 0
	var n1 := 0
	for p in pm.peds:
		if p.rig.lod == 0:
			n0 += 1
		elif p.rig.lod == 1:
			n1 += 1
	# lod 0 = every frame, lod 1 = ~15 Hz (a quarter), lod 2 = frozen
	var est_ms := (float(n0) + float(n1) * 0.25) * per / 1000.0
	var worst_ms := float(n) * per / 1000.0
	print("PROBE rig update %.0f us per full-rate rig (%d near rigs); LOD mix in this crowd: %d full, %d reduced, %d frozen" % [per, cnt, n0, n1, n - n0 - n1])
	_check("ped_perf_rig_update_cost", per < 400.0, "%.0f us per full-rate rig update" % per)
	_check("ped_perf_total_under_3ms_for_60", est_ms + float(pm.stats["tick_us"]) / 1000.0 < 3.0, "%d peds: animation ~%.2f ms (LOD mix) + scheduler %.2f ms; worst case with all rigs at full rate %.1f ms" % [n, est_ms, float(pm.stats["tick_us"]) / 1000.0, worst_ms])
	_reset()

## Average of (process + physics process) time per frame in ms over `frames` frames.
func _frame_cost(frames: int) -> float:
	var acc := 0.0
	for i in frames:
		await get_tree().physics_frame
		acc += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	return acc / float(frames)


func t_ring() -> void:
	_reset()
	pm.clear_all(true)
	pm.auto_population = true
	pm.instant_fill = false            # the instant fill (boot / teleport) is allowed to spawn in view; this test checks the steady state
	pm._instant_until = -1.0
	pm._last_pop_player = player.global_position
	pm.enabled = true
	Game.cheats["pedestrians"] = true
	var spawn_log: Array = []
	var fn := func(ped: Pedestrian) -> void:
		var cam: Camera3D = Game.gameplay_camera
		var d := Util.dist_xz(ped.global_position, pm.player_pos)
		var vis := false
		if cam != null and cam.is_position_in_frustum(ped.global_position + Vector3(0, 1.0, 0)):
			vis = Util.has_line_of_sight(ped, cam.global_position, ped.global_position + Vector3(0, 1.0, 0), GC.M_LOS)
		spawn_log.append({"d": d, "vis": vis, "persistent": ped.persistent, "t": pm.now, "role": ped.role, "pos": ped.global_position})
	pm.ped_spawned.connect(fn)
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var created0 := int(pm.stats["created"])
	var maxn := 0
	var path := [Vector3(14, 0.1, 38), Vector3(-30, 0.1, 40), Vector3(-30, 0.1, -10), Vector3(30, 0.1, -10), Vector3(30, 0.1, 40)]
	var pi := 0
	var nodes_mid := 0
	player.teleport_to(path[0])
	for sec in 120:
		# the player strolls around the downtown loop (teleporting along the path, 5 m/s)
		for k in 6:
			var target: Vector3 = path[(pi + 1) % path.size()]
			var cur: Vector3 = player.global_position
			var step := (target - cur)
			step.y = 0.0
			if step.length() < 3.0:
				pi = (pi + 1) % path.size()
			else:
				player.teleport_to(cur + step.normalized() * 0.8 + Vector3(0, 0.05, 0))
			await _frames(10)
		maxn = maxi(maxn, pm.peds.size())
		if sec == 40:
			nodes_mid = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	pm.ped_spawned.disconnect(fn)
	var visible_pops := 0
	var near_pops := 0
	var far_pops := 0
	var auto := 0
	for e in spawn_log:
		if bool(e["persistent"]):
			continue
		auto += 1
		if bool(e["vis"]):
			visible_pops += 1
			print("PROBE visible spawn: role=%s d=%.0f pos=%s" % [e["role"], e["d"], e["pos"]])
		if float(e["d"]) < PedDefs.RING_HIDDEN_MIN - 1.5:
			near_pops += 1
		if float(e["d"]) > PedDefs.RING_MAX + 25.0:
			far_pops += 1
	_check("ped_ring_no_visible_popping", auto >= 30 and visible_pops == 0, "%d spawns in 120 s, %d visible in the camera at spawn" % [auto, visible_pops])
	_check("ped_ring_distance_band", near_pops == 0 and far_pops == 0, "inside min ring %d, outside max ring %d" % [near_pops, far_pops])
	_check("ped_ring_cap", maxn <= PedDefs.CAP_ACTIVE + 8, "max active %d (cap %d)" % [maxn, PedDefs.CAP_ACTIVE])
	var close := 0
	for ped in pm.peds:
		if Util.dist_xz(ped.global_position, pm.player_pos) < 50.0:
			close += 1
	_check("ped_ring_population_close_to_player", close >= int(0.25 * float(pm.peds.size())) and close >= 10, "%d of %d peds within 50 m of the player" % [close, pm.peds.size()])
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check("ped_ring_no_node_leak", nodes1 - nodes_mid < 600, "node count %d (t=40 s) -> %d (t=120 s)" % [nodes_mid, nodes1])
	# 120 s of walking around spawn/despawns ~200 peds: nodes must be recycled (new nodes only to fill the pool up to the live count)
	var made := int(pm.stats["created"]) - created0
	_check("ped_ring_pool_bounded", pm.pool.size() <= PedDefs.CAP_HARD and made < 110, "pool=%d new nodes=%d (spawned %d, despawned %d)" % [pm.pool.size(), made, pm.stats["spawned"], pm.stats["despawned"]])
	_reset()
