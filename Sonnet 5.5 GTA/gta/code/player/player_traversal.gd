class_name PlayerTraversal
extends Node
## Contextual traversal for the Player: vault over low obstacles, mantle onto ledges, climb out of water onto quays,
## ladders and the parachute. All of them are short scripted motions: collisions are suspended, the body follows a
## Catmull-Rom path and control returns at the end (Player.begin_scripted_motion / end_scripted_motion).
##
## Entry points used by Player: try_vault_or_mantle() (jump pressed on the ground), try_climb_out() (jump pressed while
## swimming), try_parachute() (jump pressed in the air), start_ladder(), tick(dt), cancel().

const MAX_VAULT_H := 1.25
const MAX_MANTLE_H := 2.3
const MAX_CLIMB_OUT_H := 3.1
const MIN_LEDGE_H := 0.52           # below this the step-up / normal jump handles it
const CHUTE_FALL_SPEED := 4.6
const CHUTE_MIN_HEIGHT := 7.0
const CHUTE_SPEED := 9.0

var player: Player = null
var kind: StringName = &""
var _t := 0.0
var _dur := 0.0
var _pts: Array[Vector3] = []
var _end_vel := Vector3.ZERO
var _face_yaw := 0.0

# ladder
var _ladder_bottom := Vector3.ZERO
var _ladder_top := Vector3.ZERO
var _ladder_dir := Vector3.FORWARD      # direction the player faces while climbing (towards the ladder)
var _ladder_u := 0.0                    # 0 bottom .. 1 top

# parachute
var _canopy: Node3D = null
var _chute_t := 0.0


func setup(p: Player) -> void:
	player = p


# ==========================================================================================================
# Ledge detection
# ==========================================================================================================
func _ray(from: Vector3, to: Vector3, mask: int = GC.L_WORLD | GC.L_PROP) -> Dictionary:
	return Util.raycast(player, from, to, mask, [player])


## Returns {} or {kind, pts, dur, yaw, exit_vel, h}.
func analyse(facing: Vector3, ray_h: float, max_h: float, allow_vault: bool) -> Dictionary:
	var f := Util.flat(facing).normalized()
	if f.length_squared() < 0.5:
		return {}
	var origin: Vector3 = player.global_position
	var hit := _ray(origin + Vector3.UP * ray_h, origin + Vector3.UP * ray_h + f * 1.1)
	if hit.is_empty():
		return {}
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.45:
		return {}
	var wall_d: float = Util.dist_xz(hit["position"], origin)
	# face the wall squarely
	var wall_f := Util.flat(-n).normalized()
	if wall_f.dot(f) < 0.35:
		return {}
	f = wall_f
	# top surface right behind the wall edge
	var probe := origin + f * (wall_d + 0.28)
	var top := _ray(probe + Vector3.UP * (max_h + 0.05), probe + Vector3.UP * (MIN_LEDGE_H - 0.2))
	if top.is_empty():
		return {}
	var top_n: Vector3 = top["normal"]
	if top_n.y < 0.75:
		return {}
	var top_y: float = (top["position"] as Vector3).y
	var h := top_y - origin.y
	if h < MIN_LEDGE_H or h > max_h:
		return {}
	# find where the top surface ends (thickness of the obstacle)
	var depth_end := -1.0
	for k in range(1, 6):
		var d := wall_d + 0.28 + k * 0.4
		var pp := origin + f * d
		var th := _ray(pp + Vector3.UP * (h + 0.35), pp + Vector3.DOWN * 0.1 + Vector3.UP * (top_y - origin.y - 0.45))
		if th.is_empty() or absf((th["position"] as Vector3).y - top_y) > 0.25:
			depth_end = d - 0.2
			break
	var result := {"yaw": Util.dir_to_yaw(f), "h": h}
	# --- vault: thin obstacle, low height, free landing on the other side
	if allow_vault and h <= MAX_VAULT_H and depth_end > 0.0 and depth_end - wall_d < 1.5:
		var land_xz := origin + f * (depth_end + 0.55)
		var g := _ray(land_xz + Vector3.UP * (h + 0.6), land_xz + Vector3.DOWN * 3.0)
		if not g.is_empty():
			var land: Vector3 = g["position"]
			if absf(land.y - origin.y) < 1.8 and _fits_at(land + Vector3.UP * 0.05):
				var a := origin + f * (wall_d - 0.15) + Vector3.UP * (h + 0.32)
				var b := origin + f * (depth_end + 0.1) + Vector3.UP * (h + 0.3)
				result["kind"] = &"vault"
				result["pts"] = [origin, a, b, land + Vector3.UP * 0.02]
				result["dur"] = 0.5 + h * 0.18
				result["exit_vel"] = f * 3.6
				return result
	# --- mantle: climb up and stand on top
	var stand := origin + f * (wall_d + 0.55)
	stand.y = top_y + 0.02
	if not _fits_at(stand):
		return {}
	var hang := origin + f * (wall_d - 0.34) + Vector3.UP * (maxf(h - 0.35, 0.3))
	var lip := origin + f * (wall_d + 0.18) + Vector3.UP * (h + 0.12)
	result["kind"] = &"mantle"
	result["pts"] = [origin, hang, lip, stand]
	result["dur"] = 0.55 + h * 0.3
	result["exit_vel"] = Vector3.ZERO
	return result


func _fits_at(foot: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.5
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.95, 0))
	params.collision_mask = GC.L_WORLD | GC.L_PROP
	params.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _facing_for_traversal() -> Vector3:
	var yaw: float = player.get_move_yaw()
	var cm: Vector2 = player.cmd_move
	if cm.length() > 0.3:
		var fwd := Util.yaw_to_dir(yaw)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		return (fwd * cm.y + right * cm.x).normalized()
	return -player.global_transform.basis.z


func try_vault_or_mantle() -> bool:
	if player.move_mode != Player.Move.GROUND or player.is_in_vehicle():
		return false
	var a := analyse(_facing_for_traversal(), 0.5, MAX_MANTLE_H, true)
	if a.is_empty():
		return false
	_begin(a)
	return true


## Vault / mantle towards an explicit flat direction (cover vault, scripted traversal). The player must be on the ground.
func try_vault_facing(dir: Vector3) -> bool:
	if player.move_mode != Player.Move.GROUND or player.is_in_vehicle():
		return false
	var a := analyse(dir, 0.5, MAX_MANTLE_H, true)
	if a.is_empty():
		return false
	_begin(a)
	return true


func try_climb_out() -> bool:
	var a := analyse(_facing_for_traversal(), 1.0, MAX_CLIMB_OUT_H, false)
	if a.is_empty():
		# water edge scan along the camera direction as a fallback
		if is_instance_valid(player.camera):
			a = analyse(Util.flat(player.camera.get_aim_forward()), 1.0, MAX_CLIMB_OUT_H, false)
		if a.is_empty():
			return false
	if a.get("kind", &"") != &"mantle":
		return false
	a["dur"] = float(a["dur"]) * 1.25
	player._exit_swim()
	_begin(a)
	kind = &"climb_out"
	return true


func try_ledge_grab() -> bool:
	return false      # NOT IMPLEMENTED (hanging from ledges mid-air)


func _begin(a: Dictionary) -> void:
	kind = a["kind"]
	_pts.clear()
	for p in a["pts"]:
		_pts.append(p)
	_dur = a["dur"]
	_t = 0.0
	_end_vel = a.get("exit_vel", Vector3.ZERO)
	_face_yaw = a["yaw"]
	player.move_mode = Player.Move.TRAVERSE
	player.crouching = false
	player.sprinting = false
	player.begin_scripted_motion(kind)
	if player.weapons != null:
		player.weapons.set_trigger(false)
	if player.rig != null:
		player.rig.play_action(&"jump")
	Sfx.play_3d(&"jump", player.global_position, -6.0, 0.9, 25.0)


# ==========================================================================================================
# Per-frame
# ==========================================================================================================
func tick(dt: float) -> void:
	match player.move_mode:
		Player.Move.TRAVERSE:
			_tick_path(dt)
		Player.Move.LADDER:
			_tick_ladder(dt)
		Player.Move.PARACHUTE:
			_tick_parachute(dt)


func _tick_path(dt: float) -> void:
	_t += dt
	var u := clampf(_t / _dur, 0.0, 1.0)
	var ue := lerpf(u, u * u * (3.0 - 2.0 * u), 0.55)
	player.global_position = _sample(ue)
	player.rotation.y = lerp_angle(player.rotation.y, _face_yaw, 1.0 - exp(-14.0 * dt))
	if u >= 1.0:
		var ev := _end_vel
		kind = &""
		player.end_scripted_motion(ev)


func _sample(u: float) -> Vector3:
	var n := _pts.size()
	if n < 2:
		return player.global_position
	var seg_f := u * float(n - 1)
	var i := mini(int(seg_f), n - 2)
	var t := seg_f - float(i)
	var p0 := _pts[maxi(i - 1, 0)]
	var p1 := _pts[i]
	var p2 := _pts[i + 1]
	var p3 := _pts[mini(i + 2, n - 1)]
	return p1.cubic_interpolate(p2, p0, p3, t)


func cancel() -> void:
	var m = player.move_mode
	if m == Player.Move.TRAVERSE:
		kind = &""
		player.end_scripted_motion()
	elif m == Player.Move.LADDER:
		_end_ladder(false)
	elif m == Player.Move.PARACHUTE:
		_end_parachute(false)


# ==========================================================================================================
# Ladders
# ==========================================================================================================
## bottom/top: world positions of the ladder foot / top rung (centre line). face_dir: direction from the player towards
## the ladder (flat). The player ends at `top + face_dir * 0.7 + up` when climbing off the top.
func start_ladder(bottom: Vector3, top: Vector3, face_dir: Vector3, start_u: float = 0.0) -> bool:
	if player.move_mode != Player.Move.GROUND and player.move_mode != Player.Move.AIR:
		return false
	_ladder_bottom = bottom
	_ladder_top = top
	_ladder_dir = Util.flat(face_dir).normalized()
	_ladder_u = clampf(start_u, 0.0, 1.0)
	player.move_mode = Player.Move.LADDER
	player.crouching = false
	player.sprinting = false
	player.begin_scripted_motion(&"ladder")
	player.rotation.y = Util.dir_to_yaw(_ladder_dir)
	player.stow_weapon()
	_apply_ladder_pos()
	return true


func _ladder_pos(u: float) -> Vector3:
	return _ladder_bottom.lerp(_ladder_top, u) - _ladder_dir * 0.38


func _apply_ladder_pos() -> void:
	player.global_position = _ladder_pos(_ladder_u)


func _tick_ladder(dt: float) -> void:
	var length := maxf(_ladder_bottom.distance_to(_ladder_top), 0.5)
	var v: float = player.cmd_move.y
	var speed := 1.7 * (1.6 if player.cmd_sprint else 1.0)
	_ladder_u = clampf(_ladder_u + v * speed * dt / length, 0.0, 1.0)
	_apply_ladder_pos()
	player.velocity = Vector3.ZERO
	if player.edge_jump:
		_end_ladder(true)
		return
	if _ladder_u >= 1.0 and v > 0.1:
		# climb off at the top
		var exit_pos := _ladder_top + _ladder_dir * 0.75 + Vector3.UP * 0.05
		_end_ladder(false)
		player.global_position = exit_pos
		player._reset_interp()
		return
	if _ladder_u <= 0.0 and v < -0.1:
		_end_ladder(false)
		player.global_position = _ladder_bottom - _ladder_dir * 0.7
		player._reset_interp()


func _end_ladder(jump_off: bool) -> void:
	player.unstow_weapon()
	var ev := Vector3.ZERO
	if jump_off:
		ev = -_ladder_dir * 3.0 + Vector3.UP * 4.0
	player.end_scripted_motion(ev)


# ==========================================================================================================
# Parachute
# ==========================================================================================================
func ground_distance() -> float:
	var from: Vector3 = player.global_position
	var hit := _ray(from, from + Vector3.DOWN * 400.0, GC.M_GROUND)
	if hit.is_empty():
		return 400.0
	return from.y - (hit["position"] as Vector3).y


func try_parachute() -> bool:
	if not (player.has_parachute or Game.cheats.get("parachute", false)):
		return false
	if player.is_on_floor() or player.velocity.y > -5.5 or player.is_swimming:
		return false
	if ground_distance() < CHUTE_MIN_HEIGHT:
		return false
	player.move_mode = Player.Move.PARACHUTE
	player.crouching = false
	player.sprinting = false
	_chute_t = 0.0
	_build_canopy()
	player.stow_weapon()
	Sfx.play_3d(&"splash", player.global_position, -10.0, 0.5, 40.0)     # no dedicated chute sound id exists; soft whoosh stand-in
	return true


func _tick_parachute(dt: float) -> void:
	_chute_t += dt
	var wish: Vector3 = player._compute_wish()
	var yaw: float = player.get_move_yaw()
	var fwd := Util.yaw_to_dir(yaw)
	# steering: camera forward drift, A/D carve, S brakes
	var target_h := fwd * CHUTE_SPEED * 0.55 + wish * CHUTE_SPEED * 0.45
	if player.cmd_move.y < -0.1:
		target_h *= 0.45
	var h := Vector3(player.velocity.x, 0.0, player.velocity.z).move_toward(target_h, 7.0 * dt)
	var inflate := clampf(_chute_t / 0.8, 0.0, 1.0)
	var vy := move_toward(player.velocity.y, -CHUTE_FALL_SPEED, (9.0 + 14.0 * inflate) * dt)
	player.velocity = Vector3(h.x, vy, h.z)
	if h.length() > 0.5:
		player.rotation.y = lerp_angle(player.rotation.y, Util.dir_to_yaw(h), 1.0 - exp(-4.0 * dt))
	player.floor_snap_length = 0.0
	player.move_and_slide()
	player._fall_peak_y = player.global_position.y       # no fall damage while under canopy
	if is_instance_valid(_canopy):
		_canopy.scale = Vector3.ONE * lerpf(0.25, 1.0, inflate)
		_canopy.rotation.z = clampf(-player.cmd_move.x * 0.22, -0.3, 0.3)
	player._sample_water()
	var under_water: bool = not is_nan(player.water_surface_y) and player.global_position.y < player.water_surface_y - 0.4
	if player.is_on_floor() or under_water or (player.edge_jump and _chute_t > 0.6):
		_end_parachute(true)


func _end_parachute(landed: bool) -> void:
	if is_instance_valid(_canopy):
		_canopy.queue_free()
	_canopy = null
	player.move_mode = Player.Move.AIR
	player._fall_peak_y = player.global_position.y
	player.velocity.x *= 0.4
	player.velocity.z *= 0.4
	player.unstow_weapon()
	if landed and player.rig != null:
		player.rig.play_action(&"land")
	player._land_slow = 0.3


func _build_canopy() -> void:
	if is_instance_valid(_canopy):
		_canopy.queue_free()
	_canopy = Node3D.new()
	_canopy.name = "Canopy"
	var top := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.4
	sm.height = 2.4
	sm.is_hemisphere = true
	sm.radial_segments = 14
	sm.rings = 6
	top.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ff3d9a")
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	top.material_override = mat
	top.scale = Vector3(1.0, 0.55, 1.35)
	top.position = Vector3(0, 3.4, 0)
	_canopy.add_child(top)
	# suspension lines
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("#eaf2f7")
	for corner in [Vector3(1.9, 3.4, 0.0), Vector3(-1.9, 3.4, 0.0), Vector3(0.0, 3.4, 2.4), Vector3(0.0, 3.4, -2.4)]:
		var line := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		var a: Vector3 = corner
		var b := Vector3(0, 1.45, 0)
		cm.height = a.distance_to(b)
		line.mesh = cm
		line.material_override = lm
		line.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), (a + b) * 0.5)
		_canopy.add_child(line)
	if player.visual != null:
		player.visual.add_child(_canopy)
	else:
		player.add_child(_canopy)
