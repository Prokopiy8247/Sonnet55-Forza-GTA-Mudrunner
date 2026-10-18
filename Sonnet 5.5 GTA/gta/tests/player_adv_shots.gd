extends Node
## Scenario setup for the advanced player screenshots (real renderer):
##   tools\gd.ps1 shot -Out screenshots\adv\x.png -GameArgs "--exec=res://gta/tests/player_adv_shots.gd --scene=cover_low --delay=4 --time=11 --no-peds --no-traffic"
## Scenes: stealth cover_low cover_high cover_corner cover_aim takedown takedown_knife fp_rifle fp_pistol_ads fp_car chute chute_pack scuba melee_block dodge roll_aim passenger driveby
## Options: --side (free camera beside the player), --dist, --ang, --height, --wait=<frames>

var player: Player
var _extra: Array = []


class ShotNpc extends CharacterBase:
	var rig_node: Node3D
	func _ready() -> void:
		super._ready()
		add_to_group(GC.G_NPC)
		collision_layer = GC.L_NPC
		collision_mask = GC.L_WORLD
		var c := CollisionShape3D.new()
		var s := CapsuleShape3D.new()
		s.radius = 0.35
		s.height = 1.8
		c.shape = s
		c.position = Vector3(0, 0.9, 0)
		add_child(c)
		var r := CharacterRig.new()
		add_child(r)
		r.setup(CharacterVariants.random_pedestrian(null))
		rig = r
	func knock_down(_impulse: Vector3, _duration: float = 2.2) -> void:
		if rig != null:
			rig.start_ragdoll(_impulse * 3.0, global_position + Vector3.UP)
	func _on_death(info: Dictionary) -> void:
		if rig != null:
			rig.start_ragdoll(Vector3(info.get("direction", Vector3.FORWARD)) * 3.0, global_position + Vector3.UP)


func _arg(key: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
		if s == "--" + key:
			return "true"
	return default_value


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _side_cam(dist: float, angle_deg: float, height: float, target_h: float = 1.0, fov: float = 45.0) -> Camera3D:
	var c := Camera3D.new()
	c.fov = fov
	c.near = 0.05
	add_child(c)
	var yaw := player.rotation.y + deg_to_rad(angle_deg)
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var tgt := player.global_position + Vector3(0, target_h, 0)
	c.global_position = tgt + dir * dist + Vector3(0, height - target_h, 0)
	c.look_at(tgt, Vector3.UP)
	c.make_current()
	return c


func _solid(model: String, pos: Vector3, yaw: float, size: Vector3, fallback_color: Color = Color(0.5, 0.5, 0.55)) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = GC.L_WORLD
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	c.position = Vector3(0, size.y * 0.5, 0)
	b.add_child(c)
	var inst: Node3D = ModelLib.instance(model) if model != "" else null
	if inst != null:
		b.add_child(inst)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = Vector3(0, size.y * 0.5, 0)
		var m := StandardMaterial3D.new()
		m.albedo_color = fallback_color
		mi.material_override = m
		b.add_child(mi)
	add_child(b)
	b.global_position = pos
	b.rotation.y = yaw
	_extra.append(b)
	return b


func _npc(pos: Vector3, yaw: float) -> ShotNpc:
	var n := ShotNpc.new()
	add_child(n)
	n.global_position = pos
	n.rotation.y = yaw
	_extra.append(n)
	return n


func run(_main: Node) -> Variant:
	player = Game.player as Player
	var scene := _arg("scene", "stealth")
	var yaw_deg := float(_arg("yaw", "0"))
	player.use_real_input = false
	player.move_yaw_override = deg_to_rad(yaw_deg)
	player.rotation.y = deg_to_rad(yaw_deg)
	if is_instance_valid(player.camera):
		player.camera.snap_behind(deg_to_rad(yaw_deg))
	await _frames(20)
	var fwd := Util.yaw_to_dir(player.rotation.y)
	var right := Vector3(cos(player.rotation.y), 0.0, -sin(player.rotation.y))
	var p0 := player.global_position
	var wait := int(_arg("wait", "0"))
	match scene:
		"stealth":
			player.weapons.give_weapon(&"pistol", 60)
			player.weapons.equip(&"pistol")
			player.press_crouch()
			await _frames(30)
			player.set_input(Vector2(0, 1))
			await _frames(50)
		"cover_low":
			_solid("props/concrete_barrier", p0 + fwd * 1.5, player.rotation.y, Vector3(3.0, 0.9, 0.5))
			_solid("props/concrete_barrier", p0 + fwd * 1.5 + right * 3.0, player.rotation.y, Vector3(3.0, 0.9, 0.5))
			await _frames(6)
			player.cover.toggle()
			await _frames(40)
		"cover_high":
			_solid("props/container", p0 + fwd * 2.2, player.rotation.y, Vector3(2.6, 2.6, 6.0))
			await _frames(6)
			player.cover.toggle()
			await _frames(40)
		"cover_aim":
			player.weapons.give_weapon(&"rifle_assault", 90)
			player.weapons.equip(&"rifle_assault")
			_solid("props/concrete_barrier", p0 + fwd * 1.5, player.rotation.y, Vector3(3.0, 0.9, 0.5))
			await _frames(20)
			player.cover.toggle()
			await _frames(30)
			player.cmd_aim = true
			await _frames(40)
		"cover_corner":
			_solid("", p0 + fwd * 1.5 + Vector3(0, 0, 0), player.rotation.y, Vector3(6.0, 3.0, 0.4), Color(0.72, 0.68, 0.6))
			_solid("", p0 + fwd * 4.5 + right * 3.0, player.rotation.y, Vector3(0.4, 3.0, 6.4), Color(0.72, 0.68, 0.6))
			await _frames(6)
			player.cover.toggle()
			await _frames(30)
			player.set_input(Vector2(1, 0))
			await _frames(int(_arg("slide", "55")))
		"takedown", "takedown_knife":
			var knife := scene == "takedown_knife"
			if knife:
				player.weapons.give_weapon(&"knife", 1)
				player.weapons.equip(&"knife")
			else:
				player.weapons.equip(&"fists")
			var n := _npc(p0 + fwd * 3.0, player.rotation.y)
			player.press_crouch()
			await _frames(30)
			player.set_input(Vector2(0, 1))
			await _frames(int(_arg("approach", "50")))
			player.melee(false)
			await _frames(int(_arg("tdwait", "22")))
			_extra.append(n)
		"fp_rifle", "fp_pistol_ads":
			var wid := &"rifle_assault" if scene == "fp_rifle" else &"pistol"
			player.weapons.give_weapon(wid, 90)
			player.weapons.equip(wid)
			player.camera.first_person = true
			await _frames(40)
			if _arg("ads", "0") == "1" or scene == "fp_pistol_ads":
				player.cmd_aim = true
				player.use_real_input = false
				await _frames(40)
		"fp_car":
			player.camera.first_person = true
			var v = VehicleFactory.spawn(&"sports", Transform3D(player.global_transform.basis, p0 + fwd * 4.0 + Vector3(0, 1.0, 0)), {})
			await _frames(30)
			if v != null:
				player.enter_vehicle(v, 0)
			await _frames(80)
			player.set_input(Vector2(0, 1))
			await _frames(60)
		"chute", "chute_pack":
			player.has_parachute = true
			if scene == "chute_pack":
				await _frames(30)
			else:
				var site: Dictionary = WorldLayout.get_location(&"parachute_peak")
				if not site.is_empty():
					player.teleport_to((site["pos"] as Vector3) + Vector3(0, 0.3, 0), player.rotation.y)
				else:
					player.teleport_to(p0 + Vector3(0, 90, 0))
				await _frames(40)
				player.press_jump(true)
				player.set_input(Vector2(0, 1))
				await _frames(70)
				player.press_jump(false)
				await _frames(120)
		"scuba":
			player.has_scuba = true
			var dx := float(_arg("x", "0"))
			var dz := float(_arg("z", "215"))
			player.teleport_to(Vector3(dx, GC.WATER_LEVEL + 2.0, dz), player.rotation.y)
			await _frames(70)
			player.cmd_crouch_held = true
			player.set_input(Vector2(0, 1))
			await _frames(80)
		"melee_block":
			var n2 := _npc(p0 + fwd * 1.8, player.rotation.y + PI)
			player.weapons.equip(&"fists")
			player.cmd_aim = true
			await _frames(40)
			_extra.append(n2)
		"dodge", "roll_aim":
			player.weapons.give_weapon(&"pistol", 60)
			player.weapons.equip(&"pistol")
			player.cmd_aim = true
			await _frames(30)
			if player.has_method("dodge"):
				player.dodge(right)
			await _frames(int(_arg("rollwait", "18")))
		"passenger", "driveby":
			var v2 = VehicleFactory.spawn(&"sedan", Transform3D(player.global_transform.basis, p0 + fwd * 4.0 + Vector3(0, 1.0, 0)), {})
			await _frames(40)
			if v2 != null:
				if scene == "passenger" and player.has_method("enter_as_passenger"):
					player.enter_as_passenger(v2, 1)
				else:
					player.enter_vehicle(v2, 0)
			await _frames(60)
			if scene == "driveby":
				player.weapons.give_weapon(&"smg", 120)
				player.weapons.equip(&"smg")
				player.cmd_aim = true
				await _frames(50)
	if wait > 0:
		await _frames(wait)
	if _arg("side", "0") != "0":
		_side_cam(float(_arg("dist", "3.2")), float(_arg("ang", "55")), float(_arg("height", "1.3")), float(_arg("th", "1.0")))
		await _frames(4)
	print("HARNESS: SCENE %s ready: pos=%s mode=%d stance=%s cover=%s" % [scene, str(player.global_position), player.move_mode, str(player.stance), str(player.cover.active if player.cover != null else false)])
	return true
