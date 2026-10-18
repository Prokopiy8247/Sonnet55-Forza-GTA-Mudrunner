extends Node
## Systems-A: EconomySystem / PickupPlacer tests (cash API, ~35 cash stashes, supply points, weapon crates, parachutes, scuba, respawn, saving).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/economy_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds"

var _fails := 0
var _passes := 0
var eco: EconomySystem = null
var player: Player = null


func _check(test_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST %s PASS %s" % [test_name, detail])
	else:
		_fails += 1
		print("TEST %s FAIL %s" % [test_name, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Walks the player onto a pickup and waits until it is collected (or `frames` pass). Returns whether it was collected.
func _collect(id: String, frames: int = 90) -> bool:
	var p: PickupBase = eco.get_pickup(id)
	if p == null:
		return false
	player.teleport_to(p.global_position + Vector3(0.0, 0.15, 0.0), 0.0)
	for i in frames:
		await get_tree().physics_frame
		if not p.active:
			return true
	return not p.active


func run(_main: Node) -> Variant:
	await _frames(30)
	eco = Game.sys(&"economy") as EconomySystem
	player = Game.player as Player
	_check("economy_boot", eco != null and player != null, "system + player")
	if eco == null or player == null:
		return false
	var sk = Game.sys(&"skills")
	if sk != null:
		sk.announce = false
	var guard := 0
	while not eco.is_built and guard < 600:
		await get_tree().physics_frame
		guard += 1
	_check("economy_world_built", eco.is_built and eco.spots.size() > 40, "%d spots, %d pickups" % [eco.spots.size(), eco.get_pickups().size()])

	# ---- the table ------------------------------------------------------------------------------------------------------
	var groups := {}
	var kinds := {}
	for s in eco.spots:
		groups[s["group"]] = int(groups.get(s["group"], 0)) + 1
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
	var cash_total := int(kinds.get(&"cash", 0))
	print("TEST INFO groups=%s kinds=%s" % [str(groups), str(kinds)])
	_check("economy_cash_stashes_35", cash_total >= 33, "%d cash stashes" % cash_total)
	_check("economy_cash_places", int(groups.get("roof", 0)) >= 9 and int(groups.get("alley", 0)) >= 2 and int(groups.get("dock", 0)) >= 3 and int(groups.get("hill", 0)) >= 3 and int(groups.get("wreck", 0)) >= 1, "roofs/alleys/docks/hills/wreck present")
	_check("economy_supply_kinds", int(kinds.get(&"health", 0)) >= 5 and int(kinds.get(&"armor", 0)) >= 3 and int(kinds.get(&"ammo", 0)) >= 2 and int(kinds.get(&"weapon_crate", 0)) >= 4, "health %d armor %d ammo %d crates %d" % [int(kinds.get(&"health", 0)), int(kinds.get(&"armor", 0)), int(kinds.get(&"ammo", 0)), int(kinds.get(&"weapon_crate", 0))])
	_check("economy_gear_pickups", int(kinds.get(&"parachute", 0)) >= 3 and int(kinds.get(&"scuba", 0)) >= 1, "parachutes %d scuba %d" % [int(kinds.get(&"parachute", 0)), int(kinds.get(&"scuba", 0))])
	var bad := 0
	var floating := 0
	var ids := {}
	for s in eco.spots:
		var pos: Vector3 = s["pos"]
		if pos == Vector3.INF or is_nan(pos.x):
			bad += 1
			continue
		if ids.has(s["id"]):
			bad += 1
		ids[s["id"]] = true
		var hit := InteractionUtil.ray(pos + Vector3(0, 0.4, 0), pos + Vector3(0, -1.2, 0), GC.L_WORLD | GC.L_PROP)
		if hit.is_empty():
			floating += 1
	_check("economy_spots_valid_unique", bad == 0, "%d invalid / duplicate" % bad)
	_check("economy_spots_on_ground", floating <= 1, "%d of %d spots without ground within 1.2 m" % [floating, eco.spots.size()])
	var min_d := INF
	for i in eco.spots.size():
		for j in range(i + 1, eco.spots.size()):
			min_d = minf(min_d, (eco.spots[i]["pos"] as Vector3).distance_to(eco.spots[j]["pos"]))
	_check("economy_spots_not_stacked", min_d >= 1.5, "closest pair %.1f m" % min_d)
	var cs = Game.sys(&"combat")
	var combat_world := 0
	if cs != null and cs.get("pickups_root") != null:
		combat_world = (cs.pickups_root as Node).get_child_count()
	_check("economy_takes_over_world_pickups", cs == null or (cs.world_pickups_enabled == false and combat_world == 0), "combat scatter off, %d pickups left in CombatSystem" % combat_world)
	var fallbacks := 0
	for p in eco.get_pickups():
		if p.get("_fallback") == true:
			fallbacks += 1
	_check("economy_pickups_use_glb_models", fallbacks == 0, "%d pickups on code fallbacks" % fallbacks)

	# ---- cash API -----------------------------------------------------------------------------------------------------------
	var seen: Array = []
	var cb := func(amount: int, delta: int) -> void: seen.append([amount, delta])
	Events.cash_changed.connect(cb)
	eco.set_cash(0)
	var e0 := eco.total_earned
	var s0 := eco.total_spent
	eco.set_cash(1000)
	eco.add_cash(250)
	var paid := eco.spend(400)
	var denied := not eco.spend(5000, true)
	Events.cash_changed.disconnect(cb)
	_check("economy_cash_api", Game.cash == 850 and paid and denied and eco.can_afford(850) and not eco.can_afford(851), "cash %d" % Game.cash)
	_check("economy_cash_events_stats", seen.size() >= 3 and eco.total_earned - e0 == 1250 and eco.total_spent - s0 == 400, "events %d, earned +%d spent +%d" % [seen.size(), eco.total_earned - e0, eco.total_spent - s0])
	eco.set_cash(-50)
	_check("economy_cash_never_negative", Game.cash == 0, "cash %d" % Game.cash)

	# ---- collecting a cash stash + respawn ---------------------------------------------------------------------------------------------
	eco.set_cash(100)
	var got: Array = []
	var gcb := func(kind: StringName, amount: int) -> void: got.append([kind, amount])
	Events.pickup_collected.connect(gcb)
	var spot_events: Array = []
	var scb := func(id: String, kind: StringName, amount: int) -> void: spot_events.append([id, kind, amount])
	eco.spot_collected.connect(scb)
	var alley: Dictionary = eco.get_spot("cash_alley_0")
	var took := await _collect("cash_alley_0")
	_check("economy_cash_collected", took and Game.cash == 100 + int(alley["amount"]), "cash %d (+%d)" % [Game.cash, int(alley["amount"])])
	_check("economy_pickup_events", got.size() >= 1 and got[0][0] == &"cash" and spot_events.size() >= 1 and spot_events[0][0] == "cash_alley_0", "pickup_collected %s / spot_collected %s" % [str(got), str(spot_events)])
	var pk: PickupBase = eco.get_pickup("cash_alley_0")
	var left_ms := int(pk.get("_respawn_at")) - Time.get_ticks_msec()
	_check("economy_cash_respawn_timer_15min", pk.respawn_time == PickupPlacer.CASH_RESPAWN and left_ms > 800000, "respawn in %d s" % (left_ms / 1000))
	_check("economy_collected_hidden", not pk.active and not pk.visible, "inactive + hidden")
	player.teleport_to(pk.global_position + Vector3(0, 0.15, 40.0), 0.0)
	pk.set("_respawn_at", Time.get_ticks_msec() - 10)
	await _frames(8)
	_check("economy_pickup_respawns", pk.active and pk.visible, "active again")
	_check("economy_serialize_collected", eco.serialize()["collected"].size() == 0, "nothing collected right now")
	Events.pickup_collected.disconnect(gcb)
	eco.spot_collected.disconnect(scb)

	# ---- persistence of collected pickups --------------------------------------------------------------------------------------------------
	await _collect("cash_pier_beach_pier")
	var blob := eco.serialize()
	var decoded: Dictionary = SaveCodec.decode(JSON.parse_string(JSON.stringify(SaveCodec.encode(blob))))
	_check("economy_serialize_has_collected", decoded["collected"].has("cash_pier_beach_pier") and float(decoded["collected"]["cash_pier_beach_pier"]) > 800.0, "%s" % str(decoded["collected"].keys()))
	var pier: PickupBase = eco.get_pickup("cash_pier_beach_pier")
	pier.set("_respawn_at", 0)
	pier.set_active(true)
	eco.deserialize(decoded)
	_check("economy_deserialize_recollects", not pier.active, "collected pickup is hidden again after load")
	eco.deserialize({"collected": {}})
	_check("economy_deserialize_restores", pier.active, "pickups not in the save are back")
	eco.deserialize({})
	eco.deserialize({"collected": "garbage"})
	_check("economy_deserialize_tolerant", true, "empty / garbage dictionaries do not crash")

	# ---- health / armor only when needed ----------------------------------------------------------------------------------------------------------
	player.health = player.max_health
	var hp: PickupBase = eco.get_pickup("hp_hospital_a")
	player.teleport_to(hp.global_position + Vector3(0, 0.15, 0), 0.0)
	await _frames(60)
	_check("economy_health_ignored_when_full", hp.active, "stays in the world at full health")
	player.health = 30.0
	await _frames(60)
	_check("economy_health_heals", not hp.active and player.health >= 79.0, "hp %.0f" % player.health)
	player.armor = 0.0
	var ar: PickupBase = eco.get_pickup("armor_hospital")
	var aok := await _collect("armor_hospital")
	_check("economy_armor_given", aok and player.armor >= 49.0, "armor %.0f" % player.armor)

	# ---- weapon crate: random mid-tier weapon once, respawns after 10 min ------------------------------------------------------------------
	var w = player.weapons
	var before_ids: Array = w.get_weapon_ids()
	var cok := await _collect("crate_construction")
	var after_ids: Array = w.get_weapon_ids()
	var new_ids: Array = []
	for id in after_ids:
		if not before_ids.has(id):
			new_ids.append(id)
	var crate: PickupBase = eco.get_pickup("crate_construction")
	var crate_left := (int(crate.get("_respawn_at")) - Time.get_ticks_msec()) / 1000
	_check("economy_crate_gives_weapon", cok and new_ids.size() == 1 and PickupPlacer.CRATE_WEAPONS.has(new_ids[0]), "got %s" % str(new_ids))
	_check("economy_crate_respawn_10min", crate_left > 560 and crate_left <= 600, "respawn in %d s" % crate_left)
	_check("economy_crate_label", crate.get_label().begins_with("Weapon crate:"), crate.get_label())

	# ---- parachute ---------------------------------------------------------------------------------------------------------------------------------
	player.has_parachute = false
	var chute_ok := await _collect("chute_b")
	_check("economy_parachute_given", chute_ok and player.has_parachute, "has_parachute=%s" % str(player.has_parachute))
	var chute: PickupBase = eco.get_pickup("chute_tower")
	player.teleport_to(chute.global_position + Vector3(0, 0.15, 0), 0.0)
	await _frames(70)
	_check("economy_parachute_not_taken_twice", chute.active, "already owned -> stays")

	# ---- scuba ----------------------------------------------------------------------------------------------------------------------------------------------
	player.has_scuba = false
	var base_cap := player.lung_capacity()
	var scuba_ok := await _collect("scuba_beach")
	_check("economy_scuba_given", scuba_ok and player.has_scuba and player.lung_capacity() >= base_cap * 3.9, "lung capacity %.0f s -> %.0f s" % [base_cap, player.lung_capacity()])
	player.has_scuba = false

	# ---- underwater stash at the dive wreck (really diving) ------------------------------------------------------------------------------------------------
	var wreck: PickupBase = eco.get_pickup("cash_wreck_0")
	if wreck != null:
		eco.set_cash(0)
		player.teleport_to(wreck.global_position + Vector3(0.0, 1.6, 0.0), 0.0)
		await _frames(20)
		player.cmd_crouch_held = true
		player.use_real_input = false
		var dived := false
		for i in 900:
			await get_tree().physics_frame
			player.cmd_crouch_held = true
			if not wreck.active:
				dived = true
				break
		player.cmd_crouch_held = false
		player.release_input()
		_check("economy_underwater_cash", dived and Game.cash >= 800, "collected while diving (cash %d, depth %.1f)" % [Game.cash, player.global_position.y])
		player.use_real_input = true
	else:
		_check("economy_underwater_cash", false, "no wreck pickup")

	# ---- NPC drops from the weapons module are accepted ----------------------------------------------------------------------------------------------------
	player.teleport_to(Vector3(22.0, 0.3, 41.0), 0.0)
	await _frames(40)
	eco.set_cash(10)
	if cs != null:
		var drop = cs.spawn_pickup(&"cash", player.global_position + Vector3(0.0, 0.0, -0.4), 77, {"lifetime": 30.0})
		await _frames(40)
		_check("economy_npc_cash_drop", drop == null or Game.cash == 87, "cash %d after a dropped 77" % Game.cash)

	# ---- debug helpers ----------------------------------------------------------------------------------------------------------------------------------------------
	var collected_now := eco.get_pickups().size() - eco.count_active()
	eco.respawn_all()
	await _frames(4)
	_check("economy_respawn_all", eco.count_active() == eco.get_pickups().size() and collected_now > 3, "%d pickups restored" % collected_now)
	_check("economy_goto_spot", eco.goto_spot("cash_peak") and absf(player.global_position.y - eco.get_spot("cash_peak")["pos"].y) < 6.0, "teleported to the summit stash")
	await _frames(30)

	# ---- cost --------------------------------------------------------------------------------------------------------------------------------------------------------------
	var t0 := Time.get_ticks_usec()
	for i in 600:
		eco._process(0.016)
	var per_frame := float(Time.get_ticks_usec() - t0) / 600.0
	_check("economy_process_cost", per_frame < 150.0, "%.1f us per frame for %d pickups" % [per_frame, eco.get_pickups().size()])

	if sk != null:
		sk.announce = true
	eco.set_cash(5000)
	print("TEST SUMMARY economy pass=%d fail=%d" % [_passes, _fails])
	return _fails == 0
