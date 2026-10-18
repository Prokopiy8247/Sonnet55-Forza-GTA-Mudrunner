shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay: far-LOD building. Instances of a unit box (x,z in -0.5..0.5, y 0..1) scaled to the building size.
// A window grid in metres, cornice band, ground-floor band and lit-at-night panes are drawn procedurally, so a whole
// skyline costs a handful of draw calls.
// Instance data: x = palette+1, y = brightness, z = building random, w = style (0 office 1 apartment 2 industrial 3 house 4 plain).

#include "res://gta/generated/shaders/building_common.gdshaderinc"

global uniform float gta_night;
global uniform float gta_wetness;
global uniform float gta_sun_energy;

uniform float hour = 21.0;
uniform float bay = 4.0;
uniform float floor_h = 3.6;

varying flat vec4 v_inst;
varying flat vec3 v_size;
varying vec2 v_fuv;
varying float v_side;
varying float v_top;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	v_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 m = (VERTEX + vec3(0.5, 0.0, 0.5)) * v_size;
	v_side = step(abs(NORMAL.y), 0.5);
	v_top = step(0.5, NORMAL.y);
	float along = abs(NORMAL.x) > 0.5 ? m.z : m.x;
	v_fuv = vec2(along, m.y);
}

void fragment() {
	int pal = clamp(int(v_inst.x + 0.5) - 1, 0, 3);
	float bseed = v_inst.z;
	int sty = int(v_inst.w + 0.5);
	bool upper = sty >= 8;
	int style = sty - (upper ? 8 : 0);
	vec3 wallA = srgb2lin(BLD_PAL[pal * 6 + 0]);
	vec3 wallD = srgb2lin(BLD_PAL[pal * 6 + 3]);
	vec3 roof = srgb2lin(BLD_PAL[pal * 6 + 4]);
	vec3 trim = srgb2lin(BLD_PAL[pal * 6 + 5]);
	float night = clamp(gta_night, 0.0, 1.0);
	float wet = clamp(gta_wetness, 0.0, 1.0);
	vec3 col = wallA * (0.92 + 0.16 * v_inst.y);
	vec3 emis = vec3(0.0);
	float rough = 0.9;
	float metal = 0.0;

	if (v_top > 0.5) {
		col = roof * (0.9 + 0.2 * hash21(floor(v_fuv * 0.5)));
	} else if (v_side > 0.5) {
		vec2 cellsz = vec2(bay, floor_h);
		vec2 g = v_fuv / cellsz;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float top_y = v_size.y;
		bool in_cornice = v_fuv.y > top_y - 0.7;
		bool ground = cell.y < 0.5 && !upper;
		vec2 wmin = vec2(0.14, 0.26);
		vec2 wmax = vec2(0.86, 0.84);
		if (style == 1) { wmin = vec2(0.28, 0.30); wmax = vec2(0.72, 0.80); }
		else if (style == 2) { wmin = vec2(0.08, 0.72); wmax = vec2(0.92, 0.92); }
		else if (style == 3) { wmin = vec2(0.30, 0.30); wmax = vec2(0.70, 0.78); }
		bool has_win = style != 4 && !in_cornice && v_fuv.y < top_y - 0.9;
		if (style == 2 && v_fuv.y > 5.0) has_win = false;
		if (style == 2 && cell.y > 0.5) { has_win = false; }
		if (ground && style <= 1) {
			col = wallD * 0.85;            // shop band / lobby plinth
			wmin = vec2(0.10, 0.12); wmax = vec2(0.90, 0.80);
		}
		if (in_cornice) {
			col = trim * 0.95;
		} else if (f.y < 0.035) {
			col *= 0.86;                    // floor line
		}
		if (style == 2) {
			col = mix(wallD, wallA, 0.4) * (0.92 + 0.16 * v_inst.y);
			col *= 0.94 + 0.06 * step(0.5, fract(v_fuv.x * 2.0));   // corrugation hint
		}
		if (has_win && f.x > wmin.x && f.x < wmax.x && f.y > wmin.y && f.y < wmax.y) {
			float grad = (f.y - wmin.y) / (wmax.y - wmin.y);
			col = mix(vec3(0.015, 0.03, 0.05), vec3(0.09, 0.16, 0.24), grad * gta_sun_energy);
			rough = 0.1;
			metal = 0.3;
			float tv;
			vec3 lit = window_light(cell + vec2(floor(v_fuv.x * 0.01), 0.0), bseed, 0.37, night, hour, tv);
			emis = lit * (0.55 + 0.45 * grad) * 2.0;
		}
	} else {
		col = wallD;
	}
	float low = 1.0 - smoothstep(0.0, 2.4, v_fuv.y);
	col *= 1.0 - 0.2 * low * v_side;
	col *= 1.0 - 0.22 * wet;
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.35, wet);
	METALLIC = metal;
	EMISSION = emis;
}
