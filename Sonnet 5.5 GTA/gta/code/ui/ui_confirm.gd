class_name UIConfirm
extends Control
## Modal confirm dialog (yes / no) drawn above the current menu. Use UIConfirm.show_in(parent, ...) or
## UIRoot.confirm(...). Esc / ui_cancel = "no". Emits nothing; runs the callbacks and frees itself.

static var active: UIConfirm = null

var _on_yes: Callable
var _on_no: Callable


static func show_in(parent: Control, title: String, text: String, on_yes: Callable, on_no: Callable = Callable(),
		yes_text: String = "Confirm", no_text: String = "Cancel") -> UIConfirm:
	if active != null and is_instance_valid(active):
		active.queue_free()
	var d := UIConfirm.new()
	d._on_yes = on_yes
	d._on_no = on_no
	d._build(title, text, yes_text, no_text)
	parent.add_child(d)
	active = d
	return d


func _build(title: String, text: String, yes_text: String, no_text: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UIKit.panel(&"PanelHi")
	p.custom_minimum_size = Vector2(560, 0)
	center.add_child(p)
	var v := UIKit.vbox(16)
	p.add_child(v)
	v.add_child(UIKit.label(title.to_upper(), 28, UITheme.C_TEXT, true))
	var body := UIKit.label(text, 21, UITheme.C_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 0)
	v.add_child(body)
	var h := UIKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	var no_b := UIKit.button(no_text, func(): _answer(false))
	var yes_b := UIKit.button(yes_text, func(): _answer(true), &"AccentButton")
	h.add_child(no_b)
	h.add_child(yes_b)
	no_b.call_deferred("grab_focus")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)


func _answer(yes: bool) -> void:
	if active == self:
		active = null
	var cb := _on_yes if yes else _on_no
	queue_free()
	if cb.is_valid():
		cb.call()
