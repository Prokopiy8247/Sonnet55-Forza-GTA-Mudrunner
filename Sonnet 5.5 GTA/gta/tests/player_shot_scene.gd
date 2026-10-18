extends Node
## Scenario setup for Player screenshots. Use with the harness:
##   tools\gd.ps1 shot -Out screenshots\p.png -GameArgs "--exec=res://gta/tests/player_shot_scene.gd --scene=aim --delay=4 --time=11"
## Scenes: stand run sprint crouch aim aim_rifle fp cover swim dive vehicle death side_run side_sprint side_aim side_crouch side_swim
## "side_*" scenes view the player from a free camera at the given distance (default 3.2 m) to inspect the rig.

var player: Player
var cam_args := {}


func _arg(key: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
	return default_value


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _side_cam(dist: float = 3.2, angle_deg: float = 55.0, height: float = 1.1, target_h: float = 0.95) -> Camera3D:
	var c := Camera3D.new()
	c.fov = 45.0
	c.near = 0.05
	add_child(c)
	var yaw := player.rotation.y + deg_to_rad(angle_deg)
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var tgt := player.global_position + Vector3(0, target_h, 0)
	c.global_position = tgt + dir * dist + Vector3(0, height - target_h, 0)
	c.look_at(tgt, Vector3.UP)
	c.make_current()
	return c


func run(_main: Node) -> Variant:
	player = Game.player as Player
	var scene := _arg("scene", "stand")
	var yaw_deg := float(_arg("yaw", "0"))
	var dist := float(_arg("dist", "3.2"))
	var ang := float(_arg("ang", "55"))
	player.use_real_input = false
	player.move_yaw_override = deg_to_rad(yaw_deg)
	player.rotation.y = deg_to_rad(yaw_deg)
	if is_instance_valid(player.camera):
		player.camera.snap_behind(deg_to_rad(yaw_deg))
	await _frames(20)
	var side := scene.begins_with("side_")
	var base := scene.trim_prefix("side_")
	match base:
		"stand":
			pass
		"run":
			player.set_input(Vector2(0, 1))
			await _frames(70)
		"sprint":
			player.set_input(Vector2(0, 1), true)
			await _frames(80)
		"crouch":
			player.press_crouch()
			await _frames(40)
			player.set_input(Vector2(0, 1))
			await _frames(40)
		"aim":
			player.set_input(Vector2(0, 0), false, true)
			await _frames(60)
		"aim_rifle":
			if player.weapons != null:
				player.weapons.give_weapon(&"rifle_assault", 90)
				player.weapons.equip(&"rifle_assault")
			await _frames(40)
			player.set_input(Vector2(0, 0), false, true)
			await _frames(60)
		"fp":
			player.camera.first_person = true
			if player.weapons != null:
				player.weapons.give_weapon(&"pistol", 60)
				player.weapons.equip(&"pistol")
			await _frames(70)
		"cover", "cover_low":
			var low := base == "cover_low"
			var b := StaticBody3D.new()
			b.collision_layer = GC.L_WORLD
			var c := CollisionShape3D.new()
			var s := BoxShape3D.new()
			s.size = Vector3(5, 1.0 if low else 3.0, 0.4)
			c.shape = s
			b.add_child(c)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = s.size
			mi.mesh = bm
			b.add_child(mi)
			add_child(b)
			var fwd := Util.yaw_to_dir(player.rotation.y)
			b.global_position = player.global_position + fwd * 1.5 + Vector3(0, s.size.y * 0.5, 0)
			b.rotation.y = player.rotation.y
			await _frames(5)
			player.cover.toggle()
			await _frames(40)
			if scene.ends_with("peek"):
				player.set_input(Vector2.ZERO, false, true)
				await _frames(40)
		"chute":
			player.has_parachute = true
			player.teleport_to(player.global_position + Vector3(0, 90, 0))
			await _frames(70)
			player.press_jump(false)
			await _frames(110)
		"swim", "dive":
			var sy: float = GC.WATER_LEVEL
			var p := Vector3(float(_arg("x", "0")), sy + 2.0, float(_arg("z", "215")))
			player.teleport_to(p, deg_to_rad(yaw_deg))
			await _frames(70)
			if base == "dive":
				player.cmd_crouch_held = true
				player.set_input(Vector2(0, 1))
				await _frames(60)
			else:
				player.set_input(Vector2(0, 1))
				await _frames(60)
		"vehicle":
			player.set_input(Vector2(0.0, 1.0))
			await _frames(150)
			player.set_input(Vector2(0.45, 1.0))
			await _frames(40)
		"drive_fp":
			player.camera.first_person = true
			player.set_input(Vector2(0.0, 1.0))
			await _frames(120)
		"death":
			player.apply_damage(500.0, {"source": null, "type": GC.DMG_BULLET, "zone": GC.ZONE_TORSO, "direction": Vector3(0, 0, -1), "impulse": 8.0})
			await _frames(int(float(_arg("wait", "90"))))
	if side:
		_side_cam(dist, ang)
		await _frames(4)
	print("HARNESS: SCENE %s ready: pos=%s vel=%s mode=%d stance=%s swim=%s uw=%s rigy=%.2f surf=%.2f" % [scene, str(player.global_position), str(player.velocity), player.move_mode, str(player.stance), str(player.is_swimming), str(player.is_underwater), player.rig.position.y, player.water_surface_y])
	return true
