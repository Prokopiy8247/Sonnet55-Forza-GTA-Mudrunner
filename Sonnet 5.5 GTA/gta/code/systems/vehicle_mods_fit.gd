class_name VehicleModsFit
extends RefCounted
## Body analysis of a vehicle model (cached per vehicle id): extents, per-surface triangle meshes for ray queries, the centre-line
## profile (hood / roof / trunk runs), plate clusters, exhaust, wheel layout. The garage uses it to mount parts ON the surface
## of every ground vehicle without per-model hand tuning, and to drape livery stripes over the paint surfaces.
## All results are in the vehicle MODEL space (the same space as VehicleBase.model children; forward = -Z).

class Surf:
	var tm: TriangleMesh
	var xf := Transform3D.IDENTITY
	var inv := Transform3D.IDENTITY
	var mat := ""

static var _cache: Dictionary = {}

const SKIP_PREFIX: Array[String] = ["Wheel_", "Fork", "Pedals", "Prop", "Rotor"]


static func clear_cache() -> void:
	_cache.clear()


static func analyze(model: Node3D, def_id: StringName) -> Dictionary:
	if _cache.has(def_id):
		return _cache[def_id]
	var an := _analyze(model)
	_cache[def_id] = an
	return an


static func _skip(model: Node3D, mi: MeshInstance3D) -> bool:
	var n: Node = mi
	while n != null and n != model:
		var nm := String(n.name)
		if nm == "ModParts":
			return true
		for p in SKIP_PREFIX:
			if nm.begins_with(p):
				return true
		n = n.get_parent()
	return false


static func _analyze(model: Node3D) -> Dictionary:
	var surfs: Array = []
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	var plate_pts: Array[Vector3] = []
	for mi in ModelLib.meshes(model):
		if mi.mesh == null or _skip(model, mi):
			continue
		var xf := Util._rel_transform(model, mi)
		var bb := xf * mi.mesh.get_aabb()
		mn = mn.min(bb.position)
		mx = mx.max(bb.end)
		for s in mi.mesh.get_surface_count():
			var arrs := mi.mesh.surface_get_arrays(s)
			var vv = arrs[Mesh.ARRAY_VERTEX]
			if vv == null:
				continue
			var verts: PackedVector3Array = vv
			var idx = arrs[Mesh.ARRAY_INDEX]
			var faces := PackedVector3Array()
			if idx != null and (idx as PackedInt32Array).size() >= 3:
				for i in (idx as PackedInt32Array):
					faces.append(verts[i])
			else:
				faces = verts
			if faces.size() < 3:
				continue
			var sf := Surf.new()
			sf.tm = TriangleMesh.new()
			sf.tm.create_from_faces(faces)
			sf.xf = xf
			sf.inv = xf.affine_inverse()
			var m := mi.mesh.surface_get_material(s)
			sf.mat = m.resource_name if m != null else ""
			surfs.append(sf)
			if sf.mat == "Plate":
				for p in verts:
					plate_pts.append(xf * p)
	if surfs.is_empty():
		mn = Vector3(-0.9, 0.2, -2.2)
		mx = Vector3(0.9, 1.45, 2.2)
	var an := {"surfs": surfs, "min": mn, "max": mx}
	an["plates"] = _plate_clusters(plate_pts)
	var ex := model.find_child("Exhaust", true, false) as Node3D
	an["exhaust"] = Util._rel_transform(model, ex).origin if ex != null else Vector3.ZERO
	an["has_exhaust"] = ex != null
	_profile(an)
	return an


static func _plate_clusters(pts: Array[Vector3]) -> Array:
	var out: Array = []
	if pts.is_empty():
		return out
	for front in [true, false]:
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		var n := 0
		for p in pts:
			if (p.z < 0.0) == front:
				mn = mn.min(p)
				mx = mx.max(p)
				n += 1
		if n >= 4:
			out.append({"front": front, "min": mn, "max": mx})
	return out


# ---- ray helpers -------------------------------------------------------------------------------------------------
## Closest hit of a ray (model space) over the body surfaces: {pos, normal, mat, t} or {}.
static func ray(an: Dictionary, origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for s in an["surfs"]:
		var sf: Surf = s
		var h: Dictionary = sf.tm.intersect_ray(sf.inv * origin, sf.inv.basis * dir)
		if h.is_empty():
			continue
		var p: Vector3 = sf.xf * (h["position"] as Vector3)
		var t := (p - origin).dot(dir)
		if t < best_t and t > 0.0:
			best_t = t
			best = {"pos": p, "normal": (sf.xf.basis * (h["normal"] as Vector3)).normalized(), "mat": sf.mat, "t": t}
	return best


static func ray_down(an: Dictionary, x: float, z: float) -> Dictionary:
	var top: float = (an["max"] as Vector3).y + 1.0
	return ray(an, Vector3(x, top, z), Vector3.DOWN)


## Horizontal ray along Z (dir_z = +1 travels toward +Z) at height y.
static func ray_z(an: Dictionary, x: float, y: float, from_z: float, dir_z: float) -> Dictionary:
	return ray(an, Vector3(x, y, from_z), Vector3(0, 0, dir_z))


## Horizontal ray along X from outside toward the centre (dir_x = -sign(from_x)).
static func ray_x(an: Dictionary, z: float, y: float, from_x: float, dir_x: float) -> Dictionary:
	return ray(an, Vector3(from_x, y, z), Vector3(dir_x, 0, 0))


# ---- centre-line profile -----------------------------------------------------------------------------------------------
static func _profile(an: Dictionary) -> void:
	var mn: Vector3 = an["min"]
	var mx: Vector3 = an["max"]
	var samples: Array = []
	var z := mn.z + 0.03
	while z <= mx.z - 0.03:
		var h := ray_down(an, 0.0, z)
		if h.is_empty():
			samples.append({"z": z, "ok": false})
		else:
			samples.append({"z": z, "ok": true, "y": (h["pos"] as Vector3).y, "ny": (h["normal"] as Vector3).y, "mat": h["mat"]})
		z += 0.04
	# flat runs
	var runs: Array = []
	var cur: Dictionary = {}
	for i in samples.size():
		var s: Dictionary = samples[i]
		var flat := false
		if s["ok"] and float(s["ny"]) > 0.82 and String(s["mat"]) != "Glass":
			flat = true
			if not cur.is_empty():
				flat = absf(float(s["y"]) - float(cur["y1"])) < 0.028
		if flat:
			if cur.is_empty():
				cur = {"z0": float(s["z"]), "z1": float(s["z"]), "y0": float(s["y"]), "y1": float(s["y"]), "sum": float(s["y"]), "n": 1}
			else:
				cur["z1"] = float(s["z"])
				cur["y1"] = float(s["y"])
				cur["sum"] = float(cur["sum"]) + float(s["y"])
				cur["n"] = int(cur["n"]) + 1
		else:
			if not cur.is_empty():
				runs.append(cur)
				cur = {}
			if s["ok"] and float(s["ny"]) > 0.82 and String(s["mat"]) != "Glass":
				cur = {"z0": float(s["z"]), "z1": float(s["z"]), "y0": float(s["y"]), "y1": float(s["y"]), "sum": float(s["y"]), "n": 1}
	if not cur.is_empty():
		runs.append(cur)
	for r in runs:
		r["len"] = float(r["z1"]) - float(r["z0"])
		r["y"] = float(r["sum"]) / float(r["n"])
	an["runs"] = runs
	var len_total := mx.z - mn.z
	# hood = first long run in the front 55 %, roof = highest long run, trunk = last long run in the rear 45 %
	var hood: Dictionary = {}
	for r in runs:
		if float(r["len"]) >= 0.3 and float(r["z0"]) < mn.z + len_total * 0.5:
			hood = r
			break
	var roof: Dictionary = {}
	for r in runs:
		if float(r["len"]) >= 0.25 and (roof.is_empty() or float(r["y"]) > float(roof["y"])):
			roof = r
	var trunk: Dictionary = {}
	for i in range(runs.size() - 1, -1, -1):
		var r2: Dictionary = runs[i]
		if float(r2["len"]) >= 0.2 and float(r2["z1"]) > mn.z + len_total * 0.62 and r2 != roof:
			trunk = r2
			break
	if hood.is_empty():
		hood = {"z0": mn.z + 0.25, "z1": mn.z + len_total * 0.3, "y": (mx.y - mn.y) * 0.62 + mn.y, "len": len_total * 0.2, "synth": true}
		var hh := ray_down(an, 0.0, (float(hood["z0"]) + float(hood["z1"])) * 0.5)
		if not hh.is_empty():
			hood["y"] = (hh["pos"] as Vector3).y
	if roof.is_empty():
		roof = {"z0": mn.z + len_total * 0.35, "z1": mn.z + len_total * 0.6, "y": mx.y, "len": len_total * 0.25, "synth": true}
	an["hood"] = hood
	an["roof"] = roof
	an["trunk"] = trunk


## Half width of the upward-facing surface at a given z around the centre line (scan outward until the surface drops).
static func half_width_at(an: Dictionary, z: float, ref_y: float, max_hw: float = 1.4) -> float:
	var x := 0.1
	var last := 0.1
	while x < max_hw:
		var h := ray_down(an, x, z)
		if h.is_empty() or absf((h["pos"] as Vector3).y - ref_y) > 0.09 or float((h["normal"] as Vector3).y) < 0.6:
			break
		last = x
		x += 0.04
	return last


# =====================================================================================================
# Ribbons draped over the paint surfaces (livery)
# =====================================================================================================
const PAINT_MATS: Array[String] = ["Paint", "Paint2", "LiveryWhite", "LiveryRed"]


## Strip between x0 and x1 following the surface along z (top surfaces). Returns an ArrayMesh (material "Livery") or null.
static func drape_top(an: Dictionary, x0: float, x1: float, z0: float, z1: float, offset: float, step: float = 0.06) -> ArrayMesh:
	var mb := VehicleModsMeshes.MB.new()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_n := Vector3.UP
	var have_prev := false
	var z := z0
	var count := 0
	while z <= z1 + 0.0001:
		var hl := ray_down(an, x0, z)
		var hr := ray_down(an, x1, z)
		var ok := not hl.is_empty() and not hr.is_empty()
		if ok:
			ok = PAINT_MATS.has(String(hl["mat"])) and PAINT_MATS.has(String(hr["mat"])) and float((hl["normal"] as Vector3).y) > 0.2 and float((hr["normal"] as Vector3).y) > 0.2
		if ok:
			var nl: Vector3 = hl["normal"]
			var nr: Vector3 = hr["normal"]
			var pl: Vector3 = (hl["pos"] as Vector3) + nl * offset
			var pr: Vector3 = (hr["pos"] as Vector3) + nr * offset
			if have_prev and absf(pl.y - prev_l.y) < 0.2:
				mb.quad("Livery", prev_l, prev_r, pr, pl, (prev_n + nl + nr) * 0.3333)
				count += 1
			prev_l = pl
			prev_r = pr
			prev_n = (nl + nr) * 0.5
			have_prev = true
		else:
			have_prev = false
		z += step
	if count == 0:
		return null
	return mb.build()


## Band along the flank between heights ya..yb, following the body side (side = +1 right, -1 left).
static func drape_side(an: Dictionary, side: float, ya: float, yb: float, z0: float, z1: float, offset: float, step: float = 0.08) -> ArrayMesh:
	var mb := VehicleModsMeshes.MB.new()
	var bbmax: Vector3 = an["max"]
	var from_x := side * (bbmax.x + 1.0)
	# reference flank x: median of the hits at mid height
	var xs: Array[float] = []
	var z := z0
	while z <= z1:
		var h := ray_x(an, z, (ya + yb) * 0.5, from_x, -side)
		if not h.is_empty():
			xs.append(absf((h["pos"] as Vector3).x))
		z += 0.2
	if xs.is_empty():
		return null
	xs.sort()
	var flank: float = xs[xs.size() / 2]
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	var prev_n := Vector3.RIGHT
	var have := false
	var count := 0
	z = z0
	while z <= z1:
		var ha := ray_x(an, z, ya, from_x, -side)
		var hb := ray_x(an, z, yb, from_x, -side)
		var ok := not ha.is_empty() and not hb.is_empty()
		if ok:
			ok = PAINT_MATS.has(String(ha["mat"])) and PAINT_MATS.has(String(hb["mat"])) and absf(absf((ha["pos"] as Vector3).x) - flank) < 0.12 and absf(absf((hb["pos"] as Vector3).x) - flank) < 0.12
		if ok:
			var na: Vector3 = ha["normal"]
			var nb: Vector3 = hb["normal"]
			var pa: Vector3 = (ha["pos"] as Vector3) + na * offset
			var pb: Vector3 = (hb["pos"] as Vector3) + nb * offset
			if have:
				mb.quad("Livery", prev_a, prev_b, pb, pa, Vector3(side, 0, 0))
				count += 1
			prev_a = pa
			prev_b = pb
			prev_n = (na + nb) * 0.5
			have = true
		else:
			have = false
		z += step
	if count == 0:
		return null
	return mb.build()
