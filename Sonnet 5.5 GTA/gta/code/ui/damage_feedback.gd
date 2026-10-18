class_name DamageFeedback
extends Control
## Screen feedback for damage: red edge vignette (pulsing at low health), desaturation, hit flash, directional hit
## indicators around the crosshair, plus the death / busted colour grade driven by DeathScreen.
## One full-screen shader rect (reads the 3D scene via hint_screen_texture, so the HUD above it stays colourful); the
## rect is hidden while nothing is active so the screen copy costs nothing in normal play.

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float desat = 0.0;
uniform float vignette = 0.0;
uniform vec4 vig_color : source_color = vec4(0.62, 0.0, 0.03, 1.0);
uniform float tint_amount = 0.0;
uniform vec4 tint_color : source_color = vec4(1.0, 0.45, 0.45, 1.0);
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat);
	c = mix(c, c * tint_color.rgb * 0.62, tint_amount);
	float d = length(UV - 0.5) * 1.4142;
	float v = smoothstep(0.32, 1.02, d) * vignette;
	c = mix(c, vig_color.rgb, clamp(v, 0.0, 0.92));
	COLOR = vec4(c, 1.0);
}
"""

var death_desat := 0.0          # driven by DeathScreen
var death_tint := 0.0
var death_tint_color := Color(1.0, 0.42, 0.42)
var health_ratio := 1.0         # pushed by UIRoot each frame (or tests)
var test_mode := false

var _fx: ColorRect
var _mat: ShaderMaterial
var _indicators: Control
var _hits: Array[Dictionary] = []     # {angle, age, strength}
var _flash := 0.0
var _t := 0.0
var _had_hits := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx = ColorRect.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.color = Color.WHITE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_fx.material = _mat
	_fx.visible = false
	add_child(_fx)
	_indicators = IndicatorLayer.new()
	_indicators.owner_fx = self
	_indicators.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_indicators)


func _ready() -> void:
	Events.player_hurt.connect(_on_player_hurt)


func _on_player_hurt(amount: float, info: Dictionary) -> void:
	_flash = clampf(maxf(_flash, 0.25 + amount / 55.0), 0.0, 0.9)
	var pp: Vector3 = Game.get_player_position()
	var src := Vector3.INF
	var s = info.get("source", null)
	if s != null and is_instance_valid(s) and s is Node3D and s != Game.player:
		src = (s as Node3D).global_position
	elif info.has("direction") and info.get("direction") is Vector3 and (info["direction"] as Vector3).length() > 0.01:
		src = pp - (info["direction"] as Vector3).normalized() * 10.0
	if src != Vector3.INF:
		add_hit_from(src, clampf(amount / 30.0, 0.35, 1.0))


## Adds a directional indicator for damage coming from world position `src`.
func add_hit_from(src: Vector3, strength: float = 1.0) -> void:
	var pp := Game.get_player_position()
	var v := Vector2(src.x - pp.x, src.z - pp.z)
	if v.length() < 0.1:
		return
	v = v.normalized()
	var fwd := Vector2(0, -1)
	if is_instance_valid(Game.gameplay_camera):
		var cf := -Game.gameplay_camera.global_transform.basis.z
		if Vector2(cf.x, cf.z).length() > 0.1:
			fwd = Vector2(cf.x, cf.z).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var ang := atan2(v.dot(right), v.dot(fwd))
	_hits.append({"angle": ang, "age": 0.0, "strength": strength})
	if _hits.size() > 6:
		_hits.pop_front()


func add_hit_angle(angle: float, strength: float = 1.0) -> void:
	_hits.append({"angle": angle, "age": 0.0, "strength": strength})


func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.05)
	_t += dt
	_flash = move_toward(_flash, 0.0, dt * 2.2)
	var i := 0
	while i < _hits.size():
		_hits[i]["age"] = float(_hits[i]["age"]) + dt
		if float(_hits[i]["age"]) > 1.5:
			_hits.remove_at(i)
		else:
			i += 1
	if not test_mode and is_instance_valid(Game.player):
		var p = Game.player
		if p.get("health") != null:
			var mh: float = maxf(float(p.get("max_health")) if p.get("max_health") != null else 100.0, 1.0)
			health_ratio = clampf(float(p.get("health")) / mh, 0.0, 1.0)
	var low := 0.0
	if health_ratio < 0.36 and health_ratio > 0.0:
		low = (0.36 - health_ratio) / 0.36
	var pulse := 0.5 + 0.5 * sin(_t * (3.5 + low * 5.0))
	var vig := _flash * 0.9 + low * (0.6 + 0.32 * pulse) + death_tint * 0.55
	var ds := low * 0.55 + death_desat
	var tint := death_tint
	var active := vig > 0.004 or ds > 0.004 or tint > 0.004
	_fx.visible = active
	if active:
		_mat.set_shader_parameter("vignette", clampf(vig, 0.0, 1.0))
		_mat.set_shader_parameter("desat", clampf(ds, 0.0, 1.0))
		_mat.set_shader_parameter("tint_amount", clampf(tint, 0.0, 1.0))
		_mat.set_shader_parameter("tint_color", death_tint_color)
	if not _hits.is_empty() or _had_hits:
		_indicators.queue_redraw()
	_had_hits = not _hits.is_empty()


func _draw_indicators(ci: Control) -> void:
	var c := ci.size * 0.5
	for h in _hits:
		var age: float = h["age"]
		var a := clampf((1.5 - age) / 0.9, 0.0, 1.0) * clampf(age / 0.05, 0.0, 1.0) * float(h["strength"])
		var ang: float = h["angle"]
		var a0 := ang - PI * 0.5 - 0.30
		var a1 := ang - PI * 0.5 + 0.30
		UIDraw.sector(ci, c, 190.0, 214.0, a0, a1, Color(1.0, 0.16, 0.2, 0.85 * a), 14)
		UIDraw.sector(ci, c, 214.0, 232.0, a0 + 0.08, a1 - 0.08, Color(1.0, 0.16, 0.2, 0.28 * a), 14)


class IndicatorLayer extends Control:
	var owner_fx: DamageFeedback

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if owner_fx != null:
			owner_fx._draw_indicators(self)
