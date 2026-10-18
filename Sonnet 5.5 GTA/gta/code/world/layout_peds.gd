class_name LayoutPeds
extends RefCounted
## Generates WorldLayout.ped_graph: sidewalks along every road with sidewalks, corner nodes, signal-aware crossings at
## every junction arm, plus park paths, plaza, beach promenade, quay + piers. Crossing points carry the junction's signal id
## and `walk_phase` = the TRAFFIC phase (0/1) of the vehicles being crossed: pedestrians may walk while
## WorldLayout.signal_state(signal_id, walk_phase, t) == 2 (red for that traffic). Use WorldLayout.crossing_open().

const SW_Y := 0.15
const SPACING := 8.0
const END_OFF := 1.8

static var sw_idx: Dictionary = {}     # edge id -> {1: PackedInt32Array, -1: PackedInt32Array}


static func _gy(p: Vector2) -> float:
	return LayoutTerrain.height(p.x, p.y)


static func _add(pg: PedGraph, p: Vector2, zone: int, dy: float = SW_Y) -> int:
	return pg.add_point(Vector3(p.x, _gy(p) + dy, p.y), zone)


static func build(pg: PedGraph, piers: Array, extra_paths: Array) -> void:
	sw_idx.clear()
	# ---- sidewalks along edges ---------------------------------------------------------------------------------------
	for e in LayoutRoadNet.edges:
		if float(e["sw"]) < 0.1:
			continue
		var s0: float = float(e["trim_a"]) + END_OFF
		var s1: float = float(e["len"]) - float(e["trim_b"]) - END_OFF
		if s1 - s0 < 1.0:
			continue
		var pts: PackedVector2Array = e["pts"]
		var cum := LayoutGeo.cum_lengths(pts)
		var m := maxi(int(ceil((s1 - s0) / SPACING)), 1)
		var lat: float = float(e["hw"]) + float(e["sw"]) * 0.5
		var per_side := {}
		for side in [1, -1]:
			var arr := PackedInt32Array()
			var prev := -1
			for i in m + 1:
				var s := lerpf(s0, s1, float(i) / float(m))
				var c := LayoutGeo.point_at(pts, s, cum)
				var d := LayoutGeo.dir_smooth(pts, s, cum)
				var p := c + LayoutGeo.right_of(d) * lat * float(side)
				var idx := _add(pg, p, PedGraph.ZONE_SIDEWALK)
				arr.append(idx)
				if prev >= 0:
					pg.connect_points(prev, idx)
				prev = idx
			per_side[side] = arr
		sw_idx[e["id"]] = per_side
	# ---- junction corners + crossings -------------------------------------------------------------------------------
	for id in LayoutRoadNet.node_ids:
		var n: Dictionary = LayoutRoadNet.nodes[id]
		var arms: Array = n["arms"]
		var cnt := arms.size()
		if cnt < 2:
			continue
		var j: Dictionary = LayoutRoadNet.junctions[id]
		var pads: Array = j["pads"]
		var sid: int = int(LayoutLanes.node_signal.get(id, -1))
		for pad in pads:
			if not pad.has("i"):
				continue
			var ai: Dictionary = arms[pad["i"]]
			var aj: Dictionary = arms[pad["j"]]
			var pi := _sw_pt(ai, true)
			var pj := _sw_pt(aj, false)
			var cp: Vector2 = pad["corner"]
			# pull the corner point toward the pad's interior so it sits on the paving
			var mid := ((pad["er"] as Vector2) + (pad["ej"] as Vector2)) * 0.5
			cp = cp.lerp(mid, 0.45)
			if pi >= 0 and pj >= 0:
				var ci := _add(pg, cp, PedGraph.ZONE_SIDEWALK)
				pg.connect_points(ci, pi)
				pg.connect_points(ci, pj)
			elif pi >= 0 and pj < 0:
				pass
		if cnt < 3:
			continue
		var c: Vector2 = n["pos"]
		for a in arms:
			if float(a["sw"]) < 0.1:
				continue
			var pl := _sw_pt(a, false)
			var pr := _sw_pt(a, true)
			if pl < 0 or pr < 0:
				continue
			var d: Vector2 = a["dir"]
			var rd := LayoutGeo.right_of(d)
			var base := c + d * (float(a["trim"]) + END_OFF)
			var lat: float = float(a["hw"]) + 0.5
			var width := lat * 2.0
			var steps := maxi(int(ceil(width / 7.0)), 1)
			var prev := -1
			var first := -1
			for k in steps + 1:
				var t := lerpf(-lat, lat, float(k) / float(steps))
				var idx := _add(pg, base + rd * t, PedGraph.ZONE_CROSSING, 0.08)
				pg.signal_id[idx] = sid
				pg.walk_phase[idx] = int(a.get("phase", 0))
				if prev >= 0:
					pg.connect_points(prev, idx)
				else:
					first = idx
				prev = idx
			pg.connect_points(pl, first)
			pg.connect_points(pr, prev)
	# ---- extra paths (park, plaza, promenade, quay, piers) ---------------------------------------------------------------
	pg.build_index()
	for ep in extra_paths:
		_add_path(pg, ep["pts"], int(ep["zone"]), float(ep.get("dy", 0.05)), float(ep.get("step", 7.0)), bool(ep.get("closed", false)), float(ep.get("link", 14.0)))
	for p in piers:
		var r: Rect2 = p["rect"]
		var pts2 := PackedVector2Array()
		var long_z := r.size.y >= r.size.x
		var cx := r.position.x + r.size.x * 0.5
		var cz := r.position.y + r.size.y * 0.5
		if long_z:
			pts2.append(Vector2(cx, r.position.y - 4.0))
			pts2.append(Vector2(cx, r.position.y + r.size.y - 2.0))
		else:
			pts2.append(Vector2(r.position.x - 4.0, cz))
			pts2.append(Vector2(r.position.x + r.size.x - 2.0, cz))
		_add_path(pg, pts2, PedGraph.ZONE_DOCK, float(p.get("height", 0.0)) + 0.06, 6.0, false, 14.0, true)
	pg.build_index()


## idx of the sidewalk end point on the arm's right (true) or left (false) side, or -1.
static func _sw_pt(arm: Dictionary, right_side: bool) -> int:
	var per_side: Dictionary = sw_idx.get(arm["edge"], {})
	if per_side.is_empty():
		return -1
	if arm["end"] == 0:
		var arr: PackedInt32Array = per_side[1] if right_side else per_side[-1]
		return arr[0]
	var arr2: PackedInt32Array = per_side[-1] if right_side else per_side[1]
	return arr2[arr2.size() - 1]


## deck_abs: `dy` is an absolute deck height (piers): nodes sit on the deck instead of the sea floor below it (world-fill fix).
static func _add_path(pg: PedGraph, pts: PackedVector2Array, zone: int, dy: float, step: float, closed: bool, link_dist: float, deck_abs: bool = false) -> void:
	var rs := LayoutGeo.resample(pts, step)
	if closed and rs.size() > 2:
		rs.remove_at(rs.size() - 1)
	var ids := PackedInt32Array()
	for p in rs:
		var h := _gy(p)
		ids.append(pg.add_point(Vector3(p.x, maxf(h, dy) if deck_abs else h + dy, p.y), zone))
	for i in range(1, ids.size()):
		pg.connect_points(ids[i - 1], ids[i])
	if closed and ids.size() > 2:
		pg.connect_points(ids[ids.size() - 1], ids[0])
	# link to the existing network (every point that has a sidewalk/crossing/etc. neighbour in range, at most a few links)
	var linked := 0
	for i in ids.size():
		var is_end := i == 0 or i == ids.size() - 1
		var ld := link_dist if is_end else minf(link_dist, 10.0)
		var best := -1
		var best_d := ld * ld
		for k in pg.points_in_radius(pg.positions[ids[i]], ld):
			if ids.has(k):
				continue
			var q: Vector3 = pg.positions[k] - pg.positions[ids[i]]
			var d2 := q.x * q.x + q.z * q.z
			if d2 < best_d and pg.zone[k] != PedGraph.ZONE_CROSSING:
				best_d = d2
				best = k
		if best >= 0 and (is_end or linked < 6):
			pg.connect_points(ids[i], best)
			linked += 1
	pg.build_index()
