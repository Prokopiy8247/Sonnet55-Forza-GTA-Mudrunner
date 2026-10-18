extends Node
## Lane-7 dev check: compares every hero landmark GLB (buildings/<id>.glb) with the lot the world layout reserves for it.
##   powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/landmark_fit_dev.gd -Seconds 60
## Prints "FIT id: model=(w x d) lot=(w x d) yaw=.. door=.." per landmark. Models are centred on the lot centre, front = lot yaw.

const IDS := ["police_station", "hospital", "weapon_shop", "garage_shop", "safehouse", "gas_station", "clothing_store", "barber", "scuba_shop",
	"train_station_a", "train_station_b", "parking_garage"]


func _aabb(n: Node3D) -> AABB:
	var have := false
	var bb := AABB()
	for mi in ModelLib.meshes(n):
		if mi.mesh == null or String(mi.name).begins_with("Collision"):
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.get_aabb()
		bb = b if not have else bb.merge(b)
		have = true
	return bb


func run(main: Node) -> Variant:
	for id: String in IDS:
		var rel: String = "buildings/" + id
		if not ModelLib.exists(rel):
			print("FIT %s: GLB missing" % id)
			continue
		var node: Node3D = ModelLib.instance(rel)
		var bb: AABB = _aabb(node)
		var em: Dictionary = ContentLib.empties(node)
		var lot: Dictionary = LayoutLots.landmark_lots.get(StringName(id), {})
		var lot_s := "no lot"
		if not lot.is_empty():
			var r: Rect2 = lot["rect"]
			var yaw: float = float(lot.get("yaw", 0.0))
			var sw: float = r.size.x
			var sd: float = r.size.y
			if absf(sin(yaw)) > 0.7:
				sw = r.size.y
				sd = r.size.x
			lot_s = "(%.1f x %.1f) yaw=%.0f" % [sw, sd, rad_to_deg(yaw)]
			var c: Vector2 = r.get_center()
			var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var rt := Vector3(cos(yaw), 0.0, -sin(yaw))
			var d: float = maxf(bb.size.x, bb.size.z) * 1.15 + 6.0
			var cam: Vector3 = Vector3(c.x, 0.0, c.y) + f * d + rt * d * 0.45 + Vector3(0, bb.size.y * 0.5 + 6.0, 0)
			print("CAM %s: %.1f,%.1f,%.1f,%.1f,%.1f,%.1f" % [id, cam.x, cam.y, cam.z, c.x, bb.size.y * 0.35, c.y])
		print("FIT %s: model=(%.1f x %.1f x h%.1f) lot=%s empties=%s" % [id, bb.size.x, bb.size.z, bb.size.y, lot_s, str(em.keys())])
		node.free()
	return true
