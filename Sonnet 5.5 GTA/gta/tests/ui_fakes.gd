class_name UiFakes
extends RefCounted
## Test doubles for the UI module: a fake player (health, weapons, stance...), fake vehicles and a fake WorldLayout so the
## HUD / minimap / map can be exercised and screenshotted before the real modules exist. NEVER used by the game itself.


## Fills WorldLayout with a believable fake map when it is still empty. Returns true if fake data was installed.
static func fill_world() -> bool:
	if not WorldLayout.roads.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	WorldLayout.districts = [
		{"id": GC.D_DOWNTOWN, "name": "Downtown", "rect": Rect2(-110, -80, 210, 200), "color": Color("#34e0ff")},
		{"id": GC.D_RESIDENTIAL, "name": "Westbrook", "rect": Rect2(-300, -250, 200, 335), "color": Color("#ffb347")},
		{"id": GC.D_INDUSTRIAL, "name": "Ironworks", "rect": Rect2(110, -60, 190, 140), "color": Color("#ff6a4d")},
		{"id": GC.D_WATERFRONT, "name": "Docklands", "rect": Rect2(-300, 90, 210, 110), "color": Color("#4d8bff")},
		{"id": GC.D_PARK, "name": "Highpark", "rect": Rect2(-100, -200, 140, 120), "color": Color("#7be495")},
		{"id": GC.D_AIRPORT, "name": "Halcyon Airfield", "rect": Rect2(75, 85, 220, 100), "color": Color("#9bb4ff")},
		{"id": GC.D_BEACH, "name": "Sunset Beach", "rect": Rect2(-80, 140, 160, 60), "color": Color("#ffd35a")},
	]
	WorldLayout.water_polys = [PackedVector2Array([Vector2(-320, 192), Vector2(-200, 205), Vector2(-80, 180), Vector2(0, 196), Vector2(120, 178), Vector2(230, 200), Vector2(320, 190), Vector2(320, 320), Vector2(-320, 320)])]
	WorldLayout.nature_zones = [
		{"poly": PackedVector2Array([Vector2(-100, -200), Vector2(40, -200), Vector2(40, -80), Vector2(-100, -80)]), "kind": &"park", "density": 0.5},
		{"poly": PackedVector2Array([Vector2(40, -250), Vector2(300, -250), Vector2(300, -80), Vector2(40, -80)]), "kind": &"hills", "density": 0.3},
	]
	var roads: Array = []
	# downtown grid
	for x in [-110, -40, 30, 100]:
		roads.append({"points": PackedVector2Array([Vector2(x, -80), Vector2(x, 120)]), "width": 10.0, "kind": &"street"})
	for z in [-80, -10, 60, 120]:
		roads.append({"points": PackedVector2Array([Vector2(-110, z), Vector2(100, z)]), "width": 10.0, "kind": &"street"})
	# arterial ring
	roads.append({"points": PackedVector2Array([Vector2(-210, -150), Vector2(210, -150), Vector2(210, 150), Vector2(-210, 150), Vector2(-210, -150)]), "width": 16.0, "kind": &"arterial"})
	# coastal road + hill switchback + residential streets
	roads.append({"points": PackedVector2Array([Vector2(-290, 160), Vector2(-150, 170), Vector2(0, 165), Vector2(150, 160), Vector2(290, 165)]), "width": 12.0, "kind": &"street"})
	roads.append({"points": PackedVector2Array([Vector2(100, -150), Vector2(150, -170), Vector2(130, -200), Vector2(200, -210), Vector2(170, -240)]), "width": 6.0, "kind": &"hill"})
	for i in 5:
		var z2 := -220.0 + i * 60.0
		roads.append({"points": PackedVector2Array([Vector2(-290, z2), Vector2(-110, z2)]), "width": 7.0, "kind": &"street"})
	for i in 3:
		var x2 := -250.0 + i * 70.0
		roads.append({"points": PackedVector2Array([Vector2(x2, -230), Vector2(x2, 80)]), "width": 7.0, "kind": &"street"})
	WorldLayout.roads = roads
	var b: Array = []
	for i in 140:
		var d: Dictionary = WorldLayout.districts[rng.randi() % 3]
		var r: Rect2 = d["rect"]
		var w := rng.randf_range(10.0, 28.0)
		var h := rng.randf_range(10.0, 28.0)
		var x3 := rng.randf_range(r.position.x + 6.0, r.end.x - w - 6.0)
		var z3 := rng.randf_range(r.position.y + 6.0, r.end.y - h - 6.0)
		b.append({"rect": Rect2(x3, z3, w, h), "height": rng.randf_range(8.0, 70.0) if d["id"] == GC.D_DOWNTOWN else rng.randf_range(6.0, 16.0), "kind": &"office"})
	WorldLayout.building_footprints = b
	WorldLayout.piers = [{"rect": Rect2(-230, 170, 10, 44), "height": 1.5}, {"rect": Rect2(-190, 172, 10, 38), "height": 1.5}]
	WorldLayout.airport = {"runway_start": Vector3(110, 0, 140), "runway_end": Vector3(250, 0, 140), "runway_width": 18.0,
		"taxiway": [Vector3(110, 0, 120), Vector3(250, 0, 120)], "apron": Rect2(180, 100, 80, 20)}
	var locs := {}
	var defs := {
		&"player_spawn": [Vector3(0, 1, 20), &"spawn"], &"hospital": [Vector3(-60, 0, -40), &"service"], &"police_station": [Vector3(40, 0, -30), &"service"],
		&"weapon_shop": [Vector3(-20, 0, 30), &"shop"], &"garage_shop": [Vector3(60, 0, 20), &"shop"], &"clothing_store": [Vector3(-70, 0, 70), &"shop"],
		&"barber": [Vector3(10, 0, 90), &"shop"], &"gas_station": [Vector3(120, 0, 30), &"shop"], &"dealer_lot": [Vector3(70, 0, 70), &"shop"],
		&"safehouse": [Vector3(-180, 0, -60), &"safehouse"], &"airport_runway_start": [Vector3(110, 0, 140), &"airport"], &"helipad_downtown": [Vector3(-10, 0, -50), &"heli"],
		&"dock_boat_spawn": [Vector3(-210, 0, 180), &"dock"], &"scuba_shop": [Vector3(-150, 0, 150), &"shop"], &"train_station_a": [Vector3(-90, 0, 100), &"transit"],
		&"train_station_b": [Vector3(180, 0, -20), &"transit"], &"shooting_range": [Vector3(220, 0, 40), &"activity"], &"viewpoint": [Vector3(170, 40, -200), &"poi"],
		&"parachute_peak": [Vector3(200, 55, -215), &"poi"], &"stunt_jump_1": [Vector3(-30, 0, 160), &"stunt"], &"taxi_stand": [Vector3(20, 0, 10), &"transit"],
	}
	for id in defs:
		locs[id] = {"pos": defs[id][0], "yaw": 0.0, "radius": 8.0, "kind": defs[id][1], "name": String(id).replace("_", " ").capitalize()}
	WorldLayout.locations = locs
	WorldLayout.built = true
	return true


class FakeWeapons extends Node:
	var current_id: StringName = &"fists"
	var inventory: Dictionary = {}
	var is_aiming := false
	var is_reloading := false
	var mag := 12
	var reserve := 84
	var scope_active := false
	var current_spread := 2.0
	var reload_progress := 0.0

	func setup(_c: Node) -> void:
		pass

	func get_ammo_in_mag() -> int:
		return mag

	func get_ammo_reserve() -> int:
		return reserve

	func get_weapon_ids() -> Array:
		return inventory.keys()

	func equip(id: StringName) -> bool:
		if not inventory.has(id):
			return false
		current_id = id
		return true

	func get_current_def() -> Dictionary:
		return {"spread": current_spread, "reload_time": 2.0}


class FakePlayer extends CharacterBase:
	var stance: StringName = &"stand"
	var stamina := 1.0
	var lung := 1.0
	var is_underwater := false
	var is_parachuting := false
	var noise_level := 0.3

	func _ready() -> void:
		super._ready()
		add_to_group(GC.G_PLAYER)
		faction = GC.F_PLAYER


class FakeVehicle extends RigidBody3D:
	var vclass: StringName = GC.VC_CAR
	var display_name := "Sports Coupe"
	var max_health := 1000.0
	var health := 800.0
	var headlights_on := true
	var siren_on := false
	var input_handbrake := false
	var input_throttle := 0.6
	var is_player_owned := false
	var kmh := 87.0
	var rpm01 := 0.55
	var gear := 3

	func _init() -> void:
		freeze = true

	func get_speed_kmh() -> float:
		return kmh

	func get_forward_speed() -> float:
		return kmh / 3.6


## Creates a fake armed player in `parent` and registers it as Game.player.
static func make_player(parent: Node, pos: Vector3 = Vector3(0, 0, 20)) -> FakePlayer:
	var p := FakePlayer.new()
	p.name = "FakePlayer"
	parent.add_child(p)
	p.global_position = pos
	p.armor = 60.0
	var w := FakeWeapons.new()
	w.name = "FakeWeapons"
	p.add_child(w)
	w.setup(p)
	p.weapons = w
	w.inventory = {&"fists": {"mag": 0, "reserve": 0}, &"knife": {"mag": 0, "reserve": 0}, &"pistol": {"mag": 12, "reserve": 84}, &"revolver": {"mag": 6, "reserve": 30},
		&"smg": {"mag": 30, "reserve": 180}, &"shotgun_pump": {"mag": 8, "reserve": 32}, &"rifle_assault": {"mag": 30, "reserve": 240}, &"carbine": {"mag": 30, "reserve": 150},
		&"sniper": {"mag": 5, "reserve": 25}, &"rocket_launcher": {"mag": 1, "reserve": 4}, &"grenade": {"mag": 0, "reserve": 6}}
	w.current_id = &"pistol"
	Game.player = p
	return p


static func make_police(parent: Node, center: Vector3, count: int = 6) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in count:
		var n := FakeVehicle.new()
		n.name = "FakePolice%d" % i
		n.vclass = GC.VC_HELI if i == 0 else GC.VC_CAR
		n.add_to_group(GC.G_POLICE)
		parent.add_child(n)
		n.global_position = center + Vector3(rng.randf_range(-90, 90), 0, rng.randf_range(-90, 90))
		out.append(n)
	return out
