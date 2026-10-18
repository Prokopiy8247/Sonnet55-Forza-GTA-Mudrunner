extends Node
## Garage / vehicle mods headless tests: data consistency, apply_mods numeric effects (measured acceleration / braking / top speed),
## tyre durability, cosmetic visuals on all 15 ground vehicles, pricing + cash accounting, store / deliver cycle, serialization round trip.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/garage_test.gd -Seconds 240 -GameArgs "--no-traffic --no-peds --no-intro"

const GROUND := [&"compact", &"sedan", &"sports", &"muscle", &"suv", &"pickup", &"van", &"police_cruiser", &"taxi", &"ambulance", &"firetruck",
	&"truck", &"police_tactical", &"motorcycle", &"bicycle"]

var gs: GarageSystem = null


func T(test_name: String, ok: bool, detail: String = "") -> void:
	VehicleTestUtil.report(test_name, ok, detail)


func run(main: Node) -> String:
	await get_tree().create_timer(2.0).timeout
	gs = Game.sys(&"garage")
	T("garage_system_booted", gs != null and gs is GarageSystem)
	if gs == null:
		return "no garage"
	_test_data()
	_test_fit_and_meshes()
	await _test_stats_plumbing(main)
	await _test_performance_numbers(main)
	await _test_cosmetics_all_vehicles(main)
	_test_pricing()
	await _test_store_deliver()
	_test_serialize()
	print("TEST SUMMARY passed=%d failed=%d" % [VehicleTestUtil.passed, VehicleTestUtil.failed])
	return "done passed=%d failed=%d" % [VehicleTestUtil.passed, VehicleTestUtil.failed]


# ---------------------------------------------------------------------------------------------------- data
func _test_data() -> void:
	var perf := VehicleModsData.performance()
	T("data_perf_count", perf.size() >= 8, "n=%d" % perf.size())
	var bad := ""
	for p in perf:
		var lv: Array = p["levels"]
		var fx: Dictionary = p["fx"]
		if fx.is_empty():
			bad += " %s:no_fx" % p["key"]
		for stat in fx:
			if (fx[stat] as Array).size() != lv.size():
				bad += " %s.%s:size" % [p["key"], stat]
		if int(lv[0]["price"]) != 0:
			bad += " %s:lvl0_price" % p["key"]
		for i in range(1, lv.size()):
			if int(lv[i]["price"]) <= 0:
				bad += " %s:lvl%d_free" % [p["key"], i]
	T("data_perf_consistent", bad == "", bad)
	# every part option has a model or a fallback
	var missing := ""
	var nglb := 0
	for slot in VehicleModsData.SLOTS:
		for o in VehicleModsData.slot_options(slot):
			if o["id"] == &"stock":
				continue
			var has_glb: bool = o.has("glb") and ModelLib.exists(String(o["glb"]))
			if has_glb:
				nglb += 1
			else:
				missing += " %s/%s" % [slot, o["id"]]
	T("data_parts_have_model", missing == "", "missing=[%s] glb=%d" % [missing, nglb])
	var rim_bad := ""
	for r in VehicleModsData.rims():
		if r["id"] == &"stock":
			continue
		if not ModelLib.exists(String(r["glb"])):
			rim_bad += " %s" % r["id"]
	T("data_rims_have_model", rim_bad == "", rim_bad)
	var opt_bad := ""
	for id in GROUND:
		for slot in VehicleModsData.slots_for(id):
			if VehicleModsData.slot_options_for(id, slot).size() < 2:
				opt_bad += " %s/%s" % [id, slot]
	T("data_each_slot_has_options", opt_bad == "", opt_bad)
	var cfg_bad := ""
	for id in GROUND:
		var cats := VehicleModsData.categories_for(id)
		if cats.is_empty():
			cfg_bad += " %s" % id
		if not VehicleDefs.has(id):
			cfg_bad += " nodef:%s" % id
	T("data_vehicle_cfg", cfg_bad == "", cfg_bad)
	var tex_ok := true
	for sd in VehicleModsData.PLATES:
		var tex := VehicleModsDecals.plate_texture(sd, "AB 123")
		tex_ok = tex_ok and tex != null and tex.get_width() == 256
	T("data_plate_textures", tex_ok)
	# effects used by VehicleBase include the new stats
	var fx := VehicleModsData.effects()
	T("data_effects_new_stats", fx["turbo"].has("turbo_boost") and fx["armor"].has("health") and fx["tires"].has("tire_hits"))
	T("data_cost_cumulative", VehicleModsData.perf_cost("engine", 0, 3) == 2500 + 5000 + 9000 and VehicleModsData.perf_cost("engine", 3, 1) == 0)


func _test_fit_and_meshes() -> void:
	var bad := ""
	for id in GROUND:
		var m := ModelLib.instance("vehicles/" + String(id))
		if m == null:
			bad += " nomodel:%s" % id
			continue
		add_child(m)
		var an := VehicleModsFit.analyze(m, StringName("test_" + String(id)))
		var mn: Vector3 = an["min"]
		var mx: Vector3 = an["max"]
		if (mx - mn).x < 0.1 or (mx - mn).z < 1.0:
			bad += " extents:%s" % id
		if not ((an["hood"] as Dictionary).has("z0") and (an["roof"] as Dictionary).has("z0")):
			bad += " runs:%s" % id
		m.queue_free()
	T("fit_analysis_15_models", bad == "", bad)


# ---------------------------------------------------------------------------------------------------- stats plumbing
func _test_stats_plumbing(_main: Node) -> void:
	var v := VehicleTestUtil.spawn(&"sedan", Vector3(0, 0.4, 0), 0.0, {"ai": false})
	await VehicleTestUtil.frames(get_tree(), 5)
	var base_mass := v.mass
	var base_hp := v.max_health
	v.apply_mods({"engine": 4, "brakes": 3, "suspension": 3, "transmission": 3, "turbo": 1, "armor": 5, "tires": 3, "weight": 2})
	T("mods_power", is_equal_approx(v.mod_power, 1.35 * 1.07), "mod_power=%.3f" % v.mod_power)
	T("mods_brake", is_equal_approx(v.mod_brake, 1.40), "mod_brake=%.3f" % v.mod_brake)
	T("mods_grip", is_equal_approx(v.mod_grip, 1.09 * 1.08), "mod_grip=%.3f" % v.mod_grip)
	T("mods_shift", is_equal_approx(v.mod_shift, 0.4), "mod_shift=%.3f" % v.mod_shift)
	T("mods_susp_freq", is_equal_approx(v.mod_susp, 1.3), "mod_susp=%.3f" % v.mod_susp)
	T("mods_turbo", is_equal_approx(v.mod_turbo_boost, 0.24) and v.mod_turbo_spool > 1.0, "boost=%.2f spool=%.2f" % [v.mod_turbo_boost, v.mod_turbo_spool])
	T("mods_armor_damage", is_equal_approx(v.damage_taken_mult, 0.5), "dmg_mult=%.2f" % v.damage_taken_mult)
	T("mods_health_multiplier", is_equal_approx(v.max_health, base_hp * 1.4) and is_equal_approx(v.health, v.max_health), "max_health=%.0f (base %.0f)" % [v.max_health, base_hp])
	T("mods_mass", is_equal_approx(v.mass, base_mass * 0.88), "mass=%.0f (base %.0f)" % [v.mass, base_mass])
	T("mods_bulletproof_tyres", v.bulletproof_tires and v.mod_tire_hits >= 99)
	T("mods_suspension_rebuilt", is_equal_approx(v.wheels[0].k, v.wheels[0].k) and v.wheels[0].k > 0.0)
	v.apply_mods({})
	T("mods_reset", is_equal_approx(v.mod_power, 1.0) and is_equal_approx(v.max_health, base_hp) and is_equal_approx(v.mass, base_mass) and not v.bulletproof_tires)
	# tyre durability: reinforced tyres need 3 hits
	v.apply_mods({"tires": 2})
	var wp := v.global_transform * v.wheels[0].rest
	var info := {"zone": GC.ZONE_TIRE, "type": GC.DMG_BULLET, "position": wp, "direction": Vector3.UP}
	v.apply_damage(5.0, info)
	v.apply_damage(5.0, info)
	var flat_after2 := v.wheels[0].flat
	v.apply_damage(5.0, info)
	T("tyre_durability_reinforced", (not flat_after2) and v.wheels[0].flat, "flat after 2 hits=%s after 3=%s" % [flat_after2, v.wheels[0].flat])
	v.repair()
	T("repair_restores_tyres", not v.wheels[0].flat and is_equal_approx(v.health, v.max_health))
	v.apply_mods({"tires": 3})
	v.apply_damage(5.0, info)
	v.apply_damage(5.0, info)
	T("tyre_bulletproof", not v.wheels[0].flat)
	VehicleFactory.despawn(v)


# ---------------------------------------------------------------------------------------------------- measured performance
func _drive(v: VehicleBase, seconds: float, throttle: float, brake: float = 0.0) -> void:
	v.input_throttle = throttle
	v.input_brake = brake
	v.input_steer = 0.0
	var n := int(seconds * 60.0)
	for i in n:
		await get_tree().physics_frame


## returns {t100, v_after, brake_dist}
func _measure(id: StringName, mods: Dictionary, top_run: float) -> Dictionary:
	var v := VehicleTestUtil.spawn(id, Vector3(0, 0.4, 0), 0.0, {"mods": mods})
	await VehicleTestUtil.frames(get_tree(), 90)
	v.set_engine(true)
	var res := {"t100": -1.0, "top": 0.0, "brake": -1.0}
	var t := 0.0
	var start_z := v.global_position.z
	v.input_throttle = 1.0
	while t < 25.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if v.get_speed_kmh() >= 100.0 and res["t100"] < 0.0:
			res["t100"] = t
			break
	# brake from 100
	v.input_throttle = 0.0
	v.input_brake = 1.0
	var p0 := v.global_position
	var tb := 0.0
	while v.get_speed_kmh() > 2.0 and tb < 12.0:
		await get_tree().physics_frame
		tb += 1.0 / 60.0
	res["brake"] = Util.dist_xz(p0, v.global_position)
	# top speed run
	v.input_brake = 0.0
	await _drive(v, top_run, 1.0)
	res["top"] = v.get_speed_kmh()
	VehicleFactory.despawn(v)
	await VehicleTestUtil.frames(get_tree(), 5)
	return res


func _test_performance_numbers(_main: Node) -> void:
	VehicleTestUtil.make_floor(self)
	var full := {"engine": 4, "transmission": 3, "turbo": 1, "brakes": 3, "tires": 2, "suspension": 3, "weight": 2}
	var stock = await _measure(&"sedan", {}, 32.0)
	var tuned = await _measure(&"sedan", full, 32.0)
	print("PERF sedan stock=", stock, " tuned=", tuned)
	T("perf_accel_0_100_faster", stock["t100"] > 0.0 and tuned["t100"] > 0.0 and tuned["t100"] < stock["t100"] * 0.85, "stock %.2fs tuned %.2fs" % [stock["t100"], tuned["t100"]])
	T("perf_brake_distance_shorter", tuned["brake"] > 0.0 and tuned["brake"] < stock["brake"] * 0.95, "stock %.1fm tuned %.1fm" % [stock["brake"], tuned["brake"]])
	T("perf_top_speed_higher", tuned["top"] > stock["top"] + 3.0, "stock %.1f km/h tuned %.1f km/h" % [stock["top"], tuned["top"]])
	var eng_only = await _measure(&"sedan", {"engine": 4}, 6.0)
	T("perf_engine_only_accel", eng_only["t100"] < stock["t100"] * 0.9, "stock %.2fs engine4 %.2fs" % [stock["t100"], eng_only["t100"]])
	var turbo_only = await _measure(&"sedan", {"turbo": 1}, 6.0)
	T("perf_turbo_accel", turbo_only["t100"] < stock["t100"] * 0.97, "stock %.2fs turbo %.2fs" % [stock["t100"], turbo_only["t100"]])
	var brake_only = await _measure(&"sedan", {"brakes": 3}, 4.0)
	T("perf_brakes_only", brake_only["brake"] < stock["brake"] * 0.97, "stock %.1fm brakes3 %.1fm" % [stock["brake"], brake_only["brake"]])
	var arm = await _measure(&"sedan", {"weight": 2}, 4.0)
	T("perf_weight_reduction_accel", arm["t100"] < stock["t100"], "stock %.2fs light %.2fs" % [stock["t100"], arm["t100"]])


# ---------------------------------------------------------------------------------------------------- cosmetics on all vehicles
func _full_cosmetics(id: StringName) -> Dictionary:
	var m := {"rim_style": "split_six", "rim_color": Color(0.85, 0.62, 0.16), "headlight": "cyan", "taillight": "magenta", "underglow": "magenta",
		"plate": "neon", "plate_text": "HB 777", "livery": "racing_twin", "livery_color": Color(1, 1, 1), "horn": 2, "window_tint": 2, "spoiler": 2, "tires": 1}
	for slot in VehicleModsData.slots_for(id):
		var opts := VehicleModsData.slot_options(slot)
		m["p_" + String(slot)] = String(opts[opts.size() - 1]["id"])
	return m


func _test_cosmetics_all_vehicles(_main: Node) -> void:
	var fail := ""
	var total_nodes := 0
	var pos_i := 0
	for id in GROUND:
		var v := VehicleTestUtil.spawn(id, Vector3(20 + pos_i * 9, 0.4, 20), 0.0, {"ai": false})
		pos_i += 1
		if v == null:
			fail += " spawn:%s" % id
			continue
		await VehicleTestUtil.frames(get_tree(), 3)
		v.apply_mods(_full_cosmetics(id))
		var cont := v.model.get_node_or_null("ModParts")
		var kind := String(VehicleModsData.vehicle_cfg(id).get("kind", "car"))
		var n_children := cont.get_child_count() if cont != null else 0
		total_nodes += n_children
		var expect_min := 1
		if kind == "bicycle":
			expect_min = 0
		if n_children < expect_min:
			fail += " noparts:%s(%d)" % [id, n_children]
		if kind == "car" or kind == "truck":
			var rim := v.wheels[0].node.get_node_or_null("RimMod")
			if rim == null:
				fail += " norim:%s" % id
			for slot in VehicleModsData.slots_for(id):
				if cont == null or cont.get_node_or_null("Part_" + String(slot)) == null:
					fail += " nopart:%s/%s" % [id, slot]
		if kind == "car" and cont.get_node_or_null("Livery") == null:
			fail += " nolivery:%s" % id
		if kind != "bicycle" and cont.get_node_or_null("Underglow") == null:
			fail += " nounderglow:%s" % id
		if v.lights != null and not v.lights.tints.has(&"head"):
			fail += " notint:%s" % id
		if not v.has_meta(&"horn_sound"):
			fail += " nohorn:%s" % id
		# removal
		v.apply_mods({})
		var cont2 := v.model.get_node_or_null("ModParts")
		await VehicleTestUtil.frames(get_tree(), 2)
		if cont2 != null and cont2.get_child_count() > 0:
			fail += " leftover:%s(%d)" % [id, cont2.get_child_count()]
		if v.has_meta(&"horn_sound"):
			fail += " horn_left:%s" % id
		VehicleFactory.despawn(v)
	T("cosmetics_all_15_vehicles", fail == "", "%s parts_nodes=%d fallbacks=%s" % [fail, total_nodes, str(VehicleModsVisual.fallbacks_used.size())])


# ---------------------------------------------------------------------------------------------------- pricing / cash
func _test_pricing() -> void:
	var v := VehicleTestUtil.spawn(&"sedan", Vector3(0, 0.4, 60), 0.0, {"ai": false})
	var base := GarageBuild.from_vehicle(v)
	var tgt := base.copy()
	tgt.paint1 = Color("#ff3d9a")
	tgt.finish = &"pearl"
	tgt.set_level("engine", 2)
	tgt.set_part(&"spoiler", &"gt_wing")
	tgt.set_id("rim_style", &"five_spoke")
	tgt.set_level("window_tint", 2)
	var was_unlock := gs.unlock_all
	gs.unlock_all = false
	Game.cheats["unlock_all_mods"] = false
	var entries := gs.quote(base, tgt)
	var total := GarageBuild.total_cost(entries)
	var expect := VehicleModsData.PAINT_PRICE + 1100 + 2500 + 5000 + 3400 + 1400 + (800)
	T("pricing_quote_total", total == int(round(float(expect) * 1.0 / 10.0)) * 10, "total=%d expect~%d entries=%d" % [total, expect, entries.size()])
	var cash0 := Game.cash
	Game.cash = total - 1
	T("pricing_charge_refused", not gs.charge(entries) and Game.cash == total - 1)
	Game.cash = total + 77
	T("pricing_charge_ok", gs.charge(entries) and Game.cash == 77, "cash=%d" % Game.cash)
	gs.unlock_all = true
	T("pricing_unlock_all_free", GarageBuild.total_cost(gs.quote(base, tgt)) == 0)
	gs.unlock_all = false
	Game.cheats["unlock_all_mods"] = true
	T("pricing_cheat_free", GarageBuild.total_cost(gs.quote(base, tgt)) == 0)
	Game.cheats["unlock_all_mods"] = false
	gs.unlock_all = was_unlock
	# downgrade costs nothing
	var down := tgt.copy()
	down.set_level("engine", 0)
	T("pricing_downgrade_free", GarageBuild.total_cost(down.diff_against(tgt, true, 1.0, false)) == 0)
	# repair
	v.health = v.max_health * 0.5
	v.wheels[0].flat = true
	var rc := gs.repair_cost(v)
	T("repair_cost_scales", rc > 0 and gs.repair_needed(v), "cost=%d" % rc)
	Game.cash = 10000
	var ok := gs.repair_vehicle(v, true)
	T("repair_pays_and_fixes", ok and Game.cash == 10000 - rc and is_equal_approx(v.health, v.max_health) and not v.wheels[0].flat, "cash=%d" % Game.cash)
	Game.cash = 0
	v.health = v.max_health * 0.4
	gs.unlock_all = false
	T("repair_refused_without_cash", not gs.repair_vehicle(v, true) and v.health < v.max_health)
	gs.unlock_all = true
	T("repair_free_in_debug", gs.repair_vehicle(v, true) and Game.cash == 0)
	gs.unlock_all = was_unlock
	Game.cash = cash0
	VehicleFactory.despawn(v)


# ---------------------------------------------------------------------------------------------------- store / deliver
func _test_store_deliver() -> void:
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)
	var xf := Transform3D(Basis(Vector3.UP, 0.4), Game.get_player_position() + Vector3(8, 1.0, 6))
	var v := VehicleFactory.spawn(&"muscle", xf, {"paint": Color("#34e0ff"), "paint2": Color("#222222"), "finish": &"pearl",
		"mods": {"engine": 3, "p_spoiler": "gt_wing", "rim_style": "five_spoke", "plate": "sunset", "plate_text": "ZZ 123"}, "health_ratio": 0.7})
	await VehicleTestUtil.frames(get_tree(), 20)
	var slot := gs.store(v)
	T("store_returns_slot", slot == 0, "slot=%d" % slot)
	await VehicleTestUtil.frames(get_tree(), 3)
	var recs := gs.get_stored_vehicles()
	T("store_record", recs.size() == 1 and recs[0]["def"] == "muscle", str(recs.size()))
	var b := GarageBuild.from_dict(gs.get_record(0)["build"])
	T("store_serializes_build", b.def_id == &"muscle" and b.finish == &"pearl" and b.level("engine") == 3 and b.part(&"spoiler") == &"gt_wing" and b.paint1.is_equal_approx(Color("#34e0ff")), "mods=%s" % str(b.mods))
	var d := gs.deliver_now(0)
	T("deliver_now_spawns", d != null and d.def_id == &"muscle")
	if d != null:
		await VehicleTestUtil.frames(get_tree(), 10)
		T("deliver_restores_mods", d.mods.get("engine", 0) == 3 and d.mod_power > 1.2 and d.paint_finish == &"pearl" and d.is_player_owned, "mods=%s power=%.2f" % [str(d.mods), d.mod_power])
		T("deliver_restores_parts", d.model.get_node_or_null("ModParts") != null and d.model.get_node_or_null("ModParts").get_node_or_null("Part_spoiler") != null)
		T("deliver_health", d.get_health_ratio() > 0.6 and d.get_health_ratio() < 0.8, "hr=%.2f" % d.get_health_ratio())
		var out_dist := Util.dist_xz(d.global_position, Game.get_player_position())
		T("deliver_distance_from_player", out_dist > 35.0, "dist=%.1f" % out_dist)
		# deliver again returns the same vehicle (already out)
		var d2 := gs.deliver_now(0)
		T("deliver_twice_same_vehicle", d2 == d)
		# store it back into its own slot
		var slot2 := gs.store(d)
		T("store_back_same_slot", slot2 == 0 and gs.get_stored_vehicles().size() == 1, "slot=%d" % slot2)
	# async delivery with delay
	var f0 := Engine.get_physics_frames()
	var dv: VehicleBase = await gs.deliver(0, 0.5)
	T("deliver_coroutine", dv != null and Engine.get_physics_frames() - f0 >= 25, "frames=%d" % (Engine.get_physics_frames() - f0))
	# slots limit
	for i in range(1, GarageSystem.MAX_SLOTS):
		gs.add_record(&"sedan", Color.RED, Color.BLACK)
	T("slots_full", gs.free_slot_count() == 0 and gs.add_record(&"sedan", Color.RED, Color.BLACK) == -1)
	var cash0 := Game.cash
	Game.cash = 999999
	T("buy_refused_when_full", gs.buy_vehicle(&"sports", Color.RED, Color.BLACK) == -1 and Game.cash == 999999)
	gs.remove(5)
	var price := int(VehicleDefs.get_def(&"sports")["price"])
	Game.cash = price - 1
	T("buy_refused_without_cash", gs.buy_vehicle(&"sports", Color.RED, Color.BLACK) == -1)
	Game.cash = price + 5
	var bs := gs.buy_vehicle(&"sports", Color.RED, Color.BLACK)
	T("buy_vehicle_charges_and_stores", bs == 5 and Game.cash == 5, "slot=%d cash=%d" % [bs, Game.cash])
	Game.cash = cash0
	# dealer vehicles get a buy interaction point
	await get_tree().create_timer(3.0).timeout
	var vs = Game.sys(&"vehicles")
	var pts := 0
	for dvh in vs.dealer_vehicles:
		if is_instance_valid(dvh) and dvh.get_node_or_null("GarageDealerPoint") != null:
			pts += 1
	T("dealer_points_created", pts >= 10, "points=%d dealer=%d" % [pts, vs.dealer_vehicles.size()])
	if dv != null and is_instance_valid(dv):
		VehicleFactory.despawn(dv)
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)


# ---------------------------------------------------------------------------------------------------- serialize
func _test_serialize() -> void:
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)
	var s0 := gs.add_record(&"sports", Color("#ff3d9a"), Color("#101010"), &"chrome", {"engine": 4, "turbo": 1, "p_spoiler": "track_wing", "rim_color": Color(0.1, 0.2, 0.3), "underglow": "cyan", "horn": 3})
	var s1 := gs.add_record(&"bicycle", Color.GREEN, Color.BLACK)
	T("serialize_add_records", s0 == 0 and s1 == 1)
	var data := gs.serialize()
	var json := JSON.stringify(data)
	var parsed = JSON.parse_string(json)
	T("serialize_json_roundtrip", parsed is Dictionary and (parsed["slots"] as Array).size() == GarageSystem.MAX_SLOTS)
	for i in GarageSystem.MAX_SLOTS:
		gs.remove(i)
	T("serialize_cleared", gs.get_stored_vehicles().is_empty())
	gs.deserialize(parsed)
	var recs := gs.get_stored_vehicles()
	T("deserialize_restores_slots", recs.size() == 2 and recs[0]["slot"] == 0 and recs[1]["slot"] == 1)
	var b := GarageBuild.from_dict(gs.get_record(0)["build"])
	T("deserialize_build_equal", b.def_id == &"sports" and b.finish == &"chrome" and b.level("engine") == 4 and b.level("turbo") == 1 and b.part(&"spoiler") == &"track_wing"
		and b.mods["rim_color"] is Color and absf((b.mods["rim_color"] as Color).r - 0.1) < 0.01 and absf((b.mods["rim_color"] as Color).b - 0.3) < 0.01 and int(b.mods["horn"]) == 3 and b.paint1.is_equal_approx(Color("#ff3d9a")), str(b.mods))
	gs.deserialize({"slots": [null, "garbage", {"bad": 1}]})
	T("deserialize_tolerates_garbage", gs.get_stored_vehicles().is_empty())
	gs.deserialize({})
	T("deserialize_tolerates_empty", gs.get_stored_vehicles().is_empty())
