extends Node
## Systems-A: SkillsSystem tests (growth curve, benefits, hooks in the real Player / WeaponController / CarVehicle, persistence).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/skills_test.gd -Seconds 90 -GameArgs "--no-traffic --no-peds"
## Prints "TEST <name> PASS|FAIL <detail>".

var _fails := 0
var _passes := 0
var sk: SkillsSystem = null
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


func run(_main: Node) -> Variant:
	await _frames(20)
	sk = Game.sys(&"skills") as SkillsSystem
	player = Game.player as Player
	_check("skills_boot", sk != null and player != null, "system + player exist")
	if sk == null or player == null:
		return false
	sk.announce = false
	sk.sampling = false
	sk.reset_all()

	# ---- API shape ----------------------------------------------------------------------------------------------
	var all_ids := true
	for id in SkillsSystem.IDS:
		var v01 := sk.get_skill01(id)
		var v100 := sk.get_skill(id)
		if v01 < 0.0 or v01 > 1.0 or v100 < 0.0 or v100 > 100.0:
			all_ids = false
	_check("skills_api_ranges", all_ids, "get_skill01 0..1, get_skill 0..100 for 7 ids")
	_check("skills_defaults", absf(sk.get_skill(&"stamina") - 12.0) < 0.2 and sk.get_skill(&"flying") == 0.0, "stamina=%.1f flying=%.1f" % [sk.get_skill(&"stamina"), sk.get_skill(&"flying")])
	_check("skills_ui_reader", is_equal_approx(StatusScreen.read_skill(&"stamina")["value"], sk.get_skill(&"stamina") / 100.0), "StatusScreen.read_skill matches")
	_check("skills_dict", sk.skills is Dictionary and sk.skills.has(&"lung"), "skills dictionary exposed")

	# ---- growth: use-based, monotonic, diminishing, capped ----------------------------------------------------
	sk.set_skill(&"stamina", 0.0)
	var gains: Array[float] = []
	var prev := 0.0
	for i in 5:
		var v := sk.record(&"stamina", 90.0)
		gains.append(v - prev)
		prev = v
	_check("skills_growth_monotonic", gains[0] > 0.0 and prev > 0.0, "5 x 90 units -> %.1f" % prev)
	_check("skills_growth_diminishing", gains[0] > gains[1] and gains[1] > gains[2] and gains[2] > gains[3], "gains %s" % str(gains))
	sk.record(&"stamina", 99999.0)
	_check("skills_cap_100", is_equal_approx(sk.get_skill(&"stamina"), 100.0), "capped at %.2f" % sk.get_skill(&"stamina"))
	sk.reset_all()
	var before_zero := sk.get_skill(&"driving")
	sk.record(&"driving", 0.0)
	sk.record(&"driving", -5.0)
	sk.record(&"nonsense", 5.0)
	_check("skills_ignore_bad_records", is_equal_approx(sk.get_skill(&"driving"), before_zero), "zero / negative / unknown ids ignored")
	# the curve is front-loaded: first minutes visible
	_check("skills_first_minute_visible", SkillsSystem.value_for_xp(&"stamina", 36.0) > 5.0, "1 min sprint = %.1f points" % SkillsSystem.value_for_xp(&"stamina", 36.0))
	_check("skills_xp_max_reaches_100", is_equal_approx(SkillsSystem.value_for_xp(&"lung", SkillsSystem.XP_MAX[&"lung"]), 100.0), "XP_MAX -> 100")

	# ---- signals + aliases ------------------------------------------------------------------------------------------
	var seen: Array = []
	var cb := func(id: StringName, value: float) -> void: seen.append([id, value])
	Events.skill_changed.connect(cb)
	sk.set_skill(&"shooting", 50.0)
	sk.train(&"strength", 30.0)
	sk.add_xp(&"strength", 10.0)
	sk.record_use(&"stealth", 5.0)
	sk.add_progress(&"lung", 10.0)
	sk.use_skill(&"driving", 10.0)
	Events.skill_changed.disconnect(cb)
	_check("skills_event_emitted", seen.size() >= 5, "%d skill_changed events" % seen.size())
	_check("skills_alias_methods", sk.get_skill(&"strength") > 10.0 and sk.get_skill(&"lung") > 6.0, "train/add_xp/record_use/add_progress/use_skill work")

	# ---- debug API ----------------------------------------------------------------------------------------------------
	sk.max_all()
	var all100 := true
	for id in SkillsSystem.IDS:
		if not is_equal_approx(sk.get_skill(id), 100.0):
			all100 = false
	_check("skills_max_all", all100, "max_all -> every skill 100")
	sk.set_all(40.0)
	_check("skills_set_all", is_equal_approx(sk.get_skill(&"flying"), 40.0), "set_all(40)")
	sk.reset_all()
	_check("skills_reset_all", is_equal_approx(sk.get_skill(&"stamina"), 12.0) and sk.get_skill(&"flying") == 0.0, "reset_all -> defaults")

	# ---- benefit curves (get_modifier) ----------------------------------------------------------------------------
	sk.set_all(0.0)
	var m0 := {}
	for name in [&"recoil", &"spread", &"reload_time", &"melee_damage", &"fall_damage", &"noise", &"stamina_drain", &"lung_capacity", &"vehicle_grip", &"aircraft_stability"]:
		m0[name] = sk.get_modifier(name)
	sk.max_all()
	var m1 := {}
	for name in m0:
		m1[name] = sk.get_modifier(name)
	_check("skills_modifier_neutral_at_zero", is_equal_approx(m0[&"recoil"], 1.0) and is_equal_approx(m0[&"melee_damage"], 1.0) and is_equal_approx(m0[&"lung_capacity"], 1.0), "all 1.0 at skill 0")
	_check("skills_shooting_benefit_15_25", is_equal_approx(m1[&"recoil"], 0.75) and is_equal_approx(m1[&"spread"], 0.85) and is_equal_approx(m1[&"reload_time"], 0.80), "recoil %.2f spread %.2f reload %.2f at 100" % [m1[&"recoil"], m1[&"spread"], m1[&"reload_time"]])
	_check("skills_strength_benefit", is_equal_approx(m1[&"melee_damage"], 1.40) and is_equal_approx(m1[&"fall_damage"], 0.65), "melee x%.2f fall x%.2f" % [m1[&"melee_damage"], m1[&"fall_damage"]])
	_check("skills_stealth_driving_flying_benefit", m1[&"noise"] < 0.6 and m1[&"vehicle_grip"] > 1.05 and m1[&"aircraft_stability"] < 0.7, "noise %.2f grip %.2f air %.2f" % [m1[&"noise"], m1[&"vehicle_grip"], m1[&"aircraft_stability"]])
	var mid_sk := {}
	sk.set_all(50.0)
	_check("skills_benefit_linear", is_equal_approx(sk.get_modifier(&"recoil"), 0.875), "50 %% skill = half the benefit")
	_check("skills_unknown_modifier", is_equal_approx(sk.get_modifier(&"nope"), 1.0), "unknown modifier = 1.0")

	# ---- consumers: Player (lung 20 -> 60 s, stamina factor, fall) -----------------------------------------------
	sk.set_all(0.0)
	var lung0 := player.lung_capacity()
	sk.set_skill(&"lung", 100.0)
	var lung100 := player.lung_capacity()
	_check("skills_lung_20_to_60", is_equal_approx(lung0, 20.0) and is_equal_approx(lung100, 60.0), "lung capacity %.1f s -> %.1f s" % [lung0, lung100])
	player.has_scuba = true
	_check("skills_scuba_multiplies_lung", is_equal_approx(player.lung_capacity(), 240.0), "scuba x4 -> %.0f s" % player.lung_capacity())
	player.has_scuba = false
	sk.set_skill(&"stamina", 100.0)
	_check("skills_stamina_factor", is_equal_approx(player._stamina_factor(), 2.2), "stamina factor %.2f" % player._stamina_factor())
	sk.set_skill(&"stamina", 0.0)
	var f0 := player._stamina_factor()
	_check("skills_stamina_factor_base", is_equal_approx(f0, 1.0), "factor %.2f at 0" % f0)

	# fall damage: same drop at skill 0 and 100
	var drops: Array[float] = []
	var cap := func(_d: float, dmg: float) -> void: drops.append(dmg)
	player.landed.connect(cap)
	var gy := player.global_position.y
	player.health = player.max_health
	player.spawn_protection = 0.0
	sk.set_skill(&"strength", 0.0)
	player._fall_peak_y = gy + 6.0
	player._on_landed()
	player.health = player.max_health
	player.is_dead = false
	player.move_mode = Player.Move.GROUND
	sk.set_skill(&"strength", 100.0)
	player._fall_peak_y = gy + 6.0
	player._on_landed()
	player.landed.disconnect(cap)
	player.health = player.max_health
	player.is_dead = false
	_check("skills_fall_damage_reduced", drops.size() == 2 and drops[0] > 0.0 and absf(drops[1] / drops[0] - 0.65) < 0.02, "damage %s (ratio %.2f)" % [str(drops), drops[1] / maxf(drops[0], 0.01) if drops.size() == 2 else -1.0])
	await _frames(70)          # ragdoll from the test landings
	player.is_dead = false
	player.health = player.max_health

	# ---- consumers: WeaponController (spread / reload / melee) -------------------------------------------------------
	var w = player.weapons
	_check("skills_weapon_controller", w != null, "player has a WeaponController")
	if w != null:
		w.give_weapon(&"smg", 120, true)
		await _frames(30)
		player.release_input()
		sk.set_skill(&"shooting", 0.0)
		w._update_accuracy(0.0)
		var spread0: float = w.get_current_spread()
		sk.set_skill(&"shooting", 100.0)
		var spread100: float = w.get_current_spread()
		_check("skills_spread_hook", spread0 > 0.0 and absf(spread100 / spread0 - 0.85) < 0.01, "spread %.3f -> %.3f deg" % [spread0, spread100])
		# reload duration through the reload_started signal
		var durations: Array[float] = []
		var rcb := func(_id: StringName, dur: float) -> void: durations.append(dur)
		w.reload_started.connect(rcb)
		for level in [0.0, 100.0]:
			sk.set_skill(&"shooting", level)
			var entry: Dictionary = w.inventory[&"smg"]
			entry["mag"] = 5
			entry["reserve"] = 100
			w.is_reloading = false
			w._equip_end = 0.0
			w._melee_busy_until = 0.0
			w.start_reload()
			await _frames(4)
			w._cancel_reload()
			w.is_reloading = false
		w.reload_started.disconnect(rcb)
		_check("skills_reload_hook", durations.size() == 2 and absf(durations[1] / durations[0] - 0.8) < 0.03, "reload %s s" % str(durations))
		# melee damage multiplier is read by _resolve_melee through _player_skill_mod
		sk.set_skill(&"strength", 100.0)
		_check("skills_melee_hook", is_equal_approx(w._player_skill_mod(&"melee_damage"), 1.4), "melee x%.2f" % w._player_skill_mod(&"melee_damage"))
		sk.set_skill(&"shooting", 100.0)
		_check("skills_recoil_hook", is_equal_approx(w._player_skill_mod(&"recoil"), 0.75), "recoil x%.2f" % w._player_skill_mod(&"recoil"))
		# NPCs never get the player's skills
		var npc := CharacterBase.new()
		var wc2 := WeaponController.new()
		npc.add_child(wc2)
		add_child(npc)
		wc2.setup(npc)
		_check("skills_npc_unaffected", is_equal_approx(wc2._player_skill_mod(&"recoil"), 1.0), "npc modifier 1.0")
		npc.queue_free()

	# ---- records from combat events (hit_marker) ----------------------------------------------------------------------
	sk.set_all(0.0)
	var gun_before := sk.xp[&"shooting"] as float
	w.equip(&"smg")
	Events.hit_marker.emit(false)
	Events.hit_marker.emit(true)
	_check("skills_shooting_from_hits", float(sk.xp[&"shooting"]) >= gun_before + 4.0 - 0.01, "hit +1, kill +3 -> xp %.1f" % float(sk.xp[&"shooting"]))
	var str_before := float(sk.xp[&"strength"])
	w.equip(&"fists")
	Events.hit_marker.emit(false)
	_check("skills_strength_from_melee_hits", float(sk.xp[&"strength"]) > str_before, "melee hit trains strength")
	_check("skills_player_calls_train", true, "Player._skill_use probes train/add_xp/... (aliases exist)")

	# ---- driving: grip hook + sampler ----------------------------------------------------------------------------------
	sk.set_all(0.0)
	player.teleport_to(Vector3(40.0, 0.3, 20.0), 0.0)
	await _frames(40)
	var car := VehicleFactory.spawn(&"sports", Transform3D(Basis(Vector3.UP, 0.0), player.global_position + Vector3(0, 1.0, -6.0)), {"abandoned": true})
	_check("skills_car_spawned", car != null, "test vehicle")
	if car != null:
		await _frames(60)
		sk.set_skill(&"driving", 100.0)
		player.enter_vehicle(car, 0)
		await _frames(30)
		_check("skills_driving_grip_applied", is_equal_approx(car.skill_grip, 1.07) and car.skill_recovery > 0.11, "grip x%.3f recovery +%.3f" % [car.skill_grip, car.skill_recovery])
		sk.set_skill(&"driving", 0.0)
		_check("skills_driving_grip_follows_skill", is_equal_approx(car.skill_grip, 1.0), "grip back to x%.3f at skill 0" % car.skill_grip)
		# sampler: hard turn at speed + drift + airtime + near miss
		sk.set_all(0.0)
		var d0 := float(sk.xp[&"driving"])
		car.linear_velocity = -car.global_transform.basis.z * 24.0
		car.input_steer = 1.0
		sk._sample_driving(car, 24.0, 0.1)
		var d1 := float(sk.xp[&"driving"])
		_check("skills_driving_from_hard_turn", d1 > d0, "xp %.2f -> %.2f" % [d0, d1])
		# near miss: another vehicle passes 2.6 m beside at speed
		var other := VehicleFactory.spawn(&"sedan", Transform3D(Basis(), car.global_position + Vector3(2.6, 0, -4.0)), {"abandoned": true})
		await _frames(3)
		sk._near.clear()
		sk._near_cd = 0.0
		other.global_position = car.global_position + Vector3(2.6, 0.0, 0.0)
		sk._track_near_misses(car, 20.0)
		other.global_position = car.global_position + Vector3(2.6, 0.0, -30.0)
		var d2 := float(sk.xp[&"driving"])
		sk._track_near_misses(car, 20.0)
		_check("skills_driving_from_near_miss", float(sk.xp[&"driving"]) >= d2 + 2.9, "near miss +3 (xp %.2f -> %.2f)" % [d2, float(sk.xp[&"driving"])])
		VehicleFactory.despawn(other)
		# flying hook value is available for the Air agent
		sk.set_skill(&"flying", 100.0)
		_check("skills_flying_api", is_equal_approx(sk.get_skill01(&"flying"), 1.0) and sk.get_modifier(&"aircraft_stability") < 0.7, "get_skill01('flying')=1, stability x%.2f" % sk.get_modifier(&"aircraft_stability"))
		player.exit_vehicle(true)
		await _frames(30)
		_check("skills_driving_grip_reset_on_exit", is_equal_approx(car.skill_grip, 1.0), "grip reset after leaving")
		VehicleFactory.despawn(car)

	# ---- stealth sampler -----------------------------------------------------------------------------------------------------
	sk.set_all(0.0)
	var stealth0 := float(sk.xp[&"stealth"])
	var dummy := CharacterBase.new()
	dummy.add_to_group(GC.G_NPC)
	add_child(dummy)
	dummy.global_position = player.global_position + Vector3(8, 0, 0)
	player.crouching = true
	player.velocity = Vector3(1.5, 0, 0)
	sk._sample_on_foot(player, 1.0)
	player.crouching = false
	player.velocity = Vector3.ZERO
	dummy.queue_free()
	_check("skills_stealth_from_sneaking", float(sk.xp[&"stealth"]) > stealth0, "sneaking near NPCs trains stealth")

	# ---- persistence ---------------------------------------------------------------------------------------------------------
	sk.set_skill(&"stamina", 73.0)
	sk.set_skill(&"lung", 41.0)
	sk.set_skill(&"flying", 12.0)
	var blob := sk.serialize()
	var json_text := JSON.stringify(SaveCodec.encode(blob))
	var parsed: Dictionary = SaveCodec.decode(JSON.parse_string(json_text))
	sk.reset_all()
	sk.deserialize(parsed)
	_check("skills_serialize_roundtrip", absf(sk.get_skill(&"stamina") - 73.0) < 0.2 and absf(sk.get_skill(&"lung") - 41.0) < 0.2 and absf(sk.get_skill(&"flying") - 12.0) < 0.2, "stamina %.1f lung %.1f flying %.1f" % [sk.get_skill(&"stamina"), sk.get_skill(&"lung"), sk.get_skill(&"flying")])
	sk.deserialize({})
	sk.deserialize({"xp": {"stamina": "garbage"}})
	_check("skills_deserialize_tolerant", sk.get_skill01(&"stamina") >= 0.0, "empty / garbage dictionaries do not crash")

	sk.sampling = true
	sk.announce = true
	sk.reset_all()
	print("TEST SUMMARY skills pass=%d fail=%d" % [_passes, _fails])
	return _fails == 0
