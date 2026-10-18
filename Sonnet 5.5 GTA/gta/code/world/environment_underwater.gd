class_name EnvironmentUnderwater
extends CanvasLayer
## Full-screen underwater treatment (refraction wobble, turquoise grade, caustic shimmer, vignette) drawn under the HUD.
## Costs nothing while `amount` is 0 (the rect is hidden, no screen texture copy). Fog / light changes underwater are
## applied by EnvironmentSystem; this node is purely the screen-space part.

const SHADER := "res://gta/generated/vfx/underwater_overlay.gdshader"

var amount := 0.0
var depth01 := 0.0

var _rect: ColorRect
var _mat: ShaderMaterial


func setup() -> void:
	name = "UnderwaterOverlay"
	layer = -50
	var sh := load(SHADER) as Shader
	if sh == null:
		push_warning("EnvironmentUnderwater: overlay shader missing - screen-space underwater effect disabled")
		return
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.name = "Overlay"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func set_state(new_amount: float, new_depth01: float, aspect: float) -> void:
	amount = new_amount
	depth01 = new_depth01
	if _rect == null:
		return
	var show_it := new_amount > 0.01
	if _rect.visible != show_it:
		_rect.visible = show_it
	if show_it:
		_mat.set_shader_parameter("amount", new_amount)
		_mat.set_shader_parameter("depth01", new_depth01)
		_mat.set_shader_parameter("aspect", aspect)
