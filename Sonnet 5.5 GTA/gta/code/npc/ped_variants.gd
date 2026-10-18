class_name PedVariants
extends RefCounted
## District / role specific outfits for pedestrians, built on CharacterVariants.random_pedestrian (body, skin, hair, scale stay
## varied; shirt / pants / hat / jacket / accessories are overridden by the look style). All colours come from the Halcyon palette.

const BIZ_SHIRTS: Array[Color] = [Color("#f2f0ea"), Color("#8fc6e8"), Color("#e6e2d6"), Color("#5b7fa6"), Color("#f0b290"), Color("#25324d"), Color("#e6d5b8")]
const BIZ_PANTS: Array[Color] = [Color("#2a2d33"), Color("#25324d"), Color("#15171a"), Color("#4b525b"), Color("#3f5a80"), Color("#5f4330")]
const BIZ_JACKETS: Array[Color] = [Color("#2a2d33"), Color("#25324d"), Color("#4b525b"), Color("#15171a"), Color("#5f4330"), Color("#9a958c")]
const BIZ_SHOES: Array[Color] = [Color("#15171a"), Color("#5f4330"), Color("#2a2d33")]
const HIVIS: Array[Color] = [Color("#ee8a2b"), Color("#f2cf3a"), Color("#e0b04a"), Color("#ee8a2b")]
const WORK_PANTS: Array[Color] = [Color("#25324d"), Color("#4b525b"), Color("#5f4330"), Color("#2a2d33"), Color("#3f5a80")]
const BEACH_TOPS: Array[Color] = [Color("#e8795f"), Color("#2f9c95"), Color("#f2cf3a"), Color("#ff3d9a"), Color("#34e0ff"), Color("#f2f0ea"), Color("#8fc6e8"), Color("#ee8a2b"), Color("#4f9d52")]
const BEACH_PANTS: Array[Color] = [Color("#f2f0ea"), Color("#b9a77d"), Color("#e6d5b8"), Color("#34e0ff"), Color("#e8795f"), Color("#8fc6e8"), Color("#f2cf3a")]
const SPORT_TOPS: Array[Color] = [Color("#34e0ff"), Color("#ff3d9a"), Color("#f2cf3a"), Color("#4f9d52"), Color("#ee8a2b"), Color("#d93a3a"), Color("#f2f0ea")]
const SPORT_PANTS: Array[Color] = [Color("#15171a"), Color("#25324d"), Color("#2a2d33"), Color("#4b525b")]
const ELDER_TOPS: Array[Color] = [Color("#e6d5b8"), Color("#7ea286"), Color("#8fc6e8"), Color("#a4553f"), Color("#7b4b7a"), Color("#e6e2d6")]
const ELDER_JACKETS: Array[Color] = [Color("#9a958c"), Color("#5f4330"), Color("#7b4b7a"), Color("#25324d"), Color("#b9a77d")]
const SKIN_ELDER_HAIR: Array[Color] = [Color("#a9a39a"), Color("#d8d4cc"), Color("#a9a39a"), Color("#4a3022")]
const TAXI_SHIRT := Color("#f2cf3a")


static func make(look: StringName, rng: RandomNumberGenerator) -> Dictionary:
	if look == &"shop":
		var s := CharacterVariants.shop_staff(rng)
		s["kind"] = &"shop"
		return s
	var v := CharacterVariants.random_pedestrian(rng)
	v["kind"] = &"pedestrian"
	match look:
		&"business":
			_business(v, rng)
		&"worker":
			_worker(v, rng)
		&"beach":
			_beach(v, rng)
		&"jogger":
			_jogger(v, rng)
		&"tourist":
			_tourist(v, rng)
		&"elder":
			_elder(v, rng)
		&"taxi":
			_taxi(v, rng)
		&"casual", &"plain", _:
			_casual(v, rng)
	return v


static func _pick(arr: Array, rng: RandomNumberGenerator) -> Variant:
	return arr[rng.randi() % arr.size()]


static func _business(v: Dictionary, rng: RandomNumberGenerator) -> void:
	v["shirt"] = _pick(BIZ_SHIRTS, rng)
	v["pants"] = _pick(BIZ_PANTS, rng)
	v["shoes"] = _pick(BIZ_SHOES, rng)
	v["accent"] = _pick([Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347"), Color("#2b2e33")], rng)
	v["hat"] = &""
	v["jacket"] = &"Jacket_Short" if rng.randf() < 0.5 else (&"Jacket_Long" if rng.randf() < 0.55 else &"")
	v["jacket_color"] = _pick(BIZ_JACKETS, rng)
	v["glasses"] = &"Glasses_Round" if rng.randf() < 0.18 else (&"Glasses_Shades" if rng.randf() < 0.12 else &"")
	v["backpack"] = &""
	if rng.randf() < 0.05:
		v["backpack"] = &"Backpack"
		v["pack_color"] = Color("#2a2d33")
	if v["body"] == &"C":
		v["body"] = &"A" if rng.randf() < 0.55 else &"C"
	v["scale"] = clampf(float(v.get("scale", 1.0)), 0.96, 1.06)


static func _casual(v: Dictionary, rng: RandomNumberGenerator) -> void:
	# keep the random casual palette of CharacterVariants, add some hats / caps for variety
	if rng.randf() < 0.18 and String(v.get("hat", "")) == "":
		v["hat"] = &"Hat_Cap" if rng.randf() < 0.6 else &"Hat_Beanie"
		v["hat_color"] = _pick(CharacterVariants.SHIRTS, rng)


static func _worker(v: Dictionary, rng: RandomNumberGenerator) -> void:
	v["shirt"] = _pick(HIVIS, rng) if rng.randf() < 0.75 else _pick(CharacterVariants.SHIRTS, rng)
	v["pants"] = _pick(WORK_PANTS, rng)
	v["shoes"] = _pick([Color("#5f4330"), Color("#15171a"), Color("#2a2d33")], rng)
	v["accent"] = Color("#f2cf3a")
	if rng.randf() < 0.7:
		v["hat"] = &"Hat_Cap"
		v["hat_color"] = Color("#f2cf3a") if rng.randf() < 0.6 else Color("#ee8a2b")
	else:
		v["hat"] = &""
	v["jacket"] = &"Jacket_Short" if rng.randf() < 0.25 else &""
	v["jacket_color"] = _pick(HIVIS, rng)
	v["glasses"] = &"Glasses_Shades" if rng.randf() < 0.15 else &""
	if rng.randf() < 0.35:
		v["body"] = &"C"
	if v["body"] != &"B" and rng.randf() < 0.3:
		v["beard"] = &"Beard_1" if rng.randf() < 0.6 else &"Beard_2"


static func _beach(v: Dictionary, rng: RandomNumberGenerator) -> void:
	v["shirt"] = _pick(BEACH_TOPS, rng)
	v["pants"] = _pick(BEACH_PANTS, rng)
	v["shoes"] = _pick([Color("#f2f0ea"), Color("#e6d5b8"), Color("#34e0ff"), Color("#ff3d9a")], rng)
	v["accent"] = _pick([Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347")], rng)
	v["jacket"] = &""
	v["backpack"] = &"Backpack" if rng.randf() < 0.1 else &""
	v["pack_color"] = _pick(BEACH_TOPS, rng)
	v["glasses"] = &"Glasses_Shades" if rng.randf() < 0.55 else &""
	v["hat"] = &"Hat_Cap" if rng.randf() < 0.28 else &""
	v["hat_color"] = _pick(BEACH_TOPS, rng)
	# beach-goers tend to be a bit tanner: bias the skin tone darker a touch
	var sk: Color = v["skin"]
	v["skin"] = sk.darkened(0.06)


static func _jogger(v: Dictionary, rng: RandomNumberGenerator) -> void:
	v["shirt"] = _pick(SPORT_TOPS, rng)
	v["pants"] = _pick(SPORT_PANTS, rng)
	v["shoes"] = _pick([Color("#f2f0ea"), Color("#f2f0ea"), Color("#ff3d9a"), Color("#34e0ff")], rng)
	v["accent"] = _pick([Color("#ff3d9a"), Color("#34e0ff"), Color("#f2cf3a")], rng)
	v["jacket"] = &""
	v["backpack"] = &""
	v["hat"] = &"Hat_Cap" if rng.randf() < 0.3 else &""
	v["hat_color"] = _pick(SPORT_TOPS, rng)
	v["glasses"] = &"Glasses_Shades" if rng.randf() < 0.25 else &""
	v["beard"] = &"" if rng.randf() < 0.7 else v.get("beard", &"")
	if v["body"] == &"C":
		v["body"] = &"A"
	v["scale"] = clampf(float(v.get("scale", 1.0)), 0.95, 1.05)


static func _tourist(v: Dictionary, rng: RandomNumberGenerator) -> void:
	v["shirt"] = _pick(BEACH_TOPS, rng)
	v["pants"] = _pick([Color("#b9a77d"), Color("#3f5a80"), Color("#9a958c"), Color("#e6d5b8")], rng)
	v["hat"] = &"Hat_Cap" if rng.randf() < 0.55 else &""
	v["hat_color"] = _pick(BEACH_TOPS, rng)
	v["glasses"] = &"Glasses_Shades" if rng.randf() < 0.6 else &"Glasses_Round" if rng.randf() < 0.2 else &""
	v["backpack"] = &"Backpack" if rng.randf() < 0.75 else &""
	v["pack_color"] = _pick([Color("#ee8a2b"), Color("#2f9c95"), Color("#d93a3a"), Color("#34e0ff")], rng)
	v["jacket"] = &""


static func _elder(v: Dictionary, rng: RandomNumberGenerator) -> void:
	v["shirt"] = _pick(ELDER_TOPS, rng)
	v["pants"] = _pick([Color("#4b525b"), Color("#5f4330"), Color("#b9a77d"), Color("#25324d")], rng)
	v["shoes"] = _pick([Color("#15171a"), Color("#5f4330"), Color("#e6e2d6")], rng)
	v["hair_color"] = _pick(SKIN_ELDER_HAIR, rng)
	v["hair"] = 0 if (v["body"] != &"B" and rng.randf() < 0.3) else (2 if v["body"] != &"B" else 4)
	v["jacket"] = &"Jacket_Long" if rng.randf() < 0.45 else (&"Jacket_Short" if rng.randf() < 0.5 else &"")
	v["jacket_color"] = _pick(ELDER_JACKETS, rng)
	v["glasses"] = &"Glasses_Round" if rng.randf() < 0.5 else &""
	v["hat"] = &"Hat_Beanie" if rng.randf() < 0.18 else &""
	v["hat_color"] = _pick(ELDER_JACKETS, rng)
	v["backpack"] = &""
	if v["body"] == &"C" and rng.randf() < 0.4:
		v["body"] = &"A"
	v["scale"] = rng.randf_range(0.92, 0.99)


static func _taxi(v: Dictionary, rng: RandomNumberGenerator) -> void:
	v["shirt"] = _pick([Color("#f2f0ea"), Color("#8fc6e8"), TAXI_SHIRT], rng)
	v["pants"] = _pick([Color("#15171a"), Color("#2a2d33")], rng)
	v["hat"] = &"Hat_Cap"
	v["hat_color"] = TAXI_SHIRT
	v["jacket"] = &"Jacket_Short" if rng.randf() < 0.35 else &""
	v["jacket_color"] = Color("#2a2d33")
	v["accent"] = TAXI_SHIRT
	v["glasses"] = &"Glasses_Shades" if rng.randf() < 0.25 else &""
	v["backpack"] = &""
	if v["body"] == &"B" and rng.randf() < 0.55:
		v["body"] = &"A"


## Look style of a driver for a given vehicle id / class (VehicleDefs ids).
static func look_for_vehicle(def_id: StringName, vclass: StringName, rng: RandomNumberGenerator) -> StringName:
	match def_id:
		&"taxi":
			return &"taxi"
		&"truck", &"van", &"pickup", &"firetruck":
			return &"worker"
		&"sports", &"muscle":
			return &"casual" if rng.randf() < 0.6 else &"business"
		&"suv", &"sedan", &"compact":
			return &"business" if rng.randf() < 0.4 else &"casual"
		&"ambulance":
			return &"business"
	if vclass == GC.VC_BIKE or vclass == GC.VC_BICYCLE:
		return &"jogger" if vclass == GC.VC_BICYCLE else &"casual"
	return &"casual"
