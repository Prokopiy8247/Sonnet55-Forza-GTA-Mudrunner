extends Node
## Police-B headless tests: gang / hostile NPCs (GangNpc + HostileManager) and gang-vs-police fights.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/gang_test.gd -Seconds 240 -GameArgs "--no-traffic --no-peds"
## Part 1 runs in the real city (autostart, groups, cap, respawn); part 2 in a private flat arena far from the map (provocation rules,
## friend alert, retreat, calm-down, gang vs police, perf).

const ORIGIN := Vector3(5000.0, 0.0, 5000.0)

var passed := 0
var failed := 0
var arena: Node3D = null
var main_node: Node = null


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(s * 60.0))


func _only(name: String) -> bool:
	var want := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			want = String(a).substr(7)
	return want == "" or want.split(",").has(name)


func make_arena() -> Node3D:
	var a := Node3D.new()
	a.name = "GangTestArena"
	main_node.add_child(a)
	a.global_position = ORIGIN
	var fb := StaticBody3D.new()
	fb.collision_layer = GC.L_WORLD
	fb.collision_mask = 0
	fb.set_meta(&"surface", &"concrete")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	fb.add_child(cs)
	a.add_child(fb)
	return a


func wall(local_pos: Vector3, size: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.name = "Wall"
	w.collision_layer = GC.L_WORLD
	w.collision_mask = 0
	w.set_meta(&"surface", &"concrete")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	arena.add_child(w)
	w.position = local_pos + Vector3(0, size.y * 0.5, 0)
	return w


func gang(local_pos: Vector3, shared: Array, gid := 0, weapon: StringName = &"smg") -> GangNpc:
	var g := GangNpc.new()
	g.forced_weapon = weapon
	g.turf = ORIGIN + local_pos
	g.turf_radius = 4.0
	g.group_id = gid
	g.group_members = shared
	main_node.add_child(g)
	g.global_transform = Transform3D(Basis(Vector3.UP, 0.0), ORIGIN + local_pos)
	shared.append(g)
	return g


func officer(kind: StringName, local_pos: Vector3, yaw := 0.0) -> PoliceOfficer:
	return PoliceUnits.spawn_officer(kind, Transform3D(Basis(Vector3.UP, yaw), ORIGIN + local_pos)) as PoliceOfficer


func arm_player(on: bool) -> void:
	var wc = Game.player.weapons
	if on:
		wc.give_weapon(&"pistol", 60, true)
		wc.equip(&"pistol")
	else:
		wc.equip(&"fists")


func place_player(local_pos: Vector3, yaw := 0.0) -> void:
	Game.player.teleport_to(ORIGIN + local_pos + Vector3(0, 0.3, 0), yaw)


func run(main: Node) -> String:
	main_node = main
	await get_tree().process_frame
	var pm = Game.sys(&"police")
	if pm != null:
		pm.enabled = false
	Game.cheats["invulnerable"] = true
	if _only("city"):
		await _t_city()
	arena = make_arena()
	await frames(4)
	if _only("provoke"):
		await _t_provoke()
	if _only("retreat"):
		await _t_retreat()
	if _only("calm"):
		await _t_calm()
	if _only("police"):
		await _t_vs_police()
	if _only("perf"):
		await _t_perf()
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
	arena.queue_free()
	return "passed=%d failed=%d" % [passed, failed]


# --------------------------------------------------------------------------------------------------------------------
func _t_city() -> void:
	await seconds(2.0)
	var m = Game.world.get_node_or_null("HostileManager") if Game.world != null else null
	check("hostile_autostart", m != null, "HostileManager created by the deferred hook (no main.gd change)")
	if m == null:
		m = PoliceUnits.ensure_hostile_manager()
	check("ensure_hostile_manager", m is HostileManager and PoliceUnits.ensure_hostile_manager() == m, "idempotent")
	var hm := m as HostileManager
	await seconds(2.5)
	check("turfs_found", hm.turfs.size() >= 2, "turfs=%d" % hm.turfs.size())
	for t in hm.turfs:
		print("TEST info turf %s kind=%s at (%.0f, %.0f) r=%.1f" % [t["name"], t["kind"], t["center"].x, t["center"].z, t["radius"]])
	hm.clear_all()
	hm.force_spawn_all()
	await seconds(1.5)
	var sizes: Array[int] = []
	var all_ok := true
	var on_floor := 0
	var total := 0
	var near_turf := true
	for g in hm.groups:
		sizes.append((g["members"] as Array).size())
		for mem in g["members"]:
			var gn := mem as GangNpc
			total += 1
			if gn.faction != GC.F_GANG or not gn.is_in_group(GC.G_HOSTILE) or not gn.is_in_group(GC.G_NPC):
				all_ok = false
			if gn.is_on_floor():
				on_floor += 1
			if Util.dist_xz(gn.global_position, g["turf"]["center"]) > float(g["turf"]["radius"]) + 3.0:
				near_turf = false
	var sizes_ok := true
	for s in sizes:
		if s < 3 or s > 4:
			sizes_ok = false
	check("groups_of_3_4", sizes_ok and sizes.size() >= 2, "sizes=%s" % str(sizes))
	check("members_factions_groups", all_ok and total > 0, "members=%d" % total)
	check("members_on_floor_near_turf", on_floor >= total - 1 and near_turf, "on_floor=%d/%d near_turf=%s" % [on_floor, total, near_turf])
	check("cap_12_active", hm.alive_count() <= HostileManager.MAX_ACTIVE, "alive=%d" % hm.alive_count())
	# idle: nobody provoked while the player is far away and nothing happens
	var provoked_any := false
	for g in hm.groups:
		for mem in g["members"]:
			if (mem as GangNpc).provoked:
				provoked_any = true
	check("idle_until_provoked", not provoked_any, "")
	# a wiped group stays dead, then respawns (out of sight, >85 m away) after RESPAWN_DELAY (shortened here)
	var g0: Dictionary = hm.groups[0]
	for mem in (g0["members"] as Array).duplicate():
		(mem as GangNpc).apply_damage(5000.0, {"source": Game.player, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": (mem as Node3D).global_position, "direction": Vector3(0, 0, -1), "weapon": &"pistol", "impulse": 1.0})
	await seconds(2.5)
	check("group_wipe_detected", bool(g0["wiped"]) and hm.stats["groups_wiped"] >= 1, "wiped=%s" % g0["wiped"])
	var tc: Vector3 = g0["turf"]["center"]
	var back := (WorldLayout.location_pos(&"player_spawn") - tc)
	back.y = 0.0
	back = back.normalized() if back.length() > 1.0 else Vector3(-1, 0, 0)
	Game.player.teleport_to(tc + back * 130.0 + Vector3(0, 1.5, 0), Util.dir_to_yaw(back))
	g0["respawn_at"] = hm._clock - 1.0
	await seconds(4.0)
	var back_alive := 0
	for mem in g0["members"]:
		if is_instance_valid(mem) and not (mem as GangNpc).is_dead:
			back_alive += 1
	check("group_respawns", back_alive >= 3 and not bool(g0["wiped"]) and hm.stats["respawns"] >= 1, "alive=%d respawns=%d" % [back_alive, hm.stats["respawns"]])
	hm.clear_all()
	hm.enabled = false


func _t_provoke() -> void:
	# unarmed player at 20 m: ignored; armed at 20 m with LOS: attacked; a wall blocks the provocation; the friends 55 m away join in
	var shared: Array = []
	var g1 := gang(Vector3(0, 0, -20), shared)
	var g2 := gang(Vector3(3, 0, -21), shared)
	var g3 := gang(Vector3(-3, 0, -22), shared)
	var far := gang(Vector3(0, 0, -62), shared, 0, &"bat")
	place_player(Vector3(0, 0, 0), 0.0)
	arm_player(false)
	await seconds(2.5)
	check("gang_ignores_unarmed_at_range", not g1.provoked and not g2.provoked and not g3.provoked, "")
	check("gang_starts_holstered", g1.holstered and not g1.brain.combat_enabled, "")
	# a wall between: armed player is not noticed
	var w := wall(Vector3(0, 0, -10), Vector3(30, 5, 0.6))
	arm_player(true)
	await seconds(2.5)
	check("gang_wall_blocks_provocation", not g1.provoked and not g2.provoked and not g3.provoked, "")
	w.queue_free()
	await seconds(0.1)
	arm_player(true)
	var shots := [0]
	var on_shot := func(_pos: Vector3, _l: float, src: Node):
		if src is GangNpc:
			shots[0] += 1
	Events.gunshot.connect(on_shot)
	await seconds(3.0)
	check("gang_provoked_by_armed_player", g1.provoked or g2.provoked or g3.provoked, "provoked=%s/%s/%s" % [g1.provoked, g2.provoked, g3.provoked])
	check("gang_draws_weapon_targets_player", not g1.holstered and g1.brain.target == Game.player and g1.brain.combat_enabled, "state=%s" % g1.brain.describe())
	check("gang_calls_friends_60m", far.provoked, "member 42 m behind the group provoked=%s" % far.provoked)
	await seconds(10.0)
	Events.gunshot.disconnect(on_shot)
	var roster := ""
	for g in [g1, g2, g3, far]:
		roster += " [%s %s hp=%.0f dead=%s by=%s/%s %s pos=(%.1f,%.1f,%.1f)]" % [g.name, g.weapon_kind, g.health, g.is_dead, str(g.last_attacker.name) if is_instance_valid(g.last_attacker) else "-", str(g.last_damage_info.get("weapon", "-")), g.brain.describe() if is_instance_valid(g) else "-", g.global_position.x - ORIGIN.x, g.global_position.y, g.global_position.z - ORIGIN.z]
	check("gang_fires_at_player", shots[0] >= 6, "gang shots=%d roster:%s" % [shots[0], roster])
	var engaged := 0
	for g in shared:
		if (g as GangNpc).brain.is_engaged():
			engaged += 1
	check("gang_engaged_states", engaged >= 2, "engaged=%d of %d" % [engaged, shared.size()])
	for g in shared:
		if is_instance_valid(g):
			g.queue_free()
	await seconds(0.5)
	# unarmed but close (11 m): provoked by proximity
	shared = []
	place_player(Vector3(0, 0, 0), 0.0)
	var c1 := gang(Vector3(0, 0, -8), shared)
	arm_player(false)
	await seconds(2.0)
	check("gang_provoked_by_proximity", c1.provoked, "dist=%.1f los=%s player_armed=%s" % [c1.global_position.distance_to(Game.player.global_position),
		Util.has_line_of_sight(c1, c1.global_position + Vector3(0, 1.6, 0), Game.player.global_position + Vector3(0, 1.3, 0), GC.M_LOS, [c1]), c1._player_armed(Game.player)])
	c1.queue_free()
	# hurting one provokes it even without line-of-sight trigger
	shared = []
	var d1 := gang(Vector3(40, 0, 40), shared)
	var d2 := gang(Vector3(44, 0, 41), shared)
	await seconds(1.0)
	d1.apply_damage(5.0, {"source": Game.player, "type": GC.DMG_BULLET, "zone": GC.ZONE_LIMB, "position": d1.global_position + Vector3(0, 1, 0), "direction": Vector3(1, 0, 0), "weapon": &"pistol", "impulse": 1.0})
	await seconds(1.0)
	check("gang_provoked_by_damage_and_friend", d1.provoked and d2.provoked, "d1=%s d2=%s" % [d1.provoked, d2.provoked])
	d1.queue_free()
	d2.queue_free()
	await seconds(0.5)


func _t_retreat() -> void:
	# a share of the wounded flee, the rest keeps fighting
	place_player(Vector3(-100, 0, 0), 0.0)
	var shared: Array = []
	var n := 14
	var gs: Array = []
	for i in n:
		var g := gang(Vector3(-100 + (i % 7) * 2.0 - 6.0, 0, -22 - (i / 7) * 2.0), shared)
		gs.append(g)
	arm_player(true)
	await seconds(2.0)
	for g in gs:
		var gn := g as GangNpc
		gn.provoke(Game.player)
		gn.health = gn.max_health * 0.27
		gn.apply_damage(1.0, {"source": Game.player, "type": GC.DMG_BULLET, "zone": GC.ZONE_LIMB, "position": gn.global_position + Vector3(0, 1, 0), "direction": Vector3(0, 0, 1), "weapon": &"pistol", "impulse": 1.0})
	var fled := 0
	var seen: Dictionary = {}
	for k in 24:
		await seconds(0.25)
		for g in gs:
			if is_instance_valid(g) and (g as GangNpc).brain.state == CombatBrain.State.RETREAT:
				seen[g.get_instance_id()] = true
	fled = seen.size()
	check("gang_some_flee_when_hurt", fled >= 1 and fled <= n - 1, "fled=%d of %d" % [fled, n])
	for g in gs:
		if is_instance_valid(g):
			g.queue_free()
	await seconds(0.5)


func _t_calm() -> void:
	# after losing the player (> 60 m for CALM_AFTER s) the gang holsters and walks back to its turf
	place_player(Vector3(0, 0, 0), 0.0)
	var shared: Array = []
	var g := gang(Vector3(0, 0, -14), shared)
	arm_player(true)
	await seconds(2.0)
	check("calm_setup_provoked", g.provoked, "")
	place_player(Vector3(0, 0, 190), 0.0)
	arm_player(false)
	g.brain.clear_target()
	g.brain.forced_target = null
	await seconds(GangNpc.CALM_AFTER + 8.0)
	check("gang_calms_down_when_player_gone", not g.provoked and g.holstered, "provoked=%s holstered=%s state=%s" % [g.provoked, g.holstered, g.brain.describe()])
	g.queue_free()
	await seconds(0.3)


func _t_vs_police() -> void:
	# 3 gang members vs 3 patrol officers 30 m apart (player far away, wanted 0): the factions fight each other
	place_player(Vector3(150, 0, 150), 0.0)
	arm_player(false)
	var shared: Array = []
	var gs: Array = []
	for i in 3:
		gs.append(gang(Vector3(-4 + i * 4, 0, -30), shared))
	var os: Array = []
	for i in 3:
		os.append(officer(&"patrol", Vector3(-4 + i * 4, 0, 0), 0.0))
	await seconds(0.5)
	var gang_targets_cop := false
	var cop_targets_gang := false
	var t := 0.0
	var dead_g := 0
	var dead_o := 0
	while t < 45.0:
		await seconds(0.5)
		t += 0.5
		for g in gs:
			if is_instance_valid(g) and (g as GangNpc).brain.target is PoliceOfficer:
				gang_targets_cop = true
		for o in os:
			if is_instance_valid(o) and (o as PoliceOfficer).brain.target is GangNpc:
				cop_targets_gang = true
		dead_g = 0
		dead_o = 0
		for g in gs:
			if not is_instance_valid(g) or (g as GangNpc).is_dead:
				dead_g += 1
		for o in os:
			if not is_instance_valid(o) or (o as PoliceOfficer).is_dead:
				dead_o += 1
		if dead_g == 3 or dead_o == 3:
			break
	check("gang_vs_police_targeting", gang_targets_cop and cop_targets_gang, "gang->cop=%s cop->gang=%s" % [gang_targets_cop, cop_targets_gang])
	check("gang_vs_police_resolves", dead_g + dead_o >= 2, "dead gang=%d dead police=%d after %.0f s" % [dead_g, dead_o, t])
	for g in gs:
		if is_instance_valid(g):
			g.queue_free()
	for o in os:
		if is_instance_valid(o):
			PoliceUnits.despawn(o)
	await seconds(0.5)


func _t_perf() -> void:
	# 12 gang members in a firefight with the player + 6 officers: cost of the brains per physics frame
	place_player(Vector3(0, 0, 0), 0.0)
	arm_player(true)
	var shared: Array = []
	var gs: Array = []
	for i in 12:
		gs.append(gang(Vector3(-15 + (i % 6) * 6.0, 0, -25 - (i / 6) * 5.0), shared))
	var os: Array = []
	for i in 6:
		os.append(officer(&"patrol", Vector3(-10 + i * 4, 0, 6), 0.0))
	await seconds(1.0)
	for g in gs:
		(g as GangNpc).provoke(Game.player)
	PoliceUnits.reset_stats()
	var f0 := Engine.get_physics_frames()
	await seconds(8.0)
	var fr := maxi(Engine.get_physics_frames() - f0, 1)
	var st := PoliceUnits.stats()
	var ms := float(st["brain_usec"]) / 1000.0 / float(fr)
	check("gang_perf_under_3ms", ms < 3.0, "brain=%.3f ms/frame (12 gang + 6 police) cover_queries=%d paths=%d" % [ms, st["cover_queries"], st["paths"]])
	for g in gs:
		if is_instance_valid(g):
			g.queue_free()
	for o in os:
		if is_instance_valid(o):
			PoliceUnits.despawn(o)
	await seconds(0.3)



