class_name BarberMenu
extends ShopMenuBase
## Clip & Co barber: hair style (0..6), beard (none / stubble / full), hair colour. Live head preview, price = sum of what
## actually changes (ShopSystem.barber_price), persisted via ShopSystem.apply_appearance().

var _tab := 0
var _hair := 1
var _beard: StringName = &""
var _color := Color("#2a1c14")
var _tabs: HBoxContainer
var _list: VBoxContainer
var _preview: ShopPreview
var _total_label: Label
var _pay: Button


func _init() -> void:
	super._init()
	var b := build_frame("Clip & Co", "Barber", 1400, 800)
	var top := UIKit.hbox(16)
	_tabs = UIKit.tab_bar(["Hair style", "Beard", "Hair colour"], _on_tab)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_tabs)
	top.add_child(make_cash_label())
	b.add_child(top)
	var main := UIKit.hbox(22)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(main)
	_list = UIKit.scroll_list(8)
	var sc := _list.get_parent() as Control
	sc.custom_minimum_size = Vector2(640, 560)
	main.add_child(sc)
	var right := UIKit.panel(&"PanelDeep")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	var rv := UIKit.vbox(10)
	right.add_child(rv)
	_preview = ShopPreview.new(Vector2i(560, 440))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(_preview)
	_total_label = UIKit.label("", 22, UITheme.C_TEXT, true)
	rv.add_child(_total_label)
	_pay = UIKit.button("Confirm", _confirm, &"AccentButton")
	rv.add_child(_pay)
	set_hints([["Click", "Choose"], ["Esc", "Leave chair"]])


func _on_open(open_data: Dictionary) -> void:
	super._on_open(open_data)
	var s := _shops()
	var v: Dictionary = s.get_variant() if s != null else CharacterVariants.player_default()
	var hv: Variant = v.get("hair", 1)
	_hair = int(hv) if (hv is int or hv is float) else 1
	_beard = StringName(String(v.get("beard", "")))
	_color = v.get("hair_color", Color("#2a1c14"))
	_tab = 0
	UIKit.tab_select(_tabs, 0)
	_show_preview()
	_populate()
	focus_first()


func on_cash_changed() -> void:
	_update_total()


func _on_tab(i: int) -> void:
	_tab = i
	_populate()


func _variant() -> Dictionary:
	var s := _shops()
	var v: Dictionary = s.get_variant() if s != null else CharacterVariants.player_default()
	v["hair"] = _hair
	v["beard"] = _beard
	v["hair_color"] = _color
	return v


func _show_preview() -> void:
	_preview.show_rig(_variant(), &"head")
	_update_total()


func _populate() -> void:
	clear_children(_list)
	group = ButtonGroup.new()
	var s := _shops()
	var free: bool = s != null and s.free_shopping_active()
	match _tab:
		0:
			for h in WardrobeDefs.HAIR_STYLES:
				var hid: int = h["id"]
				var row := UIKit.list_row(str(h["name"]), str(h["desc"]), 0 if free else int(h["price"]), func(): _pick_hair(hid))
				row.button_pressed = (hid == _hair)
				_list.add_child(selectable(row))
		1:
			for bd in WardrobeDefs.BEARDS:
				var bid: StringName = bd["id"]
				var row2 := UIKit.list_row(str(bd["name"]), str(bd["desc"]), 0 if free else int(bd["price"]), func(): _pick_beard(bid))
				row2.button_pressed = (String(bid) == String(_beard))
				_list.add_child(selectable(row2))
		_:
			for hc in WardrobeDefs.HAIR_COLORS:
				var col: Color = hc["color"]
				var price := 0 if free else (int(hc["price"]))
				var row3 := UIKit.list_row(str(hc["name"]), "Dye" if int(hc["price"]) > 0 else "Natural shade", price, func(): _pick_color(col), func(ci: Control, rect: Rect2):
					var r := minf(rect.size.x, rect.size.y) * 0.34
					ci.draw_circle(rect.get_center(), r + 3.0, Color(1, 1, 1, 0.22))
					ci.draw_circle(rect.get_center(), r, col))
				row3.button_pressed = col.is_equal_approx(_color)
				_list.add_child(selectable(row3))


func _pick_hair(id: int) -> void:
	_hair = id
	_show_preview()


func _pick_beard(id: StringName) -> void:
	_beard = id
	_show_preview()


func _pick_color(c: Color) -> void:
	_color = c
	_show_preview()


func _update_total() -> void:
	var s := _shops()
	var price: int = s.barber_price(_hair, _beard, _color) if s != null else 0
	_total_label.text = "Total  %s" % ("no change" if price <= 0 and _is_unchanged() else ("FREE" if price <= 0 else Util.format_money(price)))
	_pay.text = "Pay and leave with the new look" if price > 0 else "Done"
	_pay.disabled = price > 0 and not Game.can_afford(price)


func _is_unchanged() -> bool:
	var s := _shops()
	if s == null:
		return true
	var v: Dictionary = s.get_variant()
	var hv: Variant = v.get("hair", 1)
	return _hair == (int(hv) if (hv is int or hv is float) else 1) and String(_beard) == String(v.get("beard", "")) and _color.is_equal_approx(v.get("hair_color", Color("#2a1c14")))


func _confirm() -> void:
	var s := _shops()
	if s == null:
		close()
		return
	var r: Dictionary = s.buy_haircut(_hair, _beard, _color)
	if bool(r.get("ok", false)):
		close()
