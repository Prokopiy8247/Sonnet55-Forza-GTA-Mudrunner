class_name UIDraw
extends RefCounted
## Tiny immediate-mode drawing helpers used by every custom-drawn HUD widget (call from a Control's _draw()).

static var _sb := StyleBoxFlat.new()
static var _sb_ready := false


static func _prep() -> void:
	if not _sb_ready:
		_sb.anti_aliasing = true
		_sb.corner_detail = 8
		_sb_ready = true


## Anti-aliased rounded rectangle (optionally with a border).
static func rrect(ci: CanvasItem, rect: Rect2, color: Color, radius: float = 6.0, border_w: float = 0.0, border: Color = Color.WHITE) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_prep()
	_sb.bg_color = color
	_sb.set_corner_radius_all(int(minf(radius, minf(rect.size.x, rect.size.y) * 0.5)))
	_sb.set_border_width_all(int(border_w))
	_sb.border_color = border
	_sb.shadow_size = 0
	ci.draw_style_box(_sb, rect)


## Annulus sector polygon (angles in radians, 0 = +X, clockwise on screen).
static func sector(ci: CanvasItem, center: Vector2, r_in: float, r_out: float, a0: float, a1: float, color: Color, steps: int = 0) -> void:
	var pts := sector_points(center, r_in, r_out, a0, a1, steps)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, color)


static func sector_points(center: Vector2, r_in: float, r_out: float, a0: float, a1: float, steps: int = 0) -> PackedVector2Array:
	var n := steps if steps > 0 else maxi(4, int(absf(a1 - a0) / 0.08))
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(center + Vector2(cos(a), sin(a)) * r_out)
	for i in n + 1:
		var a2 := lerpf(a1, a0, float(i) / n)
		pts.append(center + Vector2(cos(a2), sin(a2)) * r_in)
	return pts


static func star_points(center: Vector2, r_out: float, r_in: float = -1.0, rot: float = -PI * 0.5) -> PackedVector2Array:
	var ri := r_in if r_in > 0.0 else r_out * 0.45
	var pts := PackedVector2Array()
	for i in 10:
		var a := rot + float(i) * PI / 5.0
		var r := r_out if i % 2 == 0 else ri
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


static func star(ci: CanvasItem, center: Vector2, r_out: float, color: Color, outline: Color = Color(0, 0, 0, 0), outline_w: float = 0.0) -> void:
	var pts := star_points(center, r_out)
	ci.draw_colored_polygon(pts, color)
	if outline_w > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, outline, outline_w, true)


static func text(ci: CanvasItem, font: Font, s: String, pos: Vector2, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(font, pos, s, align, width, size, color)


## Draws `s` centred on `center` (both axes).
static func text_center(ci: CanvasItem, font: Font, s: String, center: Vector2, size: int, color: Color) -> void:
	var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	ci.draw_string(font, Vector2(center.x - sz.x * 0.5, center.y + (asc - desc) * 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


## Soft drop shadow text (draws a dark copy first).
static func text_shadow(ci: CanvasItem, font: Font, s: String, pos: Vector2, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(font, pos + Vector2(1.5, 2.0), s, align, width, size, Color(0, 0, 0, color.a * 0.6))
	ci.draw_string(font, pos, s, align, width, size, color)


static func triangle(ci: CanvasItem, center: Vector2, size: float, angle: float, color: Color) -> void:
	# points up at angle 0
	var f := Vector2(sin(angle), -cos(angle))
	var r := Vector2(cos(angle), sin(angle))
	var pts := PackedVector2Array([center + f * size, center - f * size * 0.7 + r * size * 0.75, center - f * size * 0.35, center - f * size * 0.7 - r * size * 0.75])
	ci.draw_colored_polygon(pts, color)


## Smoothstep-style ease helpers
static func ease_out(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u
