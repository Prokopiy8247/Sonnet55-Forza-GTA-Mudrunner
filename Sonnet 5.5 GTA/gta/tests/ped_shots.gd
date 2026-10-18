extends Node
## Screenshot scenarios for the pedestrian module. Use with the harness:
##   tools\gd.ps1 shot -Out screenshots\peds\street.png -GameArgs "--exec=res://gta/tests/ped_shots.gd --scene=street --delay=4 --time=12 --no-traffic"
## Scenes: street crowd panic beach park bench sunbathe phone talk dead driver carjack witness walk_side

var pm: PedManager
var player: Node3D
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
	Game.gameplay_camera = cam         # PedManager's LOD / visibility decisions follow the camera that is actually rendering


func _co(default_offset: Vector3) -> Vector3:
	var s := _arg("co", "")
	if s == "":
		return default_offset
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _put_player(pos: Vector3) -> void:
	if player != null and player.has_method("teleport_to"):
		player.teleport_to(pos)


func _node_near(p: Vector3, zone: int = -1) -> int:
	var pg := WorldLayout.ped_graph
	var best := -1
	var bd := 1e9
	for i in pg.points_in_radius(p, 40.0):
		if zone >= 0 and pg.zone[i] != zone:
			continue
		var d := Util.dist_xz(pg.positions[i], p)
		if d < bd:
			bd = d
			best = i
	return best


func run(_main: Node) -> Variant:
	pm = Game.sys(&"peds")
	player = Game.player
	pm.spawner.instant = true            # scenes call the spawner directly: allow spots in view
	var scene := _arg("scene", "street")
	pm.enabled = true
	match scene:
		"street":
			# downtown pavement, camera at eye height looking along the street
			var base := Vector3(-35.0, 0.0, 16.0)
			_put_player(Vector3(-30.0, 0.1, 40.0))
			pm.spawn_crowd(base, 38.0, 30)
			await _frames(30)
			_cam(base + Vector3(3.0, 1.7, 12.0), base + Vector3(0.0, 1.4, -20.0), 62.0)
			await _frames(150)
		"crowd":
			var base2 := Vector3(0.0, 0.0, 34.0)
			_put_player(Vector3(0.0, 0.1, 60.0))
			pm.spawn_crowd(base2, 26.0, 26)
			await _frames(30)
			_cam(base2 + Vector3(-10.0, 2.4, 12.0), base2 + Vector3(4.0, 1.2, -4.0), 55.0)
			await _frames(120)
		"lineup":
			var base3 := Vector3(6.0, 0.15, 30.0)
			_put_player(Vector3(30.0, 0.1, 60.0))
			var looks: Array[StringName] = [&"business", &"casual", &"worker", &"beach", &"jogger", &"tourist", &"elder", &"business", &"casual"]
			for i in looks.size():
				var p := pm.spawn_pedestrian(base3 + Vector3((i - 4) * 1.15, 0, 0), looks[i], {"yaw": PI + (i - 4) * 0.05, "stationary": true, "persistent": true})
				p.brain.begin_idle(&"relaxed" if i % 3 == 0 else (&"hands_pockets" if i % 3 == 1 else &"arms_crossed"), 999.0, PI + (i - 4) * 0.05)
			await _frames(20)
			_cam(base3 + Vector3(0.0, 1.45, 6.6), base3 + Vector3(0.0, 1.0, 0.0), 50.0)
			await _frames(60)
		"panic":
			var base4 := Vector3(0.0, 0.0, 34.0)
			_put_player(Vector3(0.0, 0.1, 60.0))
			pm.spawn_crowd(base4, 22.0, 22)
			await _frames(90)
			_cam(base4 + _co(Vector3(-9.0, 3.2, 14.0)), base4 + Vector3(0.0, 1.0, -2.0), 58.0)
			Events.gunshot.emit(base4 + Vector3(0, 1.2, -2.0), 90.0, null)
			await _frames(_frames_arg(75))
		"bench":
			var bi := -1
			var bd := 1e9
			var c0 := Vector3(-60.0, 0.0, -125.0)
			for i in pm.benches.size():
				var d: float = Util.dist_xz(pm.benches[i]["pos"], c0)
				if d < bd:
					bd = d
					bi = i
			var bp: Vector3 = pm.benches[bi]["pos"]
			var byaw: float = float(pm.benches[bi]["yaw"])
			_put_player(bp + Vector3(30, 0.1, 30))
			pm.spawner._spawn_sitter(bi)
			var bfwd := Util.yaw_to_dir(byaw)
			var bright := Vector3(cos(byaw), 0.0, -sin(byaw))
			await _frames(40)
			var dist_cam := float(_arg("dist", "3.2"))
			var ang := float(_arg("ang", "0.7"))
			_cam(bp + bfwd * dist_cam * cos(ang) + bright * dist_cam * sin(ang) + Vector3(0, 1.1, 0), bp + Vector3(0, 0.75, 0), 50.0)
			await _frames(30)
		"sunbathe":
			var sb := Vector3(0.0, 0.0, 165.0)
			_put_player(sb + Vector3(40, 0.1, -30))
			pm.spawner._spawn_sunbather(sb)
			pm.spawner._spawn_sunbather(sb + Vector3(6, 0, 0))
			pm.spawn_crowd(sb, 20.0, 10)
			await _frames(40)
			var sp := Vector3(0, 0, 0)
			for p in pm.peds:
				if p.brain.state == PedBrain.S.SUNBATHE:
					sp = p.global_position
					break
			_cam(sp + Vector3(3.0, 2.2, 3.6), sp + Vector3(0, 0.2, 0), 55.0)
			await _frames(30)
		"phone":
			var pp := Vector3(0.0, 0.15, 30.0)
			_put_player(Vector3(30.0, 0.1, 60.0))
			var ped := pm.spawn_pedestrian(pp, &"casual", {"yaw": PI, "stationary": true, "persistent": true})
			ped.brain.begin_idle(&"phone", 999.0, PI)
			await _frames(70)
			_cam(pp + Vector3(0.9, 1.6, 1.6), pp + Vector3(0, 1.45, 0), 40.0)
			await _frames(20)
		"pier":
			# peds on the pier deck over the water (the graph carries the sea floor height there: PedNav.fix_heights)
			var pg := WorldLayout.ped_graph
			var made := 0
			var c := Vector3.ZERO
			for i in pg.size():
				if pg.zone[i] == PedGraph.ZONE_DOCK and absf(pg.positions[i].x) < 2.0 and pg.positions[i].z > 168.0 and pg.positions[i].z < 190.0 and made < 4:
					var pd := pm.spawn_pedestrian(PedNav.node_pos(i), &"tourist", {"node": i, "persistent": true})
					if pd != null:
						made += 1
						c = pd.global_position
			_put_player(Vector3(12.0, 0.1, 150.0))
			await _frames(60)
			_cam(c + Vector3(7.0, 2.2, 5.0), c + Vector3(0, 0.8, 0), 55.0)
			await _frames(20)
		"talk":
			_put_player(Vector3(30.0, 0.1, 60.0))
			var tp := Vector3(0.0, 0.15, 30.0)
			var a := pm.spawn_pedestrian(tp + Vector3(-0.6, 0, 0), &"casual", {"yaw": -PI * 0.5, "stationary": true, "persistent": true})
			var b := pm.spawn_pedestrian(tp + Vector3(0.6, 0, 0), &"business", {"yaw": PI * 0.5, "stationary": true, "persistent": true})
			a.brain.begin_talk(b, -PI * 0.5, 999.0)
			b.brain.begin_talk(a, PI * 0.5, 999.0)
			await _frames(60)
			_cam(tp + Vector3(0.5, 1.5, 2.6), tp + Vector3(0, 1.2, 0), 50.0)
			await _frames(20)
	return null


func _frames_arg(default_n: int) -> int:
	return int(_arg("after", str(default_n)))
