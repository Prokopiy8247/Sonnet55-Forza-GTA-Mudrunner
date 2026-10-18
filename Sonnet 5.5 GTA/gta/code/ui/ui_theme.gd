class_name UITheme
extends RefCounted
## The shared "Halcyon" UI theme, built entirely in code (no image assets): dark translucent rounded panels,
## cyan / magenta accents (GC.COL_*), clean sans type. Everything in the UI module pulls colours, fonts and
## styleboxes from here so the HUD, menus and widgets look like one product.
##
##   var theme: Theme = UITheme.build()          # cached; assign to the UI root Control
##   UITheme.font_display()                       # condensed bold face for big numbers (speed, cash)
##   UITheme.box(radius, fill, border_w, border)  # one-off StyleBoxFlat

# ---- Layout ----------------------------------------------------------------------------------------
const SAFE_X := 56.0           # horizontal safe margin (design space is 1920 x 1080, scaled by canvas_items stretch)
const SAFE_Y := 40.0
const BASE_SIZE := 22          # default body font size
const RADIUS := 12

# ---- Palette (extends GC.COL_*) ---------------------------------------------------------------------
const C_ACCENT := GC.COL_ACCENT
const C_ACCENT2 := GC.COL_ACCENT2
const C_WARN := GC.COL_WARN
const C_DANGER := GC.COL_DANGER
const C_OK := GC.COL_OK
const C_TEXT := GC.COL_TEXT
const C_DIM := GC.COL_TEXT_DIM
const C_PANEL := Color(0.043, 0.059, 0.086, 0.86)
const C_PANEL_HI := Color(0.075, 0.102, 0.145, 0.94)
const C_PANEL_DEEP := Color(0.028, 0.038, 0.056, 0.92)
const C_ROW := Color(1, 1, 1, 0.045)
const C_ROW_HOVER := Color(0.20, 0.88, 1.0, 0.13)
const C_BORDER := Color(1, 1, 1, 0.09)
const C_BORDER_HI := Color(0.20, 0.88, 1.0, 0.60)
const C_SHADOW := Color(0, 0, 0, 0.38)
const C_POLICE_RED := Color("#ff3b4a")
const C_POLICE_BLUE := Color("#3a7bff")
const C_GOLD := Color("#ffd35a")

static var _theme: Theme = null
static var _fonts: Dictionary = {}
static var _tex_cache: Dictionary = {}


# ---- Fonts -------------------------------------------------------------------------------------------
static func font(bold: bool = false) -> Font:
	var key := "b" if bold else "r"
	if not _fonts.has(key):
		_fonts[key] = _make_font(PackedStringArray(["Segoe UI Variable Display", "Segoe UI", "Inter", "Roboto", "Helvetica Neue", "Arial", "sans-serif"]),
			700 if bold else 400)
	return _fonts[key]


## Condensed technical face for big numbers (speed, cash, ammo). Bahnschrift ships with Windows 10+.
static func font_display() -> Font:
	if not _fonts.has("d"):
		_fonts["d"] = _make_font(PackedStringArray(["Bahnschrift", "Bahnschrift SemiBold", "Segoe UI Semibold", "Segoe UI", "Arial", "sans-serif"]), 600)
	return _fonts["d"]


static func _make_font(names: PackedStringArray, weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = names
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.hinting = TextServer.HINTING_NONE
	f.fallbacks = [ThemeDB.fallback_font]
	return f


# ---- Style helpers -------------------------------------------------------------------------------------
static func box(radius: float = RADIUS, fill: Color = C_PANEL, border_w: float = 0.0, border: Color = C_BORDER,
		margin_h: float = 0.0, margin_v: float = 0.0, shadow: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if border_w > 0.0:
		sb.set_border_width_all(int(border_w))
		sb.border_color = border
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	if shadow > 0.0:
		sb.shadow_size = int(shadow)
		sb.shadow_color = C_SHADOW
		sb.shadow_offset = Vector2(0, 4)
	return sb


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Anti-aliased disc / ring / pill textures generated once (used for slider knobs and toggles).
static func disc_tex(size: int, fill: Color, ring: Color = Color(0, 0, 0, 0), ring_w: float = 0.0) -> Texture2D:
	var key := "d%d%s%s%.1f" % [size, fill.to_html(), ring.to_html(), ring_w]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	var r := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var col := fill
			if ring_w > 0.0:
				var t := clampf(d - (r - ring_w) + 0.5, 0.0, 1.0)
				col = fill.lerp(ring, t)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func toggle_tex(on: bool, disabled: bool = false) -> Texture2D:
	var key := "t%s%s" % [on, disabled]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := 56
	var h := 30
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var track := C_ACCENT.darkened(0.15) if on else Color(0.22, 0.27, 0.34, 1.0)
	if disabled:
		track = track.darkened(0.4)
	var knob := Color(1, 1, 1, 1) if on else Color(0.72, 0.78, 0.84, 1)
	var kx := w - h * 0.5 if on else h * 0.5
	var kr := h * 0.5 - 4.0
	for y in h:
		for x in w:
			# pill track: distance to the capsule segment
			var px := clampf(float(x), h * 0.5, w - h * 0.5)
			var d := Vector2(x - px, y - (h - 1) * 0.5).length()
			var a := clampf(h * 0.5 - 1.0 - d + 0.5, 0.0, 1.0)
			var col := Color(track.r, track.g, track.b, a)
			var kd := Vector2(x - kx, y - (h - 1) * 0.5).length()
			var ka := clampf(kr - kd + 0.5, 0.0, 1.0)
			col = col.lerp(Color(knob.r, knob.g, knob.b, 1.0), ka)
			col.a = maxf(col.a, ka)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


# ---- Theme --------------------------------------------------------------------------------------------------
static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = BASE_SIZE

	# Label / RichText
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_font("normal_font", "RichTextLabel", font(false))
	t.set_font("bold_font", "RichTextLabel", font(true))
	t.set_font_size("normal_font_size", "RichTextLabel", BASE_SIZE)
	t.set_font_size("bold_font_size", "RichTextLabel", BASE_SIZE)

	# Label variations
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font(true))
	t.set_font_size("font_size", "Title", 34)
	t.set_type_variation("Subtle", "Label")
	t.set_color("font_color", "Subtle", C_DIM)
	t.set_font_size("font_size", "Subtle", 18)
	t.set_type_variation("Caption", "Label")
	t.set_color("font_color", "Caption", C_DIM)
	t.set_font("font", "Caption", font(true))
	t.set_font_size("font_size", "Caption", 15)

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(14, C_PANEL, 1, C_BORDER, 22, 18, 22))
	t.set_stylebox("panel", "Panel", box(14, C_PANEL, 1, C_BORDER))
	t.set_type_variation("PanelHi", "PanelContainer")
	t.set_stylebox("panel", "PanelHi", box(12, C_PANEL_HI, 1, C_BORDER, 16, 12))
	t.set_type_variation("PanelDeep", "PanelContainer")
	t.set_stylebox("panel", "PanelDeep", box(12, C_PANEL_DEEP, 1, C_BORDER, 16, 12))
	t.set_type_variation("PanelFlat", "PanelContainer")
	t.set_stylebox("panel", "PanelFlat", box(10, C_ROW, 0, C_BORDER, 14, 10))
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", box(20, Color(0.06, 0.08, 0.12, 0.88), 1, C_BORDER, 14, 4))
	t.set_type_variation("PriceTag", "PanelContainer")
	t.set_stylebox("panel", "PriceTag", box(20, with_alpha(C_OK, 0.16), 1, with_alpha(C_OK, 0.55), 12, 3))
	t.set_type_variation("PriceTagBad", "PanelContainer")
	t.set_stylebox("panel", "PriceTagBad", box(20, with_alpha(C_DANGER, 0.14), 1, with_alpha(C_DANGER, 0.55), 12, 3))
	t.set_type_variation("KeyCap", "PanelContainer")
	t.set_stylebox("panel", "KeyCap", box(7, Color(1, 1, 1, 0.12), 2, Color(1, 1, 1, 0.38), 9, 1))

	# Buttons
	var b_norm := box(10, Color(0.09, 0.12, 0.17, 0.92), 1, C_BORDER, 22, 11)
	var b_hover := box(10, Color(0.12, 0.17, 0.24, 0.95), 1, C_BORDER_HI, 22, 11)
	var b_press := box(10, with_alpha(C_ACCENT, 0.30), 1, C_ACCENT, 22, 11)
	var b_dis := box(10, Color(0.07, 0.09, 0.12, 0.6), 1, Color(1, 1, 1, 0.04), 22, 11)
	var b_focus := box(10, Color(0, 0, 0, 0), 2, C_ACCENT, 22, 11)
	for ty in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", ty, b_norm)
		t.set_stylebox("hover", ty, b_hover)
		t.set_stylebox("pressed", ty, b_press)
		t.set_stylebox("disabled", ty, b_dis)
		t.set_stylebox("focus", ty, b_focus)
		t.set_stylebox("hover_pressed", ty, b_press)
		t.set_color("font_color", ty, C_TEXT)
		t.set_color("font_hover_color", ty, Color.WHITE)
		t.set_color("font_pressed_color", ty, Color.WHITE)
		t.set_color("font_focus_color", ty, Color.WHITE)
		t.set_color("font_hover_pressed_color", ty, Color.WHITE)
		t.set_color("font_disabled_color", ty, Color(0.5, 0.57, 0.64, 0.7))
		t.set_font_size("font_size", ty, BASE_SIZE)
		t.set_constant("h_separation", ty, 10)
	t.set_font("font", "Button", font(true))
	# AccentButton: filled cyan, dark text
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", box(10, with_alpha(C_ACCENT, 0.92), 0, C_ACCENT, 26, 11))
	t.set_stylebox("hover", "AccentButton", box(10, C_ACCENT.lightened(0.25), 0, C_ACCENT, 26, 11))
	t.set_stylebox("pressed", "AccentButton", box(10, C_ACCENT.darkened(0.2), 0, C_ACCENT, 26, 11))
	t.set_stylebox("focus", "AccentButton", box(10, Color(0, 0, 0, 0), 2, Color.WHITE, 26, 11))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "AccentButton", Color(0.02, 0.07, 0.1))
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", box(10, with_alpha(C_ACCENT2, 0.2), 1, with_alpha(C_ACCENT2, 0.7), 22, 11))
	t.set_stylebox("hover", "DangerButton", box(10, with_alpha(C_ACCENT2, 0.4), 1, C_ACCENT2, 22, 11))
	t.set_stylebox("pressed", "DangerButton", box(10, with_alpha(C_ACCENT2, 0.6), 1, C_ACCENT2, 22, 11))
	# Tab button (toggle)
	t.set_type_variation("TabButton", "Button")
	t.set_stylebox("normal", "TabButton", box(8, Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 24, 10))
	t.set_stylebox("hover", "TabButton", box(8, Color(1, 1, 1, 0.06), 0, Color(0, 0, 0, 0), 24, 10))
	t.set_stylebox("pressed", "TabButton", box(8, with_alpha(C_ACCENT, 0.18), 0, C_ACCENT, 24, 10))
	t.set_stylebox("hover_pressed", "TabButton", box(8, with_alpha(C_ACCENT, 0.24), 0, C_ACCENT, 24, 10))
	t.set_color("font_color", "TabButton", C_DIM)
	t.set_color("font_pressed_color", "TabButton", C_ACCENT)
	t.set_color("font_hover_pressed_color", "TabButton", C_ACCENT)
	# Row / Card buttons (children laid out by UIKit)
	t.set_type_variation("RowButton", "Button")
	t.set_stylebox("normal", "RowButton", box(9, C_ROW, 0, C_BORDER, 14, 8))
	t.set_stylebox("hover", "RowButton", box(9, C_ROW_HOVER, 1, with_alpha(C_ACCENT, 0.4), 14, 8))
	t.set_stylebox("pressed", "RowButton", box(9, with_alpha(C_ACCENT, 0.26), 1, C_ACCENT, 14, 8))
	t.set_stylebox("hover_pressed", "RowButton", box(9, with_alpha(C_ACCENT, 0.3), 1, C_ACCENT, 14, 8))
	t.set_stylebox("focus", "RowButton", box(9, Color(0, 0, 0, 0), 2, C_ACCENT, 14, 8))
	t.set_type_variation("CardButton", "Button")
	t.set_stylebox("normal", "CardButton", box(14, C_PANEL_HI, 1, C_BORDER, 14, 12))
	t.set_stylebox("hover", "CardButton", box(14, Color(0.10, 0.14, 0.2, 0.96), 1, C_BORDER_HI, 14, 12))
	t.set_stylebox("pressed", "CardButton", box(14, with_alpha(C_ACCENT, 0.24), 2, C_ACCENT, 14, 12))
	t.set_stylebox("hover_pressed", "CardButton", box(14, with_alpha(C_ACCENT, 0.28), 2, C_ACCENT, 14, 12))
	t.set_stylebox("focus", "CardButton", box(14, Color(0, 0, 0, 0), 2, C_ACCENT, 14, 12))

	# Inputs
	var le := box(8, Color(0.03, 0.05, 0.08, 0.9), 1, C_BORDER, 12, 8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(8, Color(0.03, 0.05, 0.08, 0.95), 2, C_ACCENT, 12, 8))
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("caret_color", "LineEdit", C_ACCENT)
	t.set_color("selection_color", "LineEdit", with_alpha(C_ACCENT, 0.35))

	# Sliders
	var track := box(4, Color(1, 1, 1, 0.12), 0, C_BORDER)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := box(4, C_ACCENT, 0, C_BORDER)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var fill_hi := box(4, C_ACCENT.lightened(0.25), 0, C_BORDER)
	fill_hi.content_margin_top = 4
	fill_hi.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", disc_tex(26, Color.WHITE, C_ACCENT, 4.0))
	t.set_icon("grabber_highlight", "HSlider", disc_tex(30, Color.WHITE, C_ACCENT.lightened(0.3), 5.0))
	t.set_icon("grabber_disabled", "HSlider", disc_tex(26, Color(0.5, 0.55, 0.6), Color(0.3, 0.33, 0.37), 4.0))
	t.set_constant("center_grabber", "HSlider", 0)

	# Toggle switches
	for ty in ["CheckButton", "CheckBox"]:
		t.set_icon("checked", ty, toggle_tex(true))
		t.set_icon("unchecked", ty, toggle_tex(false))
		t.set_icon("checked_disabled", ty, toggle_tex(true, true))
		t.set_icon("unchecked_disabled", ty, toggle_tex(false, true))
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 8
		for sn in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(sn, ty, empty)
		t.set_stylebox("focus", ty, box(8, Color(0, 0, 0, 0), 2, C_ACCENT))
		t.set_color("font_color", ty, C_TEXT)
		t.set_color("font_hover_color", ty, Color.WHITE)
		t.set_color("font_pressed_color", ty, C_TEXT)
		t.set_color("font_hover_pressed_color", ty, Color.WHITE)
		t.set_constant("h_separation", ty, 12)

	# Scrollbars
	var sc := box(4, Color(1, 1, 1, 0.05))
	sc.content_margin_left = 5
	sc.content_margin_right = 5
	for ty in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", ty, sc)
		t.set_stylebox("scroll_focus", ty, sc)
		t.set_stylebox("grabber", ty, box(4, with_alpha(C_ACCENT, 0.45)))
		t.set_stylebox("grabber_highlight", ty, box(4, with_alpha(C_ACCENT, 0.75)))
		t.set_stylebox("grabber_pressed", ty, box(4, C_ACCENT))
	t.set_constant("separation", "ScrollContainer", 0)

	# Progress
	t.set_stylebox("background", "ProgressBar", box(5, Color(1, 1, 1, 0.1)))
	t.set_stylebox("fill", "ProgressBar", box(5, C_ACCENT))
	t.set_color("font_color", "ProgressBar", C_TEXT)
	t.set_font_size("font_size", "ProgressBar", 15)

	# Separators / boxes
	var sep := StyleBoxLine.new()
	sep.color = C_BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 14)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("h_separation", "GridContainer", 14)
	t.set_constant("v_separation", "GridContainer", 14)

	# Popups (OptionButton lists)
	t.set_stylebox("panel", "PopupMenu", box(10, Color(0.05, 0.07, 0.1, 0.98), 1, C_BORDER_HI, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(6, with_alpha(C_ACCENT, 0.25)))
	t.set_color("font_color", "PopupMenu", C_TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", BASE_SIZE)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_stylebox("panel", "TooltipPanel", box(8, Color(0.03, 0.04, 0.06, 0.96), 1, C_BORDER_HI, 12, 8))
	t.set_color("font_color", "TooltipLabel", C_TEXT)

	_theme = t
	return t
