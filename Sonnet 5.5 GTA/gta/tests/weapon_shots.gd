extends Node
## Visual QA scenes for the weapon / FX work. Run with the real renderer:
##   powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\w_gallery.png -GameArgs "--exec=res://gta/tests/weapon_shots.gd --wshot=gallery --cam=4000,1.3,4006,4000,0.8,4000 --time=12 --delay=3"
## --wshot = gallery | mods | flash | impacts | explosion | rocket | pickups | night_flash
## Optional: --wwait=<seconds> keeps the scene running before the screenshot is taken (explosion timing).

const K = preload("res://gta/tests/weapon_test_kit.gd")

var _arena: Node3D = null


func _arg(key: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
	return default


func run(main: Node) -> String:
	await get_tree().process_frame
	var mode := _arg("wshot", "gallery")
	_arena = K.make_arena(main)
	_add_visual_floor()
	await K.frames(get_tree(), 3)
	match mode:
		"gallery":
			_gallery(false)
		"mods":
			_gallery(true)
		"flash":
			await _flash(false)
		"night_flash":
			await _flash(true)
		"impacts":
			await _impacts()
		"explosion":
			await _explosion()
		"rocket":
			await _rocket()
		"pickups":
			_pickups()
		"player":
			await _player()
	var wait := float(_arg("wwait", "0"))
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	return mode


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _add_visual_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	mi.mesh = pm
	mi.material_override = _mat(Color(0.55, 0.53, 0.5))
	_arena.add_child(mi)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 6, 0.4)
	back.mesh = bm
	back.material_override = _mat(Color(0.75, 0.72, 0.66))
	back.position = Vector3(0, 3, -12)
	_arena.add_child(back)


func _gallery(with_mods: bool) -> void:
	var ids := [&"knife", &"bat", &"crowbar", &"pistol", &"revolver", &"smg", &"shotgun_pump", &"shotgun_auto",
		&"rifle_assault", &"carbine", &"rifle_marksman", &"sniper", &"grenade", &"rocket_launcher", &"grenade_launcher"]
	var cols := 4
	for i in ids.size():
		var id: StringName = ids[i]
		var mods := {}
		if with_mods:
			for m in WeaponMods.compatible_mods(id):
				mods[m] = true
		var wm := WeaponModel.create(id, mods, Color(0, 0, 0, 0))
		_arena.add_child(wm)
		var row := i / cols
		var col := i % cols
		wm.position = Vector3(-3.2 + col * 2.2, 1.5 - row * 0.62, -2.0)
		wm.rotation_degrees = Vector3(0, -90, 0)
		wm.scale = Vector3.ONE * 1.0
		wm.set_flashlight(with_mods)
		var lbl := Label3D.new()
		lbl.text = String(id) + ("*" if wm.is_fallback else "")
		lbl.font_size = 22
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.1, 0.1, 0.1)
		lbl.position = wm.position + Vector3(0, -0.22, 0)
		_arena.add_child(lbl)


func _shooter_visual(shooter: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.32
	cm.height = 1.8
	mi.mesh = cm
	mi.material_override = _mat(Color(0.2, 0.35, 0.5))
	mi.position = Vector3(0, 0.9, 0)
	shooter.add_child(mi)


func _flash(night: bool) -> void:
	var shooter := K.make_shooter(_arena, Vector3(0, 0, 0))
	_shooter_visual(shooter)
	var wc: WeaponController = shooter.weapons
	var id := StringName(_arg("wweapon", "rifle_assault"))
	wc.give_weapon(id, 300, true)
	wc.auto_reload = false
	await K.frames(get_tree(), 50)
	wc.set_aiming(true)
	if WeaponDefs.get_def(id)["mode"] == &"auto":
		wc.set_trigger(true)
		for i in 60:
			K.aim(wc, shooter, Vector3(0, 0, -1))
			await get_tree().physics_frame
	else:
		var shots := 0
		for i in 400:
			K.aim(wc, shooter, Vector3(0, 0, -1))
			if wc.fire_once():
				shots += 1
				await get_tree().physics_frame
				if shots >= 3:
					break
			await get_tree().physics_frame
	# the capture happens a frame or two later: the flash is still visible


func _impacts() -> void:
	var shooter := K.make_shooter(_arena, Vector3(0, 0, 6))
	_shooter_visual(shooter)
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(&"rifle_assault", 900, true)
	wc.auto_reload = false
	# surface panels
	var panels := [[-3.0, &"metal", Color(0.45, 0.5, 0.55)], [-1.0, &"concrete", Color(0.7, 0.68, 0.64)], [1.0, &"glass", Color(0.55, 0.8, 0.9)],
		[3.0, &"wood", Color(0.5, 0.35, 0.2)]]
	for p in panels:
		var wall := K.make_wall(_arena, Vector3(p[0], 1.5, -8), Vector3(1.8, 2.6, 0.2), p[1])
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 2.6, 0.2)
		mi.mesh = bm
		var m := _mat(p[2], 0.4 if p[1] == &"metal" else 0.8)
		if p[1] == &"glass":
			m.albedo_color.a = 0.4
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		wall.add_child(mi)
	await K.frames(get_tree(), 50)
	wc.set_aiming(true)
	for p in panels:
		var target := K.ORIGIN + Vector3(p[0], 1.5, -8)
		for k in 7:
			var t := target + Vector3(randf_range(-0.6, 0.6), randf_range(-0.7, 0.7), 0.1)
			wc.set_aim_ray(shooter.get_eye_position(), (t - shooter.get_eye_position()).normalized())
			wc.fire_once()
			await K.frames(get_tree(), 6)
	# last burst right before the capture
	var focus := String(_arg("wfocus", "-3,-1,1")).split(",")
	for k in focus.size():
		var tgt := K.ORIGIN + Vector3(float(focus[k]) + randf_range(-0.4, 0.4), 1.5 + randf_range(-0.5, 0.5), -8)
		wc.set_aim_ray(shooter.get_eye_position(), (tgt - shooter.get_eye_position()).normalized())
		wc.fire_once()
		await K.frames(get_tree(), 4)


func _explosion() -> void:
	var cs := CombatSystem.get_instance()
	for i in 3:
		var d := K.make_dummy(_arena, Vector3(-4 + i * 4, 0, -2 - i))
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.32
		cm.height = 1.8
		mi.mesh = cm
		mi.material_override = _mat(Color(0.3, 0.45, 0.3))
		mi.position = Vector3(0, 0.9, 0)
		d.add_child(mi)
		d.max_health = 5000.0
		d.health = 5000.0
	await K.frames(get_tree(), 20)
	cs.explode(K.ORIGIN + Vector3(0, 0.3, -4), 7.5, 230.0, null, {"weapon": &"grenade"})


func _rocket() -> void:
	var shooter := K.make_shooter(_arena, Vector3(0, 0, 8))
	_shooter_visual(shooter)
	var wc: WeaponController = shooter.weapons
	wc.give_weapon(&"rocket_launcher", 5, true)
	await K.frames(get_tree(), 60)
	wc.set_aim_ray(shooter.get_eye_position(), Vector3(0.0, 0.02, -1.0).normalized())
	wc.fire_once()
	var wait_frames := int(float(_arg("wframes", "20")))
	await K.frames(get_tree(), wait_frames)


func _pickups() -> void:
	var cs := CombatSystem.get_instance()
	var kinds := [[&"health", 50, &""], [&"armor", 50, &""], [&"cash", 100, &""], [&"ammo", 30, &""], [&"weapon", 30, &"pistol"],
		[&"weapon", 30, &"smg"], [&"weapon", 15, &"rifle_assault"], [&"weapon", 4, &"rocket_launcher"], [&"weapon", 5, &"shotgun_pump"],
		[&"weapon", 5, &"sniper"]]
	for i in kinds.size():
		var k: Array = kinds[i]
		var opts := {"snap": false}
		if k[2] != &"":
			opts["weapon"] = k[2]
		var p := cs.spawn_pickup(k[0], K.ORIGIN + Vector3(-5.0 + i * 1.1, 0.0, -3.0), k[1], opts)
		p.monitoring = false
	await K.frames(get_tree(), 40)


func _player() -> void:
	var p = Game.player
	if p == null:
		return
	p.teleport_to(K.ORIGIN + Vector3(0, 0.2, 0), PI)
	await K.frames(get_tree(), 40)
	var w: WeaponController = p.weapons
	var id := StringName(_arg("wweapon", "rifle_assault"))
	w.give_weapon(id, 300, true)
	await K.frames(get_tree(), 50)
	if _arg("waim", "1") == "1":
		p.use_real_input = false
		p.cmd_aim = true
		p.cmd_fire = _arg("wfire", "0") == "1"
	await K.frames(get_tree(), 30)
	for i in 30:
		w.set_aim_ray(p.global_position + Vector3(0, 1.4, 0), -p.global_transform.basis.z)
		await get_tree().physics_frame
