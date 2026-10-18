class_name CharacterVariants
extends RefCounted
## Appearance generators for CharacterRig.setup(variant). Every function returns a fresh Dictionary:
##   body: &"A"|&"B"|&"C"            A = average masculine, B = average feminine, C = stocky
##   skin, hair_color, shirt, pants, shoes, accent: Color
##   hair: int (0 = bald, 1..6)      hat: &"" | &"Hat_Cap" | &"Hat_Beanie" | &"Hat_Police" | &"Helmet_Tactical"
##   glasses: &"" | &"Glasses_Round" | &"Glasses_Shades"      jacket: &"" | &"Jacket_Short" | &"Jacket_Long"
##   vest: &"" | &"Vest_Armor" | &"Vest_Tactical"           backpack: &"" | &"Backpack"       beard: &"" | &"Beard_1" | &"Beard_2"
##   scale: float (0.92 .. 1.08)
##   optional colour overrides: jacket_color, vest_color, hat_color, pack_color
##   kind: &"pedestrian" &"police" &"tactical" &"shop" &"gang" &"player"  (informational)
## All colours come from the Halcyon palette (see tools/blender/gta_lib.py PAL).

const SKIN: Array[Color] = [Color("#f1c9a5"), Color("#d9a77c"), Color("#b57e57"), Color("#8a5a3c"), Color("#5e3b27")]
const SKIN_WEIGHTS: Array[float] = [0.26, 0.28, 0.20, 0.16, 0.10]
const HAIR_COLORS: Array[Color] = [Color("#1a1512"), Color("#4a3022"), Color("#d6b46a"), Color("#a8482a"), Color("#a9a39a")]
const HAIR_WEIGHTS: Array[float] = [0.38, 0.30, 0.14, 0.08, 0.10]
const SHIRTS: Array[Color] = [Color("#e8795f"), Color("#2f9c95"), Color("#e0b04a"), Color("#5b7fa6"), Color("#7ea286"), Color("#7b4b7a"),
	Color("#a4553f"), Color("#25324d"), Color("#8fc6e8"), Color("#f0b290"), Color("#f2f0ea"), Color("#e6e2d6"), Color("#ee8a2b"),
	Color("#4f9d52"), Color("#d93a3a"), Color("#2a2d33"), Color("#e6d5b8")]
const PANTS: Array[Color] = [Color("#25324d"), Color("#2a2d33"), Color("#3f5a80"), Color("#9a958c"), Color("#b9a77d"), Color("#4b525b"),
	Color("#5f4330"), Color("#15171a"), Color("#6d7b8d"), Color("#7b4b7a")]
const SHOES: Array[Color] = [Color("#15171a"), Color("#f2f0ea"), Color("#2a2d33"), Color("#5f4330"), Color("#d93a3a"), Color("#e6e2d6"), Color("#25324d")]
const ACCENTS: Array[Color] = [Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347"), Color("#e8795f"), Color("#2f9c95"), Color("#f2cf3a"), Color("#2b2e33")]

const POLICE_SHIRT := Color("#3d5f93")
const POLICE_PANTS := Color("#1d2740")
const TACTICAL_SHIRT := Color("#23262b")
const TACTICAL_PANTS := Color("#1d2024")
const GANG_A := Color("#ff3d9a")     # "Neon Vipers" colours
const GANG_B := Color("#15171a")

const COLOR_NAMES := {
	"white": Color("#f2f0ea"), "cream": Color("#e6d5b8"), "grey": Color("#9a958c"), "charcoal": Color("#2a2d33"), "black": Color("#15171a"),
	"coral": Color("#e8795f"), "teal": Color("#2f9c95"), "mustard": Color("#e0b04a"), "blue": Color("#5b7fa6"), "sage": Color("#7ea286"),
	"plum": Color("#7b4b7a"), "brick": Color("#a4553f"), "navy": Color("#25324d"), "sky blue": Color("#8fc6e8"), "peach": Color("#f0b290"),
	"magenta": Color("#ff3d9a"), "cyan": Color("#34e0ff"), "amber": Color("#ffb347"), "red": Color("#d93a3a"), "green": Color("#4f9d52"),
	"yellow": Color("#f2cf3a"), "orange": Color("#ee8a2b"), "brown": Color("#5f4330"), "khaki": Color("#b9a77d"), "steel blue": Color("#3f5a80"),
	"police blue": Color("#3d5f93"),
}

static var _rng: RandomNumberGenerator = null


static func _r(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng != null:
		return rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


static func _pick(arr: Array, rng: RandomNumberGenerator) -> Variant:
	return arr[rng.randi() % arr.size()]


static func _pick_weighted(items: Array, weights: Array, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for w in weights:
		total += float(w)
	var t := rng.randf() * total
	for i in items.size():
		t -= float(weights[i])
		if t <= 0.0:
			return items[i]
	return items[items.size() - 1]


static func _jitter(c: Color, rng: RandomNumberGenerator, amt: float = 0.04) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amt, amt), 0.0, 1.0), clampf(c.g + rng.randf_range(-amt, amt), 0.0, 1.0),
		clampf(c.b + rng.randf_range(-amt, amt), 0.0, 1.0))


static func _base(rng: RandomNumberGenerator, kind: StringName) -> Dictionary:
	var body: StringName = _pick_weighted([&"A", &"B", &"C"], [0.42, 0.40, 0.18], rng)
	var skin: Color = _pick_weighted(SKIN, SKIN_WEIGHTS, rng)
	return {
		"kind": kind, "body": body, "skin": _jitter(skin, rng, 0.015), "hair": 1, "hair_color": _pick_weighted(HAIR_COLORS, HAIR_WEIGHTS, rng),
		"shirt": _pick(SHIRTS, rng), "pants": _pick(PANTS, rng), "shoes": _pick(SHOES, rng), "accent": _pick(ACCENTS, rng),
		"hat": &"", "glasses": &"", "jacket": &"", "vest": &"", "backpack": &"", "beard": &"",
		"scale": rng.randf_range(0.92, 1.08),
	}


## Hair styles that suit the body type: A mostly short, B mostly long / ponytail, C short or bald.
static func _hair_for(body: StringName, rng: RandomNumberGenerator) -> int:
	var t := rng.randf()
	match body:
		&"B":
			return 3 if t < 0.34 else (4 if t < 0.58 else (2 if t < 0.78 else (5 if t < 0.88 else 1)))
		&"C":
			return 0 if t < 0.22 else (1 if t < 0.6 else (2 if t < 0.82 else 6))
		_:
			return 0 if t < 0.07 else (1 if t < 0.38 else (2 if t < 0.66 else (6 if t < 0.76 else (5 if t < 0.86 else 4))))


# ---- Public generators --------------------------------------------------------------------------------------------------
static func random_pedestrian(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _r(rng)
	var v := _base(r, &"pedestrian")
	var body: StringName = v["body"]
	v["hair"] = _hair_for(body, r)
	var t := r.randf()
	if t < 0.06:
		v["hat"] = &"Hat_Cap"
	elif t < 0.115:
		v["hat"] = &"Hat_Beanie"
	if v["hat"] != &"":
		v["hat_color"] = _pick(SHIRTS, r)
	if r.randf() < 0.14:
		v["glasses"] = &"Glasses_Round" if r.randf() < 0.45 else &"Glasses_Shades"
	var tj := r.randf()
	if tj < 0.18:
		v["jacket"] = &"Jacket_Short"
		v["jacket_color"] = _pick(SHIRTS, r)
	elif tj < 0.27:
		v["jacket"] = &"Jacket_Long"
		v["jacket_color"] = _pick([Color("#2a2d33"), Color("#25324d"), Color("#5f4330"), Color("#9a958c"), Color("#7b4b7a"), Color("#a4553f")], r)
	if r.randf() < 0.08:
		v["backpack"] = &"Backpack"
		v["pack_color"] = _pick(ACCENTS, r)
	if body != &"B" and r.randf() < 0.17:
		v["beard"] = &"Beard_1" if r.randf() < 0.6 else &"Beard_2"
	# keep shirt and trousers from being identical
	if (v["shirt"] as Color).is_equal_approx(v["pants"]):
		v["pants"] = PANTS[0]
	return v


static func police_officer(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _r(rng)
	var v := _base(r, &"police")
	var body: StringName = v["body"]
	if body == &"B" and r.randf() < 0.4:
		v["body"] = &"A"
	v["shirt"] = _jitter(POLICE_SHIRT, r, 0.02)
	v["pants"] = _jitter(POLICE_PANTS, r, 0.015)
	v["shoes"] = Color("#15171a")
	v["accent"] = Color("#ffb347")
	v["hair"] = clampi(_hair_for(v["body"], r), 0, 2) if v["body"] != &"B" else (4 if r.randf() < 0.5 else 2)
	v["hat"] = &"Hat_Police" if r.randf() < 0.72 else &""
	v["hat_color"] = Color("#1d2740")
	if r.randf() < 0.3:
		v["glasses"] = &"Glasses_Shades"
	if r.randf() < 0.28:
		v["vest"] = &"Vest_Armor"
		v["vest_color"] = Color("#15171a")
	if v["body"] != &"B" and r.randf() < 0.12:
		v["beard"] = &"Beard_1"
	v["scale"] = r.randf_range(0.97, 1.06)
	return v


static func tactical_officer(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _r(rng)
	var v := _base(r, &"tactical")
	if v["body"] == &"B" and r.randf() < 0.5:
		v["body"] = &"C"
	v["shirt"] = _jitter(TACTICAL_SHIRT, r, 0.012)
	v["pants"] = _jitter(TACTICAL_PANTS, r, 0.012)
	v["shoes"] = Color("#15171a")
	v["accent"] = Color("#2b2e33")
	v["hair"] = 0
	v["hat"] = &"Helmet_Tactical"
	v["hat_color"] = Color("#23262b")
	v["vest"] = &"Vest_Tactical"
	v["vest_color"] = Color("#3a3f47")
	if r.randf() < 0.55:
		v["glasses"] = &"Glasses_Shades"
	if r.randf() < 0.25:
		v["backpack"] = &"Backpack"
		v["pack_color"] = Color("#2b2e33")
	v["scale"] = r.randf_range(1.0, 1.08)
	return v


static func shop_staff(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _r(rng)
	var v := _base(r, &"shop")
	v["hair"] = _hair_for(v["body"], r)
	v["shirt"] = _pick([Color("#2f9c95"), Color("#e0b04a"), Color("#e8795f"), Color("#5b7fa6"), Color("#ff3d9a"), Color("#f2f0ea")], r)
	v["pants"] = _pick([Color("#25324d"), Color("#2a2d33"), Color("#15171a"), Color("#3f5a80")], r)
	v["accent"] = _pick([Color("#ff3d9a"), Color("#34e0ff"), Color("#ffb347")], r)
	v["shoes"] = _pick([Color("#15171a"), Color("#f2f0ea"), Color("#2a2d33")], r)
	if r.randf() < 0.2:
		v["hat"] = &"Hat_Cap"
		v["hat_color"] = v["accent"]
	if r.randf() < 0.12:
		v["glasses"] = &"Glasses_Round"
	if v["body"] != &"B" and r.randf() < 0.15:
		v["beard"] = &"Beard_1"
	v["scale"] = r.randf_range(0.95, 1.05)
	return v


static func gang_member(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _r(rng)
	var v := _base(r, &"gang")
	if v["body"] == &"B" and r.randf() < 0.5:
		v["body"] = &"A"
	v["hair"] = _pick([0, 1, 6, 5, 1, 2], r)
	v["shirt"] = GANG_B if r.randf() < 0.5 else _jitter(GANG_A, r, 0.02)
	v["jacket"] = &"Jacket_Short"
	v["jacket_color"] = GANG_A if (v["shirt"] as Color).is_equal_approx(GANG_B) else GANG_B
	v["pants"] = _pick([Color("#15171a"), Color("#2a2d33"), Color("#4b525b")], r)
	v["shoes"] = _pick([Color("#15171a"), Color("#f2f0ea"), Color("#ff3d9a")], r)
	v["accent"] = Color("#ff3d9a")
	var t := r.randf()
	if t < 0.3:
		v["hat"] = &"Hat_Beanie"
		v["hat_color"] = GANG_B
	elif t < 0.5:
		v["hat"] = &"Hat_Cap"
		v["hat_color"] = GANG_A
	if r.randf() < 0.45:
		v["glasses"] = &"Glasses_Shades"
	if r.randf() < 0.2:
		v["vest"] = &"Vest_Armor"
		v["vest_color"] = Color("#2b2e33")
	if v["body"] != &"B" and r.randf() < 0.35:
		v["beard"] = &"Beard_1" if r.randf() < 0.5 else &"Beard_2"
	v["scale"] = r.randf_range(0.96, 1.08)
	return v


## The player's signature look: teal bomber jacket over a white tee, navy jeans, white sneakers with magenta trim,
## swept dark-brown hair and a short stubble beard.
static func player_default() -> Dictionary:
	return {
		"kind": &"player", "body": &"A", "skin": SKIN[1], "hair": 2, "hair_color": Color("#2a1c14"),
		"shirt": Color("#f2f0ea"), "pants": Color("#25324d"), "shoes": Color("#f2f0ea"), "accent": Color("#ff3d9a"),
		"hat": &"", "glasses": &"", "jacket": &"Jacket_Short", "jacket_color": Color("#2f9c95"), "vest": &"", "backpack": &"",
		"beard": &"Beard_1", "scale": 1.0,
	}


## Dispatch by kind name (&"pedestrian" &"police" &"tactical" &"shop" &"gang" &"player").
static func make(kind: StringName, rng: RandomNumberGenerator = null) -> Dictionary:
	match kind:
		&"police":
			return police_officer(rng)
		&"tactical":
			return tactical_officer(rng)
		&"shop":
			return shop_staff(rng)
		&"gang":
			return gang_member(rng)
		&"player":
			return player_default()
	return random_pedestrian(rng)


# ---- Naming ------------------------------------------------------------------------------------------------------------------
static func color_name(c: Color) -> String:
	var best := "grey"
	var best_d := 1e9
	for n in COLOR_NAMES:
		var o: Color = COLOR_NAMES[n]
		var d := (c.r - o.r) * (c.r - o.r) * 0.9 + (c.g - o.g) * (c.g - o.g) * 1.2 + (c.b - o.b) * (c.b - o.b) * 0.8
		if d < best_d:
			best_d = d
			best = n
	return best


static func hair_name(style: int, c: Color) -> String:
	var shades: Dictionary = {0: "bald", 1: "cropped", 2: "side-parted", 3: "long", 4: "ponytailed", 5: "curly", 6: "mohawked"}
	if style <= 0:
		return "bald"
	var cn := color_name(c)
	if cn in ["black", "charcoal"]:
		cn = "black"
	elif cn in ["brown", "brick", "coral", "orange"]:
		cn = "brown" if cn == "brown" else "red"
	elif cn in ["mustard", "cream", "amber", "yellow", "peach"]:
		cn = "blond"
	elif cn in ["grey", "white", "steel blue"]:
		cn = "grey"
	return "%s %s" % [shades.get(style, "short"), cn]


## Short human readable description, e.g. "feminine ponytailed brown hair, teal jacket, navy trousers, cap".
static func appearance_name(v: Dictionary) -> String:
	var body: StringName = v.get("body", &"A")
	var who := "man"
	match body:
		&"B":
			who = "woman"
		&"C":
			who = "stocky man"
	var kind: StringName = v.get("kind", &"pedestrian")
	var role := ""
	match kind:
		&"police":
			role = "police officer"
		&"tactical":
			role = "tactical officer"
		&"shop":
			role = "shop assistant"
		&"gang":
			role = "gang member"
		&"player":
			role = "protagonist"
	var parts: Array[String] = []
	var hair_v: Variant = v.get("hair", 1)
	var style: int = int(hair_v) if (hair_v is int or hair_v is float) else int(v.get("hair_style", 1))
	var hc: Color = v.get("hair_color", hair_v if hair_v is Color else Color("#4a3022"))
	if style > 0 and String(v.get("hat", "")) == "":
		parts.append(hair_name(style, hc) + " hair")
	elif style <= 0 and String(v.get("hat", "")) == "":
		parts.append("bald")
	var top_col: Color = v.get("shirt", Color.WHITE)
	var top := "shirt"
	if String(v.get("jacket", "")) != "":
		top = "jacket" if String(v.get("jacket")) == "Jacket_Short" else "long coat"
		top_col = v.get("jacket_color", top_col)
	parts.append("%s %s" % [color_name(top_col), top])
	if String(v.get("vest", "")) != "":
		parts.append("armor vest" if String(v.get("vest")) == "Vest_Armor" else "tactical vest")
	parts.append("%s trousers" % color_name(v.get("pants", Color.BLACK)))
	var hat := String(v.get("hat", ""))
	if hat != "":
		parts.append({"Hat_Cap": "cap", "Hat_Beanie": "beanie", "Hat_Police": "police cap", "Helmet_Tactical": "tactical helmet"}.get(hat, "hat"))
	var gl := String(v.get("glasses", ""))
	if gl != "":
		parts.append("shades" if gl == "Glasses_Shades" else "round glasses")
	if String(v.get("backpack", "")) != "":
		parts.append("backpack")
	if String(v.get("beard", "")) != "":
		parts.append("beard")
	var head := (role if role != "" else who)
	if role != "" and body == &"B":
		head = "female " + role
	return "%s, %s" % [head.capitalize() if role == "" else head, ", ".join(parts)]
