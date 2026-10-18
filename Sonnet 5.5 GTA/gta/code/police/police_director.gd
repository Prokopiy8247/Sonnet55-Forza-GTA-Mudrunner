class_name PoliceDirector
extends RefCounted
## The DECISION side of the police director (Police-A): force tables per star level, spawn-site search (lane graph / ped graph, outside the
## camera frustum, >= 80 m away), role picking and order building. No scene ownership - PoliceManager (the Node) owns the units and
## executes what this object decides, so everything here is unit-testable.

const MAX_VEHICLES := 10         # police cars + vans (+ helis counted separately)
const MAX_OFFICERS := 20
const MAX_HELIS := 2
const MIN_SPAWN_DIST := 80.0
const CONVERGE_RADIUS := 35.0    # search orders start this tight around the last known position ...
const CONVERGE_TIME := 25.0      # ... and widen to the full search radius over this many seconds

## Desired force per wanted level. cars = patrol cruisers (2 officers each), vans = tactical vans, foot = extra foot officers (swat of them
## are heavy tactical officers), heli = helicopters, blocks = concurrent roadblocks, aggr = base aggression 0..1, lethal = shoot to kill.
static var force_table: Dictionary = {
	0: {"cars": 0, "vans": 0, "foot": 0, "swat": 0, "heli": 0, "blocks": 0, "aggr": 0.0, "lethal": false},
	1: {"cars": 1, "vans": 0, "foot": 2, "swat": 0, "heli": 0, "blocks": 0, "aggr": 0.25, "lethal": false},
	2: {"cars": 3, "vans": 0, "foot": 2, "swat": 0, "heli": 0, "blocks": 0, "aggr": 0.55, "lethal": true},
	3: {"cars": 4, "vans": 0, "foot": 3, "swat": 1, "heli": 1, "blocks": 1, "aggr": 0.75, "lethal": true},
	4: {"cars": 5, "vans": 1, "foot": 4, "swat": 3, "heli": 1, "blocks": 2, "aggr": 0.9, "lethal": true},
	5: {"cars": 6, "vans": 2, "foot": 4, "swat": 4, "heli": 2, "blocks": 1, "aggr": 1.0, "lethal": true},
}

var rng := RandomNumberGenerator.new()
var stats := {"site_calls": 0, "site_ok": 0, "rej_view": 0, "rej_near": 0, "rej_overlap": 0, "rej_graph": 0, "rej_spacing": 0}

var _box := BoxShape3D.new()
var _shape_q := PhysicsShapeQueryParameters3D.new()


func _init() -> void:
	rng.randomize()
	_box.size = Vector3(2.4, 1.8, 5.2)
	_shape_q.shape = _box
	_shape_q.collision_mask = GC.L_VEHICLE | GC.L_PLAYER | GC.L_NPC
	_shape_q.margin = 0.05


# ---- force --------------------------------------------------------------------------------------------------------------------------
func force_for(level: int, state: StringName) -> Dictionary:
	var f: Dictionary = (force_table.get(clampi(level, 0, 5), force_table[0]) as Dictionary).duplicate()
	if level > 0 and state == &"search":
		f["cars"] = maxi(int(round(float(f["cars"]) * 0.75)), 1)
		f["blocks"] = 0
		f["aggr"] = float(f["aggr"]) * 0.7
		f["lethal"] = false
	return f


## Which flavour the next patrol car takes: the first tails the player, the second cuts ahead, then flankers; rolling blockers at 5 stars.
func pick_role(level: int, cars_by_role: Dictionary) -> StringName:
	var tail := int(cars_by_role.get(&"tail", 0))
	var inter := int(cars_by_role.get(&"intercept", 0))
	var flank := int(cars_by_role.get(&"flank", 0))
	var block := int(cars_by_role.get(&"block", 0))
	if tail == 0:
		return &"tail"
	if level >= 2 and inter == 0:
		return &"intercept"
	if level >= 3 and flank == 0:
		return &"flank"
	if level >= 5 and block < 2:
		return &"block"
	if inter <= tail and level >= 2:
		return &"intercept"
	return &"flank" if flank <= tail else &"tail"


# ---- site search --------------------------------------------------------------------------------------------------------------------
## True when the camera could see a vehicle standing at pos (frustum test on the centre + ends, unless world geometry hides it).
func visible_to_camera(cam: Camera3D, pos: Vector3, dir: Vector3, space: PhysicsDirectSpaceState3D = null) -> bool:
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return false
	var d := Util.flat(dir)
	d = d.normalized() if d.length() > 0.01 else Vector3(0, 0, -1)
	var pts: Array[Vector3] = [pos + Vector3.UP * 1.0, pos + Vector3.UP * 2.0, pos + d * 2.4 + Vector3.UP * 1.0, pos - d * 2.4 + Vector3.UP * 1.0]
	for p in pts:
		if cam.is_position_in_frustum(p):
			if space != null:
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, p, GC.M_LOS)
				if not space.intersect_ray(q).is_empty():
					continue    # in the frustum but behind a wall / hill
			return true
	return false


## req: center (ring centre: player or last known), player, camera, space, min_dist, max_dist, pref_dist, want (&"any" &"ahead" &"behind" &"side"),
## heading (flat unit, ZERO = none), avoid (Array[Vector3] positions that must keep their distance), station (bool: try the police_station first).
## -> {pos, dir, idx, dist, source} or {}.
func find_road_site(req: Dictionary) -> Dictionary:
	stats["site_calls"] = int(stats["site_calls"]) + 1
	var lanes: LaneGraph = WorldLayout.lanes
	if lanes == null or lanes.size() == 0:
		stats["rej_graph"] = int(stats["rej_graph"]) + 1
		return {}
	var center: Vector3 = req.get("center", Vector3.ZERO)
	var player: Vector3 = req.get("player", center)
	var cam: Camera3D = req.get("camera", null)
	var space: PhysicsDirectSpaceState3D = req.get("space", null)
	var min_d := float(req.get("min_dist", MIN_SPAWN_DIST))
	var max_d := float(req.get("max_dist", 260.0))
	var pref := float(req.get("pref_dist", (min_d + max_d) * 0.5))
	var want: StringName = req.get("want", &"any")
	var heading: Vector3 = req.get("heading", Vector3.ZERO)
	var avoid: Array = req.get("avoid", [])
	var cam_pos: Vector3 = cam.global_position if (cam != null and is_instance_valid(cam)) else player
	if bool(req.get("station", false)):
		var loc := WorldLayout.get_location(&"police_station")
		if not loc.is_empty():
			var idx := lanes.nearest(loc.get("pos", Vector3.ZERO), Vector3.ZERO, 40.0)
			if idx >= 0:
				var sc := _check_site(lanes, idx, player, cam, cam_pos, space, min_d, avoid)
				if sc > -INF:
					stats["site_ok"] = int(stats["site_ok"]) + 1
					return _site(lanes, idx, player, &"station")
	var best := -1
	var best_score := -INF
	var valid := 0
	for t in 70:
		var idx2 := lanes.random_point_in_ring(center, min_d, max_d, rng, 6)
		if idx2 < 0:
			continue
		var base := _check_site(lanes, idx2, player, cam, cam_pos, space, min_d, avoid)
		if base == -INF:
			continue
		valid += 1
		var pos := lanes.positions[idx2]
		var to_site := pos - player
		to_site.y = 0.0
		var d := to_site.length()
		var dirn := to_site / maxf(d, 0.01)
		var score := base - absf(d - pref) * 0.012
		match want:
			&"ahead":
				if heading != Vector3.ZERO:
					score += heading.dot(dirn) * 2.2
			&"behind":
				if heading != Vector3.ZERO:
					score += -heading.dot(dirn) * 1.6
			&"side":
				if heading != Vector3.ZERO:
					score += (1.0 - absf(heading.dot(dirn))) * 1.6
		# lanes that point towards the player: the car is already facing its target
		score += maxf(lanes.dirs[idx2].dot(-dirn), 0.0) * 0.7
		score += rng.randf() * 0.5
		if score > best_score:
			best_score = score
			best = idx2
		if valid >= 14:
			break
	if best < 0:
		return {}
	stats["site_ok"] = int(stats["site_ok"]) + 1
	return _site(lanes, best, player, &"ring")


func _site(lanes: LaneGraph, idx: int, player: Vector3, source: StringName) -> Dictionary:
	var pos := lanes.positions[idx]
	var dir := lanes.dirs[idx]
	return {"pos": pos, "dir": dir, "idx": idx, "dist": Util.dist_xz(pos, player), "source": source}


## -INF when the lane point is unusable, else a base score (0).
func _check_site(lanes: LaneGraph, idx: int, player: Vector3, cam: Camera3D, cam_pos: Vector3, space: PhysicsDirectSpaceState3D,
		min_d: float, avoid: Array) -> float:
	if lanes.kind[idx] == LaneGraph.KIND_CONNECTOR or (lanes.next[idx] as PackedInt32Array).is_empty():
		stats["rej_graph"] = int(stats["rej_graph"]) + 1
		return -INF
	var pos := lanes.positions[idx]
	if Util.dist_xz(pos, player) < min_d or Util.dist_xz(pos, cam_pos) < min_d:
		stats["rej_near"] = int(stats["rej_near"]) + 1
		return -INF
	for a in avoid:
		if a is Vector3 and Util.dist_xz(a, pos) < 28.0:
			stats["rej_spacing"] = int(stats["rej_spacing"]) + 1
			return -INF
	if visible_to_camera(cam, pos, lanes.dirs[idx], space):
		stats["rej_view"] = int(stats["rej_view"]) + 1
		return -INF
	if space != null:
		_shape_q.transform = Transform3D(Basis(Vector3.UP, Util.dir_to_yaw(lanes.dirs[idx])), pos + Vector3.UP * 1.1)
		if not space.intersect_shape(_shape_q, 1).is_empty():
			stats["rej_overlap"] = int(stats["rej_overlap"]) + 1
			return -INF
	return 0.0


## Foot officers: sidewalk / path points of the ped graph, same visibility rules. -> {pos, dir} or {}.
func find_foot_site(req: Dictionary) -> Dictionary:
	var pg: PedGraph = WorldLayout.ped_graph
	if pg == null or pg.size() == 0:
		return {}
	var center: Vector3 = req.get("center", Vector3.ZERO)
	var player: Vector3 = req.get("player", center)
	var cam: Camera3D = req.get("camera", null)
	var space: PhysicsDirectSpaceState3D = req.get("space", null)
	var min_d := float(req.get("min_dist", MIN_SPAWN_DIST))
	var max_d := float(req.get("max_dist", 170.0))
	var avoid: Array = req.get("avoid", [])
	var cam_pos: Vector3 = cam.global_position if (cam != null and is_instance_valid(cam)) else player
	for t in 40:
		var idx := pg.random_point_in_ring(center, min_d, max_d, rng, 4)
		if idx < 0:
			continue
		if pg.zone[idx] == PedGraph.ZONE_INDOOR:
			continue
		var pos := pg.positions[idx]
		if Util.dist_xz(pos, player) < min_d or Util.dist_xz(pos, cam_pos) < min_d:
			continue
		var crowded := false
		for a in avoid:
			if a is Vector3 and Util.dist_xz(a, pos) < 10.0:
				crowded = true
				break
		if crowded:
			continue
		if visible_to_camera(cam, pos, Vector3(0, 0, -1), space):
			continue
		var to_p := Util.flat(player - pos)
		return {"pos": pos, "dir": to_p.normalized() if to_p.length() > 0.1 else Vector3(0, 0, -1), "idx": idx}
	return {}


## Where a flanking / intercepting unit should aim: the player's predicted position `lead` seconds ahead, snapped to the lane graph.
func predict_intercept(player: Vector3, velocity: Vector3, lead: float) -> Vector3:
	var v := Util.flat(velocity)
	if v.length() < 3.0:
		return player
	var target := player + v.limit_length(40.0) * lead
	var lanes: LaneGraph = WorldLayout.lanes
	if lanes != null and lanes.size() > 0:
		var idx := lanes.nearest(target, v.normalized(), 25.0)
		if idx >= 0:
			return lanes.positions[idx]
	return target


# ---- orders --------------------------------------------------------------------------------------------------------------------------
## snap: level, state, player (Node), ppos, pvel, last_known, search_radius, stand_down (bool), force (the level's force row).
## rec: role, kind. -> order dictionary for unit.set_order() (extra keys role / tactic are hints Police-B may use).
func make_order(rec: Dictionary, snap: Dictionary) -> Dictionary:
	var level := int(snap.get("level", 0))
	var state: StringName = snap.get("state", &"clear")
	var role: StringName = rec.get("role", &"tail")
	var kind: StringName = rec.get("kind", &"car")
	var force: Dictionary = snap.get("force", force_for(level, state))
	var aggr := clampf(float(force.get("aggr", 0.3)), 0.0, 1.0)
	var lethal := bool(force.get("lethal", false))
	if bool(rec.get("leaving", false)) or level <= 0:
		return {"mode": &"leave", "target": null, "pos": snap.get("ppos", Vector3.ZERO), "radius": 0.0, "aggression": 0.0, "lethal": false, "role": role}
	if bool(snap.get("stand_down", false)):
		return {"mode": &"hold", "target": null, "pos": rec.get("last_pos", snap.get("ppos", Vector3.ZERO)), "radius": 0.0, "aggression": 0.0, "lethal": false, "role": role}
	if kind == &"roadblock":
		return {"mode": &"hold", "target": snap.get("player", null), "pos": rec.get("block_pos", snap.get("last_known", Vector3.ZERO)), "radius": 12.0, "aggression": aggr, "lethal": lethal, "role": &"block", "level": level}
	if state == &"search":
		var center: Vector3 = snap.get("last_known", Vector3.ZERO)
		var radius := float(snap.get("search_radius", 80.0))
		# converge on the last known position first, then widen to the full search area (units pick random points inside `radius`)
		var age := float(snap.get("search_age", 99.0))
		radius = lerpf(CONVERGE_RADIUS, radius, clampf(age / CONVERGE_TIME, 0.0, 1.0))
		if role == &"flank" or role == &"intercept":
			radius = maxf(radius * 0.7, CONVERGE_RADIUS)
		radius = snappedf(radius, 10.0)    # quantised: orders only change when the area really grew
		return {"mode": &"search", "target": null, "pos": center, "radius": radius, "aggression": aggr * 0.8, "lethal": false, "role": role, "level": level}
	# pursuit
	var target_pos: Vector3 = snap.get("last_known", Vector3.ZERO)
	var tactic: StringName = &"tail"
	var pvel: Vector3 = snap.get("pvel", Vector3.ZERO)
	var pspeed := Util.flat(pvel).length()
	match role:
		&"intercept":
			tactic = &"intercept"
			target_pos = predict_intercept(snap.get("ppos", target_pos), pvel, 4.5)
		&"flank":
			tactic = &"flank"
			target_pos = predict_intercept(snap.get("ppos", target_pos), pvel, 2.5)
		&"block":
			tactic = &"block"
			target_pos = predict_intercept(snap.get("ppos", target_pos), pvel, 3.0)
		_:
			tactic = &"pit" if (level >= 2 and pspeed > 9.0) else &"tail"
	if pspeed < 2.5 and kind != &"foot":
		tactic = &"box"
	var unit_aggr := aggr
	if role == &"intercept" or role == &"block":
		unit_aggr = minf(aggr + 0.1, 1.0)
	var ord := {"mode": &"pursue", "target": snap.get("player", null), "pos": target_pos, "radius": 0.0,
		"aggression": unit_aggr, "lethal": lethal, "role": role, "tactic": tactic, "level": level}
	if kind == &"foot" or kind == &"swat":
		ord["tactic"] = &"close_in"
	if kind == &"heli":
		ord["tactic"] = &"overwatch"
		ord["radius"] = 55.0
	return ord
