shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay: window glass (replaces the Blender "Window" material). UV is in METRES in the module's frame
// (origin bottom-centre of the bay, u across, v up). Panes are cut on a regular grid; every pane gets a random lit
// state driven by the global night factor (warm yellows plus the occasional cyan / magenta window).
// Instance data: x = palette+1, y = brightness, z = building random, w = instance random.

#include "res://gta/generated/shaders/building_common.gdshaderinc"

global uniform float gta_night;
global uniform float gta_wetness;
global uniform float gta_sun_energy;

uniform vec4 glass_color : source_color = vec4(0.14, 0.26, 0.36, 1.0);
uniform vec4 glass_sky : source_color = vec4(0.40, 0.62, 0.78, 1.0);
uniform vec4 frame_color : source_color = vec4(0.80, 0.78, 0.72, 1.0);
uniform vec2 pane_size = vec2(2.0, 3.6);        // pane grid in metres (u offset by +half bay so 0 is a seam)
uniform float u_offset = 2.0;
uniform float mullion = 0.0;                    // frame thickness in metres drawn on pane borders (0 = none, geometry has frames)
uniform float emission_energy = 1.25;
uniform float hour = 21.0;                      // game clock, set by the content manager
uniform float rough = 0.10;

varying flat vec4 v_inst;
varying vec2 v_uv;
varying vec3 v_world;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	v_uv = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = vec2((v_uv.x + u_offset) / pane_size.x, v_uv.y / pane_size.y);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float night = clamp(gta_night, 0.0, 1.0);
	float wet = clamp(gta_wetness, 0.0, 1.0);

	float frame = 0.0;
	if (mullion > 0.0) {
		vec2 edge = min(f, 1.0 - f) * pane_size;
		frame = 1.0 - step(mullion, min(edge.x, edge.y));
	}

	// day glass: dark teal with a brighter sky-reflection gradient towards the top of every pane
	float grad = clamp(v_uv.y / 3.6, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float sky_k = clamp((0.30 + 0.45 * grad * grad + 0.40 * fres) * gta_sun_energy, 0.0, 0.95);
	vec3 glass = mix(srgb2lin(glass_color.rgb), srgb2lin(glass_sky.rgb), sky_k);
	glass *= 0.88 + 0.24 * hash13(vec3(cell, v_inst.z * 7.0));
	glass = mix(glass, glass * vec3(1.12, 1.0, 0.86), step(0.8, hash13(vec3(cell + 7.0, v_inst.z * 3.0))));   // the odd warm-tinted pane
	vec3 fr = srgb2lin(frame_color.rgb);
	vec3 albedo = mix(glass, fr, frame);

	float tv;
	vec3 lit = window_light(cell, v_inst.z, v_inst.w, night, hour, tv);
	float room = 0.55 + 0.45 * smoothstep(0.0, 0.5, f.y) * (1.0 - 0.35 * smoothstep(0.7, 1.0, f.y));
	float curtain = step(0.62, hash13(vec3(cell + 3.0, v_inst.w * 5.0 + v_inst.z))) * step(f.x, 0.34);
	room *= 1.0 - 0.7 * curtain;
	float flick = 1.0 + tv * 0.18 * sin(TIME * 7.0 + cell.x * 13.0 + cell.y * 5.0);
	vec3 emis = lit * room * flick * emission_energy * (1.0 - frame);

	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.04, wet) + frame * 0.6;
	METALLIC = 0.2 * (1.0 - frame);
	SPECULAR = 0.7;
	EMISSION = emis;
}
