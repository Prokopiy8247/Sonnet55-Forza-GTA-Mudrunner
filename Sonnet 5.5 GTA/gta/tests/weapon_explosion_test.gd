extends Node
## Explosion / projectile test: radial damage falloff, line-of-sight, impulses, knockdown, chain reactions, Events.explosion,
## rocket + grenade launcher + thrown grenades (fuse, cook).
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/weapon_explosion_test.gd -Seconds 60

const K = preload("res://gta/tests/weapon_test_kit.gd")

var _arena: Node3D = null
var _cs: CombatSystem = null
var _explosions: Array = []


class FakeCar:
	extends RigidBody3D
	var health := 300.0
	var is_destroyed := false
	var on_destroy: Callable

	func _ready() -> void:
		add_to_group(GC.G_DAMAGEABLE)
		add_to_group(GC.G_VEHICLE)

	func apply_damage(amount: float, _info: Dictionary = {}) -> void:
		if is_destroyed:
			return
		health -= amount
		if health <= 0.0:
			is_destroyed = true
			if on_destroy.is_valid():
				on_destroy.call(self)


func _make_car(local_pos: Vector3, hp: float) -> FakeCar:
	var car := FakeCar.new()
	car.mass = 1200.0
	car.health = hp
	car.collision_layer = GC.L_VEHICLE
	car.collision_mask = GC.L_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.4, 4.2)
	cs.shape = box
	car.add_child(cs)
	_arena.add_child(car)
	car.position = local_pos + Vector3(0, 0.75, 0)
	return car


func run(main: Node) -> String:
	await get_tree().process_frame
	_cs = CombatSystem.get_instance()
	if _cs == null:
		K.check("combat_system_present", false, "")
		return "no combat"
	_arena = K.make_arena(main)
	await K.frames(get_tree(), 3)
	Events.explosion.connect(func(pos, radius, _src): _explosions.append([pos, radius, Time.get_ticks_msec()]))
	await _t_radial()
	await _t_los_and_impulse()
	await _t_chain()
	await _t_rocket()
	await _t_grenade()
	await _t_launcher()
	K.summary()
	_arena.queue_free()
	return "passed=%d failed=%d" % [K.passed, K.failed]


func _hp_dummy(local_pos: Vector3) -> WeaponTestKit.Dummy:
	var d := K.make_dummy(_arena, local_pos)
	d.max_health = 5000.0
	d.health = 5000.0
	return d


func _t_radial() -> void:
	var center := Vector3(0, 0.5, -60)
	var ds: Array = []
	for off in [1.0, 3.5, 6.0, 9.0]:
		ds.append(_hp_dummy(center + Vector3(off, -0.5, 0)))
		center += Vector3(0, 0, 0)
	# spread them around the circle so they do not shield each other
	ds[0].position = center + Vector3(1.0, -0.5, 0)
	ds[1].position = center + Vector3(0, -0.5, 3.5)
	ds[2].position = center + Vector3(-6.0, -0.5, 0)
	ds[3].position = center + Vector3(0, -0.5, -9.0)
	await K.frames(get_tree(), 3)
	_explosions.clear()
	var res := _cs.explode(K.ORIGIN + center, 7.5, 230.0, null, {"weapon": &"test", "fx": true})
	var lost: Array = []
	for d in ds:
		lost.append(5000.0 - d.health)
	var expect_f := func(h: float) -> float:
		var dist := maxf(sqrt(h * h + 0.45 * 0.45) - 0.35, 0.0)
		return 230.0 * pow(clampf(1.0 - dist / 7.5, 0.0, 1.0), 1.2)
	K.check("explosion_falloff", lost[0] > lost[1] and lost[1] > lost[2] and lost[2] > 0.0 and lost[3] == 0.0
		and K.approx(lost[0], expect_f.call(1.0), 8.0) and K.approx(lost[1], expect_f.call(3.5), 8.0),
		"lost=%s expect0=%.0f" % [str(lost), expect_f.call(1.0)])
	K.check("explosion_event", _explosions.size() == 1 and (_explosions[0][1] as float) == 7.5, "n=%d" % _explosions.size())
	K.check("explosion_result", res["targets"] == 3, "targets=%d" % res["targets"])
	K.check("explosion_knockdown", ds[0].knocked >= 1 and ds[1].knocked >= 1 and ds[3].knocked == 0, "k=%d,%d,%d" % [ds[0].knocked, ds[1].knocked, ds[3].knocked])
	var blast_info: Dictionary = ds[0].last_damage_info
	K.check("explosion_damage_info", blast_info.get("type") == GC.DMG_EXPLOSION and blast_info.has("direction") and float(blast_info.get("impulse", 0.0)) > 5.0,
		"type=%s imp=%.1f" % [blast_info.get("type"), float(blast_info.get("impulse", 0.0))])
	# kill + killed credit
	var victim := K.make_dummy(_arena, center + Vector3(0, -0.5, 2.0))
	await K.frames(get_tree(), 2)
	var killer := K.make_dummy(_arena, Vector3(30, 0, -60))
	var credit := [null]
	victim.died.connect(func(k, _i): credit[0] = k)
	_cs.explode(K.ORIGIN + center, 7.5, 230.0, killer, {})
	K.check("explosion_kill_credit", victim.is_dead and credit[0] == killer, "dead=%s" % victim.is_dead)
	for d in ds:
		d.queue_free()
	victim.queue_free()
	killer.queue_free()
	await K.frames(get_tree(), 2)


func _t_los_and_impulse() -> void:
	var center := Vector3(0, 0.5, -60)
	var open_d := _hp_dummy(center + Vector3(4.0, -0.5, 0))
	var shielded := _hp_dummy(center + Vector3(-4.0, -0.5, 0))
	var wall := K.make_wall(_arena, center + Vector3(-2.0, 0.5, 0), Vector3(0.5, 4, 8), &"concrete")
	var car := _make_car(center + Vector3(0, -0.5, 5.5), 100000.0)
	await K.frames(get_tree(), 5)
	_cs.explode(K.ORIGIN + center, 8.0, 200.0, null, {"fx": false})
	var l_open := 5000.0 - open_d.health
	var l_shield := 5000.0 - shielded.health
	K.check("explosion_los", l_open > 0.0 and l_shield > 0.0 and l_shield < l_open * 0.5, "open=%.1f shielded=%.1f" % [l_open, l_shield])
	await K.frames(get_tree(), 3)
	K.check("explosion_impulse_vehicle", car.linear_velocity.length() > 4.0 and car.linear_velocity.y > 0.5, "v=%s" % str(car.linear_velocity))
	open_d.queue_free()
	shielded.queue_free()
	wall.queue_free()
	car.queue_free()
	await K.frames(get_tree(), 2)


func _t_chain() -> void:
	var center := Vector3(0, 0.5, -60)
	var car1 := _make_car(center + Vector3(0, -0.5, 3.0), 100.0)
	var car2 := _make_car(center + Vector3(0, -0.5, 8.0), 60.0)
	var car3 := _make_car(center + Vector3(0, -0.5, 30.0), 100.0)
	var blasts := [0]
	var chain := func(car: Node3D) -> void:
		blasts[0] += 1
		_cs.explode(car.global_position, 6.0, 160.0, null, {"fx": false})
	car1.on_destroy = chain
	car2.on_destroy = chain
	car3.on_destroy = chain
	await K.frames(get_tree(), 5)
	_explosions.clear()
	_cs.explode(K.ORIGIN + center, 5.0, 200.0, null, {"fx": false})
	K.check("explosion_chain_reaction", car1.is_destroyed and car2.is_destroyed and not car3.is_destroyed and blasts[0] == 2 and _explosions.size() == 3,
		"c1=%s c2=%s c3=%s blasts=%d events=%d" % [car1.is_destroyed, car2.is_destroyed, car3.is_destroyed, blasts[0], _explosions.size()])
	car1.queue_free()
	car2.queue_free()
	car3.queue_free()
	await K.frames(get_tree(), 2)


func _shooter_with(weapon: StringName, ammo: int) -> WeaponTestKit.Dummy:
	var shooter := K.make_shooter(_arena, Vector3(0, 0, 0))
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(weapon, ammo, true)
	await K.frames(get_tree(), 60)
	return shooter


func _t_rocket() -> void:
	var shooter := await _shooter_with(&"rocket_launcher", 3)
	var wc: WeaponController = shooter.weapons
	var target := _hp_dummy(Vector3(2.0, 0, -40))
	await K.frames(get_tree(), 3)
	_explosions.clear()
	wc.auto_reload = false
	wc.set_aim_ray(shooter.get_eye_position(), (target.global_position + Vector3(0, 1.0, 0) - shooter.get_eye_position()).normalized())
	var ok_fire := wc.fire_once()
	K.check("rocket_fired", ok_fire and wc.get_ammo_in_mag() == 0, "mag=%d" % wc.get_ammo_in_mag())
	await K.frames(get_tree(), 80)
	var lost := 5000.0 - target.health
	var ex_pos: Vector3 = _explosions[0][0] if _explosions.size() > 0 else Vector3.ZERO
	K.check("rocket_explodes_on_target", _explosions.size() == 1 and lost > 300.0 and ex_pos.distance_to(target.global_position) < 3.0,
		"explosions=%d lost=%.0f pos=%s" % [_explosions.size(), lost, str(ex_pos - K.ORIGIN)])
	# reload one rocket
	wc.start_reload()
	await K.frames(get_tree(), 240)
	K.check("rocket_reload", wc.get_ammo_in_mag() == 1 and wc.get_ammo_reserve() == 1, "mag=%d res=%d" % [wc.get_ammo_in_mag(), wc.get_ammo_reserve()])
	# rocket into the ground at distance (timeout / world hit)
	_explosions.clear()
	wc.set_aim_ray(shooter.get_eye_position(), Vector3(0, -0.3, -1).normalized())
	await K.frames(get_tree(), 40)
	wc.fire_once()
	await K.frames(get_tree(), 100)
	K.check("rocket_world_hit", _explosions.size() == 1, "n=%d" % _explosions.size())
	shooter.queue_free()
	target.queue_free()
	await K.frames(get_tree(), 2)


func _t_grenade() -> void:
	var shooter := await _shooter_with(&"fists", 0)
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(&"grenade", 4)
	K.check("grenade_given", wc.inventory[&"grenade"]["mag"] == 1 and wc.inventory[&"grenade"]["reserve"] == 3, "mag=%d res=%d" % [wc.inventory[&"grenade"]["mag"], wc.inventory[&"grenade"]["reserve"]])
	wc.equip(&"grenade")
	await K.frames(get_tree(), 30)
	var target_pos := K.ORIGIN + Vector3(0, 0, -14)
	var victim := _hp_dummy(Vector3(0, 0, -14))
	await K.frames(get_tree(), 3)
	var thrown := [null]
	wc.grenade_thrown.connect(func(g): thrown[0] = g)
	_explosions.clear()
	wc.set_aim_ray(shooter.get_eye_position(), (target_pos + Vector3(0, 0.5, 0) - shooter.get_eye_position()).normalized())
	var t0 := Time.get_ticks_msec()
	wc.throw_grenade()
	await K.frames(get_tree(), 20)
	K.check("grenade_thrown_signal", thrown[0] != null and is_instance_valid(thrown[0]) and _explosions.is_empty(), "")
	await K.frames(get_tree(), 200)   # fuse 3 s
	K.check("grenade_explodes_near_target", _explosions.size() == 1 and (_explosions[0][0] as Vector3).distance_to(target_pos) < 7.0 and victim.health < 5000.0,
		"n=%d pos=%s lost=%.0f" % [_explosions.size(), str(((_explosions[0][0] as Vector3) - K.ORIGIN) if _explosions.size() > 0 else Vector3.ZERO), 5000.0 - victim.health])
	K.check("grenade_ammo_consumed", wc.get_ammo_in_mag() + wc.get_ammo_reserve() == 3, "total=%d" % (wc.get_ammo_in_mag() + wc.get_ammo_reserve()))
	wc.equip(&"fists")
	# cooking shortens the fuse
	await K.frames(get_tree(), 40)
	_explosions.clear()
	victim.health = 5000.0
	wc.set_aim_ray(shooter.get_eye_position(), (target_pos + Vector3(0, 0.5, 0) - shooter.get_eye_position()).normalized())
	var began := wc.begin_grenade_cook()
	await K.frames(get_tree(), 90)    # cook 1.5 s
	wc.release_grenade()
	var release_ms := Time.get_ticks_msec()
	var frames_to_boom := 0
	while _explosions.is_empty() and frames_to_boom < 400:
		await get_tree().physics_frame
		frames_to_boom += 1
	K.check("grenade_cook_shortens_fuse", began and frames_to_boom < 150 and frames_to_boom > 40, "frames=%d (fuse left ~1.5s + windup)" % frames_to_boom)
	# trajectory preview
	var arc := wc.get_throw_preview()
	K.check("grenade_preview_arc", arc.size() > 5, "pts=%d" % arc.size())
	shooter.queue_free()
	victim.queue_free()
	await K.frames(get_tree(), 2)


func _t_launcher() -> void:
	var shooter := await _shooter_with(&"grenade_launcher", 12)
	var wc: WeaponController = shooter.weapons
	var target := _hp_dummy(Vector3(1.0, 0, -22))
	await K.frames(get_tree(), 3)
	_explosions.clear()
	wc.auto_reload = false
	wc.set_aim_ray(shooter.get_eye_position(), (target.global_position + Vector3(0, 1.0, 0) - shooter.get_eye_position()).normalized() + Vector3(0, 0.12, 0))
	wc.fire_once()
	await K.frames(get_tree(), 240)
	K.check("grenade_launcher_explodes", _explosions.size() == 1 and wc.get_ammo_in_mag() == 3, "n=%d mag=%d" % [_explosions.size(), wc.get_ammo_in_mag()])
	shooter.queue_free()
	target.queue_free()
	await K.frames(get_tree(), 2)
