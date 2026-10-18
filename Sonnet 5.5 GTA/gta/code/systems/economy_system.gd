class_name EconomySystem
extends Node
## Money + world pickups + the world-interaction hub (Systems-A). Booted by Main as Game.sys(&"economy").
##
## * Cash API (debug menu / shops): get_cash() set_cash(n) add_cash(n) spend(n) can_afford(n). The balance itself is Game.cash;
##   Events.cash_changed feeds the HUD floaters and the UI money statistics.
## * ~35 cash stashes (rooftops, alleys, docks, hills, beach, park, yards, airport, the dive wreck), health / armor / ammo points, weapon crates,
##   parachutes and a scuba set (PickupPlacer holds the table). Pickups use the weapons module's PickupBase / CashPickup / HealthPickup /
##   ArmorPickup / AmmoPickup / WeaponPickup classes; this system animates the ones near the player, handles respawn timers and saving.
##   NPC cash drops come from CombatSystem.drop_loot() (Peds agent) and are not touched here.
## * Hosts the InteractionManager (ladders, elevator, benches, phone booths, hydrants): Game.sys(&"interactions").

signal world_ready(pickup_count: int)
signal spot_collected(spot_id: String, kind: StringName, amount: int)

const ANIMATE_RADIUS := 45.0
const VIS_END := 120.0

var pickups_root: Node3D = null
var interactions: InteractionManager = null
var spots: Array = []                    # PickupPlacer spot dictionaries
var is_built := false
var total_earned := 0                    # this session, from Events.cash_changed
var total_spent := 0

var _nodes: Dictionary = {}              # spot id -> PickupBase
var _list: Array[PickupBase] = []
var _pending_state: Dictionary = {}      # id -> seconds left (a save was loaded before the pickups existed)
var _t := 0.0


func setup(_main: Node) -> void:
	name = "Economy"
	pickups_root = Node3D.new()
	pickups_root.name = "WorldPickups"
	add_child(pickups_root)
	# this system takes over the world pickups the weapons module used to scatter (same spots, plus the rest of the table)
	var cs = Game.sys(&"combat")
	if cs != null and cs.get("world_pickups_enabled") != null:
		cs.set("world_pickups_enabled", false)
	interactions = InteractionManager.new()
	interactions.name = "Interactions"
	add_child(interactions)
	Game.systems[&"interactions"] = interactions
	interactions.setup(self)
	Events.cash_changed.connect(_on_cash_changed)


func post_setup() -> void:
	interactions.post_setup()
	_build_world.call_deferred()


# ======================================================================================================== cash API
func get_cash() -> int:
	return Game.cash


func set_cash(amount: int) -> void:
	Game.cash = maxi(amount, 0)


func add_cash(amount: int, _reason: String = "") -> void:
	if amount != 0:
		Game.cash = maxi(Game.cash + amount, 0)


func can_afford(amount: int) -> bool:
	return Game.cash >= amount


## Pays `amount` if possible (toast on failure when `warn`). Returns whether it was paid.
func spend(amount: int, warn: bool = false) -> bool:
	if amount <= 0:
		return true
	if Game.cash < amount:
		if warn:
			Game.notify("Not enough cash (%s needed)" % Util.format_money(amount), &"warn")
			Sfx.play_ui(&"ui_error")
		return false
	Game.cash -= amount
	return true


func _on_cash_changed(_amount: int, delta: int) -> void:
	if delta > 0:
		total_earned += delta
	elif delta < 0:
		total_spent -= delta


# ======================================================================================================== world pickups
func _build_world() -> void:
	for i in 10:
		await get_tree().physics_frame
	while not WorldLayout.built:
		await get_tree().physics_frame
	await interactions.build()
	var t0 := Time.get_ticks_msec()
	spots = PickupPlacer.build_spots(interactions.get_roof_rewards())
	for s in spots:
		_spawn_spot(s)
	is_built = true
	_apply_state(_pending_state)
	_pending_state.clear()
	print("[Economy] %d world pickups placed in %d ms (cash %d, supply %d, crates %d, gear %d)" % [
		_list.size(), Time.get_ticks_msec() - t0, count_group("cash") + count_group("roof") + count_group("alley") + count_group("dock")
		+ count_group("hill") + count_group("beach") + count_group("park") + count_group("yard") + count_group("airport") + count_group("wreck"),
		count_group("supply"), count_group("crate"), count_group("gear")])
	world_ready.emit(_list.size())


func _spawn_spot(s: Dictionary) -> PickupBase:
	var p := PickupPlacer.create(s)
	if p == null:
		return null
	p.set_meta(&"spot_id", s["id"])
	p.name = "P_" + String(s["id"])
	pickups_root.add_child(p)
	p.global_position = s["pos"]
	for gi in p.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = VIS_END
	p.collected.connect(_on_spot_collected.bind(s))
	_nodes[s["id"]] = p
	_list.append(p)
	return p


func _on_spot_collected(_by: Node, s: Dictionary) -> void:
	spot_collected.emit(String(s["id"]), s["kind"], int((_nodes[s["id"]] as PickupBase).amount))


func _process(delta: float) -> void:
	if _list.is_empty():
		return
	_t += delta
	var pp := Game.get_player_position()
	var r2 := ANIMATE_RADIUS * ANIMATE_RADIUS
	for p in _list:
		if not is_instance_valid(p):
			continue
		if not p.active:
			p.animate(_t, delta)                 # respawn timer
		elif p.global_position.distance_squared_to(pp) < r2:
			p.animate(_t, delta)


func count_group(group: String) -> int:
	var n := 0
	for s in spots:
		if s["group"] == group:
			n += 1
	return n


func get_spot(id: String) -> Dictionary:
	for s in spots:
		if s["id"] == id:
			return s
	return {}


func get_pickup(id: String) -> PickupBase:
	var p = _nodes.get(id, null)
	return p if p != null and is_instance_valid(p) else null


func get_pickups() -> Array[PickupBase]:
	return _list


func count_active() -> int:
	var n := 0
	for p in _list:
		if is_instance_valid(p) and p.active:
			n += 1
	return n


## Debug: every collected pickup is back immediately.
func respawn_all() -> void:
	for p in _list:
		if is_instance_valid(p) and not p.active:
			p.set("_respawn_at", 0)
			p.set_active(true)


## Debug: moves the player next to a pickup spot.
func goto_spot(id: String) -> bool:
	var s := get_spot(id)
	if s.is_empty() or not is_instance_valid(Game.player):
		return false
	Game.player.teleport_to((s["pos"] as Vector3) + Vector3(1.6, 0.3, 0.0))
	return true


# ======================================================================================================== persistence
func serialize() -> Dictionary:
	var collected := {}
	var now := Time.get_ticks_msec()
	for id in _nodes:
		var p: PickupBase = _nodes[id]
		if is_instance_valid(p) and not p.active:
			var at := int(p.get("_respawn_at"))
			collected[String(id)] = maxf(float(at - now) * 0.001, 1.0) if at > 0 else 1.0
	return {"collected": collected}


func deserialize(data: Dictionary) -> void:
	var c = data.get("collected", {})
	var state := {}
	if c is Dictionary:
		for k in c:
			state[String(k)] = float(c[k])
	if not is_built:
		_pending_state = state
		return
	_apply_state(state)


func _apply_state(state: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	for id in _nodes:
		var p: PickupBase = _nodes[id]
		if not is_instance_valid(p):
			continue
		if state.has(String(id)):
			p.set_active(false)
			p.set("_respawn_at", now + int(float(state[String(id)]) * 1000.0))
		elif not p.active:
			p.set("_respawn_at", 0)
			p.set_active(true)
