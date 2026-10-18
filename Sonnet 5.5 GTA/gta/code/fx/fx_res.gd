class_name FxRes
extends RefCounted
## Shared, lazily-built VFX resources (procedural textures, meshes, materials). Everything is generated in code:
## the project has no image textures. All getters are static and cached, so any module can use them
## (WeaponModel muzzle flashes, FxManager particles, decals, projectile trails ...).

static var _tex: Dictionary = {}
static var _mat: Dictionary = {}
static var _mesh: Dictionary = {}


static func warm_up() -> void:
	soft_tex(); ring_tex(); star_tex(); flame_tex(); hole_tex(); glass_tex(); scorch_tex(); blood_tex()
	quad(); box(); flash_mat(); smoke_mat(); spark_mat(); chip_mat(); tracer_mat()


# ------------------------------------------------------------------------------------------------ meshes
static func quad() -> QuadMesh:
	if not _mesh.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		_mesh["quad"] = q
	return _mesh["quad"]


static func box() -> BoxMesh:
	if not _mesh.has("box"):
		var b := BoxMesh.new()
		b.size = Vector3(1, 1, 1)
		_mesh["box"] = b
	return _mesh["box"]


## Low-poly (faceted) sphere for fire cores / shockwaves. Unit radius.
static func facet_sphere() -> SphereMesh:
	if not _mesh.has("facet_sphere"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 10
		s.rings = 5
		_mesh["facet_sphere"] = s
	return _mesh["facet_sphere"]


## Thin box used as a spark streak (aligned to the particle velocity). Long axis = Y.
static func streak_mesh() -> BoxMesh:
	if not _mesh.has("streak"):
		var b := BoxMesh.new()
		b.size = Vector3(0.011, 0.15, 0.011)
		_mesh["streak"] = b
	return _mesh["streak"]


## Flat quad lying on the XZ plane facing +Y (for shockwave rings / ground scorch glows).
static func ground_quad() -> QuadMesh:
	if not _mesh.has("ground_quad"):
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.orientation = PlaneMesh.FACE_Y
		_mesh["ground_quad"] = q
	return _mesh["ground_quad"]


# ------------------------------------------------------------------------------------------------ textures
## Soft round blob (white, alpha falls off to the edge).
static func soft_tex() -> Texture2D:
	if not _tex.has("soft"):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_tex["soft"] = t
	return _tex["soft"]


static func _new_img(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func ring_tex() -> Texture2D:
	if not _tex.has("ring"):
		var n := 128
		var img := _new_img(n)
		for y in n:
			for x in n:
				var u := (float(x) + 0.5) / n * 2.0 - 1.0
				var v := (float(y) + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var a := clampf(1.0 - absf(r - 0.82) / 0.16, 0.0, 1.0)
				a *= clampf((1.0 - r) * 8.0 + 0.2, 0.0, 1.0) if r > 0.82 else 1.0
				a = a * a * (3.0 - 2.0 * a)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_tex["ring"] = ImageTexture.create_from_image(img)
	return _tex["ring"]


## 4-point muzzle star (white hot centre, long vertical/horizontal spikes).
static func star_tex() -> Texture2D:
	if not _tex.has("star"):
		var n := 64
		var img := _new_img(n)
		for y in n:
			for x in n:
				var u := absf((float(x) + 0.5) / n * 2.0 - 1.0)
				var v := absf((float(y) + 0.5) / n * 2.0 - 1.0)
				var r := sqrt(u * u + v * v)
				var core := clampf(1.0 - r * 2.6, 0.0, 1.0)
				var spike_a := clampf(1.0 - v * 9.0, 0.0, 1.0) * clampf(1.0 - u * 1.05, 0.0, 1.0)
				var spike_b := clampf(1.0 - u * 9.0, 0.0, 1.0) * clampf(1.0 - v * 1.05, 0.0, 1.0)
				var diag := clampf(1.0 - absf(u - v) * 7.0, 0.0, 1.0) * clampf(1.0 - r * 1.3, 0.0, 1.0) * 0.6
				var a := clampf(maxf(maxf(core, spike_a), maxf(spike_b, diag)), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_tex["star"] = ImageTexture.create_from_image(img)
	return _tex["star"]


## Flame cone for the muzzle flash planes: u (x) runs from the muzzle (left, 0) to the tip (right, 1).
static func flame_tex() -> Texture2D:
	if not _tex.has("flame"):
		var w := 64
		var h := 32
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in h:
			for x in w:
				var u := (float(x) + 0.5) / w
				var v := absf((float(y) + 0.5) / h * 2.0 - 1.0)
				var width := (1.0 - u) * 0.9 + 0.08
				var a := clampf(1.0 - v / maxf(width, 0.01), 0.0, 1.0)
				a *= clampf(1.0 - u * 0.85, 0.0, 1.0)
				a = pow(a, 0.8)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_tex["flame"] = ImageTexture.create_from_image(img)
	return _tex["flame"]


static func hole_tex() -> Texture2D:
	if not _tex.has("hole"):
		var n := 64
		var img := _new_img(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var cracks: Array[float] = []
		for i in 6:
			cracks.append(rng.randf() * TAU)
		for y in n:
			for x in n:
				var u := (float(x) + 0.5) / n * 2.0 - 1.0
				var v := (float(y) + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var ang := atan2(v, u)
				var hole := clampf(1.0 - r * 4.2, 0.0, 1.0)
				var halo := clampf(1.0 - r * 1.25, 0.0, 1.0) * 0.38
				var crack := 0.0
				for ca in cracks:
					var d := absf(wrapf(ang - ca, -PI, PI))
					crack = maxf(crack, clampf(1.0 - d * r * 14.0, 0.0, 1.0) * clampf(1.0 - r * 1.35, 0.0, 1.0) * 0.8)
				var a := clampf(maxf(hole * 1.6, maxf(halo, crack)), 0.0, 1.0)
				img.set_pixel(x, y, Color(0.04, 0.04, 0.05, a))
		_tex["hole"] = ImageTexture.create_from_image(img)
	return _tex["hole"]


static func glass_tex() -> Texture2D:
	if not _tex.has("glass"):
		var n := 96
		var img := _new_img(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		var rays: Array[float] = []
		for i in 9:
			rays.append(rng.randf() * TAU)
		for y in n:
			for x in n:
				var u := (float(x) + 0.5) / n * 2.0 - 1.0
				var v := (float(y) + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var ang := atan2(v, u)
				var a := clampf(1.0 - r * 6.0, 0.0, 1.0) * 0.9
				for ra in rays:
					var d := absf(wrapf(ang - ra, -PI, PI))
					a = maxf(a, clampf(1.0 - d * r * 20.0, 0.0, 1.0) * clampf(1.0 - r * 1.05, 0.0, 1.0) * 0.85)
				# concentric ring cracks
				for k in 3:
					var rr := 0.28 + 0.24 * k
					a = maxf(a, clampf(1.0 - absf(r - rr) * 26.0, 0.0, 1.0) * clampf(1.0 - r * 1.1, 0.0, 1.0) * 0.4)
				img.set_pixel(x, y, Color(0.92, 0.97, 1.0, clampf(a, 0.0, 1.0)))
		_tex["glass"] = ImageTexture.create_from_image(img)
	return _tex["glass"]


static func scorch_tex() -> Texture2D:
	if not _tex.has("scorch"):
		var n := 128
		var img := _new_img(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for y in n:
			for x in n:
				var u := (float(x) + 0.5) / n * 2.0 - 1.0
				var v := (float(y) + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var ang := atan2(v, u)
				var ragged := 0.84 + 0.07 * sin(ang * 5.0 + 1.3) + 0.04 * sin(ang * 11.0)
				var a := clampf((ragged - r) * 3.2, 0.0, 1.0)
				a *= 0.9 - 0.35 * clampf(r, 0.0, 1.0)
				a *= 0.85 + 0.15 * rng.randf()
				img.set_pixel(x, y, Color(0.02, 0.02, 0.02, clampf(a, 0.0, 1.0)))
		_tex["scorch"] = ImageTexture.create_from_image(img)
	return _tex["scorch"]


static func blood_tex() -> Texture2D:
	if not _tex.has("blood"):
		var n := 64
		var img := _new_img(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var blobs: Array[Vector3] = []
		for i in 7:
			blobs.append(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(0.12, 0.34)))
		for y in n:
			for x in n:
				var u := (float(x) + 0.5) / n * 2.0 - 1.0
				var v := (float(y) + 0.5) / n * 2.0 - 1.0
				var a := clampf(1.0 - sqrt(u * u + v * v) * 3.0, 0.0, 1.0)
				for b in blobs:
					var d := sqrt((u - b.x) * (u - b.x) + (v - b.y) * (v - b.y))
					a = maxf(a, clampf((b.z - d) * 9.0, 0.0, 1.0))
				img.set_pixel(x, y, Color(0.55, 0.04, 0.05, clampf(a, 0.0, 1.0) * 0.85))
		_tex["blood"] = ImageTexture.create_from_image(img)
	return _tex["blood"]


# ------------------------------------------------------------------------------------------------ materials
## Additive, unshaded, double-sided (muzzle flash planes / fire cores). Uses vertex colour * albedo texture.
static func flash_mat() -> StandardMaterial3D:
	if not _mat.has("flash"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = flame_tex()
		m.albedo_color = Color(1.0, 0.82, 0.45, 1.0)
		m.disable_receive_shadows = true
		m.no_depth_test = false
		_mat["flash"] = m
	return _mat["flash"]


static func star_mat() -> StandardMaterial3D:
	if not _mat.has("star"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = star_tex()
		m.albedo_color = Color(1.0, 0.9, 0.6, 1.0)
		_mat["star"] = m
	return _mat["star"]


## Alpha-blended particle material (smoke, dust, blood, water). Colour comes from the particle colour ramp.
static func smoke_mat() -> StandardMaterial3D:
	if not _mat.has("smoke"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.albedo_texture = soft_tex()
		m.disable_receive_shadows = true
		_mat["smoke"] = m
	return _mat["smoke"]


## Additive particle material (sparks, fire puffs, glints).
static func spark_mat() -> StandardMaterial3D:
	if not _mat.has("spark"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.albedo_texture = soft_tex()
		_mat["spark"] = m
	return _mat["spark"]


## Lit solid chunks (debris, glass shards, dirt clumps) coloured by particle colour.
static func chip_mat() -> StandardMaterial3D:
	if not _mat.has("chip"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat["chip"] = m
	return _mat["chip"]


## Additive unshaded material for streak sparks (vertex colour).
static func streak_mat() -> StandardMaterial3D:
	if not _mat.has("streak"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(1.6, 1.4, 1.0, 1.0)
		_mat["streak"] = m
	return _mat["streak"]


## Bright emissive chunks (glowing embers, glass glints) — unshaded so they read in shadow.
static func glow_chip_mat() -> StandardMaterial3D:
	if not _mat.has("glow_chip"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat["glow_chip"] = m
	return _mat["glow_chip"]


## Tracer streak shader: head bright, tail fades. Per-instance colour (instance uniform).
static func tracer_mat() -> ShaderMaterial:
	if not _mat.has("tracer"):
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
instance uniform vec4 col : source_color = vec4(1.0, 0.85, 0.5, 1.0);
varying float zt;
void vertex() { zt = VERTEX.z + 0.5; }
void fragment() {
	float a = pow(clamp(1.0 - zt, 0.0, 1.0), 1.6);
	ALBEDO = col.rgb * (1.6 + a);
	ALPHA = col.a * (0.15 + a * 0.85);
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_mat["tracer"] = m
	return _mat["tracer"]


## Soft additive glow shader for lights' halos / ground glows (unit quad, billboard).
static func glow_mat(color: Color) -> StandardMaterial3D:
	var key := "glow_%s" % color.to_html()
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = soft_tex()
		m.albedo_color = color
		_mat[key] = m
	return _mat[key]


## Unlit fire-core material for the faceted sphere flash (colour animated through albedo_color on a duplicate).
static func fire_core_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.7, 0.3, 1.0)
	return m


## Alpha-blended (not additive) faceted fireball shell: reads orange even against a bright daytime sky.
static func fire_shell_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.albedo_color = Color(1.0, 0.5, 0.1, 0.85)
	return m


static func ring_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = ring_tex()
	m.albedo_color = Color(1.0, 0.8, 0.5, 0.7)
	return m


# ------------------------------------------------------------------------------------------------ colours
static func color_from(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is String or v is StringName:
		var s := String(v)
		if s != "":
			return Color(s)
	return fallback
