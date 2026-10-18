shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Halcyon Bay ground surfaces drawn procedurally (no textures): asphalt with lane markings / wear / cracks / wet look,
// junction asphalt, sidewalk paving, crosswalk + stop-line paint, dirt paths, apron concrete, runway/taxiway markings,
// parking bays, pier planks, plaza tiles.
//
// UV convention for road strips: UV.x = signed lateral metres from the centre line (right of travel = +), UV.y = metres along.
// For every other mode UV is ignored and world XZ is used. COLOR.r = pattern id for paint (0.1 zebra, 0.2 stop line, 0.3 arrow),
// COLOR.g = per-mesh random in 0..1.

global uniform float gta_wetness;
global uniform float gta_night;
global uniform float gta_rain;

// 0 road strip, 1 junction asphalt, 2 sidewalk, 3 paint, 4 dirt path, 5 curb concrete, 6 apron concrete, 7 runway,
// 8 taxiway, 9 parking lot, 10 pier planks, 11 plaza tiles, 12 yard / lot ground, 13 helipad
uniform int mode = 0;
uniform float half_w = 4.0;
uniform float lane_w = 3.7;
uniform float median_w = 0.0;
uniform int mark = 1;            // 0 none, 1 street, 2 arterial, 3 residential/hill (dashed yellow)
uniform float length_m = 220.0;  // runway length
uniform vec3 asphalt : source_color = vec3(0.285, 0.285, 0.300);
uniform vec3 paint_white : source_color = vec3(0.96, 0.95, 0.90);
uniform vec3 paint_yellow : source_color = vec3(1.0, 0.76, 0.12);
uniform vec3 concrete : source_color = vec3(0.60, 0.56, 0.50);
uniform vec3 plaza_a : source_color = vec3(0.73, 0.65, 0.53);     // warm sandstone tile
uniform vec3 plaza_b : source_color = vec3(0.65, 0.56, 0.46);     // darker sandstone tile
uniform vec3 plaza_c : source_color = vec3(0.50, 0.52, 0.52);     // cool slate accent tile (rare)
uniform vec3 dirt_col : source_color = vec3(0.60, 0.48, 0.32);
uniform vec3 plank_col : source_color = vec3(0.50, 0.37, 0.25);

varying vec3 w_pos;
varying vec4 vcol;
varying vec2 uvm;

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

// anti-aliased stripe of half-width w centred at c
float stripe(float x, float c, float w) {
	float aa = max(fwidth(x), 0.0005);
	return 1.0 - smoothstep(w - aa, w + aa, abs(x - c));
}

// dash pattern along t: on for `on` metres in every `period`
float dashes(float t, float period, float on) {
	float aa = max(fwidth(t), 0.0005);
	float f = fract(t / period) * period;
	return smoothstep(0.0, aa, f) * (1.0 - smoothstep(on - aa, on + aa, f));
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
	uvm = UV;
}

void fragment() {
	vec2 wp = w_pos.xz;
	vec3 col = asphalt;
	float rough = 0.88;
	float spec = 0.3;
	float paint = 0.0;
	vec3 paint_c = paint_white;
	float alpha = 1.0;
	float rnd = vcol.g;
	float wet = clamp(gta_wetness, 0.0, 1.0);

	if (mode == 0 || mode == 1) {
		// ---- asphalt body ----
		float n1 = vnoise(wp * 0.35);
		float n2 = vnoise(wp * 1.7 + 11.0);
		float n3 = vnoise(wp * 5.0);
		col *= 0.82 + 0.34 * n1 + 0.10 * (n2 - 0.5);
		col += (n3 - 0.5) * 0.020;
		// cool/warm drift in large patches so long roads never read as one flat colour
		col *= mix(vec3(0.96, 0.98, 1.06), vec3(1.07, 1.02, 0.95), vnoise(wp * 0.05 + 7.0));
		// tyre wear tracks along each lane
		if (mode == 0) {
			float u = abs(uvm.x);
			float lane_c = median_w * 0.5 + lane_w * 0.5;
			float track = 0.0;
			for (int k = 0; k < 2; k++) {
				float c = lane_c + float(k) * lane_w;
				track += stripe(u, c - 0.78, 0.30) + stripe(u, c + 0.78, 0.30);
			}
			col *= 1.0 - 0.17 * clamp(track, 0.0, 1.0) * (0.6 + 0.6 * n1);
			rough -= 0.05 * clamp(track, 0.0, 1.0);
		}
		// hairline cracks + patches
		float cr = abs(vnoise(wp * 1.3 + 3.0) - 0.5);
		col *= 1.0 - 0.28 * (1.0 - smoothstep(0.0, 0.018, cr)) * step(0.55, vnoise(wp * 0.11));
		float patch_n = smoothstep(0.62, 0.7, vnoise(wp * 0.22 + 20.0));
		col = mix(col, col * 0.78, patch_n * 0.7);
		// oil stains at lane centres
		float oil = smoothstep(0.78, 0.9, vnoise(wp * 0.6 + 40.0)) * 0.35;
		col *= 1.0 - oil;
		rough = 0.86 - oil * 0.2;

		if (mode == 0 && mark > 0) {
			float v = uvm.y;
			float u = uvm.x;
			float edge_l = 0.0;
			float yel = 0.0;
			float wht = 0.0;
			if (mark == 1 || mark == 2) {
				float cy = median_w * 0.5 + 0.17;
				yel += stripe(u, cy, 0.055) + stripe(u, -cy, 0.055);
				wht += stripe(abs(u), half_w - 0.35, 0.065);
			}
			if (mark == 2) {
				float lc = median_w * 0.5 + lane_w;
				wht += (stripe(u, lc, 0.06) + stripe(u, -lc, 0.06)) * dashes(v, 9.0, 3.5);
			}
			if (mark == 3) {
				yel += stripe(u, 0.0, 0.06) * dashes(v, 8.0, 3.2);
			}
			// worn paint
			float wear = 0.55 + 0.45 * smoothstep(0.15, 0.6, vnoise(wp * 2.2 + 5.0));
			paint = clamp(max(yel, wht), 0.0, 1.0) * wear;
			paint_c = mix(paint_white, paint_yellow, clamp(yel / max(yel + wht, 0.001), 0.0, 1.0));
		}
	} else if (mode == 2) {
		// ---- sidewalk paving ----
		vec2 g = wp / 1.5;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float tile = hash21(cell + 3.0);
		float hue = hash21(cell + 17.0);
		vec3 base = concrete * mix(vec3(1.06, 1.0, 0.92), vec3(0.94, 0.98, 1.06), hue);
		col = base * (0.86 + 0.26 * tile);
		float seam = 1.0 - smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		col *= 1.0 - 0.34 * seam;
		col *= 0.88 + 0.22 * vnoise(wp * 0.35) + 0.08 * (vnoise(wp * 2.3) - 0.5);
		col *= 1.0 - 0.18 * smoothstep(0.62, 0.85, vnoise(wp * 0.21 + 31.0));    // damp / dirt patches
		rough = 0.8;
		spec = 0.22;
	} else if (mode == 3) {
		// ---- paint decals ----
		float id = vcol.r;
		float u = uvm.x;
		float v = uvm.y;
		float p = 0.0;
		if (id < 0.15) {
			// zebra: bars parallel to traffic, 0.55 m bar / 0.55 m gap
			p = 1.0 - smoothstep(0.26, 0.30, abs(fract(u / 1.1 + 0.5) - 0.5) * 1.1);
		} else if (id < 0.25) {
			p = 1.0;
		} else {
			p = 1.0;
		}
		float wear = 0.5 + 0.5 * smoothstep(0.1, 0.5, vnoise(wp * 2.0 + 9.0));
		col = paint_white;
		alpha = p * wear;
		rough = 0.75;
	} else if (mode == 4) {
		float n = vnoise(wp * 0.8);
		col = dirt_col * (0.82 + 0.3 * n) * (0.92 + 0.16 * vnoise(wp * 3.0));
		rough = 0.98;
		spec = 0.1;
	} else if (mode == 5) {
		col = concrete * vec3(1.04, 1.0, 0.94) * (0.9 + 0.14 * vnoise(wp * 0.7));
		rough = 0.85;
	} else if (mode == 6) {
		// apron slabs 6 x 6 m
		vec2 g = wp / 6.0;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float tile = hash21(cell + 9.0);
		col = concrete * vec3(0.98, 1.0, 1.02) * (0.84 + 0.2 * tile) * (0.9 + 0.14 * vnoise(wp * 0.6));
		float seam = 1.0 - smoothstep(0.0, 0.012, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		col *= 1.0 - 0.25 * seam;
		// tyre / oil marks
		col *= 1.0 - 0.15 * smoothstep(0.7, 0.85, vnoise(wp * 0.25 + 4.0));
		rough = 0.8;
	} else if (mode == 7 || mode == 8) {
		// runway / taxiway asphalt with markings. UV.x = lateral from centreline, UV.y = along (m)
		float n1 = vnoise(wp * 0.3);
		col = asphalt * (mode == 7 ? 1.05 : 1.12) * (0.80 + 0.40 * n1 + 0.08 * (vnoise(wp * 1.9 + 5.0) - 0.5));
		col *= 1.0 - 0.18 * smoothstep(0.5, 0.8, vnoise(wp * 0.15 + 3.0)) * 0.5;
		col *= mix(vec3(0.96, 0.98, 1.05), vec3(1.07, 1.02, 0.95), vnoise(wp * 0.04 + 11.0));     // cool / warm drift: long runways never read as one flat colour
		float u = uvm.x;
		float v = uvm.y;
		col *= 1.0 - 0.14 * smoothstep(1.2, 0.2, abs(abs(u) - 1.6)) * (0.5 + 0.5 * vnoise(vec2(v * 0.3, u)));   // wheel-track polish along the runway
		col *= 1.0 - 0.28 * smoothstep(0.55, 0.9, vnoise(vec2(v * 0.55, u * 0.7) + 2.0)) * smoothstep(8.0, 30.0, v);   // rubber / oil streaks
		rough = 0.85;
		float wear = 0.65 + 0.35 * smoothstep(0.1, 0.6, vnoise(wp * 2.0));
		if (mode == 7) {
			float hwid = half_w;
			float cl = stripe(u, 0.0, 0.18) * dashes(v - 12.0, 36.0, 22.0) * step(12.0, v) * step(v, length_m - 12.0);
			float edge = stripe(abs(u), hwid - 0.5, 0.15);
			// threshold piano keys at both ends
			float key = 0.0;
			float uu = clamp(u, -hwid + 1.5, hwid - 1.5);
			float kbar = step(0.5, fract((uu + hwid) / 1.8)) ;
			float at_start = step(2.0, v) * step(v, 11.0);
			float at_end = step(length_m - 11.0, v) * step(v, length_m - 2.0);
			key = kbar * (at_start + at_end) * step(abs(u), hwid - 1.2);
			// touchdown zone bars
			float tz = 0.0;
			for (int i = 0; i < 3; i++) {
				float d = 24.0 + float(i) * 14.0;
				float b1 = step(d, v) * step(v, d + 3.0) * step(3.5, abs(u)) * step(abs(u), 7.0);
				float b2 = step(length_m - d - 3.0, v) * step(v, length_m - d) * step(3.5, abs(u)) * step(abs(u), 7.0);
				tz += b1 + b2;
			}
			paint = clamp(cl + edge + key + tz, 0.0, 1.0) * wear;
		} else {
			float cl = stripe(u, 0.0, 0.11);
			float edge = stripe(abs(u), half_w - 0.4, 0.09);
			paint = clamp(cl + edge * 0.0, 0.0, 1.0) * wear;
			paint_c = paint_yellow;
		}
	} else if (mode == 9) {
		// parking lot asphalt with bay lines every 2.6 m (bays along world X rows)
		col = asphalt * (0.95 + 0.15 * vnoise(wp * 0.5));
		col *= 1.0 - 0.2 * smoothstep(0.7, 0.9, vnoise(wp * 0.3 + 6.0));
		float bx = stripe(fract(wp.x / 5.2 + 0.5) - 0.5, 0.0, 0.015);
		float row = fract(wp.y / 14.0);
		float inrow = step(0.0, row) * step(row, 0.36);
		paint = bx * inrow * 0.8;
		rough = 0.88;
	} else if (mode == 10) {
		// pier planks: boards run along world Z, 0.22 m wide
		float b = floor(wp.x / 0.22);
		float f = fract(wp.x / 0.22);
		float tone = hash21(vec2(b, floor(wp.y / 3.3)));
		col = plank_col * (0.78 + 0.35 * tone);
		col *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.06, min(f, 1.0 - f)));
		rough = 0.9;
		spec = 0.15;
	} else if (mode == 11) {
		// plaza: 2.4 m tiles in a sandstone / terracotta checker with the odd slate accent, inlay lines, grout, mottling, wear
		vec2 g = wp / 2.4;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float checker = mod(cell.x + cell.y, 2.0);
		float acc = step(0.965, hash21(cell + 5.0));
		vec3 t = mix(plaza_a, plaza_b, checker);
		t = mix(t, plaza_c, acc);
		col = t * (0.90 + 0.18 * hash21(cell)) * mix(vec3(1.05, 1.0, 0.94), vec3(0.95, 0.99, 1.04), hash21(cell + 13.0));
		vec2 e = min(f, 1.0 - f);
		float md = min(e.x, e.y);
		float inlay = smoothstep(0.075, 0.085, md) * (1.0 - smoothstep(0.105, 0.115, md));
		col = mix(col, col * 1.14 + vec3(0.02), inlay * 0.6);
		float seam = 1.0 - smoothstep(0.0, 0.032, md);
		col *= 1.0 - 0.38 * seam;
		col *= 0.86 + 0.24 * vnoise(wp * 0.22) + 0.08 * (vnoise(wp * 1.9) - 0.5);
		col *= 1.0 - 0.2 * smoothstep(0.6, 0.85, vnoise(wp * 0.16 + 12.0));
		rough = 0.72;
		spec = 0.28;
	} else if (mode == 12) {
		float n = vnoise(wp * 0.3);
		col = mix(vec3(0.20, 0.21, 0.21), vec3(0.27, 0.25, 0.22), n) * (0.88 + 0.2 * vnoise(wp * 1.5));
		rough = 0.9;
	} else if (mode == 13) {
		// helipad disc with H (UV centred, metres)
		vec2 q = uvm;
		float r = length(q);
		col = vec3(0.30, 0.31, 0.34);
		float ring = stripe(r, half_w - 0.8, 0.28);
		float hbar = step(abs(q.x), 2.6) * step(abs(q.y), 0.55);
		float hleg = step(abs(abs(q.x) - 2.3), 0.5) * step(abs(q.y), 3.2);
		paint = clamp(ring + hbar + hleg, 0.0, 1.0);
		paint_c = paint_yellow;
		rough = 0.8;
	}

	vec3 final_col = mix(col, paint_c, paint);
	// wet look: darker, glossier, puddles in low-frequency patches
	float puddle = smoothstep(0.45, 0.75, vnoise(wp * 0.12 + 17.0));
	float wetmask = wet * (0.55 + 0.45 * puddle);
	vec3 refl = vec3(0.0);
	if (mode != 3) {
		final_col *= 1.0 - 0.36 * wetmask;
		rough = mix(rough, 0.12, wetmask * (1.0 - paint * 0.5));
		spec = mix(spec, 0.95, wetmask);
		if (wetmask > 0.03 && gta_night > 0.05) {
			// cheap fake of lamp / neon reflections: blobs stretched along the street (road v / world z), strongest at grazing angles
			vec2 sp = (mode == 0) ? vec2(uvm.x * 0.7, uvm.y * 0.035) : vec2(wp.x * 0.6, wp.y * 0.04);
			vec2 cid = floor(sp);
			float h = hash21(cid);
			vec2 q = fract(sp) - 0.5;
			float blob = exp(-(q.x * q.x * 16.0 + q.y * q.y * 1.4));
			vec3 neon = h < 0.5 ? vec3(1.0, 0.62, 0.26) : (h < 0.72 ? vec3(1.0, 0.22, 0.56) : vec3(0.22, 0.82, 1.0));
			float keep = step(0.62, hash21(cid + 9.0));
			float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
			refl = neon * blob * keep * gta_night * wetmask * (0.12 + 0.9 * fres) * 0.55;
		}
	}
	ALBEDO = final_col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	// retro-reflective paint glints a little at night, wet streets mirror the lights
	EMISSION = paint_c * paint * 0.05 * gta_night + refl;
	if (mode == 3) {
		ALPHA = alpha;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
