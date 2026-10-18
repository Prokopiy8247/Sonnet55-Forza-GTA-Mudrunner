class_name WeaponDefs
extends RefCounted
## Complete weapon data table for Halcyon Bay (original generic designs, arcade-realistic tuning).
## Other modules use only get_def()/ids()/has()/by_category() (+ price helpers). The returned dictionaries are shared:
## treat them as READ-ONLY (duplicate before modifying).
##
## Def keys (all weapons have every key; melee/thrown simply ignore the ballistic ones):
##   id name desc category model pose price ammo_price shop mods
##   mag_size reserve_cap give_reserve            -- ammo (reserve excludes the magazine)
##   damage pellets range falloff_start falloff_min penetration impulse     -- ballistics (damage is per bullet / pellet)
##   spread aim_spread move_spread bloom bloom_max bloom_recover pellet_spread   -- accuracy (degrees, half-angle)
##   fire_rate mode(&"auto" &"semi" &"burst" &"pump" &"bolt" &"melee" &"throw") auto burst_count burst_rate burst_pause
##   reload_time reload_style(&"mag" &"shell") shell_time equip_time
##   recoil recoil_yaw recoil_recover recoil_max                           -- camera kick (degrees)
##   aim_zoom scope scope_zoom2                                              -- ADS FOV divisor, full-screen scope, 2nd zoom level
##   projectile(&"" hitscan, &"rocket", &"grenade_launcher", &"grenade") proj_speed fuse blast_radius blast_damage blast_force
##   noise sfx_shot flash tracer tracer_every shell                         -- audio / vfx
##   vehicle_ok move_mult                                                    -- handling
##   reach arc knockback heavy_mult hit_delay combo                         -- melee

const CATEGORY_ORDER := [&"melee", &"handgun", &"smg", &"shotgun", &"rifle", &"sniper", &"heavy", &"thrown"]

## Names of the weapon-id <-> slot mapping used by equip_slot(1..9): category order, slot 9 = unarmed.
const SLOT_CATEGORIES := [&"melee", &"handgun", &"smg", &"shotgun", &"rifle", &"sniper", &"heavy", &"thrown"]

const BASE := {
	"id": &"", "name": "", "desc": "", "category": &"handgun", "model": "", "pose": &"pistol",
	"price": 0, "ammo_price": 0, "shop": true, "mods": [],
	"mag_size": 12, "reserve_cap": 120, "give_reserve": 48,
	"damage": 20.0, "pellets": 1, "range": 90.0, "falloff_start": 35.0, "falloff_min": 0.55, "penetration": 1, "impulse": 3.0,
	"spread": 2.0, "aim_spread": 0.5, "move_spread": 2.0, "bloom": 0.35, "bloom_max": 3.0, "bloom_recover": 5.0, "pellet_spread": 0.0,
	"fire_rate": 5.0, "mode": &"semi", "auto": false, "burst_count": 3, "burst_rate": 14.0, "burst_pause": 0.22,
	"reload_time": 1.6, "reload_style": &"mag", "shell_time": 0.4, "equip_time": 0.4,
	"recoil": 1.2, "recoil_yaw": 0.4, "recoil_recover": 9.0, "recoil_max": 7.0,
	"aim_zoom": 1.25, "scope": false, "scope_zoom2": 0.0,
	"projectile": &"", "proj_speed": 0.0, "fuse": 0.0, "blast_radius": 0.0, "blast_damage": 0.0, "blast_force": 0.0,
	"noise": 70.0, "sfx_shot": &"shot_pistol", "flash": 1.0, "tracer": "#ffe2a0", "tracer_every": 1, "shell": &"pistol",
	"vehicle_ok": false, "move_mult": 1.0,
	"reach": 0.0, "arc": 0.0, "knockback": 0.0, "heavy_mult": 1.6, "hit_delay": 0.15, "combo": false,
	"length": 0.3,
}

static var DEFS: Dictionary = _build()


static func _d(over: Dictionary) -> Dictionary:
	var d: Dictionary = BASE.duplicate(true)
	d.merge(over, true)
	if d["mode"] == &"auto":
		d["auto"] = true
	return d


static func _build() -> Dictionary:
	var out: Dictionary = {}
	var all_mods := [&"suppressor", &"scope", &"flashlight", &"grip", &"magazine_ext"]
	# ---------------------------------------------------------------- melee
	out[&"fists"] = _d({
		"id": &"fists", "name": "Fists", "desc": "Bare knuckles. The third hit of a combo knocks people down.",
		"category": &"melee", "model": "", "pose": &"none", "price": 0, "shop": false,
		"mag_size": 0, "reserve_cap": 0, "give_reserve": 0, "damage": 12.0, "range": 1.6, "mode": &"melee", "fire_rate": 2.3,
		"equip_time": 0.15, "reach": 1.65, "arc": 80.0, "knockback": 3.5, "heavy_mult": 1.7, "hit_delay": 0.13, "combo": true,
		"noise": 8.0, "impulse": 3.5, "sfx_shot": &"punch", "move_mult": 1.0,
	})
	out[&"knife"] = _d({
		"id": &"knife", "name": "Combat Knife", "desc": "Fast and quiet. Lethal from behind.",
		"category": &"melee", "model": "weapons/knife", "pose": &"melee_knife", "price": 90, "shop": true,
		"mag_size": 0, "reserve_cap": 0, "give_reserve": 0, "damage": 26.0, "range": 1.5, "mode": &"melee", "fire_rate": 2.8,
		"equip_time": 0.25, "reach": 1.55, "arc": 65.0, "knockback": 1.8, "heavy_mult": 1.9, "hit_delay": 0.11, "length": 0.28,
		"noise": 6.0, "impulse": 1.5, "sfx_shot": &"melee_swing",
	})
	out[&"bat"] = _d({
		"id": &"bat", "name": "Slugger Bat", "desc": "Heavy swing, big knockback.",
		"category": &"melee", "model": "weapons/bat", "pose": &"melee_bat", "price": 140, "shop": true,
		"mag_size": 0, "reserve_cap": 0, "give_reserve": 0, "damage": 34.0, "range": 2.1, "mode": &"melee", "fire_rate": 1.5,
		"equip_time": 0.35, "reach": 2.15, "arc": 100.0, "knockback": 7.0, "heavy_mult": 1.8, "hit_delay": 0.2, "length": 0.85,
		"noise": 10.0, "impulse": 6.0, "sfx_shot": &"melee_swing", "move_mult": 0.97,
	})
	out[&"crowbar"] = _d({
		"id": &"crowbar", "name": "Pry Bar", "desc": "Solid steel. Good for heads and windows.",
		"category": &"melee", "model": "weapons/crowbar", "pose": &"melee_bat", "price": 120, "shop": true,
		"mag_size": 0, "reserve_cap": 0, "give_reserve": 0, "damage": 30.0, "range": 1.95, "mode": &"melee", "fire_rate": 1.8,
		"equip_time": 0.3, "reach": 2.0, "arc": 85.0, "knockback": 5.0, "heavy_mult": 1.75, "hit_delay": 0.17, "length": 0.65,
		"noise": 9.0, "impulse": 5.0, "sfx_shot": &"melee_swing", "move_mult": 0.98,
	})
	# ---------------------------------------------------------------- handguns
	out[&"pistol"] = _d({
		"id": &"pistol", "name": "Service Pistol", "desc": "Reliable 9 mm sidearm. Fires from a moving car.",
		"category": &"handgun", "model": "weapons/pistol", "pose": &"pistol", "price": 450, "ammo_price": 45,
		"mods": [&"suppressor", &"flashlight", &"scope", &"magazine_ext"],
		"mag_size": 15, "reserve_cap": 150, "give_reserve": 45,
		"damage": 22.0, "range": 90.0, "falloff_start": 28.0, "falloff_min": 0.45, "impulse": 3.0,
		"spread": 1.9, "aim_spread": 0.35, "move_spread": 1.8, "bloom": 0.55, "bloom_max": 2.8, "bloom_recover": 6.0,
		"fire_rate": 6.0, "mode": &"semi", "reload_time": 1.45, "equip_time": 0.3,
		"recoil": 1.5, "recoil_yaw": 0.45, "recoil_recover": 11.0, "recoil_max": 6.0, "aim_zoom": 1.2,
		"noise": 65.0, "sfx_shot": &"shot_pistol", "flash": 0.8, "tracer_every": 1, "shell": &"pistol", "vehicle_ok": true, "length": 0.21,
	})
	out[&"revolver"] = _d({
		"id": &"revolver", "name": "Heavy Revolver", "desc": "Six rounds of pure stopping power.",
		"category": &"handgun", "model": "weapons/revolver", "pose": &"pistol", "price": 1150, "ammo_price": 90,
		"mods": [&"flashlight", &"scope"],
		"mag_size": 6, "reserve_cap": 60, "give_reserve": 24,
		"damage": 62.0, "range": 110.0, "falloff_start": 40.0, "falloff_min": 0.6, "impulse": 7.0, "penetration": 2,
		"spread": 2.2, "aim_spread": 0.3, "move_spread": 2.0, "bloom": 1.4, "bloom_max": 4.0, "bloom_recover": 4.5,
		"fire_rate": 2.1, "mode": &"semi", "reload_time": 2.9, "equip_time": 0.4,
		"recoil": 4.4, "recoil_yaw": 1.0, "recoil_recover": 7.5, "recoil_max": 11.0, "aim_zoom": 1.25,
		"noise": 95.0, "sfx_shot": &"shot_revolver", "flash": 1.35, "tracer": "#ffd890", "shell": &"revolver", "vehicle_ok": true, "length": 0.27,
	})
	# ---------------------------------------------------------------- SMG
	out[&"smg"] = _d({
		"id": &"smg", "name": "Compact SMG", "desc": "Spray-and-pray close quarters. Usable from a car.",
		"category": &"smg", "model": "weapons/smg", "pose": &"smg", "price": 1650, "ammo_price": 70,
		"mods": all_mods,
		"mag_size": 30, "reserve_cap": 300, "give_reserve": 90,
		"damage": 15.0, "range": 80.0, "falloff_start": 20.0, "falloff_min": 0.35, "impulse": 2.0,
		"spread": 3.3, "aim_spread": 0.9, "move_spread": 2.2, "bloom": 0.3, "bloom_max": 3.8, "bloom_recover": 5.5,
		"fire_rate": 14.0, "mode": &"auto", "reload_time": 1.7, "equip_time": 0.35,
		"recoil": 0.85, "recoil_yaw": 0.6, "recoil_recover": 12.0, "recoil_max": 6.5, "aim_zoom": 1.3,
		"noise": 75.0, "sfx_shot": &"shot_smg", "flash": 0.85, "tracer_every": 2, "shell": &"pistol", "vehicle_ok": true, "length": 0.45,
	})
	# ---------------------------------------------------------------- shotguns
	out[&"shotgun_pump"] = _d({
		"id": &"shotgun_pump", "name": "Pump Shotgun", "desc": "Devastating up close. Pump between shots.",
		"category": &"shotgun", "model": "weapons/shotgun_pump", "pose": &"shotgun", "price": 1500, "ammo_price": 60,
		"mods": [&"flashlight", &"grip", &"scope"],
		"mag_size": 7, "reserve_cap": 56, "give_reserve": 21,
		"damage": 11.0, "pellets": 9, "range": 55.0, "falloff_start": 6.0, "falloff_min": 0.12, "impulse": 4.5, "penetration": 0,
		"spread": 3.4, "aim_spread": 2.4, "move_spread": 1.5, "pellet_spread": 2.6, "bloom": 0.6, "bloom_max": 1.5, "bloom_recover": 6.0,
		"fire_rate": 1.15, "mode": &"pump", "reload_time": 0.55, "reload_style": &"shell", "shell_time": 0.42, "equip_time": 0.5,
		"recoil": 5.2, "recoil_yaw": 1.2, "recoil_recover": 8.0, "recoil_max": 12.0, "aim_zoom": 1.2,
		"noise": 100.0, "sfx_shot": &"shot_shotgun", "flash": 1.4, "tracer": "#ffcf88", "tracer_every": 3, "shell": &"shotgun", "length": 0.95, "move_mult": 0.96,
	})
	out[&"shotgun_auto"] = _d({
		"id": &"shotgun_auto", "name": "Auto Shotgun", "desc": "Semi-automatic scattergun with a big drum.",
		"category": &"shotgun", "model": "weapons/shotgun_auto", "pose": &"shotgun", "price": 3100, "ammo_price": 90,
		"mods": [&"flashlight", &"grip", &"scope", &"magazine_ext"],
		"mag_size": 8, "reserve_cap": 64, "give_reserve": 24,
		"damage": 8.5, "pellets": 8, "range": 50.0, "falloff_start": 6.0, "falloff_min": 0.12, "impulse": 3.2, "penetration": 0,
		"spread": 3.8, "aim_spread": 2.8, "move_spread": 1.6, "pellet_spread": 2.9, "bloom": 0.7, "bloom_max": 2.2, "bloom_recover": 6.0,
		"fire_rate": 3.4, "mode": &"semi", "reload_time": 2.7, "equip_time": 0.5,
		"recoil": 3.6, "recoil_yaw": 1.0, "recoil_recover": 9.0, "recoil_max": 12.0, "aim_zoom": 1.2,
		"noise": 100.0, "sfx_shot": &"shot_shotgun", "flash": 1.3, "tracer": "#ffcf88", "tracer_every": 3, "shell": &"shotgun", "length": 0.9, "move_mult": 0.95,
	})
	# ---------------------------------------------------------------- rifles
	out[&"rifle_assault"] = _d({
		"id": &"rifle_assault", "name": "Assault Rifle", "desc": "All-round full-auto workhorse.",
		"category": &"rifle", "model": "weapons/rifle_assault", "pose": &"rifle", "price": 3600, "ammo_price": 110,
		"mods": all_mods,
		"mag_size": 30, "reserve_cap": 240, "give_reserve": 90,
		"damage": 24.0, "range": 160.0, "falloff_start": 55.0, "falloff_min": 0.55, "impulse": 3.0, "penetration": 2,
		"spread": 3.0, "aim_spread": 0.55, "move_spread": 2.6, "bloom": 0.4, "bloom_max": 4.0, "bloom_recover": 5.0,
		"fire_rate": 10.0, "mode": &"auto", "reload_time": 2.1, "equip_time": 0.5,
		"recoil": 1.2, "recoil_yaw": 0.7, "recoil_recover": 10.0, "recoil_max": 9.0, "aim_zoom": 1.45,
		"noise": 100.0, "sfx_shot": &"shot_rifle", "flash": 1.15, "tracer_every": 2, "shell": &"rifle", "length": 0.85, "move_mult": 0.96,
	})
	out[&"carbine"] = _d({
		"id": &"carbine", "name": "Burst Carbine", "desc": "Light and accurate. Fires 3-round bursts (switch to full-auto).",
		"category": &"rifle", "model": "weapons/carbine", "pose": &"rifle", "price": 2800, "ammo_price": 95,
		"mods": all_mods,
		"mag_size": 30, "reserve_cap": 240, "give_reserve": 90,
		"damage": 21.0, "range": 140.0, "falloff_start": 50.0, "falloff_min": 0.55, "impulse": 2.6, "penetration": 1,
		"spread": 2.5, "aim_spread": 0.45, "move_spread": 2.3, "bloom": 0.35, "bloom_max": 3.2, "bloom_recover": 5.5,
		"fire_rate": 8.0, "mode": &"burst", "burst_count": 3, "burst_rate": 16.0, "burst_pause": 0.2, "reload_time": 1.9, "equip_time": 0.45,
		"recoil": 0.95, "recoil_yaw": 0.55, "recoil_recover": 11.0, "recoil_max": 8.0, "aim_zoom": 1.45,
		"noise": 95.0, "sfx_shot": &"shot_rifle", "flash": 1.05, "tracer_every": 2, "shell": &"rifle", "length": 0.75, "move_mult": 0.97,
	})
	out[&"rifle_marksman"] = _d({
		"id": &"rifle_marksman", "name": "Marksman Rifle", "desc": "Semi-auto precision rifle with a 2x zoom.",
		"category": &"rifle", "model": "weapons/rifle_marksman", "pose": &"rifle", "price": 4800, "ammo_price": 150,
		"mods": [&"suppressor", &"scope", &"flashlight", &"grip", &"magazine_ext"],
		"mag_size": 10, "reserve_cap": 80, "give_reserve": 30,
		"damage": 52.0, "range": 260.0, "falloff_start": 120.0, "falloff_min": 0.7, "impulse": 5.5, "penetration": 3,
		"spread": 2.4, "aim_spread": 0.2, "move_spread": 3.0, "bloom": 0.9, "bloom_max": 3.0, "bloom_recover": 5.0,
		"fire_rate": 3.4, "mode": &"semi", "reload_time": 2.4, "equip_time": 0.55,
		"recoil": 2.6, "recoil_yaw": 0.6, "recoil_recover": 9.0, "recoil_max": 10.0, "aim_zoom": 2.2,
		"noise": 110.0, "sfx_shot": &"shot_rifle", "flash": 1.2, "tracer": "#ffd890", "tracer_every": 1, "shell": &"rifle", "length": 1.0, "move_mult": 0.94,
	})
	# ---------------------------------------------------------------- sniper
	out[&"sniper"] = _d({
		"id": &"sniper", "name": "Long-Range Sniper", "desc": "Bolt action. Scope in, hold your breath, one shot.",
		"category": &"sniper", "model": "weapons/sniper", "pose": &"sniper", "price": 7200, "ammo_price": 180,
		"mods": [&"suppressor", &"flashlight", &"grip", &"magazine_ext"],
		"mag_size": 5, "reserve_cap": 30, "give_reserve": 15,
		"damage": 125.0, "range": 600.0, "falloff_start": 600.0, "falloff_min": 1.0, "impulse": 10.0, "penetration": 4,
		"spread": 5.0, "aim_spread": 0.0, "move_spread": 4.0, "bloom": 1.2, "bloom_max": 3.0, "bloom_recover": 4.0,
		"fire_rate": 0.9, "mode": &"bolt", "reload_time": 3.1, "equip_time": 0.7,
		"recoil": 5.5, "recoil_yaw": 0.8, "recoil_recover": 7.0, "recoil_max": 12.0, "aim_zoom": 4.0, "scope": true, "scope_zoom2": 8.0,
		"noise": 140.0, "sfx_shot": &"shot_sniper", "flash": 1.5, "tracer": "#ffe9b8", "tracer_every": 1, "shell": &"sniper", "length": 1.25, "move_mult": 0.9,
	})
	# ---------------------------------------------------------------- heavy / thrown
	out[&"rocket_launcher"] = _d({
		"id": &"rocket_launcher", "name": "Rocket Launcher", "desc": "Shoulder-fired. Hits hard. Everything near burns.",
		"category": &"heavy", "model": "weapons/rocket_launcher", "pose": &"heavy", "price": 9500, "ammo_price": 380,
		"mods": [],
		"mag_size": 1, "reserve_cap": 8, "give_reserve": 3,
		"damage": 0.0, "range": 400.0, "impulse": 0.0,
		"spread": 1.5, "aim_spread": 0.3, "move_spread": 2.0, "bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 5.0,
		"fire_rate": 0.8, "mode": &"semi", "reload_time": 3.2, "equip_time": 0.7,
		"recoil": 4.0, "recoil_yaw": 0.4, "recoil_recover": 7.0, "recoil_max": 8.0, "aim_zoom": 1.5,
		"projectile": &"rocket", "proj_speed": 62.0, "fuse": 5.0, "blast_radius": 9.5, "blast_damage": 340.0, "blast_force": 18.0,
		"noise": 130.0, "sfx_shot": &"shot_rocket", "flash": 0.0, "shell": &"", "length": 1.0, "move_mult": 0.88,
	})
	out[&"grenade_launcher"] = _d({
		"id": &"grenade_launcher", "name": "Grenade Launcher", "desc": "Four lobbed 40 mm grenades per cylinder.",
		"category": &"heavy", "model": "weapons/grenade_launcher", "pose": &"heavy", "price": 6600, "ammo_price": 200,
		"mods": [],
		"mag_size": 4, "reserve_cap": 24, "give_reserve": 8,
		"damage": 0.0, "range": 160.0, "impulse": 0.0,
		"spread": 1.2, "aim_spread": 0.3, "move_spread": 1.5, "bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 5.0,
		"fire_rate": 1.4, "mode": &"semi", "reload_time": 3.3, "equip_time": 0.65,
		"recoil": 3.2, "recoil_yaw": 0.4, "recoil_recover": 8.0, "recoil_max": 7.0, "aim_zoom": 1.4,
		"projectile": &"grenade_launcher", "proj_speed": 34.0, "fuse": 2.6, "blast_radius": 6.5, "blast_damage": 200.0, "blast_force": 14.0,
		"noise": 110.0, "sfx_shot": &"shot_rocket", "flash": 0.7, "shell": &"", "length": 0.8, "move_mult": 0.92,
	})
	out[&"grenade"] = _d({
		"id": &"grenade", "name": "Frag Grenade", "desc": "Hold to cook, release to throw. Fuse 3.0 s.",
		"category": &"thrown", "model": "weapons/grenade", "pose": &"thrown", "price": 130, "ammo_price": 130,
		"mods": [],
		"mag_size": 1, "reserve_cap": 9, "give_reserve": 3,
		"damage": 0.0, "range": 40.0, "impulse": 0.0,
		"spread": 0.0, "aim_spread": 0.0, "move_spread": 0.0, "bloom": 0.0, "bloom_max": 0.0,
		"fire_rate": 1.2, "mode": &"throw", "reload_time": 0.55, "equip_time": 0.3,
		"recoil": 0.0, "recoil_yaw": 0.0, "aim_zoom": 1.1,
		"projectile": &"grenade", "proj_speed": 17.0, "fuse": 3.0, "blast_radius": 7.5, "blast_damage": 230.0, "blast_force": 15.0,
		"noise": 40.0, "sfx_shot": &"melee_swing", "flash": 0.0, "shell": &"", "length": 0.1, "vehicle_ok": true,
	})
	return out


# ---------------------------------------------------------------------------------------------------------
static func get_def(id: StringName) -> Dictionary:
	return DEFS.get(id, {})


static func has(id: StringName) -> bool:
	return DEFS.has(id)


static func ids() -> Array:
	return DEFS.keys()


static func by_category(category: StringName) -> Array:
	var out: Array = []
	for id in DEFS:
		if DEFS[id].get("category", &"") == category:
			out.append(id)
	return out


## Ids sold in the weapon shop (def.shop == true), ordered by category then price.
static func shop_ids() -> Array:
	var out: Array = []
	for cat in CATEGORY_ORDER:
		var in_cat: Array = []
		for id in DEFS:
			var d: Dictionary = DEFS[id]
			if d["category"] == cat and d["shop"]:
				in_cat.append(id)
		in_cat.sort_custom(func(a, b): return int(DEFS[a]["price"]) < int(DEFS[b]["price"]))
		out.append_array(in_cat)
	return out


static func is_melee(id: StringName) -> bool:
	return DEFS.get(id, {}).get("category", &"") == &"melee"


static func is_firearm(id: StringName) -> bool:
	var c: StringName = DEFS.get(id, {}).get("category", &"")
	return c != &"melee" and c != &"thrown" and c != &""


static func is_projectile_weapon(id: StringName) -> bool:
	return DEFS.get(id, {}).get("projectile", &"") != &""


## Magazine capacity incl. the extended-magazine mod.
static func mag_capacity(id: StringName, mods: Dictionary = {}) -> int:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return 0
	var cap: float = float(d["mag_size"])
	if mods.get(&"magazine_ext", false):
		cap = ceilf(cap * float(WeaponMods.MODS[&"magazine_ext"]["mag_mult"]))
	return int(cap)


static func reserve_capacity(id: StringName, mods: Dictionary = {}) -> int:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return 0
	var cap: float = float(d["reserve_cap"])
	if mods.get(&"magazine_ext", false):
		cap = ceilf(cap * float(WeaponMods.MODS[&"magazine_ext"]["reserve_mult"]))
	return int(cap)


## Price of one magazine of ammo for the weapon (shop).
static func ammo_cost(id: StringName) -> int:
	return int(DEFS.get(id, {}).get("ammo_price", 0))


## Effective rate of fire (shots/s) including burst pauses. Used by tests and the UI stat bars.
static func effective_fire_rate(id: StringName) -> float:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return 0.0
	if d["mode"] == &"burst":
		var n: float = float(d["burst_count"])
		return n / ((n - 1.0) / float(d["burst_rate"]) + float(d["burst_pause"]))
	return float(d["fire_rate"])


## UI helper: rough 0..1 stat bars {damage, rate, range, accuracy, control}.
static func stat_bars(id: StringName) -> Dictionary:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return {}
	var dmg: float = float(d["damage"]) * float(d["pellets"]) * 0.5 + float(d["blast_damage"]) * 0.1
	return {
		"damage": clampf(dmg / 80.0, 0.04, 1.0),
		"rate": clampf(float(d["fire_rate"]) / 14.0, 0.05, 1.0),
		"range": clampf(float(d["range"]) / 300.0, 0.04, 1.0),
		"accuracy": clampf(1.0 - float(d["aim_spread"]) / 3.0, 0.05, 1.0),
		"control": clampf(1.0 - float(d["recoil"]) / 7.0, 0.05, 1.0),
	}
