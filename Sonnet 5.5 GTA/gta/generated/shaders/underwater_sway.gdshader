shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Underwater plant sway (kelp / seaweed): vertices bend with height above the root, phase from the world position. Flat colour per
// material (the albedo of the original GLB surface is copied into `albedo`).

uniform vec4 albedo : source_color = vec4(0.2, 0.55, 0.3, 1.0);
uniform float sway = 0.22;
uniform float speed = 1.15;
uniform float roughness = 0.9;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = wp.x * 0.37 + wp.z * 0.51;
	float h = max(VERTEX.y, 0.0);
	float amt = h * h * sway * 0.35;
	VERTEX.x += sin(TIME * speed + ph + h * 0.9) * amt;
	VERTEX.z += cos(TIME * speed * 0.8 + ph * 1.3 + h * 0.7) * amt * 0.7;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.15;
}
