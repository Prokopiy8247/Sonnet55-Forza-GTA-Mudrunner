class_name ActivityPoint
extends Node3D
## World interaction anchor of one activity (group `interactable`): the Player's PlayerInteraction scan shows "[E] <text>" and calls
## interact(player). No _process, no collision: it only forwards to the ActivitySystem. The neon marker is a separate node.

var activity: ActivityBase = null
var system: Node = null              # ActivitySystem
var interact_range := 3.2            # read by PlayerInteraction (property `interact_range`)


func _init() -> void:
	add_to_group(GC.G_INTERACT)


func get_interaction(player: Node) -> Dictionary:
	if system != null and is_instance_valid(system) and system.has_method("describe_point"):
		return system.describe_point(self, player)
	return {"text": "Activity", "key": "E", "enabled": true}


func interact(player: Node) -> void:
	if system != null and is_instance_valid(system) and system.has_method("interact_point"):
		system.interact_point(self, player)
