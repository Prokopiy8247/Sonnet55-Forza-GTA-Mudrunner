class_name WeaponWheel
extends Control
## Radial weapon selector (hold Tab): inner ring = weapon categories you own, outer ring = the weapons of the hovered
## category, hub = selected weapon (icon, name, ammo). Slows time (Engine.time_scale = SLOWMO), frees the mouse, picks by
## mouse direction (or stick), releasing the key equips via WeaponController.equip(). Only owned weapons are shown.
##
## UIRoot opens / closes it from the `weapon_wheel` action:   open_wheel()  /  close_wheel(apply := true)

signal selection_changed(weapon_id: StringName)
signal wheel_closed(weapon_id: StringName, applied: bool)

const SLOWMO := 0.2
const R_HUB := 104.0
const R_IN := 128.0
const R_OUT := 222.0
const R_W_IN := 232.0
const R_W_OUT := 346.0
const DEAD_ZONE := 46.0

var is_open := false
var selected: StringName = &""
var current: StringName = &"fists"

var _cats: Array[Dictionary] = []      # {key, name, weapons: Array, a0, a1}
var _ammo: Dictionary = {}             # id -> [mag, reserve]
var _sel_cat := 0
var _sel_w := 0
var _t := 0.0
var _saved_scale := 1.0
var _mouse_ref := Vector2.ZERO
var _moved := false
var _stick := Vector2.ZERO
var _last_us := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## Opens with the player's real inventory. Returns false when it cannot open.
func open_wheel() -> bool:
	var ids: Array = []
	var cur: StringName = &"fists"
	var ammo: Dictionary = {}
	var p = Game.player
	var w = p.get("weapons") if is_instance_valid(p) else null
	if w != null and is_instance_valid(w):
		ids = w.get_weapon_ids() if w.has_method("get_weapon_ids") else []
		cur = w.get("current_id") if w.get("current_id") != null else &"fists"
		var inv = w.get("inventory")
		if inv is Dictionary:
			for id in inv:
				var e: Dictionary = inv[id] if inv[id] is Dictionary else {}
				ammo[id] = [int(e.get("mag", 0)), int(e.get("reserve", 0))]
		if w.has_method("get_ammo_in_mag"):
			ammo[cur] = [int(w.get_ammo_in_mag()), int(w.get_ammo_reserve())]
	return open_with(ids, cur, ammo)


## Opens with explicit data (tests / showcase): ids = owned weapon ids, ammo = {id: [mag, reserve]}.
func open_with(ids: Array, cur: StringName, ammo: Dictionary = {}) -> bool:
	if is_open:
		return true
	var owned: Array = ids.duplicate()
	if not owned.has(&"fists"):
		owned.push_front(&"fists")
	_ammo = ammo
	current = cur
	_build_categories(owned)
	if _cats.is_empty():
		return false
	_sel_cat = 0
	_sel_w = 0
	for ci in _cats.size():
		var ws: Array = _cats[ci]["weapons"]
		var wi := ws.find(cur)
		if wi >= 0:
			_sel_cat = ci
			_sel_w = wi
	selected = _cats[_sel_cat]["weapons"][_sel_w]
	is_open = true
	visible = true
	_t = 0.0
	_moved = false
	_stick = Vector2.ZERO
	_saved_scale = Engine.time_scale if Engine.time_scale > 0.5 else 1.0
	Engine.time_scale = SLOWMO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var c := get_viewport_rect().size * 0.5
	get_viewport().warp_mouse(c)
	_mouse_ref = c
	_last_us = Time.get_ticks_usec()
	Sfx.play_ui(&"ui_click")
	set_process(true)
	queue_redraw()
	return true


## Closes the wheel; when `apply` the selected weapon is equipped. Returns the selected weapon id.
func close_wheel(apply: bool = true) -> StringName:
	if not is_open:
		return &""
	is_open = false
	visible = false
	Engine.time_scale = _saved_scale
	var sel := selected
	if apply and sel != &"" and sel != current:
		var w = Game.player.get("weapons") if is_instance_valid(Game.player) else null
		if w != null and is_instance_valid(w) and w.has_method("equip"):
			w.equip(sel)
		Sfx.play_ui(&"ui_confirm")
	elif not apply:
		Sfx.play_ui(&"ui_back")
	wheel_closed.emit(sel, apply)
	return sel


func _exit_tree() -> void:
	if is_open:
		Engine.time_scale = _saved_scale


func _build_categories(owned: Array) -> void:
	_cats.clear()
	var by_cat: Dictionary = {}
	for id in owned:
		var info := UIIcons.weapon_info(id)
		var cat: StringName = info["category"]
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(id)
	for cat in WeaponDefs.CATEGORY_ORDER:
		if by_cat.has(cat):
			_cats.append({"key": cat, "name": UIIcons.CATEGORY_NAMES.get(cat, String(cat).capitalize()), "weapons": by_cat[cat]})
			by_cat.erase(cat)
	for cat2 in by_cat:      # unknown categories last
		_cats.append({"key": cat2, "name": String(cat2).capitalize(), "weapons": by_cat[cat2]})
	var n := _cats.size()
	var span := TAU / maxf(n, 1)
	for i in n:
		var mid := -PI * 0.5 + span * i
		_cats[i]["a0"] = mid - span * 0.5
		_cats[i]["a1"] = mid + span * 0.5


# ---- Input -------------------------------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		_update_from_vector((event as InputEventMouseMotion).position - get_viewport_rect().size * 0.5, true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"weapon_next"):
		_cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"weapon_prev"):
		_cycle(-1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		close_wheel(true)
		get_viewport().set_input_as_handled()


func _cycle(dir: int) -> void:
	var flat: Array = []
	for ci in _cats.size():
		for wi in (_cats[ci]["weapons"] as Array).size():
			flat.append(Vector2i(ci, wi))
	var idx := flat.find(Vector2i(_sel_cat, _sel_w))
	idx = posmod(idx + dir, flat.size())
	_set_selection(flat[idx].x, flat[idx].y)


func _update_from_vector(v: Vector2, from_mouse: bool) -> void:
	if v.length() < DEAD_ZONE:
		return
	_moved = true
	var ang := atan2(v.y, v.x)
	var n := _cats.size()
	var span := TAU / maxf(n, 1)
	var rel := wrapf(ang + PI * 0.5 + span * 0.5, 0.0, TAU)       # 0 at the start of sector 0
	var ci := clampi(int(floor(rel / span)), 0, n - 1)
	var ws: Array = _cats[ci]["weapons"]
	var wi := 0
	if ci == _sel_cat:
		wi = _sel_w
	else:
		var f := ws.find(current)
		wi = f if f >= 0 else 0
	if v.length() > R_OUT + 4.0:
		var frac := (rel - ci * span) / span
		wi = clampi(int(floor(frac * ws.size())), 0, ws.size() - 1)
	_set_selection(ci, wi)


func _set_selection(ci: int, wi: int) -> void:
	if ci == _sel_cat and wi == _sel_w:
		return
	_sel_cat = ci
	_sel_w = wi
	selected = _cats[ci]["weapons"][wi]
	Sfx.play_ui(&"ui_click", -6.0)
	selection_changed.emit(selected)
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_open:
		set_process(false)
		return
	var now := Time.get_ticks_usec()
	var dt := minf(float(now - _last_us) / 1000000.0, 0.1)
	_last_us = now
	_t += dt
	# gamepad sticks (right stick preferred, left as fallback)
	var sv := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if sv.length() < 0.35:
		sv = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if sv.length() > 0.5:
		_update_from_vector(sv.normalized() * (R_OUT * 0.7), false)
	queue_redraw()


# ---- Drawing ---------------------------------------------------------------------------------------------------------------
func _ammo_text(id: StringName) -> String:
	var info := UIIcons.weapon_info(id)
	if info["category"] == &"melee":
		return ""
	var a: Array = _ammo.get(id, [0, 0])
	if info["category"] == &"thrown":
		return "x%d" % (int(a[0]) + int(a[1]))
	return "%d / %d" % [int(a[0]), int(a[1])]


func _draw() -> void:
	if not is_open:
		return
	var a_open := UIDraw.ease_out(_t / 0.18)
	var vs := get_viewport_rect().size
	var c := vs * 0.5
	# backdrop
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.02, 0.04, 0.55 * a_open))
	var o := c
	var fd := UITheme.font_display()
	var f := UITheme.font(true)
	var n := _cats.size()
	for i in n:
		var cat: Dictionary = _cats[i]
		var gap := 0.035 if n > 1 else 0.0
		var a0: float = cat["a0"] + gap
		var a1: float = cat["a1"] - gap
		var sel := i == _sel_cat
		var fill := Color(0.05, 0.075, 0.11, 0.9 * a_open)
		if sel:
			fill = Color(UITheme.C_ACCENT.r * 0.3, UITheme.C_ACCENT.g * 0.4, UITheme.C_ACCENT.b * 0.45, 0.92 * a_open)
		var pts := UIDraw.sector_points(o, R_IN, R_OUT, a0, a1)
		if n == 1:
			pts = UIDraw.sector_points(o, R_IN, R_OUT, a0 + 0.02, a1 - 0.02, 64)
		draw_colored_polygon(pts, fill)
		var edge := Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, 0.95 * a_open) if sel else Color(1, 1, 1, 0.1 * a_open)
		draw_arc(o, R_OUT, a0, a1, 24, edge, 3.0 if sel else 1.5, true)
		draw_arc(o, R_IN, a0, a1, 24, edge, 1.5, true)
		# icon: representative weapon (current if in this category)
		var ws: Array = cat["weapons"]
		var rep: StringName = current if ws.has(current) else ws[0]
		if sel:
			rep = ws[_sel_w]
		var mid := (a0 + a1) * 0.5
		var ip := o + Vector2(cos(mid), sin(mid)) * (R_IN + R_OUT) * 0.5
		var isz := 92.0 if n <= 4 else 76.0
		var irect := Rect2(ip - Vector2(isz, isz * 0.5) * 0.5 + Vector2(0, -10), Vector2(isz, isz * 0.5))
		UIIcons.draw_weapon(self, rep, irect, Color(1, 1, 1, (0.98 if sel else 0.6) * a_open))
		var ctext := String(cat["name"]).to_upper()
		if ws.size() > 1:
			ctext += "  (%d)" % ws.size()
		UIDraw.text_center(self, f, ctext, ip + Vector2(0, 24), 14, Color(1, 1, 1, (0.92 if sel else 0.5) * a_open))
	# outer ring: weapons of the selected category
	if n > 0:
		var cat2: Dictionary = _cats[_sel_cat]
		var ws2: Array = cat2["weapons"]
		var span: float = float(cat2["a1"]) - float(cat2["a0"])
		var base: float = cat2["a0"]
		var wn := ws2.size()
		var each := span / wn
		for wi in wn:
			var b0 := base + each * wi + 0.02
			var b1 := base + each * (wi + 1) - 0.02
			var wsel := wi == _sel_w
			var id: StringName = ws2[wi]
			var fill2 := Color(0.05, 0.075, 0.11, 0.92 * a_open)
			if wsel:
				fill2 = Color(UITheme.C_ACCENT.r * 0.5, UITheme.C_ACCENT.g * 0.6, UITheme.C_ACCENT.b * 0.65, 0.96 * a_open)
			draw_colored_polygon(UIDraw.sector_points(o, R_W_IN, R_W_OUT, b0, b1, 20), fill2)
			var e2 := Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a_open) if wsel else Color(1, 1, 1, 0.12 * a_open)
			draw_arc(o, R_W_OUT, b0, b1, 20, e2, 3.0 if wsel else 1.5, true)
			var m2 := (b0 + b1) * 0.5
			var chord := 2.0 * (R_W_IN + R_W_OUT) * 0.5 * sin(minf((b1 - b0) * 0.5, PI * 0.5))
			var w_sz := clampf(chord * 0.82, 50.0, 112.0)
			var wp := o + Vector2(cos(m2), sin(m2)) * (R_W_IN + R_W_OUT) * 0.5
			UIIcons.draw_weapon(self, id, Rect2(wp - Vector2(w_sz, w_sz * 0.5) * 0.5, Vector2(w_sz, w_sz * 0.5)), Color(1, 1, 1, (1.0 if wsel else 0.62) * a_open))
			if id == current:
				draw_circle(o + Vector2(cos(m2), sin(m2)) * (R_W_OUT - 11.0), 4.5, Color(UITheme.C_OK.r, UITheme.C_OK.g, UITheme.C_OK.b, a_open))
	# hub
	draw_circle(o, R_HUB + 4.0, Color(0, 0, 0, 0.5 * a_open))
	draw_circle(o, R_HUB, Color(0.035, 0.05, 0.075, 0.96 * a_open))
	draw_arc(o, R_HUB, 0.0, TAU, 64, Color(1, 1, 1, 0.14 * a_open), 2.0, true)
	if selected != &"":
		var info := UIIcons.weapon_info(selected)
		UIIcons.draw_weapon(self, selected, Rect2(o + Vector2(-70, -64), Vector2(140, 70)), Color(1, 1, 1, a_open))
		UIDraw.text_center(self, f, String(info["name"]).to_upper(), o + Vector2(0, 26), 17, Color(1, 1, 1, a_open))
		var at := _ammo_text(selected)
		if at != "":
			UIDraw.text_center(self, fd, at, o + Vector2(0, 62), 32, Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a_open))
		elif selected == current:
			UIDraw.text_center(self, f, "EQUIPPED", o + Vector2(0, 58), 15, Color(UITheme.C_OK.r, UITheme.C_OK.g, UITheme.C_OK.b, a_open))
	# pointer toward the mouse
	var mv := get_viewport().get_mouse_position() - c
	if _moved and mv.length() > DEAD_ZONE:
		var d := mv.normalized()
		UIDraw.triangle(self, o + d * (R_HUB - 12.0), 9.0, atan2(d.x, -d.y), Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a_open))
	# hint
	UIDraw.text_center(self, f, "RELEASE TO EQUIP   -   MOVE MOUSE TO SELECT   -   SCROLL TO CYCLE", Vector2(c.x, vs.y - 150.0), 17, Color(1, 1, 1, 0.55 * a_open))
