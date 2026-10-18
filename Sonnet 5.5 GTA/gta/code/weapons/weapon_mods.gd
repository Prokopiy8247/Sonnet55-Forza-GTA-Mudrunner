class_name WeaponMods
extends RefCounted
## Weapon customisation table (spec 17A): suppressor, scope, flashlight, grip, extended magazine + cosmetic tint.
## The weapon shop / workbench reads MODS / TINTS / is_compatible() / price(); WeaponController applies the
## gameplay effect through effective(). Mod ids are the attachment model ids without the "att_" prefix.

## mount: attachment point node name in the weapon GLB (empties AttMuzzle/AttOptic/AttRail/AttGrip/AttMag).
## Multipliers default to 1.0 when a key is missing.
const MODS := {
	&"suppressor": {
		"id": &"suppressor", "name": "Suppressor", "desc": "Audible radius -75%, no muzzle flash, slightly lower damage.",
		"model": "weapons/att_suppressor", "mount": &"AttMuzzle", "price": 450,
		"noise_mult": 0.25, "damage_mult": 0.92, "range_mult": 0.95, "flash_mult": 0.15, "length": 0.17,
	},
	&"scope": {
		"id": &"scope", "name": "Optic Scope", "desc": "Mid-range zoom and a tighter aimed spread.",
		"model": "weapons/att_scope", "mount": &"AttOptic", "price": 350,
		"zoom_mult": 1.9, "aim_spread_mult": 0.75,
	},
	&"flashlight": {
		"id": &"flashlight", "name": "Tactical Flashlight", "desc": "Lights up dark areas (T toggles; auto-on while aiming at night).",
		"model": "weapons/att_flashlight", "mount": &"AttRail", "price": 120,
	},
	&"grip": {
		"id": &"grip", "name": "Stability Grip", "desc": "Recoil and spread -25%.",
		"model": "weapons/att_grip", "mount": &"AttGrip", "price": 280,
		"recoil_mult": 0.75, "spread_mult": 0.75, "aim_spread_mult": 0.8,
	},
	&"magazine_ext": {
		"id": &"magazine_ext", "name": "Extended Magazine", "desc": "Magazine capacity x1.5.",
		"model": "weapons/att_magazine_ext", "mount": &"AttMag", "price": 300,
		"mag_mult": 1.5, "reserve_mult": 1.25,
	},
}

const TINT_PRICE := 60
## Cosmetic finishes (Color or hex). The first entry is the factory finish (no override).
const TINTS := {
	&"factory": "",
	&"midnight": "#1f2430",
	&"sand": "#b9a27a",
	&"olive": "#5c6b3f",
	&"crimson": "#a3262e",
	&"cobalt": "#2f5fb0",
	&"magenta": "#ff3d9a",
	&"cyan": "#34e0ff",
	&"gold": "#d4a63a",
	&"arctic": "#d9e2e8",
}

const MOD_ORDER := [&"suppressor", &"scope", &"flashlight", &"grip", &"magazine_ext"]


static func get_mod(mod_id: StringName) -> Dictionary:
	return MODS.get(mod_id, {})


static func ids() -> Array:
	return MOD_ORDER.duplicate()


static func price(mod_id: StringName) -> int:
	return int(MODS.get(mod_id, {}).get("price", 0))


static func is_compatible(weapon_id: StringName, mod_id: StringName) -> bool:
	if not MODS.has(mod_id):
		return false
	var d: Dictionary = WeaponDefs.get_def(weapon_id)
	if d.is_empty():
		return false
	return mod_id in (d["mods"] as Array)


## Mods that can be fitted to this weapon, in display order.
static func compatible_mods(weapon_id: StringName) -> Array:
	var out: Array = []
	var d: Dictionary = WeaponDefs.get_def(weapon_id)
	if d.is_empty():
		return out
	for m in MOD_ORDER:
		if m in (d["mods"] as Array):
			out.append(m)
	return out


static func tint_color(tint_id: StringName) -> Color:
	var h: String = String(TINTS.get(tint_id, ""))
	return Color(h) if h != "" else Color(0, 0, 0, 0)


## Combined multipliers of the installed mods (mods: {mod_id: true}).
static func effective(mods: Dictionary) -> Dictionary:
	var e := {
		"noise_mult": 1.0, "damage_mult": 1.0, "range_mult": 1.0, "flash_mult": 1.0, "recoil_mult": 1.0,
		"spread_mult": 1.0, "aim_spread_mult": 1.0, "zoom_mult": 1.0, "suppressed": false, "light": false,
	}
	for m in MOD_ORDER:
		if not mods.get(m, false):
			continue
		var md: Dictionary = MODS[m]
		for k in ["noise_mult", "damage_mult", "range_mult", "flash_mult", "recoil_mult", "spread_mult", "aim_spread_mult", "zoom_mult"]:
			if md.has(k):
				e[k] = float(e[k]) * float(md[k])
	e["suppressed"] = bool(mods.get(&"suppressor", false))
	e["light"] = bool(mods.get(&"flashlight", false))
	return e
