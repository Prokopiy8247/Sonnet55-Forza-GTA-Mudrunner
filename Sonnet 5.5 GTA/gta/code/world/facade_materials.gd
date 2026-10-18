class_name FacadeMaterials
extends RefCounted
## Shared shader materials of the world content (buildings, props, nature). Replaces Blender materials BY NAME
## (WallA..D, Roof, Window, SignalRed/Amber/Green, LampGlow, Neon*, Glass) and builds the generic vertex-colour material.
## Every material here is created once and shared by all instances (few state changes, few draw calls).

const SH_WALL := "res://gta/generated/shaders/building_wall.gdshader"
const SH_WINDOW := "res://gta/generated/shaders/building_window.gdshader"
const SH_FAR := "res://gta/generated/shaders/building_far.gdshader"
const SH_NEON := "res://gta/generated/shaders/building_neon.gdshader"
const SH_SIGNAL := "res://gta/generated/shaders/building_signal.gdshader"
const SH_FOLIAGE := "res://gta/generated/shaders/building_foliage.gdshader"

static var _shaders: Dictionary = {}
static var _mats: Dictionary = {}
static var _hour_mats: Array[ShaderMaterial] = []
static var _name_re: RegEx = null


static func _shader(path: String) -> Shader:
	if _shaders.has(path):
		return _shaders[path]
	var s := load(path) as Shader
	if s == null:
		push_error("FacadeMaterials: shader missing: " + path)
		s = Shader.new()
		s.code = "shader_type spatial;\nvoid fragment(){ ALBEDO = vec3(1.0, 0.0, 1.0); }\n"
	_shaders[path] = s
	return s


static func _cached(key: String, builder: Callable) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial = builder.call()
	m.resource_name = key
	_mats[key] = m
	return m


## Wall slot 0..3 = WallA..WallD, 4 = roof, 5 = trim.
static func wall(slot: int) -> ShaderMaterial:
	return _cached("wall%d" % slot, func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_WALL)
		m.set_shader_parameter("slot", slot)
		if slot == 4:
			m.set_shader_parameter("rough", 0.97)
			m.set_shader_parameter("noise_amount", 0.12)
		return m)


## Merged wall material: the slot (0..5 palette, 6 generic, 7 metal) is baked into the vertex alpha (slot / 8), rgb = colour.
## Every opaque wall / trim / metal / concrete surface of a module is merged into ONE surface with this material.
static func wall_merged() -> ShaderMaterial:
	return _cached("wall_merged", func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_WALL)
		m.set_shader_parameter("vertex_slot", true)
		m.set_shader_parameter("base_color", Color.WHITE)
		m.set_shader_parameter("rough", 0.9)
		m.set_shader_parameter("grime", 0.4)
		return m)


## True when `m` is rendered by the wall shader (can be merged into the vertex-slot surface). Fills slot / colour.
static func wall_info(m: Material) -> Dictionary:
	if not (m is ShaderMaterial):
		return {}
	var sm := m as ShaderMaterial
	if sm.shader == null or sm.shader.resource_path != SH_WALL:
		return {}
	var slot_v: int = int(sm.get_shader_parameter("slot"))
	var col := Color.WHITE
	if slot_v >= 6:
		col = sm.get_shader_parameter("base_color")
		if float(sm.get_shader_parameter("metal")) > 0.4:
			slot_v = 7
	return {"slot": slot_v, "color": col}


## Vertex-colour driven prop material (all colour comes from the mesh COLOR; `tint` multiplies it).
static func vcol(metal := 0.0, rough := 0.85) -> ShaderMaterial:
	return _cached("vcol_%.2f_%.2f" % [metal, rough], func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_WALL)
		m.set_shader_parameter("slot", 6)
		m.set_shader_parameter("base_color", Color.WHITE)
		m.set_shader_parameter("metal", metal)
		m.set_shader_parameter("rough", rough)
		m.set_shader_parameter("grime", 0.25)
		m.set_shader_parameter("noise_amount", 0.04)
		return m)


## Generic coloured material (colour in sRGB) - used for any unknown GLB material name.
static func generic(color: Color, metal := 0.0, rough := 0.85, key := "") -> ShaderMaterial:
	var k := "gen_%s_%.2f_%.2f_%s" % [color.to_html(false), metal, rough, key]
	return _cached(k, func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_WALL)
		m.set_shader_parameter("slot", 6)
		m.set_shader_parameter("base_color", color)
		m.set_shader_parameter("metal", metal)
		m.set_shader_parameter("rough", rough)
		m.set_shader_parameter("grime", 0.25)
		m.set_shader_parameter("noise_amount", 0.04)
		return m)


## Window glass. variants: office (curtain-wall glass), res (apartment / house), shop, industrial, glb (frames are modelled).
static func window(variant: StringName = &"office") -> ShaderMaterial:
	return _cached("window_" + String(variant), func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_WINDOW)
		match variant:
			&"office":
				m.set_shader_parameter("glass_color", Color("#1e4458"))
				m.set_shader_parameter("glass_sky", Color("#86bde2"))
				m.set_shader_parameter("mullion", 0.07)
				m.set_shader_parameter("frame_color", Color("#c6c9cc"))
			&"res":
				m.set_shader_parameter("glass_color", Color("#2a4a63"))
				m.set_shader_parameter("glass_sky", Color("#8fc0da"))
				m.set_shader_parameter("mullion", 0.06)
				m.set_shader_parameter("frame_color", Color("#f2f0ea"))
			&"shop":
				m.set_shader_parameter("glass_color", Color("#25414f"))
				m.set_shader_parameter("glass_sky", Color("#9cc8da"))
				m.set_shader_parameter("mullion", 0.0)
				m.set_shader_parameter("emission_energy", 2.8)
			&"industrial":
				m.set_shader_parameter("glass_color", Color("#34505e"))
				m.set_shader_parameter("glass_sky", Color("#9bbccb"))
				m.set_shader_parameter("mullion", 0.08)
				m.set_shader_parameter("frame_color", Color("#6a727b"))
			_:
				m.set_shader_parameter("mullion", 0.0)
		_hour_mats.append(m)
		return m)


static func far() -> ShaderMaterial:
	return _cached("far", func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_FAR)
		_hour_mats.append(m)
		return m)


static func neon(color: Color, day_energy := 0.9, night_energy := 4.5, hue_from_instance := false, flicker := 0.0) -> ShaderMaterial:
	var k := "neon_%s_%.1f_%.1f_%s_%.1f" % [color.to_html(false), day_energy, night_energy, str(hue_from_instance), flicker]
	return _cached(k, func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_NEON)
		m.set_shader_parameter("neon_color", color)
		m.set_shader_parameter("day_energy", day_energy)
		m.set_shader_parameter("night_energy", night_energy)
		m.set_shader_parameter("hue_from_instance", 1.0 if hue_from_instance else 0.0)
		m.set_shader_parameter("flicker", flicker)
		return m)


## Blank billboard faces (BillboardFace): two-hue neon art that glows at night, hue chosen per instance.
static func billboard() -> ShaderMaterial:
	return _cached("billboard", func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_NEON)
		m.set_shader_parameter("neon_color", Color("#ff3d9a"))
		m.set_shader_parameter("hue_from_instance", 1.0)
		m.set_shader_parameter("pattern", 1.0)
		m.set_shader_parameter("day_energy", 0.6)
		m.set_shader_parameter("night_energy", 1.05)
		return m)


static func lamp_glow() -> ShaderMaterial:
	return neon(Color("#ffe2a8"), 0.25, 6.0)


## lens 1 red / 2 amber / 3 green.
static func signal_lens(lens: int) -> ShaderMaterial:
	return _cached("signal%d" % lens, func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_SIGNAL)
		m.set_shader_parameter("lens", lens)
		var c: Color = [Color("#ff2a22"), Color("#ffb347"), Color("#38ff80")][lens - 1]
		m.set_shader_parameter("lens_color", c)
		return m)


## Foliage (tree / bush / grass) material. kind: tree, grass (stronger sway), rock-like use vcol().
static func foliage(kind: StringName = &"tree") -> ShaderMaterial:
	return _cached("foliage_" + String(kind), func() -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = _shader(SH_FOLIAGE)
		match kind:
			&"grass":
				m.set_shader_parameter("sway", 0.16)
				m.set_shader_parameter("sway_speed", 2.1)
			&"palm":
				m.set_shader_parameter("sway", 0.12)
				m.set_shader_parameter("sway_speed", 1.1)
			&"reed":
				m.set_shader_parameter("sway", 0.2)
				m.set_shader_parameter("sway_speed", 1.7)
			&"rigid":
				m.set_shader_parameter("sway", 0.0)
			_:
				m.set_shader_parameter("sway", 0.06)
		return m)


static func glass() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.resource_name = "glass"
	m.albedo_color = Color(0.35, 0.6, 0.72, 0.32)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = m
	return m


## Strip Blender duplicate suffixes: "WallA.001" / "WallA_001" -> "WallA".
static func base_name(mat_name: String) -> String:
	if _name_re == null:
		_name_re = RegEx.new()
		_name_re.compile("^(.+?)[._]\\d{3}$")
	var r := _name_re.search(mat_name)
	return r.get_string(1) if r != null else mat_name


## Maps a GLB material (by NAME) to the shared runtime material. `src` is the imported material (may be null).
static func for_glb(mat_name: String, src: Material = null) -> Material:
	var b := base_name(mat_name)
	match b:
		"WallA": return wall(0)
		"WallB": return wall(1)
		"WallC": return wall(2)
		"WallD": return wall(3)
		"Roof": return wall(4)
		"Window": return window(&"glb")
		"SignalRed": return signal_lens(1)
		"SignalAmber": return signal_lens(2)
		"SignalGreen": return signal_lens(3)
		"LampGlow": return lamp_glow()
		"Glass": return glass()
		"BillboardFace", "NeonBillboard", "NeonAd": return billboard()
	var col := Color(0.6, 0.6, 0.6)
	var metal := 0.0
	var rough := 0.85
	var emissive := false
	var emit_col := Color.WHITE
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		col = bm.albedo_color
		col.a = 1.0
		metal = bm.metallic
		rough = bm.roughness
		if bm.emission_enabled:
			emissive = true
			emit_col = bm.emission
	if b.begins_with("Neon") or b.begins_with("Sign") or (emissive and b.begins_with("Light")):
		return neon(emit_col if emissive else col)
	if b.begins_with("RoofTile"):
		return generic(col, 0.0, 0.9, "roof")
	return generic(col, metal, rough, b)


## Window materials need the game clock to decide when the lights go out.
static func set_hour(hour: float) -> void:
	for m in _hour_mats:
		if is_instance_valid(m):
			m.set_shader_parameter("hour", hour)


static func debug_count() -> int:
	return _mats.size()
