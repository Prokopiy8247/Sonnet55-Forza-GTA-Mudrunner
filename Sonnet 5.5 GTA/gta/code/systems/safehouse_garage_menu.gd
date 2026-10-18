class_name SafehouseGarageMenu
extends MenuBase
## Vehicle console of the safehouse garage: lists the vehicles stored through GarageSystem (get_stored_vehicles) and brings one
## out through the roller door (SafehouseSystem.bring_out_vehicle -> GarageSystem.deliver_now). Duck typed: works with whatever
## subset of the Garage API exists.

var _list: VBoxContainer


func _init() -> void:
	super._init()
	pauses_game = true
	var b := build_frame("Vehicle console", "Safehouse garage", 900, 0)
	_list = UIKit.vbox(8)
	b.add_child(_list)
	set_hints([["Click", "Bring outside"], ["Esc", "Close"]])


func _on_open(_open_data: Dictionary) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var sh = Game.sys(&"safehouse")
	var recs: Array = sh.get_stored_records() if sh != null else []
	if recs.is_empty():
		var l := UIKit.label("No vehicles stored yet.\nCustomize or buy a vehicle at Foundry Garage / the dealership, or call the garage service from your phone.", 20, UITheme.C_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for rec in recs:
		var slot := int(rec.get("slot", 0))
		var out := bool(rec.get("out", false))
		var hp := int(round(float(rec.get("health", 1.0)) * 100.0))
		var sub := "Plate %s   |   condition %d%%   |   %s" % [str(rec.get("plate", "-")), hp, "currently outside" if out else "parked in the garage"]
		var row := UIKit.list_row(str(rec.get("name", "Vehicle")), sub, "OUTSIDE" if out else "BRING OUT", func():
			if sh != null:
				sh.bring_out_vehicle(slot))
		_list.add_child(row)
	focus_first()
