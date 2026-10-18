class_name InteractionPoint
extends Node3D
## Lightweight world interaction anchor (group `interactable`): the Player's PlayerInteraction scans it, shows "[E] <text>" and calls
## interact(player). No _process, no collision shape: every point simply forwards to its InteractionManager. Props that are baked into
## MultiMeshes (benches, hydrants) are served by a small pool of these anchors that follows the player.

var kind: StringName = &"generic"
var text := "Interact"
var key := "E"
var enabled := true
var interact_range := 2.2               # read by PlayerInteraction (property `interact_range`)
var data: Dictionary = {}
var manager: Node = null                # InteractionManager


func _init() -> void:
	add_to_group(GC.G_INTERACT)


func get_interaction(player: Node) -> Dictionary:
	if manager != null and is_instance_valid(manager) and manager.has_method("describe"):
		return manager.describe(self, player)
	return {"text": text, "key": key, "enabled": enabled}


func interact(player: Node) -> void:
	if manager != null and is_instance_valid(manager) and manager.has_method("activate"):
		manager.activate(self, player)
