class_name TrafficNet
extends RefCounted
## Static lookup tables derived ONCE from WorldLayout.lanes (the project-owned lane graph) for the traffic AI:
##   * junction chains (every connector path through a junction box), the junctions they form, conflict tests between chains
##   * dead-end ("cul-de-sac") lanes so cars avoid driving into bulbs, lane points near junctions (no parking there)
## Nothing here touches the scene tree. Call TrafficNet.ensure() before use (idempotent, ~10-25 ms for the real map).

const TURN_STRAIGHT := 0
const TURN_RIGHT := 1
const TURN_LEFT := 2
const TURN_UTURN := 3

static var built := false
static var graph: LaneGraph = null
## per lane point: chain id for connector points (= index of the first connector point of that chain), else -1
static var chain_of := PackedInt32Array()
## per lane point: 1 = this lane leads into a dead end bulb (U-turn), else 0
static var dead_lane := PackedByteArray()
## per lane point: 1 = within ~24 m before a junction mouth or ~16 m after one (no parking, no overtaking)
static var near_junction := PackedByteArray()
## chain id -> {id, jid, pts: PackedInt32Array (connector points), approach: int, exit: int, turn: int, length: float, rank: float,
##              geo: PackedVector3Array (approach + connectors + exit), appr_dir: Vector3 (centre -> approach), heading: Vector3, signal: int}
static var chains: Dictionary = {}
## jid -> {id, center: Vector3, radius: float, signal: int, chains: Array[int]}
static var junctions: Array = []
static var build_ms := 0
static var _conflict_cache: Dictionary = {}


static func ensure() -> bool:
	if built and graph == WorldLayout.lanes:
		return true
	if WorldLayout.lanes == null or WorldLayout.lanes.size() == 0:
		return false
	_build()
	return built


static func _build() -> void:
	var t0 := Time.get_ticks_usec()
	var g: LaneGraph = WorldLayout.lanes
	graph = g
	var n := g.size()
	chain_of = PackedInt32Array()
	chain_of.resize(n)
	chain_of.fill(-1)
	dead_lane = PackedByteArray()
	dead_lane.resize(n)
	near_junction = PackedByteArray()
	near_junction.resize(n)
	chains = {}
	junctions = []
	_conflict_cache = {}
	# ---- 1. chains: every connector path from an approach point to the first point of the out lane ---------------------------
	var conn := LaneGraph.KIND_CONNECTOR
	for i in n:
		if g.kind[i] == conn:
			continue
		var nx: PackedInt32Array = g.next[i]
		for c in nx:
			if g.kind[c] != conn:
				continue
			var pts := PackedInt32Array()
			var cur: int = c
			var guard := 0
			while g.kind[cur] == conn and guard < 40:
				pts.append(cur)
				chain_of[cur] = c
				var nn: PackedInt32Array = g.next[cur]
				if nn.is_empty():
					cur = -1
					break
				cur = nn[0]
				guard += 1
			if cur < 0 or pts.is_empty():
				continue
			var geo := PackedVector3Array()
			geo.append(g.positions[i])
			var length := g.positions[i].distance_to(g.positions[pts[0]])
			var prev_p: Vector3 = g.positions[i]
			for pt in pts:
				geo.append(g.positions[pt])
				length += prev_p.distance_to(g.positions[pt])
				prev_p = g.positions[pt]
			geo.append(g.positions[cur])
			length += prev_p.distance_to(g.positions[cur])
			var d0: Vector3 = g.dirs[i]
			var d1: Vector3 = g.dirs[cur]
			var r0 := Vector3(-d0.z, 0.0, d0.x)
			var side := d1.dot(r0)
			var fw := d1.dot(d0)
			var turn := TURN_STRAIGHT
			if fw < -0.5:
				turn = TURN_UTURN
			elif side > 0.5:
				turn = TURN_RIGHT
			elif side < -0.5:
				turn = TURN_LEFT
			# rank of the approach = the speed limit of the lane just before the mouth (highest of the two preceding points)
			var rank := g.speed_limit[i]
			var pv: PackedInt32Array = g.prev[i]
			for q in pv:
				if g.kind[q] != conn:
					rank = maxf(rank, g.speed_limit[q])
			chains[c] = {"id": c, "jid": -1, "pts": pts, "approach": i, "exit": cur, "turn": turn, "length": length, "rank": rank,
				"geo": geo, "appr_dir": Vector3.ZERO, "heading": Vector3(d0.x, 0.0, d0.z), "signal": -1}
	# ---- 2. junction clustering (union-find over shared approach / exit points) ---------------------------------------------------
	var parent: Dictionary = {}
	var owner_of_point: Dictionary = {}
	for cid in chains:
		parent[cid] = cid
	for cid in chains:
		var ch: Dictionary = chains[cid]
		for pt in [ch["approach"], ch["exit"]]:
			if owner_of_point.has(pt):
				_union(parent, int(owner_of_point[pt]), int(cid))
			else:
				owner_of_point[pt] = cid
	var root_to_j: Dictionary = {}
	for cid in chains:
		var r := _find(parent, int(cid))
		if not root_to_j.has(r):
			root_to_j[r] = junctions.size()
			junctions.append({"id": junctions.size(), "center": Vector3.ZERO, "radius": 0.0, "signal": -1, "chains": []})
		var jid: int = root_to_j[r]
		chains[cid]["jid"] = jid
		(junctions[jid]["chains"] as Array).append(cid)
	for j in junctions:
		var sum := Vector3.ZERO
		var cnt := 0
		for cid in j["chains"]:
			for pt in chains[cid]["pts"]:
				sum += g.positions[pt]
				cnt += 1
		var centre: Vector3 = sum / maxf(float(cnt), 1.0)
		var rad := 0.0
		for cid in j["chains"]:
			for pt in chains[cid]["pts"]:
				rad = maxf(rad, g.positions[pt].distance_to(centre))
		j["center"] = centre
		j["radius"] = rad + 2.0
		var max_rank := 0.0
		for cid in j["chains"]:
			max_rank = maxf(max_rank, float(chains[cid]["rank"]))
		j["max_rank"] = max_rank
		var sig := -1
		for cid in j["chains"]:
			var ch2: Dictionary = chains[cid]
			var ap: int = ch2["approach"]
			var d := (g.positions[ap] - centre)
			d.y = 0.0
			ch2["appr_dir"] = d.normalized() if d.length_squared() > 0.01 else -ch2["heading"]
			# the stop line point sits right before the approach point
			for q in g.prev[ap]:
				if g.signal_id[q] >= 0:
					ch2["signal"] = g.signal_id[q]
					sig = g.signal_id[q]
		j["signal"] = sig
	# ---- 3. dead-end lanes (walk back from every U-turn chain) --------------------------------------------------------------------
	for cid in chains:
		var ch3: Dictionary = chains[cid]
		if int(ch3["turn"]) != TURN_UTURN:
			continue
		var p: int = ch3["approach"]
		var guard2 := 0
		while p >= 0 and guard2 < 60:
			dead_lane[p] = 1
			var prs: PackedInt32Array = g.prev[p]
			if prs.size() != 1 or g.kind[prs[0]] == conn:
				break
			p = prs[0]
			guard2 += 1
	# ---- 4. points near junctions ------------------------------------------------------------------------------------------------------
	for cid in chains:
		var ch4: Dictionary = chains[cid]
		var acc := 0.0
		var p2: int = ch4["approach"]
		var guard3 := 0
		while p2 >= 0 and acc < 26.0 and guard3 < 12:
			near_junction[p2] = 1
			var prs2: PackedInt32Array = g.prev[p2]
			if prs2.is_empty() or g.kind[prs2[0]] == conn:
				break
			acc += g.positions[p2].distance_to(g.positions[prs2[0]])
			p2 = prs2[0]
			guard3 += 1
		var acc2 := 0.0
		var p3: int = ch4["exit"]
		guard3 = 0
		while p3 >= 0 and acc2 < 18.0 and guard3 < 8:
			near_junction[p3] = 1
			var nxs: PackedInt32Array = g.next[p3]
			if nxs.is_empty() or g.kind[nxs[0]] == conn:
				break
			acc2 += g.positions[p3].distance_to(g.positions[nxs[0]])
			p3 = nxs[0]
			guard3 += 1
	for i2 in n:
		if g.kind[i2] == conn:
			near_junction[i2] = 1
	built = true
	build_ms = int((Time.get_ticks_usec() - t0) / 1000)
	print("[Traffic] lane net: %d lane points, %d junction chains in %d junctions (%d signalised) in %d ms" % [
		n, chains.size(), junctions.size(), _count_signalised(), build_ms])


static func _count_signalised() -> int:
	var c := 0
	for j in junctions:
		if int(j["signal"]) >= 0:
			c += 1
	return c


static func _find(parent: Dictionary, a: int) -> int:
	var r := a
	while int(parent[r]) != r:
		r = int(parent[r])
	var c := a
	while int(parent[c]) != r:
		var nxt := int(parent[c])
		parent[c] = r
		c = nxt
	return r


static func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


# ---- queries --------------------------------------------------------------------------------------------------------------------
## True when two chains of the same junction cross / merge (cars on both would collide). Cached.
static func chains_conflict(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0:
		return false
	var key := (mini(a, b) << 16) | maxi(a, b)
	if _conflict_cache.has(key):
		return _conflict_cache[key]
	var res := _compute_conflict(a, b)
	_conflict_cache[key] = res
	return res


static func _compute_conflict(a: int, b: int) -> bool:
	var ca: Dictionary = chains.get(a, {})
	var cb: Dictionary = chains.get(b, {})
	if ca.is_empty() or cb.is_empty() or ca["jid"] != cb["jid"]:
		return false
	if ca["approach"] == cb["approach"]:
		return false                        # same lane: they follow each other
	if ca["exit"] == cb["exit"]:
		return true                         # merge into the same out lane
	var ga: PackedVector3Array = ca["geo"]
	var gb: PackedVector3Array = cb["geo"]
	# same arm, neighbouring lanes (e.g. arterial 2 lanes): paths diverge but never cross -> allowed unless they really touch
	var thr := 3.3
	var same_arm: bool = ga[0].distance_to(gb[0]) < 7.0
	var best := INF
	var start_a := 1 if same_arm else 0
	var start_b := 1 if same_arm else 0
	for i in range(start_a, ga.size()):
		var pa: Vector3 = ga[i]
		for j in range(start_b, gb.size()):
			var pb: Vector3 = gb[j]
			var dx := pa.x - pb.x
			var dz := pa.z - pb.z
			var d2 := dx * dx + dz * dz
			if d2 < best:
				best = d2
	if same_arm:
		thr = 2.2
	return best < thr * thr


## Weighted pick of the successor of lane point `cur` (used when a lane point has several successors = a junction choice).
## `dir_to_player` (XZ unit, or ZERO) biases far cars to head back toward the player.
static func pick_next(cur: int, rng: RandomNumberGenerator, toward_player: Vector3, bias: float) -> int:
	var g := graph
	var nx: PackedInt32Array = g.next[cur]
	if nx.is_empty():
		return -1
	if nx.size() == 1:
		return nx[0]
	var weights := PackedFloat32Array()
	var total := 0.0
	for c in nx:
		var w := 1.0
		if g.kind[c] == LaneGraph.KIND_CONNECTOR and chains.has(c):
			var ch: Dictionary = chains[c]
			match int(ch["turn"]):
				TURN_STRAIGHT:
					w = 1.0
				TURN_RIGHT:
					w = 0.55
				TURN_LEFT:
					w = 0.5
				_:
					w = 0.02
			var ex: int = ch["exit"]
			if dead_lane[ex] != 0:
				w *= 0.12
			if g.speed_limit[ex] < 8.0:
				w *= 0.02                                  # one-way alleys: tight, lamps stand in the middle, nothing to gain
			if not LaneClearance.chain_passable(ch["pts"]):
				w = 0.0
			if bias > 0.0 and toward_player != Vector3.ZERO:
				var ed: Vector3 = g.dirs[ex]
				w *= 1.0 + bias * maxf(ed.dot(toward_player), -0.4)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for k in nx.size():
		r -= weights[k]
		if r <= 0.0:
			return nx[k]
	return nx[nx.size() - 1]


## Cheap check: is this lane point a stop line / signal approach?
static func signal_at(i: int) -> int:
	return graph.signal_id[i] if graph != null else -1
