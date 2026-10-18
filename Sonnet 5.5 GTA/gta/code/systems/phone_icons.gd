class_name PhoneIcons
extends RefCounted
## Vector glyphs for the phone app tiles (drawn with canvas primitives, no image assets).


static func draw(ci: CanvasItem, id: StringName, rect: Rect2, col: Color) -> void:
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) * 0.5
	var lw := maxf(s * 0.12, 2.0)
	match id:
		&"services":
			ci.draw_circle(c + Vector2(0, -s * 0.28), s * 0.26, col)
			ci.draw_arc(c + Vector2(0, s * 0.62), s * 0.52, PI * 1.08, PI * 1.92, 16, col, lw * 1.6)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.52, s * 0.55), Vector2(s * 1.04, lw)), col)
		&"vehicles":
			var body := Rect2(c + Vector2(-s * 0.8, -s * 0.05), Vector2(s * 1.6, s * 0.5))
			ci.draw_rect(body, col)
			var roof := PackedVector2Array([c + Vector2(-s * 0.45, -s * 0.05), c + Vector2(-s * 0.25, -s * 0.5), c + Vector2(s * 0.3, -s * 0.5), c + Vector2(s * 0.55, -s * 0.05)])
			ci.draw_colored_polygon(roof, col)
			ci.draw_circle(c + Vector2(-s * 0.45, s * 0.46), s * 0.2, Color(0.05, 0.07, 0.1))
			ci.draw_circle(c + Vector2(s * 0.45, s * 0.46), s * 0.2, Color(0.05, 0.07, 0.1))
			ci.draw_arc(c + Vector2(-s * 0.45, s * 0.46), s * 0.2, 0, TAU, 12, col, lw)
			ci.draw_arc(c + Vector2(s * 0.45, s * 0.46), s * 0.2, 0, TAU, 12, col, lw)
		&"camera":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.4), Vector2(s * 1.6, s * 1.05)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.62), Vector2(s * 0.6, s * 0.25)), col)
			ci.draw_circle(c + Vector2(0, s * 0.12), s * 0.38, Color(0.05, 0.07, 0.1))
			ci.draw_arc(c + Vector2(0, s * 0.12), s * 0.38, 0, TAU, 20, Color(1, 1, 1, 0.9), lw)
			ci.draw_circle(c + Vector2(0, s * 0.12), s * 0.15, Color(1, 1, 1, 0.9))
		&"map":
			var pts := PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.55), c + Vector2(-s * 0.27, -s * 0.4), c + Vector2(s * 0.27, -s * 0.6), c + Vector2(s * 0.8, -s * 0.42),
				c + Vector2(s * 0.8, s * 0.6), c + Vector2(s * 0.27, s * 0.42), c + Vector2(-s * 0.27, s * 0.62), c + Vector2(-s * 0.8, s * 0.44)])
			ci.draw_colored_polygon(pts, col)
			ci.draw_line(c + Vector2(-s * 0.27, -s * 0.4), c + Vector2(-s * 0.27, s * 0.62), Color(0.05, 0.07, 0.1, 0.8), lw * 0.7)
			ci.draw_line(c + Vector2(s * 0.27, -s * 0.6), c + Vector2(s * 0.27, s * 0.42), Color(0.05, 0.07, 0.1, 0.8), lw * 0.7)
			ci.draw_circle(c + Vector2(s * 0.05, -s * 0.05), s * 0.2, Color(1.0, 0.25, 0.55))
		&"save":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.7), Vector2(s * 1.4, s * 1.4)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, -s * 0.7), Vector2(s * 0.8, s * 0.5)), Color(0.05, 0.07, 0.1))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.45, s * 0.1), Vector2(s * 0.9, s * 0.6)), Color(0.05, 0.07, 0.1))
			ci.draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.62), Vector2(s * 0.18, s * 0.34)), col)
		&"radio":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.25), Vector2(s * 1.6, s * 0.95)), col)
			ci.draw_line(c + Vector2(s * 0.3, -s * 0.25), c + Vector2(s * 0.7, -s * 0.8), col, lw)
			ci.draw_circle(c + Vector2(-s * 0.4, s * 0.22), s * 0.27, Color(0.05, 0.07, 0.1))
			ci.draw_circle(c + Vector2(-s * 0.4, s * 0.22), s * 0.08, Color(1, 1, 1, 0.9))
			for i in 4:
				ci.draw_rect(Rect2(c + Vector2(s * 0.05 + float(i) * s * 0.2, s * 0.05 + (i % 2) * s * 0.08), Vector2(s * 0.1, s * 0.34)), Color(0.05, 0.07, 0.1))
		&"settings":
			ci.draw_circle(c, s * 0.5, col)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * s * 0.5, c + d * s * 0.78, col, lw * 1.8)
			ci.draw_circle(c, s * 0.22, Color(0.05, 0.07, 0.1))
		&"stats":
			var base := c.y + s * 0.65
			var hs := [0.45, 0.9, 0.65, 1.2]
			for i in 4:
				var h: float = float(hs[i]) * s * 0.9
				ci.draw_rect(Rect2(Vector2(c.x - s * 0.75 + float(i) * s * 0.42, base - h), Vector2(s * 0.3, h)), col)
		_:
			ci.draw_circle(c, s * 0.6, col)
