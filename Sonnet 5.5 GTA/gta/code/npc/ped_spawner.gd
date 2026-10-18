class_name PedSpawner
extends RefCounted
## Decides WHO spawns WHERE for PedManager: picks ped-graph points in the ring around the player that nobody can see, rolls the
## district / time dependent scene (stroller, jogger, bench sitter, talking pair, bus-stop waiter, sunbather) and creates it.

const TOWEL_COLORS: Array[Color] = [Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347"), Color("#f2f0ea"), Color("#4f9d52"), Color("#e8795f"), Color("#5b7fa6")]

var m: PedManager = null
var instant := false                  # set by fill(): the boot / teleport fill may spawn in view
var _min_d := PedDefs.RING_HIDDEN_MIN
var scenes := {"walker": 0, "jogger": 0, "sitter": 0, "talker": 0, "waiter": 0, "sunbather": 0}


func _init(manager) -> void:
	m = manager


## Outfit style for a district (and graph zone when known: -1 = unknown).
func look_for_district(d: StringName, zone: int) -> StringName:
	var w: Dictionary
	match d:
		GC.D_DOWNTOWN:
			w = {"business": 0.50, "casual": 0.30, "tourist": 0.08, "elder": 0.06, "worker": 0.04, "jogger": 0.02}
		GC.D_RESIDENTIAL:
			w = {"casual": 0.60, "elder": 0.11, "business": 0.08, "jogger": 0.09, "tourist": 0.02, "worker": 0.10}
		GC.D_INDUSTRIAL:
			w = {"worker": 0.72, "casual": 0.16, "business": 0.08, "elder": 0.04}
		GC.D_WATERFRONT:
			w = {"worker": 0.40, "casual": 0.32, "tourist": 0.20, "elder": 0.04, "jogger": 0.04}
		GC.D_BEACH:
			w = {"beach": 0.66, "tourist": 0.14, "jogger": 0.10, "casual": 0.07, "elder": 0.03}
		GC.D_PARK:
			w = {"casual": 0.38, "jogger": 0.28, "tourist": 0.14, "elder": 0.12, "beach": 0.0, "business": 0.08}
		GC.D_AIRPORT:
			w = {"business": 0.42, "tourist": 0.30, "worker": 0.28}
		_:
			w = {"casual": 0.7, "business": 0.2, "tourist": 0.1}
	if zone == PedGraph.ZONE_PARK:
		w["jogger"] = float(w.get("jogger", 0.0)) + 0.25
	elif zone == PedGraph.ZONE_BEACH:
		w["beach"] = float(w.get("beach", 0.0)) + 0.35
	elif zone == PedGraph.ZONE_DOCK:
		w["worker"] = float(w.get("worker", 0.0)) + 0.2
		w["tourist"] = float(w.get("tourist", 0.0)) + 0.15
	var hour := Game.time_of_day
	if hour < 6.5 or hour > 21.0:
		w["jogger"] = float(w.get("jogger", 0.0)) * 0.3
	elif hour < 9.0 and (zone == PedGraph.ZONE_PARK or d == GC.D_PARK):
		w["jogger"] = float(w.get("jogger", 0.0)) + 0.3
	return PedDefs.weighted(w, m.rng)


## Spawns up to `budget` scenes. Returns the number of pedestrians created.
## `instant` (boot / teleport): the area around the player is populated at once, also inside the view (the scene has just appeared anyway).
func fill(budget: int, instant_fill: bool = false) -> int:
	instant = instant_fill
	var pg := WorldLayout.ped_graph
	if pg.size() == 0 or m.player == null:
		return 0
	var created := 0
	var scenes_done := 0
	var tries := budget * 8 + 6
	var center: Vector3 = m.player_pos
	var pv: Vector3 = m.player_vel
	if Vector2(pv.x, pv.z).length() > 7.0:
		center += Vector3(pv.x, 0.0, pv.z).normalized() * 40.0      # driving: populate the road ahead
	var min_d: float = PedDefs.INSTANT_MIN if instant else PedDefs.RING_HIDDEN_MIN
	_min_d = min_d
	for t in tries:
		if scenes_done >= budget:
			break
		# distance band: most of the population lives close to the player
		var pick: float = m.rng.randf()
		var r0: float = 0.0
		var r1: float = PedDefs.RING_MAX
		for band in PedDefs.RING_BANDS:
			pick -= float(band[0])
			if pick <= 0.0:
				r0 = float(band[1])
				r1 = float(band[2])
				break
		var idx := pg.random_point_in_ring(center, maxf(r0, min_d), r1, m.rng, 5)
		if idx < 0:
			continue
		var pos := PedNav.node_pos(idx)
		var zone: int = pg.zone[idx]
		if zone == PedGraph.ZONE_CROSSING or zone == PedGraph.ZONE_INDOOR or PedNav.no_go(idx):
			continue
		var d := Util.dist_xz(pos, m.player_pos)
		if d < min_d:
			continue
		var district := WorldLayout.district_at(pos.x, pos.z)
		if district == GC.D_SEA:
			continue
		var dens := PedDefs.density(district, Game.time_of_day)
		if m.rng.randf() > clampf(dens * 1.15, 0.05, 1.0):
			continue
		if PedNav.blocked(pos.x, pos.z, 0.35) or _crowded(pos, 1.7):
			continue
		if not instant and m.is_ped_visible(pos):
			m.stats["visible_rejects"] += 1
			continue
		var n := _spawn_scene(idx, pos, zone, district)
		if n > 0:
			created += n
			scenes_done += 1
	return created


## True when nobody can see `p` (or the instant fill is running): the final spot of a scene must be hidden too, not only the sampled point.
func _hidden(p: Vector3) -> bool:
	var d := Util.dist_xz(p, m.player_pos)
	if instant:
		return d >= PedDefs.INSTANT_MIN
	return d >= _min_d and not m.is_ped_visible(p)


func _crowded(pos: Vector3, r: float) -> bool:
	for c in m.query_radius(pos, r):
		if not (c as Pedestrian).is_dead:
			return true
	return false


func _spawn_scene(idx: int, pos: Vector3, zone: int, district: StringName) -> int:
	var hour := Game.time_of_day
	var r: float = m.rng.randf()
	var rain := Game.weather == GC.W_RAIN or Game.weather == GC.W_STORM
	var open_zone := zone == PedGraph.ZONE_SIDEWALK or zone == PedGraph.ZONE_PLAZA or zone == PedGraph.ZONE_PARK or zone == PedGraph.ZONE_BEACH
	# ---- sunbathers on the sand
	if zone == PedGraph.ZONE_BEACH and not rain and hour > 9.5 and hour < 19.0 and r < 0.40:
		if _spawn_sunbather(pos):
			return 1
	# ---- bench sitters
	if open_zone and r < 0.55:
		var bi := _free_bench_near(pos, 9.0)
		if bi >= 0:
			var n := _spawn_sitter(bi)
			if n > 0:
				return n
	# ---- bus stop waiters
	if zone == PedGraph.ZONE_SIDEWALK and m.bus_stop_near(pos, 4.0) and m.rng.randf() < 0.55:
		return _spawn_waiters(idx, pos)
	# ---- talking pairs / trios
	if open_zone and m.rng.randf() < 0.075:
		var n2 := _spawn_talkers(idx, pos, district)
		if n2 > 0:
			return n2
	# ---- ordinary stroller or jogger
	var look: StringName = look_for_district(district, zone)
	var role: StringName = &"jogger" if look == &"jogger" else &"walker"
	if role == &"jogger" and zone != PedGraph.ZONE_PARK and zone != PedGraph.ZONE_BEACH and zone != PedGraph.ZONE_SIDEWALK:
		role = &"walker"
	var ped: Pedestrian = m._spawn(look, role, pos, m.rng.randf() * TAU, {"node": idx, "require_hidden": not instant})
	if ped == null:
		return 0
	scenes[String(role)] = int(scenes.get(String(role), 0)) + 1
	ped.scene_tag = role
	return 1


# ---- scenes ------------------------------------------------------------------------------------------------------------------
func _spawn_sunbather(near: Vector3) -> bool:
	for k in 8:
		var a: float = m.rng.randf() * TAU
		var dist: float = m.rng.randf_range(3.0, 10.0)
		var p := near + Vector3(cos(a) * dist, 0.0, sin(a) * dist)
		if WorldLayout.is_water(p.x, p.z) or WorldLayout.surface_at(p.x, p.z) != &"sand":
			continue
		var h := WorldLayout.terrain_height(p.x, p.z)
		if h < -0.25 or _crowded(p, 2.6) or not _hidden(p):
			continue
		p.y = h + 0.02
		var yaw: float = m.rng.randf() * TAU
		var ped: Pedestrian = m._spawn(&"beach", &"sunbather", p, yaw, {"stationary": true})
		if ped == null:
			return false
		ped.brain.begin_sunbathe(yaw, m.rng.randf_range(70.0, 240.0), TOWEL_COLORS[m.rng.randi() % TOWEL_COLORS.size()])
		ped.scene_tag = &"sunbather"
		scenes["sunbather"] += 1
		return true
	return false


func _free_bench_near(pos: Vector3, r: float) -> int:
	var best := -1
	var best_d := r
	for i in m.benches.size():
		var b: Dictionary = m.benches[i]
		var taken: Array = b["taken"]
		if taken[0] and taken[1]:
			continue
		var d := Util.dist_xz(b["pos"], pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _spawn_sitter(bench_i: int) -> int:
	var b: Dictionary = m.benches[bench_i]
	var taken: Array = b["taken"]
	var side := 0 if not taken[0] else 1
	if m.rng.randf() < 0.5 and not taken[1]:
		side = 1
	var yaw: float = float(b["yaw"])
	var bp: Vector3 = b["pos"]
	if not _hidden(bp):
		return 0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Util.yaw_to_dir(yaw)
	var seat := bp + right * (0.42 if side == 0 else -0.42) - fwd * 0.04
	var look: StringName = look_for_district(WorldLayout.district_at(bp.x, bp.z), -1)
	if look == &"jogger":
		look = &"casual"
	var ped: Pedestrian = m._spawn(look, &"sitter", Vector3(seat.x, bp.y, seat.z), yaw, {"stationary": true})
	if ped == null:
		return 0
	taken[side] = true
	ped.brain.begin_sit(seat, yaw, bench_i * 2 + side, m.rng.randf_range(25.0, 110.0), bp.y)
	ped.scene_tag = &"sitter"
	scenes["sitter"] += 1
	var n := 1
	# two people on one bench now and then
	if not taken[1 - side] and m.rng.randf() < 0.3:
		var side2 := 1 - side
		var seat2 := bp + right * (0.42 if side2 == 0 else -0.42) - fwd * 0.04
		var p2: Pedestrian = m._spawn(look, &"sitter", Vector3(seat2.x, bp.y, seat2.z), yaw, {"stationary": true})
		if p2 != null:
			taken[side2] = true
			p2.brain.begin_sit(seat2, yaw, bench_i * 2 + side2, m.rng.randf_range(25.0, 110.0), bp.y)
			p2.scene_tag = &"sitter"
			scenes["sitter"] += 1
			n += 1
	return n


func _spawn_waiters(idx: int, pos: Vector3) -> int:
	var pg := WorldLayout.ped_graph
	var face := Vector3.INF
	var br: PedBrain = null
	var count: int = 1 + (1 if m.rng.randf() < 0.5 else 0) + (1 if m.rng.randf() < 0.2 else 0)
	var made := 0
	var d: StringName = WorldLayout.district_at(pos.x, pos.z)
	for k in count:
		var off := Vector3(m.rng.randf_range(-1.4, 1.4), 0.0, m.rng.randf_range(-1.4, 1.4))
		var p := pos + off
		if PedNav.blocked(p.x, p.z, 0.3) and k > 0:
			continue
		var ped: Pedestrian = m._spawn(look_for_district(d, PedGraph.ZONE_SIDEWALK), &"waiter", p, m.rng.randf() * TAU, {"node": idx, "stationary": true, "require_hidden": not instant})
		if ped == null:
			continue
		br = ped.brain
		if face == Vector3.INF:
			face = br._road_facing(p)
			if face == Vector3.INF:
				face = Vector3(0, 0, -1)
		br.begin_idle(PedBrain.IDLE_STYLES[m.rng.randi() % 3], m.rng.randf_range(20.0, 60.0), Util.dir_to_yaw(face) + m.rng.randf_range(-0.4, 0.4), true)
		br.activity_kind = &"bus_stop"
		br.idle_look_target = p + face * 20.0 + Vector3(0, 1.5, 0)
		br.n_cur = idx
		ped.scene_tag = &"waiter"
		scenes["waiter"] += 1
		made += 1
	return made


func _spawn_talkers(idx: int, pos: Vector3, district: StringName) -> int:
	var pg := WorldLayout.ped_graph
	# stand along the pavement so the walkway stays free
	var axis := Vector3(1, 0, 0)
	var links: PackedInt32Array = pg.links[idx]
	if links.size() > 0:
		var dv := pg.positions[links[0]] - pos
		dv.y = 0.0
		if dv.length() > 0.1:
			axis = dv.normalized()
	var a_pos := pos + axis * 0.62
	var b_pos := pos - axis * 0.62
	if PedNav.blocked(a_pos.x, a_pos.z, 0.3) or PedNav.blocked(b_pos.x, b_pos.z, 0.3):
		return 0
	var look_a: StringName = look_for_district(district, pg.zone[idx])
	var look_b: StringName = look_for_district(district, pg.zone[idx])
	if look_a == &"jogger":
		look_a = &"casual"
	if look_b == &"jogger":
		look_b = &"casual"
	var yaw_a := Util.dir_to_yaw(-axis)
	var yaw_b := Util.dir_to_yaw(axis)
	var a: Pedestrian = m._spawn(look_a, &"talker", a_pos, yaw_a, {"stationary": true, "node": idx, "require_hidden": not instant})
	if a == null:
		return 0
	var b: Pedestrian = m._spawn(look_b, &"talker", b_pos, yaw_b, {"stationary": true, "node": idx, "require_hidden": not instant})
	if b == null:
		m.release(a)                  # the partner would have been visible: no lonely half of a conversation
		return 0
	var seconds: float = m.rng.randf_range(14.0, 50.0)
	a.brain.begin_talk(b, yaw_a, seconds)
	b.brain.begin_talk(a, yaw_b, seconds)
	a.brain.n_cur = idx
	b.brain.n_cur = idx
	a.scene_tag = &"talker"
	b.scene_tag = &"talker"
	a.group_id = m.stats["spawned"]
	b.group_id = a.group_id
	scenes["talker"] += 2
	return 2
