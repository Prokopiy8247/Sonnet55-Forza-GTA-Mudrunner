class_name InteriorSafehouse
extends RefCounted
## Layouts of the player's safehouse: the apartment (bed = sleep / time skip, wardrobe = free outfit changes, nightstand = save,
## TV, kitchen snack, door to the garage) and the 3-bay garage with its roller door, vehicle console and the stairs back up.
## Use points call SafehouseSystem (Game.sys(&"safehouse")).

const BAYS := [Vector3(-3.7, 0.0, -0.4), Vector3(0.0, 0.0, -0.4), Vector3(3.7, 0.0, -0.4)]


static func _sh() -> Node:
	return Game.sys(&"safehouse")


static func _use(room: InteriorRoom, tag: StringName, pos: Vector3, text: String, method: String, rng: float = 1.9) -> InteriorDoor:
	var p := pos
	p.y = 0.0
	var d := room.add_use(tag, p, text, Callable(), rng)
	d.on_interact = func(_p: Variant) -> void:
		var s := _sh()
		if s != null and s.has_method(method):
			s.call(method)
	return d


static func _plant(room: InteriorRoom, pos: Vector3) -> void:
	room.add_cyl(pos + Vector3(0, 0.22, 0), 0.22, 0.44, Color("#c9704f"), 0.8, 0.0, 0.0, 8)
	var leaves := [Vector3(0, 0.75, 0), Vector3(0.14, 0.95, 0.06), Vector3(-0.12, 1.1, -0.05), Vector3(0.02, 1.28, 0.1)]
	var cols := [Color("#3f8a4d"), Color("#4fa05a"), Color("#357a43"), Color("#5ab466")]
	for i in leaves.size():
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2 - float(i) * 0.02
		sm.height = sm.radius * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		mi.position = pos + leaves[i]
		mi.material_override = InteriorRoom.mat(cols[i], 0.8)
		room.add_child(mi)


static func _floor_lamp(room: InteriorRoom, pos: Vector3, color: Color) -> void:
	room.add_cyl(pos + Vector3(0, 0.03, 0), 0.16, 0.06, Color("#23262b"), 0.5, 0.6, 0.0, 10)
	room.add_cyl(pos + Vector3(0, 0.8, 0), 0.02, 1.6, Color("#23262b"), 0.5, 0.6, 0.0, 6)
	room.add_cyl(pos + Vector3(0, 1.6, 0), 0.17, 0.26, color, 0.6, 0.0, 1.6, 8)
	room.add_light(pos + Vector3(0, 1.55, 0), color.lerp(Color.WHITE, 0.2), 0.8, 4.2)


static func build_apartment(room: InteriorRoom) -> void:
	var w := 10.0
	var d := 8.0
	room.build_shell(w, d, 2.9, {
		"floor_pattern": &"planks", "tile": 0.42, "floor_a": Color("#7a5238"), "floor_b": Color("#5d3d29"), "grout": Color("#1f140d"),
		"wall": Color("#d4dcd6"), "wainscot": Color("#2f9c95"), "wainscot_h": 0.0, "trim": Color("#f0ede6"), "ceiling": Color("#ece8e0"),
		"accent": Color("#ff3d9a"), "neon": Color("#ff3d9a"), "light": Color("#ffd6a0"), "light_energy": 1.35, "ambient": Color("#b8a898"),
		"ambient_energy": 0.5, "surface": &"wood", "door": Color("#2f9c95"), "floor_rough": 0.45,
	})
	room.set_exit(-3.5, "Leave apartment")
	# accent wall behind the TV + rug
	room.add_box(room.wall_point(&"w", -0.6, 1.45, 0.012), Vector3(0.02, 2.9, 4.2), Color("#355f66"), 0.9)
	room.add_box(Vector3(-2.7, 0.012, -0.6), Vector3(3.9, 0.022, 3.2), Color("#2d6c75"), 0.95)
	room.add_box(Vector3(-2.7, 0.026, -0.6), Vector3(3.4, 0.014, 2.7), Color("#ff3d9a"), 0.95, 0.0, 0.0)
	room.add_box(Vector3(-2.7, 0.034, -0.6), Vector3(3.1, 0.012, 2.4), Color("#234f57"), 0.95)
	# bed + nightstand (save) + wardrobe
	room.wall_prop("bed_double", &"n", 3.3)
	_use(room, &"bed", Vector3(3.3, 0, -1.2), "Sleep", "open_sleep_menu", 2.2)
	room.wall_prop("nightstand", &"n", 1.95)
	_use(room, &"save", Vector3(1.95, 0, -4.0 + 1.0), "Save game", "save_game", 1.5)
	var ward := room.wall_prop("wardrobe", &"n", 0.45)
	_use(room, &"wardrobe", room.prop_point(ward, "UsePoint", Vector3(0, 0, -0.9)), "Open wardrobe", "open_wardrobe", 1.8)
	# living area
	var tv := room.wall_prop("tv_stand_tv", &"w", -0.6)
	_use(room, &"tv", Vector3(-3.55, 0, -0.6), "Turn TV on / off", "toggle_tv", 2.4)
	room.add_prop("sofa", Vector3(-1.3, 0, -0.6), PI * 0.5)
	room.info["tv"] = tv
	# kitchen + dining
	var kit := room.wall_prop("kitchen_unit", &"e", 1.5)
	_use(room, &"kitchen", room.prop_point(kit, "UsePoint", Vector3(0, 0, -0.9)), "Grab a snack from the fridge", "snack", 1.9)
	room.add_prop("table_round", Vector3(1.9, 0, 1.4), 0.0)
	room.add_prop("chair", Vector3(1.9, 0, 2.3), 0.0)
	room.add_prop("chair", Vector3(1.9, 0, 0.5), PI)
	# garage door in the south wall (east of the entrance)
	var gx := 3.2
	room.add_box(Vector3(gx, 1.15, 3.97), Vector3(1.9, 2.3, 0.06), Color("#59606b"), 0.55, 0.3)
	for i in 5:
		room.add_box(Vector3(gx, 0.3 + float(i) * 0.42, 3.93), Vector3(1.86, 0.05, 0.04), Color("#3d434c"), 0.5, 0.4)
	room.add_box(Vector3(gx, 2.38, 3.95), Vector3(2.2, 0.12, 0.08), Color("#f0ede6"))
	room.add_sign("GARAGE", Vector3(gx, 2.62, 3.9), PI, Color("#34e0ff"), 70, 0.0035)
	_use(room, &"garage", Vector3(gx, 0, 3.1), "Go down to the garage", "enter_garage", 1.9)
	# decoration
	_plant(room, Vector3(-4.35, 0, 3.3))
	_plant(room, Vector3(4.4, 0, -0.8))
	_floor_lamp(room, Vector3(-4.3, 0, 1.9), Color("#ffb347"))
	room.add_window(&"s", -0.6, 2.6, 1.4, 0.95)
	room.add_window(&"e", -2.6, 1.8, 1.3, 1.0)
	# wall art
	room.add_box(room.wall_point(&"n", -2.4, 1.7, 0.02), Vector3(1.0, 0.7, 0.03), Color("#e8795f"), 0.7)
	room.add_box(room.wall_point(&"n", -2.4, 1.7, 0.04), Vector3(0.88, 0.58, 0.02), Color("#25324d"), 0.7)
	room.add_box(room.wall_point(&"n", -2.4, 1.78, 0.052), Vector3(0.5, 0.08, 0.01), Color("#ff3d9a"), 0.6, 0.0, 1.8)
	room.add_box(room.wall_point(&"n", -2.4, 1.6, 0.052), Vector3(0.62, 0.05, 0.01), Color("#34e0ff"), 0.6, 0.0, 1.8)
	room.add_light(Vector3(3.3, 2.2, -2.4), Color("#ffc080"), 0.9, 4.5)
	room.add_light(Vector3(3.4, 2.5, 2.0), Color("#fff0dc"), 0.7, 4.5)
	var tvl := room.add_light(Vector3(-3.6, 1.1, -0.6), Color("#34e0ff"), 0.0, 3.6)
	room.info["tv_light"] = tvl
	room.info["robbable"] = false
	room.spawn_pos = Vector3(-3.5, 0.08, 4.0 - 1.35)


static func build_garage(room: InteriorRoom) -> void:
	var w := 12.0
	var d := 9.0
	room.build_shell(w, d, 3.4, {
		"floor_pattern": &"tiles", "tile": 1.5, "floor_a": Color("#6a6f77"), "floor_b": Color("#5d6269"), "grout": Color("#25282d"),
		"wall": Color("#8e959d"), "wainscot": Color("#363b43"), "wainscot_h": 1.2, "trim": Color("#23262b"), "ceiling": Color("#4a4f57"),
		"accent": Color("#f2cf3a"), "neon": Color("#34e0ff"), "light": Color("#e9f4ff"), "light_energy": 1.5, "ambient": Color("#9aa3ad"),
		"ambient_energy": 0.5, "surface": &"concrete", "door": Color("#3d434c"), "floor_rough": 0.6,
	})
	# roller door (exit to the street) in the south wall
	var z := d * 0.5 - 0.04
	room.add_box(Vector3(0, 1.6, z), Vector3(5.6, 3.2, 0.06), Color("#59606b"), 0.5, 0.35)
	for i in 8:
		room.add_box(Vector3(0, 0.2 + float(i) * 0.4, z - 0.04), Vector3(5.5, 0.05, 0.03), Color("#3d434c"), 0.5, 0.4)
	room.add_box(Vector3(0, 3.25, z - 0.02), Vector3(5.9, 0.16, 0.1), Color("#f2cf3a"), 0.6)
	room.add_sign("EXIT", Vector3(0, 3.0, d * 0.5 - 0.1), PI, Color("#7be495"), 56, 0.0035)
	var ex := room.add_use(&"exit", Vector3(0, 0, d * 0.5 - 1.0), "Open the garage door", Callable(), 2.6)
	room.exit_door = ex
	room.spawn_pos = Vector3(0, 0.08, d * 0.5 - 1.6)
	room.info["exit_door_id"] = &"safehouse_garage"        # InteriorSystem returns to the GarageDoor world door, wherever we came from
	# the three bays: painted frames + number plates on the wall
	for i in BAYS.size():
		var c: Vector3 = BAYS[i]
		for sx in [-1.0, 1.0]:
			room.add_box(c + Vector3(sx * 1.55, 0.012, 0.0), Vector3(0.07, 0.02, 4.8), Color("#f2cf3a"), 0.6, 0.0, 0.6)
		room.add_box(c + Vector3(0, 0.012, -2.4), Vector3(3.14, 0.02, 0.07), Color("#f2cf3a"), 0.6, 0.0, 0.6)
		room.add_sign(str(i + 1), Vector3(c.x, 2.1, -d * 0.5 + 0.1), 0.0, Color("#34e0ff"), 120, 0.006)
	# bench, tool chest, shelf, lift as decoration
	room.wall_prop("tool_chest", &"w", 2.6)
	room.wall_prop("shelf_wall", &"w", -0.4)
	var terminal_pos := Vector3(-w * 0.5 + 1.2, 0, 3.2)
	room.add_solid(Vector3(-w * 0.5 + 0.55, 0.5, 3.2), Vector3(0.7, 1.0, 1.2), Color("#2b2e33"), 0.6, 0.4)
	room.add_box(Vector3(-w * 0.5 + 0.55, 1.18, 3.2), Vector3(0.5, 0.36, 0.9), Color("#34e0ff"), 0.2, 0.0, 1.4)
	room.add_sign("VEHICLES", Vector3(-w * 0.5 + 0.2, 1.6, 3.2), PI * 0.5, Color("#34e0ff"), 48, 0.0032)
	_use(room, &"console", terminal_pos, "Vehicle console", "open_garage_menu", 2.0)
	# stairs door (west wall, back corner) back to the apartment
	room.add_box(Vector3(w * 0.5 - 0.04, 1.1, -2.6), Vector3(0.06, 2.2, 1.1), Color("#2f9c95"), 0.6)
	room.add_box(Vector3(w * 0.5 - 0.06, 2.28, -2.6), Vector3(0.1, 0.12, 1.4), Color("#23262b"))
	room.add_sign("APARTMENT", Vector3(w * 0.5 - 0.1, 2.55, -2.6), -PI * 0.5, Color("#ff3d9a"), 44, 0.0032)
	_use(room, &"stairs", Vector3(w * 0.5 - 1.1, 0, -2.6), "Go up to the apartment", "enter_apartment", 1.9)
	# hanging light tubes over the bays
	for i in BAYS.size():
		var c2: Vector3 = BAYS[i]
		room.add_box(Vector3(c2.x, 3.2, c2.z), Vector3(2.4, 0.06, 0.16), Color("#e9f4ff"), 0.4, 0.0, 2.6)
		room.add_light(Vector3(c2.x, 2.9, c2.z), Color("#e9f4ff"), 0.9, 5.5)
	room.info["robbable"] = false
	room.info["bays"] = BAYS
	room.info["display"] = []


## Colour of a GarageSystem stored-vehicle build dictionary (keys p1 / p2: "#rrggbb"; also tolerates paint1 / paint2 as Color or [r,g,b]).
static func _record_color(build: Dictionary, keys: Array, fallback: Color) -> Color:
	for k in keys:
		if not build.has(k):
			continue
		var v: Variant = build[k]
		if v is Color:
			return v
		if v is String:
			return Color(String(v))
		if v is Array and (v as Array).size() >= 3:
			return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


## Shows the stored vehicles (models only, no physics) in the garage bays. Call on entry.
static func refresh_garage_display(room: InteriorRoom, records: Array) -> void:
	for n in room.info.get("display", []):
		if is_instance_valid(n):
			n.queue_free()
	var shown: Array = []
	var bay := 0
	for rec in records:
		if bay >= BAYS.size():
			break
		if bool(rec.get("out", false)):
			continue
		var def_id := String(rec.get("def", ""))
		var rel := "vehicles/" + def_id
		if not ModelLib.exists(rel):
			continue
		var m := ModelLib.instance(rel)
		if m == null:
			continue
		m.position = BAYS[bay] + Vector3(0, 0.02, 0)
		m.rotation.y = PI
		m.set_meta(&"stat_display", true)
		InteriorRoom.no_shadows(m)
		var build: Dictionary = rec.get("build", {})
		Util.replace_material(m, "Paint", InteriorRoom.mat(_record_color(build, ["p1", "paint1"], Color("#c9ccd1")), 0.3, 0.55))
		Util.replace_material(m, "Paint2", InteriorRoom.mat(_record_color(build, ["p2", "paint2"], Color("#2a2d33")), 0.3, 0.55))
		room.add_child(m)
		shown.append(m)
		bay += 1
	room.info["display"] = shown
