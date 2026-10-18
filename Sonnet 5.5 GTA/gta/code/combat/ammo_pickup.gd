class_name AmmoPickup
extends PickupBase
## Ammo box. weapon_id = &"" fills the equipped firearm (or, when unarmed, the first firearm you own).

var weapon_id: StringName = &""


func _init() -> void:
	super._init()
	kind = &"ammo"
	glow_color = Color(1.0, 0.75, 0.25)
	amount = 30


func _fallback_model() -> Node3D:
	var r := Node3D.new()
	r.name = "FallbackAmmo"
	r.set_meta(&"fallback", true)
	WeaponModel._part(r, "box", Vector3(0.34, 0.2, 0.22), Vector3.ZERO, "olive")
	WeaponModel._part(r, "box", Vector3(0.36, 0.04, 0.24), Vector3(0, 0.1, 0), "accent")
	for i in 3:
		WeaponModel._part(r, "cyl", Vector3(0.025, 0.12, 0.025), Vector3(-0.09 + i * 0.09, 0.17, 0), "metal")
	return r


func apply(character: Node) -> bool:
	var w = character.get("weapons")
	if w == null:
		return false
	var target: StringName = weapon_id
	if target == &"":
		target = w.current_id
		if not WeaponDefs.is_firearm(target) or not w.has_weapon(target):
			target = &""
			for id in w.get_weapon_ids():
				if WeaponDefs.is_firearm(id):
					target = id
					break
	if target == &"" or not w.has_weapon(target):
		return false
	var added: int = w.add_ammo(target, amount)
	return added > 0


func get_label() -> String:
	return "+%d ammo" % amount
