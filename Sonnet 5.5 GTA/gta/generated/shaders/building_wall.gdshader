shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay: walls, roofs, trims and generic props of buildings (replaces Blender WallA..D / Roof / generic materials).
// Instance data (MultiMesh custom data): x = palette index + 1 (0 = use default_palette), y = brightness variation 0..1,
// z = building random, w = instance random. Vertex colour multiplies the result (white = untouched).

#include "res://gta/generated/shaders/building_common.gdshaderinc"

global uniform float gta_night;
global uniform float gta_wetness;

uniform int slot = 0;                       // 0..3 WallA..WallD, 4 roof, 5 trim, 6 generic (base_color), 7 generic metal
uniform bool vertex_slot = false;           // merged meshes: the slot is baked into the vertex alpha (slot / 8), rgb = colour multiplier
uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform int default_palette = 0;
uniform float rough = 0.92;
uniform float metal = 0.0;
uniform float noise_amount = 0.06;
uniform float grime = 0.55;
uniform float night_dim = 0.0;              // 1 for materials that should not look sun-lit at night (unused by default)

varying flat vec4 v_inst;
varying vec3 v_world;
varying vec3 v_wn;
varying vec4 v_col;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

void fragment() {
	vec3 col;
	int sl = vertex_slot ? int(v_col.a * 8.0 + 0.5) : slot;
	float metal_v = metal;
	if (sl < 6) {
		int pal = int(v_inst.x + 0.5) - 1;
		if (pal < 0) {
			pal = default_palette;
		}
		pal = clamp(pal, 0, 3);
		col = srgb2lin(BLD_PAL[pal * 6 + sl]);
	} else {
		col = base_color.rgb;
		if (sl == 7) {
			metal_v = 0.6;
		}
	}
	col *= v_col.rgb;
	float bright = 0.92 + 0.16 * v_inst.y;
	col *= bright;

	// cheap blocky grit (world-space 0.25 m cells) keeps big flat faces from looking like plastic
	float n = hash13(floor(v_world * vec3(4.0, 3.0, 4.0)));
	col *= 1.0 - noise_amount * n;
	float up = smoothstep(0.7, 0.95, v_wn.y);
	col *= 1.0 - up * 0.10 * hash13(floor(v_world * 2.0));

	// ground grime + soft ambient-occlusion-like darkening near the pavement
	float low = 1.0 - smoothstep(0.0, 3.2, v_world.y);
	col *= 1.0 - grime * 0.40 * low * (1.0 - up);
	// facade height gradient: richer low down, sun-bleached towards the top (breaks up tall flat walls)
	col *= 0.93 + 0.11 * smoothstep(0.0, 40.0, v_world.y);

	float wet = clamp(gta_wetness, 0.0, 1.0);
	col *= 1.0 - 0.22 * wet;
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.38, wet);
	METALLIC = metal_v;
	SPECULAR = 0.35 + 0.25 * wet;
}
