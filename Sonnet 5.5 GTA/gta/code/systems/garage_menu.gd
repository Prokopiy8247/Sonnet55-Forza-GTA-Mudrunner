class_name GarageMenu
extends MenuBase
## Customization menu of the garage (menu id &"garage"). Left: categories + options, right: vehicle stats (before / after), pending
## changes with prices, Install / Revert / Store / Exit. The 3D view (studio + orbit camera) stays visible in the middle; dragging
## the mouse there orbits the car, the wheel zooms. Everything is a PREVIEW on the real vehicle until "Install" pays for it.

const PANEL_W := 640.0
const RIGHT_W := 440.0

var session: GarageSession = null
var _cats: Array[StringName] = []
var _cat := 0
var _cat_btns: Array[Button] = []
var _opts: VBoxContainer = null
var _right_box: VBoxContainer = null
var _pending_box: VBoxContainer = null
var _stat_box: VBoxContainer = null
var _total_label: Label = null
var _cash_label: Label = null
var _title_lbl: Label = null
var _apply_btn: Button = null
var _revert_btn: Button = null
var _paint_target := 0                  # 0 primary, 1 secondary
var _body_slot: StringName = &"spoiler"
var _light_section := 0
var _drag := false
var _sub := 0
var _left_panel: Control = null
var _right_panel: Control = null


func _init() -> void:
	super._init()
	dim_background = false
	pauses_game = true
	wants_cursor = true


func _on_open(open_data: Dictionary) -> void:
	session = open_data.get("session", null)
	if session == null:
		push_warning("GarageMenu opened without a session")
		close()
		return
	_cats.clear()
	for c in VehicleModsData.categories_for(session.vehicle.def_id):
		_cats.append(c)
	_cat = 0
	_build_layout()
	_show_category(0)
	if not Events.cash_changed.is_connected(_on_cash):
		Events.cash_changed.connect(_on_cash)


func _on_close() -> void:
	if Events.cash_changed.is_connected(_on_cash):
		Events.cash_changed.disconnect(_on_cash)


func _on_cash(_a: int, _d: int) -> void:
	if is_open:
		_refresh_summary()
		_refresh_options_prices()


func on_back() -> bool:
	if session != null and session.has_pending():
		confirm("Discard changes?", "Your unpaid changes (%s) will be lost." % Util.format_money(session.total_cost()), func():
			session.revert_pending()
			close(), Callable(), "Discard", "Keep editing")
		return true
	return false


# =====================================================================================================
# Layout
# =====================================================================================================
func _build_layout() -> void:
	for c in get_children():
		c.queue_free()
	_cat_btns.clear()
	# ---- left panel
	var left := UIKit.panel(&"PanelHi")
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 44
	left.offset_right = 44 + PANEL_W
	left.offset_top = 44
	left.offset_bottom = -44
	left.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(left)
	# the content sits in a clipping holder: whatever a page puts inside can never widen the panel (it stays PANEL_W, the 3D view stays free)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(PANEL_W - 70.0, 0)
	holder.clip_contents = true
	left.add_child(holder)
	var lv := UIKit.vbox(12)
	lv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(lv)
	_left_panel = left
	var hdr := UIKit.header(String(session.site.get("name", VehicleModsData.SHOP_NAME)), "Customization")
	_title_lbl = hdr.get_child(1) as Label
	lv.add_child(hdr)
	lv.add_child(UIKit.separator())
	var cols := UIKit.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(cols)
	var catv := UIKit.vbox(6)
	catv.custom_minimum_size = Vector2(176, 0)
	cols.add_child(catv)
	var grp := ButtonGroup.new()
	for i in _cats.size():
		var b := Button.new()
		b.text = String(VehicleModsData.CATEGORY_NAMES.get(_cats[i], _cats[i])).to_upper()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_ALL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 46)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		b.pressed.connect(func():
			UIKit.click()
			_show_category(idx))
		catv.add_child(b)
		_cat_btns.append(b)
	var sc_list := UIKit.scroll_list(8)
	cols.add_child(sc_list.get_parent())
	_opts = sc_list
	# ---- right panel
	var right := UIKit.panel(&"PanelHi")
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -44 - RIGHT_W
	right.offset_right = -44
	right.offset_top = 44
	right.offset_bottom = -44
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(right)
	_right_panel = right
	_right_box = UIKit.vbox(10)
	right.add_child(_right_box)
	var veh_name := UIKit.label(session.vehicle.display_name, 30, UITheme.C_TEXT, true)
	_right_box.add_child(veh_name)
	_cash_label = UIKit.label("", 22, UITheme.C_OK, true)
	_right_box.add_child(_cash_label)
	_right_box.add_child(UIKit.separator())
	_right_box.add_child(UIKit.caption("Performance"))
	_stat_box = UIKit.vbox(6)
	_right_box.add_child(_stat_box)
	_right_box.add_child(UIKit.separator())
	_right_box.add_child(UIKit.caption("Pending changes"))
	var pl := UIKit.scroll_list(4)
	_right_box.add_child(pl.get_parent())
	_pending_box = pl
	_total_label = UIKit.label("", 26, UITheme.C_TEXT, true)
	_right_box.add_child(_total_label)
	_apply_btn = UIKit.button("Install changes", func(): _on_apply(), &"AccentButton")
	_apply_btn.custom_minimum_size = Vector2(0, 52)
	_right_box.add_child(_apply_btn)
	var row := UIKit.hbox(8)
	_revert_btn = UIKit.button("Revert", func(): _on_revert())
	_revert_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_revert_btn)
	var store := UIKit.button("Store in garage", func(): _on_store())
	store.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(store)
	_right_box.add_child(row)
	var exit := UIKit.button("Exit garage", func(): _on_exit(), &"DangerButton")
	exit.custom_minimum_size = Vector2(0, 48)
	_right_box.add_child(exit)
	# ---- hints (bottom centre)
	var hb := UIKit.hbox(26)
	hb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hb.offset_top = -64
	hb.offset_bottom = -22
	hb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	_hints_box = hb
	set_hints([["Drag", "Orbit"], ["Wheel", "Zoom"], ["A D", "Rotate"], ["W S", "Tilt"], ["Q E", "Zoom"], ["Esc", "Leave"]])
	_refresh_summary()


func _on_exit() -> void:
	if session.has_pending():
		on_back()
		return
	close()


func _on_apply() -> void:
	if session.apply_pending():
		_refresh_summary()
		_show_category(_cat, false)


func _on_revert() -> void:
	session.revert_pending()
	_refresh_summary()
	_show_category(_cat, false)


func _on_store() -> void:
	if session.system.free_slot_count() <= 0 and int(session.vehicle.get_meta(&"garage_slot", -1)) < 0:
		Game.notify("Your garage is full (%d/%d)." % [GarageSystem.MAX_SLOTS, GarageSystem.MAX_SLOTS], &"warn")
		return
	var name_ := session.vehicle.display_name
	confirm("Store %s?" % name_, "The vehicle goes into your garage. Unpaid changes are discarded. Call it back from the phone (P).", func():
		session.store_vehicle()
		var p = Game.player
		if is_instance_valid(p):
			p.teleport_to(session.exit_xf.origin + Vector3(0, 0.3, 0), session.exit_xf.basis.get_euler().y)
		close(), Callable(), "Store", "Cancel")


# ---- drag orbit / zoom on the empty centre -----------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if session == null or session.cam == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			session.cam.zoom(-0.45)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			session.cam.zoom(0.45)
	elif event is InputEventMouseMotion and _drag:
		var rel := (event as InputEventMouseMotion).relative
		session.cam.orbit(rel.x, rel.y)


# =====================================================================================================
# Categories
# =====================================================================================================
func _show_category(idx: int, refocus: bool = true) -> void:
	_cat = clampi(idx, 0, _cats.size() - 1)
	if _cat < _cat_btns.size() and not _cat_btns[_cat].button_pressed:
		_cat_btns[_cat].button_pressed = true
	for c in _opts.get_children():
		c.queue_free()
	var cat := _cats[_cat]
	match cat:
		&"repair":
			_page_repair()
		&"paint":
			_page_paint()
		&"wheels":
			_page_wheels()
		&"body":
			_page_body()
		&"lights":
			_page_lights()
		&"windows":
			_page_windows()
		&"plates":
			_page_plates()
		&"livery":
			_page_livery()
		&"horn":
			_page_horn()
		&"performance":
			_page_performance()
	if refocus:
		var topic: StringName = cat
		if cat == &"body":
			topic = _body_slot
		elif cat == &"lights":
			topic = [&"headlight", &"taillight", &"underglow"][_light_section]
		session.focus_on(topic)
	_refresh_summary()
	_refresh_gap()


## UIKit.slider_row reserves 250 px for its label and 260 px for the slider: shrink both so the row fits the 640 px garage panel.
func _compact_slider(row: HBoxContainer) -> HBoxContainer:
	(row.get_child(0) as Control).custom_minimum_size = Vector2(112, 0)
	(row.get_child(1) as Control).custom_minimum_size = Vector2(120, 30)
	(row.get_child(2) as Control).custom_minimum_size = Vector2(70, 0)
	row.add_theme_constant_override("separation", 10)
	return row


## Tells the orbit camera where the free 3D area between the two panels is so the car is centred in it (not behind a panel).
func _refresh_gap() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_open or session == null or session.cam == null or not is_instance_valid(session.cam):
		return
	var vw := get_viewport().get_visible_rect().size.x
	var l: float = _left_panel.get_global_rect().end.x if _left_panel != null else 0.0
	var r: float = _right_panel.get_global_rect().position.x if _right_panel != null else vw
	session.cam.screen_shift = clampf(((l + r) * 0.5) / maxf(vw, 1.0) - 0.5, -0.3, 0.3)


## Money formatting with the vehicle class multiplier (and the unlock-all flag).
func _price(base: int) -> int:
	if session.system.is_free():
		return 0
	return int(round(float(base) * VehicleModsData.price_mult(session.vehicle.def_id) / 10.0)) * 10


func _section(text: String) -> void:
	_opts.add_child(UIKit.caption(text))


func _chips(names: Array, selected: int, cb: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grp := ButtonGroup.new()
	for i in names.size():
		var b := Button.new()
		b.text = String(names[i])
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_ALL
		b.button_pressed = (i == selected)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		b.pressed.connect(func():
			UIKit.click()
			cb.call(idx))
		f.add_child(b)
	return f


## A selectable row. `installed` = it is what the vehicle already has; `selected` = the pending choice.
func _option_row(title: String, sub: String, base_price: int, selected: bool, installed: bool, cb: Callable) -> Button:
	var right: Variant = _price(base_price)
	if installed:
		right = "INSTALLED"
	var b := UIKit.list_row(title, sub, right, cb)
	b.toggle_mode = true
	b.button_pressed = selected
	return b


func _swatch(c: Color, selected: bool, tip: String, cb: Callable, size_px: float = 46.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c if c.r >= 0.0 else Color(0.25, 0.27, 0.3)
		sb.set_corner_radius_all(9)
		sb.set_border_width_all(3 if selected or st == "focus" else (2 if st == "hover" else 1))
		sb.border_color = Color(1, 1, 1, 0.95) if selected else (UITheme.C_ACCENT if st != "normal" else Color(1, 1, 1, 0.18))
		b.add_theme_stylebox_override(st, sb)
	if c.r < 0.0:
		b.text = "S"
	b.pressed.connect(func():
		UIKit.click()
		cb.call())
	return b


func _swatch_grid(colors: Array, selected_color: Variant, cb: Callable, cols: int = 7) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for entry in colors:
		var c: Color = entry["color"]
		var sel := false
		if selected_color is Color:
			sel = (selected_color as Color).is_equal_approx(c)
		elif selected_color == null:
			sel = c.r < 0.0
		var col_cap := c
		g.add_child(_swatch(c, sel, String(entry["name"]), func(): cb.call(col_cap), 46.0 if cols <= 7 else 42.0))
	return g


# ---------------------------------------------------------------------------------------------------- REPAIR
func _page_repair() -> void:
	var v := session.vehicle
	_section("Condition")
	var hp := v.get_health_ratio()
	var glass := "Intact"
	if v.dmg != null:
		glass = ["Intact", "Cracked", "Shattered"][clampi(v.dmg.glass_state, 0, 2)]
	var flat := 0
	for w in v.wheels:
		if w.flat:
			flat += 1
	var card := UIKit.panel(&"PanelDeep")
	var cv := UIKit.vbox(8)
	card.add_child(cv)
	var hb := UIKit.bar(hp, UITheme.C_OK if hp > 0.6 else (UITheme.C_WARN if hp > 0.3 else UITheme.C_DANGER), 14)
	cv.add_child(UIKit.stat_row("Body integrity", "%d %%" % int(round(hp * 100.0))))
	cv.add_child(hb)
	cv.add_child(UIKit.stat_row("Glass", glass, UITheme.C_OK if glass == "Intact" else UITheme.C_WARN))
	cv.add_child(UIKit.stat_row("Tyres", "OK" if flat == 0 else "%d flat" % flat, UITheme.C_OK if flat == 0 else UITheme.C_WARN))
	cv.add_child(UIKit.stat_row("Handling / engine", "Nominal" if hp > 0.55 else "Degraded", UITheme.C_OK if hp > 0.55 else UITheme.C_DANGER))
	_opts.add_child(card)
	var cost := session.system.repair_cost(v)
	var need := session.system.repair_needed(v)
	if need:
		var shown := 0 if session.system.is_free() else cost
		var b := UIKit.list_row("Repair vehicle", "Restores health, tyres, glass, lights and handling", shown, func():
			if session.repair_now():
				_show_category(_cat, false))
		_opts.add_child(b)
	else:
		_opts.add_child(UIKit.label("The vehicle is in perfect condition.", 22, UITheme.C_OK))


# ---------------------------------------------------------------------------------------------------- PAINT
func _page_paint() -> void:
	var p := session.pending
	_opts.add_child(_chips(["Primary", "Secondary"], _paint_target, func(i: int):
		_paint_target = i
		_show_category(_cat, false)))
	var cur: Color = p.paint1 if _paint_target == 0 else p.paint2
	_section("Colour" + (" (+%s)" % Util.format_money(_price(VehicleModsData.PAINT_PRICE)) if not session.system.is_free() else ""))
	_opts.add_child(_swatch_grid(VehicleModsData.palette(), cur, func(c: Color):
		if _paint_target == 0:
			p.paint1 = c
		else:
			p.paint2 = c
		session.preview()
		_show_category(_cat, false), 7))
	# custom colour (HSV)
	_section("Custom")
	var h := cur.h
	var s := cur.s
	var vv := cur.v
	var set_hsv := func():
		var c := Color.from_hsv(h, s, vv)
		if _paint_target == 0:
			p.paint1 = c
		else:
			p.paint2 = c
		session.preview()
		_refresh_summary()
	_opts.add_child(_compact_slider(UIKit.slider_row("Hue", 0.0, 1.0, h, 0.005, func(x: float):
		h = x
		set_hsv.call(), func(x: float): return "%d" % int(x * 360.0))))
	_opts.add_child(_compact_slider(UIKit.slider_row("Saturation", 0.0, 1.0, s, 0.01, func(x: float):
		s = x
		set_hsv.call(), func(x: float): return "%d %%" % int(x * 100.0))))
	_opts.add_child(_compact_slider(UIKit.slider_row("Brightness", 0.0, 1.0, vv, 0.01, func(x: float):
		vv = x
		set_hsv.call(), func(x: float): return "%d %%" % int(x * 100.0))))
	_section("Finish")
	for f in VehicleModsData.FINISHES:
		var id: StringName = f["id"]
		_opts.add_child(_option_row(String(f["name"]), "", int(f["price"]), p.finish == id, session.committed.finish == id, func():
			p.finish = id
			session.preview()
			_show_category(_cat, false)))


# ---------------------------------------------------------------------------------------------------- WHEELS
func _page_wheels() -> void:
	var p := session.pending
	var kind := String(VehicleModsData.vehicle_cfg(session.vehicle.def_id).get("kind", "car"))
	_section("Rim style")
	for r in VehicleModsData.rims_for(kind):
		var id: StringName = r["id"]
		_opts.add_child(_option_row(String(r["name"]), "", int(r["price"]), p.get_id("rim_style") == id, session.committed.get_id("rim_style") == id, func():
			p.set_id("rim_style", id)
			session.preview()
			_show_category(_cat, false)))
	_section("Wheel colour")
	var cur: Variant = p.mods.get("rim_color", null)
	_opts.add_child(_swatch_grid(VehicleModsData.RIM_COLORS, cur, func(c: Color):
		if c.r < 0.0:
			p.mods.erase("rim_color")
		else:
			p.mods["rim_color"] = c
		session.preview()
		_show_category(_cat, false), 6))
	_section("Tyres")
	var pd := VehicleModsData.perf_def("tires")
	var lv: Array = pd["levels"]
	for i in lv.size():
		var idx := i
		var cost_from_committed := VehicleModsData.perf_cost("tires", session.committed.level("tires"), idx)
		_opts.add_child(_option_row(String(lv[i]["name"]), String(lv[i]["desc"]), cost_from_committed, p.level("tires") == idx, session.committed.level("tires") == idx, func():
			p.set_level("tires", idx)
			session.preview()
			_show_category(_cat, false)))


# ---------------------------------------------------------------------------------------------------- BODY
func _page_body() -> void:
	var p := session.pending
	var slots: Array = VehicleModsData.slots_for(session.vehicle.def_id)
	if slots.is_empty():
		_opts.add_child(UIKit.label("No body parts available for this vehicle.", 22, UITheme.C_DIM))
		return
	if not slots.has(_body_slot):
		_body_slot = slots[0]
	var names: Array = []
	var sel := 0
	for i in slots.size():
		names.append(VehicleModsData.SLOT_NAMES.get(slots[i], slots[i]))
		if slots[i] == _body_slot:
			sel = i
	_opts.add_child(_chips(names, sel, func(i: int):
		_body_slot = slots[i]
		session.focus_on(_body_slot)
		_show_category(_cat, false)))
	_section(String(VehicleModsData.SLOT_NAMES.get(_body_slot, _body_slot)))
	for o in VehicleModsData.slot_options_for(session.vehicle.def_id, _body_slot):
		var id: StringName = o["id"]
		_opts.add_child(_option_row(String(o["name"]), "", int(o["price"]), p.part(_body_slot) == id, session.committed.part(_body_slot) == id, func():
			p.set_part(_body_slot, id)
			session.preview()
			_show_category(_cat, false)))


# ---------------------------------------------------------------------------------------------------- LIGHTS
func _page_lights() -> void:
	var p := session.pending
	_opts.add_child(_chips(["Headlights", "Tail lights", "Underglow"], _light_section, func(i: int):
		_light_section = i
		session.focus_on([&"headlight", &"taillight", &"underglow"][i])
		_show_category(_cat, false)))
	var table: Array = VehicleModsData.HEADLIGHTS
	var key := "headlight"
	var def_id := "stock"
	match _light_section:
		1:
			table = VehicleModsData.TAILLIGHTS
			key = "taillight"
		2:
			table = VehicleModsData.UNDERGLOW
			key = "underglow"
			def_id = "off"
	for o in table:
		var id: StringName = o["id"]
		var col: Color = o["color"]
		var row := _option_row(String(o["name"]), "", int(o["price"]), p.get_id(key, def_id) == id, session.committed.get_id(key, def_id) == id, func():
			p.set_id(key, id, def_id)
			session.preview()
			_show_category(_cat, false))
		_opts.add_child(row)
		if col.r >= 0.0 and col.a > 0.0:
			var dot := ColorRect.new()
			dot.color = col
			dot.custom_minimum_size = Vector2(8, 0)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
			dot.offset_right = 6
			row.add_child(dot)


# ---------------------------------------------------------------------------------------------------- WINDOWS
func _page_windows() -> void:
	var p := session.pending
	_section("Window tint")
	for i in VehicleModsData.WINDOW_TINTS.size():
		var t: Dictionary = VehicleModsData.WINDOW_TINTS[i]
		var idx := i
		var base_price := int(t["price"]) if idx > session.committed.level("window_tint") else 0
		_opts.add_child(_option_row(String(t["name"]), String(t["desc"]), base_price, p.level("window_tint") == idx, session.committed.level("window_tint") == idx, func():
			p.set_level("window_tint", idx)
			session.preview()
			_show_category(_cat, false)))


# ---------------------------------------------------------------------------------------------------- PLATES
func _page_plates() -> void:
	var p := session.pending
	_section("Licence plate")
	var text := String(p.mods.get("plate_text", "HB 0000"))
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(224, 112)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var cur_style := String(p.mods.get("plate", ""))
	var style_dict: Dictionary = VehicleModsData.PLATES[0]
	for sd in VehicleModsData.PLATES:
		if String(sd["id"]) == cur_style:
			style_dict = sd
	tex_rect.texture = VehicleModsDecals.plate_texture(style_dict, text)
	var prev_row := UIKit.hbox(12)
	prev_row.add_child(tex_rect)
	var shuffle := UIKit.button("New number", func():
		p.mods["plate_text"] = VehicleModsData.random_plate_text(Game.rng)
		session.preview()
		_show_category(_cat, false))
	shuffle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prev_row.add_child(shuffle)
	_opts.add_child(prev_row)
	_opts.add_child(_option_row("Stock plate", "Factory plate", 0, cur_style == "", session.committed.get_id("plate", "") == &"", func():
		p.mods.erase("plate")
		session.preview()
		_show_category(_cat, false)))
	for sd in VehicleModsData.PLATES:
		var id: StringName = sd["id"]
		_opts.add_child(_option_row(String(sd["name"]), "", int(sd["price"]), cur_style == String(id), session.committed.get_id("plate", "") == id, func():
			p.mods["plate"] = String(id)
			session.preview()
			_show_category(_cat, false)))


# ---------------------------------------------------------------------------------------------------- LIVERY
func _page_livery() -> void:
	var p := session.pending
	_section("Stripe pack")
	for l in VehicleModsData.LIVERIES:
		var id: StringName = l["id"]
		_opts.add_child(_option_row(String(l["name"]), "", int(l["price"]), p.get_id("livery", "none") == id, session.committed.get_id("livery", "none") == id, func():
			if id == &"none":
				p.mods.erase("livery")
			else:
				p.mods["livery"] = String(id)
				if not p.mods.has("livery_color"):
					p.mods["livery_color"] = VehicleModsData.LIVERY_COLORS[0]["color"]
			session.preview()
			_show_category(_cat, false)))
	_section("Stripe colour")
	var cur: Variant = p.mods.get("livery_color", null)
	_opts.add_child(_swatch_grid(VehicleModsData.LIVERY_COLORS, cur, func(c: Color):
		p.mods["livery_color"] = c
		session.preview()
		_show_category(_cat, false), 8))


# ---------------------------------------------------------------------------------------------------- HORN
func _page_horn() -> void:
	var p := session.pending
	_section("Horn")
	for i in VehicleModsData.HORNS.size():
		var h: Dictionary = VehicleModsData.HORNS[i]
		var idx := i
		var b := _option_row(String(h["name"]), "click to preview", int(h["price"]), int(p.mods.get("horn", 0)) == idx, int(session.committed.mods.get("horn", 0)) == idx, func():
			if idx == 0:
				p.mods.erase("horn")
			else:
				p.mods["horn"] = idx
			session.preview()
			var snd := String(h["sound"]) if idx > 0 else String(session.vehicle.def.get("horn", "horn_car"))
			if Sfx != null and Sfx.has_sound(StringName(snd)):
				Sfx.play_2d(StringName(snd), -2.0, float(h["pitch"]) if idx > 0 else 1.0)
			_show_category(_cat, false))
		_opts.add_child(b)


# ---------------------------------------------------------------------------------------------------- PERFORMANCE
func _page_performance() -> void:
	var p := session.pending
	for pd in VehicleModsData.performance():
		var key: String = pd["key"]
		var lv: Array = pd["levels"]
		var maxl := lv.size() - 1
		var cur := p.level(key)
		var card := UIKit.panel(&"PanelDeep")
		var cv := UIKit.vbox(6)
		card.add_child(cv)
		var top := UIKit.hbox(8)
		var tl := UIKit.label(String(pd["name"]), 22, UITheme.C_TEXT, true)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(tl)
		top.add_child(UIKit.label(String(lv[cur]["name"]), 20, UITheme.C_ACCENT, true, HORIZONTAL_ALIGNMENT_RIGHT))
		cv.add_child(top)
		var dl := UIKit.label(String(pd["desc"]), 17, UITheme.C_DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(dl)
		var pips := UIKit.hbox(5)
		for i in range(1, maxl + 1):
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(0, 8)
			pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pip.color = UITheme.C_ACCENT if i <= cur else Color(1, 1, 1, 0.13)
			if i <= session.committed.level(key) and i <= cur:
				pip.color = UITheme.C_OK
			pips.add_child(pip)
		cv.add_child(pips)
		var btns := UIKit.hbox(8)
		var minus := UIKit.button("-", func():
			p.set_level(key, cur - 1)
			session.preview()
			_show_category(_cat, false))
		minus.custom_minimum_size = Vector2(52, 44)
		minus.disabled = cur <= 0
		btns.add_child(minus)
		var next_txt := "Max level"
		var plus_cost := 0
		if cur < maxl:
			plus_cost = _price(VehicleModsData.perf_cost(key, session.committed.level(key), cur + 1) - VehicleModsData.perf_cost(key, session.committed.level(key), cur)) if cur >= session.committed.level(key) else 0
			next_txt = "+ %s" % lv[cur + 1]["name"]
		var plus := UIKit.button(next_txt, func():
			p.set_level(key, cur + 1)
			session.preview()
			_show_category(_cat, false), &"AccentButton")
		plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plus.clip_text = true
		plus.disabled = cur >= maxl
		btns.add_child(plus)
		if cur < maxl:
			btns.add_child(UIKit.price_tag(plus_cost))
		cv.add_child(btns)
		if cur < maxl:
			cv.add_child(UIKit.label(String(lv[cur + 1]["desc"]), 16, UITheme.C_OK))
		_opts.add_child(card)


# =====================================================================================================
# Summary (right panel)
# =====================================================================================================
func _refresh_options_prices() -> void:
	pass


func _refresh_summary() -> void:
	if session == null or _stat_box == null or not is_instance_valid(_stat_box):
		return
	_cash_label.text = "Cash %s%s" % [Util.format_money(Game.cash), "   (all upgrades unlocked)" if session.system.is_free() else ""]
	# ---- stats
	for c in _stat_box.get_children():
		c.queue_free()
	var a := VehicleModsData.stat_summary(session.committed.mods)
	var b := VehicleModsData.stat_summary(session.pending.mods)
	var rows := [
		["Top speed", _top_speed_ratio(b) / _top_speed_ratio(a), _top_speed_ratio(b)],
		["Acceleration", _accel_ratio(b) / _accel_ratio(a), _accel_ratio(b)],
		["Braking", float(b["brake"]) / float(a["brake"]), float(b["brake"])],
		["Handling", _handling_ratio(b) / _handling_ratio(a), _handling_ratio(b)],
		["Armour", _armor_ratio(b) / _armor_ratio(a), _armor_ratio(b)],
	]
	for r in rows:
		var ratio: float = r[1]
		var base_fill := _fill_for(r[0], a)
		var fill := clampf(base_fill * float(r[2]), 0.04, 1.0)
		var hb := UIKit.hbox(10)
		var l := UIKit.label(String(r[0]), 18, UITheme.C_DIM)
		l.custom_minimum_size = Vector2(120, 0)
		hb.add_child(l)
		var bar := UIKit.bar(fill, UITheme.C_ACCENT if ratio <= 1.001 else UITheme.C_OK, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(bar)
		var d := (ratio - 1.0) * 100.0
		var dl := UIKit.label("" if absf(d) < 0.5 else "%+d %%" % int(round(d)), 18, UITheme.C_OK if d > 0 else UITheme.C_WARN, true, HORIZONTAL_ALIGNMENT_RIGHT)
		dl.custom_minimum_size = Vector2(64, 0)
		hb.add_child(dl)
		_stat_box.add_child(hb)
	# ---- pending list
	for c in _pending_box.get_children():
		c.queue_free()
	var entries := session.quote()
	if entries.is_empty():
		_pending_box.add_child(UIKit.label("No changes yet.", 18, UITheme.C_DIM))
	for e in entries:
		var hb2 := UIKit.hbox(8)
		var lb := UIKit.label(String(e["label"]), 18, UITheme.C_TEXT)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.clip_text = true
		hb2.add_child(lb)
		hb2.add_child(UIKit.label("FREE" if int(e["price"]) <= 0 else Util.format_money(int(e["price"])), 18, UITheme.C_OK if int(e["price"]) <= 0 else UITheme.C_WARN, true, HORIZONTAL_ALIGNMENT_RIGHT))
		_pending_box.add_child(hb2)
	var total := GarageBuild.total_cost(entries)
	var affordable := Game.can_afford(total)
	_total_label.text = "Total  %s" % ("FREE" if total <= 0 else Util.format_money(total))
	_total_label.add_theme_color_override("font_color", UITheme.C_TEXT if affordable else UITheme.C_DANGER)
	_apply_btn.text = "Install changes" if not entries.is_empty() else "Nothing to install"
	_apply_btn.disabled = entries.is_empty() or not affordable
	_revert_btn.disabled = entries.is_empty()


func _top_speed_ratio(s: Dictionary) -> float:
	return pow(float(s["power"]) * (1.0 + float(s["turbo_boost"]) * 0.6), 1.0 / 3.0) * (1.0 - minf(float(s["downforce"]) * 0.02, 0.05))


func _accel_ratio(s: Dictionary) -> float:
	return float(s["power"]) * (1.0 + float(s["turbo_boost"]) * 0.7) / float(s["mass"]) * (1.0 + (1.0 - float(s["shift_time"])) * 0.05)


func _handling_ratio(s: Dictionary) -> float:
	return float(s["grip"]) * pow(float(s["susp_freq"]), 0.35) * (1.0 + float(s["downforce"]) * 0.03)


func _armor_ratio(s: Dictionary) -> float:
	return float(s["health"]) / float(s["damage_taken"])


func _fill_for(stat_name: String, committed_stats: Dictionary) -> float:
	# stock vehicles show a mid-range bar derived from the def; upgrades push it toward 100 %
	var d := session.vehicle.def
	match stat_name:
		"Top speed":
			return clampf(float(d.get("top_speed_kmh", 180.0)) / 280.0, 0.2, 0.8)
		"Acceleration":
			return clampf(float(d.get("power_kw", 100.0)) / maxf(float(d.get("mass", 1400.0)), 300.0) * 3.2, 0.15, 0.8)
		"Braking":
			return clampf(float(d.get("brake", 11.0)) / 18.0, 0.2, 0.75)
		"Handling":
			return clampf(float(d.get("grip", 1.1)) / 1.9, 0.25, 0.75)
		_:
			return 0.3
