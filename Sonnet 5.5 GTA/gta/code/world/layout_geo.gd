class_name LayoutGeo
extends RefCounted
## 2D polyline / curve helpers for the layout generator (all coordinates are world x,z stored in Vector2 (x, y=z)).
## Convention: for a travel direction d, the RIGHT-hand side is right(d) = (-d.y, d.x) (x east, z south).


static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


static func poly_length(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i].distance_to(p[i - 1])
	return l


## Cumulative arc length per vertex.
static func cum_lengths(p: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(p.size())
	var l := 0.0
	for i in p.size():
		if i > 0:
			l += p[i].distance_to(p[i - 1])
		out[i] = l
	return out


## Position at arc length s (clamped).
static func point_at(p: PackedVector2Array, s: float, cum: PackedFloat32Array = PackedFloat32Array()) -> Vector2:
	if p.size() == 0:
		return Vector2.ZERO
	if p.size() == 1 or s <= 0.0:
		return p[0]
	var c := cum if cum.size() == p.size() else cum_lengths(p)
	if s >= c[c.size() - 1]:
		return p[p.size() - 1]
	var lo := 0
	var hi := p.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if c[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := c[hi] - c[lo]
	var t := 0.0 if seg < 0.0001 else (s - c[lo]) / seg
	return p[lo].lerp(p[hi], t)


## Forward tangent at arc length s.
static func dir_at(p: PackedVector2Array, s: float, cum: PackedFloat32Array = PackedFloat32Array()) -> Vector2:
	if p.size() < 2:
		return Vector2(0, -1)
	var c := cum if cum.size() == p.size() else cum_lengths(p)
	var lo := 0
	var hi := p.size() - 1
	if s >= c[c.size() - 1]:
		lo = p.size() - 2
	elif s > 0.0:
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if c[mid] <= s:
				lo = mid
			else:
				hi = mid
		hi = lo + 1
	else:
		lo = 0
	var d := p[lo + 1] - p[lo]
	if d.length_squared() < 0.000001:
		return Vector2(0, -1)
	return d.normalized()


## Smoothed tangent (average of neighbouring segments) - used for offsetting so corners do not kink.
static func dir_smooth(p: PackedVector2Array, s: float, cum: PackedFloat32Array) -> Vector2:
	var a := dir_at(p, maxf(s - 2.0, 0.0), cum)
	var b := dir_at(p, s + 2.0, cum)
	var d := a + b
	if d.length_squared() < 0.0001:
		return b
	return d.normalized()


## Sub-polyline between arc lengths s0..s1.
static func sub(p: PackedVector2Array, s0: float, s1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c := cum_lengths(p)
	var total: float = c[c.size() - 1]
	s0 = clampf(s0, 0.0, total)
	s1 = clampf(s1, 0.0, total)
	if s1 <= s0:
		return out
	out.append(point_at(p, s0, c))
	for i in p.size():
		if c[i] > s0 + 0.01 and c[i] < s1 - 0.01:
			out.append(p[i])
	out.append(point_at(p, s1, c))
	return out


## Offsets a polyline sideways (positive = right of the travel direction) with smoothed normals. Vertex count preserved.
static func offset(p: PackedVector2Array, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	out.resize(n)
	for i in n:
		var d: Vector2
		if i == 0:
			d = (p[1] - p[0])
		elif i == n - 1:
			d = (p[n - 1] - p[n - 2])
		else:
			var a := (p[i] - p[i - 1]).normalized()
			var b := (p[i + 1] - p[i]).normalized()
			d = a + b
			if d.length_squared() < 0.0001:
				d = b
		d = d.normalized()
		var r := right_of(d)
		# miter scale so the offset distance stays constant at corners (clamped)
		var scale := 1.0
		if i > 0 and i < n - 1:
			var a2 := (p[i] - p[i - 1]).normalized()
			var cosh := d.dot(a2)
			scale = 1.0 / maxf(cosh, 0.5)
		out[i] = p[i] + r * dist * scale
	return out


static func reversed(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	out.resize(n)
	for i in n:
		out[i] = p[n - 1 - i]
	return out


## Evenly spaced resample (keeps both end points; spacing <= step).
static func resample(p: PackedVector2Array, step: float) -> PackedVector2Array:
	var total := poly_length(p)
	var n := maxi(int(ceil(total / step)), 1)
	var c := cum_lengths(p)
	var out := PackedVector2Array()
	for i in n + 1:
		out.append(point_at(p, total * float(i) / float(n), c))
	return out


static func bezier2(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + c * (2.0 * u * t) + b * (t * t)


static func bezier3(a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + b * (t * t * t)


## Intersection of lines a0 + a_dir*t and b0 + b_dir*s. Returns Vector2(t, s) or Vector2(NAN, NAN) if parallel.
static func line_intersect(a0: Vector2, a_dir: Vector2, b0: Vector2, b_dir: Vector2) -> Vector2:
	var den := a_dir.x * b_dir.y - a_dir.y * b_dir.x
	if absf(den) < 0.00001:
		return Vector2(NAN, NAN)
	var diff := b0 - a0
	var t := (diff.x * b_dir.y - diff.y * b_dir.x) / den
	var s := (diff.x * a_dir.y - diff.y * a_dir.x) / den
	return Vector2(t, s)


## Rounded corner: replaces the corner `c` between segments p0->c->p1 with an arc of `radius` (tangent points included).
static func fillet(p0: Vector2, c: Vector2, p1: Vector2, radius: float, steps: int = 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d0 := (p0 - c).normalized()
	var d1 := (p1 - c).normalized()
	var ang := d0.angle_to(d1)
	var half := absf(ang) * 0.5
	if half < 0.02 or absf(PI - absf(ang)) < 0.02:
		out.append(c)
		return out
	var tdist := radius / tan(half)
	tdist = minf(tdist, minf(p0.distance_to(c), p1.distance_to(c)) * 0.95)
	var a := c + d0 * tdist
	var b := c + d1 * tdist
	for i in steps + 1:
		out.append(bezier2(a, c, b, float(i) / float(steps)))
	return out


## Builds a polyline through `pts` where every interior vertex flagged in `radii` (same size, 0 = sharp) is filleted.
static func rounded_path(pts: PackedVector2Array, radii: PackedFloat32Array, steps: int = 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var r := radii[i] if i < radii.size() else 0.0
		if i == 0 or i == pts.size() - 1 or r <= 0.01:
			out.append(pts[i])
		else:
			out.append_array(fillet(pts[i - 1], pts[i], pts[i + 1], r, steps))
	return out


## Nearest point on a polyline: returns {"dist", "s", "point", "dir"}.
static func nearest_on(p: PackedVector2Array, q: Vector2) -> Dictionary:
	var best := INF
	var best_s := 0.0
	var best_pt := Vector2.ZERO
	var best_dir := Vector2(0, -1)
	var run := 0.0
	for i in range(1, p.size()):
		var a := p[i - 1]
		var b := p[i]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.000001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		var pt := a + ab * t
		var d := pt.distance_squared_to(q)
		if d < best:
			best = d
			best_s = run + sqrt(l2) * t
			best_pt = pt
			best_dir = ab.normalized() if l2 > 0.000001 else best_dir
		run += sqrt(l2)
	return {"dist": sqrt(best), "s": best_s, "point": best_pt, "dir": best_dir}


static func to_v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Cheap deterministic value noise in [0,1] (hash based, bilinear + smooth).
static func hash2(ix: int, iz: int, seed_v: int = 0) -> float:
	var h := ix * 374761393 + iz * 668265263 + seed_v * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


static func vnoise(x: float, z: float, seed_v: int = 0) -> float:
	var ix := int(floor(x))
	var iz := int(floor(z))
	var fx := x - float(ix)
	var fz := z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := hash2(ix, iz, seed_v)
	var b := hash2(ix + 1, iz, seed_v)
	var c := hash2(ix, iz + 1, seed_v)
	var d := hash2(ix + 1, iz + 1, seed_v)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


static func rect_expand(r: Rect2, m: float) -> Rect2:
	return Rect2(r.position - Vector2(m, m), r.size + Vector2(m * 2.0, m * 2.0))
