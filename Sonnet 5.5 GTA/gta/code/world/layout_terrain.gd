class_name LayoutTerrain
extends RefCounted
## Baked terrain height field for the whole map (3 m grid). `WorldLayout.terrain_height()` reads from here, the terrain
## mesh and the trimesh collider are built from the SAME grid so visuals, physics and gameplay queries agree exactly.
## Grid covers x in [-330, 330], z in [-330, 420]; the playable ground is [-300, 300]^2 (sea continues south).

const CELL := 3.0
const X0 := -330.0
const Z0 := -330.0
const NX := 221            # samples along x  (660 / 3 + 1)
const NZ := 251            # samples along z  (750 / 3 + 1)
const X1 := X0 + CELL * (NX - 1)
const Z1 := Z0 + CELL * (NZ - 1)

const PEAK := Vector2(215.0, -228.0)
const POND_C := Vector2(-80.0, -152.0)
const POND_R := 21.0

static var heights := PackedFloat32Array()
static var baked := false


# ---- natural (analytic) terrain -------------------------------------------------------------------------------
static func _bump(x: float, z: float, cx: float, cz: float, r: float, a: float) -> float:
	var dx := x - cx
	var dz := z - cz
	var d2 := (dx * dx + dz * dz) / (r * r)
	if d2 >= 1.0:
		return 0.0
	var k := 1.0 - d2
	return a * k * k


static func wq(x: float) -> float:
	## weight of the vertical quay profile (1 = seawall quay west and east, 0 = open sand beach in the middle)
	var w := LayoutGeo.smoothstep(-62.0, -100.0, x)
	var e := LayoutGeo.smoothstep(48.0, 74.0, x)
	return maxf(w, e)


static func shore_edge(x: float) -> float:
	var q := wq(x)
	var beach := 160.0 + 4.0 * sin(x / 31.0 + 1.0)
	return lerpf(beach, 192.0, q)


static func sea_profile(x: float, z: float) -> float:
	var q := wq(x)
	var t := z - shore_edge(x)
	if t <= 0.0:
		return 0.0
	var b := 0.0
	if t < 16.0:
		b = -0.09 * t
	elif t < 60.0:
		b = -1.44 - (t - 16.0) * 0.12
	else:
		b = -6.72 - (t - 60.0) * 0.16
	var qq := -minf(3.2 * t, 4.0) - 0.07 * maxf(t - 1.3, 0.0) - maxf(t - 40.0, 0.0) * 0.12
	return lerpf(b, qq, q)


static func natural_height(x: float, z: float) -> float:
	var h := 0.0
	# south sea / beach / quays
	var q := 1.0
	if z > 120.0:
		var sp := sea_profile(x, z)
		if sp < 0.0:
			h = sp
			# gentle sand ripples on the beach + sea floor
			if h < -0.5:
				h += (LayoutGeo.vnoise(x * 0.07, z * 0.07, 3) - 0.5) * 0.5
	# pond in the park
	var pd := Vector2(x, z).distance_to(POND_C)
	if pd < POND_R + 7.0:
		var pt := 1.0 - LayoutGeo.smoothstep(POND_R - 4.0, POND_R + 7.0, pd)
		h = minf(h, -3.3 * pt)
	# NE hills (+ north rise); fully flat on the urban plateau
	if z < -96.0 and x > 20.0:
		var hh := _bump(x, z, PEAK.x, PEAK.y, 135.0, 54.0)
		hh += _bump(x, z, 118.0, -190.0, 62.0, 22.0)
		hh += _bump(x, z, 280.0, -150.0, 70.0, 26.0)
		hh += _bump(x, z, 262.0, -300.0, 80.0, 20.0)
		hh += _bump(x, z, 150.0, -300.0, 80.0, 14.0)
		var mask := LayoutGeo.smoothstep(-96.0, -126.0, z) * LayoutGeo.smoothstep(20.0, 60.0, x)
		hh *= mask
		if hh > 0.2:
			var nz := (LayoutGeo.vnoise(x * 0.05, z * 0.05, 7) - 0.5) * 6.0 + (LayoutGeo.vnoise(x * 0.16, z * 0.16, 11) - 0.5) * 2.2
			hh += nz * clampf(hh / 14.0, 0.0, 1.0)
		h += maxf(hh, 0.0)
	# world edge berms (hide the invisible walls, give the backdrop something to start from)
	var edge := maxf(maxf(absf(x), -z), 0.0)
	if edge > 292.0:
		var berm := 7.0 * LayoutGeo.smoothstep(292.0, 328.0, edge)
		var land := 1.0
		if z > 150.0:
			land = clampf(1.0 - maxf(z - shore_edge(x), 0.0) / 6.0, 0.0, 1.0)
		if x > 0.0:
			land *= LayoutGeo.smoothstep(12.0, 34.0, absf(z - 165.0)) if z > 120.0 else 1.0
		h += berm * land * (0.8 + 0.4 * LayoutGeo.vnoise(x * 0.1, z * 0.1, 5))
	return h


# ---- baking ---------------------------------------------------------------------------------------------------
static func bake(carve_paths: Array = []) -> void:
	heights.resize(NX * NZ)
	for iz in NZ:
		var z := Z0 + iz * CELL
		var row := iz * NX
		for ix in NX:
			heights[row + ix] = natural_height(X0 + ix * CELL, z)
	baked = true
	for cp in carve_paths:
		_carve(cp)


## cp = {"pts": PackedVector2Array (dense, ~2 m), "half": float, "ys": PackedFloat32Array (out), "start_y", "end_free"}
static func _carve(cp: Dictionary) -> void:
	var pts: PackedVector2Array = cp["pts"]
	var n := pts.size()
	if n < 2:
		return
	# raw natural profile
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = height(pts[i].x, pts[i].y)
	# smooth (moving average +-8 samples) then grade-limit
	var ys := PackedFloat32Array()
	ys.resize(n)
	var win := 9
	for i in n:
		var acc := 0.0
		var cnt := 0
		for k in range(maxi(i - win, 0), mini(i + win, n - 1) + 1):
			acc += raw[k]
			cnt += 1
		ys[i] = acc / float(cnt)
	ys[0] = raw[0]
	var max_grade := float(cp.get("max_grade", 0.105))
	for i in range(1, n):
		var ds := pts[i].distance_to(pts[i - 1])
		ys[i] = clampf(ys[i], ys[i - 1] - max_grade * ds, ys[i - 1] + max_grade * ds)
	if not bool(cp.get("end_free", true)):
		ys[n - 1] = raw[n - 1]
		for i in range(n - 2, -1, -1):
			var ds2 := pts[i].distance_to(pts[i + 1])
			ys[i] = clampf(ys[i], ys[i + 1] - max_grade * ds2, ys[i + 1] + max_grade * ds2)
	cp["ys"] = ys
	# rasterise onto the grid: per cell keep the nearest path sample
	var half: float = cp["half"]
	var flat := half + 2.0
	var reach := flat + 9.0
	var best_d := {}
	var best_y := {}
	for i in n:
		var p := pts[i]
		var cx0 := int(floor((p.x - reach - X0) / CELL))
		var cx1 := int(ceil((p.x + reach - X0) / CELL))
		var cz0 := int(floor((p.y - reach - Z0) / CELL))
		var cz1 := int(ceil((p.y + reach - Z0) / CELL))
		for iz in range(maxi(cz0, 0), mini(cz1, NZ - 1) + 1):
			for ix in range(maxi(cx0, 0), mini(cx1, NX - 1) + 1):
				var gx := X0 + ix * CELL
				var gz := Z0 + iz * CELL
				var d := Vector2(gx, gz).distance_to(p)
				if d > reach:
					continue
				var key := iz * NX + ix
				if not best_d.has(key) or d < float(best_d[key]):
					best_d[key] = d
					best_y[key] = ys[i]
	for key in best_d:
		var d: float = best_d[key]
		var w := 1.0 - LayoutGeo.smoothstep(flat, reach, d)
		heights[key] = lerpf(heights[key], best_y[key], w)


# ---- queries ----------------------------------------------------------------------------------------------------
## Triangle-exact height (matches the mesh/collider split along the (ix+1,iz)-(ix,iz+1) diagonal).
static func height(x: float, z: float) -> float:
	if not baked:
		return natural_height(x, z)
	var fx := (x - X0) / CELL
	var fz := (z - Z0) / CELL
	if fx <= 0.0:
		fx = 0.0
	elif fx >= NX - 1.001:
		fx = NX - 1.001
	if fz <= 0.0:
		fz = 0.0
	elif fz >= NZ - 1.001:
		fz = NZ - 1.001
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - float(ix)
	var v := fz - float(iz)
	var i00 := iz * NX + ix
	var h00 := heights[i00]
	var h10 := heights[i00 + 1]
	var h01 := heights[i00 + NX]
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	var h11 := heights[i00 + NX + 1]
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


static func sample_idx(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, NZ - 1) * NX + clampi(ix, 0, NX - 1)]


## Surface normal estimate (central differences on the grid).
static func normal_at(x: float, z: float) -> Vector3:
	var e := 1.5
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()
