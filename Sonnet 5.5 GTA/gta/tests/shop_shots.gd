extends Node
## Screenshot scenarios for the Shops / Interiors module (use with the harness `shot` command, real renderer):
##   tools\gd.ps1 shot -Out screenshots\shops\weapon_a.png -GameArgs "--exec=res://gta/tests/shop_shots.gd --room=weapon_shop --view=a --no-peds --no-traffic --time=14 --delay=4"
## args: --room=<interior id>  --view=a|b|c|d|player|x,y,z,tx,ty,tz (room-local)  --menu=weapons|bench|clothes|wardrobe|barber|food|scuba|sleep|garage
##       --store=sports,muscle (vehicles in the safehouse garage)  --clerk=hands_up  --night=1  --tv=1  --own=pistol,smg  --mod=suppressor,scope  --door=<id> (exterior shot of a world door)
##       --fov=70  --wait=<frames>  --cash=<n>

var _cam: Camera3D = null


func _arg(key: String, default_value: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--" + key + "="):
			return s.substr(key.length() + 3)
	return default_value


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _preset(room: InteriorRoom, view: String) -> Array:
	var w := room.size.x
	var d := room.size.z
	var h := room.size.y
	match view:
		"a":
			return [Vector3(w * 0.5 - 0.45, h - 0.7, d * 0.5 - 0.45), Vector3(-0.3, 1.1, -d * 0.25)]
		"b":
			return [Vector3(-w * 0.5 + 0.45, h - 0.7, d * 0.5 - 0.45), Vector3(w * 0.25, 1.0, -d * 0.2)]
		"c":
			return [Vector3(-w * 0.5 + 0.5, h - 0.6, -d * 0.5 + 0.5), Vector3(w * 0.15, 1.0, d * 0.3)]
		"d":
			return [Vector3(w * 0.5 - 0.5, h - 0.6, -d * 0.5 + 0.5), Vector3(-w * 0.2, 1.0, d * 0.25)]
		"top":
			return [Vector3(0.01, h + 6.0, 0.01), Vector3(0, 0, 0)]
	var p := view.split(",")
	if p.size() >= 6:
		return [Vector3(float(p[0]), float(p[1]), float(p[2])), Vector3(float(p[3]), float(p[4]), float(p[5]))]
	return [Vector3(0, 1.6, 0), Vector3(0, 1.4, -2)]


func run(_main: Node) -> Variant:
	var it = Game.sys(&"interiors")
	var shops = Game.sys(&"shops")
	var p = Game.player
	var room_id := StringName(_arg("room", "weapon_shop"))
	var view := _arg("view", "a")
	var menu := _arg("menu", "")
	if _arg("cash", "") != "":
		Game.cash = int(_arg("cash", "5000"))
	if _arg("night", "") == "1":
		var env = Game.sys(&"environment")
		if env != null:
			env.set_time(2.0)
		Game.time_frozen = true
	if _arg("own", "") != "":
		for id in _arg("own", "").split(","):
			p.weapons.give_weapon(StringName(id), 200, false)
	if _arg("mod", "") != "" and _arg("own", "") != "":
		var first := StringName(_arg("own", "").split(",")[0])
		for m in _arg("mod", "").split(","):
			p.weapons.set_mod(first, StringName(m), true)
		p.weapons.equip(first)
	if _arg("store", "") != "":
		var garage = Game.sys(&"garage")
		var cols := [Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347")]
		var ci := 0
		for vid in _arg("store", "").split(","):
			if garage != null:
				garage.add_record(StringName(vid), cols[ci % 3], Color("#f2f0ea"))
				ci += 1
	await _frames(20)
	var door_arg := _arg("door", "")
	if door_arg != "":
		var d = it.door_for(StringName(door_arg))
		var pos: Vector3 = d.global_position
		var out: Vector3 = Util.yaw_to_dir(float(d.data["yaw"]))
		p.teleport_to(d.data["return"] + Vector3(0, 0.3, 0), float(d.data["yaw"]))
		await _frames(30)
		_cam = Camera3D.new()
		_cam.fov = float(_arg("fov", "62"))
		add_child(_cam)
		_cam.global_position = pos + out * 6.5 + Vector3(2.0, 2.2, 0)
		_cam.look_at(pos + Vector3(0, 1.7, 0), Vector3.UP)
		_cam.make_current()
		await _frames(int(_arg("wait", "40")))
		return null
	var room: InteriorRoom = it.get_room(room_id)
	var door = it.door_for(room_id)
	var ret: Vector3 = door.data["return"] if door != null else p.global_position
	var yaw: float = float(door.data["yaw"]) if door != null else 0.0
	p.teleport_to(ret + Vector3(0, 0.3, 0), yaw)
	await _frames(25)
	await it.enter(room_id, ret, yaw, true)
	await _frames(30)
	if _arg("tv", "") == "1":
		var sh = Game.sys(&"safehouse")
		if sh != null and not sh.tv_on:
			sh.toggle_tv()
	if _arg("clerk", "") == "hands_up" and room.clerk != null:
		room.clerk.raise_hands(60.0)
	if view != "player":
		var pr := _preset(room, view)
		_cam = Camera3D.new()
		_cam.fov = float(_arg("fov", "72"))
		_cam.near = 0.05
		add_child(_cam)
		_cam.global_position = room.to_global(pr[0])
		_cam.look_at(room.to_global(pr[1]), Vector3.UP)
		_cam.make_current()
	room.refresh_daylight(Game.daylight())
	if menu != "":
		match menu:
			"weapons": shops.open_menu(&"weapons", room)
			"bench": shops.open_menu(&"bench", room)
			"clothes": shops.open_menu(&"clothes", room)
			"wardrobe": shops.open_menu(&"wardrobe", room)
			"barber": shops.open_menu(&"barber", room)
			"food": shops.open_menu(&"food", room)
			"scuba": shops.open_menu(&"scuba", room)
			"sleep": Game.sys(&"safehouse").open_sleep_menu()
			"garage": Game.sys(&"safehouse").open_garage_menu()
		await _frames(10)
		var tab := _arg("tab", "")
		if tab != "":
			var sel := _arg("sel", "")
			match menu:
				"weapons":
					shops.menus[&"shop_weapons"]._on_tab(int(tab))
					if sel != "":
						shops.menus[&"shop_weapons"]._select(StringName(sel))
				"clothes", "wardrobe":
					shops.menus[&"shop_clothes"]._on_tab(int(tab))
				"barber":
					shops.menus[&"shop_barber"]._on_tab(int(tab))
		await _frames(int(_arg("wait", "50")))
	else:
		await _frames(int(_arg("wait", "50")))
	return null
