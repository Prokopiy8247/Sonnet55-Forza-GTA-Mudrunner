extends Node

func run(_main: Node) -> Variant:
	for i in 5:
		await get_tree().physics_frame
	var pm := Game.sys(&"police") as PoliceManager
	var player = Game.player
	pm.manual = true
	player.teleport_to(WorldLayout.location_pos(&"helipad_airport") + Vector3(0, 0.3, 4))
	for i in 30:
		await get_tree().physics_frame
	var loc := WorldLayout.get_location(&"police_station")
	print("DBG station loc ", loc)
	var lanes: LaneGraph = WorldLayout.lanes
	var idx := lanes.nearest(loc["pos"], Vector3.ZERO, 40.0)
	print("DBG nearest idx=", idx, " pos=", lanes.positions[idx] if idx >= 0 else "none", " kind=", lanes.kind[idx] if idx >= 0 else -1, " next=", lanes.next[idx] if idx >= 0 else "none")
	var d := pm.director
	var space := pm._space()
	var cam := pm._camera()
	print("DBG cam ", cam, " pos=", cam.global_position if cam else "none")
	var req := {"center": player.global_position, "player": player.global_position, "camera": cam, "space": space, "station": true, "avoid": []}
	var site := d.find_road_site(req)
	print("DBG site ", site, " stats=", d.stats)
	if idx >= 0:
		var sc := d._check_site(lanes, idx, player.global_position, cam, cam.global_position, space, 80.0, [])
		print("DBG check_site=", sc, " visible=", d.visible_to_camera(cam, lanes.positions[idx], lanes.dirs[idx], space))
	return true
