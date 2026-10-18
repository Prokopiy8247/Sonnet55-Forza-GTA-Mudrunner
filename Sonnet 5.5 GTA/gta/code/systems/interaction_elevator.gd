class_name InteractionElevator
extends RefCounted
## The downtown tower elevator (the 28-floor office lot that carries `helipad_downtown`): a lift door on the front facade at street level and a
## rooftop elevator house beside the helipad. plan() finds both spots against the live colliders; build_* instance the Blender props
## (props/elevator_door.glb, props/elevator_roof.glb: nodes DoorL / DoorR slide sideways, empty `Stand` = where a rider steps out).

const DOOR_GLB := "props/elevator_door"
const ROOF_GLB := "props/elevator_roof"
const DOOR_SLIDE := 0.52                 # how far each leaf slides (m)
const STAND_OUT := 1.5                   # rider stands this far in front of the door


## {ground: {pos, normal, stand, yaw}, roof: {pos, normal, stand, yaw, roof_y}, lot} or {} when no tower / no valid spot was found.
static func plan() -> Dictionary:
	var tower := {}
	for lot in WorldLayout.lots:
		if lot["kind"] == &"office" and lot["landmark"] == &"" and (tower.is_empty() or int(lot["floors"]) > int(tower["floors"])):
			tower = lot
	if tower.is_empty():
		return {}
	var ground := _plan_ground(tower)
	var roof := _plan_roof()
	if ground.is_empty() or roof.is_empty():
		push_warning("[InteractionElevator] no valid elevator spots (ground=%s roof=%s)" % [str(not ground.is_empty()), str(not roof.is_empty())])
		return {}
	return {"ground": ground, "roof": roof, "lot": int(tower["id"])}


static func _plan_ground(tower: Dictionary) -> Dictionary:
	var rect: Rect2 = tower["rect"]
	var face: Vector3
	var edge_p := Vector3.ZERO
	var along := Vector3.ZERO
	var length := 0.0
	match String(tower["side"]):
		"n":
			face = Vector3(0, 0, -1)
			edge_p = Vector3(rect.position.x, 0, rect.position.y)
			along = Vector3(1, 0, 0)
			length = rect.size.x
		"s":
			face = Vector3(0, 0, 1)
			edge_p = Vector3(rect.position.x, 0, rect.end.y)
			along = Vector3(1, 0, 0)
			length = rect.size.x
		"w":
			face = Vector3(-1, 0, 0)
			edge_p = Vector3(rect.position.x, 0, rect.position.y)
			along = Vector3(0, 0, 1)
			length = rect.size.y
		_:
			face = Vector3(1, 0, 0)
			edge_p = Vector3(rect.end.x, 0, rect.position.y)
			along = Vector3(0, 0, 1)
			length = rect.size.y
	for frac in [0.5, 0.38, 0.62, 0.26, 0.74, 0.18, 0.82]:
		var p: Vector3 = edge_p + along * length * frac
		if furniture_near(p + face * 1.6, 3.0):         # bus stops, benches, lamps: baked props without colliders must not hide the lift door
			continue
		var gy0 := WorldLayout.terrain_height(p.x, p.z)
		var hit := InteractionUtil.ray(Vector3(p.x, gy0 + 1.4, p.z) + face * 7.0, Vector3(p.x, gy0 + 1.4, p.z) - face * 5.0, GC.L_WORLD)
		if hit.is_empty() or absf((hit["normal"] as Vector3).y) > 0.25:
			continue
		var w: Vector3 = hit["position"]
		var out := Util.flat(hit["normal"]).normalized()
		var stand_xz := w + out * STAND_OUT
		var gnd := InteractionUtil.ground_at(stand_xz.x, stand_xz.z, 2.5, 4.0)
		if gnd.is_empty() or (gnd["normal"] as Vector3).y < 0.9:
			continue
		var gy: float = (gnd["position"] as Vector3).y
		var yaw := Util.dir_to_yaw(out)
		if not InteractionUtil.clear_at(Vector3(stand_xz.x, gy, stand_xz.z), 0.4):
			continue
		if not InteractionUtil.box_free(Vector3(w.x + out.x * 0.35, gy + 1.3, w.z + out.z * 0.35), Vector3(2.4, 2.4, 0.5), yaw):
			continue
		return {"pos": Vector3(w.x, gy, w.z), "normal": out, "stand": Vector3(stand_xz.x, gy, stand_xz.z), "yaw": yaw}
	return {}


static func furniture_near(p: Vector3, radius: float) -> bool:
	var r2 := radius * radius
	for f in WorldLayout.furniture:
		var fp: Vector3 = f["pos"]
		var dx := fp.x - p.x
		var dz := fp.z - p.z
		if dx * dx + dz * dz < r2:
			return true
	return false


static func _plan_roof() -> Dictionary:
	if not WorldLayout.has_location(&"helipad_downtown"):
		return {}
	var hp: Vector3 = WorldLayout.location_pos(&"helipad_downtown")
	var top := InteractionUtil.surface_at(hp.x, hp.z, hp.y + 6.0, hp.y - 6.0, GC.L_WORLD)
	if top.is_empty():
		return {}
	var roof_y: float = (top["position"] as Vector3).y
	for a in 12:
		var ang := TAU * float(a) / 12.0 + 0.5
		var out_dir := Vector3(cos(ang), 0.0, sin(ang))              # from the helipad centre towards the house
		for dist in [12.5, 11.0, 14.0]:
			var house: Vector3 = hp + out_dir * float(dist)
			house.y = roof_y
			# the house door faces the helipad
			var face := -out_dir
			var yaw := Util.dir_to_yaw(face)
			var ok := true
			for corner in [Vector3(-1.9, 0, -1.6), Vector3(1.9, 0, -1.6), Vector3(-1.9, 0, 1.6), Vector3(1.9, 0, 1.6)]:
				var cp: Vector3 = house + Basis(Vector3.UP, yaw) * corner
				var s := InteractionUtil.surface_at(cp.x, cp.z, roof_y + 3.0, roof_y - 1.0, GC.L_WORLD)
				if s.is_empty() or absf((s["position"] as Vector3).y - roof_y) > 0.25:
					ok = false
					break
			if not ok:
				continue
			if not InteractionUtil.box_free(house + Vector3(0, 1.7, 0), Vector3(4.0, 3.2, 3.4), yaw):
				continue
			var stand: Vector3 = house + face * (1.7 + STAND_OUT)
			var ss := InteractionUtil.surface_at(stand.x, stand.z, roof_y + 2.0, roof_y - 1.0, GC.L_WORLD)
			if ss.is_empty() or absf((ss["position"] as Vector3).y - roof_y) > 0.25:
				continue
			if not InteractionUtil.clear_at(Vector3(stand.x, roof_y + 0.02, stand.z), 0.4):
				continue
			return {"pos": house, "normal": face, "stand": Vector3(stand.x, roof_y + 0.05, stand.z), "yaw": Util.dir_to_yaw(face), "roof_y": roof_y}
	return {}


# ======================================================================================================== visuals
## Instances a Blender elevator prop (origin on the floor, front = -Z). Returns {root, left, right} (leaf nodes may be null).
static func build_door(rel: String, xform: Transform3D, parent: Node3D, solid_size: Vector3 = Vector3.ZERO) -> Dictionary:
	var root := Node3D.new()
	root.name = "Elevator_" + rel.get_file()
	parent.add_child(root)
	root.global_transform = xform
	if solid_size != Vector3.ZERO:                    # the roof house is a solid building: nobody walks through it
		var body := StaticBody3D.new()
		body.name = "Collider"
		body.collision_layer = GC.L_WORLD
		body.collision_mask = 0
		body.set_meta(&"surface", &"concrete")
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = solid_size
		cs.shape = sh
		cs.position = Vector3(0, solid_size.y * 0.5, 0)
		body.add_child(cs)
		root.add_child(body)
	var model := ModelLib.instance(rel)
	var left: Node3D = null
	var right: Node3D = null
	if model == null:
		push_warning("[InteractionElevator] %s.glb missing - code-built stand-in door" % rel)
		root.set_meta(&"fallback", true)
		left = _fallback_leaf(root, -0.5)
		right = _fallback_leaf(root, 0.5)
	else:
		root.add_child(model)
		left = model.find_child("DoorL", true, false) as Node3D
		right = model.find_child("DoorR", true, false) as Node3D
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 220.0
	var res := {"root": root, "left": left, "right": right, "left_rest": left.position if left != null else Vector3.ZERO,
		"right_rest": right.position if right != null else Vector3.ZERO, "open": 0.0}
	return res


static func _fallback_leaf(root: Node3D, x: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 2.3, 0.08)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#9aa7b0")
	mat.metallic = 0.7
	mat.roughness = 0.4
	mi.material_override = mat
	mi.position = Vector3(x, 1.15, 0)
	root.add_child(mi)
	return mi
