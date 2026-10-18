class_name Notifications
extends Control
## Toast stack (top-left, slide in / fade out, queued) + subtitle line (bottom centre). Custom-drawn: no node churn.
## Fed by Events.notification / Events.subtitle (wired by UIRoot) or directly via push_toast / push_subtitle.

const MAX_VISIBLE := 5
const TOAST_W := 560.0
const TOAST_LIFE := 4.2
const KIND_COLORS := {&"info": UITheme.C_ACCENT, &"good": UITheme.C_OK, &"warn": UITheme.C_WARN, &"bad": UITheme.C_DANGER}

var top_offset := 0.0                 # extra Y offset (HUD pushes it down when the FPS overlay is shown)
var _toasts: Array[Dictionary] = []   # {text, kind, age, life, y, target_y, h, count}
var _pending: Array[Dictionary] = []
var _subs: Array[Dictionary] = []     # {text, age, life}
var _last_sound_ms := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func push_toast(text: String, kind: StringName = &"info", seconds: float = TOAST_LIFE) -> void:
	if text.strip_edges() == "":
		return
	for t in _toasts:
		if t["text"] == text and t["kind"] == kind and float(t["age"]) < float(t["life"]) - 0.5:
			t["age"] = 0.0
			t["count"] = int(t["count"]) + 1
			set_process(true)
			return
	var entry := {"text": text, "kind": kind, "age": 0.0, "life": seconds, "y": -60.0, "target_y": 0.0, "h": 0.0, "count": 1}
	if _toasts.size() >= MAX_VISIBLE:
		_pending.append(entry)
	else:
		_add_toast(entry)
	set_process(true)


func _add_toast(entry: Dictionary) -> void:
	var f := UITheme.font(false)
	var lines := f.get_multiline_string_size(entry["text"], HORIZONTAL_ALIGNMENT_LEFT, TOAST_W - 74.0, 21)
	entry["h"] = maxf(50.0, lines.y + 22.0)
	_toasts.append(entry)
	if Sfx != null:
		var now := Time.get_ticks_msec()
		if now - _last_sound_ms > 120:
			_last_sound_ms = now
			Sfx.play_ui(&"ui_error" if entry["kind"] == &"bad" else &"ui_notify")


func push_subtitle(text: String, seconds: float = 3.0) -> void:
	if text.strip_edges() == "":
		return
	_subs.append({"text": text, "age": 0.0, "life": maxf(seconds, 0.8)})
	if _subs.size() > 3:
		_subs.pop_front()
	set_process(true)


func clear() -> void:
	_toasts.clear()
	_pending.clear()
	_subs.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _toasts.is_empty() and _subs.is_empty() and _pending.is_empty():
		set_process(false)
		queue_redraw()
		return
	delta = delta / maxf(Engine.time_scale, 0.05)     # keep UI animations on real time during slow-mo
	var y := UITheme.SAFE_Y + top_offset
	var i := 0
	while i < _toasts.size():
		var t: Dictionary = _toasts[i]
		t["age"] = float(t["age"]) + delta
		if float(t["age"]) >= float(t["life"]):
			_toasts.remove_at(i)
			continue
		t["target_y"] = y
		if float(t["y"]) < -50.0:
			t["y"] = y          # spawn in place, slide horizontally
		t["y"] = lerpf(float(t["y"]), y, 1.0 - exp(-14.0 * delta))
		y += float(t["h"]) + 8.0
		i += 1
	while _toasts.size() < MAX_VISIBLE and not _pending.is_empty():
		_add_toast(_pending.pop_front())
	var j := 0
	while j < _subs.size():
		_subs[j]["age"] = float(_subs[j]["age"]) + delta
		if float(_subs[j]["age"]) >= float(_subs[j]["life"]):
			_subs.remove_at(j)
			continue
		j += 1
	queue_redraw()


func _draw() -> void:
	var f := UITheme.font(false)
	var fb := UITheme.font(true)
	for t in _toasts:
		var age: float = t["age"]
		var life: float = t["life"]
		var slide := UIDraw.ease_out(age / 0.3)
		var fade := clampf((life - age) / 0.45, 0.0, 1.0)
		var a := minf(slide * 1.4, 1.0) * fade
		var col: Color = KIND_COLORS.get(t["kind"], UITheme.C_ACCENT)
		var h: float = t["h"]
		var x := UITheme.SAFE_X - (1.0 - slide) * (TOAST_W + 40.0)
		var r := Rect2(x, float(t["y"]), TOAST_W, h)
		UIDraw.rrect(self, r.grow(2.0), Color(0, 0, 0, 0.25 * a), 14)
		UIDraw.rrect(self, r, Color(0.045, 0.06, 0.09, 0.9 * a), 12, 1, Color(1, 1, 1, 0.09 * a))
		UIDraw.rrect(self, Rect2(r.position.x, r.position.y + 6, 5, h - 12), Color(col.r, col.g, col.b, a), 3)
		_draw_kind_icon(Vector2(r.position.x + 32, r.position.y + h * 0.5), t["kind"], Color(col.r, col.g, col.b, a))
		var txt: String = t["text"]
		if int(t["count"]) > 1:
			txt += "  x%d" % int(t["count"])
		draw_multiline_string(f, Vector2(r.position.x + 58, r.position.y + 11 + f.get_ascent(21)), txt, HORIZONTAL_ALIGNMENT_LEFT, TOAST_W - 74.0, 21, -1, Color(0.93, 0.96, 0.98, a))
	# subtitles
	var vp := size
	var sy := vp.y - UITheme.SAFE_Y - 120.0
	for k in range(_subs.size() - 1, -1, -1):
		var s: Dictionary = _subs[k]
		var age2: float = s["age"]
		var life2: float = s["life"]
		var a2 := clampf(age2 / 0.2, 0.0, 1.0) * clampf((life2 - age2) / 0.4, 0.0, 1.0)
		var tw := minf(fb.get_string_size(s["text"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26).x, 1240.0)
		var rr := Rect2((vp.x - tw) * 0.5 - 26.0, sy - 38.0, tw + 52.0, 54.0)
		UIDraw.rrect(self, rr, Color(0.02, 0.03, 0.05, 0.78 * a2), 14)
		draw_string(fb, Vector2((vp.x - tw) * 0.5, sy), s["text"], HORIZONTAL_ALIGNMENT_LEFT, 1240.0, 26, Color(1, 1, 1, a2))
		sy -= 66.0


func _draw_kind_icon(c: Vector2, kind: StringName, col: Color) -> void:
	draw_circle(c, 14.0, Color(col.r, col.g, col.b, col.a * 0.2))
	match kind:
		&"good":
			draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(-2, 5), c + Vector2(7, -5)]), col, 2.6, true)
		&"warn":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(8, 6), c + Vector2(-8, 6)]), col)
		&"bad":
			draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), col, 2.8, true)
			draw_line(c + Vector2(5, -5), c + Vector2(-5, 5), col, 2.8, true)
		_:
			draw_circle(c + Vector2(0, -6), 1.8, col)
			draw_line(c + Vector2(0, -2), c + Vector2(0, 7), col, 2.6, true)
