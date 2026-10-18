extends RefCounted
## Synth - GDScript DSP toolkit for ORIGINAL, fully procedural audio (no samples from anywhere).
##
## Everything works on mono PackedFloat32Array buffers (range about -1..1) and returns NEW buffers
## (callers reassign:  buf = Synth.lp1(buf, 800.0)).  Time arguments are in seconds, the sample rate defaults to SR.
## All functions are static, allocate only their own output and touch no global state, so they are safe to run on
## WorkerThreadPool threads concurrently.
##
## Contents:  oscillators (sine/saw/square/triangle + FM + sweeps), noise (white/pink/brown/crackle/smooth random),
## envelopes (ADSR, exponential decay, breakpoint), filters (one-pole, RBJ biquad incl. swept cutoff, formant bank),
## delay / comb / allpass / Schroeder reverb / slap echoes, distortion (tanh, hard clip, fold, bit-crush), resampling,
## granular bursts, glottal voice source, mixing / normalising / loop-seam helpers and AudioStreamWAV conversion.
##
## Speed (measured in this project, GDScript 4.7): ~0.1-0.3 us per sample per simple pass => one second of 22.05 kHz
## audio costs ~3-8 ms per pass.

const SR := 22050

enum Wave { SINE, SAW, SQUARE, TRI }
enum Filt { LP, HP, BP, NOTCH, PEAK, LOWSHELF, HIGHSHELF, ALLPASS }


# =========================================================================================================
# Construction helpers
# =========================================================================================================
static func zeros(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(n, 0))
	return b


static func secs(t: float, sr: int = SR) -> int:
	return maxi(1, int(round(t * float(sr))))


static func filled(n: int, v: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(n, 0))
	b.fill(v)
	return b


static func db_to_lin(db: float) -> float:
	return pow(10.0, db / 20.0)


static func midi_to_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Linear ramp a -> b over n samples.
static func ramp(n: int, a: float, b: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var d: float = (b - a) / float(maxi(n - 1, 1))
	var v: float = a
	for i in n:
		out[i] = v
		v += d
	return out


## Exponential ramp a -> b (both > 0) over n samples (e.g. pitch glides).
static func expramp(n: int, a: float, b: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var r: float = pow(b / a, 1.0 / float(maxi(n - 1, 1)))
	var v: float = a
	for i in n:
		out[i] = v
		v *= r
	return out


## Slow sine LFO as a per-sample control buffer: center + depth * sin(...).
static func lfo(n: int, hz: float, center: float, depth: float, sr: int = SR, phase0: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var ph: float = phase0
	var inc: float = hz / float(sr)
	for i in n:
		out[i] = center + depth * sin(ph * TAU)
		ph += inc
		if ph >= 1.0:
			ph -= 1.0
	return out


# =========================================================================================================
# Oscillators
# =========================================================================================================
static func _blep(t: float, dt: float) -> float:
	if t < dt:
		var x: float = t / dt
		return x + x - x * x - 1.0
	elif t > 1.0 - dt:
		var x2: float = (t - 1.0) / dt
		return x2 * x2 + x2 + x2 + 1.0
	return 0.0


## Oscillator with a per-sample frequency buffer (Hz). pw = pulse width for SQUARE. Band-limited saw/square (polyBLEP).
static func osc_f(wave: int, freq: PackedFloat32Array, sr: int = SR, phase0: float = 0.0, pw: float = 0.5) -> PackedFloat32Array:
	var n := freq.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var ph: float = phase0 - floor(phase0)
	var fs: float = float(sr)
	match wave:
		Wave.SINE:
			for i in n:
				out[i] = sin(ph * TAU)
				ph += freq[i] / fs
				ph -= floor(ph)
		Wave.SAW:
			for i in n:
				var dt: float = freq[i] / fs
				out[i] = 2.0 * ph - 1.0 - _blep(ph, dt)
				ph += dt
				ph -= floor(ph)
		Wave.SQUARE:
			for i in n:
				var dt2: float = freq[i] / fs
				var v: float = 1.0 if ph < pw else -1.0
				var t2: float = ph - pw
				t2 -= floor(t2)
				out[i] = v + _blep(ph, dt2) - _blep(t2, dt2)
				ph += dt2
				ph -= floor(ph)
		_:
			for i in n:
				out[i] = 4.0 * absf(ph - 0.5) - 1.0
				ph += freq[i] / fs
				ph -= floor(ph)
	return out


## Constant-frequency oscillator.
static func osc(wave: int, n: int, freq: float, sr: int = SR, phase0: float = 0.0, pw: float = 0.5) -> PackedFloat32Array:
	return osc_f(wave, filled(n, freq), sr, phase0, pw)


## Exponential pitch glide f0 -> f1 (Hz) over n samples.
static func osc_sweep(wave: int, n: int, f0: float, f1: float, sr: int = SR, pw: float = 0.5) -> PackedFloat32Array:
	return osc_f(wave, expramp(n, f0, f1), sr, 0.0, pw)


## Two-operator FM: sin(2 pi fc t + index(t) * sin(2 pi fm t)). index_env may be empty (constant `index`).
static func fm(n: int, fc: float, fm_hz: float, index: float, sr: int = SR, index_env: PackedFloat32Array = PackedFloat32Array(), fc_buf: PackedFloat32Array = PackedFloat32Array()) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var pc: float = 0.0
	var pm: float = 0.0
	var fs: float = float(sr)
	var has_env := index_env.size() >= n
	var has_f := fc_buf.size() >= n
	var incm: float = fm_hz / fs
	for i in n:
		var idx: float = index * (index_env[i] if has_env else 1.0)
		out[i] = sin(pc * TAU + idx * sin(pm * TAU))
		pc += (fc_buf[i] if has_f else fc) / fs
		pm += incm
		pc -= floor(pc)
		pm -= floor(pm)
	return out


## Additive stack: sum of harmonics h=1..count with amplitude 1/h^rolloff (rolloff 0 = flat) at fundamental freq.
static func harmonics(n: int, freq: float, count: int, rolloff: float, sr: int = SR, odd_only: bool = false) -> PackedFloat32Array:
	var out := zeros(n)
	var fs: float = float(sr)
	for h in range(1, count + 1):
		if odd_only and h % 2 == 0:
			continue
		var f: float = freq * float(h)
		if f > fs * 0.45:
			break
		var amp: float = 1.0 / pow(float(h), rolloff)
		var inc: float = f / fs
		var ph: float = 0.0
		for i in n:
			out[i] += amp * sin(ph * TAU)
			ph += inc
			ph -= floor(ph)
	return out


## Damped sine (recursive 2-pole resonator excited by an impulse): amp * exp(-t/tau) * sin(2 pi f t). Very cheap modal voice.
static func ring(n: int, f: float, tau: float, sr: int = SR, amp: float = 1.0, phase: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var w: float = TAU * f / float(sr)
	var r: float = exp(-1.0 / (maxf(tau, 1e-4) * float(sr)))
	var c: float = 2.0 * r * cos(w)
	var r2: float = r * r
	var y1: float = amp * sin(phase - w)
	var y2: float = amp * sin(phase - 2.0 * w)
	for i in n:
		var y: float = c * y1 - r2 * y2
		out[i] = y
		y2 = y1
		y1 = y
	return out


# =========================================================================================================
# Noise & random control signals
# =========================================================================================================
static func _seed(seed_value: int) -> int:
	var s: int = (seed_value * 2654435761 + 12345) & 0xFFFFFFFF
	return 1 if s == 0 else s


static func noise(n: int, seed_value: int = 1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var s: int = _seed(seed_value)
	for i in n:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		out[i] = float(s >> 8) * (2.0 / 16777216.0) - 1.0
	return out


## Pink noise (-3 dB/oct), Kellet filter, normalised to roughly +-1.
static func pink(n: int, seed_value: int = 1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var s: int = _seed(seed_value)
	var b0: float = 0.0
	var b1: float = 0.0
	var b2: float = 0.0
	var b3: float = 0.0
	var b4: float = 0.0
	var b5: float = 0.0
	var b6: float = 0.0
	for i in n:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		var w: float = float(s >> 8) * (2.0 / 16777216.0) - 1.0
		b0 = 0.99886 * b0 + w * 0.0555179
		b1 = 0.99332 * b1 + w * 0.0750759
		b2 = 0.96900 * b2 + w * 0.1538520
		b3 = 0.86650 * b3 + w * 0.3104856
		b4 = 0.55000 * b4 + w * 0.5329522
		b5 = -0.7616 * b5 - w * 0.0168980
		out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.18
		b6 = w * 0.115926
	return out


## Brown / red noise (-6 dB/oct), leaky integrator, roughly +-1.
static func brown(n: int, seed_value: int = 1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var s: int = _seed(seed_value)
	var y: float = 0.0
	for i in n:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		var w: float = float(s >> 8) * (2.0 / 16777216.0) - 1.0
		y = (y + 0.05 * w) * 0.998
		out[i] = y * 3.5
	return out


## Slowly varying random control signal in 0..1 (linear interpolation between random points `rate_hz` times per second).
static func smooth_random(n: int, rate_hz: float, sr: int = SR, seed_value: int = 1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var s: int = _seed(seed_value)
	var step: float = maxf(float(sr) / maxf(rate_hz, 0.001), 2.0)
	s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
	var a: float = float(s >> 8) / 16777216.0
	s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
	var b: float = float(s >> 8) / 16777216.0
	var t: float = 0.0
	var inv: float = 1.0 / step
	for i in n:
		var u: float = t * inv
		var us: float = u * u * (3.0 - 2.0 * u)
		out[i] = a + (b - a) * us
		t += 1.0
		if t >= step:
			t -= step
			a = b
			s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
			b = float(s >> 8) / 16777216.0
	return out


## Random sparse impulses (rate_hz per second) with exponentially decaying amplitude tails (rain drops, fire crackle,
## debris, vinyl noise). amp_var 0..1 randomises each impulse level.
static func crackle(n: int, rate_hz: float, sr: int = SR, seed_value: int = 1, decay_s: float = 0.004, amp_var: float = 0.8) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var s: int = _seed(seed_value)
	var p: float = rate_hz / float(sr)
	var env: float = 0.0
	var sign_v: float = 1.0
	var k: float = exp(-1.0 / (maxf(decay_s, 1e-5) * float(sr)))
	for i in n:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		var u: float = float(s >> 8) / 16777216.0
		if u < p:
			s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
			var a: float = 1.0 - amp_var * (float(s >> 8) / 16777216.0)
			env = a
			sign_v = 1.0 if (s & 1) == 0 else -1.0
		out[i] = env * sign_v * (0.6 + 0.4 * sin(float(i) * 2.1))
		env *= k
	return out


# =========================================================================================================
# Envelopes
# =========================================================================================================
## Classic ADSR over n samples. Attack a, decay d (to level s), release r occupies the LAST r seconds. Times in seconds.
static func env_adsr(n: int, a: float, d: float, s_level: float, r: float, sr: int = SR) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var na: int = maxi(int(a * sr), 1)
	var nd: int = maxi(int(d * sr), 1)
	var nr: int = maxi(int(r * sr), 1)
	var rel_start: int = maxi(n - nr, na)
	var rel_from: float = s_level
	for i in n:
		var v: float
		if i < na:
			v = float(i) / float(na)
		elif i < na + nd:
			v = 1.0 + (s_level - 1.0) * (float(i - na) / float(nd))
		else:
			v = s_level
		if i >= rel_start:
			if i == rel_start:
				rel_from = v
			v = rel_from * (1.0 - float(i - rel_start) / float(maxi(n - rel_start, 1)))
		out[i] = v
	return out


## Exponential decay e^(-t/tau) with a tiny linear attack (default 1.5 ms) to avoid clicks.
static func env_decay(n: int, tau: float, sr: int = SR, attack: float = 0.0015) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var k: float = exp(-1.0 / (maxf(tau, 1e-5) * float(sr)))
	var na: int = int(attack * sr)
	var v: float = 1.0
	for i in n:
		var a: float = 1.0 if i >= na else float(i) / float(maxi(na, 1))
		out[i] = v * a
		v *= k
	return out


## Piecewise-linear envelope through points [[t_seconds, value], ...] (sorted by t); holds the last value.
static func env_points(n: int, pts: Array, sr: int = SR) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var seg: int = 0
	var cnt: int = pts.size()
	for i in n:
		var t: float = float(i) / float(sr)
		while seg < cnt - 2 and t >= float(pts[seg + 1][0]):
			seg += 1
		var t0: float = pts[seg][0]
		var v0: float = pts[seg][1]
		if seg + 1 >= cnt:
			out[i] = v0
			continue
		var t1: float = pts[seg + 1][0]
		var v1: float = pts[seg + 1][1]
		if t <= t0:
			out[i] = v0
		elif t >= t1:
			out[i] = v1
		else:
			out[i] = v0 + (v1 - v0) * ((t - t0) / (t1 - t0))
	return out


## Raised-cosine "swell": 0 -> 1 -> 0 across n samples with the peak at `peak_pos` (0..1).
static func env_swell(n: int, peak_pos: float = 0.5, power: float = 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var pk: float = clampf(peak_pos, 0.01, 0.99) * float(n)
	for i in n:
		var x: float = float(i)
		var u: float = x / pk if x < pk else (float(n) - x) / (float(n) - pk)
		var v: float = 0.5 - 0.5 * cos(clampf(u, 0.0, 1.0) * PI)
		out[i] = pow(v, power)
	return out


static func mul(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := mini(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = a[i] * b[i]
	return out


static func scale(a: PackedFloat32Array, g: float) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = a[i] * g
	return out


## Sum a + b (result has the longer length).
static func add(a: PackedFloat32Array, b: PackedFloat32Array, gain_b: float = 1.0) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else _extended(a, b.size())
	var m := mini(b.size(), out.size())
	for i in m:
		out[i] += b[i] * gain_b
	return out


static func _extended(a: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := a.duplicate()
	out.resize(n)
	return out


## In-place mix: adds src * gain into dst starting at `offset` samples (clipped to dst length). Returns nothing - dst is
## modified directly (it must be a variable, not a temporary).
static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int = 0, gain: float = 1.0) -> void:
	var n := dst.size()
	var m := src.size()
	var start: int = maxi(offset, 0)
	var s0: int = start - offset
	var count: int = mini(m - s0, n - start)
	for i in count:
		dst[start + i] += src[s0 + i] * gain


## In-place circular mix (wraps around the end of dst) - used for seamless loops.
static func mix_wrap(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain: float = 1.0) -> void:
	var n := dst.size()
	var m := src.size()
	var idx: int = posmod(offset, n)
	for i in m:
		dst[idx] += src[i] * gain
		idx += 1
		if idx >= n:
			idx = 0


static func peak(a: PackedFloat32Array) -> float:
	var p: float = 0.0
	for i in a.size():
		var v: float = absf(a[i])
		if v > p:
			p = v
	return p


static func rms(a: PackedFloat32Array) -> float:
	var n := a.size()
	if n == 0:
		return 0.0
	var acc: float = 0.0
	for i in n:
		acc += a[i] * a[i]
	return sqrt(acc / float(n))


## Scale so the absolute peak equals `target` (does nothing to silent buffers).
static func normalize(a: PackedFloat32Array, target: float = 0.9) -> PackedFloat32Array:
	var p := peak(a)
	if p < 1e-9:
		return a
	return scale(a, target / p)


static func fade_in(a: PackedFloat32Array, seconds: float, sr: int = SR) -> PackedFloat32Array:
	var out := a.duplicate()
	var m := mini(int(seconds * sr), out.size())
	for i in m:
		out[i] *= float(i) / float(m)
	return out


static func fade_out(a: PackedFloat32Array, seconds: float, sr: int = SR) -> PackedFloat32Array:
	var out := a.duplicate()
	var n := out.size()
	var m := mini(int(seconds * sr), n)
	for i in m:
		out[n - 1 - i] *= float(i) / float(m)
	return out


static func slice_buf(a: PackedFloat32Array, from_s: float, to_s: float, sr: int = SR) -> PackedFloat32Array:
	return a.slice(maxi(int(from_s * sr), 0), mini(int(to_s * sr), a.size()))


static func concat(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	out.append_array(b)
	return out


static func pad_to(a: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := a.duplicate()
	out.resize(n)
	return out


static func reverse(a: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	out.reverse()
	return out


## Makes the buffer loop seamlessly: the last `xfade` seconds are cross-faded (equal power) into the start and removed.
static func make_loop(a: PackedFloat32Array, xfade: float = 0.05, sr: int = SR) -> PackedFloat32Array:
	var n := a.size()
	var xf: int = mini(int(xfade * sr), n / 2)
	if xf < 2:
		return a
	var m: int = n - xf
	var out := a.slice(0, m)
	for i in xf:
		var u: float = float(i) / float(xf)
		var w_in: float = sin(u * PI * 0.5)
		var w_out: float = cos(u * PI * 0.5)
		out[i] = a[i] * w_in + a[m + i] * w_out
	return out


# =========================================================================================================
# Filters
# =========================================================================================================
static func lp1(a: PackedFloat32Array, fc: float, sr: int = SR) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var k: float = 1.0 - exp(-TAU * minf(fc, float(sr) * 0.49) / float(sr))
	var y: float = 0.0
	for i in n:
		y += k * (a[i] - y)
		out[i] = y
	return out


static func hp1(a: PackedFloat32Array, fc: float, sr: int = SR) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var k: float = 1.0 - exp(-TAU * minf(fc, float(sr) * 0.49) / float(sr))
	var y: float = 0.0
	for i in n:
		y += k * (a[i] - y)
		out[i] = a[i] - y
	return out


## RBJ biquad coefficients [b0, b1, b2, a1, a2] (normalised by a0).
static func biquad_coeffs(type: int, fc: float, q: float, sr: int = SR, gain_db: float = 0.0) -> PackedFloat64Array:
	var f: float = clampf(fc, 10.0, float(sr) * 0.49)
	var w0: float = TAU * f / float(sr)
	var cw: float = cos(w0)
	var sw: float = sin(w0)
	var qq: float = maxf(q, 0.05)
	var alpha: float = sw / (2.0 * qq)
	var b0: float
	var b1: float
	var b2: float
	var a0: float
	var a1: float
	var a2: float
	match type:
		Filt.LP:
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = b0
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		Filt.HP:
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = b0
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		Filt.BP:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		Filt.NOTCH:
			b0 = 1.0
			b1 = -2.0 * cw
			b2 = 1.0
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		Filt.PEAK:
			var aa: float = pow(10.0, gain_db / 40.0)
			b0 = 1.0 + alpha * aa
			b1 = -2.0 * cw
			b2 = 1.0 - alpha * aa
			a0 = 1.0 + alpha / aa
			a1 = -2.0 * cw
			a2 = 1.0 - alpha / aa
		Filt.LOWSHELF:
			var a_ls: float = pow(10.0, gain_db / 40.0)
			var beta: float = 2.0 * sqrt(a_ls) * (sw / 2.0) * sqrt(2.0)
			b0 = a_ls * ((a_ls + 1.0) - (a_ls - 1.0) * cw + beta)
			b1 = 2.0 * a_ls * ((a_ls - 1.0) - (a_ls + 1.0) * cw)
			b2 = a_ls * ((a_ls + 1.0) - (a_ls - 1.0) * cw - beta)
			a0 = (a_ls + 1.0) + (a_ls - 1.0) * cw + beta
			a1 = -2.0 * ((a_ls - 1.0) + (a_ls + 1.0) * cw)
			a2 = (a_ls + 1.0) + (a_ls - 1.0) * cw - beta
		Filt.HIGHSHELF:
			var a_hs: float = pow(10.0, gain_db / 40.0)
			var beta2: float = 2.0 * sqrt(a_hs) * (sw / 2.0) * sqrt(2.0)
			b0 = a_hs * ((a_hs + 1.0) + (a_hs - 1.0) * cw + beta2)
			b1 = -2.0 * a_hs * ((a_hs - 1.0) + (a_hs + 1.0) * cw)
			b2 = a_hs * ((a_hs + 1.0) + (a_hs - 1.0) * cw - beta2)
			a0 = (a_hs + 1.0) - (a_hs - 1.0) * cw + beta2
			a1 = 2.0 * ((a_hs - 1.0) - (a_hs + 1.0) * cw)
			a2 = (a_hs + 1.0) - (a_hs - 1.0) * cw - beta2
		_:
			b0 = 1.0 - alpha
			b1 = -2.0 * cw
			b2 = 1.0 + alpha
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
	var c := PackedFloat64Array()
	c.resize(5)
	c[0] = b0 / a0
	c[1] = b1 / a0
	c[2] = b2 / a0
	c[3] = a1 / a0
	c[4] = a2 / a0
	return c


static func biquad(a: PackedFloat32Array, type: int, fc: float, q: float = 0.707, sr: int = SR, gain_db: float = 0.0) -> PackedFloat32Array:
	var c := biquad_coeffs(type, fc, q, sr, gain_db)
	var b0: float = c[0]
	var b1: float = c[1]
	var b2: float = c[2]
	var a1: float = c[3]
	var a2: float = c[4]
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var z1: float = 0.0
	var z2: float = 0.0
	for i in n:
		var x: float = a[i]
		var y: float = b0 * x + z1
		z1 = b1 * x - a1 * y + z2
		z2 = b2 * x - a2 * y
		out[i] = y
	return out


## Biquad with a per-sample cutoff buffer (Hz); coefficients are recomputed every `step` samples.
static func biquad_sweep(a: PackedFloat32Array, type: int, fc: PackedFloat32Array, q: float = 0.707, sr: int = SR, step: int = 24) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var z1: float = 0.0
	var z2: float = 0.0
	var b0: float = 0.0
	var b1: float = 0.0
	var b2: float = 0.0
	var a1: float = 0.0
	var a2: float = 0.0
	var m := fc.size()
	for i in n:
		if i % step == 0:
			var c := biquad_coeffs(type, fc[mini(i, m - 1)], q, sr)
			b0 = c[0]
			b1 = c[1]
			b2 = c[2]
			a1 = c[3]
			a2 = c[4]
		var x: float = a[i]
		var y: float = b0 * x + z1
		z1 = b1 * x - a1 * y + z2
		z2 = b2 * x - a2 * y
		out[i] = y
	return out


static func lowpass(a: PackedFloat32Array, fc: float, q: float = 0.707, sr: int = SR) -> PackedFloat32Array:
	return biquad(a, Filt.LP, fc, q, sr)


static func highpass(a: PackedFloat32Array, fc: float, q: float = 0.707, sr: int = SR) -> PackedFloat32Array:
	return biquad(a, Filt.HP, fc, q, sr)


static func bandpass(a: PackedFloat32Array, fc: float, q: float = 1.0, sr: int = SR) -> PackedFloat32Array:
	return biquad(a, Filt.BP, fc, q, sr)


## Band-limits to [lo, hi] Hz with a high-pass followed by a low-pass.
static func band(a: PackedFloat32Array, lo: float, hi: float, sr: int = SR) -> PackedFloat32Array:
	return biquad(biquad(a, Filt.HP, lo, 0.707, sr), Filt.LP, hi, 0.707, sr)


## Filters a buffer that is meant to loop so the filter state at the seam matches (runs the filter over buf+buf and
## returns the second half). `fn` receives the doubled buffer and must return a same-length buffer.
static func circular(a: PackedFloat32Array, fn: Callable) -> PackedFloat32Array:
	var n := a.size()
	var dbl := a.duplicate()
	dbl.append_array(a)
	var res: PackedFloat32Array = fn.call(dbl)
	return res.slice(n, n * 2)


## Parallel resonant band-pass bank (vowel formants). formants = [[freq, bandwidth, gain], ...]
static func formants(a: PackedFloat32Array, fmts: Array, sr: int = SR) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for f in fmts:
		var fc: float = f[0]
		var bw: float = f[1]
		var g: float = f[2]
		var c := biquad_coeffs(Filt.BP, fc, fc / maxf(bw, 20.0), sr)
		var b0: float = c[0]
		var b2: float = c[2]
		var a1: float = c[3]
		var a2: float = c[4]
		var z1: float = 0.0
		var z2: float = 0.0
		for i in n:
			var x: float = a[i]
			var y: float = b0 * x + z1
			z1 = -a1 * y + z2
			z2 = b2 * x - a2 * y
			out[i] += y * g
	return out


# =========================================================================================================
# Delay / reverb
# =========================================================================================================
## Feed-forward + feedback echo. Output is extended by `tail` seconds so the repeats ring out.
static func delay(a: PackedFloat32Array, time_s: float, feedback: float, wet: float, sr: int = SR, tail: float = 0.0, damp: float = 0.0) -> PackedFloat32Array:
	var n := a.size()
	var d: int = maxi(int(time_s * sr), 1)
	var total: int = n + int(tail * sr)
	var out := PackedFloat32Array()
	out.resize(total)
	var line := PackedFloat32Array()
	line.resize(d)
	var idx: int = 0
	var lz: float = 0.0
	for i in total:
		var x: float = a[i] if i < n else 0.0
		var dl: float = line[idx]
		lz = dl * (1.0 - damp) + lz * damp
		line[idx] = x + lz * feedback
		idx += 1
		if idx >= d:
			idx = 0
		out[i] = x + dl * wet
	return out


static func comb_pass(a: PackedFloat32Array, d: int, fb: float, damp: float, total: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(total)
	var line := PackedFloat32Array()
	line.resize(d)
	var idx: int = 0
	var lz: float = 0.0
	for i in total:
		var x: float = a[i] if i < n else 0.0
		var dl: float = line[idx]
		lz = dl * (1.0 - damp) + lz * damp
		line[idx] = x + lz * fb
		idx += 1
		if idx >= d:
			idx = 0
		out[i] = dl
	return out


static func allpass_pass(a: PackedFloat32Array, d: int, g: float) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var line := PackedFloat32Array()
	line.resize(d)
	var idx: int = 0
	for i in n:
		var x: float = a[i]
		var bufo: float = line[idx]
		var y: float = -x + bufo
		line[idx] = x + bufo * g
		idx += 1
		if idx >= d:
			idx = 0
		out[i] = y
	return out


## Small Schroeder/Freeverb-style reverb (4 damped combs + 2 allpasses). room 0..1 sets size+decay, damp 0..1 darkens the
## tail, wet is the reverb level added to the dry signal. The result is extended by `tail` seconds.
static func reverb(a: PackedFloat32Array, room: float = 0.5, damp: float = 0.4, wet: float = 0.3, sr: int = SR, tail: float = 0.6) -> PackedFloat32Array:
	var n := a.size()
	var total: int = n + int(tail * sr)
	var sc: float = (0.55 + room * 0.9) * float(sr) / 44100.0
	var fb: float = 0.62 + room * 0.33
	var sum := PackedFloat32Array()
	sum.resize(total)
	for d0 in [1116, 1277, 1422, 1557]:
		var c := comb_pass(a, maxi(int(d0 * sc), 8), fb, damp, total)
		for i in total:
			sum[i] += c[i] * 0.25
	var ap := allpass_pass(sum, maxi(int(556 * sc), 8), 0.5)
	ap = allpass_pass(ap, maxi(int(341 * sc), 8), 0.5)
	var out := PackedFloat32Array()
	out.resize(total)
	for i in total:
		out[i] = (a[i] if i < n else 0.0) + ap[i] * wet
	return out


## Outdoor slap-back echoes: taps = [[delay_s, gain], ...]. Output is extended to hold the last tap.
static func echoes(a: PackedFloat32Array, taps: Array, sr: int = SR, lp_hz: float = 3000.0) -> PackedFloat32Array:
	var n := a.size()
	var max_d: float = 0.0
	for t in taps:
		max_d = maxf(max_d, float(t[0]))
	var out := a.duplicate()
	out.resize(n + int(max_d * sr) + 1)
	var dark := lp1(a, lp_hz, sr)
	for t in taps:
		mix_into(out, dark, int(float(t[0]) * sr), float(t[1]))
	return out


# =========================================================================================================
# Distortion / shaping
# =========================================================================================================
static func soft_clip(a: PackedFloat32Array, drive: float = 2.0) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var norm: float = 1.0 / tanh(drive)
	for i in n:
		out[i] = tanh(a[i] * drive) * norm
	return out


static func hard_clip(a: PackedFloat32Array, limit: float = 0.5) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = clampf(a[i], -limit, limit) / limit
	return out


## Wave folding (adds bright, metallic harmonics).
static func fold(a: PackedFloat32Array, gain: float = 2.0) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sin(a[i] * gain * PI * 0.5)
	return out


## Bit crusher / sample-rate reducer.
static func crush(a: PackedFloat32Array, bits: int = 8, hold: int = 1) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var levels: float = pow(2.0, float(bits - 1))
	var held: float = 0.0
	for i in n:
		if i % hold == 0:
			held = round(a[i] * levels) / levels
		out[i] = held
	return out


## Gentle final limiter: leaves signals below `knee` untouched and bends the rest towards +-1 (no hard clipping).
static func limit(a: PackedFloat32Array, knee: float = 0.8) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var span: float = 1.0 - knee
	for i in n:
		var v: float = a[i]
		var av: float = absf(v)
		if av > knee:
			var x: float = (av - knee) / span
			av = knee + span * tanh(x)
			v = av if v > 0.0 else -av
		out[i] = v
	return out


## Removes NaN/inf and DC offset (cheap one-pole DC blocker) - always call before to_wav on untrusted chains.
static func sanitize(a: PackedFloat32Array, dc_block: bool = true) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var x1: float = 0.0
	var y1: float = 0.0
	for i in n:
		var v: float = a[i]
		if is_nan(v) or is_inf(v):
			v = 0.0
		if dc_block:
			var y: float = v - x1 + 0.995 * y1
			x1 = v
			y1 = y
			v = y
		out[i] = v
	return out


# =========================================================================================================
# Resampling / granular / voice source
# =========================================================================================================
## Resample by `ratio` (>1 = higher pitch and shorter, <1 = lower and longer), linear interpolation.
static func resample(a: PackedFloat32Array, ratio: float) -> PackedFloat32Array:
	var n := a.size()
	var m: int = maxi(int(float(n) / maxf(ratio, 0.01)), 1)
	var out := PackedFloat32Array()
	out.resize(m)
	var pos: float = 0.0
	for i in m:
		var i0: int = int(pos)
		var fr: float = pos - float(i0)
		var s0: float = a[mini(i0, n - 1)]
		var s1: float = a[mini(i0 + 1, n - 1)]
		out[i] = s0 + (s1 - s0) * fr
		pos += ratio
	return out


## Resample with a per-sample ratio buffer (variable pitch / doppler sweeps). Output length = n_out.
static func resample_var(a: PackedFloat32Array, ratio: PackedFloat32Array) -> PackedFloat32Array:
	var n := a.size()
	var m := ratio.size()
	var out := PackedFloat32Array()
	out.resize(m)
	var pos: float = 0.0
	for i in m:
		var i0: int = int(pos)
		if i0 >= n - 1:
			break
		var fr: float = pos - float(i0)
		out[i] = a[i0] + (a[i0 + 1] - a[i0]) * fr
		pos += ratio[i]
	return out


## Granular texture: scatters Hann-windowed grains (length grain_s) from `src` into an n_out buffer.
static func granular(src: PackedFloat32Array, n_out: int, grain_s: float, density_hz: float, pitch_var: float = 0.0, sr: int = SR, seed_value: int = 1, gain: float = 1.0) -> PackedFloat32Array:
	var out := zeros(n_out)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var g: int = maxi(int(grain_s * sr), 8)
	var count: int = maxi(int(float(n_out) / float(sr) * density_hz), 1)
	var win := PackedFloat32Array()
	win.resize(g)
	for i in g:
		win[i] = 0.5 - 0.5 * cos(TAU * float(i) / float(g - 1))
	for k in count:
		var at: int = rng.randi_range(0, maxi(n_out - 1, 0))
		var from: int = rng.randi_range(0, maxi(src.size() - g - 1, 0))
		var pr: float = 1.0 + rng.randf_range(-pitch_var, pitch_var)
		var amp: float = gain * rng.randf_range(0.5, 1.0)
		var sgn: float = 1.0 if rng.randf() < 0.5 else -1.0
		for i in g:
			var idx: int = at + i
			if idx >= n_out:
				break
			var si: int = from + int(float(i) * pr)
			if si >= src.size():
				break
			out[idx] += src[si] * win[i] * amp * sgn
	return out


## Glottal voice source (Rosenberg-type pulse, differentiated = "radiated" flow) driven by a per-sample f0 buffer.
## `open` = open phase fraction, `close` = closing phase fraction of one period (smaller close = brighter / tenser).
static func glottal(f0: PackedFloat32Array, sr: int = SR, open: float = 0.55, close: float = 0.16) -> PackedFloat32Array:
	var n := f0.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var ph: float = 0.0
	var prev: float = 0.0
	var fs: float = float(sr)
	for i in n:
		var g: float = 0.0
		if ph < open:
			g = 0.5 * (1.0 - cos(PI * ph / open))
		elif ph < open + close:
			g = cos(0.5 * PI * (ph - open) / close)
		out[i] = (g - prev) * 12.0
		prev = g
		ph += f0[i] / fs
		ph -= floor(ph)
	return out


# =========================================================================================================
# Convenience voices used all over the sound bank
# =========================================================================================================
## Sine sweep with exponential decay (kick / boom / thump).
static func thump(dur: float, f0: float, f1: float, tau: float, sr: int = SR, amp: float = 1.0) -> PackedFloat32Array:
	var n := secs(dur, sr)
	var s := osc_sweep(Wave.SINE, n, f0, f1, sr)
	return scale(mul(s, env_decay(n, tau, sr, 0.0008)), amp)


## Filtered noise burst with exponential decay; hp/lp in Hz (<=0 = off).
static func noise_hit(dur: float, tau: float, hp_hz: float, lp_hz: float, seed_value: int, sr: int = SR, amp: float = 1.0) -> PackedFloat32Array:
	var n := secs(dur, sr)
	var s := noise(n, seed_value)
	if hp_hz > 0.0:
		s = biquad(s, Filt.HP, hp_hz, 0.707, sr)
	if lp_hz > 0.0:
		s = biquad(s, Filt.LP, lp_hz, 0.707, sr)
	return scale(mul(s, env_decay(n, tau, sr, 0.0006)), amp)


## Modal "metal" voice: partials = [[freq, tau, amp], ...] rung by an impulse, n samples.
static func modal(n: int, partials: Array, sr: int = SR) -> PackedFloat32Array:
	var out := zeros(n)
	for p in partials:
		var r := ring(n, float(p[0]), float(p[1]), sr, float(p[2]))
		for i in n:
			out[i] += r[i]
	return out


## Short tonal blip: wave at freq with exponential decay.
static func blip(wave: int, freq: float, dur: float, tau: float, sr: int = SR, amp: float = 1.0) -> PackedFloat32Array:
	var n := secs(dur, sr)
	return scale(mul(osc(wave, n, freq, sr), env_decay(n, tau, sr, 0.002)), amp)


# =========================================================================================================
# Output
# =========================================================================================================
## Converts a float buffer to a mono 16-bit AudioStreamWAV. NaN-safe, hard-limits to +-1.
static func to_wav(a: PackedFloat32Array, sr: int = SR, looped: bool = false, loop_begin: int = 0, loop_end: int = -1) -> AudioStreamWAV:
	var n := a.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v: float = a[i]
		if v != v:
			v = 0.0
		elif v > 1.0:
			v = 1.0
		elif v < -1.0:
			v = -1.0
		bytes.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = maxi(loop_begin, 0)
		w.loop_end = n if loop_end < 0 else mini(loop_end, n)
	else:
		w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return w


## Reads a 16-bit mono AudioStreamWAV back into floats (tests / analysis).
static func from_wav(w: AudioStreamWAV) -> PackedFloat32Array:
	var data: PackedByteArray = w.data
	var step: int = 4 if w.stereo else 2
	var n: int = data.size() / step
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(data.decode_s16(i * step)) / 32768.0
	return out


## Writes a mono 16-bit PCM .wav file (OS path or res://) for inspection in any audio editor.
static func save_wav_file(path: String, a: PackedFloat32Array, sr: int = SR) -> int:
	var n := a.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v: float = clampf(a[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + bytes.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(sr)
	f.store_32(sr * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(bytes.size())
	f.store_buffer(bytes)
	f.close()
	return OK
