class_name ContentProps
extends RefCounted
## Code-built FALLBACK meshes for the street furniture (used only while the Blender props GLBs are missing).
## Conventions like the Blender props: origin = footprint centre on the ground, front toward -Z, metres.
## Surface keys -> runtime materials (see ContentLib._default_materials): V / Metal (vertex colour), LampGlow, SignalRed/Amber/Green,
## Neon (hue from instance), NeonMagenta / NeonCyan / NeonAmber, Glass.

const C_POLE := Color("#4b525b")
const C_STEEL := Color("#8d96a0")
const C_DARK := Color("#2a2d33")
const C_RED := Color("#d93a3a")
const C_WHITE := Color("#f2f0ea")
const C_ORANGE := Color("#ee8a2b")
const C_GREEN := Color("#4f9d52")
const C_WOOD := Color("#8a5a3b")
const C_YELLOW := Color("#f2cf3a")


static func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


## Flat disc / regular polygon in the XY plane facing -Z (sign plates).
static func _disc(m: ContentMesh, key: StringName, center: Vector3, r: float, segs: int, col: Color, phase := 0.0) -> void:
	for i in segs:
		var a0 := phase + TAU * float(i) / float(segs)
		var a1 := phase + TAU * float(i + 1) / float(segs)
		m.tri(key, center, center + _v(cos(a0) * r, sin(a0) * r, 0), center + _v(cos(a1) * r, sin(a1) * r, 0), Vector3(0, 0, -1), col)


static func lamp() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"Metal", _v(0, 0, 0), 0.2, 0.2, 0.18, 8, C_POLE, false, false, true)
	m.cyl(&"Metal", _v(0, 0.18, 0), 0.12, 0.07, 6.2, 8, C_POLE, true, false, true)
	# curved arm toward the road (-Z)
	m.box(&"Metal", _v(0, 6.3, -0.35), _v(0.09, 0.09, 0.9), C_POLE, 0)
	m.box(&"Metal", _v(0, 6.42, -1.0), _v(0.09, 0.09, 0.6), C_POLE, 0)
	m.box(&"Metal", _v(0, 6.52, -1.55), _v(0.45, 0.14, 1.0), C_STEEL, 8)
	m.box(&"LampGlow", _v(0, 6.44, -1.55), _v(0.38, 0.03, 0.85), Color.WHITE, 4 | 1 | 2 | 16 | 32)
	return m


## Pole + signal head facing -Z (3 lenses) + pedestrian head. Lens keys switch emission through the instance custom data.
static func signal_pole() -> ContentMesh:
	var m := ContentMesh.new()
	# pole at the origin, mast arm to +X across the road (the heads face -Z toward the oncoming traffic) - same layout as the Blender prop
	m.cyl(&"Metal", _v(0, 0, 0), 0.13, 0.13, 0.25, 8, C_POLE, false, false, true)
	m.cyl(&"Metal", _v(0, 0.25, 0), 0.09, 0.07, 5.0, 8, C_POLE, true, false, true)
	m.box(&"Metal", _v(2.0, 5.1, 0), _v(4.0, 0.1, 0.1), C_POLE)
	var hx := 3.2
	m.box(&"V", _v(hx, 4.5, 0), _v(0.34, 1.05, 0.3), C_DARK)
	m.box(&"V", _v(hx, 4.5, 0.2), _v(0.7, 1.25, 0.08), C_DARK)
	var ys := [4.82, 4.5, 4.18]
	var keys: Array[StringName] = [&"SignalRed", &"SignalAmber", &"SignalGreen"]
	for i in 3:
		m.quad(keys[i], _v(hx - 0.11, ys[i] - 0.11, -0.155), _v(hx + 0.11, ys[i] - 0.11, -0.155), _v(hx + 0.11, ys[i] + 0.11, -0.155), _v(hx - 0.11, ys[i] + 0.11, -0.155), Vector3(0, 0, -1), Color.WHITE)
		m.box(&"V", _v(hx, ys[i] + 0.14, -0.2), _v(0.3, 0.04, 0.12), C_DARK)
	# second head on the pole at eye height for the stop line
	m.box(&"V", _v(0, 3.6, -0.05), _v(0.26, 0.72, 0.22), C_DARK)
	for i in 3:
		var y := 3.8 - i * 0.22
		m.quad(keys[i], _v(-0.08, y - 0.08, -0.17), _v(0.08, y - 0.08, -0.17), _v(0.08, y + 0.08, -0.17), _v(-0.08, y + 0.08, -0.17), Vector3(0, 0, -1), Color.WHITE)
	m.box(&"V", _v(0.12, 1.2, -0.12), _v(0.12, 0.2, 0.08), C_YELLOW)
	return m


static func sign_stop() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"Metal", _v(0, 0, 0), 0.04, 0.04, 2.5, 6, C_STEEL, true, false, true)
	_disc(m, &"V", _v(0, 2.2, -0.06), 0.33, 8, C_WHITE, PI / 8.0)
	_disc(m, &"V", _v(0, 2.2, -0.065), 0.29, 8, C_RED, PI / 8.0)
	m.box(&"V", _v(0, 2.2, -0.075), _v(0.36, 0.07, 0.01), C_WHITE)
	m.box(&"V", _v(0, 2.2, -0.0), _v(0.5, 0.5, 0.02), C_DARK, 16 | 32)
	return m


static func sign_speed() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"Metal", _v(0, 0, 0), 0.04, 0.04, 2.5, 6, C_STEEL, true, false, true)
	_disc(m, &"V", _v(0, 2.2, -0.06), 0.32, 14, C_RED)
	_disc(m, &"V", _v(0, 2.2, -0.065), 0.25, 14, C_WHITE)
	m.box(&"V", _v(-0.07, 2.2, -0.075), _v(0.07, 0.3, 0.01), C_DARK)
	m.box(&"V", _v(0.08, 2.2, -0.075), _v(0.07, 0.3, 0.01), C_DARK)
	m.box(&"V", _v(0, 2.2, 0.0), _v(0.5, 0.5, 0.02), C_DARK, 16 | 32)
	return m


static func hydrant() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"V", _v(0, 0, 0), 0.2, 0.2, 0.08, 8, C_RED.darkened(0.2), false, false, true)
	m.cyl(&"V", _v(0, 0.08, 0), 0.15, 0.13, 0.58, 8, C_RED, true, false, true)
	m.blob(&"V", _v(0, 0.7, 0), Vector3(0.15, 0.1, 0.15), C_RED.lightened(0.1), 3, 0.0, 0)
	m.cyl(&"V", _v(0, 0.78, 0), 0.05, 0.05, 0.05, 6, C_STEEL, false, false, true)
	for s in [-1.0, 1.0]:
		m.push(Transform3D(Basis(Vector3.BACK, PI * 0.5 * s), _v(s * 0.13, 0.46, 0)))
		m.cyl(&"V", _v(0, 0, 0), 0.06, 0.06, 0.12, 6, C_STEEL, false, false, true)
		m.pop()
	m.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), _v(0, 0.4, -0.12)))
	m.cyl(&"V", _v(0, 0, 0), 0.07, 0.07, 0.1, 6, C_STEEL, false, false, true)
	m.pop()
	return m


static func bench() -> ContentMesh:
	var m := ContentMesh.new()
	for i in 3:
		m.box(&"V", _v(0, 0.46, 0.14 - i * 0.14), _v(1.8, 0.05, 0.12), C_WOOD)
	for i in 2:
		m.box(&"V", _v(0, 0.72 + i * 0.16, 0.29), _v(1.8, 0.12, 0.04), C_WOOD)
	for sx in [-0.8, 0.8]:
		m.box(&"Metal", _v(sx, 0.23, 0.0), _v(0.06, 0.46, 0.5), C_DARK)
		m.box(&"Metal", _v(sx, 0.62, 0.27), _v(0.06, 0.8, 0.06), C_DARK)
		m.box(&"Metal", _v(sx, 0.55, 0.0), _v(0.08, 0.04, 0.5), C_DARK)
	return m


static func bin() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"V", _v(0, 0, 0), 0.26, 0.3, 0.85, 10, C_GREEN.darkened(0.15), true, false, false)
	m.cyl(&"V", _v(0, 0.85, 0), 0.32, 0.3, 0.06, 10, C_DARK, true, false, true)
	m.cyl(&"Metal", _v(0, 0.35, 0), 0.31, 0.31, 0.04, 10, C_STEEL, true, false, false)
	m.cyl(&"Metal", _v(0, 0.62, 0), 0.305, 0.305, 0.04, 10, C_STEEL, true, false, false)
	return m


static func bollard() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"Metal", _v(0, 0, 0), 0.11, 0.11, 0.9, 8, C_STEEL, true, false, false)
	m.blob(&"Metal", _v(0, 0.9, 0), Vector3(0.11, 0.07, 0.11), C_STEEL.lightened(0.1), 5, 0.0, 0)
	m.cyl(&"V", _v(0, 0.55, 0), 0.115, 0.115, 0.1, 8, C_YELLOW, true, false, false)
	return m


static func bus_stop() -> ContentMesh:
	var m := ContentMesh.new()
	# shelter roof + posts + glass back + bench + route sign pole
	m.box(&"V", _v(0, 2.55, 0.1), _v(3.4, 0.1, 1.6), C_DARK)
	m.box(&"Metal", _v(0, 2.62, 0.1), _v(3.5, 0.04, 1.7), C_STEEL)
	for sx in [-1.6, 1.6]:
		m.box(&"Metal", _v(sx, 1.25, 0.75), _v(0.07, 2.5, 0.07), C_POLE)
		m.box(&"Metal", _v(sx, 1.25, -0.5), _v(0.07, 2.5, 0.07), C_POLE)
	m.box(&"Glass", _v(0, 1.35, 0.78), _v(3.1, 2.1, 0.03), Color.WHITE)
	m.box(&"Glass", _v(-1.6, 1.35, 0.15), _v(0.03, 2.1, 1.2), Color.WHITE)
	m.box(&"V", _v(0, 0.48, 0.55), _v(2.6, 0.06, 0.4), C_WOOD)
	m.box(&"Metal", _v(-1.0, 0.24, 0.55), _v(0.06, 0.48, 0.36), C_DARK)
	m.box(&"Metal", _v(1.0, 0.24, 0.55), _v(0.06, 0.48, 0.36), C_DARK)
	# advertising panel with a cyan glow strip
	m.box(&"V", _v(1.35, 1.25, 0.72), _v(0.5, 0.9, 0.05), C_DARK)
	m.box(&"NeonCyan", _v(1.35, 1.25, 0.69), _v(0.4, 0.8, 0.02))
	# stop sign pole beside the shelter
	m.cyl(&"Metal", _v(2.1, 0, -0.3), 0.04, 0.04, 2.6, 6, C_STEEL, true, false, true)
	_disc(m, &"V", _v(2.1, 2.45, -0.36), 0.22, 12, C_YELLOW)
	m.box(&"V", _v(2.1, 2.45, -0.3), _v(0.4, 0.4, 0.02), C_DARK, 16 | 32)
	return m


static func cone() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"V", _v(0, 0.025, 0), _v(0.42, 0.05, 0.42), C_ORANGE.darkened(0.3), 8)
	m.cyl(&"V", _v(0, 0.05, 0), 0.16, 0.045, 0.62, 10, C_ORANGE, true, false, true)
	m.cyl(&"V", _v(0, 0.30, 0), 0.118, 0.1, 0.12, 10, C_WHITE, true, false, false)
	return m


static func barrier() -> ContentMesh:
	var m := ContentMesh.new()
	for sx in [-0.55, 0.55]:
		m.box(&"Metal", _v(sx, 0.05, 0), _v(0.08, 0.1, 0.6), C_DARK)
		m.box(&"Metal", _v(sx, 0.4, 0), _v(0.06, 0.8, 0.06), C_DARK)
	m.box(&"V", _v(0, 0.58, 0), _v(1.5, 0.22, 0.05), C_WHITE)
	m.box(&"V", _v(-0.5, 0.58, -0.005), _v(0.25, 0.22, 0.05), C_RED)
	m.box(&"V", _v(0.0, 0.58, -0.005), _v(0.25, 0.22, 0.05), C_RED)
	m.box(&"V", _v(0.5, 0.58, -0.005), _v(0.25, 0.22, 0.05), C_RED)
	m.box(&"V", _v(0, 0.28, 0), _v(1.5, 0.2, 0.05), C_WHITE)
	m.box(&"V", _v(-0.25, 0.28, -0.005), _v(0.25, 0.2, 0.05), C_RED)
	m.box(&"V", _v(0.25, 0.28, -0.005), _v(0.25, 0.2, 0.05), C_RED)
	m.box(&"NeonAmber", _v(0, 0.88, 0), _v(0.12, 0.1, 0.12))
	return m


## 3 m chain-link segment.
static func fence() -> ContentMesh:
	var m := ContentMesh.new()
	for sx in [-1.5, 0.0, 1.5]:
		m.box(&"Metal", _v(sx, 0.9, 0), _v(0.07, 1.8, 0.07), C_STEEL)
	m.box(&"Metal", _v(0, 1.78, 0), _v(3.0, 0.05, 0.05), C_STEEL)
	m.box(&"Metal", _v(0, 0.12, 0), _v(3.0, 0.04, 0.04), C_STEEL)
	for i in 13:
		m.box(&"Metal", _v(-1.4 + i * 0.2333, 0.95, 0), _v(0.02, 1.6, 0.02), C_STEEL.darkened(0.1))
	for j in 5:
		m.box(&"Metal", _v(0, 0.35 + j * 0.34, 0), _v(3.0, 0.018, 0.018), C_STEEL.darkened(0.1))
	return m


static func utility_box() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"V", _v(0, 0.65, 0), _v(0.85, 1.3, 0.5), Color("#7e8f87"), 8)
	m.box(&"V", _v(0, 1.33, 0), _v(0.95, 0.08, 0.6), Color("#5f6d67"), 8)
	m.box(&"V", _v(0, 0.55, -0.255), _v(0.7, 1.0, 0.02), Color("#6b7a73"), 16)
	m.box(&"Metal", _v(0.28, 0.6, -0.27), _v(0.05, 0.2, 0.03), C_DARK)
	return m


static func mailbox() -> ContentMesh:
	var m := ContentMesh.new()
	m.box(&"Metal", _v(0, 0.55, 0.0), _v(0.08, 1.1, 0.08), C_DARK)
	m.box(&"V", _v(0, 1.18, 0), _v(0.5, 0.36, 0.34), Color("#2f6fd6"), 8)
	m.cyl(&"V", _v(0, 1.36, 0), 0.17, 0.17, 0.0, 8, Color("#2f6fd6"), true, false, true)
	m.box(&"V", _v(0, 1.2, -0.175), _v(0.34, 0.06, 0.01), C_DARK)
	return m


static func parking_meter() -> ContentMesh:
	var m := ContentMesh.new()
	m.cyl(&"Metal", _v(0, 0, 0), 0.04, 0.04, 1.15, 6, C_STEEL, true, false, true)
	m.box(&"V", _v(0, 1.28, 0), _v(0.2, 0.26, 0.14), Color("#3a4a5e"))
	m.box(&"NeonCyan", _v(0, 1.32, -0.075), _v(0.12, 0.08, 0.01))
	return m


static func _billboard_face(m: ContentMesh) -> void:
	# coloured panel + neon trim + neon art bars on the -Z face (hue chosen per instance)
	m.box(&"V", _v(0, 7.6, 0.09), _v(7.6, 2.8, 0.04), Color("#e6e2d6"), 0)
	m.box(&"Neon", _v(0, 9.1, 0.06), _v(8.0, 0.14, 0.1))
	m.box(&"Neon", _v(0, 6.1, 0.06), _v(8.0, 0.14, 0.1))
	m.box(&"Neon", _v(-3.95, 7.6, 0.06), _v(0.14, 3.2, 0.1))
	m.box(&"Neon", _v(3.95, 7.6, 0.06), _v(0.14, 3.2, 0.1))
	m.box(&"Neon", _v(-1.2, 7.7, 0.05), _v(3.6, 0.7, 0.05))
	m.box(&"Neon", _v(2.2, 7.1, 0.05), _v(1.8, 0.4, 0.05))
	m.box(&"Neon", _v(-2.4, 6.8, 0.05), _v(1.2, 0.3, 0.05))


static func billboard() -> ContentMesh:
	var m := ContentMesh.new()
	for sx in [-3.2, 3.2]:
		m.cyl(&"Metal", _v(sx, 0, 0.2), 0.22, 0.18, 6.0, 8, C_POLE, true, false, true)
	m.box(&"Metal", _v(0, 6.2, 0.25), _v(8.4, 0.25, 0.3), C_POLE)
	m.box(&"V", _v(0, 7.6, 0.2), _v(8.0, 3.2, 0.18), C_DARK)
	_billboard_face(m)
	# the same art on the back (a billboard is seen from both sides)
	m.push(Transform3D(Basis(Vector3.UP, PI), _v(0, 0, 0.4)))
	_billboard_face(m)
	m.pop()
	# service catwalk + lamps
	m.box(&"Metal", _v(0, 6.35, -0.2), _v(8.0, 0.06, 0.7), C_STEEL)
	for i in 4:
		m.box(&"LampGlow", _v(-3.0 + i * 2.0, 9.4, -0.1), _v(0.3, 0.1, 0.3))
	return m
