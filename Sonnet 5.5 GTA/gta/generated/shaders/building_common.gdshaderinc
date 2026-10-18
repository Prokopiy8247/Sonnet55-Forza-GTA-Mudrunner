// Shared helpers for the building_* shaders (Halcyon Bay world content).
// Palette table: 4 wall palettes x 6 slots [WallA, WallB, WallC, WallD, Roof, Trim] in sRGB (converted in-shader).

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 srgb2lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

const vec3 BLD_PAL[24] = vec3[24](
	// 0 coral & cream: WallA warm cream, WallB coral, WallC dusty teal, WallD sand, Roof terracotta, Trim plum-charcoal
	vec3(0.961, 0.839, 0.702), vec3(0.922, 0.400, 0.322), vec3(0.280, 0.500, 0.620), vec3(0.840, 0.700, 0.580), vec3(0.620, 0.300, 0.240), vec3(0.340, 0.260, 0.280),
	// 1 teal & mint & mustard: mint, teal, mustard, sage, slate roof, deep teal trim
	vec3(0.780, 0.910, 0.840), vec3(0.120, 0.580, 0.580), vec3(0.960, 0.740, 0.260), vec3(0.580, 0.720, 0.580), vec3(0.240, 0.320, 0.380), vec3(0.140, 0.280, 0.320),
	// 2 brick & mustard: butter, brick, mustard, clay, dark brown roof, oxblood trim
	vec3(0.940, 0.820, 0.620), vec3(0.640, 0.280, 0.220), vec3(0.880, 0.640, 0.200), vec3(0.800, 0.580, 0.460), vec3(0.300, 0.220, 0.220), vec3(0.360, 0.200, 0.170),
	// 3 dusty blue & navy: pale sky, navy, dusty blue, steel, charcoal roof, ink-navy trim
	vec3(0.760, 0.840, 0.920), vec3(0.200, 0.280, 0.460), vec3(0.460, 0.580, 0.740), vec3(0.600, 0.640, 0.700), vec3(0.240, 0.260, 0.300), vec3(0.160, 0.200, 0.300)
);

// Emission colour of one lit window pane (rgb, 0 when dark).
// cell: integer pane id, bseed/iseed: building / instance random 0..1, night 0..1, hour 0..24 game clock.
vec3 window_light(vec2 cell, float bseed, float iseed, float night, float hour, out float tv) {
	float r1 = hash13(vec3(cell, bseed * 57.3 + iseed * 13.7));
	float r2 = hash13(vec3(cell + 11.1, bseed * 31.1 + iseed * 7.7));
	float r3 = hash13(vec3(cell + 23.7, bseed * 17.9 + iseed * 3.3));
	float r4 = hash13(vec3(cell + 5.3, bseed * 43.7 + iseed * 19.1));
	float r5 = hash13(vec3(cell + 41.9, bseed * 11.3 + iseed * 29.9));
	float occupancy = mix(0.30, 0.86, hash11(bseed * 91.7 + 3.1));
	float owned = step(r1, occupancy);
	float evening = smoothstep(r2 * 0.7, r2 * 0.7 + 0.12, night);
	float h = hour < 12.0 ? hour + 24.0 : hour;
	float bedtime = 1.0 - smoothstep(22.5 + r3 * 5.0, 23.5 + r3 * 5.0, h);
	float lit = owned * evening * max(bedtime, step(0.86, r5)) * step(0.04, night);
	vec3 col = vec3(1.0, 0.76, 0.42);
	tv = 0.0;
	if (r4 > 0.55) col = vec3(1.0, 0.62, 0.30);
	if (r4 > 0.80) col = vec3(1.0, 0.90, 0.70);
	if (r4 > 0.90) { col = vec3(0.35, 0.82, 1.0); tv = 1.0; }
	if (r4 > 0.965) { col = vec3(1.0, 0.30, 0.68); tv = 0.0; }
	return col * lit;
}
