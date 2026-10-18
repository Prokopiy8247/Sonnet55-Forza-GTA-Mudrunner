class_name PierBuilder
extends RefCounted
## Harbour structures: concrete quay rim (vertical wall into the sea so the 3 m terrain cell does not look like a ramp), plank
## piers on piles, beach pier. All decks are collidable (surface "wood" / "concrete").

const QUAY_Z := 192.0
const QUAY_FRONT := 194.9


static func build(rb: RoadBuilder) -> void:
	var piers: Array = WorldLayout.piers
	# --- piers: deck + side skirts + piles
	for p in piers:
		var r: Rect2 = p["rect"]
		var h: float = float(p["height"])
		var top := h + 0.03
		var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		rb.add_poly("planks", poly, 0.0, Color(0, 0.5, 0, 1), top)
		# skirts (0.45 m) on the three water sides
		var y0 := top - 0.45
		rb.wall("planks", Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), y0, top, Vector3(0, 0, 1))
		rb.wall("planks", Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), y0, top, Vector3(1, 0, 0))
		rb.wall("planks", Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), y0, top, Vector3(-1, 0, 0))
		# piles every 5 m along both long edges, down to the sea bed
		var long_z := r.size.y >= r.size.x
		var steps := int(max(r.size.y if long_z else r.size.x, 1.0) / 5.0)
		for i in steps + 1:
			var t := float(i) / float(max(steps, 1))
			var sides: Array = [0.35, 0.65] if (r.size.x > 6.0 or r.size.y > 6.0) else [0.5]
			for side in sides:
				var px: float
				var pz: float
				if long_z:
					px = r.position.x + 0.5 + (r.size.x - 1.0) * (0.0 if side < 0.5 else 1.0)
					pz = r.position.y + r.size.y * t
				else:
					px = r.position.x + r.size.x * t
					pz = r.position.y + 0.5 + (r.size.y - 1.0) * (0.0 if side < 0.5 else 1.0)
				_pile(rb, Vector2(px, pz), y0)
	# --- quay rim
	var gaps: Array = []
	for p in piers:
		var r2: Rect2 = p["rect"]
		if absf(r2.position.y - QUAY_Z) < 0.5:
			gaps.append(Vector2(r2.position.x - 0.1, r2.end.x + 0.1))
	gaps.sort_custom(func(a, b): return a.x < b.x)
	_rim_segments(rb, -300.0, -104.0, gaps)
	_rim_segments(rb, 78.0, 300.0, gaps)


static func _rim_segments(rb: RoadBuilder, x0: float, x1: float, gaps: Array) -> void:
	var cur := x0
	for g in gaps:
		var gv: Vector2 = g
		if gv.y < x0 or gv.x > x1:
			continue
		if gv.x > cur:
			_rim(rb, cur, gv.x)
		cur = maxf(cur, gv.y)
	if cur < x1:
		_rim(rb, cur, x1)


static func _rim(rb: RoadBuilder, xa: float, xb: float) -> void:
	# top cap (walkable), front wall facing the sea
	var steps := maxi(int(ceil((xb - xa) / 20.0)), 1)
	for i in steps:
		var a := lerpf(xa, xb, float(i) / float(steps))
		var b := lerpf(xa, xb, float(i + 1) / float(steps))
		rb.quad("apron", Vector3(a, 0.015, QUAY_Z), Vector3(b, 0.015, QUAY_Z), Vector3(b, 0.015, QUAY_FRONT), Vector3(a, 0.015, QUAY_FRONT),
			Vector2(a, QUAY_Z), Vector2(b, QUAY_Z), Vector2(b, QUAY_FRONT), Vector2(a, QUAY_FRONT), Color(0, 0.5, 0, 1))
		rb.wall("curb", Vector2(a, QUAY_FRONT), Vector2(b, QUAY_FRONT), -4.3, 0.015, Vector3(0, 0, 1))


static func _pile(rb: RoadBuilder, c: Vector2, top_y: float) -> void:
	var bottom := LayoutTerrain.height(c.x, c.y) - 0.3
	if bottom > top_y - 0.5:
		return
	var s := 0.17
	var corners := [Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)]
	var normals := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for i in 4:
		var p0: Vector2 = c + corners[i]
		var p1: Vector2 = c + corners[(i + 1) % 4]
		rb.wall("planks", p0, p1, bottom, top_y, normals[i])
