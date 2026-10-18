shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Swaying underwater plants (kelp, seaweed) for MultiMesh decoration. Sway grows with height above the instance origin and is
// phase-shifted by the world position so a forest does not move in unison. Colour = albedo uniform (the Blender material colour or the
// code fallback colour) multiplied by the vertex colour when the mesh has one.

uniform vec4 albedo : source_color = vec4(0.25, 0.45, 0.2, 1.0);
uniform vec4 tip_color : source_color = vec4(0.5, 0.62, 0.25, 1.0);
uniform float height = 4.0;
uniform float sway = 0.42;
uniform float speed = 0.85;
uniform float rough = 0.7;
uniform bool use_vertex_color = true;

varying float v_h;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / height, 0.0, 1.0);
	v_h = h;
	float ph = wp.x * 0.31 + wp.z * 0.23;
	float sw = sway * h * h;
	VERTEX.x += sin(TIME * speed + ph + VERTEX.y * 0.5) * sw;
	VERTEX.z += cos(TIME * speed * 0.83 + ph * 1.31 + VERTEX.y * 0.41) * sw * 0.65;
}

void fragment() {
	vec3 c = mix(albedo.rgb, tip_color.rgb, smoothstep(0.35, 1.0, v_h));
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	// translucent leaves: a little light from behind
	BACKLIGHT = c * 0.25;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
