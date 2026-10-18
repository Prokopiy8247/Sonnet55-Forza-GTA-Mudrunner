class_name IntersectionManager
extends RefCounted
## Right-of-way arbiter for junctions (signalised and not). Drivers ask for a RESERVATION of their connector chain before they
## enter the junction box; a reservation is granted when
##   * no current holder uses a conflicting chain (crossing / merging paths, see TrafficNet.chains_conflict) and
##   * no conflicting contender with priority would arrive inside our crossing window.
## Priority: road rank (arterial > street > residential), left turns yield to oncoming traffic, "yield to the right" on equal
## rank, then first-come-first-served; anyone waiting > 4 s longer than a contender beats it (no deadlocks).
## Holders that sit in the box for > HOLD_TIMEOUT seconds lose their reservation (stuck / crashed cars must not freeze a junction).

const HOLD_TIMEOUT := 16.0

var _state: Dictionary = {}      # jid -> {"holders": Array, "requests": Array}
var stats := {"grants": 0, "denied": 0, "timeouts": 0}
var _prune_t := 0.0


func _get_state(jid: int) -> Dictionary:
	var st: Variant = _state.get(jid, null)
	if st == null:
		st = {"holders": [], "requests": []}
		_state[jid] = st
	return st


func request(d: TrafficDriver, jid: int, chain: int) -> bool:
	if d.jn_granted:
		return true
	var st := _get_state(jid)
	var holders: Array = st["holders"]
	var requests: Array = st["requests"]
	if not requests.has(d):
		requests.append(d)
		d.jn_wait_start = d.mgr_clock()
	# 1) a holder with a conflicting chain is (still) inside the box
	for h in holders:
		if h != d and TrafficNet.chains_conflict(h.jn_chain, chain):
			stats["denied"] += 1
			return false
	# 2) a conflicting contender that has priority and would be there before we are clear of the box
	var my_clear: float = d.jn_clear_time()
	for o in requests:
		if o == d or o.jn_granted:
			continue
		if not TrafficNet.chains_conflict(o.jn_chain, chain):
			continue
		if _has_priority(o, d) and o.jn_eta < my_clear + 0.8:
			stats["denied"] += 1
			return false
	d.jn_granted = true
	d.jn_hold_start = d.mgr_clock()
	requests.erase(d)
	holders.append(d)
	stats["grants"] += 1
	return true


func cancel(d: TrafficDriver) -> void:
	if d.jn_jid < 0:
		return
	var st: Variant = _state.get(d.jn_jid, null)
	if st != null:
		(st["requests"] as Array).erase(d)


## Gives up everything the driver holds (left the junction, got despawned, crashed ...).
func release(d: TrafficDriver) -> void:
	if d.jn_jid >= 0:
		var st: Variant = _state.get(d.jn_jid, null)
		if st != null:
			(st["holders"] as Array).erase(d)
			(st["requests"] as Array).erase(d)
	d.jn_granted = false
	d.jn_jid = -1
	d.jn_chain = -1


func has_holders(jid: int) -> bool:
	var st: Variant = _state.get(jid, null)
	return st != null and not (st["holders"] as Array).is_empty()


## Number of vehicles currently holding a reservation (debug / test metric).
func holder_count() -> int:
	var n := 0
	for jid in _state:
		n += (_state[jid]["holders"] as Array).size()
	return n


func tick(dt: float, now: float) -> void:
	_prune_t -= dt
	if _prune_t > 0.0:
		return
	_prune_t = 0.5
	for jid in _state:
		var st: Dictionary = _state[jid]
		var holders: Array = st["holders"]
		for i in range(holders.size() - 1, -1, -1):
			var h: TrafficDriver = holders[i]
			if h == null or h.mode == TrafficDriver.MODE_DEAD or not is_instance_valid(h.v):
				holders.remove_at(i)
				continue
			if now - h.jn_hold_start > HOLD_TIMEOUT:
				holders.remove_at(i)
				h.jn_granted = false
				h.jn_chain = -1
				h.jn_jid = -1
				stats["timeouts"] += 1
		var requests: Array = st["requests"]
		for i in range(requests.size() - 1, -1, -1):
			var r: TrafficDriver = requests[i]
			if r == null or r.mode == TrafficDriver.MODE_DEAD or not is_instance_valid(r.v) or now - r.jn_wait_start > 60.0:
				requests.remove_at(i)


# ---- priority -----------------------------------------------------------------------------------------------------------------
## Does `a` go before `b`? (both want conflicting chains of the same junction)
func _has_priority(a: TrafficDriver, b: TrafficDriver) -> bool:
	var wa := a.jn_wait()
	var wb := b.jn_wait()
	if wa > wb + 4.0:
		return true
	if wb > wa + 4.0:
		return false
	var ca: Dictionary = TrafficNet.chains.get(a.jn_chain, {})
	var cb: Dictionary = TrafficNet.chains.get(b.jn_chain, {})
	if ca.is_empty() or cb.is_empty():
		return a.uid < b.uid
	var ra: float = ca["rank"]
	var rb: float = cb["rank"]
	if absf(ra - rb) > 1.5:
		return ra > rb
	var ha: Vector3 = ca["heading"]
	var hb: Vector3 = cb["heading"]
	var ta: int = ca["turn"]
	var tb: int = cb["turn"]
	# oncoming traffic: the left turner yields
	if ha.dot(hb) < -0.75 and ta != tb:
		if ta == TrafficNet.TURN_LEFT:
			return false
		if tb == TrafficNet.TURN_LEFT:
			return true
	# yield to the right (right-hand traffic): a comes from b's right?
	var rb_vec := Vector3(-hb.z, 0.0, hb.x)
	var ra_vec := Vector3(-ha.z, 0.0, ha.x)
	var a_on_right: bool = (ca["appr_dir"] as Vector3).dot(rb_vec) > 0.55
	var b_on_right: bool = (cb["appr_dir"] as Vector3).dot(ra_vec) > 0.55
	if a_on_right and not b_on_right:
		return true
	if b_on_right and not a_on_right:
		return false
	if absf(wa - wb) > 0.4:
		return wa > wb
	return a.uid < b.uid
