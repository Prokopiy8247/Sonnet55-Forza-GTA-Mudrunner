class_name GarageStoredMenu
extends MenuBase
## Stored vehicles (menu id &"garage_stored"): the 6 garage slots with Deliver / Remove, plus "Store current vehicle" when the player
## is driving up to a garage (safehouse door). Also provides build_slot_list() which the phone's vehicle service reuses.

var _list: VBoxContainer = null
var _store_btn_box: HBoxContainer = null
var _site: StringName = &""


func _init() -> void:
	super._init()
	pauses_game = true
	var body := build_frame("Garage", "Stored vehicles", 820, 0)
	_store_btn_box = UIKit.hbox(10)
	body.add_child(_store_btn_box)
	var sl := UIKit.scroll_list(8)
	sl.get_parent().custom_minimum_size = Vector2(0, 460)
	body.add_child(sl.get_parent())
	_list = sl
	set_hints([["Esc", "Close"]])


func _on_open(open_data: Dictionary) -> void:
	_site = StringName(open_data.get("site", ""))
	var gs = Game.sys(&"garage")
	if gs != null and not gs.stored_changed.is_connected(_refresh):
		gs.stored_changed.connect(_refresh)
	_refresh()


func _on_close() -> void:
	var gs = Game.sys(&"garage")
	if gs != null and gs.stored_changed.is_connected(_refresh):
		gs.stored_changed.disconnect(_refresh)


func _refresh() -> void:
	var gs = Game.sys(&"garage")
	if gs == null or not is_open:
		return
	for c in _store_btn_box.get_children():
		c.queue_free()
	var p = Game.player
	var cur = p.get("current_vehicle") if is_instance_valid(p) else null
	if cur is VehicleBase and gs.can_customize(cur):
		var v: VehicleBase = cur
		_store_btn_box.add_child(UIKit.label("Driving: %s" % v.display_name, 22, UITheme.C_TEXT, true))
		_store_btn_box.add_child(UIKit.spacer(0, 0, true))
		var b := UIKit.button("Store this vehicle", func():
			var slot: int = gs.store(v)
			if slot >= 0 and is_instance_valid(p) and v != null:
				p.teleport_to(p.global_position + Vector3(0, 0.3, 0)), &"AccentButton")
		_store_btn_box.add_child(b)
	build_slot_list(gs, _list, true)
	set_title("Garage")


## Fills `container` with one row per slot. `with_remove` adds the Remove button.
## `compact` = the narrow phone layout (smaller texts, shorter status line, narrower buttons).
static func build_slot_list(gs: Node, container: VBoxContainer, with_remove: bool, compact: bool = false) -> void:
	for c in container.get_children():
		c.queue_free()
	var recs: Array = gs.get_stored_vehicles()
	var by_slot: Dictionary = {}
	for r in recs:
		by_slot[int(r["slot"])] = r
	for i in GarageSystem.MAX_SLOTS:
		var row := UIKit.panel(&"PanelDeep")
		var hb := UIKit.hbox(12)
		row.add_child(hb)
		if not by_slot.has(i):
			hb.add_child(UIKit.label("Slot %d" % (i + 1), 20, UITheme.C_DIM, true))
			hb.add_child(UIKit.label("empty", 18, UITheme.C_DIM))
			container.add_child(row)
			continue
		var r: Dictionary = by_slot[i]
		var b := GarageBuild.from_dict(r["build"])
		var chip := ColorRect.new()
		chip.color = b.paint1
		chip.custom_minimum_size = Vector2(10, 46)
		hb.add_child(chip)
		var tv := UIKit.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := UIKit.label(String(r["name"]), 20 if compact else 22, UITheme.C_TEXT, true)
		name_lbl.clip_text = true
		tv.add_child(name_lbl)
		var status := "Plate %s   -   %d %% condition" % [String(r.get("plate", "")), int(round(float(r.get("health", 1.0)) * 100.0))]
		if compact:
			status = "%s  -  %d %%" % [String(r.get("plate", "")), int(round(float(r.get("health", 1.0)) * 100.0))]
		var out_now: bool = bool(r.get("out", false))
		if out_now:
			status = "Out in the world"
		elif gs.pending_delivery.has(i):
			status = "On its way..."
		var status_lbl := UIKit.label(status, 16 if compact else 17, UITheme.C_ACCENT if out_now else UITheme.C_DIM)
		status_lbl.clip_text = true
		tv.add_child(status_lbl)
		tv.custom_minimum_size = Vector2(0, 0)
		hb.add_child(tv)
		var slot := i
		var dbtn := UIKit.button("Locate" if out_now else "Deliver", func():
			gs.deliver(slot, 3.5), &"AccentButton")
		dbtn.custom_minimum_size = Vector2(96 if compact else 120, 44)
		dbtn.disabled = gs.pending_delivery.has(i)
		hb.add_child(dbtn)
		if with_remove:
			var rbtn := UIKit.button("Remove", func():
				gs.remove(slot), &"DangerButton")
			rbtn.custom_minimum_size = Vector2(100, 44)
			hb.add_child(rbtn)
		container.add_child(row)
