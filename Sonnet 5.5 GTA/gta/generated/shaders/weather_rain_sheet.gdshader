shader_type spatial;
// Distant rain curtain: an open cylinder that follows the camera. Scrolling vertical streak noise gives the
// impression of rain falling beyond the particle box at almost zero cost.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 sheet_color : source_color = vec4(0.78, 0.86, 0.98, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float fall_speed = 1.15;
uniform float brightness = 1.0;
uniform vec2 slant = vec2(0.0, 0.0);

varying float v_view_dist;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// UV.x around the cylinder, UV.y bottom->top. Three layers of very fine, short streaks.
	float acc = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float cols = 520.0 + fi * 380.0;
		float cx = floor(UV.x * cols);
		float rnd = hash11(cx + fi * 71.7);
		float speed = fall_speed * (0.8 + rnd * 0.6) * (1.0 + fi * 0.35) * 6.0;
		float y = UV.y * (18.0 + fi * 9.0) + TIME * speed + rnd * 40.0 + UV.x * slant.x * 30.0;
		float streak = smoothstep(0.80, 1.0, fract(y)) * (1.0 - smoothstep(0.97, 1.0, fract(y))) * step(0.62, rnd);
		float fx = abs(fract(UV.x * cols) - 0.5) * 2.0;
		streak *= smoothstep(1.0, 0.1, fx);
		acc += streak * (0.8 - fi * 0.18);
	}
	float edge = smoothstep(0.0, 0.18, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	float dist_fade = smoothstep(14.0, 34.0, v_view_dist);
	float a = acc * edge * dist_fade * intensity * 0.5;
	ALBEDO = sheet_color.rgb * brightness;
	ALPHA = clamp(a, 0.0, 0.7);
}
