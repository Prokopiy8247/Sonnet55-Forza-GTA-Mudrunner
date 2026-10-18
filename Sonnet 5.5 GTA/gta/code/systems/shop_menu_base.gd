class_name ShopMenuBase
extends MenuBase
## Shared helpers of the shop menus (weapon shop, bench, wardrobe, barber, goods): cash read-out, stat bars, selectable rows.

var cash_label: Label = null
var group := ButtonGroup.new()
var shop_id: StringName = &""
var room: InteriorRoom = null


func _init() -> void:
	super._init()
	pauses_game = true
	Events.cash_changed.connect(_on_cash_changed)


func _shops() -> Node:
	return Game.sys(&"shops")


func make_cash_label() -> Label:
	cash_label = UIKit.label("", 24, UITheme.C_OK, true, HORIZONTAL_ALIGNMENT_RIGHT)
	cash_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh_cash()
	return cash_label


func refresh_cash() -> void:
	if cash_label != null:
		var free: bool = _shops() != null and _shops().free_shopping_active()
		cash_label.text = ("CASH  " + Util.format_money(Game.cash)) + ("   (FREE SHOPPING)" if free else "")


func _on_cash_changed(_amount: int, _delta: int) -> void:
	if is_open:
		refresh_cash()
		on_cash_changed()


func on_cash_changed() -> void:
	pass


func _on_open(open_data: Dictionary) -> void:
	room = open_data.get("room", null)
	shop_id = open_data.get("shop", &"")
	refresh_cash()


static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func bar_row(label: String, ratio: float, color: Color = UITheme.C_ACCENT) -> HBoxContainer:
	var h := UIKit.hbox(12)
	var l := UIKit.label(label, 18, UITheme.C_DIM)
	l.custom_minimum_size = Vector2(120, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var b := UIKit.bar(ratio, color, 12.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	return h


## Makes a list row / card a radio button of this menu's group (selected row stays highlighted).
func selectable(btn: Button) -> Button:
	btn.toggle_mode = true
	btn.button_group = group
	return btn


func owned_tag(text: String = "OWNED") -> Label:
	return UIKit.label(text, 18, UITheme.C_OK, true)


func divider_label(text: String) -> Label:
	var l := UIKit.caption(text)
	return l


func shop_title(room_name: String, fallback: String) -> String:
	return room_name if room_name != "" else fallback
