class_name WeaponShopMenu
extends ShopMenuBase
## Gunsmith counter menu: categories, weapon list with owned markers, rotating 3D preview with stat bars, buy weapon / ammo,
## body armor and medkit. All purchases go through ShopSystem (WeaponTrade rules, cash checks, toasts, sounds).

const TABS := [
	["Handguns", [&"handgun"]], ["SMGs", [&"smg"]], ["Shotguns", [&"shotgun"]], ["Rifles", [&"rifle", &"sniper"]],
	["Heavy", [&"heavy", &"thrown"]], ["Melee", [&"melee"]], ["Gear", []],
]
const GEAR_TAB := 6
const STAT_NAMES := {"damage": "Damage", "rate": "Fire rate", "range": "Range", "accuracy": "Accuracy", "control": "Control"}

var _tab := 0
var _sel: StringName = &""
var _tabs: HBoxContainer
var _list: VBoxContainer
var _preview: ShopPreview
var _info: VBoxContainer
var _title_box: Label


func _init() -> void:
	super._init()
	var b := build_frame("Gunsmith", "Weapons, ammo and armor", 1500, 820)
	var top := UIKit.hbox(16)
	_tabs = UIKit.tab_bar(_tab_names(), _on_tab)
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
	_preview = ShopPreview.new(Vector2i(640, 300))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(_preview)
	_info = UIKit.vbox(8)
	rv.add_child(_info)
	set_hints([["Click", "Select / buy"], ["Esc", "Leave counter"]])


static func _tab_names() -> Array:
	var out: Array = []
	for t in TABS:
		out.append(t[0])
	return out


func _on_open(open_data: Dictionary) -> void:
	super._on_open(open_data)
	set_title("Gunsmith")
	_tab = 0
	UIKit.tab_select(_tabs, 0)
	_populate()
	focus_first()


func on_cash_changed() -> void:
	_populate(false)


func _on_tab(i: int) -> void:
	_tab = i
	_sel = &""
	_populate()


func _items_for_tab() -> Array:
	if _tab == GEAR_TAB:
		return [&"armor", &"medkit"]
	var out: Array = []
	var cats: Array = TABS[_tab][1]
	for id in WeaponDefs.shop_ids():
		if WeaponDefs.get_def(id)["category"] in cats:
			out.append(id)
	return out


func _wc() -> Variant:
	var p = Game.player
	return p.get("weapons") if is_instance_valid(p) else null


func _owned(id: StringName) -> bool:
	var wc = _wc()
	return wc != null and wc.has_weapon(id)


func _populate(reselect: bool = true) -> void:
	clear_children(_list)
	group = ButtonGroup.new()
	var items := _items_for_tab()
	if _sel == &"" and not items.is_empty():
		_sel = items[0]
	elif not items.has(_sel) and not items.is_empty():
		_sel = items[0]
	for id in items:
		_list.add_child(_make_row(id))
	_rebuild_info(reselect)


func _make_row(id: StringName) -> Button:
	if id == &"armor" or id == &"medkit":
		var armor := id == &"armor"
		var nm := "Body armor" if armor else "Field medkit"
		var sub := "+100 armor plates" if armor else "+60 health"
		var price: int = ShopSystem.ARMOR_PRICE if armor else ShopSystem.HEALTH_PRICE
		var gid: StringName = &"shield" if armor else &"cross"
		var col := Color("#34e0ff") if armor else Color("#ff4d6a")
		var row := UIKit.list_row(nm, sub, price, func(): _select(id), func(ci: Control, rect: Rect2): UIIcons.draw_glyph(ci, gid, rect.get_center(), minf(rect.size.x, rect.size.y) * 0.4, col))
		row.button_pressed = (id == _sel)
		return selectable(row)
	var d := WeaponDefs.get_def(id)
	var owned := _owned(id)
	var is_fire := WeaponDefs.is_firearm(id)
	var right: Variant = ""
	if owned and (is_fire or WeaponDefs.is_melee(id)):
		right = "OWNED"
	else:
		right = int(d["price"])
	var sub2 := "%s" % str(UIIcons.CATEGORY_NAMES.get(d["category"], d["category"]))
	if int(d["mag_size"]) > 0:
		sub2 += "   |   %d round magazine" % int(d["mag_size"])
	var row2 := UIKit.list_row(str(d["name"]), sub2, right, func(): _select(id),
		func(ci: Control, rect: Rect2): UIIcons.draw_weapon(ci, id, rect.grow(-6.0), Color(0.93, 0.97, 1.0)))
	row2.button_pressed = (id == _sel)
	return selectable(row2)


func _select(id: StringName) -> void:
	_sel = id
	_rebuild_info(true)


func _rebuild_info(reshow: bool) -> void:
	clear_children(_info)
	var s := _shops()
	if _sel == &"":
		return
	if _sel == &"armor" or _sel == &"medkit":
		_preview.clear_item()
		_preview.visible = true
		var armor := _sel == &"armor"
		_info.add_child(UIKit.label("Body armor" if armor else "Field medkit", 30, UITheme.C_TEXT, true))
		var desc := UIKit.label("Ceramic plates that soak 70% of incoming damage. Wear it under your jacket." if armor else "Bandages, sutures and painkillers. Restores 60 health instantly.", 19, UITheme.C_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info.add_child(desc)
		var p = Game.player
		if is_instance_valid(p):
			_info.add_child(UIKit.stat_row("Armor" if armor else "Health", "%d / %d" % [int(p.get("armor" if armor else "health")), int(p.get("max_armor" if armor else "max_health"))]))
		var price: int = ShopSystem.ARMOR_PRICE if armor else ShopSystem.HEALTH_PRICE
		var free: bool = s != null and s.free_shopping_active()
		var buy := UIKit.button("Buy for %s" % ("FREE" if free else Util.format_money(price)), func():
			if s != null:
				if armor:
					s.buy_armor()
				else:
					s.buy_health()
			_populate(false), &"AccentButton")
		buy.disabled = not free and not Game.can_afford(price)
		_info.add_child(buy)
		return
	var d := WeaponDefs.get_def(_sel)
	if d.is_empty():
		return
	if reshow:
		_preview.show_weapon(_sel)
	var wc = _wc()
	var owned := _owned(_sel)
	var head := UIKit.hbox(12)
	head.add_child(UIKit.label(str(d["name"]), 30, UITheme.C_TEXT, true))
	if owned:
		var tag := owned_tag("OWNED")
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(tag)
	_info.add_child(head)
	var desc2 := UIKit.label(str(d["desc"]), 19, UITheme.C_DIM)
	desc2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(desc2)
	var bars := WeaponDefs.stat_bars(_sel)
	for k in ["damage", "rate", "range", "accuracy", "control"]:
		if bars.has(k):
			_info.add_child(bar_row(STAT_NAMES[k], float(bars[k]), UITheme.C_ACCENT if k != "control" else UITheme.C_OK))
	var free2: bool = s != null and s.free_shopping_active()
	var is_fire := WeaponDefs.is_firearm(_sel)
	var thrown: bool = d["category"] == &"thrown"
	if wc != null and owned and (is_fire or thrown):
		var e: Dictionary = wc.inventory[_sel]
		var cap := WeaponDefs.reserve_capacity(_sel, e["mods"])
		_info.add_child(UIKit.stat_row("Ammo", "%d + %d / %d" % [int(e["mag"]), int(e["reserve"]), cap], UITheme.C_TEXT))
		var row := UIKit.hbox(10)
		for mags in [1, 3]:
			var m: int = mags
			var price: int = int(d["ammo_price"]) * m
			var lab := "+%d mag%s  %s" % [m, "" if m == 1 else "s", "FREE" if free2 else Util.format_money(price)]
			if thrown:
				lab = "+%d grenade%s  %s" % [m, "" if m == 1 else "s", "FREE" if free2 else Util.format_money(price)]
			var bb := UIKit.button(lab, func():
				if s != null:
					s.buy_ammo(_sel, m)
				_populate(false), &"AccentButton" if m == 1 else &"")
			bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bb.disabled = int(e["reserve"]) >= cap or (not free2 and not Game.can_afford(price))
			row.add_child(bb)
		_info.add_child(row)
	elif owned and WeaponDefs.is_melee(_sel):
		_info.add_child(UIKit.label("You already carry this one.", 19, UITheme.C_DIM))
	else:
		var price2 := int(d["price"])
		var buy2 := UIKit.button("Buy  %s" % ("FREE" if free2 else Util.format_money(price2)), func():
			if s != null:
				s.buy_weapon(_sel)
			_populate(false), &"AccentButton")
		buy2.disabled = not free2 and not Game.can_afford(price2)
		_info.add_child(buy2)
		if int(d["mag_size"]) > 0:
			_info.add_child(UIKit.label("Includes %d rounds of ammunition." % (int(d["mag_size"]) + int(d["give_reserve"])), 17, UITheme.C_DIM))
	if bool(d.get("scope", false)):
		_info.add_child(UIKit.label("Scoped - zoom with the mouse wheel while aiming.", 17, UITheme.C_DIM))
