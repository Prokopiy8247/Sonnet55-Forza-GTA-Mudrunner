class_name PlayerCover
extends Node
## Contextual wall / low-cover / vehicle-cover system for the Player (Q toggles).
##  * Finds a wall, low obstacle or vehicle in front of the camera (ray fan) and snaps the body against it; if nothing is in front, the
##    SAME CoverFinder the police and gang AI use (ai/cover_finder.gd) looks for a shielded spot within a few metres and the player
##    glides there. Occupied spots are published with CoverFinder.claim() so AI units avoid the player's cover and vice versa.
##  * A / D slide along the cover. At the end of a wall that continues round an outside corner the player wraps round it (corner transition).
##  * Stance: wall > player height = high cover (back to the wall), 0.7 .. 1.3 m obstacle or any vehicle up to 1.6 m = low cover (crouched,
##    peeks over the top).
##  * Hold RMB to aim out: low cover = lean over the top (accurate), high cover = step out to the nearest edge on the camera's shoulder side
##    (no edge within reach = blind aim). LMB without aim = blind fire: the aim ray is jittered (BLIND_JITTER_DEG) so accuracy is poor.
##  * Leaves on Q, sprint, jump (vaults low cover towards the obstacle), pressing back for a moment, a moving cover vehicle or a long drop.

const FAN_ANGLES := [0.0, -0.45, 0.45, -0.9, 0.9, -1.4, 1.4]
const CHECK_DIST := 1.7
const SLIDE_SPEED := 2.3
const LOW_MIN := 0.7
const LOW_MAX := 1.3
const VEHICLE_LOW_MAX := 1.62
const MASK := GC.L_WORLD | GC.L_PROP | GC.L_VEHICLE
const BLIND_JITTER_DEG := 3.4
const ASSIST_RADIUS := 4.6
const PEEK_REACH := 1.25
const CORNER_HOLD := 0.16
const CORNER_TIME := 0.62

var player: Player = null
var active := false
var normal := Vector3.ZERO          # wall normal (points from the wall towards the player)
var wall_point := Vector3.ZERO
var low := false
var peek := 0.0                     # -1 left .. +1 right, fed to CharacterRig.set_cover_peek
var blind_firing := false           # firing without an aimed peek (poor accuracy)
var aim_exposed := false            # aiming out: stepped out to an edge / leaning over the top
var cover_body: Node3D = null       # obstacle (vehicle / prop) the cover is attached to, null for static world
var transitioning := false          # corner wrap / assist glide in progress

var _back_time := 0.0
var _away_armed := true
var _tangent := Vector3.RIGHT
var _lp := Vector3.ZERO             # cover point in cover_body space (moving covers)
var _ln := Vector3.ZERO
var _corner_t := 0.0
var _rest_t := NAN                  # tangent coordinate to return to after leaning out
var _path: Array[Vector3] = []
var _path_t := 0.0
var _path_dur := 0.5
var _path_face := 0.0
var _path_next: Dictionary = {}     # cover state to commit when the path ends
var _vehicle_speed_limit := 1.3


func setup(p: Player) -> void:
	player = p


func get_stance() -> StringName:
	return &"cover_low" if low else &"cover_high"


func toggle() -> void:
	if active:
		leave(false)
	else:
		try_enter()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return Util.raycast(player, from, to, MASK, [player])


func _vehicle_of(n: Object) -> Node3D:
	var node := n as Node
	var depth := 0
	while node != null and depth < 6:
		if node.is_in_group(GC.G_VEHICLE) and node is Node3D:
			return node as Node3D
		node = node.get_parent()
		depth += 1
	return null


func _can_enter() -> bool:
	if player == null or player.is_dead or player.is_in_vehicle() or player.is_swimming:
		return false
	return player.move_mode == Player.Move.GROUND


# ==========================================================================================================
# Enter
# ==========================================================================================================
func try_enter() -> bool:
	if not _can_enter():
		return false
	var origin: Vector3 = player.global_position
	var base_yaw: float = player.get_move_yaw()
	var best := {}
	var best_d := INF
	for a in FAN_ANGLES:
		var dir := Util.yaw_to_dir(base_yaw + a)
		var lo := _ray(origin + Vector3.UP * 0.55, origin + Vector3.UP * 0.55 + dir * CHECK_DIST)
		if lo.is_empty():
			continue
		var n: Vector3 = lo["normal"]
		if absf(n.y) > 0.4:
			continue
		var d := origin.distance_to(lo["position"]) + absf(a) * 0.35
		if d >= best_d:
			continue
		best_d = d
		best = lo
	if not best.is_empty():
		var info := _classify(best, origin)
		if not info.is_empty():
			_begin(info)
			return true
	return _assist_enter()


## Height class + geometry of the hit face. Returns {} when the obstacle is unusable (too low / too thin).
func _classify(hit: Dictionary, origin: Vector3) -> Dictionary:
	var n2: Vector3 = Util.flat(hit["normal"]).normalized()
	if n2.length_squared() < 0.5:
		return {}
	var hit_pos: Vector3 = hit["position"]
	var body := _vehicle_of(hit.get("collider", null))
	var probe := hit_pos - n2 * 0.25
	var top := _ray(probe + Vector3.UP * 2.4, probe + Vector3.DOWN * 0.1)
	var h := 9.0
	if not top.is_empty():
		h = (top["position"] as Vector3).y - origin.y
	var cover_low := false
	if body != null:
		if h < LOW_MIN:
			return {}
		cover_low = h <= VEHICLE_LOW_MAX
	else:
		var hi_start := Vector3(hit_pos.x, origin.y + 1.45, hit_pos.z) + n2 * 0.5
		var hi := _ray(hi_start, hi_start - n2 * 1.1)
		cover_low = hi.is_empty()
		if cover_low and (top.is_empty() or h < LOW_MIN or h > LOW_MAX):
			return {}
	# need a few tenths of wall to either side
	var tang := n2.cross(Vector3.UP).normalized()
	var side_ok := 0
	for s in [-0.55, 0.55]:
		var q: Vector3 = hit_pos + tang * s + n2 * 0.1
		var chk := _ray(q + n2 * 0.3, q - n2 * 0.5)
		if not chk.is_empty():
			side_ok += 1
	if side_ok == 0:
		return {}
	return {"normal": n2, "point": hit_pos, "low": cover_low, "body": body, "tangent": tang}


func _begin(info: Dictionary) -> void:
	normal = info["normal"]
	wall_point = info["point"]
	low = info["low"]
	_tangent = info["tangent"]
	cover_body = info.get("body", null)
	if cover_body != null:
		_lp = cover_body.to_local(wall_point)
		_ln = cover_body.global_transform.basis.inverse() * normal
	active = true
	transitioning = false
	_back_time = 0.0
	_corner_t = 0.0
	_rest_t = NAN
	peek = 0.0
	aim_exposed = false
	blind_firing = false
	player.move_mode = Player.Move.COVER
	player.crouching = low
	player.sprinting = false
	if low:
		player._cur_height = Player.CROUCH_HEIGHT
		player._apply_capsule(Player.CROUCH_HEIGHT)
	CoverFinder.claim(player.get_instance_id(), player.global_position)
	Sfx.play_3d(&"step_concrete", player.global_position, -10.0, 0.8, 15.0)


## Nothing in front: borrow the AI's cover probe. A shielded spot within ASSIST_RADIUS (relative to the nearest hostile / the aim point)
## is entered by a short glide.
func _assist_enter() -> bool:
	var threat := _threat_point()
	var res: Array = CoverFinder.find(player, player.global_position, threat, {
		"radius": ASSIST_RADIUS, "range": 90.0, "min_threat_dist": 3.0, "max": 1, "exclude": [player],
		"id": player.get_instance_id(), "prefer_min": 2.0, "prefer_max": 70.0})
	if res.is_empty():
		return false
	var c: Dictionary = res[0]
	var spot: Vector3 = c["pos"]
	var n2: Vector3 = c["normal"]
	var body := _vehicle_of(c.get("obstacle", null))
	var info := {"normal": n2, "point": spot - n2 * (Player.RADIUS + 0.06), "low": c["kind"] == &"low", "body": body,
		"tangent": n2.cross(Vector3.UP).normalized()}
	# the glide ends at the spot, then the cover is committed
	var start := player.global_position
	spot.y = start.y
	_start_path([start, start.lerp(spot, 0.5), spot], clampf(start.distance_to(spot) / 5.2, 0.25, 1.0), Util.dir_to_yaw(n2), info)
	return true


func _threat_point() -> Vector3:
	var best: Node3D = null
	var best_d := 55.0 * 55.0
	var pp := player.global_position
	for grp in [GC.G_HOSTILE, GC.G_POLICE]:
		for n in get_tree().get_nodes_in_group(grp):
			var n3 := n as Node3D
			if n3 == null or not (n3 is CharacterBody3D) or n3.get("is_dead") == true:
				continue
			if grp == GC.G_POLICE and Game.wanted_level <= 0:
				continue
			var d := n3.global_position.distance_squared_to(pp)
			if d < best_d:
				best_d = d
				best = n3
	if best != null:
		return best.global_position
	var f: Vector3 = Util.yaw_to_dir(player.get_move_yaw())
	if is_instance_valid(player.camera):
		f = Util.flat(player.camera.get_aim_forward()).normalized()
	return pp + f * 25.0


# ==========================================================================================================
# Leave
# ==========================================================================================================
## Leave cover. instant=true skips the stand-up check (used when forced out).
func leave(instant: bool) -> void:
	if not active:
		return
	active = false
	transitioning = false
	_path.clear()
	if player.move_mode == Player.Move.COVER:
		player.move_mode = Player.Move.GROUND
	if low:
		player.crouching = true     # keep crouch; the player stands up with the next crouch toggle / sprint
	player.aim_jitter_deg = 0.0
	blind_firing = false
	aim_exposed = false
	peek = 0.0
	cover_body = null
	CoverFinder.release(player.get_instance_id())
	if instant:
		player.crouching = false


# ==========================================================================================================
# Per-tick
# ==========================================================================================================
func tick(dt: float) -> void:
	if not active:
		player.move_mode = Player.Move.GROUND
		return
	if not _path.is_empty():
		_tick_path(dt)
		return
	if not _refresh_dynamic():
		return
	# exits
	if player.cmd_sprint and player.cmd_move.length() > 0.5:
		leave(false)
		return
	if player.edge_jump:
		_jump_out()
		return
	# movement along the wall
	var yaw: float = player.get_move_yaw()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Util.yaw_to_dir(yaw)
	# input split: lateral part moves along the wall, pushing away from the wall (back) leaves
	var lateral: float = player.cmd_move.x * right.dot(_tangent) + player.cmd_move.y * fwd.dot(_tangent)
	var away: float = player.cmd_move.x * right.dot(normal) + player.cmd_move.y * fwd.dot(normal)
	if away < 0.3:
		_away_armed = true                      # after a corner wrap / glide the held key must be released before 'back' leaves
	if away > 0.6 and absf(lateral) < 0.4 and _away_armed:
		_back_time += dt
		if _back_time > 0.35:
			leave(false)
			return
	else:
		_back_time = 0.0
	var wants_aim: bool = player.cmd_aim
	var firing: bool = player.cmd_fire and player._weapon_is_ranged()
	var side_t := signf(right.dot(_tangent))
	if side_t == 0.0:
		side_t = 1.0
	var shoulder: float = player.camera.shoulder_side if is_instance_valid(player.camera) else 1.0
	var peek_dir := _tangent * side_t * shoulder          # world direction of the peek side
	var speed := SLIDE_SPEED * (0.6 if wants_aim else 1.0)
	var vel := Vector3.ZERO
	var peek_target := 0.0
	var aimed_ok := false
	if wants_aim:
		if low:
			aimed_ok = true
			peek_target = shoulder
		else:
			var e := _edge_distance(peek_dir)
			if e <= PEEK_REACH:
				aimed_ok = true
				peek_target = shoulder
				if is_nan(_rest_t):
					_rest_t = _t_coord()
				var goal_t := _rest_t + (e - 0.1) * signf(peek_dir.dot(_tangent))
				var dt_off := goal_t - _t_coord()
				vel += _tangent * clampf(dt_off * 7.0, -3.0, 3.0)
	else:
		if not is_nan(_rest_t):                                   # lean back to where we were
			var back := _rest_t - _t_coord()
			if absf(back) < 0.04:
				_rest_t = NAN
			else:
				vel += _tangent * clampf(back * 7.0, -3.0, 3.0)
		else:
			vel += _tangent * clampf(lateral, -1.0, 1.0) * speed
	player.aiming = wants_aim and aimed_ok
	aim_exposed = aimed_ok and wants_aim
	blind_firing = firing and not (wants_aim and aimed_ok)
	player.aim_jitter_deg = BLIND_JITTER_DEG if blind_firing else (BLIND_JITTER_DEG * 0.55 if (wants_aim and not aimed_ok and firing) else 0.0)
	peek = Util.damp(peek, peek_target, 10.0, dt)
	# keep a fixed distance from the wall
	var to_wall := normal.dot(player.global_position - wall_point)
	var desired := Player.RADIUS + 0.06
	vel += normal * clampf((desired - to_wall) * 6.0, -1.5, 1.5)
	# corner / end of cover: probe ahead along the wall
	var slide_v := vel.dot(_tangent)
	if absf(slide_v) > 0.1 and not aim_exposed:
		var step_dir := _tangent * signf(slide_v)
		var probe: Vector3 = player.global_position + step_dir * 0.45 + Vector3.UP * 0.55
		var chk := _ray(probe + normal * 0.4, probe - normal * 0.6)
		if chk.is_empty():
			vel = normal * clampf((desired - to_wall) * 6.0, -1.5, 1.5)     # end of the wall: stop
			_corner_t += dt
			if _corner_t > CORNER_HOLD and _try_corner(step_dir):
				return
		else:
			_corner_t = 0.0
	else:
		_corner_t = 0.0
	player.velocity.x = vel.x
	player.velocity.z = vel.z
	player.velocity.y = maxf(player.velocity.y - Player.GRAVITY * dt, -20.0)
	# facing: back to the wall (face along the normal) unless aiming out / firing
	var face_yaw := Util.dir_to_yaw(normal)
	if (wants_aim and aimed_ok) or firing:
		face_yaw = yaw
	player.rotation.y = lerp_angle(player.rotation.y, face_yaw, 1.0 - exp(-16.0 * dt))
	player.move_and_slide()
	player._was_on_floor = player.is_on_floor()
	player._fall_peak_y = player.global_position.y
	if not player.is_on_floor() and player.global_position.y < wall_point.y - 1.5:
		leave(true)


## Coordinate of the player along the wall tangent (relative to the cover point).
func _t_coord() -> float:
	return (player.global_position - wall_point).dot(_tangent)


## Distance along `dir` (flat) to the end of the cover, or INF when it continues beyond PEEK_REACH + a margin.
func _edge_distance(dir: Vector3) -> float:
	var d := Util.flat(dir).normalized()
	var pos := player.global_position + Vector3.UP * 0.55
	var step := 0.25
	var k := 1
	while k * step <= PEEK_REACH + 0.5:
		var probe := pos + d * (k * step)
		var chk := _ray(probe + normal * 0.4, probe - normal * 0.6)
		if chk.is_empty():
			return k * step - step * 0.5
		k += 1
	return INF


## Moving covers (vehicles / pushed props): follow them, leave when a vehicle drives off.
func _refresh_dynamic() -> bool:
	if cover_body == null:
		return true
	if not is_instance_valid(cover_body):
		leave(false)
		return false
	var lv = cover_body.get("linear_velocity")
	if lv is Vector3 and (lv as Vector3).length() > _vehicle_speed_limit:
		leave(false)
		return false
	if cover_body.get("is_destroyed") == true:
		leave(false)
		return false
	var wp := cover_body.to_global(_lp)
	wall_point = Vector3(wp.x, wall_point.y, wp.z)
	var nn := Util.flat(cover_body.global_transform.basis * _ln).normalized()
	if nn.length_squared() > 0.5:
		normal = nn
		_tangent = normal.cross(Vector3.UP).normalized()
	return true


## Jump: low cover is vaulted towards the obstacle; otherwise just leave.
func _jump_out() -> void:
	var toward := -normal
	var was_low := low
	leave(false)
	if was_low and player.traversal != null:
		player.rotation.y = Util.dir_to_yaw(toward)
		if player.traversal.try_vault_facing(toward):
			return
	player.velocity += normal * 2.0


# ==========================================================================================================
# Corner transition / glides
# ==========================================================================================================
## At the end of a wall that continues round an outside corner (a second wall facing the direction of travel), wrap round the corner and
## stay in cover against the new wall. Returns true when the wrap started.
func _try_corner(step_dir: Vector3) -> bool:
	var pos := player.global_position
	var rel := pos - wall_point
	var p_front := pos - normal * rel.dot(normal)                 # on the wall plane, at the player's tangent position
	p_front.y = pos.y
	var start := p_front + step_dir * 1.15 - normal * 0.15 + Vector3.UP * 0.55
	var hit := _ray(start, start - step_dir * 1.5)
	if hit.is_empty():
		return false
	var n2: Vector3 = Util.flat(hit["normal"]).normalized()
	if n2.dot(step_dir) < 0.8 or absf((hit["normal"] as Vector3).y) > 0.4:
		return false
	var h2: Vector3 = hit["position"]
	# the new wall has to be real: at least ~0.9 m of face going back behind the old wall plane
	var back_probe := h2 - normal * 0.9 + n2 * 0.3
	if _ray(back_probe, back_probe - n2 * 0.6).is_empty():
		return false
	# vertical class of the new wall
	var info := _classify(hit, pos)
	if info.is_empty():
		return false
	var r := Player.RADIUS + 0.06
	var out_pt := p_front + step_dir * ((h2 - p_front).dot(step_dir) + r) + normal * (Player.RADIUS + 0.06)
	var end_pt := h2 + n2 * r - normal * 0.26
	out_pt.y = pos.y
	end_pt.y = pos.y
	_start_path([pos, out_pt, end_pt], CORNER_TIME, Util.dir_to_yaw(n2), info)
	return true


func _start_path(pts: Array[Vector3], dur: float, face: float, next: Dictionary) -> void:
	_path = pts
	_path_t = 0.0
	_path_dur = maxf(dur, 0.1)
	_path_face = face
	_path_next = next
	transitioning = true
	active = true
	player.move_mode = Player.Move.COVER
	player.velocity = Vector3.ZERO
	CoverFinder.claim(player.get_instance_id(), pts[pts.size() - 1])


func _tick_path(dt: float) -> void:
	_path_t += dt
	var u := clampf(_path_t / _path_dur, 0.0, 1.0)
	var ue := u * u * (3.0 - 2.0 * u)
	player.global_position = _sample_path(ue)
	player.velocity = Vector3.ZERO
	player.rotation.y = lerp_angle(player.rotation.y, _path_face, 1.0 - exp(-14.0 * dt))
	player._fall_peak_y = player.global_position.y
	if player.cmd_sprint and player.cmd_move.length() > 0.5 and u > 0.2:
		_path.clear()
		leave(false)
		return
	if u >= 1.0:
		_path.clear()
		var nx := _path_next
		_path_next = {}
		transitioning = false
		if not nx.is_empty():
			_begin(nx)
			_away_armed = false
			player.rotation.y = _path_face


func _sample_path(u: float) -> Vector3:
	var n := _path.size()
	if n < 2:
		return player.global_position
	var seg_f := u * float(n - 1)
	var i := mini(int(seg_f), n - 2)
	var t := seg_f - float(i)
	var p0 := _path[maxi(i - 1, 0)]
	var p1 := _path[i]
	var p2 := _path[i + 1]
	var p3 := _path[mini(i + 2, n - 1)]
	return p1.cubic_interpolate(p2, p0, p3, t)


# ==========================================================================================================
# Shared with AI
# ==========================================================================================================
## The same probe the police / gang AI use, for scripts and for the player (see ai/cover_finder.gd for the entry format).
static func find_points(node: Node3D, origin: Vector3, threat: Vector3, opts: Dictionary = {}) -> Array:
	return CoverFinder.find(node, origin, threat, opts)
