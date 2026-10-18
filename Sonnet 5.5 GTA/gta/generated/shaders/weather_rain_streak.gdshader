shader_type spatial;
// Rain streaks for GPUParticles3D (ParticleProcessMaterial with particle_flag_align_y = true so MODEL_MATRIX[1] runs
// along the fall direction). Each particle is a camera-facing ribbon aligned with its velocity; streak length comes
// from the particle scale. Distance fade keeps the box edges invisible.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 streak_color : source_color = vec4(0.80, 0.88, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float width = 0.012;
uniform float fade_near = 1.2;
uniform float fade_far = 30.0;
uniform float brightness = 1.0;

varying float v_fade;
varying vec2 v_uv;

void vertex() {
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 vdir_raw = MODEL_MATRIX[1].xyz;
	float len = length(vdir_raw);
	vec3 vdir = vdir_raw / max(len, 1e-4);
	vec3 to_cam = CAMERA_POSITION_WORLD - pos;
	float dist = length(to_cam);
	to_cam /= max(dist, 1e-3);
	vec3 side = cross(vdir, to_cam);
	float sl = length(side);
	side = sl > 1e-3 ? side / sl : normalize(cross(vdir, vec3(1.0, 0.0, 0.0)));
	// keep far streaks readable: width grows slowly with distance
	float w = width * (1.0 + dist * 0.035);
	vec3 world_pos = pos + side * VERTEX.x * w + vdir * VERTEX.y * len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
	v_uv = UV;
	v_fade = smoothstep(fade_near, fade_near + 3.0, dist) * (1.0 - smoothstep(fade_far * 0.55, fade_far, dist));
}

void fragment() {
	float across = 1.0 - abs(v_uv.x - 0.5) * 2.0;
	float along = smoothstep(0.0, 0.25, v_uv.y) * (1.0 - smoothstep(0.55, 1.0, v_uv.y) * 0.85);
	float a = pow(clamp(across, 0.0, 1.0), 0.7) * along * v_fade * intensity * COLOR.a;
	ALBEDO = streak_color.rgb * brightness;
	ALPHA = clamp(a * 0.75, 0.0, 1.0);
}
