class_name WeaponPickup
extends PickupBase
## A weapon lying in the world (dropped by a dead NPC, or placed by the world). Walk over it to take the weapon (+ its ammo);
## if you already own it, you only receive the ammo.

var weapon_id: StringName = &"pistol"


func _init() -> void:
	super._init()
	kind = &"weapon"
	glow_color = Color(1.0, 0.8, 0.3)
	bob_height = 0.8
	spin_speed = 1.2


func _make_model() -> Node3D:
	var wm := WeaponModel.create(weapon_id)
	var holder := Node3D.new()
	holder.add_child(wm)
	wm.scale = Vector3.ONE * clampf(0.7 / maxf(float(WeaponDefs.get_def(weapon_id).get("length", 0.3)), 0.1), 0.7, 1.6)
	wm.position = Vector3(0, 0, 0.0)
	wm.rotation_degrees = Vector3(-8, 90, 0)
	holder.rotation_degrees = Vector3(0, 0, 14)
	return holder


func apply(character: Node) -> bool:
	var w = character.get("weapons")
	if w == null or not WeaponDefs.has(weapon_id):
		return false
	var def := WeaponDefs.get_def(weapon_id)
	var had: bool = w.has_weapon(weapon_id)
	if had and WeaponDefs.is_firearm(weapon_id):
		var inv: Dictionary = w.inventory[weapon_id]
		var mods: Dictionary = inv.get("mods", {})
		if int(inv.get("reserve", 0)) >= WeaponDefs.reserve_capacity(weapon_id, mods) and int(inv.get("mag", 0)) >= WeaponDefs.mag_capacity(weapon_id, mods):
			return false
	elif had and def["category"] == &"melee":
		return false
	w.give_weapon(weapon_id, amount)
	if not had and (w.current_id == &"fists"):
		w.equip(weapon_id)
	return true


func get_label() -> String:
	return "Picked up " + String(WeaponDefs.get_def(weapon_id).get("name", String(weapon_id)))
