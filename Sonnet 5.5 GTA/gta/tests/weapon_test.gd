extends Node
## Weapons core test: defs, ballistics (damage, zones, falloff, armor, penetration), fire rate, ammo / reload accounting,
## recoil decay, mods, scope, serialization, AI accuracy, pickups, loot drops.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/weapon_test.gd -Seconds 90

const K = preload("res://gta/tests/weapon_test_kit.gd")

var _arena: Node3D = null
var _main: Node = null


func run(main: Node) -> String:
	_main = main
	await get_tree().process_frame
	_arena = K.make_arena(main)
	await K.frames(get_tree(), 3)
	_t_defs()
	await _t_ballistics()
	await _t_fire_rate()
	await _t_ammo()
	await _t_shell_reload()
	await _t_recoil()
	await _t_mods()
	await _t_scope()
	await _t_ai_accuracy()
	await _t_pickups()
	await _t_drops()
	await _t_trade()
	await _t_perf()
	K.summary()
	_arena.queue_free()
	return "passed=%d failed=%d" % [K.passed, K.failed]


# ------------------------------------------------------------------------------------------------ defs
func _t_defs() -> void:
	var ids := [&"fists", &"knife", &"bat", &"crowbar", &"pistol", &"revolver", &"smg", &"shotgun_pump", &"shotgun_auto",
		&"rifle_assault", &"carbine", &"rifle_marksman", &"sniper", &"grenade", &"rocket_launcher", &"grenade_launcher"]
	var ok := true
	var missing := ""
	for id in ids:
		if not WeaponDefs.has(id):
			ok = false
			missing += String(id) + " "
			continue
		var d := WeaponDefs.get_def(id)
		for k in WeaponDefs.BASE:
			if not d.has(k):
				ok = false
				missing += "%s.%s " % [id, k]
	K.check("defs_complete", ok and WeaponDefs.ids().size() == 16, "n=%d missing=%s" % [WeaponDefs.ids().size(), missing])
	var cats_ok := true
	for cat in WeaponDefs.CATEGORY_ORDER:
		if WeaponDefs.by_category(cat).is_empty():
			cats_ok = false
	K.check("defs_categories", cats_ok, str(WeaponDefs.CATEGORY_ORDER))
	var shop := WeaponDefs.shop_ids()
	K.check("defs_shop_list", shop.size() >= 12 and not shop.has(&"fists"), "shop=%d" % shop.size())
	K.check("mods_compat", WeaponMods.is_compatible(&"pistol", &"suppressor") and not WeaponMods.is_compatible(&"revolver", &"suppressor")
		and WeaponMods.price(&"scope") > 0 and WeaponMods.compatible_mods(&"smg").size() == 5, "")
	K.check("mag_capacity_ext", WeaponDefs.mag_capacity(&"pistol", {&"magazine_ext": true}) == 23, str(WeaponDefs.mag_capacity(&"pistol", {&"magazine_ext": true})))


# ------------------------------------------------------------------------------------------------ ballistics
func _params(weapon: StringName) -> Dictionary:
	var d := WeaponDefs.get_def(weapon)
	return {"shooter": null, "weapon": weapon, "damage": d["damage"], "range": d["range"], "falloff_start": d["falloff_start"],
		"falloff_min": d["falloff_min"], "penetration": d["penetration"], "impulse": 0.0, "exclude": [], "spawn_fx": true}


func _shoot_at(from: Vector3, to: Vector3, p: Dictionary) -> Dictionary:
	var space := _arena.get_world_3d().direct_space_state
	return Ballistics.shoot(space, from, (to - from).normalized(), p)


func _t_ballistics() -> void:
	var dummy := K.make_dummy(_arena, Vector3(0, 0, -30))
	await K.frames(get_tree(), 2)
	var from := K.ORIGIN + Vector3(0, 1.5, 0)
	var base := K.ORIGIN + Vector3(0, 0, -30)
	var p := _params(&"pistol")
	var fo := Ballistics.falloff(30.0, p["falloff_start"], p["falloff_min"], p["range"])
	# torso
	var r := _shoot_at(from, base + Vector3(0, 1.2, 0), p)
	var lost := 100.0 - dummy.health
	K.check("ballistics_torso_30m", r["hit"] and r["target"] == dummy and r["zone"] == GC.ZONE_TORSO and K.approx(lost, 22.0 * fo, 0.6),
		"zone=%s lost=%.2f expect=%.2f dist=%.1f" % [r["zone"], lost, 22.0 * fo, r["dist"]])
	# head
	dummy.health = 100.0
	r = _shoot_at(from, base + Vector3(0, 1.7, 0), p)
	lost = 100.0 - dummy.health
	K.check("ballistics_headshot", r["zone"] == GC.ZONE_HEAD and K.approx(lost, 22.0 * fo * 3.0, 1.2), "zone=%s lost=%.2f" % [r["zone"], lost])
	# limb
	dummy.health = 100.0
	r = _shoot_at(from, base + Vector3(0, 0.35, 0), p)
	lost = 100.0 - dummy.health
	K.check("ballistics_limb", r["zone"] == GC.ZONE_LIMB and K.approx(lost, 22.0 * fo * 0.7, 0.8), "zone=%s lost=%.2f" % [r["zone"], lost])
	# armor absorbs 70 %
	dummy.health = 100.0
	dummy.armor = 100.0
	r = _shoot_at(from, base + Vector3(0, 1.2, 0), p)
	var hp_lost := 100.0 - dummy.health
	var armor_lost := 100.0 - dummy.armor
	K.check("ballistics_armor", K.approx(armor_lost, 22.0 * fo * 0.7, 0.8) and K.approx(hp_lost, 22.0 * fo * 0.3, 0.6),
		"armor_lost=%.2f hp_lost=%.2f" % [armor_lost, hp_lost])
	# kill flag
	dummy.health = 10.0
	dummy.armor = 0.0
	var died := [0]
	dummy.died.connect(func(_k, _i): died[0] += 1)
	r = _shoot_at(from, base + Vector3(0, 1.2, 0), p)
	K.check("ballistics_kill_flag", r["killed"] and dummy.is_dead and died[0] == 1, "killed=%s dead=%s" % [r["killed"], dummy.is_dead])
	# a dead target is not hit again as killed
	dummy.revive()
	# shotgun falloff near vs far
	var sp := _params(&"shotgun_pump")
	var near_dummy := K.make_dummy(_arena, Vector3(2.0, 0, -5))
	var far_dummy := K.make_dummy(_arena, Vector3(-2.0, 0, -45))
	await K.frames(get_tree(), 2)
	_shoot_at(from, K.ORIGIN + Vector3(2, 1.2, -5), sp)
	_shoot_at(from, K.ORIGIN + Vector3(-2, 1.2, -45), sp)
	var near_lost := 100.0 - near_dummy.health
	var far_lost := 100.0 - far_dummy.health
	K.check("ballistics_falloff_shotgun", near_lost > far_lost * 2.5 and far_lost > 0.0, "near=%.1f far=%.1f" % [near_lost, far_lost])
	# thin glass is penetrated (damage reduced), concrete blocks
	dummy.health = 100.0
	var glass := K.make_wall(_arena, Vector3(0, 1.5, -12), Vector3(4, 3, 0.05), &"glass")
	await K.frames(get_tree(), 2)
	r = _shoot_at(from, base + Vector3(0, 1.2, 0), p)
	lost = 100.0 - dummy.health
	K.check("ballistics_penetrate_glass", r["target"] == dummy and lost > 0.0 and lost < 22.0 * fo, "lost=%.2f" % lost)
	glass.queue_free()
	var conc := K.make_wall(_arena, Vector3(0, 1.5, -12), Vector3(4, 3, 0.4), &"concrete")
	await K.frames(get_tree(), 2)
	dummy.health = 100.0
	r = _shoot_at(from, base + Vector3(0, 1.2, 0), p)
	K.check("ballistics_wall_blocks", r["target"] == null and dummy.health == 100.0 and r["surface"] == &"concrete", "surface=%s" % r["surface"])
	# marksman rifle penetrates thin glass only if penetration>=1; wood table
	conc.queue_free()
	near_dummy.queue_free()
	far_dummy.queue_free()
	dummy.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ fire rate
func _count_shots(wc: WeaponController, shooter: CharacterBase, seconds: float, hold: bool) -> int:
	var counter := [0]
	var cb := func(_id): counter[0] += 1
	wc.fired.connect(cb)
	var frames := int(round(seconds * 60.0))
	if hold:
		wc.set_trigger(true)
	for i in frames:
		K.aim(wc, shooter, Vector3(0, 0, -1))
		if not hold:
			wc.set_trigger(true)
			wc.set_trigger(false)
		await get_tree().physics_frame
	wc.set_trigger(false)
	wc.fired.disconnect(cb)
	return counter[0]


func _t_fire_rate() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	for id in [&"smg", &"rifle_assault", &"pistol", &"shotgun_pump"]:
		wc.give_weapon(id, 900, true)
		wc.refill_all_ammo()
		wc.auto_reload = false
		await K.frames(get_tree(), 60)
		var d := WeaponDefs.get_def(id)
		var rate := float(d["fire_rate"])
		var secs := minf(3.0, float(d["mag_size"]) / rate * 0.85)
		var shots: int = await _count_shots(wc, shooter, secs, d["mode"] == &"auto")
		var expect := rate * secs
		var ok := absf(float(shots) - expect) <= maxf(expect * 0.05, 1.5)
		K.check("fire_rate_" + String(id), ok, "shots=%d expect=%.1f (rate %.1f/s)" % [shots, expect, rate])
		wc.refill_all_ammo()
	# burst
	wc.give_weapon(&"carbine", 300, true)
	wc.auto_reload = false
	await K.frames(get_tree(), 60)
	var counter := [0]
	var cb := func(_id): counter[0] += 1
	wc.fired.connect(cb)
	wc.set_trigger(true)
	K.aim(wc, shooter, Vector3(0, 0, -1))
	await get_tree().physics_frame
	wc.set_trigger(false)
	await K.frames(get_tree(), 40)
	wc.fired.disconnect(cb)
	K.check("fire_burst_3", counter[0] == 3, "shots=%d" % counter[0])
	shooter.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ ammo / reload
func _fire_n(wc: WeaponController, shooter: CharacterBase, n: int) -> int:
	var done := 0
	var guard := 0
	while done < n and guard < 600:
		guard += 1
		K.aim(wc, shooter, Vector3(0, 0, -1))
		if wc.fire_once():
			done += 1
		await get_tree().physics_frame
	return done


func _t_ammo() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.auto_reload = false
	wc.give_weapon(&"pistol", 60, true)
	await K.frames(get_tree(), 40)
	K.check("ammo_give", wc.get_ammo_in_mag() == 15 and wc.get_ammo_reserve() == 45, "mag=%d res=%d" % [wc.get_ammo_in_mag(), wc.get_ammo_reserve()])
	var n: int = await _fire_n(wc, shooter, 15)
	K.check("ammo_fire_15", n == 15 and wc.get_ammo_in_mag() == 0 and wc.get_ammo_reserve() == 45, "mag=%d" % wc.get_ammo_in_mag())
	var clicks := [0]
	wc.empty_clicked.connect(func(_id): clicks[0] += 1)
	await K.frames(get_tree(), 20)
	K.aim(wc, shooter, Vector3(0, 0, -1))
	var fired_empty := wc.fire_once()
	await K.frames(get_tree(), 5)
	K.check("ammo_dry_fire", not fired_empty and clicks[0] >= 1, "clicks=%d" % clicks[0])
	var reloaded_sig := [0]
	wc.reloaded.connect(func(_id): reloaded_sig[0] += 1)
	wc.start_reload()
	K.check("reload_starts", wc.is_reloading, "")
	await K.frames(get_tree(), 20)
	var prog_mid := wc.reload_progress
	await K.frames(get_tree(), 90)
	K.check("reload_full", not wc.is_reloading and wc.get_ammo_in_mag() == 15 and wc.get_ammo_reserve() == 30 and reloaded_sig[0] == 1 and prog_mid > 0.1,
		"mag=%d res=%d mid=%.2f" % [wc.get_ammo_in_mag(), wc.get_ammo_reserve(), prog_mid])
	# partial reserve
	wc.inventory[&"pistol"]["mag"] = 0
	wc.inventory[&"pistol"]["reserve"] = 5
	wc.start_reload()
	await K.frames(get_tree(), 120)
	K.check("reload_partial", wc.get_ammo_in_mag() == 5 and wc.get_ammo_reserve() == 0, "mag=%d res=%d" % [wc.get_ammo_in_mag(), wc.get_ammo_reserve()])
	# no reserve -> no reload
	wc.inventory[&"pistol"]["mag"] = 3
	wc.start_reload()
	K.check("reload_no_reserve", not wc.is_reloading, "")
	# full mag -> no reload
	wc.inventory[&"pistol"]["mag"] = 15
	wc.inventory[&"pistol"]["reserve"] = 30
	wc.start_reload()
	K.check("reload_full_mag_noop", not wc.is_reloading, "")
	# cancel on weapon switch, ammo untouched
	wc.inventory[&"pistol"]["mag"] = 4
	wc.start_reload()
	await K.frames(get_tree(), 15)
	wc.equip(&"fists")
	await K.frames(get_tree(), 5)
	K.check("reload_cancel_on_switch", not wc.is_reloading and int(wc.inventory[&"pistol"]["mag"]) == 4 and int(wc.inventory[&"pistol"]["reserve"]) == 30,
		"mag=%d res=%d" % [int(wc.inventory[&"pistol"]["mag"]), int(wc.inventory[&"pistol"]["reserve"])])
	# ammo cap
	wc.give_weapon(&"pistol", 9999)
	K.check("ammo_reserve_cap", wc.inventory[&"pistol"]["reserve"] == 150, "res=%d" % wc.inventory[&"pistol"]["reserve"])
	var added := wc.add_ammo(&"pistol", 50)
	K.check("ammo_add_at_cap", added == 0, "added=%d" % added)
	# auto reload on empty
	wc.auto_reload = true
	wc.equip(&"pistol")
	await K.frames(get_tree(), 40)
	wc.inventory[&"pistol"]["mag"] = 1
	wc.inventory[&"pistol"]["reserve"] = 20
	await _fire_n(wc, shooter, 1)
	await K.frames(get_tree(), 150)
	K.check("auto_reload_on_empty", wc.get_ammo_in_mag() == 15 and wc.get_ammo_reserve() == 5, "mag=%d res=%d" % [wc.get_ammo_in_mag(), wc.get_ammo_reserve()])
	# slot switching
	wc.give_weapon(&"smg", 90)
	wc.give_weapon(&"knife")
	wc.equip_slot(3)
	var s3 := wc.current_id
	wc.equip_slot(2)
	var s2 := wc.current_id
	wc.equip_slot(1)
	var s1 := wc.current_id
	wc.equip_next()
	var nx := wc.current_id
	wc.equip_slot(9)
	K.check("equip_slots", s3 == &"smg" and s2 == &"pistol" and s1 == &"knife" and nx != &"knife" and wc.current_id == &"fists", "%s %s %s %s %s" % [s3, s2, s1, nx, wc.current_id])
	shooter.queue_free()
	await K.frames(get_tree(), 2)


func _t_shell_reload() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.auto_reload = false
	wc.give_weapon(&"shotgun_pump", 30, true)
	await K.frames(get_tree(), 50)
	await _fire_n(wc, shooter, 3)
	K.check("shell_fire", wc.get_ammo_in_mag() == 4, "mag=%d" % wc.get_ammo_in_mag())
	wc.start_reload()
	await K.frames(get_tree(), 70)   # 0.55 start + ~1 shell
	var mid := wc.get_ammo_in_mag()
	K.check("shell_reload_progress", wc.is_reloading and mid >= 5 and mid <= 6, "mag=%d reloading=%s" % [mid, wc.is_reloading])
	# fire interrupts the reload
	K.aim(wc, shooter, Vector3(0, 0, -1))
	var fired_now := wc.fire_once()
	await K.frames(get_tree(), 3)
	K.check("shell_reload_interrupt", fired_now and not wc.is_reloading and wc.get_ammo_in_mag() == mid - 1, "fired=%s mag=%d" % [fired_now, wc.get_ammo_in_mag()])
	wc.start_reload()
	await K.frames(get_tree(), 300)
	K.check("shell_reload_full", not wc.is_reloading and wc.get_ammo_in_mag() == 7, "mag=%d res=%d" % [wc.get_ammo_in_mag(), wc.get_ammo_reserve()])
	shooter.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ recoil
func _t_recoil() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.auto_reload = false
	wc.give_weapon(&"rifle_assault", 300, true)
	await K.frames(get_tree(), 50)
	var kicks := [0.0]
	wc.recoil_kick.connect(func(p, _y): kicks[0] += p)
	wc.set_trigger(true)
	for i in 30:
		K.aim(wc, shooter, Vector3(0, 0, -1))
		await get_tree().physics_frame
	var peak := wc.kick_pitch
	var spread_peak := wc.current_spread
	wc.set_trigger(false)
	await K.frames(get_tree(), 150)
	K.check("recoil_kick_and_decay", peak > 0.01 and absf(wc.kick_pitch) < 0.0008 and kicks[0] > 0.02, "peak=%.4f after=%.5f sum=%.3f" % [peak, wc.kick_pitch, kicks[0]])
	var spread_rest := wc.current_spread
	K.check("spread_bloom_decay", spread_peak > spread_rest + 0.5, "peak=%.2f rest=%.2f" % [spread_peak, spread_rest])
	# aiming tightens, crouching tightens
	wc.set_aiming(true)
	await K.frames(get_tree(), 40)
	var aimed := wc.current_spread
	wc.set_aiming(false)
	await K.frames(get_tree(), 40)
	wc.crouched = true
	var crouch := wc.get_current_spread()
	wc.crouched = false
	K.check("accuracy_model", aimed < spread_rest * 0.8 and crouch < spread_rest, "hip=%.2f aim=%.2f crouch=%.2f" % [spread_rest, aimed, crouch])
	shooter.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ mods
func _t_mods() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.auto_reload = false
	wc.give_weapon(&"pistol", 60, true)
	await K.frames(get_tree(), 40)
	var loud := []
	var cb := func(_pos, l, _src): loud.append(l)
	Events.gunshot.connect(cb)
	await _fire_n(wc, shooter, 1)
	var plain := float(loud.back())
	K.check("noise_unsuppressed", K.approx(plain, 65.0, 0.1) and K.approx(wc.get_noise_radius(), 65.0, 0.1), "loud=%.1f" % plain)
	K.check("mod_install", wc.set_mod(&"pistol", &"suppressor", true) and wc.has_mod(&"pistol", &"suppressor"), "")
	K.check("mod_incompatible", not wc.set_mod(&"pistol", &"grip", true), "")
	await K.frames(get_tree(), 15)
	await _fire_n(wc, shooter, 1)
	var supp := float(loud.back())
	var eff := wc.get_effective()
	K.check("mod_suppressor", K.approx(supp, plain * 0.25, 0.1) and K.approx(float(eff["damage"]), 22.0 * 0.92, 0.01), "loud=%.1f dmg=%.2f" % [supp, float(eff["damage"])])
	wc.set_mod(&"pistol", &"magazine_ext", true)
	K.check("mod_magazine_ext", wc.get_mag_capacity() == 23, "cap=%d" % wc.get_mag_capacity())
	wc.set_mod(&"pistol", &"scope", true)
	K.check("mod_scope_zoom", K.approx(wc.get_zoom_factor(), 1.2 * 1.9, 0.01), "zoom=%.2f" % wc.get_zoom_factor())
	wc.set_mod(&"pistol", &"flashlight", true)
	wc.toggle_flashlight()
	await K.frames(get_tree(), 5)
	var m := wc.get_model()
	K.check("mod_flashlight", m != null and m.has_flashlight() and m.is_flashlight_on(), "")
	wc.set_tint(&"pistol", WeaponMods.tint_color(&"magenta"))
	K.check("mod_tint", wc.inventory[&"pistol"]["tint"].is_equal_approx(Color("#ff3d9a")), "")
	# grip on smg halves nothing but scales recoil/spread
	wc.give_weapon(&"smg", 90)
	var base_spread := float(WeaponDefs.get_def(&"smg")["spread"])
	wc.set_mod(&"smg", &"grip", true)
	wc.equip(&"smg")
	await K.frames(get_tree(), 30)
	K.check("mod_grip", K.approx(float(wc.get_effective()["recoil_mult"]), 0.75, 0.001) and wc.current_spread < base_spread * 0.9, "recoil_mult=%.2f spread=%.2f/%.2f" % [float(wc.get_effective()["recoil_mult"]), wc.current_spread, base_spread])
	# serialization round trip
	var data := wc.serialize()
	var json := JSON.stringify(data)
	var back = JSON.parse_string(json)
	var shooter2 := K.make_shooter(_arena, Vector3(5, 0, 0))
	var wc2: WeaponController = shooter2.weapons
	wc2.deserialize(back)
	var ok: bool = wc2.has_weapon(&"pistol") and wc2.has_mod(&"pistol", &"suppressor") and wc2.has_mod(&"pistol", &"magazine_ext") and wc2.has_weapon(&"smg") \
		and wc2.current_id == &"smg" and wc2.inventory[&"pistol"]["mag"] == wc.inventory[&"pistol"]["mag"] and wc2.has_mod(&"smg", &"grip") \
		and wc2.inventory[&"pistol"]["tint"].is_equal_approx(Color("#ff3d9a"))
	K.check("serialize_roundtrip", ok, json.substr(0, 120))
	Events.gunshot.disconnect(cb)
	shooter.queue_free()
	shooter2.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ scope
func _t_scope() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(&"sniper", 40, true)
	await K.frames(get_tree(), 60)
	K.check("scope_inactive_hip", not wc.scope_active, "")
	wc.set_aiming(true)
	for i in 40:
		K.aim(wc, shooter, Vector3(0, 0, -1))
		await get_tree().physics_frame
	var z1 := wc.get_zoom_factor()
	var fov1 := wc.get_aim_fov(75.0)
	K.check("scope_active_aimed", wc.scope_active and K.approx(z1, 4.0, 0.01) and fov1 < 25.0, "zoom=%.1f fov=%.1f" % [z1, fov1])
	wc.cycle_zoom()
	K.check("scope_zoom_level2", K.approx(wc.get_zoom_factor(), 8.0, 0.01) and wc.get_aim_fov(75.0) < 12.0, "fov=%.1f" % wc.get_aim_fov(75.0))
	var sway_before := wc.scope_sway.length()
	wc.hold_breath(true)
	for i in 30:
		await get_tree().physics_frame
	var sway_held := wc.scope_sway.length()
	wc.hold_breath(false)
	K.check("scope_sway", sway_before > 0.0 and wc.scope_sway.length() >= 0.0, "free=%.5f held=%.5f" % [sway_before, sway_held])
	wc.set_aiming(false)
	await K.frames(get_tree(), 40)
	K.check("scope_inactive_after", not wc.scope_active, "")
	shooter.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ AI
func _t_ai_accuracy() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.auto_reload = false
	wc.give_weapon(&"smg", 900, true)
	await K.frames(get_tree(), 40)
	var target := K.make_dummy(_arena, Vector3(0, 0, -20))
	target.max_health = 100000.0
	target.health = 100000.0
	await K.frames(get_tree(), 3)
	var chest := target.global_position + Vector3(0, 1.1, 0)
	var results := {}
	for acc in [1.0, 0.0]:
		shooter.set_meta(&"_acc_override", acc)
		var hits := 0
		var tracker := [0]
		var cb := func(_c, _a, info): if info.get("source") == shooter: tracker[0] += 1
		Events.character_damaged.connect(cb)
		for i in 80:
			wc.aim_at_point(chest, acc)
			wc.refill_all_ammo()
			wc.fire_once()
			await K.frames(get_tree(), 5)
		Events.character_damaged.disconnect(cb)
		results[acc] = tracker[0]
	K.check("ai_accuracy_skill", results[1.0] > results[0.0] * 2 and results[1.0] > 15, "acc1=%d acc0=%d" % [results[1.0], results[0.0]])
	shooter.queue_free()
	target.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ pickups / drops
func _t_pickups() -> void:
	var cs := CombatSystem.get_instance()
	if cs == null:
		K.check("pickups_combat_system", false, "no CombatSystem")
		return
	var player := K.make_shooter(_arena, Vector3(30, 0, 0))
	player.add_to_group(GC.G_PLAYER)
	player.collision_layer = GC.L_PLAYER
	player.health = 40.0
	player.armor = 0.0
	player.name = "FakePlayer"
	await K.frames(get_tree(), 2)
	var pos := player.global_position
	var hp := cs.spawn_pickup(&"health", pos + Vector3(0, 0.0, 0), 50, {"snap": false})
	var ap := cs.spawn_pickup(&"armor", pos, 60, {"snap": false})
	var cp := cs.spawn_pickup(&"cash", pos, 75, {"snap": false})
	var wp := cs.spawn_weapon_pickup(&"smg", pos, 60, {"snap": false})
	var ammo := cs.spawn_pickup(&"ammo", pos, 20, {"snap": false, "weapon": &"smg"})
	var cash0 := Game.cash
	var collected: Array = []
	Events.pickup_collected.connect(func(kind, amount): collected.append([kind, amount]))
	await K.frames(get_tree(), 12)
	K.check("pickup_health", is_equal_approx(player.health, 90.0) and not is_instance_valid(hp), "health=%.0f" % player.health)
	K.check("pickup_armor", is_equal_approx(player.armor, 60.0), "armor=%.0f" % player.armor)
	K.check("pickup_cash", Game.cash == cash0 + 75, "cash delta=%d" % (Game.cash - cash0))
	var pw: WeaponController = player.weapons
	K.check("pickup_weapon", pw.has_weapon(&"smg") and pw.current_id == &"smg" and pw.get_ammo_in_mag() == 30, "smg=%s cur=%s mag=%d" % [pw.has_weapon(&"smg"), pw.current_id, pw.get_ammo_in_mag()])
	K.check("pickup_ammo", pw.get_ammo_reserve() >= 50, "res=%d" % pw.get_ammo_reserve())
	K.check("pickup_events", collected.size() >= 5, "events=%d" % collected.size())
	# full health pack is not wasted
	player.health = 100.0
	var hp2 := cs.spawn_pickup(&"health", pos, 50, {"snap": false})
	await K.frames(get_tree(), 12)
	K.check("pickup_not_wasted", is_instance_valid(hp2), "")
	if is_instance_valid(hp2):
		hp2.queue_free()
	player.queue_free()
	await K.frames(get_tree(), 2)


func _t_drops() -> void:
	var cs := CombatSystem.get_instance()
	if cs == null:
		return
	cs.drop_weapon_chance[GC.F_GANG] = 1.0
	cs.drop_cash_chance[GC.F_GANG] = 1.0
	var npc := K.make_shooter(_arena, Vector3(-30, 0, 0))
	npc.faction = GC.F_GANG
	var nw: WeaponController = npc.weapons
	nw.give_weapon(&"pistol", 40, true)
	await K.frames(get_tree(), 20)
	npc.apply_damage(500.0, {"source": null, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO})
	await K.frames(get_tree(), 60)
	var found_weapon := false
	var found_cash := false
	for p in get_tree().get_nodes_in_group(GC.G_PICKUP):
		if p is WeaponPickup and (p as WeaponPickup).weapon_id == &"pistol" and (p as Node3D).global_position.distance_to(npc.global_position) < 3.0:
			found_weapon = true
		if p is CashPickup and (p as Node3D).global_position.distance_to(npc.global_position) < 3.0:
			found_cash = true
	K.check("drop_weapon_and_cash", found_weapon and found_cash and not nw.has_weapon(&"pistol"), "weapon=%s cash=%s" % [found_weapon, found_cash])
	for p in get_tree().get_nodes_in_group(GC.G_PICKUP):
		if (p as Node3D).global_position.distance_to(K.ORIGIN) < 150.0:
			p.queue_free()
	npc.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ perf
func _t_perf() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(&"smg", 900, true)
	await K.frames(get_tree(), 40)
	var target := K.make_dummy(_arena, Vector3(0, 0, -25))
	target.max_health = 1.0e7
	target.health = 1.0e7
	await K.frames(get_tree(), 3)
	var total_us := 0
	var shots := 0
	for i in 200:
		wc.refill_all_ammo()
		K.aim(wc, shooter, Vector3(0, 0, -1))
		await get_tree().physics_frame
		var t0 := Time.get_ticks_usec()
		var fired := wc.fire_once()
		var dt := Time.get_ticks_usec() - t0
		if fired:
			total_us += dt
			shots += 1
		await K.frames(get_tree(), 4)
	var avg := float(total_us) / maxf(shots, 1)
	K.check("perf_shot_cost", shots > 100 and avg < 600.0, "shots=%d avg=%.0f us" % [shots, avg])
	shooter.queue_free()
	target.queue_free()
	await K.frames(get_tree(), 2)


# ------------------------------------------------------------------------------------------------ shop transactions
func _t_trade() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	var cash0 := Game.cash
	Game.cash = 10000
	var r := WeaponTrade.buy_weapon(wc, &"smg")
	K.check("trade_buy_weapon", r["ok"] and wc.has_weapon(&"smg") and Game.cash == 10000 - 1650 and wc.inventory[&"smg"]["mag"] == 30, "r=%s cash=%d" % [str(r), Game.cash])
	r = WeaponTrade.buy_weapon(wc, &"smg")
	K.check("trade_already_owned", not r["ok"] and r["reason"] == "already owned", str(r))
	wc.inventory[&"smg"]["reserve"] = 0
	r = WeaponTrade.buy_ammo(wc, &"smg", 2)
	K.check("trade_buy_ammo", r["ok"] and wc.inventory[&"smg"]["reserve"] == 60 and r["price"] == 140, str(r))
	r = WeaponTrade.buy_mod(wc, &"smg", &"suppressor")
	K.check("trade_buy_mod", r["ok"] and wc.has_mod(&"smg", &"suppressor") and r["price"] == 450, str(r))
	r = WeaponTrade.buy_mod(wc, &"smg", &"suppressor")
	K.check("trade_mod_twice", not r["ok"], str(r))
	r = WeaponTrade.buy_tint(wc, &"smg", &"olive")
	K.check("trade_tint", r["ok"] and wc.inventory[&"smg"]["tint"].is_equal_approx(Color("#5c6b3f")), str(r))
	Game.cash = 10
	r = WeaponTrade.buy_weapon(wc, &"sniper")
	K.check("trade_no_cash", not r["ok"] and r["reason"] == "not enough cash" and not wc.has_weapon(&"sniper"), str(r))
	Game.cash = cash0
	shooter.queue_free()
	await K.frames(get_tree(), 2)
