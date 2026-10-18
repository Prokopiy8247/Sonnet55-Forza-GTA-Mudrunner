class_name UIIcons
extends RefCounted
## Vector icons drawn in code (no image assets): weapon silhouettes for the HUD / weapon wheel and glyphs for
## map + minimap locations. Everything is defined as small op lists in a fixed design grid and drawn through a
## CanvasItem transform, so icons scale crisply to any size.
##
## Op formats: ["p", [x,y,...]] polygon · ["c", x, y, r] disc · ["o", x, y, r, w] ring · ["l", [x,y,...], w] polyline ·
##             ["r", x, y, w, h] rectangle.   Weapon grid: 100 x 50 (barrel +X).  Glyph grid: -10..10.

# ---- Weapons ---------------------------------------------------------------------------------------------
const WEAPON_OPS := {
	&"fists": [["r", 22, 17, 44, 24], ["c", 28, 17, 6.5], ["c", 38, 14.5, 6.5], ["c", 48, 14.5, 6.5], ["c", 58, 17, 6.5],
		["p", [20, 28, 8, 33, 14, 44, 30, 38]], ["r", 66, 21, 18, 16]],
	&"knife": [["p", [34, 20, 96, 25, 34, 31]], ["r", 6, 20, 28, 12], ["r", 32, 15, 4, 22]],
	&"bat": [["p", [2, 24, 16, 21, 58, 18.5, 86, 15, 96, 17, 96, 33, 86, 35, 58, 31.5, 16, 29, 2, 26]]],
	&"crowbar": [["l", [10, 42, 32, 28, 68, 14, 86, 11, 94, 17], 5.0], ["l", [10, 42, 4, 38], 5.0]],
	&"pistol": [["p", [10, 12, 80, 12, 85, 17, 85, 25, 10, 25]], ["p", [13, 25, 36, 25, 30, 47, 14, 47]], ["p", [38, 26, 52, 26, 50, 34, 40, 34]]],
	&"revolver": [["p", [30, 12, 93, 12, 93, 22, 30, 22]], ["c", 34, 21, 11], ["p", [8, 16, 30, 13, 30, 28, 26, 28, 20, 47, 6, 47, 9, 28]], ["p", [44, 26, 58, 26, 56, 35, 46, 35]]],
	&"smg": [["p", [14, 12, 72, 12, 72, 25, 14, 25]], ["r", 72, 15, 24, 5], ["p", [36, 25, 47, 25, 44, 47, 33, 47]], ["p", [18, 25, 29, 25, 25, 43, 14, 43]],
		["p", [1, 14, 14, 13, 14, 24, 1, 22]], ["r", 30, 8, 12, 4]],
	&"shotgun_pump": [["r", 30, 14, 68, 5], ["r", 30, 20, 56, 4], ["r", 52, 22, 18, 8], ["p", [14, 12, 42, 12, 42, 27, 14, 27]],
		["p", [0, 17, 14, 12, 14, 30, 4, 36, 0, 31]], ["p", [26, 27, 36, 27, 32, 40, 24, 40]]],
	&"shotgun_auto": [["r", 30, 13, 68, 6], ["r", 30, 20, 50, 4], ["p", [12, 11, 46, 11, 46, 28, 12, 28]], ["c", 38, 30, 9],
		["p", [0, 17, 12, 12, 12, 30, 4, 36, 0, 31]], ["p", [24, 28, 33, 28, 30, 42, 22, 42]]],
	&"rifle_assault": [["p", [22, 12, 66, 12, 66, 25, 22, 25]], ["r", 66, 14, 16, 8], ["r", 82, 16, 16, 4], ["p", [2, 14, 22, 12, 22, 27, 10, 29, 2, 25]],
		["p", [40, 25, 53, 25, 51, 35, 47, 47, 36, 45]], ["r", 30, 8, 26, 4], ["p", [26, 25, 34, 25, 31, 41, 23, 41]]],
	&"carbine": [["p", [20, 12, 60, 12, 60, 25, 20, 25]], ["r", 60, 14, 14, 8], ["r", 74, 16, 18, 4], ["p", [2, 15, 20, 12, 20, 27, 10, 29, 2, 24]],
		["p", [36, 25, 47, 25, 45, 40, 33, 40]], ["r", 28, 8, 22, 4], ["p", [24, 25, 31, 25, 28, 39, 21, 39]]],
	&"rifle_marksman": [["p", [20, 14, 62, 14, 62, 26, 20, 26]], ["r", 62, 16, 12, 8], ["r", 74, 18, 24, 4], ["p", [1, 16, 20, 14, 20, 28, 9, 31, 1, 26]],
		["r", 30, 7, 22, 6], ["p", [38, 26, 48, 26, 46, 38, 36, 38]], ["p", [24, 26, 31, 26, 28, 40, 21, 40]]],
	&"sniper": [["r", 50, 18, 48, 4], ["p", [20, 14, 58, 14, 58, 27, 20, 27]], ["p", [0, 16, 20, 14, 20, 29, 8, 33, 0, 27]],
		["r", 26, 4, 34, 7], ["r", 32, 11, 4, 3], ["r", 50, 11, 4, 3], ["l", [58, 27, 70, 40], 2.0], ["l", [58, 27, 66, 42], 2.0], ["p", [30, 27, 38, 27, 35, 40, 28, 40]]],
	&"rocket_launcher": [["r", 10, 11, 80, 15], ["p", [90, 7, 99, 7, 99, 30, 90, 30]], ["p", [2, 9, 10, 11, 10, 26, 2, 28]], ["p", [38, 26, 48, 26, 46, 44, 38, 44]], ["r", 56, 6, 16, 5]],
	&"grenade_launcher": [["r", 38, 12, 58, 12], ["c", 44, 28, 12], ["p", [8, 14, 38, 12, 38, 28, 16, 30, 8, 26]], ["p", [54, 24, 64, 24, 62, 40, 54, 40]], ["r", 76, 8, 12, 4]],
	&"grenade": [["c", 50, 31, 17], ["r", 44, 8, 12, 8], ["p", [56, 9, 76, 12, 76, 17, 56, 15]], ["o", 36, 12, 6, 2.0]],
}

## Category fallback silhouette (when a weapon id has no dedicated icon).
const CATEGORY_ICON := {
	&"melee": &"knife", &"handgun": &"pistol", &"smg": &"smg", &"shotgun": &"shotgun_pump", &"rifle": &"rifle_assault",
	&"sniper": &"sniper", &"heavy": &"rocket_launcher", &"thrown": &"grenade",
}

## Fallback table used until the Weapons agent's WeaponDefs is filled: id -> [display name, category].
const WEAPON_FALLBACK := {
	&"fists": ["Fists", &"melee"], &"knife": ["Combat Knife", &"melee"], &"bat": ["Baseball Bat", &"melee"], &"crowbar": ["Crowbar", &"melee"],
	&"pistol": ["Pistol", &"handgun"], &"revolver": ["Revolver", &"handgun"], &"smg": ["Submachine Gun", &"smg"],
	&"shotgun_pump": ["Pump Shotgun", &"shotgun"], &"shotgun_auto": ["Auto Shotgun", &"shotgun"],
	&"rifle_assault": ["Assault Rifle", &"rifle"], &"carbine": ["Carbine", &"rifle"], &"rifle_marksman": ["Marksman Rifle", &"rifle"],
	&"sniper": ["Sniper Rifle", &"sniper"], &"grenade": ["Grenade", &"thrown"],
	&"rocket_launcher": ["Rocket Launcher", &"heavy"], &"grenade_launcher": ["Grenade Launcher", &"heavy"],
}

const CATEGORY_NAMES := {
	&"melee": "Melee", &"handgun": "Handguns", &"smg": "SMGs", &"shotgun": "Shotguns", &"rifle": "Rifles",
	&"sniper": "Snipers", &"heavy": "Heavy", &"thrown": "Thrown",
}

# ---- Location glyphs ---------------------------------------------------------------------------------------
const GLYPH_OPS := {
	&"cross": [["r", -2.6, -7.5, 5.2, 15], ["r", -7.5, -2.6, 15, 5.2]],
	&"shield": [["p", [0, -8.5, 6.8, -6, 6.2, 1, 0, 8.5, -6.2, 1, -6.8, -6]]],
	&"target": [["o", 0, 0, 6.5, 1.6], ["o", 0, 0, 3, 1.4], ["c", 0, 0, 1.0], ["r", -0.8, -9.5, 1.6, 4], ["r", -0.8, 5.5, 1.6, 4], ["r", -9.5, -0.8, 4, 1.6], ["r", 5.5, -0.8, 4, 1.6]],
	&"wrench": [["l", [-6, 6, 3, -3], 3.4], ["o", 4.5, -4.5, 3.6, 2.4]],
	&"shirt": [["p", [-3, -7.5, 3, -7.5, 8.5, -3, 6.5, 0.5, 4.2, -1.2, 4.2, 7.5, -4.2, 7.5, -4.2, -1.2, -6.5, 0.5, -8.5, -3]]],
	&"scissors": [["l", [-6, -7, 6, 4], 1.8], ["l", [6, -7, -6, 4], 1.8], ["o", -6, 6.5, 2.4, 1.5], ["o", 6, 6.5, 2.4, 1.5]],
	&"drop": [["p", [0, -9, 5.8, 0, 5.8, 3.5, 3.2, 7.5, -3.2, 7.5, -5.8, 3.5, -5.8, 0]]],
	&"house": [["p", [0, -8.5, 8.8, 0, 6, 0, 6, 7.5, -6, 7.5, -6, 0, -8.8, 0]]],
	&"car": [["p", [-8.5, 2, -6.5, -3, -3.5, -5.5, 3.5, -5.5, 6.5, -3, 8.5, 2, 8.5, 5.5, -8.5, 5.5]], ["c", -4.5, 5.5, 2.2], ["c", 4.5, 5.5, 2.2]],
	&"plane": [["p", [0, -9.5, 1.6, -3, 9.5, 2, 9.5, 4, 1.6, 2, 1.2, 6.5, 4.2, 8.2, 4.2, 9.4, 0, 8.4, -4.2, 9.4, -4.2, 8.2, -1.2, 6.5, -1.6, 2, -9.5, 4, -9.5, 2, -1.6, -3]]],
	&"helipad": [["r", -5.8, -7, 3, 14], ["r", 2.8, -7, 3, 14], ["r", -5, -1.5, 10, 3]],
	&"boat": [["p", [-9, 1.5, 9, 1.5, 6, 6.5, -6, 6.5]], ["p", [0, -8.5, 0, 0, 6.5, 0]]],
	&"waves": [["l", [-8.5, -2.5, -4.2, -5.5, 0, -2.5, 4.2, -5.5, 8.5, -2.5], 1.9], ["l", [-8.5, 3.5, -4.2, 0.5, 0, 3.5, 4.2, 0.5, 8.5, 3.5], 1.9]],
	&"train": [["r", -6, -7.5, 12, 12], ["c", -3, 7, 1.9], ["c", 3, 7, 1.9]],
	&"eye": [["p", [-9.5, 0, -4.5, -4.5, 4.5, -4.5, 9.5, 0, 4.5, 4.5, -4.5, 4.5]]],
	&"ramp": [["p", [-8.5, 6.5, 8.5, 6.5, 8.5, -6.5]]],
	&"tree": [["c", 0, -2.5, 6], ["r", -1.2, 2.5, 2.4, 6]],
	&"chute": [["p", [-8.5, -1, -6.5, -5.5, 0, -8, 6.5, -5.5, 8.5, -1]], ["l", [-8, -1, 0, 7], 1.1], ["l", [8, -1, 0, 7], 1.1], ["l", [0, -1, 0, 7], 1.1]],
	&"anchor": [["l", [0, -6.5, 0, 6.5], 1.9], ["o", 0, -6.5, 2.2, 1.5], ["l", [-6, 0.5, 0, 6.8, 6, 0.5], 1.9], ["l", [-4, -2.5, 4, -2.5], 1.9]],
	&"pin": [["p", [0, 9, -5, -1, 5, -1]], ["c", 0, -3.5, 5.5]],
	&"dot": [["c", 0, 0, 3.4]],
	&"star": [],
}

## Location id -> [glyph, colour, tier (1 = radar + map, 2 = map only), label]
const LOC := {
	&"hospital": [&"cross", Color("#ff4d6a"), 1, "Hospital"],
	&"police_station": [&"shield", Color("#3a7bff"), 1, "Police Station"],
	&"weapon_shop": [&"target", Color("#ffb347"), 1, "Weapon Shop"],
	&"garage_shop": [&"wrench", Color("#34e0ff"), 1, "Garage"],
	&"clothing_store": [&"shirt", Color("#ff3d9a"), 1, "Clothing"],
	&"barber": [&"scissors", Color("#ff3d9a"), 1, "Barber"],
	&"gas_station": [&"drop", Color("#ffb347"), 1, "Gas Station"],
	&"dealer_lot": [&"car", Color("#34e0ff"), 1, "Vehicle Dealer"],
	&"safehouse": [&"house", Color("#7be495"), 1, "Safehouse"],
	&"airport_runway_start": [&"plane", Color("#9bb4ff"), 1, "Airport"],
	&"airport_hangar": [&"plane", Color("#9bb4ff"), 2, "Hangar"],
	&"helipad_airport": [&"helipad", Color("#9bb4ff"), 2, "Helipad"],
	&"helipad_downtown": [&"helipad", Color("#9bb4ff"), 1, "Helipad"],
	&"helipad_hospital": [&"helipad", Color("#ff4d6a"), 2, "Helipad"],
	&"dock_boat_spawn": [&"boat", Color("#34e0ff"), 1, "Boat Rental"],
	&"marina_pier": [&"anchor", Color("#34e0ff"), 2, "Marina"],
	&"scuba_shop": [&"waves", Color("#34e0ff"), 1, "Dive Shop"],
	&"train_station_a": [&"train", Color("#c8d4e0"), 1, "Station"],
	&"train_station_b": [&"train", Color("#c8d4e0"), 1, "Station"],
	&"taxi_stand": [&"car", Color("#ffd35a"), 2, "Taxi Stand"],
	&"shooting_range": [&"target", Color("#ffb347"), 1, "Shooting Range"],
	&"race_start": [&"car", Color("#ff3d9a"), 1, "Street Race"],       # added by the Activities module (ActivityRace registers the location)
	&"viewpoint": [&"eye", Color("#7be495"), 2, "Viewpoint"],
	&"parachute_peak": [&"chute", Color("#7be495"), 2, "Jump Peak"],
	&"parachute_pickup_a": [&"chute", Color("#7be495"), 2, "Parachute"],
	&"parachute_pickup_b": [&"chute", Color("#7be495"), 2, "Parachute"],
	&"stunt_jump_1": [&"ramp", Color("#ff3d9a"), 2, "Stunt Jump"],
	&"stunt_jump_2": [&"ramp", Color("#ff3d9a"), 2, "Stunt Jump"],
	&"stunt_jump_3": [&"ramp", Color("#ff3d9a"), 2, "Stunt Jump"],
	&"park_center": [&"tree", Color("#7be495"), 2, "Park"],
	&"diving_wreck": [&"waves", Color("#8fa3b3"), 2, "Wreck"],
	&"beach_spawn": [&"waves", Color("#ffd35a"), 2, "Beach"],
}

static var _parsed: Dictionary = {}


static func weapon_info(id: StringName) -> Dictionary:
	## {"name": String, "category": StringName, "icon": StringName} resolved from WeaponDefs, else the fallback table.
	var out := {"name": String(id).replace("_", " ").capitalize(), "category": &"handgun", "icon": &"pistol"}
	var d: Dictionary = WeaponDefs.get_def(id)
	if WEAPON_FALLBACK.has(id):
		out["name"] = WEAPON_FALLBACK[id][0]
		out["category"] = WEAPON_FALLBACK[id][1]
	if not d.is_empty():
		out["name"] = str(d.get("name", out["name"]))
		out["category"] = StringName(d.get("category", out["category"]))
	out["icon"] = id if WEAPON_OPS.has(id) else CATEGORY_ICON.get(out["category"], &"pistol")
	return out


static func _ops(table: Dictionary, key: StringName, glyph: bool) -> Array:
	var ck := String(key) + ("#g" if glyph else "#w")
	if _parsed.has(ck):
		return _parsed[ck]
	var out: Array = []
	for op in table.get(key, []):
		var kind: String = op[0]
		match kind:
			"p":
				var pts := PackedVector2Array()
				var flat: Array = op[1]
				for i in range(0, flat.size() - 1, 2):
					pts.append(Vector2(flat[i], flat[i + 1]))
				out.append({"t": "p", "pts": pts})
			"l":
				var lp := PackedVector2Array()
				var lflat: Array = op[1]
				for j in range(0, lflat.size() - 1, 2):
					lp.append(Vector2(lflat[j], lflat[j + 1]))
				out.append({"t": "l", "pts": lp, "w": float(op[2])})
			"c":
				out.append({"t": "c", "c": Vector2(op[1], op[2]), "r": float(op[3])})
			"o":
				out.append({"t": "o", "c": Vector2(op[1], op[2]), "r": float(op[3]), "w": float(op[4])})
			"r":
				out.append({"t": "r", "rect": Rect2(op[1], op[2], op[3], op[4])})
	_parsed[ck] = out
	return out


static func _run(ci: CanvasItem, ops: Array, color: Color) -> void:
	for op in ops:
		match op["t"]:
			"p":
				if Geometry2D.triangulate_polygon(op["pts"]).size() >= 3:
					ci.draw_colored_polygon(op["pts"], color)
			"l":
				ci.draw_polyline(op["pts"], color, op["w"], true)
			"c":
				ci.draw_circle(op["c"], op["r"], color)
			"o":
				ci.draw_arc(op["c"], op["r"], 0.0, TAU, 20, color, op["w"], true)
			"r":
				ci.draw_rect(op["rect"], color)


## Draws the silhouette of weapon `id` (or a category key) fitted and centred inside `rect`.
static func draw_weapon(ci: CanvasItem, id: StringName, rect: Rect2, color: Color) -> void:
	var key := id
	if not WEAPON_OPS.has(key):
		key = weapon_info(id)["icon"]
	var s := minf(rect.size.x / 100.0, rect.size.y / 50.0)
	var off := rect.position + (rect.size - Vector2(100.0, 50.0) * s) * 0.5
	ci.draw_set_transform(off, 0.0, Vector2(s, s))
	_run(ci, _ops(WEAPON_OPS, key, false), color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws a location badge (coloured disc + white glyph) centred at `center`, radius `r`.
static func draw_location(ci: CanvasItem, loc_id: StringName, center: Vector2, r: float, alpha: float = 1.0, ring: bool = true) -> void:
	var info: Array = LOC.get(loc_id, [&"dot", Color("#8fa3b3"), 2, String(loc_id).capitalize()])
	draw_glyph(ci, info[0], center, r, info[1], alpha, ring)


static func draw_glyph(ci: CanvasItem, glyph: StringName, center: Vector2, r: float, color: Color, alpha: float = 1.0, ring: bool = true) -> void:
	ci.draw_circle(center, r + (1.5 if ring else 0.0), Color(0.02, 0.03, 0.05, 0.85 * alpha))
	ci.draw_circle(center, r, Color(color.r, color.g, color.b, 0.95 * alpha))
	var s := r / 11.0
	ci.draw_set_transform(center, 0.0, Vector2(s, s))
	_run(ci, _ops(GLYPH_OPS, glyph, true), Color(1, 1, 1, 0.97 * alpha) if color.get_luminance() < 0.8 else Color(0.05, 0.07, 0.1, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func location_info(loc_id: StringName) -> Array:
	return LOC.get(loc_id, [])
