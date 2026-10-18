class_name CombatMover
extends RefCounted
## On-foot locomotion for combat AI (police, SWAT, gangs): direct steering with raycast obstacle avoidance, long routes along the
## WorldLayout.ped_graph (A*, there is no baked navmesh), a stuck detector, gravity + move_and_slide on the owner CharacterBody3D and
## the CharacterRig locomotion feed (so the legs match the real speed and strafing works while the body faces a target).
##
## Usage (owner = CharacterBody3D with a CharacterRig):
##   mover.set_goal(pos, speed)        # run to pos (path along sidewalks when it is far or walled off)
##   mover.face(point) / clear_face()  # keep the body turned to a point (strafe / back-pedal) instead of the move direction
##   mover.stop()                      # brake to a halt, keeps facing
##   mover.tick(dt)                    # every physics frame (dt may be larger when the owner skips frames)

const MASK_OBST := GC.L_WORLD | GC.L_VEHICLE | GC.L_PROP
const PATH_MIN := 24.0            # beyond this distance a ped-graph route is used
const PATH_REPLAN_GOAL := 9.0     # re-plan when the goal moved further than this
const STUCK_CHECK := 0.4
const MAX_EXPANSIONS := 1400

# ---- static A* scratch (shared; the ped graph has ~2k nodes) -------------------------------------------------------------
static var _gscore := PackedFloat32Array()
static var _came := PackedInt32Array()
static var _stamp := PackedInt32Array()
static var _run := 0
static var _hf := PackedFloat32Array()
static var _hn := PackedInt32Array()
static var paths_planned := 0
static var path_usec := 0
static var _frame_budget_frame := -1
static var _frame_budget := 0

var body: CharacterBody3D = null
var rig: Node = null

# ---- tunables (the owner may change them) --------------------------------------------------------------------------------
var walk_speed := 1.9
var run_speed := 5.0
var sprint_speed := 6.6
var accel := 20.0
var decel := 30.0
var turn_rate := 11.0
var gravity := 24.0
var speed_scale := 1.0            # temporary slow-down (hit flinch, reload, ...)

# ---- command state --------------------------------------------------------------------------------------------------------
var goal := Vector3.ZERO
var has_goal := false
var goal_speed := 5.0
var arrive_dist := 0.8
var arrived := true
var face_point := Vector3.INF
var face_yaw := NAN
var sprinting := false
var path := PackedVector3Array()
var path_i := 0
var stuck := false
var stuck_time := 0.0
var fatal_stuck := false          # stuck for a long time: the brain should pick another goal
var move_vel := Vector3.ZERO      # planar velocity actually applied
var distance_walked := 0.0

var _path_goal := Vector3.INF
var _avoid_off := 0.0
var _avoid_target := 0.0
var _probe_t := 0.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _side_t := 0.0
var _side_dir := 1.0
var _query := PhysicsRayQueryParameters3D.new()
var _gquery := PhysicsRayQueryParameters3D.new()
var _vy := 0.0
var _plan_cooldown := 0.0
var _last_yaw_v := 0.0


func setup(owner_body: CharacterBody3D, owner_rig: Node) -> void:
	body = owner_body
	rig = owner_rig
	_query.collision_mask = MASK_OBST
	_gquery.collision_mask = GC.L_WORLD
	_stuck_pos = body.global_position


# =====================================================================================================================
# Commands
# =====================================================================================================================
func set_goal(pos: Vector3, speed: float, arrive: float = 0.8) -> void:
	var moved := Util.dist_xz(pos, goal)
	goal = pos
	goal_speed = speed
	arrive_dist = arrive
	has_goal = true
	if Util.dist_xz(pos, body.global_position) > arrive + 0.5:
		arrived = false
	if moved > 0.01 or path.is_empty():
		_maybe_plan(moved)


func stop() -> void:
	has_goal = false
	arrived = true
	path = PackedVector3Array()
	path_i = 0
	_path_goal = Vector3.INF
	stuck = false
	stuck_time = 0.0
	fatal_stuck = false


func face(point: Vector3) -> void:
	face_point = point
	face_yaw = NAN


func face_direction(yaw: float) -> void:
	face_point = Vector3.INF
	face_yaw = yaw


func clear_face() -> void:
	face_point = Vector3.INF
	face_yaw = NAN


func is_moving() -> bool:
	return move_vel.length_squared() > 0.25


func speed_xz() -> float:
	return move_vel.length()


func remaining() -> float:
	if not has_goal:
		return 0.0
	return Util.dist_xz(goal, body.global_position)


# =====================================================================================================================
# Planning
# =====================================================================================================================
func _maybe_plan(goal_moved: float) -> void:
	var here := body.global_position
	var d := Util.dist_xz(goal, here)
	var need := false
	if d > PATH_MIN:
		need = true
	elif d > 7.0 and not _direct_clear(goal):
		need = true
	if not need:
		if not path.is_empty() and d < PATH_MIN * 0.6:
			path = PackedVector3Array()
			path_i = 0
		return
	if not path.is_empty() and _path_goal != Vector3.INF and Util.dist_xz(_path_goal, goal) < PATH_REPLAN_GOAL:
		return
	if _plan_cooldown > 0.0:
		return
	var fr := Engine.get_physics_frames()
	if _frame_budget_frame != fr:
		_frame_budget_frame = fr
		_frame_budget = 0
	if _frame_budget >= 2:
		return
	_frame_budget += 1
	var t0 := Time.get_ticks_usec()
	var p := find_path(here, goal)
	path_usec += Time.get_ticks_usec() - t0
	paths_planned += 1
	_plan_cooldown = 0.6
	if p.size() >= 2:
		path = p
		path_i = 0
		_path_goal = goal
		if path.size() >= 3 and Util.dist_xz(here, path[1]) < Util.dist_xz(path[0], path[1]):
			path_i = 1
	else:
		path = PackedVector3Array()
		path_i = 0
		_path_goal = goal


func _direct_clear(to: Vector3) -> bool:
	var from := body.global_position + Vector3(0, 0.6, 0)
	_gquery.from = from
	_gquery.to = Vector3(to.x, from.y, to.z)
	_gquery.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_ray(_gquery).is_empty()


## A* over WorldLayout.ped_graph from the node nearest to `from` to the node nearest to `to`. Returns waypoints (ends with `to`).
static func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var g: PedGraph = WorldLayout.ped_graph
	var n := g.size()
	if n == 0:
		return PackedVector3Array()
	var s := g.nearest(from, 40.0)
	var e := g.nearest(to, 40.0)
	if s < 0 or e < 0:
		return PackedVector3Array()
	if s == e:
		return PackedVector3Array([to])
	if _gscore.size() != n:
		_gscore.resize(n)
		_came.resize(n)
		_stamp.resize(n)
		_stamp.fill(0)
		_run = 0
	_run += 1
	var pos := g.positions
	var goal_p := pos[e]
	_hf.resize(0)
	_hn.resize(0)
	_gscore[s] = 0.0
	_came[s] = -1
	_stamp[s] = _run
	_heap_push(_dist2(pos[s], goal_p), s)
	var found := false
	var expansions := 0
	while _hn.size() > 0 and expansions < MAX_EXPANSIONS:
		var cur := _heap_pop()
		expansions += 1
		if cur == e:
			found = true
			break
		var cg := _gscore[cur]
		var links: PackedInt32Array = g.links[cur]
		for nb in links:
			var step := _dist2(pos[cur], pos[nb]) + absf(pos[cur].y - pos[nb].y) * 0.5
			if g.zone[nb] == PedGraph.ZONE_CROSSING:
				step += 1.5
			var ng := cg + step
			if _stamp[nb] != _run or ng < _gscore[nb]:
				_stamp[nb] = _run
				_gscore[nb] = ng
				_came[nb] = cur
				_heap_push(ng + _dist2(pos[nb], goal_p), nb)
	if not found:
		return PackedVector3Array()
	var rev: Array[int] = []
	var c := e
	var guard := 0
	while c != -1 and guard < 800:
		rev.append(c)
		c = _came[c]
		guard += 1
	var out := PackedVector3Array()
	for i in range(rev.size() - 1, -1, -1):
		out.append(pos[rev[i]])
	out.append(to)
	return out


static func _dist2(a: Vector3, b: Vector3) -> float:
	return sqrt((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z))


static func _heap_push(f: float, node: int) -> void:
	_hf.append(f)
	_hn.append(node)
	var i := _hf.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hf[p] <= _hf[i]:
			break
		var tf := _hf[p]
		var tn := _hn[p]
		_hf[p] = _hf[i]
		_hn[p] = _hn[i]
		_hf[i] = tf
		_hn[i] = tn
		i = p


static func _heap_pop() -> int:
	var top := _hn[0]
	var last := _hf.size() - 1
	_hf[0] = _hf[last]
	_hn[0] = _hn[last]
	_hf.resize(last)
	_hn.resize(last)
	var i := 0
	var size := last
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < size and _hf[l] < _hf[m]:
			m = l
		if r < size and _hf[r] < _hf[m]:
			m = r
		if m == i:
			break
		var tf := _hf[m]
		var tn := _hn[m]
		_hf[m] = _hf[i]
		_hn[m] = _hn[i]
		_hf[i] = tf
		_hn[i] = tn
		i = m
	return top


# =====================================================================================================================
# Per-frame step
# =====================================================================================================================
func tick(dt: float) -> void:
	if body == null or dt <= 0.0:
		return
	var pos := body.global_position
	_plan_cooldown = maxf(_plan_cooldown - dt, 0.0)
	var wish := Vector3.ZERO
	var target_speed := 0.0
	if has_goal:
		var wp := _next_waypoint(pos)
		var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
		var d := to.length()
		var final_leg := path.is_empty() or path_i >= path.size() - 1
		if final_leg:
			var gd := Util.dist_xz(goal, pos)
			if arrived:
				if gd > arrive_dist + 0.7:
					arrived = false
			elif gd <= arrive_dist:
				arrived = true
			if arrived:
				target_speed = 0.0
			else:
				var slow := sqrt(2.0 * decel * 0.5 * maxf(gd - arrive_dist, 0.0)) + 0.6
				target_speed = minf(goal_speed, slow)
				wish = to / maxf(d, 0.001)
		else:
			target_speed = goal_speed
			wish = to / maxf(d, 0.001)
	if wish != Vector3.ZERO and target_speed > 0.2:
		wish = _avoid(pos, wish, maxf(move_vel.length(), target_speed * 0.6), dt)
	# side-step recovery
	if _side_t > 0.0:
		_side_t -= dt
		var perp := Vector3(-wish.z, 0.0, wish.x) * _side_dir if wish != Vector3.ZERO else Vector3(1, 0, 0) * _side_dir
		wish = (wish * 0.35 + perp).normalized()
		target_speed = maxf(target_speed, 2.2)
	var want := wish * (target_speed * speed_scale)
	var rate := accel if want.length() > move_vel.length() - 0.2 else decel
	move_vel = move_vel.move_toward(want, rate * dt)
	if body.is_on_floor():
		_vy = -0.5
	else:
		_vy = maxf(_vy - gravity * dt, -40.0)
	# move_and_slide advances by ONE physics frame of velocity; the owner may tick us every 2nd / 4th frame (distance tiers), so the velocity is
	# scaled by the number of frames this step covers (the capsule sweep keeps it from tunnelling) and scaled back afterwards.
	var k := clampf(dt * float(Engine.physics_ticks_per_second), 1.0, 6.0)
	body.velocity = Vector3(move_vel.x, _vy, move_vel.z) * k
	var before := body.global_position
	body.move_and_slide()
	body.velocity /= k
	distance_walked += Util.dist_xz(before, body.global_position)
	# the real velocity may differ (walls): keep our planar state honest
	var real := Vector2(body.velocity.x, body.velocity.z)
	if real.length() < move_vel.length() * 0.6:
		move_vel = Vector3(real.x, 0.0, real.y).lerp(move_vel, 0.5) if real.length() > 0.2 else move_vel * 0.6
	_vy = body.velocity.y
	_face(dt, wish)
	_feed_rig()
	_stuck_check(dt, target_speed, wish)


func _next_waypoint(pos: Vector3) -> Vector3:
	if path.is_empty():
		return goal
	while path_i < path.size() - 1 and Util.dist_xz(path[path_i], pos) < 1.7:
		path_i += 1
	if path_i >= path.size():
		return goal
	return path[path_i] if path_i < path.size() - 1 else goal


func _avoid(pos: Vector3, dir: Vector3, speed: float, dt: float) -> Vector3:
	_probe_t -= dt
	if _probe_t <= 0.0:
		_probe_t = 0.07
		var look := clampf(speed * 0.5, 1.2, 3.0)
		if _blocked(pos, dir, look, true):
			var l := _blocked(pos, dir.rotated(Vector3.UP, 0.75), look, false)
			var r := _blocked(pos, dir.rotated(Vector3.UP, -0.75), look, false)
			if not l and (r or _avoid_target >= 0.0):
				_avoid_target = 0.9
			elif not r:
				_avoid_target = -0.9
			else:
				var l2 := _blocked(pos, dir.rotated(Vector3.UP, 1.5), look, false)
				var r2 := _blocked(pos, dir.rotated(Vector3.UP, -1.5), look, false)
				if not l2:
					_avoid_target = 1.6
				elif not r2:
					_avoid_target = -1.6
				else:
					_avoid_target = 2.4 * (1.0 if _avoid_target >= 0.0 else -1.0)
		else:
			_avoid_target = 0.0
	_avoid_off = lerpf(_avoid_off, _avoid_target, 1.0 - exp(-9.0 * dt))
	if absf(_avoid_off) < 0.02:
		return dir
	return dir.rotated(Vector3.UP, _avoid_off)


func _blocked(pos: Vector3, dir: Vector3, length: float, high_too: bool) -> bool:
	var space := body.get_world_3d().direct_space_state
	_query.exclude = [body.get_rid()]
	_query.from = pos + Vector3(0, 0.5, 0)
	_query.to = _query.from + dir * length
	var hit := space.intersect_ray(_query)
	if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.6:
		return true
	if high_too:
		_query.from = pos + Vector3(0, 1.3, 0)
		_query.to = _query.from + dir * length
		hit = space.intersect_ray(_query)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.6:
			return true
	var ahead := pos + dir * length
	if WorldLayout.built and WorldLayout.is_water(ahead.x, ahead.z) and not WorldLayout.is_water(pos.x, pos.z):
		return true
	return false


func _face(dt: float, wish: Vector3) -> void:
	var want_yaw := body.rotation.y
	var spd := move_vel.length()
	if face_point != Vector3.INF:
		var to := face_point - body.global_position
		if Vector2(to.x, to.z).length() > 0.3:
			want_yaw = Util.dir_to_yaw(to)
	elif not is_nan(face_yaw):
		want_yaw = face_yaw
	elif spd > 0.5:
		want_yaw = Util.dir_to_yaw(Vector3(move_vel.x, 0.0, move_vel.z))
	elif wish != Vector3.ZERO:
		want_yaw = Util.dir_to_yaw(wish)
	body.rotation.y = lerp_angle(body.rotation.y, want_yaw, 1.0 - exp(-turn_rate * dt))


func _feed_rig() -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var spd := move_vel.length()
	var local_dir := Vector3(0, 0, -1)
	if spd > 0.15:
		local_dir = (body.global_transform.basis.inverse() * Vector3(move_vel.x, 0.0, move_vel.z)).normalized()
	rig.set_locomotion(spd, local_dir, sprinting and spd > 5.8)


func _stuck_check(dt: float, target_speed: float, wish: Vector3) -> void:
	_stuck_t += dt
	if _stuck_t < STUCK_CHECK:
		return
	var moved := Util.dist_xz(body.global_position, _stuck_pos)
	var expected := minf(target_speed, 3.0) * _stuck_t * 0.4
	_stuck_pos = body.global_position
	_stuck_t = 0.0
	if target_speed > 1.0 and moved < expected and wish != Vector3.ZERO:
		stuck_time += STUCK_CHECK
		if stuck_time > 1.0:
			stuck = true
			_side_t = 0.7
			_side_dir = -_side_dir
			if stuck_time > 1.4 and stuck_time < 1.9:
				# force a fresh route (the goal may be behind a wall the avoidance cannot see through)
				_path_goal = Vector3.INF
				_plan_cooldown = 0.0
				_maybe_plan(99.0)
			elif stuck_time > 2.6 and stuck_time < 3.1 and path.size() > 2 and path_i < path.size() - 1:
				# the same route keeps leading into the same obstacle (a queue of cars across the crossing): cut the blocked waypoint
				path_i += 1
			elif stuck_time > 4.0 and stuck_time < 4.5:
				# give up the route: head straight for the goal for a while
				path = PackedVector3Array()
				path_i = 0
				_path_goal = goal
				_plan_cooldown = 3.0
		if stuck_time > 5.0:
			fatal_stuck = true
	else:
		stuck_time = maxf(stuck_time - STUCK_CHECK * 2.0, 0.0)
		if stuck_time <= 0.0:
			stuck = false
			fatal_stuck = false


## Instantly repositions bookkeeping after a teleport / ragdoll recovery.
func reset_after_teleport() -> void:
	move_vel = Vector3.ZERO
	_vy = 0.0
	_stuck_pos = body.global_position
	stuck_time = 0.0
	stuck = false
	fatal_stuck = false
	path = PackedVector3Array()
	path_i = 0
	_path_goal = Vector3.INF
