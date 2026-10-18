class_name InteractionLadders
extends RefCounted
## Roof-access ladders (props/ladder_wall.glb, 3.6 m per segment). plan() scans the building lots for wall spots that really work
## (ray + capsule + roof tests against the live colliders) and picks WANTED of them spread over the districts; build_visual() renders
## one ladder as a single MultiMesh. The climb itself is PlayerTraversal.start_ladder(bottom, top, face_dir, start_u).
##
## record = {id, lot, district, bottom (ground at the wall), top (roof height at the wall), normal (outward, flat), roof_y, height}

const GLB := "props/ladder_wall"
const SEG_H := 3.6
const WANTED := 8
const MIN_ROOF_H := 6.5
const MAX_ROOF_H := 40.0
const MIN_SEP := 45.0
const OVERSHOOT := 1.1                   # rails stick out above the roof edge
const DISTRICT_CAP := {&"downtown": 3, &"residential": 3, &"industrial": 3, &"waterfront": 2, &"airport": 2, &"beach": 1, &"park_hills": 1}
const KINDS: Array[StringName] = [&"apartment", &"office", &"shop", &"warehouse", &"factory"]


static func plan(rng: RandomNumberGenerator, wanted: int = WANTED) -> Array:
	var cands: Array = []
	for lot in WorldLayout.lots:
		if not (lot["kind"] in KINDS) or lot["landmark"] != &"":
			continue
		var rect: Rect2 = lot["rect"]
		var best := {}
		var best_score := -INF
		for side in 4:
			for frac in [0.5, 0.3, 0.7, 0.15, 0.85]:
				var rec := _probe(rect, side, frac)
				if rec.is_empty():
					continue
				# prefer flanks / backs over the street front, and a mid-sized roof
				var front_penalty := 6.0 if _is_front(lot, side) else 0.0
				var score := rng.randf() * 4.0 - front_penalty - absf(float(rec["height"]) - 16.0) * 0.12
				if score > best_score:
					best_score = score
					best = rec
					best["lot"] = int(lot["id"])
					best["district"] = lot["district"]
				break
		if not best.is_empty():
			best["score"] = best_score
			cands.append(best)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var picked: Array = []
	var per_district: Dictionary = {}
	for c in cands:
		if picked.size() >= wanted:
			break
		var d: StringName = c["district"]
		if int(per_district.get(d, 0)) >= int(DISTRICT_CAP.get(d, 2)):
			continue
		var ok := true
		for p in picked:
			if Util.dist_xz(p["bottom"], c["bottom"]) < MIN_SEP:
				ok = false
				break
		if not ok:
			continue
		per_district[d] = int(per_district.get(d, 0)) + 1
		c["id"] = "ladder_%d" % picked.size()
		picked.append(c)
	return picked


static func _is_front(lot: Dictionary, side: int) -> bool:
	var face: String = lot["side"]
	return (side == 0 and face == "n") or (side == 1 and face == "s") or (side == 2 and face == "w") or (side == 3 and face == "e")


## One wall candidate on `side` (0 north, 1 south, 2 west, 3 east) of a lot rect at fraction `frac`; {} when the spot is unusable.
static func _probe(rect: Rect2, side: int, frac: float) -> Dictionary:
	var n: Vector3
	var p: Vector3
	match side:
		0:
			n = Vector3(0, 0, -1)
			p = Vector3(rect.position.x + rect.size.x * frac, 0.0, rect.position.y)
		1:
			n = Vector3(0, 0, 1)
			p = Vector3(rect.position.x + rect.size.x * frac, 0.0, rect.end.y)
		2:
			n = Vector3(-1, 0, 0)
			p = Vector3(rect.position.x, 0.0, rect.position.y + rect.size.y * frac)
		_:
			n = Vector3(1, 0, 0)
			p = Vector3(rect.end.x, 0.0, rect.position.y + rect.size.y * frac)
	var gy0 := WorldLayout.terrain_height(p.x, p.z)
	var from := Vector3(p.x, gy0 + 1.4, p.z) + n * 8.0
	var to := Vector3(p.x, gy0 + 1.4, p.z) - n * 5.0
	var hit := InteractionUtil.ray(from, to, GC.L_WORLD)
	if hit.is_empty():
		return {}
	var wn: Vector3 = hit["normal"]
	if absf(wn.y) > 0.25 or Util.flat(wn).normalized().dot(n) < 0.9:
		return {}
	var w: Vector3 = hit["position"]
	var out := Util.flat(wn).normalized()
	# ground in front of the ladder
	var gnd := InteractionUtil.ground_at(w.x + out.x * 0.95, w.z + out.z * 0.95, 2.5, 4.0)
	if gnd.is_empty() or (gnd["normal"] as Vector3).y < 0.9:
		return {}
	var gy: float = (gnd["position"] as Vector3).y
	if gy < -0.5 or absf(gy - gy0) > 1.0:
		return {}
	if not InteractionUtil.clear_at(Vector3(w.x + out.x * 0.95, gy, w.z + out.z * 0.95), 0.4):
		return {}
	var yaw := Util.dir_to_yaw(out)
	if not InteractionUtil.box_free(Vector3(w.x + out.x * 0.3, gy + 1.8, w.z + out.z * 0.3), Vector3(0.9, 3.4, 0.4), yaw):
		return {}
	# roof above the wall
	var rx := w.x - out.x * 0.7
	var rz := w.z - out.z * 0.7
	var roof := InteractionUtil.surface_at(rx, rz, gy + 120.0, gy + 2.0, GC.L_WORLD)
	if roof.is_empty() or (roof["normal"] as Vector3).y < 0.85:
		return {}
	var roof_y: float = (roof["position"] as Vector3).y
	var height := roof_y - gy
	if height < MIN_ROOF_H or height > MAX_ROOF_H:
		return {}
	# the roof must continue inland at the same height and the exit point must be free
	var inland := InteractionUtil.surface_at(w.x - out.x * 2.0, w.z - out.z * 2.0, roof_y + 2.0, roof_y - 0.6, GC.L_WORLD)
	if inland.is_empty():
		return {}
	if not InteractionUtil.clear_at(Vector3(w.x - out.x * 0.8, roof_y + 0.02, w.z - out.z * 0.8), 0.35, 1.7):
		return {}
	if InteractionElevator.furniture_near(Vector3(w.x + out.x * 1.0, gy, w.z + out.z * 1.0), 1.3):     # baked bins / lamps / benches have no collider
		return {}
	return {"bottom": Vector3(w.x, gy, w.z), "top": Vector3(w.x, roof_y, w.z), "normal": out, "roof_y": roof_y, "height": height}


# ======================================================================================================== visual
## One ladder as a MultiMeshInstance3D (stacked segments, last one shortened to end OVERSHOOT above the roof).
static func build_visual(rec: Dictionary) -> Node3D:
	var model := ModelLib.instance(GLB)
	if model == null:
		push_warning("[InteractionLadders] props/ladder_wall.glb missing - ladder uses a code-built stand-in")
		return _fallback_visual(rec)
	var body := ModelLib.find_mesh(model, "Body")
	if body == null or body.mesh == null:
		model.free()
		return _fallback_visual(rec)
	var total := float(rec["height"]) + OVERSHOOT
	var n := maxi(int(ceil(total / SEG_H - 0.001)), 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = body.mesh
	mm.instance_count = n
	var out: Vector3 = rec["normal"]
	var basis := Basis(Vector3.UP, Util.dir_to_yaw(out))
	var base: Vector3 = rec["bottom"]
	for i in n:
		var seg_len := minf(SEG_H, total - SEG_H * float(i))
		var sy := seg_len / SEG_H
		var origin := base + Vector3.UP * (SEG_H * float(i))
		mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(Vector3(1.0, sy, 1.0)), origin))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Ladder_" + String(rec["id"])
	mmi.multimesh = mm
	mmi.position = Vector3.ZERO
	model.free()
	return mmi


static func _fallback_visual(rec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "LadderFallback_" + String(rec["id"])
	root.set_meta(&"fallback", true)
	var out: Vector3 = rec["normal"]
	var h := float(rec["height"]) + OVERSHOOT
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#d8c040")
	for sx in [-0.28, 0.28]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, h, 0.05)
		rail.mesh = bm
		rail.material_override = mat
		rail.position = Vector3(sx, h * 0.5, -0.12)
		root.add_child(rail)
	var rungs := int(h / 0.3)
	for i in rungs:
		var r := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.56, 0.04, 0.04)
		r.mesh = rm
		r.material_override = mat
		r.position = Vector3(0, 0.2 + i * 0.3, -0.12)
		root.add_child(r)
	root.position = rec["bottom"]
	root.rotation.y = Util.dir_to_yaw(out)
	return root
