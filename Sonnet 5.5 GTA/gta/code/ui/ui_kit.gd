class_name UIKit
extends RefCounted
## Reusable widget kit for menus (shop, garage, phone, wardrobe, pause...). Every function returns a ready-styled
## Control built on the shared theme (UITheme.build()). All interactive widgets play UI sounds through `Sfx`.
##
##   var body := UIKit.vbox()
##   body.add_child(UIKit.header("Weapon Shop", "Buy and upgrade"))
##   body.add_child(UIKit.slider_row("Volume", 0, 1, 0.8, 0.05, func(v): ..., func(v): return "%d%%" % int(v * 100)))
##   var list := UIKit.scroll_list()
##   list.add_child(UIKit.list_row("Pistol", "Handgun - 12 rounds", 500, func(): buy(&"pistol")))
##   var grid := UIKit.card_grid(3); grid.add_child(UIKit.card("Sedan", "4 doors", 12000, draw_cb, func(): ...))


# ---- Sound helpers ------------------------------------------------------------------------------------------------
static func click() -> void:
	if Sfx != null:
		Sfx.play_ui(&"ui_click")


static func hover_tick() -> void:
	if Sfx != null:
		Sfx.play_ui(&"ui_click", -14.0)


# ---- Basic building blocks --------------------------------------------------------------------------------------------
static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(h: float = 0.0, w: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func label(text: String = "", size: int = UITheme.BASE_SIZE, color: Color = UITheme.C_TEXT, bold: bool = false,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", UITheme.font(true))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func caption(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = &"Caption"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(variation: StringName = &"") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	return p


static func separator() -> HSeparator:
	return HSeparator.new()


static func margin(child: Control, l: int = 0, t: int = 0, r: int = 0, b: int = 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	if child != null:
		m.add_child(child)
	return m


## Section header: accent bar + title (+ optional dim subtitle on the right).
static func header(title: String, subtitle: String = "") -> Control:
	var h := hbox(14)
	var bar := ColorRect.new()
	bar.color = UITheme.C_ACCENT
	bar.custom_minimum_size = Vector2(5, 34)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var t := Label.new()
	t.text = title.to_upper()
	t.theme_type_variation = &"Title"
	h.add_child(t)
	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.theme_type_variation = &"Subtle"
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(s)
	return h


# ---- Buttons ----------------------------------------------------------------------------------------------------------------
## variation: &"" normal, &"AccentButton" primary, &"DangerButton" destructive.
static func button(text: String, cb: Callable = Callable(), variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		click()
		if cb.is_valid():
			cb.call())
	b.mouse_entered.connect(hover_tick)
	return b


## Row of exclusive tab buttons. Returns the HBox; `cb(index)` fires on change. `set_tab(i)` helper via meta "buttons".
static func tab_bar(names: Array, cb: Callable, start: int = 0) -> HBoxContainer:
	var h := hbox(6)
	var group := ButtonGroup.new()
	var btns: Array = []
	for i in names.size():
		var b := Button.new()
		b.text = String(names[i]).to_upper()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.button_pressed = (i == start)
		var idx := i
		b.pressed.connect(func():
			click()
			if cb.is_valid():
				cb.call(idx))
		h.add_child(b)
		btns.append(b)
	h.set_meta(&"buttons", btns)
	return h


static func tab_select(bar: Control, index: int) -> void:
	var btns: Array = bar.get_meta(&"buttons", [])
	if index >= 0 and index < btns.size():
		btns[index].button_pressed = true


# ---- Setting rows --------------------------------------------------------------------------------------------------------------
## Label | slider | value text. cb(value: float); fmt(value) -> String. meta "slider" holds the HSlider.
static func slider_row(text: String, min_v: float, max_v: float, value: float, step: float, cb: Callable, fmt: Callable = Callable()) -> HBoxContainer:
	var row := hbox(16)
	row.custom_minimum_size = Vector2(0, 44)
	var l := label(text, UITheme.BASE_SIZE, UITheme.C_TEXT)
	l.custom_minimum_size = Vector2(250, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(260, 30)
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	var v := label("", UITheme.BASE_SIZE, UITheme.C_ACCENT, true, HORIZONTAL_ALIGNMENT_RIGHT)
	v.custom_minimum_size = Vector2(96, 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	var upd := func(val: float):
		v.text = str(fmt.call(val)) if fmt.is_valid() else str(snappedf(val, step))
	upd.call(value)
	s.value_changed.connect(func(val: float):
		upd.call(val)
		if cb.is_valid():
			cb.call(val))
	s.drag_ended.connect(func(_changed: bool): click())
	row.set_meta(&"slider", s)
	return row


## Label | toggle switch. cb(on: bool). meta "toggle" holds the CheckButton.
static func toggle_row(text: String, value: bool, cb: Callable) -> HBoxContainer:
	var row := hbox(16)
	row.custom_minimum_size = Vector2(0, 44)
	var l := label(text, UITheme.BASE_SIZE, UITheme.C_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_ALL
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.toggled.connect(func(on: bool):
		click()
		if cb.is_valid():
			cb.call(on))
	row.add_child(c)
	row.set_meta(&"toggle", c)
	return row


## Label | dropdown. cb(index: int).
static func option_row(text: String, options: Array, index: int, cb: Callable) -> HBoxContainer:
	var row := hbox(16)
	row.custom_minimum_size = Vector2(0, 48)
	var l := label(text, UITheme.BASE_SIZE, UITheme.C_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var o := OptionButton.new()
	for opt in options:
		o.add_item(String(opt))
	o.selected = clampi(index, 0, maxi(options.size() - 1, 0))
	o.custom_minimum_size = Vector2(240, 0)
	o.item_selected.connect(func(i: int):
		click()
		if cb.is_valid():
			cb.call(i))
	row.add_child(o)
	row.set_meta(&"option", o)
	return row


static func stat_row(text: String, value: String, value_color: Color = UITheme.C_TEXT) -> HBoxContainer:
	var row := hbox(12)
	var l := label(text, 20, UITheme.C_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := label(value, 20, value_color, true, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(v)
	row.set_meta(&"value", v)
	return row


## Slim progress bar (0..1). meta "bar" holds the ProgressBar.
static func bar(ratio: float, color: Color = UITheme.C_ACCENT, height: float = 10.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = ratio
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("fill", UITheme.box(int(height * 0.5), color))
	p.add_theme_stylebox_override("background", UITheme.box(int(height * 0.5), Color(1, 1, 1, 0.1)))
	return p


# ---- Lists ---------------------------------------------------------------------------------------------------------------------------
static func scroll_list(sep: int = 8) -> VBoxContainer:
	## Returns the VBox (inside a ScrollContainer reachable through list.get_parent()). Add the scroll container to
	## your layout:  parent.add_child(list.get_parent())
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 120)
	var v := vbox(sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


## Selectable list row: title (+ dim subtitle) on the left, optional right text or price tag. `right` may be an
## int (price, formatted + green/red by Game.can_afford), a String, or "" for none.
static func list_row(title: String, subtitle: String = "", right: Variant = "", cb: Callable = Callable(), icon_cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 64 if subtitle != "" else 52)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
	h.offset_left = 14
	h.offset_right = -14
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	if icon_cb.is_valid():
		var ic := IconBox.new()
		ic.draw_cb = icon_cb
		ic.custom_minimum_size = Vector2(76, 0)
		h.add_child(ic)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(label(title, 22, UITheme.C_TEXT, true))
	if subtitle != "":
		tv.add_child(label(subtitle, 17, UITheme.C_DIM))
	h.add_child(tv)
	if right is int:
		var pt := price_tag(int(right))
		pt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pt)
	elif String(right) != "":
		var rl := label(String(right), 20, UITheme.C_ACCENT, true, HORIZONTAL_ALIGNMENT_RIGHT)
		rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(rl)
	b.pressed.connect(func():
		click()
		if cb.is_valid():
			cb.call())
	b.mouse_entered.connect(hover_tick)
	return b


static func price_tag(amount: int, affordable: Variant = null) -> PanelContainer:
	var ok: bool = Game.can_afford(amount) if affordable == null else bool(affordable)
	var p := panel(&"PriceTag" if ok else &"PriceTagBad")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label("FREE" if amount <= 0 else Util.format_money(amount), 20, UITheme.C_OK if ok else UITheme.C_DANGER, true)
	p.add_child(l)
	return p


static func keycap(text: String) -> PanelContainer:
	var p := panel(&"KeyCap")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, 17, UITheme.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER))
	return p


## Text of the first key bound to an InputMap action (e.g. "E"), or "?".
static func action_key(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			var s := OS.get_keycode_string(code)
			return s if s != "" else "?"
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
				MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
	return "?"


# ---- Cards ----------------------------------------------------------------------------------------------------------------------------------
static func card_grid(columns: int = 3) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 16)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


## Card with a drawn preview area (icon_cb(ci: Control, rect: Rect2)), title, subtitle and price tag.
static func card(title: String, subtitle: String = "", price: int = -1, icon_cb: Callable = Callable(), cb: Callable = Callable(),
		size: Vector2 = Vector2(250, 190)) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"CardButton"
	b.custom_minimum_size = size
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := IconBox.new()
	ic.draw_cb = icon_cb
	ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ic.custom_minimum_size = Vector2(0, 70)
	v.add_child(ic)
	v.add_child(label(title, 21, UITheme.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER))
	if subtitle != "":
		v.add_child(label(subtitle, 16, UITheme.C_DIM, false, HORIZONTAL_ALIGNMENT_CENTER))
	if price >= 0:
		var pt := price_tag(price)
		pt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(pt)
	b.pressed.connect(func():
		click()
		if cb.is_valid():
			cb.call())
	b.mouse_entered.connect(hover_tick)
	return b


## Small Control that calls `draw_cb(self, Rect2(Vector2.ZERO, size))` from _draw (icons, previews).
class IconBox extends Control:
	var draw_cb: Callable

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if draw_cb.is_valid():
			draw_cb.call(self, Rect2(Vector2.ZERO, size))
