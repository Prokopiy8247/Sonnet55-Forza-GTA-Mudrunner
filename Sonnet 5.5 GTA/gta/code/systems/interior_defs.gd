class_name InteriorDefs
extends RefCounted
## Room layouts of the street shops (weapon shop, clothing store, barber, gas station shop, scuba shop). Each builder fills an
## InteriorRoom (shell + Blender `interiors/*.glb` props + clerk + use points). Registered by InteriorSystem.post_setup().
## Use points call into ShopSystem (Game.sys(&"shops")): open_menu(kind, room), counter_info(room, text), counter_use(room, kind).

## id -> {name, location (WorldLayout id of the street door), sign, hours (true = closed 23:00-06:00), builder}
const SHOPS := {
	&"weapon_shop": {"name": "Gunsmith", "location": &"weapon_shop", "hours": true, "prompt": "Enter Gunsmith"},
	&"clothing_store": {"name": "Threads", "location": &"clothing_store", "hours": true, "prompt": "Enter Threads"},
	&"barber": {"name": "Clip & Co Barber", "location": &"barber", "hours": true, "prompt": "Enter Clip & Co Barber"},
	&"gas_station": {"name": "Halcyon Fuel Mart", "location": &"gas_station", "hours": false, "prompt": "Enter Fuel Mart"},
	&"scuba_shop": {"name": "Reef Dive Shop", "location": &"scuba_shop", "hours": true, "prompt": "Enter Reef Dive Shop"},
}


static func register_all(sys: Node) -> void:
	sys.register_interior(&"weapon_shop", Callable(InteriorDefs, "build_weapon_shop"), SHOPS[&"weapon_shop"])
	sys.register_interior(&"clothing_store", Callable(InteriorDefs, "build_clothing_store"), SHOPS[&"clothing_store"])
	sys.register_interior(&"barber", Callable(InteriorDefs, "build_barber"), SHOPS[&"barber"])
	sys.register_interior(&"gas_station", Callable(InteriorDefs, "build_gas_station"), SHOPS[&"gas_station"])
	sys.register_interior(&"scuba_shop", Callable(InteriorDefs, "build_scuba_shop"), SHOPS[&"scuba_shop"])


# ================================================================================================= helpers
static func _shops() -> Node:
	return Game.sys(&"shops")


## Use point in front of a counter (the CustomerPoint empty). Handles the robbery prompt through ShopSystem.counter_info().
static func _counter_point(room: InteriorRoom, counter: Node3D, menu: StringName, text: String) -> InteriorDoor:
	var pos := room.prop_point(counter, "CustomerPoint", Vector3(0, 0, -0.9))
	pos.y = 0.0
	var d := room.add_use(&"counter", pos, text, Callable(), 2.3)
	d.data["menu"] = menu
	d.text_provider = func(_p: Variant) -> Dictionary:
		var s := _shops()
		if s != null and s.has_method("counter_info"):
			return s.counter_info(room, text)
		return {"text": text, "key": "E", "enabled": true}
	d.on_interact = func(_p: Variant) -> void:
		var s := _shops()
		if s != null and s.has_method("counter_use"):
			s.counter_use(room, menu)
	return d


static func _menu_point(room: InteriorRoom, tag: StringName, local_pos: Vector3, menu: StringName, text: String, range_m: float = 2.0) -> InteriorDoor:
	var p := local_pos
	p.y = 0.0
	var d := room.add_use(tag, p, text, Callable(), range_m)
	d.data["menu"] = menu
	d.on_interact = func(_p: Variant) -> void:
		var s := _shops()
		if s != null and s.has_method("open_menu"):
			s.open_menu(menu, room)
	return d


static func _make_clerk(room: InteriorRoom, counter: Node3D, shop: StringName, overrides: Dictionary, style: StringName = &"hands_pockets") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(shop) + "clerk")
	var v: Dictionary = CharacterVariants.shop_staff(rng)
	for k in overrides:
		v[k] = overrides[k]
	var pos := room.prop_point(counter, "ClerkPoint", Vector3(0, 0, 0.9))
	pos.y = 0.0
	room.clerk = ShopClerk.create(room, pos, counter.rotation.y, shop, v, style)


## Full-width counter: the prop in the middle + low cabinets to the side walls so the staff area is closed.
static func _close_counter_line(room: InteriorRoom, cz: float, half_prop: float, col: Color, top: Color) -> void:
	var hw := room.size.x * 0.5
	for sgn in [-1.0, 1.0]:
		var x0: float = half_prop * sgn
		var x1: float = hw * sgn
		var cx := (x0 + x1) * 0.5
		var wd := absf(x1 - x0)
		if wd < 0.1:
			continue
		room.add_solid(Vector3(cx, 0.52, cz), Vector3(wd, 1.04, 0.7), col, 0.7)
		room.add_box(Vector3(cx, 1.06, cz), Vector3(wd + 0.02, 0.05, 0.76), top, 0.45)


## Mount real weapon GLBs on the SlotXxx empties of a weapon_rack_wall.
static func _display_rack(room: InteriorRoom, rack: Node3D, mapping: Dictionary) -> void:
	for slot_name in mapping:
		var wid: StringName = mapping[slot_name]
		var slot := rack.find_child(String(slot_name), true, false) as Node3D
		if slot == null:
			continue
		var rel := "weapons/" + String(wid)
		if not ModelLib.exists(rel):
			continue
		var gun := ModelLib.instance(rel)
		if gun == null:
			continue
		gun.name = "Display_" + String(wid)
		gun.set_meta(&"stat_display", true)
		InteriorRoom.no_shadows(gun)
		var bb := Util.local_aabb(gun)
		# barrel (-Z of the weapon) points along the rack's -X, centred on the slot; the gun hangs 5 cm off the wall
		var basis_g := Basis(Vector3.UP, PI * 0.5)
		var origin_local := slot.position + Vector3(0, 0, -0.03)
		var shift := basis_g * Vector3(0, 0, bb.get_center().z)
		gun.transform = Transform3D(basis_g, origin_local - shift)
		rack.add_child(gun)


# ================================================================================================= weapon shop
static func build_weapon_shop(room: InteriorRoom) -> void:
	var w := 9.0
	var d := 8.4
	room.build_shell(w, d, 3.2, {
		"floor_pattern": &"checker", "tile": 1.0, "floor_a": Color("#4a515c"), "floor_b": Color("#363c46"), "grout": Color("#101216"),
		"wall": Color("#99a3ad"), "wainscot": Color("#2b2f37"), "trim": Color("#1b1e23"), "ceiling": Color("#565c66"),
		"accent": Color("#ffb347"), "neon": Color("#ff4d4d"), "light": Color("#ffd8aa"), "light_energy": 1.7,
		"ambient": Color("#a49a90"), "surface": &"concrete", "door": Color("#3a4a5c"), "floor_rough": 0.45,
	})
	room.set_exit(2.8)
	var rack := room.wall_prop("weapon_rack_wall", &"n", 0.0, 0.02, false)
	_display_rack(room, rack, {
		"SlotPistol1": &"pistol", "SlotPistol2": &"revolver", "SlotPistol3": &"pistol", "SlotPistol4": &"revolver",
		"SlotSmg1": &"smg", "SlotSmg2": &"smg",
		"SlotLong1": &"shotgun_pump", "SlotLong2": &"rifle_assault", "SlotLong3": &"carbine", "SlotLong4": &"rifle_marksman",
	})
	var cz := -d * 0.5 + 2.7
	var counter := room.add_prop("shop_counter", Vector3(0, 0, cz), PI)
	_close_counter_line(room, cz, 1.56, Color("#2b2f37"), Color("#d6dbe0"))
	_counter_point(room, counter, &"weapons", "Browse weapons")
	_make_clerk(room, counter, &"weapon_shop", {"body": &"C", "hair": 0, "shirt": Color("#23262b"), "pants": Color("#1d2024"), "accent": Color("#ffb347"),
		"hat": &"Hat_Cap", "hat_color": Color("#23262b"), "beard": &"Beard_2", "hair_color": Color("#3a2c20"), "glasses": &"Glasses_Shades"}, &"arms_crossed")
	# modification bench on the east wall
	var bench := room.wall_prop("gun_bench", &"e", -0.2)
	var bp := room.prop_point(bench, "UsePoint", Vector3(0, 0, -0.8))
	_menu_point(room, &"bench", bp, &"bench", "Weapon modification bench", 2.0)
	# ammo shelf on the west wall
	var shelf := room.wall_prop("shelf_wall", &"w", 1.6)
	var sp := room.prop_point(shelf, "UsePoint", Vector3(0, 0, -0.9))
	_menu_point(room, &"shelf", sp, &"weapons", "Browse weapons and ammo", 1.9)
	# decoration: ammo crates, floor queue line, signs, windows
	room.add_solid(Vector3(-3.7, 0.3, -3.4), Vector3(0.9, 0.6, 0.6), Color("#5c6b3f"), 0.8)
	room.add_solid(Vector3(-3.7, 0.9, -3.4), Vector3(0.8, 0.5, 0.55), Color("#4d5a35"), 0.8)
	room.add_solid(Vector3(-2.8, 0.25, -3.5), Vector3(0.7, 0.5, 0.5), Color("#6b7a47"), 0.8)
	room.add_box(Vector3(0, 0.012, cz + 1.6), Vector3(5.2, 0.02, 0.07), Color("#ffb347"), 0.5, 0.0, 0.9)
	room.add_sign("GUNSMITH", room.wall_point(&"n", 0.0, 2.62, 0.09), InteriorRoom.wall_label_yaw(&"n"), Color("#ffb347"), 110, 0.0042)
	room.add_sign("AMMO  /  ARMOR  /  MODS", room.wall_point(&"w", 3.0, 2.35, 0.09), InteriorRoom.wall_label_yaw(&"w"), Color("#ff6a5a"), 56, 0.0034)
	room.add_window(&"s", -1.6, 3.0, 1.3, 1.0)
	room.add_light(Vector3(0, 2.5, -3.5), Color("#ffb347"), 1.1, 4.5)


# ================================================================================================= clothing store
static func build_clothing_store(room: InteriorRoom) -> void:
	var w := 9.0
	var d := 8.4
	room.build_shell(w, d, 3.2, {
		"floor_pattern": &"planks", "tile": 0.5, "floor_a": Color("#b9895b"), "floor_b": Color("#9d724a"), "grout": Color("#3b2a1c"),
		"wall": Color("#f0e6d4"), "wainscot": Color("#2f9c95"), "trim": Color("#33403f"), "ceiling": Color("#e7ddca"),
		"accent": Color("#e8795f"), "neon": Color("#ff3d9a"), "light": Color("#ffe6c4"), "light_energy": 1.6,
		"ambient": Color("#b9a99a"), "surface": &"wood", "door": Color("#e8795f"), "floor_rough": 0.5,
	})
	room.set_exit(-2.8)
	# counter nook north-east
	var cz := -d * 0.5 + 2.1
	var cx := 2.4
	var counter := room.add_prop("shop_counter", Vector3(cx, 0, cz), PI)
	room.add_solid(Vector3(4.25, 0.52, cz), Vector3(0.5, 1.04, 0.7), Color("#33403f"), 0.7)
	room.add_solid(Vector3(0.45, 1.1, cz - 1.0), Vector3(0.3, 2.2, 2.0), Color("#d9cdb8"), 0.85)
	room.add_solid(Vector3(0.55, 0.52, cz + 0.0), Vector3(0.3, 1.04, 0.7), Color("#33403f"), 0.7)
	_counter_point(room, counter, &"clothes", "Browse clothes")
	_make_clerk(room, counter, &"clothing_store", {"body": &"B", "hair": 4, "hair_color": Color("#2a1c14"), "shirt": Color("#e8795f"), "pants": Color("#25324d"),
		"accent": Color("#ff3d9a"), "glasses": &"Glasses_Round", "skin": Color("#b57e57")}, &"relaxed")
	# racks + mannequin + fitting mirror
	var rack_a := room.add_prop("clothing_rack", Vector3(-2.2, 0, -1.4), PI)
	var rack_b := room.add_prop("clothing_rack", Vector3(0.9, 0, 0.3), PI)
	for r in [rack_a, rack_b]:
		_menu_point(room, StringName("rack_%d" % room.points.size()), room.prop_point(r, "UsePoint", Vector3(0, 0, -0.9)), &"clothes", "Browse clothes", 1.8)
	var mirror := room.wall_prop("mirror_wall", &"w", -0.4)
	_menu_point(room, &"mirror", room.prop_point(mirror, "UsePoint", Vector3(0, 0, -0.9)), &"clothes", "Try on clothes", 2.0)
	var mann := room.add_prop("mannequin", Vector3(-3.6, 0, 2.5), -PI * 0.5)
	InteriorRoom.recolor(mann, {"Shirt": Color("#e0b04a"), "Pants": Color("#25324d")})
	room.add_solid(Vector3(3.1, 0.22, 1.8), Vector3(1.6, 0.44, 0.7), Color("#7b4b7a"), 0.9)       # waiting bench
	room.add_box(Vector3(3.1, 0.52, 1.8), Vector3(1.6, 0.16, 0.7), Color("#e8795f"), 0.8)
	room.add_sign("THREADS", room.wall_point(&"n", -2.2, 2.55, 0.09), InteriorRoom.wall_label_yaw(&"n"), Color("#ff3d9a"), 110, 0.0042)
	room.add_sign("NEW SEASON", room.wall_point(&"e", 1.4, 2.3, 0.09), InteriorRoom.wall_label_yaw(&"e"), Color("#34e0ff"), 56, 0.0034)
	room.add_window(&"s", 1.2, 3.0, 1.3, 1.0)
	room.add_light(Vector3(-3.0, 2.4, 0.5), Color("#ff9ac8"), 0.9, 4.5)


# ================================================================================================= barber
static func build_barber(room: InteriorRoom) -> void:
	var w := 7.6
	var d := 7.2
	room.build_shell(w, d, 3.1, {
		"floor_pattern": &"checker", "tile": 0.6, "floor_a": Color("#ece8de"), "floor_b": Color("#2a2d33"), "grout": Color("#15171a"),
		"wall": Color("#e8dfd0"), "wainscot": Color("#b8403a"), "trim": Color("#23262b"), "ceiling": Color("#d9d1c3"),
		"accent": Color("#34e0ff"), "neon": Color("#ff3d4a"), "light": Color("#fff0d6"), "light_energy": 1.5,
		"ambient": Color("#b2a79a"), "surface": &"concrete", "door": Color("#3a7bff"), "floor_rough": 0.35,
	})
	room.set_exit(2.2)
	var m1 := room.wall_prop("mirror_wall", &"n", -1.5)
	var m2 := room.wall_prop("mirror_wall", &"n", 1.5)
	var c1 := room.add_prop("barber_chair", Vector3(-1.5, 0, -d * 0.5 + 2.1), 0.0)
	var c2 := room.add_prop("barber_chair", Vector3(1.5, 0, -d * 0.5 + 2.1), 0.0)
	for c in [c1, c2]:
		_menu_point(room, StringName("chair_%d" % room.points.size()), room.prop_point(c, "UsePoint", Vector3(0, 0, -1.0)), &"barber", "Get a haircut", 1.9)
	for m in [m1, m2]:
		_menu_point(room, StringName("mirror_%d" % room.points.size()), room.prop_point(m, "UsePoint", Vector3(0, 0, -0.9)) + Vector3(0, 0, 0.0), &"barber", "Choose a new look", 1.6)
	# barber stands next to chair 2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("barber_clerk")
	var v: Dictionary = CharacterVariants.shop_staff(rng)
	v["body"] = &"A"
	v["shirt"] = Color("#f2f0ea")
	v["pants"] = Color("#15171a")
	v["accent"] = Color("#b8403a")
	v["hair"] = 6
	v["hair_color"] = Color("#15171a")
	v["beard"] = &"Beard_1"
	v["hat"] = &""
	v["glasses"] = &""
	room.clerk = ShopClerk.create(room, Vector3(2.7, 0, -d * 0.5 + 2.1), -PI * 0.5 + 0.4, &"barber", v, &"relaxed")
	room.info["robbable"] = false
	room.wall_prop("shelf_wall", &"w", -0.4)
	room.add_solid(Vector3(3.1, 0.22, 1.5), Vector3(0.6, 0.44, 2.0), Color("#23262b"), 0.9)    # waiting bench along the east wall
	room.add_box(Vector3(3.1, 0.5, 1.5), Vector3(0.6, 0.14, 2.0), Color("#b8403a"), 0.7)
	room.add_sign("CLIP & CO", room.wall_point(&"n", 0.0, 2.65, 0.09), InteriorRoom.wall_label_yaw(&"n"), Color("#ff3d4a"), 100, 0.004)
	room.add_sign("BARBER", room.wall_point(&"w", 2.2, 2.3, 0.09), InteriorRoom.wall_label_yaw(&"w"), Color("#34e0ff"), 70, 0.0035)
	room.add_window(&"s", -1.2, 2.6, 1.3, 1.0)
	room.add_light(Vector3(0, 2.4, -2.5), Color("#fff0d6"), 1.0, 4.0)


# ================================================================================================= gas station shop
static func build_gas_station(room: InteriorRoom) -> void:
	var w := 8.0
	var d := 6.8
	room.build_shell(w, d, 3.0, {
		"floor_pattern": &"checker", "tile": 0.8, "floor_a": Color("#e8eef0"), "floor_b": Color("#8fbcbd"), "grout": Color("#1c2a2c"),
		"wall": Color("#f1f1ea"), "wainscot": Color("#d93a3a"), "trim": Color("#2a2d33"), "ceiling": Color("#e6e6dc"),
		"accent": Color("#f2cf3a"), "neon": Color("#34e0ff"), "light": Color("#f4fbff"), "light_energy": 1.7,
		"ambient": Color("#bfc7c9"), "surface": &"concrete", "door": Color("#d93a3a"), "floor_rough": 0.3,
	})
	room.set_exit(2.4)
	var cz := -d * 0.5 + 2.0
	var cx := 2.0
	var counter := room.add_prop("shop_counter", Vector3(cx, 0, cz), PI)
	room.add_solid(Vector3(3.76, 0.52, cz), Vector3(0.5, 1.04, 0.7), Color("#2a2d33"), 0.7)
	room.add_solid(Vector3(0.45, 1.1, cz - 0.95), Vector3(0.3, 2.2, 1.9), Color("#d8d8d0"), 0.85)
	room.add_solid(Vector3(0.55, 0.52, cz), Vector3(0.3, 1.04, 0.7), Color("#2a2d33"), 0.7)
	_counter_point(room, counter, &"food", "Buy snacks and drinks")
	_make_clerk(room, counter, &"gas_station", {"body": &"A", "hair": 1, "shirt": Color("#d93a3a"), "pants": Color("#25324d"), "accent": Color("#f2cf3a"),
		"hat": &"Hat_Cap", "hat_color": Color("#d93a3a"), "beard": &"", "glasses": &""}, &"hands_pockets")
	var s1 := room.wall_prop("shelf_wall", &"w", -1.0)
	var s2 := room.wall_prop("shelf_wall", &"w", 1.2)
	var s3 := room.wall_prop("shelf_wall", &"n", -2.3)
	for s in [s1, s2, s3]:
		_menu_point(room, StringName("shelf_%d" % room.points.size()), room.prop_point(s, "UsePoint", Vector3(0, 0, -0.9)), &"food", "Browse snacks and drinks", 1.9)
	# drinks fridge on the east wall (emissive glass)
	room.add_solid(Vector3(w * 0.5 - 0.4, 1.0, 1.3), Vector3(0.7, 2.0, 2.2), Color("#c9d3d6"), 0.4, 0.3)
	room.add_box(Vector3(w * 0.5 - 0.75, 1.0, 1.3), Vector3(0.04, 1.7, 1.9), Color("#7fc9e6"), 0.2, 0.0, 0.55)
	_menu_point(room, &"fridge", Vector3(w * 0.5 - 1.6, 0, 1.3), &"food", "Cold drinks", 1.7)
	room.add_sign("HALCYON FUEL", room.wall_point(&"n", 1.4, 2.5, 0.09), InteriorRoom.wall_label_yaw(&"n"), Color("#34e0ff"), 96, 0.0038)
	room.add_sign("OPEN 24 HOURS", room.wall_point(&"w", 3.0, 2.3, 0.09), InteriorRoom.wall_label_yaw(&"w"), Color("#f2cf3a"), 56, 0.0034)
	room.add_window(&"s", -1.4, 2.8, 1.3, 1.0)
	room.add_light(Vector3(-2.0, 2.4, 0.5), Color("#cfeaff"), 0.8, 4.5)


# ================================================================================================= scuba shop
static func build_scuba_shop(room: InteriorRoom) -> void:
	var w := 8.4
	var d := 7.2
	room.build_shell(w, d, 3.2, {
		"floor_pattern": &"planks", "tile": 0.5, "floor_a": Color("#8f7455"), "floor_b": Color("#7a6146"), "grout": Color("#2a1f15"),
		"wall": Color("#d4ecee"), "wainscot": Color("#1c6f7a"), "trim": Color("#16323a"), "ceiling": Color("#c1dde0"),
		"accent": Color("#34e0ff"), "neon": Color("#34e0ff"), "light": Color("#e6fbff"), "light_energy": 1.6,
		"ambient": Color("#a5c3c8"), "surface": &"wood", "door": Color("#2f9c95"), "floor_rough": 0.5,
	})
	room.set_exit(-2.4)
	var cz := -d * 0.5 + 2.1
	var cx := 2.3
	var counter := room.add_prop("shop_counter", Vector3(cx, 0, cz), PI)
	room.add_solid(Vector3(4.0, 0.52, cz), Vector3(0.4, 1.04, 0.7), Color("#16323a"), 0.7)
	room.add_solid(Vector3(0.7, 1.1, cz - 1.0), Vector3(0.3, 2.2, 2.0), Color("#bcd9dc"), 0.85)
	room.add_solid(Vector3(0.76, 0.52, cz), Vector3(0.3, 1.04, 0.7), Color("#16323a"), 0.7)
	_counter_point(room, counter, &"scuba", "Browse diving gear")
	_make_clerk(room, counter, &"scuba_shop", {"body": &"B", "hair": 3, "hair_color": Color("#d6b46a"), "shirt": Color("#2f9c95"), "pants": Color("#25324d"),
		"accent": Color("#34e0ff"), "skin": Color("#d9a77c"), "glasses": &"", "hat": &""}, &"relaxed")
	var r1 := room.wall_prop("scuba_rack", &"w", -0.4)
	var r2 := room.wall_prop("scuba_rack", &"w", 1.8)
	for r in [r1, r2]:
		_menu_point(room, StringName("rack_%d" % room.points.size()), room.prop_point(r, "UsePoint", Vector3(0, 0, -0.9)), &"scuba", "Browse diving gear", 1.9)
	var sh := room.wall_prop("shelf_wall", &"e", 1.6)
	_menu_point(room, &"shelf", room.prop_point(sh, "UsePoint", Vector3(0, 0, -0.9)), &"scuba", "Browse diving gear", 1.9)
	# aquarium on the north wall
	room.add_solid(Vector3(-2.4, 0.45, -d * 0.5 + 0.5), Vector3(2.2, 0.9, 0.7), Color("#16323a"), 0.7)
	room.add_box(Vector3(-2.4, 1.45, -d * 0.5 + 0.5), Vector3(2.0, 1.0, 0.55), Color("#46c8e8"), 0.1, 0.0, 0.9, 0.55)
	for i in 5:
		var fx := -3.1 + float(i) * 0.35
		room.add_box(Vector3(fx, 1.2 + float(i % 3) * 0.22, -d * 0.5 + 0.5), Vector3(0.14, 0.07, 0.04), Color("#ff9a3c") if i % 2 == 0 else Color("#ffe27a"), 0.6, 0.0, 0.5)
	room.add_light(Vector3(-2.4, 1.9, -d * 0.5 + 1.2), Color("#46c8e8"), 0.9, 3.5)
	room.add_sign("REEF DIVE", room.wall_point(&"n", 1.6, 2.6, 0.09), InteriorRoom.wall_label_yaw(&"n"), Color("#34e0ff"), 110, 0.0042)
	room.add_sign("TANKS  /  MASKS  /  CHUTES", room.wall_point(&"e", -1.2, 2.3, 0.09), InteriorRoom.wall_label_yaw(&"e"), Color("#7be495"), 52, 0.0032)
	room.add_window(&"s", 1.4, 3.0, 1.3, 1.0)
