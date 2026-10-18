class_name DebugCatalog
extends RefCounted
## Static tables for the benchmark / debug menu (Debug agent): teleport groups, vehicle groups, presets, hotkey list.
## Everything that is not listed in a group is still reachable: unknown WorldLayout locations land in "Other",
## unknown implemented vehicle ids land in "More vehicles", so new content from other agents shows up by itself.

const MENU_ID := &"debug"

## [group title, [location ids]]. Order = display order.
const LOCATION_GROUPS: Array = [
	["Districts", ["district_center_downtown", "district_center_residential", "district_center_industrial", "district_center_waterfront",
		"district_center_park_hills", "district_center_airport", "district_center_beach"]],
	["Start & services", ["player_spawn", "safehouse", "hospital", "police_station", "garage_shop", "gas_station"]],
	["Shops", ["weapon_shop", "clothing_store", "barber", "dealer_lot", "scuba_shop"]],
	["Airport & helipads", ["airport_runway_start", "airport_runway_end", "airport_hangar", "helipad_airport", "helipad_downtown", "helipad_hospital"]],
	["Docks, beach & sea", ["dock_boat_spawn", "marina_pier", "marina_office", "beach_spawn", "diving_wreck"]],
	["Nature & viewpoints", ["viewpoint", "parachute_peak", "park_center", "parachute_pickup_a", "parachute_pickup_b"]],
	["Activities", ["shooting_range", "stunt_jump_1", "stunt_jump_2", "stunt_jump_3"]],
	["Transport", ["taxi_stand", "train_station_a", "train_station_b"]],
]

## Short labels where the WorldLayout name is too long for a button.
const LOCATION_LABELS := {
	"district_center_downtown": "Downtown", "district_center_residential": "Westbrook (residential)", "district_center_industrial": "Foundry (industrial)",
	"district_center_waterfront": "Harbor (waterfront)", "district_center_park_hills": "Park & hills", "district_center_airport": "Airport",
	"district_center_beach": "Beach", "player_spawn": "Central Plaza (spawn)", "safehouse": "Safehouse", "hospital": "Hospital",
	"police_station": "Police HQ", "garage_shop": "Customization garage", "gas_station": "Gas station", "weapon_shop": "Weapon shop",
	"clothing_store": "Clothing store", "barber": "Barber", "dealer_lot": "Car dealer lot", "scuba_shop": "Scuba shop",
	"airport_runway_start": "Runway start", "airport_runway_end": "Runway end", "airport_hangar": "Hangar", "helipad_airport": "Helipad (airport)",
	"helipad_downtown": "Helipad (downtown roof)", "helipad_hospital": "Helipad (hospital roof)", "dock_boat_spawn": "Boat spawn (open water)",
	"marina_pier": "Marina pier", "marina_office": "Marina office", "beach_spawn": "Beach", "diving_wreck": "Diving wreck (14 m deep)",
	"viewpoint": "Viewpoint", "parachute_peak": "Parachute peak", "park_center": "Park centre", "parachute_pickup_a": "Parachute pickup A",
	"parachute_pickup_b": "Parachute pickup B", "shooting_range": "Shooting range", "stunt_jump_1": "Stunt jump 1", "stunt_jump_2": "Stunt jump 2",
	"stunt_jump_3": "Stunt jump 3", "taxi_stand": "Taxi stand", "train_station_a": "Train station A", "train_station_b": "Train station B",
}

## [group title, [vehicle ids]]
const VEHICLE_GROUPS: Array = [
	["Cars", ["compact", "sedan", "sports", "muscle", "suv", "pickup", "van", "taxi"]],
	["Bikes", ["motorcycle", "bicycle"]],
	["Trucks & emergency", ["truck", "police_cruiser", "police_tactical", "ambulance", "firetruck"]],
	["Boats", ["speedboat"]],
	["Helicopters", ["heli_civil", "heli_police"]],
	["Airplanes", ["plane_prop", "plane_jet"]],
]

## Paint swatches for spawned vehicles (Halcyon palette first). Color(0,0,0,0) = factory random.
const PAINTS: Array = [
	["Random", Color(0, 0, 0, 0)],
	["Magenta", Color("#ff3d9a")], ["Cyan", Color("#34e0ff")], ["Amber", Color("#ffb347")], ["Pearl", Color("#e8e4da")],
	["Charcoal", Color("#2a2d33")], ["Red", Color("#c43a3a")], ["Blue", Color("#2f6fb5")], ["Green", Color("#4b8a5f")], ["Violet", Color("#7a3f8f")],
]

const TIME_PRESETS: Array = [["Dawn", 5.9], ["Noon", 12.0], ["Dusk", 19.2], ["Midnight", 0.0]]
const MONEY_PRESETS: Array = [["+$10k", 10000], ["+$1M", 1000000], ["$0", 0]]
const WEATHER_LABELS := {"clear": "Clear", "cloudy": "Cloudy", "rain": "Rain", "fog": "Fog", "storm": "Storm"}
const SKILL_LABELS := {"stamina": "Stamina", "shooting": "Shooting", "strength": "Strength", "stealth": "Stealth", "driving": "Driving",
	"flying": "Flying", "lung": "Lung capacity"}
const SAVE_SLOTS: Array = [2, 3, 4]       # SaveSystem slots used by the menu (0 = quick save/phone, 1 = autosave, 6 = shop test)

## Viewport debug-draw modes: [label, Viewport.DebugDraw value]. (Wireframe is deliberately absent: Godot only generates the wireframe
## index buffers for meshes uploaded after RenderingServer.set_debug_generate_wireframes(true), i.e. it would show nothing for the city.)
const RENDER_MODES: Array = [
	["Normal", Viewport.DEBUG_DRAW_DISABLED], ["Unshaded", Viewport.DEBUG_DRAW_UNSHADED], ["Lighting only", Viewport.DEBUG_DRAW_LIGHTING],
	["Overdraw", Viewport.DEBUG_DRAW_OVERDRAW], ["Normals", Viewport.DEBUG_DRAW_NORMAL_BUFFER],
]

## Hotkey layer. Ctrl = crouch / descend and plain keys are all gameplay, so the demo keys are Alt + key (Alt is only the slow-walk
## modifier) and the numpad (not bound by the game). Every Alt combo is consumed before the player sees it. [key label, description]
const HOTKEYS: Array = [
	["F1  /  `", "Open / close the benchmark menu"],
	["Alt+1 .. 5", "Wanted level 1-5   (Alt+0 clears;  Numpad 0-5 does the same)"],
	["Alt+T", "Time of day: dawn / noon / dusk / midnight   (Numpad * ; Numpad + / - = +-1 h)"],
	["Alt+W", "Weather: clear / cloudy / rain / fog / storm   (Numpad /)"],
	["Alt+V", "Spawn the last vehicle (default sedan) in front of you and get in   (Numpad Enter)"],
	["Alt+R", "Repair + flip the current vehicle   (Numpad .)"],
	["Alt+H", "Heal: full health + armor, refill lungs   (Numpad 7)"],
	["Alt+M", "+$10,000;  Alt+Shift+M = +$1,000,000   (Numpad 8)"],
	["Alt+G", "Toggle invulnerability: player + vehicle god mode   (Numpad 9)"],
	["Alt+K", "Give all weapons with full ammo   (Numpad 6)"],
	["Alt+B", "Teleport to the map waypoint"],
	["Alt+X", "Delete nearby vehicles"],
	["Alt+Z", "Toggle slow motion"],
	["Alt+P", "Spawn a police patrol car ahead"],
	["Alt+E", "Explosion at the crosshair"],
	["Alt+F", "Toggle the benchmark stats overlay"],
]


## Vehicle groups with a trailing "More vehicles" group for ids nobody listed (implemented only).
static func vehicle_groups() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for g in VEHICLE_GROUPS:
		var ids: Array = []
		for id in g[1]:
			var sid := StringName(id)
			if VehicleDefs.has(sid):
				ids.append(sid)
				seen[sid] = true
		out.append([g[0], ids])
	var extra: Array = []
	for id in VehicleDefs.ids():
		if not seen.has(id):
			extra.append(id)
	if not extra.is_empty():
		out.append(["More vehicles", extra])
	return out


static func all_vehicle_ids() -> Array:
	var out: Array = []
	for g in vehicle_groups():
		out.append_array(g[1])
	return out


## Location groups resolved against WorldLayout: [[title, [{id, name, pos, yaw, kind}]]]. Unlisted locations go to "Other".
static func location_groups() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for g in LOCATION_GROUPS:
		var items: Array = []
		for id in g[1]:
			var sid := StringName(id)
			var loc: Dictionary = WorldLayout.get_location(sid)
			if loc.is_empty():
				continue
			seen[sid] = true
			items.append(_loc_entry(sid, loc))
		if not items.is_empty():
			out.append([g[0], items])
	var extra: Array = []
	var keys: Array = WorldLayout.locations.keys()
	keys.sort()
	for k in keys:
		var sk := StringName(k)
		if not seen.has(sk):
			extra.append(_loc_entry(sk, WorldLayout.locations[k]))
	if not extra.is_empty():
		out.append(["Other", extra])
	return out


static func _loc_entry(id: StringName, loc: Dictionary) -> Dictionary:
	var label: String = LOCATION_LABELS.get(String(id), "")
	if label == "":
		label = String(loc.get("name", String(id).replace("_", " ").capitalize()))
	return {"id": id, "name": label, "pos": loc.get("pos", Vector3.ZERO), "yaw": float(loc.get("yaw", 0.0)), "kind": loc.get("kind", &"")}


static func vehicle_name(id: StringName) -> String:
	return String(VehicleDefs.get_def(id).get("name", String(id)))


static func weapon_name(id: StringName) -> String:
	return String(WeaponDefs.get_def(id).get("name", String(id)))


## Weapon ids in shop order (category, price) - fists first.
static func weapon_ids() -> Array:
	var ids: Array = WeaponDefs.ids()
	ids.sort_custom(func(a, b):
		var da := WeaponDefs.get_def(a)
		var db := WeaponDefs.get_def(b)
		var ca := WeaponDefs.CATEGORY_ORDER.find(da.get("category", &""))
		var cb := WeaponDefs.CATEGORY_ORDER.find(db.get("category", &""))
		if ca != cb:
			return ca < cb
		return int(da.get("price", 0)) < int(db.get("price", 0)))
	return ids
