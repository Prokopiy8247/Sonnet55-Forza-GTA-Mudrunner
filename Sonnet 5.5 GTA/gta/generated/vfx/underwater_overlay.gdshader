shader_type canvas_item;
// Full-screen underwater treatment drawn by EnvironmentUnderwater on a CanvasLayer below the HUD:
// gentle refraction wobble, turquoise grade, cheap animated caustics, vignette and a murky depth falloff.
// Only visible (and only sampling the screen) while the camera is below the sea surface.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float depth01 : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.05, 0.50, 0.58, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.01, 0.12, 0.22, 1.0);
uniform float wobble = 0.0022;
uniform float aspect = 1.7778;

float caustic(vec2 uv, float t) {
	vec2 p = mod(uv * 6.28318, 6.28318) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.0055;
	for (int n = 0; n < 3; n++) {
		float tt = t * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
	}
	c /= 3.0;
	c = 1.17 - pow(c, 1.4);
	return pow(abs(c), 8.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 w = vec2(sin(uv.y * 17.0 + TIME * 1.6), cos(uv.x * 13.0 + TIME * 1.25)) * wobble * amount;
	vec3 scene = texture(screen_tex, uv + w).rgb;

	// turquoise grade: multiply (water absorbs red first) then add a little in-scatter haze
	vec3 grade = mix(tint.rgb, deep_tint.rgb, depth01);
	vec3 absorbed = scene * mix(vec3(0.55, 0.95, 1.05), vec3(0.20, 0.55, 0.80), depth01);
	scene = mix(scene, absorbed, 0.75 * amount);
	scene += grade * 0.10 * amount;

	// caustic light shimmer, strongest near the surface
	vec2 cuv = vec2(uv.x * aspect, uv.y) * 1.9;
	float c = caustic(cuv + w * 6.0, TIME * 0.45 + 23.0);
	scene += vec3(0.30, 0.85, 0.95) * c * 0.22 * amount * (1.0 - depth01 * 0.85);

	// soft god rays fanning down from the surface + a lighter top / darker bottom gradient
	float ray = (0.5 + 0.5 * sin((uv.x * aspect + uv.y * 0.35) * 9.0 + TIME * 0.35)) * (0.5 + 0.5 * sin((uv.x * aspect - uv.y * 0.2) * 5.3 - TIME * 0.22));
	scene += vec3(0.25, 0.80, 0.85) * pow(ray, 3.0) * (1.0 - uv.y) * (1.0 - depth01) * 0.14 * amount;
	scene *= mix(1.0, 0.78 + 0.40 * (1.0 - uv.y), amount * 0.65);

	// vignette
	float v = smoothstep(0.30, 1.05, length((uv - 0.5) * vec2(aspect * 0.6, 1.0)) * 1.25);
	scene *= 1.0 - v * 0.55 * amount;

	COLOR = vec4(scene, 1.0);
}
