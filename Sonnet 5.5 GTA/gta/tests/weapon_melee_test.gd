extends Node
## Melee test: fists combo (3rd hit knocks down), reach / arc / line of sight, knife backstab, bat + heavy attacks,
## direction-based hit info, props, gun-whip fallback.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/weapon_melee_test.gd -Seconds 60

const K = preload("res://gta/tests/weapon_test_kit.gd")

var _arena: Node3D = null


func run(main: Node) -> String:
	await get_tree().process_frame
	_arena = K.make_arena(main)
	await K.frames(get_tree(), 3)
	await _t_fists()
	await _t_reach_arc()
	await _t_knife()
	await _t_bat()
	await _t_misc()
	K.summary()
	_arena.queue_free()
	return "passed=%d failed=%d" % [K.passed, K.failed]


func _victim(local_pos: Vector3, facing_attacker := true) -> WeaponTestKit.Dummy:
	var d := K.make_dummy(_arena, local_pos)
	d.max_health = 1000.0
	d.health = 1000.0
	if facing_attacker:
		d.rotation.y = PI
	return d


func _attack(wc: WeaponController, shooter: CharacterBase, heavy := false, wait := 40) -> void:
	K.aim(wc, shooter, Vector3(0, 0, -1))
	wc.melee_attack(heavy)
	await K.frames(get_tree(), wait)


func _t_fists() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	var v := _victim(Vector3(0, 0, -1.2))
	await K.frames(get_tree(), 30)
	var hp0 := v.health
	await _attack(wc, shooter)
	var d1 := hp0 - v.health
	hp0 = v.health
	await _attack(wc, shooter)
	var d2 := hp0 - v.health
	var kd_before := v.knocked
	hp0 = v.health
	await _attack(wc, shooter)
	var d3 := hp0 - v.health
	K.check("melee_fists_combo", K.approx(d1, 12.0, 0.1) and K.approx(d2, 12.0, 0.1) and K.approx(d3, 18.0, 0.1), "d=%.1f %.1f %.1f" % [d1, d2, d3])
	K.check("melee_fists_third_knockdown", kd_before == 0 and v.knocked == 1, "knocked=%d" % v.knocked)
	var info: Dictionary = v.last_damage_info
	K.check("melee_hit_info", info.get("type") == GC.DMG_MELEE and info.get("hit_side") == &"front" and info.get("combo") == 3 and info.get("source") == shooter,
		"type=%s side=%s combo=%s" % [info.get("type"), info.get("hit_side"), info.get("combo")])
	# the combo restarts after the pause
	await K.frames(get_tree(), 80)
	hp0 = v.health
	await _attack(wc, shooter)
	var d4 := hp0 - v.health
	K.check("melee_combo_resets", K.approx(d4, 12.0, 0.1), "d4=%.1f" % d4)
	# attacked from behind -> hit_side back
	v.rotation.y = 0.0
	await K.frames(get_tree(), 40)
	await _attack(wc, shooter)
	K.check("melee_hit_side_back", v.last_damage_info.get("hit_side") == &"back", "side=%s" % v.last_damage_info.get("hit_side"))
	# heavy fists = kick with knockdown
	v.rotation.y = PI
	await K.frames(get_tree(), 60)
	var kd := v.knocked
	hp0 = v.health
	await _attack(wc, shooter, true, 70)
	K.check("melee_fists_heavy", v.knocked == kd + 1 and hp0 - v.health > 18.0, "dmg=%.1f knocked=%d" % [hp0 - v.health, v.knocked])
	shooter.queue_free()
	v.queue_free()
	await K.frames(get_tree(), 2)


func _t_reach_arc() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	var far := _victim(Vector3(0, 0, -3.4))
	var behind := _victim(Vector3(0, 0, 1.2))
	var side := _victim(Vector3(1.4, 0, 0.2))
	await K.frames(get_tree(), 30)
	await _attack(wc, shooter)
	K.check("melee_out_of_reach", far.health == 1000.0, "")
	K.check("melee_behind_not_hit", behind.health == 1000.0, "")
	K.check("melee_outside_arc", side.health == 1000.0, "hp=%.0f" % side.health)
	far.queue_free()
	behind.queue_free()
	side.queue_free()
	# line of sight: wall in between
	var v := _victim(Vector3(0, 0, -1.5))
	var wall := K.make_wall(_arena, Vector3(0, 1.0, -0.8), Vector3(3, 3, 0.1), &"concrete")
	await K.frames(get_tree(), 40)
	await _attack(wc, shooter)
	K.check("melee_blocked_by_wall", v.health == 1000.0, "hp=%.0f" % v.health)
	wall.queue_free()
	v.queue_free()
	shooter.queue_free()
	await K.frames(get_tree(), 2)


func _t_knife() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(&"knife", 0, true)
	await K.frames(get_tree(), 40)
	var front := _victim(Vector3(0, 0, -1.2), true)
	await K.frames(get_tree(), 20)
	await _attack(wc, shooter)
	K.check("melee_knife_front", K.approx(1000.0 - front.health, 26.0, 0.2), "dmg=%.1f" % (1000.0 - front.health))
	front.queue_free()
	var back := K.make_dummy(_arena, Vector3(0, 0, -1.2))   # faces -Z like the attacker: attacker is behind it
	await K.frames(get_tree(), 20)
	var died := [false]
	back.died.connect(func(_k, _i): died[0] = true)
	await _attack(wc, shooter)
	K.check("melee_knife_backstab", died[0] and back.is_dead, "hp=%.0f" % back.health)
	back.queue_free()
	shooter.queue_free()
	await K.frames(get_tree(), 2)


func _t_bat() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(&"bat", 0, true)
	await K.frames(get_tree(), 40)
	var v := _victim(Vector3(0, 0, -1.8))
	await K.frames(get_tree(), 20)
	var hp0 := v.health
	await _attack(wc, shooter, false, 60)
	var light := hp0 - v.health
	K.check("melee_bat_light", K.approx(light, 34.0, 0.3) and v.knocked == 0, "dmg=%.1f knocked=%d" % [light, v.knocked])
	hp0 = v.health
	await _attack(wc, shooter, true, 80)
	var heavy := hp0 - v.health
	K.check("melee_bat_heavy_knockdown", K.approx(heavy, 34.0 * 1.8, 0.6) and v.knocked == 1, "dmg=%.1f knocked=%d" % [heavy, v.knocked])
	var imp := v.knock_impulse.length()
	K.check("melee_knockback_force", imp > 8.0, "impulse=%.1f" % imp)
	v.queue_free()
	shooter.queue_free()
	await K.frames(get_tree(), 2)


func _t_misc() -> void:
	var shooter := K.make_shooter(_arena)
	var wc: WeaponController = shooter.weapons
	# gun-whip: pistol equipped -> melee uses the fists profile
	wc.give_weapon(&"pistol", 30, true)
	await K.frames(get_tree(), 40)
	var v := _victim(Vector3(0, 0, -1.2))
	await K.frames(get_tree(), 20)
	var hp0 := v.health
	await _attack(wc, shooter)
	K.check("melee_with_gun_equipped", K.approx(hp0 - v.health, 12.0, 0.2) and wc.current_id == &"pistol" and wc.get_ammo_in_mag() == 15, "dmg=%.1f" % (hp0 - v.health))
	v.queue_free()
	# loose prop gets pushed
	var box := RigidBody3D.new()
	box.mass = 5.0
	box.collision_layer = GC.L_PROP
	box.collision_mask = GC.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.6, 0.6)
	cs.shape = bs
	box.add_child(cs)
	_arena.add_child(box)
	box.position = Vector3(0, 0.4, -1.4)
	await K.frames(get_tree(), 20)
	await _attack(wc, shooter, false, 16)
	K.check("melee_pushes_props", box.linear_velocity.length() > 1.5, "v=%s" % str(box.linear_velocity))
	box.queue_free()
	# no melee while dead
	shooter.die({})
	var v2 := _victim(Vector3(0, 0, -1.2))
	await K.frames(get_tree(), 10)
	wc.melee_attack()
	await K.frames(get_tree(), 30)
	K.check("melee_dead_cannot_attack", v2.health == 1000.0, "")
	v2.queue_free()
	shooter.queue_free()
	await K.frames(get_tree(), 2)
