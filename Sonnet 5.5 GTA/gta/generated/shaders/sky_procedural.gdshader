shader_type sky;
// Halcyon Bay procedural sky. Driven entirely by EnvironmentSystem / DayNightCycle (no TIME use on purpose so
// the radiance map is not forced into real-time mode).
//  - 3-stop gradient (zenith / mid / horizon) + ground colour below the horizon
//  - sunset glow lobe around the sun azimuth + magenta "belt" on the anti-sun side
//  - stars, moon with phase + craters, sun disc (HDR so glow/bloom picks it up)
//  - stylised toon clouds: 4-octave value noise on a projected plane, 3-band cell shading, silver lining
//  - lightning flash + a procedural bolt
// Radiance (ambient / reflection) pass only evaluates the cheap gradient + glow so it stays inexpensive.

uniform vec4 sky_zenith : source_color = vec4(0.16, 0.44, 0.90, 1.0);
uniform vec4 sky_mid : source_color = vec4(0.38, 0.68, 0.96, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.74, 0.88, 0.97, 1.0);
uniform vec4 sky_ground : source_color = vec4(0.50, 0.62, 0.72, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float glow_amount = 0.0;
uniform vec4 band_color : source_color = vec4(1.0, 0.35, 0.6, 1.0);
uniform float band_amount = 0.0;
uniform float haze = 0.5;
uniform vec4 overcast_tint : source_color = vec4(0.86, 0.96, 1.10, 1.0);
uniform float overcast = 0.0;
uniform float overcast_dark = 0.0;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float sun_vis = 1.0;
uniform float sun_size = 0.034;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec4 moon_color : source_color = vec4(0.88, 0.92, 1.0, 1.0);
uniform float moon_vis = 0.0;
uniform float moon_size = 0.052;
uniform vec3 moon_phase = vec3(-0.55, 0.35, 0.76);
uniform float stars_amt = 0.0;

uniform float cloud_cover = 0.35;
uniform float cloud_dark = 0.0;
uniform vec4 cloud_lit : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.62, 0.70, 0.84, 1.0);
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_scale = 1.1;

uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(0.75, 0.82, 1.0, 1.0);
uniform vec4 bolt = vec4(0.0, 1.0, 0.0, 0.0);   // xy: horizon direction (x,z) unit, z: seed, w: strength
uniform float sky_time = 0.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash31(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cloud_field(vec2 uv) {
	float a = 0.55;
	float s = 0.0;
	vec2 p = uv;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.7);
		a *= 0.5;
	}
	return s;
}

float star_layer(vec3 dir, float scale, float chance, float radius) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	vec3 f = fract(p);
	float h = hash31(id);
	if (h < chance) {
		return 0.0;
	}
	vec3 c = vec3(hash31(id + 3.1), hash31(id + 7.7), hash31(id + 11.9));
	float d = length(f - c);
	float tw = 0.78 + 0.22 * sin(sky_time * (1.2 + h * 3.0) + h * 90.0);
	float mag = (h - chance) / (1.0 - chance);
	return smoothstep(radius, 0.0, d) * (0.35 + mag * 1.4) * tw;
}

// Base gradient + sunset glow + belt of Venus. Cheap: used for the radiance map too.
vec3 base_sky(vec3 dir) {
	float e = clamp(dir.y, 0.0, 1.0);
	vec3 col = mix(sky_horizon.rgb, sky_mid.rgb, smoothstep(0.0, 0.24, e));
	col = mix(col, sky_zenith.rgb, smoothstep(0.10, 0.95, pow(e, 0.85)));

	// overcast: desaturate toward a luminance-matched grey
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(l) * overcast_tint.rgb * (1.0 - overcast_dark * 0.55);
	col = mix(col, grey, overcast);

	vec3 sh = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(1e-5, 0.0, 0.0));
	vec3 dh = normalize(vec3(dir.x, 0.0, dir.z) + vec3(1e-5, 0.0, 0.0));
	float az = dot(dh, sh);
	float one_minus_e = 1.0 - e;
	float lobe = pow(max(az * 0.5 + 0.5, 0.0), 2.6);
	float g = glow_amount * lobe * (pow(one_minus_e, 6.0) * 0.95 + pow(one_minus_e, 2.0) * 0.12) * (1.0 - overcast * 0.7);
	col = mix(col, glow_color.rgb, clamp(g, 0.0, 1.0));
	float sc = max(dot(dir, sun_dir), 0.0);
	col += glow_color.rgb * (pow(sc, 10.0) * 0.30 + pow(sc, 90.0) * 0.45) * glow_amount * (1.0 - overcast * 0.8);

	float anti = max(-az, 0.0);
	float bandh = exp(-pow((e - 0.08) / 0.11, 2.0));
	col = mix(col, band_color.rgb, clamp(band_amount * pow(anti, 1.4) * bandh * (1.0 - overcast), 0.0, 0.9));

	col = mix(col, sky_horizon.rgb, haze * pow(one_minus_e, 5.0));

	if (dir.y < 0.0) {
		col = mix(sky_horizon.rgb, sky_ground.rgb, smoothstep(0.0, 0.32, -dir.y));
	}
	return col;
}

// returns cloud rgb in .rgb and coverage in .a
vec4 clouds(vec3 dir, float sc) {
	float up = dir.y;
	if (up <= 0.005) {
		return vec4(0.0);
	}
	vec2 uv = dir.xz / (up + 0.16) * cloud_scale + cloud_offset;
	float n = cloud_field(uv);
	float th = mix(0.97, 0.40, cloud_cover);
	float d = smoothstep(th, th + 0.016, n);
	d *= smoothstep(0.0, 0.12, up);
	if (d <= 0.002) {
		return vec4(0.0);
	}
	vec2 sd = normalize(sun_dir.xz + vec2(1e-4, 0.0));
	float n2 = cloud_field(uv + sd * 0.10);
	float edge_lit = clamp(0.5 + (n - n2) * 5.0, 0.0, 1.0);
	float core = smoothstep(th, th + 0.30, n);
	float shade = clamp((1.0 - edge_lit) * 0.62 + core * 0.45, 0.0, 1.0);
	// 3-band toon shading
	shade = smoothstep(0.30, 0.36, shade) * 0.5 + smoothstep(0.62, 0.68, shade) * 0.5;
	shade = clamp(shade + cloud_dark * 0.35, 0.0, 1.0);
	shade = mix(shade, 0.5, overcast * 0.45);
	vec3 col = mix(cloud_lit.rgb, cloud_shade.rgb, shade);
	col += sun_color.rgb * pow(max(sc, 0.0), 7.0) * (1.0 - shade) * 0.45 * sun_vis;
	// distance haze toward horizon colour
	col = mix(col, sky_horizon.rgb, (1.0 - smoothstep(0.0, 0.45, up)) * 0.65);
	return vec4(col, d);
}

vec3 moon_disc(vec3 dir, out float alpha) {
	alpha = 0.0;
	vec3 md = normalize(moon_dir);
	float mc = dot(dir, md) * smoothstep(-0.02, 0.02, dir.y);
	vec3 col = vec3(0.0);
	float halo = pow(max(mc, 0.0), 90.0) * 0.16 + pow(max(mc, 0.0), 16.0) * 0.025;
	col += moon_color.rgb * halo;
	if (mc > cos(moon_size * 1.15)) {
		vec3 up = abs(md.y) < 0.98 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 mx = normalize(cross(up, md));
		vec3 my = cross(md, mx);
		vec2 q = vec2(dot(dir, mx), dot(dir, my)) / sin(moon_size);
		float r2 = dot(q, q);
		float r = sqrt(r2);
		vec3 nrm = vec3(q, sqrt(max(1.0 - r2, 0.0)));
		float lit = clamp(dot(nrm, normalize(moon_phase)) * 2.6 + 0.12, 0.0, 1.0);
		float crater = vnoise(q * 3.2 + vec2(5.0, 2.0)) * 0.6 + vnoise(q * 7.0) * 0.4;
		lit *= mix(0.62, 1.0, smoothstep(0.30, 0.62, crater));
		alpha = smoothstep(1.0, 0.93, r);
		col = mix(col, moon_color.rgb * (0.05 + lit * 2.4), alpha);
	}
	return col;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col = base_sky(dir);
	if (AT_CUBEMAP_PASS) {
		COLOR = col;
	} else {
		float sc = dot(dir, sun_dir);
		// heavy overcast: the clear gaps between clouds are the same grey as the deck (no bright camouflage patches)
		vec3 deck = mix(cloud_lit.rgb, cloud_shade.rgb, 0.5);
		col = mix(col, deck, overcast * 0.88 * smoothstep(0.02, 0.40, dir.y));
		vec4 cl = clouds(dir, sc);
		float cover_at = cl.a;

		// stars + moon (behind clouds)
		if (stars_amt > 0.001 && dir.y > 0.0) {
			float s = star_layer(dir, 95.0, 0.90, 0.17) + star_layer(dir, 42.0, 0.965, 0.14) * 1.6;
			s *= smoothstep(0.0, 0.22, dir.y) * stars_amt * (1.0 - overcast) * (1.0 - cover_at);
			col += vec3(0.85, 0.92, 1.0) * s * 1.5;
		}
		if (moon_vis > 0.001) {
			float ma;
			vec3 mcol = moon_disc(dir, ma);
			float mvis = moon_vis * (1.0 - overcast * 0.85) * (1.0 - cover_at * 0.92);
			col = mix(col, col + mcol, mvis);
		}
		// sun disc
		if (sun_vis > 0.001) {
			float inner = cos(sun_size * 0.78);
			float outer = cos(sun_size);
			float disc = smoothstep(outer, inner, sc) * smoothstep(-0.004, 0.012, dir.y);
			float vis = sun_vis * (1.0 - overcast * 0.9) * (1.0 - cover_at * 0.95);
			col += sun_color.rgb * disc * 14.0 * vis;
		}
		if (cl.a > 0.0) {
			col = mix(col, cl.rgb, cl.a);
		}
		// lightning
		if (flash > 0.001) {
			col = mix(col, flash_color.rgb * 1.1, flash * 0.35 * (0.4 + cl.a));
			col += flash_color.rgb * cl.a * flash * 0.9;
		}
		if (bolt.w > 0.001 && dir.y > 0.0) {
			vec2 a = normalize(dir.xz + vec2(1e-5, 0.0));
			vec2 b = bolt.xy;
			float daz = atan(a.x * b.y - a.y * b.x, dot(a, b));
			float el = asin(clamp(dir.y, 0.0, 1.0));
			float seed = bolt.z;
			float j = sin(el * 23.0 + seed) * 0.010 + sin(el * 57.0 + seed * 2.3) * 0.005 + sin(el * 9.0 + seed * 0.7) * 0.022;
			float dd = abs(daz - j);
			float wdt = mix(0.0035, 0.010, clamp(el / 0.7, 0.0, 1.0));
			float line = exp(-dd * dd / (wdt * wdt));
			// side branch
			float j2 = j + (el - 0.28) * 0.35 * sign(sin(seed * 5.0));
			float dd2 = abs(daz - j2);
			float branch = exp(-dd2 * dd2 / (wdt * wdt * 0.5)) * smoothstep(0.28, 0.34, el) * smoothstep(0.62, 0.40, el);
			float vert = smoothstep(0.0, 0.06, el) * smoothstep(0.80, 0.50, el);
			float glow = exp(-dd * dd / 0.012) * 0.22;
			col += flash_color.rgb * (line + branch * 0.7 + glow) * vert * bolt.w * 6.0;
		}
		COLOR = col;
	}
}
