class_name WardrobeMenu
extends ShopMenuBase
## Clothing menu used by the Threads store (mode &"store": try everything on for free, pay for what you keep) and by the
## safehouse wardrobe (mode &"wardrobe": free, only basics and clothes you already own). Live try-on on a rotating copy of the
## player rig (ShopPreview); "Buy & wear" persists the outfit through ShopSystem.apply_appearance().

var mode: StringName = &"store"
var _cat := 0
var _tryon: Dictionary = {}                 # category -> item key
var _tabs: HBoxContainer
var _list: VBoxContainer
var _preview: ShopPreview
var _summary: VBoxContainer
var _buy_btn: Button


func _init() -> void:
	super._init()
	var b := build_frame("Threads", "Clothing", 1500, 840)
	var top := UIKit.hbox(16)
	var names: Array = []
	for c in WardrobeDefs.CATEGORIES:
		names.append(WardrobeDefs.CATEGORY_NAMES[c])
	_tabs = UIKit.tab_bar(names, _on_tab)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_tabs)
	top.add_child(make_cash_label())
	b.add_child(top)
	var main := UIKit.hbox(22)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(main)
	_list = UIKit.scroll_list(8)
	var sc := _list.get_parent() as Control
	sc.custom_minimum_size = Vector2(700, 600)
	main.add_child(sc)
	var right := UIKit.panel(&"PanelDeep")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	var rv := UIKit.vbox(8)
	right.add_child(rv)
	_preview = ShopPreview.new(Vector2i(560, 440))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(_preview)
	_summary = UIKit.vbox(6)
	rv.add_child(_summary)
	set_hints([["Click", "Try on"], ["Esc", "Leave"]])


func _on_open(open_data: Dictionary) -> void:
	super._on_open(open_data)
	mode = StringName(open_data.get("mode", &"store"))
	set_title("Threads" if mode == &"store" else "Wardrobe")
	_tryon.clear()
	_cat = 0
	UIKit.tab_select(_tabs, 0)
	_preview.show_rig(_variant())
	_populate()
	focus_first()


func on_cash_changed() -> void:
	_populate()


func _on_tab(i: int) -> void:
	_cat = i
	_preview.show_rig(_variant())
	_populate()


func _variant() -> Dictionary:
	var s := _shops()
	var v: Dictionary = s.get_variant() if s != null else CharacterVariants.player_default()
	for cat in _tryon:
		var it := WardrobeDefs.find(String(_tryon[cat]))
		for k in (it.get("delta", {}) as Dictionary):
			v[k] = it["delta"][k]
	# while browsing tops the jacket would hide the shirt: take it off in the preview only (the purchase never touches it)
	if WardrobeDefs.CATEGORIES[_cat] == &"tops" and not _tryon.has(&"jackets"):
		v["jacket"] = &""
	return v


func _is_owned(key: String) -> bool:
	var s := _shops()
	return s != null and s.owns_item(key)


func _populate() -> void:
	clear_children(_list)
	group = ButtonGroup.new()
	var cat: StringName = WardrobeDefs.CATEGORIES[_cat]
	var s := _shops()
	var cur: Dictionary = s.get_variant() if s != null else {}
	var worn := WardrobeDefs.worn_in(cat, cur)
	var shown := 0
	for it in WardrobeDefs.items(cat):
		var key: String = it["key"]
		var owned := _is_owned(key)
		if mode == &"wardrobe" and not owned and not bool(it["basic"]):
			continue
		shown += 1
		var right: Variant = ""
		if owned:
			right = "OWNED"
		elif mode == &"store":
			right = 0 if (s != null and s.free_shopping_active()) else int(it["price"])
		var sub := ""
		if not worn.is_empty() and worn["key"] == key:
			sub = "Currently wearing"
		elif _tryon.get(cat, "") == key:
			sub = "Trying on"
		var sw: Color = it["swatch"]
		var icon_cat := cat
		var row := UIKit.list_row(str(it["name"]), sub, right, func(): _try(cat, key), func(ci: Control, rect: Rect2):
			var r := minf(rect.size.x, rect.size.y) * 0.34
			var c := rect.get_center()
			ci.draw_circle(c, r + 3.0, Color(1, 1, 1, 0.22))
			ci.draw_circle(c, r, sw)
			if icon_cat == &"tops" or icon_cat == &"jackets":
				UIIcons.draw_glyph(ci, &"shirt", c, r * 0.9, sw.lightened(0.5) if sw.get_luminance() < 0.45 else sw.darkened(0.45), 0.9, false))
		row.button_pressed = (_tryon.get(cat, "") == key)
		_list.add_child(selectable(row))
	if shown == 0:
		_list.add_child(UIKit.label("Nothing here yet - buy more clothes at Threads.", 20, UITheme.C_DIM))
	_rebuild_summary()


func _try(cat: StringName, key: String) -> void:
	_tryon[cat] = key
	_preview.show_rig(_variant())
	_rebuild_summary()
	_populate_marks()


func _populate_marks() -> void:
	# keep the list as it is (the pressed state of the radio group already highlights the row); only the sub-captions are stale
	pass


func _pending() -> Dictionary:
	var keys: Array = []
	var total := 0
	var s := _shops()
	for cat in _tryon:
		var key: String = String(_tryon[cat])
		var it := WardrobeDefs.find(key)
		keys.append(key)
		if not _is_owned(key):
			total += 0 if (s != null and s.free_shopping_active()) else int(it.get("price", 0))
	return {"keys": keys, "total": total}


func _rebuild_summary() -> void:
	clear_children(_summary)
	var pend := _pending()
	var keys: Array = pend["keys"]
	_summary.add_child(UIKit.label("Outfit preview", 24, UITheme.C_TEXT, true))
	if keys.is_empty():
		_summary.add_child(UIKit.label("Pick items on the left to try them on. Nothing is charged until you confirm.", 18, UITheme.C_DIM))
	else:
		for k in keys:
			var it := WardrobeDefs.find(String(k))
			var owned := _is_owned(String(k))
			var line := UIKit.stat_row(str(it["name"]), "owned" if owned else ("free" if mode == &"wardrobe" else Util.format_money(int(it["price"]))), UITheme.C_OK if owned else UITheme.C_TEXT)
			_summary.add_child(line)
	var total: int = int(pend["total"])
	var row := UIKit.hbox(10)
	var reset := UIKit.button("Reset", func():
		_tryon.clear()
		_preview.show_rig(_variant())
		_populate())
	row.add_child(reset)
	var label := "Wear outfit" if (mode == &"wardrobe" or total == 0) else "Buy & wear  %s" % Util.format_money(total)
	_buy_btn = UIKit.button(label, _confirm, &"AccentButton")
	_buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_btn.disabled = keys.is_empty() or (total > 0 and not Game.can_afford(total))
	row.add_child(_buy_btn)
	_summary.add_child(row)


func _confirm() -> void:
	var s := _shops()
	if s == null:
		return
	var pend := _pending()
	var r: Dictionary = s.buy_outfit(pend["keys"], mode == &"wardrobe")
	if bool(r.get("ok", false)):
		_tryon.clear()
		_preview.show_rig(_variant())
		_populate()
