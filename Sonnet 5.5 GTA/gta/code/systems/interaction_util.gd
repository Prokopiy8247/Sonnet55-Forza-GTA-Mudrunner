class_name InteractionUtil
extends RefCounted
## Physics / world query helpers shared by the Systems-A modules (pickup placement, ladders, elevator, benches, phone booths).
## Everything is static and tolerant: queries return {} / false when the physics space is not available yet.

const MASK_WALK := GC.L_WORLD | GC.L_PROP


static func space() -> PhysicsDirectSpaceState3D:
	var m: Node = Game.main
	if m == null or not is_instance_valid(m) or not m.is_inside_tree():
		return null
	return (m as Node).get_viewport().world_3d.direct_space_state


static func ray(from: Vector3, to: Vector3, mask: int = MASK_WALK) -> Dictionary:
	var sp := space()
	if sp == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return sp.intersect_ray(q)


## Top surface under (x, z) found by a ray from `top_y` down to `bottom_y` ({} when nothing is hit).
static func surface_at(x: float, z: float, top_y: float, bottom_y: float, mask: int = MASK_WALK) -> Dictionary:
	return ray(Vector3(x, top_y, z), Vector3(x, bottom_y, z), mask)


## Ground at street level: ray from `up` metres above the terrain height down `down` metres.
static func ground_at(x: float, z: float, up: float = 3.0, down: float = 9.0, mask: int = MASK_WALK) -> Dictionary:
	var th := WorldLayout.terrain_height(x, z)
	return ray(Vector3(x, th + up, z), Vector3(x, th - down, z), mask)


## True when a standing capsule (radius, height) fits with its feet at `foot` (no walls / props inside).
static func clear_at(foot: Vector3, radius: float = 0.4, height: float = 1.75, mask: int = MASK_WALK) -> bool:
	var sp := space()
	if sp == null:
		return false
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, foot + Vector3(0, height * 0.5 + 0.12, 0))
	q.collision_mask = mask
	return sp.intersect_shape(q, 1).is_empty()


## True when a box (full size) centred at `centre` with yaw rotation overlaps nothing in the mask.
static func box_free(centre: Vector3, size: Vector3, yaw: float = 0.0, mask: int = MASK_WALK) -> bool:
	var sp := space()
	if sp == null:
		return false
	var shape := BoxShape3D.new()
	shape.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, yaw), centre)
	q.collision_mask = mask
	return sp.intersect_shape(q, 1).is_empty()


## First valid, walkable point near `center` (XZ). Returns Vector3.INF when nothing fits.
##   opts: min_r, max_r (ring, default 0..6), tries (28), avoid_road (true), min_up (normal.y, 0.8), radius (0.45), water (false = no water),
##         rng (RandomNumberGenerator), ref_y (NAN = terrain height; set for roofs / piers), up (3.0), down (9.0)
static func find_walkable(center: Vector3, opts: Dictionary = {}) -> Vector3:
	var rng: RandomNumberGenerator = opts.get("rng", Game.rng)
	var rmin: float = float(opts.get("min_r", 0.0))
	var rmax: float = float(opts.get("max_r", 6.0))
	var tries: int = int(opts.get("tries", 28))
	var avoid_road: bool = bool(opts.get("avoid_road", true))
	var min_up: float = float(opts.get("min_up", 0.8))
	var radius: float = float(opts.get("radius", 0.45))
	var allow_water: bool = bool(opts.get("water", false))
	var ref_y: float = float(opts.get("ref_y", NAN))
	var up: float = float(opts.get("up", 3.0))
	var down: float = float(opts.get("down", 9.0))
	for i in tries:
		var p := center
		if i > 0 or rmin > 0.0:
			var a := rng.randf() * TAU
			var d := sqrt(lerpf(rmin * rmin, rmax * rmax, rng.randf()))
			p = center + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if not allow_water and WorldLayout.is_water(p.x, p.z) and is_nan(ref_y):
			continue
		var hit: Dictionary
		if is_nan(ref_y):
			hit = ground_at(p.x, p.z, up, down)
		else:
			hit = surface_at(p.x, p.z, ref_y + up, ref_y - down)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.y < min_up:
			continue
		var pos: Vector3 = hit["position"]
		if avoid_road and is_nan(ref_y):
			var rd := WorldLayout.road_at(pos.x, pos.z, 6.0)
			if not rd.is_empty() and bool(rd.get("on_road", false)):
				continue
		if not clear_at(pos, radius):
			continue
		return pos
	return Vector3.INF


## Distance (XZ, metres) from `p` to the nearest lane CENTRE LINE of the traffic graph (segments between linked lane points, so a spot in the
## middle of a long segment is measured correctly). INF when there is no lane graph. Props closer than ~2 m make traffic dodge / queue.
static func lane_distance(p: Vector3, search: float = 14.0) -> float:
	var lg: LaneGraph = WorldLayout.lanes
	if lg == null or lg.size() == 0:
		return INF
	var best := INF
	var pv := Vector2(p.x, p.z)
	for i in lg.points_in_radius(p, search):
		var a := Vector2(lg.positions[i].x, lg.positions[i].z)
		best = minf(best, pv.distance_to(a))
		for j in (lg.next[i] as PackedInt32Array):
			best = minf(best, _seg_dist(pv, a, Vector2(lg.positions[j].x, lg.positions[j].z)))
		for j in (lg.prev[i] as PackedInt32Array):
			best = minf(best, _seg_dist(pv, a, Vector2(lg.positions[j].x, lg.positions[j].z)))
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


## True when a prop at `p` leaves at least `min_dist` metres to every lane centre line (default 2.0 m: a car is 1.9 m wide).
static func lane_clear(p: Vector3, min_dist: float = 2.0) -> bool:
	return lane_distance(p, min_dist + 12.0) >= min_dist


## Nearest point on a polyline (Vector2 x,z points) and its tangent. Returns {"pos": Vector2, "dir": Vector2, "dist": float}.
static func nearest_on_polyline(pts: Array, p: Vector2) -> Dictionary:
	var best := {"pos": p, "dir": Vector2(0, -1), "dist": INF}
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < float(best["dist"]):
			best = {"pos": q, "dir": ab.normalized() if l2 > 0.0001 else Vector2(0, -1), "dist": d}
	return best


static func fade_out(seconds: float) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("fade"):
		await ui.fade(true, seconds)


static func fade_in(seconds: float) -> void:
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("fade"):
		await ui.fade(false, seconds)
