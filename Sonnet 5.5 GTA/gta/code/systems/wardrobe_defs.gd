class_name WardrobeDefs
extends RefCounted
## Clothing / barber catalogue (data only). Items are variant DELTAS for CharacterRig.setup() (see CharacterVariants):
##   {key, name, cat, price, basic, delta: {shirt: Color, jacket: &"Jacket_Short", jacket_color: Color, hat: &"Hat_Cap", ...}, swatch: Color}
## `basic` items are wearable for free from the safehouse wardrobe; everything else must be bought in Threads first.

const CATEGORIES: Array[StringName] = [&"tops", &"jackets", &"pants", &"shoes", &"hats", &"glasses", &"packs"]
const CATEGORY_NAMES := {
	&"tops": "Tops", &"jackets": "Jackets", &"pants": "Pants", &"shoes": "Shoes", &"hats": "Hats", &"glasses": "Eyewear", &"packs": "Bags",
}

const HAIR_STYLES := [
	{"id": 0, "name": "Buzzed", "price": 15, "desc": "Clean shave, no fuss."},
	{"id": 1, "name": "Crop", "price": 25, "desc": "Short and tidy."},
	{"id": 2, "name": "Side Part", "price": 30, "desc": "Swept to one side."},
	{"id": 3, "name": "Long", "price": 35, "desc": "Down to the shoulders."},
	{"id": 4, "name": "Ponytail", "price": 35, "desc": "Tied back, out of the way."},
	{"id": 5, "name": "Curls", "price": 30, "desc": "Loose natural curls."},
	{"id": 6, "name": "Mohawk", "price": 40, "desc": "Loud and proud."},
]
const BEARDS := [
	{"id": &"", "name": "Clean shaven", "price": 10, "desc": "Smooth."},
	{"id": &"Beard_1", "name": "Stubble", "price": 20, "desc": "Short beard trim."},
	{"id": &"Beard_2", "name": "Full beard", "price": 25, "desc": "Properly groomed."},
]
const HAIR_COLORS := [
	{"name": "Jet black", "color": Color("#1a1512"), "price": 0},
	{"name": "Espresso", "color": Color("#2a1c14"), "price": 0},
	{"name": "Chestnut", "color": Color("#4a3022"), "price": 0},
	{"name": "Honey blond", "color": Color("#d6b46a"), "price": 0},
	{"name": "Copper", "color": Color("#a8482a"), "price": 0},
	{"name": "Silver", "color": Color("#a9a39a"), "price": 0},
	{"name": "Neon magenta", "color": Color("#ff3d9a"), "price": 40},
	{"name": "Electric cyan", "color": Color("#34e0ff"), "price": 40},
	{"name": "Plum", "color": Color("#7b4b7a"), "price": 35},
]

static var _items: Dictionary = {}
static var _by_key: Dictionary = {}


static func _add(cat: StringName, key: String, nm: String, price: int, basic: bool, delta: Dictionary, swatch: Color) -> void:
	var it := {"key": key, "name": nm, "cat": cat, "price": price, "basic": basic, "delta": delta, "swatch": swatch}
	if not _items.has(cat):
		_items[cat] = []
	(_items[cat] as Array).append(it)
	_by_key[key] = it


static func _build() -> void:
	if not _items.is_empty():
		return
	# ---- tops (shirt colour)
	var tops := [["White tee", "#f2f0ea", 35, true], ["Black tee", "#2a2d33", 35, true], ["Navy tee", "#25324d", 35, true], ["Coral tee", "#e8795f", 45, false],
		["Teal tee", "#2f9c95", 45, false], ["Mustard tee", "#e0b04a", 45, false], ["Sage tee", "#7ea286", 45, false], ["Sky tee", "#8fc6e8", 45, false],
		["Plum tee", "#7b4b7a", 55, false], ["Neon magenta tee", "#ff3d9a", 70, false]]
	for t in tops:
		_add(&"tops", "top_" + String(t[0]).to_lower().replace(" ", "_"), t[0], t[2], t[3], {"shirt": Color(t[1])}, Color(t[1]))
	# ---- jackets
	_add(&"jackets", "jacket_none", "No jacket", 0, true, {"jacket": &""}, Color("#555b66"))
	var jackets := [["Teal bomber", "#2f9c95", &"Jacket_Short", 120, true], ["Black bomber", "#2a2d33", &"Jacket_Short", 120, true], ["Navy bomber", "#25324d", &"Jacket_Short", 120, false],
		["Brick bomber", "#a4553f", &"Jacket_Short", 130, false], ["Plum bomber", "#7b4b7a", &"Jacket_Short", 140, false], ["Mustard bomber", "#e0b04a", &"Jacket_Short", 140, false],
		["Charcoal coat", "#2a2d33", &"Jacket_Long", 210, false], ["Brown coat", "#5f4330", &"Jacket_Long", 220, false], ["Navy coat", "#25324d", &"Jacket_Long", 220, false],
		["Grey coat", "#9a958c", &"Jacket_Long", 200, false]]
	for j in jackets:
		_add(&"jackets", "jacket_" + String(j[0]).to_lower().replace(" ", "_"), j[0], j[3], j[4], {"jacket": j[2], "jacket_color": Color(j[1])}, Color(j[1]))
	# ---- pants
	var pants := [["Navy jeans", "#25324d", 55, true], ["Black jeans", "#15171a", 55, true], ["Charcoal slacks", "#2a2d33", 60, true], ["Steel blue jeans", "#3f5a80", 60, false],
		["Khaki chinos", "#b9a77d", 65, false], ["Grey trousers", "#9a958c", 65, false], ["Brown cords", "#5f4330", 70, false], ["Plum trousers", "#7b4b7a", 85, false]]
	for p in pants:
		_add(&"pants", "pants_" + String(p[0]).to_lower().replace(" ", "_"), p[0], p[2], p[3], {"pants": Color(p[1])}, Color(p[1]))
	# ---- shoes
	var shoes := [["White sneakers", "#f2f0ea", 70, true], ["Black sneakers", "#15171a", 70, true], ["Brown boots", "#5f4330", 90, false], ["Red high-tops", "#d93a3a", 95, false],
		["Navy runners", "#25324d", 80, false], ["Cream loafers", "#e6e2d6", 85, false]]
	for s in shoes:
		_add(&"shoes", "shoes_" + String(s[0]).to_lower().replace(" ", "_").replace("-", "_"), s[0], s[2], s[3], {"shoes": Color(s[1])}, Color(s[1]))
	# ---- hats
	_add(&"hats", "hat_none", "No hat", 0, true, {"hat": &""}, Color("#555b66"))
	var caps := [["Teal cap", "#2f9c95", 25, true], ["Black cap", "#15171a", 25, true], ["Coral cap", "#e8795f", 28, false], ["Navy cap", "#25324d", 28, false], ["White cap", "#f2f0ea", 28, false]]
	for c in caps:
		_add(&"hats", "hat_" + String(c[0]).to_lower().replace(" ", "_"), c[0], c[2], c[3], {"hat": &"Hat_Cap", "hat_color": Color(c[1])}, Color(c[1]))
	var beanies := [["Charcoal beanie", "#2a2d33", 22, true], ["Mustard beanie", "#e0b04a", 24, false], ["Plum beanie", "#7b4b7a", 24, false], ["Teal beanie", "#2f9c95", 24, false]]
	for b in beanies:
		_add(&"hats", "hat_" + String(b[0]).to_lower().replace(" ", "_"), b[0], b[2], b[3], {"hat": &"Hat_Beanie", "hat_color": Color(b[1])}, Color(b[1]))
	# ---- glasses
	_add(&"glasses", "glasses_none", "No glasses", 0, true, {"glasses": &""}, Color("#555b66"))
	_add(&"glasses", "glasses_round", "Round frames", 35, true, {"glasses": &"Glasses_Round"}, Color("#d9a63a"))
	_add(&"glasses", "glasses_shades", "Dark shades", 45, false, {"glasses": &"Glasses_Shades"}, Color("#15171a"))
	# ---- bags
	_add(&"packs", "pack_none", "No bag", 0, true, {"backpack": &""}, Color("#555b66"))
	var packs := [["Charcoal backpack", "#2b2e33", 75, true], ["Coral backpack", "#e8795f", 80, false], ["Teal backpack", "#2f9c95", 80, false], ["Mustard backpack", "#e0b04a", 80, false]]
	for k in packs:
		_add(&"packs", "pack_" + String(k[0]).to_lower().replace(" ", "_"), k[0], k[2], k[3], {"backpack": &"Backpack", "pack_color": Color(k[1])}, Color(k[1]))


static func items(cat: StringName) -> Array:
	_build()
	return _items.get(cat, [])


static func find(key: String) -> Dictionary:
	_build()
	return _by_key.get(key, {})


static func all_keys() -> Array:
	_build()
	return _by_key.keys()


## Item that is currently worn in `variant` for the category (best effort, by delta comparison) or {}.
static func worn_in(cat: StringName, variant: Dictionary) -> Dictionary:
	for it in items(cat):
		var ok := true
		for k in (it["delta"] as Dictionary):
			var a: Variant = variant.get(k, null)
			var b: Variant = it["delta"][k]
			if a is Color and b is Color:
				if not (a as Color).is_equal_approx(b):
					ok = false
					break
			elif String(a if a != null else "") != String(b):
				ok = false
				break
		if ok:
			return it
	return {}
