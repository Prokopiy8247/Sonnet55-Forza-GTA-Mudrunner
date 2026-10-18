class_name PickupPlacer
extends RefCounted
## Fixed world pickups of Halcyon Bay (Systems-A): the table of ~35 cash stashes, health / armor / ammo points, weapon crates, parachutes
## and the scuba set, plus the three extra pickup kinds that the weapons module does not have (ParachutePickup, ScubaPickup, WeaponCrate).
## build_spots() resolves every spot against the REAL world (ray casts on the colliders, capsule clearance, road / water rejection) with a
## fixed seed, so the layout is identical on every run of the same map. EconomySystem spawns them and owns collection / respawn / saving.

const CASH_RESPAWN := 900.0           # stashes are restocked after 15 minutes
const CRATE_RESPAWN := 600.0          # weapon crates come back after 10 minutes
const SUPPLY_RESPAWN := 100.0         # health / armor / ammo
const GEAR_RESPAWN := 120.0           # parachute / scuba (the gear is only taken when you do not own it yet)
const SEED := 20260610

## Weapons a crate may hold (mid tier: neither a starter nor a heavy launcher).
const CRATE_WEAPONS: Array[StringName] = [&"revolver", &"smg", &"shotgun_pump", &"carbine", &"rifle_assault", &"shotgun_auto", &"rifle_marksman"]


# ================================================================================================ extra pickup kinds
class ParachutePickup extends PickupBase:
	func _init() -> void:
		super._init()
		kind = &"parachute"
		glow_color = Color(1.0, 0.72, 0.25)
		bob_height = 0.85
		spin_speed = 1.3

	func apply(character: Node) -> bool:
		if character.get("has_parachute") == null or character.get("has_parachute") == true:
			return false
		character.set("has_parachute", true)
		return true

	func get_label() -> String:
		return "Parachute equipped - press Space in mid-air to open it"


class ScubaPickup extends PickupBase:
	func _init() -> void:
		super._init()
		kind = &"scuba"
		glow_color = Color(0.25, 0.85, 1.0)
		bob_height = 0.8
		spin_speed = 1.2

	func _make_model() -> Node3D:
		if ModelLib.exists("props/scuba_gear"):
			var m := ModelLib.instance("props/scuba_gear")
			if m != null:
				return m
		_fallback = true
		return _fallback_model()

	func apply(character: Node) -> bool:
		if character.get("has_scuba") == null or character.get("has_scuba") == true:
			return false
		character.set("has_scuba", true)
		if character.get("lungs") != null and character.has_method("lung_capacity"):
			character.set("lungs", character.lung_capacity())
		return true

	func get_label() -> String:
		return "Scuba gear equipped - four times the breath underwater"


class WeaponCrate extends PickupBase:
	var last_weapon: StringName = &""

	func _init() -> void:
		super._init()
		kind = &"weapon_crate"
		glow_color = Color(0.3, 0.9, 1.0)
		bob_height = 0.75
		spin_speed = 1.1

	func _make_model() -> Node3D:
		if ModelLib.exists("props/pickup_weapon"):
			var m := ModelLib.instance("props/pickup_weapon")
			if m != null:
				m.scale = Vector3.ONE * 1.35
				return m
		_fallback = true
		return _fallback_model()

	func apply(character: Node) -> bool:
		var w = character.get("weapons")
		if w == null:
			return false
		var fresh: Array[StringName] = []
		for id in PickupPlacer.CRATE_WEAPONS:
			if WeaponDefs.has(id) and not w.has_weapon(id):
				fresh.append(id)
		var pool: Array[StringName] = fresh if not fresh.is_empty() else PickupPlacer.CRATE_WEAPONS
		var pick: StringName = pool[Game.rng.randi() % pool.size()]
		var def := WeaponDefs.get_def(pick)
		var rounds := int(def.get("mag_size", 10)) * 3
		var had: bool = w.has_weapon(pick)
		w.give_weapon(pick, rounds)
		if not had:
			w.equip(pick)
		last_weapon = pick
		amount = rounds
		return true

	func get_label() -> String:
		return "Weapon crate: %s" % String(WeaponDefs.get_def(last_weapon).get("name", String(last_weapon)))


# ================================================================================================ factory
## Creates the pickup node for a spot dictionary (not yet in the tree). Returns null for an unknown kind.
static func create(spot: Dictionary) -> PickupBase:
	var p: PickupBase = null
	var kind: StringName = spot["kind"]
	match kind:
		&"cash":
			p = CashPickup.new()
		&"health":
			p = HealthPickup.new()
		&"armor":
			p = ArmorPickup.new()
		&"ammo":
			var ap := AmmoPickup.new()
			ap.weapon_id = spot.get("weapon", &"")
			p = ap
		&"weapon":
			var wp := WeaponPickup.new()
			wp.weapon_id = spot.get("weapon", &"pistol")
			p = wp
		&"weapon_crate":
			p = WeaponCrate.new()
		&"parachute":
			p = ParachutePickup.new()
		&"scuba":
			p = ScubaPickup.new()
		_:
			push_warning("PickupPlacer.create: unknown kind '%s'" % kind)
			return null
	if int(spot.get("amount", 0)) > 0:
		p.amount = int(spot["amount"])
	p.respawn_time = float(spot.get("respawn", 0.0))
	return p


# ================================================================================================ spot table
## All spots of the map: [{id, kind, amount, pos, weapon?, respawn, group}]. `roof_cash` are extra stashes handed in by the ladder builder
## ([{id, pos, amount}]).
static func build_spots(roof_cash: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out: Array = []
	_services(out, rng)
	_gear(out, rng)
	_cash(out, rng, roof_cash)
	return out


static func _add(out: Array, id: String, kind: StringName, pos: Vector3, amount: int, respawn: float, group: String, weapon: StringName = &"") -> bool:
	if pos == Vector3.INF:
		push_warning("[PickupPlacer] no valid spot for '%s' (%s) - skipped" % [id, group])
		return false
	for s in out:
		if (s["pos"] as Vector3).distance_to(pos) < 1.8:
			pos += Vector3(2.2, 0.0, 0.0)             # never stack two pickups
			break
	var d := {"id": id, "kind": kind, "amount": amount, "pos": pos, "respawn": respawn, "group": group}
	if weapon != &"":
		d["weapon"] = weapon
	out.append(d)
	return true


static func _loc(id: StringName) -> Vector3:
	return WorldLayout.location_pos(id) if WorldLayout.has_location(id) else Vector3.INF


static func _near(center: Vector3, rng: RandomNumberGenerator, r_max: float = 4.0, opts: Dictionary = {}) -> Vector3:
	if center == Vector3.INF:
		return Vector3.INF
	var o := {"rng": rng, "max_r": r_max, "tries": 40}
	o.merge(opts, true)
	var p := InteractionUtil.find_walkable(center, o)
	if p != Vector3.INF:
		return p
	o["max_r"] = r_max * 2.2                       # second pass: wider ring
	o["tries"] = 80
	p = InteractionUtil.find_walkable(center, o)
	if p != Vector3.INF:
		return p
	o["max_r"] = r_max * 3.5                       # last pass: allow roads and steeper ground
	o["avoid_road"] = false
	o["min_up"] = minf(float(o.get("min_up", 0.8)), 0.6)
	return InteractionUtil.find_walkable(center, o)


## Top surface height at a location's x/z (roofs: the location y is only approximate), NAN when nothing is there.
static func _roof_y(loc: Vector3) -> float:
	var h := InteractionUtil.surface_at(loc.x, loc.z, loc.y + 8.0, loc.y - 8.0, GC.L_WORLD)
	return float((h["position"] as Vector3).y) if not h.is_empty() else NAN


static func _services(out: Array, rng: RandomNumberGenerator) -> void:
	var s := SUPPLY_RESPAWN
	# hospital front (the entrance forecourt faces +X)
	var h := _loc(&"hospital")
	_add(out, "hp_hospital_a", &"health", _near(h + Vector3(2.0, 0, 7.0), rng, 3.0, {"avoid_road": true}), 50, s, "supply")
	_add(out, "hp_hospital_b", &"health", _near(h + Vector3(2.0, 0, -7.0), rng, 3.0), 50, s, "supply")
	_add(out, "armor_hospital", &"armor", _near(h + Vector3(5.0, 0, 0.0), rng, 3.0), 50, s, "supply")
	# weapon shop front
	var ws := _loc(&"weapon_shop")
	_add(out, "ammo_weapon_shop", &"ammo", _near(ws + Vector3(5.0, 0, -1.5), rng, 3.0), 45, s, "supply")
	_add(out, "armor_weapon_shop", &"armor", _near(ws + Vector3(-5.0, 0, -1.5), rng, 3.0), 40, s, "supply")
	# police HQ forecourt
	_add(out, "armor_police", &"armor", _near(_loc(&"police_station") + Vector3(7.0, 0, -4.0), rng, 4.0), 60, s, "supply")
	# shooting range
	var sr := _loc(&"shooting_range")
	_add(out, "ammo_range", &"ammo", _near(sr + Vector3(-4.0, 0, 4.0), rng, 3.0), 60, s, "supply")
	_add(out, "weapon_range_pistol", &"weapon", _near(sr + Vector3(-4.0, 0, -2.0), rng, 3.0), 30, 120.0, "supply", &"pistol")
	# park, beach, safehouse
	_add(out, "hp_park", &"health", _near(_loc(&"park_center") + Vector3(4.0, 0, 3.0), rng, 4.0), 35, s, "supply")
	_add(out, "hp_beach", &"health", _near(_loc(&"beach_spawn") + Vector3(-8.0, 0, -4.0), rng, 4.0, {"avoid_road": true}), 30, s, "supply")
	_add(out, "hp_safehouse", &"health", _near(_loc(&"safehouse") + Vector3(5.0, 0, 5.0), rng, 4.0), 40, s, "supply")
	# viewpoint on the hills
	_add(out, "armor_viewpoint", &"armor", _near(_loc(&"viewpoint") + Vector3(3.0, 0, 2.0), rng, 3.0, {"min_up": 0.7}), 40, s, "supply")
	# construction site (work-zone cones in the furniture list) and industrial yards: the crates
	var site := _construction_site()
	if site != Vector3.INF:
		_add(out, "crate_construction", &"weapon_crate", _near(site, rng, 5.0, {"avoid_road": false}), 0, CRATE_RESPAWN, "crate")
		_add(out, "hp_construction", &"health", _near(site + Vector3(5.0, 0, 3.0), rng, 5.0, {"avoid_road": false}), 40, s, "supply")
	_add(out, "crate_industrial", &"weapon_crate", _near(_loc(&"district_center_industrial") + Vector3(18.0, 0, -14.0), rng, 10.0), 0, CRATE_RESPAWN, "crate")
	_add(out, "hp_garage", &"health", _near(_loc(&"garage_shop") + Vector3(-14.0, 0, 6.0), rng, 5.0), 40, s, "supply")
	_add(out, "crate_viewpoint", &"weapon_crate", _near(_loc(&"viewpoint") + Vector3(-9.0, 0, 6.0), rng, 5.0, {"min_up": 0.7}), 0, CRATE_RESPAWN, "crate")
	# airport hangar
	var hg := _loc(&"airport_hangar")
	_add(out, "crate_hangar", &"weapon_crate", _near(hg + Vector3(9.0, 0, 8.0), rng, 5.0), 0, CRATE_RESPAWN, "crate")
	_add(out, "ammo_hangar", &"ammo", _near(hg + Vector3(-9.0, 0, 8.0), rng, 5.0), 60, s, "supply")
	# docks: a crate between the cargo containers
	_add(out, "crate_docks", &"weapon_crate", _near(Vector3(-186.0, 0.1, 150.0), rng, 8.0), 0, CRATE_RESPAWN, "crate")


static func _gear(out: Array, rng: RandomNumberGenerator) -> void:
	var r := GEAR_RESPAWN
	_add(out, "chute_a", &"parachute", _near(_loc(&"parachute_pickup_a"), rng, 2.0, {"min_up": 0.6}), 0, r, "gear")
	_add(out, "chute_b", &"parachute", _near(_loc(&"parachute_pickup_b"), rng, 2.0), 0, r, "gear")
	# tower roofs: the downtown skyscraper (elevator) and the hospital roof
	var hd := _loc(&"helipad_downtown")
	if hd != Vector3.INF:
		_add(out, "chute_tower", &"parachute", _near(hd + Vector3(7.0, 0, -4.0), rng, 4.0, {"ref_y": _roof_y(hd), "up": 2.5, "down": 2.5, "avoid_road": false}), 0, r, "gear")
	var hh := _loc(&"helipad_hospital")
	if hh != Vector3.INF:
		_add(out, "chute_hospital", &"parachute", _near(hh + Vector3(5.0, 0, 2.0), rng, 4.0, {"ref_y": _roof_y(hh), "up": 2.5, "down": 2.5, "avoid_road": false}), 0, r, "gear")
	# scuba set on the beach right above the dive wreck
	var dw := _loc(&"diving_wreck")
	if dw != Vector3.INF:
		var shore := _shore_point(dw.x)
		_add(out, "scuba_beach", &"scuba", _near(shore, rng, 2.5, {"min_up": 0.5, "avoid_road": false}), 0, r, "gear")


static func _cash(out: Array, rng: RandomNumberGenerator, roof_cash: Array) -> void:
	var cr := CASH_RESPAWN
	# --- roofs reached by ladders
	for rc in roof_cash:
		_add(out, String(rc["id"]), &"cash", rc["pos"], int(rc["amount"]), cr, "roof")
	# --- helipad roofs (heli / parachute / elevator)
	var hd := _loc(&"helipad_downtown")
	if hd != Vector3.INF:
		_add(out, "cash_tower_roof", &"cash", _near(hd + Vector3(-6.0, 0, 5.0), rng, 4.0, {"ref_y": _roof_y(hd), "up": 2.5, "down": 2.5, "avoid_road": false}), 2500, cr, "roof")
	var hh := _loc(&"helipad_hospital")
	if hh != Vector3.INF:
		_add(out, "cash_hospital_roof", &"cash", _near(hh + Vector3(-4.0, 0, -3.0), rng, 4.0, {"ref_y": _roof_y(hh), "up": 2.5, "down": 2.5, "avoid_road": false}), 1500, cr, "roof")
	var pr := _anchor_pos(&"police_station", &"RoofHelipad")
	if pr != Vector3.INF:
		_add(out, "cash_police_roof", &"cash", _near(pr + Vector3(0, 0, 0), rng, 3.0, {"ref_y": _roof_y(pr), "up": 2.5, "down": 2.5, "avoid_road": false}), 1800, cr, "roof")
	# --- alleys (mid point, pressed against the wall side)
	var n_alley := 0
	for e in LayoutRoadNet.edges:
		if e["cls"] != &"alley":
			continue
		var pts: Array = e["pts"]
		if pts.size() < 2:
			continue
		var mid: Vector2 = pts[pts.size() / 2]
		var c := Vector3(mid.x, 0.0, mid.y)
		_add(out, "cash_alley_%d" % n_alley, &"cash", _near(c, rng, 3.0, {"avoid_road": false}), 220 + 40 * n_alley, cr, "alley")
		n_alley += 1
	# --- docks: tips of the piers
	for pier in WorldLayout.piers:
		if bool(pier.get("finger", false)):
			continue
		var r: Rect2 = pier["rect"]
		var tip := Vector3(r.position.x + r.size.x * 0.5, 0.2, r.end.y - 1.8)
		var pos := InteractionUtil.find_walkable(tip, {"rng": rng, "max_r": 1.5, "avoid_road": false, "water": true, "tries": 20,
			"ref_y": float(pier.get("height", 0.0)) + 0.5, "up": 2.5, "down": 3.0})
		_add(out, "cash_pier_%s" % String(pier["name"]), &"cash", pos, 260, cr, "dock")
	# --- hills: along the Summit Road switchbacks + the summit
	var hill_pts: Array = []
	for e in LayoutRoadNet.edges:
		if bool(e["hill"]):
			hill_pts.append_array(e["pts"])
	if hill_pts.size() > 12:
		var k := 0
		for frac in [0.22, 0.48, 0.74]:
			var q: Vector2 = hill_pts[int(float(hill_pts.size() - 1) * frac)]
			var side := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * 6.0
			var pos2 := InteractionUtil.find_walkable(Vector3(q.x + side.x, WorldLayout.terrain_height(q.x, q.y), q.y + side.y),
				{"rng": rng, "max_r": 5.0, "min_up": 0.65, "tries": 40, "radius": 0.5})
			_add(out, "cash_hill_%d" % k, &"cash", pos2, 300, cr, "hill")
			k += 1
	var peak := _loc(&"parachute_peak")
	if peak != Vector3.INF:
		_add(out, "cash_peak", &"cash", _near(peak + Vector3(-4.0, 0, -3.0), rng, 4.0, {"min_up": 0.65, "avoid_road": false}), 650, cr, "hill")
	# --- beach dunes, park, pond
	var beach := _loc(&"beach_spawn")
	if beach != Vector3.INF:
		_add(out, "cash_beach_a", &"cash", _near(beach + Vector3(-42.0, 0, -3.0), rng, 8.0, {"min_up": 0.6}), 180, cr, "beach")
		_add(out, "cash_beach_b", &"cash", _near(beach + Vector3(36.0, 0, -2.0), rng, 8.0, {"min_up": 0.6}), 200, cr, "beach")
		_add(out, "cash_beach_c", &"cash", _near(beach + Vector3(66.0, 0, -4.0), rng, 8.0, {"min_up": 0.6}), 240, cr, "beach")
	var park := _loc(&"district_center_park_hills")
	if park != Vector3.INF:
		_add(out, "cash_park_a", &"cash", _near(park + Vector3(-34.0, 0, 38.0), rng, 10.0), 240, cr, "park")
		_add(out, "cash_park_b", &"cash", _near(park + Vector3(48.0, 0, -35.0), rng, 10.0), 280, cr, "park")
		_add(out, "cash_pond", &"cash", _near(Vector3(-80.0, 0.0, -125.0), rng, 4.0, {"min_up": 0.6}), 320, cr, "park")
	# --- industrial yards: behind the warehouses
	var n_yard := 0
	for lot in WorldLayout.lots:
		if n_yard >= 4:
			break
		if lot["kind"] != &"warehouse" and lot["kind"] != &"factory":
			continue
		var rect: Rect2 = lot["rect"]
		var centre := rect.get_center()
		var back := -Util.yaw_to_dir(float(lot["yaw"]))        # opposite of the front
		var half := Vector2(rect.size.x * 0.5 * absf(back.x) + rect.size.y * 0.5 * absf(back.z), 0.0).x + 3.5
		var pos3 := _near(Vector3(centre.x + back.x * half, 0.0, centre.y + back.z * half), rng, 4.0)
		if _add(out, "cash_yard_%d" % n_yard, &"cash", pos3, 250 + 30 * n_yard, cr, "yard"):
			n_yard += 1
	# --- airport
	var ap := _loc(&"airport_tower")
	if ap != Vector3.INF:
		_add(out, "cash_airport_tower", &"cash", _near(ap + Vector3(0, 0, 8.0), rng, 5.0), 300, cr, "airport")
	var re := _loc(&"airport_runway_end")
	if re != Vector3.INF:
		_add(out, "cash_runway_end", &"cash", _near(re + Vector3(0, 0, 18.0), rng, 8.0, {"min_up": 0.7}), 350, cr, "airport")
	var tx := _loc(&"airport_terminal")
	if tx != Vector3.INF:
		_add(out, "cash_terminal_back", &"cash", _near(tx + Vector3(14.0, 0, -12.0), rng, 6.0), 280, cr, "airport")
	# --- underwater, at the dive wreck
	var dw := _loc(&"diving_wreck")
	if dw != Vector3.INF:
		for i in 2:
			var c2 := dw + Vector3(-5.0 + 11.0 * i, 3.0, 2.0 - 5.0 * i)
			var hit := InteractionUtil.surface_at(c2.x, c2.z, 2.0, -40.0, GC.L_WORLD)
			if not hit.is_empty():
				_add(out, "cash_wreck_%d" % i, &"cash", hit["position"], 800, cr, "wreck")


# ================================================================================================ small world queries
## Centre of the first cluster of work-zone furniture (cones / barriers), or INF.
static func _construction_site() -> Vector3:
	var pts: Array[Vector3] = []
	for f in WorldLayout.furniture:
		var k: StringName = f["kind"]
		if k == &"cone" or k == &"road_cone":             # cones only exist at the two work sites (barriers also guard the hill road)
			pts.append(f["pos"])
	if pts.size() < 3:
		return Vector3.INF
	var c := Vector3.ZERO
	var first := pts[0]
	var n := 0
	for p in pts:
		if p.distance_to(first) < 30.0:
			c += p
			n += 1
	return c / float(maxi(n, 1))


## Position of a landmark GLB empty (group landmark_anchor), or INF.
static func _anchor_pos(landmark: StringName, anchor: StringName) -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Vector3.INF
	for a in tree.get_nodes_in_group("landmark_anchor"):
		if a is Node3D and a.name == String(anchor) and StringName(String(a.get_meta("landmark", ""))) == landmark:
			return (a as Node3D).global_position
	return Vector3.INF


## Where the dry beach ends at column x (first point walking north from the sea).
static func _shore_point(x: float) -> Vector3:
	var z := 270.0
	while z > 120.0:
		if not WorldLayout.is_water(x, z) and WorldLayout.terrain_height(x, z) > 0.4:
			return Vector3(x, WorldLayout.terrain_height(x, z), z - 1.0)
		z -= 1.0
	return Vector3(x, 0.2, 160.0)
