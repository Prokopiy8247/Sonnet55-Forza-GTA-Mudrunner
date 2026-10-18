shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay: trees, bushes, grass and reeds. Vertex colour rgb = albedo (linear), vertex colour a = sway weight
// (0 at the root, 1 at the tips). Instance data (MultiMesh custom data): x = brightness/hue variation 0..1, y = phase.
// Wind sway uses real time so it keeps moving when the game clock is frozen; storms bend harder via gta_rain.

global uniform float gta_wetness;
global uniform float gta_rain;
global uniform float gta_night;

uniform float sway = 0.07;
uniform float sway_speed = 1.4;
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.3);
uniform float roughness_val = 0.9;
uniform float translucency = 0.0;

varying flat float v_var;

void vertex() {
	v_var = INSTANCE_CUSTOM.x;
	float w = COLOR.a;
	if (w > 0.001) {
		vec3 wp = MODEL_MATRIX[3].xyz;
		float ph = INSTANCE_CUSTOM.y * 6.2831 + wp.x * 0.13 + wp.z * 0.11;
		float amp = sway * w * (1.0 + gta_rain * 2.2);
		float s1 = sin(TIME * sway_speed + ph) + 0.5 * sin(TIME * sway_speed * 2.3 + ph * 1.7);
		vec3 off_world = normalize(wind_dir) * s1 * amp + vec3(cos(TIME * 0.8 + ph), 0.0, sin(TIME * 0.7 + ph)) * 0.25 * amp;
		// bring the world-space offset back into the (possibly scaled / rotated) model space
		mat3 inv_m = inverse(mat3(MODEL_MATRIX));
		VERTEX += inv_m * off_world;
	}
}

void fragment() {
	vec3 c = COLOR.rgb;
	c *= 0.86 + 0.28 * v_var;
	float wet = clamp(gta_wetness, 0.0, 1.0);
	c *= 1.0 - 0.18 * wet;
	ALBEDO = c;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.2;
	if (translucency > 0.0) {
		BACKLIGHT = c * translucency;
	}
}
