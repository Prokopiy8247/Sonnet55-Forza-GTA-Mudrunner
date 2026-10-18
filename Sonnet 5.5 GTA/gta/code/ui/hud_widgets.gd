class_name HudWidgets
extends RefCounted
## Small custom-drawn HUD widgets (inner classes). The Hud owns / feeds them; they only draw state they are given.
## Design space is 1920 x 1080 (canvas_items stretch scales it).

const HEALTH_HI := Color("#7be495")
const HEALTH_LO := Color("#ff4d4d")


# =====================================================================================================================
## Health / armour bars (bottom-left, next to the minimap).
class StatBars extends Control:
	var health := 1.0
	var armor := 0.0
	var ghost := 1.0
	var health_val := 100
	var armor_val := 0
	var pulse := 0.0          # 0..1 low-health pulse
	var armor_visible := 0.0  # animated 0..1 (armour bar slides in when armour > 0)

	func _init() -> void:
		custom_minimum_size = Vector2(400, 84)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var fd := UITheme.font_display()
		var x0 := 42.0
		var w := size.x - x0 - 78.0
		var hy := size.y - 30.0
		# ---- health ----
		var r := Rect2(x0, hy, w, 20)
		if pulse > 0.01:
			UIDraw.rrect(self, r.grow(3.0 + pulse * 5.0), Color(1.0, 0.18, 0.2, 0.18 + pulse * 0.32), 12)
		UIDraw.rrect(self, r.grow(2), Color(0, 0, 0, 0.5), 10)
		UIDraw.rrect(self, r, Color(1, 1, 1, 0.1), 8)
		var gw := clampf(ghost, 0.0, 1.0) * w
		if gw > health * w + 1.0:
			UIDraw.rrect(self, Rect2(r.position, Vector2(gw, r.size.y)), Color(1, 1, 1, 0.38), 8)
		var col := HudWidgets.HEALTH_LO.lerp(HudWidgets.HEALTH_HI, smoothstep(0.12, 0.65, health))
		if health > 0.005:
			UIDraw.rrect(self, Rect2(r.position, Vector2(maxf(health * w, 10.0), r.size.y)), col, 8)
			UIDraw.rrect(self, Rect2(r.position + Vector2(3, 2), Vector2(maxf(health * w - 6.0, 4.0), 5)), Color(1, 1, 1, 0.22), 3)
		# heart icon
		var hc := Vector2(20, hy + 10)
		var hcol := col.lerp(Color.WHITE, 0.15 + pulse * 0.4)
		draw_circle(hc + Vector2(-4.5, -2.5), 5.8, hcol)
		draw_circle(hc + Vector2(4.5, -2.5), 5.8, hcol)
		draw_colored_polygon(PackedVector2Array([hc + Vector2(-9.9, 0.2), hc + Vector2(9.9, 0.2), hc + Vector2(0, 11)]), hcol)
		UIDraw.text_shadow(self, fd, str(health_val), Vector2(size.x - 66.0, hy + 19), 32, Color.WHITE.lerp(HudWidgets.HEALTH_LO, pulse * 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 62.0)
		# ---- armour ----
		if armor_visible > 0.02:
			var a := armor_visible
			var ay := hy - 22.0 * a
			var ar := Rect2(x0, ay, w, 12)
			UIDraw.rrect(self, ar.grow(2), Color(0, 0, 0, 0.5 * a), 8)
			UIDraw.rrect(self, ar, Color(1, 1, 1, 0.1 * a), 6)
			if armor > 0.005:
				UIDraw.rrect(self, Rect2(ar.position, Vector2(maxf(armor * w, 8.0), ar.size.y)), Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a), 6)
				UIDraw.rrect(self, Rect2(ar.position + Vector2(3, 2), Vector2(maxf(armor * w - 6.0, 3.0), 3)), Color(1, 1, 1, 0.3 * a), 2)
			var sc := Vector2(22, ay + 5.5)
			var scol := Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a)
			draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -8), sc + Vector2(8, -5), sc + Vector2(7, 2), sc + Vector2(0, 9), sc + Vector2(-7, 2), sc + Vector2(-8, -5)]), scol)
			UIDraw.text_shadow(self, fd, str(armor_val), Vector2(size.x - 66.0, ay + 13), 24, Color(0.7, 0.95, 1.0, a), HORIZONTAL_ALIGNMENT_RIGHT, 62.0)


# =====================================================================================================================
## Five wanted stars + pursuit / search state.
class WantedStars extends Control:
	var level := 0
	var state: StringName = &"clear"
	var progress := 0.0          # escape progress 0..1 while searching
	var t := 0.0
	var pop := 0.0               # brief scale pop when the level changes

	func _init() -> void:
		custom_minimum_size = Vector2(300, 88)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if level <= 0:
			return
		var searching := state == &"search"
		var flash := 0.5 + 0.5 * sin(t * 9.0)
		var step := 46.0
		var total := 5.0 * step
		var x0 := size.x - total + step * 0.5
		var cy := 24.0
		UIDraw.rrect(self, Rect2(size.x - total - 12.0 - (40.0 if searching else 0.0), -4.0, total + 24.0 + (40.0 if searching else 0.0), 84.0), Color(0.03, 0.045, 0.07, 0.62), 18)
		# police light strip under the stars (pursuit) / escape bar (search)
		var strip := Rect2(size.x - total + 4.0, 52.0, total - 8.0, 6.0)
		if searching:
			UIDraw.rrect(self, strip, Color(1, 1, 1, 0.12), 3)
			UIDraw.rrect(self, Rect2(strip.position, Vector2(maxf(strip.size.x * progress, 6.0), strip.size.y)), UITheme.C_ACCENT, 3)
		else:
			var half := strip.size.x * 0.5
			var red_on := fmod(t * 3.0, 2.0) < 1.0
			UIDraw.rrect(self, Rect2(strip.position, Vector2(half - 2.0, strip.size.y)), Color(UITheme.C_POLICE_RED.r, UITheme.C_POLICE_RED.g, UITheme.C_POLICE_RED.b, 1.0 if red_on else 0.25), 3)
			UIDraw.rrect(self, Rect2(strip.position + Vector2(half + 2.0, 0), Vector2(half - 2.0, strip.size.y)), Color(UITheme.C_POLICE_BLUE.r, UITheme.C_POLICE_BLUE.g, UITheme.C_POLICE_BLUE.b, 0.25 if red_on else 1.0), 3)
		var fnt := UITheme.font(true)
		var label := "SEARCHING" if searching else "WANTED"
		var lcol := UITheme.C_ACCENT if searching else UITheme.C_POLICE_RED.lightened(0.15)
		UIDraw.text_shadow(self, fnt, label, Vector2(size.x - total + 4.0, 75.0), 15, Color(lcol.r, lcol.g, lcol.b, 0.65 + 0.35 * (flash if searching else 1.0)))
		for i in 5:
			var c := Vector2(x0 + i * step, cy)
			var lit := i < level
			var r := 19.0 * (1.0 + pop * 0.28 * (1.0 if i == level - 1 else 0.0))
			if lit:
				var a := 1.0
				if searching:
					a = 0.25 + 0.75 * smoothstep(0.2, 0.8, flash)
				var base := UITheme.C_GOLD
				draw_colored_polygon(UIDraw.star_points(c + Vector2(0, 2), r + 2.0), Color(0, 0, 0, 0.45 * a))
				UIDraw.star(self, c, r, Color(base.r, base.g, base.b, a), Color(1, 0.95, 0.75, a * 0.9), 1.6)
			else:
				var pts := UIDraw.star_points(c, 17.0)
				var closed := pts.duplicate()
				closed.append(pts[0])
				draw_colored_polygon(pts, Color(1, 1, 1, 0.06))
				draw_polyline(closed, Color(1, 1, 1, 0.42), 1.8, true)
		if searching:
			# escape progress arc to the left of the stars
			var ac := Vector2(size.x - total - 26.0, cy + 2.0)
			draw_arc(ac, 15.0, 0.0, TAU, 40, Color(1, 1, 1, 0.14), 4.0, true)
			if progress > 0.005:
				draw_arc(ac, 15.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, UITheme.C_ACCENT, 4.0, true)


# =====================================================================================================================
## Cash with animated count and floating +/- deltas.
class CashDisplay extends Control:
	var shown := 0.0
	var target := 0
	var flash := 0.0           # +1 green .. -1 red, decays to 0
	var floaters: Array[Dictionary] = []   # {text, age, color}

	func _init() -> void:
		custom_minimum_size = Vector2(420, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add_delta(delta: int) -> void:
		if delta == 0:
			return
		var txt := ("+" if delta > 0 else "-") + Util.format_money(absi(delta))
		floaters.append({"text": txt, "age": 0.0, "color": UITheme.C_OK if delta > 0 else UITheme.C_DANGER})
		if floaters.size() > 4:
			floaters.pop_front()
		flash = 1.0 if delta > 0 else -1.0

	func step(dt: float) -> bool:
		## Returns true when something visible changed.
		var changed := false
		if absf(shown - float(target)) > 0.5:
			var diff := float(target) - shown
			var speed := maxf(absf(diff) * 5.0, 40.0)
			var mv := minf(speed * dt, absf(diff))
			shown += signf(diff) * mv
			changed = true
		elif shown != float(target):
			shown = float(target)
			changed = true
		if absf(flash) > 0.01:
			flash = move_toward(flash, 0.0, dt * 1.6)
			changed = true
		var i := 0
		while i < floaters.size():
			floaters[i]["age"] = float(floaters[i]["age"]) + dt
			changed = true
			if float(floaters[i]["age"]) > 2.6:
				floaters.remove_at(i)
			else:
				i += 1
		return changed

	func _draw() -> void:
		var fd := UITheme.font_display()
		var s := Util.format_money(int(round(shown)))
		var col := Color.WHITE
		if flash > 0.0:
			col = Color.WHITE.lerp(UITheme.C_OK, flash)
		elif flash < 0.0:
			col = Color.WHITE.lerp(UITheme.C_DANGER, -flash)
		var sz := 52
		var tw := fd.get_string_size(s, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, sz).x
		UIDraw.text_shadow(self, fd, s, Vector2(size.x - tw - 4.0, 50.0), sz, col)
		var base_y := 46.0
		var xr := size.x - tw - 26.0
		for i in floaters.size():
			var fl: Dictionary = floaters[floaters.size() - 1 - i]
			var age: float = fl["age"]
			var a := clampf(age / 0.15, 0.0, 1.0) * clampf((2.6 - age) / 0.6, 0.0, 1.0)
			var c: Color = fl["color"]
			var txt: String = fl["text"]
			var w2 := fd.get_string_size(txt, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 28).x
			UIDraw.text_shadow(self, fd, txt, Vector2(xr - w2, base_y - i * 26.0 - age * 5.0), 28, Color(c.r, c.g, c.b, a))


# =====================================================================================================================
## Weapon icon, name, ammo, reload progress.
class WeaponCard extends Control:
	var weapon_id: StringName = &"fists"
	var weapon_name := "Fists"
	var shows_ammo := false
	var mag := 0
	var reserve := 0
	var infinite := false
	var reloading := false
	var reload_t := 0.0
	var t := 0.0
	var kick := 0.0           # ammo number kick on fire
	var total_only := false   # thrown weapons: show a single count
	var category: StringName = &"melee"

	func _init() -> void:
		custom_minimum_size = Vector2(380, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		UIDraw.rrect(self, Rect2(Vector2.ZERO, size).grow(2.0), Color(0, 0, 0, 0.22), 18)
		UIDraw.rrect(self, Rect2(Vector2.ZERO, size), Color(0.04, 0.055, 0.08, 0.80), 16, 1, Color(1, 1, 1, 0.10))
		UIDraw.rrect(self, Rect2(0, 14, 4, size.y - 28), UITheme.C_ACCENT, 2)
		UIIcons.draw_weapon(self, weapon_id, Rect2(18, 12, 136, 70), Color(0.93, 0.97, 1.0, 0.95))
		var f := UITheme.font(true)
		var fd := UITheme.font_display()
		var low := shows_ammo and not infinite and mag <= 0
		if reloading:
			var fl := 0.55 + 0.45 * sin(t * 10.0)
			UIDraw.text(self, f, "RELOADING", Vector2(170, 30), 16, Color(UITheme.C_WARN.r, UITheme.C_WARN.g, UITheme.C_WARN.b, fl))
		else:
			UIDraw.text(self, f, weapon_name.to_upper(), Vector2(170, 30), 16, UITheme.C_DIM, HORIZONTAL_ALIGNMENT_LEFT, size.x - 180.0)
		if shows_ammo:
			var mcol := UITheme.C_DANGER if low else Color.WHITE
			var ms := "--" if infinite else str(mag)
			if total_only:
				ms = "x%d" % (mag + reserve)
				low = mag + reserve <= 0
				mcol = UITheme.C_DANGER if low else Color.WHITE
			var msize := 50 + int(kick * 8.0)
			UIDraw.text_shadow(self, fd, ms, Vector2(170, 78), msize, mcol)
			if not total_only:
				var mw := fd.get_string_size(ms, HORIZONTAL_ALIGNMENT_LEFT, -1.0, msize).x
				var rs := "INF" if infinite else str(reserve)
				UIDraw.text_shadow(self, fd, "/ " + rs, Vector2(170 + mw + 10.0, 78), 28, UITheme.C_DIM)
		else:
			UIDraw.text(self, fd, UIIcons.CATEGORY_NAMES.get(category, "").to_upper(), Vector2(170, 72), 26, Color(1, 1, 1, 0.55))
		if reloading:
			var br := Rect2(18, size.y - 12, size.x - 36, 4)
			UIDraw.rrect(self, br, Color(1, 1, 1, 0.14), 2)
			UIDraw.rrect(self, Rect2(br.position, Vector2(maxf(br.size.x * reload_t, 4.0), br.size.y)), UITheme.C_WARN, 2)


# =====================================================================================================================
## Crosshair / reticle (screen centre). `spread` in pixels; `mode` 0 hidden, 1 dot only, 2 full.
class Crosshair extends Control:
	var mode := 0
	var spread := 8.0
	var hit := 0.0            # 0..1 hit marker flash
	var kill := 0.0           # 0..1 kill marker flash
	var aiming := false
	var tint := Color(1, 1, 1, 0.92)

	func _init() -> void:
		custom_minimum_size = Vector2(400, 400)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var col := tint
		if mode >= 1:
			draw_circle(c, 3.2, Color(0, 0, 0, 0.5))
			draw_circle(c, 2.2, col)
		if mode >= 2:
			var gap := spread
			var ln := 10.0 if aiming else 8.0
			var w := 2.6
			var shadow := Color(0, 0, 0, 0.45)
			for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
				var d: Vector2 = dir
				draw_line(c + d * (gap - 1.0), c + d * (gap + ln + 1.0), shadow, w + 2.0, true)
			for dir2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var d2: Vector2 = dir2
				if d2 == Vector2.DOWN and not aiming:
					continue        # tactical "T" reticle while hip-firing
				draw_line(c + d2 * gap, c + d2 * (gap + ln), col, w, true)
		if hit > 0.01:
			var a := hit
			var rr := 9.0 + (1.0 - hit) * 6.0
			var hc := Color(1, 1, 1, a)
			for sgn in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var v: Vector2 = sgn
				draw_line(c + v * rr, c + v * (rr + 8.0), hc, 2.6, true)
		if kill > 0.01:
			var ka := kill
			var kr := 14.0 + (1.0 - kill) * 6.0
			var kc := Color(UITheme.C_DANGER.r, UITheme.C_DANGER.g, UITheme.C_DANGER.b, ka)
			for sgn2 in [Vector2(1, 1), Vector2(-1, 1)]:
				var v2: Vector2 = sgn2
				draw_line(c - v2 * kr, c + v2 * kr, kc, 3.6, true)
				draw_line(c - v2 * kr, c + v2 * kr, Color(1, 1, 1, ka * 0.5), 1.2, true)


# =====================================================================================================================
## Context prompt (bottom-centre): [E] Buy weapons
class PromptBar extends Control:
	var text := ""
	var key := "E"
	var shown := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(900, 72)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if shown < 0.01 or text == "":
			return
		var f := UITheme.font(true)
		var tsz := 26
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tsz).x
		var cap := 44.0
		var total := cap + 16.0 + tw + 44.0
		var sc := lerpf(0.9, 1.0, shown)
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2(sc, sc))
		var r := Rect2(-total * 0.5, -30.0, total, 60.0)
		UIDraw.rrect(self, r.grow(2.0), Color(0, 0, 0, 0.3 * shown), 20)
		UIDraw.rrect(self, r, Color(0.035, 0.05, 0.075, 0.86 * shown), 18, 1, Color(1, 1, 1, 0.12 * shown))
		var kr := Rect2(r.position.x + 14.0, -cap * 0.5, cap, cap)
		UIDraw.rrect(self, kr, Color(0.0, 0.0, 0.0, 0.0), 10, 2.5, Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, shown))
		UIDraw.text_center(self, f, key, kr.get_center(), 24, Color(1, 1, 1, shown))
		UIDraw.text(self, f, text, Vector2(kr.end.x + 16.0, 9.0), tsz, Color(1, 1, 1, shown))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# =====================================================================================================================
## District name banner (top-centre) with wide tracking and an accent underline wipe.
class DistrictBanner extends Control:
	var text := ""
	var t := 1.0              # 0..1 life progress; >= 1 = hidden
	const LIFE := 4.0

	func _init() -> void:
		custom_minimum_size = Vector2(1000, 120)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_text(s: String) -> void:
		text = s.to_upper()
		t = 0.0

	func _draw() -> void:
		if t >= 1.0 or text == "":
			return
		var life := t * LIFE
		var a := clampf(life / 0.35, 0.0, 1.0) * clampf((LIFE - life) / 0.7, 0.0, 1.0)
		var wipe := UIDraw.ease_out(life / 0.6)
		var fd := UITheme.font_display()
		var f := UITheme.font(true)
		var sz := 56
		var track := 9.0
		var total := 0.0
		for i in text.length():
			total += fd.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x + track
		total -= track
		var x := (size.x - total) * 0.5 + (1.0 - wipe) * 30.0
		var base_y := 74.0
		for i in text.length():
			var ch := text[i]
			var cw := fd.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
			UIDraw.text_shadow(self, fd, ch, Vector2(x, base_y), sz, Color(1, 1, 1, a))
			x += cw + track
		var cap := "NOW ENTERING"
		var cw2 := f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
		UIDraw.text(self, f, cap, Vector2((size.x - cw2) * 0.5, 22.0), 16, Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a * 0.9))
		var lw := total * wipe
		UIDraw.rrect(self, Rect2((size.x - lw) * 0.5, 90.0, lw, 3.0), Color(UITheme.C_ACCENT2.r, UITheme.C_ACCENT2.g, UITheme.C_ACCENT2.b, a), 1)


# =====================================================================================================================
## Underwater air bar.
class AirBar extends Control:
	var ratio := 1.0
	var t := 0.0
	var shown := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(380, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if shown < 0.01:
			return
		var low := ratio < 0.28
		var col := UITheme.C_ACCENT.lerp(UITheme.C_DANGER, 1.0 - smoothstep(0.05, 0.3, ratio))
		var flash := 0.6 + 0.4 * sin(t * 12.0) if low else 1.0
		var f := UITheme.font(true)
		var r := Rect2(70, 14, size.x - 82, 16)
		UIDraw.rrect(self, Rect2(0, 2, size.x, size.y - 4), Color(0.03, 0.045, 0.07, 0.72 * shown), 16)
		UIDraw.text_shadow(self, f, "AIR", Vector2(18, 30), 20, Color(col.r, col.g, col.b, shown * flash))
		UIDraw.rrect(self, r.grow(2), Color(0, 0, 0, 0.5 * shown), 10)
		UIDraw.rrect(self, r, Color(1, 1, 1, 0.1 * shown), 8)
		UIDraw.rrect(self, Rect2(r.position, Vector2(maxf(r.size.x * ratio, 8.0), r.size.y)), Color(col.r, col.g, col.b, shown * flash), 8)


# =====================================================================================================================
## Stealth eye: shows while crouching.
class StealthIcon extends Control:
	var noise := 0.0          # 0..1 how loud the player is
	var seen := false
	var shown := 0.0
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(220, 52)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if shown < 0.01:
			return
		var col := UITheme.C_DANGER if seen else UITheme.C_OK.lerp(UITheme.C_WARN, clampf(noise * 1.4, 0.0, 1.0))
		col.a = shown
		var f := UITheme.font(true)
		UIDraw.rrect(self, Rect2(Vector2.ZERO, size), Color(0.03, 0.045, 0.07, 0.78 * shown), 14)
		var c := Vector2(32, size.y * 0.5)
		var pts := PackedVector2Array([c + Vector2(-17, 0), c + Vector2(-8, -9), c + Vector2(8, -9), c + Vector2(17, 0), c + Vector2(8, 9), c + Vector2(-8, 9)])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, shown * 0.3))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, 2.2, true)
		draw_circle(c, 4.5 + (1.5 * sin(t * 6.0) if seen else 0.0), col)
		UIDraw.text(self, f, "SPOTTED" if seen else "HIDDEN", Vector2(60, 22), 16, col)
		var br := Rect2(60, 31, size.x - 76, 6)
		UIDraw.rrect(self, br, Color(1, 1, 1, 0.12 * shown), 3)
		UIDraw.rrect(self, Rect2(br.position, Vector2(maxf(br.size.x * noise, 5.0), br.size.y)), Color(col.r, col.g, col.b, shown * 0.9), 3)


# =====================================================================================================================
## Parachute altimeter (shown while parachuting / free-falling with a chute).
class ChuteGauge extends Control:
	var altitude := 0.0
	var vspeed := 0.0
	var shown := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(240, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if shown < 0.01:
			return
		var a := shown
		var f := UITheme.font(true)
		var fd := UITheme.font_display()
		UIDraw.rrect(self, Rect2(Vector2.ZERO, size), Color(0.04, 0.055, 0.08, 0.8 * a), 16, 1, Color(1, 1, 1, 0.1 * a))
		UIDraw.text(self, f, "ALTITUDE", Vector2(18, 28), 15, Color(UITheme.C_DIM.r, UITheme.C_DIM.g, UITheme.C_DIM.b, a))
		UIDraw.text_shadow(self, fd, "%d m" % int(altitude), Vector2(18, 70), 42, Color(1, 1, 1, a))
		var vs := clampf(-vspeed / 20.0, 0.0, 1.0)
		var c := Vector2(size.x - 34.0, size.y * 0.5)
		draw_arc(c, 18.0, PI * 0.75, PI * 2.25, 24, Color(1, 1, 1, 0.14 * a), 4.0, true)
		draw_arc(c, 18.0, PI * 0.75, PI * 0.75 + PI * 1.5 * vs, 24, Color(UITheme.C_ACCENT.r, UITheme.C_ACCENT.g, UITheme.C_ACCENT.b, a), 4.0, true)
		UIDraw.text_center(self, f, "%d" % int(-vspeed), c, 15, Color(1, 1, 1, a))


# =====================================================================================================================
## Full-screen sniper scope overlay (shader ring + hair-lines).
class ScopeOverlay extends ColorRect:
	const CODE := """
shader_type canvas_item;
uniform float ratio = 1.7778;
uniform float radius = 0.44;
void fragment() {
	vec2 p = UV - 0.5;
	p.x *= ratio;
	float d = length(p);
	float a = smoothstep(radius, radius + 0.004, d);
	float rim = smoothstep(radius - 0.012, radius - 0.002, d) * (1.0 - a);
	float hair = 0.0;
	if (d < radius) {
		float w = 0.0007;
		hair = max(step(abs(p.x), w) * step(0.012, abs(p.y)), step(abs(p.y), w) * step(0.012, abs(p.x)));
		float tick = step(abs(p.y), 0.003) * step(0.1, abs(p.x)) * step(fract(abs(p.x) * 24.0), 0.08);
		hair = max(hair, tick * 0.7);
	}
	float vign = smoothstep(0.0, radius, d) * 0.35;
	vec3 col = vec3(0.0);
	float alpha = max(a, max(rim * 0.8, max(hair * 0.9, vign)));
	COLOR = vec4(col, alpha);
}
"""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		color = Color.WHITE
		var sh := Shader.new()
		sh.code = CODE
		var m := ShaderMaterial.new()
		m.shader = sh
		material = m
		resized.connect(_on_resized)

	func _on_resized() -> void:
		if size.y > 1.0:
			(material as ShaderMaterial).set_shader_parameter("ratio", size.x / size.y)
