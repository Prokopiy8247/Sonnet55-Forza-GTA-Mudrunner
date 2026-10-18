class_name WeatherController
extends RefCounted
## Weather state machine for EnvironmentSystem (no nodes - testable headless):
##  - states clear / cloudy / rain / fog / storm (GC.WEATHERS), smooth 10 s transitions of every parameter
##  - wetness that rises fast under rain and dries slowly afterwards
##  - wind (direction drifts, gusts), fog amount, rain intensity
##  - storm lightning: schedules strikes, produces a flash envelope (multi-pulse) and emits `lightning`
##  - optional automatic weather drift (Markov chain) when `auto_drift` is true

signal state_changed(weather: StringName)
signal lightning(distance: float, azimuth: float)

const TRANSITION_TIME := 10.0
const WETNESS_RISE := 0.07           # per second while the target is above the current value
const WETNESS_DRY := 0.0035          # per second while drying (about 4-5 real minutes from soaked)

var state: StringName = &"clear"
var params: Dictionary = DayNightCycle.weather_params(&"clear")   # current blended parameters (see DayNightCycle.WEATHER_PARAMS)
var transition := 1.0                # 0..1, 1 = settled
var wetness := 0.0
var rain := 0.0                      # current rain intensity 0..1
var fog_amount := 0.0
var wind := Vector3(1.0, 0.0, 0.3)

# lightning
var flash := 0.0                     # current flash envelope 0..1
var bolt_azimuth := 0.0              # radians, direction of the last bolt (world, atan2 style, see EnvironmentSystem)
var bolt_strength := 0.0
var bolt_seed := 1.0
var lightning_enabled := true

# optional automatic drift
var auto_drift := false

var _from: Dictionary = {}
var _to: Dictionary = {}
var _clock := 0.0
var _lightning_timer := 6.0
var _pulses: Array = []              # [start_time, peak, decay]
var _bolt_clock := 0.0
var _drift_timer := 240.0
var _rng := RandomNumberGenerator.new()
var _wind_angle := 0.35


func _init() -> void:
	_rng.randomize()
	_from = params.duplicate()
	_to = params.duplicate()


## Switches the target weather. instant = snap every parameter (and wetness) immediately.
func set_state(weather: StringName, instant: bool = false) -> bool:
	if not (weather in GC.WEATHERS):
		return false
	var changed := weather != state
	state = weather
	_from = params.duplicate()
	_to = DayNightCycle.weather_params(weather)
	if instant:
		params = _to.duplicate()
		transition = 1.0
		_sync_outputs()
		wetness = wetness_target()
	else:
		transition = 0.0
	_lightning_timer = _rng.randf_range(3.0, 8.0)
	if changed or instant:
		state_changed.emit(weather)
	return true


func is_settled() -> bool:
	return transition >= 1.0


func update(delta: float) -> void:
	_clock += delta
	if transition < 1.0:
		transition = minf(transition + delta / TRANSITION_TIME, 1.0)
		var s := smoothstep(0.0, 1.0, transition)
		for k in _to:
			params[k] = lerpf(float(_from.get(k, 0.0)), float(_to[k]), s)
	rain = clampf(float(params.get("rain", 0.0)), 0.0, 1.0)
	fog_amount = clampf(float(params.get("fogginess", 0.0)), 0.0, 1.0)

	# wetness: soaks fast while it rains, dries slowly afterwards
	var target := wetness_target()
	if wetness < target:
		wetness = minf(wetness + WETNESS_RISE * delta * lerpf(0.4, 1.0, target), target)
	else:
		wetness = maxf(wetness - WETNESS_DRY * delta, target)

	# wind: slowly rotating direction, gusty magnitude
	_wind_angle += delta * 0.01 * (0.4 + float(params.get("wind", 1.0)) * 0.15)
	var strength := float(params.get("wind", 1.0))
	var gust := 1.0 + 0.35 * sin(_clock * 0.71) * sin(_clock * 0.23 + 1.3)
	wind = Vector3(cos(_wind_angle), 0.0, sin(_wind_angle) * 0.6) * strength * gust

	_update_lightning(delta)
	if auto_drift:
		_update_drift(delta)


## Wetness the surfaces converge to for the current (blended) parameters.
func wetness_target() -> float:
	return clampf(maxf(rain * 1.2, float(params.get("wet", 0.0))), 0.0, 1.0)


func _sync_outputs() -> void:
	rain = clampf(float(params.get("rain", 0.0)), 0.0, 1.0)
	fog_amount = clampf(float(params.get("fogginess", 0.0)), 0.0, 1.0)


# ---- Lightning --------------------------------------------------------------------------------------
func _update_lightning(delta: float) -> void:
	_bolt_clock += delta
	# envelope
	var f := 0.0
	var i := 0
	while i < _pulses.size():
		var p: Array = _pulses[i]
		var age: float = _bolt_clock - float(p[0])
		if age > 1.6:
			_pulses.remove_at(i)
			continue
		if age >= 0.0:
			f = maxf(f, float(p[1]) * exp(-age / float(p[2])))
		i += 1
	flash = f
	if _pulses.is_empty():
		bolt_strength = 0.0
	else:
		bolt_strength = clampf(f * 1.4, 0.0, 1.0)

	var rate := float(params.get("lightning", 0.0))
	if lightning_enabled and rate > 0.35:
		_lightning_timer -= delta * rate
		if _lightning_timer <= 0.0:
			trigger_lightning()
			_lightning_timer = _rng.randf_range(5.0, 15.0)


## Fires one strike. distance < 0 picks a random one (mostly far, occasionally close).
func trigger_lightning(distance: float = -1.0, azimuth: float = NAN) -> void:
	if distance < 0.0:
		distance = _rng.randf_range(120.0, 400.0) if _rng.randf() < 0.18 else _rng.randf_range(500.0, 2600.0)
	if is_nan(azimuth):
		azimuth = _rng.randf() * TAU
	bolt_azimuth = azimuth
	bolt_seed = _rng.randf_range(1.0, 100.0)
	var amp := clampf(1.15 - distance / 3200.0, 0.30, 1.0)
	var t0 := _bolt_clock
	_pulses.append([t0, amp, 0.07])
	_pulses.append([t0 + 0.11, amp * 0.65, 0.06])
	_pulses.append([t0 + 0.23, amp * 0.95, 0.16])
	if _rng.randf() < 0.4:
		_pulses.append([t0 + 0.46, amp * 0.5, 0.10])
	lightning.emit(distance, azimuth)


# ---- Automatic drift ------------------------------------------------------------------------------------
const _NEXT := {
	&"clear": [[&"clear", 1], [&"cloudy", 4]],
	&"cloudy": [[&"clear", 3], [&"rain", 3], [&"fog", 1], [&"cloudy", 1]],
	&"rain": [[&"cloudy", 4], [&"storm", 2], [&"rain", 1]],
	&"fog": [[&"clear", 3], [&"cloudy", 2]],
	&"storm": [[&"rain", 4], [&"cloudy", 2]],
}


func _update_drift(delta: float) -> void:
	_drift_timer -= delta
	if _drift_timer > 0.0:
		return
	_drift_timer = _rng.randf_range(150.0, 420.0)
	var options: Array = _NEXT.get(state, _NEXT[&"clear"])
	var total := 0.0
	for o in options:
		total += float(o[1])
	var r := _rng.randf() * total
	for o in options:
		r -= float(o[1])
		if r <= 0.0:
			set_state(o[0])
			return
