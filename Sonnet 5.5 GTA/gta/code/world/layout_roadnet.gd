class_name LayoutRoadNet
extends RefCounted
## The road network as DATA: nodes (junctions / dead ends) + edges (polyline roads between nodes) + road classes.
## Everything else (terrain carving, road meshes, lane graph, ped graph, lots, furniture) is generated from this.
## Coordinates are Vector2(x, z). Right-hand traffic.

const CLASSES := {
	&"arterial": {"lanes": 2, "lane_w": 3.4, "median": 0.8, "sidewalk": 3.0, "kmh": 80.0, "mark": 2, "oneway": false, "hill": false},
	&"street": {"lanes": 1, "lane_w": 3.7, "median": 0.0, "sidewalk": 3.0, "kmh": 50.0, "mark": 1, "oneway": false, "hill": false},
	&"residential": {"lanes": 1, "lane_w": 3.2, "median": 0.0, "sidewalk": 2.4, "kmh": 40.0, "mark": 3, "oneway": false, "hill": false},
	&"industrial": {"lanes": 1, "lane_w": 3.9, "median": 0.0, "sidewalk": 2.0, "kmh": 50.0, "mark": 1, "oneway": false, "hill": false},
	&"alley": {"lanes": 1, "lane_w": 3.4, "median": 0.0, "sidewalk": 0.0, "kmh": 25.0, "mark": 0, "oneway": true, "hill": false},
	&"hill": {"lanes": 1, "lane_w": 3.4, "median": 0.0, "sidewalk": 0.0, "kmh": 45.0, "mark": 3, "oneway": false, "hill": true},
}
const CURB_R := 4.5
const BULB_TRIM := 3.2
const BULB_EXTRA := 5.5

static var nodes: Dictionary = {}       # id(String) -> {"pos": Vector2, "sig": bool, "arms": Array, "idx": int, "bulb": bool}
static var node_ids: Array = []
static var edges: Array = []            # see _add_edge
static var junctions: Dictionary = {}   # id -> {"patch": PackedVector2Array, "pads": Array[PackedVector2Array], "corners": Array}
static var _chain_n := 0


static func clear() -> void:
	nodes.clear()
	node_ids.clear()
	edges.clear()
	junctions.clear()
	_chain_n = 0


static func _node(id: String, x: float, z: float, sig: bool = false) -> void:
	nodes[id] = {"pos": Vector2(x, z), "sig": sig, "arms": [], "idx": node_ids.size(), "bulb": false}
	node_ids.append(id)


## items: node id Strings and free vertices [x, z] / [x, z, fillet_radius]. First and last item must be nodes.
static func _chain(cls: StringName, road_name: String, items: Array, oneway_override: int = -1) -> void:
	var seg_pts := PackedVector2Array()
	var seg_r := PackedFloat32Array()
	var prev_id := ""
	for it in items:
		if it is String:
			var n: Dictionary = nodes[it]
			if prev_id != "":
				seg_pts.append(n["pos"])
				seg_r.append(0.0)
				_add_edge(cls, road_name, prev_id, it, seg_pts, seg_r, oneway_override)
			prev_id = it
			seg_pts = PackedVector2Array([n["pos"]])
			seg_r = PackedFloat32Array([0.0])
		else:
			var arr: Array = it
			seg_pts.append(Vector2(float(arr[0]), float(arr[1])))
			seg_r.append(float(arr[2]) if arr.size() > 2 else 0.0)


static func _add_edge(cls: StringName, road_name: String, a: String, b: String, pts: PackedVector2Array, radii: PackedFloat32Array, oneway_override: int) -> void:
	var c: Dictionary = CLASSES[cls]
	var oneway: bool = c["oneway"] if oneway_override < 0 else (oneway_override == 1)
	var lanes: int = c["lanes"]
	var lane_w: float = c["lane_w"]
	var median: float = c["median"]
	var hw: float
	if oneway:
		hw = float(lanes) * lane_w * 0.5 + 0.5
	else:
		hw = median * 0.5 + float(lanes) * lane_w + 0.25
	var full := LayoutGeo.rounded_path(pts, radii, 7)
	var e := {
		"id": edges.size(), "a": a, "b": b, "pts": full, "cls": cls, "name": road_name, "oneway": oneway,
		"lanes": lanes, "lane_w": lane_w, "median": median, "hw": hw, "sw": float(c["sidewalk"]),
		"kmh": float(c["kmh"]), "mark": int(c["mark"]), "hill": bool(c["hill"]), "len": LayoutGeo.poly_length(full),
		"trim_a": 0.0, "trim_b": 0.0,
	}
	edges.append(e)
	(nodes[a]["arms"] as Array).append({"edge": e["id"], "end": 0})
	(nodes[b]["arms"] as Array).append({"edge": e["id"], "end": 1})


## Defines the whole Halcyon Bay road network.
static func define() -> void:
	clear()
	# ---- downtown grid (4 x 4 lines, 70 m blocks) -----------------------------------------------------------------
	var xs := [-105.0, -35.0, 35.0, 105.0]
	var zs := [-90.0, -20.0, 50.0, 120.0]
	for i in 4:
		for j in 4:
			if i == 3 and j == 3:
				continue
			_node("g%d%d" % [i, j], xs[i], zs[j], true)
	# alley / mid-block nodes
	_node("a1a", -70, -20, false)
	_node("a1b", -70, 50, false)
	_node("a3a", -35, -55, false)
	_node("a3b", 35, -55, false)
	_node("a2a", 35, 85, false)
	_node("a2b", -35, 85, false)
	_node("t0", 105, 85, true)
	# ---- east: ridge road, eastern link, industrial, airport ---------------------------------------------------------
	_node("e1", 190, -90, true)
	_node("e2", 190, -20, true)
	_node("e3", 190, 50, true)
	_node("e4", 190, 85, true)
	_node("di1", 250, -60, false)
	_node("di2", 250, -20, false)
	_node("di3", 250, 50, false)
	_node("di4", 250, 85, false)
	_node("f_end", 288, -20, false)
	_node("ia_end", 288, 50, false)
	_node("ta_end", 290, 85, false)
	_node("vpb", 205, -224, false)
	# ---- north / park ---------------------------------------------------------------------------------------------
	_node("p1", -35, -150, false)
	_node("p4", -35, -190, false)
	_node("p2", -35, -215, false)
	_node("pe_end", 60, -215, false)
	_node("nw0", -262, -215, false)
	_node("oc", -225, -215, false)
	_node("oc_end", -225, -180, false)
	_node("nN1", -185, -215, true)
	# ---- residential west --------------------------------------------------------------------------------------------
	_node("w1", -262, -150, false)
	_node("w2", -262, -90, false)
	_node("w3", -262, -20, false)
	_node("w4", -262, 50, false)
	_node("w5", -262, 120, false)
	_node("m0", -185, -150, false)
	_node("m1", -185, -90, true)
	_node("m2", -185, -20, true)
	_node("m3", -185, 50, true)
	_node("m4", -185, 120, true)
	_node("m5", -185, 148, false)
	_node("mq", -185, 176, false)
	_node("ll1", -160, -20, false)
	_node("ll2", -132, -20, false)
	_node("cc", -230, -20, false)
	_node("cc_end", -230, 24, false)
	_node("hc_end", -125, -150, false)
	# ---- waterfront / beach --------------------------------------------------------------------------------------
	_node("cw0", -225, 120, false)
	_node("cw", -225, 148, false)
	_node("cwq", -225, 176, false)
	_node("pr0", -146, 120, false)
	_node("pr", -146, 148, false)
	_node("prq", -146, 176, false)
	_node("sb1", -35, 148, false)
	_node("sb2", 35, 148, false)
	_node("sv_end", 74, 148, false)

	# ---- Halcyon Ring (fast arterial, 2+2, 80 km/h) ------------------------------------------------------------------
	_chain(&"arterial", "Halcyon Ring", ["g00", "g10", "g20", "g30"])
	_chain(&"arterial", "Halcyon Ring", ["g30", "g31", "g32", "t0", [105, 120, 30], "g23"])
	_chain(&"arterial", "Halcyon Ring", ["g23", "g13", "g03"])
	_chain(&"arterial", "Halcyon Ring", ["g03", "g02", "g01", "g00"])
	# ---- downtown streets (50 km/h) ---------------------------------------------------------------------------------
	_chain(&"street", "Alder Street", ["g10", "a3a", "g11", "g12", "a2b", "g13"])
	_chain(&"street", "Birch Street", ["g20", "a3b", "g21", "g22", "a2a", "g23"])
	_chain(&"street", "Cedar Avenue", ["g01", "a1a", "g11", "g21", "g31"])
	_chain(&"street", "Dune Avenue", ["g02", "a1b", "g12", "g22", "g32"])
	_chain(&"alley", "Lantern Alley", ["a1a", "a1b"])
	_chain(&"alley", "Gull Alley", ["a3a", "a3b"])
	_chain(&"alley", "Anchor Alley", ["a2a", "a2b"])
	# ---- east spur: Ridge Road, Eastern Link, industrial ------------------------------------------------------------
	_chain(&"arterial", "Ridge Road", ["g30", "e1"])
	_chain(&"arterial", "Eastern Link", ["e1", "e2", "e3", "e4"])
	_chain(&"industrial", "Foundry Street", ["g31", "e2", "di2", "f_end"])
	_chain(&"industrial", "Industrial Avenue", ["g32", "e3", "di3", "ia_end"])
	_chain(&"industrial", "Depot Street", ["di1", "di2", "di3", "di4"])
	_chain(&"street", "Terminal Road", ["t0", "e4", "di4", "ta_end"])
	# switchback hill road up to the viewpoint
	_chain(&"hill", "Summit Road", ["e1", [190, -114, 14], [262, -114, 15], [262, -146, 15], [166, -146, 15], [166, -178, 15],
		[252, -178, 15], [252, -206, 15], [205, -206, 12], "vpb"])
	# ---- park + north -------------------------------------------------------------------------------------------------
	_chain(&"street", "Parkway", ["g10", "p1", "p4", "p2"])
	_chain(&"residential", "Greenway", ["p1", [20, -150, 12], [20, -190, 12], "p4"])
	_chain(&"street", "Northern Avenue", ["nw0", "oc", "nN1", "p2", "pe_end"])
	_chain(&"residential", "Oak Court", ["oc", "oc_end"])
	# ---- residential west --------------------------------------------------------------------------------------------
	_chain(&"street", "Westside Road", ["nw0", "w1", "w2", "w3", "w4", "w5", [-262, 148, 16], "cw"])
	_chain(&"street", "Parkside Road", ["g00", "m1", "w2"])
	_chain(&"street", "Westbrook Avenue", ["g01", "ll2", "ll1", "m2", "cc", "w3"])
	_chain(&"residential", "Elm Street", ["g02", "m3", "w4"])
	_chain(&"street", "Harbor Road", ["g03", "pr0", "m4", "cw0", "w5"])
	_chain(&"street", "Maple Lane", ["nN1", "m0", "m1", "m2", "m3", "m4", "m5", "mq"])
	_chain(&"residential", "Hillcrest Road", ["w1", "m0", "hc_end"])
	_chain(&"residential", "Linden Loop", ["ll1", [-160, -62, 10], [-132, -62, 10], "ll2"])
	_chain(&"residential", "Cedar Court", ["cc", "cc_end"])
	# ---- waterfront + coast -----------------------------------------------------------------------------------------
	_chain(&"industrial", "Crane Way", ["cw0", "cw", "cwq"])
	_chain(&"industrial", "Pier Road", ["pr0", "pr", "prq"])
	_chain(&"street", "Seaview Drive", ["cw", "m5", "pr", "sb1", "sb2", "sv_end"])
	_chain(&"street", "Beach Access", ["g13", "sb1"])
	_chain(&"street", "Promenade Access", ["g23", "sb2"])

	_mark_bulbs()


static func _mark_bulbs() -> void:
	for id in node_ids:
		var n: Dictionary = nodes[id]
		var arms: Array = n["arms"]
		n["bulb"] = arms.size() == 1
		n["junction"] = arms.size() >= 3
		if arms.size() < 3:
			n["sig"] = false


# ---- junction geometry ------------------------------------------------------------------------------------------------
static func edge_dir_at_node(e: Dictionary, end: int) -> Vector2:
	var pts: PackedVector2Array = e["pts"]
	if end == 0:
		return (LayoutGeo.point_at(pts, minf(8.0, e["len"] * 0.45)) - pts[0]).normalized()
	return (LayoutGeo.point_at(pts, maxf(e["len"] - 8.0, e["len"] * 0.55)) - pts[pts.size() - 1]).normalized()


## Computes arms (sorted by angle), trim distances, patch polygons and sidewalk corner pads for every node.
static func compute_junctions() -> void:
	junctions.clear()
	for id in node_ids:
		var n: Dictionary = nodes[id]
		var arms: Array = n["arms"]
		for a in arms:
			var e: Dictionary = edges[a["edge"]]
			a["dir"] = edge_dir_at_node(e, a["end"])
			a["hw"] = e["hw"]
			a["sw"] = e["sw"]
			a["ang"] = atan2(a["dir"].y, a["dir"].x)
		arms.sort_custom(func(p, q): return p["ang"] < q["ang"])
		var cnt := arms.size()
		if cnt == 1:
			arms[0]["trim"] = BULB_TRIM
		else:
			for i in cnt:
				var ai: Dictionary = arms[i]
				var best := 4.5
				for nb in [(i + 1) % cnt, (i + cnt - 1) % cnt]:
					if nb == i:
						continue
					var aj: Dictionary = arms[nb]
					var th := absf(wrapf(aj["ang"] - ai["ang"], -PI, PI))
					if th > deg_to_rad(165.0):
						continue
					th = maxf(th, deg_to_rad(25.0))
					var k := maxf((float(aj["hw"]) + float(ai["hw"]) * cos(th)) / sin(th), 0.0)
					best = maxf(best, k + CURB_R / tan(th * 0.5))
				ai["trim"] = best
		for a in arms:
			var e2: Dictionary = edges[a["edge"]]
			if a["end"] == 0:
				e2["trim_a"] = a["trim"]
			else:
				e2["trim_b"] = a["trim"]
	for id in node_ids:
		junctions[id] = _build_junction(id)


static func _arm_edge_pt(n: Vector2, a: Dictionary, lateral: float, extra: float = 0.0) -> Vector2:
	# point at distance trim(+extra) along the arm, `lateral` metres to the arm's right (outward travel)
	var d: Vector2 = a["dir"]
	return n + d * (float(a["trim"]) + extra) + LayoutGeo.right_of(d) * lateral


static func _build_junction(id: String) -> Dictionary:
	var n: Dictionary = nodes[id]
	var c: Vector2 = n["pos"]
	var arms: Array = n["arms"]
	var cnt := arms.size()
	var patch := PackedVector2Array()
	var pads: Array = []
	var corners: Array = []
	if cnt == 1:
		var a: Dictionary = arms[0]
		var r := float(a["hw"]) + BULB_EXTRA
		var d: Vector2 = a["dir"]
		for k in 16:
			var ang := TAU * float(k) / 16.0
			patch.append(c + Vector2(cos(ang), sin(ang)) * r)
		# sidewalk ring (only when the arm has sidewalks)
		if float(a["sw"]) > 0.1:
			var ring := PackedVector2Array()
			var inner := PackedVector2Array()
			var rs := r + float(a["sw"])
			for k in 16:
				var ang2 := TAU * float(k) / 16.0
				var dir2 := Vector2(cos(ang2), sin(ang2))
				# leave the arm mouth open
				ring.append(c + dir2 * rs)
				inner.append(c + dir2 * r)
			pads.append({"ring_outer": ring, "ring_inner": inner, "bulb": true, "dir": d})
		corners.append({"kind": "bulb", "pos": c, "radius": r})
		return {"patch": patch, "pads": pads, "corners": corners}
	for i in cnt:
		var ai: Dictionary = arms[i]
		var aj: Dictionary = arms[(i + 1) % cnt]
		var el: Vector2 = _arm_edge_pt(c, ai, -float(ai["hw"]))
		var er: Vector2 = _arm_edge_pt(c, ai, float(ai["hw"]))
		patch.append(el)
		patch.append(er)
		# corner between arm i (its right side) and arm j (its left side)
		var ej: Vector2 = _arm_edge_pt(c, aj, -float(aj["hw"]))
		var th := wrapf(aj["ang"] - ai["ang"], 0.0, TAU)
		if cnt == 2 and i == 1:
			th = wrapf(arms[0]["ang"] - arms[1]["ang"], 0.0, TAU)
		var straight := th > deg_to_rad(165.0) and th < deg_to_rad(195.0)
		var arc := PackedVector2Array()
		var kpt := Vector2.ZERO
		if not straight:
			var isect := LayoutGeo.line_intersect(er, ai["dir"], ej, aj["dir"])
			if is_nan(isect.x):
				kpt = (er + ej) * 0.5
			else:
				kpt = er + (ai["dir"] as Vector2) * isect.x
			# pull the control point toward the middle when the geometry is extreme
			for s in range(1, 6):
				arc.append(LayoutGeo.bezier2(er, kpt, ej, float(s) / 6.0))
			patch.append_array(arc)
		# sidewalk pad
		var sw_i := float(ai["sw"])
		var sw_j := float(aj["sw"])
		if sw_i > 0.1 or sw_j > 0.1:
			var si: Vector2 = _arm_edge_pt(c, ai, float(ai["hw"]) + sw_i)
			var sj: Vector2 = _arm_edge_pt(c, aj, -float(aj["hw"]) - sw_j)
			var pad := PackedVector2Array()
			pad.append(er)
			pad.append_array(arc)
			pad.append(ej)
			pad.append(sj)
			var xpt := Vector2.ZERO
			var has_x := false
			if not straight:
				var is2 := LayoutGeo.line_intersect(si, ai["dir"], sj, aj["dir"])
				if not is_nan(is2.x):
					xpt = si + (ai["dir"] as Vector2) * is2.x
					has_x = true
					pad.append(xpt)
			pad.append(si)
			pads.append({"poly": pad, "straight": straight, "corner": xpt if has_x else (si + sj) * 0.5, "i": i, "j": (i + 1) % cnt,
				"si": si, "sj": sj, "er": er, "ej": ej})
			corners.append({"kind": "corner", "pos": xpt if has_x else (si + sj) * 0.5, "straight": straight})
	return {"patch": patch, "pads": pads, "corners": corners}


# ---- queries ----------------------------------------------------------------------------------------------------------
static func edge_trimmed(e: Dictionary) -> PackedVector2Array:
	return LayoutGeo.sub(e["pts"], e["trim_a"], e["len"] - e["trim_b"])


## Lateral offset of lane `k` (0 = nearest the centre) from the road centre for traffic travelling in the edge direction (+) or against (-)
static func lane_offset(e: Dictionary, k: int) -> float:
	if e["oneway"]:
		return (float(k) - (float(e["lanes"]) - 1.0) * 0.5) * float(e["lane_w"])
	return float(e["median"]) * 0.5 + (float(k) + 0.5) * float(e["lane_w"])


static func signal_nodes() -> Array:
	var out: Array = []
	for id in node_ids:
		if nodes[id]["sig"]:
			out.append(id)
	return out
