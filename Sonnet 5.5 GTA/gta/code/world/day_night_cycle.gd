class_name DayNightCycle
extends RefCounted
## Pure, static maths for the Halcyon Bay day/night cycle (no nodes, safe to call from tests):
##  - solar / lunar position from the hour of day (sunrise SUNRISE, sunset SUNSET, mid-latitude sun path)
##  - the colour / energy palette as a function of SUN ELEVATION (twilight reads the same whatever the hour)
##  - weather modulation of that palette (compose())
## EnvironmentSystem feeds the result into the sky shader, Environment, lights and the global shader params.
## Hours are 0..24 (Game.time_of_day).

const SUNRISE := 6.0              # sun elevation crosses 0 at this hour
const SUNSET := 19.0
const LATITUDE_DEG := 48.0        # shapes the sun path (max elevation ~48 degrees: long soft shadows, facade gradients at noon)

## Sun elevation (deg) is the palette key. Each key: el + a dictionary of values (colours are sRGB hex strings).
const _KEYS: Array = [
	# night
	{"el": -30.0, "zenith": "#0a1538", "mid": "#13255a", "horizon": "#26417f", "ground": "#0b1530", "glow": "#000000", "glow_a": 0.0,
	 "band": "#000000", "band_a": 0.0, "sun_col": "#ffb070", "sun_e": 0.0, "amb": 2.1, "fog": "#1b2d5c", "fogd": 0.0010,
	 "expo": 1.15, "stars": 1.0, "cl_lit": "#3d5288", "cl_shade": "#1b274e", "sat": 1.06, "glow_i": 0.55, "glow_th": 1.0, "haze": 0.55},
	{"el": -14.0, "zenith": "#101f4c", "mid": "#243369", "horizon": "#4d4488", "ground": "#141b3a", "glow": "#8a4a9a", "glow_a": 0.25,
	 "band": "#7a3c86", "band_a": 0.25, "sun_col": "#ffb070", "sun_e": 0.0, "amb": 1.95, "fog": "#2d3566", "fogd": 0.0010,
	 "expo": 1.12, "stars": 0.8, "cl_lit": "#6a5a9a", "cl_shade": "#2c3064", "sat": 1.06, "glow_i": 0.52, "glow_th": 1.0, "haze": 0.6},
	{"el": -8.0, "zenith": "#1b3274", "mid": "#4b4a98", "horizon": "#c4528c", "ground": "#251f4a", "glow": "#ff5a7a", "glow_a": 0.65,
	 "band": "#c4409c", "band_a": 0.55, "sun_col": "#ff8a5a", "sun_e": 0.0, "amb": 1.6, "fog": "#5c4284", "fogd": 0.0011,
	 "expo": 1.08, "stars": 0.35, "cl_lit": "#ff7aa2", "cl_shade": "#4a3a84", "sat": 1.08, "glow_i": 0.5, "glow_th": 1.0, "haze": 0.7},
	{"el": -4.0, "zenith": "#2b4e9c", "mid": "#8c5aa8", "horizon": "#ff7a6c", "ground": "#3b305c", "glow": "#ff7840", "glow_a": 0.92,
	 "band": "#e0508c", "band_a": 0.78, "sun_col": "#ff7a40", "sun_e": 0.0, "amb": 1.25, "fog": "#a45c8c", "fogd": 0.00095,
	 "expo": 1.04, "stars": 0.0, "cl_lit": "#ffa070", "cl_shade": "#6c4c9a", "sat": 1.12, "glow_i": 0.6, "glow_th": 0.95, "haze": 0.8},
	{"el": -1.0, "zenith": "#386abb", "mid": "#b2729e", "horizon": "#ff9250", "ground": "#5a4a6c", "glow": "#ff8a3a", "glow_a": 1.0,
	 "band": "#e85a8c", "band_a": 0.7, "sun_col": "#ff7a3a", "sun_e": 0.45, "amb": 1.0, "fog": "#d08268", "fogd": 0.00092,
	 "expo": 1.0, "stars": 0.0, "cl_lit": "#ffb070", "cl_shade": "#8c5c9a", "sat": 1.14, "glow_i": 0.55, "glow_th": 1.0, "haze": 0.85},
	{"el": 2.0, "zenith": "#3a6fcc", "mid": "#c08cb4", "horizon": "#ffa65a", "ground": "#6a5a74", "glow": "#ff9440", "glow_a": 1.0,
	 "band": "#e0608c", "band_a": 0.5, "sun_col": "#ff8e44", "sun_e": 1.05, "amb": 0.86, "fog": "#e89c74", "fogd": 0.00085,
	 "expo": 1.08, "stars": 0.0, "cl_lit": "#ffc080", "cl_shade": "#9a6ea4", "sat": 1.26, "glow_i": 0.5, "glow_th": 1.0, "haze": 0.8},
	{"el": 6.0, "zenith": "#3678de", "mid": "#a8b0de", "horizon": "#ffbb70", "ground": "#78708a", "glow": "#ffa450", "glow_a": 1.0,
	 "band": "#e8789c", "band_a": 0.3, "sun_col": "#ffae60", "sun_e": 1.40, "amb": 0.76, "fog": "#f2bc92", "fogd": 0.00058,
	 "expo": 1.05, "stars": 0.0, "cl_lit": "#ffd0a0", "cl_shade": "#8a86c0", "sat": 1.26, "glow_i": 0.45, "glow_th": 1.05, "haze": 0.55},
	{"el": 12.0, "zenith": "#3a86e8", "mid": "#7eb0ea", "horizon": "#f8c898", "ground": "#8a90a0", "glow": "#ffc283", "glow_a": 0.62,
	 "band": "#f0a07c", "band_a": 0.10, "sun_col": "#ffae68", "sun_e": 1.58, "amb": 0.68, "fog": "#ecd4b8", "fogd": 0.00060,
	 "expo": 1.0, "stars": 0.0, "cl_lit": "#fff0da", "cl_shade": "#86a4d6", "sat": 1.22, "glow_i": 0.4, "glow_th": 1.1, "haze": 0.42},
	{"el": 24.0, "zenith": "#2a82f0", "mid": "#62b2f6", "horizon": "#cde4f6", "ground": "#8fa4b8", "glow": "#fff0d0", "glow_a": 0.22,
	 "band": "#000000", "band_a": 0.0, "sun_col": "#ffd6a0", "sun_e": 1.64, "amb": 0.63, "fog": "#d4e4f2", "fogd": 0.00038,
	 "expo": 1.0, "stars": 0.0, "cl_lit": "#ffffff", "cl_shade": "#86a8dc", "sat": 1.18, "glow_i": 0.38, "glow_th": 1.1, "haze": 0.34},
	{"el": 45.0, "zenith": "#1f76ee", "mid": "#55acf8", "horizon": "#b8dcfa", "ground": "#8fa8c0", "glow": "#fff6e0", "glow_a": 0.1,
	 "band": "#000000", "band_a": 0.0, "sun_col": "#ffe8c8", "sun_e": 1.66, "amb": 0.60, "fog": "#c2e0fa", "fogd": 0.00028,
	 "expo": 1.0, "stars": 0.0, "cl_lit": "#ffffff", "cl_shade": "#8cb0e4", "sat": 1.16, "glow_i": 0.36, "glow_th": 1.1, "haze": 0.3},
]

const _COLOR_KEYS: PackedStringArray = ["zenith", "mid", "horizon", "ground", "glow", "band", "sun_col", "fog", "cl_lit", "cl_shade"]
const _FLOAT_KEYS: PackedStringArray = ["glow_a", "band_a", "sun_e", "amb", "fogd", "expo", "stars", "sat", "glow_i", "glow_th", "haze"]

static var _table: Array = []      # parsed keys (colours converted)
static var _decl_tan := 0.0
static var _lat_sin := 0.0
static var _lat_cos := 0.0
static var _decl_sin := 0.0
static var _decl_cos := 0.0
static var _inited := false


static func _init_table() -> void:
	if _inited:
		return
	_inited = true
	for k in _KEYS:
		var d: Dictionary = {"el": float(k["el"])}
		for ck in _COLOR_KEYS:
			d[ck] = Color(String(k[ck]))
		for fk in _FLOAT_KEYS:
			d[fk] = float(k[fk])
		_table.append(d)
	var lat := deg_to_rad(LATITUDE_DEG)
	var half_day := (SUNSET - SUNRISE) * 0.5
	var h0 := deg_to_rad(half_day * 15.0)
	var tan_decl := -cos(h0) / tan(lat)
	var decl := atan(tan_decl)
	_lat_sin = sin(lat)
	_lat_cos = cos(lat)
	_decl_sin = sin(decl)
	_decl_cos = cos(decl)


# ---- Sun / moon geometry ---------------------------------------------------------------------------
static func solar_noon() -> float:
	return (SUNRISE + SUNSET) * 0.5


## Returns Vector2(elevation_rad, azimuth_rad). Azimuth is measured from north (-Z) clockwise (east = +X).
static func sun_angles(hour: float) -> Vector2:
	_init_table()
	var h := deg_to_rad((hour - solar_noon()) * 15.0)
	var sin_el := _lat_sin * _decl_sin + _lat_cos * _decl_cos * cos(h)
	var el := asin(clampf(sin_el, -1.0, 1.0))
	var cos_el := maxf(cos(el), 1e-4)
	var cos_az := clampf((_decl_sin - sin_el * _lat_sin) / (cos_el * _lat_cos), -1.0, 1.0)
	var az := acos(cos_az)
	if sin(h) > 0.0:
		az = TAU - az
	return Vector2(el, az)


static func dir_from_angles(el: float, az: float) -> Vector3:
	var ce := cos(el)
	return Vector3(ce * sin(az), sin(el), -ce * cos(az))


## Unit vector from the world TOWARD the sun.
static func sun_direction(hour: float) -> Vector3:
	var a := sun_angles(hour)
	return dir_from_angles(a.x, a.y)


## Unit vector toward the moon: roughly opposite the sun, tilted a little so it does not trace the exact mirror arc.
static func moon_direction(hour: float) -> Vector3:
	var m := -sun_direction(hour) + Vector3(0.12, 0.0, -0.08)
	return m.normalized()


static func sun_elevation_deg(hour: float) -> float:
	return rad_to_deg(sun_angles(hour).x)


## 0 = full day, 1 = full night, smooth through dusk/dawn (drives window / lamp / neon emission).
static func night_amount(el_deg: float) -> float:
	return 1.0 - smoothstep(-9.0, 3.0, el_deg)


## true after solar noon
static func is_evening(hour: float) -> bool:
	return hour >= solar_noon()


# ---- Palette -------------------------------------------------------------------------------------------
## Base palette for a sun elevation (deg). Returns a fresh Dictionary of Colors/floats (see _KEYS for the names).
static func sample(el_deg: float, evening: bool = true) -> Dictionary:
	_init_table()
	var n := _table.size()
	var a: Dictionary = _table[0]
	var b: Dictionary = _table[0]
	var t := 0.0
	if el_deg <= float(_table[0]["el"]):
		a = _table[0]
		b = _table[0]
	elif el_deg >= float(_table[n - 1]["el"]):
		a = _table[n - 1]
		b = _table[n - 1]
	else:
		for i in range(n - 1):
			var e1 := float(_table[i]["el"])
			var e2 := float(_table[i + 1]["el"])
			if el_deg >= e1 and el_deg <= e2:
				a = _table[i]
				b = _table[i + 1]
				t = (el_deg - e1) / maxf(e2 - e1, 0.0001)
				t = t * t * (3.0 - 2.0 * t)
				break
	var out: Dictionary = {}
	for ck in _COLOR_KEYS:
		out[ck] = (a[ck] as Color).lerp(b[ck] as Color, t)
	for fk in _FLOAT_KEYS:
		out[fk] = lerpf(float(a[fk]), float(b[fk]), t)
	if not evening:
		# mornings: softer, pinker, mistier twilight than the saturated evening
		var low := 1.0 - smoothstep(-6.0, 14.0, el_deg)
		low *= smoothstep(-16.0, -6.0, el_deg)
		var glow_c: Color = out["glow"]
		out["glow"] = glow_c.lerp(Color("#ffa890"), 0.35 * low)
		out["band"] = (out["band"] as Color).lerp(Color("#f080b8"), 0.3 * low)
		out["horizon"] = (out["horizon"] as Color).lerp(Color("#ffbcae"), 0.18 * low)
		out["glow_a"] = float(out["glow_a"]) * (1.0 - 0.12 * low)
		out["fogd"] = float(out["fogd"]) * (1.0 + 0.9 * low)
		out["haze"] = minf(float(out["haze"]) * (1.0 + 0.2 * low), 1.0)
	return out


## Per-weather target parameter sets (all floats). The WeatherController blends between these.
const WEATHER_PARAMS := {
	&"clear": {"cover": 0.30, "dark": 0.0, "sun_vis": 1.0, "overcast": 0.0, "fog_add": 0.0, "fogginess": 0.0, "sat": 1.0,
		"amb_mul": 1.0, "rain": 0.0, "wind": 1.0, "wet": 0.0, "cloud_speed": 1.0, "lightning": 0.0, "expo_mul": 1.0, "contrast": 1.0},
	&"cloudy": {"cover": 0.74, "dark": 0.30, "sun_vis": 0.50, "overcast": 0.50, "fog_add": 0.0004, "fogginess": 0.04, "sat": 0.98,
		"amb_mul": 1.30, "rain": 0.0, "wind": 2.4, "wet": 0.0, "cloud_speed": 1.6, "lightning": 0.0, "expo_mul": 1.05, "contrast": 0.97},
	&"rain": {"cover": 0.92, "dark": 0.62, "sun_vis": 0.15, "overcast": 0.82, "fog_add": 0.0026, "fogginess": 0.18, "sat": 0.92,
		"amb_mul": 1.45, "rain": 0.70, "wind": 3.6, "wet": 0.9, "cloud_speed": 2.4, "lightning": 0.0, "expo_mul": 1.10, "contrast": 0.95},
	&"fog": {"cover": 0.50, "dark": 0.25, "sun_vis": 0.28, "overcast": 0.72, "fog_add": 0.0105, "fogginess": 1.0, "sat": 0.92,
		"amb_mul": 1.45, "rain": 0.0, "wind": 0.6, "wet": 0.15, "cloud_speed": 0.5, "lightning": 0.0, "expo_mul": 1.08, "contrast": 0.92},
	&"storm": {"cover": 1.0, "dark": 0.92, "sun_vis": 0.05, "overcast": 0.94, "fog_add": 0.0050, "fogginess": 0.35, "sat": 0.86,
		"amb_mul": 1.65, "rain": 1.0, "wind": 8.0, "wet": 1.0, "cloud_speed": 4.0, "lightning": 1.0, "expo_mul": 1.14, "contrast": 0.95},
}


static func weather_params(weather: StringName) -> Dictionary:
	return (WEATHER_PARAMS.get(weather, WEATHER_PARAMS[&"clear"]) as Dictionary).duplicate()


## Full lighting description for a sun elevation + blended weather parameters (see WEATHER_PARAMS keys).
## Returned keys: everything from sample() plus the derived values the EnvironmentSystem applies.
static func compose(el_deg: float, evening: bool, wx: Dictionary) -> Dictionary:
	var p := sample(el_deg, evening)
	var ov: float = wx.get("overcast", 0.0)
	var dark: float = wx.get("dark", 0.0)
	var fogginess: float = wx.get("fogginess", 0.0)
	var night := night_amount(el_deg)
	var day := 1.0 - night
	p["night"] = night
	p["el_deg"] = el_deg

	# sun
	var sun_vis_wx: float = wx.get("sun_vis", 1.0)
	p["sun_energy"] = float(p["sun_e"]) * sun_vis_wx
	p["sun_color"] = (p["sun_col"] as Color).lerp(Color(0.80, 0.86, 1.0), ov * 0.55)
	p["sun_disc_vis"] = smoothstep(-2.5, 1.5, el_deg)

	# ambient & exposure compensate for the missing direct light
	p["ambient_energy"] = float(p["amb"]) * lerpf(1.0, float(wx.get("amb_mul", 1.0)), day)
	p["exposure"] = float(p["expo"]) * lerpf(1.0, float(wx.get("expo_mul", 1.0)), day)
	p["saturation"] = float(p["sat"]) * float(wx.get("sat", 1.0))
	p["contrast"] = lerpf(1.0, 1.13, day) * float(wx.get("contrast", 1.0))
	p["stars_amt"] = float(p["stars"]) * (1.0 - ov * 0.9)

	# fog
	var fog_col: Color = p["fog"]
	var lum := fog_col.get_luminance()
	var grey := Color(lum * 0.96, lum * 1.0, lum * 1.05)
	var fog_out := fog_col.lerp(grey, clampf(ov * 0.5 + fogginess * 0.08, 0.0, 1.0))
	# thick fog is milky (pearl / pale peach), never the brown-grey mud a dark sunrise tint gives on a dim ground
	fog_out = fog_out.lerp(Color(0.94, 0.88, 0.88) * lerpf(0.55, 1.0, day), fogginess * 0.55)
	p["fog_color"] = fog_out
	p["fog_density"] = float(p["fogd"]) + float(wx.get("fog_add", 0.0))
	p["fog_aerial"] = lerpf(0.85, 0.12, fogginess)
	p["fog_sky_affect"] = lerpf(0.0, 1.0, smoothstep(0.1, 0.8, fogginess))
	p["fog_sun_scatter"] = lerpf(0.10, 0.02, ov) * day * (1.0 - fogginess * 0.5) + (0.10 * fogginess * day)
	p["fog_height"] = 8.0
	p["fog_height_density"] = fogginess * 0.045 + maxf(float(p["fogd"]) - 0.0010, 0.0) * 20.0
	p["haze_amt"] = clampf(float(p["haze"]) + fogginess * 0.5, 0.0, 1.0)

	# clouds
	var cl_lit: Color = p["cl_lit"]
	var cl_shade: Color = p["cl_shade"]
	var cl_lum := cl_lit.get_luminance()
	var cl_grey := Color(cl_lum * 0.82, cl_lum * 0.88, cl_lum * 0.96)
	var lit_out: Color = cl_lit.lerp(cl_grey, clampf(dark * 0.85, 0.0, 1.0)) * (1.0 - 0.40 * dark)
	lit_out.a = 1.0
	p["cloud_lit"] = lit_out
	var sh_lum := cl_shade.get_luminance()
	var shade_out: Color = cl_shade.lerp(Color(sh_lum * 0.7, sh_lum * 0.78, sh_lum * 0.9), clampf(dark * 0.9, 0.0, 1.0)) * (1.0 - 0.35 * dark)
	shade_out.a = 1.0
	p["cloud_shade"] = shade_out
	p["cloud_cover"] = float(wx.get("cover", 0.3))
	p["cloud_dark"] = dark
	p["overcast"] = ov
	p["glow_amount"] = float(p["glow_a"]) * (1.0 - ov * 0.75)
	p["band_amount"] = float(p["band_a"]) * (1.0 - ov * 0.85)

	# moon (energy handled by the caller because it needs the moon elevation)
	p["moon_night"] = smoothstep(-1.0, -11.0, el_deg)
	# visibility for gameplay systems (street lamps / headlights): 0 bright .. 1 dark
	p["gloom"] = clampf(maxf(night, smoothstep(0.35, 0.9, dark) * day * 0.85), 0.0, 1.0)
	return p
