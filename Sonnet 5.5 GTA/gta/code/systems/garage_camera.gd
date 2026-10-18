class_name GarageCamera
extends Camera3D
## Orbit camera of the customization garage. Process mode ALWAYS (the tree is paused while the menu is open); inputs are fed by the
## menu (mouse drag / wheel through orbit() / zoom()) and by keys polled here (A/D orbit, W/S tilt, Q/E zoom). Smooth, auto-rotates a
## little when idle (showcase), and can be pointed at a body area (focus()) when the player browses a category.
## yaw 0 = looking at the FRONT of the car (camera on the -Z side), 90 deg = right side, 180 = rear.

var target := Vector3(0, 0.7, 0)
var yaw := deg_to_rad(36.0)
var pitch := deg_to_rad(13.0)
var dist := 7.0
var min_dist := 2.0
var max_dist := 10.5
var auto_rotate := true
var keys_enabled := true
## Where the target appears on screen, as a fraction of the screen width right of centre (the menu sets it so the car sits in the free
## gap between the two side panels instead of behind one of them).
var screen_shift := 0.0
var _shift_cur := 0.0

var _g_target := Vector3(0, 0.7, 0)
var _g_yaw := deg_to_rad(36.0)
var _g_pitch := deg_to_rad(13.0)
var _g_dist := 7.0
var _idle := 0.0
var _snap := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF       # moved from _process while the tree is paused: no physics ticks to lerp with
	near = 0.08
	far = 120.0
	fov = 46.0
	cull_mask = 0xFFFFF & ~(1 << 19)            # layer 20 = reflection-only studio softboxes (see GarageStudio)
	process_priority = 150


func orbit(dx: float, dy: float) -> void:
	_g_yaw += dx * 0.0052
	_g_pitch = clampf(_g_pitch + dy * 0.0042, deg_to_rad(-6.0), deg_to_rad(62.0))
	yaw = _g_yaw if absf(dx) > 0.0 else yaw
	_idle = 0.0


func zoom(delta: float) -> void:
	_g_dist = clampf(_g_dist + delta, min_dist, max_dist)
	_idle = 0.0


func focus(new_target: Vector3, new_yaw: float, new_pitch: float, new_dist: float, keep_yaw_near: bool = true) -> void:
	_g_target = new_target
	if keep_yaw_near:
		# choose the equivalent yaw closest to the current one (no spinning the long way round)
		_g_yaw = _g_yaw + wrapf(new_yaw - _g_yaw, -PI, PI)
	else:
		_g_yaw = new_yaw
	_g_pitch = clampf(new_pitch, deg_to_rad(-6.0), deg_to_rad(62.0))
	_g_dist = clampf(new_dist, min_dist, max_dist)
	_idle = -1.0           # hold the auto-rotate off for a moment


func snap_now() -> void:
	_snap = true
	_shift_cur = screen_shift


func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	if keys_enabled and DisplayServer.get_name() != "headless":
		var kx := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
		var ky := (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
		var kz := (1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0)
		if kx != 0.0 or ky != 0.0 or kz != 0.0:
			_g_yaw += kx * 1.6 * dt
			_g_pitch = clampf(_g_pitch + ky * 0.9 * dt, deg_to_rad(-6.0), deg_to_rad(62.0))
			_g_dist = clampf(_g_dist - kz * 5.0 * dt, min_dist, max_dist)
			_idle = 0.0
	_idle += dt
	if auto_rotate and _idle > 3.0:
		_g_yaw += deg_to_rad(7.0) * dt
	if _snap:
		target = _g_target
		yaw = _g_yaw
		pitch = _g_pitch
		dist = _g_dist
		_snap = false
	else:
		target = Util.damp_v3(target, _g_target, 7.0, dt)
		yaw = Util.damp(yaw, _g_yaw, 8.0, dt)
		pitch = Util.damp(pitch, _g_pitch, 8.0, dt)
		dist = Util.damp(dist, _g_dist, 7.0, dt)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	var pos := target + off
	global_position = pos if is_inside_tree() else pos
	if (target - pos).length() > 0.01:
		look_at(target, Vector3.UP)
	_shift_cur = Util.damp(_shift_cur, screen_shift, 6.0, dt)
	if absf(_shift_cur) > 0.0005:
		var vp := get_viewport()
		var aspect := 16.0 / 9.0
		if vp != null:
			var vs := vp.get_visible_rect().size
			aspect = vs.x / maxf(vs.y, 1.0)
		var vis_w := 2.0 * dist * tan(deg_to_rad(fov) * 0.5) * aspect
		global_position -= global_transform.basis.x * (_shift_cur * vis_w)
