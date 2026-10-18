shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Fish for the MultiMesh schools (MarineFish): the whole body wriggles with a travelling wave that grows toward the tail (+Z),
// the phase comes from INSTANCE_CUSTOM.x so every fish swims out of step. Colours come from the Blender materials (albedo uniform).

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float body_len = 0.3;
uniform float wiggle = 0.22;
uniform float freq = 9.0;
uniform float rough = 0.55;
uniform float emit = 0.0;

void vertex() {
	float zn = VERTEX.z / (0.5 * body_len);                 // -1 (nose) .. +1 (tail tip)
	float ph = INSTANCE_CUSTOM.x;
	float speed_k = 0.75 + 0.5 * INSTANCE_CUSTOM.y;
	float t = smoothstep(-0.25, 1.0, zn);
	float wave = sin(TIME * freq * speed_k + ph - zn * 2.4);
	VERTEX.x += wave * wiggle * body_len * 0.5 * t * t;
	VERTEX.x += sin(TIME * freq * speed_k + ph + 1.3) * 0.02 * body_len;   // slight body yaw
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	EMISSION = albedo.rgb * emit;
}
