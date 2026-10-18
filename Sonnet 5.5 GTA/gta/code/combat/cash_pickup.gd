class_name CashPickup
extends PickupBase
## Loose cash (dropped by pedestrians). Always collected.


func _init() -> void:
	super._init()
	kind = &"cash"
	glow_color = Color(0.45, 1.0, 0.5)
	amount = 50
	spin_speed = 2.2


func _fallback_model() -> Node3D:
	var r := Node3D.new()
	r.name = "FallbackCash"
	r.set_meta(&"fallback", true)
	var bill := StandardMaterial3D.new()
	bill.albedo_color = Color(0.35, 0.75, 0.4)
	bill.roughness = 0.8
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.95, 0.9, 0.7)
	for i in 3:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.07, 0.15)
		b.mesh = bm
		b.material_override = bill
		b.position = Vector3(0, -0.07 + i * 0.075, 0)
		b.rotation.y = (i - 1) * 0.12
		r.add_child(b)
	var bd := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.06, 0.24, 0.16)
	bd.mesh = dm
	bd.material_override = band
	r.add_child(bd)
	return r


func apply(_character: Node) -> bool:
	Game.add_cash(amount)
	return true


func get_label() -> String:
	return "+" + Util.format_money(amount)
