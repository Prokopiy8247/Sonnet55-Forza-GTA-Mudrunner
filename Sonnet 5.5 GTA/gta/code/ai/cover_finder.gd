class_name CoverFinder
extends RefCounted
## Cover probing for combat AI (police, SWAT, gangs).
##
## find() throws a ring of horizontal rays around a unit, turns every wall / vehicle / barrier face it hits into a candidate standing
## spot in front of that face, keeps the spots that are really shielded from the threat (the obstacle lies between the spot and the
## threat at knee height and optionally head height) and that offer a firing position (stand over a low obstacle, or step out sideways
## around a high one), then scores them by walking distance, protection, range to the threat and whether somebody else already
## claimed the spot. A query costs ~40-90 physics rays (~0.2-0.5 ms): callers rate-limit it (CombatBrain: <= 1 per second per unit).
##
## Result entry: {pos: Vector3 (stand here), normal: Vector3 (flat, points from the obstacle toward the unit),
##   kind: &"low"|&"high", peek: Vector3 (position to shoot from), peek_side: float (-1/+1 along the tangent, 0 = stand up in place),
##   tangent: Vector3, score: float, dist: float, threat_dist: float}

const MASK := GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
const DIRS := 30
const DIRS_FWD := 22
const CLAIM_RADIUS := 1.7

static var _claims: Dictionary = {}          # claimer instance id -> Vector3
static var queries := 0                      # stats for tests
static var rays_total := 0


static func claim(claimer_id: int, pos: Vector3) -> void:
	_claims[claimer_id] = pos


static func release(claimer_id: int) -> void:
	_claims.erase(claimer_id)


static func is_claimed(pos: Vector3, my_id: int) -> bool:
	for k in _claims:
		if k == my_id:
			continue
		var p: Vector3 = _claims[k]
		if (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z) < CLAIM_RADIUS * CLAIM_RADIUS:
			return true
	return false


## True when something solid (mask) lies on the line from `pos` to the threat's chest, i.e. the spot is shielded.
## `low` = crouched behind low cover (the ray starts at hip height instead of head height).
static func is_protected(node: Node3D, pos: Vector3, threat: Vector3, exclude: Array = [], low: bool = false) -> bool:
	var space := node.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.65 if low else 1.45, 0), threat + Vector3(0, 1.25, 0), MASK)
	var rids: Array[RID] = []
	for e in exclude:
		if e is CollisionObject3D:
			rids.append(e.get_rid())
	q.exclude = rids
	return not space.intersect_ray(q).is_empty()


## Returns the best candidates (descending score). opts: radius (14), range (weapon range, 60), id (claimer id), min_threat_dist (4),
## max (3), exclude (Array of CollisionObject3D), prefer_min / prefer_max (ideal distance band to the threat), toward_penalty (0..1).
static func find(node: Node3D, origin: Vector3, threat: Vector3, opts: Dictionary = {}) -> Array:
	queries += 1
	var space := node.get_world_3d().direct_space_state
	var radius: float = opts.get("radius", 14.0)
	var wrange: float = opts.get("range", 60.0)
	var my_id: int = opts.get("id", 0)
	var min_td: float = opts.get("min_threat_dist", 4.0)
	var max_n: int = opts.get("max", 3)
	var pmin: float = opts.get("prefer_min", 8.0)
	var pmax: float = opts.get("prefer_max", 24.0)
	var rids: Array[RID] = []
	for e in opts.get("exclude", []):
		if e is CollisionObject3D:
			rids.append(e.get_rid())
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = MASK
	q.exclude = rids
	var gq := PhysicsRayQueryParameters3D.new()
	gq.collision_mask = GC.L_WORLD
	var threat_chest := threat + Vector3(0, 1.25, 0)
	var out: Array = []
	var taken: Array[Vector3] = []
	var jitter := randf()
	var rays := 0
	var to_threat_flat := Vector3(threat.x - origin.x, 0.0, threat.z - origin.z)
	var tdist0 := to_threat_flat.length()
	var tdir0 := to_threat_flat / maxf(tdist0, 0.01)
	# cover must lie between the unit and the threat or beside it: most rays go into the half-plane facing the threat (+-105 deg), a few cover the rest
	var base_a := atan2(tdir0.z, tdir0.x)
	for i in DIRS:
		var a: float
		if i < DIRS_FWD:
			a = base_a + deg_to_rad(-105.0 + 210.0 * (float(i) + jitter) / float(DIRS_FWD))
		else:
			a = base_a + deg_to_rad(105.0 + 150.0 * (float(i - DIRS_FWD) + jitter) / float(DIRS - DIRS_FWD))
		var dir := Vector3(cos(a), 0.0, sin(a))
		q.from = origin + Vector3(0, 0.6, 0)
		q.to = q.from + dir * radius
		var hit := space.intersect_ray(q)
		rays += 1
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.5:
			continue
		var nh := Vector3(n.x, 0.0, n.z).normalized()
		var p: Vector3 = (hit["position"] as Vector3) + nh * 0.62
		gq.from = p + Vector3(0, 1.4, 0)
		gq.to = p + Vector3(0, -2.5, 0)
		var g := space.intersect_ray(gq)
		rays += 1
		if g.is_empty():
			continue
		p.y = (g["position"] as Vector3).y + 0.03
		if absf(p.y - origin.y) > 1.5:
			continue
		var dup := false
		for t in taken:
			if (t.x - p.x) * (t.x - p.x) + (t.z - p.z) * (t.z - p.z) < 1.0:
				dup = true
				break
		if dup:
			continue
		var to_t := Vector3(threat.x - p.x, 0.0, threat.z - p.z)
		var td := to_t.length()
		if td < min_td or td > wrange:
			continue
		var tdir := to_t / td
		if nh.dot(tdir) > -0.2:
			continue                       # the obstacle is not between us and the threat
		# ---- protection at knee and head height
		q.from = p + Vector3(0, 0.7, 0)
		q.to = q.from + (threat_chest - q.from).normalized() * 2.4
		var lo_blocked := not space.intersect_ray(q).is_empty()
		rays += 1
		if not lo_blocked:
			continue
		q.from = p + Vector3(0, 1.5, 0)
		q.to = q.from + (threat_chest - q.from).normalized() * 2.4
		var hi_blocked := not space.intersect_ray(q).is_empty()
		rays += 1
		var kind: StringName = &"high" if hi_blocked else &"low"
		# ---- a firing position must exist
		var tang := Vector3(-nh.z, 0.0, nh.x)
		var peek_pos := p
		var peek_side := 0.0
		if kind == &"low":
			q.from = p + Vector3(0, 1.6, 0)
			q.to = threat_chest
			var clear := space.intersect_ray(q).is_empty()
			rays += 1
			if not clear:
				continue
		else:
			var ok := false
			for s in [1.0, -1.0]:
				var pp: Vector3 = p + tang * s * 1.15
				# the step-out spot must itself be free (not inside the obstacle)
				q.from = p + Vector3(0, 1.0, 0)
				q.to = pp + Vector3(0, 1.0, 0)
				if not space.intersect_ray(q).is_empty():
					rays += 1
					continue
				q.from = pp + Vector3(0, 1.55, 0)
				q.to = threat_chest
				var clear2 := space.intersect_ray(q).is_empty()
				rays += 2
				if clear2:
					ok = true
					peek_pos = pp
					peek_side = s
					break
			if not ok:
				continue
		# ---- score
		var d_move := Vector2(p.x - origin.x, p.z - origin.z).length()
		var score := -d_move * 1.0
		score += 3.0 if kind == &"high" else 1.5
		if td < pmin:
			score -= (pmin - td) * 0.7
		elif td > pmax:
			score -= (td - pmax) * 0.25
		# running toward the threat to reach the spot is worse than sideways / away
		var move_dir := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
		if move_dir.length() > 0.5:
			var toward := move_dir.normalized().dot(tdir0)
			if toward > 0.3:
				score -= toward * d_move * 0.8
		if my_id != 0 and is_claimed(p, my_id):
			score -= 40.0
		taken.append(p)
		out.append({"pos": p, "normal": nh, "kind": kind, "peek": peek_pos, "peek_side": peek_side, "tangent": tang,
			"score": score, "dist": d_move, "threat_dist": td, "obstacle": hit.get("collider", null)})
	rays_total += rays
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	if out.size() > max_n:
		out.resize(max_n)
	return out
