class_name LayoutLanes
extends RefCounted
## Generates WorldLayout.lanes (LaneGraph) + WorldLayout.signals from the LayoutRoadNet data.
## Lane points sit on lane centres every ~7 m, junction connectors are Bezier paths (straight / left / right / U-turn
## at dead-end bulbs), every signalised approach has a stop-line point 4.5 m before the junction mouth.

const STEP := 7.0
const STOP_BACK := 6.6
const CYCLE := 26.0
const YELLOW := 2.5
const LANE_Y := 0.06

## node id -> signal id
static var node_signal: Dictionary = {}
## "edge,dir,lane" -> {"first": int, "last": int, "stop": int}
static var lane_ends: Dictionary = {}


static func _ground(p: Vector2) -> float:
	return LayoutTerrain.height(p.x, p.y) + LANE_Y


static func build(g: LaneGraph, sigs: Array) -> void:
	node_signal.clear()
	lane_ends.clear()
	sigs.clear()
	# ---- signals ----------------------------------------------------------------------------------------------------
	for id in LayoutRoadNet.node_ids:
		var n: Dictionary = LayoutRoadNet.nodes[id]
		if n["sig"]:
			var p: Vector2 = n["pos"]
			var sid := sigs.size()
			sigs.append({"id": sid, "pos": Vector3(p.x, LayoutTerrain.height(p.x, p.y), p.y), "cycle": CYCLE, "yellow": YELLOW,
				"offset": fposmod(p.x * 0.06 + p.y * 0.09, CYCLE), "node": id})
			node_signal[id] = sid
			for a in n["arms"]:
				var d: Vector2 = a["dir"]
				a["phase"] = 0 if absf(d.y) >= absf(d.x) else 1
	# ---- lanes along edges ----------------------------------------------------------------------------------------------
	for e in LayoutRoadNet.edges:
		_build_edge_lanes(g, e)
	# ---- junction connectors ------------------------------------------------------------------------------------------
	for id in LayoutRoadNet.node_ids:
		_build_connectors(g, id)
	g.build_index()


static func _s_fractions(e: Dictionary, trimmed_len: float, end_has_signal: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(int(ceil(trimmed_len / STEP)), 1)
	if end_has_signal and trimmed_len > STOP_BACK * 2.0 + 6.0:
		var body := trimmed_len - STOP_BACK
		var m := maxi(int(ceil(body / STEP)), 1)
		for i in m + 1:
			out.append(body * float(i) / float(m) / trimmed_len)
		out.append(1.0)
	else:
		for i in n + 1:
			out.append(float(i) / float(n))
	return out


static func _build_edge_lanes(g: LaneGraph, e: Dictionary) -> void:
	var trimmed := LayoutRoadNet.edge_trimmed(e)
	if trimmed.size() < 2:
		return
	var tl := LayoutGeo.poly_length(trimmed)
	var dirs_to_do: Array = [0] if e["oneway"] else [0, 1]
	var speed: float = float(e["kmh"]) / 3.6
	var kind := LaneGraph.KIND_HIGHWAY if float(e["kmh"]) >= 75.0 else LaneGraph.KIND_STRAIGHT
	for dir in dirs_to_do:
		var end_node: String = e["b"] if dir == 0 else e["a"]
		var has_sig := bool(LayoutRoadNet.nodes[end_node]["sig"])
		var fracs := _s_fractions(e, tl, has_sig)
		var prev_lane_pts: PackedInt32Array = PackedInt32Array()
		for k in int(e["lanes"]):
			var off := LayoutRoadNet.lane_offset(e, k)
			var lp: PackedVector2Array
			if dir == 0:
				lp = LayoutGeo.offset(trimmed, off)
			else:
				lp = LayoutGeo.reversed(LayoutGeo.offset(trimmed, -off))
			var cum := LayoutGeo.cum_lengths(lp)
			var llen: float = cum[cum.size() - 1]
			var pts := PackedInt32Array()
			var prev := -1
			for f in fracs:
				var s := llen * f
				var p := LayoutGeo.point_at(lp, s, cum)
				var d := LayoutGeo.dir_smooth(lp, s, cum)
				var idx := g.add_point(Vector3(p.x, _ground(p), p.y), Vector3(d.x, 0.0, d.y), speed, e["id"], kind)
				pts.append(idx)
				if prev >= 0:
					g.link(prev, idx)
				prev = idx
			var stop_i := pts[pts.size() - 2] if pts.size() >= 3 and has_sig else -1
			lane_ends["%d,%d,%d" % [e["id"], dir, k]] = {"first": pts[0], "last": pts[pts.size() - 1], "stop": stop_i}
			if prev_lane_pts.size() == pts.size():
				for i in pts.size():
					g.right_of[prev_lane_pts[i]] = pts[i]
					g.left_of[pts[i]] = prev_lane_pts[i]
			prev_lane_pts = pts


static func _lane(e: Dictionary, dir: int, k: int) -> Dictionary:
	return lane_ends.get("%d,%d,%d" % [e["id"], dir, k], {})


static func _build_connectors(g: LaneGraph, node_id: String) -> void:
	var n: Dictionary = LayoutRoadNet.nodes[node_id]
	var arms: Array = n["arms"]
	var cnt := arms.size()
	var has_sig: bool = n["sig"]
	var sid: int = int(node_signal.get(node_id, -1))
	for ai in cnt:
		var a: Dictionary = arms[ai]
		var ea: Dictionary = LayoutRoadNet.edges[a["edge"]]
		var in_dir: int = 0 if a["end"] == 1 else 1   # travelling toward this node
		var n_in := 0 if (ea["oneway"] and in_dir == 1) else int(ea["lanes"])
		if n_in == 0:
			continue
		# stop lines on every incoming lane of a signalised junction
		if has_sig:
			for k in n_in:
				var le := _lane(ea, in_dir, k)
				if not le.is_empty() and int(le["stop"]) >= 0:
					g.set_stop_line(int(le["stop"]), sid, int(a.get("phase", 0)))
		for bi in cnt:
			if bi == ai and cnt > 1:
				continue
			var b: Dictionary = arms[bi]
			var eb: Dictionary = LayoutRoadNet.edges[b["edge"]]
			var out_dir: int = 0 if b["end"] == 0 else 1  # travelling away from this node
			var n_out := 0 if (eb["oneway"] and out_dir == 1) else int(eb["lanes"])
			if n_out == 0:
				continue
			# turn angle between the heading into the node (-dir_a) and the heading out (dir_b): >0 = right turn
			var heading_in: Vector2 = -(a["dir"] as Vector2)
			var heading_out: Vector2 = b["dir"]
			var turn := heading_in.angle_to(heading_out)
			# angle_to is signed CCW in (x,z) math terms: positive = turning toward right_of() => right turn
			var is_uturn := cnt == 1
			if not is_uturn and absf(turn) > deg_to_rad(150.0):
				continue
			var kind_turn := 0   # 0 straight, 1 right, 2 left, 3 uturn
			if is_uturn:
				kind_turn = 3
			elif turn > deg_to_rad(30.0):
				kind_turn = 1
			elif turn < -deg_to_rad(30.0):
				kind_turn = 2
			for k in n_in:
				var targets: Array = []
				match kind_turn:
					0:
						targets.append(mini(k, n_out - 1))
						if k == n_in - 1:
							for ko in range(k + 1, n_out):
								targets.append(ko)
					1:
						if k == n_in - 1:
							targets.append(n_out - 1)
					2:
						if k == 0:
							targets.append(0)
					3:
						targets.append(mini(k, n_out - 1))
				for k_out in targets:
					var li := _lane(ea, in_dir, k)
					var lo := _lane(eb, out_dir, k_out)
					if li.is_empty() or lo.is_empty():
						continue
					_connect(g, int(li["last"]), int(lo["first"]), kind_turn, float(ea["kmh"]), a, b, n["pos"])


static func _connect(g: LaneGraph, from_i: int, to_i: int, kind_turn: int, kmh: float, _a: Dictionary, _b: Dictionary, node_pos: Vector2) -> void:
	var p0 := Vector2(g.positions[from_i].x, g.positions[from_i].z)
	var p1 := Vector2(g.positions[to_i].x, g.positions[to_i].z)
	var d0 := Vector2(g.dirs[from_i].x, g.dirs[from_i].z)
	var d1 := Vector2(g.dirs[to_i].x, g.dirs[to_i].z)
	var dist := p0.distance_to(p1)
	var speed := kmh / 3.6
	match kind_turn:
		1:
			speed = minf(speed, 6.5)
		2:
			speed = minf(speed, 8.0)
		3:
			speed = 4.5
		_:
			speed = minf(speed, 14.0 if kmh > 60.0 else speed)
	var segs := clampi(int(ceil(dist / 3.0)), 1, 10)
	var pts := PackedVector2Array()
	if kind_turn == 3:
		# U-turn around the bulb: cubic with controls pushed toward the dead end
		var push := maxf(dist * 1.1, 6.0)
		var c1 := p0 + d0 * push
		var c2 := p1 - d1 * push
		segs = 8
		for s in range(1, segs):
			pts.append(LayoutGeo.bezier3(p0, c1, c2, p1, float(s) / float(segs)))
	elif kind_turn == 0:
		for s in range(1, segs):
			pts.append(p0.lerp(p1, float(s) / float(segs)))
		# gentle S-curve for lateral offsets
		if absf((p1 - p0).normalized().cross(d0)) > 0.02 and segs > 1:
			pts = PackedVector2Array()
			var ctrl1 := p0 + d0 * dist * 0.35
			var ctrl2 := p1 - d1 * dist * 0.35
			for s in range(1, segs):
				pts.append(LayoutGeo.bezier3(p0, ctrl1, ctrl2, p1, float(s) / float(segs)))
	else:
		var isect := LayoutGeo.line_intersect(p0, d0, p1, d1)
		var ctrl := (p0 + p1) * 0.5
		if not is_nan(isect.x) and isect.x > 0.0 and isect.y < 0.0:
			ctrl = p0 + d0 * isect.x
		elif not is_nan(isect.x):
			ctrl = p0 + d0 * clampf(isect.x, 0.5, dist)
		segs = clampi(int(ceil(dist / 2.2)), 3, 10)
		for s in range(1, segs):
			pts.append(LayoutGeo.bezier2(p0, ctrl, p1, float(s) / float(segs)))
	var prev := from_i
	var road := g.road_id[from_i]
	for i in pts.size():
		var p := pts[i]
		var t := pts[i + 1] - p if i < pts.size() - 1 else p1 - p
		if t.length_squared() < 0.0001:
			t = d1
		var idx := g.add_point(Vector3(p.x, _ground(p), p.y), Vector3(t.x, 0.0, t.y), speed, road, LaneGraph.KIND_CONNECTOR)
		g.link(prev, idx)
		prev = idx
	g.link(prev, to_i)
	# lower the speed limit on the lane exit points a little so vehicles slow down before turning
	if kind_turn != 0:
		g.speed_limit[from_i] = minf(g.speed_limit[from_i], maxf(speed + 3.0, 8.0))
