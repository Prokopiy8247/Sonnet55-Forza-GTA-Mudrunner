class_name LayoutLocations
extends RefCounted
## Named locations (WorldLayout.locations): {pos, yaw, radius, kind, name}. Positions are on walkable / drivable ground, doors of
## landmark buildings sit on the sidewalk in front of the door (yaw = direction the front faces, i.e. where a person leaves the building).

const SW := 0.16

static var _loc: Dictionary = {}


static func _gy(x: float, z: float) -> float:
	return LayoutTerrain.height(x, z)


static func _put(id: StringName, pos: Vector3, yaw: float, radius: float, kind: StringName, nm: String, extra: Dictionary = {}) -> void:
	var d := {"pos": pos, "yaw": yaw, "radius": radius, "kind": kind, "name": nm}
	for k in extra:
		d[k] = extra[k]
	_loc[id] = d


static func _ground(id: StringName, x: float, z: float, yaw: float, radius: float, kind: StringName, nm: String, dy: float = SW, extra: Dictionary = {}) -> void:
	_put(id, Vector3(x, _gy(x, z) + dy, z), yaw, radius, kind, nm, extra)


## Door position of a landmark lot: front edge centre pushed 1.7 m out along the facing direction.
static func _door(lid: StringName, radius: float, kind: StringName, nm: String, out: float = 1.7, shift: float = 0.0) -> void:
	var lot: Dictionary = LayoutLots.landmark_lots.get(lid, {})
	if lot.is_empty():
		push_warning("LayoutLocations: landmark lot '%s' missing" % lid)
		return
	var r: Rect2 = lot["rect"]
	var side: String = lot["side"]
	var c := r.get_center()
	var p := c
	var yaw := float(lot["yaw"])
	match side:
		"n":
			p = Vector2(c.x + shift, r.position.y - out)
		"s":
			p = Vector2(c.x + shift, r.end.y + out)
		"e":
			p = Vector2(r.end.x + out, c.y + shift)
		"w":
			p = Vector2(r.position.x - out, c.y + shift)
	_ground(lid, p.x, p.y, yaw, radius, kind, nm, SW, {"lot": lot["id"]})


static func build() -> void:
	_loc = {}
	# ---- spawns + services (landmark doors) ----------------------------------------------------------------------------------
	_ground(&"player_spawn", 14.0, 38.0, 0.0, 4.0, &"spawn", "Central Plaza", 0.08)
	_door(&"safehouse", 3.5, &"safehouse", "Safehouse")
	_door(&"hospital", 7.0, &"service", "Halcyon General Hospital", 2.2)
	_door(&"police_station", 7.0, &"service", "Harbor Police HQ", 2.2)
	_door(&"weapon_shop", 3.5, &"shop", "Gunsmith")
	_door(&"clothing_store", 3.5, &"shop", "Threads")
	_door(&"barber", 3.5, &"shop", "Clip & Co Barber")
	_door(&"garage_shop", 6.0, &"service", "Foundry Garage", 2.5)
	_door(&"scuba_shop", 3.5, &"shop", "Reef Dive Shop")
	_door(&"train_station_a", 6.0, &"transport", "Downtown Station")
	_door(&"train_station_b", 6.0, &"transport", "Foundry Station")
	_door(&"shooting_range", 5.0, &"activity", "Shooting Range", 2.0)
	_door(&"airport_terminal", 6.0, &"airport", "Terminal", 2.0)
	_door(&"airport_tower", 4.0, &"airport", "Control Tower", 2.0)
	_door(&"marina_office", 4.0, &"service", "Marina Office")
	# gas station: under the canopy (building centre, pumps in front)
	var gs: Dictionary = LayoutLots.landmark_lots.get(&"gas_station", {})
	if not gs.is_empty():
		var gr: Rect2 = gs["rect"]
		var gc := gr.get_center()
		_ground(&"gas_station", gc.x, gc.y - 2.5, float(gs["yaw"]), 9.0, &"service", "Halcyon Fuel", 0.05, {"lot": gs["id"]})
	# dealership: forecourt in front of the showroom (one row of display bays along X)
	var dl: Dictionary = LayoutLots.landmark_lots.get(&"dealer_lot", {})
	if not dl.is_empty():
		var dr: Rect2 = dl["rect"]
		_ground(&"dealer_lot", dr.get_center().x, dr.position.y - 6.0, 0.0, 30.0, &"shop", "Showroom Motors", 0.05, {"lot": dl["id"], "extent": Vector2(26.0, 5.0)})
	# ---- aviation ------------------------------------------------------------------------------------------------------------------
	var a: Dictionary = WorldLayout.airport
	var rs: Vector3 = a["runway_start"]
	var re: Vector3 = a["runway_end"]
	_put(&"airport_runway_start", Vector3(rs.x + 6.0, 0.05, rs.z), -PI * 0.5, 8.0, &"airport", "Runway 09 threshold")
	_put(&"airport_runway_end", Vector3(re.x - 6.0, 0.05, re.z), -PI * 0.5, 8.0, &"airport", "Runway 27 end")
	var h1: Dictionary = {}
	for lot in WorldLayout.lots:
		if lot["kind"] == &"hangar":
			h1 = lot
			break
	if not h1.is_empty():
		var hr: Rect2 = h1["rect"]
		_ground(&"airport_hangar", hr.get_center().x, hr.end.y + 2.0, 0.0, 12.0, &"airport", "Hangar 1", 0.05, {"lot": h1["id"]})
	_ground(&"helipad_airport", 238.0, 121.0, 0.0, 10.0, &"helipad", "Airfield helipad", 0.06)
	# downtown tower roof (y is corrected by WorldRoot from the real roof height after the buildings exist)
	var tower: Dictionary = {}
	for lot in WorldLayout.lots:
		if lot["kind"] == &"office" and int(lot["floors"]) >= 28:
			tower = lot
			break
	if not tower.is_empty():
		var tr: Rect2 = tower["rect"]
		var tc := tr.get_center()
		_put(&"helipad_downtown", Vector3(tc.x, float(tower["height"]) + 0.4, tc.y), 0.0, 9.0, &"helipad", "Halcyon Tower helipad", {"lot": tower["id"]})
	var hosp: Dictionary = LayoutLots.landmark_lots.get(&"hospital", {})
	if not hosp.is_empty():
		var hrr: Rect2 = hosp["rect"]
		var hc := hrr.get_center()
		_put(&"helipad_hospital", Vector3(hc.x, float(hosp["height"]) + 0.5, hc.y), 0.0, 9.0, &"helipad", "Hospital helipad", {"lot": hosp["id"]})
	# ---- water + coast ------------------------------------------------------------------------------------------------------------------
	_put(&"dock_boat_spawn", Vector3(-117.0, GC.WATER_LEVEL, 214.0), PI, 8.0, &"water", "Harbor boat berth")
	_put(&"marina_pier", Vector3(-146.0, 0.05, 204.0), PI, 10.0, &"water", "Marina Pier")
	_ground(&"beach_spawn", 0.0, 164.0, PI, 6.0, &"spawn", "Halcyon Beach", 0.1)
	_put(&"diving_wreck", Vector3(-22.0, _gy(-22.0, 268.0) + 0.6, 268.0), 0.0, 14.0, &"water", "Sunken freighter")
	# ---- hills ----------------------------------------------------------------------------------------------------------------------------
	var vp := Vector2(205.0, -224.0)
	_ground(&"viewpoint", vp.x, vp.y, PI, 8.0, &"nature", "Summit Viewpoint", 0.15)
	var pk := LayoutTerrain.PEAK
	_ground(&"parachute_peak", pk.x, pk.y, 0.0, 8.0, &"nature", "Parachute Peak", 0.2)
	_ground(&"parachute_pickup_a", vp.x + 6.0, vp.y + 5.0, 0.0, 3.0, &"pickup", "Parachute", 0.4)
	_ground(&"parachute_pickup_b", 148.0, 113.0, 0.0, 3.0, &"pickup", "Parachute", 0.4)
	# ---- city extras -------------------------------------------------------------------------------------------------------------------
	_ground(&"taxi_stand", 96.4, 12.0, PI * 0.5, 6.0, &"transport", "Taxi Stand", 0.1)
	_ground(&"park_center", -12.0, -122.0, 0.0, 22.0, &"nature", "Greenhill Park", 0.05)
	# stunt jumps: ramp base + launch yaw + landing target (ramps are built by WorldRoot / StuntBuilder)
	_ground(&"stunt_jump_1", -26.0, -130.0, -PI * 0.5, 10.0, &"activity", "Park Gap Jump", 0.05, {"land": Vector3(16.0, 0.05, -130.0), "ramp": true})
	# world-fill: jump 2 moved to z = 126 (hero hangars occupy z < 116); jump 3 ramp moved to the pier END (z 198..210) so the pier path stays open
	_ground(&"stunt_jump_2", 140.0, 126.0, -PI * 0.5, 10.0, &"activity", "Apron Jump", 0.05, {"land": Vector3(196.0, 0.05, 126.0), "ramp": true})
	_put(&"stunt_jump_3", Vector3(0.0, 0.23, 198.0), PI, 10.0, &"activity", "Pier Leap", {"land": Vector3(0.0, GC.WATER_LEVEL, 238.0), "ramp": true})
	# ---- district centres (open ground, not inside buildings) ----------------------------------------------------------------------
	_ground(&"district_center_downtown", 0.0, 36.0, 0.0, 30.0, &"district", "Downtown", 0.08)
	_ground(&"district_center_residential", -185.0, -90.0, 0.0, 30.0, &"district", "Westbrook", 0.0)
	_ground(&"district_center_industrial", 190.0, -20.0, 0.0, 30.0, &"district", "Foundry District", 0.0)
	_ground(&"district_center_waterfront", -185.0, 120.0, 0.0, 30.0, &"district", "Harbor", 0.0)
	_ground(&"district_center_park_hills", -60.0, -125.0, 0.0, 30.0, &"district", "Greenhill Park", 0.0)
	_ground(&"district_center_airport", 189.0, 121.0, 0.0, 30.0, &"district", "Halcyon Airfield", 0.03)
	_ground(&"district_center_beach", 0.0, 157.0, 0.0, 30.0, &"district", "Halcyon Beach", 0.05)
	# any other landmark lot gets a location of its own id (door position)
	for lid in LayoutLots.landmark_lots:
		if not _loc.has(lid):
			_door(lid, 4.0, &"landmark", String(lid).capitalize())
	WorldLayout.locations = _loc
