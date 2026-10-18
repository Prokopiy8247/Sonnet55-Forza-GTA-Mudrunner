class_name Hud
extends Control
## The in-game HUD: health / armour, cash, clock, wanted stars, weapon + ammo, crosshair (spread, hit / kill markers),
## minimap, interaction prompt, district banner, toasts + subtitles, vehicle / aircraft instruments, stealth eye,
## underwater air, parachute altimeter, scope overlay and the FPS / coordinate overlay.
## Everything is null-safe: the HUD polls Game.player / Game.sys() with get() probes and lights up as modules arrive.
## Layout: slot rectangles anchored to the screen corners (design space 1920 x 1080, canvas_items stretch).

var raster: MapRaster
var minimap: Minimap
var bars: HudWidgets.StatBars
var cash: HudWidgets.CashDisplay
var wanted: HudWidgets.WantedStars
var weapon: HudWidgets.WeaponCard
var crosshair: HudWidgets.Crosshair
var prompt: HudWidgets.PromptBar
var district: HudWidgets.DistrictBanner
var air: HudWidgets.AirBar
var stealth: HudWidgets.StealthIcon
var chute: HudWidgets.ChuteGauge
var scope: HudWidgets.ScopeOverlay
var vehicle_hud: VehicleHud
var notifications: Notifications
var clock_label: Label
var weather_label: Label
var debug_label: Label

var test_mode := false           # showcase / tests: skip polling Game.player (values are pushed manually)
var menu_dim := 0.0              # 0..1 how much the HUD fades while a menu is open
var dead_dim := 0.0              # 0..1 HUD fade while the death / busted sequence runs
var scope_active_override := false

var _t := 0.0
var _last_district: StringName = &""
var _district_event_ms := -10000
var _district_poll := 0.0
var _prompt_target := 0.0
var _health_hold := 0.0
var _reload_started := 0.0
var _last_weapon: StringName = &""
var _dbg_acc := 1.0
var _clock_text := ""
var _weather_text := ""
var _spread_smooth := 8.0
var _wanted_prev := 0
var _alpha := 1.0
var _mag_prev := 0
var _cash_synced := false
var _day := 0
var _last_tod := -1.0

const DAYS := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build()
	_connect_events()
	cash.target = Game.cash
	cash.shown = float(Game.cash)


# =====================================================================================================================
func _slot(c: Control, a_l: float, a_t: float, a_r: float, a_b: float, o_l: float, o_t: float, o_r: float, o_b: float) -> void:
	c.anchor_left = a_l
	c.anchor_top = a_t
	c.anchor_right = a_r
	c.anchor_bottom = a_b
	c.offset_left = o_l
	c.offset_top = o_t
	c.offset_right = o_r
	c.offset_bottom = o_b
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build() -> void:
	var sx := UITheme.SAFE_X
	var sy := UITheme.SAFE_Y
	# scope (behind everything else)
	scope = HudWidgets.ScopeOverlay.new()
	_slot(scope, 0, 0, 1, 1, 0, 0, 0, 0)
	scope.visible = false
	add_child(scope)

	# ---- top-right column ----
	var tr := VBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	_slot(tr, 1, 0, 1, 0, -(sx + 430.0), sy - 6.0, -sx, sy + 430.0)
	add_child(tr)
	cash = HudWidgets.CashDisplay.new()
	tr.add_child(cash)
	var clock_pill := UIKit.panel(&"Pill")
	clock_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	clock_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(clock_pill)
	var clock_row := HBoxContainer.new()
	clock_row.alignment = BoxContainer.ALIGNMENT_END
	clock_row.add_theme_constant_override("separation", 14)
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_pill.add_child(clock_row)
	weather_label = UIKit.label("", 18, Color(0.86, 0.93, 0.98, 0.85), true)
	weather_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_row.add_child(weather_label)
	clock_label = UIKit.label("09:30", 30, Color.WHITE, true)
	clock_label.add_theme_font_override("font", UITheme.font_display())
	clock_row.add_child(clock_label)
	wanted = HudWidgets.WantedStars.new()
	wanted.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(wanted)
	weapon = HudWidgets.WeaponCard.new()
	weapon.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(weapon)

	# ---- bottom-left: minimap + bars ----
	var bl := HBoxContainer.new()
	bl.add_theme_constant_override("separation", 6)
	bl.alignment = BoxContainer.ALIGNMENT_BEGIN
	_slot(bl, 0, 1, 0, 1, sx - 12.0, -(sy - 6.0) - 316.0, sx - 12.0 + 780.0, -(sy - 6.0))
	add_child(bl)
	raster = MapRaster.new()
	raster.name = "MapRaster"
	add_child(raster)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(Minimap.SIZE_PX + 24.0, Minimap.SIZE_PX + 24.0)
	minimap.size_flags_vertical = Control.SIZE_SHRINK_END
	bl.add_child(minimap)
	minimap.attach_raster(raster)
	bars = HudWidgets.StatBars.new()
	bars.size_flags_vertical = Control.SIZE_SHRINK_END
	var bars_box := VBoxContainer.new()
	bars_box.size_flags_vertical = Control.SIZE_SHRINK_END
	bars_box.add_theme_constant_override("separation", 0)
	bars_box.add_child(bars)
	bars_box.add_child(UIKit.spacer(14))
	bl.add_child(bars_box)

	# ---- bottom-right: vehicle instruments / parachute ----
	vehicle_hud = VehicleHud.new()
	_slot(vehicle_hud, 1, 1, 1, 1, -(sx + 460.0), -(sy + 380.0), -sx, -sy)
	vehicle_hud.visible = false
	add_child(vehicle_hud)
	chute = HudWidgets.ChuteGauge.new()
	_slot(chute, 1, 1, 1, 1, -(sx + 240.0), -(sy + 96.0 + 10.0), -sx, -(sy + 10.0))
	add_child(chute)

	# ---- bottom-centre: air + stealth ----
	air = HudWidgets.AirBar.new()
	_slot(air, 0.5, 1, 0.5, 1, -190.0, -(sy + 190.0), 190.0, -(sy + 146.0))
	add_child(air)
	stealth = HudWidgets.StealthIcon.new()
	_slot(stealth, 0.5, 1, 0.5, 1, -110.0, -(sy + 262.0), 110.0, -(sy + 210.0))
	add_child(stealth)

	# ---- centre ----
	crosshair = HudWidgets.Crosshair.new()
	_slot(crosshair, 0.5, 0.5, 0.5, 0.5, -200, -200, 200, 200)
	add_child(crosshair)
	prompt = HudWidgets.PromptBar.new()
	_slot(prompt, 0.5, 0.5, 0.5, 0.5, -450, 150, 450, 222)
	add_child(prompt)

	# ---- top-centre ----
	district = HudWidgets.DistrictBanner.new()
	_slot(district, 0.5, 0, 0.5, 0, -500, sy - 6.0, 500, sy + 114.0)
	add_child(district)

	# ---- debug overlay (top-left) ----
	debug_label = Label.new()
	debug_label.add_theme_font_size_override("font_size", 17)
	debug_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.85, 0.95))
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot(debug_label, 0, 0, 0, 0, 14, 8, 760, 60)
	debug_label.visible = false
	add_child(debug_label)

	# ---- toasts + subtitles ----
	notifications = Notifications.new()
	add_child(notifications)


func _connect_events() -> void:
	Events.cash_changed.connect(_on_cash_changed)
	Events.interaction_prompt.connect(set_prompt)
	Events.district_changed.connect(_on_district_event)
	Events.hit_marker.connect(_on_hit_marker)
	Events.wanted_search_progress.connect(func(p: float): wanted.progress = p)
	Events.wanted_changed.connect(_on_wanted_changed)
	Events.notification.connect(func(text: String, kind: StringName): notifications.push_toast(text, kind))
	Events.subtitle.connect(func(text: String, seconds: float): notifications.push_subtitle(text, seconds))
	Events.weapon_changed.connect(func(_c: Node, _w: StringName): weapon.kick = 1.0)
	Events.ammo_changed.connect(func(c: Node, _w: StringName, _m: int, _r: int):
		if c == Game.player:
			weapon.kick = 1.0)


# ---- Event handlers --------------------------------------------------------------------------------------------------
func _on_cash_changed(amount: int, delta: int) -> void:
	cash.target = amount
	cash.add_delta(delta)
	cash.queue_redraw()


func set_prompt(text: String) -> void:
	var t := text.strip_edges()
	var key := UIKit.action_key(&"interact")
	if t.begins_with("[") and t.find("]") > 0:
		key = t.substr(1, t.find("]") - 1)
		t = t.substr(t.find("]") + 1).strip_edges()
	prompt.key = key
	if t != "":
		prompt.text = t
	_prompt_target = 1.0 if t != "" else 0.0


func _on_hit_marker(kill: bool) -> void:
	crosshair.hit = 1.0
	if kill:
		crosshair.kill = 1.0


func _on_wanted_changed(level: int, _state: StringName) -> void:
	if level != _wanted_prev:
		wanted.pop = 1.0
		_wanted_prev = level


func _on_district_event(id: StringName) -> void:
	_district_event_ms = Time.get_ticks_msec()
	_announce_district(id)


func _announce_district(id: StringName) -> void:
	if id == _last_district:
		return
	_last_district = id
	if id == &"" or id == &"none":
		return
	district.show_text(district_name(id))


static func district_name(id: StringName) -> String:
	for d in WorldLayout.districts:
		if d.get("id", &"") == id and str(d.get("name", "")) != "":
			return str(d["name"])
	match id:
		GC.D_SEA: return "Halcyon Bay"
		GC.D_PARK: return "Park & Hills"
	return String(id).replace("_", " ").capitalize()


# =====================================================================================================================
func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.05)
	dt = minf(dt, 0.1)
	_t += dt
	_alpha = Util.damp(_alpha, 1.0 - maxf(menu_dim, dead_dim), 6.0 if dead_dim > 0.0 else 10.0, dt)
	modulate.a = _alpha
	wanted.t = _t
	weapon.t = _t
	air.t = _t
	stealth.t = _t
	if not test_mode:
		_poll_player(dt)
		_poll_world(dt)
	_animate(dt)
	_update_debug(dt)


func _poll_player(dt: float) -> void:
	var p = Game.player
	if not is_instance_valid(p):
		return
	var mh: float = maxf(float(p.get("max_health")) if p.get("max_health") != null else 100.0, 1.0)
	var hp: float = clampf(float(p.get("health")) / mh, 0.0, 1.0) if p.get("health") != null else 1.0
	var ma: float = maxf(float(p.get("max_armor")) if p.get("max_armor") != null else 100.0, 1.0)
	var ar: float = clampf(float(p.get("armor")) / ma, 0.0, 1.0) if p.get("armor") != null else 0.0
	bars.health = hp
	bars.health_val = int(ceil(hp * mh))
	bars.armor = ar
	bars.armor_val = int(ceil(ar * ma))
	var st := _ratio_ex(p, ["stamina_ratio", "stamina"], ["max_stamina"], ["MAX_STAMINA"], 1.0)
	minimap.stamina = st
	# weapons / ammo
	var w = p.get("weapons")
	_poll_weapon(w, p, dt)
	# vehicle
	var veh = p.get("current_vehicle")
	if veh != null and is_instance_valid(veh):
		vehicle_hud.read(veh, dt)
	else:
		vehicle_hud.clear()
	# stealth
	var crouching := false
	var stance = p.get("stance")
	if stance != null and (stance == &"crouch" or stance == &"cover_low" or stance == &"cover_high"):
		crouching = true
	if p.get("is_crouching") == true or p.get("crouching") == true:
		crouching = true
	stealth.shown = move_toward(stealth.shown, 1.0 if crouching and veh == null else 0.0, dt * 4.0)
	if stealth.shown > 0.01:
		var spd := 0.0
		if p is CharacterBody3D:
			spd = Vector2((p as CharacterBody3D).velocity.x, (p as CharacterBody3D).velocity.z).length()
		var nl = p.get("noise_level")
		var nr = p.get("noise_radius")
		if nl != null:
			stealth.noise = clampf(float(nl), 0.0, 1.0)
		elif nr != null:
			stealth.noise = clampf(float(nr) / 13.0, 0.0, 1.0)       # metres audible (sprinting ~ 13 m)
		else:
			stealth.noise = clampf(spd / 5.0, 0.0, 1.0)
		var wsys = Game.sys(&"wanted")
		stealth.seen = Game.wanted_level > 0 and wsys != null and wsys.has_method("is_player_seen") and bool(wsys.is_player_seen())
		stealth.queue_redraw()
	# air / lung
	var lung := _ratio_ex(p, ["lung_ratio", "lungs", "lung", "breath", "air"], ["max_lung", "max_lungs", "max_breath", "max_air"], ["LUNG_TIME"], 1.0)
	var under: bool = p.get("head_underwater") == true or p.get("underwater") == true
	air.ratio = lung
	air.shown = move_toward(air.shown, 1.0 if (under or lung < 0.995) else 0.0, dt * 4.0)
	if air.shown > 0.01:
		air.queue_redraw()
	# parachute
	var chuting: bool = p.get("is_parachuting") == true or p.get("parachute_open") == true or (stance != null and stance == &"parachute")
	chute.shown = move_toward(chute.shown, 1.0 if chuting else 0.0, dt * 4.0)
	if chute.shown > 0.01 and p is Node3D:
		var pn := p as Node3D
		chute.altitude = maxf(pn.global_position.y - WorldLayout.terrain_height(pn.global_position.x, pn.global_position.z), 0.0)
		if p is CharacterBody3D:
			chute.vspeed = (p as CharacterBody3D).velocity.y
		chute.queue_redraw()


## Ratio 0..1 of the first matching property. The maximum comes from a max_* property, else from a script constant
## (e.g. Player.MAX_STAMINA), else values > 1 are assumed to be percentages.
func _ratio_ex(obj: Object, names: Array, max_names: Array, const_names: Array, default_v: float) -> float:
	for n in names:
		var v = obj.get(n)
		if v == null or not (v is float or v is int):
			continue
		var f := float(v)
		var mx := -1.0
		for mn in max_names:
			var m = obj.get(mn)
			if m != null and (m is float or m is int):
				mx = float(m)
				break
		if mx <= 0.0 and obj.get_script() != null:
			var cm: Dictionary = (obj.get_script() as Script).get_script_constant_map()
			for cn in const_names:
				if cm.has(cn):
					mx = float(cm[cn])
					break
		if mx <= 0.0:
			mx = 1.0 if f <= 1.0001 else 100.0
		return clampf(f / mx, 0.0, 1.0)
	return default_v


func _ratio(obj: Object, names: Array, max_names: Array, default_v: float) -> float:
	for n in names:
		var v = obj.get(n)
		if v != null and (v is float or v is int):
			var f := float(v)
			if f > 1.0001:
				var mx := 100.0
				for mn in max_names:
					var m = obj.get(mn)
					if m != null:
						mx = maxf(float(m), 1.0)
						break
				return clampf(f / mx, 0.0, 1.0)
			return clampf(f, 0.0, 1.0)
	return default_v


func _poll_weapon(w: Object, p: Object, dt: float) -> void:
	if w == null or not is_instance_valid(w):
		weapon.weapon_id = &"fists"
		weapon.weapon_name = "Fists"
		weapon.shows_ammo = false
		weapon.category = &"melee"
		crosshair.mode = 0
		scope.visible = scope_active_override
		return
	var id: StringName = w.get("current_id") if w.get("current_id") != null else &"fists"
	var info := UIIcons.weapon_info(id)
	var cat: StringName = info["category"]
	weapon.weapon_id = id
	weapon.weapon_name = info["name"]
	weapon.category = cat
	var firearm := cat != &"melee"
	weapon.shows_ammo = firearm
	weapon.total_only = cat == &"thrown"
	var mag: int = int(w.get_ammo_in_mag()) if w.has_method("get_ammo_in_mag") else 0
	var res: int = int(w.get_ammo_reserve()) if w.has_method("get_ammo_reserve") else 0
	weapon.mag = mag
	weapon.reserve = res
	weapon.infinite = false
	var rl: bool = w.get("is_reloading") == true
	if rl and not weapon.reloading:
		_reload_started = _t
	weapon.reloading = rl
	if rl:
		var rp = w.get("reload_progress")
		if rp != null:
			weapon.reload_t = clampf(float(rp), 0.0, 1.0)
		else:
			var def: Dictionary = w.get_current_def() if w.has_method("get_current_def") else {}
			var dur := float(def.get("reload_time", 2.0))
			weapon.reload_t = clampf((_t - _reload_started) / maxf(dur, 0.2), 0.0, 1.0)
	var aiming: bool = w.get("is_aiming") == true
	var veh = p.get("current_vehicle")
	var in_veh: bool = veh != null and is_instance_valid(veh)
	var can_show := firearm and cat != &"thrown" and (not in_veh or aiming)
	# spread (degrees -> pixels); weapon controllers may expose current_spread
	var spread_deg := 1.5
	var cs = w.get("current_spread")
	if cs != null:
		spread_deg = float(cs)
	else:
		var d: Dictionary = w.get_current_def() if w.has_method("get_current_def") else {}
		spread_deg = float(d.get("spread", 1.5))
		if p is CharacterBody3D:
			var spd := Vector2((p as CharacterBody3D).velocity.x, (p as CharacterBody3D).velocity.z).length()
			spread_deg *= 1.0 + clampf(spd / 6.0, 0.0, 1.0) * 0.8
		if aiming:
			spread_deg *= 0.45
	var target_px := 7.0 + minf(spread_deg * 13.0, 84.0)
	_spread_smooth = Util.damp(_spread_smooth, target_px, 16.0, dt)
	crosshair.spread = _spread_smooth
	crosshair.aiming = aiming
	var scoped: bool = w.get("scope_active") == true or scope_active_override
	scope.visible = scoped
	if scoped:
		crosshair.mode = 0
	elif can_show:
		crosshair.mode = 2 if aiming else 1
	else:
		crosshair.mode = 0
	crosshair.tint = Color(1, 0.35, 0.35, 0.95) if _crosshair_on_enemy() else Color(1, 1, 1, 0.92)


func _crosshair_on_enemy() -> bool:
	# the weapon controller may expose the aimed target; tint red when it is hostile
	var w = Game.player.get("weapons") if is_instance_valid(Game.player) else null
	if w == null:
		return false
	var tgt = w.get("aim_target")
	return tgt != null and tgt is Node and is_instance_valid(tgt) and Game.player.is_hostile_to(tgt)


func _poll_world(dt: float) -> void:
	# clock / weather (text updated only when it changes)
	var ct := Util.format_clock(Game.time_of_day)
	if ct != _clock_text:
		_clock_text = ct
		clock_label.text = ct
	if _last_tod >= 0.0 and Game.time_of_day < _last_tod - 6.0:
		_day += 1
	_last_tod = Game.time_of_day
	var wt := "%s  -  %s" % [DAYS[_day % 7], String(Game.weather).to_upper()]
	if wt != _weather_text:
		_weather_text = wt
		weather_label.text = wt
	if cash.target != Game.cash:
		cash.target = Game.cash
	wanted.level = Game.wanted_level
	wanted.state = Game.wanted_state
	# district (compute from the player position when nobody emitted the event recently)
	_district_poll += dt
	if _district_poll >= 0.5 and is_instance_valid(Game.player):
		_district_poll = 0.0
		var pos: Vector3 = Game.player.global_position
		var d: StringName = WorldLayout.district_at(pos.x, pos.z)
		if d != _last_district:
			_announce_district(d)
			if Time.get_ticks_msec() - _district_event_ms > 1500:
				Events.district_changed.emit(d)


func _animate(dt: float) -> void:
	# health ghost + pulse
	if bars.ghost > bars.health:
		_health_hold += dt
		if _health_hold > 0.5:
			bars.ghost = move_toward(bars.ghost, bars.health, dt * 0.35)
	else:
		bars.ghost = bars.health
		_health_hold = 0.0
	var low := bars.health < 0.3 and bars.health > 0.0
	if low:
		bars.pulse = 0.5 + 0.5 * sin(_t * (5.0 + (0.3 - bars.health) * 22.0))
	else:
		bars.pulse = move_toward(bars.pulse, 0.0, dt * 4.0)
	bars.armor_visible = move_toward(bars.armor_visible, 1.0 if bars.armor > 0.002 else 0.0, dt * 5.0)
	bars.queue_redraw()
	# cash
	if cash.step(dt):
		cash.queue_redraw()
	# wanted
	wanted.pop = move_toward(wanted.pop, 0.0, dt * 3.0)
	wanted.queue_redraw()
	# weapon card
	weapon.kick = move_toward(weapon.kick, 0.0, dt * 6.0)
	weapon.queue_redraw()
	# crosshair
	crosshair.hit = move_toward(crosshair.hit, 0.0, dt * 4.5)
	crosshair.kill = move_toward(crosshair.kill, 0.0, dt * 2.6)
	crosshair.queue_redraw()
	# prompt
	var menu_open: bool = Game.ui != null and Game.ui.has_method("is_menu_open") and Game.ui.is_menu_open()
	prompt.shown = move_toward(prompt.shown, _prompt_target if not menu_open else 0.0, dt * 7.0)
	prompt.queue_redraw()
	# district banner
	if district.t < 1.0:
		district.t += dt / HudWidgets.DistrictBanner.LIFE
		district.queue_redraw()


func _update_debug(dt: float) -> void:
	var show_fps: bool = Game.cheats.get("show_fps", false)
	var show_xyz: bool = Game.cheats.get("show_coords", false)
	debug_label.visible = show_fps or show_xyz
	notifications.top_offset = 56.0 if debug_label.visible else 0.0
	if not debug_label.visible:
		return
	_dbg_acc += dt
	if _dbg_acc < 0.25:
		return
	_dbg_acc = 0.0
	var parts: Array[String] = []
	if show_fps:
		var fps := Engine.get_frames_per_second()
		parts.append("FPS %d  (%.1f ms)" % [fps, 1000.0 / maxf(float(fps), 1.0)])
	if show_xyz and is_instance_valid(Game.player):
		var p: Vector3 = Game.player.global_position
		var heading := 0.0
		if is_instance_valid(Game.gameplay_camera):
			var f := -Game.gameplay_camera.global_transform.basis.z
			heading = fposmod(-rad_to_deg(Util.dir_to_yaw(Vector3(f.x, 0.0, f.z))), 360.0)
		parts.append("X %.1f  Y %.1f  Z %.1f  |  %s  |  HDG %d" % [p.x, p.y, p.z, String(WorldLayout.district_at(p.x, p.z)), int(heading)])
	debug_label.text = "\n".join(parts)
