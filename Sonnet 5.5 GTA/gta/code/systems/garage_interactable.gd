class_name GarageInteractable
extends Node3D
## Small interaction point created by the GarageSystem (group `interactable`, see the interaction contract in ARCHITECTURE s8):
##   kind &"dealer"  - child of a showroom vehicle: "[E] Buy <vehicle> - $price" -> GarageSystem.buy_dealer_vehicle()
##   kind &"garage"  - safehouse garage door: "[E] Open garage" -> stored vehicles menu
## `interact_range` is read by PlayerInteraction (property override of its default 2.5 m).

var kind: StringName = &"dealer"
var vehicle: VehicleBase = null
var site_id: StringName = &""
var interact_range := 3.4


func _ready() -> void:
	add_to_group(GC.G_INTERACT)


func get_interaction(_player: Node) -> Dictionary:
	var gs = Game.sys(&"garage")
	if gs == null:
		return {}
	match kind:
		&"dealer":
			if not is_instance_valid(vehicle):
				return {}
			var price := int(vehicle.def.get("price", 0))
			if price <= 0:
				return {}
			var free: bool = gs.is_free()
			var txt := "Buy %s  (%s)" % [vehicle.display_name, "FREE" if free else Util.format_money(price)]
			return {"text": txt, "key": "E", "enabled": free or Game.can_afford(price)}
		&"garage":
			return {"text": "Open garage", "key": "E", "enabled": true}
	return {}


func interact(_player: Node) -> void:
	var gs = Game.sys(&"garage")
	if gs == null:
		return
	match kind:
		&"dealer":
			if is_instance_valid(vehicle):
				gs.buy_dealer_vehicle(vehicle)
		&"garage":
			gs.open_stored_menu(site_id)
