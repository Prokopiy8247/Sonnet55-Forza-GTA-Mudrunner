class_name PedBrain
extends RefCounted
## Behaviour of one pedestrian: a compact state machine (stroll, wait at the curb, cross, sit, talk, sunbathe, phone, flee, cower,
## surrender, gawk, fight, stagger, knocked down) driven by PedManager's central scheduler:
##   think(dt, now)  decisions + perception (rate depends on the tier: 20 Hz near, 6 Hz mid)
##   move(dt)        kinematic locomotion along the PedGraph (every physics tick, ~5 us)
## Reactions are data driven (PedDefs.PERSONALITIES). Nothing here uses physics queries except the rare get-up ground ray.

enum S { IDLE, WALK, WAIT, CROSS, JAYWALK, SIT, TALK, SUNBATHE, STATIC, CALL, FLEE, COWER, HANDS_UP, GAWK, FIGHT, STAGGER, KNOCKED, GETUP, DRIVING, DEAD }
const NAMES: Array[String] = ["idle", "walk", "wait", "cross", "jaywalk", "sit", "talk", "sunbathe", "static", "call", "flee", "cower",
	"hands_up", "gawk", "fight", "stagger", "knocked", "getup", "driving", "dead"]
const SIT_SEAT_HEIGHT := 0.46        # bench seat plank height (bench.glb) above the ground
const SIT_RIG_DROP := 0.02
const IDLE_STYLES: Array[StringName] = [&"relaxed", &"arms_crossed", &"hands_pockets", &"relaxed"]

var p: Pedestrian = null
var state: int = S.IDLE
var prev_state: int = S.IDLE
var t_state := 0.0
var dur := 0.0
var now := 0.0

# ---- navigation ------------------------------------------------------------------------------------------------------------
var n_cur := -1                       # last reached node
var n_prev := -1
var n_next := -1                      # node being walked to
var wait_node := -1                   # crossing entry waiting for green
var path := PackedInt32Array()
var path_i := 0
var use_path := false
var lane := 0.6
var seg_a := Vector3.ZERO
var seg_b := Vector3.ZERO
var seg_dir := Vector3(0, 0, -1)
var off := Vector3.ZERO
var has_free := false
var free_target := Vector3.ZERO
var cross_w := 0.35
var heading := 0.0
var speed := 0.0
var speed_goal := 0.0
var push := Vector3.ZERO
var sep := Vector2.ZERO
var ground_y := 0.0
var px := 0.0                         # cached position (the brain is the only mover)
var pz := 0.0

# ---- reactions ----------------------------------------------------------------------------------------------------------------
var threat_pos := Vector3.ZERO
var threat_src: Node = null
var threat_t := -100.0
var fear_t := 0.0
var flee_dur := 10.0
var attacker: Node = null
var pend_t := -1.0
var pend_kind: StringName = &""
var pend_pos := Vector3.ZERO
var pend_sev := 0.0
var pend_src: Node = null
var pend_direct := false
var aimed_t := -100.0
var aimed_react_t := -100.0
var last_bump_t := -100.0
var last_dodge_t := -100.0
var glance_t := -100.0
var glanced := false
var knock_t := 0.0
var getup_t := 0.0
var stagger_t := 0.0
var punch_cd := 0.0
var punch_hit_t := -1.0
var fight_t := 0.0
var air_t := 0.0
var idle_style_t := 0.0
var call_resume_flee := false
var victim_until := -1.0              # carjacked / mugged: decides by itself (stagger -> flee / fight), ignores crowd reactions
var _stance_cache: StringName = &"stand"
var _yelled_t := -100.0
var _think_acc := 0.0
var step_acc := 0.0

# ---- scenarios ------------------------------------------------------------------------------------------------------------------
var sit_yaw := 0.0
var face_yaw := 0.0
var has_face := false                 # IDLE: turn towards face_yaw
var idle_look_target := Vector3.INF
var activity_kind: StringName = &""


func _init(ped: Pedestrian) -> void:
	p = ped


func state_name() -> String:
	return NAMES[state]


func mgr() -> PedManager:
	return p.manager


func reset() -> void:
	state = S.IDLE
	prev_state = S.IDLE
	t_state = 0.0
	dur = 4.0
	n_cur = -1
	n_prev = -1
	n_next = -1
	wait_node = -1
	path = PackedInt32Array()
	use_path = false
	has_free = false
	speed = 0.0
	speed_goal = 0.0
	push = Vector3.ZERO
	sep = Vector2.ZERO
	threat_src = null
	threat_t = -100.0
	attacker = null
	pend_t = -1.0
	aimed_t = -100.0
	aimed_react_t = -100.0
	last_bump_t = -100.0
	last_dodge_t = -100.0
	glance_t = -100.0
	knock_t = 0.0
	getup_t = 0.0
	stagger_t = 0.0
	punch_cd = 0.0
	punch_hit_t = -1.0
	fear_t = 0.0
	air_t = 0.0
	activity_kind = &""
	idle_look_target = Vector3.INF
	call_resume_flee = false
	_stance_cache = &"stand"
	_think_acc = 0.0
	cross_w = 0.35
	lane = 0.35 + 0.6 * float(randi() % 100) / 100.0


func release_claims() -> void:
	if p.bench_claim >= 0 and p.manager != null:
		p.manager.release_bench(p.bench_claim)
	p.bench_claim = -1


# =====================================================================================================================
# Scenario entry points (PedSpawner / tests)
# =====================================================================================================================
## Start strolling along the graph from `node` (coming from `prev`, or -1). Joggers use the jog speed.
func begin_walk(node: int, prev: int = -1, yaw: float = NAN) -> void:
	var pg := WorldLayout.ped_graph
	n_cur = node
	n_prev = prev
	var fwd := Util.yaw_to_dir(yaw) if not is_nan(yaw) else Vector3(randf() - 0.5, 0, randf() - 0.5)
	var nxt := PedNav.next_random(node, prev, fwd, mgr().rng, cross_w)
	if nxt < 0:
		nxt = node
	lane = mgr().rng.randf_range(0.3, 0.95)
	_set_segment(node, nxt)
	var here := PedNav.node_pos(node)
	px = here.x + off.x
	pz = here.z + off.z
	ground_y = here.y
	heading = Util.dir_to_yaw(seg_dir) if is_nan(yaw) else yaw
	_apply_transform()
	_enter(S.WALK)


func begin_idle(style: StringName, seconds: float, yaw: float = NAN, snap: bool = false) -> void:
	_enter(S.IDLE)
	dur = seconds
	if not is_nan(yaw):
		face_yaw = yaw
		has_face = true                    # turns towards it smoothly (_turn_in_place); snap = instantly (spawn)
		if snap:
			heading = yaw
	p.rig.set_idle_style(style)
	if style == &"phone":
		p._show_phone(true)
	_apply_transform()


func begin_static(yaw: float) -> void:
	heading = yaw
	_enter(S.STATIC)
	dur = 1e9
	_apply_transform()


## Sit on a bench: `seat` is the world position of the seat plank centre (ground y + seat height is added by the caller via ground_y).
func begin_sit(seat_xz: Vector3, yaw: float, bench_idx: int, seconds: float, ground: float) -> void:
	px = seat_xz.x
	pz = seat_xz.z
	ground_y = ground
	heading = yaw
	sit_yaw = yaw
	p.bench_claim = bench_idx
	_enter(S.SIT)
	dur = seconds
	_apply_transform()


func begin_talk(partner, yaw: float, seconds: float) -> void:
	p.partner = partner
	heading = yaw
	face_yaw = yaw
	_enter(S.TALK)
	dur = seconds
	_apply_transform()


func begin_sunbathe(yaw: float, seconds: float, towel: Color) -> void:
	heading = yaw
	_enter(S.SUNBATHE)
	dur = seconds
	p.show_towel(true, towel)
	_apply_transform()


## Seated in a vehicle: the vehicle owns the transform; the manager animates the steering.
func begin_driving() -> void:
	_enter(S.DRIVING)
	dur = 1e9
	speed = 0.0


## Follow an explicit node path (A*) then continue strolling.
func go_to_node(target: int) -> bool:
	var from := n_next if n_next >= 0 else n_cur
	if from < 0:
		from = PedNav.nearest_node(p.global_position)
	var pth := PedNav.find_path(from, target)
	if pth.size() < 2:
		return false
	path = pth
	use_path = true
	n_cur = pth[0]
	n_prev = -1
	path_i = 1
	_commit_next(pth[1])
	return true


# =====================================================================================================================
# State changes
# =====================================================================================================================
func _enter(s: int) -> void:
	var old := state
	if old != s:
		_exit(old)
	prev_state = old
	state = s
	t_state = 0.0
	has_face = false
	var r = p.rig
	match s:
		S.IDLE:
			speed_goal = 0.0
			dur = mgr().rng.randf_range(3.0, 9.0)
			idle_style_t = 0.0
			if old != S.IDLE:
				r.set_idle_style(IDLE_STYLES[mgr().rng.randi() % IDLE_STYLES.size()])
		S.WALK:
			speed_goal = p.jog_speed if p.role == &"jogger" else p.walk_speed
		S.WAIT:
			speed_goal = 0.0
			dur = PedDefs.WAIT_MAX
		S.CROSS, S.JAYWALK:
			speed_goal = p.walk_speed * 1.25
		S.SIT:
			speed_goal = 0.0
			speed = 0.0
			r.set_stance(&"sit_car")
			r.set_seat(&"passenger", Vector3.ZERO)
			_rig_lift(SIT_SEAT_HEIGHT - SIT_RIG_DROP)
			p.body_height = 1.35
		S.TALK:
			speed_goal = 0.0
			dur = maxf(dur, 6.0)
			idle_style_t = 0.0
			r.set_idle_style(IDLE_STYLES[mgr().rng.randi() % IDLE_STYLES.size()])
		S.SUNBATHE:
			speed_goal = 0.0
			speed = 0.0
			r.set_stance(&"dead")
			r.motion.dead_face_down = mgr().rng.randf() < 0.12
			p.body_height = 0.5
		S.STATIC:
			speed_goal = 0.0
		S.CALL:
			speed_goal = 0.0
		S.FLEE:
			speed_goal = p.run_speed
			fear_t = 0.0
			flee_dur = mgr().rng.randf_range(8.0, 14.0)
			r.play_action(&"hands_down")
			r.set_idle_style(&"relaxed")
			r.clear_look()
		S.COWER:
			speed_goal = 0.0
			speed = 0.0
			dur = mgr().rng.randf_range(5.0, 10.0)
			r.set_stance(&"crouch")
			r.play_action(&"hands_up")
			p.is_crouching = true
			p.body_height = 1.2
		S.HANDS_UP:
			speed_goal = 0.0
			dur = 25.0
			r.play_action(&"hands_up")
		S.GAWK:
			speed_goal = 0.0
			dur = mgr().rng.randf_range(2.0, 5.5)
		S.FIGHT:
			speed_goal = p.run_speed * 0.8
			fight_t = 0.0
			punch_cd = 0.4
			r.play_action(&"hands_down")
		S.STAGGER:
			speed_goal = 0.0
			stagger_t = 0.5
		S.KNOCKED:
			speed_goal = 0.0
			speed = 0.0
		S.GETUP:
			speed_goal = 0.0
			getup_t = 0.75
		S.DRIVING:
			speed_goal = 0.0
		S.DEAD:
			speed_goal = 0.0
			speed = 0.0


func _exit(old: int) -> void:
	var r = p.rig
	match old:
		S.SIT:
			_rig_lift(0.0)
			r.set_stance(&"stand")
			r.set_seat(&"driver", Vector3.ZERO)
			p.body_height = 1.8 * float(p.variant.get("scale", 1.0))
			release_claims()
		S.SUNBATHE:
			r.set_stance(&"stand")
			p.show_towel(false)
			p.body_height = 1.8 * float(p.variant.get("scale", 1.0))
		S.COWER:
			r.set_stance(&"stand")
			r.play_action(&"hands_down")
			p.is_crouching = false
			p.body_height = 1.8 * float(p.variant.get("scale", 1.0))
		S.HANDS_UP:
			r.play_action(&"hands_down")
		S.IDLE, S.CALL, S.TALK, S.WAIT:
			if p.phone_visible and not p.is_calling():
				p._show_phone(false)
			if old == S.IDLE or old == S.TALK or old == S.WAIT:
				r.set_idle_style(&"relaxed")


## The rig sits on the bench: lift the rig above the ground (rig origin = seat point, see character_rig.md).
func _rig_lift(h: float) -> void:
	p.rig.position = Vector3(0, h, 0.0)


func _enter_walk_like() -> void:
	if state != S.WALK:
		_enter(S.WALK)


func resume_walk() -> void:
	## After an activity: continue strolling from the nearest graph position.
	has_free = false
	use_path = false
	if n_cur < 0 or Util.dist_xz(WorldLayout.ped_graph.positions[n_cur], p.global_position) > 14.0:
		n_cur = PedNav.nearest_node(p.global_position, 30.0)
		n_prev = -1
	if n_cur < 0:
		_enter(S.IDLE)
		return
	var nxt := PedNav.next_random(n_cur, n_prev, Util.yaw_to_dir(heading), mgr().rng, cross_w)
	if nxt < 0:
		nxt = n_cur
	_set_segment(n_cur, nxt)
	_pick_lane_side()
	if state != S.WALK:
		_enter(S.WALK)
	speed_goal = p.jog_speed if p.role == &"jogger" else p.walk_speed


func _pick_lane_side() -> void:
	lane = mgr().rng.randf_range(0.3, 0.95)


func _set_segment(a: int, b: int) -> void:
	var pg := WorldLayout.ped_graph
	n_prev = a
	n_next = b
	seg_a = PedNav.node_pos(a)
	seg_b = PedNav.node_pos(b)
	var d := Vector3(seg_b.x - seg_a.x, 0.0, seg_b.z - seg_a.z)
	if d.length() > 0.05:
		seg_dir = d.normalized()
	var crossing := pg.zone[b] == PedGraph.ZONE_CROSSING or pg.zone[a] == PedGraph.ZONE_CROSSING
	var l := lane * (0.35 if crossing else 1.0)
	off = PedNav.right_of(seg_dir) * l


# =====================================================================================================================
# Decisions
# =====================================================================================================================
func think(dt: float, t_now: float) -> void:
	now = t_now
	t_state += dt
	if state == S.DEAD or state == S.DRIVING:
		return
	# panic decays
	if p.panic > 0.0:
		var calm: Array = p.pers.get("calm", [16.0, 24.0])
		p.panic = maxf(p.panic - dt / float(calm[0] + (calm[1] - calm[0]) * 0.5), 0.0)
	# delayed reaction (people need a moment to realise what that bang was)
	if pend_t >= 0.0:
		pend_t -= dt
		if pend_t < 0.0:
			# the source may have been freed during the reaction delay ("previously freed" otherwise)
			var psrc: Node = pend_src if is_instance_valid(pend_src) else null
			pend_src = null
			_decide(pend_kind, pend_pos, pend_sev, psrc, pend_direct)
	# phone call bookkeeping
	if p.has_pending_call():
		p.tick_call(dt)
	match state:
		S.IDLE:
			_think_idle(dt)
		S.WALK, S.CROSS, S.JAYWALK:
			_think_walk(dt)
		S.WAIT:
			_think_wait(dt)
		S.SIT, S.SUNBATHE:
			if t_state >= dur:
				_end_activity()
		S.TALK:
			_think_talk(dt)
		S.CALL:
			if not p.is_calling():
				_after_call()
		S.FLEE:
			_think_flee(dt)
		S.COWER:
			_think_cower(dt)
		S.HANDS_UP:
			_think_hands_up(dt)
		S.GAWK:
			_think_gawk(dt)
		S.FIGHT:
			_think_fight(dt)
		S.STAGGER:
			stagger_t -= dt
			if stagger_t <= 0.0:
				_after_stagger()
		S.KNOCKED:
			_think_knocked(dt)
		S.GETUP:
			getup_t -= dt
			if getup_t <= 0.0:
				_after_getup()
		S.STATIC:
			_think_static(dt)
	# perception: only for peds that can act on it and are close enough to matter
	if p.tier == 0 and state != S.KNOCKED and state != S.GETUP and state != S.STAGGER and p.role != &"dummy":
		_perceive(dt)
		if p.tier == 0 and (state == S.WALK or state == S.CROSS or state == S.JAYWALK or state == S.FLEE or state == S.FIGHT):
			_update_sep()


func _think_idle(dt: float) -> void:
	idle_style_t += dt
	if t_state >= dur:
		_end_activity()
		return
	if activity_kind == &"window" or activity_kind == &"bus_stop":
		if idle_look_target != Vector3.INF and idle_style_t > 0.0:
			p.rig.look_at_point(idle_look_target)
	elif mgr().rng.randf() < 0.02:
		# idle glances
		var a := mgr().rng.randf() * TAU
		idle_look_target = p.global_position + Vector3(cos(a) * 8.0, 1.5, sin(a) * 8.0)
		p.rig.look_at_point(idle_look_target)


func _end_activity() -> void:
	activity_kind = &""
	idle_look_target = Vector3.INF
	p.rig.clear_look()
	if p.role == &"sitter" or p.role == &"sunbather" or p.role == &"talker" or p.role == &"waiter":
		p.role = &"walker"
	_exit_scene_group()
	resume_walk()


func _exit_scene_group() -> void:
	if p.partner != null and is_instance_valid(p.partner):
		var other = p.partner
		if other.brain != null and other.brain.state == S.TALK:
			other.brain.dur = other.brain.t_state            # the partner ends the chat as well
		p.partner = null


func _think_walk(dt: float) -> void:
	if state == S.CROSS:
		_update_cross_speed()
	if p.tier == 0 and p.role != &"jogger" and not has_free:
		# occasional glance at the player when passing close by
		var d2 := (mgr().player_pos - p.global_position)
		d2.y = 0.0
		if d2.length_squared() < 36.0 and now - glance_t > 14.0 and mgr().rng.randf() < 0.05:
			glance_t = now
			glanced = true
		if glanced and now - glance_t < 1.6:
			p.rig.look_at_point(mgr().player_pos + Vector3(0, 1.55, 0))
		else:
			glanced = false


func _update_cross_speed() -> void:
	var pg := WorldLayout.ped_graph
	if n_next < 0 or n_next >= pg.size():
		return
	var sid: int = pg.signal_id[n_next]
	var want := p.walk_speed * 1.25
	if sid >= 0 and pg.zone[n_next] == PedGraph.ZONE_CROSSING:
		var left := WorldLayout.red_time_left(sid, pg.walk_phase[n_next], mgr().signal_time())
		var remaining := _crossing_remaining(n_next)
		if left < remaining / maxf(want, 0.5) + 1.5:
			want = maxf(want, 3.4)              # hurry, the light is about to change
	speed_goal = want


func _crossing_remaining(idx: int) -> float:
	var pg := WorldLayout.ped_graph
	var total := 0.0
	var cur := idx
	var prev := n_cur
	var guard := 0
	var here := Vector3(px, 0.0, pz)
	total += Util.dist_xz(here, pg.positions[cur])
	while guard < 8:
		guard += 1
		var nxt := -1
		for n in pg.links[cur]:
			if n != prev and pg.zone[n] == PedGraph.ZONE_CROSSING:
				nxt = n
				break
		if nxt < 0:
			break
		total += Util.dist_xz(pg.positions[cur], pg.positions[nxt])
		prev = cur
		cur = nxt
	return total


func _think_wait(dt: float) -> void:
	if wait_node < 0:
		_end_activity()
		return
	var pg := WorldLayout.ped_graph
	# look at the road / lights
	if activity_kind == &"" or activity_kind == &"crossing":
		var tp := pg.positions[wait_node]
		p.rig.look_at_point(Vector3(tp.x, 1.6, tp.z))
	if _crossing_ok(wait_node) or t_state > PedDefs.WAIT_MAX:
		var nxt := wait_node
		wait_node = -1
		_enter(S.CROSS if pg.zone[nxt] == PedGraph.ZONE_CROSSING else S.WALK)
		_set_segment(n_cur, nxt)
		p.rig.clear_look()
	elif t_state > 1.0 and float(p.pers.get("jaywalk", 0.0)) > 0.0 and mgr().rng.randf() < float(p.pers.get("jaywalk", 0.0)) * 0.02:
		# impatient: cross anyway when no car is coming
		if not mgr().vehicle_threat_near(Vector3(px, 0.0, pz), 30.0):
			var nxt2 := wait_node
			wait_node = -1
			_enter(S.CROSS)
			_set_segment(n_cur, nxt2)


func _crossing_ok(idx: int) -> bool:
	var m: PedManager = mgr()
	var pg := WorldLayout.ped_graph
	if pg.signal_id[idx] >= 0:
		return WorldLayout.crossing_open(idx, m.signal_time(), 4.0)
	# uncontrolled crossing: wait for a gap in the traffic
	var c: Vector3 = pg.positions[idx]
	return not m.vehicle_threat_near(c, 26.0)


func _think_talk(dt: float) -> void:
	idle_style_t += dt
	var other = p.partner
	if other == null or not is_instance_valid(other) or other.is_dead or other.brain.state != S.TALK:
		p.partner = null
		_end_activity()
		return
	if t_state >= dur:
		_end_activity()
		return
	var hp: Vector3 = other.get_eye_position()
	p.rig.look_at_point(hp)
	# turn towards the partner, gesture now and then
	var dx: float = other.global_position.x - px
	var dz: float = other.global_position.z - pz
	face_yaw = atan2(-dx, -dz)
	if idle_style_t > 4.0 + float(p.get_instance_id() % 5):
		idle_style_t = 0.0
		p.rig.set_idle_style(IDLE_STYLES[mgr().rng.randi() % IDLE_STYLES.size()])


func _think_static(dt: float) -> void:
	if p.role == &"dummy":
		return
	if mgr().rng.randf() < 0.01:
		var a := mgr().rng.randf() * TAU
		p.rig.look_at_point(p.global_position + Vector3(cos(a) * 6.0, 1.5, sin(a) * 6.0))


# ---- fear states ---------------------------------------------------------------------------------------------------------------
func _think_flee(dt: float) -> void:
	fear_t += dt
	var d := Util.dist_xz(p.global_position, threat_pos)
	if mgr().rng.randf() < dt * 0.15 and now - _yelled_t > 5.0 and p.tier == 0 and d < 45.0:
		_yelled_t = now
		mgr().voice(p, &"scream", 0.7)
	# over: far enough from the danger or simply exhausted
	var safe := d > 48.0 or (fear_t > flee_dur and d > 22.0)
	if p.panic > 0.5 and fear_t < flee_dur * 1.6 and d < 60.0:
		safe = false
	if safe or fear_t > flee_dur * 2.5:
		_calm_down()


func _calm_down() -> void:
	var r = p.rig
	r.clear_look()
	p.panic = minf(p.panic, 0.35)
	if p.has_pending_call() and not p.is_calling():
		pass
	resume_walk()


func _think_cower(dt: float) -> void:
	if now - threat_t < 3.5 and Util.dist_xz(p.global_position, threat_pos) < 32.0:
		t_state = minf(t_state, dur - 1.5)         # stay down while the danger is fresh
	if t_state >= dur:
		var calm_ok: bool = p.panic < 0.55
		if calm_ok:
			_end_activity()
		else:
			_start_flee(threat_pos)
	# keep the hands up pose alive (it releases itself after 25 s)
	elif t_state > 12.0:
		p.rig.play_action(&"hands_up")


func _think_hands_up(dt: float) -> void:
	if now - aimed_t > 2.8 or t_state > dur:
		# the gun is not on me any more: still shaken, slowly walk away
		p.rig.play_action(&"hands_down")
		_enter(S.IDLE)
		dur = 0.6
		p.panic = maxf(p.panic, 0.4)
	else:
		p.rig.look_at_point(mgr().player_pos + Vector3(0, 1.5, 0))
		face_yaw = atan2(-(mgr().player_pos.x - px), -(mgr().player_pos.z - pz))
		if t_state > 6.0:
			p.rig.play_action(&"hands_up")


func _think_gawk(dt: float) -> void:
	if t_state >= dur:
		p.rig.clear_look()
		resume_walk()
		return
	p.rig.look_at_point(Vector3(threat_pos.x, 1.4, threat_pos.z))
	face_yaw = atan2(-(threat_pos.x - px), -(threat_pos.z - pz))


func _think_fight(dt: float) -> void:
	fight_t += dt
	punch_cd -= dt
	if attacker == null or not is_instance_valid(attacker) or (attacker.get("is_dead") == true) or fight_t > 14.0:
		resume_walk()
		return
	if p.health < p.max_health * 0.4 and fight_t > 1.5:
		_start_flee((attacker as Node3D).global_position)
		return
	var tp: Vector3 = (attacker as Node3D).global_position
	var d := Util.dist_xz(p.global_position, tp)
	if d > 30.0:
		resume_walk()
		return
	if d < 1.55:
		speed_goal = 0.0
		face_yaw = atan2(-(tp.x - px), -(tp.z - pz))
		if punch_cd <= 0.0:
			punch_cd = mgr().rng.randf_range(0.8, 1.2)
			p.rig.play_action(&"punch")
			punch_hit_t = 0.2
	else:
		speed_goal = p.run_speed * 0.75
	if punch_hit_t >= 0.0:
		punch_hit_t -= dt
		if punch_hit_t < 0.0:
			_punch_hit()


func _punch_hit() -> void:
	if attacker == null or not is_instance_valid(attacker) or not attacker.has_method("apply_damage"):
		return
	var tp: Vector3 = (attacker as Node3D).global_position
	if Util.dist_xz(p.global_position, tp) > 2.1:
		return
	var dirv := (tp - p.global_position)
	dirv.y = 0.0
	dirv = dirv.normalized()
	attacker.apply_damage(mgr().rng.randf_range(4.0, 8.0), {"source": p, "type": GC.DMG_MELEE, "zone": GC.ZONE_TORSO,
		"position": tp + Vector3(0, 1.2, 0), "direction": dirv, "weapon": &"fists", "impulse": 1.5})
	Sfx.play_3d(&"punch", tp + Vector3(0, 1.2, 0), -4.0, mgr().rng.randf_range(0.9, 1.1), 30.0)


func _after_stagger() -> void:
	if attacker != null and is_instance_valid(attacker):
		_decide(&"hit", (attacker as Node3D).global_position, 0.85, attacker, true)
	else:
		_decide(&"hit", threat_pos, 0.8, null, true)
	if state == S.STAGGER:
		_start_flee(threat_pos)


func _think_knocked(dt: float) -> void:
	knock_t -= dt
	if knock_t > 0.0:
		return
	_get_up()


func _get_up() -> void:
	var r = p.rig
	var rp: Vector3 = r.get_ragdoll_position()
	var gy := _probe_ground(rp)
	var sp: Vector3 = Vector3(rp.x, gy, rp.z)
	# the ragdoll hips are on the ground: stand up where the body lies
	px = sp.x
	pz = sp.z
	ground_y = gy
	p.global_position = sp
	r.stop_ragdoll()
	p.collision_layer = GC.L_NPC
	_enter(S.GETUP)
	p.got_up.emit()
	_apply_transform()
	p.reset_physics_interpolation()


func _probe_ground(at: Vector3) -> float:
	var res := Util.raycast(p, at + Vector3(0, 1.5, 0), at + Vector3(0, -4.0, 0), GC.M_GROUND)
	if res.is_empty():
		return WorldLayout.terrain_height(at.x, at.z)
	return (res["position"] as Vector3).y


func _after_getup() -> void:
	# stand up, then decide what to do about it
	p.panic = maxf(p.panic, 0.7)
	_enter(S.IDLE)
	dur = 0.1
	if attacker != null and is_instance_valid(attacker):
		_decide(&"hit", (attacker as Node3D).global_position, 0.9, attacker, true)
	else:
		_decide(&"hit", threat_pos if threat_t > 0.0 else p.global_position, 0.8, null, true)
	if state == S.GETUP:
		_start_flee(threat_pos if threat_t > 0.0 else p.global_position + Util.yaw_to_dir(heading) * -6.0)


func _after_call() -> void:
	if call_resume_flee or p.panic > 0.6:
		_start_flee(threat_pos)
	else:
		resume_walk()
	call_resume_flee = false


# =====================================================================================================================
# Perception (near tier)
# =====================================================================================================================
func _perceive(dt: float) -> void:
	var m: PedManager = mgr()
	var pos := p.global_position
	# ---- vehicle heading for me
	if now - last_dodge_t > 1.4 and state != S.SIT and state != S.SUNBATHE:
		_check_vehicles(pos)
	# ---- player aiming a weapon at me / bumping into me
	if m.player != null:
		var to := m.player_pos - pos
		to.y = 0.0
		var d := to.length()
		if m.aim_active and d < 20.0 and d > 0.6 and state != S.FLEE:
			var ad: Vector3 = m.aim_dir
			var ad_flat := Vector3(ad.x, 0.0, ad.z)
			var from_p := -to / d
			var cone := 0.90 if d > 6.0 else (0.80 if d > 2.5 else 0.5)
			if ad_flat.length() > 0.05 and from_p.dot(ad_flat.normalized()) > cone:
				aimed_t = now
				if now - aimed_react_t > 2.0 and state != S.HANDS_UP and state != S.COWER and state != S.FIGHT:
					aimed_react_t = now
					_decide(&"aimed", m.player_pos, 0.9, m.player, true)
		if d < 0.85 and now - last_bump_t > 3.0 and state != S.FLEE and state != S.FIGHT and state != S.SIT:
			if Vector2(m.player_vel.x, m.player_vel.z).length() > 1.2:
				_bump(to, d)


func _check_vehicles(pos: Vector3) -> void:
	var veh: PackedFloat32Array = mgr().veh
	var n := veh.size()
	var i := 0
	while i < n:
		var spd := veh[i + 4]
		var vx := veh[i + 2]
		var vz := veh[i + 3]
		var dx := pos.x - veh[i]
		var dz := pos.z - veh[i + 1]
		var dist2 := dx * dx + dz * dz
		var reach := spd * 1.5 + 5.0
		if dist2 < reach * reach:
			var inv := 1.0 / maxf(spd, 0.01)
			var ux := vx * inv
			var uz := vz * inv
			var along := dx * ux + dz * uz
			if along > -0.5 and along < reach:
				var lat := dx * (-uz) + dz * ux
				if absf(lat) < veh[i + 6] + 0.9 and (along - veh[i + 5]) / maxf(spd, 1.0) < 1.35:
					_dodge(Vector3(-uz, 0.0, ux) * (1.0 if lat >= 0.0 else -1.0), spd, Vector3(veh[i], pos.y, veh[i + 1]))
					return
		i += 7


## A vehicle is about to run me over: hop aside (rig jump pose), then stand there shaken and stare after it.
func _dodge(side: Vector3, car_speed: float, car_pos: Vector3) -> void:
	last_dodge_t = now
	var m: PedManager = mgr()
	if state == S.SIT or state == S.SUNBATHE or state == S.COWER:
		_decide(&"vehicle", p.global_position - side * 4.0, 0.9, null, true)
		return
	p.rig.play_action(&"jump")
	air_t = 0.42
	push += side * clampf(7.0 + car_speed * 0.12, 8.0, 10.5)
	m.voice(p, &"gasp" if m.rng.randf() < 0.6 else &"scream", 0.9)
	p.panic = maxf(p.panic, 0.7)
	threat_pos = car_pos
	threat_t = now
	p.panicked.emit(car_pos)
	if state != S.FLEE and state != S.FIGHT:
		_enter(S.GAWK)
		dur = 2.2
		activity_kind = &"dodge"
	m.notify_neighbors(p, p.global_position, 10.0, &"crash", 0.5, null)


func _bump(to_player: Vector3, d: float) -> void:
	last_bump_t = now
	var away := -to_player / maxf(d, 0.1)
	push += away * 1.8
	p.rig.hit_react(-away, 0.7)
	p.rig.look_at_point(mgr().player_pos + Vector3(0, 1.6, 0))
	mgr().voice(p, &"cough" if mgr().rng.randf() < 0.55 else &"gasp", 0.8)
	if state == S.IDLE or state == S.WALK or state == S.WAIT:
		glance_t = now
		glanced = true
	var rn: float = mgr().rng.randf()
	if p.personality == &"tough" and rn < 0.25 or p.personality == &"brave" and rn < 0.1:
		attacker = mgr().player
		_enter(S.FIGHT)


# ---- avoidance ---------------------------------------------------------------------------------------------------------------------
func _update_sep() -> void:
	var m: PedManager = mgr()
	var pos := p.global_position
	var s := Vector2.ZERO
	var neigh: Array = m.query_radius(pos, PedDefs.SEPARATION + 0.6)
	var fwd := Vector2(-sin(heading), -cos(heading))
	var rt := Vector2(-fwd.y, fwd.x)
	for o in neigh:
		if o == p or o.is_dead:
			continue
		var d := Vector2(pos.x - o.hpos.x, pos.z - o.hpos.z)
		var l := d.length()
		if l < 0.001 or l > PedDefs.SEPARATION:
			continue
		var w := (PedDefs.SEPARATION - l) / PedDefs.SEPARATION
		s += d / l * w * 1.3
		# head-on: both sidestep to their right
		var ofwd := Vector2(-sin(o.brain.heading), -cos(o.brain.heading))
		if o.brain.speed > 0.4 and fwd.dot(ofwd) < -0.3:
			s += rt * w * 0.9
	# the player is a big obstacle
	if m.player != null:
		var dp := Vector2(pos.x - m.player_pos.x, pos.z - m.player_pos.z)
		var lp := dp.length()
		if lp < 1.4 and lp > 0.01:
			s += dp / lp * (1.4 - lp) * 1.1
	s += PedNav.avoid(pos.x, pos.z) * 0.9
	sep = sep.lerp(s, 0.55)
	if sep.length() > 1.6:
		sep = sep.normalized() * 1.6


# =====================================================================================================================
# Reacting to the world
# =====================================================================================================================
## Entry point of every threat. Direct threats react immediately, others after a human reaction delay (0.1 - 0.55 s).
func react(kind: StringName, pos: Vector3, severity: float, src_in, direct: bool) -> void:
	var src: Node = src_in if (src_in != null and is_instance_valid(src_in)) else null   # tolerate a source freed by now
	if state == S.DEAD or state == S.KNOCKED or state == S.GETUP or p.role == &"dummy":
		return
	if mgr().now < victim_until and not direct:
		threat_pos = pos
		threat_t = mgr().now
		return
	if p.is_driver:
		p.panic = maxf(p.panic, severity)
		threat_pos = pos
		threat_t = mgr().now
		p.panicked.emit(pos)
		return
	var alert := float(p.pers.get("alert", 1.0))
	severity = clampf(severity * (0.75 + 0.25 * alert), 0.0, 1.0)
	if direct or severity >= 0.95:
		_decide(kind, pos, severity, src, direct)
		return
	if pend_t >= 0.0:
		pend_sev = maxf(pend_sev, severity)
		return
	pend_t = mgr().rng.randf_range(0.1, 0.55)
	pend_kind = kind
	pend_pos = pos
	pend_sev = severity
	pend_src = src
	pend_direct = direct


func _decide(kind: StringName, pos: Vector3, sev: float, src_in, direct: bool) -> void:
	var src: Node = src_in if (src_in != null and is_instance_valid(src_in)) else null   # untyped param: tolerate freed sources
	var m: PedManager = mgr()
	if state == S.DEAD or state == S.KNOCKED or state == S.GETUP:
		return
	now = m.now
	pend_t = -1.0
	threat_pos = pos
	threat_src = src
	threat_t = now
	p.panic = clampf(maxf(p.panic, sev), 0.0, 1.0)
	p.panicked.emit(pos)
	if sev < 0.22:
		return
	# already running / hiding: just refresh the danger position
	if state == S.FLEE:
		fear_t = minf(fear_t, flee_dur * 0.5)
		return
	if state == S.COWER or state == S.HANDS_UP:
		if state == S.HANDS_UP and kind != &"aimed" and sev > 0.7 and kind != &"crime":
			_enter(S.COWER)
		return
	if state == S.FIGHT and kind != &"explosion":
		return
	var shopkeeper: bool = p.role == &"shopkeeper"
	var tables: Dictionary = p.pers
	var table: Dictionary
	match kind:
		&"aimed":
			table = tables.get("aimed", {})
		&"hit":
			table = tables.get("hit", {})
		_:
			table = tables.get("react", {})
	if sev < 0.5 and kind != &"aimed" and kind != &"hit":
		# mild: look, don't run (curious types stop to gawk, others carry on warily)
		if m.rng.randf() < float(table.get("gawk", 0.0)) + 0.2 and p.tier == 0 and state != S.SIT:
			_enter(S.GAWK)
		return
	var choice: StringName = PedDefs.weighted(table, m.rng)
	if choice == &"":
		choice = &"flee"
	# not everyone reacts to everything: far gunfire barely worries the bold
	if kind == &"gunshot" or kind == &"explosion":
		if choice == &"hands_up":
			choice = &"cower"
		if choice == &"gawk" and sev > 0.7:
			choice = &"flee"
	if (kind == &"explosion" or kind == &"vehicle") and (choice == &"gawk" or choice == &"fight"):
		choice = &"flee"
	if shopkeeper:
		choice = &"cower" if choice == &"flee" or choice == &"gawk" else choice
	match choice:
		&"flee":
			_start_flee(pos)
		&"cower":
			_enter(S.COWER)
			m.voice(p, &"gasp", 0.7)
			m.spread_panic(p, pos, sev * 0.6)
		&"hands_up":
			_enter(S.HANDS_UP)
			aimed_t = now
			m.voice(p, &"gasp", 0.8)
		&"fight":
			if src != null and is_instance_valid(src) and src is Node3D and src != p:
				attacker = src
				_enter(S.FIGHT)
			else:
				_start_flee(pos)
		&"gawk":
			_enter(S.GAWK)
		_:
			_start_flee(pos)


func _start_flee(from_pos: Vector3) -> void:
	var m: PedManager = mgr()
	var pg := WorldLayout.ped_graph
	threat_pos = from_pos
	if state != S.FLEE:
		_enter(S.FLEE)
		if m.rng.randf() < float(p.pers.get("scream", 0.5)):
			m.voice(p, &"scream", 1.0)
		m.spread_panic(p, from_pos, p.panic * 0.7)
	has_free = false
	use_path = false
	if p.bench_claim >= 0:
		release_claims()
	# choose the graph direction that leads away from the threat
	var here := p.global_position
	if n_cur < 0 or Util.dist_xz(pg.positions[n_cur], here) > 20.0:
		n_cur = PedNav.nearest_node(here, 36.0)
		n_prev = -1
	if n_cur < 0:
		# off the graph: run straight away
		has_free = true
		var away := Vector3(here.x - from_pos.x, 0, here.z - from_pos.z)
		away = away.normalized() if away.length() > 0.1 else Util.yaw_to_dir(heading)
		free_target = here + away * 40.0
		n_next = -1
		return
	var a := n_next if n_next >= 0 else n_cur
	var b := n_prev if n_prev >= 0 else n_cur
	if n_next >= 0 and n_prev >= 0:
		# currently on the segment prev -> next: continue to whichever end is farther from the threat
		var da := Util.dist_xz(pg.positions[n_next], from_pos)
		var db := Util.dist_xz(pg.positions[n_prev], from_pos)
		if db > da + 2.0:
			a = n_prev
			b = n_next
		else:
			a = n_next
			b = n_prev
		n_cur = b
	else:
		n_cur = a
		a = PedNav.flee_next(n_cur, n_prev, from_pos, m.rng)
		if a < 0:
			a = n_cur
	n_prev = n_cur
	_set_segment(n_cur, a)
	n_cur = n_prev
	lane = m.rng.randf_range(0.0, 0.5)


## Hurt but alive (bullets, punches, bats): stagger, then fight back or run.
func on_damaged(amount: float, info: Dictionary) -> void:
	if state == S.DEAD:
		return
	var src = info.get("source", null)
	if src != null and is_instance_valid(src) and src is Node3D:
		attacker = src
		threat_pos = (src as Node3D).global_position
	else:
		attacker = null
		threat_pos = info.get("position", p.global_position)
	threat_t = mgr().now
	threat_src = src
	p.panic = 1.0
	var t: StringName = info.get("type", GC.DMG_BULLET)
	var dirv: Vector3 = info.get("direction", Vector3.ZERO)
	dirv.y = 0.0
	if dirv.length() < 0.01:
		dirv = -p.global_transform.basis.z
	dirv = dirv.normalized()
	if t == GC.DMG_RUNOVER or t == GC.DMG_EXPLOSION:
		if state != S.KNOCKED:
			var kick := dirv * 5.0 + Vector3.UP * 2.0
			if t == GC.DMG_EXPLOSION:
				kick = info.get("blast_center", p.global_position)
				kick = (p.global_position - kick)
				kick.y = 0.0
				kick = kick.normalized() * 6.0 + Vector3.UP * 3.0
			knock_down(kick, 2.4 if t == GC.DMG_RUNOVER else 2.8)
		return
	if t == GC.DMG_FALL or t == GC.DMG_COLLISION:
		if amount > 6.0 and state != S.KNOCKED:
			knock_down(dirv * 3.0 + Vector3.UP, 2.0)
		return
	p.rig.hit_react(dirv, clampf(amount / 25.0, 0.5, 1.6))
	if state == S.STAGGER or state == S.KNOCKED or state == S.GETUP:
		return
	if state == S.SIT or state == S.SUNBATHE or state == S.COWER or state == S.HANDS_UP or state == S.CALL:
		pass
	_enter(S.STAGGER)
	push += dirv * 0.8
	# neighbours notice violence
	mgr().notify_neighbors(p, p.global_position, 14.0, &"violence", 0.7, src)


func on_death() -> void:
	release_claims()
	_enter(S.DEAD)
	pend_t = -1.0


func knock_down(impulse: Vector3, duration: float) -> void:
	if state == S.DEAD:
		return
	var r = p.rig
	if state == S.KNOCKED:
		r.start_ragdoll(impulse, Vector3.ZERO)
		knock_t = maxf(knock_t, duration)
		return
	release_claims()
	_enter(S.KNOCKED)
	knock_t = duration
	p.collision_layer = 0
	p.is_crouching = false
	p._abort_call(false)
	r.play_action(&"hands_down")
	r.set_locomotion(0.0, Vector3(0, 0, -1), false)
	r.start_ragdoll(impulse, p.global_position + Vector3(0, 1.0, 0))
	p.knocked_down.emit()
	mgr().voice(p, &"gasp", 0.9)
	mgr().notify_neighbors(p, p.global_position, 16.0, &"violence", 0.6, attacker)


func shove(impulse: Vector3) -> void:
	push += Vector3(impulse.x, 0.0, impulse.z) * 0.6
	if state == S.SIT or state == S.SUNBATHE:
		return
	if state != S.FLEE and state != S.STAGGER:
		p.rig.hit_react(impulse.normalized(), 0.6)


func on_carjacked(thief: Node) -> void:
	_enter(S.STAGGER)
	stagger_t = 0.7
	victim_until = mgr().now + 2.5
	attacker = thief
	if thief is Node3D:
		threat_pos = (thief as Node3D).global_position
	threat_t = mgr().now
	threat_src = thief
	p.panic = 1.0
	speed = 0.0
	n_cur = -1
	n_prev = -1
	n_next = -1
	has_free = false
	heading = p.rotation.y
	px = p.global_position.x
	pz = p.global_position.z
	ground_y = p.global_position.y
	p.rig.hit_react(Vector3(0, 0, 1), 1.2)
	mgr().voice(p, &"scream" if mgr().rng.randf() < 0.6 else &"gasp", 1.0)
	mgr().spread_panic(p, threat_pos, 0.8)


## Thrown out of a wrecked / abandoned vehicle: stagger, then run.
func on_ejected(from_pos: Vector3) -> void:
	heading = p.rotation.y
	px = p.global_position.x
	pz = p.global_position.z
	ground_y = p.global_position.y
	n_cur = -1
	n_prev = -1
	n_next = -1
	has_free = false
	speed = 0.0
	p.panic = 1.0
	threat_pos = from_pos
	threat_t = mgr().now
	attacker = null
	_enter(S.STAGGER)
	stagger_t = 0.6
	p.rig.hit_react(Vector3(0, 0, 1), 1.0)


## Called by the Pedestrian when the call starts / ends.
func can_phone() -> bool:
	match state:
		S.KNOCKED, S.GETUP, S.STAGGER, S.DEAD, S.FIGHT, S.HANDS_UP, S.DRIVING:
			return false
		S.FLEE:
			return fear_t > 2.6
		S.COWER:
			return t_state > 1.2
	return true


func begin_call() -> void:
	match state:
		S.COWER, S.HANDS_UP:
			pass
		S.FLEE:
			call_resume_flee = true
			_enter(S.CALL)
		_:
			if state != S.SIT and state != S.SUNBATHE:
				_enter(S.CALL)
	p.rig.set_idle_style(&"phone")


func end_call() -> void:
	if state == S.CALL:
		_after_call()


# =====================================================================================================================
# Locomotion (every physics tick)
# =====================================================================================================================
var _tx := 0.0
var _tz := 0.0


static func _is_moving(s: int) -> bool:
	return s == S.WALK or s == S.CROSS or s == S.JAYWALK or s == S.FLEE or s == S.FIGHT


## Resolves the point the ped is walking to (writes _tx / _tz). False when there is nothing to walk to.
func _target(s: int) -> bool:
	if s == S.FIGHT:
		if attacker != null and is_instance_valid(attacker):
			var tp: Vector3 = (attacker as Node3D).global_position
			_tx = tp.x
			_tz = tp.z
			return true
		return false
	if has_free:
		_tx = free_target.x
		_tz = free_target.z
		return true
	if n_next >= 0:
		_tx = seg_b.x + off.x
		_tz = seg_b.z + off.z
		return true
	return false


func move(dt: float) -> void:
	var s := state
	if s == S.DEAD or s == S.DRIVING or s == S.KNOCKED:
		return
	var moving := _is_moving(s)
	if not moving and speed < 0.02 and push.length_squared() < 0.0004:
		_turn_in_place(dt)
		return
	if air_t > 0.0:
		air_t -= dt
		if air_t <= 0.0:
			p.rig.set_grounded(true, -2.0)
	var have_t := false
	if moving:
		have_t = _target(s)
		if have_t and s != S.FIGHT:
			var ddx := _tx - px
			var ddz := _tz - pz
			var arrive := PedDefs.ARRIVE if speed < 3.0 else 1.5
			if ddx * ddx + ddz * ddz < arrive * arrive:
				_arrive()
				s = state
				moving = _is_moving(s)
				have_t = moving and _target(s)
	var target_speed := 0.0
	if moving and have_t:
		target_speed = speed_goal
		var dx := _tx - px
		var dz := _tz - pz
		var dist := sqrt(dx * dx + dz * dz)
		var ax := dx
		var az := dz
		if dist > 0.001:
			ax = dx / dist
			az = dz / dist
		ax += sep.x * 0.8
		az += sep.y * 0.8
		var want := atan2(-ax, -az)
		var diff := wrapf(want - heading, -PI, PI)
		var rate := PedDefs.TURN_RATE_RUN if speed > 3.5 else PedDefs.TURN_RATE
		heading += clampf(diff, -rate * dt, rate * dt)
		target_speed *= clampf(1.0 - absf(diff) / 2.4, 0.2, 1.0)
		if s == S.FIGHT and dist < 1.4:
			target_speed = 0.0
	else:
		_turn_in_place(dt)
	var a := PedDefs.ACCEL if target_speed > speed else PedDefs.DECEL
	speed = move_toward(speed, target_speed, a * dt)
	if not moving and speed < 0.05:
		speed = 0.0
	px += (-sin(heading) * speed + push.x) * dt
	pz += (-cos(heading) * speed + push.z) * dt
	if push.length_squared() > 0.0004:
		push *= exp(-4.0 * dt)
	else:
		push = Vector3.ZERO
	# height: interpolate the graph segment (sidewalks / crossings / paths carry their own y), free walks follow the terrain
	var gy := ground_y
	if has_free or n_next < 0 or s == S.FIGHT:
		gy = WorldLayout.terrain_height(px, pz) + 0.06
	else:
		var abx := seg_b.x - seg_a.x
		var abz := seg_b.z - seg_a.z
		var l2 := abx * abx + abz * abz
		var t := 0.0
		if l2 > 0.01:
			t = clampf(((px - seg_a.x) * abx + (pz - seg_a.z) * abz) / l2, 0.0, 1.0)
		gy = lerpf(seg_a.y, seg_b.y, t)
	ground_y = move_toward(ground_y, gy, (3.0 + speed) * dt)
	_apply_transform()
	p.rig.set_locomotion(speed, Vector3(0, 0, -1), speed > 5.2)


func _turn_in_place(dt: float) -> void:
	var target := heading
	match state:
		S.TALK, S.GAWK, S.HANDS_UP, S.FIGHT:
			target = face_yaw
		S.SIT:
			target = sit_yaw
		S.IDLE:
			if not has_face:
				return
			target = face_yaw
		_:
			if state == S.WAIT and wait_node >= 0:
				var tp := WorldLayout.ped_graph.positions[wait_node]
				target = atan2(-(tp.x - px), -(tp.z - pz))
			else:
				return
	var diff := wrapf(target - heading, -PI, PI)
	if absf(diff) < 0.01:
		return
	heading += clampf(diff, -3.2 * dt, 3.2 * dt)
	_apply_transform()


func _apply_transform() -> void:
	p.global_transform = Transform3D(Basis(Vector3.UP, heading), Vector3(px, ground_y, pz))


# =====================================================================================================================
# Node arrival
# =====================================================================================================================
func _arrive() -> void:
	var pg := WorldLayout.ped_graph
	var m: PedManager = mgr()
	if has_free:
		has_free = false
		if state == S.JAYWALK:
			_enter(S.WALK)
		if n_next >= 0:
			n_cur = n_next
		elif state == S.FLEE:
			# off-graph flee ended: look for a pavement again
			n_cur = PedNav.nearest_node(Vector3(px, ground_y, pz), 40.0)
			n_prev = -1
			if n_cur < 0:
				_calm_down_or_stop()
				return
		else:
			resume_walk()
			return
	else:
		n_cur = n_next
	if n_cur < 0 or n_cur >= pg.size():
		_calm_down_or_stop()
		return
	var cz: int = pg.zone[n_cur]
	var cur_state := state
	# role stops while strolling
	if cur_state == S.WALK and (cz == PedGraph.ZONE_SIDEWALK or cz == PedGraph.ZONE_PLAZA or cz == PedGraph.ZONE_PARK or cz == PedGraph.ZONE_BEACH):
		if p.tier <= 1 and _roll_activity(cz):
			return
	# next node
	var nxt := -1
	if cur_state == S.FLEE:
		nxt = PedNav.flee_next(n_cur, n_prev, threat_pos, m.rng)
	elif use_path:
		if path_i + 1 < path.size():
			path_i += 1
			nxt = path[path_i]
		else:
			use_path = false
			nxt = PedNav.next_random(n_cur, n_prev, seg_dir, m.rng, cross_w)
	else:
		nxt = PedNav.next_random(n_cur, n_prev, seg_dir, m.rng, cross_w)
	if nxt < 0:
		_enter(S.IDLE)
		return
	_commit_next(nxt)
	# a pedestrian who just reached a curb may decide to jaywalk
	if state == S.WALK and p.tier == 0 and cz == PedGraph.ZONE_SIDEWALK and nxt >= 0 and pg.zone[nxt] == PedGraph.ZONE_SIDEWALK 			and mgr().rng.randf() < float(p.pers.get("jaywalk", 0.0)) * 0.5:
		_try_jaywalk()


## Starts the segment n_cur -> nxt: waits at the curb when the crossing is closed, changes between WALK and CROSS.
func _commit_next(nxt: int) -> void:
	var pg := WorldLayout.ped_graph
	if nxt < 0:
		_enter(S.IDLE)
		return
	var cz: int = pg.zone[n_cur]
	var nz: int = pg.zone[nxt]
	var cur_state := state
	if nz == PedGraph.ZONE_CROSSING and cz != PedGraph.ZONE_CROSSING and cur_state != S.FLEE and cur_state != S.FIGHT:
		if not _crossing_ok(nxt):
			wait_node = nxt
			activity_kind = &"crossing"
			_enter(S.WAIT)
			return
		_enter(S.CROSS)
	elif cz == PedGraph.ZONE_CROSSING and nz != PedGraph.ZONE_CROSSING and cur_state == S.CROSS:
		_enter(S.WALK)
	elif cur_state == S.IDLE or cur_state == S.STATIC:
		_enter(S.WALK)
	_set_segment(n_cur, nxt)
	# change the side of the pavement now and then (and keep right at crossings)
	if cz != PedGraph.ZONE_CROSSING and mgr().rng.randf() < 0.12:
		_pick_lane_side()
		_set_segment(n_cur, nxt)


func _calm_down_or_stop() -> void:
	if state == S.FLEE:
		_calm_down()
	else:
		_enter(S.IDLE)


## 3 - 6 % of the nodes of a strolling pedestrian turn into a short activity.
func _roll_activity(zone: int) -> bool:
	var m: PedManager = mgr()
	if p.role == &"jogger" or p.persistent and p.role != &"walker":
		return false
	var r: float = m.rng.randf()
	var pos := Vector3(px, ground_y, pz)
	if r < 0.022:
		begin_idle(&"phone", m.rng.randf_range(9.0, 22.0), heading + m.rng.randf_range(-0.6, 0.6))
		activity_kind = &"phone"
		return true
	if r < 0.04 and zone == PedGraph.ZONE_SIDEWALK:
		var face := _building_facing(pos)
		if face != Vector3.INF:
			begin_idle(IDLE_STYLES[m.rng.randi() % 3], m.rng.randf_range(5.0, 12.0), Util.dir_to_yaw(face))
			activity_kind = &"window"
			idle_look_target = pos + face * 3.0 + Vector3(0, 1.4, 0)
			return true
	if r < 0.30 and m.bus_stop_near(pos, 4.2):
		var fr := _road_facing(pos)
		if fr != Vector3.INF:
			begin_idle(IDLE_STYLES[m.rng.randi() % 3], m.rng.randf_range(14.0, 34.0), Util.dir_to_yaw(fr))
			activity_kind = &"bus_stop"
			idle_look_target = pos + fr * 20.0 + Vector3(0, 1.5, 0)
			p.role = &"waiter"
			return true
	if r < 0.055:
		begin_idle(IDLE_STYLES[m.rng.randi() % 3], m.rng.randf_range(4.0, 10.0), heading + m.rng.randf_range(-1.0, 1.0))
		activity_kind = &"pause"
		return true
	return false


## Unit vector (xz) pointing from the nearest road towards the buildings (window shopping direction), or INF.
func _building_facing(pos: Vector3) -> Vector3:
	var rd := WorldLayout.road_at(pos.x, pos.z, 14.0)
	if rd.is_empty():
		return Vector3.INF
	var dirv: Vector2 = rd["dir"]
	var n := Vector3(-dirv.y, 0.0, dirv.x)
	# choose the perpendicular that points away from the road centre line
	var cx := pos.x
	var cz := pos.z
	var d := float(rd["dist"])
	var probe := Vector3(cx, 0, cz) + n * 1.0
	var rd2 := WorldLayout.road_at(probe.x, probe.z, 14.0)
	if not rd2.is_empty() and float(rd2["dist"]) < d:
		n = -n
	return n


func _road_facing(pos: Vector3) -> Vector3:
	var b := _building_facing(pos)
	if b == Vector3.INF:
		return b
	return -b


func _try_jaywalk() -> void:
	var m: PedManager = mgr()
	var pg := WorldLayout.ped_graph
	if m.vehicle_threat_near(Vector3(px, 0, pz), 34.0):
		return
	var here := Vector3(px, 0, pz)
	var cand := pg.points_in_radius(here, 22.0)
	var best := -1
	var best_d := 1e9
	for i in cand:
		if pg.zone[i] != PedGraph.ZONE_SIDEWALK or i == n_cur or i == n_next:
			continue
		var q := pg.positions[i]
		var d := Util.dist_xz(q, here)
		if d < 8.0 or d > 20.0 or d > best_d:
			continue
		var mid := (q + here) * 0.5
		var rd := WorldLayout.road_at(mid.x, mid.z, 12.0)
		if rd.is_empty() or not bool(rd.get("on_road", false)):
			continue
		# roughly across the road, not along it
		var rdir: Vector2 = rd["dir"]
		var cross := Vector2(q.x - here.x, q.z - here.z).normalized()
		if absf(cross.dot(rdir)) > 0.55:
			continue
		best = i
		best_d = d
	if best < 0:
		return
	has_free = true
	free_target = PedNav.node_pos(best)
	n_next = best
	seg_a = Vector3(px, ground_y, pz)
	seg_b = free_target
	_enter(S.JAYWALK)
	speed_goal = p.walk_speed * 1.35
