class_name InteriorDoor
extends Node3D
## Generic interactable (docs/ARCHITECTURE.md s8 interaction contract) used for world entrances, interior exit doors and
## every shop / safehouse "use point". Group `interactable`; the Player's PlayerInteraction reads `interact_range`,
## `get_interaction(player)` and calls `interact(player)`.
##
##   var d := InteriorDoor.new("Browse weapons", func(p): shops.open_menu(&"weapons"))
##   d.text_provider = func(p) -> Dictionary: return {"text": "Closed", "key": "E", "enabled": false}   # optional, overrides text
##
## `tag` is free for the owner (tests look doors up by tag); `meta` is a scratch dictionary.

var interact_range := 2.4
var text := "Use"
var key := "E"
var enabled := true
var on_interact: Callable = Callable()
var text_provider: Callable = Callable()
var tag: StringName = &""
var data: Dictionary = {}
var uses := 0


func _init(p_text: String = "Use", p_cb: Callable = Callable()) -> void:
	text = p_text
	on_interact = p_cb
	add_to_group(GC.G_INTERACT)


func get_interaction(player: Variant = null) -> Dictionary:
	if text_provider.is_valid():
		var d: Variant = text_provider.call(player)
		if d is Dictionary:
			return d
		return {}
	return {"text": text, "key": key, "enabled": enabled}


func interact(player: Variant = null) -> void:
	if not enabled:
		return
	uses += 1
	if on_interact.is_valid():
		on_interact.call(player)
