class_name SpikeStrip
extends Node3D
## Police spike strip laid across a road (stretch feature). Any non-police ground vehicle whose wheels roll over the strip gets those
## tyres punctured (VehicleBase.puncture_wheel). Code-built mesh (there is no Blender asset for it - listed as a fallback in the report).

var width := 8.0                       # across the road (local X)
var depth := 0.9
var punctured: Dictionary = {}         # vehicle instance id -> true
var hits := 0

var _area: Area3D = null
var _bodies: Array[VehicleBase] = []
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#2b2e33")
	mat.roughness = 0.8
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.05, depth)
	base.mesh = bm
	base.material_override = mat
	base.position = Vector3(0, 0.025, 0)
	add_child(base)
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color("#c9ced6")
	spike_mat.metallic = 0.6
	spike_mat.roughness = 0.35
	var sm := PrismMesh.new()
	sm.size = Vector3(0.1, 0.12, 0.1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	var per_row := int(width / 0.28)
	mm.instance_count = per_row * 3
	var k := 0
	for row in 3:
		for i in per_row:
			var x := -width * 0.5 + 0.14 + float(i) * (width - 0.28) / float(maxi(per_row - 1, 1))
			var z := (float(row) - 1.0) * 0.28
			mm.set_instance_transform(k, Transform3D(Basis(), Vector3(x, 0.11, z)))
			k += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = spike_mat
	add_child(mmi)
	# trigger volume
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = GC.L_VEHICLE
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 1.2, depth + 1.0)
	cs.shape = box
	cs.position = Vector3(0, 0.6, 0)
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	push_warning("SpikeStrip: code-built mesh (no Blender asset 'props/spike_strip')")


func _on_body_entered(b: Node) -> void:
	if b is VehicleBase and not _bodies.has(b):
		_bodies.append(b)


func _on_body_exited(b: Node) -> void:
	_bodies.erase(b)


func _physics_process(_dt: float) -> void:
	if _bodies.is_empty():
		return
	var inv := global_transform.affine_inverse()
	for b in _bodies:
		if not is_instance_valid(b) or b.faction == GC.F_POLICE or b.is_destroyed:
			continue
		if b.get_speed() < 1.0:
			continue
		for i in b.wheels.size():
			var w: VehicleWheel = b.wheels[i]
			if w.flat:
				continue
			var wp: Vector3 = b.global_transform * w.rest
			var local := inv * wp
			if absf(local.x) <= width * 0.5 and absf(local.z) <= depth * 0.5 + 0.12:
				b.puncture_wheel(i)
				hits += 1
				punctured[b.get_instance_id()] = true
