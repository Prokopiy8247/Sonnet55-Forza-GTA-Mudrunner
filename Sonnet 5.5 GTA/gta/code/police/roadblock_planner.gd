class_name RoadblockPlanner
extends RefCounted
## Picks a roadblock site on the lane graph ahead of the player's direction of travel (Police-A).
##   RoadblockPlanner.plan(lanes, player_pos, heading, camera, rng, space) -> {pos, dir, idx, ahead, road_center} or {}
## The walk follows the lane successors from the lane point nearest to the player (straightest branch first, then random branches),
## 190-340 m along the road. The chosen point is a plain straight lane point (no junction connector / stop line near it), at least
## `min_player_dist` from the player and outside the camera frustum (or hidden behind world geometry).

const MIN_AHEAD := 190.0
const MAX_AHEAD := 340.0
const MIN_PLAYER_DIST := 150.0


static func plan(lanes: LaneGraph, ppos: Vector3, heading: Vector3, camera: Camera3D, rng: RandomNumberGenerator,
		space: PhysicsDirectSpaceState3D = null, taken: Array = [], min_ahead: float = MIN_AHEAD, max_ahead: float = MAX_AHEAD) -> Dictionary:
	if lanes == null or lanes.size() == 0:
		return {}
	var h := Util.flat(heading)
	if h.length() < 0.1:
		return {}
	h = h.normalized()
	var start := lanes.nearest(ppos, h, 30.0)
	if start < 0:
		start = lanes.nearest(ppos, Vector3.ZERO, 50.0)
	if start < 0:
		return {}
	var best := {}
	var best_score := -INF
	for attempt in 7:
		var cur := start
		var dist := 0.0
		var steps := 0
		var target_d := rng.randf_range(min_ahead, max_ahead)
		while dist < target_d and steps < 160:
			var nx: PackedInt32Array = lanes.next[cur]
			if nx.is_empty():
				break
			var pick: int = nx[0]
			if nx.size() > 1:
				if attempt == 0:
					pick = _straightest(lanes, cur, nx, h)
				else:
					pick = nx[rng.randi() % nx.size()]
			dist += lanes.positions[pick].distance_to(lanes.positions[cur])
			cur = pick
			steps += 1
		if dist < min_ahead * 0.75:
			continue
		# step back along the lane until the point is a clean straight piece
		var idx := cur
		for back in 10:
			if _valid_point(lanes, idx, ppos, camera, space, taken):
				var pos := lanes.positions[idx]
				var d_ahead := Util.dist_xz(pos, ppos)
				var score := -absf(d_ahead - (min_ahead + max_ahead) * 0.5) * 0.01 - float(attempt) * 0.15 + rng.randf() * 0.25
				if score > best_score:
					best_score = score
					best = _make_plan(lanes, idx, d_ahead)
				break
			var pv: PackedInt32Array = lanes.prev[idx]
			if pv.is_empty():
				break
			idx = pv[0]
	return best


static func _straightest(lanes: LaneGraph, from_i: int, options: PackedInt32Array, heading: Vector3) -> int:
	var best: int = options[0]
	var best_dot := -2.0
	for o in options:
		var d: Vector3 = lanes.positions[o] - lanes.positions[from_i]
		d.y = 0.0
		if d.length_squared() < 0.01:
			d = lanes.dirs[o]
		var dt := d.normalized().dot(heading)
		if dt > best_dot:
			best_dot = dt
			best = o
	return best


static func _valid_point(lanes: LaneGraph, idx: int, ppos: Vector3, camera: Camera3D, space: PhysicsDirectSpaceState3D, taken: Array) -> bool:
	if lanes.kind[idx] == LaneGraph.KIND_CONNECTOR or lanes.signal_id[idx] >= 0:
		return false
	var pos := lanes.positions[idx]
	if Util.dist_xz(pos, ppos) < MIN_PLAYER_DIST:
		return false
	# no junction piece within 3 points either way
	var chain: Array[int] = [idx]
	for step in 3:
		var nx: PackedInt32Array = lanes.next[chain[chain.size() - 1]]
		if nx.is_empty():
			break
		chain.append(nx[0])
	var cur := idx
	for step in 3:
		var pv: PackedInt32Array = lanes.prev[cur]
		if pv.is_empty():
			break
		cur = pv[0]
		chain.append(cur)
	for c in chain:
		if lanes.kind[c] == LaneGraph.KIND_CONNECTOR or lanes.signal_id[c] >= 0:
			return false
	for t in taken:
		if t is Vector3 and Util.dist_xz(t, pos) < 90.0:
			return false
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		var up := pos + Vector3.UP * 1.5
		if camera.is_position_in_frustum(up):
			var hidden := false
			if space != null:
				var q := PhysicsRayQueryParameters3D.create(camera.global_position, up, GC.M_LOS)
				hidden = not space.intersect_ray(q).is_empty()
			if not hidden:
				return false
	return true


## Roadblock centre = middle of the road (the lane point shifted over the lanes to its left, i.e. towards the centre line).
static func _make_plan(lanes: LaneGraph, idx: int, d_ahead: float) -> Dictionary:
	var pos := lanes.positions[idx]
	var dir := lanes.dirs[idx]
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, -1)
	var left := Vector3(dir.z, 0.0, -dir.x)
	var lanes_left := 0
	var cur := idx
	while lanes.left_of[cur] >= 0 and lanes_left < 3:
		cur = lanes.left_of[cur]
		lanes_left += 1
	var center := pos + left * (1.6 + 3.2 * float(lanes_left))
	return {"pos": pos, "dir": dir, "idx": idx, "ahead": d_ahead, "road_center": center}
