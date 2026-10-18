# Environment API (EnvironmentSystem)

Owner: Environment agent. Boot key `environment` (`Game.sys(&"environment")`, class `EnvironmentSystem`, `gta/code/world/environment_system.gd`).
Always null-check the system and call through `has_method` if you want to stay tolerant of older builds.

## What it owns
| piece | file |
|---|---|
| WorldEnvironment + Environment (Forward+), sky, sun, moon, lightning light, reflection probe, quality | `environment_system.gd` |
| sun/moon position, palette keyframes (by sun elevation), weather modulation | `day_night_cycle.gd` (`DayNightCycle`, static, pure) |
| weather state machine, wetness, wind, lightning scheduling | `weather_controller.gd` (`WeatherController`) |
| rain streaks / ground splashes / rain curtain | `weather_fx.gd` (`WeatherFx`) |
| street-lamp lights + halos | `lamp_manager.gd` (`LampManager`) |
| underwater screen treatment | `environment_underwater.gd` (`EnvironmentUnderwater`) |
| shaders | `generated/shaders/sky_procedural.gdshader`, `weather_rain_streak/splash/sheet.gdshader`, `generated/vfx/lamp_halo.gdshader`, `underwater_overlay.gdshader` |

## Time of day
`Game.time_of_day` (hours 0..24) is advanced by `Game.time_scale` game-seconds per real second (default 60 -> 24 min per day) unless `Game.time_frozen`.
Sun rises at 06:00 (elevation 0) and sets at 19:00; maximum elevation ~56 deg; noon sun is in the south (+Z), mornings east (+X), evenings west (-X). 18:30 is golden hour, 19:00-19:45 is the magenta/orange dusk, 21:00 is night.

| call | meaning |
|---|---|
| `set_time(hour: float, instant := true)` | jump the clock; emits `Events.time_changed` (and `hour_changed` if the hour changed) immediately |
| `fast_forward_to(hour: float, seconds := 2.0)` | sleep / wait: runs the clock forward (wraps midnight) in `seconds` real seconds |
| `get_time() -> float` | same as `Game.time_of_day` |
| `get_sun_direction() -> Vector3` | unit vector from the world TOWARD the sun (also valid below the horizon) |
| `get_light_direction() -> Vector3` | direction the sunlight travels (`-get_sun_direction()`) |
| `get_moon_direction() -> Vector3` | unit vector toward the moon |
| `get_sun_elevation_deg() -> float` | degrees above the horizon (negative = night) |
| `is_night() -> bool` | `get_night_amount() > 0.5` (sun about 3 deg below the horizon) |
| `get_night_amount() -> float` | 0 day .. 1 night, smooth through dusk/dawn (this is `gta_night`) |
| `headlights_wanted() -> bool` | **use this for vehicle headlights / lamps**: dusk-to-dawn, dense fog, heavy rain, dark storm |
| `get_gloom() -> float` | 0 bright .. 1 dark (night OR storm gloom); drives street lamps |

> `Game.is_night()` (lead's rough `<5.5 or >20.5` test) is NOT synchronised with the sun (it flips ~1.5 h after sunset). Traffic / police / peds should call `EnvironmentSystem.is_night()` / `headlights_wanted()`; the lead may make `Game.is_night()` delegate to it.

Events: `Events.time_changed(hour: float)` about once per real second (not while frozen), `Events.hour_changed(hour: int)` on the hour.

## Weather
States `clear cloudy rain fog storm` (`GC.WEATHERS`).

| call | meaning |
|---|---|
| `set_weather(name: StringName, instant := false) -> bool` | 10 s smooth blend of sky, clouds, light, fog, rain, wind; `instant` snaps everything (and wetness). Requests during the first ~6 s after boot are always instant (so `DevHarness --weather=rain` shots are settled). Returns false for an unknown name |
| `get_weather() -> StringName` / `get_weather_transition() -> float` | target state / 0..1 blend progress |
| `is_raining()`, `get_rain_intensity()`, `get_wetness()`, `get_wind() -> Vector3` | live values (also in `Game.*`) |
| `get_visibility_distance() -> float` | metres where fog hides ~95% (clear ~3 km, fog ~200 m) |
| `trigger_lightning(distance := -1.0, azimuth := NAN)` | fire a strike now (distance m, azimuth rad from north clockwise) |
| `set_dynamic_weather(on: bool)` | Markov drift every 2.5-7 min (also `Game.settings["dynamic_weather"]`, default false) |

Writes every frame (cheaply): `Game.weather` (target state), `Game.rain_intensity`, `Game.wetness` (rises ~14 s to soaked under rain, dries over ~4-5 min), `Game.fog_amount`, `Game.wind` (m/s, gusty, slowly rotating).
Event: `Events.weather_changed(weather: StringName)` whenever the target state changes (also from dynamic drift / load).
Rain tuning of sibling systems: vehicles may scale grip with `Game.wetness`.
Storm: lightning every 5-15 s (sky flash, a drawn bolt, a flash light, ambient spike); thunder is `Sfx.play_2d(&"thunder")` delayed by distance/343 m/s (falls back to a pitched-down `explosion_big` with a warning if `thunder` does not exist).
Rain audio hook: if the Sfx bank has `rain_loop` (or `ambient_rain` / `rain`) the system plays it looped at a volume following the rain; AudioSystem may take over by exposing `handles_weather_audio() -> true`.

## Global shader parameters (`global uniform float ...`)
`gta_night` (0..1; 0.16 at 06:00 and at 19:00, 0.66 at 19:25, 1 by ~20:00 and until ~05:00), `gta_sun_energy` (0..1 incl. weather dimming), `gta_wetness`, `gta_rain`, `gta_fog` (0 clear .. 1 dense fog), `gta_time` (game seconds, wraps every 24 h).
Last-written values are readable with `get_shader_global(name) -> float` (works in headless runs, unlike `RenderingServer.global_shader_parameter_get`, which also logs an editor-only error).

## Street lamps
Content builders add `Node3D`s to group **`street_lamp`**. Meta: `lamp_height` (head height above the node origin, default 6.0), optional `lamp_offset` (Vector3, node-local, for lamp arms), `lamp_color` (Color), `lamp_energy` (float multiplier). Call `EnvironmentSystem.refresh_lamps()` after bulk placement (a count change is also detected every 2 s).
The 28 nearest lamps (within 95 m, with hysteresis and distance fading, re-assigned every 0.5 s) get a real `SpotLight3D` (warm, no shadows); up to 200 lamps within 150 m get an additive halo billboard (one MultiMesh draw call). Lamps fade on across dusk (per-lamp threshold) and rarely flicker; nothing runs by day. Emissive lamp heads should multiply their emission by `gta_night` (World-Content material `LampGlow`).

## Underwater
Automatic when the camera is below `GC.WATER_LEVEL` over water (`WorldLayout.is_water`) or `Game.player.is_underwater` is true: turquoise fog (visibility ~55 m at the surface, ~30 m deep; deeper = darker), dimmer breathing sun, SSAO off, full-screen overlay (wobble, grade, caustics, vignette on a CanvasLayer at layer -50, below the HUD), cross-fade in ~0.3 s / out ~0.7 s.
`is_underwater()`, `get_underwater_amount()`, signal `EnvironmentSystem.underwater_changed(is_underwater: bool)` (for the Audio agent's muffling), `set_underwater_override(-1|0|1)` for tests / cutscenes.

## Look & quality
AgX tonemap, per-time exposure/saturation/contrast, glow (bloom for neon/headlights/windows, HDR threshold 1.0), cheap half-res SSAO, exponential fog with aerial perspective (distance fog takes the sky colour) + sun scatter + height mist, soft PCSS-ish sun shadows (4 PSSM splits, 220 m), moon light at night, sky reflection + a `ReflectionProbe` that follows the player (one recapture at most every 4 s while moving, otherwise every 30 s), SSR only while the ground is wet, viewport debanding.
`Game.settings` keys read (all optional): `shadows` (bool), `env_quality` (0 low / 1 medium / 2 high, default 2), `ssao`, `glow`, `reflections`, `ssr` (bool, default on at quality 2), `dynamic_weather`. Changes apply on `Events.settings_changed` (or within 1 s). `apply_quality()` re-reads them.
Low = 2 PSSM splits/110 m, 12 lamp lights, half the rain; medium = 170 m shadows, 20 lamp lights, 75% rain.

## Other API
`get_sun_light() -> DirectionalLight3D`, `get_environment() -> Environment`, `get_palette() -> Dictionary`, `get_cpu_cost_ms()`, `get_stats()`; public nodes `world_environment, environment, sun, moon, flash_light, probe, lamps, weather_fx, underwater_fx, weather`.
`DayNightCycle` static helpers (no nodes needed): `sun_direction(hour)`, `moon_direction(hour)`, `sun_elevation_deg(hour)`, `night_amount(el_deg)`, `compose(el_deg, evening, weather_params)`.
Booting is independent of the other systems: camera = `get_viewport().get_camera_3d()` (fallback `Game.gameplay_camera`), player optional.

## Cost (RTX 5070, 1920x1080, light test city - see `gta/tests/env_perf.gd`)
Whole environment (sky + SSAO + glow + fog + tonemap) ~0.2-0.3 ms GPU, sun shadows +0.04 ms in the test city (scale with the real scene), 28 lamp lights + halos ~0.05 ms, rain +0.2-0.45 ms, SSR while raining +0.2 ms, underwater frame ~0.65 ms total. Script cost ~0.06-0.09 ms/frame. Probe recapture is a one-frame cost (~1 ms in the test city).

## Limits / notes
- Clouds are a procedural sky layer (no volumetric clouds), the moon phase is fixed (gibbous), stars are static.
- `fog_amount`/rain do not change traffic/AI by themselves; siblings read `Game.wetness`, `Game.rain_intensity`, `EnvironmentSystem.headlights_wanted()`.
- Rain particles are thinned (not removed) under a roof (ray up 28 m on `GC.L_WORLD`); vehicle roofs do not shelter.
- No interior mode yet (an interior system should call `set_underwater_override`-style helpers or hide `weather_fx`).
