extends Node
## Shops / safehouse gameplay test: purchases + cash accounting, mods and tints, armor / health, clothing + barber + appearance
## persistence (JSON round trip), goods (food, scuba, parachute, vests), robbery flow, sleep time skip, respawn redirect.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/shop_economy_test.gd -Seconds 150 -GameArgs "--no-intro --no-traffic --no-peds"

var _fails := 0
var _passes := 0
var _crimes: Array = []
var _reported: Array = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		print("TEST ", name, " PASS ", detail)
	else:
		_fails += 1
		print("TEST ", name, " FAIL ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run(_main: Node) -> void:
	await _frames(25)
	var shops = Game.sys(&"shops")
	var it = Game.sys(&"interiors")
	var sh = Game.sys(&"safehouse")
	var p = Game.player
	var wc = p.weapons
	if shops == null or it == null or sh == null or not is_instance_valid(p):
		print("TEST ABORT missing systems")
		return
	Events.crime_committed.connect(func(c: StringName, pos: Vector3, perp: Node, info: Dictionary) -> void: _crimes.append([c, pos, perp, info]))
	Events.crime_reported.connect(func(c: StringName, pos: Vector3, perp: Node) -> void: _reported.append([c, pos, perp]))
	# ---------------------------------------------------------------- weapons
	Game.cash = 5000
	shops.free_shopping = false
	var r: Dictionary = shops.buy_weapon(&"smg")
	_ok("buy_weapon_smg", bool(r["ok"]) and wc.has_weapon(&"smg") and Game.cash == 5000 - 1650, "cash %d result %s" % [Game.cash, str(r)])
	var reserve0 := int(wc.inventory[&"smg"]["reserve"])
	r = shops.buy_ammo(&"smg", 1)
	_ok("buy_ammo", bool(r["ok"]) and int(wc.inventory[&"smg"]["reserve"]) == reserve0 + 30 and Game.cash == 5000 - 1650 - 70, "reserve %d -> %d cash %d" % [reserve0, int(wc.inventory[&"smg"]["reserve"]), Game.cash])
	var cash_before := Game.cash
	r = shops.buy_weapon(&"smg")
	_ok("already_owned", not bool(r["ok"]) and Game.cash == cash_before, str(r))
	Game.cash = 100
	r = shops.buy_weapon(&"revolver")
	_ok("cannot_afford", not bool(r["ok"]) and Game.cash == 100 and not wc.has_weapon(&"revolver"), str(r))
	shops.free_shopping = true
	r = shops.buy_weapon(&"revolver")
	_ok("free_shopping_weapon", bool(r["ok"]) and wc.has_weapon(&"revolver") and Game.cash == 100, "cash %d" % Game.cash)
	shops.free_shopping = false
	Game.cash = 5000
	# armor / health
	p.armor = 0.0
	r = shops.buy_armor()
	_ok("buy_armor", bool(r["ok"]) and p.armor >= 99.0 and Game.cash == 4700, "armor %.0f cash %d" % [p.armor, Game.cash])
	p.health = 30.0
	r = shops.buy_health()
	_ok("buy_health", bool(r["ok"]) and absf(p.health - 90.0) < 0.5 and Game.cash == 4580, "health %.0f cash %d" % [p.health, Game.cash])
	p.health = p.max_health
	# mods + tint
	Game.cash = 2000
	wc.give_weapon(&"pistol", 60, false)
	r = shops.buy_mod(&"pistol", &"suppressor")
	var eff: Dictionary = WeaponMods.effective(wc.inventory[&"pistol"]["mods"])
	_ok("buy_mod_suppressor", bool(r["ok"]) and Game.cash == 1550 and absf(float(eff["noise_mult"]) - 0.25) < 0.001 and bool(eff["suppressed"]), "cash %d noise x%.2f" % [Game.cash, float(eff["noise_mult"])])
	r = shops.buy_mod(&"pistol", &"magazine_ext")
	_ok("buy_mod_magazine", bool(r["ok"]) and WeaponDefs.mag_capacity(&"pistol", wc.inventory[&"pistol"]["mods"]) == 23, "mag %d" % WeaponDefs.mag_capacity(&"pistol", wc.inventory[&"pistol"]["mods"]))
	r = shops.buy_mod(&"pistol", &"grip")
	_ok("incompatible_mod_rejected", not bool(r["ok"]) and Game.cash == 1250, str(r))
	r = shops.buy_tint(&"pistol", &"crimson")
	var tint: Color = wc.inventory[&"pistol"]["tint"]
	_ok("buy_tint", bool(r["ok"]) and Game.cash == 1190 and tint.a > 0.5 and tint.is_equal_approx(WeaponMods.tint_color(&"crimson")), "cash %d tint %s" % [Game.cash, tint.to_html()])
	r = shops.buy_tint(&"pistol", &"factory")
	_ok("tint_factory_free", bool(r["ok"]) and Game.cash == 1190 and wc.inventory[&"pistol"]["tint"].a < 0.01)
	r = shops.remove_mod(&"pistol", &"suppressor")
	_ok("remove_mod_free", bool(r["ok"]) and Game.cash == 1190 and not wc.has_mod(&"pistol", &"suppressor"))
	# ---------------------------------------------------------------- clothing
	Game.cash = 1000
	var base_variant: Dictionary = shops.get_variant()
	r = shops.buy_outfit(["top_coral_tee", "hat_black_cap", "glasses_shades"], false)
	var v: Dictionary = shops.get_variant()
	_ok("buy_outfit", bool(r["ok"]) and Game.cash == 1000 - (45 + 25 + 45) and (v["shirt"] as Color).is_equal_approx(Color("#e8795f")) and v["hat"] == &"Hat_Cap" and v["glasses"] == &"Glasses_Shades", "cash %d" % Game.cash)
	_ok("outfit_owned", shops.owns_item("top_coral_tee") and shops.owns_item("hat_black_cap"))
	var rig_v: Dictionary = p.rig.variant
	_ok("rig_dressed", (rig_v["shirt"] as Color).is_equal_approx(Color("#e8795f")) and String(rig_v["hat"]) == "Hat_Cap", "rig shirt %s hat %s" % [str(rig_v.get("shirt")), str(rig_v.get("hat"))])
	var meta_app = p.get_meta(&"appearance", null)
	_ok("appearance_meta", meta_app is Dictionary and (meta_app["shirt"] as Color).is_equal_approx(Color("#e8795f")))
	Game.cash = 10
	r = shops.buy_outfit(["jacket_charcoal_coat"], false)
	_ok("outfit_cannot_afford", not bool(r["ok"]) and not shops.owns_item("jacket_charcoal_coat") and Game.cash == 10, str(r))
	r = shops.buy_outfit(["jacket_charcoal_coat"], true)
	_ok("wardrobe_rejects_unowned_premium", not bool(r["ok"]) and Game.cash == 10, str(r))
	r = shops.buy_outfit(["top_black_tee"], true)
	_ok("wardrobe_basic_free", bool(r["ok"]) and Game.cash == 10 and (shops.get_variant()["shirt"] as Color).is_equal_approx(Color("#2a2d33")), str(shops.get_variant()["shirt"]))
	# barber
	Game.cash = 500
	var price: int = shops.barber_price(3, &"Beard_2", Color("#ff3d9a"))
	_ok("barber_price", price == 35 + 25 + 15 + 40, "price %d" % price)
	r = shops.buy_haircut(3, &"Beard_2", Color("#ff3d9a"))
	_ok("barber_buy", bool(r["ok"]) and Game.cash == 500 - 115 and int(p.rig.variant["hair"]) == 3 and String(p.rig.variant["beard"]) == "Beard_2", "cash %d hair %s" % [Game.cash, str(p.rig.variant["hair"])])
	# persistence: JSON round trip
	var data: Dictionary = shops.serialize()
	var json := JSON.stringify(data)
	var back: Variant = JSON.parse_string(json)
	_ok("serialize_json", back is Dictionary and (back as Dictionary).has("appearance"), "%d bytes" % json.length())
	shops.reset_appearance()
	shops.owned_items.clear()
	_ok("reset_appearance", not (shops.get_variant()["shirt"] as Color).is_equal_approx(Color("#2a2d33")))
	shops.deserialize(back)
	await _frames(3)
	var v2: Dictionary = shops.get_variant()
	_ok("deserialize_appearance", (v2["shirt"] as Color).is_equal_approx(Color("#2a2d33")) and int(v2["hair"]) == 3 and v2["beard"] == &"Beard_2" and (v2["hair_color"] as Color).is_equal_approx(Color("#ff3d9a")) and v2["hat"] == &"Hat_Cap", "shirt %s hair %s" % [str(v2["shirt"]), str(v2["hair"])])
	_ok("deserialize_rig", (p.rig.variant["shirt"] as Color).is_equal_approx(Color("#2a2d33")) and shops.owns_item("hat_black_cap"), "")
	shops.apply_appearance({"shirt": Color("#f2f0ea")})
	_ok("apply_appearance_api", (p.rig.variant["shirt"] as Color).is_equal_approx(Color("#f2f0ea")))
	# ---------------------------------------------------------------- goods
	Game.cash = 200
	p.health = 50.0
	r = shops.buy_good(&"food", &"burger")
	_ok("food_burger", bool(r["ok"]) and absf(p.health - 75.0) < 0.5 and Game.cash == 192, "health %.0f cash %d" % [p.health, Game.cash])
	p.health = 100.0
	r = shops.buy_good(&"food", &"burger")
	_ok("food_full_health_rejected", not bool(r["ok"]) and Game.cash == 192, str(r))
	p.stamina = 10.0
	r = shops.buy_good(&"food", &"energy")
	_ok("energy_drink", bool(r["ok"]) and p.stamina >= p.max_stamina - 0.5 and shops.energy_until > Time.get_ticks_msec() * 0.001, "")
	Game.cash = 3000
	r = shops.buy_good(&"scuba", &"scuba_kit")
	_ok("scuba_kit", bool(r["ok"]) and shops.scuba_owned and bool(p.get_meta(&"has_scuba", false)) and Game.cash == 1200, "cash %d" % Game.cash)
	p.head_underwater = true
	shops.tank_air = 100.0
	shops._tick_scuba(1.0)
	_ok("scuba_tank_drains", Game.cheats.get("scuba", false) == true and absf(shops.tank_air - 99.0) < 0.01, "tank %.1f cheat %s" % [shops.tank_air, str(Game.cheats.get("scuba"))])
	shops.tank_air = 0.5
	shops._tick_scuba(1.0)
	shops._tick_scuba(0.1)
	_ok("scuba_tank_empty_stops_air", Game.cheats.get("scuba", false) == false, "tank %.2f" % shops.tank_air)
	p.head_underwater = false
	shops._tick_scuba(1.0)
	_ok("scuba_refills_at_surface", shops.tank_air > 5.0, "tank %.1f" % shops.tank_air)
	r = shops.buy_good(&"scuba", &"scuba_kit")
	_ok("scuba_once_only", not bool(r["ok"]) and Game.cash == 1200, str(r))
	p.has_parachute = false
	r = shops.buy_good(&"scuba", &"parachute")
	_ok("parachute_pack", bool(r["ok"]) and p.has_parachute and Game.cash == 600, "cash %d" % Game.cash)
	r = shops.buy_good(&"scuba", &"vest")
	_ok("life_vest", bool(r["ok"]) and shops.life_vests == 1 and Game.cash == 350)
	p.head_underwater = true
	p.lungs = 0.2
	Game.cheats["scuba"] = false
	var scuba_was: bool = shops.scuba_owned
	shops.scuba_owned = false
	shops._tick_scuba(0.1)
	shops.scuba_owned = scuba_was
	p.head_underwater = false
	_ok("life_vest_refills_lungs", shops.life_vests == 0 and p.lungs > 10.0, "lungs %.1f" % p.lungs)
	# ---------------------------------------------------------------- robbery
	Game.cash = 1000
	var door = it.door_for(&"gas_station")
	var ret: Vector3 = door.data["return"]
	await it.enter(&"gas_station", ret, float(door.data["yaw"]), true)
	await _frames(20)
	var room: InteriorRoom = it.get_current_room()
	var clerk = room.clerk
	_ok("clerk_exists", clerk != null and is_instance_valid(clerk) and not clerk.is_dead and clerk.rig != null, "")
	var cp: InteriorDoor = room.points[&"counter"]
	_ok("counter_prompt_normal", String(cp.get_interaction(p).get("text", "")).begins_with("Buy"), str(cp.get_interaction(p)))
	# threat detection: aim at the clerk with a firearm
	p.global_position = room.to_global(cp.position)
	wc.equip(&"pistol")
	wc.is_aiming = true
	var cam = Game.gameplay_camera
	var from: Vector3 = cam.global_position
	var to: Vector3 = clerk.global_position + Vector3(0, 1.2, 0)
	cam.yaw = Util.dir_to_yaw(Util.flat(to - from).normalized())
	cam.pitch = atan2(to.y - from.y, Util.dist_xz(to, from))
	await _frames(3)
	shops._tick_threat(0.2)
	shops._tick_threat(0.2)
	_ok("clerk_hands_up_when_aimed_at", clerk.hands_up, "state %s" % str(clerk.state))
	wc.is_aiming = false
	var info: Dictionary = cp.get_interaction(p)
	_ok("counter_prompt_rob", String(info.get("text", "")) == "Rob the register" and bool(info.get("enabled", false)), str(info))
	var cash0 := Game.cash
	_crimes.clear()
	cp.interact(p)
	await _frames(3)
	var gained := Game.cash - cash0
	_ok("rob_cash_range", gained >= 300 and gained <= 900, "+$%d" % gained)
	_ok("rob_crime_event", _crimes.size() >= 1 and _crimes[0][0] == GC.CRIME_ROBBERY and bool(_crimes[0][3].get("witnessed", false)) and _crimes[0][2] == p, str(_crimes.size()))
	var alarm: AudioStreamWAV = ShopSystem.alarm_stream()
	var alarm_peak := 0
	for i in range(0, alarm.data.size() - 1, 2):
		alarm_peak = maxi(alarm_peak, absi(alarm.data.decode_s16(i)))
	_ok("alarm_sound_generated", alarm.get_length() > 3.4 and alarm_peak > 10000, "length %.2f s peak %d" % [alarm.get_length(), alarm_peak])
	_ok("alarm_player_running", room.find_children("*", "AudioStreamPlayer3D", true, false).size() >= 1, "")
	info = cp.get_interaction(p)
	_ok("rob_cooldown_blocks", not bool(info.get("enabled", true)) and shops.rob_cooldown_left(&"gas_station") > 590.0, "left %.0f s" % shops.rob_cooldown_left(&"gas_station"))
	cash0 = Game.cash
	cp.interact(p)
	_ok("no_second_rob", Game.cash == cash0)
	# the clerk phones the police a few seconds later when nobody else reported it
	Game.wanted_level = 0
	await get_tree().create_timer(8.0).timeout
	_ok("clerk_reports_robbery", _reported.size() >= 1 and _reported[0][0] == GC.CRIME_ROBBERY, str(_reported.size()))
	# serialize the cooldown
	var sd: Dictionary = shops.serialize()
	_ok("rob_time_serialized", (sd["rob"] as Dictionary).has("gas_station"))
	# kill the clerk -> loot
	clerk.apply_damage(500.0, {"source": p, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "position": clerk.global_position + Vector3(0, 1.2, 0), "direction": Vector3.FORWARD})
	await _frames(5)
	_ok("clerk_dies", clerk.is_dead and clerk.state == &"dead", "")
	shops.rob_times.erase(&"gas_station")
	info = cp.get_interaction(p)
	_ok("dead_clerk_register_lootable", String(info.get("text", "")) == "Loot the register", str(info))
	await it.exit(true)
	# ---------------------------------------------------------------- safehouse
	Game.time_of_day = 14.0
	Game.time_frozen = true
	p.health = 40.0
	var passed: float = await sh.sleep(&"night", true)
	_ok("sleep_time_skip", absf(Game.time_of_day - 7.0) < 0.01 and absf(passed - 17.0) < 0.1, "time %.2f passed %.1f" % [Game.time_of_day, passed])
	_ok("sleep_heals", p.health >= p.max_health - 0.5, "health %.0f" % p.health)
	Game.time_of_day = 23.0
	passed = await sh.sleep(&"nap", true)
	_ok("nap_3h", absf(Game.time_of_day - 2.0) < 0.01 and absf(passed - 3.0) < 0.1, "time %.2f" % Game.time_of_day)
	var hosp: Dictionary = WorldLayout.get_location(&"hospital")
	p.teleport_to(hosp["pos"] + Vector3(0, 0.3, 0))
	await _frames(10)
	Game.cash = 2000
	Events.player_died.emit()
	p.respawn_at(&"hospital", {"penalty": 500, "reason": &"death", "silent": true})
	await _frames(5)
	var tf: Dictionary = it.door_transform(&"safehouse", "Door")
	var d_home: float = p.global_position.distance_to(tf["return"])
	_ok("respawn_at_safehouse", d_home < 3.0, "distance to safehouse door %.1f m" % d_home)
	_ok("respawn_fee_reduced", Game.cash >= 1900 and Game.cash <= 1960, "cash %d" % Game.cash)
	_ok("appearance_survives_respawn", (p.rig.variant["shirt"] as Color).is_equal_approx(Color("#f2f0ea")), "rig shirt %s" % str(p.rig.variant.get("shirt")))
	sh.set_respawn_here(false)
	Game.cash = 2000
	Events.player_died.emit()
	p.respawn_at(&"hospital", {"penalty": 500, "reason": &"death", "silent": true})
	await _frames(5)
	_ok("respawn_hospital_when_disabled", p.global_position.distance_to(hosp["pos"]) < 6.0 and Game.cash == 1500, "dist %.1f cash %d" % [p.global_position.distance_to(hosp["pos"]), Game.cash])
	sh.set_respawn_here(true)
	# save point + tv + snack
	var ok_save: bool = sh.save_game(6)          # slot 6, never the player's own slot 0
	_ok("safehouse_save_point", ok_save and SaveSystem.has_save(6) and sh.last_saved_unix > 0.0, "")
	SaveSystem.delete_save(6)
	await it.enter(&"safehouse", ret, 0.0, true)
	await _frames(5)
	var room2: InteriorRoom = it.get_current_room()
	sh.toggle_tv()
	_ok("tv_on", sh.tv_on and room2.info["tv_light"].light_energy > 0.1)
	await _frames(30)
	_ok("tv_animates", sh._tv_mat != null and sh._tv_mat.emission_enabled)
	sh.toggle_tv()
	_ok("tv_off", not sh.tv_on and room2.info["tv_light"].light_energy < 0.01)
	p.health = 50.0
	sh.snack()
	_ok("snack_heals", p.health >= 74.0, "health %.0f" % p.health)
	var h2: float = p.health
	p.health = 50.0
	sh.snack()
	_ok("snack_cooldown", p.health < 51.0)
	await it.exit(true)
	print("TEST SUMMARY pass=%d fail=%d" % [_passes, _fails])
