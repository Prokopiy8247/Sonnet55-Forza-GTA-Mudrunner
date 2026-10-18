class_name ActivityMenu
extends MenuBase
## Small pre-start menu of an activity (weapon set for the range, race options): title, description, best result, one row per option.
## Opened by ActivitySystem.interact_point -> Game.ui.open_menu(&"activity", {"id": activity_id}); choosing a row closes the menu and
## starts the activity with {"option": <id>}.

var system: Node = null
var _desc: Label
var _best: Label
var _list: VBoxContainer
var _activity_id: StringName = &""


func _init() -> void:
	super._init()
	pauses_game = true
	var b := build_frame("Activity", "", 820, 0)
	_desc = UIKit.label("", 20, UITheme.C_TEXT)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(760, 0)
	b.add_child(_desc)
	_best = UIKit.label("", 19, UITheme.C_WARN, true)
	b.add_child(_best)
	_list = UIKit.vbox(8)
	b.add_child(_list)
	set_hints([["Click", "Start"], ["Esc", "Cancel"]])


func _on_open(open_data: Dictionary) -> void:
	_activity_id = StringName(String(open_data.get("id", "")))
	_rebuild()
	focus_first()


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var act: ActivityBase = null
	if system != null and is_instance_valid(system):
		act = system.get_activity(_activity_id)
	if act == null:
		_desc.text = "This activity is not available."
		_best.text = ""
		return
	set_title(act.title)
	_desc.text = act.description + (("\n" + act.menu_hint) if act.menu_hint != "" else "")
	_best.text = act.best_line()
	var opts: Array = act.options
	if opts.is_empty():
		opts = [{"id": "start", "name": "Start", "desc": "Hold E at any time to quit."}]
	for o in opts:
		var od: Dictionary = o
		var oid := String(od.get("id", ""))
		var right := String(od.get("right", ""))
		if right == "" and system != null:
			right = system.best_text(String(act.id) + ":" + oid, true)
		var row := UIKit.list_row(String(od.get("name", oid)), String(od.get("desc", "")), right, func():
			_choose(oid))
		if od.has("enabled") and not bool(od["enabled"]):
			row.disabled = true
		_list.add_child(row)


func _choose(opt_id: String) -> void:
	if Game.ui != null:
		Game.ui.close_menu()
	if system != null and is_instance_valid(system):
		system.start_deferred(_activity_id, {"option": opt_id})
