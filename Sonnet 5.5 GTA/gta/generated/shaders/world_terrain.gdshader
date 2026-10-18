shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay terrain: faceted low-poly look (flat normals from screen-space derivatives), colour from vertex data
// COLOR.r = sand, COLOR.g = rock, COLOR.b = urban paving, COLOR.a = noise seed.

global uniform float gta_wetness;
global uniform float gta_night;

uniform vec3 grass_a : source_color = vec3(0.27, 0.46, 0.20);
uniform vec3 grass_b : source_color = vec3(0.40, 0.57, 0.22);
uniform vec3 grass_dry : source_color = vec3(0.80, 0.70, 0.34);
uniform vec3 grass_dark : source_color = vec3(0.14, 0.32, 0.17);
uniform vec3 sand_col : source_color = vec3(0.96, 0.85, 0.60);
uniform vec3 sand_wet : source_color = vec3(0.80, 0.65, 0.46);
uniform vec3 rock_a : source_color = vec3(0.58, 0.40, 0.34);
uniform vec3 rock_b : source_color = vec3(0.80, 0.64, 0.50);
uniform vec3 rock_c : source_color = vec3(0.42, 0.36, 0.38);
uniform vec3 urban_col : source_color = vec3(0.50, 0.48, 0.45);
uniform float facet_strength = 0.10;

varying vec3 w_pos;
varying vec4 vcol;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
}

void fragment() {
	// faceted shading: normal from derivatives of the view-space position
	// NOTE: the sign matters - with +cross() the normal pointed INTO the ground in Godot 4.x (sun never reached the terrain, only ambient).
	vec3 fn = -normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = fn;

	vec2 p = w_pos.xz;
	float patch_n = vnoise(p * 0.045);
	float fine_n = vnoise(p * 0.35);
	float cell = hash21(floor(p / 3.0));

	float pn = 0.55 * patch_n + 0.30 * vnoise(p * 0.13 + 3.0) + 0.15 * fine_n;
	vec3 grass = mix(grass_a, grass_b, clamp(pn * 1.25 - 0.1, 0.0, 1.0));
	float dry = 0.5 * vnoise(p * 0.017 + 7.0) + 0.5 * vnoise(p * 0.06 + 19.0);
	grass = mix(grass, grass_dry, smoothstep(0.58, 0.88, dry) * 0.32);
	grass = mix(grass, grass_dark, smoothstep(0.62, 0.9, vnoise(p * 0.026 + 41.0)) * 0.55);   // lush dark patches
	grass *= 0.90 + 0.20 * fine_n;
	grass *= 1.0 + (cell - 0.5) * facet_strength;

	// sandstone strata: horizontal bands in world height, broken up by noise, plus cool shadow-grey facets
	float strata = vnoise(vec2(w_pos.y * 0.55 + vnoise(p * 0.05) * 2.0, 3.0));
	vec3 rock = mix(rock_a, rock_b, smoothstep(0.25, 0.75, strata * 0.7 + fine_n * 0.5));
	rock = mix(rock, rock_c, smoothstep(0.70, 0.95, hash21(floor(p / 4.0) + floor(w_pos.y * 0.5))) * 0.55);
	rock *= 1.0 + (cell - 0.5) * facet_strength * 2.6;

	float wet_edge = smoothstep(-0.85, -1.55, w_pos.y);          // darker wet sand only right at the waterline
	vec3 sand = mix(sand_col, sand_wet, clamp(wet_edge * 1.2, 0.0, 1.0));
	sand *= 0.93 + 0.14 * fine_n + 0.05 * (vnoise(p * 1.7) - 0.5);
	sand = mix(sand, sand * vec3(1.05, 0.98, 0.9), smoothstep(0.4, 0.8, vnoise(p * 0.09 + 5.0)) * 0.6);   // warm/pale drifts
	// underwater: bluish/darker bed
	float under = smoothstep(-1.5, -9.0, w_pos.y);
	sand = mix(sand, sand * vec3(0.78, 0.95, 0.98), under);

	// urban ground (yards, lots, plinths): 6 m concrete slabs with per-slab tone, seams and stains so wide yards never read flat
	vec2 ug = p / 6.0;
	vec2 uc = floor(ug);
	vec2 uf = fract(ug);
	float useam = 1.0 - smoothstep(0.0, 0.025, min(min(uf.x, 1.0 - uf.x), min(uf.y, 1.0 - uf.y)));
	vec3 urban = urban_col * (0.84 + 0.22 * hash21(uc + 2.0)) * (0.88 + 0.2 * vnoise(p * 0.8) + 0.1 * (vnoise(p * 0.11 + 9.0) - 0.5));
	urban *= 1.0 - 0.26 * useam;
	urban *= 1.0 - 0.22 * smoothstep(0.62, 0.86, vnoise(p * 0.17 + 21.0));

	// the whole beach slope (everything below the promenade level towards the sea) is sand, not just a thin ribbon at the waterline
	float beach = smoothstep(157.5, 161.0, w_pos.z) * smoothstep(-103.0, -92.0, w_pos.x) * (1.0 - smoothstep(70.0, 84.0, w_pos.x));
	beach = max(beach, smoothstep(-0.03, -0.30, w_pos.y) * smoothstep(118.0, 140.0, w_pos.z));
	vec3 col = mix(grass, sand, max(vcol.r, beach));
	col = mix(col, rock, vcol.g);
	col = mix(col, urban, vcol.b);

	float wet = clamp(gta_wetness, 0.0, 1.0);
	col *= 1.0 - 0.28 * wet;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, wet * (1.0 - vcol.g));
	SPECULAR = 0.25 + 0.2 * wet;
}
