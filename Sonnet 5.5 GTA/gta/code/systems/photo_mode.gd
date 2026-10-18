class_name PhotoMode
extends Node
## Photo mode (F3 / phone camera). Pauses the game (tree paused, this node and its UI run in PROCESS_MODE_ALWAYS, so the world, the clock and
## the weather are held), hides the HUD, and gives a free orbit camera: LMB drag = orbit, MMB / Shift+LMB drag = pan, wheel = dolly,
## W A S D / Q E = fly, Z / C = roll, plus a control panel (FOV, roll, depth of field + focus distance, filter preset: neutral / vivid /
## noir / sunset). Enter / Space / F12 / the button takes the photo: user://photos/photo_<timestamp>.png + toast with the path +
## Events.photo_taken. F3 / Esc leaves; everything is restored (camera, HUD, mouse, pause, player input).

signal entered()
signal exited()
signal photo_saved(path: String)

const FILTERS: Array[StringName] = [&"neutral", &"vivid", &"noir", &"sunset"]

var active := false
var cam: Camera3D = null
var filter: StringName = &"neutral"
var fov_deg := 60.0
var roll_deg := 0.0
var dof_amount := 0.0
var focus_dist := 8.0
var auto_focus := true
var photos_taken := 0
var last_path := ""

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _flash: ColorRect = null
var _thumb: TextureRect = null
var _thumb_t := 0.0
var _env: Environment = null
var _attrs: CameraAttributesPractical = null
var _orig_adjust: Dictionary = {}
var _pivot := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _dist := 6.0
var _prev_cam: Camera3D = null
var _was_paused := false
var _hud_hidden_before := false
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _drag_mode := 0                 # 1 orbit, 2 pan
var _panel_visible := true
var _busy := false
var _sliders: Dictionary = {}
var _info: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func can_enter() -> bool:
	if active or _busy:
		return false
	var p = Game.player
	if not is_instance_valid(p) or bool(p.get("is_dead")):
		return false
	var gs = Game.sys(&"garage")
	if gs != null and gs.session != null:
		return false
	if Game.ui != null and (Game.ui.is_menu_open() or (Game.ui.death != null and Game.ui.death.is_active())):
		return false
	return true


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"photo_mode") and not event.is_echo():
		if active:
			exit()
		elif can_enter():
			enter()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.physical_keycode:
			KEY_ESCAPE:
				exit()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_F12:
				take_photo()
				get_viewport().set_input_as_handled()
			KEY_TAB, KEY_H:
				_set_panel_visible(not _panel_visible)
				get_viewport().set_input_as_handled()
			KEY_R:
				_reset_view()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and not _over_panel(mb.position):
			_dist = clampf(_dist * 0.92, 0.6, 60.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and not _over_panel(mb.position):
			_dist = clampf(_dist / 0.92, 0.6, 60.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and not _over_panel(mb.position):
				_drag_mode = 2 if (mb.button_index == MOUSE_BUTTON_MIDDLE or mb.shift_pressed) else 1
			elif not mb.pressed:
				_drag_mode = 0
	elif event is InputEventMouseMotion and _drag_mode != 0:
		var rel := (event as InputEventMouseMotion).relative
		if _drag_mode == 1:
			_yaw -= rel.x * 0.0045
			_pitch = clampf(_pitch + rel.y * 0.0045, -1.45, 1.45)
		else:
			var b := cam.global_transform.basis
			_pivot += (-b.x * rel.x + b.y * rel.y) * 0.0022 * _dist


func _over_panel(pos: Vector2) -> bool:
	return _panel != null and _panel.visible and _panel.get_global_rect().has_point(pos)


# =====================================================================================================
# Enter / exit
# =====================================================================================================
func enter() -> void:
	if active:
		return
	active = true
	var vp := get_viewport()
	_prev_cam = vp.get_camera_3d()
	var ui = Game.ui
	_was_paused = get_tree().paused
	if is_instance_valid(Game.player):
		Game.player.input_locked = true
	if ui != null:
		_hud_hidden_before = false
		ui.set_hud_visible(false)
	Game.cheats["photo_mode"] = true
	_prev_mouse = Input.mouse_mode
	# camera: start where the gameplay camera is, orbiting a point in front of it (the player when visible)
	cam = Camera3D.new()
	cam.name = "PhotoCamera"
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF       # driven from _process while the tree is paused
	cam.near = 0.05
	cam.far = 1500.0
	add_child(cam)
	var src: Camera3D = _prev_cam if _prev_cam != null else Game.gameplay_camera
	if src != null:
		cam.global_transform = src.global_transform
		fov_deg = src.fov
	else:
		cam.global_position = Game.get_player_position() + Vector3(0, 2, 4)
	var focus_pt := Game.get_player_position() + Vector3(0, 1.1, 0)
	var to_focus := focus_pt - cam.global_position
	_dist = clampf(to_focus.length(), 2.5, 14.0)
	var fwd := -cam.global_transform.basis.z
	_pivot = cam.global_position + fwd * _dist
	var d := (cam.global_position - _pivot).normalized()
	_yaw = atan2(d.x, d.z)
	_pitch = asin(clampf(d.y, -1.0, 1.0))
	roll_deg = 0.0
	dof_amount = 0.0
	filter = &"neutral"
	_setup_environment()
	cam.fov = fov_deg
	cam.make_current()
	_apply_camera(0.0)
	_build_ui()
	Game.set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	entered.emit()
	if Sfx != null:
		Sfx.play_ui(&"ui_notify", -8.0)


func exit() -> void:
	if not active:
		return
	active = false
	_drag_mode = 0
	var ui = Game.ui
	Game.cheats["photo_mode"] = false
	if is_instance_valid(cam):
		cam.queue_free()
	cam = null
	if _layer != null:
		_layer.queue_free()
		_layer = null
	_panel = null
	_env = null
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	elif Game.gameplay_camera != null and is_instance_valid(Game.gameplay_camera):
		Game.gameplay_camera.make_current()
	if ui != null:
		ui.set_hud_visible(true)
	Game.set_paused(_was_paused)
	if is_instance_valid(Game.player):
		Game.player.input_locked = false
	if ui != null and ui.has_method("_apply_mouse"):
		ui._apply_mouse()
	else:
		Input.mouse_mode = _prev_mouse
	exited.emit()


# =====================================================================================================
# Camera / environment
# =====================================================================================================
func _setup_environment() -> void:
	var es = Game.sys(&"environment")
	var base_env: Environment = null
	if es != null and es.has_method("get_environment"):
		base_env = es.get_environment()
	if base_env == null:
		var we := get_viewport().find_world_3d()
		if we != null:
			base_env = we.environment
	_attrs = CameraAttributesPractical.new()
	if es != null and es.get("world_environment") != null:
		var wea = es.world_environment.camera_attributes if es.world_environment is WorldEnvironment else null
		if wea is CameraAttributesPractical:
			_attrs.exposure_multiplier = wea.exposure_multiplier
			_attrs.auto_exposure_enabled = wea.auto_exposure_enabled
	if base_env != null:
		_env = base_env.duplicate()
		_orig_adjust = {"enabled": _env.adjustment_enabled, "sat": _env.adjustment_saturation, "con": _env.adjustment_contrast,
			"bri": _env.adjustment_brightness, "lut": _env.adjustment_color_correction}
		cam.environment = _env
	cam.attributes = _attrs
	_apply_filter()
	_apply_dof()


func _apply_filter() -> void:
	if _env == null:
		return
	match filter:
		&"vivid":
			_env.adjustment_enabled = true
			_env.adjustment_saturation = 1.5
			_env.adjustment_contrast = 1.12
			_env.adjustment_brightness = 1.02
			_env.adjustment_color_correction = null
		&"noir":
			_env.adjustment_enabled = true
			_env.adjustment_saturation = 0.0
			_env.adjustment_contrast = 1.32
			_env.adjustment_brightness = 0.97
			_env.adjustment_color_correction = null
		&"sunset":
			_env.adjustment_enabled = true
			_env.adjustment_saturation = 1.22
			_env.adjustment_contrast = 1.08
			_env.adjustment_brightness = 1.0
			_env.adjustment_color_correction = _sunset_lut()
		_:
			_env.adjustment_enabled = bool(_orig_adjust.get("enabled", false))
			_env.adjustment_saturation = float(_orig_adjust.get("sat", 1.0))
			_env.adjustment_contrast = float(_orig_adjust.get("con", 1.0))
			_env.adjustment_brightness = float(_orig_adjust.get("bri", 1.0))
			_env.adjustment_color_correction = _orig_adjust.get("lut", null)


static var _lut: GradientTexture1D = null


static func _sunset_lut() -> GradientTexture1D:
	if _lut == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.02, 0.0, 0.08), Color(0.62, 0.3, 0.38), Color(1.0, 0.72, 0.5), Color(1.0, 0.96, 0.86)])
		g.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
		_lut = GradientTexture1D.new()
		_lut.gradient = g
		_lut.width = 64
	return _lut


func _apply_dof() -> void:
	if _attrs == null:
		return
	var on := dof_amount > 0.02
	_attrs.dof_blur_far_enabled = on
	_attrs.dof_blur_near_enabled = on
	_attrs.dof_blur_far_distance = focus_dist
	_attrs.dof_blur_far_transition = maxf(focus_dist * 0.7, 3.0)
	_attrs.dof_blur_near_distance = maxf(focus_dist * 0.55, 0.3)
	_attrs.dof_blur_near_transition = maxf(focus_dist * 0.4, 1.0)
	_attrs.dof_blur_amount = dof_amount * 0.22


func _reset_view() -> void:
	roll_deg = 0.0
	fov_deg = 60.0
	dof_amount = 0.0
	filter = &"neutral"
	_apply_filter()
	_apply_dof()
	_sync_sliders()


func _apply_camera(dt: float) -> void:
	if cam == null:
		return
	# fly: WASD moves the pivot along the view plane, Q / E down / up
	if dt > 0.0 and DisplayServer.get_name() != "headless":
		var b := cam.global_transform.basis
		var fwd := -b.z
		var mv := Vector3.ZERO
		mv += fwd * ((1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0))
		mv += b.x * ((1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0))
		mv += Vector3.UP * ((1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0))
		if mv != Vector3.ZERO:
			_pivot += mv.normalized() * (6.0 if not Input.is_physical_key_pressed(KEY_SHIFT) else 18.0) * dt
		var rr := (1.0 if Input.is_physical_key_pressed(KEY_C) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_Z) else 0.0)
		if rr != 0.0:
			roll_deg = clampf(roll_deg + rr * 40.0 * dt, -60.0, 60.0)
			_sync_sliders()
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	cam.global_position = _pivot + off
	cam.look_at(_pivot, Vector3.UP)
	if roll_deg != 0.0:
		cam.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(roll_deg))
	cam.fov = fov_deg
	if auto_focus:
		focus_dist = maxf(_dist, 0.5)
		_apply_dof()


func _process(dt: float) -> void:
	if not active:
		return
	_apply_camera(minf(dt, 0.1))
	if _flash != null and _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - dt * 3.0, 0.0)
	if _thumb != null and _thumb.visible:
		_thumb_t -= dt
		if _thumb_t <= 0.0:
			_thumb.visible = false


# =====================================================================================================
# Photo
# =====================================================================================================
## Saves the current frame. Returns the absolute path ("" on failure). Headless runs have no renderer: a tiny placeholder PNG is written
## so the flow (file, toast, event) can be tested; real runs save the viewport image.
func take_photo() -> String:
	if _busy:
		return ""
	_busy = true
	var panel_was := _panel_visible
	_set_panel_visible(false)
	var hidden_thumb := false
	if _thumb != null:
		hidden_thumb = _thumb.visible
		_thumb.visible = false
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	var img: Image = null
	var placeholder := false
	if DisplayServer.get_name() != "headless":
		img = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.1, 0.1, 0.12))
		placeholder = true
	DirAccess.make_dir_recursive_absolute("user://photos")
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var rel := "user://photos/photo_%s_%d.png" % [ts, Time.get_ticks_msec() % 1000]
	var err := img.save_png(rel)
	var path := ProjectSettings.globalize_path(rel)
	_set_panel_visible(panel_was)
	_busy = false
	if err != OK:
		Game.notify("Could not save the photo.", &"bad")
		return ""
	photos_taken += 1
	last_path = path
	if _flash != null:
		_flash.color.a = 0.85
	if _thumb != null:
		var small := img.duplicate() as Image
		small.resize(256, int(256.0 * float(img.get_height()) / maxf(float(img.get_width()), 1.0)), Image.INTERPOLATE_BILINEAR)
		_thumb.texture = ImageTexture.create_from_image(small)
		_thumb.visible = true
		_thumb_t = 3.5
	if Sfx != null:
		Sfx.play_ui(&"ui_confirm")
	Game.notify("Photo saved: %s%s" % [path, " (headless placeholder)" if placeholder else ""], &"good")
	Events.photo_taken.emit(path)
	photo_saved.emit(path)
	return path


# =====================================================================================================
# Panel
# =====================================================================================================
func _set_panel_visible(v: bool) -> void:
	_panel_visible = v
	if _panel != null:
		_panel.visible = v


func _sync_sliders() -> void:
	for k in _sliders:
		var s: HSlider = _sliders[k]
		if not is_instance_valid(s):
			continue
		match k:
			"fov": s.set_value_no_signal(fov_deg)
			"roll": s.set_value_no_signal(roll_deg)
			"dof": s.set_value_no_signal(dof_amount)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 70
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	_panel = UIKit.panel(&"PanelHi")
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 36
	_panel.offset_right = 36 + 420
	_panel.offset_top = 120
	_panel.offset_bottom = -120
	root.add_child(_panel)
	var v := UIKit.vbox(10)
	_panel.add_child(v)
	v.add_child(UIKit.header("Photo mode", "game paused"))
	v.add_child(UIKit.separator())
	_sliders.clear()
	var r1 := UIKit.slider_row("Field of view", 15.0, 110.0, fov_deg, 1.0, func(x: float): fov_deg = x, func(x: float): return "%d deg" % int(x))
	_sliders["fov"] = r1.get_meta(&"slider")
	v.add_child(r1)
	var r2 := UIKit.slider_row("Roll", -45.0, 45.0, roll_deg, 0.5, func(x: float): roll_deg = x, func(x: float): return "%.1f deg" % x)
	_sliders["roll"] = r2.get_meta(&"slider")
	v.add_child(r2)
	var r3 := UIKit.slider_row("Depth of field", 0.0, 1.0, dof_amount, 0.01, func(x: float):
		dof_amount = x
		_apply_dof(), func(x: float): return "off" if x < 0.02 else "%d %%" % int(x * 100.0))
	_sliders["dof"] = r3.get_meta(&"slider")
	v.add_child(r3)
	v.add_child(UIKit.toggle_row("Auto focus on subject", auto_focus, func(on: bool): auto_focus = on))
	var r4 := UIKit.slider_row("Focus distance", 0.5, 60.0, focus_dist, 0.1, func(x: float):
		if not auto_focus:
			focus_dist = x
			_apply_dof(), func(x: float): return "%.1f m" % x)
	v.add_child(r4)
	var names: Array = []
	for f in FILTERS:
		names.append(String(f).capitalize())
	v.add_child(UIKit.option_row("Filter", names, FILTERS.find(filter), func(i: int):
		filter = FILTERS[i]
		_apply_filter()))
	_info = UIKit.label("Time of day held at %s" % Util.format_clock(Game.time_of_day), 17, UITheme.C_DIM)
	v.add_child(_info)
	v.add_child(UIKit.spacer(0, 0, true))
	var shoot := UIKit.button("Take photo", func(): take_photo(), &"AccentButton")
	shoot.custom_minimum_size = Vector2(0, 54)
	v.add_child(shoot)
	v.add_child(UIKit.button("Exit photo mode", func(): exit(), &"DangerButton"))
	# hints
	var hb := UIKit.hbox(22)
	hb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hb.offset_top = -62
	hb.offset_bottom = -20
	hb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for h in [["LMB", "Orbit"], ["MMB", "Pan"], ["Wheel", "Dolly"], ["WASD QE", "Fly"], ["Z C", "Roll"], ["Tab", "Hide panel"], ["Enter", "Shoot"], ["F3", "Exit"]]:
		var item := UIKit.hbox(7)
		item.add_child(UIKit.keycap(String(h[0])))
		item.add_child(UIKit.label(String(h[1]), 17, UITheme.C_TEXT))
		hb.add_child(item)
	root.add_child(hb)
	# flash + thumbnail
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(256, 144)
	_thumb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_thumb.offset_left = -300
	_thumb.offset_top = -210
	_thumb.offset_right = -44
	_thumb.offset_bottom = -66
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.visible = false
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_thumb)
	_set_panel_visible(true)
