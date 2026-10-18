class_name GarageBuild
extends RefCounted
## One vehicle's customization state (paint, finish, the mods dictionary). Used for the garage session (committed vs pending
## build, live preview), for the cost breakdown of pending changes, and for (de)serialising stored vehicles.
## `mods` is exactly the dictionary that ends up in VehicleBase.mods: integer performance levels + cosmetic keys
## (see VehicleModsData.COSMETIC_KEYS). A missing key means "stock".

var def_id: StringName = &"sedan"
var paint1 := Color(0.75, 0.15, 0.15)
var paint2 := Color(0.1, 0.1, 0.12)
var finish: StringName = &"gloss"
var mods: Dictionary = {}


static func from_vehicle(v: VehicleBase) -> GarageBuild:
	var b := GarageBuild.new()
	b.def_id = v.def_id
	b.paint1 = v.paint_primary
	b.paint2 = v.paint_secondary
	b.finish = v.paint_finish
	b.mods = v.mods.duplicate(true)
	return b


func copy() -> GarageBuild:
	var b := GarageBuild.new()
	b.def_id = def_id
	b.paint1 = paint1
	b.paint2 = paint2
	b.finish = finish
	b.mods = mods.duplicate(true)
	return b


## Pushes this build onto a live vehicle (paint first, then mods -> VehicleBase.apply_mods -> visual hook).
func apply_to(v: VehicleBase) -> void:
	if v == null or not is_instance_valid(v):
		return
	v.set_paint(paint1, paint2, finish)
	v.apply_mods(mods.duplicate(true))
	v.set_paint(paint1, paint2, finish)         # parts built by the hook pick up the paint


func equals(o: GarageBuild) -> bool:
	if o == null:
		return false
	return diff_against(o, false).is_empty()


# ---- mods dictionary helpers ---------------------------------------------------------------------------------------------
func level(key: String) -> int:
	return int(mods.get(key, 0))


func set_level(key: String, lvl: int) -> void:
	if lvl <= 0:
		mods.erase(key)
	else:
		mods[key] = lvl


func get_id(key: String, default_id: String = "stock") -> StringName:
	return StringName(mods.get(key, default_id))


func set_id(key: String, id: StringName, default_id: String = "stock") -> void:
	if String(id) == default_id:
		mods.erase(key)
	else:
		mods[key] = String(id)


func part(slot: StringName) -> StringName:
	return get_id("p_" + String(slot))


func set_part(slot: StringName, id: StringName) -> void:
	set_id("p_" + String(slot), id)


# =====================================================================================================
# Cost / diff
# =====================================================================================================
## Entries {key, label, price} for everything in `self` that costs money compared with `base` (upgrades only).
## With price_mult applied by the caller via price_mult (vehicle class factor); unlock_all => every price is 0.
func diff_against(base: GarageBuild, include_prices: bool = true, price_mult: float = 1.0, unlock_all: bool = false) -> Array:
	var out: Array = []
	var pm := 0.0 if unlock_all else price_mult
	var add := func(key: String, label: String, price: int) -> void:
		out.append({"key": key, "label": label, "price": int(round(float(price) * pm / 10.0)) * 10 if include_prices else 0})
	if not paint1.is_equal_approx(base.paint1):
		add.call("paint1", "Primary paint: %s" % color_name(paint1), VehicleModsData.PAINT_PRICE)
	if not paint2.is_equal_approx(base.paint2):
		add.call("paint2", "Secondary paint: %s" % color_name(paint2), VehicleModsData.PAINT_PRICE)
	if finish != base.finish:
		add.call("finish", "Finish: %s" % String(finish).capitalize(), VehicleModsData.finish_price(finish))
	for p in VehicleModsData.performance():
		var key: String = p["key"]
		var a := base.level(key)
		var b := level(key)
		if a != b:
			var lv: Array = p["levels"]
			add.call(key, "%s: %s" % [p["name"], lv[clampi(b, 0, lv.size() - 1)]["name"]], VehicleModsData.perf_cost(key, a, b))
	for slot in VehicleModsData.SLOTS:
		var ida := base.part(slot)
		var idb := part(slot)
		if ida != idb:
			var o := VehicleModsData.slot_option(slot, idb)
			add.call("p_" + String(slot), "%s: %s" % [VehicleModsData.SLOT_NAMES.get(slot, slot), o.get("name", "Stock")], int(o.get("price", 0)))
	if get_id("rim_style") != base.get_id("rim_style"):
		var r := VehicleModsData.rim_def(get_id("rim_style"))
		add.call("rim_style", "Rims: %s" % r["name"], int(r["price"]))
	if _color_changed(mods.get("rim_color", null), base.mods.get("rim_color", null)):
		add.call("rim_color", "Rim colour", VehicleModsData.RIM_COLOR_PRICE if mods.has("rim_color") else 0)
	for pair in [["headlight", VehicleModsData.HEADLIGHTS, "Headlights"], ["taillight", VehicleModsData.TAILLIGHTS, "Tail lights"], ["underglow", VehicleModsData.UNDERGLOW, "Underglow"]]:
		var k: String = pair[0]
		var def_id_s := "off" if k == "underglow" else "stock"
		if get_id(k, def_id_s) != base.get_id(k, def_id_s):
			var price := 0
			var nm := ""
			for o2 in pair[1]:
				if o2["id"] == get_id(k, def_id_s):
					price = int(o2["price"])
					nm = String(o2["name"])
			add.call(k, "%s: %s" % [pair[2], nm], price)
	var tint_a := base.level("window_tint")
	var tint_b := level("window_tint")
	if tint_a != tint_b:
		var tp := int(VehicleModsData.WINDOW_TINTS[clampi(tint_b, 0, 3)]["price"]) if tint_b > tint_a else 0
		add.call("window_tint", "Window tint: %s" % VehicleModsData.WINDOW_TINTS[clampi(tint_b, 0, 3)]["name"], tp)
	if get_id("plate", "") != base.get_id("plate", ""):
		var pp := 0
		var pn := "Stock plate"
		for p2 in VehicleModsData.PLATES:
			if p2["id"] == get_id("plate", ""):
				pp = int(p2["price"])
				pn = String(p2["name"])
		add.call("plate", "Plate: %s" % pn, pp)
	if get_id("livery", "none") != base.get_id("livery", "none"):
		var lp := 0
		var ln := "None"
		for l in VehicleModsData.LIVERIES:
			if l["id"] == get_id("livery", "none"):
				lp = int(l["price"])
				ln = String(l["name"])
		add.call("livery", "Livery: %s" % ln, lp)
	if int(mods.get("horn", 0)) != int(base.mods.get("horn", 0)):
		var hi := clampi(int(mods.get("horn", 0)), 0, VehicleModsData.HORNS.size() - 1)
		add.call("horn", "Horn: %s" % VehicleModsData.HORNS[hi]["name"], int(VehicleModsData.HORNS[hi]["price"]))
	return out


static func total_cost(entries: Array) -> int:
	var t := 0
	for e in entries:
		t += int(e["price"])
	return t


static func _color_changed(a: Variant, b: Variant) -> bool:
	if a == null and b == null:
		return false
	if a is Color and b is Color:
		return not (a as Color).is_equal_approx(b)
	return true


static func color_name(c: Color) -> String:
	var best := ""
	var best_d := 0.0001
	for p in VehicleModsData.palette():
		var d := Vector3(c.r - p["color"].r, c.g - p["color"].g, c.b - p["color"].b).length_squared()
		if best == "" or d < best_d:
			best_d = d
			best = String(p["name"])
	if best_d > 0.004:
		return "Custom #" + c.to_html(false).to_upper()
	return best


# =====================================================================================================
# Serialization (JSON friendly)
# =====================================================================================================
func to_dict() -> Dictionary:
	var m := {}
	for k in mods:
		var v = mods[k]
		if v is Color:
			m[k] = "#" + (v as Color).to_html(false)
		elif v is StringName:
			m[k] = String(v)
		else:
			m[k] = v
	return {"def": String(def_id), "p1": "#" + paint1.to_html(false), "p2": "#" + paint2.to_html(false), "finish": String(finish), "mods": m}


static func from_dict(d: Dictionary) -> GarageBuild:
	var b := GarageBuild.new()
	b.def_id = StringName(d.get("def", "sedan"))
	b.paint1 = Color(String(d.get("p1", "#bf2626")))
	b.paint2 = Color(String(d.get("p2", "#1a1a1f")))
	b.finish = StringName(d.get("finish", "gloss"))
	var m = d.get("mods", {})
	if m is Dictionary:
		for k in m:
			var key := String(k)
			var v = m[k]
			if VehicleModsData.COLOR_KEYS.has(key) and v is String:
				b.mods[key] = Color(v)
			elif v is float and absf(float(v) - roundf(float(v))) < 0.0001:
				b.mods[key] = int(v)           # JSON numbers come back as floats
			else:
				b.mods[key] = v
	return b
