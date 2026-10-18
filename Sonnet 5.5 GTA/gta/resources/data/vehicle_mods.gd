class_name VehicleModsData
extends RefCounted
## Data-driven vehicle customization tables (Garage agent). Pure data + tiny helpers, no scene access.
##
## * PERFORMANCE mods ("levels", price per level, stat effects). EFFECTS (derived) is what VehicleBase.apply_mods() applies:
##     power brake grip susp_freq shift_time damage_taken downforce mass            (original stats)
##     health turbo_boost turbo_spool tire_hits                                   (added by the garage module)
## * COSMETIC catalogs: paint palette / finishes, rim styles, body parts per slot, lights, windows, plates, liveries, horns.
## * VEHICLE_CFG: which slots each ground vehicle supports + per-vehicle mount overrides for the fitting code.
## Everything that is purchasable has an integer `price`; level based mods are cumulative (price of level n = cost of the step n-1 -> n).

const SHOP_NAME := "Foundry Garage"
const SLOTS: Array[StringName] = [&"spoiler", &"front_bumper", &"rear_bumper", &"hood", &"roof", &"skirts", &"exhaust", &"grille", &"mirrors"]

const FINISHES: Array = [
	{"id": &"gloss", "name": "Gloss", "price": 0},
	{"id": &"matte", "name": "Matte", "price": 450},
	{"id": &"metallic", "name": "Metallic", "price": 700},
	{"id": &"pearl", "name": "Pearl", "price": 1100},
	{"id": &"chrome", "name": "Chrome", "price": 2400},
]
const PAINT_PRICE := 350            # per colour change (primary or secondary)

static var _perf: Array = []
static var _effects: Dictionary = {}
static var _palette: Array = []
static var _parts: Dictionary = {}
static var _cfg: Dictionary = {}


# =====================================================================================================
# PERFORMANCE
# =====================================================================================================
static func performance() -> Array:
	if _perf.is_empty():
		_perf = _build_perf()
	return _perf


static func _lv(name: String, price: int, desc: String = "") -> Dictionary:
	return {"name": name, "price": price, "desc": desc}


static func _build_perf() -> Array:
	return [
		{"key": "engine", "name": "Engine Tuning", "desc": "Intake, ECU and internals: more power across the rev range.", "icon": "engine",
			"levels": [_lv("Stock", 0), _lv("Street Tune", 2500, "+8 % power"), _lv("Sport Tune", 5000, "+16 % power"), _lv("Race Tune", 9000, "+25 % power"), _lv("Competition", 15000, "+35 % power")],
			"fx": {"power": [1.0, 1.08, 1.16, 1.25, 1.35]}},
		{"key": "brakes", "name": "Brakes", "desc": "Bigger discs and pads: shorter stopping distances.", "icon": "brakes",
			"levels": [_lv("Stock", 0), _lv("Street Pads", 1200, "+12 % braking"), _lv("Sport Brakes", 2600, "+25 % braking"), _lv("Race Brakes", 4800, "+40 % braking")],
			"fx": {"brake": [1.0, 1.12, 1.25, 1.40]}},
		{"key": "suspension", "name": "Suspension", "desc": "Stiffer springs and dampers: more grip and less body roll.", "icon": "suspension",
			"levels": [_lv("Stock", 0), _lv("Lowered", 1500, "+3 % grip, stiffer"), _lv("Sport", 3200, "+6 % grip, stiffer"), _lv("Competition", 5500, "+9 % grip, stiffest")],
			"fx": {"grip": [1.0, 1.03, 1.06, 1.09], "susp_freq": [1.0, 1.10, 1.20, 1.30]}},
		{"key": "transmission", "name": "Transmission", "desc": "Quicker shifts and a tighter drivetrain.", "icon": "gearbox",
			"levels": [_lv("Stock", 0), _lv("Short Shift", 1800, "-20 % shift time"), _lv("Sport Box", 3600, "-40 % shift time"), _lv("Racing Box", 6500, "-60 % shift time, +7 % power")],
			"fx": {"shift_time": [1.0, 0.8, 0.6, 0.4], "power": [1.0, 1.02, 1.04, 1.07]}},
		{"key": "turbo", "name": "Turbocharger", "desc": "Forced induction. Spools up under full throttle for a big surge of power.", "icon": "turbo",
			"levels": [_lv("None", 0), _lv("Twin-Scroll Turbo", 12000, "up to +24 % power at full boost")],
			"fx": {"turbo_boost": [0.0, 0.24], "turbo_spool": [1.0, 1.6]}},
		{"key": "armor", "name": "Armour Plating", "desc": "Reinforced panels absorb bullets, blasts and crashes.", "icon": "armor",
			"levels": [_lv("None", 0), _lv("Level 1", 3000, "-10 % damage"), _lv("Level 2", 6000, "-20 % damage"), _lv("Level 3", 10000, "-30 % damage"), _lv("Level 4", 16000, "-40 % damage"), _lv("Level 5", 25000, "-50 % damage")],
			"fx": {"damage_taken": [1.0, 0.9, 0.8, 0.7, 0.6, 0.5], "health": [1.0, 1.05, 1.10, 1.18, 1.27, 1.40]}},
		{"key": "tires", "name": "Tyres", "desc": "Tyre compound and construction.", "icon": "tire",
			"levels": [_lv("Standard", 0), _lv("Low-Profile", 900, "+4 % grip"), _lv("Reinforced", 1800, "+4 % grip, takes 3 hits to burst"), _lv("Bullet-Resistant", 4200, "+8 % grip, cannot be shot flat")],
			"fx": {"grip": [1.0, 1.04, 1.04, 1.08], "tire_hits": [1, 1, 3, 99]}},
		{"key": "spoiler", "name": "Aero Tuning", "desc": "Downforce kit: stability at speed.", "icon": "wing",
			"levels": [_lv("None", 0), _lv("Mild", 1400, "light downforce"), _lv("Sport", 2800, "medium downforce"), _lv("Track", 4600, "high downforce")],
			"fx": {"downforce": [0.0, 0.35, 0.7, 1.2]}},
		{"key": "weight", "name": "Weight Reduction", "desc": "Lightweight panels: quicker everything.", "icon": "feather",
			"levels": [_lv("Stock", 0), _lv("Light", 2200, "-6 % mass"), _lv("Ultra Light", 5200, "-12 % mass")],
			"fx": {"mass": [1.0, 0.94, 0.88]}},
	]


## key -> {stat: [value per level]}  (superset of VehicleDefs.MOD_EFFECTS; read by VehicleBase.apply_mods)
static func effects() -> Dictionary:
	if _effects.is_empty():
		for p in performance():
			_effects[p["key"]] = p["fx"]
	return _effects


static func perf_def(key: String) -> Dictionary:
	for p in performance():
		if p["key"] == key:
			return p
	return {}


static func perf_max_level(key: String) -> int:
	var p := perf_def(key)
	return (p.get("levels", []) as Array).size() - 1 if not p.is_empty() else 0


## Cost to move a performance mod from level a to level b (upgrades only; downgrades are free and not refunded).
static func perf_cost(key: String, from_lvl: int, to_lvl: int) -> int:
	if to_lvl <= from_lvl:
		return 0
	var p := perf_def(key)
	if p.is_empty():
		return 0
	var lv: Array = p["levels"]
	var total := 0
	for i in range(from_lvl + 1, mini(to_lvl, lv.size() - 1) + 1):
		total += int(lv[i]["price"])
	return total


# =====================================================================================================
# PAINT / FINISH
# =====================================================================================================
static func palette() -> Array:
	if _palette.is_empty():
		var rows := [
			["Obsidian", "#14161b"], ["Graphite", "#2c3038"], ["Gunmetal", "#59606b"], ["Silver", "#a9b0ba"], ["Frost White", "#eceff1"], ["Ivory", "#e8dcc2"],
			["Crimson", "#b3202c"], ["Rally Red", "#e0322b"], ["Ember", "#e2571f"], ["Amber", "#ffb347"], ["Sunflower", "#f2c230"], ["Lime", "#9bd631"],
			["Racing Green", "#145a3a"], ["Mint", "#4bd1a0"], ["Teal", "#17a2a8"], ["Cyan", "#34e0ff"], ["Sky", "#4aa3e8"], ["Cobalt", "#1f4fb8"],
			["Midnight", "#16224f"], ["Violet", "#6a3cc9"], ["Orchid", "#b05fe0"], ["Magenta", "#ff3d9a"], ["Rose", "#f08aa8"], ["Burgundy", "#5b1230"],
			["Copper", "#b3703d"], ["Sand", "#c9b48a"], ["Olive", "#6b7040"], ["Chocolate", "#4a2f22"],
		]
		for r in rows:
			_palette.append({"name": r[0], "color": Color(String(r[1]))})
	return _palette


static func finish_price(id: StringName) -> int:
	for f in FINISHES:
		if f["id"] == id:
			return int(f["price"])
	return 0


# =====================================================================================================
# RIMS / WHEELS: Blender wheel GLBs (models/vehicle_parts/wheel_*.glb: tyre + rim, radius 0.34, spin axis X, centred, same on both sides)
# =====================================================================================================
static func rims() -> Array:
	return [
		{"id": &"stock", "name": "Stock", "price": 0, "glb": ""},
		{"id": &"oem", "name": "OEM Covers", "price": 300, "glb": "vehicle_parts/wheel_stock"},
		{"id": &"steel", "name": "Pressed Steel", "price": 500, "glb": "vehicle_parts/wheel_steel_basic"},
		{"id": &"five_spoke", "name": "Five-Spoke", "price": 1400, "glb": "vehicle_parts/wheel_five_spoke"},
		{"id": &"mesh", "name": "Chrome Mesh", "price": 1900, "glb": "vehicle_parts/wheel_mesh"},
		{"id": &"split_six", "name": "Split Six", "price": 2300, "glb": "vehicle_parts/wheel_split_six"},
		{"id": &"dish", "name": "Deep Dish", "price": 2800, "glb": "vehicle_parts/wheel_dish"},
		{"id": &"turbine", "name": "Turbine", "price": 3300, "glb": "vehicle_parts/wheel_turbine"},
		{"id": &"lowprofile", "name": "Low-Profile Ten", "price": 3600, "glb": "vehicle_parts/wheel_lowprofile"},
		{"id": &"offroad", "name": "Off-Road", "price": 2600, "glb": "vehicle_parts/wheel_offroad"},
		{"id": &"mc_sport", "name": "Sport Bike Wheels", "price": 1500, "glb": "vehicle_parts/wheel_mc_sport", "bike": true},
	]


## Rim options shown for a vehicle kind ("car" / "truck" / "bike").
static func rims_for(kind: String) -> Array:
	var out: Array = []
	for r in rims():
		var bike_only: bool = r.get("bike", false)
		if kind == "bike":
			if r["id"] == &"stock" or bike_only:
				out.append(r)
		elif not bike_only:
			out.append(r)
	return out


static func rim_def(id: StringName) -> Dictionary:
	for r in rims():
		if r["id"] == id:
			return r
	return rims()[0]


const RIM_COLORS: Array = [
	{"name": "Stock", "color": Color(-1, 0, 0)},
	{"name": "Chrome", "color": Color(0.86, 0.88, 0.92)},
	{"name": "Gunmetal", "color": Color(0.22, 0.24, 0.28)},
	{"name": "Black", "color": Color(0.05, 0.05, 0.06)},
	{"name": "Gold", "color": Color(0.85, 0.62, 0.16)},
	{"name": "Bronze", "color": Color(0.55, 0.34, 0.17)},
	{"name": "Cyan", "color": Color(0.1, 0.78, 0.95)},
	{"name": "Magenta", "color": Color(0.95, 0.2, 0.55)},
	{"name": "Red", "color": Color(0.8, 0.1, 0.12)},
	{"name": "White", "color": Color(0.93, 0.94, 0.96)},
	{"name": "Lime", "color": Color(0.55, 0.85, 0.2)},
	{"name": "Violet", "color": Color(0.45, 0.25, 0.85)},
]
const RIM_COLOR_PRICE := 250


# =====================================================================================================
# BODY PARTS  (slot -> options). `glb` = Blender part (models/vehicle_parts/<id>.glb, origin = mount point, vehicle frame).
# The fitting rules per slot live in VehicleModsVisual (derived from docs/api/blender_vehicle_parts.md + the body analysis).
# =====================================================================================================
static func parts() -> Dictionary:
	if _parts.is_empty():
		_parts = {
			&"spoiler": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"lip", "name": "Lip Spoiler", "price": 1200, "glb": "vehicle_parts/spoiler_lip"},
				{"id": &"ducktail", "name": "Ducktail", "price": 1800, "glb": "vehicle_parts/spoiler_ducktail"},
				{"id": &"gt_wing", "name": "GT Wing", "price": 3400, "glb": "vehicle_parts/spoiler_wing_low"},
				{"id": &"track_wing", "name": "Track Wing", "price": 4800, "glb": "vehicle_parts/spoiler_wing_high"},
			],
			&"front_bumper": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"splitter", "name": "Race Splitter", "price": 1500, "glb": "vehicle_parts/splitter_front"},
				{"id": &"sport", "name": "Sport Bumper", "price": 2600, "glb": "vehicle_parts/bumper_front_sport"},
			],
			&"rear_bumper": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"diffuser", "name": "Rear Diffuser", "price": 1600, "glb": "vehicle_parts/bumper_rear_diffuser"},
			],
			&"hood": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"scoop", "name": "Hood Scoop", "price": 900, "glb": "vehicle_parts/hood_scoop_a"},
				{"id": &"vents", "name": "Vented Hood", "price": 1300, "glb": "vehicle_parts/hood_vents_b"},
			],
			&"roof": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"scoop", "name": "Roof Scoop", "price": 800, "glb": "vehicle_parts/roof_scoop"},
				{"id": &"rack", "name": "Roof Rack", "price": 1100, "glb": "vehicle_parts/roof_rack"},
				{"id": &"light_bar", "name": "Light Bar", "price": 1400, "glb": "vehicle_parts/roof_light_bar"},
				{"id": &"antenna", "name": "Whip Antenna", "price": 250, "glb": "vehicle_parts/antenna"},
			],
			&"skirts": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"sport", "name": "Sport Skirts", "price": 1000, "glb": "vehicle_parts/skirt_side_sport"},
			],
			&"exhaust": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"single", "name": "Single Tip", "price": 450, "glb": "vehicle_parts/exhaust_tip_single"},
				{"id": &"twin", "name": "Twin Tips", "price": 700, "glb": "vehicle_parts/exhaust_tip_dual"},
				{"id": &"quad", "name": "Quad Tips", "price": 1200, "glb": "vehicle_parts/exhaust_tip_quad"},
			],
			&"grille": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"mesh", "name": "Chrome Mesh Grille", "price": 800, "glb": "vehicle_parts/grille_mesh"},
			],
			&"mirrors": [
				{"id": &"stock", "name": "Stock", "price": 0},
				{"id": &"sport", "name": "Sport Mirrors", "price": 700, "glb": "vehicle_parts/mirror_sport"},
			],
		}
	return _parts


static func slot_options(slot: StringName) -> Array:
	return parts().get(slot, [])


## Options of a slot that fit a given vehicle (per-vehicle exclusions from the Blender fit notes), stock first.
static func slot_options_for(vid: StringName, slot: StringName) -> Array:
	var excl: Dictionary = vehicle_cfg(vid).get("exclude", {})
	var banned: Array = excl.get(slot, [])
	var out: Array = []
	for o in slot_options(slot):
		if not banned.has(o["id"]):
			out.append(o)
	return out


static func slot_option(slot: StringName, id: StringName) -> Dictionary:
	for o in slot_options(slot):
		if o["id"] == id:
			return o
	return {}


const SLOT_NAMES := {
	&"spoiler": "Spoiler / Wing", &"front_bumper": "Front Bumper", &"rear_bumper": "Rear Bumper", &"hood": "Hood",
	&"roof": "Roof", &"skirts": "Side Skirts", &"exhaust": "Exhaust", &"grille": "Grille", &"mirrors": "Mirrors",
}


# =====================================================================================================
# LIGHTS
# =====================================================================================================
const HEADLIGHTS: Array = [
	{"id": &"stock", "name": "Stock Halogen", "price": 0, "color": Color(-1, 0, 0)},
	{"id": &"xenon", "name": "Xenon White", "price": 700, "color": Color(0.78, 0.9, 1.0)},
	{"id": &"amber", "name": "Amber", "price": 500, "color": Color(1.0, 0.68, 0.2)},
	{"id": &"cyan", "name": "Cyan", "price": 900, "color": Color(0.2, 0.9, 1.0)},
	{"id": &"magenta", "name": "Magenta", "price": 900, "color": Color(1.0, 0.25, 0.65)},
	{"id": &"green", "name": "Lime", "price": 900, "color": Color(0.5, 1.0, 0.35)},
]
const TAILLIGHTS: Array = [
	{"id": &"stock", "name": "Stock Red", "price": 0, "color": Color(-1, 0, 0)},
	{"id": &"smoked", "name": "Smoked", "price": 500, "color": Color(0.55, 0.05, 0.05)},
	{"id": &"magenta", "name": "Magenta", "price": 700, "color": Color(1.0, 0.2, 0.6)},
	{"id": &"cyan", "name": "Cyan", "price": 700, "color": Color(0.2, 0.9, 1.0)},
	{"id": &"amber", "name": "Amber", "price": 600, "color": Color(1.0, 0.6, 0.1)},
]
const UNDERGLOW: Array = [
	{"id": &"off", "name": "None", "price": 0, "color": Color(0, 0, 0, 0)},
	{"id": &"cyan", "name": "Cyan Neon", "price": 1200, "color": Color(0.1, 0.9, 1.0)},
	{"id": &"magenta", "name": "Magenta Neon", "price": 1200, "color": Color(1.0, 0.2, 0.6)},
	{"id": &"amber", "name": "Amber Neon", "price": 1200, "color": Color(1.0, 0.65, 0.15)},
	{"id": &"lime", "name": "Lime Neon", "price": 1200, "color": Color(0.5, 1.0, 0.25)},
	{"id": &"violet", "name": "Violet Neon", "price": 1200, "color": Color(0.6, 0.3, 1.0)},
	{"id": &"white", "name": "Ice White", "price": 1000, "color": Color(0.85, 0.95, 1.0)},
]
const WINDOW_TINTS: Array = [
	{"name": "Clear", "price": 0, "desc": "Factory glass"},
	{"name": "Light Tint", "price": 400, "desc": "~30 % darker"},
	{"name": "Dark Tint", "price": 800, "desc": "~60 % darker"},
	{"name": "Limo", "price": 1400, "desc": "Privacy black"},
]


# =====================================================================================================
# PLATES / LIVERIES / HORNS
# =====================================================================================================
const PLATES: Array = [
	{"id": &"harbor", "name": "Harbor Blue", "price": 0, "bg": Color(0.93, 0.95, 0.98), "fg": Color(0.07, 0.2, 0.55), "band": Color(0.1, 0.35, 0.8), "band_text": "HALCYON BAY"},
	{"id": &"sunset", "name": "Sunset Gold", "price": 300, "bg": Color(1.0, 0.72, 0.28), "fg": Color(0.15, 0.08, 0.04), "band": Color(0.85, 0.3, 0.2), "band_text": "SUNSET COAST"},
	{"id": &"noir", "name": "Noir", "price": 400, "bg": Color(0.06, 0.07, 0.09), "fg": Color(0.93, 0.95, 0.97), "band": Color(0.5, 0.5, 0.55), "band_text": "HALCYON BAY"},
	{"id": &"neon", "name": "Neon Night", "price": 600, "bg": Color(0.07, 0.04, 0.16), "fg": Color(0.2, 0.95, 1.0), "band": Color(1.0, 0.25, 0.62), "band_text": "NEON BAY"},
]
const LIVERIES: Array = [
	{"id": &"none", "name": "None", "price": 0},
	{"id": &"racing_twin", "name": "Twin Racing Stripes", "price": 1200},
	{"id": &"racing_single", "name": "Wide Racing Stripe", "price": 1000},
	{"id": &"side_line", "name": "Side Line", "price": 900},
	{"id": &"hood_band", "name": "Hood & Trunk Band", "price": 1100},
	{"id": &"double_side", "name": "Double Side Stripes", "price": 1300},
]
const LIVERY_COLORS: Array = [
	{"name": "White", "color": Color(0.94, 0.95, 0.97)},
	{"name": "Black", "color": Color(0.05, 0.05, 0.07)},
	{"name": "Cyan", "color": Color(0.1, 0.85, 1.0)},
	{"name": "Magenta", "color": Color(1.0, 0.25, 0.6)},
	{"name": "Amber", "color": Color(1.0, 0.7, 0.2)},
	{"name": "Red", "color": Color(0.85, 0.1, 0.12)},
	{"name": "Lime", "color": Color(0.55, 0.9, 0.2)},
	{"name": "Silver", "color": Color(0.7, 0.73, 0.78)},
]
## mods["horn"] = numeric style (the original VehicleAudio contract): 0 stock, 1.. = these Sfx variants
const HORNS: Array = [
	{"name": "Stock", "price": 0, "sound": "", "pitch": 1.0},
	{"name": "Deep Bass", "price": 400, "sound": "horn_truck", "pitch": 0.92},
	{"name": "Air Horn", "price": 700, "sound": "horn_fire", "pitch": 1.0},
	{"name": "Sport Beep", "price": 500, "sound": "horn_bike", "pitch": 1.12},
]


# =====================================================================================================
# PER-VEHICLE CONFIG
# =====================================================================================================
## kind: car | truck | bike | bicycle ; slots: supported body slots ; ov: per slot override {dx,dy,dz (m), s (scale mult), yaw (deg)}
static func vehicle_cfg(id: StringName) -> Dictionary:
	if _cfg.is_empty():
		var all_cars: Array = [&"spoiler", &"front_bumper", &"rear_bumper", &"hood", &"roof", &"skirts", &"exhaust", &"grille", &"mirrors"]
		# `exclude`: options the Blender fit notes say do not work on that body (slot -> [option ids])
		_cfg = {
			&"sedan": {"kind": "car", "slots": all_cars, "price_mult": 1.0},
			&"compact": {"kind": "car", "slots": all_cars, "price_mult": 0.8, "exclude": {&"spoiler": [&"gt_wing", &"track_wing"], &"roof": [&"rack"]}},
			&"taxi": {"kind": "car", "slots": all_cars, "price_mult": 0.9, "exclude": {&"roof": [&"light_bar", &"scoop", &"rack"]}},
			&"police_cruiser": {"kind": "car", "slots": [&"spoiler", &"front_bumper", &"rear_bumper", &"hood", &"skirts", &"exhaust", &"grille", &"mirrors"], "price_mult": 1.0},
			&"sports": {"kind": "car", "slots": all_cars, "price_mult": 1.4},
			&"muscle": {"kind": "car", "slots": all_cars, "price_mult": 1.2, "exclude": {&"hood": [&"scoop"]}},
			&"suv": {"kind": "car", "slots": all_cars, "price_mult": 1.1},
			&"pickup": {"kind": "car", "slots": [&"spoiler", &"front_bumper", &"rear_bumper", &"hood", &"roof", &"skirts", &"exhaust", &"grille", &"mirrors"], "price_mult": 1.1,
				"exclude": {&"spoiler": [&"gt_wing", &"track_wing"]}},
			&"van": {"kind": "truck", "slots": [&"spoiler", &"front_bumper", &"rear_bumper", &"roof", &"skirts", &"exhaust", &"mirrors"], "price_mult": 1.1,
				"exclude": {&"spoiler": [&"gt_wing", &"track_wing"]}},
			&"ambulance": {"kind": "truck", "slots": [&"front_bumper", &"skirts", &"exhaust", &"mirrors"], "price_mult": 1.3},
			&"police_tactical": {"kind": "truck", "slots": [&"front_bumper", &"skirts", &"exhaust"], "price_mult": 1.5},
			&"truck": {"kind": "truck", "slots": [&"front_bumper", &"skirts", &"exhaust"], "price_mult": 1.6},
			&"firetruck": {"kind": "truck", "slots": [&"front_bumper", &"skirts", &"exhaust"], "price_mult": 1.8},
			&"motorcycle": {"kind": "bike", "slots": [], "price_mult": 0.7},
			&"bicycle": {"kind": "bicycle", "slots": [], "price_mult": 0.3},
		}
	return _cfg.get(id, {"kind": "car", "slots": [], "price_mult": 1.0})


## Per-vehicle mount tweaks for the fitting code: vehicle id -> slot -> {dx, dy, dz (m, model space), s (scale mult), yaw (deg)}.
## Filled in after the visual QA contact sheet (docs/api/garage_phone.md lists what each entry fixes).
const FIT_OVERRIDES := {}


static func fit_override(vid: StringName, slot: StringName) -> Dictionary:
	var per_vehicle: Dictionary = FIT_OVERRIDES.get(vid, {})
	return per_vehicle.get(slot, {})


static func slots_for(id: StringName) -> Array:
	return vehicle_cfg(id).get("slots", [])


static func price_mult(id: StringName) -> float:
	return float(vehicle_cfg(id).get("price_mult", 1.0))


## Categories shown in the garage menu for a vehicle id.
static func categories_for(id: StringName) -> Array:
	var kind: String = String(vehicle_cfg(id).get("kind", "car"))
	match kind:
		"bicycle":
			return [&"paint", &"horn"]
		"bike":
			return [&"repair", &"paint", &"wheels", &"lights", &"plates", &"horn", &"performance"]
		_:
			return [&"repair", &"paint", &"wheels", &"body", &"lights", &"windows", &"plates", &"livery", &"horn", &"performance"]


const CATEGORY_NAMES := {
	&"repair": "Repair", &"paint": "Paint", &"wheels": "Wheels", &"body": "Body", &"lights": "Lights",
	&"windows": "Windows", &"plates": "Plates", &"livery": "Livery", &"horn": "Horn", &"performance": "Performance",
}


# =====================================================================================================
# Defaults / validation
# =====================================================================================================
## The cosmetic keys that live in VehicleBase.mods next to the numeric performance levels.
const COSMETIC_KEYS: Array[String] = [
	"p_spoiler", "p_front_bumper", "p_rear_bumper", "p_hood", "p_roof", "p_skirts", "p_exhaust", "p_grille", "p_mirrors",
	"rim_style", "rim_color", "headlight", "taillight", "underglow", "plate", "plate_text", "livery", "livery_color", "horn", "window_tint",
]
## keys whose values are Colors (JSON round trip)
const COLOR_KEYS: Array[String] = ["rim_color", "livery_color"]


static func random_plate_text(rng: RandomNumberGenerator = null) -> String:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var letters := "ABCDEFGHJKLMNPRSTUVWXYZ"
	return "%s%s %03d" % [letters[r.randi() % letters.length()], letters[r.randi() % letters.length()], r.randi() % 1000]


## Total stat multipliers of a mods dict (the numbers VehicleBase.apply_mods ends up with), for UI bars and tests.
static func stat_summary(mods: Dictionary) -> Dictionary:
	var out := {"power": 1.0, "brake": 1.0, "grip": 1.0, "susp_freq": 1.0, "shift_time": 1.0, "damage_taken": 1.0, "downforce": 0.0, "mass": 1.0,
		"health": 1.0, "turbo_boost": 0.0, "tire_hits": 1}
	var fx := effects()
	for key in mods:
		if not fx.has(key):
			continue
		var lvl := int(mods[key])
		for stat in fx[key]:
			var arr: Array = fx[key][stat]
			var v: float = float(arr[clampi(lvl, 0, arr.size() - 1)])
			match stat:
				"power", "brake", "grip", "susp_freq", "shift_time", "damage_taken", "mass", "health":
					out[stat] = float(out[stat]) * v
				"downforce":
					out["downforce"] = float(out["downforce"]) + v
				"turbo_boost":
					out["turbo_boost"] = maxf(float(out["turbo_boost"]), v)
				"tire_hits":
					out["tire_hits"] = maxi(int(out["tire_hits"]), int(v))
	return out
