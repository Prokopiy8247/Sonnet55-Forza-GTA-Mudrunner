class_name VehicleFallback
extends RefCounted
## CODE-BUILT FALLBACK vehicle model, used ONLY while the Blender GLB (vehicles/<id>.glb) does not exist yet.
## It follows the same node contract as the Blender assets (Body, Wheel_*, Seat*, Exit*, Headlight*, Taillight*, SirenBar,
## materials Paint / Glass / Trim / LightHead / LightTail ...), so physics, paint, lights and enter/exit work identically.
## VehicleFactory logs a warning and records the id in VehicleFactory.fallback_used every time this is used.


static func build(def: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "FallbackModel_" + String(def.get("id", "vehicle"))
	var cls: StringName = def.get("class", GC.VC_CAR)
	if cls == GC.VC_BIKE or cls == GC.VC_BICYCLE:
		_build_bike(root, def)
		return root
	var l: float = def.get("length", 4.5)
	var w: float = def.get("width", 1.8)
	var h: float = def.get("height", 1.45)
	var wb: float = def.get("wheelbase", 2.7)
	var tr: float = def.get("track", 1.55)
	var r: float = def.get("wheel_radius", 0.33)
	var ww: float = def.get("wheel_width", 0.22)
	var low_h := (h - 0.3) * 0.5
	var floor_y := 0.3
	var is_big := l > 7.0
	# lower body
	_box(root, "Body", Vector3(0, floor_y + low_h * 0.5, 0), Vector3(w, low_h, l), "Paint")
	# cabin (glass) + roof; trucks get a cab at the front, vans a full-length box
	var cab_len := l * (0.5 if not is_big else 0.28)
	var cab_z := l * 0.06 if not is_big else -l * 0.3
	var cab_h := h - floor_y - low_h
	_box(root, "Cabin", Vector3(0, floor_y + low_h + cab_h * 0.5, cab_z), Vector3(w * 0.9, cab_h, cab_len), "Glass")
	_box(root, "Roof", Vector3(0, floor_y + low_h + cab_h, cab_z), Vector3(w * 0.92, 0.06, cab_len * 0.98), "Paint")
	if is_big or l > 4.9 and h > 1.9:
		var box_h := h - floor_y - low_h
		_box(root, "Cargo", Vector3(0, floor_y + low_h + box_h * 0.5, l * 0.2), Vector3(w * 0.98, box_h, l * 0.5), "Paint2")
	# bumpers (trim)
	_box(root, "BumperF", Vector3(0, floor_y + 0.1, -l * 0.5 - 0.02), Vector3(w * 0.96, 0.22, 0.12), "Trim")
	_box(root, "BumperR", Vector3(0, floor_y + 0.1, l * 0.5 + 0.02), Vector3(w * 0.96, 0.22, 0.12), "Trim")
	# lamps
	var lx := w * 0.5 - 0.28
	_box(root, "LampHL", Vector3(-lx, floor_y + low_h * 0.7, -l * 0.5 - 0.03), Vector3(0.34, 0.15, 0.06), "LightHead")
	_box(root, "LampHR", Vector3(lx, floor_y + low_h * 0.7, -l * 0.5 - 0.03), Vector3(0.34, 0.15, 0.06), "LightHead")
	_box(root, "LampTL", Vector3(-lx, floor_y + low_h * 0.7, l * 0.5 + 0.03), Vector3(0.34, 0.15, 0.06), "LightTail")
	_box(root, "LampTR", Vector3(lx, floor_y + low_h * 0.7, l * 0.5 + 0.03), Vector3(0.34, 0.15, 0.06), "LightTail")
	_empty(root, "HeadlightL", Vector3(-lx, floor_y + low_h * 0.7, -l * 0.5))
	_empty(root, "HeadlightR", Vector3(lx, floor_y + low_h * 0.7, -l * 0.5))
	_empty(root, "TaillightL", Vector3(-lx, floor_y + low_h * 0.7, l * 0.5))
	_empty(root, "TaillightR", Vector3(lx, floor_y + low_h * 0.7, l * 0.5))
	_empty(root, "Exhaust", Vector3(w * 0.3, 0.25, l * 0.5 + 0.05))
	_empty(root, "Hood", Vector3(0, floor_y + low_h, -l * 0.33))
	# siren bar
	var siren: String = String(def.get("siren", ""))
	if siren != "":
		var sy := h + 0.06
		_box(root, "SirenBase", Vector3(0, sy, cab_z), Vector3(0.9, 0.08, 0.3), "Trim")
		_box(root, "SirenR", Vector3(-0.22, sy + 0.08, cab_z), Vector3(0.36, 0.12, 0.26), "LightRed")
		_box(root, "SirenB", Vector3(0.22, sy + 0.08, cab_z), Vector3(0.36, 0.12, 0.26), "LightBlue")
		_empty(root, "SirenBar", Vector3(0, sy + 0.1, cab_z))
	# wheels
	var zf := -wb * 0.5
	var zr := wb * 0.5
	var xs := tr * 0.5
	var wheel_defs: Array = [["Wheel_FL", -xs, zf], ["Wheel_FR", xs, zf], ["Wheel_RL", -xs, zr], ["Wheel_RR", xs, zr]]
	if is_big:
		wheel_defs = [["Wheel_FL", -xs, zf], ["Wheel_FR", xs, zf], ["Wheel_ML", -xs, zr - 1.35], ["Wheel_MR", xs, zr - 1.35], ["Wheel_RL", -xs, zr], ["Wheel_RR", xs, zr]]
	for wd in wheel_defs:
		_wheel(root, wd[0], Vector3(wd[1], r, wd[2]), r, ww)
	# seats (feet / floor level; the character origin is placed here) and exits
	var sz := cab_z - cab_len * 0.15 if not is_big else cab_z
	var seat_y := floor_y + 0.3 + (0.25 if is_big else 0.0)
	_empty(root, "SeatDriver", Vector3(-w * 0.22, seat_y, sz))
	_empty(root, "SeatPassenger", Vector3(w * 0.22, seat_y, sz))
	if int(def.get("seats", 4)) > 2 and not is_big and not (l > 4.9 and h > 1.9):
		_empty(root, "SeatRearL", Vector3(-w * 0.22, seat_y, sz + 1.0))
		_empty(root, "SeatRearR", Vector3(w * 0.22, seat_y, sz + 1.0))
	_empty(root, "ExitL", Vector3(-(w * 0.5 + 0.6), 0, sz))
	_empty(root, "ExitR", Vector3(w * 0.5 + 0.6, 0, sz))
	return root


static func _build_bike(root: Node3D, def: Dictionary) -> void:
	var l: float = def.get("length", 2.0)
	var wb: float = def.get("wheelbase", 1.45)
	var r: float = def.get("wheel_radius", 0.32)
	var is_bicycle: bool = def.get("class", GC.VC_BIKE) == GC.VC_BICYCLE
	_box(root, "Body", Vector3(0, r + 0.28, 0.05), Vector3(0.22 if not is_bicycle else 0.05, 0.3 if not is_bicycle else 0.05, wb * 0.8), "Paint")
	if not is_bicycle:
		_box(root, "Tank", Vector3(0, r + 0.5, -0.2), Vector3(0.3, 0.2, 0.55), "Paint2")
		_box(root, "Lamp", Vector3(0, r + 0.5, -wb * 0.5 - 0.1), Vector3(0.18, 0.14, 0.08), "LightHead")
		_box(root, "Tail", Vector3(0, r + 0.55, wb * 0.5 + 0.05), Vector3(0.16, 0.06, 0.08), "LightTail")
	_box(root, "Seat", Vector3(0, r + 0.5, 0.28), Vector3(0.22, 0.08, 0.6), "Trim")
	var fork := Node3D.new()
	fork.name = "Fork"
	fork.position = Vector3(0, r + 0.55, -wb * 0.5 + 0.15)
	root.add_child(fork)
	_box(fork, "ForkMesh", Vector3(0, -0.15, -0.05), Vector3(0.06, 0.55, 0.06), "Trim")
	_box(fork, "Bars", Vector3(0, 0.1, 0.0), Vector3(0.7, 0.05, 0.05), "Trim")
	_wheel(root, "Wheel_F", Vector3(0, r, -wb * 0.5), r, def.get("wheel_width", 0.16))
	_wheel(root, "Wheel_R", Vector3(0, r, wb * 0.5), r, def.get("wheel_width", 0.16))
	if is_bicycle:
		_empty(root, "Pedals", Vector3(0, r * 0.7, 0.0))
	_empty(root, "HeadlightF", Vector3(0, r + 0.5, -wb * 0.5 - 0.1))
	_empty(root, "TaillightR", Vector3(0, r + 0.55, wb * 0.5 + 0.05))
	_empty(root, "Exhaust", Vector3(0.2, 0.25, wb * 0.5))
	_empty(root, "SeatDriver", Vector3(0, r + 0.5, 0.28))
	if int(def.get("seats", 1)) > 1:
		_empty(root, "SeatPassenger", Vector3(0, r + 0.5, 0.68))
	_empty(root, "ExitL", Vector3(-0.75, 0, 0.25))
	_empty(root, "ExitR", Vector3(0.75, 0, 0.25))


static func _empty(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


static func _mat(mat_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	match mat_name:
		"Paint": m.albedo_color = Color("#c43a3a"); m.roughness = 0.35; m.metallic = 0.2
		"Paint2": m.albedo_color = Color("#2a2d33"); m.roughness = 0.5
		"Glass": m.albedo_color = Color(0.07, 0.11, 0.14, 0.55); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.roughness = 0.08
		"Trim": m.albedo_color = Color("#1c1e22"); m.roughness = 0.7
		"LightHead": m.albedo_color = Color(0.86, 0.9, 0.95)
		"LightTail": m.albedo_color = Color(0.42, 0.04, 0.05)
		"LightRed": m.albedo_color = Color(0.4, 0.03, 0.03)
		"LightBlue": m.albedo_color = Color(0.03, 0.08, 0.4)
		"Tire": m.albedo_color = Color("#17181b"); m.roughness = 0.9
		"Rim": m.albedo_color = Color("#aab2bb"); m.metallic = 0.7; m.roughness = 0.3
		_: m.albedo_color = Color.GRAY
	return m


static func _box(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, mat_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(mat_name)
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _wheel(parent: Node3D, node_name: String, pos: Vector3, r: float, width: float) -> void:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = width
	cm.radial_segments = 16
	cm.rings = 1
	cm.material = _mat("Tire")
	tire.mesh = cm
	tire.rotation = Vector3(0, 0, PI * 0.5)
	n.add_child(tire)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var rm := CylinderMesh.new()
	rm.top_radius = r * 0.6
	rm.bottom_radius = r * 0.6
	rm.height = width * 1.04
	rm.radial_segments = 8
	rm.rings = 1
	rm.material = _mat("Rim")
	rim.mesh = rm
	rim.rotation = Vector3(0, 0, PI * 0.5)
	n.add_child(rim)
