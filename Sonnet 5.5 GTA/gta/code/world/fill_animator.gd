class_name FillAnimator
extends Node
## Animates the few moving world-fill props (ferris wheel). One node, processing only while the wheel is within 420 m of the camera.
## Entries: {base: Transform3D, wheel_mm, wheel_local, gondolas: [{mm, local}], speed, angle, inv}.

var wheels: Array = []
var _acc := 0.0


static func get_or_create(batch: ContentBatch) -> FillAnimator:
	if is_instance_valid(FillBuilder.animator):
		return FillBuilder.animator as FillAnimator
	var a := FillAnimator.new()
	a.name = "FillAnimator"
	batch.content_root.add_child(a)
	batch.own(a)
	FillBuilder.animator = a
	return a


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.033:
		return
	var dt := _acc
	_acc = 0.0
	var cam := get_viewport().get_camera_3d()
	for e in wheels:
		var base: Transform3D = e["base"]
		if cam != null and cam.global_position.distance_squared_to(base.origin) > 420.0 * 420.0:
			continue
		e["angle"] = fposmod(float(e["angle"]) + float(e["speed"]) * dt, TAU)
		var ang := float(e["angle"])
		var inv: Transform3D = e["inv"]
		var wl: Transform3D = e["wheel_local"]
		var wheel_xf: Transform3D = base * wl * Transform3D(Basis(Vector3.BACK, ang), Vector3.ZERO)
		var wmm: MultiMesh = e["wheel_mm"]
		if wmm != null:
			wmm.set_instance_transform(0, inv * wheel_xf)
		for g in (e["gondolas"] as Array):
			var gl: Transform3D = g["local"]
			var gx: Transform3D = wheel_xf * Transform3D(Basis.IDENTITY, gl.origin) * Transform3D(Basis(Vector3.BACK, -ang) * gl.basis, Vector3.ZERO)
			(g["mm"] as MultiMesh).set_instance_transform(0, inv * gx)
