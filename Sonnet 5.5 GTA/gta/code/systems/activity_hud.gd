class_name ActivityHud
extends Control
## Reusable activity HUD widget (custom drawn like the rest of the UI): a stat strip at the top centre (timer, score, checkpoint counter,
## any "label / value" cells), a big countdown, a banner line, floating score popups and the results card with the medal.
## Owned by ActivitySystem (own CanvasLayer); every activity only talks to the ActivitySystem helpers / this API:
##   begin(title, subtitle, accent) / finish_activity()        show / hide the stat strip
##   set_cells([{label, value, color}])  or  set_cell(i, label, value, color)
##   banner(text, seconds, color)       transient line under the strip ("ROUND 2", "RETURN TO THE ROUTE")
##   countdown(text)                    big centre text with a pop animation ("3", "2", "1", "GO")
##   popup(text, color, pos)            floating "+100" that rises and fades (pos = screen position, default = crosshair)
##   show_results(dict) / hide_results()  the medal card (see _draw_results for the dictionary)
##   set_progress(0..1, color)          thin progress bar under the strip (round time, route progress)

const COL_GOLD := Color("#ffd35a")
const COL_SILVER := Color("#d5dde6")
const COL_BRONZE := Color("#d98c4a")
const STRIP_Y := 112.0
const CELL_W := 188.0
const CELL_H := 78.0

var active := false
var title := ""
var subtitle := ""
var accent: Color = GC.COL_ACCENT
var cells: Array = []
var progress := -1.0
var progress_color: Color = GC.COL_ACCENT

var _banner_text := ""
var _banner_t := 99.0
var _banner_life := 2.0
var _banner_col: Color = GC.COL_TEXT
var _count_text := ""
var _count_t := 99.0
var _pops: Array = []
var _results: Dictionary = {}
var _results_t := -1.0
var _t := 0.0
var _strip_alpha := 0.0


func _init() -> void:
	name = "ActivityHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true


# ---- API -----------------------------------------------------------------------------------------------------------------
func begin(t: String, sub: String = "", col: Color = GC.COL_ACCENT) -> void:
	active = true
	title = t
	subtitle = sub
	accent = col
	cells = []
	progress = -1.0
	_pops.clear()
	queue_redraw()


func finish_activity() -> void:
	active = false
	cells = []
	progress = -1.0
	_count_t = 99.0
	_banner_t = 99.0
	queue_redraw()


func set_cells(arr: Array) -> void:
	cells = arr


func set_cell(i: int, label: String, value: String, col: Color = GC.COL_TEXT) -> void:
	while cells.size() <= i:
		cells.append({"label": "", "value": "", "color": GC.COL_TEXT})
	var c: Dictionary = cells[i]
	c["label"] = label
	c["value"] = value
	c["color"] = col


func set_progress(v: float, col: Color = GC.COL_ACCENT) -> void:
	progress = v
	progress_color = col


func banner(text: String, seconds: float = 2.0, col: Color = GC.COL_TEXT) -> void:
	_banner_text = text
	_banner_t = 0.0
	_banner_life = maxf(seconds, 0.4)
	_banner_col = col


func countdown(text: String) -> void:
	_count_text = text
	_count_t = 0.0


func popup(text: String, col: Color = GC.COL_OK, pos: Vector2 = Vector2(-1, -1), size_px: int = 34) -> void:
	var p := pos
	if p.x < 0.0:
		p = size * 0.5 + Vector2(randf_range(-40.0, 40.0), -70.0)
	_pops.append({"text": text, "pos": p, "age": 0.0, "life": 1.15, "color": col, "size": size_px})
	if _pops.size() > 10:
		_pops.pop_front()


func show_results(d: Dictionary) -> void:
	_results = d
	_results_t = 0.0
	queue_redraw()


func hide_results() -> void:
	_results = {}
	_results_t = -1.0
	queue_redraw()


func has_results() -> bool:
	return _results_t >= 0.0


func medal_color(medal: String) -> Color:
	match medal:
		"gold":
			return COL_GOLD
		"silver":
			return COL_SILVER
		"bronze":
			return COL_BRONZE
	return GC.COL_TEXT_DIM


static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out


static func format_time(seconds: float, with_tenths: bool = true) -> String:
	var s := maxf(seconds, 0.0)
	var m := int(s / 60.0)
	var rest := s - float(m) * 60.0
	if with_tenths:
		return "%d:%04.1f" % [m, rest]
	return "%d:%02d" % [m, int(rest)]


# ---- frame ---------------------------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.05)
	_t += dt
	var want := 1.0 if active else 0.0
	_strip_alpha = move_toward(_strip_alpha, want, dt * 5.0)
	if _banner_t < 90.0:
		_banner_t += dt
		if _banner_t > _banner_life:
			_banner_t = 99.0
	if _count_t < 90.0:
		_count_t += dt
		if _count_t > 1.1:
			_count_t = 99.0
	var i := 0
	while i < _pops.size():
		var p: Dictionary = _pops[i]
		p["age"] = float(p["age"]) + dt
		if float(p["age"]) >= float(p["life"]):
			_pops.remove_at(i)
		else:
			i += 1
	if _results_t >= 0.0:
		_results_t += dt
	if _strip_alpha > 0.01 or _banner_t < 90.0 or _count_t < 90.0 or not _pops.is_empty() or _results_t >= 0.0:
		queue_redraw()


func _draw() -> void:
	var f := UITheme.font(false)
	var fb := UITheme.font(true)
	var fd := UITheme.font_display()
	var cx := size.x * 0.5
	if _strip_alpha > 0.01:
		_draw_strip(f, fb, fd, cx)
	if _banner_t < 90.0:
		var a := 1.0
		if _banner_t < 0.18:
			a = _banner_t / 0.18
		elif _banner_t > _banner_life - 0.4:
			a = clampf((_banner_life - _banner_t) / 0.4, 0.0, 1.0)
		var y := STRIP_Y + CELL_H + 54.0 + (1.0 - UIDraw.ease_out(_banner_t / 0.25)) * -14.0
		var sz := fb.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36)
		UIDraw.rrect(self, Rect2(cx - sz.x * 0.5 - 24.0, y - 38.0, sz.x + 48.0, 54.0), Color(0.03, 0.04, 0.06, 0.72 * a), 14.0)
		UIDraw.text_shadow(self, fb, _banner_text, Vector2(cx - sz.x * 0.5, y), 36, Color(_banner_col.r, _banner_col.g, _banner_col.b, a))
	if _count_t < 90.0:
		_draw_countdown(fd, cx)
	for p in _pops:
		var k := float(p["age"]) / float(p["life"])
		var pos: Vector2 = p["pos"]
		pos.y -= UIDraw.ease_out(k) * 70.0
		var col: Color = p["color"]
		col.a = 1.0 - smoothstep(0.55, 1.0, k)
		var psz: int = int(p["size"])
		var s2 := fd.get_string_size(String(p["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, psz)
		UIDraw.text_shadow(self, fd, String(p["text"]), Vector2(pos.x - s2.x * 0.5, pos.y), psz, col)
	if _results_t >= 0.0:
		_draw_results(f, fb, fd)


func _draw_strip(f: Font, fb: Font, fd: Font, cx: float) -> void:
	var n := maxi(cells.size(), 1)
	var w := CELL_W * float(n) + 28.0
	var x0 := cx - w * 0.5
	var a := _strip_alpha
	var y0 := STRIP_Y - 38.0 + (1.0 - a) * -18.0
	UIDraw.rrect(self, Rect2(x0, y0, w, CELL_H + 40.0), Color(0.043, 0.059, 0.086, 0.82 * a), 16.0, 1.5, Color(accent.r, accent.g, accent.b, 0.55 * a))
	# header: title + subtitle
	UIDraw.text(self, fb, title.to_upper(), Vector2(x0 + 18.0, y0 + 25.0), 18, Color(accent.r, accent.g, accent.b, a))
	if subtitle != "":
		UIDraw.text(self, f, subtitle, Vector2(x0 + w - 18.0 - 460.0, y0 + 25.0), 16, Color(GC.COL_TEXT_DIM.r, GC.COL_TEXT_DIM.g, GC.COL_TEXT_DIM.b, a), HORIZONTAL_ALIGNMENT_RIGHT, 460.0)
	for i in cells.size():
		var c: Dictionary = cells[i]
		var cell_x := x0 + 14.0 + CELL_W * float(i)
		var col: Color = c.get("color", GC.COL_TEXT)
		col.a = a
		var dim := GC.COL_TEXT_DIM
		dim.a = a
		UIDraw.text(self, f, String(c.get("label", "")).to_upper(), Vector2(cell_x + 6.0, y0 + 52.0), 14, dim)
		UIDraw.text(self, fd, String(c.get("value", "")), Vector2(cell_x + 6.0, y0 + 90.0), 38, col)
		if i > 0:
			draw_line(Vector2(cell_x - 2.0, y0 + 40.0), Vector2(cell_x - 2.0, y0 + 98.0), Color(1, 1, 1, 0.10 * a), 1.5)
	if progress >= 0.0:
		var bw := w - 36.0
		UIDraw.rrect(self, Rect2(x0 + 18.0, y0 + CELL_H + 40.0 - 14.0, bw, 5.0), Color(1, 1, 1, 0.10 * a), 2.5)
		UIDraw.rrect(self, Rect2(x0 + 18.0, y0 + CELL_H + 40.0 - 14.0, bw * clampf(progress, 0.0, 1.0), 5.0), Color(progress_color.r, progress_color.g, progress_color.b, 0.95 * a), 2.5)


func _draw_countdown(fd: Font, cx: float) -> void:
	var k := _count_t / 1.1
	var pop := 1.0 + 0.55 * (1.0 - UIDraw.ease_out(minf(_count_t / 0.22, 1.0)))
	var a := 1.0 - smoothstep(0.6, 1.0, k)
	var go := _count_text.begins_with("GO")
	var col := GC.COL_OK if go else GC.COL_ACCENT
	col.a = a
	var sz := int((140.0 if not go else 150.0) * pop)
	var cy := size.y * 0.30
	var ss := fd.get_string_size(_count_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz)
	# glow ring behind the number
	draw_arc(Vector2(cx, cy), 112.0 * pop, 0.0, TAU, 56, Color(col.r, col.g, col.b, 0.35 * a), 6.0, true)
	UIDraw.text_shadow(self, fd, _count_text, Vector2(cx - ss.x * 0.5, cy + ss.y * 0.30), sz, col)


func _draw_results(f: Font, fb: Font, fd: Font) -> void:
	var d := _results
	var rows: Array = d.get("rows", [])
	var medal := String(d.get("medal", "none"))
	var mcol := medal_color(medal)
	var k := UIDraw.ease_out(_results_t / 0.35)
	var w := 700.0
	var h := 250.0 + 40.0 * float(rows.size())
	var x0 := size.x * 0.5 - w * 0.5
	var y0 := size.y * 0.5 - h * 0.5 - 20.0 + (1.0 - k) * 30.0
	UIDraw.rrect(self, Rect2(x0 - 6.0, y0 - 6.0, w + 12.0, h + 12.0), Color(0, 0, 0, 0.35 * k), 24.0)
	UIDraw.rrect(self, Rect2(x0, y0, w, h), Color(0.043, 0.059, 0.086, 0.94 * k), 20.0, 2.0, Color(mcol.r, mcol.g, mcol.b, 0.8 * k))
	# medal disc
	var mc := Vector2(x0 + 96.0, y0 + 112.0)
	draw_circle(mc, 58.0, Color(0, 0, 0, 0.45 * k))
	draw_circle(mc, 52.0, Color(mcol.r, mcol.g, mcol.b, k))
	draw_arc(mc, 42.0, 0.0, TAU, 48, Color(1, 1, 1, 0.55 * k), 3.0, true)
	var star_col := Color(0.12, 0.10, 0.06, k) if medal != "none" else Color(0.05, 0.07, 0.1, k)
	if medal != "none":
		UIDraw.star(self, mc, 30.0, star_col)
	else:
		UIDraw.text_center(self, fb, "-", mc, 44, star_col)
	var label := medal.to_upper() if medal != "none" else "COMPLETE"
	UIDraw.text_center(self, fb, label, mc + Vector2(0, 76.0), 20, Color(mcol.r, mcol.g, mcol.b, k))
	# header
	var tx := x0 + 190.0
	UIDraw.text(self, fb, String(d.get("title", "ACTIVITY")).to_upper(), Vector2(tx, y0 + 48.0), 26, Color(GC.COL_ACCENT.r, GC.COL_ACCENT.g, GC.COL_ACCENT.b, k))
	UIDraw.text(self, f, String(d.get("subtitle", "")), Vector2(tx, y0 + 76.0), 18, Color(GC.COL_TEXT_DIM.r, GC.COL_TEXT_DIM.g, GC.COL_TEXT_DIM.b, k))
	UIDraw.text(self, fd, String(d.get("main", "")), Vector2(tx, y0 + 140.0), 58, Color(1, 1, 1, k))
	if bool(d.get("new_best", false)):
		var nb := "NEW BEST"
		var nsz := fb.get_string_size(nb, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17)
		var nx := x0 + w - 28.0 - nsz.x - 20.0
		UIDraw.rrect(self, Rect2(nx, y0 + 24.0, nsz.x + 20.0, 30.0), Color(GC.COL_ACCENT2.r, GC.COL_ACCENT2.g, GC.COL_ACCENT2.b, 0.95 * k), 15.0)
		UIDraw.text(self, fb, nb, Vector2(nx + 10.0, y0 + 45.0), 17, Color(1, 1, 1, k))
	var ry := y0 + 182.0
	for r in rows:
		var rr: Array = r
		draw_line(Vector2(x0 + 28.0, ry - 22.0), Vector2(x0 + w - 28.0, ry - 22.0), Color(1, 1, 1, 0.07 * k), 1.0)
		UIDraw.text(self, f, String(rr[0]), Vector2(x0 + 36.0, ry), 21, Color(GC.COL_TEXT_DIM.r, GC.COL_TEXT_DIM.g, GC.COL_TEXT_DIM.b, k))
		var vcol: Color = rr[2] if rr.size() > 2 else GC.COL_TEXT
		vcol.a = k
		UIDraw.text(self, fb, String(rr[1]), Vector2(x0 + w - 36.0 - 360.0, ry), 21, vcol, HORIZONTAL_ALIGNMENT_RIGHT, 360.0)
		ry += 40.0
	var cash := int(d.get("cash", 0))
	var foot := ""
	if cash > 0:
		foot = "+" + Util.format_money(cash)
	var skill_txt := String(d.get("skill", ""))
	if skill_txt != "":
		foot += ("   " if foot != "" else "") + skill_txt
	if foot != "":
		UIDraw.text(self, fb, foot, Vector2(x0 + 36.0, y0 + h - 22.0), 22, Color(GC.COL_OK.r, GC.COL_OK.g, GC.COL_OK.b, k))
	UIDraw.text(self, f, String(d.get("hint", "")), Vector2(x0 + w - 36.0 - 360.0, y0 + h - 22.0), 16, Color(GC.COL_TEXT_DIM.r, GC.COL_TEXT_DIM.g, GC.COL_TEXT_DIM.b, k), HORIZONTAL_ALIGNMENT_RIGHT, 360.0)
