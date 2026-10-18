class_name TransitSystem
extends Node
## Public transport: the taxi passenger service (TaxiService, phone Taxi app -> call_taxi()) and the elevated shuttle train (TrainService).
## Booted by Main: setup(main) once, post_setup() after all systems exist.

var taxi: TaxiService = null
var trains: Node = null


func setup(_main: Node) -> void:
	taxi = TaxiService.new()
	taxi.name = "Taxi"
	add_child(taxi)


func post_setup() -> void:
	if Game.ui != null and Game.ui.has_method("register_menu"):
		Game.ui.register_menu(&"taxi", TaxiMenu.new())
	if taxi != null:
		taxi.post_setup()
	var scr = load("res://gta/code/systems/train_service.gd") if ResourceLoader.exists("res://gta/code/systems/train_service.gd") else null
	if scr != null and scr.can_instantiate():
		trains = scr.new()
		trains.name = "Trains"
		add_child(trains)
		if trains.has_method("post_setup"):
			trains.post_setup()


## Phone Taxi app / debug: sends a cab to the player. Returns false when no cab can be sent (the phone then toasts).
func call_taxi() -> bool:
	return taxi != null and taxi.call_taxi()


func despawn_all() -> void:
	if taxi != null:
		taxi.reset()


func get_stats() -> Dictionary:
	return {"taxi_state": taxi.state if taxi != null else -1, "trips": taxi.trips if taxi != null else 0}
