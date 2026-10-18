class_name WeaponTrade
extends RefCounted
## Cash transactions for the weapon shop / workbench (Systems agent UI calls these; rules live here so they stay consistent).
## Every call returns {"ok": bool, "reason": String, "price": int}; on success the cash is already spent and the
## WeaponController inventory updated (the UI only has to refresh and play a sound).


static func _res(ok: bool, reason: String, price: int = 0) -> Dictionary:
	return {"ok": ok, "reason": reason, "price": price}


## Buy a weapon: you receive its price-listed starter ammo (2 magazines; grenades x3 ...).
static func buy_weapon(w: WeaponController, id: StringName) -> Dictionary:
	var d := WeaponDefs.get_def(id)
	if w == null or d.is_empty():
		return _res(false, "unknown weapon")
	if not d["shop"]:
		return _res(false, "not for sale")
	if w.has_weapon(id) and WeaponDefs.is_firearm(id):
		return _res(false, "already owned")
	var price := int(d["price"])
	if not Game.can_afford(price):
		return _res(false, "not enough cash", price)
	Game.spend_cash(price)
	var rounds := int(d["mag_size"]) + int(d["give_reserve"]) * 1 if int(d["mag_size"]) > 0 else 0
	w.give_weapon(id, rounds)
	return _res(true, "", price)


## Buy `mags` magazines of ammo (price = def.ammo_price per magazine, grenades: per grenade).
static func buy_ammo(w: WeaponController, id: StringName, mags: int = 1) -> Dictionary:
	var d := WeaponDefs.get_def(id)
	if w == null or d.is_empty() or int(d["mag_size"]) <= 0:
		return _res(false, "no ammo for this weapon")
	if not w.has_weapon(id):
		return _res(false, "weapon not owned")
	var entry: Dictionary = w.inventory[id]
	var cap := WeaponDefs.reserve_capacity(id, entry["mods"])
	if int(entry["reserve"]) >= cap:
		return _res(false, "ammo full")
	var price := int(d["ammo_price"]) * maxi(mags, 1)
	if not Game.can_afford(price):
		return _res(false, "not enough cash", price)
	Game.spend_cash(price)
	w.add_ammo(id, int(d["mag_size"]) * maxi(mags, 1))
	return _res(true, "", price)


static func buy_mod(w: WeaponController, id: StringName, mod_id: StringName) -> Dictionary:
	if w == null or not w.has_weapon(id):
		return _res(false, "weapon not owned")
	if not WeaponMods.is_compatible(id, mod_id):
		return _res(false, "not compatible")
	if w.has_mod(id, mod_id):
		return _res(false, "already installed")
	var price := WeaponMods.price(mod_id)
	if not Game.can_afford(price):
		return _res(false, "not enough cash", price)
	Game.spend_cash(price)
	w.set_mod(id, mod_id, true)
	return _res(true, "", price)


## Removing a mod is free (no refund).
static func remove_mod(w: WeaponController, id: StringName, mod_id: StringName) -> Dictionary:
	if w == null or not w.has_mod(id, mod_id):
		return _res(false, "not installed")
	w.set_mod(id, mod_id, false)
	return _res(true, "", 0)


## Cosmetic finish from WeaponMods.TINTS ("factory" resets it for free).
static func buy_tint(w: WeaponController, id: StringName, tint_id: StringName) -> Dictionary:
	if w == null or not w.has_weapon(id) or not WeaponMods.TINTS.has(tint_id):
		return _res(false, "unavailable")
	var price := 0 if tint_id == &"factory" else WeaponMods.TINT_PRICE
	if not Game.can_afford(price):
		return _res(false, "not enough cash", price)
	Game.spend_cash(price)
	w.set_tint(id, WeaponMods.tint_color(tint_id))
	return _res(true, "", price)
