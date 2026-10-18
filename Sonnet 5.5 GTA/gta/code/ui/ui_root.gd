class_name UIRoot
extends CanvasLayer
## The UI host (ARCHITECTURE s8): HUD, minimap, weapon wheel, map, pause / status, notifications, death / busted
## sequences, fades and the modal-menu host used by the shop / garage / phone / debug menus (subclass MenuBase).
##
## Booted by Main: setup(main) once in boot order, post_setup() after ALL systems exist. Sets `Game.ui = self`.
## Everything is null-safe: missing modules (player, wanted, weapons...) just leave their HUD parts idle.
##
## Menu host API
##   register_menu(id, menu)  open_menu(id, data := {}) -> bool  close_menu()  is_menu_open() -> bool
##   toast(text, kind := &"info")  show_prompt(text)  confirm(title, text, on_yes, on_no)
## Screen API
##   fade(to_black, seconds := 0.5)   (awaitable)   show_loading(text) / hide_loading()   set_hud_visible(bool)
## Navigation: set_waypoint(Vector3) / clear_waypoint() / waypoint / has_waypoint / route (GPS polyline).

signal waypoint_changed(active: bool, position: Vector3)

const MENU_PAUSE := &"pause"
const MENU_MAP := &"map"
const MENU_STATUS := &"status"

var root: Control
var hud: Hud
var feedback: DamageFeedback
var wheel: WeaponWheel
var death: DeathScreen
var menu_layer: Control
var map_screen: MapScreen
var pause_menu: PauseMenu
var status_screen: StatusScreen

var menus: Dictionary = {}                 # StringName -> MenuBase
var current_menu: MenuBase = null
var current_menu_id: StringName = &""

var capture_when_idle := true              # re-capture the mouse when the last menu closes
var hud_hidden := false                    # photo mode / cinematic: hide all HUD

var waypoint := Vector3.ZERO
var has_waypoint := false
var route: UIRoute = null

var stats: Dictionary = {
	"time_played": 0.0, "dist_foot": 0.0, "dist_driven": 0.0, "kills": 0, "money_earned": 0, "money_spent": 0,
	"wanted_peak": 0, "deaths": 0, "busted": 0, "vehicles": 0,
}
var skill_cache: Dictionary = {}

var _fade: ColorRect
var _fade_tween: Tween = null
var _loading: LoadingOverlay
var _switching := false
var _menu_paused := false
var _last_pos := Vector3.INF
var _route_from := Vector3.INF
var _route_acc := 0.0
var _intro_done := false


# ---- Lifecycle ---------------------------------------------------------------------------------------------------
func setup(_main: Node) -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.ui = self
	root = Control.new()
	root.name = "Root"
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	feedback = DamageFeedback.new()
	feedback.name = "DamageFeedback"
	root.add_child(feedback)
	hud = Hud.new()
	hud.name = "Hud"
	root.add_child(hud)
	wheel = WeaponWheel.new()
	wheel.name = "WeaponWheel"
	wheel.wheel_closed.connect(_on_wheel_closed)
	root.add_child(wheel)
	menu_layer = Control.new()
	menu_layer.name = "Menus"
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_layer)
	# toasts live above menus (they are created by the HUD; re-parent so menu dimming does not fade them)
	var notif := hud.notifications
	hud.remove_child(notif)
	root.add_child(notif)
	death = DeathScreen.new()
	death.name = "DeathScreen"
	death.feedback = feedback
	death.ui = self
	root.add_child(death)
	_loading = LoadingOverlay.new()
	_loading.name = "Loading"
	root.add_child(_loading)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)

	# built-in menus
	map_screen = MapScreen.new()
	map_screen.attach_raster(hud.raster)
	register_menu(MENU_MAP, map_screen)
	pause_menu = PauseMenu.new()
	register_menu(MENU_PAUSE, pause_menu)
	status_screen = StatusScreen.new()
	register_menu(MENU_STATUS, status_screen)

	_connect_events()
	if not OS.get_cmdline_user_args().has("--no-intro"):
		_loading.show_now("")
		Events.game_ready.connect(_end_intro, CONNECT_ONE_SHOT)
		get_tree().create_timer(6.0, true, false, true).timeout.connect(_end_intro)
	else:
		_intro_done = true


func post_setup() -> void:
	register_menu(&"ui_showcase", UIShowcase.new())
	apply_settings()


func _connect_events() -> void:
	Events.player_died.connect(_on_player_died)
	Events.player_busted.connect(_on_player_busted)
	Events.player_respawned.connect(_on_player_respawned)
	Events.character_died.connect(_on_character_died)
	Events.cash_changed.connect(_on_cash_changed)
	Events.wanted_changed.connect(_on_wanted_changed)
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.skill_changed.connect(func(skill: StringName, value: float): skill_cache[skill] = value)
	Events.settings_changed.connect(apply_settings)


func _end_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	await get_tree().create_timer(0.55, true, false, true).timeout
	hide_loading(0.8)


# =====================================================================================================================
# Menu host
# =====================================================================================================================
func register_menu(id: StringName, menu: MenuBase) -> void:
	if menu == null:
		return
	if menus.has(id) and is_instance_valid(menus[id]) and menus[id] != menu:
		push_warning("UIRoot.register_menu: replacing menu '%s'" % id)
		(menus[id] as Node).queue_free()
	menu.menu_id = id
	menus[id] = menu
	if menu.get_parent() == null:
		menu_layer.add_child(menu)
	menu.visible = false
	if not menu.closed.is_connected(_on_menu_closed.bind(menu)):
		menu.closed.connect(_on_menu_closed.bind(menu))


func has_menu(id: StringName) -> bool:
	return menus.has(id) and is_instance_valid(menus[id])


func get_menu(id: StringName) -> MenuBase:
	return menus.get(id, null)


func open_menu(id: StringName, data: Dictionary = {}) -> bool:
	var m: MenuBase = menus.get(id, null)
	if m == null or not is_instance_valid(m):
		push_warning("UIRoot.open_menu: unknown menu '%s'" % id)
		return false
	if current_menu == m:
		return true
	if wheel.is_open:
		wheel.close_wheel(false)
	if current_menu != null:
		_switching = true
		current_menu.close()
		_switching = false
	current_menu = m
	current_menu_id = id
	_menu_paused = m.pauses_game
	if m.pauses_game and not get_tree().paused:
		Game.set_paused(true)
	hud.menu_dim = 1.0 if id == MENU_MAP else 0.55
	_apply_mouse()
	m.open(data)
	m.visible = true
	m.move_to_front()
	Events.menu_opened.emit(id)
	return true


func close_menu() -> void:
	if current_menu == null:
		return
	var m := current_menu
	m.close()
	if current_menu == m:      # a menu that overrides close() without emitting `closed`
		_on_menu_closed(m)


## True while a modal menu is open OR the weapon wheel is up (Player / Weapons read this to ignore gameplay input and
## to leave the mouse cursor free). Use `current_menu` to test for an actual menu only.
func is_menu_open() -> bool:
	return (current_menu != null and is_instance_valid(current_menu)) or (wheel != null and wheel.is_open)


## True while gameplay input should be ignored (menu, wheel or confirm dialog open).
func is_input_blocked() -> bool:
	return is_menu_open() or (UIConfirm.active != null and is_instance_valid(UIConfirm.active))


func _on_menu_closed(menu: MenuBase) -> void:
	if menu != current_menu:
		return
	var id := current_menu_id
	current_menu = null
	current_menu_id = &""
	if not _switching:
		if _menu_paused and get_tree().paused:
			Game.set_paused(false)
		_menu_paused = false
		hud.menu_dim = 0.0
		_apply_mouse()
	Events.menu_closed.emit(id)


func _apply_mouse() -> void:
	if is_menu_open() or wheel.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif capture_when_idle:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =====================================================================================================================
# Small API
# =====================================================================================================================
func toast(text: String, kind: StringName = &"info") -> void:
	if hud != null:
		hud.notifications.push_toast(text, kind)


func subtitle(text: String, seconds: float = 3.0) -> void:
	if hud != null:
		hud.notifications.push_subtitle(text, seconds)


func show_prompt(text: String) -> void:
	if hud != null:
		hud.set_prompt(text)


func confirm(title: String, text: String, on_yes: Callable, on_no: Callable = Callable(), yes_text: String = "Confirm", no_text: String = "Cancel") -> void:
	UIConfirm.show_in(root, title, text, on_yes, on_no, yes_text, no_text)


func set_hud_visible(v: bool) -> void:
	hud_hidden = not v


## Fades the screen to / from `color`. Awaitable:  await Game.ui.fade(true, 0.4)
func fade(to_black: bool, seconds: float = 0.5, color: Color = Color.BLACK) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade.color = Color(color.r, color.g, color.b, _fade.color.a)
	var target := 1.0 if to_black else 0.0
	if seconds <= 0.001:
		_fade.color.a = target
		return
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.tween_property(_fade, "color:a", target, seconds)
	await _fade_tween.finished


func is_faded_out() -> bool:
	return _fade.color.a > 0.98


func show_loading(text: String = "Loading") -> void:
	_loading.show_text(text)


func hide_loading(seconds: float = 0.5) -> void:
	_loading.hide_fade(seconds)


# =====================================================================================================================
# Waypoint + GPS
# =====================================================================================================================
func set_waypoint(pos: Vector3) -> void:
	waypoint = pos
	has_waypoint = true
	Game.set_meta(&"waypoint", pos)
	if "waypoint" in Game:
		Game.set("waypoint", pos)
	_route_from = Vector3.INF
	_update_route(true)
	toast("Waypoint set - follow the route on the map.", &"info")
	waypoint_changed.emit(true, pos)


func clear_waypoint() -> void:
	if not has_waypoint:
		return
	has_waypoint = false
	route = null
	if Game.has_meta(&"waypoint"):
		Game.remove_meta(&"waypoint")
	if "waypoint" in Game:
		Game.set("waypoint", Vector3.INF)
	waypoint_changed.emit(false, Vector3.ZERO)


func get_waypoint() -> Variant:
	return waypoint if has_waypoint else null


func _update_route(force: bool = false) -> void:
	if not has_waypoint:
		return
	var from := Game.get_player_position()
	if not force and _route_from != Vector3.INF and Vector2(from.x - _route_from.x, from.z - _route_from.z).length() < 25.0:
		return
	_route_from = from
	route = UIRoute.find(from, waypoint)


# =====================================================================================================================
# Settings
# =====================================================================================================================
func apply_settings() -> void:
	var s: Dictionary = Game.settings
	_set_bus_volume("Master", float(s.get("master_volume", 0.8)))
	_set_bus_volume("Music", float(s.get("music_volume", 0.6)))
	_set_bus_volume("SFX", float(s.get("sfx_volume", 1.0)), "Sfx")
	if DisplayServer.get_name() != "headless":
		var want_fs: bool = bool(s.get("fullscreen", false))
		var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
	var shadows: bool = bool(s.get("shadows", true))
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).shadow_enabled = shadows
	if hud != null and hud.minimap != null:
		hud.minimap.set_shape(bool(s.get("minimap_round", true)))


func _set_bus_volume(bus: String, linear: float, alt: String = "") -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0 and alt != "":
		idx = AudioServer.get_bus_index(alt)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


# =====================================================================================================================
# Input
# =====================================================================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	if event.is_action_pressed(&"debug_overlay"):
		_cycle_overlay()
		return
	if event.is_action_pressed(&"photo_mode"):
		hud_hidden = not hud_hidden
		return
	if UIConfirm.active != null and is_instance_valid(UIConfirm.active):
		return
	if event.is_action_pressed(&"pause"):
		if wheel.is_open:
			wheel.close_wheel(false)
			_apply_mouse()
		elif current_menu != null:
			if not current_menu.on_back() and current_menu.closes_on_pause:
				close_menu()
		elif not death.is_active() and not _player_dead():
			open_menu(MENU_PAUSE)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"map"):
		if current_menu == map_screen:
			close_menu()
			get_viewport().set_input_as_handled()
		elif current_menu == null and not death.is_active() and not _player_dead():
			open_menu(MENU_MAP)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"weapon_wheel"):
		if current_menu == null and not wheel.is_open and not death.is_active() and not _player_dead():
			if wheel.open_wheel():
				_apply_mouse()
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_save"):
		_quick_save()
	elif event.is_action_pressed(&"quick_load"):
		_quick_load()
	elif event.is_action_released(&"weapon_wheel"):
		if wheel.is_open:
			wheel.close_wheel(true)
			get_viewport().set_input_as_handled()


## F5 / F9. Skipped when the SaveSystem declares that it handles the quick keys itself (handles_quick_keys()).
func _quick_save() -> void:
	if SaveSystem == null or death.is_active() or _player_dead():
		return
	if SaveSystem.has_method("handles_quick_keys") and SaveSystem.handles_quick_keys():
		return
	var ok: bool = SaveSystem.has_method("save_game") and SaveSystem.save_game(0)
	toast("Quick saved." if ok else "Quick save is not available yet.", &"good" if ok else &"warn")


func _quick_load() -> void:
	if SaveSystem == null or death.is_active():
		return
	if SaveSystem.has_method("handles_quick_keys") and SaveSystem.handles_quick_keys():
		return
	if not SaveSystem.has_method("has_save") or not SaveSystem.has_save(0):
		toast("No quick save found.", &"warn")
		return
	var ok: bool = SaveSystem.load_game(0)
	toast("Quick load complete." if ok else "Quick load failed.", &"good" if ok else &"bad")


func _on_wheel_closed(_id: StringName, _applied: bool) -> void:
	_apply_mouse()


func _player_dead() -> bool:
	return is_instance_valid(Game.player) and Game.player.get("is_dead") == true


func _cycle_overlay() -> void:
	var fps: bool = Game.cheats.get("show_fps", false)
	var xyz: bool = Game.cheats.get("show_coords", false)
	if not fps and not xyz:
		Game.cheats["show_fps"] = true
	elif fps and not xyz:
		Game.cheats["show_coords"] = true
	else:
		Game.cheats["show_fps"] = false
		Game.cheats["show_coords"] = false


# =====================================================================================================================
# Per-frame
# =====================================================================================================================
func _process(delta: float) -> void:
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.25)
	var photo: bool = hud_hidden or Game.cheats.get("photo_mode", false) == true
	hud.visible = not photo
	hud.dead_dim = 0.88 if death.is_active() else 0.0
	hud.notifications.visible = not photo
	if not get_tree().paused:
		stats["time_played"] = float(stats["time_played"]) + dt
		_track_distance()
	if has_waypoint:
		_route_acc += dt
		if _route_acc > 2.0:
			_route_acc = 0.0
			_update_route()
		_check_waypoint_reached()


func _track_distance() -> void:
	var p = Game.player
	if not is_instance_valid(p) or not (p is Node3D):
		_last_pos = Vector3.INF
		return
	var pos := (p as Node3D).global_position
	if _last_pos != Vector3.INF:
		var d := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		if d < 25.0:
			if p.has_method("is_in_vehicle") and p.is_in_vehicle():
				stats["dist_driven"] = float(stats["dist_driven"]) + d
			else:
				stats["dist_foot"] = float(stats["dist_foot"]) + d
	_last_pos = pos


func _check_waypoint_reached() -> void:
	var p := Game.get_player_position()
	var in_veh: bool = is_instance_valid(Game.player) and Game.player.has_method("is_in_vehicle") and Game.player.is_in_vehicle()
	var limit := 28.0 if in_veh else 12.0
	if Vector2(p.x - waypoint.x, p.z - waypoint.z).length() < limit:
		toast("You have reached your destination.", &"good")
		clear_waypoint()


# ---- Events ------------------------------------------------------------------------------------------------------------------
func _on_player_died() -> void:
	stats["deaths"] = int(stats["deaths"]) + 1
	_close_everything()
	death.begin_knocked()


func _on_player_busted() -> void:
	stats["busted"] = int(stats["busted"]) + 1
	_close_everything()
	death.begin_busted()


func _on_player_respawned(_pos: Vector3) -> void:
	death.on_respawned()
	feedback.death_desat = 0.0
	feedback.death_tint = 0.0


func _close_everything() -> void:
	if wheel.is_open:
		wheel.close_wheel(false)
	if current_menu != null:
		close_menu()
	if UIConfirm.active != null and is_instance_valid(UIConfirm.active):
		UIConfirm.active.queue_free()
		UIConfirm.active = null


func _on_character_died(character: Node, killer: Node, _info: Dictionary) -> void:
	if killer != null and killer == Game.player and character != Game.player:
		stats["kills"] = int(stats["kills"]) + 1


func _on_cash_changed(_amount: int, delta: int) -> void:
	if delta > 0:
		stats["money_earned"] = int(stats["money_earned"]) + delta
		if Sfx != null:
			Sfx.play_ui(&"ui_cash", -4.0)
	elif delta < 0:
		stats["money_spent"] = int(stats["money_spent"]) - delta


func _on_wanted_changed(level: int, _state: StringName) -> void:
	if level > int(stats["wanted_peak"]):
		stats["wanted_peak"] = level


func _on_vehicle_entered(_v: Node, character: Node, _seat: int) -> void:
	if character == Game.player:
		stats["vehicles"] = int(stats["vehicles"]) + 1


# ---- Persistence (SaveSystem calls serialize() / deserialize() on systems that provide them) ------------------------------
func serialize() -> Dictionary:
	var out := {"stats": stats.duplicate(), "skills_seen": skill_cache.duplicate()}
	if has_waypoint:
		out["waypoint"] = [waypoint.x, waypoint.y, waypoint.z]
	return out


func deserialize(data: Dictionary) -> void:
	var st = data.get("stats", {})
	if st is Dictionary:
		for k in st:
			if stats.has(k):
				stats[k] = st[k]
	var wp = data.get("waypoint", null)
	if wp is Array and wp.size() == 3:
		set_waypoint(Vector3(wp[0], wp[1], wp[2]))


# =====================================================================================================================
## Full-screen loading / title card with fade (used for the boot intro, save loading, fast transitions).
class LoadingOverlay extends Control:
	var text := ""
	var alpha := 0.0
	var _tween: Tween = null
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visible = false

	func show_now(s: String) -> void:
		text = s
		alpha = 1.0
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		queue_redraw()

	func show_text(s: String) -> void:
		text = s
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_animate(1.0, 0.3)

	func hide_fade(seconds: float) -> void:
		_animate(0.0, seconds)

	func _animate(target: float, seconds: float) -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_tween.set_ignore_time_scale(true)
		_tween.tween_property(self, "alpha", target, seconds)
		if target <= 0.0:
			_tween.tween_callback(func():
				visible = false
				mouse_filter = Control.MOUSE_FILTER_IGNORE)

	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if alpha <= 0.003:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, alpha))
		var fd := UITheme.font_display()
		var f := UITheme.font(true)
		var c := size * 0.5
		var title := GC.GAME_NAME.to_upper()
		var sz := 92
		var track := 14.0
		var total := 0.0
		for i in title.length():
			total += fd.get_string_size(title[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x + track
		total -= track
		var x := c.x - total * 0.5
		for i in title.length():
			var ch := title[i]
			var w := fd.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
			draw_string(fd, Vector2(x, c.y + 22.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz, Color(1, 1, 1, alpha))
			x += w + track
		draw_rect(Rect2(c.x - total * 0.5, c.y + 48.0, total, 4.0), Color(UITheme.C_ACCENT2.r, UITheme.C_ACCENT2.g, UITheme.C_ACCENT2.b, alpha))
		draw_rect(Rect2(c.x - total * 0.5, c.y + 48.0, total * (0.5 + 0.5 * sin(_t * 2.0)), 4.0), Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, alpha))
		if text != "":
			UIDraw.text_center(self, f, text.to_upper(), Vector2(c.x, c.y + 96.0), 22, Color(1, 1, 1, alpha * 0.75))
