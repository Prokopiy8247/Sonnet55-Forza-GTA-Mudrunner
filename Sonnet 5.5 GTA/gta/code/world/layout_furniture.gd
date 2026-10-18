class_name LayoutFurniture
extends RefCounted
## Street furniture spots (WorldLayout.furniture): lamps every ~30 m, traffic signal heads at signalised junctions (signal_id + phase),
## stop / speed signs, hydrants, benches, bins, bollards along the quay, bus stops, cones + barriers at works, fences, utility boxes,
## mailboxes, parking meters, billboards, palms on the promenade, street trees.

const SW_Y := 0.15

static var _out: Array = []
static var _rng := RandomNumberGenerator.new()


static func _gy(p: Vector2) -> float:
	return LayoutTerrain.height(p.x, p.y)


static func _add(kind: StringName, p: Vector2, yaw: float, dy: float = SW_Y, signal_id: int = -1, phase: int = -1) -> void:
	var d := {"kind": kind, "pos": Vector3(p.x, _gy(p) + dy, p.y), "yaw": yaw, "signal_id": signal_id}
	if phase >= 0:
		d["phase"] = phase
	_out.append(d)


static func _yaw_of(dir: Vector2) -> float:
	return Util.dir_to_yaw(Vector3(dir.x, 0.0, dir.y))


static func build() -> void:
	_out = []
	_rng.seed = 777
	_lamps_and_edge_props()
	_signals_and_signs()
	_promenade_and_quay()
	_works_fences_misc()
	_park_and_plaza()
	_validate_against_lanes()
	WorldLayout.furniture = _out
	var counts := {}
	for f in _out:
		counts[f["kind"]] = int(counts.get(f["kind"], 0)) + 1
	print("[LayoutFurniture] ", _out.size(), " items ", counts)


# ---- along roads --------------------------------------------------------------------------------------------------------------------
static func _lamps_and_edge_props() -> void:
	var stop_i := 0
	for e in LayoutRoadNet.edges:
		var sw: float = e["sw"]
		var pts: PackedVector2Array = e["pts"]
		var cum := LayoutGeo.cum_lengths(pts)
		var hw: float = e["hw"]
		var s0: float = float(e["trim_a"]) + 7.0
		var s1: float = float(e["len"]) - float(e["trim_b"]) - 7.0
		var cls: StringName = e["cls"]
		var downtown: bool = e["name"] in ["Alder Street", "Birch Street", "Cedar Avenue", "Dune Avenue"]
		if cls == &"alley":
			# wall lamps: one per alley end
			var mid := LayoutGeo.point_at(pts, float(e["len"]) * 0.5, cum)
			_add(&"lamp", mid, 0.0, 0.0)
			continue
		if cls == &"hill":
			# guard barriers on the outer bends + speed signs
			var ss := s0
			var k := 0
			while ss < s1:
				var dd := LayoutGeo.dir_at(pts, ss, cum)
				var cc := LayoutGeo.point_at(pts, ss, cum)
				var rr := LayoutGeo.right_of(dd)
				if k % 3 == 0:
					_add(&"barrier", cc + rr * (hw + 0.8), _yaw_of(dd) + PI * 0.5, 0.0)
					_add(&"barrier", cc - rr * (hw + 0.8), _yaw_of(dd) + PI * 0.5, 0.0)
				if k % 6 == 0:
					_add(&"lamp", cc + rr * (hw + 1.0), _yaw_of(-rr), 0.0)
				ss += 14.0
				k += 1
			continue
		if sw < 0.1:
			continue
		var spacing := 30.0
		var s := s0
		var idx := 0
		while s < s1:
			var d := LayoutGeo.dir_at(pts, s, cum)
			var c := LayoutGeo.point_at(pts, s, cum)
			var r := LayoutGeo.right_of(d)
			var side := 1.0 if idx % 2 == 0 else -1.0
			# lamp at the outer part of the curb strip, arm over the road
			var lp := c + r * side * (hw + 0.8)
			_add(&"lamp", lp, _yaw_of(-r * side))
			# periodic props on the other side
			var op := c - r * side * (hw + sw - 0.7)
			var roll := _rng.randf()
			if downtown and idx % 2 == 1:
				_add(&"parking_meter", c + r * side * (hw + 0.6), _yaw_of(-r * side))
			if roll < 0.12:
				_add(&"hydrant", c - r * side * (hw + 0.7), _yaw_of(r * side))
			elif roll < 0.22:
				_add(&"bin", op, _yaw_of(r * side))
			elif roll < 0.30 and (downtown or cls == &"street"):
				_add(&"bench", op, _yaw_of(r * side))
			elif roll < 0.36 and cls == &"residential":
				_add(&"mailbox", op, _yaw_of(r * side))
			elif roll < 0.40 and cls == &"industrial":
				_add(&"utility_box", op, _yaw_of(r * side))
			# street trees on residential + collector streets (every other lamp slot)
			if (cls == &"residential" or cls == &"street") and not downtown and idx % 2 == 0:
				var tp := c - r * side * (hw + sw - 0.9) + d * 12.0
				_add(&"tree_street", tp, _rng.randf() * TAU)
			elif downtown and idx % 3 == 0:
				var tp2 := c - r * side * (hw + sw - 0.9) + d * 10.0
				_add(&"tree_street", tp2, _rng.randf() * TAU)
			s += spacing * 0.5 if idx % 2 == 0 else spacing * 0.5
			idx += 1
		# bus stop mid-block on selected streets
		if (cls == &"street" or cls == &"arterial") and float(e["len"]) > 60.0 and stop_i % 2 == 0:
			var sm := float(e["len"]) * 0.5
			var dm := LayoutGeo.dir_at(pts, sm, cum)
			var cm := LayoutGeo.point_at(pts, sm, cum)
			var rm := LayoutGeo.right_of(dm)
			_add(&"bus_stop", cm + rm * (hw + sw - 1.1), _yaw_of(-rm))
		if cls == &"street" or cls == &"arterial":
			stop_i += 1
		# speed sign near each end, on the right-hand sidewalk of the travel direction
		if cls == &"arterial" or cls == &"residential" or cls == &"industrial":
			var sa := float(e["trim_a"]) + 14.0
			var da := LayoutGeo.dir_at(pts, sa, cum)
			_add(&"sign_speed", LayoutGeo.point_at(pts, sa, cum) + LayoutGeo.right_of(da) * (hw + 0.6), _yaw_of(-da))
			var sb := float(e["len"]) - float(e["trim_b"]) - 14.0
			var db := LayoutGeo.dir_at(pts, sb, cum)
			_add(&"sign_speed", LayoutGeo.point_at(pts, sb, cum) - LayoutGeo.right_of(db) * (hw + 0.6), _yaw_of(db))


# ---- junctions ------------------------------------------------------------------------------------------------------------------------
static func _signals_and_signs() -> void:
	for id in LayoutRoadNet.node_ids:
		var n: Dictionary = LayoutRoadNet.nodes[id]
		var c: Vector2 = n["pos"]
		var arms: Array = n["arms"]
		if arms.size() < 3:
			continue
		var sid: int = int(LayoutLanes.node_signal.get(id, -1))
		for a in arms:
			var d: Vector2 = a["dir"]
			var r := LayoutGeo.right_of(d)
			var hw: float = a["hw"]
			var trim: float = a["trim"]
			if float(a["sw"]) < 0.1:
				continue
			var e: Dictionary = LayoutRoadNet.edges[a["edge"]]
			var p_near := c + d * (trim + 5.5) - r * (hw + 0.9)
			if sid >= 0:
				var ph := int(a.get("phase", 0))
				_add(&"signal", p_near, _yaw_of(d), SW_Y, sid, ph)
				if e["cls"] == &"arterial":
					# second head on the far side for the wide 2+2 approach (right side beyond the lanes, outgoing side)
					_add(&"signal", c + d * (trim + 5.5) + r * (hw + 0.9), _yaw_of(d), SW_Y, sid, ph)
			else:
				# stop sign for minor roads meeting a bigger one
				var max_hw := 0.0
				for o in arms:
					max_hw = maxf(max_hw, float(o["hw"]))
				if hw < max_hw - 0.2 or e["cls"] == &"residential":
					_add(&"sign_stop", p_near, _yaw_of(d))


# ---- promenade, quay, beach ------------------------------------------------------------------------------------------------
static func _promenade_and_quay() -> void:
	# palms along the promenade and the south side of Seaview Drive
	var x := -92.0
	while x <= 66.0:
		_add(&"palm", Vector2(x, 154.8), _rng.randf() * TAU, 0.0)
		if int(x) % 2 == 0:
			_add(&"palm", Vector2(x + 5.0, 142.8), _rng.randf() * TAU, 0.0)
		x += 9.0
	for bx in [-75.0, -45.0, -15.0, 15.0, 45.0]:
		_add(&"bench", Vector2(bx, 156.6), PI * 0.5 * 2.0, 0.0)
		_add(&"bin", Vector2(bx + 3.0, 156.6), 0.0, 0.0)
	# bollards along the quay rim (west + east) and pier roots
	for seg in [Vector2(-296.0, -104.0), Vector2(80.0, 296.0)]:
		var sx: float = seg.x
		while sx <= seg.y:
			var on_pier := false
			for p in WorldLayout.piers:
				var r: Rect2 = p["rect"]
				if absf(r.position.y - 192.0) < 0.5 and sx > r.position.x - 1.0 and sx < r.end.x + 1.0:
					on_pier = true
			if not on_pier:
				_add(&"bollard", Vector2(sx, 194.2), 0.0, 0.0)
			sx += 7.0
	# pier lamps + bollards at the tips
	for p in WorldLayout.piers:
		if p.get("finger", false):
			continue
		var r2: Rect2 = p["rect"]
		var h: float = float(p["height"])
		var zz := r2.position.y + 4.0
		while zz < r2.end.y - 2.0:
			_add(&"lamp", Vector2(r2.position.x + 0.6, zz), PI * 0.5, h + 0.03)
			_add(&"lamp", Vector2(r2.end.x - 0.6, zz + 8.0), -PI * 0.5, h + 0.03)
			zz += 16.0
		_add(&"bollard", Vector2(r2.position.x + 0.5, r2.end.y - 0.6), 0.0, h + 0.03)
		_add(&"bollard", Vector2(r2.end.x - 0.5, r2.end.y - 0.6), 0.0, h + 0.03)
	# airfield boundary fence (landside west edge + seaward side)
	var fx := 76.0
	while fx < 296.0:
		_add(&"fence", Vector2(fx, 186.5), 0.0, 0.0)
		fx += 3.0


# ---- works, fences, misc --------------------------------------------------------------------------------------------------------------
static func _works_fences_misc() -> void:
	# road works: cone line + barriers along the kerb of Foundry Street and a residential construction site
	var wx := 126.0
	while wx < 156.0:
		_add(&"cone", Vector2(wx, -26.0), 0.0, SW_Y)
		wx += 3.0
	_add(&"barrier", Vector2(125.0, -26.5), 0.0, SW_Y)
	_add(&"barrier", Vector2(157.5, -26.5), 0.0, SW_Y)
	for i in 6:
		_add(&"cone", Vector2(-148.0 + i * 2.5, 52.5), 0.0, SW_Y)
	_add(&"barrier", Vector2(-150.5, 53.0), 0.0, SW_Y)
	_add(&"barrier", Vector2(-132.0, 53.0), 0.0, SW_Y)
	# fences around industrial yards and parking lots
	for g in LayoutLots.grounds:
		var key: String = g["key"]
		if key != "yard":
			continue
		var r: Rect2 = g["rect"]
		var step := 3.0
		var x := r.position.x + 1.5
		while x < r.end.x - 1.0:
			_add(&"fence", Vector2(x, r.end.y - 0.4), 0.0, 0.0)
			x += step
		var z := r.position.y + 1.5
		while z < r.end.y - 1.0:
			_add(&"fence", Vector2(r.end.x - 0.4, z), PI * 0.5, 0.0)
			z += step
	# billboards
	# world-fill: billboards face the road (front = -Z at yaw 0): the ones north of their road need yaw PI
	for bb in [[Vector2(130.0, -96.5), PI], [Vector2(160.0, -83.0), 0.0], [Vector2(-60.0, -97.0), PI], [Vector2(-150.0, 105.0), PI], [Vector2(215.0, 78.5), PI]]:
		_add(&"billboard", bb[0], float(bb[1]), 0.0)
	# utility boxes at downtown + residential corners
	for id in LayoutRoadNet.node_ids:
		var n: Dictionary = LayoutRoadNet.nodes[id]
		if (n["arms"] as Array).size() >= 3 and _rng.randf() < 0.3:
			var c: Vector2 = n["pos"]
			var best: Dictionary = (n["arms"] as Array)[0]
			var dd: Vector2 = best["dir"]
			var rr := LayoutGeo.right_of(dd)
			_add(&"utility_box", c + dd * (float(best["trim"]) + 7.5) + rr * (float(best["hw"]) + 1.8), _yaw_of(-rr), SW_Y)


static func _park_and_plaza() -> void:
	# benches + bins around the pond loop and in the plaza, lamps on park paths
	for k in 8:
		var a := TAU * float(k) / 8.0 + 0.2
		var p := LayoutTerrain.POND_C + Vector2(cos(a), sin(a)) * 33.5
		_add(&"bench", p, _yaw_of(-Vector2(cos(a), sin(a))), 0.0)
		if k % 2 == 0:
			_add(&"lamp", LayoutTerrain.POND_C + Vector2(cos(a + 0.3), sin(a + 0.3)) * 32.0, a, 0.0)
	for k in 4:
		var px := -20.0 + 13.0 * k
		_add(&"bench", Vector2(px, 33.5), 0.0, 0.05)
		_add(&"lamp", Vector2(px + 6.0, 27.5), 0.0, 0.05)
	_add(&"bin", Vector2(-24.0, 33.5), 0.0, 0.05)
	_add(&"bin", Vector2(24.0, 33.5), 0.0, 0.05)
	# viewpoint railing
	var vp := Vector2(205.0, -224.0)
	for k in 10:
		var a2 := PI * 0.1 * k + PI * 1.0
		_add(&"barrier", vp + Vector2(cos(a2), sin(a2)) * 11.0, a2 + PI * 0.5, 0.0)
	_add(&"bench", vp + Vector2(0, 6.0), PI, 0.0)


# ---- lane clearance (world-fill) --------------------------------------------------------------------------------------------------------
## Solid street props must stand at least LANE_CLEAR m (XZ, segment distance) from every lane of the lane graph. Barriers, cones, fences and
## signals are intentional lane-side objects and are never removed. Alley wall lamps (they stood in the one-way alley lane) are dropped.
const LANE_CLEAR := 1.6
const LANE_CHECKED: Array[StringName] = [&"lamp", &"bin", &"bollard", &"hydrant", &"parking_meter", &"bench", &"mailbox", &"utility_box", &"tree_street", &"palm"]

static var lane_removed: Dictionary = {}


static func _lane_dist(p: Vector3) -> float:
	var lanes: LaneGraph = WorldLayout.lanes
	var best := 1e9
	var q := Vector2(p.x, p.z)
	for i in lanes.points_in_radius(p, 10.0):
		var a: Vector3 = lanes.positions[i]
		var av := Vector2(a.x, a.z)
		best = minf(best, av.distance_to(q))
		for j in (lanes.next[i] as PackedInt32Array):
			var b: Vector3 = lanes.positions[j]
			var bv := Vector2(b.x, b.z)
			var ab := bv - av
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 0.0001 else clampf((q - av).dot(ab) / l2, 0.0, 1.0)
			best = minf(best, (av + ab * t).distance_to(q))
	return best


static func _validate_against_lanes() -> void:
	lane_removed = {}
	if WorldLayout.lanes == null or WorldLayout.lanes.size() == 0:
		return
	var kept: Array = []
	for f in _out:
		var k: StringName = f["kind"]
		if k in LANE_CHECKED and _lane_dist(f["pos"]) < LANE_CLEAR:
			lane_removed[k] = int(lane_removed.get(k, 0)) + 1
			continue
		kept.append(f)
	_out = kept
	if not lane_removed.is_empty():
		print("[LayoutFurniture] lane clearance removed ", lane_removed)
