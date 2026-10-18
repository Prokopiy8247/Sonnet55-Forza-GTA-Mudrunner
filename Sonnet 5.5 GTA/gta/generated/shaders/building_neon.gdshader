shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay: emissive neon signs / lamp heads / billboards. Brightness follows the global night factor.
// Colour = neon_color * vertex colour. When hue_from_instance > 0 the colour cycles through magenta / cyan / amber
// using the instance random (MultiMesh custom data w).

#include "res://gta/generated/shaders/building_common.gdshaderinc"

global uniform float gta_night;
global uniform float gta_wetness;

uniform vec4 neon_color : source_color = vec4(1.0, 0.24, 0.6, 1.0);
uniform float day_energy = 0.9;
uniform float night_energy = 4.5;
uniform float hue_from_instance = 0.0;
uniform float flicker = 0.0;
uniform float pattern = 0.0;                // 1 = billboard art (diagonal bands in two neon hues) instead of a flat colour

varying flat vec4 v_inst;
varying vec4 v_col;
varying vec3 v_world;
varying vec3 v_lp;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	v_col = COLOR;
	v_lp = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = neon_color.rgb * v_col.rgb;
	if (hue_from_instance > 0.5) {
		float r = fract(v_inst.w * 7.0 + v_inst.z * 3.0);
		vec3 a = srgb2lin(vec3(1.0, 0.24, 0.6));
		vec3 b = srgb2lin(vec3(0.2, 0.88, 1.0));
		vec3 d = srgb2lin(vec3(1.0, 0.70, 0.28));
		c = r < 0.4 ? a : (r < 0.75 ? b : d);
		c *= v_col.rgb;
	}
	if (pattern > 0.5) {
		float r2 = fract(v_inst.w * 5.0 + v_inst.z * 11.0);
		vec3 c2 = r2 < 0.5 ? srgb2lin(vec3(0.2, 0.88, 1.0)) : srgb2lin(vec3(1.0, 0.70, 0.28));
		float bands = step(0.5, fract((v_lp.x + v_lp.y * 0.55) * 0.32));
		float thin = smoothstep(0.42, 0.5, abs(fract((v_lp.x - v_lp.y * 0.55) * 0.9) - 0.5));
		c = mix(c, c2, bands);
		c = mix(c, vec3(1.0), thin * 0.25);
	}
	float night = clamp(gta_night, 0.0, 1.0);
	float e = mix(day_energy, night_energy, night);
	float fl = 1.0 - flicker * step(0.93, fract(sin(floor(TIME * 9.0) + v_inst.w * 40.0) * 43758.5)) * night;
	ALBEDO = c * 0.25;
	EMISSION = c * e * fl;
	ROUGHNESS = 0.4;
}
