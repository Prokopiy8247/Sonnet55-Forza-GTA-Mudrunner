class_name TaxiMenu
extends MenuBase
## Destination picker of the taxi service. open(data): {"destinations": [{name, sub, fare, ...}], "on_pick": Callable(dest)}.


func _on_open(open_data: Dictionary) -> void:
	var b := build_frame("City Cab", "Where to? The meter starts when the cab moves.", 780.0, 0.0)
	var list := UIKit.scroll_list(8)
	list.get_parent().custom_minimum_size = Vector2(0, 430)
	b.add_child(list.get_parent())
	var dests: Array = open_data.get("destinations", [])
	if dests.is_empty():
		list.add_child(UIKit.label("No destination reachable by road.", 18, UITheme.C_TEXT))
	var on_pick: Callable = open_data.get("on_pick", Callable())
	var free: bool = bool(open_data.get("free", false))
	for d in dests:
		var dd: Dictionary = d
		var fare_txt := "FREE" if free else Util.format_money(int(dd.get("fare", 0)))
		list.add_child(UIKit.list_row(str(dd.get("name", "?")), str(dd.get("sub", "")), fare_txt, func() -> void:
			close()
			if on_pick.is_valid():
				on_pick.call(dd)))
	set_hints([["Click", "Choose destination"], ["Esc", "Stay in the cab"]])
	focus_first()
