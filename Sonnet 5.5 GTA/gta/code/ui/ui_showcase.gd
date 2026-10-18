class_name UIShowcase
extends MenuBase
## Widget showcase / style guide: exercises every widget of the UI kit (buttons, sliders, toggles, dropdown, tabs, list rows
## with price tags, card grid, bars, key caps, glyph + weapon icons, toasts, confirm dialog). Open with
## Game.ui.open_menu(&"ui_showcase") (registered by UIRoot.post_setup when the menu exists). Debug builds only; harmless otherwise.

var _tabs: HBoxContainer
var _pages: Array[Control] = []
var _stack: Control
var _slider_val := 0.5


func _init() -> void:
	super._init()
	pauses_game = true
	var b := build_frame("UI Showcase", "Halcyon widget kit", 1320, 780)
	_tabs = UIKit.tab_bar(["Inputs", "Lists and cards", "Icons", "Feedback"], _select)
	b.add_child(_tabs)
	_stack = Control.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.custom_minimum_size = Vector2(0, 560)
	b.add_child(_stack)
	_pages = [_page_inputs(), _page_lists(), _page_icons(), _page_feedback()]
	for p in _pages:
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_stack.add_child(p)
	_select(0)
	set_hints([["Esc", "Close"]])


func _on_open(d: Dictionary) -> void:
	var t := int(d.get("tab", 0))
	UIKit.tab_select(_tabs, t)
	_select(t)


func _select(i: int) -> void:
	for k in _pages.size():
		_pages[k].visible = (k == i)


func _page_inputs() -> Control:
	var h := UIKit.hbox(26)
	var left := UIKit.panel(&"PanelDeep")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var v := UIKit.vbox(10)
	left.add_child(v)
	v.add_child(UIKit.caption("Buttons"))
	var row := UIKit.hbox(12)
	row.add_child(UIKit.button("Default", func(): Events.notification.emit("Default button", &"info")))
	row.add_child(UIKit.button("Primary", func(): Events.notification.emit("Primary action", &"good"), &"AccentButton"))
	row.add_child(UIKit.button("Danger", func(): Events.notification.emit("Danger action", &"bad"), &"DangerButton"))
	var dis := UIKit.button("Disabled")
	dis.disabled = true
	row.add_child(dis)
	v.add_child(row)
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.caption("Sliders, toggles, dropdown"))
	v.add_child(UIKit.slider_row("Volume", 0.0, 1.0, 0.6, 0.01, func(x): _slider_val = x, func(x: float) -> String: return "%d%%" % int(x * 100.0)))
	v.add_child(UIKit.slider_row("Field of view", 55.0, 110.0, 75.0, 1.0, Callable(), func(x: float) -> String: return "%d deg" % int(x)))
	v.add_child(UIKit.toggle_row("Shadows", true, Callable()))
	v.add_child(UIKit.toggle_row("Invert Y axis", false, Callable()))
	v.add_child(UIKit.option_row("Quality preset", ["Low", "Medium", "High", "Ultra"], 2, Callable()))
	var right := UIKit.panel(&"PanelDeep")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var r := UIKit.vbox(10)
	right.add_child(r)
	r.add_child(UIKit.caption("Stats and bars"))
	r.add_child(UIKit.stat_row("Cash", Util.format_money(48250), UITheme.C_OK))
	r.add_child(UIKit.stat_row("Distance driven", "12.4 km"))
	r.add_child(UIKit.stat_row("Wanted peak", "3 stars", UITheme.C_GOLD))
	r.add_child(UIKit.bar(0.72, UITheme.C_ACCENT, 12.0))
	r.add_child(UIKit.bar(0.35, UITheme.C_WARN, 12.0))
	r.add_child(UIKit.bar(0.12, UITheme.C_DANGER, 12.0))
	r.add_child(UIKit.spacer(6))
	r.add_child(UIKit.caption("Key caps"))
	var keys := UIKit.hbox(8)
	for k in ["W", "A", "S", "D", "Shift", "Space", "Esc"]:
		keys.add_child(UIKit.keycap(k))
	r.add_child(keys)
	r.add_child(UIKit.spacer(6))
	r.add_child(UIKit.caption("Price tags"))
	var prices := UIKit.hbox(10)
	prices.add_child(UIKit.price_tag(1500, true))
	prices.add_child(UIKit.price_tag(125000, false))
	prices.add_child(UIKit.price_tag(0, true))
	r.add_child(prices)
	return h


func _page_lists() -> Control:
	var v := UIKit.vbox(12)
	v.add_child(UIKit.caption("List rows (selectable, price tag, icon)"))
	var list := UIKit.scroll_list(8)
	var items := [[&"pistol", "Pistol", "Handgun - 12 round magazine", 600], [&"smg", "Submachine Gun", "Fast fire rate, 30 rounds", 2400],
		[&"shotgun_pump", "Pump Shotgun", "Devastating at close range", 3200], [&"rifle_assault", "Assault Rifle", "Balanced and accurate", 9500],
		[&"sniper", "Sniper Rifle", "Extreme range, scoped", 48000]]
	for it in items:
		var id: StringName = it[0]
		list.add_child(UIKit.list_row(it[1], it[2], int(it[3]), func(): Events.notification.emit("Selected %s" % id, &"info"),
			func(ci: Control, rect: Rect2): UIIcons.draw_weapon(ci, id, rect.grow(-4.0), Color(0.93, 0.97, 1.0))))
	v.add_child(list.get_parent())
	v.add_child(UIKit.caption("Card grid"))
	var grid := UIKit.card_grid(4)
	for c in [[&"knife", "Combat Knife", "Silent melee", 250], [&"revolver", "Revolver", "Heavy hitter", 1800], [&"carbine", "Carbine", "Light rifle", 5200], [&"rocket_launcher", "Launcher", "Heavy", 62000]]:
		var cid: StringName = c[0]
		grid.add_child(UIKit.card(c[1], c[2], int(c[3]), func(ci: Control, rect: Rect2): UIIcons.draw_weapon(ci, cid, rect.grow(-6.0), Color(0.93, 0.97, 1.0)),
			func(): Events.notification.emit("Bought %s" % cid, &"good"), Vector2(250, 170)))
	v.add_child(grid)
	return v


func _page_icons() -> Control:
	var v := UIKit.vbox(14)
	v.add_child(UIKit.caption("Weapon silhouettes"))
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for id in UIIcons.WEAPON_OPS.keys():
		var wid: StringName = id
		var cell := UIKit.panel(&"PanelFlat")
		var ib := UIKit.IconBox.new()
		ib.custom_minimum_size = Vector2(120, 62)
		ib.draw_cb = func(ci: Control, rect: Rect2): UIIcons.draw_weapon(ci, wid, rect, Color(0.93, 0.97, 1.0))
		cell.add_child(ib)
		g.add_child(cell)
	v.add_child(g)
	v.add_child(UIKit.caption("Location glyphs"))
	var g2 := GridContainer.new()
	g2.columns = 14
	g2.add_theme_constant_override("h_separation", 12)
	g2.add_theme_constant_override("v_separation", 12)
	for id in UIIcons.LOC.keys():
		var lid: StringName = id
		var ib2 := UIKit.IconBox.new()
		ib2.custom_minimum_size = Vector2(46, 46)
		ib2.draw_cb = func(ci: Control, rect: Rect2): UIIcons.draw_location(ci, lid, rect.get_center(), 18.0)
		g2.add_child(ib2)
	v.add_child(g2)
	return v


func _page_feedback() -> Control:
	var v := UIKit.vbox(14)
	v.add_child(UIKit.caption("Toasts"))
	var row := UIKit.hbox(12)
	row.add_child(UIKit.button("Info", func(): Events.notification.emit("Radio station changed to Halcyon FM.", &"info")))
	row.add_child(UIKit.button("Good", func(): Events.notification.emit("Mission-free cash bonus: +$500", &"good")))
	row.add_child(UIKit.button("Warning", func(): Events.notification.emit("Low on ammo - visit a weapon shop.", &"warn")))
	row.add_child(UIKit.button("Bad", func(): Events.notification.emit("You cannot carry more weapons.", &"bad")))
	v.add_child(row)
	v.add_child(UIKit.caption("Dialogs"))
	var row2 := UIKit.hbox(12)
	row2.add_child(UIKit.button("Confirm dialog", func(): confirm("Buy vehicle", "Purchase the Sports Coupe for $42,000?", func(): toast("Purchased!", &"good"), func(): toast("Cancelled", &"warn"), "Buy", "Cancel"), &"AccentButton"))
	row2.add_child(UIKit.button("Subtitle", func(): Events.subtitle.emit("Driver: Hold on tight, we are taking the coast road.", 3.0)))
	v.add_child(row2)
	return v
