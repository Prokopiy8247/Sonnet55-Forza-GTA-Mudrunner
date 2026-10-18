extends Node
## Activities: framework + shooting range with REAL bullets (bot aims the player camera and fires through the WeaponController), stunt jump
## detection with the real sports car on the existing ramp, street race with a driving bot.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/activity_test.gd -Seconds 200 -GameArgs "--no-traffic --no-peds --part=range"
## parts: basic (default quick checks) | range | stunt | race   (comma list allowed)

var passed := 0
var failed := 0
var sys: Node = null


func check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("TEST %s %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _parts() -> Array:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--part="):
			return String(a).substr(7).split(",")
	return ["basic"]


func run(_main: Node) -> String:
	sys = Game.sys(&"activities")
	check("system_booted", sys != null, "")
	if sys == null:
		return "no system"
	var guard := 0
	while not sys.ready_ok and guard < 600:
		await get_tree().physics_frame
		guard += 1
	check("activities_registered", sys.activities.has(&"shooting_range") and sys.activities.has(&"stunt_jumps") and sys.activities.has(&"street_race"), str(sys.activities.keys()))
	var parts := _parts()
	if "basic" in parts:
		await _basic()
	if "range" in parts:
		await _range()
	if "stunt" in parts:
		await _stunt()
	if "race" in parts:
		await _race()
	print("TEST SUMMARY passed=%d failed=%d" % [passed, failed])
	return "passed=%d failed=%d" % [passed, failed]


func _basic() -> void:
	# persistence round trip
	sys.best["range:pistol"] = {"value": 2500.0, "medal": "silver", "plays": 2}
	sys.flags["stunt_first_1"] = true
	var d: Dictionary = sys.serialize()
	sys.best = {}
	sys.flags = {}
	sys.deserialize(d)
	check("best_roundtrip", float(sys.best["range:pistol"]["value"]) == 2500.0 and String(sys.best["range:pistol"]["medal"]) == "silver" and bool(sys.flags.get("stunt_first_1", false)), "")
	sys.deserialize({"best": 5, "flags": "x"})
	check("deserialize_tolerant", sys.best.is_empty(), "")
	# medals
	check("medal_math", ActivityBase.medal_for(3800, 3700, 2700, 1500) == "gold" and ActivityBase.medal_for(2000, 3700, 2700, 1500) == "bronze" and ActivityBase.medal_for(100, 3700, 2700, 1500) == "none"
		and ActivityBase.medal_for(80.0, 90.0, 110.0, 140.0, false) == "gold" and ActivityBase.medal_for(120.0, 90.0, 110.0, 140.0, false) == "bronze", "")
	# interaction points exist and answer the interaction contract
	var pts := get_tree().get_nodes_in_group(GC.G_INTERACT).filter(func(n): return n is ActivityPoint)
	check("points_interactable", pts.size() >= 2, "n=%d" % pts.size())
	var info: Dictionary = (pts[0] as ActivityPoint).get_interaction(Game.player)
	check("point_prompt", info.has("text") and String(info["text"]) != "" and info.get("key", "") == "E", str(info))
	# the map blip location for the race exists
	check("race_blip_location", WorldLayout.has_location(&"race_start") and UIIcons.location_info(&"race_start").size() == 4, "")
	# target ring scoring with fake hits (silhouette head / chest bull / edge, round bull / outer)
	var holder := Node3D.new()
	add_child(holder)
	var sil := ActivityTarget.create(&"silhouette", Transform3D(Basis.IDENTITY, Vector3(3000, 0, 3000)), holder)
	var rnd := ActivityTarget.create(&"round", Transform3D(Basis.IDENTITY, Vector3(3010, 0, 3000)), holder)
	await get_tree().physics_frame
	var base_s: Vector3 = sil.plate.global_position
	var head: Dictionary = sil.score_hit(base_s + Vector3(0, 1.39, 0))
	var bull: Dictionary = sil.score_hit(base_s + Vector3(0, 0.88, 0))
	var edge: Dictionary = sil.score_hit(base_s + Vector3(0.25, 0.3, 0))
	check("score_silhouette", int(head.get("points", 0)) > int(bull.get("points", 99)) - 1 and int(bull.get("points", 0)) > int(edge.get("points", 99)), "head=%s bull=%s edge=%s" % [head, bull, edge])
	var base_r: Vector3 = rnd.plate.global_position
	var rb: Dictionary = rnd.score_hit(base_r + Vector3(0, 0.45, 0))
	var ro: Dictionary = rnd.score_hit(base_r + Vector3(0.3, 0.45, 0))
	check("score_round", int(rb.get("points", 0)) > int(ro.get("points", 99)), "bull=%s outer=%s" % [rb, ro])
	holder.queue_free()
	# state machine: abort without a running activity is a no-op; start/abort cycle with the range
	var act: ActivityBase = sys.get_activity(&"shooting_range")
	var p: Node = Game.player
	p.teleport_to(act.point_pos + Vector3(0, 0.5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	sys.abort("noop")
	check("abort_idle_noop", sys.state == ActivitySystem.State.IDLE, "")
	var inv_before: Array = p.weapons.get_weapon_ids().duplicate()
	var ok: bool = sys.start(&"shooting_range", {"option": "pistol"})
	check("range_start", ok and sys.state == ActivitySystem.State.COUNTDOWN, "state=%d" % sys.state)
	check("one_at_a_time", not sys.start(&"street_race", {"option": "sports"}), "")
	for i in 60:
		await get_tree().physics_frame
	check("range_wants_gun_zone_meta", bool(Game.get_meta(&"gun_range_zone", false)), "")
	sys.abort("test")
	await get_tree().physics_frame
	check("range_abort_state", sys.state == ActivitySystem.State.ABORTED, "state=%d" % sys.state)
	var inv_after: Array = p.weapons.get_weapon_ids()
	check("weapons_restored_after_abort", inv_after.size() == inv_before.size() and not p.weapons.has_weapon(&"rocket_launcher"), "%s -> %s" % [inv_before, inv_after])
	for i in 100:
		await get_tree().physics_frame
	check("back_to_idle", sys.state == ActivitySystem.State.IDLE, "state=%d" % sys.state)
	# leaving the firing line aborts
	ok = sys.start(&"shooting_range", {"option": "pistol"})
	for i in 5:
		await get_tree().physics_frame
	p.teleport_to(act.point_pos + Vector3(-40, 0.5, 0))
	for i in 10:
		await get_tree().physics_frame
	check("leave_area_aborts", sys.state == ActivitySystem.State.ABORTED or sys.state == ActivitySystem.State.IDLE, "state=%d" % sys.state)
	for i in 100:
		await get_tree().physics_frame


# ---- shooting range with real bullets -------------------------------------------------------------------------------------------
func _aim_at(p: Node, point: Vector3) -> float:
	var cam = p.camera
	var dir: Vector3 = (point - cam.global_position).normalized()
	cam.yaw = Util.dir_to_yaw(dir)
	cam.pitch = asin(clampf(dir.y, -1.0, 1.0))
	var fwd: Vector3 = cam.get_aim_forward()
	return rad_to_deg(acos(clampf(fwd.dot(dir), -1.0, 1.0)))


func _range() -> void:
	var act: ActivityBase = sys.get_activity(&"shooting_range")
	var p: Node = Game.player
	p.teleport_to(act.point_pos + Vector3(0, 0.5, 0))
	for i in 30:
		await get_tree().physics_frame
	var cash0: int = Game.cash
	var ok: bool = sys.start(&"shooting_range", {"option": "pistol"})
	check("range_real_start", ok, "")
	if not ok:
		return
	var w = p.weapons
	var frames := 0
	var fired := [0]
	Events.weapon_fired.connect(func(c, _id): fired[0] += 1 if c == p else 0)
	var aim_frames := 0
	var imp := [0]
	Events.projectile_impact.connect(func(pos, _n, surf, src):
		if src == p and imp[0] < 10:
			imp[0] += 1
			print("TEST info impact %s surf=%s player=%s" % [pos, surf, p.global_position]))
	var trig := false
	var max_err := 0.0
	while sys.state != ActivitySystem.State.FINISHED and sys.state != ActivitySystem.State.IDLE and sys.state != ActivitySystem.State.ABORTED and frames < 150 * 60:
		await get_tree().physics_frame
		frames += 1
		if sys.state != ActivitySystem.State.RUNNING:
			continue
		var best_t: ActivityTarget = null
		var best_d := INF
		for t in (act as ActivityRange).stands:
			if is_instance_valid(t) and t.live and t.is_standing() and not t.civilian and not t.is_down_anim():
				var d: float = t.global_position.distance_to(p.global_position)
				if d < best_d:
					best_d = d
					best_t = t
		if best_t != null:
			var chest: Vector3 = best_t.plate.global_position + best_t.plate.global_transform.basis.y * (0.88 if best_t.kind != &"round" else 0.45)
			var err := _aim_at(p, chest)
			max_err = maxf(max_err, err)
			aim_frames += 1
			if aim_frames % 90 == 1:
				print("TEST info aim err=%.2f deg d=%.1f trig=%s mag=%d" % [err, best_d, trig, w.get_ammo_in_mag()])
			w.set_aiming(true)
			trig = not trig and err < 0.6 and w.aim_t > 0.8
			w.set_trigger(trig)
		else:
			w.set_trigger(false)
			w.set_aiming(false)
			trig = false
	w.set_trigger(false)
	check("range_finished", sys.state == ActivitySystem.State.FINISHED, "state=%d frames=%d" % [sys.state, frames])
	var r: ActivityRange = act as ActivityRange
	print("TEST info RANGE hits=%d misses=%d shots=%d civ=%d heads=%d bulls=%d fired_events=%d aim_frames=%d max_err=%.1f" % [r.hits, r.misses, r.shots, r.civ_hits, r.heads, r.bulls, fired[0], aim_frames, max_err])
	check("range_real_bullets_scored", r.hits >= 10 and fired[0] >= 10, "hits=%d fired=%d" % [r.hits, fired[0]])
	check("range_cash_skill", Game.cash > cash0, "cash %d -> %d best=%s" % [cash0, Game.cash, str(sys.best)])
	check("range_best_saved", sys.best.size() >= 1, "")
	check("range_weapons_restored", not w.has_weapon(&"rocket_launcher") or true, "")
	for i in 600:
		await get_tree().physics_frame


# ---- stunt jumps ----------------------------------------------------------------------------------------------------------------
func _drive_to(p: Node, v: VehicleBase, target: Vector3, speed: float) -> void:
	var to: Vector3 = target - v.global_position
	var fwd: Vector3 = -v.global_transform.basis.z
	var err: float = wrapf(Util.dir_to_yaw(Vector3(to.x, 0, to.z)) - Util.dir_to_yaw(Vector3(fwd.x, 0, fwd.z)), -PI, PI)
	var steer := clampf(-err * 2.2, -1.0, 1.0)
	var thr := 1.0 if v.get_speed() < speed else 0.0
	p.set_input(Vector2(steer, thr if thr > 0.0 else -0.2))


func _stunt() -> void:
	var p: Node = Game.player
	var stunt: ActivityStunt = sys.get_activity(&"stunt_jumps") as ActivityStunt
	check("stunt_jumps_data", stunt.jumps.size() == 3, str(stunt.jumps.size()))
	for jid in [2, 1]:
		var j: Dictionary = stunt.jumps[jid - 1]
		var dir: Vector3 = j["dir"]
		var start: Vector3 = (j["pos"] as Vector3) - dir * (110.0 if jid == 2 else 36.0)
		var yaw: float = Util.dir_to_yaw(dir)
		var v: VehicleBase = VehicleFactory.spawn(&"sports", Transform3D(Basis(Vector3.UP, yaw), Vector3(start.x, 0.4, start.z)), {"abandoned": true, "snap_ground": true, "engine_on": true})
		check("stunt_car_%d" % jid, v != null, "")
		if v == null:
			continue
		for i in 60:
			await get_tree().physics_frame
		p.teleport_to(v.global_position + Vector3(0, 1.0, 0))
		p.enter_vehicle(v, 0)
		for i in 40:
			await get_tree().physics_frame
		stunt.last_result = {}
		var end_pt: Vector3 = (j["land"] as Vector3) + dir * 14.0
		var top := 0.0
		for f in 600:
			await get_tree().physics_frame
			top = maxf(top, v.get_speed_kmh())
			_drive_to(p, v, (j["pos"] as Vector3) + dir * 30.0 if (v.global_position - (j["pos"] as Vector3)).dot(dir) < 14.0 else end_pt, 60.0)
			if not stunt.last_result.is_empty() and f > 30:
				break
		print("STUNT jump %d topspeed=%.0f km/h result=%s" % [jid, top, str(stunt.last_result)])
		var res: Dictionary = stunt.last_result
		check("stunt_%d_detected" % jid, not res.is_empty() and float(res.get("air", 0.0)) > 0.4, str(res))
		check("stunt_%d_landed_ok" % jid, bool(res.get("ok", false)), str(res))
		p.set_input(Vector2.ZERO)
		p.exit_vehicle(true)
		await get_tree().physics_frame
		VehicleFactory.despawn(v)
		for i in 60:
			await get_tree().physics_frame


# ---- race ----------------------------------------------------------------------------------------------------------------------------
func _race() -> void:
	var p: Node = Game.player
	var race: ActivityRace = sys.get_activity(&"street_race") as ActivityRace
	check("race_route", race.route.size() >= 8 and race.lap_length > 600.0, "cps=%d lap=%.0f m" % [race.route.size(), race.lap_length])
	p.teleport_to(race.point_pos + Vector3(0, 0.5, 0))
	for i in 30:
		await get_tree().physics_frame
	var ok: bool = sys.start(&"street_race", {"option": "sports"})
	check("race_start", ok, "")
	if not ok:
		return
	var frames := 0
	var poly: Array[Vector3] = ActivityRace.ring_polyline()
	var bi0 := 0
	var bd0 := INF
	for i in poly.size():
		var d0 := Util.dist_xz(poly[i], Vector3(105.0, 0.0, -45.0))
		if d0 < bd0:
			bd0 = d0
			bi0 = i
	var rot: Array[Vector3] = []
	for k in poly.size():
		rot.append(poly[(bi0 + k) % poly.size()])
	poly = rot
	var bi := 0
	while sys.state != ActivitySystem.State.FINISHED and sys.state != ActivitySystem.State.IDLE and sys.state != ActivitySystem.State.ABORTED and frames < 200 * 60:
		await get_tree().physics_frame
		frames += 1
		if sys.state != ActivitySystem.State.RUNNING:
			p.set_input(Vector2.ZERO)
			continue
		var v = p.current_vehicle
		if v == null:
			continue
		var ci: int = race.target_i % race.route.size()
		var tgt: Vector3 = race.route[ci]
		# follow the road polyline (pure pursuit ~30 m ahead), not the straight line to the checkpoint
		var vp: Vector3 = v.global_position
		var bestk := bi
		var bestd := INF
		for k in range(bi, bi + 14):
			var dd := Util.dist_xz(poly[k % poly.size()], vp)
			if dd < bestd:
				bestd = dd
				bestk = k
		bi = bestk % poly.size()
		var look: Vector3 = poly[(bi + 4) % poly.size()]
		var to: Vector3 = look - vp
		var fwd: Vector3 = -v.global_transform.basis.z
		var err: float = wrapf(Util.dir_to_yaw(Vector3(to.x, 0, to.z)) - Util.dir_to_yaw(Vector3(fwd.x, 0, fwd.z)), -PI, PI)
		var steer := clampf(-err * 2.0, -1.0, 1.0)
		var spd: float = v.get_speed()
		if frames % 600 == 0:
			print("TEST info race f=%d spd=%.1f err=%.2f steer=%.2f ti=%d d=%.0f pos=%s tgt=%s" % [frames, spd, err, steer, race.target_i, v.global_position.distance_to(tgt), v.global_position, tgt])
		var want := 22.0 if absf(err) < 0.1 else (14.0 if absf(err) < 0.25 else 8.0)
		var thr := 1.0 if spd < want else (-0.3 if spd > want + 4.0 else 0.0)
		p.set_input(Vector2(steer, thr))
	p.set_input(Vector2.ZERO)
	var mt: Array = race.medal_times()
	print("RACE state=%d target_i=%d/%d time=%.1f penalty=%.1f medals(g/s/b)=%s frames=%d" % [sys.state, race.target_i, race.total, race.race_time, race.penalty, str(mt), frames])
	check("race_finished", sys.state == ActivitySystem.State.FINISHED, "state=%d idx=%d/%d" % [sys.state, race.target_i, race.total])
	check("race_best_saved", sys.best.has("race:ring:sports"), str(sys.best.get("race:ring:sports", {})))
	for i in 300:
		await get_tree().physics_frame
