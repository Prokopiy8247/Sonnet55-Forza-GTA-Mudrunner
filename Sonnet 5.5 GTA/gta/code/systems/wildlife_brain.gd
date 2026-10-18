class_name WildlifeBrain
extends RefCounted
## Land + bird behaviour (static, data driven by WildlifeDefs.SPECIES). move_*() runs every physics tick (cheap), think_*() is staggered
## by WildlifeSystem (near 0.12 s, mid 0.45 s). No navmesh: terrain height + water/slope/tree/obstacle-ray checks, short look-ahead steering.

const S_IDLE := 0
const S_WALK := 1
const S_GRAZE := 2
const S_ALERT := 3
const S_FLEE := 4
const S_EAT := 5
const S_CHASE := 6
const S_FIGHT := 7
const S_DEAD := 8
const S_FLY := 9
const S_TAKEOFF := 10
const S_LAND := 11
const S_PECK := 12
const S_PERCH := 13
const S_SWIM := 14
const S_STALK := 15
const S_ATTACK := 16
const S_RETREAT := 17

const OFFSETS: Array[float] = [0.0, 0.55, -0.55, 1.1, -1.1, 1.8, -1.8, 2.6, -2.6]


# =====================================================================================================================
# movement (every tick)
# =====================================================================================================================
static func set_state(a: Animal, s: int, dur: float = 0.0) -> void:
	a.prev_state = a.state
	a.state = s
	a.state_t = 0.0
	a.dur = dur


static func walkable_xz(x: float, z: float) -> bool:
	return WorldLayout.terrain_height(x, z) > GC.WATER_LEVEL + 0.3 or WorldLayout.on_pier(x, z)


static func ground_at(a: Animal) -> float:
	return WorldLayout.terrain_height(a.pos.x, a.pos.z) + a.ground_off


static func move_land(a: Animal, w: WildlifeWorld, dt: float) -> void:
	if a.is_dead:
		move_dead(a, dt)
		return
	var diff := Util.angle_diff(a.yaw, a.heading)
	var turn := a.turn_rate * (1.0 if a.speed > 0.4 else 0.55)
	a.yaw += clampf(diff, -turn * dt, turn * dt)
	var accel := 8.0 if a.state == S_FLEE or a.state == S_ATTACK else 3.5
	a.speed = move_toward(a.speed, a.want_speed, accel * dt)
	if a.speed > 0.02:
		var dir := Util.yaw_to_dir(a.yaw)
		var nx := a.pos.x + dir.x * a.speed * dt
		var nz := a.pos.z + dir.z * a.speed * dt
		var rise := WorldLayout.terrain_height(nx, nz) - WorldLayout.terrain_height(a.pos.x, a.pos.z)
		if walkable_xz(nx, nz) and rise < a.speed * dt * 1.2 + 0.02:
			a.pos.x = nx
			a.pos.z = nz
		else:
			a.speed = 0.0
			a.want_speed = 0.0
			a.think_t = 0.0                 # re-think right away
	var gy := ground_at(a)
	if a.airborne:
		return
	a.pos.y = gy if absf(gy - a.pos.y) > 1.5 else Util.damp(a.pos.y, gy, 22.0, dt)
	a.xf_dirty = true


static func move_dead(a: Animal, dt: float) -> void:
	a.death_time += dt
	if a.kind == &"swim":
		var target := GC.WATER_LEVEL - 0.28
		a.pos.y = Util.damp(a.pos.y, target, 0.8, dt)
		a.pos += a.take_fling() * dt
		a.xf_dirty = true
		return
	if a.airborne:
		var f := a.peek_fling()
		a.pos.x += f.x * dt
		a.pos.z += f.z * dt
		a.set_fling(f * 0.985)
		a.vy -= WildlifeDefs.GRAVITY * dt
		a.pos.y += a.vy * dt
		var gy := maxf(ground_at(a), GC.WATER_LEVEL - 0.2 if WorldLayout.is_water(a.pos.x, a.pos.z) else -1000.0)
		if a.pos.y <= gy:
			a.pos.y = gy
			a.airborne = false
			a.vy = 0.0
			a.set_fling(Vector3.ZERO)
	else:
		var gy2 := ground_at(a)
		if a.death_time > WildlifeDefs.BODY_LIFETIME:
			a.pos.y -= 0.22 * dt                      # sink into the ground and vanish
		else:
			a.pos.y = Util.damp(a.pos.y, gy2, 12.0, dt)
	a.speed = 0.0
	a.xf_dirty = true


static func move_bird(a: Animal, w: WildlifeWorld, dt: float) -> void:
	if a.is_dead:
		move_dead(a, dt)
		return
	var flying := a.state == S_FLY or a.state == S_TAKEOFF or a.state == S_LAND
	if not flying:
		move_land(a, w, dt)
		return
	var diff := Util.angle_diff(a.yaw, a.heading)
	var max_turn := 2.3 * dt
	var step := clampf(diff, -max_turn, max_turn)
	a.yaw += step
	a.roll_visual = Util.damp(a.roll_visual, clampf(-step / maxf(dt, 0.001) * 0.35, -0.55, 0.55), 5.0, dt)
	a.speed = move_toward(a.speed, a.want_speed, 4.0 * dt)
	var dir := Util.yaw_to_dir(a.yaw)
	a.pos.x += dir.x * a.speed * dt
	a.pos.z += dir.z * a.speed * dt
	var ty: float
	if a.state == S_LAND and a.perch_pos != Vector3.INF:
		var dl := Util.dist_xz(a.pos, a.perch_pos)
		ty = a.perch_pos.y + clampf((dl - 1.2) * 0.45, 0.0, 12.0)
	else:
		var base := maxf(WorldLayout.terrain_height(a.pos.x, a.pos.z), GC.WATER_LEVEL)
		ty = base + a.fly_alt
	var want_vy := clampf((ty - a.pos.y) * 1.4, -3.5, 4.6)
	if a.state == S_TAKEOFF:
		want_vy = 3.4
	a.vy = Util.damp(a.vy, want_vy, 4.0, dt)
	a.pos.y += a.vy * dt
	a.pitch_visual = Util.damp(a.pitch_visual, clampf(a.vy / maxf(a.speed, 2.0), -0.5, 0.5), 5.0, dt)
	a.flap_amp = Util.damp(a.flap_amp, 0.62 if (a.vy > 0.8 or a.state == S_TAKEOFF) else (0.05 if a.vy < -1.5 else 0.3), 3.0, dt)
	a.xf_dirty = true


# =====================================================================================================================
# perception helpers
# =====================================================================================================================
static func notice_radius(a: Animal, w: WildlifeWorld) -> float:
	var r := float(a.def.get("flee_r", 10.0))
	if w.player == null:
		return 0.0
	if w.player_in_vehicle:
		r *= 1.5 if w.player_speed > 6.0 else 0.7
	elif w.player_speed > 5.0:
		r *= 1.35
	elif w.player_speed < 0.4:
		r *= 0.45
	elif w.player_crouch:
		r *= 0.6
	if w.player_aiming:
		r *= 1.3
	return r


## Returns {pos, urgent} of the strongest current threat or {} (player proximity, fast vehicles, fresh gunshots / explosions).
static func perceive(a: Animal, w: WildlifeWorld) -> Dictionary:
	var out: Dictionary = {}
	var best := 1e9
	if w.player != null:
		var d := Util.dist_xz(a.pos, w.player_pos)
		var n := notice_radius(a, w)
		if d < n and not w.player_underwater:
			out = {"pos": w.player_pos, "urgent": d < n * 0.5, "d": d, "notice": n}
			best = d
	for v in w.vehicles:
		var vp: Vector3 = v["pos"]
		var dv := Util.dist_xz(a.pos, vp)
		if dv < 24.0 and float(v["speed"]) > 4.0 and dv < best:
			var away := a.pos - vp
			if away.dot(v["vel"]) > 0.0:
				out = {"pos": vp, "urgent": true, "d": dv, "notice": 24.0}
				best = dv
	for s in w.scares:
		var sid: int = s["id"]
		if sid > a.last_scare:
			var ds := Util.dist_xz(a.pos, s["pos"])
			if ds < float(s["r"]):
				a.last_scare = sid
				out = {"pos": s["pos"], "urgent": true, "d": ds, "notice": float(s["r"]), "delay": clampf(ds / 340.0, 0.05, 0.6)}
				best = 0.0
	return out


static func ahead_ok(a: Animal, w: WildlifeWorld, heading: float, dist: float, fleeing: bool) -> bool:
	var dir := Util.yaw_to_dir(heading)
	var x := a.pos.x + dir.x * dist
	var z := a.pos.z + dir.z * dist
	if not walkable_xz(x, z):
		return false
	if a.kind == &"land" and WildlifeRegions.tree_near(x, z, 1.1):
		return false
	if not fleeing:
		if WildlifeRegions.is_wild(a.sp) and not WorldLayout.road_at(x, z, 5.5).is_empty():
			return false
		var reg := WildlifeRegions.classify(x, z)
		if not WildlifeRegions.species_ok(a.sp, reg):
			return false
		if (a.sp == &"cow" or a.sp == &"horse") and WildlifeRegions.has_pasture and not WildlifeRegions.pasture.grow(-1.5).has_point(Vector2(x, z)):
			return false
	if a.tier == 0:
		var from := a.pos + Vector3(0.0, 0.55, 0.0)
		if not w.raycast(from, from + dir * dist, GC.L_WORLD).is_empty():
			return false
	return true


## Picks the heading closest to `desired` that passes the look-ahead checks; falls back to the desired one.
static func steer(a: Animal, w: WildlifeWorld, desired: float, fleeing: bool) -> float:
	var look := clampf(a.speed * 0.9 + 2.2, 2.2, 7.0) * (0.8 + a.model_scale * 0.2)
	for o in OFFSETS:
		if ahead_ok(a, w, desired + o, look, fleeing):
			return desired + o * 0.8
	return desired + PI * 0.75


static func refresh_ground(a: Animal, w: WildlifeWorld) -> void:
	var from := Vector3(a.pos.x, a.pos.y + 1.4, a.pos.z)
	var hit := w.raycast(from, from + Vector3(0.0, -6.0, 0.0), GC.L_WORLD)
	if hit.is_empty():
		a.ground_off = 0.0
		return
	var hp: Vector3 = hit["position"]
	var off := hp.y - WorldLayout.terrain_height(hp.x, hp.z)
	a.ground_off = off if absf(off) < 8.0 else 0.0
	var dir := Util.yaw_to_dir(a.yaw)
	var hf := WorldLayout.terrain_height(a.pos.x + dir.x * 0.6, a.pos.z + dir.z * 0.6)
	var hb := WorldLayout.terrain_height(a.pos.x - dir.x * 0.6, a.pos.z - dir.z * 0.6)
	a.slope_pitch = clampf(atan2(hf - hb, 1.2), -0.45, 0.45)


# =====================================================================================================================
# decisions: land animals
# =====================================================================================================================
static func begin_flee(a: Animal, w: WildlifeWorld, from: Vector3, delay: float, propagate: bool = true) -> void:
	if a.is_dead:
		return
	a.threat_pos = from
	a.threat_t = 0.0
	if a.state != S_FLEE:
		set_state(a, S_ALERT if delay > 0.12 else S_FLEE, 0.0)
		a.react_delay = delay
		a.flee_t = 0.0
		if a.state == S_FLEE:
			_flee_heading(a, w)
	if propagate and a.herd.size() > 1:
		for m in a.herd:
			var o: Animal = m
			if o != a and is_instance_valid(o) and not o.is_dead and o.state != S_FLEE and Util.dist_xz(o.pos, a.pos) < 45.0:
				begin_flee(o, w, from, w.rng.randf_range(0.1, 0.5), false)


static func _flee_heading(a: Animal, w: WildlifeWorld) -> void:
	var away := Util.flat(a.pos - a.threat_pos)
	if away.length() < 0.1:
		away = Util.yaw_to_dir(a.yaw)
	var desired := Util.dir_to_yaw(away) + w.rng.randf_range(-0.35, 0.35)
	a.heading = steer(a, w, desired, true)


static func think_land(a: Animal, w: WildlifeWorld, dt: float) -> void:
	if a.is_dead:
		return
	var d := a.def
	a.state_t += dt
	a.threat_t += dt
	if a.herd.size() > 1 and (a.leader == null or not is_instance_valid(a.leader) or a.leader.is_dead):
		a.leader = null
		for m in a.herd:
			var o: Animal = m
			if is_instance_valid(o) and not o.is_dead:
				if o != a:
					a.leader = o
				break
	if a.tier == 0:
		a.gy_t -= dt
		if a.gy_t <= 0.0:
			a.gy_t = 0.35
			refresh_ground(a, w)
	var run_speed := float(d["run"])
	var threat := perceive(a, w)
	# ---- fighting back (bold animals that were hurt) --------------------------------------------------------------------
	if a.state == S_FIGHT:
		_think_fight(a, w, dt)
		return
	if not threat.is_empty():
		a.threat_pos = threat["pos"]
		a.threat_t = 0.0
		var td: float = threat["d"]
		var urgent: bool = threat["urgent"]
		if a.state == S_FLEE:
			a.flee_t = 0.0
		elif urgent or td < float(threat["notice"]) * 0.45:
			begin_flee(a, w, threat["pos"], float(threat.get("delay", w.rng.randf_range(0.05, 0.3))))
		elif a.state != S_ALERT:
			set_state(a, S_ALERT, 0.0)
			a.react_delay = w.rng.randf_range(0.5, 1.4)
			a.want_speed = 0.0
			if a.herd.size() > 1:
				for m in a.herd:
					var o2: Animal = m
					if o2 != a and is_instance_valid(o2) and not o2.is_dead and o2.state != S_FLEE and o2.state != S_ALERT and Util.dist_xz(o2.pos, a.pos) < 40.0:
						set_state(o2, S_ALERT, 0.0)
						o2.react_delay = w.rng.randf_range(0.6, 1.5)
						o2.threat_pos = threat["pos"]
						o2.want_speed = 0.0
	match a.state:
		S_ALERT:
			a.want_speed = 0.0
			if a.state_t > a.react_delay:
				if threat.is_empty():
					set_state(a, S_IDLE, w.rng.randf_range(2.0, 4.0))
				else:
					begin_flee(a, w, a.threat_pos, 0.0)
			elif a.threat_t > 3.0:
				set_state(a, S_IDLE, w.rng.randf_range(2.0, 4.0))
		S_FLEE:
			var closeness := 0.0
			if a.threat_pos != Vector3.INF:
				closeness = clampf(1.0 - Util.dist_xz(a.pos, a.threat_pos) / 28.0, 0.2, 1.0)
			a.want_speed = lerpf(float(d["trot"]), run_speed, closeness)
			a.turn_rate = 7.0
			_flee_heading(a, w)
			a.flee_t += dt
			if threat.is_empty() and (a.threat_t > 4.0 or (a.threat_pos != Vector3.INF and Util.dist_xz(a.pos, a.threat_pos) > 55.0)):
				a.turn_rate = 4.0
				set_state(a, S_IDLE, w.rng.randf_range(2.0, 5.0))
				a.home = a.pos
		S_IDLE, S_GRAZE, S_EAT:
			a.want_speed = 0.0
			if a.state_t > a.dur:
				_next_activity(a, w)
		S_WALK:
			_think_walk(a, w, dt)
	if a.state != S_FLEE:
		a.turn_rate = lerpf(a.turn_rate, 3.5, 0.3)
	_voice(a, w)


static func _next_activity(a: Animal, w: WildlifeWorld) -> void:
	var d := a.def
	var r := w.rng.randf()
	if a.leader != null and is_instance_valid(a.leader) and (a.leader.state == S_WALK or Util.dist_xz(a.pos, a.leader.pos) > 10.0):
		set_state(a, S_WALK, w.rng.randf_range(6.0, 12.0))
		a.goal = Vector3.INF
		return
	if r < 0.5 and bool(d.get("graze", false)):
		set_state(a, S_GRAZE, w.rng.randf_range(5.0, 12.0))
	elif r < 0.68:
		set_state(a, S_IDLE, w.rng.randf_range(2.0, 6.0))
	else:
		set_state(a, S_WALK, w.rng.randf_range(6.0, 16.0))
		a.goal = _pick_goal(a, w)
		if a.goal == Vector3.INF:
			set_state(a, S_IDLE, w.rng.randf_range(2.0, 4.0))


static func _pick_goal(a: Animal, w: WildlifeWorld) -> Vector3:
	for i in 6:
		var ang := w.rng.randf() * TAU
		var dist := w.rng.randf_range(4.0, 16.0)
		var gx := a.pos.x + cos(ang) * dist
		var gz := a.pos.z + sin(ang) * dist
		if not walkable_xz(gx, gz):
			continue
		if not WildlifeRegions.species_ok(a.sp, WildlifeRegions.classify(gx, gz)):
			continue
		if a.kind == &"land" and WildlifeRegions.tree_near(gx, gz, 1.2):
			continue
		if WildlifeRegions.is_wild(a.sp) and not WorldLayout.road_at(gx, gz, 6.0).is_empty():
			continue
		if (a.sp == &"cow" or a.sp == &"horse") and WildlifeRegions.has_pasture and not WildlifeRegions.pasture.grow(-2.0).has_point(Vector2(gx, gz)):
			continue
		return Vector3(gx, 0.0, gz)
	return Vector3.INF


static func _think_walk(a: Animal, w: WildlifeWorld, dt: float) -> void:
	var d := a.def
	var spd := float(d["walk"])
	var lead := a.leader
	if lead != null and is_instance_valid(lead) and not lead.is_dead:
		var gp := lead.pos + Vector3(a.follow_off.x, 0.0, a.follow_off.y)
		var dl := Util.dist_xz(a.pos, gp)
		if dl < 2.5 and lead.state != S_WALK:
			set_state(a, S_GRAZE if bool(d.get("graze", false)) else S_IDLE, w.rng.randf_range(4.0, 9.0))
			return
		a.goal = gp
		spd *= 1.0 + clampf((dl - 4.0) / 8.0, 0.0, 1.0) * 2.2
	if a.goal == Vector3.INF:
		if lead == null or not is_instance_valid(lead):
			set_state(a, S_IDLE, w.rng.randf_range(2.0, 4.0))
		return
	var to := Util.flat(a.goal - a.pos)
	if to.length() < 1.4 or a.state_t > a.dur:
		set_state(a, S_IDLE, w.rng.randf_range(2.0, 5.0))
		return
	a.heading = steer(a, w, Util.dir_to_yaw(to), false)
	a.want_speed = minf(spd, float(d["trot"]))


static func _think_fight(a: Animal, w: WildlifeWorld, dt: float) -> void:
	var tgt := a.target
	if tgt == null or not is_instance_valid(tgt) or w.now > a.fight_until or bool(tgt.get("is_dead")):
		a.target = null
		set_state(a, S_IDLE, 3.0)
		return
	var tp: Vector3 = (tgt as Node3D).global_position
	var dist := Util.dist_xz(a.pos, tp)
	a.heading = Util.dir_to_yaw(Util.flat(tp - a.pos))
	a.bite_cd -= dt
	if dist > 1.5:
		a.want_speed = float(a.def["run"]) * 0.8
	else:
		a.want_speed = 0.0
		if a.bite_cd <= 0.0:
			a.bite_cd = 1.3
			a.jaw_open = 1.0
			var dmg := float(a.def.get("bite", 5.0))
			if tgt.has_method("apply_damage"):
				tgt.apply_damage(dmg, {"source": a, "type": GC.DMG_ANIMAL, "zone": GC.ZONE_LIMB, "position": tp + Vector3.UP, "direction": Util.yaw_to_dir(a.yaw), "weapon": &"bite"})
			if tgt.is_in_group(GC.G_PLAYER) and Game.gameplay_camera != null and Game.gameplay_camera.has_method("add_shake"):
				Game.gameplay_camera.add_shake(0.18, 0.25)
			a.bites_left -= 1
			if a.bites_left <= 0:
				a.target = null
				begin_flee(a, w, tp, 0.0, false)
	if dist > 45.0:
		a.target = null
		set_state(a, S_IDLE, 3.0)


static func _voice(a: Animal, w: WildlifeWorld) -> void:
	var vid: StringName = a.def.get("voice", &"")
	if vid == &"" or a.tier != 0:
		return
	if w.now < a.next_voice:
		return
	a.next_voice = w.now + w.rng.randf_range(14.0, 40.0)
	if Util.dist_xz(a.pos, w.player_pos) < 45.0:
		w.voice(a, vid, -4.0)


# =====================================================================================================================
# decisions: birds
# =====================================================================================================================
static func land_bird_on(a: Animal, p: Vector3) -> void:
	a.pos = p
	a.speed = 0.0
	a.want_speed = 0.0
	a.airborne = false
	a.vy = 0.0
	a.ground_off = p.y - WorldLayout.terrain_height(p.x, p.z)
	a.set_model_variant(1)
	a.perch_pos = Vector3.INF
	a.pitch_visual = 0.0
	a.roll_visual = 0.0
	set_state(a, S_PERCH, 4.0)
	a.xf_dirty = true


static func take_off(a: Animal, w: WildlifeWorld, away_from: Vector3) -> void:
	a.set_model_variant(0)
	a.airborne = false
	a.vy = 2.0
	set_state(a, S_TAKEOFF, 1.1)
	a.want_speed = float(a.def.get("fly", 8.0))
	a.speed = maxf(a.speed, 2.0)
	a.fly_alt = w.rng.randf_range(7.0, 16.0)
	var dir := Util.flat(a.pos - away_from) if away_from != Vector3.INF else Util.yaw_to_dir(a.yaw)
	a.heading = Util.dir_to_yaw(dir) + w.rng.randf_range(-0.5, 0.5)
	a.perch_pos = Vector3.INF
	a.flap_amp = 0.7
	if a.tier == 0 and Util.dist_xz(a.pos, w.player_pos) < 40.0:
		var vid: StringName = a.def.get("voice", &"")
		if vid != &"" and w.rng.randf() < 0.5:
			w.voice(a, vid, -3.0)


static func think_bird(a: Animal, w: WildlifeWorld, dt: float) -> void:
	if a.is_dead:
		return
	a.state_t += dt
	var d := a.def
	var fly_speed := float(d.get("fly", 8.0))
	var flying := a.state == S_FLY or a.state == S_TAKEOFF or a.state == S_LAND
	if not flying and a.tier == 0:
		a.gy_t -= dt
		if a.gy_t <= 0.0:
			a.gy_t = 0.5
			if a.state != S_PERCH and a.state != S_PECK or a.speed > 0.05:
				refresh_ground(a, w)
	if not flying:
		var threat := perceive(a, w)
		if not threat.is_empty() and (bool(threat["urgent"]) or float(threat["d"]) < float(threat["notice"])):
			take_off(a, w, threat["pos"])
			return
	match a.state:
		S_PERCH, S_PECK, S_ALERT, S_IDLE:
			a.want_speed = 0.0
			if a.state_t > a.dur:
				var r := w.rng.randf()
				var long_idle := a.state_t > 14.0
				if r < 0.08 + (0.25 if long_idle and a.sp == &"seagull" else 0.0):
					take_off(a, w, Vector3.INF)
				elif r < 0.45:
					set_state(a, S_PECK, w.rng.randf_range(2.5, 6.0))
				elif r < 0.62 and bool(WildlifeDefs.SPECIES[a.sp].get("kind", &"") == &"bird"):
					set_state(a, S_WALK, w.rng.randf_range(2.0, 4.5))
					a.goal = _pick_bird_walk(a, w)
				else:
					set_state(a, S_PERCH, w.rng.randf_range(3.0, 8.0))
		S_WALK:
			a.want_speed = 0.0
			if a.goal != Vector3.INF:
				var to := Util.flat(a.goal - a.pos)
				if to.length() > 0.5 and a.state_t < a.dur:
					a.heading = Util.dir_to_yaw(to)
					a.want_speed = float(d["walk"]) * 0.8
				else:
					set_state(a, S_PECK, w.rng.randf_range(2.0, 4.0))
			else:
				set_state(a, S_PERCH, 3.0)
		S_TAKEOFF:
			a.want_speed = fly_speed
			if a.state_t > a.dur:
				set_state(a, S_FLY, w.rng.randf_range(14.0, 34.0))
				a.goal = _bird_goal(a, w)
		S_FLY:
			a.want_speed = fly_speed
			var to2 := Util.flat(a.goal - a.pos) if a.goal != Vector3.INF else Vector3.ZERO
			if a.goal == Vector3.INF or to2.length() < 6.0:
				a.goal = _bird_goal(a, w)
				to2 = Util.flat(a.goal - a.pos)
			a.heading = Util.dir_to_yaw(to2)
			if a.state_t > a.dur:
				var perch := WildlifeRegions.nearest_perch(a.pos, 80.0, w.rng, _taken_perches(w))
				if perch != Vector3.INF:
					a.perch_pos = perch
					set_state(a, S_LAND, 12.0)
				else:
					a.dur += 10.0
		S_LAND:
			if a.perch_pos == Vector3.INF:
				set_state(a, S_FLY, 8.0)
				return
			var to3 := Util.flat(a.perch_pos - a.pos)
			var dl := to3.length()
			a.heading = Util.dir_to_yaw(to3)
			a.want_speed = clampf(dl * 0.7, 2.2, fly_speed)
			if (dl < 0.9 and absf(a.pos.y - a.perch_pos.y) < 0.6) or a.state_t > a.dur:
				if dl < 3.0:
					land_bird_on(a, a.perch_pos)
				else:
					set_state(a, S_FLY, 10.0)
					a.goal = _bird_goal(a, w)
	_voice(a, w)


static func _taken_perches(w: WildlifeWorld) -> Array:
	var out: Array = []
	for o in w.animals:
		var an: Animal = o
		if an.kind == &"bird" and an.state == S_PERCH:
			out.append(an.pos)
	return out


static func _pick_bird_walk(a: Animal, w: WildlifeWorld) -> Vector3:
	for i in 4:
		var ang := w.rng.randf() * TAU
		var dd := w.rng.randf_range(1.0, 3.5)
		var gx := a.pos.x + cos(ang) * dd
		var gz := a.pos.z + sin(ang) * dd
		if walkable_xz(gx, gz) and absf(WorldLayout.terrain_height(gx, gz) + a.ground_off - a.pos.y) < 0.3:
			return Vector3(gx, 0.0, gz)
	return Vector3.INF


static func _bird_goal(a: Animal, w: WildlifeWorld) -> Vector3:
	var ang := w.rng.randf() * TAU
	var dd := w.rng.randf_range(25.0, 70.0)
	var g := a.pos + Vector3(cos(ang) * dd, 0.0, sin(ang) * dd)
	# gulls like the coast: bias towards the shoreline band
	if a.sp == &"seagull":
		g.z = lerpf(g.z, 175.0, 0.45)
	# keep birds around the player's area (despawned when far)
	var pull := Util.flat(w.player_pos - g)
	if pull.length() > 90.0:
		g += pull.normalized() * 40.0
	g.x = clampf(g.x, -285.0, 285.0)
	g.z = clampf(g.z, -285.0, 380.0)
	return g
