using System.Runtime.CompilerServices;
using Unity.Mathematics;

namespace MudRunner.Rendering
{
    /// <summary>
    /// Burst-friendly procedural pattern library. Every function is periodic with period 1 in uv (integer lattice
    /// frequencies wrap), so everything built from it tiles seamlessly. No managed allocations, no static arrays.
    /// </summary>
    public static class GroundPatterns
    {
        // ------------------------------------------------------------------ hashing / noise primitives

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static uint H(uint x)
        {
            x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
            return x;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static uint H2(int x, int y, uint seed)
        {
            return H(H((uint)x + seed * 0x9E3779B9U) ^ ((uint)y * 0x85EBCA6BU + 0x165667B1U));
        }

        /// <summary>uint hash to 0..1</summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        public static float R(uint h) { return (h >> 8) * (1f / 16777216f); }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static int Wrap(int i, int per) { int m = i % per; return m < 0 ? m + per : m; }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static float Grad(uint h, float x, float y)
        {
            switch (h & 7u)
            {
                case 0: return x + y;
                case 1: return -x + y;
                case 2: return x - y;
                case 3: return -x - y;
                case 4: return x * 1.41421f;
                case 5: return -x * 1.41421f;
                case 6: return y * 1.41421f;
                default: return -y * 1.41421f;
            }
        }

        /// <summary>Periodic gradient noise, roughly -1..1 (typically +-0.5). Periods perX/perY in lattice cells.</summary>
        public static float Perlin(float2 p, int perX, int perY, uint seed)
        {
            float2 fl = math.floor(p);
            int x0 = (int)fl.x, y0 = (int)fl.y;
            float fx = p.x - fl.x, fy = p.y - fl.y;
            float u = fx * fx * fx * (fx * (fx * 6f - 15f) + 10f);
            float v = fy * fy * fy * (fy * (fy * 6f - 15f) + 10f);
            int xa = Wrap(x0, perX), xb = Wrap(x0 + 1, perX), ya = Wrap(y0, perY), yb = Wrap(y0 + 1, perY);
            float n00 = Grad(H2(xa, ya, seed), fx, fy);
            float n10 = Grad(H2(xb, ya, seed), fx - 1f, fy);
            float n01 = Grad(H2(xa, yb, seed), fx, fy - 1f);
            float n11 = Grad(H2(xb, yb, seed), fx - 1f, fy - 1f);
            return math.lerp(math.lerp(n00, n10, u), math.lerp(n01, n11, u), v) * 1.15f;
        }

        /// <summary>Periodic fBm; baseFreq lattice cells across the tile, doubling per octave. ~ -1..1 (typ. +-0.45).</summary>
        public static float Fbm(float2 uv, int baseFreq, int oct, float gain, uint seed)
        {
            float sum = 0f, amp = 1f, nrm = 0f;
            int f = baseFreq;
            for (int o = 0; o < oct; o++)
            {
                sum += amp * Perlin(uv * f, f, f, seed + (uint)o * 7919U);
                nrm += amp; amp *= gain; f <<= 1;
            }
            return sum / nrm;
        }

        /// <summary>Periodic cellular noise. f1/f2 = distance to nearest/second nearest feature (cell units), id = hash of nearest cell, vec = vector pixel->feature.</summary>
        public static void Worley(float2 uv, int freq, uint seed, out float f1, out float f2, out uint id, out float2 vec)
        {
            float2 p = uv * freq;
            float2 fl = math.floor(p);
            int ix = (int)fl.x, iy = (int)fl.y;
            float2 fp = p - fl;
            float d1 = 8f, d2 = 8f; uint bid = 0; float2 bv = default;
            for (int dy = -1; dy <= 1; dy++)
                for (int dx = -1; dx <= 1; dx++)
                {
                    uint h = H2(Wrap(ix + dx, freq), Wrap(iy + dy, freq), seed);
                    float2 o = new float2(R(h), R(H(h ^ 0xA511E9B3U)));
                    float2 r = new float2(dx, dy) + o * 0.8f + 0.1f - fp;
                    float d = math.dot(r, r);
                    if (d < d1) { d2 = d1; d1 = d; bid = h; bv = r; }
                    else if (d < d2) d2 = d;
                }
            f1 = math.sqrt(d1); f2 = math.sqrt(d2); id = bid; vec = bv;
        }

        /// <summary>Randomly oriented tapered line segments (grass blades, needles, fibres). len/halfWidth in cell units. Returns coverage 0..1.</summary>
        public static float Blades(float2 uv, int freq, uint seed, float len, float halfWidth, out float rnd, out float along)
        {
            float2 p = uv * freq;
            float2 fl = math.floor(p);
            int ix = (int)fl.x, iy = (int)fl.y;
            float2 fp = p - fl;
            float best = 0f; rnd = 0f; along = 0f;
            for (int dy = -1; dy <= 1; dy++)
                for (int dx = -1; dx <= 1; dx++)
                {
                    uint h = H2(Wrap(ix + dx, freq), Wrap(iy + dy, freq), seed);
                    float2 o = new float2(R(h), R(H(h ^ 0xA511E9B3U)));
                    float ang = R(H(h ^ 0x68E31DA4U)) * 6.2831853f;
                    math.sincos(ang, out float s, out float c);
                    float2 dir = new float2(c, s);
                    float2 r = fp - (new float2(dx, dy) + o);
                    float half = 0.5f * len;
                    float t = math.clamp(math.dot(r, dir), -half, half);
                    float dist = math.length(r - dir * t);
                    float taper = 1f - 0.75f * math.abs(t) / half;
                    float hw = halfWidth * taper;
                    float cov = 1f - math.smoothstep(hw * 0.55f, hw, dist);
                    if (cov > best) { best = cov; rnd = R(H(h ^ 0x1B873593U)); along = t / len + 0.5f; }
                }
            return best;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static float Sat(float x) { return math.saturate(x); }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static float SS(float a, float b, float x) { return math.smoothstep(a, b, x); }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        static float2 Warp(float2 uv, int freq, uint seed, float amount)
        {
            return uv + amount * new float2(Fbm(uv, freq, 3, 0.5f, seed), Fbm(uv, freq, 3, 0.5f, seed + 101U));
        }

        /// <summary>Round pebble/stone layer. Returns mask, writes height dome and a colour.</summary>
        static float Stones(float2 p, int freq, uint seed, float rMin, float rMax, float density, out float hgt, out float3 col, out float edgeAO)
        {
            Worley(p, freq, seed, out float f1, out float f2, out uint id, out float2 vec);
            float rr = R(id);
            float has = rr < density ? 1f : 0f;
            float r = math.lerp(rMin, rMax, R(H(id ^ 0x3C6EF372U)));
            // wobbly outline
            r *= 1f + 0.18f * Perlin(p * (freq * 2), freq * 2, freq * 2, seed + 9U);
            float e = f1 / r;
            float mask = (1f - SS(0.80f, 1.0f, e)) * has;
            hgt = math.sqrt(Sat(1f - e * e)) * has * math.lerp(0.55f, 1f, R(H(id ^ 0x510E527FU)));
            float k = R(H(id ^ 0x9B05688CU));
            float3 c;
            if (k < 0.26f) c = new float3(0.52f, 0.51f, 0.49f);        // grey
            else if (k < 0.54f) c = new float3(0.68f, 0.61f, 0.49f);   // tan
            else if (k < 0.80f) c = new float3(0.71f, 0.68f, 0.62f);   // pale
            else if (k < 0.90f) c = new float3(0.42f, 0.40f, 0.38f);   // dark
            else c = new float3(0.60f, 0.44f, 0.34f);                  // rusty
            float shade = 0.70f + 0.45f * hgt;
            float fine = 1f + 0.22f * Perlin(p * (freq * 6), freq * 6, freq * 6, seed + 33U);
            col = c * shade * fine;
            edgeAO = 1f - 0.34f * (1f - SS(0.9f, 1.55f, e)) * (1f - mask);   // dark halo around a stone
            return mask;
        }

        // ------------------------------------------------------------------ the 8 surface layers
        // out: col = sRGB albedo, sm = smoothness 0..1, h = height 0..1

        public static void Rock(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 p = Warp(uv, 3, 11U, 0.03f);
            Worley(p, 8, 21U, out float f1, out float f2, out uint id, out float2 vec);
            float edge = f2 - f1;
            float crackWide = 1f - SS(0f, 0.08f, edge);
            float crackCore = 1f - SS(0f, 0.022f, edge);
            Worley(p + 0.31f, 13, 22U, out float g1, out float g2, out uint id2, out float2 vec2);
            float edge2 = g2 - g1;
            float crack2 = (1f - SS(0f, 0.035f, edge2)) * SS(0.35f, 0.7f, R(H(id2)));
            float strata = Perlin(new float2(p.x * 2f, p.y * 26f), 2, 26, 23U);
            float strata2 = Perlin(new float2(p.x * 5f, p.y * 70f), 5, 70, 24U);
            float mid = Fbm(p, 6, 4, 0.5f, 26U);
            float grain = Fbm(p, 28, 3, 0.55f, 25U);
            float cellR = R(H(id));
            float tone = Sat(0.5f + 0.9f * mid + 0.55f * strata + 0.25f * grain);
            float3 baseC = math.lerp(new float3(0.20f, 0.20f, 0.21f), new float3(0.52f, 0.51f, 0.49f), tone);
            baseC *= math.lerp(new float3(1f), new float3(1.06f, 1.0f, 0.92f), cellR * 0.6f);
            float lich = SS(0.12f, 0.30f, Fbm(p, 9, 4, 0.55f, 27U) + 0.25f * grain);
            baseC = math.lerp(baseC, new float3(0.46f, 0.50f, 0.28f), lich * 0.22f);
            float dark = 1f - 0.60f * crackCore - 0.16f * crackWide - 0.30f * crack2;
            col = baseC * dark;
            h = 0.30f * cellR + 0.22f * mid + 0.12f * strata + 0.08f * strata2 + 0.07f * grain + 0.35f;
            h -= 0.42f * crackWide + 0.25f * crack2;
            h = Sat(h);
            sm = (0.16f + 0.25f * tone) * (1f - 0.5f * crackCore);
        }

        public static void FirmSoil(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 p = Warp(uv, 3, 31U, 0.03f);
            float mid = Fbm(p, 5, 4, 0.5f, 32U);
            float grain = Fbm(p, 64, 3, 0.55f, 33U);
            float3 c = math.lerp(new float3(0.34f, 0.255f, 0.175f), new float3(0.55f, 0.43f, 0.30f), Sat(0.5f + 0.9f * mid));
            c *= 1f + 0.35f * grain;
            // clods and dry cracks
            Worley(p, 9, 34U, out float f1, out float f2, out uint id, out float2 vec);
            float edge = f2 - f1;
            float crack = (1f - SS(0f, 0.07f, edge)) * SS(0.25f, 0.6f, 0.5f + mid);
            float clod = SS(0f, 0.55f, f1);
            c *= 1f - 0.30f * crack;
            c *= 0.90f + 0.16f * (1f - clod) + 0.1f * R(H(id));
            h = 0.5f + 0.20f * mid + 0.10f * grain + 0.14f * (1f - clod) - 0.16f * crack;
            // pebbles
            float peb = Stones(p, 34, 35U, 0.16f, 0.34f, 0.16f, out float ph, out float3 pc, out float ao);
            c *= ao;
            c = math.lerp(c, pc * new float3(0.95f, 0.9f, 0.85f), peb);
            h += 0.35f * ph;
            col = c;
            h = Sat(h);
            sm = 0.10f + 0.12f * peb;
        }

        public static void Grass(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 p = Warp(uv, 3, 41U, 0.025f);
            float mid = Fbm(p, 4, 4, 0.5f, 42U);
            float grain = Fbm(p, 48, 3, 0.55f, 43U);
            float3 c = math.lerp(new float3(0.115f, 0.10f, 0.045f), new float3(0.23f, 0.18f, 0.08f), Sat(0.5f + 1.0f * grain));
            // moss
            float moss = SS(0.02f, 0.28f, Fbm(p, 6, 4, 0.55f, 44U));
            float3 mossC = math.lerp(new float3(0.10f, 0.22f, 0.045f), new float3(0.18f, 0.33f, 0.07f), Sat(0.5f + 1.2f * grain));
            c = math.lerp(c, mossC, moss * 0.85f);
            // dry needles / twigs
            float nR, nA;
            float needles = Blades(p, 46, 45U, 3.6f, 0.11f, out nR, out nA);
            float3 needleC = math.lerp(new float3(0.34f, 0.20f, 0.085f), new float3(0.46f, 0.31f, 0.14f), nR);
            c = math.lerp(c, needleC, needles * 0.85f * SS(0.35f, 0.7f, nR));
            // grass blades (two densities)
            float r2, a2, r1, a1;
            float b2 = Blades(p + 0.37f, 44, 46U, 2.8f, 0.17f, out r2, out a2);
            float b1 = Blades(p, 72, 47U, 2.4f, 0.19f, out r1, out a1);
            float lush = Sat(0.55f + 0.9f * mid);
            float3 g2c = math.lerp(new float3(0.15f, 0.27f, 0.045f), new float3(0.34f, 0.46f, 0.10f), r2 * 0.6f + 0.4f * a2) ;
            float3 g1c = math.lerp(new float3(0.20f, 0.34f, 0.06f), new float3(0.44f, 0.55f, 0.14f), r1 * 0.5f + 0.5f * a1);
            g2c = math.lerp(g2c, new float3(0.42f, 0.44f, 0.12f), (1f - lush) * 0.6f);
            g1c = math.lerp(g1c, new float3(0.46f, 0.47f, 0.13f), (1f - lush) * 0.5f);
            c = math.lerp(c, g2c, b2 * 0.92f);
            c = math.lerp(c, g1c, b1 * 0.92f);
            // tuft centres: darker, lush
            Worley(p, 8, 48U, out float f1, out float f2, out uint id, out float2 vec);
            float tuft = 1f - SS(0f, 0.5f, f1);
            c *= 1f - 0.22f * (1f - tuft);
            col = c;
            h = Sat(0.35f + 0.25f * mid + 0.28f * b2 + 0.30f * b1 + 0.2f * tuft + 0.08f * grain);
            sm = 0.10f + 0.10f * b1;
        }

        public static void Gravel(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 p = Warp(uv, 3, 51U, 0.02f);
            float mid = Fbm(p, 10, 4, 0.5f, 52U);
            float grain = Fbm(p, 110, 2, 0.6f, 53U);
            float3 soil = math.lerp(new float3(0.46f, 0.41f, 0.34f), new float3(0.66f, 0.60f, 0.50f), Sat(0.5f + 0.9f * mid));
            soil *= 1f + 0.40f * grain;
            float3 c = soil; h = 0.30f + 0.10f * mid + 0.05f * grain;
            // three stone scales, bigger ones on top
            float hh; float3 sc; float ao;
            float m3 = Stones(p, 96, 54U, 0.30f, 0.46f, 0.75f, out hh, out sc, out ao);
            c *= ao; c = math.lerp(c, sc, m3); h = math.max(h, 0.35f + 0.28f * hh * m3);
            float m2 = Stones(p + 0.13f, 56, 55U, 0.32f, 0.47f, 0.80f, out hh, out sc, out ao);
            c *= ao; c = math.lerp(c, sc, m2); h = math.max(h, 0.30f + 0.45f * hh * m2);
            float m1 = Stones(p + 0.29f, 30, 56U, 0.34f, 0.48f, 0.72f, out hh, out sc, out ao);
            c *= ao; c = math.lerp(c, sc, m1); h = math.max(h, 0.25f + 0.65f * hh * m1);
            col = c;
            h = Sat(h);
            sm = 0.18f + 0.14f * math.max(m1, math.max(m2, m3));
        }

        public static void ShallowMud(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 p = Warp(uv, 2, 61U, 0.06f);
            float big = Fbm(p, 3, 5, 0.55f, 62U);
            float lumps = Fbm(p, 14, 4, 0.55f, 63U);
            float3 c = math.lerp(new float3(0.20f, 0.145f, 0.10f), new float3(0.35f, 0.26f, 0.18f), Sat(0.5f + 1.1f * big));
            c *= 1f + 0.22f * lumps;
            // slow ripples / drag marks
            float phase = 5f * uv.x + 3f * uv.y + 3.2f * big + 1.1f * Fbm(p, 8, 3, 0.5f, 64U);
            float rip = 0.5f + 0.5f * math.sin(6.2831853f * phase);
            c *= 0.93f + 0.14f * rip;
            // wet sheen patches and glints
            float wetp = SS(-0.05f, 0.25f, Fbm(p, 6, 3, 0.5f, 65U));
            Worley(p, 17, 66U, out float f1, out float f2, out uint id, out float2 vec);
            float glint = (R(id) > 0.78f ? 1f : 0f) * (1f - SS(0.12f, 0.34f, f1));
            c = math.lerp(c, c * 0.55f, glint);
            // a few embedded pebbles
            float peb = Stones(p, 22, 67U, 0.12f, 0.24f, 0.03f, out float ph, out float3 pc, out float ao);
            c = math.lerp(c, pc * 0.55f, peb);
            col = c;
            h = Sat(0.45f + 0.30f * big + 0.12f * lumps + 0.10f * rip * (1f - glint) + 0.2f * ph);
            sm = Sat(0.34f + 0.24f * wetp + 0.16f * glint - 0.06f * lumps);
        }

        public static void DeepMud(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 w1 = Warp(uv, 2, 71U, 0.09f);
            float2 p = Warp(w1, 3, 72U, 0.05f);
            float flow = Fbm(p, 3, 5, 0.55f, 73U);
            float ridged = 1f - math.abs(Fbm(p, 4, 4, 0.5f, 74U) * 2.4f);
            float folds = math.pow(Sat(ridged), 3f);
            float fine = Fbm(p, 20, 3, 0.55f, 75U);
            float3 c = math.lerp(new float3(0.11f, 0.077f, 0.052f), new float3(0.27f, 0.195f, 0.130f), Sat(0.5f + 1.1f * flow));
            c *= 1f + 0.20f * fine;
            c += new float3(0.050f, 0.033f, 0.018f) * folds;
            // bubbles with bright rims
            Worley(p, 21, 76U, out float f1, out float f2, out uint id, out float2 vec);
            float isB = R(id) > 0.84f ? 1f : 0f;
            float rr = 0.26f;
            float ring = SS(rr - 0.07f, rr - 0.01f, f1) * (1f - SS(rr - 0.01f, rr + 0.05f, f1)) * isB;
            float dome = (1f - SS(0f, rr, f1)) * isB;
            c += new float3(0.035f, 0.025f, 0.015f) * ring;
            col = c;
            h = Sat(0.45f + 0.35f * flow + 0.18f * folds + 0.15f * ring + 0.10f * dome);
            sm = Sat(0.46f + 0.18f * Sat(0.5f + flow) + 0.12f * folds);
        }

        public static void Bog(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 p = Warp(uv, 2, 81U, 0.07f);
            float peat = Fbm(p, 8, 5, 0.55f, 82U);
            float3 c = math.lerp(new float3(0.050f, 0.040f, 0.026f), new float3(0.105f, 0.082f, 0.050f), Sat(0.5f + 1.2f * peat));
            // plant fibres
            float fR, fA;
            float fib = Blades(p, 58, 83U, 3.8f, 0.20f, out fR, out fA);
            c = math.lerp(c, math.lerp(new float3(0.10f, 0.075f, 0.04f), new float3(0.19f, 0.15f, 0.08f), fR), fib * 0.75f);
            // black open water pockets
            float waterF = Fbm(p + 0.2f, 3, 4, 0.55f, 84U);
            float water = SS(0.12f, 0.20f, waterF);
            // algae film
            float algF = Fbm(p, 4, 5, 0.55f, 85U);
            float alg = SS(-0.06f, 0.22f, algF);
            float3 algC = math.lerp(new float3(0.050f, 0.110f, 0.028f), new float3(0.20f, 0.30f, 0.065f), Sat(0.5f + 1.3f * Fbm(p, 22, 3, 0.55f, 86U)));
            c = math.lerp(c, algC, alg * 0.85f * (1f - water));
            // dark mirror water
            c = math.lerp(c, new float3(0.022f, 0.026f, 0.018f), water);
            // duckweed specks on the water
            Worley(p, 90, 87U, out float f1, out float f2, out uint id, out float2 vec);
            float dw = (R(id) > 0.72f ? 1f : 0f) * (1f - SS(0.10f, 0.22f, f1)) * SS(0.0f, 0.5f, water + 0.2f);
            c = math.lerp(c, math.lerp(new float3(0.16f, 0.32f, 0.06f), new float3(0.28f, 0.46f, 0.10f), R(H(id))), dw);
            col = c;
            h = Sat(0.42f + 0.22f * peat + 0.28f * fib * (1f - water) + 0.12f * alg - 0.2f * water);
            sm = Sat(math.lerp(0.26f, 0.60f, alg) * (1f - water) + 0.95f * water - 0.2f * fib);
        }

        public static void Sand(float2 uv, out float3 col, out float sm, out float h)
        {
            float2 p = Warp(uv, 3, 91U, 0.03f);
            float mid = Fbm(p, 5, 4, 0.5f, 92U);
            float warpPh = 2.4f * Fbm(p, 3, 4, 0.5f, 93U) + 0.7f * Fbm(p, 9, 3, 0.5f, 94U);
            float rip = 0.5f + 0.5f * math.sin(6.2831853f * (7f * uv.x + 3f * uv.y + warpPh));
            float rip2 = 0.5f + 0.5f * math.sin(6.2831853f * (23f * uv.x - 9f * uv.y + 3f * warpPh));
            float grain = Fbm(p, 160, 2, 0.6f, 95U);
            float3 c = math.lerp(new float3(0.64f, 0.53f, 0.34f), new float3(0.80f, 0.70f, 0.49f), Sat(0.5f + 0.9f * mid));
            c *= 0.90f + 0.16f * rip + 0.05f * rip2;
            c *= 1f + 0.18f * grain;
            // sparse pebbles / shell bits
            float peb = Stones(p, 40, 96U, 0.14f, 0.28f, 0.07f, out float ph, out float3 pc, out float ao);
            c = math.lerp(c, pc * new float3(1.0f, 0.95f, 0.88f), peb);
            col = c;
            h = Sat(0.30f + 0.38f * rip + 0.10f * rip2 + 0.08f * grain + 0.25f * ph);
            sm = Sat(0.07f + 0.05f * rip + 0.06f * peb);
        }

        // ------------------------------------------------------------------ non-layer textures

        /// <summary>Macro variation: 4 channels of tileable noise at different scales (0..1).</summary>
        public static float4 Macro(float2 uv)
        {
            float a = Fbm(uv, 3, 5, 0.55f, 101U);
            float b = Fbm(uv, 6, 5, 0.55f, 102U);
            float c = Fbm(uv, 12, 4, 0.55f, 103U);
            Worley(Warp(uv, 4, 105U, 0.05f), 5, 104U, out float f1, out float f2, out uint id, out float2 vec);
            return new float4(Sat(0.5f + 1.2f * a), Sat(0.5f + 1.2f * b), Sat(0.5f + 1.3f * c), Sat(0.2f + f1 * 0.9f * 1.2f + 0.15f * R(id)));
        }

        /// <summary>Detail height for the fine-grain detail normal map.</summary>
        public static float DetailHeight(float2 uv)
        {
            float a = Fbm(uv, 24, 3, 0.55f, 111U);
            Worley(uv, 40, 112U, out float f1, out float f2, out uint id, out float2 vec);
            float bump = (1f - SS(0f, 0.6f, f1)) * R(id);
            return 0.5f + 0.9f * a + 0.35f * bump;
        }
    }
}
