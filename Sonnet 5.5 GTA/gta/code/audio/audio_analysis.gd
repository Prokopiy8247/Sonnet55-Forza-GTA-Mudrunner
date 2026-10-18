extends RefCounted
## AudioAnalysis - tiny offline analysis toolkit (FFT, spectral centroid, pitch tracks, loop-seam metrics, spectrogram PNG)
## used by the audio tests so that procedurally generated sounds can be verified numerically and visually WITHOUT listening.

const SR := 22050
static var _tw_cache: Dictionary = {}


## In-place radix-2 FFT (arrays must have power-of-two length). Packed arrays are passed by reference in Godot 4.
static func fft(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var n := re.size()
	var j: int = 0
	for i in range(1, n):
		var bit: int = n >> 1
		while (j & bit) != 0:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var tr: float = re[i]
			re[i] = re[j]
			re[j] = tr
			var ti: float = im[i]
			im[i] = im[j]
			im[j] = ti
	var tw := _twiddles(n)
	var half_n: int = n >> 1
	var length: int = 2
	while length <= n:
		var half: int = length >> 1
		var stride: int = n / length
		var i: int = 0
		while i < n:
			for k in half:
				var wr: float = tw[2 * (k * stride)]
				var wi: float = tw[2 * (k * stride) + 1]
				var a: int = i + k
				var b: int = a + half
				var xr: float = re[b] * wr - im[b] * wi
				var xi: float = re[b] * wi + im[b] * wr
				re[b] = re[a] - xr
				im[b] = im[a] - xi
				re[a] += xr
				im[a] += xi
			i += length
		length <<= 1
	if half_n < 0:
		return


static func _twiddles(n: int) -> PackedFloat32Array:
	if _tw_cache.has(n):
		return _tw_cache[n]
	var t := PackedFloat32Array()
	t.resize(n)
	for k in n / 2:
		var ang: float = -TAU * float(k) / float(n)
		t[2 * k] = cos(ang)
		t[2 * k + 1] = sin(ang)
	_tw_cache[n] = t
	return t


## Magnitude spectrum (n/2 bins) of buf[start : start+n] with a Hann window.
static func spectrum(buf: PackedFloat32Array, start: int, n: int = 2048) -> PackedFloat32Array:
	var re := PackedFloat32Array()
	re.resize(n)
	var im := PackedFloat32Array()
	im.resize(n)
	var m := buf.size()
	for i in n:
		var idx: int = start + i
		var v: float = buf[idx] if idx >= 0 and idx < m else 0.0
		re[i] = v * (0.5 - 0.5 * cos(TAU * float(i) / float(n - 1)))
	fft(re, im)
	var mag := PackedFloat32Array()
	mag.resize(n / 2)
	for k in n / 2:
		mag[k] = sqrt(re[k] * re[k] + im[k] * im[k])
	return mag


## Energy-weighted mean spectral centroid in Hz (up to `frames` evenly spaced analysis windows).
static func spectral_centroid(buf: PackedFloat32Array, sr: int = SR, frames: int = 8, n: int = 2048) -> float:
	var total := buf.size()
	if total < n:
		return 0.0
	var num: float = 0.0
	var den: float = 0.0
	var hz_per_bin: float = float(sr) / float(n)
	for f in frames:
		var start: int = int(float(total - n) * float(f) / float(maxi(frames - 1, 1)))
		var mag := spectrum(buf, start, n)
		for k in range(1, mag.size()):
			var e: float = mag[k] * mag[k]
			num += e * float(k) * hz_per_bin
			den += e
	return num / maxf(den, 1e-12)


## Fraction (0..1) of spectral energy between lo and hi Hz.
static func band_fraction(buf: PackedFloat32Array, lo: float, hi: float, sr: int = SR, frames: int = 8, n: int = 2048) -> float:
	var total := buf.size()
	if total < n:
		return 0.0
	var inside: float = 0.0
	var all: float = 0.0
	var hz_per_bin: float = float(sr) / float(n)
	for f in frames:
		var start: int = int(float(total - n) * float(f) / float(maxi(frames - 1, 1)))
		var mag := spectrum(buf, start, n)
		for k in range(1, mag.size()):
			var e: float = mag[k] * mag[k]
			all += e
			var hz: float = float(k) * hz_per_bin
			if hz >= lo and hz <= hi:
				inside += e
	return inside / maxf(all, 1e-12)


static func zero_cross_rate(buf: PackedFloat32Array, sr: int = SR) -> float:
	var n := buf.size()
	if n < 2:
		return 0.0
	var c: int = 0
	var prev: float = buf[0]
	for i in range(1, n):
		var v: float = buf[i]
		if (v >= 0.0) != (prev >= 0.0):
			c += 1
		prev = v
	return float(c) / (float(n) / float(sr))


static func peak(buf: PackedFloat32Array) -> float:
	var p: float = 0.0
	for i in buf.size():
		var v: float = absf(buf[i])
		if v > p:
			p = v
	return p


static func rms(buf: PackedFloat32Array) -> float:
	var n := buf.size()
	if n == 0:
		return 0.0
	var acc: float = 0.0
	for i in n:
		acc += buf[i] * buf[i]
	return sqrt(acc / float(n))


static func has_nan(buf: PackedFloat32Array) -> bool:
	for i in buf.size():
		var v: float = buf[i]
		if v != v or absf(v) > 1e9:
			return true
	return false


static func dc_offset(buf: PackedFloat32Array) -> float:
	var n := buf.size()
	if n == 0:
		return 0.0
	var acc: float = 0.0
	for i in n:
		acc += buf[i]
	return acc / float(n)


## RMS envelope (one value per `win_s` seconds).
static func rms_envelope(buf: PackedFloat32Array, win_s: float = 0.02, sr: int = SR) -> PackedFloat32Array:
	var w: int = maxi(int(win_s * sr), 8)
	var count: int = buf.size() / w
	var out := PackedFloat32Array()
	out.resize(count)
	for k in count:
		var acc: float = 0.0
		for i in w:
			var v: float = buf[k * w + i]
			acc += v * v
		out[k] = sqrt(acc / float(w))
	return out


## Seconds from the envelope peak until the RMS falls `drop_db` below it and stays below (decay length measure).
static func decay_time(buf: PackedFloat32Array, drop_db: float = 30.0, sr: int = SR) -> float:
	var win: float = 0.02
	var env := rms_envelope(buf, win, sr)
	if env.is_empty():
		return 0.0
	var pk_i: int = 0
	var pk: float = 0.0
	for i in env.size():
		if env[i] > pk:
			pk = env[i]
			pk_i = i
	var thr: float = pk * pow(10.0, -drop_db / 20.0)
	var last_above: int = pk_i
	for i in range(pk_i, env.size()):
		if env[i] > thr:
			last_above = i
	return float(last_above - pk_i) * win


## Time of the envelope peak in seconds.
static func peak_time(buf: PackedFloat32Array, sr: int = SR) -> float:
	var env := rms_envelope(buf, 0.01, sr)
	var pk: float = 0.0
	var pk_i: int = 0
	for i in env.size():
		if env[i] > pk:
			pk = env[i]
			pk_i = i
	return float(pk_i) * 0.01


## Dominant frequency per frame (Hz), parabolic-interpolated spectral peak between f_lo and f_hi. Used for siren checks.
static func pitch_track(buf: PackedFloat32Array, sr: int = SR, frame_s: float = 0.1, f_lo: float = 150.0, f_hi: float = 4000.0, n: int = 2048) -> PackedFloat32Array:
	var hop: int = maxi(int(frame_s * sr), 64)
	var out := PackedFloat32Array()
	var hz_per_bin: float = float(sr) / float(n)
	var k_lo: int = maxi(int(f_lo / hz_per_bin), 1)
	var k_hi: int = mini(int(f_hi / hz_per_bin), n / 2 - 2)
	var start: int = 0
	while start + n <= buf.size():
		var mag := spectrum(buf, start, n)
		var best: int = k_lo
		var bv: float = 0.0
		for k in range(k_lo, k_hi):
			if mag[k] > bv:
				bv = mag[k]
				best = k
		var a: float = mag[best - 1]
		var b: float = mag[best]
		var c: float = mag[best + 1]
		var denom: float = a - 2.0 * b + c
		var shift: float = 0.5 * (a - c) / denom if absf(denom) > 1e-9 else 0.0
		out.append((float(best) + shift) * hz_per_bin)
		start += hop
	return out


## Median fundamental frequency (Hz) of the voiced frames, via normalised autocorrelation on the loudest frames.
## Returns 0 when nothing is voiced. Spectral-peak pitch trackers lock onto formant harmonics for voices; this does not.
static func autocorr_pitch(buf: PackedFloat32Array, sr: int = SR, f_lo: float = 80.0, f_hi: float = 700.0, max_frames: int = 8) -> float:
	var n: int = int(0.032 * float(sr))
	var lag_min: int = int(float(sr) / f_hi)
	var lag_max: int = int(float(sr) / f_lo)
	var total := buf.size()
	if total < n + lag_max + 8:
		return 0.0
	# rank frames by energy
	var hop: int = n / 2
	var frames: Array = []
	var start: int = 0
	while start + n + lag_max < total:
		var e: float = 0.0
		for i in range(0, n, 4):
			e += buf[start + i] * buf[start + i]
		frames.append([e, start])
		start += hop
	frames.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var pitches: Array = []
	for fi in mini(max_frames, frames.size()):
		var st: int = frames[fi][1]
		var e0: float = 0.0
		for i in n:
			e0 += buf[st + i] * buf[st + i]
		if e0 < 1e-6:
			continue
		var best_c: float = 0.0
		var best_lag: int = 0
		for lag in range(lag_min, lag_max):
			var c: float = 0.0
			var e1: float = 0.0
			for i in range(0, n, 2):
				var a: float = buf[st + i]
				var b: float = buf[st + i + lag]
				c += a * b
				e1 += b * b
			var norm: float = c / sqrt(maxf(e0 * 0.5 * e1, 1e-12))
			if norm > best_c:
				best_c = norm
				best_lag = lag
		if best_c > 0.5 and best_lag > 0:
			pitches.append(float(sr) / float(best_lag))
	if pitches.is_empty():
		return 0.0
	pitches.sort()
	return float(pitches[pitches.size() / 2])


## Loop-seam discontinuity: |last - first| relative to the 99.5th percentile of the sample-to-sample steps inside the
## buffer. <= ~1 means the seam is no bigger than the signal's own natural steps (seamless); a click shows up as >> 1.
static func loop_seam_ratio(buf: PackedFloat32Array) -> float:
	var n := buf.size()
	if n < 16:
		return 0.0
	var steps := PackedFloat32Array()
	steps.resize(n - 1)
	for i in range(1, n):
		steps[i - 1] = absf(buf[i] - buf[i - 1])
	steps.sort()
	var ref: float = steps[int(float(n - 2) * 0.995)]
	var jump: float = absf(buf[0] - buf[n - 1])
	return jump / maxf(ref, 1e-6)


## Pearson-like measure of how much a loop's start matches the continuation of its end (RMS of the 64 samples around the seam
## relative to the RMS of the whole buffer; ~1 for noise-like seamless loops).
static func seam_energy_ratio(buf: PackedFloat32Array, win: int = 256) -> float:
	var n := buf.size()
	if n < win * 4:
		return 1.0
	var acc: float = 0.0
	for i in win:
		acc += buf[i] * buf[i] + buf[n - 1 - i] * buf[n - 1 - i]
	var seam: float = sqrt(acc / float(2 * win))
	return seam / maxf(rms(buf), 1e-9)


# =========================================================================================================
# Visualisation (spectrogram + waveform PNG)
# =========================================================================================================
## Returns an Image (waveform on top, log-magnitude spectrogram below, 0..sr/2 vertical axis) so a sound can be
## judged visually by reading the PNG.
static func plot(buf: PackedFloat32Array, sr: int = SR, w: int = 720, h_wave: int = 120, h_spec: int = 240, max_hz: float = 0.0) -> Image:
	var img := Image.create(w, h_wave + h_spec, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.06, 0.09))
	var n := buf.size()
	if n < 64:
		return img
	# waveform min/max per column
	var mid: int = h_wave / 2
	for x in w:
		var s0: int = int(float(x) * float(n) / float(w))
		var s1: int = maxi(int(float(x + 1) * float(n) / float(w)), s0 + 1)
		var mn: float = 1.0
		var mx: float = -1.0
		var step: int = maxi((s1 - s0) / 16, 1)
		var i: int = s0
		while i < s1 and i < n:
			var v: float = buf[i]
			mn = minf(mn, v)
			mx = maxf(mx, v)
			i += step
		var y0: int = clampi(mid - int(mx * float(mid - 2)), 0, h_wave - 1)
		var y1: int = clampi(mid - int(mn * float(mid - 2)), 0, h_wave - 1)
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			img.set_pixel(x, y, Color(0.2, 0.85, 1.0))
	# spectrogram
	var fft_n: int = 1024
	var hz_top: float = max_hz if max_hz > 0.0 else float(sr) * 0.5
	var bins_top: int = clampi(int(hz_top / (float(sr) / float(fft_n))), 8, fft_n / 2)
	var cols: int = mini(w, maxi((n - fft_n) / 128, 1))
	var mags: Array = []
	var gmax: float = 1e-9
	for c in cols:
		var start: int = int(float(c) * float(maxi(n - fft_n, 1)) / float(maxi(cols - 1, 1)))
		var m := spectrum(buf, start, fft_n)
		mags.append(m)
		for k in bins_top:
			gmax = maxf(gmax, m[k])
	for x in w:
		var c2: int = mini(int(float(x) * float(cols) / float(w)), cols - 1)
		var m2: PackedFloat32Array = mags[c2]
		for y in h_spec:
			var k2: int = clampi(int(float(h_spec - 1 - y) / float(h_spec) * float(bins_top)), 0, bins_top - 1)
			var db: float = 20.0 * log(maxf(m2[k2] / gmax, 1e-5)) / log(10.0)
			var t: float = clampf((db + 70.0) / 70.0, 0.0, 1.0)
			img.set_pixel(x, h_wave + y, Color(t * t, t * 0.8, 0.35 + 0.65 * t * (1.0 - t * 0.4)) if t > 0.02 else Color(0.02, 0.02, 0.05))
	return img
