extends Node
## Bootstrap: the project's main scene. Boots every game system in a fixed order, then hands control to free roam.
## There is NO mission system: the game launches straight into free roam.
##
## Each entry is [registry key, script path]. A system script `extends Node` (or a subclass), exposes
##   func setup(main: Node) -> void       # called once, in this order
##   func post_setup() -> void            # called after ALL systems exist (register UI menus, look up other systems)
## and is reachable afterwards as Game.sys(key). A failing/missing script is skipped with an error so one broken
## module can never prevent the game from booting.

const SYSTEMS: Array = [
	[&"world", "res://gta/code/world/world_root.gd"],
	[&"environment", "res://gta/code/world/environment_system.gd"],
	[&"audio", "res://gta/code/audio/audio_system.gd"],
	[&"vehicles", "res://gta/code/vehicles/vehicle_system.gd"],
	[&"combat", "res://gta/code/weapons/combat_system.gd"],
	[&"player", "res://gta/code/player/player_system.gd"],
	[&"wanted", "res://gta/code/police/wanted_system.gd"],
	[&"police", "res://gta/code/police/police_manager.gd"],
	[&"traffic", "res://gta/code/traffic/traffic_manager.gd"],
	[&"peds", "res://gta/code/npc/ped_manager.gd"],
	[&"economy", "res://gta/code/systems/economy_system.gd"],
	[&"shops", "res://gta/code/systems/shop_system.gd"],
	[&"garage", "res://gta/code/systems/garage_system.gd"],
	[&"safehouse", "res://gta/code/systems/safehouse_system.gd"],
	[&"skills", "res://gta/code/systems/skills_system.gd"],
	[&"wildlife", "res://gta/code/systems/wildlife_system.gd"],
	[&"activities", "res://gta/code/systems/activity_system.gd"],
	[&"transit", "res://gta/code/systems/transit_system.gd"],
	[&"emergency", "res://gta/code/systems/emergency_system.gd"],
	[&"ui", "res://gta/code/ui/ui_root.gd"],
	[&"debug", "res://gta/code/debug/debug_menu.gd"],
]

var systems_root: Node
var boot_log: Array[String] = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Game.main = self
	InputSetup.register()
	systems_root = Node.new()
	systems_root.name = "Systems"
	add_child(systems_root)

	var booted: Array[Node] = []
	for entry in SYSTEMS:
		var node := _boot_system(entry[0], entry[1])
		if node != null:
			booted.append(node)
	for node in booted:
		if is_instance_valid(node) and node.has_method("post_setup"):
			node.post_setup()

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var harness := DevHarness.new()
		harness.name = "DevHarness"
		add_child(harness)
		harness.start(self, args)

	print("[Main] booted %d/%d systems in %d ms" % [booted.size(), SYSTEMS.size(), Time.get_ticks_msec() - t0])
	Events.game_ready.emit()


func _boot_system(key: StringName, script_path: String) -> Node:
	var scr = load(script_path)
	if scr == null or not (scr is Script) or not scr.can_instantiate():
		push_error("[Main] system '%s' failed to load: %s" % [key, script_path])
		boot_log.append("FAILED " + String(key))
		return null
	var node: Node = scr.new()
	node.name = String(key).capitalize().replace(" ", "")
	node.add_to_group(GC.G_SYSTEM)
	systems_root.add_child(node)
	Game.systems[key] = node
	if node.has_method("setup"):
		node.setup(self)
	boot_log.append("ok " + String(key))
	return node
