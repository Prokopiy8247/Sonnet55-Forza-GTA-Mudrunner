class_name ShopSystem
extends Node
## Shops (weapon shop + modification bench, clothing store + wardrobe, barber, gas station food, scuba / parachute gear),
## player appearance persistence, store robbery, shop hours, scuba tank. Booted by Main as Game.sys(&"shops"); owns the
## InteriorSystem (`interiors`, also Game.sys(&"interiors")). Lifecycle: setup(main) -> post_setup().
##
## Purchases return {ok: bool, reason: String, price: int} and already spent the money. Free shopping (debug unlock):
## `free_shopping = true` or Game.cheats["free_shopping" | "free_shop" | "shop_unlock"].
## Menus (registered with Game.ui in post_setup): shop_weapons shop_bench shop_clothes shop_barber shop_goods.

signal purchase_made(kind: StringName, item: StringName, price: int)
signal appearance_changed()
signal robbery_done(shop_id: StringName, amount: int)

const ROB_COOLDOWN_S := 600.0
const ROB_MIN := 300
const ROB_MAX := 900
const ARMOR_PRICE := 300
const ARMOR_AMOUNT := 100.0
const HEALTH_PRICE := 120
const HEALTH_AMOUNT := 60.0
const SCUBA_PRICE := 1800
const PARACHUTE_PRICE := 600
const VEST_PRICE := 250
const MAX_VESTS := 3
const SCUBA_TANK_S := 600.0
const DEFAULT_OWNED := ["top_white_tee", "jacket_teal_bomber", "pants_navy_jeans", "shoes_white_sneakers", "hat_none", "glasses_none", "pack_none", "jacket_none"]
const COLOR_KEYS := ["skin", "hair_color", "shirt", "pants", "shoes", "accent", "jacket_color", "hat_color", "pack_color", "vest_color"]

const FOOD := [
	{"id": &"water", "name": "Bottled water", "desc": "Cold and clean. +5 HP.", "price": 2, "heal": 5.0, "glyph": &"drop", "color": Color("#34e0ff")},
	{"id": &"chips", "name": "Salted chips", "desc": "Crunchy. +10 HP.", "price": 3, "heal": 10.0, "glyph": &"dot", "color": Color("#ffd35a")},
	{"id": &"coffee", "name": "Black coffee", "desc": "+8 HP and a stamina refill.", "price": 3, "heal": 8.0, "stamina": true, "glyph": &"drop", "color": Color("#a4553f")},
	{"id": &"hotdog", "name": "Chili hot dog", "desc": "Gas station classic. +18 HP.", "price": 5, "heal": 18.0, "glyph": &"dot", "color": Color("#e8795f")},
	{"id": &"sandwich", "name": "Club sandwich", "desc": "Fresh today. +22 HP.", "price": 7, "heal": 22.0, "glyph": &"dot", "color": Color("#7be495")},
	{"id": &"burger", "name": "Double burger", "desc": "Big and greasy. +25 HP.", "price": 8, "heal": 25.0, "glyph": &"dot", "color": Color("#ffb347")},
	{"id": &"meal", "name": "Combo meal", "desc": "Burger, fries and a soda. +35 HP.", "price": 12, "heal": 35.0, "glyph": &"star", "color": Color("#ff3d9a")},
	{"id": &"energy", "name": "Volt energy drink", "desc": "+10 HP and no stamina drain for 45 s.", "price": 4, "heal": 10.0, "energy": 45.0, "glyph": &"star", "color": Color("#34e0ff")},
	{"id": &"firstaid", "name": "First aid kit", "desc": "Patches you up. +50 HP.", "price": 25, "heal": 50.0, "glyph": &"cross", "color": Color("#ff4d6a")},
]
const SCUBA := [
	{"id": &"scuba_kit", "name": "Scuba kit", "desc": "Mask, regulator and a 10 minute tank. Dive as deep and as long as you like. Refills on the surface.", "price": SCUBA_PRICE, "glyph": &"waves", "color": Color("#34e0ff"), "once": true},
	{"id": &"parachute", "name": "Parachute pack", "desc": "Jump from anything. Open with Space after the fall begins.", "price": PARACHUTE_PRICE, "glyph": &"chute", "color": Color("#7be495"), "once": true},
	{"id": &"vest", "name": "Auto-inflate life vest", "desc": "When you run out of breath it fills your lungs once. Single use, carry up to 3.", "price": VEST_PRICE, "glyph": &"anchor", "color": Color("#ffb347")},
]

var interiors: InteriorSystem = null
var appearance: Dictionary = {}               # delta over CharacterVariants.player_default()
var owned_items: Dictionary = {}              # clothing item key -> true
var free_shopping := false
var scuba_owned := false
var life_vests := 0
var tank_air := SCUBA_TANK_S
var rob_times: Dictionary = {}                # shop id -> unix time of the last robbery
var energy_until := 0.0
var menus: Dictionary = {}
var stats := {"purchases": 0, "spent": 0, "robberies": 0, "stolen": 0}

var _scuba_forced := false
var _threat_t := 0.0
var _threat_tick := 0.0
var _load_pending: Dictionary = {}
var _tank_warned := false
var _last_hour_sign := -1


# ================================================================================================= lifecycle
func setup(main: Node) -> void:
	interiors = InteriorSystem.new()
	interiors.name = "Interiors"
	add_child(interiors)
	interiors.setup(main)
	for k in DEFAULT_OWNED:
		owned_items[k] = true


func post_setup() -> void:
	interiors.post_setup()
	var ui = Game.ui
	if ui != null and ui.has_method("register_menu"):
		menus[&"shop_weapons"] = WeaponShopMenu.new()
		menus[&"shop_bench"] = WeaponBenchMenu.new()
		menus[&"shop_clothes"] = WardrobeMenu.new()
		menus[&"shop_barber"] = BarberMenu.new()
		menus[&"shop_goods"] = GoodsMenu.new()
		for id in menus:
			ui.register_menu(id, menus[id])
	Events.gunshot.connect(_on_gunshot)
	Events.player_respawned.connect(_on_player_respawned)
	Events.load_completed.connect(_on_load_completed)
	call_deferred("_sync_player_flags")
	if not _load_pending.is_empty():
		call_deferred("_apply_loaded")


func _process(dt: float) -> void:
	_tick_scuba(dt)
	if Time.get_ticks_msec() * 0.001 < energy_until:
		var p = Game.player
		if is_instance_valid(p) and p.get("stamina") != null:
			p.set("stamina", float(p.get("max_stamina")))
	if interiors != null and interiors.is_inside():
		_threat_tick -= dt
		if _threat_tick <= 0.0:
			_tick_threat(0.1)
			_threat_tick = 0.1


# ================================================================================================= public helpers
func is_open(shop_id: StringName) -> bool:
	return interiors.is_open(shop_id) if interiors != null else true


func free_shopping_active() -> bool:
	return free_shopping or bool(Game.cheats.get("free_shopping", false)) or bool(Game.cheats.get("free_shop", false)) or bool(Game.cheats.get("shop_unlock", false))


func get_tank01() -> float:
	return clampf(tank_air / SCUBA_TANK_S, 0.0, 1.0)


func _wc() -> Variant:
	var p = Game.player
	if is_instance_valid(p):
		return p.get("weapons")
	return null


static func _res(ok: bool, reason: String = "", price: int = 0) -> Dictionary:
	return {"ok": ok, "reason": reason, "price": price}


func _done(r: Dictionary, kind: StringName, item: StringName, label: String) -> Dictionary:
	if bool(r.get("ok", false)):
		var price := int(r.get("price", 0))
		stats["purchases"] = int(stats["purchases"]) + 1
		stats["spent"] = int(stats["spent"]) + price
		Sfx.play_ui(&"ui_confirm")
		Game.notify("%s%s" % [label, ("  (-" + Util.format_money(price) + ")") if price > 0 else ("  (free)" if free_shopping_active() else "")], &"good")
		purchase_made.emit(kind, item, price)
	else:
		Sfx.play_ui(&"ui_error")
		var reason := String(r.get("reason", "unavailable"))
		var extra := ""
		if reason == "not enough cash":
			extra = " - you need %s" % Util.format_money(int(r.get("price", 0)))
		Game.notify("Can't buy that: %s%s" % [reason, extra], &"warn")
	return r


# ================================================================================================= menus
func open_menu(kind: StringName, room: InteriorRoom = null) -> bool:
	var ui = Game.ui
	if ui == null or not ui.has_method("open_menu"):
		return false
	var data := {"room": room, "shop": (room.id if room != null else &"")}
	match kind:
		&"weapons":
			return ui.open_menu(&"shop_weapons", data)
		&"bench":
			return ui.open_menu(&"shop_bench", data)
		&"clothes":
			data["mode"] = &"store"
			return ui.open_menu(&"shop_clothes", data)
		&"wardrobe":
			data["mode"] = &"wardrobe"
			return ui.open_menu(&"shop_clothes", data)
		&"barber":
			return ui.open_menu(&"shop_barber", data)
		&"food":
			data["catalog"] = &"food"
			return ui.open_menu(&"shop_goods", data)
		&"scuba":
			data["catalog"] = &"scuba"
			return ui.open_menu(&"shop_goods", data)
	push_warning("ShopSystem.open_menu: unknown menu kind '%s'" % kind)
	return false


## Prompt of the counter use point (robbery aware). Called every scan by PlayerInteraction.
func counter_info(room: InteriorRoom, text: String) -> Dictionary:
	var c = room.clerk
	if c != null and is_instance_valid(c) and bool(room.info.get("robbable", true)):
		if c.is_dead or c.hands_up:
			if _rob_ready(room.id):
				return {"text": "Rob the register" if not c.is_dead else "Loot the register", "key": "E", "enabled": true}
			return {"text": "The register is empty", "key": "E", "enabled": false}
	return {"text": text, "key": "E", "enabled": true}


func counter_use(room: InteriorRoom, menu: StringName) -> void:
	var c = room.clerk
	if c != null and is_instance_valid(c) and bool(room.info.get("robbable", true)) and (c.is_dead or c.hands_up):
		rob(room)
		return
	if c != null and is_instance_valid(c) and c.hands_up:
		Game.notify("The clerk is too scared to serve you.", &"warn")
		return
	open_menu(menu, room)


# ================================================================================================= weapon shop
func buy_weapon(id: StringName) -> Dictionary:
	var wc = _wc()
	var d := WeaponDefs.get_def(id)
	if wc == null or d.is_empty():
		return _done(_res(false, "unknown weapon"), &"weapon", id, "")
	var label := "Bought %s" % str(d.get("name", id))
	if free_shopping_active():
		if not bool(d["shop"]):
			return _done(_res(false, "not for sale"), &"weapon", id, label)
		if wc.has_weapon(id) and WeaponDefs.is_firearm(id):
			return _done(_res(false, "already owned"), &"weapon", id, label)
		var rounds := int(d["mag_size"]) + int(d["give_reserve"]) if int(d["mag_size"]) > 0 else 0
		wc.give_weapon(id, rounds)
		return _done(_res(true, "", 0), &"weapon", id, label)
	return _done(WeaponTrade.buy_weapon(wc, id), &"weapon", id, label)


func buy_ammo(id: StringName, mags: int = 1) -> Dictionary:
	var wc = _wc()
	var d := WeaponDefs.get_def(id)
	if wc == null or d.is_empty():
		return _done(_res(false, "unknown weapon"), &"ammo", id, "")
	var label := "%d x ammo for %s" % [mags, str(d.get("name", id))]
	if free_shopping_active():
		if not wc.has_weapon(id) or int(d["mag_size"]) <= 0:
			return _done(_res(false, "weapon not owned"), &"ammo", id, label)
		var entry: Dictionary = wc.inventory[id]
		if int(entry["reserve"]) >= WeaponDefs.reserve_capacity(id, entry["mods"]):
			return _done(_res(false, "ammo full"), &"ammo", id, label)
		wc.add_ammo(id, int(d["mag_size"]) * maxi(mags, 1))
		return _done(_res(true, "", 0), &"ammo", id, label)
	return _done(WeaponTrade.buy_ammo(wc, id, mags), &"ammo", id, label)


func buy_armor() -> Dictionary:
	var p = Game.player
	if not is_instance_valid(p):
		return _res(false, "no player")
	if float(p.get("armor")) >= float(p.get("max_armor")) - 0.5:
		return _done(_res(false, "armor already full"), &"gear", &"armor", "")
	var price := ARMOR_PRICE
	if not free_shopping_active():
		if not Game.can_afford(price):
			return _done(_res(false, "not enough cash", price), &"gear", &"armor", "")
		Game.spend_cash(price)
	else:
		price = 0
	p.add_armor(ARMOR_AMOUNT)
	return _done(_res(true, "", price), &"gear", &"armor", "Body armor equipped")


func buy_health() -> Dictionary:
	var p = Game.player
	if not is_instance_valid(p):
		return _res(false, "no player")
	if float(p.get("health")) >= float(p.get("max_health")) - 0.5:
		return _done(_res(false, "you are at full health"), &"gear", &"medkit", "")
	var price := HEALTH_PRICE
	if not free_shopping_active():
		if not Game.can_afford(price):
			return _done(_res(false, "not enough cash", price), &"gear", &"medkit", "")
		Game.spend_cash(price)
	else:
		price = 0
	p.heal(HEALTH_AMOUNT)
	return _done(_res(true, "", price), &"gear", &"medkit", "Medkit used (+%d HP)" % int(HEALTH_AMOUNT))


# ---- modification bench
func buy_mod(weapon_id: StringName, mod_id: StringName) -> Dictionary:
	var wc = _wc()
	if wc == null:
		return _res(false, "no player")
	var mod_name := str(WeaponMods.get_mod(mod_id).get("name", mod_id))
	if free_shopping_active():
		if not wc.has_weapon(weapon_id):
			return _done(_res(false, "weapon not owned"), &"mod", mod_id, "")
		if not WeaponMods.is_compatible(weapon_id, mod_id):
			return _done(_res(false, "not compatible"), &"mod", mod_id, "")
		if wc.has_mod(weapon_id, mod_id):
			return _done(_res(false, "already installed"), &"mod", mod_id, "")
		wc.set_mod(weapon_id, mod_id, true)
		return _done(_res(true, "", 0), &"mod", mod_id, "%s installed" % mod_name)
	return _done(WeaponTrade.buy_mod(wc, weapon_id, mod_id), &"mod", mod_id, "%s installed" % mod_name)


func remove_mod(weapon_id: StringName, mod_id: StringName) -> Dictionary:
	var wc = _wc()
	var r := WeaponTrade.remove_mod(wc, weapon_id, mod_id)
	if bool(r["ok"]):
		Sfx.play_ui(&"ui_click")
		Game.notify("%s removed" % str(WeaponMods.get_mod(mod_id).get("name", mod_id)), &"info")
	return r


func buy_tint(weapon_id: StringName, tint_id: StringName) -> Dictionary:
	var wc = _wc()
	if wc == null:
		return _res(false, "no player")
	if free_shopping_active():
		if not wc.has_weapon(weapon_id) or not WeaponMods.TINTS.has(tint_id):
			return _done(_res(false, "unavailable"), &"tint", tint_id, "")
		wc.set_tint(weapon_id, WeaponMods.tint_color(tint_id))
		return _done(_res(true, "", 0), &"tint", tint_id, "Finish applied: %s" % str(tint_id).capitalize())
	return _done(WeaponTrade.buy_tint(wc, weapon_id, tint_id), &"tint", tint_id, "Finish applied: %s" % str(tint_id).capitalize())


# ================================================================================================= appearance
func get_variant() -> Dictionary:
	var v: Dictionary = CharacterVariants.player_default()
	for k in appearance:
		v[k] = appearance[k]
	return v


## Merge a (partial) rig variant into the player's persistent look and re-dress the player's rig.
func apply_appearance(variant: Dictionary, persist: bool = true) -> void:
	if persist:
		for k in variant:
			if k == "kind":
				continue
			appearance[k] = variant[k]
	_apply_to_player()
	appearance_changed.emit()


func reset_appearance() -> void:
	appearance.clear()
	_apply_to_player()
	appearance_changed.emit()


func _apply_to_player() -> void:
	var p = Game.player
	if not is_instance_valid(p):
		return
	var v := get_variant()
	p.set_meta(&"appearance", v)
	if "appearance" in p:
		p.set("appearance", v)
	var rig = p.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("setup"):
		rig.setup(v)
		var cam = p.get("camera")
		if cam != null and is_instance_valid(cam) and cam.has_method("refresh_first_person_visuals"):
			cam.refresh_first_person_visuals()
	var w = Game.sys(&"wanted")
	if w != null and w.has_method("notify_appearance_changed"):
		w.notify_appearance_changed()


func owns_item(key: String) -> bool:
	return owned_items.has(key)


func item_price(it: Dictionary) -> int:
	return 0 if free_shopping_active() else int(it.get("price", 0))


## Buys every not-yet-owned item of `keys` at once. `wardrobe` mode (safehouse) only wears owned / basic items for free.
func buy_outfit(keys: Array, wardrobe: bool = false) -> Dictionary:
	var total := 0
	var delta: Dictionary = {}
	var to_buy: Array = []
	for k in keys:
		var it := WardrobeDefs.find(String(k))
		if it.is_empty():
			continue
		if not owned_items.has(String(k)):
			if wardrobe and not bool(it["basic"]):
				return _done(_res(false, "you don't own that yet - buy it at Threads"), &"clothes", &"outfit", "")
			if not wardrobe:
				total += item_price(it)
			to_buy.append(String(k))
		for dk in (it["delta"] as Dictionary):
			delta[dk] = it["delta"][dk]
	if total > 0 and not Game.can_afford(total):
		return _done(_res(false, "not enough cash", total), &"clothes", &"outfit", "")
	if total > 0:
		Game.spend_cash(total)
	for k in to_buy:
		owned_items[k] = true
	apply_appearance(delta)
	var label := "New outfit on" if not to_buy.is_empty() else "Changed outfit"
	if wardrobe:
		Sfx.play_ui(&"ui_confirm")
		Game.notify("Changed outfit", &"good")
		return _res(true, "", 0)
	return _done(_res(true, "", total), &"clothes", &"outfit", label)


func barber_price(hair: int, beard: StringName, hair_color: Color) -> int:
	if free_shopping_active():
		return 0
	var cur := get_variant()
	var total := 0
	var cur_hair := int(cur.get("hair", 1))
	if hair != cur_hair:
		for h in WardrobeDefs.HAIR_STYLES:
			if int(h["id"]) == hair:
				total += int(h["price"])
	if String(beard) != String(cur.get("beard", "")):
		for b in WardrobeDefs.BEARDS:
			if String(b["id"]) == String(beard):
				total += int(b["price"])
	var cur_col: Color = cur.get("hair_color", Color("#2a1c14"))
	if not hair_color.is_equal_approx(cur_col):
		total += 15
		for hc in WardrobeDefs.HAIR_COLORS:
			if (hc["color"] as Color).is_equal_approx(hair_color):
				total += int(hc["price"])
	return total


func buy_haircut(hair: int, beard: StringName, hair_color: Color) -> Dictionary:
	var price := barber_price(hair, beard, hair_color)
	if price > 0 and not Game.can_afford(price):
		return _done(_res(false, "not enough cash", price), &"barber", &"cut", "")
	if price > 0:
		Game.spend_cash(price)
	apply_appearance({"hair": hair, "beard": beard, "hair_color": hair_color})
	return _done(_res(true, "", price), &"barber", &"cut", "Fresh cut!" if price > 0 else "Looking the same")


# ================================================================================================= goods (food / diving gear)
func catalog(kind: StringName) -> Array:
	return FOOD if kind == &"food" else SCUBA


func good_owned(item_id: StringName) -> bool:
	match item_id:
		&"scuba_kit":
			return scuba_owned
		&"parachute":
			var p = Game.player
			return is_instance_valid(p) and bool(p.get("has_parachute"))
		&"vest":
			return life_vests >= MAX_VESTS
	return false


func buy_good(kind: StringName, item_id: StringName) -> Dictionary:
	var item: Dictionary = {}
	for it in catalog(kind):
		if it["id"] == item_id:
			item = it
	if item.is_empty():
		return _res(false, "unknown item")
	var p = Game.player
	if not is_instance_valid(p):
		return _res(false, "no player")
	var price := int(item["price"])
	if kind == &"food":
		var heal := float(item.get("heal", 0.0))
		if heal > 0.0 and float(p.get("health")) >= float(p.get("max_health")) - 0.5 and not item.has("energy") and not item.has("stamina"):
			return _done(_res(false, "you are not hungry (full health)"), &"food", item_id, "")
	elif good_owned(item_id):
		return _done(_res(false, "already owned" if item_id != &"vest" else "you carry the maximum"), &"scuba", item_id, "")
	if free_shopping_active():
		price = 0
	elif not Game.can_afford(price):
		return _done(_res(false, "not enough cash", price), &"goods", item_id, "")
	else:
		Game.spend_cash(price)
	var label := "Bought %s" % str(item["name"])
	if kind == &"food":
		p.heal(float(item.get("heal", 0.0)))
		if item.has("stamina") or item.has("energy"):
			if p.get("stamina") != null:
				p.set("stamina", float(p.get("max_stamina")))
		if item.has("energy"):
			energy_until = Time.get_ticks_msec() * 0.001 + float(item["energy"])
		label = "%s: +%d HP" % [str(item["name"]), int(item.get("heal", 0.0))]
	else:
		match item_id:
			&"scuba_kit":
				scuba_owned = true
				tank_air = SCUBA_TANK_S
				_sync_player_flags()
				label = "Scuba kit bought - dive deep, the tank lasts 10 minutes"
			&"parachute":
				p.set("has_parachute", true)
				label = "Parachute pack on your back - jump and press Space"
			&"vest":
				life_vests = mini(life_vests + 1, MAX_VESTS)
				label = "Life vest stowed (%d)" % life_vests
	return _done(_res(true, "", price), &"food" if kind == &"food" else &"scuba", item_id, label)


func _on_player_respawned(_pos: Vector3) -> void:
	_sync_player_flags()
	_reapply_if_needed.call_deferred()


## The rig normally survives a respawn untouched; if something rebuilt it with the default look, dress it again.
func _reapply_if_needed() -> void:
	if appearance.is_empty():
		return
	var p = Game.player
	if not is_instance_valid(p):
		return
	var rig = p.get("rig")
	if rig == null or not is_instance_valid(rig):
		return
	var cur: Variant = rig.get("variant")
	if not (cur is Dictionary):
		return
	for k in appearance:
		if str((cur as Dictionary).get(k, "")) != str(appearance[k]):
			_apply_to_player()
			return


func _sync_player_flags() -> void:
	var p = Game.player
	if not is_instance_valid(p):
		return
	p.set_meta(&"has_scuba", scuba_owned)
	if "has_scuba" in p:
		p.set("has_scuba", scuba_owned)
	p.set_meta(&"life_vests", life_vests)


func _tick_scuba(dt: float) -> void:
	var p = Game.player
	if not is_instance_valid(p):
		return
	var uw: bool = p.get("head_underwater") == true
	if scuba_owned:
		if uw and tank_air > 0.0:
			tank_air = maxf(tank_air - dt, 0.0)
			if not bool(Game.cheats.get("scuba", false)):
				Game.cheats["scuba"] = true
				_scuba_forced = true
			if tank_air < SCUBA_TANK_S * 0.2 and not _tank_warned:
				_tank_warned = true
				Game.notify("Tank air low - head for the surface.", &"warn")
			if tank_air <= 0.0:
				Game.notify("Tank empty!", &"bad")
		else:
			if _scuba_forced:
				Game.cheats["scuba"] = false
				_scuba_forced = false
			if not uw and tank_air < SCUBA_TANK_S:
				tank_air = minf(tank_air + dt * 10.0, SCUBA_TANK_S)
				if tank_air > SCUBA_TANK_S * 0.5:
					_tank_warned = false
	elif _scuba_forced:
		Game.cheats["scuba"] = false
		_scuba_forced = false
	if life_vests > 0 and uw and not bool(Game.cheats.get("scuba", false)):
		var lungs = p.get("lungs")
		if lungs != null and float(lungs) < 0.6 and p.has_method("lung_capacity"):
			p.set("lungs", float(p.lung_capacity()))
			life_vests -= 1
			p.set_meta(&"life_vests", life_vests)
			Game.notify("Life vest inflated - catch your breath! (%d left)" % life_vests, &"good")
			Sfx.play_3d(&"gasp", p.global_position, 0.0, 1.0, 30.0)


# ================================================================================================= robbery
func _rob_ready(shop_id: StringName) -> bool:
	if not rob_times.has(shop_id):
		return true
	return Time.get_unix_time_from_system() - float(rob_times[shop_id]) >= ROB_COOLDOWN_S


func rob_cooldown_left(shop_id: StringName) -> float:
	if not rob_times.has(shop_id):
		return 0.0
	return maxf(ROB_COOLDOWN_S - (Time.get_unix_time_from_system() - float(rob_times[shop_id])), 0.0)


func _tick_threat(step: float) -> void:
	var room: InteriorRoom = interiors.get_current_room()
	if room == null:
		return
	var c = room.clerk
	if c == null or not is_instance_valid(c) or c.is_dead or not bool(room.info.get("robbable", true)):
		return
	var p = Game.player
	if not is_instance_valid(p):
		return
	var threat := false
	var w = p.get("weapons")
	if w != null and w.get("is_aiming") == true and WeaponDefs.is_firearm(StringName(w.get("current_id"))):
		var cam: Camera3D = Game.gameplay_camera
		if cam != null and is_instance_valid(cam):
			var fwd := -cam.global_transform.basis.z
			var origin := cam.global_position
			if cam.has_method("get_aim_forward"):
				fwd = cam.get_aim_forward()
			if cam.has_method("get_aim_origin"):
				origin = cam.get_aim_origin()
			var to: Vector3 = (c.global_position + Vector3(0, 1.2, 0)) - origin
			var dist := to.length()
			if dist < 14.0 and dist > 0.5 and fwd.dot(to / dist) > 0.94:
				threat = true
	if threat:
		_threat_t += step
		if _threat_t > 0.35:
			c.raise_hands(4.0)
	else:
		_threat_t = maxf(_threat_t - step * 0.5, 0.0)


func _on_gunshot(_pos: Vector3, _loud: float, source: Node) -> void:
	if interiors == null or not interiors.is_inside() or source != Game.player:
		return
	var room: InteriorRoom = interiors.get_current_room()
	if room != null and room.clerk != null and is_instance_valid(room.clerk) and not room.clerk.is_dead:
		room.clerk.raise_hands(8.0)


## Hold-up: cash from the register, crime event, alarm, the clerk phones the police a few seconds later.
func rob(room: InteriorRoom) -> bool:
	if room == null or not _rob_ready(room.id):
		return false
	var p = Game.player
	var clerk = room.clerk
	var amount := Game.rng.randi_range(ROB_MIN, ROB_MAX)
	if room.id == &"gas_station":
		amount = Game.rng.randi_range(ROB_MIN, 600)
	rob_times[room.id] = Time.get_unix_time_from_system()
	stats["robberies"] = int(stats["robberies"]) + 1
	stats["stolen"] = int(stats["stolen"]) + amount
	Game.add_cash(amount)
	Sfx.play_ui(&"ui_cash")
	Game.notify("You emptied the register: +%s" % Util.format_money(amount), &"good")
	var door := interiors.door_for(room.id)
	var crime_pos: Vector3 = door.global_position if door != null else (p.global_position if is_instance_valid(p) else Vector3.ZERO)
	var weapon_id: StringName = &"fists"
	if is_instance_valid(p) and p.get("weapons") != null:
		weapon_id = StringName(p.weapons.get("current_id"))
	var info := {"victim": clerk, "witnesses": [clerk] if clerk != null and is_instance_valid(clerk) and not clerk.is_dead else [], "witnessed": clerk != null and is_instance_valid(clerk) and not clerk.is_dead,
		"severity": 1.2, "weapon": weapon_id, "shop": room.id, "seen_by_police": false}
	Events.crime_committed.emit(GC.CRIME_ROBBERY, crime_pos, p, info)
	if clerk != null and is_instance_valid(clerk):
		clerk.mark_robbed()
		if not clerk.is_dead:
			clerk.raise_hands(5.0)
	_play_alarm(room)
	robbery_done.emit(room.id, amount)
	# the clerk hits the silent alarm / phones the police: if nobody else has reported it after a few seconds, report it
	_clerk_phone_call(room, crime_pos)
	return true


func _clerk_phone_call(room: InteriorRoom, crime_pos: Vector3) -> void:
	var clerk = room.clerk
	await get_tree().create_timer(Game.rng.randf_range(4.5, 7.0)).timeout
	if clerk == null or not is_instance_valid(clerk) or clerk.is_dead:
		return
	if Game.wanted_level <= 0 and is_instance_valid(Game.player):
		Events.crime_reported.emit(GC.CRIME_ROBBERY, crime_pos, Game.player)


static var _alarm_wav: AudioStreamWAV = null


## Procedural burglar alarm (project-owned, generated once): two alternating 1.5 kHz / 1.2 kHz beeps, 3.6 s.
static func alarm_stream() -> AudioStreamWAV:
	if _alarm_wav != null:
		return _alarm_wav
	var rate := 16000
	var n := int(float(rate) * 3.6)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var cyc := fmod(t, 0.36)
		var v := 0.0
		if cyc < 0.22:
			var f := 1500.0 if fmod(t, 0.72) < 0.36 else 1200.0
			phase += TAU * f / float(rate)
			var env := minf(cyc / 0.008, 1.0) * minf((0.22 - cyc) / 0.02, 1.0)
			v = (sin(phase) * 0.62 + sin(phase * 3.0) * 0.2 + sin(phase * 5.0) * 0.08) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 22000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_alarm_wav = w
	return w


func _play_alarm(room: InteriorRoom) -> void:
	var snd := AudioStreamPlayer3D.new()
	snd.stream = alarm_stream()
	snd.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	snd.volume_db = -4.0
	snd.unit_size = 9.0
	snd.max_distance = 50.0
	snd.position = Vector3(0, room.size.y - 0.6, 0)
	room.add_child(snd)
	snd.play()
	var l := room.add_light(Vector3(0, room.size.y - 0.6, 0), Color("#ff2a3a"), 2.4, 7.0)
	var tw := create_tween().set_loops(8)
	tw.tween_property(l, "light_energy", 0.2, 0.22)
	tw.tween_property(l, "light_energy", 2.4, 0.22)
	await get_tree().create_timer(3.6).timeout
	tw.kill()
	if is_instance_valid(l):
		room.lights.erase(l)
		l.queue_free()
	if snd != null and is_instance_valid(snd):
		snd.stop()
		snd.queue_free()


# ================================================================================================= save / load
func serialize() -> Dictionary:
	var app := {}
	for k in appearance:
		var v: Variant = appearance[k]
		if v is Color:
			app[k] = (v as Color).to_html(false)
		elif v is StringName:
			app[k] = String(v)
		else:
			app[k] = v
	var rob := {}
	for k in rob_times:
		rob[String(k)] = float(rob_times[k])
	return {"appearance": app, "owned": owned_items.keys(), "rob": rob, "scuba": scuba_owned, "vests": life_vests,
		"tank": tank_air, "stats": stats.duplicate()}


func deserialize(data: Dictionary) -> void:
	_load_pending = data.duplicate(true)
	if Game.player != null and is_instance_valid(Game.player):
		_apply_loaded()


func _on_load_completed() -> void:
	if not _load_pending.is_empty():
		_apply_loaded()
	else:
		_sync_player_flags()          # the player block of the save may have been restored after this system: ShopSystem owns scuba ownership
		if not appearance.is_empty():
			_apply_to_player()


func _apply_loaded() -> void:
	var data := _load_pending
	_load_pending = {}
	appearance.clear()
	var app: Variant = data.get("appearance", {})
	if app is Dictionary:
		for k in app:
			var v: Variant = app[k]
			if k in COLOR_KEYS and v is String:
				appearance[k] = Color(String(v))
			elif v is String and k in ["hat", "glasses", "jacket", "vest", "backpack", "beard", "body"]:
				appearance[k] = StringName(String(v))
			elif k == "hair" and (v is float or v is int):
				appearance[k] = int(v)
			else:
				appearance[k] = v
	owned_items.clear()
	for k in DEFAULT_OWNED:
		owned_items[k] = true
	var owned: Variant = data.get("owned", [])
	if owned is Array:
		for k in owned:
			owned_items[String(k)] = true
	var rt: Variant = data.get("rob", {})
	rob_times.clear()
	if rt is Dictionary:
		for k in rt:
			rob_times[StringName(String(k))] = float(rt[k])
	scuba_owned = bool(data.get("scuba", false))
	life_vests = int(data.get("vests", 0))
	tank_air = float(data.get("tank", SCUBA_TANK_S))
	var st: Variant = data.get("stats", {})
	if st is Dictionary:
		for k in st:
			if stats.has(k):
				stats[k] = int(st[k])
	_sync_player_flags()
	_apply_to_player()
