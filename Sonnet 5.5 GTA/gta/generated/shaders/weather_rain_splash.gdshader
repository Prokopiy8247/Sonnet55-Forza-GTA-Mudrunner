shader_type spatial;
// Ground splash ring + droplets for rain. Used on a horizontal QuadMesh (orientation FACE_Y) drawn by GPUParticles3D.
// INSTANCE_CUSTOM.y is the normalised particle age (ParticleProcessMaterial).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 splash_color : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float fade_far = 26.0;
uniform float brightness = 1.0;

varying float v_age;
varying float v_fade;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	float dist = distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
	v_fade = (1.0 - smoothstep(fade_far * 0.5, fade_far, dist)) * smoothstep(1.2, 3.5, dist);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float age = clamp(v_age, 0.0, 1.0);
	// expanding ring + a small bright impact dot at the start
	float ring_r = mix(0.20, 0.95, 1.0 - pow(1.0 - age, 2.0));
	float ring = smoothstep(0.30, 0.0, abs(r - ring_r)) * pow(1.0 - age, 2.0);
	float dot_ = smoothstep(0.42, 0.0, r) * pow(1.0 - age, 4.0) * 0.9;
	float a = (ring * 0.85 + dot_) * v_fade * intensity;
	ALBEDO = splash_color.rgb * brightness;
	ALPHA = clamp(a * 0.62, 0.0, 1.0);
}
