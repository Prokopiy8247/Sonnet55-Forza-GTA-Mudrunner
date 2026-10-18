class_name TrafficDriver
extends RefCounted
## AI brain of ONE civilian traffic car. NOT a node: TrafficManager ticks every driver from a single _physics_process with
## distance tiers (near < 60 m every frame, mid 60-140 m every 3rd, far every 6th), so there is no per-car script cost.
##
## Pipeline per update:  progress along the lane path -> look-ahead scan (speed limits, curvature, stop lines, junction mouth)
## -> obstacle scan (grid: vehicles + pedestrians, corridor test along the path, lateral side-step for parked cars)
## -> signal / junction right-of-way gate (IntersectionManager reservations) -> target speed (time-gap following,
## stopping profiles) -> smooth throttle / brake + pure-pursuit steering -> reactions (honk, flee, crash, siren yield, stuck recovery).
## The vehicle only ever receives input_throttle / input_brake / input_steer / input_horn (VehicleBase contract).

const MODE_DRIVE := 0
const MODE_CRASHED := 1        # stopped after a collision (hazards), resumes after crash_t
const MODE_BREAKDOWN := 2      # pulled over with hazards for a while
const MODE_REVERSE := 3        # stuck recovery: backing up a few metres
const MODE_DEAD := 4           # no longer driven by traffic (released / despawned)

const R_FREE := 0
const R_SIGNAL := 1
const R_YIELD := 2
const R_LEADER := 3
const R_PED := 4
const R_BLOCK := 5

const A_LAT := 3.3             # comfortable lateral acceleration (m/s^2) for the curve speed limit
const B_STOP := 2.7            # comfortable braking used by the stopping profiles
const MAX_CRUISE := 21.0       # no civilian goes faster than this (75 km/h)
const NP := 56                 # scratch array size (path points ahead)
const LANE_CHANGE_RATE := 1.25 # m/s lateral
const BRAKE_MIN_SPEED := 1.25  # m/s: below this the brake pedal is released (VehicleBase treats the pedal as REVERSE under 1.0 m/s, its own stationary hold takes over under 0.9)
const STOP_MARGIN := 1.3       # m: cars stop this far before a stop line (the last ~1 m is coasting)
const REV_SPEED := 2.4         # m/s: maximum backing-up speed of the stuck-recovery manoeuvre

# ---- statics pushed by TrafficManager each frame -------------------------------------------------------------------------
static var g_speed_scale := 1.0      # < 1 in rain / fog
static var g_headway_scale := 1.0
static var g_want_lights := false
static var g_player_pos := Vector3.ZERO
static var g_siren_idx: Array = []
static var g_ped_hazard := true
static var _ray_q: PhysicsRayQueryParameters3D = null

# ---- identity -------------------------------------------------------------------------------------------------------------
var v: VehicleBase = null
var npc: Node = null
var uid := 0
var mode := MODE_DRIVE
var tier := 0
var stagger := 0
var last_update := 0.0
var now := 0.0
var spawn_time := 0.0
var rng: RandomNumberGenerator = null
var grid: TrafficGrid = null
var junction: IntersectionManager = null
var want_recycle := false
var released_reason := ""

# ---- vehicle constants ------------------------------------------------------------------------------------------------------
var hl := 2.3
var hw := 0.9
var wheelbase := 2.7
var steer_lock := 0.6
var steer_min := 0.05
var steer_gain := 1.5
var lat_lim := 11.0
var brake_cap := 9.0
var accel_avail_k := 117000.0     # P*eta/mass  (m^2/s^3)
var a_acc_max := 2.5

# ---- personality ----------------------------------------------------------------------------------------------------------------
var spd_factor := 1.0
var headway := 1.5
var aggression := 0.5
var patience := 2.5

# ---- path -------------------------------------------------------------------------------------------------------------------------
var _pos: PackedVector3Array
var _dir: PackedVector3Array
var _lim: PackedFloat32Array
var _kind: PackedByteArray
var _sigid: PackedInt32Array
var _sigph: PackedInt32Array
var _next: Array
var P := PackedInt32Array()
var seg := 0
var ad := PackedFloat32Array()     # distance from the car's projection to path point seg+k
var sx := PackedFloat32Array()
var sz := PackedFloat32Array()
var sdx := PackedFloat32Array()
var sdz := PackedFloat32Array()
var sl := PackedFloat32Array()
var m_ahead := 0
var lat_off := 0.0                  # lateral offset of the intended track from the path (+ = right)
var lat_pos := 0.0                  # measured lateral position of the car relative to the path
var xte_max := 0.0
var xte_sum := 0.0
var xte_n := 0

# ---- junction / signal state --------------------------------------------------------------------------------------------------
var jn_jid := -1
var jn_chain := -1
var jn_granted := false
var jn_eta := 0.0
var jn_wait_start := 0.0
var jn_hold_start := 0.0
var jn_exit_pt := -1
var jn_len := 10.0
var jn_d_entry := 0.0
var _dec_sig := -1
var _dec_go := true
var _dec_st := 0                     # signal state (0 green / 1 yellow / 2 red) the last go / stop decision was made in
var red_runs := 0
var box_t := 0.0
var box_stall_t := 0.0
var box_block_counted := false

# ---- control state ----------------------------------------------------------------------------------------------------------------
var thr := 0.0
var brk := 0.0
var steer_cmd := 0.0
var stop_reason := R_FREE
var idle_t := 0.0
var wait_signal_t := 0.0
var stuck_count := 0
var honk_t := 0.0
var honk_cd := 0.0
var honks := 0
var emergency_count := 0
var crash_t := 0.0
var crashed_at := 0.0
var rev_t := 0.0
var rev_steer := 0.0
var flee_t := 0.0
var yield_t := 0.0
var breakdown_t := 0.0
var hazard_on := false
var _haz_phase := 0.0
var _lights_t := 0.0
var lc_cool := 0.0
var pass_t := 0.0
var pass_obstacle: Node = null
var coast_lead_t := 0.0

# ---- scan results ---------------------------------------------------------------------------------------------------------------------
var lead_s := 999.0          # path distance from my centre to the rear of the nearest blocking obstacle
var lead_v := 0.0
var lead_kind := 0           # 0 none, 1 vehicle, 2 pedestrian, 3 solid
var lead_node: Node = null
var lead_ai: TrafficDriver = null
var side_shift := 0.0
var caution := false
var solid_s := 999.0
var solid_t := -10.0
var _scan_out := PackedInt32Array()
var _probe_n := 0

var a_meas := 0.0
var _prev_spd := 0.0
var thr_trim := 0.0
var dbg_vt := 0.0
var dbg_stop := 999.0
var dbg_a := 0.0

# stats
var dist_driven := 0.0
var speed_sum := 0.0
var speed_n := 0


func mgr_clock() -> float:
	return now


func jn_wait() -> float:
	return maxf(now - jn_wait_start, 0.0) if jn_wait_start > 0.0 else 0.0


func jn_clear_time() -> float:
	return (jn_d_entry + jn_len + hl * 2.0) / maxf(absf(_cur_spd) + 1.5, 4.0)


var _cur_spd := 0.0


# =====================================================================================================================
# Setup
# =====================================================================================================================
func setup(vehicle: VehicleBase, lane_idx: int, random: RandomNumberGenerator, grid_ref: TrafficGrid, junc: IntersectionManager, start_time: float) -> bool:
	v = vehicle
	rng = random
	grid = grid_ref
	junction = junc
	spawn_time = start_time
	now = start_time
	last_update = start_time
	var G: LaneGraph = WorldLayout.lanes
	_pos = G.positions
	_dir = G.dirs
	_lim = G.speed_limit
	_kind = G.kind
	_sigid = G.signal_id
	_sigph = G.signal_phase
	_next = G.next
	hl = float(v.def.get("length", 4.5)) * 0.5
	hw = float(v.def.get("width", 1.8)) * 0.5
	wheelbase = float(v.def.get("wheelbase", 2.7))
	var sl_v: Variant = v.get("steer_lock")
	steer_lock = float(sl_v) if sl_v != null else deg_to_rad(float(v.def.get("steer_lock", 34.0)))
	var sm_v: Variant = v.get("steer_min")
	steer_min = float(sm_v) if sm_v != null else deg_to_rad(float(v.def.get("steer_min", 4.5)))
	steer_gain = float(v.def.get("steer_gain", 1.5))
	lat_lim = float(v.def.get("grip", 1.15)) * 9.81 * float(v.def.get("gravity_scale", 1.15))
	brake_cap = float(v.def.get("brake", 11.0))
	var mass_v := float(v.def.get("mass", 1400.0))
	accel_avail_k = float(v.def.get("power_kw", 100.0)) * 1000.0 * float(v.def.get("power_mult", 1.25)) * 0.8 / mass_v
	# personality
	spd_factor = clampf(rng.randfn(1.0, 0.07), 0.85, 1.15)
	headway = clampf(rng.randfn(1.5, 0.22), 1.05, 2.1)
	aggression = rng.randf()
	patience = rng.randf_range(1.8, 4.5)
	a_acc_max = lerpf(1.9, 3.0, aggression)
	if mass_v > 5000.0:
		spd_factor = minf(spd_factor, 1.0) * 0.93
		a_acc_max = minf(a_acc_max, 1.7)
	ad.resize(NP)
	sx.resize(NP)
	sz.resize(NP)
	sdx.resize(NP)
	sdz.resize(NP)
	sl.resize(NP)
	v.auto_headlights = false
	v.set_ai_controlled(true)
	P = PackedInt32Array([lane_idx])
	seg = 0
	_extend_path()
	return P.size() >= 3


## Highest speed the car may be given when it is placed on the road right now (spawn): it must still be able to stop at the first
## signal ahead that is not (and will not stay) green, and must not be thrown into a junction mouth it cannot see yet.
func safe_spawn_speed(want: float, t: float) -> float:
	var best := want
	var dist := 0.0
	var n := mini(P.size(), 30)
	for k in range(1, n):
		dist += _pos[P[k - 1]].distance_to(_pos[P[k]])
		if dist > 80.0:
			break
		var si: int = _sigid[P[k]]
		if si >= 0:
			var eta := dist / maxf(want, 3.0)
			var st := WorldLayout.signal_state(si, _sigph[P[k]], t)
			if st != 0 or WorldLayout.signal_state(si, _sigph[P[k]], t + eta) != 0:
				var room := maxf(dist + 2.2 - 0.6 - hl, 0.0)
				best = minf(best, sqrt(2.0 * 2.0 * room))
			break
	return best


## Re-plans the path from the closest suitable lane point (after being pushed off the road, lane-graph changes, recovery).
func replan(p: Vector3, fwd: Vector3) -> bool:
	var G: LaneGraph = WorldLayout.lanes
	var idx := G.nearest(p, fwd, 22.0)
	if idx < 0:
		idx = G.nearest(p, Vector3.ZERO, 30.0)
	if idx < 0:
		return false
	# start from the point AHEAD of the car along the lane
	var nx: PackedInt32Array = G.next[idx]
	var start := idx
	var rel := (_pos[idx] - p)
	if rel.dot(fwd) < 0.0 and not nx.is_empty():
		start = nx[0]
	if jn_granted or jn_jid >= 0:
		junction.release(self)
	P = PackedInt32Array([start])
	seg = 0
	lat_off = 0.0
	_extend_path()
	return P.size() >= 3


func _extend_path() -> void:
	var guard := 0
	while P.size() - seg < 28 and guard < 40:
		var last: int = P[P.size() - 1]
		var nx: PackedInt32Array = _next[last]
		if nx.is_empty():
			break
		var nxt: int
		if nx.size() == 1:
			nxt = nx[0]
		else:
			var tp := g_player_pos - _pos[last]
			tp.y = 0.0
			var bias := 0.0
			var dir_to := Vector3.ZERO
			if tp.length_squared() > 110.0 * 110.0:
				bias = 0.9
				dir_to = tp.normalized()
			nxt = TrafficNet.pick_next(last, rng, dir_to, bias)
		if nxt < 0:
			break
		P.append(nxt)
		guard += 1


# =====================================================================================================================
# Main update
# =====================================================================================================================
func update(dt: float, now_: float) -> void:
	now = now_
	if mode == MODE_DEAD:
		return
	if v == null or not is_instance_valid(v) or not v.is_inside_tree():
		_die("freed")
		return
	if v.is_destroyed:
		_die("destroyed")
		return
	if not v.is_ai_controlled:
		_die("taken")
		return
	var occ: Node = v.driver
	if (occ != null and occ != npc) or (npc != null and occ != npc):
		_die("driver_changed")
		return
	if dt <= 0.0:
		return
	dt = minf(dt, 0.25)

	var xf: Transform3D = v.global_transform
	var p: Vector3 = xf.origin
	var bz: Vector3 = xf.basis.z
	var fwd := Vector3(-bz.x, 0.0, -bz.z)
	var fl := fwd.length()
	if fl < 0.01:
		return
	fwd /= fl
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var vel: Vector3 = v.linear_velocity
	var spd: float = vel.x * fwd.x + vel.z * fwd.z
	_cur_spd = spd
	dist_driven += absf(spd) * dt
	speed_sum += absf(spd)
	speed_n += 1
	var upright: float = xf.basis.y.y

	# ---- timers ---------------------------------------------------------------------------------------------------------------
	if honk_t > 0.0:
		honk_t -= dt
		if honk_t <= 0.0:
			v.input_horn = false
	honk_cd = maxf(honk_cd - dt, 0.0)
	lc_cool = maxf(lc_cool - dt, 0.0)
	if flee_t > 0.0:
		flee_t -= dt
	_tick_lights(dt)

	# ---- special modes ---------------------------------------------------------------------------------------------------------------
	if mode == MODE_CRASHED:
		_update_crashed(dt, spd, upright)
		return
	if mode == MODE_REVERSE:
		_update_reverse(dt, spd, p, fwd)
		return

	# ---- 1. progress along the path -------------------------------------------------------------------------------------------------
	_extend_path()
	var Pl := P
	var n := Pl.size()
	if n < 3:
		if not replan(p, fwd):
			want_recycle = true
		return
	var guard := 0
	while seg < n - 2 and guard < 8:
		var a0: Vector3 = _pos[Pl[seg]]
		var b0: Vector3 = _pos[Pl[seg + 1]]
		var ex := b0.x - a0.x
		var ez := b0.z - a0.z
		var l2 := ex * ex + ez * ez
		if l2 < 0.0001:
			seg += 1
			guard += 1
			continue
		if ((p.x - a0.x) * ex + (p.z - a0.z) * ez) / l2 >= 1.0:
			seg += 1
			guard += 1
		else:
			break
	if seg > 8:
		P = P.slice(seg - 2)
		seg = 2
		Pl = P
		n = Pl.size()
		_extend_path()
		Pl = P
		n = Pl.size()
	if seg >= n - 2:
		if not replan(p, fwd):
			want_recycle = true
		return

	# ---- 2. geometry ahead -------------------------------------------------------------------------------------------------------------
	var horizon := clampf(absf(spd) * 4.6 + 32.0, 42.0, 100.0)
	var m := _build_ahead(p, horizon)
	m_ahead = m
	var seg_right_x := -sdz[0]
	var seg_right_z := sdx[0]
	lat_pos = (p.x - sx[0]) * seg_right_x + (p.z - sz[0]) * seg_right_z
	var xte := absf(lat_pos - lat_off)
	if absf(spd) > 2.0:
		xte_max = maxf(xte_max, xte)
		xte_sum += xte
		xte_n += 1
	if xte > 7.0 and absf(spd) < 14.0 and not jn_granted:
		# thrown off the road: replan
		replan(p, fwd)
		return

	# look-ahead scan: speed limit changes, bends, stop line, junction mouth
	var lim_here: float = minf(_lim[Pl[seg]], _lim[Pl[seg + 1]])
	var eff := spd_factor * g_speed_scale
	var v_cap := 999.0
	var stop_k := -1
	var entry_k := -1
	var prev_dir: Vector3 = _dir[Pl[seg + 1]]
	for k in range(1, m + 1):
		var idx: int = Pl[seg + k]
		var d: float = ad[k]
		var lim: float = _lim[idx]
		if lim < lim_here - 0.4:
			var le := lim * eff
			v_cap = minf(v_cap, sqrt(le * le + 2.0 * B_STOP * maxf(d - 1.5, 0.0)))
		if k >= 2:
			var dd: Vector3 = _dir[idx]
			var dotp := dd.x * prev_dir.x + dd.z * prev_dir.z
			if dotp < 0.997:
				var seg_l := maxf(ad[k] - ad[k - 1], 1.0)
				var kappa := sqrt(maxf(2.0 * (1.0 - dotp), 0.0)) / seg_l
				var vc := sqrt(A_LAT / maxf(kappa, 0.002)) * minf(eff, 1.0)
				v_cap = minf(v_cap, sqrt(vc * vc + 2.0 * B_STOP * maxf(ad[k - 1] - 1.0, 0.0)))
			prev_dir = dd
		if stop_k < 0 and _sigid[idx] >= 0 and d > -1.0:
			stop_k = k
		if entry_k < 0 and _kind[idx] == LaneGraph.KIND_CONNECTOR and k >= 1 and _kind[Pl[seg + k - 1]] != LaneGraph.KIND_CONNECTOR:
			entry_k = k - 1
	var in_box: bool = _kind[Pl[seg]] == LaneGraph.KIND_CONNECTOR or _kind[Pl[seg + 1]] == LaneGraph.KIND_CONNECTOR
	if in_box:
		box_t += dt
		if absf(spd) < 0.5:
			box_stall_t += dt
		else:
			box_stall_t = 0.0
	else:
		box_t = 0.0
		box_stall_t = 0.0

	# ---- 3. obstacles ---------------------------------------------------------------------------------------------------------------------
	_scan(p, fwd, spd, m)
	# static clearance of the lane ahead (poles standing in / at the edge of the lane, see LaneClearance)
	var dodge_target := 0.0
	var blocked_s := 999.0
	for k in range(0, m + 1):
		var dk: float = ad[k]
		if dk > 40.0:
			break
		if dk < -3.0:
			continue
		var pidx: int = Pl[seg + k]
		var cs: int = LaneClearance.state[pidx] if pidx < LaneClearance.state.size() else 0
		if cs == LaneClearance.UNKNOWN:
			cs = LaneClearance.get_state(pidx)
		if cs == LaneClearance.DODGE and dk < 16.0:
			var dv: float = LaneClearance.dodge[pidx]
			if absf(dv) > absf(dodge_target):
				dodge_target = dv
		elif cs == LaneClearance.BLOCKED:
			blocked_s = minf(blocked_s, dk - 2.0)
	if blocked_s < 900.0 and blocked_s < lead_s:
		lead_s = blocked_s
		lead_v = 0.0
		lead_kind = 3
		lead_node = null
	if tier <= 1:
		_probe_n += 1
		if (_probe_n & (3 if tier == 0 else 1)) == 0 and absf(spd) > 1.0:      # near cars: every 4th update, mid-range: every 2nd (= every 6th frame)
			_probe_solid(p, fwd, right, spd, m)
	if now - solid_t < 0.7 and solid_s < lead_s:
		lead_s = solid_s
		lead_v = 0.0
		lead_kind = 3
		lead_ai = null

	# ---- 4. sirens: yield ---------------------------------------------------------------------------------------------------------------------
	var yielding := false
	if not g_siren_idx.is_empty() and flee_t <= 0.0:
		yielding = _siren_behind(p, fwd)
	if yielding:
		yield_t = 3.0
	elif yield_t > 0.0:
		yield_t -= dt
	# pull over unless the junction mouth / stop line is close (then the car simply clears the junction first)
	var want_yield: bool = yield_t > 0.0 and not in_box and not jn_granted and (entry_k < 0 or ad[entry_k] > 26.0) and (stop_k < 0 or ad[stop_k] > 26.0)

	# ---- 5. stop line + junction gate --------------------------------------------------------------------------------------------------
	var stop_gap := 999.0
	var reason := R_FREE
	var emergency := false
	var running_light: bool = flee_t > 0.0
	if stop_k >= 0 and not running_light:
		var si: int = Pl[seg + stop_k]
		var sid: int = _sigid[si]
		var st := WorldLayout.signal_state(sid, _sigph[si], now)
		var tc: float = ad[stop_k] + 2.2 - STOP_MARGIN - hl
		var go := true
		if tc < -2.0:
			go = true
		elif st == 0:
			go = true
			_dec_sig = sid
			_dec_go = true
			_dec_st = 0
		elif st == 2:
			# red: only a car that committed to the yellow (and is almost at the line) keeps going
			go = _dec_sig == sid and _dec_go and _dec_st == 1 and tc < 5.0 and spd > 3.0
			if not go:
				_dec_sig = sid
				_dec_go = false
				_dec_st = 2
		else:
			# yellow: decide ONCE per signal and phase whether the car can stop comfortably (<= 4.4 m/s^2)
			if _dec_sig == sid and _dec_st == 1:
				go = _dec_go
			else:
				var can_stop: bool = spd < 1.5 or (tc > 1.5 and spd * spd / (2.0 * tc) < 4.4)
				go = not can_stop
				_dec_sig = sid
				_dec_go = go
				_dec_st = 1
		if not go and tc < 1.2 and spd * spd / (2.0 * maxf(tc, 0.2)) > brake_cap * 0.85:
			go = true                       # cannot stop any more: clear the junction rather than slam into it
			red_runs += 1 if st == 2 else 0
		if not go:
			stop_gap = maxf(tc, 0.0)
			reason = R_SIGNAL
	# the junction box
	if in_box:
		if not jn_granted and not running_light:
			# entered without a reservation (ran a yellow, was spawned/replanned inside): register silently if it is free
			var cid0: int = TrafficNet.chain_of[Pl[seg + 1]] if TrafficNet.chain_of[Pl[seg + 1]] >= 0 else TrafficNet.chain_of[Pl[seg]]
			if cid0 >= 0 and TrafficNet.chains.has(cid0):
				if cid0 != jn_chain:
					if jn_jid >= 0:
						junction.release(self)
					_bind_chain(cid0, 0.0)
				junction.request(self, jn_jid, cid0)
		_check_release(p)
	elif entry_k >= 0:
		var cid: int = TrafficNet.chain_of[Pl[seg + entry_k + 1]]
		if cid >= 0 and TrafficNet.chains.has(cid):
			var d_entry: float = ad[entry_k]
			if cid != jn_chain:
				if jn_jid >= 0:
					junction.release(self)
				_bind_chain(cid, d_entry)
			jn_d_entry = d_entry
			if not running_light and reason == R_FREE:
				var req_dist := maxf(13.0, spd * spd / (2.0 * 2.6) + hl + 5.0)
				if d_entry < req_dist or jn_granted:
					jn_eta = d_entry / maxf(spd, 2.5)
					var room_needed := d_entry + jn_len + hl * 2.0 + 1.0
					var exit_blocked: bool = lead_s < 900.0 and lead_v < 3.0 and lead_s < room_needed
					var ok := false
					if not exit_blocked or jn_granted:
						ok = junction.request(self, jn_jid, cid)
					else:
						junction.cancel(self)
					if not ok:
						stop_gap = minf(stop_gap, maxf(d_entry - hl - 0.7, 0.0))
						reason = R_YIELD
				elif d_entry < req_dist + 18.0 and not _is_priority_road(cid):
					# minor unsignalised road: approach the mouth slowly so we can stop
					v_cap = minf(v_cap, 7.5 + maxf(d_entry - 14.0, 0.0) * 0.6)
	elif jn_jid >= 0 and not in_box:
		_check_release(p)

	# ---- 6. target speed ---------------------------------------------------------------------------------------------------------------------
	var v_free := minf(lim_here * eff, MAX_CRUISE)
	if flee_t > 0.0:
		v_free = minf(lim_here * 1.5, 25.0)
	var vt := minf(v_free, v_cap)
	if breakdown_t > 0.0:
		# pulling over: roll to a stop at the right edge and wait with hazards on
		vt = minf(vt, maxf(minf(absf(spd), 5.0) - 1.6, 0.0))
	if caution:
		vt = minf(vt, 6.0)
	if side_shift != 0.0 and lead_s < 14.0:
		vt = minf(vt, 6.5)
	var spd_p := maxf(spd, 0.0)
	if lead_s < 900.0:
		var gap := lead_s - hl
		var t_h := headway * g_headway_scale * (0.7 if flee_t > 0.0 else 1.0)
		var s0 := 3.4 if lead_kind == 2 else 1.7           # people: keep a respectful distance, no creeping up to them
		var s_des := s0 + t_h * spd_p
		var vf := maxf(lead_v + (gap - s_des) * 0.5, 0.0)
		var bsafe := 0.55 * brake_cap
		var vs := sqrt(lead_v * lead_v + 2.0 * bsafe * maxf(gap - s0 * 0.6, 0.0))
		vt = minf(vt, minf(vf, vs))
		var d_need := (spd_p * spd_p - lead_v * lead_v) / (2.0 * brake_cap * 0.7)
		if gap < d_need + 1.0 and spd_p > lead_v + 1.5:
			emergency = true
		if lead_v < 1.0 and reason == R_FREE:
			reason = R_PED if lead_kind == 2 else (R_LEADER if lead_kind == 1 else R_BLOCK)
	if stop_gap < 900.0:
		vt = minf(vt, sqrt(2.0 * B_STOP * maxf(stop_gap, 0.0)))
	if want_yield:
		vt = minf(vt, maxf(spd_p - 2.5, 0.0) if lead_s < 900.0 else maxf(spd_p - 3.0, 0.0))
		if spd_p < 2.0:
			vt = 0.0
		reason = R_YIELD if reason == R_FREE else reason
	stop_reason = reason

	# ---- 7. lateral offset + steering ------------------------------------------------------------------------------------------------------
	var lat_target := side_shift + dodge_target
	if want_yield:
		lat_target = clampf(lat_target + 1.15, -1.0, 1.35)
	if breakdown_t > 0.0:
		lat_target = 1.1 if lead_s > 30.0 else 0.0        # pull over to the right edge unless a stopped car is right there
	var rate := LANE_CHANGE_RATE * (1.0 if absf(lat_off) < 2.5 else 1.4)
	lat_off = move_toward(lat_off, lat_target, rate * dt)
	var steer_raw := _steer_to_path(p, fwd, right, spd, m)

	# ---- 8. lane change / overtake decisions (cheap, only sometimes) -------------------------------------------------------------------------
	if tier <= 1 and lc_cool <= 0.0 and mode == MODE_DRIVE:
		_consider_lane_change(p, fwd, spd, m, entry_k, in_box)

	# ---- 9. pedals ---------------------------------------------------------------------------------------------------------------------------------
	var a_des := 0.0
	var err := vt - spd
	if vt < 0.3 and spd < BRAKE_MIN_SPEED:
		a_des = 0.0
	else:
		a_des = clampf(err * 1.0, -brake_cap, a_acc_max)
	# kinematic feed-forward: the constant deceleration that stops exactly at the nearest stop point / behind the leader
	# (the P term alone lags behind the sqrt stopping profile and overshoots)
	var ff := 0.0
	if spd > 0.8:
		if stop_gap < 900.0:
			ff = spd * spd / (2.0 * maxf(stop_gap, 0.25))
		if lead_s < 900.0 and spd_p > lead_v + 0.5:
			var gap_l := lead_s - hl - 1.2
			ff = maxf(ff, (spd_p * spd_p - lead_v * lead_v) / (2.0 * maxf(gap_l, 0.25)))
	if ff > 1.2 and ff > -a_des:
		a_des = -minf(ff * 1.08, brake_cap)
	dbg_vt = vt
	dbg_stop = stop_gap
	dbg_a = a_des
	var thr_t := 0.0
	var brk_t := 0.0
	# measured longitudinal acceleration (smoothed) closes the loop on the throttle feed-forward
	a_meas = lerpf(a_meas, clampf((spd - _prev_spd) / maxf(dt, 0.001), -12.0, 12.0), minf(1.0, 6.0 * dt))
	_prev_spd = spd
	if a_des > 0.05:
		var a_avail := clampf(accel_avail_k / maxf(spd_p, 4.0), 1.5, 8.5)
		thr_trim = clampf(thr_trim + (a_des - a_meas) * 0.14 * dt, 0.0, 0.7)
		thr_t = clampf(a_des / a_avail + thr_trim, 0.0, 0.95)
	else:
		thr_trim = move_toward(thr_trim, 0.0, 0.8 * dt)
		if a_des < -0.35:
			brk_t = clampf(-a_des / brake_cap, 0.0, 1.0)
			if spd < BRAKE_MIN_SPEED:
				brk_t = 0.0
	if emergency:
		brk_t = 1.0 if spd > 2.0 else 0.0
		thr_t = 0.0
		emergency_count += 1
		if honk_cd <= 0.0 and aggression > 0.35 and lead_kind != 3:
			_honk(0.45, 4.0)
	thr = move_toward(thr, thr_t, (1.5 if thr_t > thr else 6.0) * dt)
	brk = move_toward(brk, brk_t, ((16.0 if emergency else 3.4) if brk_t > brk else 8.0) * dt)
	if brk_t > 0.0 and brk > 0.0:
		thr = 0.0
	if thr_t > 0.0 and thr > 0.0 and brk_t <= 0.0:
		brk = 0.0
	if spd < BRAKE_MIN_SPEED and brk_t <= 0.0:
		brk = 0.0
	v.input_throttle = thr
	v.input_brake = brk
	var sm := 1.0 - exp(-13.0 * dt)
	steer_cmd = lerpf(steer_cmd, steer_raw, sm)
	v.input_steer = steer_cmd
	v.input_handbrake = false

	# ---- 10. bookkeeping: waiting, stuck, honking -----------------------------------------------------------------------------------------
	_tick_waiting(dt, spd, reason, upright)
	if breakdown_t > 0.0:
		breakdown_t -= dt
		if breakdown_t <= 0.0:
			set_hazard(false)


# =====================================================================================================================
# Geometry helpers
# =====================================================================================================================
## Fills ad[] (distance from the car's projection to path point seg+k) and the segment arrays; returns the last k.
func _build_ahead(p: Vector3, horizon: float) -> int:
	var Pl := P
	var n := Pl.size()
	var a: Vector3 = _pos[Pl[seg]]
	var b: Vector3 = _pos[Pl[seg + 1]]
	var ex := b.x - a.x
	var ez := b.z - a.z
	var len0 := maxf(sqrt(ex * ex + ez * ez), 0.01)
	var t_m := ((p.x - a.x) * ex + (p.z - a.z) * ez) / len0
	ad[0] = -t_m
	ad[1] = len0 - t_m
	sx[0] = a.x
	sz[0] = a.z
	sdx[0] = ex / len0
	sdz[0] = ez / len0
	sl[0] = len0
	var m := 1
	var last_end := b
	while m < NP - 2 and seg + m + 1 < n and ad[m] < horizon:
		var c: Vector3 = _pos[Pl[seg + m + 1]]
		var fx := c.x - last_end.x
		var fz := c.z - last_end.z
		var fl := maxf(sqrt(fx * fx + fz * fz), 0.01)
		sx[m] = last_end.x
		sz[m] = last_end.z
		sdx[m] = fx / fl
		sdz[m] = fz / fl
		sl[m] = fl
		ad[m + 1] = ad[m] + fl
		last_end = c
		m += 1
	return m


func _steer_to_path(p: Vector3, fwd: Vector3, right: Vector3, spd: float, m: int) -> float:
	var sa := absf(spd)
	var ld := clampf(2.3 + 0.40 * sa, 3.3, 16.0)
	var k := 1
	while k < m and ad[k] < ld:
		k += 1
	# the point at path distance `ld` from the car's projection lies on segment k-1 (which starts at distance ad[k-1])
	var off := clampf(ld - ad[k - 1], 0.0, sl[k - 1])
	var tx := sx[k - 1] + sdx[k - 1] * off
	var tz := sz[k - 1] + sdz[k - 1] * off
	# lateral offset of the intended track (to the right of the segment direction)
	tx += -sdz[k - 1] * lat_off
	tz += sdx[k - 1] * lat_off
	var dx := tx - p.x
	var dz := tz - p.z
	var lx := dx * right.x + dz * right.z
	var lz := dx * fwd.x + dz * fwd.z
	var ldist := maxf(sqrt(lx * lx + lz * lz), 1.0)
	var alpha := atan2(lx, maxf(lz, 0.4))
	var delta := atan2(2.0 * wheelbase * sin(alpha), ldist)
	var lim := steer_gain * wheelbase * lat_lim / (spd * spd + 4.0)
	var max_ang := clampf(lim, steer_min, steer_lock)
	return clampf(delta / max_ang, -1.0, 1.0)


# =====================================================================================================================
# Obstacle scan
# =====================================================================================================================
func _scan(p: Vector3, fwd: Vector3, spd: float, m: int) -> void:
	lead_s = 999.0
	lead_v = 0.0
	lead_kind = 0
	lead_node = null
	lead_ai = null
	side_shift = 0.0
	caution = false
	var g := grid
	var span: float = ad[m] + 6.0
	g.query(p, minf(span, 80.0), _scan_out)
	var best_shift_need := 0.0
	var ped_hazard := g_ped_hazard
	for ei in _scan_out:
		var nd = g.node[ei]        # may have been freed since the grid was rebuilt
		if nd == v or not is_instance_valid(nd):
			continue
		var q: Vector3 = g.pos[ei]
		var rx := q.x - p.x
		var rz := q.z - p.z
		var d2 := rx * rx + rz * rz
		var ok_kind: int = g.kind[ei]
		var ohl: float = g.hl[ei]
		var ohw: float = g.hw[ei]
		var reach := span + ohl + 2.0
		if d2 > reach * reach:
			continue
		if ok_kind == TrafficGrid.KIND_PED and not ped_hazard:
			continue
		var along_f := rx * fwd.x + rz * fwd.z
		if along_f < -(ohl + hl + 2.0):
			continue
		var e := sqrt(d2)
		var lo := e - ohl - 9.0
		var hi := e * 1.8 + 12.0
		var best_d2 := 1.0e9
		var best_lat := 0.0
		var best_along := 0.0
		var best_k := -1
		for k in m:
			if ad[k + 1] < lo:
				continue
			if ad[k] > hi:
				break
			var wx := q.x - sx[k]
			var wz := q.z - sz[k]
			var tt := wx * sdx[k] + wz * sdz[k]
			var tcl := clampf(tt, 0.0, sl[k])
			var cx := wx - sdx[k] * tcl
			var cz := wz - sdz[k] * tcl
			var dd2 := cx * cx + cz * cz
			if dd2 < best_d2:
				best_d2 = dd2
				best_lat = -wx * sdz[k] + wz * sdx[k]
				best_along = ad[k] + tcl
				best_k = k
		if best_k < 0 or best_d2 > 40.0:
			continue
		var odx: float = sdx[best_k]
		var odz: float = sdz[best_k]
		var ov: Vector3 = g.vel[ei]
		var vl := ov.x * odx + ov.z * odz
		var vlat := -ov.x * odz + ov.z * odx
		var o_speed := sqrt(ov.x * ov.x + ov.z * ov.z)
		var rel := best_lat - lat_off
		if ok_kind == TrafficGrid.KIND_PED:
			var arel := absf(rel)
			var block := arel < hw + 1.05
			var rel2 := rel + vlat * 1.25
			if not block and absf(rel2) < hw + 0.8 and absf(vlat) > 0.4 and best_along > 0.0:
				block = true
			if block:
				var gap_p := best_along - 0.4 - hl
				if gap_p < lead_s - hl or lead_s > 900.0:
					lead_s = best_along - 0.4
					lead_v = 0.0
					lead_kind = 2
					lead_node = nd
					lead_ai = null
			elif arel < hw + 2.6 and best_along < 16.0 and best_along > -2.0:
				caution = true
			continue
		# ---- vehicles --------------------------------------------------------------------------------------------------------------
		var of: Vector3 = g.fwd[ei]
		var cosf := absf(of.x * odx + of.z * odz)
		var sinf := absf(-of.x * odz + of.z * odx)
		var eff_hw := cosf * ohw + sinf * ohl
		var eff_hl := cosf * ohl + sinf * ohw
		var clear := hw + eff_hw
		var arel2 := absf(rel)
		var blocking := arel2 < clear + 0.4
		var is_static := o_speed < 0.9
		if blocking and is_static and best_along > -ohl:
			# parked / stopped beside the lane: squeeze past by shifting the track away if the shift is small
			var need := clear + 0.4 - arel2
			var raw_lat: float = absf(best_lat)
			if need <= 0.85 and raw_lat > 0.95:
				if need > best_shift_need:
					best_shift_need = need
					side_shift = -signf(rel) * need
				blocking = false
				if best_along - eff_hl - hl < 12.0 and best_along > 0.0:
					caution = true
		if not blocking and o_speed > 2.5 and cosf < 0.8:
			# crossing traffic: where will it be in ~1 s?
			var rel2 := rel + vlat * 1.0
			var along2 := best_along + vl * 1.0
			if absf(rel2) < clear + 0.45 and along2 > -eff_hl:
				var gap2 := along2 - eff_hl - hl
				if gap2 < lead_s - hl or lead_s > 900.0:
					lead_s = along2 - eff_hl
					lead_v = 0.0
					lead_kind = 1
					lead_node = nd
					lead_ai = null
			continue
		if not blocking:
			continue
		if best_along < -(eff_hl + hl * 0.3):
			continue                  # behind us
		var s_rear := best_along - eff_hl
		if s_rear < lead_s:
			lead_s = s_rear
			lead_v = maxf(vl, 0.0)
			lead_kind = 1
			lead_node = nd
			lead_ai = null


## Static obstacles (walls, poles, big props) that the lane scan cannot see: two parallel rays along the intended path.
func _probe_solid(p: Vector3, fwd: Vector3, right: Vector3, spd: float, m: int) -> void:
	if not v.is_inside_tree():
		return
	var reach := clampf(absf(spd) * 1.4 + 5.0, 7.0, 26.0)
	# aim along the path: look-ahead point of ~reach metres
	var k := 1
	while k < m and ad[k] < reach * 0.8:
		k += 1
	# the intended track includes the lateral offset (dodging a pole / passing a parked car): aim the rays along THAT track
	var tx := sx[k - 1] + sdx[k - 1] * sl[k - 1] * 0.5 - sdz[k - 1] * lat_off
	var tz := sz[k - 1] + sdz[k - 1] * sl[k - 1] * 0.5 + sdx[k - 1] * lat_off
	var dv := Vector3(tx - p.x, 0.0, tz - p.z)
	if dv.length_squared() < 1.0:
		dv = fwd
	dv = dv.normalized()
	if dv.dot(fwd) < 0.6:
		dv = fwd
	var space := v.get_world_3d().direct_space_state
	if _ray_q == null:
		_ray_q = PhysicsRayQueryParameters3D.new()
		_ray_q.collision_mask = GC.L_WORLD | GC.L_PROP
	var rid := v.get_rid()
	var best := 999.0
	var dr := Vector3(-dv.z, 0.0, dv.x)
	for sgn: float in [-1.0, 0.0, 1.0]:
		var from := p + Vector3(0.0, 0.5, 0.0) + dv * (hl - 0.1) + dr * (sgn * (hw - 0.12))
		_ray_q.from = from
		_ray_q.to = from + dv * reach
		_ray_q.exclude = [rid]
		var hit := space.intersect_ray(_ray_q)
		if hit.is_empty():
			continue
		var nrm: Vector3 = hit.normal
		if nrm.y > 0.5:
			continue
		var col = hit.collider
		if col is RigidBody3D and not (col is VehicleBase):
			if (col as RigidBody3D).mass < 250.0:
				continue
		var dist: float = from.distance_to(hit.position)
		best = minf(best, dist)
	if best < 900.0:
		solid_s = best + hl - 0.1
		solid_t = now
	else:
		solid_s = 999.0


func _siren_behind(p: Vector3, fwd: Vector3) -> bool:
	for si in g_siren_idx:
		if si >= grid.count:
			continue
		var nd = grid.node[si]
		if nd == v or not is_instance_valid(nd):
			continue
		var q: Vector3 = grid.pos[si]
		var rx := q.x - p.x
		var rz := q.z - p.z
		var d2 := rx * rx + rz * rz
		if d2 > 70.0 * 70.0:
			continue
		var along := rx * fwd.x + rz * fwd.z
		if along > 6.0:
			continue                 # ahead of us (oncoming): it will use the other lane
		var of: Vector3 = grid.fwd[si]
		if of.x * fwd.x + of.z * fwd.z < 0.35:
			continue                 # not travelling the same way
		if absf(-rx * fwd.z + rz * fwd.x) > 14.0:
			continue
		return true
	return false


# =====================================================================================================================
# Junction helpers
# =====================================================================================================================
func _bind_chain(cid: int, d_entry: float) -> void:
	var ch: Dictionary = TrafficNet.chains[cid]
	jn_jid = ch["jid"]
	jn_chain = cid
	jn_granted = false
	jn_exit_pt = ch["exit"]
	jn_len = float(ch["length"])
	jn_d_entry = d_entry
	jn_wait_start = 0.0


## True when this approach has the highest road rank of its junction, or the junction is signalised (no slow-down needed).
func _is_priority_road(cid: int) -> bool:
	var ch: Dictionary = TrafficNet.chains[cid]
	var jn: Dictionary = TrafficNet.junctions[ch["jid"]]
	if int(jn["signal"]) >= 0:
		return true
	return float(ch["rank"]) >= float(jn["max_rank"]) - 1.5


func _check_release(p: Vector3) -> void:
	if not jn_granted:
		return
	var ei := P.find(jn_exit_pt)
	if ei < 0 or ei < seg:
		junction.release(self)
		return
	if ei == seg:
		var a: Vector3 = _pos[P[seg]]
		var beyond := (p.x - a.x) * sdx[0] + (p.z - a.z) * sdz[0]
		if beyond > hl + 0.4:
			junction.release(self)


# =====================================================================================================================
# Lane change / overtaking
# =====================================================================================================================
func _consider_lane_change(p: Vector3, fwd: Vector3, spd: float, m: int, entry_k: int, in_box: bool) -> void:
	if in_box or entry_k >= 0 or jn_granted or flee_t > 0.0 or yield_t > 0.0:
		return
	if absf(lat_off) > 0.6:
		return
	var G: LaneGraph = WorldLayout.lanes
	var cur: int = P[seg + 1]
	var lf: int = G.left_of[cur]
	var rt: int = G.right_of[cur]
	if lf < 0 and rt < 0:
		return
	if TrafficNet.near_junction[cur] != 0:
		return
	# blocked by a slow / stationary vehicle ahead?
	var blocked: bool = lead_s < 38.0 and lead_kind == 1 and lead_v < maxf(2.0, 0.35 * spd) and spd < 9.0
	if blocked and (idle_t > 1.2 or (lead_s - hl < 9.0 and lead_v < 0.5)):
		var order: Array = [lf, rt] if aggression > 0.5 else [rt, lf]
		for cand in order:
			if cand < 0:
				continue
			if _lane_free(cand, p, fwd):
				_do_lane_change(cand, cur)
				return


## Is the neighbouring lane free around the car (no vehicle within 14 m behind .. 32 m ahead along it)?
func _lane_free(cand: int, p: Vector3, fwd: Vector3) -> bool:
	var cp: Vector3 = _pos[cand]
	var cd: Vector3 = _dir[cand]
	grid.query(cp, 36.0, _scan_out)
	for ei in _scan_out:
		var nd = grid.node[ei]
		if nd == v or not is_instance_valid(nd):
			continue
		var q: Vector3 = grid.pos[ei]
		var rx := q.x - cp.x
		var rz := q.z - cp.z
		var along := rx * cd.x + rz * cd.z
		var lat := absf(-rx * cd.z + rz * cd.x)
		if lat > 2.4:
			continue
		var o_speed: float = Vector2(grid.vel[ei].x, grid.vel[ei].z).length()
		var behind_limit := -(grid.hl[ei] + 9.0 + o_speed * 0.8)
		if along > behind_limit and along < 30.0 + grid.hl[ei]:
			return false
	return true


func _do_lane_change(cand: int, cur: int) -> void:
	var G: LaneGraph = WorldLayout.lanes
	# new path: the neighbouring lane's point beside our next point, then follow that lane
	var np := PackedInt32Array([cand])
	var guard := 0
	P = np
	seg = 0
	var lane_w: float = _pos[cand].distance_to(_pos[cur])
	var side := 1.0 if G.right_of[cur] == cand else -1.0
	# the car is currently |lane_w| to the opposite side of the new lane
	lat_off = -side * lane_w
	_extend_path()
	lc_cool = 6.0 + rng.randf() * 4.0


# =====================================================================================================================
# Special modes
# =====================================================================================================================
func _update_crashed(dt: float, spd: float, upright: float) -> void:
	crash_t -= dt
	v.input_throttle = 0.0
	v.input_steer = 0.0
	if spd > 1.8:
		v.input_brake = 1.0
	elif spd < -0.8:
		v.input_brake = 0.0
		v.input_throttle = 0.4
	else:
		v.input_brake = 0.0
	v.input_handbrake = false
	if crash_t <= 0.0:
		var wreck: bool = v.get_health_ratio() < 0.18 or upright < 0.35
		if wreck:
			# undrivable: stays as a wreck, TrafficManager clears it later out of sight
			crash_t = 5.0
			want_recycle = false
			return
		mode = MODE_DRIVE
		set_hazard(false)
		v.input_horn = false
		var xf: Transform3D = v.global_transform
		var fwd := Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized()
		replan(xf.origin, fwd)


func _update_reverse(dt: float, spd: float, p: Vector3, fwd: Vector3) -> void:
	rev_t -= dt
	v.input_steer = rev_steer
	v.input_handbrake = false
	var behind := _blocked_behind(p, fwd)
	if behind and rev_t > 0.4:
		rev_t = 0.4                   # something is right behind us: stop backing up
	if rev_t > 0.4 and spd > -REV_SPEED:
		v.input_throttle = 0.0
		v.input_brake = 0.55          # brake pedal = reverse when (nearly) stopped (VehicleBase contract)
	elif spd < -REV_SPEED + 0.3:
		v.input_brake = 0.0
		v.input_throttle = clampf(0.2 + (-spd - REV_SPEED) * 0.25, 0.1, 0.8)    # throttle slows a backwards roll
	elif rev_t > 0.4:
		v.input_throttle = 0.0
		v.input_brake = 0.0
	else:
		v.input_brake = 0.0
		v.input_throttle = 0.6 if spd < -0.5 else 0.0
	if rev_t <= 0.0:
		mode = MODE_DRIVE
		v.input_throttle = 0.0
		v.input_brake = 0.0
		thr = 0.0
		brk = 0.0
		replan(p, fwd)
		idle_t = 0.0


## Is a vehicle / pedestrian within a few metres behind the car (the reverse manoeuvre must not back into it)?
func _blocked_behind(p: Vector3, fwd: Vector3) -> bool:
	var back := p - fwd * (hl + 3.0)
	grid.query(back, 8.0, _scan_out)
	for ei in _scan_out:
		var nd = grid.node[ei]
		if nd == v or not is_instance_valid(nd):
			continue
		var q: Vector3 = grid.pos[ei]
		var rx := q.x - p.x
		var rz := q.z - p.z
		var along := rx * fwd.x + rz * fwd.z
		var lat := absf(-rx * fwd.z + rz * fwd.x)
		if along < 0.5 and along > -(hl + float(grid.hl[ei]) + 4.5) and lat < hw + float(grid.hw[ei]) + 1.1:
			return true
	return false


## The scan result may be a pedestrian / car freed since the scan (despawn, death clean-up): never test a stale
## reference with `is` ("Left operand of 'is' is a previously freed instance").
func _lead_veh() -> VehicleBase:
	if lead_node == null:
		return null
	if not is_instance_valid(lead_node):
		lead_node = null
		return null
	return lead_node as VehicleBase


func _tick_waiting(dt: float, spd: float, reason: int, upright: float) -> void:
	if breakdown_t > 0.0:
		idle_t = 0.0
		return
	if absf(spd) < 0.6:
		if reason == R_SIGNAL or reason == R_YIELD:
			wait_signal_t += dt
			idle_t += dt * (0.12 if reason == R_SIGNAL else 0.55)
		else:
			idle_t += dt
			var lv0 := _lead_veh()
			if reason == R_LEADER and lv0 != null and lv0.is_ai_controlled:
				idle_t -= dt * 0.35
		# honk at a blocker
		if honk_cd <= 0.0 and (reason == R_LEADER or reason == R_BLOCK) and idle_t > patience + 1.0 and lead_s < 9.0:
			var lv1 := _lead_veh()
			var l_is_ai: bool = lv1 != null and lv1.is_ai_controlled and lv1.get_speed() > 0.2
			if not l_is_ai:
				_honk(0.5, 5.0 + rng.randf() * 4.0)
				honks += 1
	else:
		idle_t = maxf(idle_t - dt * 2.0, 0.0)
		wait_signal_t = 0.0
	if mode == MODE_DRIVE:
		if idle_t > 7.0 and reason != R_SIGNAL and reason != R_YIELD and reason != R_PED and stuck_count < 2 and lead_s > 3.0:
			# backing up only makes sense when something static / foreign blocks us, never inside a queue of moving traffic
			var lv2 := _lead_veh()
			var queue: bool = lv2 != null and lv2.is_ai_controlled
			if not queue and not _blocked_behind(v.global_position, Vector3(-v.global_transform.basis.z.x, 0.0, -v.global_transform.basis.z.z).normalized()):
				_start_reverse()
		var limit := 40.0 if reason == R_LEADER else 26.0
		if idle_t > limit:
			want_recycle = true
	if upright < 0.2 and absf(spd) < 2.0:
		idle_t += dt


func _start_reverse() -> void:
	stuck_count += 1
	mode = MODE_REVERSE
	rev_t = 1.7 + rng.randf() * 0.8
	rev_steer = rng.randf_range(-1.0, 1.0)
	thr = 0.0
	brk = 0.0
	if jn_jid >= 0:
		junction.release(self)


# =====================================================================================================================
# Reactions
# =====================================================================================================================
func _honk(duration: float, cooldown: float) -> void:
	if v == null or honk_cd > 0.0:
		return
	v.input_horn = true
	honk_t = duration
	honk_cd = cooldown


func honk_now(duration: float = 0.5) -> void:
	honk_cd = 0.0
	_honk(duration, 3.0)


func set_hazard(on: bool) -> void:
	hazard_on = on
	if not on:
		_apply_hazard_state(false)


func _apply_hazard_state(lit: bool) -> void:
	if v == null or v.lights == null:
		return
	var lt = v.lights
	if lt.has_method("_set_state"):
		var surfs: Variant = lt.get("_surfs")
		var has_amber := false
		if surfs is Dictionary and (surfs as Dictionary).has(&"amber"):
			has_amber = not ((surfs as Dictionary)[&"amber"] as Array).is_empty()
		if has_amber:
			lt._set_state(&"amber", &"on" if lit else &"off")
		else:
			v.headlights_on = lit if hazard_on else g_want_lights


func _tick_lights(dt: float) -> void:
	if hazard_on:
		_haz_phase += dt
		var lit := fposmod(_haz_phase, 0.75) < 0.4
		_apply_hazard_state(lit)
		return
	_lights_t -= dt
	if _lights_t <= 0.0:
		_lights_t = 1.5 + rng.randf() * 0.6
		if v.headlights_on != g_want_lights:
			v.headlights_on = g_want_lights


func on_collision(other: Node, impulse: float) -> void:
	if mode == MODE_DEAD or mode == MODE_CRASHED:
		return
	if impulse < 3200.0:
		return
	mode = MODE_CRASHED
	crashed_at = now
	crash_t = rng.randf_range(5.0, 10.0)
	set_hazard(true)
	thr = 0.0
	brk = 0.0
	if jn_jid >= 0 and not jn_granted:
		junction.release(self)
	if other != null and (other.is_in_group(GC.G_PLAYER) or (other is VehicleBase and (other as VehicleBase).driver != null and (other as VehicleBase).driver.is_in_group(GC.G_PLAYER))):
		if aggression > 0.4:
			_honk(0.7, 2.0)
	if rng.randf() < 0.35:
		_honk(0.5, 3.0)


## Short stop without hazards (e.g. after running into a pedestrian).
func brief_stop(seconds: float) -> void:
	if mode != MODE_DRIVE:
		return
	mode = MODE_CRASHED
	crashed_at = now
	crash_t = seconds
	thr = 0.0
	brk = 0.0


func begin_flee(seconds: float) -> void:
	if mode == MODE_DEAD:
		return
	flee_t = maxf(flee_t, seconds)
	if mode == MODE_CRASHED:
		crash_t = minf(crash_t, 1.2)
	yield_t = 0.0
	set_hazard(false)


func begin_breakdown(seconds: float) -> void:
	breakdown_t = seconds
	set_hazard(true)


## Called when someone else takes the wheel, the driver dies or the vehicle is removed. Leaves the car as an ordinary vehicle.
func release_control() -> void:
	if mode == MODE_DEAD:
		return
	_die("released")
	if v != null and is_instance_valid(v):
		v.reset_controls()
		v.keep_engine_on = false
		if v.is_ai_controlled:
			v.set_ai_controlled(false)


func _die(reason: String) -> void:
	if mode == MODE_DEAD:
		return
	mode = MODE_DEAD
	released_reason = reason
	if junction != null:
		junction.release(self)
	if v != null and is_instance_valid(v):
		v.input_horn = false
		set_hazard(false)


func mean_xte() -> float:
	return xte_sum / maxf(float(xte_n), 1.0)


## One-line state dump for tests / debugging.
func debug_string() -> String:
	var p := v.global_position if is_instance_valid(v) else Vector3.ZERO
	return "%s %s mode=%d reason=%d spd=%.1f vt=%.1f a=%.1f stop=%.1f lead=%.1f/%.1f k%d lat=%.2f off=%.2f steer=%.2f thr=%.2f brk=%.2f jn=%d/%s seg=%d/%d idle=%.1f pt=%d" % [
		v.name if is_instance_valid(v) else "?", str(p.snapped(Vector3.ONE)), mode, stop_reason, _cur_spd, dbg_vt, dbg_a, dbg_stop,
		lead_s, lead_v, lead_kind, lat_pos, lat_off, steer_cmd, thr, brk, jn_jid, str(jn_granted), seg, P.size(), idle_t,
		P[seg] if seg < P.size() else -1]
