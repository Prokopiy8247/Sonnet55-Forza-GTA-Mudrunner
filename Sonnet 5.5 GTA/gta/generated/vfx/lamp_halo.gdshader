shader_type spatial;
// Billboard glow for street lamp heads (MultiMesh of quads). Brightness follows `on_amount` (LampManager: night or
// storm gloom) with a per-instance switch-on threshold (INSTANCE_CUSTOM.x) so lamps do not all pop on at once.
// HDR output so the environment bloom picks the cores up.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 halo_color : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform float strength = 1.0;
uniform float fade_begin = 90.0;
uniform float fade_end = 150.0;
uniform float near_fade = 3.0;
uniform float on_amount : hint_range(0.0, 1.0) = 0.0;

varying float v_fade;
varying float v_on;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float dist = distance(center, CAMERA_POSITION_WORLD);
	size *= 1.0 + dist * 0.012;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_fade = (1.0 - smoothstep(fade_begin, fade_end, dist)) * smoothstep(0.5, near_fade, dist);
	v_on = smoothstep(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.x + 0.25, on_amount);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	float core = exp(-r2 * 14.0);
	float halo = exp(-r2 * 3.6) * 0.42;
	float a = (core * 2.4 + halo) * v_on * v_fade * strength;
	ALBEDO = halo_color.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
