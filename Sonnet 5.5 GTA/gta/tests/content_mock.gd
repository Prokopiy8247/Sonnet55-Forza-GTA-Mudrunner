class_name ContentMock
extends RefCounted
## Mock layout + mini world used by the world-content tests / screenshots while (or instead of) the real WorldRoot.
## fill() fills WorldLayout.lots / furniture / nature_zones / locations with a small downtown + houses + industrial strip;
## make_world(main) builds ground, roads, sun and sky around it. Real WorldLayout data wins (fill is skipped when present).

const STREET_HALF := 7.0
const SIDEWALK := 3.0


static func fill(force := false) -> void:
	if not force and WorldLayout.lots.size() > 0:
		return
	WorldLayout.lots = []
	WorldLayout.furniture = []
	WorldLayout.nature_zones = []
	WorldLayout.signals = []
	WorldLayout.roads = [
		{"points": PackedVector2Array([Vector2(-300, 0), Vector2(300, 0)]), "width": 14.0, "kind": &"street"},
		{"points": PackedVector2Array([Vector2(0, -300), Vector2(0, 300)]), "width": 14.0, "kind": &"street"},
		{"points": PackedVector2Array([Vector2(-300, 60), Vector2(300, 60)]), "width": 8.0, "kind": &"street"},
	]
	var id := 0
	var edge := STREET_HALF + SIDEWALK
	# --- downtown: east half of the main street, both sides
	var kinds_n: Array = [[&"office", 14, 3], [&"office", 10, 0], [&"apartment", 8, 1], [&"shop", 3, 2], [&"office", 9, 3]]
	var kinds_s: Array = [[&"shop", 2, 2], [&"office", 19, 3], [&"apartment", 7, 0], [&"parking", 5, 3], [&"apartment", 6, 1]]
	var widths: Array = [24.0, 28.0, 20.0, 24.0, 24.0]
	var x := edge + 2.0
	for i in 5:
		var w: float = widths[i]
		WorldLayout.lots.append({"id": id, "rect": Rect2(x, -edge - 26.0, w, 26.0), "yaw": PI, "district": GC.D_DOWNTOWN,
			"kind": kinds_n[i][0], "landmark": &"", "floors": kinds_n[i][1], "height": kinds_n[i][1] * 3.6, "palette": kinds_n[i][2]})
		id += 1
		WorldLayout.lots.append({"id": id, "rect": Rect2(x, edge, w, 26.0), "yaw": 0.0, "district": GC.D_DOWNTOWN,
			"kind": kinds_s[i][0], "landmark": &"", "floors": kinds_s[i][1], "height": kinds_s[i][1] * 3.6, "palette": kinds_s[i][2]})
		id += 1
		x += w + 3.0
	# --- west half: low-rise shops and apartments
	x = -edge - 2.0
	var kinds_w: Array = [[&"apartment", 5, 2], [&"shop", 2, 0], [&"apartment", 6, 1], [&"shop", 3, 3]]
	for i in 4:
		var w2: float = 22.0
		WorldLayout.lots.append({"id": id, "rect": Rect2(x - w2, -edge - 22.0, w2, 22.0), "yaw": PI, "district": GC.D_DOWNTOWN,
			"kind": kinds_w[i][0], "landmark": &"", "floors": kinds_w[i][1], "height": kinds_w[i][1] * 3.6, "palette": kinds_w[i][2]})
		id += 1
		WorldLayout.lots.append({"id": id, "rect": Rect2(x - w2, edge, w2, 22.0), "yaw": 0.0, "district": GC.D_DOWNTOWN,
			"kind": kinds_w[(i + 1) % 4][0], "landmark": &"", "floors": kinds_w[(i + 1) % 4][1], "height": kinds_w[(i + 1) % 4][1] * 3.6, "palette": kinds_w[(i + 1) % 4][2]})
		id += 1
		x -= w2 + 2.0
	# --- houses along the residential street z = 60 (south side faces north, north side faces south)
	var hx := -250.0
	for i in 10:
		WorldLayout.lots.append({"id": id, "rect": Rect2(hx, 60.0 + 8.0, 22.0, 26.0), "yaw": 0.0, "district": GC.D_RESIDENTIAL,
			"kind": &"house", "landmark": &"", "floors": 1, "height": 6.0, "palette": i % 4})
		id += 1
		WorldLayout.lots.append({"id": id, "rect": Rect2(hx, 60.0 - 8.0 - 26.0, 22.0, 26.0), "yaw": PI, "district": GC.D_RESIDENTIAL,
			"kind": &"house", "landmark": &"", "floors": 1, "height": 6.0, "palette": (i + 2) % 4})
		id += 1
		hx += 25.0
	# --- industrial block + hangar
	WorldLayout.lots.append({"id": id, "rect": Rect2(90.0, 80.0, 44.0, 34.0), "yaw": 0.0, "district": GC.D_INDUSTRIAL, "kind": &"warehouse", "landmark": &"", "floors": 2, "height": 9.0, "palette": 3})
	id += 1
	WorldLayout.lots.append({"id": id, "rect": Rect2(140.0, 80.0, 56.0, 56.0), "yaw": 0.0, "district": GC.D_INDUSTRIAL, "kind": &"factory", "landmark": &"", "floors": 2, "height": 9.0, "palette": 0})
	id += 1
	WorldLayout.lots.append({"id": id, "rect": Rect2(90.0, 120.0, 36.0, 28.0), "yaw": 0.0, "district": GC.D_INDUSTRIAL, "kind": &"warehouse", "landmark": &"", "floors": 1, "height": 6.0, "palette": 2})
	id += 1
	WorldLayout.lots.append({"id": id, "rect": Rect2(110.0, -120.0, 40.0, 30.0), "yaw": 0.0, "district": GC.D_AIRPORT, "kind": &"hangar", "landmark": &"", "floors": 2, "height": 12.0, "palette": 3})
	id += 1
	WorldLayout.locations[&"helipad_downtown"] = {"pos": Vector3(62.0, 70.0, edge + 13.0), "yaw": 0.0, "radius": 9.0, "kind": &"helipad", "name": "Downtown helipad"}
	_fill_furniture(edge)
	WorldLayout.nature_zones = [
		{"poly": PackedVector2Array([Vector2(-140, -150), Vector2(-20, -150), Vector2(-20, -40), Vector2(-140, -40)]), "kind": &"park", "density": 0.5},
		{"poly": PackedVector2Array([Vector2(60, -260), Vector2(250, -260), Vector2(250, -150), Vector2(60, -150)]), "kind": &"hills", "density": 0.7},
		{"poly": PackedVector2Array([Vector2(-260, -280), Vector2(-150, -280), Vector2(-150, -170), Vector2(-260, -170)]), "kind": &"forest", "density": 0.8},
		{"poly": PackedVector2Array([Vector2(-60, 150), Vector2(60, 150), Vector2(60, 200), Vector2(-60, 200)]), "kind": &"beach_palms", "density": 0.5},
		{"poly": PackedVector2Array([Vector2(12, 11), Vector2(150, 11), Vector2(150, 16), Vector2(12, 16)]), "kind": &"roadside", "density": 0.5},
	]
	for i in 10:
		WorldLayout.furniture.append({"kind": &"palm", "pos": Vector3(-30 + i * 6.0, 0, 175), "yaw": 0.0, "signal_id": -1})
		WorldLayout.furniture.append({"kind": &"tree_street", "pos": Vector3(14 + i * 9.0, 0, -11.0), "yaw": 0.0, "signal_id": -1})
	WorldLayout.built = true


static func _fill_furniture(edge: float) -> void:
	var F := WorldLayout.furniture
	var e := STREET_HALF + 1.0
	WorldLayout.signals = [{"id": 0, "pos": Vector3.ZERO, "cycle": 20.0, "yellow": 2.0, "offset": 0.0}]
	for xx in range(-150, 151, 28):
		F.append({"kind": &"lamp", "pos": Vector3(xx, 0, -e), "yaw": PI, "signal_id": -1})
		F.append({"kind": &"lamp", "pos": Vector3(xx + 14, 0, e), "yaw": 0.0, "signal_id": -1})
	for zz in range(-150, 151, 28):
		if absf(zz) < 14.0:
			continue
		F.append({"kind": &"lamp", "pos": Vector3(-e, 0, zz), "yaw": -PI * 0.5, "signal_id": -1})
		F.append({"kind": &"lamp", "pos": Vector3(e, 0, zz + 14), "yaw": PI * 0.5, "signal_id": -1})
	var sc := STREET_HALF + 1.4
	F.append({"kind": &"signal", "pos": Vector3(sc, 0, sc), "yaw": PI, "signal_id": 0})
	F.append({"kind": &"signal", "pos": Vector3(-sc, 0, -sc), "yaw": 0.0, "signal_id": 0})
	F.append({"kind": &"signal", "pos": Vector3(sc, 0, -sc), "yaw": -PI * 0.5, "signal_id": 0})
	F.append({"kind": &"signal", "pos": Vector3(-sc, 0, sc), "yaw": PI * 0.5, "signal_id": 0})
	F.append({"kind": &"sign_stop", "pos": Vector3(60, 0, -e - 1.0), "yaw": PI, "signal_id": -1})
	F.append({"kind": &"sign_speed", "pos": Vector3(80, 0, e + 1.0), "yaw": 0.0, "signal_id": -1})
	for xx in range(20, 140, 40):
		F.append({"kind": &"hydrant", "pos": Vector3(xx, 0, -e - 0.6), "yaw": PI, "signal_id": -1})
		F.append({"kind": &"bench", "pos": Vector3(xx + 10, 0, e + 1.4), "yaw": 0.0, "signal_id": -1})
		F.append({"kind": &"bin", "pos": Vector3(xx + 12.5, 0, e + 1.4), "yaw": 0.0, "signal_id": -1})
		F.append({"kind": &"utility_box", "pos": Vector3(xx + 5, 0, -e - 1.6), "yaw": PI, "signal_id": -1})
		F.append({"kind": &"mailbox", "pos": Vector3(xx + 3, 0, e + 0.9), "yaw": 0.0, "signal_id": -1})
	for i in 10:
		F.append({"kind": &"bollard", "pos": Vector3(14 + i * 2.2, 0, -e + 0.3), "yaw": 0.0, "signal_id": -1})
		F.append({"kind": &"parking_meter", "pos": Vector3(-20 - i * 4.5, 0, e + 0.5), "yaw": 0.0, "signal_id": -1})
	for i in 14:
		F.append({"kind": &"cone", "pos": Vector3(90 + i * 1.2, 0, 1.0 + (i % 3) * 1.4), "yaw": float(i) * 0.7, "signal_id": -1})
	for i in 6:
		F.append({"kind": &"barrier", "pos": Vector3(120 + i * 1.8, 0, -3.0), "yaw": PI * 0.5 + float(i) * 0.1, "signal_id": -1})
	F.append({"kind": &"bus_stop", "pos": Vector3(-34, 0, e + 1.2), "yaw": 0.0, "signal_id": -1})
	for i in 8:
		F.append({"kind": &"fence", "pos": Vector3(86.0, 0, 76.0 - 3.0 * 0 + i * 3.0 - 24.0), "yaw": PI * 0.5, "signal_id": -1})
	F.append({"kind": &"billboard", "pos": Vector3(40, 0, 100), "yaw": 0.0, "signal_id": -1})
	F.append({"kind": &"billboard", "pos": Vector3(-60, 0, -90), "yaw": PI, "signal_id": -1})

static func make_world(main: Node, with_env := true) -> Node3D:
	var world := Node3D.new()
	world.name = "MockWorld"
	main.add_child(world)
	if is_instance_valid(Game.world) and Game.world != world:
		# the real WorldRoot (terrain, roads) also exists in the scene: hide it while the mock city is shown
		Game.world.visible = false
	# ground + roads
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	ground.mesh = pm
	ground.position = Vector3(0, -0.03, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#8a9a72")
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = GC.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(700, 1, 700)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	world.add_child(body)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("#2b2e33")
	asphalt.roughness = 0.9
	var walk := StandardMaterial3D.new()
	walk.albedo_color = Color("#bdb8ad")
	walk.roughness = 1.0
	for r in WorldLayout.roads:
		var pts: PackedVector2Array = r["points"]
		var wdt: float = r["width"]
		var a := pts[0]
		var b := pts[pts.size() - 1]
		var len_ := a.distance_to(b)
		var mid := (a + b) * 0.5
		var horizontal := absf(b.y - a.y) < 0.01
		var strip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(len_, 0.04, wdt) if horizontal else Vector3(wdt, 0.04, len_)
		strip.mesh = bm
		strip.material_override = asphalt
		strip.position = Vector3(mid.x, 0.0, mid.y)
		world.add_child(strip)
		for side in [-1.0, 1.0]:
			var sw := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(len_, 0.16, SIDEWALK) if horizontal else Vector3(SIDEWALK, 0.16, len_)
			sw.mesh = sm
			sw.material_override = walk
			var off: float = side * (wdt * 0.5 + SIDEWALK * 0.5)
			sw.position = Vector3(mid.x, 0.04, mid.y + off) if horizontal else Vector3(mid.x + off, 0.04, mid.y)
			world.add_child(sw)
	if with_env and Util.find_first_of_class(main, "WorldEnvironment") == null:
		_make_env(world)
	return world


static func _make_env(parent: Node) -> void:
	var tod: float = Game.time_of_day
	var night := clampf(smoothstep(19.0, 21.5, tod) + (1.0 - smoothstep(4.5, 6.5, tod)), 0.0, 1.0)
	var day := 1.0 - night
	var sun := DirectionalLight3D.new()
	sun.name = "MockSun"
	var elev := sin((tod - 6.0) / 12.0 * PI)
	var el_deg := clampf(elev * 65.0, -10.0, 65.0)
	if tod < 6.0 or tod > 18.0:
		el_deg = clampf(elev * 65.0, -30.0, 20.0)
	sun.rotation_degrees = Vector3(-maxf(el_deg, 4.0), -35.0 + (tod - 12.0) * 12.0, 0.0)
	var low := 1.0 - clampf(elev, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.62, 0.38), pow(low, 2.2))
	sun.light_energy = lerpf(0.05, 1.05, day) * (1.0 if el_deg > 0.0 else 0.0) + 0.04
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	parent.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	var top_day := Color("#4f8fd0")
	var hor_day := Color("#bcd7ea")
	var top_night := Color("#05070f")
	var hor_night := Color("#1a1f33")
	var dusk_h := Color("#ff9a5a")
	var dusk := clampf(1.0 - absf(elev) * 2.2, 0.0, 1.0) * day
	psm.sky_top_color = top_day.lerp(top_night, night)
	psm.sky_horizon_color = hor_day.lerp(hor_night, night).lerp(dusk_h, dusk * 0.7)
	psm.ground_horizon_color = psm.sky_horizon_color
	psm.ground_bottom_color = Color("#2a3038").lerp(Color("#05060a"), night)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = lerpf(0.35, 0.55, day)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = psm.sky_horizon_color
	env.fog_density = 0.0025
	var we := WorldEnvironment.new()
	we.environment = env
	we.name = "MockEnv"
	parent.add_child(we)
	Game.set_global(&"gta_night", night)
	Game.set_global(&"gta_sun_energy", day)
