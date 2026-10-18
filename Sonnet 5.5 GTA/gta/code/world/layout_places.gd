class_name LayoutPlaces
extends RefCounted
## Static place data of the map: districts, airport, piers, pedestrian-only paths, nature zones, water polygons.

const RUNWAY_Z := 165.0
const RUNWAY_X0 := 76.0
const RUNWAY_X1 := 296.0
const RUNWAY_W := 26.0
const TAXI_Z := 138.0
const APRON := Rect2(128.0, 110.0, 122.0, 22.0)


static func districts() -> Array:
	return [
		{"id": GC.D_DOWNTOWN, "name": "Downtown", "rect": Rect2(-108, -92, 216, 226), "color": Color("#7d8fa6")},
		{"id": GC.D_RESIDENTIAL, "name": "Westbrook", "rect": Rect2(-300, -250, 192, 340), "color": Color("#9bb58a")},
		{"id": GC.D_INDUSTRIAL, "name": "Foundry District", "rect": Rect2(108, -62, 192, 148), "color": Color("#a69a82")},
		{"id": GC.D_WATERFRONT, "name": "Harbor", "rect": Rect2(-300, 90, 200, 110), "color": Color("#6fa6b8")},
		{"id": GC.D_BEACH, "name": "Halcyon Beach", "rect": Rect2(-100, 134, 176, 66), "color": Color("#e6d49a")},
		{"id": GC.D_AIRPORT, "name": "Halcyon Airfield", "rect": Rect2(76, 86, 224, 114), "color": Color("#b7bcc4")},
		{"id": GC.D_PARK, "name": "Greenhill Park", "rect": Rect2(-108, -300, 408, 208), "color": Color("#6aa572")},
	]


static func airport() -> Dictionary:
	var taxi: Array[Vector3] = [Vector3(100, 0, TAXI_Z), Vector3(284, 0, TAXI_Z)]
	return {
		"runway_start": Vector3(RUNWAY_X0, 0.0, RUNWAY_Z), "runway_end": Vector3(RUNWAY_X1, 0.0, RUNWAY_Z),
		"runway_width": RUNWAY_W, "taxiway": taxi, "apron": APRON,
		"taxiway_width": 12.0, "taxi_links": [Vector2(112, TAXI_Z), Vector2(270, TAXI_Z)], "runway_yaw": -PI * 0.5,
	}


static func piers() -> Array:
	var out: Array = []
	out.append({"rect": Rect2(-231, 192, 12, 46), "height": 0.0, "name": "fishing_pier"})
	out.append({"rect": Rect2(-196, 192, 22, 70), "height": 0.0, "name": "cargo_pier"})
	out.append({"rect": Rect2(-152, 192, 12, 48), "height": 0.0, "name": "marina_pier"})
	for zf in [206.0, 222.0, 236.0]:
		out.append({"rect": Rect2(-168, zf, 16, 2.4), "height": 0.0, "name": "finger", "finger": true})
		out.append({"rect": Rect2(-140, zf, 16, 2.4), "height": 0.0, "name": "finger", "finger": true})
	out.append({"rect": Rect2(-4, 168, 8, 44), "height": 0.2, "name": "beach_pier"})
	return out


## Swim / boat volumes (x,z rect + surface): the open sea south of the shoreline and the park pond.
static func water_volumes() -> Array:
	return [
		{"id": &"sea", "rect": Rect2(-330, 120, 660, 300), "kind": &"sea", "level": GC.WATER_LEVEL},
		{"id": &"pond", "rect": Rect2(LayoutTerrain.POND_C - Vector2(26, 26), Vector2(52, 52)), "kind": &"pond", "level": GC.WATER_LEVEL},
	]


## Elevated light-rail route (viaduct over Dune Avenue / Industrial Avenue at z=50) between the two station buildings.
## {"points": PackedVector3Array (rail head, y = deck_y + 0.2), "stations": {id: index}, "deck_y": float, "gauge": float, "z": float}
static func rail() -> Dictionary:
	var pts := PackedVector3Array()
	var x0 := -84.0
	var x1 := 236.0
	var deck_y := 8.4
	var n := int((x1 - x0) / 8.0)
	for i in n + 1:
		pts.append(Vector3(lerpf(x0, x1, float(i) / float(n)), deck_y + 0.2, 50.0))
	return {"points": pts, "stations": {&"train_station_a": 0, &"train_station_b": pts.size() - 1}, "deck_y": deck_y, "gauge": 1.5, "z": 50.0,
		"speed": 16.0, "platform_a": Vector3(-76.0, deck_y, 50.0), "platform_b": Vector3(228.0, deck_y, 50.0)}


static func pier_contains(x: float, z: float, piers_list: Array) -> bool:
	for p in piers_list:
		var r: Rect2 = p["rect"]
		if x >= r.position.x and x <= r.position.x + r.size.x and z >= r.position.y and z <= r.position.y + r.size.y:
			return true
	return false


## Pedestrian-only paths: [{"pts": PackedVector2Array, "zone": PedGraph.ZONE_*, "closed": bool, "dy": float}]
static func ped_paths() -> Array:
	var out: Array = []
	# pond loop in the park
	var pond := PackedVector2Array()
	for k in 24:
		var a := TAU * float(k) / 24.0
		pond.append(LayoutTerrain.POND_C + Vector2(cos(a), sin(a)) * 31.0)
	pond.append(pond[0])
	out.append({"pts": pond, "zone": PedGraph.ZONE_PARK, "closed": true})
	out.append({"pts": PackedVector2Array([Vector2(-44, -101), Vector2(-60, -114), Vector2(-78, -121)]), "zone": PedGraph.ZONE_PARK})
	out.append({"pts": PackedVector2Array([Vector2(-111, -152), Vector2(-124, -151)]), "zone": PedGraph.ZONE_PARK})
	out.append({"pts": PackedVector2Array([Vector2(-47, -152), Vector2(-28, -152), Vector2(-5, -166), Vector2(12, -170), Vector2(12, -186)]), "zone": PedGraph.ZONE_PARK})
	out.append({"pts": PackedVector2Array([Vector2(-80, -183), Vector2(-60, -200), Vector2(-40, -212)]), "zone": PedGraph.ZONE_PARK})
	out.append({"pts": PackedVector2Array([Vector2(-28, -110), Vector2(-5, -125), Vector2(15, -140), Vector2(12, -150)]), "zone": PedGraph.ZONE_PARK})
	# residential pocket park (loop + cross path)
	var pocket := PackedVector2Array()
	for k in 14:
		var a2 := TAU * float(k) / 14.0
		pocket.append(Vector2(-224.0, -55.0) + Vector2(cos(a2) * 17.0, sin(a2) * 15.0))
	pocket.append(pocket[0])
	out.append({"pts": pocket, "zone": PedGraph.ZONE_PARK, "closed": true})
	out.append({"pts": PackedVector2Array([Vector2(-224, -84), Vector2(-224, -26)]), "zone": PedGraph.ZONE_PARK})
	# downtown plaza (south part of the central block)
	out.append({"pts": PackedVector2Array([Vector2(-24, 30), Vector2(24, 30)]), "zone": PedGraph.ZONE_PLAZA, "step": 6.0})
	out.append({"pts": PackedVector2Array([Vector2(-24, 38), Vector2(24, 38)]), "zone": PedGraph.ZONE_PLAZA, "step": 6.0})
	out.append({"pts": PackedVector2Array([Vector2(0, 26), Vector2(0, 44)]), "zone": PedGraph.ZONE_PLAZA, "step": 6.0})
	# beach promenade + sand spokes
	out.append({"pts": PackedVector2Array([Vector2(-96, 157), Vector2(-40, 157), Vector2(20, 158), Vector2(66, 160)]), "zone": PedGraph.ZONE_BEACH, "step": 8.0})
	for sx in [-70.0, -30.0, 10.0, 46.0]:
		out.append({"pts": PackedVector2Array([Vector2(sx, 157), Vector2(sx + 2.0, 166), Vector2(sx, 172)]), "zone": PedGraph.ZONE_BEACH, "step": 6.0, "dy": 0.05})
	# quay promenade
	out.append({"pts": PackedVector2Array([Vector2(-292, 184), Vector2(-100, 184)]), "zone": PedGraph.ZONE_DOCK, "step": 8.0})
	# hill viewpoint trail
	out.append({"pts": PackedVector2Array([Vector2(205, -230), Vector2(215, -238), Vector2(222, -246)]), "zone": PedGraph.ZONE_PARK, "step": 5.0, "link": 18.0})
	return out


static func nature_zones() -> Array:
	var out: Array = []
	out.append({"poly": _rect_poly(Rect2(-100, -200, 140, 105)), "kind": &"park", "density": 0.35})
	out.append({"poly": _rect_poly(Rect2(-252, -84, 58, 56)), "kind": &"park", "density": 0.25})
	out.append({"poly": _rect_poly(Rect2(60, -300, 240, 195)), "kind": &"hills", "density": 0.5})
	out.append({"poly": _rect_poly(Rect2(-300, -300, 192, 50)), "kind": &"forest", "density": 0.7})
	out.append({"poly": _rect_poly(Rect2(-100, -300, 160, 85)), "kind": &"forest", "density": 0.55})
	out.append({"poly": _rect_poly(Rect2(-96, 151, 168, 6)), "kind": &"beach_palms", "density": 0.5})
	out.append({"poly": _rect_poly(Rect2(250, -62, 50, 30)), "kind": &"roadside", "density": 0.2})
	return out


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Sea + pond polygons for the minimap. Shoreline sampled from the baked terrain.
static func water_polys() -> Array:
	var out: Array = []
	var sea := PackedVector2Array()
	var x := -300.0
	while x <= 300.1:
		var zz := 330.0
		var z := 120.0
		while z < 330.0:
			if LayoutTerrain.height(x, z) < GC.WATER_LEVEL:
				zz = z
				break
			z += 2.0
		sea.append(Vector2(x, zz))
		x += 12.0
	sea.append(Vector2(300, 300))
	sea.append(Vector2(-300, 300))
	out.append(sea)
	var pond := PackedVector2Array()
	for k in 20:
		var a := TAU * float(k) / 20.0
		pond.append(LayoutTerrain.POND_C + Vector2(cos(a), sin(a)) * 19.0)
	out.append(pond)
	return out
