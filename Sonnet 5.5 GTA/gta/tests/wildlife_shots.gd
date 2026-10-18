extends Node
## Screenshot scenarios for wildlife / underwater:
##   tools\gd.ps1 shot -Out screenshots\wildlife\herd.png -GameArgs "--exec=res://gta/tests/wildlife_shots.gd --scene=herd --delay=4 --time=11 --no-peds --no-traffic"
## Scenes: herd (deer herd in the park), boar, gulls (beach pier), fish (school near the marina pier), shark (fin patrol), wreck (diver view), dolphins-less.

var cam: Camera3D


func _arg(key: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
	return default_value


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _cam(from: Vector3, to: Vector3, fov: float = 60.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.near = 0.05
		cam.far = 900.0
		add_child(cam)
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.make_current()
	Game.gameplay_camera = cam


func run(_main: Node) -> Variant:
	var wl := Game.sys(&"wildlife") as WildlifeSystem
	var player := Game.player as Node3D
	wl.auto_population = false
	wl.despawn_all()
	var scene := _arg("scene", "herd")
	match scene:
		"herd":
			var base := Vector3(-30.0, 0.0, -150.0)
			base.y = WorldLayout.terrain_height(base.x, base.z)
			player.teleport_to(base + Vector3(0.0, 0.3, 70.0), 0.0)
			await _frames(30)
			var m := wl.spawn_group(&"deer", base, 5, {"buck": true})
			wl.spawn_group(&"rabbit", base + Vector3(-7.0, 0.0, 6.0), 2, {})
			await _frames(200)
			var c := (m[0] as Animal).pos
			_cam(c + Vector3(7.0, 2.0, 11.0), c + Vector3(0.0, 1.0, 0.0), 55.0)
			await _frames(40)
		"boar":
			var base2 := Vector3(-60.0, 0.0, -170.0)
			base2.y = WorldLayout.terrain_height(base2.x, base2.z)
			player.teleport_to(base2 + Vector3(0.0, 0.3, 80.0), 0.0)
			await _frames(30)
			var b := wl.spawn_group(&"boar", base2, 2, {})
			var cy := wl.spawn_animal(&"coyote", base2 + Vector3(4.0, 0.0, 4.0), {})
			await _frames(160)
			_cam((b[0] as Animal).pos + Vector3(4.0, 1.4, 6.0), (b[0] as Animal).pos + Vector3(1.0, 0.5, 1.5), 55.0)
			await _frames(30)
		"gulls":
			player.teleport_to(Vector3(0.0, 0.3, 150.0), 0.0)
			wl.auto_population = true
			wl.instant_fill = 3.0
			await _frames(260)
			_cam(Vector3(2.5, 1.9, 178.0), Vector3(0.0, 1.2, 196.0), 55.0)
			await _frames(30)
		"fish":
			player.teleport_to(Vector3(-146.0, 0.3, 200.0), 0.0)
			wl.fish.clear()
			wl.instant_fill = 2.0
			await _frames(240)
			var s: Dictionary = wl.fish.schools[0] if wl.fish.schools.size() > 0 else {"c": Vector3(-146, -3, 232)}
			var fc: Vector3 = s["c"]
			_cam(fc + Vector3(3.0, 2.8, 6.0), fc, 62.0)
			await _frames(40)
		"shark":
			player.teleport_to(Vector3(-22.0, 0.3, 160.0), 0.0)
			await _frames(30)
			var sh := wl.spawn_shark(Vector3(-22.0, -2.0, 250.0))
			sh.aux = GC.WATER_LEVEL - 0.35
			await _frames(200)
			_cam(sh.pos + Vector3(9.0, 3.0, 12.0), sh.pos, 55.0)
			await _frames(20)
		"wreck":
			var wp := WorldLayout.location_pos(&"diving_wreck")
			player.teleport_to(Vector3(-22.0, 0.3, 160.0), 0.0)
			wl.fish.clear()
			await _frames(30)
			wl.fish.add_school(wp + Vector3(-3.0, 0.0, 8.0), 10, 0)
			wl.fish.add_school(wp + Vector3(5.0, 0.0, -6.0), 8, 1)
			_cam(wp + Vector3(16.0, 7.0, 24.0), wp + Vector3(0.0, 4.0, 0.0), 62.0)
			Game.player.set("is_underwater", true)
			await _frames(150)
	return true
