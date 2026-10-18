class_name MenuBase
extends Control
## Base class for modal menus hosted by UIRoot (shop, garage, phone, wardrobe, map, pause, debug...).
##
## Host side (UIRoot): ui.register_menu(id, menu), ui.open_menu(id, data), ui.close_menu(), ui.is_menu_open().
## Menus are built in code (Control/Container nodes + the shared theme, see UIKit) and registered in post_setup():
##
##   class_name ShopMenu extends MenuBase
##   func _init() -> void:
##       var body := build_frame("Weapon Shop", "Buy weapons and ammo")     # standard dim backdrop + centred panel
##       body.add_child(UIKit.list_row("Pistol", "Handgun", 500, func(): ...))
##       set_hints([["E", "Buy"], ["Esc", "Close"]])
##   func _on_open(data: Dictionary) -> void: refresh()
##   # in post_setup:  Game.ui.register_menu(&"shop", ShopMenu.new())
##
## Pause handling: while a menu with `pauses_game == true` is open UIRoot pauses the tree (Game.set_paused) and
## frees the mouse; the menu keeps running because MenuBase uses PROCESS_MODE_ALWAYS. Esc (the `pause` action)
## closes the open menu when `closes_on_pause` is true. Override `on_back()` for custom Esc behaviour.

signal closed

var menu_id: StringName = &""
var pauses_game := true          # UIRoot pauses the tree while a pausing menu is open
var wants_cursor := true         # UIRoot frees the mouse while this menu is open
var closes_on_pause := true      # Esc / pause key closes this menu
var dim_background := true       # standard frame dims the game behind
var is_open := false
var data: Dictionary = {}        # data passed to open()

var frame: PanelContainer = null     # the centred panel created by build_frame()
var body: VBoxContainer = null       # content area inside the frame (add your widgets here)
var _hints_box: HBoxContainer = null
var _title_label: Label = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ---- Open / close (host calls these) -----------------------------------------------------------------------
func open(open_data: Dictionary = {}) -> void:
	data = open_data
	is_open = true
	show()
	_on_open(open_data)


func close() -> void:
	if not is_open and not visible:
		return
	is_open = false
	hide()
	_on_close()
	closed.emit()


## Called by UIRoot when Esc is pressed while this menu is open. Return true if handled (menu stays open).
func on_back() -> bool:
	return false


func _on_open(_open_data: Dictionary) -> void:
	pass


func _on_close() -> void:
	pass


# ---- Frame builder --------------------------------------------------------------------------------------------
## Builds the standard layout: dim backdrop, centred panel with header, divider, content `body`, footer hints.
## Returns `body`. `width`/`height` are in design pixels (1920 x 1080); height 0 = fit content.
func build_frame(title: String, subtitle: String = "", width: float = 1040.0, height: float = 0.0) -> VBoxContainer:
	for c in get_children():
		c.queue_free()
	if dim_background:
		var dim := ColorRect.new()
		dim.color = Color(0.01, 0.02, 0.04, 0.62)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	frame = UIKit.panel()
	frame.custom_minimum_size = Vector2(width, height)
	center.add_child(frame)
	var v := UIKit.vbox(14)
	frame.add_child(v)
	var hdr := UIKit.header(title, subtitle)
	_title_label = hdr.get_child(1) as Label
	v.add_child(hdr)
	v.add_child(UIKit.separator())
	body = UIKit.vbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_hints_box = UIKit.hbox(26)
	_hints_box.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_hints_box)
	set_hints([["Esc", "Close"]])
	return body


func set_title(text: String) -> void:
	if _title_label != null:
		_title_label.text = text.to_upper()


## Footer key hints: [["E", "Buy"], ["Esc", "Close"]]
func set_hints(hints: Array) -> void:
	if _hints_box == null:
		return
	for c in _hints_box.get_children():
		c.queue_free()
	for h in hints:
		var item := UIKit.hbox(8)
		item.add_child(UIKit.keycap(String(h[0])))
		var l := UIKit.label(String(h[1]), 18, UITheme.C_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(l)
		_hints_box.add_child(item)


# ---- Convenience ----------------------------------------------------------------------------------------------------
func toast(text: String, kind: StringName = &"info") -> void:
	Events.notification.emit(text, kind)


func confirm(title: String, text: String, on_yes: Callable, on_no: Callable = Callable(), yes_text: String = "Confirm", no_text: String = "Cancel") -> void:
	UIConfirm.show_in(self, title, text, on_yes, on_no, yes_text, no_text)


## Give keyboard / gamepad focus to the first focusable descendant (call after populating).
func focus_first() -> void:
	var f := _first_focusable(self)
	if f != null:
		f.call_deferred("grab_focus")


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control:
			var ctl := c as Control
			if ctl.visible and ctl.focus_mode == Control.FOCUS_ALL:
				if ctl is BaseButton and (ctl as BaseButton).disabled:
					continue
				return ctl
			var r := _first_focusable(ctl)
			if r != null:
				return r
	return null
