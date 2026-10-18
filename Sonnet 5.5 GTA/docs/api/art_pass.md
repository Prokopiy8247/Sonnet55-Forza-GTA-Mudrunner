# Art pass (look-dev) - Halcyon Bay

Owner: art-direction / tech-art agent. Scope: colour, light, tonemap, post, sky, weather look, ground / facade / water / vegetation
shaders and material constants. No structural or gameplay changes. **Status: pass complete (2 sessions); see "Changelog" and "Remaining" at the bottom.**

## Problem (lead review of the first build)
Spawn plaza (09:30) and most of the city at midday were over-exposed and washed out: near-white pavement tiles, roofs / pale walls blown to
white, low contrast, flat overhead light, thin curb faces black at night (SSAO), heavy haze in wide shots, little pastel + neon identity.

## What changed (files)
| area | file | summary |
|---|---|---|
| light / palette | `gta/code/world/day_night_cycle.gd` | key table is by sun elevation; max sun elevation lowered to ~48 deg (`LATITUDE_DEG` 48) so noon facades get gradients and long soft shadows; per-key sky gradient, fog colour/density, ambient energy, exposure, saturation, bloom threshold, cloud colours re-authored (vivid blue day, warm golden hour, magenta dusk, navy night); haze (aerial perspective) kept low at noon; weather params (`WEATHER_PARAMS`) with milky not-grey overcast |
| environment | `gta/code/world/environment_system.gd` | AgX tonemap (white 6.0), ambient from sky (night: flat moonlit blue fill `NIGHT_AMBIENT_COLOR`), SSAO radius 1.3 / power 1.35, intensity 1.5 day -> 0.7 night (`SSAO_DAY_INTENSITY`, `SSAO_NIGHT_INTENSITY`) so curbs never go black, glow only above HDR threshold 1.1 (neon / headlights / lit windows), brightness 1.0 / contrast 1.05-1.13 / saturation 1.1-1.26 per time, sun shadows: bias 0.04, normal bias 1.4, blur 1.1, 4 PSSM splits to 220 m, angular size 0.3 |
| ground | `gta/generated/shaders/world_road.gdshader` | asphalt: charcoal with world-position noise (3 octaves), cool/warm patch drift, tyre tracks, cracks, patches, oil; crisp white / yellow markings with wear; sidewalk 1.5 m tiles with per-tile tone + seams + dirt; **plaza = 2.4 m sandstone / terracotta checker with slate accent tiles, inlay lines, grout, mottling** (no more white tiles); apron slabs; wet look: darker, rough 0.12, spec 0.95, puddles, fake neon / lamp reflections at night |
| terrain | `gta/generated/shaders/world_terrain.gdshader` | grass in 2 greens + dry + dark lush patches (not neon), sand with wet edge and underwater tint, sandstone strata rock, concrete slabs with seams for yards, faceted normals, wet darkening |
| buildings | `building_wall.gdshader`, `building_window.gdshader`, `building_common.gdshaderinc`, `facade_materials.gd` | per-district pastel palettes, darker trims / roofs, ground-floor grime + height gradient, window glass reflects sky by day (gradient + fresnel), lit windows at night (warm yellow dominant, sparse cyan / magenta, curtains, tv flicker), wet gloss; draw-call count unchanged (same merged materials) |
| lamps | `gta/code/world/lamp_manager.gd` | warm sodium-ish pools, 28 nearest spot lights, halos in one MultiMesh |
| sky | `gta/generated/shaders/sky_procedural.gdshader` | gradient + sun disc + sunset bands + stylised clouds + stars + moon |
| water | `gta/generated/shaders/world_water.gdshader` | 3-stop depth ramp (turquoise -> blue -> navy), shoreline foam, sun / moon glitter, sky fresnel, night navy |

## Reference views (the "fixed set")
18 views, one Godot session, defined in `gta/tests/art_batch.gd` (`VIEWS`): spawn_0930, spawn_1200, downtown_1745, downtown_2100,
resid_1500, pier_sunset, beach_noon, industrial_1000, airport_1400, hills_1830, air_noon, rain_dusk, fog_dawn, storm, night_neon,
underwater, car_day, car_night. Extra tuning views are prefixed `x_` (cloudy, dawn city, rain night, sunset air, sea night, plaza night...).

```
powershell -NoProfile -File tools\art_shots.ps1 -Tag after                    # all 18 -> screenshots\art\after_<view>.png
powershell -NoProfile -File tools\art_shots.ps1 -Tag t1 -Only spawn_1200,car_night
powershell -NoProfile -File tools\art_shots.ps1 -Tag t1 -Only x_cloudy,x_plaza_night
powershell -NoProfile -File tools\art_perf.ps1 -Tag after                    # cpu/gpu ms + draw calls in 5 views
```
`-EnvOver 'tonemap_white:5.5,adjustment_contrast:1.1'` applies numeric Environment overrides for quick experiments (not persisted).
`before_*.png` = the build the lead reviewed; `r1_*` = state at the start of the second tuning session; `final_*` = end of the pass.

## Key tuned values (all in code, nothing is data-driven from outside)
| value | where | now |
|---|---|---|
| tonemap | `environment_system.gd` | AgX, white 6.0, exposure per palette key (1.0; 1.05-1.08 at sunrise / sunset so backlit ground is not murky) |
| ambient | `environment_system.gd` `_refresh_palette` | source SKY, day: `DAY_SKY_CONTRIB` 0.34 + soft lavender-grey tint (0.68, 0.70, 0.78) * `DAY_AMBIENT_TINT_GAIN` 0.74, blended toward the horizon colour at golden hour (`warm_k`); night: `NIGHT_SKY_CONTRIB` 0.55 + `NIGHT_AMBIENT_COLOR`. Reason: pure sky radiance gave cobalt shadows |
| sun | `day_night_cycle.gd` | max elevation ~48 deg (lat 48), colour per key: noon #ffe8c8, el 24 #ffd6a0, el 12 #ffae68 (17:45 reads late-afternoon gold), el 6 #ffae60; energy 1.4-1.66 |
| shadows | `environment_system.gd` | 4 splits, 220 m, blur 1.1, bias 0.04 / normal bias 1.4, angular distance 0.3 (2.2 overcast) |
| SSAO | `environment_system.gd` | radius 1.3, power 1.35, intensity 1.5 day -> 0.7 night |
| glow | palette keys | intensity 0.36-0.6, HDR threshold 1.0-1.1 (only neon / lamps / lit windows / headlights bloom) |
| adjustments | palette keys | saturation 1.16-1.26 (day), contrast 1.05 * 1.13 day, brightness 1.0 |
| fog | palette keys + `compose()` | noon density 0.0003-0.0006 (mountains readable, no haze), golden hour 0.00058-0.00092 (was ~0.0012-0.0013), night 0.001; thick fog colour is milky pearl / pale peach, never brown-grey |
| plaza | `world_road.gdshader` mode 11 | `plaza_a` (0.73, 0.65, 0.53), `plaza_b` (0.65, 0.56, 0.46), 2.4 m tiles, slate accents, inlay, grout, mottling |
| runway / taxiway | `world_road.gdshader` modes 7 / 8 | 3-octave variation, cool / warm drift, wheel-track polish, rubber streaks after 8 m |
| sea | `world_water.gdshader` | ripples / normal facets fade with view distance (70-280 m), crest speckles only < 110 m, roughness 0.06 -> 0.30 with distance, sun glitter uses the smooth ripple normal -> no white confetti / moire on the open sea |

## Perf guard (`tools\art_perf.ps1`, 1600x900, RTX 5070, no traffic / peds, **8 other Godot processes were running** so CPU numbers are noisy +-1 ms, GPU +-0.3 ms)
| view | before pass (22:27) cpu / gpu ms | start of round 2 | end of round 2 |
|---|---|---|---|
| spawn 09:30 | 1.27 / 1.55 | 1.80 / 1.76 | 2.23 / 1.74 |
| downtown noon | 2.45 / 1.21 | 2.99 / 1.26 | 2.61 / 1.28 |
| air noon | 1.47 / 1.06 | 1.54 / 1.38 | 1.64 / 1.34 |
| night street | 1.80 / 1.20 | 1.99 / 1.74 | 2.83-3.46 / 1.27-1.71 |
| rain dusk | 2.58 / 1.82 | 3.57 / 1.95 | 3.49 / 1.98 |
Round 2 itself is cost-neutral (same GPU ms within noise: constants, one extra `mix` per frame on the CPU side, a few ALU ops in the water / runway shaders; no new textures or loops). Against the pre-pass baseline GPU is +0.07..+0.5 ms, but draw calls grew by ~50% in the same views (spawn 1218 -> 2146, night street 1800 -> 2755) because other agents added content, so the delta is not attributable to the art pass alone. Draw-call count of the art-owned materials is unchanged (same shared / merged materials).

## Before / after pairs (screenshots\art\)
`before_<view>.png` (the build the lead reviewed) vs `final_<view>.png` for all 18 reference views, plus `final_x_*.png` extras
(cloudy, plaza night, night / sunset from the air, rain at night, beach sunset, sea at night, dawn city). Intermediate rounds: `t10_*`, `t11_*` (round 1), `r1_*` (start of round 2) ... `r10_*`.
Best pairs: spawn_0930, spawn_1200, downtown_1745 / 2100, beach_noon, air_noon, fog_dawn, car_day / car_night.

## Changelog
- Round 1 (first agent, interrupted by the usage limit): palette keys, sun path, AgX + SSAO / glow tuning, ground / facade / window / terrain / water / sky shaders, lamps, wet roads (`t10_*`, `t11_*`).
- Round 2: re-shot the whole set (`r1_*`) and judged it. Fixed: cobalt shadows (ambient = 34% sky + lavender tint, warm at golden hour), plaza hue (less pink), 17:45 not golden (warmer sun / horizon / fog at el 12-24), over-orange dusk haze (fog density -25..35% at el -4..6), muddy brown fog (milky pearl), white confetti / moire on the sea in aerial views, flat runway asphalt, murky backlit ground at sunset (exposure 1.05-1.08, warm ambient). Docs + final before/after set.

## Remaining / not in this pass's scope
- Vehicle headlight pools on the ground are weak in `car_night` (owned by `vehicle_lights.gd`, vehicles agent).
- Underwater seabed has no props (content, not look); overlay caustics are large-scale arches (`generated/vfx/underwater_overlay.gdshader`) - fine but could be smaller.
- Sunset wide shots toward the sun are intentionally orange (el ~2 deg); the haze is already reduced, the sky glow itself is the colour.
- Airport infield grass is a flat, slightly lime quad material (airport_builder.gd, not terrain shader) - could use the terrain grass shader.
- A parse error from another agent's in-progress `air_searchlight.gd` (`AirSearchlight` class not in the cache) prints during runs; unrelated to the look.
