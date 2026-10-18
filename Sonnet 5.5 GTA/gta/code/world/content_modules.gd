class_name ContentModules
extends RefCounted
## Code-built FALLBACK module meshes for the building kit (used only while the Blender kit GLBs are missing, and for
## pieces the kits do not provide). Same conventions as the Blender kits (docs/ARCHITECTURE.md s7):
## 4.0 m bays, 3.6 m floors, module origin = bottom-centre of the FRONT plane, facade faces -Z (Godot) and the wall
## slab extends toward +Z. Window UVs are in metres (u across the bay, v = height inside the module).
## Surface keys select the runtime material: WallA..WallD / Roof / Trim (palette driven), Window_<variant>, Neon (hue per
## instance), Metal / V (vertex colour driven).

const BAY := 4.0
const FH := 3.6

const C_STEEL := Color("#8d96a0")
const C_STEEL_D := Color("#4b525b")
const C_DARK := Color("#2a2d33")
const C_WHITE := Color("#f2f0ea")
const C_BRICK := Color("#a4553f")
const C_WOOD := Color("#8a5a3b")
const C_CONC := Color("#9a958c")
const C_AC := Color("#cdd3d8")


static func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


## Front-facing quad at depth z (normal -Z).
static func _fq(m: ContentMesh, key: StringName, x0: float, y0: float, x1: float, y1: float, z: float, col := Color.WHITE) -> void:
	if x1 - x0 < 0.0005 or y1 - y0 < 0.0005:
		return
	m.quad(key, _v(x0, y0, z), _v(x1, y0, z), _v(x1, y1, z), _v(x0, y1, z), Vector3(0, 0, -1), col)


## Wall of the module rectangle [x0,x1]x[y0,y1] at z=0 with rectangular openings (x ranges share oy0..oy1),
## reveals of `depth` and a glass quad at the bottom of each opening.
static func _openings(m: ContentMesh, wall_key: StringName, reveal_key: StringName, glass_key: StringName,
		x0: float, x1: float, y0: float, y1: float, ranges: Array, oy0: float, oy1: float, depth: float, glass_u_off := 0.0) -> void:
	_fq(m, wall_key, x0, y0, x1, oy0, 0.0)
	_fq(m, wall_key, x0, oy1, x1, y1, 0.0)
	var cur := x0
	for r in ranges:
		var rx0: float = (r as Vector2).x
		var rx1: float = (r as Vector2).y
		_fq(m, wall_key, cur, oy0, rx0, oy1, 0.0)
		cur = rx1
		# reveals
		m.quad(reveal_key, _v(rx0, oy0, 0), _v(rx1, oy0, 0), _v(rx1, oy0, depth), _v(rx0, oy0, depth), Vector3.UP, Color.WHITE)
		m.quad(reveal_key, _v(rx0, oy1, depth), _v(rx1, oy1, depth), _v(rx1, oy1, 0), _v(rx0, oy1, 0), Vector3.DOWN, Color.WHITE)
		m.quad(reveal_key, _v(rx0, oy0, depth), _v(rx0, oy0, 0), _v(rx0, oy1, 0), _v(rx0, oy1, depth), Vector3.RIGHT, Color.WHITE)
		m.quad(reveal_key, _v(rx1, oy0, 0), _v(rx1, oy0, depth), _v(rx1, oy1, depth), _v(rx1, oy1, 0), Vector3.LEFT, Color.WHITE)
		m.quad(glass_key, _v(rx0, oy0, depth), _v(rx1, oy0, depth), _v(rx1, oy1, depth), _v(rx0, oy1, depth), Vector3(0, 0, -1), Color.WHITE,
			Vector2(rx0 + glass_u_off, oy0), Vector2(rx1 + glass_u_off, oy1))
	_fq(m, wall_key, cur, oy0, x1, oy1, 0.0)


static func _pilasters(m: ContentMesh, key: StringName, w := 0.2, d := 0.12) -> void:
	m.box(key, _v(-BAY * 0.5 + w * 0.5, FH * 0.5, -d * 0.5), _v(w, FH, d), Color.WHITE, 2 | 8 | 16)
	m.box(key, _v(BAY * 0.5 - w * 0.5, FH * 0.5, -d * 0.5), _v(w, FH, d), Color.WHITE, 1 | 8 | 16)


# ---- Office ---------------------------------------------------------------------------------------------------
static func office_win() -> ContentMesh:
	var m := ContentMesh.new()
	_openings(m, &"WallA", &"WallD", &"Window_office", -2.0, 2.0, 0.0, FH, [Vector2(-1.7, 1.7)], 0.95, 3.25, 0.22)
	_pilasters(m, &"WallD")
	m.box(&"WallD", _v(0, 0.91, -0.07), _v(3.6, 0.08, 0.14), Color.WHITE, 8 | 16)
	m.box(&"WallD", _v(0, 0.42, -0.02), _v(3.6, 0.1, 0.04), Color.WHITE, 8 | 16)
	return m


static func office_glass() -> ContentMesh:
	var m := ContentMesh.new()
	_openings(m, &"WallD", &"Trim", &"Window_office", -2.0, 2.0, 0.0, FH, [Vector2(-1.9, 1.9)], 0.5, 3.4, 0.16)
	m.box(&"Trim", _v(0, 0.06, -0.05), _v(4.0, 0.12, 0.1), Color.WHITE, 8 | 16)
	m.box(&"WallA", _v(0, 3.52, -0.05), _v(4.0, 0.16, 0.1), Color.WHITE, 16)
	return m


static func office_door() -> ContentMesh:
	var m := ContentMesh.new()
	# lobby: tall glass wall with a double door, canopy over the entrance
	_fq(m, &"WallD", -2.0, 0.0, -1.7, 2.9, 0.0)
	_fq(m, &"WallD", 1.7, 0.0, 2.0, 2.9, 0.0)
	_fq(m, &"WallD", -2.0, 2.9, 2.0, FH, 0.0)
	m.quad(&"Window_shop", _v(-1.7, 0.0, 0.25), _v(1.7, 0.0, 0.25), _v(1.7, 2.9, 0.25), _v(-1.7, 2.9, 0.25), Vector3(0, 0, -1), Color.WHITE, Vector2(-1.7, 0.0), Vector2(1.7, 2.9))
	m.quad(&"Trim", _v(-1.7, 0, 0), _v(-1.7, 0, 0.25), _v(-1.7, 2.9, 0.25), _v(-1.7, 2.9, 0), Vector3.RIGHT, Color.WHITE)
	m.quad(&"Trim", _v(1.7, 0, 0.25), _v(1.7, 0, 0), _v(1.7, 2.9, 0), _v(1.7, 2.9, 0.25), Vector3.LEFT, Color.WHITE)
	m.box(&"Metal", _v(0, 1.2, 0.2), _v(0.07, 2.4, 0.07), C_STEEL_D)
	m.box(&"Metal", _v(0, 2.45, 0.2), _v(3.4, 0.07, 0.07), C_STEEL_D)
	m.box(&"WallA", _v(0, 3.1, -0.65), _v(3.6, 0.14, 1.5), Color.WHITE, 8)
	m.box(&"Trim", _v(0, 2.97, -1.38), _v(3.6, 0.12, 0.05), Color.WHITE)
	m.box(&"V", _v(0, 0.07, -0.5), _v(3.2, 0.14, 1.0), C_CONC, 8)
	m.box(&"Neon", _v(0, 3.3, -0.05), _v(2.4, 0.1, 0.05))
	_pilasters(m, &"WallD")
	return m


# ---- Apartment ---------------------------------------------------------------------------------------------------
static func _frame(m: ContentMesh, key: StringName, x0: float, x1: float, y0: float, y1: float, t := 0.09, d := 0.07) -> void:
	m.box(key, _v((x0 + x1) * 0.5, y0 - t * 0.5, -d * 0.5), _v(x1 - x0 + t * 2.0, t, d), Color.WHITE, 16)
	m.box(key, _v((x0 + x1) * 0.5, y1 + t * 0.5, -d * 0.5), _v(x1 - x0 + t * 2.0, t, d), Color.WHITE, 16)
	m.box(key, _v(x0 - t * 0.5, (y0 + y1) * 0.5, -d * 0.5), _v(t, y1 - y0, d), Color.WHITE, 16)
	m.box(key, _v(x1 + t * 0.5, (y0 + y1) * 0.5, -d * 0.5), _v(t, y1 - y0, d), Color.WHITE, 16)


static func apt_win() -> ContentMesh:
	var m := ContentMesh.new()
	_openings(m, &"WallA", &"WallD", &"Window_res", -2.0, 2.0, 0.0, FH, [Vector2(-0.8, 0.8)], 1.0, 2.85, 0.22)
	_frame(m, &"Trim", -0.8, 0.8, 1.0, 2.85)
	m.box(&"Trim", _v(0, 0.95, -0.1), _v(1.9, 0.09, 0.2), Color.WHITE, 8 | 16)
	m.box(&"WallD", _v(0, 3.53, -0.03), _v(4.0, 0.14, 0.06), Color.WHITE, 16)
	return m


static func apt_win2() -> ContentMesh:
	var m := ContentMesh.new()
	_openings(m, &"WallA", &"WallD", &"Window_res", -2.0, 2.0, 0.0, FH, [Vector2(-1.5, -0.5), Vector2(0.5, 1.5)], 1.0, 2.85, 0.2)
	_frame(m, &"Trim", -1.5, -0.5, 1.0, 2.85)
	_frame(m, &"Trim", 0.5, 1.5, 1.0, 2.85)
	m.box(&"Trim", _v(-1.0, 0.95, -0.1), _v(1.3, 0.09, 0.2), Color.WHITE, 8 | 16)
	m.box(&"Trim", _v(1.0, 0.95, -0.1), _v(1.3, 0.09, 0.2), Color.WHITE, 8 | 16)
	m.box(&"WallD", _v(0, 3.53, -0.03), _v(4.0, 0.14, 0.06), Color.WHITE, 16)
	return m


static func apt_balc() -> ContentMesh:
	var m := ContentMesh.new()
	_openings(m, &"WallA", &"WallD", &"Window_res", -2.0, 2.0, 0.0, FH, [Vector2(-1.3, 1.3)], 0.2, 2.8, 0.25)
	_frame(m, &"Trim", -1.3, 1.3, 0.2, 2.8, 0.1, 0.07)
	m.box(&"WallD", _v(0, 0.08, -0.75), _v(3.7, 0.16, 1.5), Color.WHITE, 16)
	# railing
	m.box(&"Metal", _v(0, 1.05, -1.48), _v(3.7, 0.05, 0.05), C_STEEL_D)
	m.box(&"Metal", _v(0, 0.55, -1.48), _v(3.7, 0.03, 0.03), C_STEEL_D)
	m.box(&"Metal", _v(-1.82, 1.05, -0.75), _v(0.05, 0.05, 1.5), C_STEEL_D)
	m.box(&"Metal", _v(1.82, 1.05, -0.75), _v(0.05, 0.05, 1.5), C_STEEL_D)
	for i in 6:
		m.box(&"Metal", _v(-1.82 + i * 0.728, 0.6, -1.48), _v(0.04, 1.0, 0.04), C_STEEL_D)
	m.box(&"WallD", _v(0, 3.53, -0.03), _v(4.0, 0.14, 0.06), Color.WHITE, 16)
	return m


static func apt_door() -> ContentMesh:
	var m := ContentMesh.new()
	_openings(m, &"WallA", &"WallD", &"Window_res", -2.0, 2.0, 0.0, FH, [Vector2(-0.8, 0.8)], 0.0, 2.45, 0.28)
	m.box(&"V", _v(0, 1.05, 0.22), _v(0.06, 2.1, 0.06), C_DARK)
	m.box(&"Metal", _v(0, 2.35, 0.2), _v(1.6, 0.06, 0.06), C_STEEL_D)
	_frame(m, &"Trim", -0.8, 0.8, 0.0, 2.45, 0.1, 0.09)
	m.box(&"WallD", _v(0, 2.72, -0.55), _v(2.4, 0.12, 1.1), Color.WHITE, 8)
	m.box(&"V", _v(0, 0.06, -0.55), _v(2.2, 0.12, 1.1), C_CONC, 8)
	m.box(&"V", _v(0, 0.03, -1.2), _v(2.4, 0.06, 0.3), C_CONC, 8)
	m.box(&"WallD", _v(0, 3.53, -0.03), _v(4.0, 0.14, 0.06), Color.WHITE, 16)
	return m


# ---- Shop ---------------------------------------------------------------------------------------------------------
static func _shop_common(m: ContentMesh) -> void:
	# sign band + piers + neon strip
	_fq(m, &"WallA", -2.0, 2.85, 2.0, FH, 0.0)
	_fq(m, &"WallD", -2.0, 0.0, -1.85, 2.85, 0.0)
	_fq(m, &"WallD", 1.85, 0.0, 2.0, 2.85, 0.0)
	m.box(&"WallD", _v(0, 2.88, -0.07), _v(4.0, 0.12, 0.14), Color.WHITE, 8 | 16)
	m.box(&"V", _v(0, 3.2, -0.05), _v(3.3, 0.5, 0.06), C_DARK, 16)
	m.box(&"Neon", _v(0, 3.2, -0.09), _v(2.6, 0.13, 0.04))
	m.box(&"WallD", _v(-1.93, 1.4, -0.06), _v(0.14, 2.9, 0.12), Color.WHITE, 8 | 16)
	m.box(&"WallD", _v(1.93, 1.4, -0.06), _v(0.14, 2.9, 0.12), Color.WHITE, 8 | 16)


static func shop_win() -> ContentMesh:
	var m := ContentMesh.new()
	_shop_common(m)
	_fq(m, &"WallD", -1.85, 0.0, 1.85, 0.5, 0.0)
	m.quad(&"Window_shop", _v(-1.85, 0.5, 0.2), _v(1.85, 0.5, 0.2), _v(1.85, 2.85, 0.2), _v(-1.85, 2.85, 0.2), Vector3(0, 0, -1), Color.WHITE, Vector2(-1.85, 0.5), Vector2(1.85, 2.85))
	m.quad(&"WallD", _v(-1.85, 0.5, 0.0), _v(-1.85, 0.5, 0.2), _v(-1.85, 2.85, 0.2), _v(-1.85, 2.85, 0.0), Vector3.RIGHT, Color.WHITE)
	m.quad(&"WallD", _v(1.85, 0.5, 0.2), _v(1.85, 0.5, 0.0), _v(1.85, 2.85, 0.0), _v(1.85, 2.85, 0.2), Vector3.LEFT, Color.WHITE)
	m.quad(&"WallD", _v(-1.85, 0.5, 0.0), _v(1.85, 0.5, 0.0), _v(1.85, 0.5, 0.2), _v(-1.85, 0.5, 0.2), Vector3.UP, Color.WHITE)
	m.box(&"Metal", _v(0, 1.7, 0.18), _v(0.06, 2.35, 0.06), C_STEEL_D)
	m.box(&"Metal", _v(0, 1.72, 0.18), _v(3.7, 0.05, 0.06), C_STEEL_D)
	return m


static func shop_door() -> ContentMesh:
	var m := ContentMesh.new()
	_shop_common(m)
	_fq(m, &"WallD", -1.85, 0.0, -0.6, 0.5, 0.0)
	_fq(m, &"WallD", 0.6, 0.0, 1.85, 0.5, 0.0)
	for r in [Vector2(-1.85, -0.6), Vector2(0.6, 1.85)]:
		var rx0: float = r.x
		var rx1: float = r.y
		m.quad(&"Window_shop", _v(rx0, 0.5, 0.2), _v(rx1, 0.5, 0.2), _v(rx1, 2.85, 0.2), _v(rx0, 2.85, 0.2), Vector3(0, 0, -1), Color.WHITE, Vector2(rx0, 0.5), Vector2(rx1, 2.85))
	m.quad(&"Window_shop", _v(-0.6, 0.0, 0.3), _v(0.6, 0.0, 0.3), _v(0.6, 2.85, 0.3), _v(-0.6, 2.85, 0.3), Vector3(0, 0, -1), Color.WHITE, Vector2(-0.6, 0.0), Vector2(0.6, 2.85))
	m.box(&"Metal", _v(0, 1.2, 0.28), _v(0.06, 2.4, 0.06), C_STEEL_D)
	m.box(&"Metal", _v(0, 2.42, 0.28), _v(1.2, 0.06, 0.06), C_STEEL_D)
	m.box(&"Metal", _v(-0.6, 1.4, 0.1), _v(0.07, 2.8, 0.3), C_STEEL_D)
	m.box(&"Metal", _v(0.6, 1.4, 0.1), _v(0.07, 2.8, 0.3), C_STEEL_D)
	m.box(&"V", _v(0, 0.04, -0.12), _v(1.4, 0.08, 0.5), C_CONC, 8)
	return m


## Striped awning; origin at the wall, 2.95 m above the module bottom.
static func awning() -> ContentMesh:
	var m := ContentMesh.new()
	var y_top := 2.95
	var y_lip := 2.45
	var depth := 1.35
	var n := 4
	for i in n:
		var x0 := -2.0 + i * 1.0
		var x1 := x0 + 1.0
		var key: StringName = &"WallB" if i % 2 == 0 else &"Trim"
		m.quad(key, _v(x0, y_top, 0.0), _v(x1, y_top, 0.0), _v(x1, y_lip, -depth), _v(x0, y_lip, -depth), Vector3(0, 0.9, -0.45).normalized(), Color.WHITE)
		m.quad(key, _v(x0, y_lip, -depth), _v(x1, y_lip, -depth), _v(x1, y_lip - 0.22, -depth), _v(x0, y_lip - 0.22, -depth), Vector3(0, 0, -1), Color.WHITE)
		# underside
		m.quad(&"V", _v(x0, y_top - 0.02, 0.0), _v(x0, y_lip - 0.02, -depth), _v(x1, y_lip - 0.02, -depth), _v(x1, y_top - 0.02, 0.0), Vector3.DOWN, C_DARK)
	m.tri(&"WallD", _v(-2.0, y_top, 0), _v(-2.0, y_lip, -depth), _v(-2.0, y_lip - 0.22, -depth), Vector3.LEFT, Color.WHITE)
	m.tri(&"WallD", _v(2.0, y_top, 0), _v(2.0, y_lip, -depth), _v(2.0, y_lip - 0.22, -depth), Vector3.RIGHT, Color.WHITE)
	return m


## Blade sign hanging from a facade (origin on the wall at x=0). Neon on both faces.
static func sign_blade() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"Metal", _v(0, 2.6, -0.4), _v(0.05, 0.05, 0.8), C_STEEL_D)
	m.box(&"V", _v(0, 2.0, -0.85), _v(0.12, 1.6, 0.8), C_DARK)
	for s in [-1.0, 1.0]:
		m.box(&"Neon", _v(s * 0.075, 2.5, -0.85), _v(0.04, 0.12, 0.6))
		m.box(&"Neon", _v(s * 0.075, 2.0, -0.85), _v(0.04, 0.5, 0.12))
		m.box(&"Neon", _v(s * 0.075, 1.5, -0.85), _v(0.04, 0.12, 0.6))
	return m


## Rooftop neon sign (origin centre-bottom, faces -Z), 5 m wide.
static func roof_sign() -> ContentMesh:
	var m := ContentMesh.new()
	for sx in [-2.0, 2.0]:
		m.box(&"Metal", _v(sx, 0.7, 0.0), _v(0.14, 1.4, 0.14), C_STEEL_D)
	m.box(&"V", _v(0, 2.1, 0.05), _v(5.2, 1.6, 0.12), C_DARK, 16)
	m.box(&"Neon", _v(0, 2.7, -0.04), _v(4.4, 0.16, 0.05))
	m.box(&"Neon", _v(0, 1.5, -0.04), _v(4.4, 0.16, 0.05))
	m.box(&"Neon", _v(-1.9, 2.1, -0.04), _v(0.16, 1.2, 0.05))
	m.box(&"Neon", _v(1.9, 2.1, -0.04), _v(0.16, 1.2, 0.05))
	m.box(&"Neon", _v(0, 2.1, -0.04), _v(2.4, 0.5, 0.05))
	return m


# ---- Caps, roofs, posts ---------------------------------------------------------------------------------------------
## Cornice ledge + parapet (origin at the top of the last floor, on the facade plane).
static func cap() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"WallD", _v(0, 0.12, -0.12), _v(4.0, 0.24, 0.62), Color.WHITE, 8 | 1 | 2)
	m.box(&"WallA", _v(0, 0.69, 0.12), _v(4.0, 0.9, 0.24), Color.WHITE, 8 | 1 | 2)
	m.box(&"WallD", _v(0, 1.17, 0.12), _v(4.0, 0.06, 0.32), Color.WHITE, 8 | 1 | 2)
	return m


static func solid() -> ContentMesh:
	var m := ContentMesh.new()
	_fq(m, &"WallA", -2.0, 0.0, 2.0, FH, 0.0)
	_pilasters(m, &"WallD")
	m.box(&"Metal", _v(0.9, 2.5, -0.04), _v(0.9, 0.5, 0.08), C_STEEL, 16)
	for i in 4:
		m.box(&"V", _v(0.9, 2.4 + i * 0.12, -0.09), _v(0.8, 0.04, 0.02), C_DARK, 16)
	return m


static func roof_slab() -> ContentMesh:
	var m := ContentMesh.new()
	m.quad(&"Roof", _v(-0.5, 0, 0.5), _v(0.5, 0, 0.5), _v(0.5, 0, -0.5), _v(-0.5, 0, -0.5), Vector3.UP, Color.WHITE)
	return m


## Unit box (base on y=0, 1 x 1 x 1) in one palette slot - scaled for corner posts / podiums / cores.
static func unit_box(key: StringName) -> ContentMesh:
	var m := ContentMesh.new()
	m.box(key, _v(0, 0.5, 0), _v(1, 1, 1), Color.WHITE, 8)
	return m


static func roof_ac() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"V", _v(0, 0.5, 0), _v(1.5, 1.0, 1.1), C_AC, 8)
	m.cyl(&"V", _v(-0.35, 1.0, 0), 0.4, 0.4, 0.07, 10, C_STEEL_D, true, false, true)
	m.cyl(&"V", _v(0.45, 1.0, 0), 0.25, 0.25, 0.05, 8, C_STEEL_D, true, false, true)
	for i in 4:
		m.box(&"V", _v(0.0, 0.25 + i * 0.18, -0.56), _v(1.2, 0.05, 0.03), C_STEEL_D)
	m.box(&"V", _v(0, 0.08, 0), _v(1.6, 0.16, 1.2), C_STEEL_D, 8)
	return m


static func roof_tank() -> ContentMesh:
	var m := ContentMesh.new()
	for sx in [-0.7, 0.7]:
		for sz in [-0.7, 0.7]:
			m.box(&"Metal", _v(sx, 0.5, sz), _v(0.12, 1.0, 0.12), C_STEEL_D)
	m.box(&"Metal", _v(0, 1.02, 0), _v(1.7, 0.06, 1.7), C_STEEL_D)
	m.cyl(&"V", _v(0, 1.05, 0), 1.0, 1.0, 1.7, 12, Color("#b6683f"), true, false, false)
	m.cyl(&"V", _v(0, 2.75, 0), 1.0, 0.0, 0.55, 12, Color("#7d4a30"), false, false, false)
	m.cyl(&"Metal", _v(0, 1.45, 0), 1.03, 1.03, 0.06, 12, C_STEEL_D, true, false, false)
	m.cyl(&"Metal", _v(0, 2.25, 0), 1.03, 1.03, 0.06, 12, C_STEEL_D, true, false, false)
	return m


static func roof_antenna() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"Metal", _v(0, 0, 0), 0.07, 0.04, 6.0, 6, C_STEEL, true, false, false)
	for i in 3:
		var y := 3.0 + i * 0.9
		m.box(&"Metal", _v(0, y, 0), _v(1.6 - i * 0.4, 0.04, 0.04), C_STEEL)
		m.box(&"Metal", _v(0, y + 0.01, 0), _v(0.04, 0.04, 1.2 - i * 0.3), C_STEEL)
	m.box(&"NeonRed", _v(0, 6.08, 0), _v(0.18, 0.18, 0.18))
	m.box(&"Metal", _v(0, 0.2, 0), _v(0.6, 0.4, 0.6), C_STEEL_D, 8)
	return m


static func roof_stairs() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"WallA", _v(0, 1.4, 0), _v(2.8, 2.8, 2.6), Color.WHITE, 8)
	m.box(&"Roof", _v(0, 2.88, 0), _v(3.1, 0.16, 2.9), Color.WHITE, 8)
	m.box(&"V", _v(0, 1.0, -1.32), _v(1.0, 2.0, 0.06), C_STEEL_D)
	m.box(&"Metal", _v(0.6, 2.4, -1.32), _v(0.4, 0.3, 0.05), C_STEEL)
	return m


static func roof_vent() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"Metal", _v(0, 0, 0), 0.25, 0.25, 1.1, 8, C_STEEL, true, false, false)
	m.cyl(&"Metal", _v(0, 1.1, 0), 0.5, 0.0, 0.3, 8, C_STEEL_D, false, false, false)
	return m


static func helipad() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"V", _v(0, 0, 0), 9.0, 9.0, 0.3, 24, Color("#3b4048"), false, false, true)
	m.cyl(&"V", _v(0, 0.31, 0), 8.2, 8.2, 0.02, 24, Color("#d8d4c8"), false, false, true)
	m.cyl(&"V", _v(0, 0.33, 0), 7.7, 7.7, 0.02, 24, Color("#3b4048"), false, false, true)
	# the H
	m.box(&"V", _v(-1.3, 0.36, 0), _v(0.7, 0.04, 5.0), Color("#f2f0ea"))
	m.box(&"V", _v(1.3, 0.36, 0), _v(0.7, 0.04, 5.0), Color("#f2f0ea"))
	m.box(&"V", _v(0, 0.36, 0), _v(2.0, 0.04, 0.7), Color("#f2f0ea"))
	for i in 16:
		var a := TAU * i / 16.0
		m.box(&"NeonCyan", _v(cos(a) * 8.7, 0.35, sin(a) * 8.7), _v(0.3, 0.12, 0.3))
	# safety net ring
	m.cyl(&"Metal", _v(0, -0.25, 0), 9.4, 9.4, 0.25, 24, C_STEEL_D, false, false, false)
	return m


# ---- Houses ----------------------------------------------------------------------------------------------------------
static func _window_unit(m: ContentMesh, w: float, h: float, uoff: float, y_glass: float) -> void:
	# local frame: front toward -Z, origin = bottom centre of the glass on the wall surface
	m.quad(&"Window_res", _v(-w * 0.5, 0, -0.03), _v(w * 0.5, 0, -0.03), _v(w * 0.5, h, -0.03), _v(-w * 0.5, h, -0.03), Vector3(0, 0, -1), Color.WHITE,
		Vector2(-w * 0.5 + uoff, y_glass), Vector2(w * 0.5 + uoff, y_glass + h))
	var t := 0.09
	m.box(&"Trim", _v(0, -t * 0.5, -0.05), _v(w + t * 2.0, t, 0.1), Color.WHITE, 16)
	m.box(&"Trim", _v(0, h + t * 0.5, -0.05), _v(w + t * 2.0, t, 0.1), Color.WHITE, 16)
	m.box(&"Trim", _v(-w * 0.5 - t * 0.5, h * 0.5, -0.05), _v(t, h, 0.1), Color.WHITE, 16)
	m.box(&"Trim", _v(w * 0.5 + t * 0.5, h * 0.5, -0.05), _v(t, h, 0.1), Color.WHITE, 16)
	m.box(&"Trim", _v(0, h * 0.5, -0.045), _v(0.05, h, 0.06), Color.WHITE, 16)
	m.box(&"Trim", _v(0, -t - 0.02, -0.1), _v(w + 0.35, 0.06, 0.2), Color.WHITE, 16)


static func _door_unit(m: ContentMesh, col: Color, w := 1.0, h := 2.15) -> void:
	m.box(&"V", _v(0, h * 0.5, -0.04), _v(w, h, 0.08), col, 16)
	m.box(&"Trim", _v(0, h + 0.07, -0.06), _v(w + 0.3, 0.14, 0.12), Color.WHITE, 16)
	m.box(&"Trim", _v(-w * 0.5 - 0.08, h * 0.5, -0.06), _v(0.16, h, 0.12), Color.WHITE, 16)
	m.box(&"Trim", _v(w * 0.5 + 0.08, h * 0.5, -0.06), _v(0.16, h, 0.12), Color.WHITE, 16)
	m.box(&"Metal", _v(w * 0.32, 1.0, -0.1), _v(0.06, 0.06, 0.05), C_STEEL)
	m.box(&"V", _v(0, 0.06, -0.55), _v(w + 0.6, 0.12, 1.0), C_CONC, 8)


## Windows along one wall. wall: 0 front(-Z) 1 back(+Z) 2 left(-X) 3 right(+X). centre_x: along-wall coordinate.
static func _wall_window(m: ContentMesh, wall: int, W: float, D: float, along: float, y_bottom: float, w: float, h: float, uidx: int) -> void:
	var pos := Vector3.ZERO
	var n := Vector3.ZERO
	match wall:
		0:
			pos = _v(along, y_bottom, -D * 0.5)
			n = Vector3(0, 0, -1)
		1:
			pos = _v(along, y_bottom, D * 0.5)
			n = Vector3(0, 0, 1)
		2:
			pos = _v(-W * 0.5, y_bottom, along)
			n = Vector3(-1, 0, 0)
		_:
			pos = _v(W * 0.5, y_bottom, along)
			n = Vector3(1, 0, 0)
	m.push(Transform3D(Basis.looking_at(n, Vector3.UP), pos))
	_window_unit(m, w, h, uidx * 8.0, y_bottom)
	m.pop()


static func _gable_roof(m: ContentMesh, key: StringName, col: Color, W: float, D: float, y_eave: float, rise: float, ov: float, gable_key: StringName) -> void:
	var ex := W * 0.5 + 0.3
	var ez := D * 0.5 + ov
	var ey := y_eave - 0.12
	var ridge := y_eave + rise
	var n_front := Vector3(0, ez, -(rise + 0.12)).normalized()
	var n_back := Vector3(0, ez, (rise + 0.12)).normalized()
	m.quad(key, _v(-ex, ey, -ez), _v(ex, ey, -ez), _v(ex, ridge, 0), _v(-ex, ridge, 0), n_front, col)
	m.quad(key, _v(ex, ey, ez), _v(-ex, ey, ez), _v(-ex, ridge, 0), _v(ex, ridge, 0), n_back, col)
	# under-eave soffits
	m.quad(&"V", _v(-ex, ey - 0.02, -ez), _v(ex, ey - 0.02, -ez), _v(ex, ey - 0.02, ez), _v(-ex, ey - 0.02, ez), Vector3.DOWN, Color("#d8d2c4"))
	m.tri(gable_key, _v(-W * 0.5, y_eave, -D * 0.5), _v(-W * 0.5, y_eave, D * 0.5), _v(-W * 0.5, ridge - 0.05, 0), Vector3.LEFT, Color.WHITE)
	m.tri(gable_key, _v(W * 0.5, y_eave, D * 0.5), _v(W * 0.5, y_eave, -D * 0.5), _v(W * 0.5, ridge - 0.05, 0), Vector3.RIGHT, Color.WHITE)
	# end rakes
	m.quad(&"Trim", _v(-ex, ey, -ez), _v(-ex, ridge, 0), _v(-ex, ridge - 0.1, 0), _v(-ex, ey - 0.1, -ez), Vector3.LEFT, Color.WHITE)
	m.quad(&"Trim", _v(-ex, ey, ez), _v(-ex, ridge, 0), _v(-ex, ridge - 0.1, 0), _v(-ex, ey - 0.1, ez), Vector3.LEFT, Color.WHITE)
	m.quad(&"Trim", _v(ex, ey, -ez), _v(ex, ridge, 0), _v(ex, ridge - 0.1, 0), _v(ex, ey - 0.1, -ez), Vector3.RIGHT, Color.WHITE)
	m.quad(&"Trim", _v(ex, ey, ez), _v(ex, ridge, 0), _v(ex, ridge - 0.1, 0), _v(ex, ey - 0.1, ez), Vector3.RIGHT, Color.WHITE)


static func _hip_roof(m: ContentMesh, key: StringName, col: Color, W: float, D: float, y_eave: float, rise: float, ov: float) -> void:
	var ex := W * 0.5 + ov
	var ez := D * 0.5 + ov
	var ey := y_eave - 0.12
	var apex := _v(0, y_eave + rise, 0)
	var c0 := _v(-ex, ey, -ez)
	var c1 := _v(ex, ey, -ez)
	var c2 := _v(ex, ey, ez)
	var c3 := _v(-ex, ey, ez)
	m.tri(key, c0, c1, apex, Vector3(0, ez, -rise).normalized(), col)
	m.tri(key, c1, c2, apex, Vector3(rise, ex, 0).normalized(), col)
	m.tri(key, c2, c3, apex, Vector3(0, ez, rise).normalized(), col)
	m.tri(key, c3, c0, apex, Vector3(-rise, ex, 0).normalized(), col)
	m.quad(&"V", c0, c1, c2, c3, Vector3.DOWN, Color("#d8d2c4"))


static func _chimney(m: ContentMesh, x: float, z: float, y: float, h: float) -> void:
	m.box(&"V", _v(x, y + h * 0.5, z), _v(0.7, h, 0.7), C_BRICK, 8)
	m.box(&"V", _v(x, y + h + 0.06, z), _v(0.9, 0.12, 0.9), C_CONC, 8)


## variant 0..3. Origin: footprint centre at ground level, front toward -Z.
static func house(variant: int) -> ContentMesh:
	var m := ContentMesh.new()
	match variant:
		0:   # single-storey gable bungalow 9 x 7
			var W := 9.0
			var D := 7.0
			var H := 3.0
			m.box(&"WallA", _v(0, H * 0.5 + 0.2, 0), _v(W, H, D), Color.WHITE, 8)
			m.box(&"WallD", _v(0, 0.2, 0), _v(W + 0.2, 0.4, D + 0.2), Color.WHITE, 8)
			_gable_roof(m, &"V", Color("#a4553f"), W, D, H + 0.2, 2.2, 0.55, &"WallA")
			_chimney(m, 2.4, 0.8, H + 0.5, 2.4)
			_wall_window(m, 0, W, D, -2.8, 1.0, 1.3, 1.25, 0)
			_wall_window(m, 0, W, D, 2.8, 1.0, 1.3, 1.25, 1)
			m.push(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), _v(0, 0.2, -D * 0.5)))
			_door_unit(m, Color("#5b3a2a"))
			m.pop()
			_wall_window(m, 1, W, D, -2.5, 1.0, 1.3, 1.25, 2)
			_wall_window(m, 1, W, D, 2.5, 1.0, 1.3, 1.25, 3)
			_wall_window(m, 2, W, D, 0.0, 1.0, 1.3, 1.25, 4)
			_wall_window(m, 3, W, D, 0.0, 1.0, 1.3, 1.25, 5)
		1:   # two-storey hip-roof house 8 x 8
			var W := 8.0
			var D := 8.0
			var H := 6.2
			m.box(&"WallA", _v(0, H * 0.5 + 0.2, 0), _v(W, H, D), Color.WHITE, 8)
			m.box(&"WallD", _v(0, 0.2, 0), _v(W + 0.2, 0.4, D + 0.2), Color.WHITE, 8)
			m.box(&"WallD", _v(0, 3.4, 0), _v(W + 0.12, 0.16, D + 0.12), Color.WHITE, 0)
			_hip_roof(m, &"V", Color("#5d6f86"), W, D, H + 0.2, 2.0, 0.6)
			_chimney(m, -2.0, 1.4, H + 0.2, 1.4)
			var i := 0
			for wall in 4:
				var len_ := W if wall < 2 else D
				for fl in 2:
					var yb := 1.0 + fl * 3.0
					if wall == 0 and fl == 0:
						_wall_window(m, 0, W, D, -2.2, yb, 1.1, 1.3, i)
						i += 1
						continue
					for k in 2:
						_wall_window(m, wall, W, D, (-0.25 + 0.5 * k) * len_ * 0.8, yb, 1.1, 1.3, i)
						i += 1
			m.push(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), _v(1.5, 0.2, -D * 0.5)))
			_door_unit(m, Color("#2f5d7a"))
			m.pop()
		2:   # bungalow with attached garage 12 x 7
			var W := 12.0
			var D := 7.0
			var H := 3.0
			m.box(&"WallA", _v(-1.5, H * 0.5 + 0.2, 0), _v(9.0, H, D), Color.WHITE, 8)
			m.box(&"WallB", _v(4.5, H * 0.5 + 0.2, 0.4), _v(3.0, H - 0.3, D - 0.8), Color.WHITE, 8)
			m.box(&"WallD", _v(-1.5, 0.2, 0), _v(9.2, 0.4, D + 0.2), Color.WHITE, 8)
			_gable_roof(m, &"V", Color("#7c8a6a"), 9.0, D, H + 0.2, 2.0, 0.5, &"WallA")
			m.push(Transform3D(Basis.IDENTITY, _v(-1.5, 0, 0)))
			m.pop()
			# garage roof: simple lean-to slab
			m.box(&"V", _v(4.5, H + 0.18, 0.4), _v(3.4, 0.2, D - 0.2), Color("#7c8a6a"), 8)
			# garage door panels
			for k in 6:
				m.box(&"V", _v(4.5, 0.55 + k * 0.4, 0.4 - (D - 0.8) * 0.5 - 0.03), _v(2.5, 0.34, 0.06), Color("#e6e2d6"), 16)
			_chimney(m, -3.5, 0.5, H + 0.4, 2.0)
			_wall_window(m, 0, W, D, -4.8, 1.0, 1.3, 1.25, 0)
			_wall_window(m, 0, W, D, -0.4, 1.0, 1.3, 1.25, 1)
			m.push(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), _v(-2.6, 0.2, -D * 0.5)))
			_door_unit(m, Color("#8a3b2e"))
			m.pop()
			_wall_window(m, 1, W, D, -4.0, 1.0, 1.3, 1.25, 2)
			_wall_window(m, 1, W, D, 0.0, 1.0, 1.3, 1.25, 3)
			_wall_window(m, 2, W, D, 0.0, 1.0, 1.3, 1.25, 4)
		_:   # modern cube house 9.5 x 8.5
			var W := 9.5
			var D := 8.5
			m.box(&"WallA", _v(0, 1.7, 0), _v(W, 3.0, D), Color.WHITE, 8)
			m.box(&"WallD", _v(0, 0.1, 0), _v(W + 0.1, 0.2, D + 0.1), Color.WHITE, 8)
			m.box(&"WallC", _v(1.2, 4.7, 0.2), _v(7.0, 3.0, 6.5), Color.WHITE, 0)
			m.box(&"Roof", _v(1.2, 6.3, 0.2), _v(7.8, 0.22, 7.3), Color.WHITE, 8)
			m.box(&"Roof", _v(0, 3.3, 0), _v(W + 1.0, 0.2, D + 1.0), Color.WHITE, 4)
			_wall_window(m, 0, W, D, -2.4, 0.9, 2.4, 1.7, 0)
			m.push(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), _v(2.8, 0.2, -D * 0.5)))
			_door_unit(m, Color("#26272b"), 1.1, 2.2)
			m.pop()
			# upper floor windows sit on the set-back volume (front face at z = 0.2 - 3.25)
			for k in 2:
				var x_up := -0.9 + k * 4.2
				m.push(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), _v(x_up, 3.4, 0.2 - 3.25)))
				_window_unit(m, 2.2, 1.7, (1 + k) * 8.0, 3.4)
				m.pop()
			_wall_window(m, 3, W, D, -1.5, 0.9, 2.2, 1.7, 3)
			_wall_window(m, 2, W, D, 1.0, 0.9, 2.2, 1.7, 4)
			_wall_window(m, 1, W, D, 0.0, 0.9, 3.0, 1.7, 5)
	return m


# ---- Industrial ---------------------------------------------------------------------------------------------------------
const IH := 4.5   # industrial module height

static func ind_bay(high_window := false) -> ContentMesh:
	var m := ContentMesh.new()
	_fq(m, &"WallD", -2.0, 0.0, 2.0, IH, 0.0, Color(0.9, 0.9, 0.9))
	for i in 8:
		var x := -1.75 + i * 0.5
		m.box(&"WallD", _v(x, IH * 0.5, -0.03), _v(0.2, IH, 0.06), Color(0.82, 0.82, 0.82), 8 | 16 | 4)
	m.box(&"WallD", _v(0, 0.3, -0.07), _v(4.0, 0.6, 0.14), Color(0.7, 0.7, 0.7), 8 | 16)
	if high_window:
		m.quad(&"Window_industrial", _v(-1.6, 3.0, -0.08), _v(1.6, 3.0, -0.08), _v(1.6, 3.9, -0.08), _v(-1.6, 3.9, -0.08), Vector3(0, 0, -1), Color.WHITE, Vector2(-1.6, 3.0), Vector2(1.6, 3.9))
		m.box(&"V", _v(0, 3.0, -0.1), _v(3.3, 0.08, 0.06), C_STEEL_D)
		m.box(&"V", _v(0, 3.9, -0.1), _v(3.3, 0.08, 0.06), C_STEEL_D)
	return m


static func ind_door() -> ContentMesh:
	var m := ContentMesh.new()
	_fq(m, &"WallD", -2.0, 0.0, -1.7, IH, 0.0, Color(0.9, 0.9, 0.9))
	_fq(m, &"WallD", 1.7, 0.0, 2.0, IH, 0.0, Color(0.9, 0.9, 0.9))
	_fq(m, &"WallD", -1.7, 3.8, 1.7, IH, 0.0, Color(0.9, 0.9, 0.9))
	m.box(&"V", _v(0, 1.9, 0.12), _v(3.4, 3.8, 0.08), Color("#b8bec4"), 0)
	for k in 9:
		m.box(&"V", _v(0, 0.2 + k * 0.42, 0.06), _v(3.4, 0.05, 0.05), Color("#7d848b"), 16)
	m.box(&"V", _v(-1.76, 1.9, -0.05), _v(0.1, 3.8, 0.1), C_STEEL_D)
	m.box(&"V", _v(1.76, 1.9, -0.05), _v(0.1, 3.8, 0.1), C_STEEL_D)
	m.box(&"V", _v(0, 3.86, -0.05), _v(3.6, 0.1, 0.1), C_STEEL_D)
	m.box(&"V", _v(0, 0.2, -0.5), _v(3.0, 0.4, 1.0), C_CONC, 8)
	m.box(&"NeonAmber", _v(1.9, 4.1, -0.04), _v(0.2, 0.1, 0.05))
	return m


static func ind_cap() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"WallD", _v(0, 0.2, -0.04), _v(4.0, 0.4, 0.12), Color(0.76, 0.76, 0.76), 8)
	m.box(&"V", _v(0, 0.46, 0.0), _v(4.0, 0.12, 0.2), C_STEEL_D, 8)
	return m


## Unit gable roof: footprint 1 x 1 centred on origin, ridge along X, rise 1, base at y=0 (scaled by the assembler).
static func gable_unit() -> ContentMesh:
	var m := ContentMesh.new()
	var rise := 1.0
	m.quad(&"Roof", _v(-0.5, 0, -0.5), _v(0.5, 0, -0.5), _v(0.5, rise, 0), _v(-0.5, rise, 0), Vector3(0, 0.5, -rise).normalized(), Color.WHITE)
	m.quad(&"Roof", _v(0.5, 0, 0.5), _v(-0.5, 0, 0.5), _v(-0.5, rise, 0), _v(0.5, rise, 0), Vector3(0, 0.5, rise).normalized(), Color.WHITE)
	m.tri(&"WallD", _v(-0.5, 0, 0.5), _v(-0.5, 0, -0.5), _v(-0.5, rise, 0), Vector3.LEFT, Color.WHITE)
	m.tri(&"WallD", _v(0.5, 0, -0.5), _v(0.5, 0, 0.5), _v(0.5, rise, 0), Vector3.RIGHT, Color.WHITE)
	return m


## Unit half-cylinder roof (hangars): axis along Z, radius 0.5 in X, height 1 (scaled).
static func arch_unit() -> ContentMesh:
	var m := ContentMesh.new()
	var segs := 10
	for i in segs:
		var a0 := PI * float(i) / float(segs)
		var a1 := PI * float(i + 1) / float(segs)
		var p0 := Vector2(cos(a0) * 0.5, sin(a0))
		var p1 := Vector2(cos(a1) * 0.5, sin(a1))
		var nm := Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5) * 0.5, 0).normalized()
		m.quad(&"Roof", _v(p0.x, p0.y, -0.5), _v(p1.x, p1.y, -0.5), _v(p1.x, p1.y, 0.5), _v(p0.x, p0.y, 0.5), nm, Color.WHITE)
		m.tri(&"WallD", _v(0, 0, -0.5), _v(p1.x, p1.y, -0.5), _v(p0.x, p0.y, -0.5), Vector3(0, 0, -1), Color.WHITE)
		m.tri(&"WallD", _v(0, 0, 0.5), _v(p0.x, p0.y, 0.5), _v(p1.x, p1.y, 0.5), Vector3(0, 0, 1), Color.WHITE)
	return m


static func chimney_stack() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"V", _v(0, 0, 0), 1.6, 1.0, 22.0, 10, Color("#a4553f"), false, false, false)
	m.cyl(&"V", _v(0, 20.5, 0), 1.2, 1.2, 0.6, 10, Color("#2a2d33"), false, false, true)
	m.cyl(&"V", _v(0, 10.0, 0), 1.35, 1.35, 0.5, 10, Color("#e6e2d6"), false, false, false)
	m.box(&"NeonRed", _v(0, 22.2, 0), _v(0.3, 0.3, 0.3))
	return m


static func silo() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"V", _v(0, 0, 0), 2.6, 2.6, 9.0, 12, Color("#cfd4d8"), true, false, false)
	m.cyl(&"V", _v(0, 9.0, 0), 2.6, 0.0, 1.8, 12, Color("#8d96a0"), false, false, false)
	for k in 3:
		m.cyl(&"Metal", _v(0, 2.0 + k * 2.6, 0), 2.64, 2.64, 0.1, 12, C_STEEL_D, true, false, false)
	m.box(&"Metal", _v(0, 5.0, -2.75), _v(0.3, 10.0, 0.1), C_STEEL_D)
	return m


static func storage_tank() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"V", _v(0, 0, 0), 4.0, 4.0, 4.5, 14, Color("#e6e2d6"), true, false, true)
	m.cyl(&"V", _v(0, 4.5, 0), 4.0, 3.6, 0.4, 14, Color("#8d96a0"), false, false, true)
	m.box(&"Metal", _v(3.8, 2.3, 0), _v(0.12, 4.6, 0.8), C_STEEL_D)
	return m


static func hangar_door() -> ContentMesh:
	var m := ContentMesh.new()
	# unit-ish door: 1 wide x 1 high, origin bottom-centre, slightly proud of the wall (scaled in X/Y by the assembler)
	m.quad(&"V", _v(-0.5, 0, -0.1), _v(0.5, 0, -0.1), _v(0.5, 1, -0.1), _v(-0.5, 1, -0.1), Vector3(0, 0, -1), Color("#c9ced2"))
	for k in 9:
		m.box(&"V", _v(0, 0.06 + k * 0.11, -0.13), _v(1.0, 0.012, 0.05), Color("#8f979e"), 16)
	m.box(&"V", _v(0, 0.5, -0.15), _v(0.02, 1.0, 0.04), C_STEEL_D, 16)
	m.box(&"V", _v(-0.5, 0.5, -0.12), _v(0.02, 1.02, 0.08), C_STEEL_D, 16)
	m.box(&"V", _v(0.5, 0.5, -0.12), _v(0.02, 1.02, 0.08), C_STEEL_D, 16)
	m.box(&"V", _v(0, 1.0, -0.12), _v(1.04, 0.02, 0.08), C_STEEL_D, 16)
	return m


# ---- Parking structure -------------------------------------------------------------------------------------------------------
static func park_bay() -> ContentMesh:
	var m := ContentMesh.new()
	# open deck edge: parapet wall 1.0 m + slab edge + column; the rest is open so the decks read as a car park
	_fq(m, &"WallA", -2.0, 0.3, 2.0, 1.1, 0.0)
	m.box(&"WallD", _v(0, 0.15, -0.04), _v(4.0, 0.3, 0.1), Color.WHITE, 8 | 16)
	m.box(&"WallD", _v(0, 1.17, -0.02), _v(4.0, 0.08, 0.1), Color.WHITE, 8 | 16)
	m.box(&"WallD", _v(-1.85, 1.8, 0.0), _v(0.3, 3.6, 0.3), Color.WHITE, 8)
	m.box(&"WallD", _v(0, 3.45, 0.0), _v(4.0, 0.3, 0.3), Color.WHITE, 0)
	# dark interior backing so the open bay does not show the far side's sky
	m.quad(&"V", _v(-2.0, 1.1, 0.9), _v(2.0, 1.1, 0.9), _v(2.0, 3.3, 0.9), _v(-2.0, 3.3, 0.9), Vector3(0, 0, -1), Color("#2a2d33"))
	return m
