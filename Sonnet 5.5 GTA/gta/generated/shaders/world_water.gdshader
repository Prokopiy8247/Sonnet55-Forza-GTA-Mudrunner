shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay stylised sea: faceted waves, depth-based colour (deep teal -> turquoise), animated shoreline foam, crest foam.
// Colour grading hooks for the Environment agent: uniforms shallow_col / deep_col / foam_col / wave_amp (set on this material,
// reachable through the node group "water_surface" -> material meta) and the global uniforms gta_night / gta_rain / gta_sun_energy.

global uniform float gta_night;
global uniform float gta_rain;
global uniform float gta_sun_energy;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec3 shallow_col : source_color = vec3(0.22, 0.86, 0.80);
uniform vec3 mid_col : source_color = vec3(0.07, 0.52, 0.72);
uniform vec3 deep_col : source_color = vec3(0.025, 0.17, 0.40);
uniform vec3 foam_col : source_color = vec3(0.97, 0.99, 1.0);
// pushed by EnvironmentSystem (sun / moon glitter, sky tint at grazing angles)
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.85, 0.6);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_vis = 0.0;
uniform vec3 sky_tint : source_color = vec3(0.6, 0.8, 0.95);
uniform float wave_amp = 0.12;
uniform float clarity = 0.42;
uniform float facet_mix = 0.65;

varying vec3 w_pos;
varying float w_open;

float wave_h(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.92, 0.38)) * 0.30 + t * 0.85);
	h += 0.6 * sin(dot(p, vec2(-0.42, 0.91)) * 0.52 + t * 1.25 + 1.7);
	h += 0.35 * sin(dot(p, vec2(0.71, -0.70)) * 1.05 + t * 1.85 + 4.0);
	return h * 0.5;
}

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
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float open_sea = mix(0.22, 1.0, smoothstep(165.0, 250.0, wp.z));
	// the park pond (far north) stays calm
	open_sea = mix(open_sea, 0.15, step(wp.z, 100.0));
	w_open = open_sea;
	float amp = wave_amp * open_sea * (1.0 + gta_rain * 1.4);
	float h = wave_h(wp.xz, TIME) * amp;
	VERTEX.y += h;
	w_pos = wp + vec3(0.0, h, 0.0);
}

void fragment() {
	vec3 fn = -normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));      // sign: +cross() points INTO the surface in Godot 4.x
	// analytic ripple normal (view space)
	float e = 0.6;
	float vdist = max(-VERTEX.z, 0.0);
	float far_fade = 1.0 - 0.85 * smoothstep(70.0, 280.0, vdist);          // ripples + speckles fade out with distance (no moire / confetti on the open sea)
	float amp = wave_amp * w_open * (1.0 + gta_rain * 1.4) * far_fade;
	float hx = wave_h(w_pos.xz + vec2(e, 0.0), TIME) - wave_h(w_pos.xz - vec2(e, 0.0), TIME);
	float hz = wave_h(w_pos.xz + vec2(0.0, e), TIME) - wave_h(w_pos.xz - vec2(0.0, e), TIME);
	vec3 wn = normalize(vec3(-hx * amp * 2.0, 1.0, -hz * amp * 2.0));
	vec3 vn = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	vec3 n = normalize(mix(vn, fn, facet_mix * 0.6 * (1.0 - 0.6 * smoothstep(40.0, 200.0, vdist))));
	if (!FRONT_FACING) {
		n = -n;
	}
	NORMAL = n;

	// scene depth below the surface (vertical metres)
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 vw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vw.xyz /= vw.w;
	vec3 scene_w = (INV_VIEW_MATRIX * vec4(vw.xyz, 1.0)).xyz;
	float depth_v = max(w_pos.y - scene_w.y, 0.0);
	float ray_thick = max(-vw.z + VERTEX.z, 0.0);

	float k = 1.0 - exp(-depth_v * clarity);
	float kk = pow(k, 0.8);
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.0, 0.55, kk));
	col = mix(col, deep_col, smoothstep(0.45, 1.0, kk));
	// subtle large-scale colour drift so the open sea is not flat
	col *= 0.94 + 0.12 * vnoise(w_pos.xz * 0.03 + vec2(TIME * 0.02, 0.0));

	// shoreline foam: animated band that follows the depth contour + wave-crest speckles
	float t = TIME;
	float band = depth_v + 0.12 * sin(w_pos.x * 0.6 + t * 1.2) + 0.1 * sin(w_pos.z * 0.8 - t * 0.9);
	float shore = smoothstep(0.75, 0.05, band);
	float surge = 0.5 + 0.5 * sin(depth_v * 5.0 - t * 1.6 + vnoise(w_pos.xz * 0.5) * 3.0);
	float foam = shore * (0.55 + 0.45 * surge);
	foam += smoothstep(0.80, 0.98, vnoise(w_pos.xz * 0.55 + vec2(t * 0.12, -t * 0.07))) * 0.35 * w_open * (1.0 + gta_rain) * (1.0 - smoothstep(30.0, 110.0, vdist));
	foam = clamp(foam, 0.0, 1.0);
	col = mix(col, foam_col, foam);

	float day = clamp(gta_sun_energy, 0.0, 1.0);
	float night = clamp(gta_night, 0.0, 1.0);
	// sky reflection at grazing angles + sun / moon glitter on the ripples (world space)
	vec3 Vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 Nw = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);     // final (ripple + facet) normal in world space
	vec3 Ng = normalize(mix(wn, Nw, 0.25));      // glitter follows the smooth ripples, not the individual triangles (no white confetti)
	vec3 Rw = reflect(-Vw, Ng);
	float fres = pow(1.0 - clamp(dot(Nw, Vw), 0.0, 1.0), 4.0);
	vec3 glint = vec3(0.0);
	float sparkle = 0.55 + 0.9 * vnoise(w_pos.xz * 1.9 + vec2(TIME * 0.6, -TIME * 0.4));
	float sun_up = smoothstep(-0.02, 0.08, sun_dir.y);
	float sg = pow(max(dot(Rw, sun_dir), 0.0), 260.0) * 4.0 + pow(max(dot(Rw, sun_dir), 0.0), 40.0) * 0.6;
	glint += sun_tint * sg * sun_up * day * sparkle;
	float mg = pow(max(dot(Rw, moon_dir), 0.0), 380.0) * 3.0 + pow(max(dot(Rw, moon_dir), 0.0), 60.0) * 0.4;
	glint += vec3(0.62, 0.78, 1.0) * mg * moon_vis * night * sparkle;
	glint *= (1.0 - foam) * w_open * 0.8 + 0.2 * (1.0 - foam);
	// night: deep navy with a faint glow instead of pitch black
	col = mix(col, col * vec3(0.45, 0.55, 0.9), night);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.06, 0.30, smoothstep(25.0, 150.0, vdist)), 0.22, foam);     // blurrier sun highlights with distance: no per-triangle white shards on the open sea
	SPECULAR = mix(0.55, 0.25, foam);
	METALLIC = 0.0;
	EMISSION = shallow_col * 0.05 * day * (1.0 - k) + sky_tint * fres * 0.22 * (1.0 - foam) * (0.25 + 0.75 * day) + deep_col * 0.28 * night + glint;
	ALPHA = clamp(mix(0.38, 0.97, pow(k, 0.7)) + foam * 0.6, 0.0, 1.0);
	if (!FRONT_FACING) {
		ALPHA = 0.55;
		ALBEDO *= 0.6;
	}
}
