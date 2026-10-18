class_name GoodsMenu
extends ShopMenuBase
## Generic product list for the gas station counter (snacks, drinks: heal 5-50 HP, energy drink = no stamina drain for 45 s)
## and the dive shop (scuba kit, parachute pack, life vest). Catalogue lives in ShopSystem.FOOD / ShopSystem.SCUBA.

var catalog: StringName = &"food"
var _list: VBoxContainer
var _info: VBoxContainer
var _sel: StringName = &""
var _icon: UIKit.IconBox
var _stats: VBoxContainer


func _init() -> void:
	super._init()
	var b := build_frame("Store", "", 1280, 760)
	var top := UIKit.hbox(16)
	top.add_child(UIKit.spacer(0, 0, true))
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
	var rv := UIKit.vbox(12)
	right.add_child(rv)
	_icon = UIKit.IconBox.new()
	_icon.custom_minimum_size = Vector2(0, 220)
	rv.add_child(_icon)
	_info = UIKit.vbox(8)
	rv.add_child(_info)
	_stats = UIKit.vbox(4)
	rv.add_child(_stats)
	set_hints([["Click", "Select / buy"], ["Esc", "Leave"]])


func _on_open(open_data: Dictionary) -> void:
	super._on_open(open_data)
	catalog = StringName(open_data.get("catalog", &"food"))
	set_title("Halcyon Fuel Mart" if catalog == &"food" else "Reef Dive Shop")
	_sel = &""
	_populate()
	focus_first()


func on_cash_changed() -> void:
	_populate()


func _populate() -> void:
	clear_children(_list)
	group = ButtonGroup.new()
	var s := _shops()
	if s == null:
		return
	var items: Array = s.catalog(catalog)
	if _sel == &"" and not items.is_empty():
		_sel = items[0]["id"]
	var free: bool = s.free_shopping_active()
	for it in items:
		var id: StringName = it["id"]
		var gl: StringName = it["glyph"]
		var col: Color = it["color"]
		var owned: bool = catalog != &"food" and s.good_owned(id)
		var right: Variant = "OWNED" if owned else (0 if free else int(it["price"]))
		var row := UIKit.list_row(str(it["name"]), _short(str(it["desc"])), right, func(): _select(id), func(ci: Control, rect: Rect2):
			UIIcons.draw_glyph(ci, gl, rect.get_center(), minf(rect.size.x, rect.size.y) * 0.4, col))
		row.button_pressed = (id == _sel)
		_list.add_child(selectable(row))
	_rebuild_info()


static func _short(t: String) -> String:
	return t if t.length() < 58 else t.substr(0, 55) + "..."


func _select(id: StringName) -> void:
	_sel = id
	_rebuild_info()


func _rebuild_info() -> void:
	clear_children(_info)
	clear_children(_stats)
	var s := _shops()
	if s == null:
		return
	var item: Dictionary = {}
	for it in s.catalog(catalog):
		if it["id"] == _sel:
			item = it
	if item.is_empty():
		return
	var gl: StringName = item["glyph"]
	var col: Color = item["color"]
	_icon.draw_cb = func(ci: Control, rect: Rect2):
		UIIcons.draw_glyph(ci, gl, rect.get_center(), minf(rect.size.x, rect.size.y) * 0.34, col)
	_icon.queue_redraw()
	_info.add_child(UIKit.label(str(item["name"]), 30, UITheme.C_TEXT, true))
	var d := UIKit.label(str(item["desc"]), 19, UITheme.C_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(d)
	var free: bool = s.free_shopping_active()
	var price := int(item["price"])
	var owned: bool = catalog != &"food" and s.good_owned(_sel)
	var buy := UIKit.button("Owned" if owned else ("Buy  %s" % ("FREE" if free else Util.format_money(price))), func():
		s.buy_good(catalog, _sel)
		_populate(), &"AccentButton")
	buy.disabled = owned or (not free and not Game.can_afford(price))
	_info.add_child(buy)
	var p = Game.player
	if is_instance_valid(p):
		_stats.add_child(UIKit.stat_row("Health", "%d / %d" % [int(p.get("health")), int(p.get("max_health"))]))
	if catalog == &"scuba":
		_stats.add_child(UIKit.stat_row("Scuba tank", "%d%%" % int(s.get_tank01() * 100.0) if s.scuba_owned else "none", UITheme.C_ACCENT))
		_stats.add_child(UIKit.stat_row("Life vests", str(s.life_vests)))
