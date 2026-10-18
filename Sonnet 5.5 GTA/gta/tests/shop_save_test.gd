extends Node
## Shops / safehouse save round trip through the REAL SaveSystem (slot 6 only, deleted afterwards): appearance, owned clothes, scuba,
## life vests, robbery cooldown, safehouse flags; saving and loading while standing inside an interior; garage integration
## (stored vehicle shown in the safehouse garage, brought out through the roller door).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/shop_save_test.gd -Seconds 150 -GameArgs "--no-intro --no-traffic --no-peds"

const SLOT := 6

var _fails := 0
var _passes := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST ", name, " PASS ", detail)
	else:
		_fails += 1
		print("TEST ", name, " FAIL ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run(_main: Node) -> void:
	await _frames(30)
	var shops = Game.sys(&"shops")
	var it = Game.sys(&"interiors")
	var sh = Game.sys(&"safehouse")
	var p = Game.player
	if shops == null or it == null or sh == null or not is_instance_valid(p):
		print("TEST ABORT missing systems")
		return
	# ---------------------------------------------------------------- round trip
	Game.cash = 7777
	Game.time_frozen = true
	shops.apply_appearance({"shirt": Color("#123456"), "hair": 5, "hat": &"Hat_Beanie", "hat_color": Color("#aa2244"), "beard": &"Beard_1"})
	shops.owned_items["hat_beanie_red"] = true
	shops.scuba_owned = true
	shops.life_vests = 2
	shops.tank_air = 321.0
	shops.rob_times[&"gas_station"] = Time.get_unix_time_from_system() - 100.0
	sh.respawn_here = false
	sh.tv_on = true
	var saved: bool = SaveSystem.save_game(SLOT)
	_ok("save_ok", saved and SaveSystem.has_save(SLOT), "")
	# wreck the state
	shops.reset_appearance()
	shops.owned_items.clear()
	shops.scuba_owned = false
	shops.life_vests = 0
	shops.tank_air = 5.0
	shops.rob_times.clear()
	sh.respawn_here = true
	sh.tv_on = false
	Game.cash = 1
	var loaded: bool = await SaveSystem.load_game_async(SLOT)
	await _frames(20)
	_ok("load_ok", loaded, "")
	var v: Dictionary = shops.get_variant()
	_ok("appearance_restored", (v["shirt"] as Color).is_equal_approx(Color("#123456")) and int(v["hair"]) == 5 and v["hat"] == &"Hat_Beanie" and v["beard"] == &"Beard_1", "shirt %s hair %s hat %s" % [str(v["shirt"]), str(v["hair"]), str(v["hat"])])
	_ok("rig_restored", (p.rig.variant["shirt"] as Color).is_equal_approx(Color("#123456")) and String(p.rig.variant["hat"]) == "Hat_Beanie", "rig hat %s" % str(p.rig.variant.get("hat")))
	_ok("owned_restored", shops.owns_item("hat_beanie_red") and shops.owns_item("top_white_tee"), "")
	_ok("scuba_restored", shops.scuba_owned and bool(p.get_meta(&"has_scuba", false)) and p.has_scuba and shops.life_vests == 2 and absf(shops.tank_air - 321.0) < 30.0, "scuba %s vests %d tank %.0f" % [str(shops.scuba_owned), shops.life_vests, shops.tank_air])
	_ok("rob_cooldown_restored", shops.rob_cooldown_left(&"gas_station") > 480.0 and shops.rob_cooldown_left(&"gas_station") < 520.0, "left %.0f s" % shops.rob_cooldown_left(&"gas_station"))
	_ok("safehouse_flags_restored", not sh.respawn_here and sh.tv_on and bool(p.get_meta(&"respawn_at_safehouse", true)) == false, "respawn_here %s tv %s" % [str(sh.respawn_here), str(sh.tv_on)])
	_ok("cash_restored", Game.cash == 7777, "cash %d" % Game.cash)
	sh.respawn_here = true
	sh.tv_on = false
	# ---------------------------------------------------------------- save / load while inside an interior
	var door = it.door_for(&"safehouse")
	var ret: Vector3 = door.data["return"]
	p.teleport_to(ret + Vector3(0, 0.3, 0), float(door.data["yaw"]))
	await _frames(20)
	await it.enter(&"safehouse", ret, float(door.data["yaw"]), true)
	await _frames(15)
	saved = sh.save_game(SLOT)
	_ok("save_inside_interior", saved, "")
	await it.exit(true)
	await _frames(15)
	p.teleport_to(Vector3(30, 0.3, 40), 0.0)
	await _frames(40)
	_ok("outside_before_load", not it.is_inside(), "")
	loaded = await SaveSystem.load_game_async(SLOT)
	await _frames(40)
	_ok("load_inside_ok", loaded, "")
	_ok("interior_adopted_after_load", it.is_inside() and it.current_interior == &"safehouse", "inside=%s id=%s pos=%s" % [str(it.is_inside()), str(it.current_interior), str(p.global_position.snappedf(0.1))])
	_ok("indoor_flag_after_load", bool(Game.get_meta(&"indoors", false)), "")
	await it.exit(true)
	await _frames(15)
	_ok("exit_after_load_returns_to_door", p.global_position.distance_to(ret) < 1.5, "distance %.2f" % p.global_position.distance_to(ret))
	# ---------------------------------------------------------------- garage integration
	var garage = Game.sys(&"garage")
	if garage == null:
		print("TEST SKIP garage integration: no garage system")
	else:
		var slot: int = garage.add_record(&"sports", Color("#ff3d9a"), Color("#ffffff"))
		_ok("garage_record_added", slot >= 0, "slot %d" % slot)
		var gd = it.door_for(&"safehouse_garage")
		var gret: Vector3 = gd.data["return"]
		p.teleport_to(gret + Vector3(0, 0.3, 0), float(gd.data["yaw"]))
		await _frames(20)
		await it.enter(&"safehouse_garage", gret, float(gd.data["yaw"]), true)
		await _frames(15)
		var room: InteriorRoom = it.get_current_room()
		var shown := 0
		for n in room.get_children():
			if String(n.name).begins_with("Bay") or n.has_meta(&"garage_vehicle"):
				shown += 1
		var tris: Dictionary = room.tri_report()
		_ok("garage_shows_stored_vehicle", int(tris["display"]) > 300, "display tris %d (children flagged %d)" % [int(tris["display"]), shown])
		var recs: Array = sh.get_stored_records()
		_ok("safehouse_lists_records", recs.size() >= 1, "%d records" % recs.size())
		var ok_out: bool = await sh.bring_out_vehicle(slot)
		await _frames(30)
		_ok("bring_out_vehicle", ok_out and not it.is_inside(), "ok=%s inside=%s" % [str(ok_out), str(it.is_inside())])
		var out_v = garage.out_vehicles.get(slot, null)
		_ok("vehicle_outside_garage_door", out_v != null and is_instance_valid(out_v) and out_v.global_position.distance_to(gret) < 8.0, "dist %s" % (str(out_v.global_position.distance_to(gret)) if out_v != null and is_instance_valid(out_v) else "n/a"))
		if out_v != null and is_instance_valid(out_v):
			out_v.queue_free()
		garage.remove(slot)
	SaveSystem.delete_save(SLOT)
	_ok("test_save_deleted", not SaveSystem.has_save(SLOT), "")
	print("TEST SUMMARY pass=%d fail=%d" % [_passes, _fails])
