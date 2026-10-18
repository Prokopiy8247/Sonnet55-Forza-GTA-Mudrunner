extends Node
## Systems-A screenshot scenes (use with tools\gd.ps1 shot):
##   tools\gd.ps1 shot -Out screenshots\sysa\x.png -GameArgs "--exec=res://gta/tests/interactions_shot.gd --scene=ladder --n=0 --time=11 --no-traffic --no-peds --delay=4"
## scenes: pickup (--id=<spot id>), pickups_row, ladder (--n), ladder_top (--n), roof (--n), elevator_ground, elevator_roof, booth (--n), bench (--n),
##         hydrant, crate, parachute, scuba, tower_roof
## --dist --ang --h tune the camera.

var scene := ""
var args: Dictionary = {}
var cam: Camera3D = null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _arg(key: String, default: String = "") -> String:
	return String(args.get(key, default))


func _look(pos: Vector3, target: Vector3, fov: float = 62.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.name = "ShotCam"
		get_tree().root.add_child(cam)
	cam.fov = fov
	cam.far = 1500.0
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.make_current()


func _orbit(target: Vector3, dist: float, ang_deg: float, h: float, fov: float = 62.0) -> void:
	var a := deg_to_rad(ang_deg)
	_look(target + Vector3(sin(a) * dist, h, cos(a) * dist), target + Vector3(0, h * 0.3, 0), fov)


func run(_main: Node) -> Variant:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			args[s] = "true"
	scene = _arg("scene", "pickup")
	await _frames(60)
	var im = Game.sys(&"interactions")
	var eco = Game.sys(&"economy")
	var player: Node = Game.player
	var dist := float(_arg("dist", "0"))
	var ang := float(_arg("ang", "35"))
	var h := float(_arg("h", "0"))
	var n := int(_arg("n", "0"))
	match scene:
		"pickup":
			var s: Dictionary = eco.get_spot(_arg("id", "cash_beach_b"))
			var p: Vector3 = s["pos"]
			player.teleport_to(p + Vector3(3.2, 0.2, 2.0), deg_to_rad(150))
			await _frames(40)
			_orbit(p, dist if dist > 0.0 else 3.6, ang, h if h > 0.0 else 1.6, 55.0)
		"pickups_row":
			# every pickup kind side by side on a flat spot near the plaza
			var base: Vector3 = WorldLayout.location_pos(&"player_spawn") + Vector3(-6, 0, -8)
			var kinds := [&"cash", &"health", &"armor", &"ammo", &"weapon_crate", &"parachute", &"scuba", &"weapon"]
			for i in kinds.size():
				var spot := {"id": "demo_%d" % i, "kind": kinds[i], "amount": 100, "weapon": &"smg", "respawn": 0.0, "group": "demo"}
				var pk := PickupPlacer.create(spot)
				eco.pickups_root.add_child(pk)
				pk.global_position = base + Vector3(float(i) * 1.7, 0.0, 0.0)
				eco.get_pickups().append(pk)
			player.teleport_to(base + Vector3(14.0, 0.2, 6.0), deg_to_rad(90))
			await _frames(40)
			_look(base + Vector3(6.0, 2.2, 5.4), base + Vector3(6.0, 0.8, 0.0), 58.0)
		"ladder", "ladder_top", "roof":
			var rec: Dictionary = im.ladders[n]
			var nrm: Vector3 = rec["normal"]
			var bottom: Vector3 = rec["bottom"]
			var roof_y: float = rec["roof_y"]
			if scene == "ladder":
				player.teleport_to(bottom + nrm * 1.0 + Vector3(0, 0.2, 0), Util.dir_to_yaw(-nrm))
				await _frames(30)
				var pt: InteractionPoint = null
				for q in im.points:
					if q.kind == &"ladder_up" and int(q.data["ladder"]) == n:
						pt = q
				pt.interact(player)
				player.set_input(Vector2(0, 1), false)
				var t := 0.0
				while player.global_position.y < bottom.y + (roof_y - bottom.y) * float(_arg("u", "0.45")) and t < 20.0:
					await get_tree().physics_frame
					t += 1.0 / 60.0
				player.set_input(Vector2.ZERO)
				var side := Vector3(-nrm.z, 0, nrm.x)
				var mid := bottom.lerp(rec["top"], 0.5)
				_look(mid + nrm * (dist if dist > 0.0 else 9.0) + side * 4.5 + Vector3(0, 2.0 + h, 0), mid, 58.0)
			elif scene == "ladder_top":
				var top: Vector3 = rec["top"]
				player.teleport_to(top - nrm * 2.2 + Vector3(0, 0.2, 0), Util.dir_to_yaw(nrm))
				await _frames(40)
				var side2 := Vector3(-nrm.z, 0, nrm.x)
				_look(top + nrm * (dist if dist > 0.0 else 4.5) + side2 * 3.0 + Vector3(0, 3.0, 0), top - nrm * 1.5, 60.0)
			else:
				var top2: Vector3 = rec["top"]
				var reward: Dictionary = rec.get("reward", {})
				player.teleport_to(top2 - nrm * 3.0 + Vector3(0, 0.2, 0), Util.dir_to_yaw(-nrm))
				await _frames(40)
				var rp: Vector3 = reward.get("pos", top2 - nrm * 5.0)
				_look(rp + Vector3(5.0, 3.0, 5.0), rp, 60.0)
		"elevator_ground":
			var g: Dictionary = im.elevator["ground"]
			var door: Dictionary = g["door"]
			player.teleport_to(g["stand"], float(g["yaw"]) + PI)
			await _frames(40)
			if _arg("open", "1") == "1":
				im._set_door(door, true, 0.1)
			var nrm2: Vector3 = g["normal"]
			_look((g["pos"] as Vector3) + nrm2 * (dist if dist > 0.0 else 5.5) + Vector3(-1.8, 1.9 + h, 0), (g["pos"] as Vector3) + Vector3(0, 1.4, 0), 60.0)
			await _frames(30)
		"elevator_roof":
			var r: Dictionary = im.elevator["roof"]
			player.teleport_to(r["stand"], float(r["yaw"]) + PI)
			await _frames(60)
			if _arg("open", "1") == "1":
				im._set_door(r["door"], true, 0.1)
			var nrm3: Vector3 = r["normal"]
			_look((r["pos"] as Vector3) + nrm3 * (dist if dist > 0.0 else 8.0) + Vector3(2.5, 2.4 + h, 0), (r["pos"] as Vector3) + Vector3(0, 1.4, 0), 62.0)
			await _frames(30)
		"booth":
			var b: Dictionary = im.booths[n]
			player.teleport_to(b["use_pos"] + Vector3(0, 0.2, 0), float(b["yaw"]) + PI)
			await _frames(40)
			_look((b["pos"] as Vector3) + Util.yaw_to_dir(float(b["yaw"])) * (dist if dist > 0.0 else 4.0) + Vector3(2.2, 1.7 + h, 0), (b["pos"] as Vector3) + Vector3(0, 1.1, 0), 58.0)
		"bench":
			var seats: Array = im.get_bench_seats()
			var s2: Dictionary = seats[n]
			var sp: Vector3 = s2["pos"]
			player.teleport_to(sp + Util.yaw_to_dir(float(s2["yaw"])) * 1.2 - Vector3(0, 0.45, 0), float(s2["yaw"]) + PI)
			await _frames(40)
			im._sit(player, n)
			await _frames(40)
			var fwd := Util.yaw_to_dir(float(s2["yaw"]))
			var side3 := Vector3(-fwd.z, 0, fwd.x)
			_look(sp + fwd * (dist if dist > 0.0 else 3.2) + side3 * 2.4 + Vector3(0, 1.3 + h, 0), sp + Vector3(0, 0.1, 0), 56.0)
		"hydrant":
			var hs: Array = im.get_hydrants()
			var hp: Vector3 = hs[n]
			player.teleport_to(hp + Vector3(5.0, 0.2, 5.0), deg_to_rad(-135))
			await _frames(30)
			im.spray_hydrant(n)
			await _frames(40)
			# camera on the side with the most free space (baked bus stops / walls would hide the jet)
			var best_pos := hp + Vector3(4.2, 1.6 + h, 3.2)
			var best_free := -1.0
			for k in 8:
				var aa := TAU * float(k) / 8.0
				var cp := hp + Vector3(sin(aa) * 5.0, 1.8 + h, cos(aa) * 5.0)
				var hit := InteractionUtil.ray(hp + Vector3(0, 1.8, 0), cp, GC.L_WORLD)
				var free_d := 5.0 if hit.is_empty() else hp.distance_to(hit["position"])
				if free_d > best_free:
					best_free = free_d
					best_pos = cp
			_look(best_pos, hp + Vector3(0, 2.0, 0), 62.0)
		"tower_roof":
			var hd: Vector3 = WorldLayout.location_pos(&"helipad_downtown")
			player.teleport_to(hd + Vector3(-8, 0.5, 6), deg_to_rad(-40))
			await _frames(60)
			_look(hd + Vector3(-24, 9, 24), hd + Vector3(4, 1.5, -2), 62.0)
		_:
			print("SHOT unknown scene ", scene)
	await _frames(20)
	return true
