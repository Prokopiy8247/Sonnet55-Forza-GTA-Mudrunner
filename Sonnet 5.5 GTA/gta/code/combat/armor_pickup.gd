class_name ArmorPickup
extends PickupBase
## Body armor: adds `amount` armor points (only collected when below the maximum).


func _init() -> void:
	super._init()
	kind = &"armor"
	glow_color = Color(0.3, 0.8, 1.0)
	amount = 50


func _fallback_model() -> Node3D:
	var r := Node3D.new()
	r.name = "FallbackArmor"
	r.set_meta(&"fallback", true)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.3, 0.52)
	mat.roughness = 0.6
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.2, 0.9, 1.0)
	rim.emission_enabled = true
	rim.emission = Color(0.2, 0.9, 1.0)
	rim.emission_energy_multiplier = 1.0
	var vest := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.42, 0.14)
	vest.mesh = bm
	vest.material_override = mat
	r.add_child(vest)
	for x in [-0.1, 0.1]:
		var sh := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.1, 0.1, 0.15)
		sh.mesh = sm
		sh.material_override = mat
		sh.position = Vector3(x, 0.26, 0)
		r.add_child(sh)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.2, 0.05, 0.16)
	plate.mesh = pm
	plate.material_override = rim
	plate.position = Vector3(0, 0.05, 0)
	r.add_child(plate)
	return r


func apply(character: Node) -> bool:
	if not character.has_method("add_armor"):
		return false
	var a: float = character.get("armor")
	var ma: float = character.get("max_armor")
	if a >= ma - 0.5:
		return false
	character.add_armor(float(amount))
	return true


func get_label() -> String:
	return "+%d armor" % amount
