class_name HealthPickup
extends PickupBase
## Health pack: heals `amount` hit points (only collected when the player is hurt).


func _init() -> void:
	super._init()
	kind = &"health"
	glow_color = Color(0.4, 1.0, 0.55)
	amount = 50


func _fallback_model() -> Node3D:
	var r := Node3D.new()
	r.name = "FallbackHealth"
	r.set_meta(&"fallback", true)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.96, 0.97)
	var cross := StandardMaterial3D.new()
	cross.albedo_color = Color(0.9, 0.12, 0.15)
	cross.emission_enabled = true
	cross.emission = Color(0.9, 0.12, 0.15)
	cross.emission_energy_multiplier = 0.9
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.26, 0.16)
	body.mesh = bm
	body.material_override = mat
	r.add_child(body)
	for sz in [Vector3(0.22, 0.07, 0.17), Vector3(0.07, 0.2, 0.17)]:
		var c := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = sz
		c.mesh = cm
		c.material_override = cross
		r.add_child(c)
	return r


func apply(character: Node) -> bool:
	if not character.has_method("heal"):
		return false
	var hp: float = character.get("health")
	var mh: float = character.get("max_health")
	if hp >= mh - 0.5:
		return false
	character.heal(float(amount))
	return true


func get_label() -> String:
	return "+%d health" % amount
