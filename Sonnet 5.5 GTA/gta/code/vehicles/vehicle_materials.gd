class_name VehicleMaterials
extends RefCounted
## Shared runtime materials for vehicles: paint finishes, glass (clean / cracked / tinted), emissive lamp states, wreck look.
## Materials are cached and SHARED between vehicles; vehicles swap references per surface (Util.replace_material semantics).

const FINISHES: Array[StringName] = [&"gloss", &"matte", &"metallic", &"pearl", &"chrome"]

static var _paint_cache: Dictionary = {}
static var _lamp_cache: Dictionary = {}
static var _glass_cache: Dictionary = {}
static var _wreck: Dictionary = {}
static var _crack_tex: ImageTexture = null


## Paint material for a colour + finish. resource_name stays "Paint" so repeated replace_material calls find it.
static func paint(color: Color, finish: StringName = &"gloss", secondary := false) -> StandardMaterial3D:
	var key := "%s|%s|%d" % [color.to_html(false), finish, 1 if secondary else 0]
	var cached: StandardMaterial3D = _paint_cache.get(key, null)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.resource_name = "Paint2" if secondary else "Paint"
	m.albedo_color = color
	match finish:
		&"matte":
			m.roughness = 0.88
			m.metallic = 0.0
		&"metallic":
			m.roughness = 0.34
			m.metallic = 0.82
			m.clearcoat_enabled = true
			m.clearcoat = 0.35
			m.clearcoat_roughness = 0.18
		&"pearl":
			m.roughness = 0.22
			m.metallic = 0.45
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.05
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.6
		&"chrome":
			m.roughness = 0.08
			m.metallic = 1.0
		_:
			m.roughness = 0.3
			m.metallic = 0.12
			m.clearcoat_enabled = true
			m.clearcoat = 0.55
			m.clearcoat_roughness = 0.12
	_paint_cache[key] = m
	return m


## Glass. state: 0 clean, 1 cracked, 2 shattered (invisible). tint: 0..3 (window tint upgrade level).
static func glass(state: int = 0, tint: int = 0) -> Material:
	var key := "%d|%d" % [state, tint]
	var cached: Material = _glass_cache.get(key, null)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.resource_name = "Glass"
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.metallic = 0.0
	m.metallic_specular = 0.9
	var alpha: float = [0.42, 0.55, 0.72, 0.86][clampi(tint, 0, 3)]
	m.albedo_color = Color(0.07, 0.11, 0.14, alpha)
	match state:
		1:
			m.albedo_texture = _crack_texture()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.9, 0.9, 0.9)
			m.albedo_color = Color(1, 1, 1, 1)
			m.roughness = 0.35
		2:
			m.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_glass_cache[key] = m
	return m


static func _crack_texture() -> ImageTexture:
	if _crack_tex != null:
		return _crack_tex
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.15, 0.19, 0.66))
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var centers: Array[Vector2] = [Vector2(sz * 0.5, sz * 0.5), Vector2(sz * 0.2, sz * 0.7), Vector2(sz * 0.8, sz * 0.25)]
	for c in centers:
		for i in 14:
			var ang := rng.randf() * TAU
			var len_ := rng.randf_range(40.0, 150.0)
			var p := c
			var step := 3.0
			var steps := int(len_ / step)
			for s in steps:
				p += Vector2(cos(ang), sin(ang)) * step
				ang += rng.randf_range(-0.18, 0.18)
				var px := int(p.x) & (sz - 1)
				var py := int(p.y) & (sz - 1)
				img.set_pixel(px, py, Color(0.92, 0.96, 1.0, 0.95))
				img.set_pixel((px + 1) & (sz - 1), py, Color(0.85, 0.9, 0.95, 0.8))
		for r: float in [10.0, 22.0, 38.0]:
			var seg := int(r * 0.9) + 8
			for k in seg:
				var a := float(k) / seg * TAU
				var pp: Vector2 = c + Vector2(cos(a), sin(a)) * (r + rng.randf_range(-1.5, 1.5))
				img.set_pixel(int(pp.x) & (sz - 1), int(pp.y) & (sz - 1), Color(0.9, 0.95, 1.0, 0.85))
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


## Lamp materials. kind: &"head" &"tail" &"amber" &"red" &"blue"; state name per kind.
## head: off/on/xenon; tail: off/low/brake/reverse; amber/red/blue: off/on.
static func lamp(kind: StringName, state: StringName) -> StandardMaterial3D:
	var key := "%s|%s" % [kind, state]
	var cached: StandardMaterial3D = _lamp_cache.get(key, null)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	var base := Color(0.8, 0.8, 0.8)
	var emit := Color.BLACK
	var energy := 0.0
	match kind:
		&"head":
			m.resource_name = "LightHead"
			base = Color(0.86, 0.9, 0.95)
			if state == &"on":
				emit = Color(1.0, 0.94, 0.78)
				energy = 4.0
			elif state == &"xenon":
				emit = Color(0.75, 0.88, 1.0)
				energy = 4.5
		&"tail":
			m.resource_name = "LightTail"
			base = Color(0.42, 0.04, 0.05)
			match state:
				&"low":
					emit = Color(1.0, 0.05, 0.04)
					energy = 1.3
				&"brake":
					emit = Color(1.0, 0.07, 0.05)
					energy = 4.8
				&"reverse":
					base = Color(0.85, 0.85, 0.85)
					emit = Color(1.0, 0.92, 0.9)
					energy = 2.2
		&"amber":
			m.resource_name = "LightAmber"
			base = Color(0.55, 0.32, 0.05)
			if state == &"on":
				emit = Color(1.0, 0.62, 0.12)
				energy = 4.0
		&"red":
			m.resource_name = "LightRed"
			base = Color(0.4, 0.03, 0.03)
			if state == &"on":
				emit = Color(1.0, 0.08, 0.06)
				energy = 6.0
		&"blue":
			m.resource_name = "LightBlue"
			base = Color(0.03, 0.08, 0.4)
			if state == &"on":
				emit = Color(0.1, 0.3, 1.0)
				energy = 6.0
	m.albedo_color = base
	m.roughness = 0.25
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	_lamp_cache[key] = m
	return m


## Garage: lamp material recoloured to `tint` (same states as lamp()). Cached per kind/state/tint.
static var _lamp_tint_cache: Dictionary = {}


static func lamp_tinted(kind: StringName, state: StringName, tint: Color) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [kind, state, tint.to_html(false)]
	var cached: StandardMaterial3D = _lamp_tint_cache.get(key, null)
	if cached != null:
		return cached
	var m: StandardMaterial3D = lamp(kind, state).duplicate() as StandardMaterial3D
	var lit := m.emission_enabled
	m.albedo_color = tint.darkened(0.35) if kind == &"tail" else tint.lerp(Color(0.85, 0.88, 0.9), 0.55)
	if lit:
		m.emission = tint
	elif kind == &"head":
		m.albedo_color = tint.lerp(Color(0.8, 0.82, 0.85), 0.7)
	_lamp_tint_cache[key] = m
	return m


## Burnt wreck look. part: &"paint" &"dark" &"glass"
static func wreck(part: StringName) -> Material:
	var cached: Material = _wreck.get(part, null)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	match part:
		&"paint":
			m.resource_name = "Paint"
			m.albedo_color = Color(0.09, 0.08, 0.075)
			m.roughness = 0.95
			m.metallic = 0.1
		&"glass":
			m.resource_name = "Glass"
			m.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_:
			m.resource_name = "Trim"
			m.albedo_color = Color(0.05, 0.045, 0.04)
			m.roughness = 0.9
	_wreck[part] = m
	return m


## Applies `mat` to every surface whose glTF material is called `mat_name` below root (per-surface override).
static func apply_named(root: Node, mat_name: String, mat: Material) -> int:
	return Util.replace_material(root, mat_name, mat)
