class_name AirportBuilder
extends RefCounted
## Airfield surfaces: 220 m runway (centre dashes, threshold bars, touchdown marks, edge lines), parallel taxiway with two links,
## concrete apron, helipad disc. Geometry comes from LayoutPlaces / WorldLayout.airport; hangars + tower are lots (World-Content).


static func build(rb: RoadBuilder) -> void:
	var a: Dictionary = WorldLayout.airport
	if a.is_empty():
		return
	var rs: Vector3 = a["runway_start"]
	var re: Vector3 = a["runway_end"]
	var rw: float = a["runway_width"]
	# runway (v = metres from the start, lateral u = metres from the centre line)
	rb.add_strip("runway", PackedVector2Array([Vector2(rs.x, rs.z), Vector2(re.x, re.z)]), rw * 0.5, 0.03, 0.0, Color(0, 0.5, 0, 1), 10.0)
	# taxiway + links
	var tw: float = a.get("taxiway_width", 12.0)
	var taxi: Array = a["taxiway"]
	var t0: Vector3 = taxi[0]
	var t1: Vector3 = taxi[taxi.size() - 1]
	rb.add_strip("taxiway", PackedVector2Array([Vector2(t0.x, t0.z), Vector2(t1.x, t1.z)]), tw * 0.5, 0.03, 0.0, Color(0, 0.5, 0, 1), 10.0)
	for l in a.get("taxi_links", []):
		var lp: Vector2 = l
		rb.add_strip("taxiway", PackedVector2Array([Vector2(lp.x, lp.y - tw * 0.5), Vector2(lp.x, rs.z - rw * 0.5 + 0.1)]), tw * 0.5, 0.03, 0.0, Color(0, 0.5, 0, 1), 6.0)
	# apron
	var ap: Rect2 = a["apron"]
	rb.add_poly("apron", PackedVector2Array([ap.position, Vector2(ap.end.x, ap.position.y), ap.end, Vector2(ap.position.x, ap.end.y)]), 0.03)
	# hangar / terminal forecourt strip between apron and buildings
	var fc := Rect2(126.0, 106.0, 162.0, 5.0)
	rb.add_poly("apron", PackedVector2Array([fc.position, Vector2(fc.end.x, fc.position.y), fc.end, Vector2(fc.position.x, fc.end.y)]), 0.03)
	# helipad disc (airport)
	var hp := WorldLayout.get_location(&"helipad_airport")
	if not hp.is_empty():
		_disc(rb, Vector2(hp["pos"].x, hp["pos"].z), 10.0, 0.04)


static func _disc(rb: RoadBuilder, c: Vector2, r: float, dy: float) -> void:
	var y := LayoutTerrain.height(c.x, c.y) + dy
	var n := 28
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		rb.tri("helipad", Vector3(c.x, y, c.y), Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector2.ZERO, p0 - c, p1 - c, Color(0, 0.5, 0, 1))
