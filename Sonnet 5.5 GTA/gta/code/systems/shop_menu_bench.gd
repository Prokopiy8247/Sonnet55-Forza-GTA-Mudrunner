class_name WeaponBenchMenu
extends ShopMenuBase
## Weapon modification bench: pick an owned firearm, fit suppressor / scope / flashlight / grip / extended magazine
## (prices from WeaponMods, real gameplay effects live in WeaponController) and a cosmetic finish (WeaponMods.TINTS).
## Hovering a mod or finish previews it on the rotating 3D model before you pay.

var _sel: StringName = &""
var _list: VBoxContainer
var _preview: ShopPreview
var _mods_box: VBoxContainer
var _tint_grid: GridContainer
var _head: Label
var _sub: Label


func _init() -> void:
	super._init()
	var b := build_frame("Modification Bench", "Fit attachments and finishes", 1500, 820)
	var top := UIKit.hbox(16)
	top.add_child(UIKit.label("Choose a weapon, then click a part to install it. Removing parts is free.", 19, UITheme.C_DIM))
	var sp := UIKit.spacer(0, 0, true)
	top.add_child(sp)
	top.add_child(make_cash_label())
	b.add_child(top)
	var main := UIKit.hbox(22)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(main)
	_list = UIKit.scroll_list(8)
	var sc := _list.get_parent() as Control
	sc.custom_minimum_size = Vector2(430, 600)
	main.add_child(sc)
	var right := UIKit.panel(&"PanelDeep")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	var rv := UIKit.vbox(8)
	right.add_child(rv)
	_preview = ShopPreview.new(Vector2i(700, 250))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(_preview)
	_head = UIKit.label("", 28, UITheme.C_TEXT, true)
	rv.add_child(_head)
	_sub = UIKit.label("", 17, UITheme.C_DIM)
	rv.add_child(_sub)
	_mods_box = UIKit.vbox(6)
	rv.add_child(_mods_box)
	rv.add_child(UIKit.caption("Finish  ($%d, factory is free)" % WeaponMods.TINT_PRICE))
	_tint_grid = GridContainer.new()
	_tint_grid.columns = 10
	_tint_grid.add_theme_constant_override("h_separation", 8)
	_tint_grid.add_theme_constant_override("v_separation", 8)
	rv.add_child(_tint_grid)
	set_hints([["Click", "Install / remove"], ["Esc", "Leave bench"]])


func _on_open(open_data: Dictionary) -> void:
	super._on_open(open_data)
	_sel = &""
	var wc = _wc()
	if wc != null:
		var p = Game.player
		var cur = wc.get("current_id")
		if cur != null and _bench_ok(StringName(cur)):
			_sel = StringName(cur)
	_populate()
	focus_first()


func on_cash_changed() -> void:
	_populate(false)


func _wc() -> Variant:
	var p = Game.player
	return p.get("weapons") if is_instance_valid(p) else null


func _bench_ok(id: StringName) -> bool:
	return WeaponDefs.is_firearm(id) and not WeaponMods.compatible_mods(id).is_empty()


func _owned_ids() -> Array:
	var out: Array = []
	var wc = _wc()
	if wc == null:
		return out
	for id in wc.get_ordered_ids():
		if _bench_ok(StringName(id)):
			out.append(StringName(id))
	return out


func _populate(reshow: bool = true) -> void:
	clear_children(_list)
	group = ButtonGroup.new()
	var ids := _owned_ids()
	if ids.is_empty():
		_list.add_child(UIKit.label("You don't own a weapon that can be modified.\nBuy a firearm at the counter first.", 20, UITheme.C_DIM))
		_sel = &""
		clear_children(_mods_box)
		clear_children(_tint_grid)
		_head.text = "No weapon"
		_sub.text = ""
		_preview.clear_item()
		return
	if not ids.has(_sel):
		_sel = ids[0]
		reshow = true
	var wc = _wc()
	for id in ids:
		var d := WeaponDefs.get_def(id)
		var e: Dictionary = wc.inventory[id]
		var n_mods := 0
		for m in e["mods"]:
			if e["mods"][m]:
				n_mods += 1
		var sub := "%d / %d parts fitted" % [n_mods, WeaponMods.compatible_mods(id).size()]
		var wid: StringName = id
		var row := UIKit.list_row(str(d["name"]), sub, "", func(): _select(wid),
			func(ci: Control, rect: Rect2): UIIcons.draw_weapon(ci, wid, rect.grow(-6.0), Color(0.93, 0.97, 1.0)))
		row.button_pressed = (id == _sel)
		_list.add_child(selectable(row))
	_rebuild(reshow)


func _select(id: StringName) -> void:
	_sel = id
	_rebuild(true)


func _entry() -> Dictionary:
	var wc = _wc()
	if wc == null or _sel == &"" or not wc.has_weapon(_sel):
		return {}
	return wc.inventory[_sel]


func _rebuild(reshow: bool) -> void:
	var e := _entry()
	if e.is_empty():
		return
	var d := WeaponDefs.get_def(_sel)
	_head.text = str(d["name"])
	var eff: Dictionary = WeaponMods.effective(e["mods"])
	_sub.text = "Mag %d   |   Noise x%.2f   |   Damage x%.2f   |   Recoil x%.2f   |   Zoom x%.1f" % [WeaponDefs.mag_capacity(_sel, e["mods"]), float(eff["noise_mult"]), float(eff["damage_mult"]), float(eff["recoil_mult"]), float(eff["zoom_mult"])]
	if reshow:
		_preview.show_weapon(_sel, e["mods"], e["tint"])
	var s := _shops()
	var free: bool = s != null and s.free_shopping_active()
	clear_children(_mods_box)
	for mod_id in WeaponMods.compatible_mods(_sel):
		var md := WeaponMods.get_mod(mod_id)
		var installed: bool = bool(e["mods"].get(mod_id, false))
		var right: Variant = "INSTALLED" if installed else (0 if free else WeaponMods.price(mod_id))
		var mid: StringName = mod_id
		var row := UIKit.list_row(str(md["name"]), str(md["desc"]), right, func(): _toggle_mod(mid))
		row.custom_minimum_size = Vector2(0, 58)
		row.mouse_entered.connect(func(): _hover_mod(mid))
		row.mouse_exited.connect(func(): _hover_mod(&""))
		_mods_box.add_child(row)
	clear_children(_tint_grid)
	var cur_tint: Color = e["tint"]
	for tid in WeaponMods.TINTS:
		var t: StringName = tid
		var col := WeaponMods.tint_color(t)
		var is_factory := t == &"factory"
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(60, 40)
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = "%s%s" % [str(t).capitalize(), "" if is_factory else "  ($%d)" % WeaponMods.TINT_PRICE]
		var fill := Color(0.30, 0.34, 0.40) if is_factory else col
		var active := (is_factory and cur_tint.a <= 0.01) or (not is_factory and cur_tint.a > 0.01 and cur_tint.is_equal_approx(col))
		var border := Color.WHITE if active else Color(1, 1, 1, 0.18)
		var bw := 3 if active else 1
		for state in ["normal", "hover", "pressed", "focus"]:
			var f := fill.lightened(0.15) if state == "hover" else fill
			btn.add_theme_stylebox_override(state, UITheme.box(8, f, bw, border))
		if is_factory:
			btn.text = "STOCK"
			btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func():
			UIKit.click()
			if s != null:
				s.buy_tint(_sel, t)
			_populate(true))
		btn.mouse_entered.connect(UIKit.hover_tick)
		btn.mouse_entered.connect(func(): _hover_tint(t))
		btn.mouse_exited.connect(func(): _hover_tint(&""))
		_tint_grid.add_child(btn)


func _toggle_mod(mod_id: StringName) -> void:
	var s := _shops()
	if s == null:
		return
	var e := _entry()
	if e.is_empty():
		return
	if bool(e["mods"].get(mod_id, false)):
		s.remove_mod(_sel, mod_id)
	else:
		s.buy_mod(_sel, mod_id)
	_populate(true)


func _hover_mod(mod_id: StringName) -> void:
	var e := _entry()
	if e.is_empty():
		return
	var mods: Dictionary = (e["mods"] as Dictionary).duplicate()
	if mod_id != &"":
		mods[mod_id] = true
	_preview.show_weapon(_sel, mods, e["tint"])


func _hover_tint(tint_id: StringName) -> void:
	var e := _entry()
	if e.is_empty():
		return
	var col: Color = e["tint"] if tint_id == &"" else WeaponMods.tint_color(tint_id)
	_preview.show_weapon(_sel, e["mods"], col)
