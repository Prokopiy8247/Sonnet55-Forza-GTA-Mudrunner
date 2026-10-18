shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
// Underwater sunlight shafts: tall thin additive quads hanging from the surface. Soft edges across the width, bright near the surface and
// fading with depth, slow drifting streaks, faded near the camera and where the quad meets geometry (soft particles via the depth texture).

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 tint : source_color = vec3(0.55, 0.95, 0.9);
uniform float intensity = 0.5;
uniform float surface_y = -1.5;
uniform float fade_depth = 16.0;
uniform vec3 cam_pos = vec3(0.0);
uniform float seed = 0.0;

varying vec3 w_pos;
varying vec2 q_uv;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	q_uv = UV;
}

void fragment() {
	float across = abs(q_uv.x * 2.0 - 1.0);
	float edge = smoothstep(1.0, 0.25, across);
	float depth_below = max(surface_y - w_pos.y, 0.0);
	float vfade = exp(-depth_below / fade_depth) * smoothstep(0.0, 1.2, depth_below);
	float streak = 0.55 + 0.45 * vnoise(vec2(q_uv.x * 7.0 + seed, TIME * 0.12 + seed * 3.0));
	streak *= 0.65 + 0.35 * vnoise(vec2(w_pos.y * 0.12 + seed, TIME * 0.2 + q_uv.x * 3.0));
	float dc = distance(w_pos, cam_pos);
	float cam_fade = smoothstep(2.0, 9.0, dc) * smoothstep(75.0, 40.0, dc);
	// soft intersection with the sea floor / props
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 vw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vw.xyz /= vw.w;
	float soft = clamp((-vw.z - (-VERTEX.z)) * 0.6, 0.0, 1.0);
	float a = edge * vfade * streak * cam_fade * soft * intensity;
	ALBEDO = tint;
	ALPHA = clamp(a, 0.0, 1.0);
}
