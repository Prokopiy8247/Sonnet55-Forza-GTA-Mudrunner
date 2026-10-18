class_name SafehouseSleepMenu
extends MenuBase
## Bed menu of the safehouse: sleep until morning / nap / rest until evening (fade, heal, EnvironmentSystem.set_time) and the
## "wake up here after a knock-out" toggle.

var _clock: Label
var _list: VBoxContainer


func _init() -> void:
	super._init()
	pauses_game = true
	var b := build_frame("Bed", "Safehouse", 760, 0)
	_clock = UIKit.label("", 24, UITheme.C_ACCENT, true)
	b.add_child(_clock)
	_list = UIKit.vbox(8)
	b.add_child(_list)
	set_hints([["Click", "Choose"], ["Esc", "Close"]])


func _on_open(_open_data: Dictionary) -> void:
	_rebuild()
	focus_first()


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var sh = Game.sys(&"safehouse")
	_clock.text = "It is %s" % Util.format_clock(Game.time_of_day)
	for kind in [&"night", &"nap", &"evening"]:
		var opt: Dictionary = SafehouseSystem.SLEEP_OPTIONS[kind]
		var target: float = float(opt["hour"]) if opt.has("hour") else fposmod(Game.time_of_day + float(opt["hours"]), 24.0)
		var hrs := fposmod(target - Game.time_of_day, 24.0)
		var k: StringName = kind
		var row := UIKit.list_row(str(opt["label"]), "Wake at %s  |  restores %d%% health" % [Util.format_clock(target), int(float(opt["heal"]) * 100.0)],
			"+%dh" % int(round(hrs)), func():
				if sh != null:
					sh.sleep(k))
		_list.add_child(row)
	if sh != null:
		_list.add_child(UIKit.toggle_row("Wake up here after a knock-out", sh.respawn_here, func(on: bool): sh.set_respawn_here(on)))
