extends Node
## Integration with the real Player: weapon wiring, camera recoil / FOV override, hit markers, HUD-facing properties,
## real vehicle hit zones.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/weapon_player_test.gd -Seconds 60

const K = preload("res://gta/tests/weapon_test_kit.gd")


func run(main: Node) -> String:
	await get_tree().process_frame
	var p = Game.player
	if p == null or not is_instance_valid(p):
		K.check("player_present", false, "Game.player is null")
		return "no player"
	var arena := K.make_arena(main)
	await K.frames(get_tree(), 3)
	p.teleport_to(K.ORIGIN + Vector3(0, 0.3, 0), 0.0)
	await K.frames(get_tree(), 40)
	var w: WeaponController = p.weapons
	K.check("player_has_controller", w != null and w.character == p, "")
	K.check("player_always_tick", w.is_physics_processing(), "")
	w.auto_reload = false
	w.give_weapon(&"rifle_assault", 300, true)
	await K.frames(get_tree(), 50)
	var cam = Game.gameplay_camera
	var fwd: Vector3 = cam.get_aim_forward()
	var chest: Vector3 = p.global_position + Vector3(0, 1.3, 0)
	var target := K.make_dummy(arena, Vector3.ZERO)
	target.max_health = 100000.0
	target.health = 100000.0
	var t_hit := clampf((cam.global_position.y - K.ORIGIN.y - 1.0) / maxf(-fwd.y, 0.02), 4.0, 25.0) if fwd.y < -0.02 else 12.0
	target.global_position = cam.global_position + fwd * t_hit - Vector3(0, 1.0, 0)
	await K.frames(get_tree(), 4)
	# look straight at the dummy chest (the camera follows the player's input; here we only verify the wiring)
	var markers := [0, 0]
	Events.hit_marker.connect(func(kill): markers[0] += 1; markers[1] += 1 if kill else 0)
	var ammo_events := [0]
	Events.ammo_changed.connect(func(c, _id, _m, _r): ammo_events[0] += 1 if c == p else 0)
	var kick_peak := 0.0
	var cam_fov0: float = cam.fov
	w.set_trigger(true)
	for i in 40:
		await get_tree().physics_frame
		if cam.get("_kick_pitch") != null:
			kick_peak = maxf(kick_peak, float(cam.get("_kick_pitch")))
	w.set_trigger(false)
	var lost := 100000.0 - target.health
	K.check("player_shots_hit_target", lost > 20.0 and markers[0] >= 1, "lost=%.0f markers=%d" % [lost, markers[0]])
	K.check("player_camera_recoil", kick_peak > 0.005, "kick_peak=%.4f" % kick_peak)
	K.check("player_ammo_events", ammo_events[0] >= 5, "events=%d" % ammo_events[0])
	# aimed sniper: scope overlay flag + camera FOV override, released afterwards
	w.give_weapon(&"sniper", 30, true)
	await K.frames(get_tree(), 60)
	w.set_aiming(true)
	await K.frames(get_tree(), 50)
	K.check("player_scope_fov_override", w.scope_active and float(cam.fov_override) > 0.0 and float(cam.fov_override) < 25.0 and float(cam.fov) < cam_fov0,
		"scope=%s override=%.1f fov=%.1f" % [w.scope_active, float(cam.fov_override), float(cam.fov)])
	w.set_aiming(false)
	await K.frames(get_tree(), 60)
	K.check("player_scope_released", not w.scope_active and float(cam.fov_override) < 0.0, "override=%.1f" % float(cam.fov_override))
	# HUD facing properties
	K.check("hud_properties", w.get("current_spread") != null and w.get("reload_progress") != null and w.get("is_reloading") != null
		and w.get("scope_active") != null and w.has_method("get_ammo_in_mag") and w.has_method("get_current_def"), "")
	# melee through the player
	w.equip(&"fists")
	await K.frames(get_tree(), 20)
	var v := K.make_dummy(arena, Vector3.ZERO)
	v.max_health = 1000.0
	v.health = 1000.0
	var pfwd: Vector3 = -p.global_transform.basis.z
	v.global_position = p.global_position + Vector3(pfwd.x, 0, pfwd.z).normalized() * 1.2
	await K.frames(get_tree(), 4)
	p.melee(false)
	await K.frames(get_tree(), 40)
	K.check("player_melee", v.health < 1000.0, "hp=%.0f" % v.health)
	v.queue_free()
	target.queue_free()
	await K.frames(get_tree(), 3)
	# real vehicle: zones + damage through the contract
	var veh = VehicleFactory.spawn(&"sedan", Transform3D(Basis.IDENTITY, K.ORIGIN + Vector3(0, 1.0, -30)), {})
	if veh != null:
		await K.frames(get_tree(), 60)
		var vp: Vector3 = veh.global_position
		var space := arena.get_world_3d().direct_space_state
		var hp0: float = veh.health
		var from := K.ORIGIN + Vector3(0, 1.5, 0)
		var res := Ballistics.shoot(space, from, (vp + Vector3(0, 0.5, 0) - from).normalized(), {"shooter": p, "weapon": &"pistol", "damage": 30.0, "range": 100.0,
			"falloff_start": 50.0, "falloff_min": 1.0, "penetration": 0, "impulse": 0.0, "exclude": [p.get_rid()], "spawn_fx": true})
		K.check("vehicle_hit_zone", res["hit"] and res["target"] == veh and veh.health < hp0, "zone=%s hp %.0f->%.0f" % [res["zone"], hp0, veh.health])
		veh.queue_free()
	else:
		K.check("vehicle_hit_zone", false, "VehicleFactory.spawn returned null")
	K.summary()
	arena.queue_free()
	return "passed=%d failed=%d" % [K.passed, K.failed]
