# FH5 reference: weather, seasons, time of day, presentation of light

Research notes for the original game in this folder (UE 5.8, ~4 x 4 km world, code-generated assets). Forza Horizon 5 (FH5) is used only as a feature-scope and structure reference. Everything below is paraphrased; nothing is copied from sources.

Confidence tags used throughout:

- **[S]** stated by an official or press source (see section 13).
- **[C]** community / forum anecdote, treat as weak.
- **[E]** verified by reading the UE 5.8 install (headers or source) on this machine.
- **[P]** physics or photometry rule of thumb with a source behind it.
- **[D]** design decision / starting value made for this project. Tunable, not a fact about FH5.

---

## 1. What FH5 does (facts, own words)

### 1.1 Seasons

- Four seasons, and the season changes **weekly** (automatically, Thursday 14:30 GMT per guide sites) [S]. In the main free-roam modes the player cannot pick the season; Creative Hub / EventLab blueprints and custom races can pick any season and weather [S/C].
- The big change versus FH4: seasons are **per biome**, not map-wide [S]. In FH4 most of the UK went white in the winter week; in FH5 snow exists only high up on the volcano while the coast is still hot. Rain at the top of the volcano turns to snow (a Playground dev said so), and snow cover thickens the higher you drive [S].
- Regional season effects named by Playground [S]: spring = rainy season in jungles and farmland; summer = intense tropical thunderstorms on the coasts; autumn = "storm season" (tropical storms blowing in off the coast, palms and foliage thrown around); winter = dry season (dust storms, a large lake in the Arid Hills dries out opening shortcuts, snow and blizzards on the volcano). Riverbeds fill and dry with wet and dry seasons [S].
- A community-sourced naming (Spring "Hot", Summer "Wet", Autumn "Storm", Winter "Dry") conflicts with the official "spring is rainy" statement; treat the local labels as unverified [C]. Our game uses its own labels (section 4).
- Pause/map screens show the current season (one article shows the map in the wet season) [C]; no official HUD description was found.

### 1.2 Biomes and weather appearance

- 11 biomes: canyon, tropical coast, farmland, arid hills, jungle, living desert, rocky coast, sand desert, swamp, the city of Guanajuato, and the volcano [S].
- Weather is **regional**: a sprinkle in the living desert can coexist with a torrential downpour in the jungle [S]. Storms are localized, can be seen from far away and driven toward ("storm chasing"), start local and **swell and grow over time** [S].
- Sky variety: Playground shot over 400 hours of real Mexican sky with a 3-camera rig (12K stitched frames, one every 30 s, ~75 TB), giving **2000+ sky presets** versus ~300 in FH4. Each season has its own sky captures and weather types; each condition's lighting was modeled separately [S].
- Custom races can mix time of day and weather, e.g. "midday rain" or "clear sunset" [S].

### 1.3 Weather types

- Photo mode lists (official patch notes) [S]:
  - Weather (10): Default, Clear, Clear Post Rain, Cloudy, Cloudy Post Rain, Overcast, Light Precipitation, Heavy Precipitation, Gale, Fog.
  - Time of day (9): Default, Dawn, Sunrise, Morning, Early Afternoon, Late Afternoon, Sunset, Evening, Night.
  - "Post Rain" means wet roads and sky leftovers without active rain, i.e. FH5 models a drying state.
- Seasonal big events [S]: **dust storms** (dry season; real 3D volumetric particles that light passes through, not a screen filter), **tropical storms** (autumn; heavy mist and atmosphere, flying debris), **blizzards** (volcano).
- Reviews say driving into a dust storm leaves only a few feet visible on either side of the car [C]. A tropical-storm race and a storm flythrough are scripted in expeditions [S].
- Rally Adventure expansion (2023) added physics-driven dust plumes behind cars (called the most complex weather effect in the series), plus deformable sand/dirt roads and a night helicopter spotlight on low-visibility stages; lead cars' dust can force you to brake [S].
- Gamers report rain is hard to find in free roam and shows up mostly in events [C]. Lesson: if weather variety is a selling point, schedule it deliberately.

### 1.4 How weather changes driving

- Official wording is vague: Playground says weather has a "significant impact" on driving; storm-week coast driving is disrupted (waves, flying foliage) [S].
- Reviews: roads go from dry to rain-slicked, dirt turns to mud and cars slide unless you adapt; puddles and standing water can wash out roads; water splashes and collects on the car (visual) [C].
- Community: rain behaves mostly as an **overall grip debuff** you can drive through with the same lines; large puddles can take a car out; street/stock and rally tires are more predictable in rain, dirt, puddles; full slicks lose the most; AI is reported to ignore wetness [C].
- **No numeric grip values exist in any source found.** All grip numbers below are derived from real tire-friction tables plus an arcade compression (section 6) [P/D].

### 1.5 Day/night

- No official day-length figure. Guide sites put a full cycle at about **1 h 40 min with only the last ~10 min being night**, free-roam time cannot be skipped or set, and night is reached by taking night-only events [C]. Night was temporarily extended for a festival (nights lengthened 30 Mar to 27 Apr 2023) with neon decorations [S].
- Photo mode exposes 9 time slots (see 1.3). Photo-mode advice from Turn 10: morning/evening are easiest to expose, midday suits stormy weather and shaded cities, desert midday overexposes, night shots need a light source; baseline exposure 50 [S].

### 1.6 Lighting and sky tech

- A new global-illumination system plus volumetric lighting for fog/dust/humidity; sky captured in HDR and used as real light that changes each frame [S]. Ray tracing only in the car viewer (Forzavista), not in the open world [S].
- Foliage reacts to storms (blown vegetation) [S].

### 1.7 Color / post look

- No official statement on grading beyond photo-mode controls: Contrast, Color (saturation), Brightness, Temperature (all default 50), plus Sepia/Vignette, Exposure, Aperture (natural look 7-13), Shutter, Bokeh, Zoom [S]. The look is high-saturation, high dynamic range, warm golden light, strong skies. Specific grade values below are my interpretation [D].
- Players complain auto-exposure shifts with car color / sun movement [C]; keep our exposure bounded and slow (section 8.5).

### 1.8 How conditions are communicated

- I found **no official or reliable description of a HUD weather widget** in FH5. Evidence says conditions are conveyed mainly diegetically (sky, storm walls visible from afar, particles, wet surfaces, car water), via the map/pause season banner, and in menus/photo mode/EventLab lists [C]. Section 10.5 defines our own HUD.
- Weather and time are fixed in some activities (e.g. open drifting events lock a time/weather) [C].

### 1.9 Known gaps

No numeric grip, no visibility distances, no official day length, no HUD spec, no cloud tech spec for FH5. All numbers in sections 4-10 are engineering design, anchored to UE docs/source and real-world photometry.

---

## 2. Decisions for THIS project

| Feature | Decision | Reason |
|---|---|---|
| Four seasons with distinct weather weights | ADAPT | Core flavor; one season active at a time (selectable + optional weekly live rotation), cheap data table. |
| Weekly automatic season change | ADAPT | Use real-UTC-week rotation as an optional toggle (off by default for stable recordings); console `season`. |
| Per-biome seasons | ADAPT | 4 climate zones (Coast, Valley, Dry Hills, Mountain) instead of 11 biomes; altitude-based snow line. |
| Localized, growing, visible storms | ADAPT | "Weather cells" (max 2 active) with radius, velocity, lifetime envelope; fits a 4x4 km map and gives storm-chasing. |
| Dust storm wall (dry season) | ADAPT | Local Fog Volume + Niagara sheets + dense height fog inside a moving cell in Dry Hills; no full 3D dust sim. |
| Snow only high up, rain turns to snow with altitude | ADOPT | Matches mountain passes; temperature/altitude rule. |
| Photo-mode style weather list (clear, post-rain, cloudy, overcast, light/heavy precip, gale, fog) | ADAPT | Use as our `EWeatherState` set plus a "wet, no rain" drying state. |
| 9 time-of-day presets | ADOPT | Console `time`/photo mode presets map to fixed sun elevations. |
| 2000 captured skies | SKIP | Replace with SkyAtmosphere + VolumetricCloud + engine `m_SimpleVolumetricCloud` parameters and ~8 weather presets. |
| Short night (~10% of cycle) | ADOPT | Elevation-based time warp that speeds the dark part (section 8.2). |
| Real-time raytraced or captured GI | SKIP | Lumen (project already `r.DynamicGlobalIlluminationMethod=1`) handles the dynamic sun. |
| Drying lakes / season-dependent water | SKIP | Out of scope; at most a lake mesh Z offset later. |
| Physics-driven dust trails | ADAPT | Speed-scaled Niagara dust on dirt/sand/gravel, no physics coupling; optional follow-dust visibility reduction. |
| Weather affects AI | ADAPT | FH5 AI reportedly ignores it; we scale traffic target speed by 0.7-0.9 in bad weather (cheap, more believable). |
| Grip numbers per surface x condition | ADAPT | No FH5 data; derive from friction tables with arcade compression (section 6). |
| Dedicated HUD weather indicator | ADAPT | FH5 has no confirmed one; we add minimal chip + grip/visibility warnings (section 10.5). |
| Rain scarcity in free roam | SKIP (avoid) | We guarantee a non-clear state at least every ~10 min and bias spring/autumn. |

---

## 3. Architecture (C++, module `Sonnet55Forza`)

- `ASkyWeatherManager` (one per level, Tick 30 Hz for environment, 60 Hz not needed). Owns components: `USkyAtmosphereComponent`, `UVolumetricCloudComponent`, `UExponentialHeightFogComponent`, `UDirectionalLightComponent Sun` (index 0), `UDirectionalLightComponent Moon` (index 1), `USkyLightComponent`, an unbound `UPostProcessComponent`, camera-attached Niagara rain/snow/dust components, star-dome mesh component.
- `UWeatherSubsystem : UWorldSubsystem` is the single query API for gameplay: `GetGripMultiplier(ESurface, FVector WorldPos)`, `GetVisibilityMeters(FVector)`, `GetWetness()`, `GetSnowCover(FVector)`, `GetPuddleDepth(FVector2D)`, `GetLocalTemperatureC(FVector)`, `GetSunElevationDeg()`, `IsNight()`, `ShouldHeadlightsBeOn(FVector)`.
- Data: `UWeatherPresetDataAsset` (rows in section 5), `USeasonDataAsset` (section 4), `UCurveLinearColor`/`UCurveFloat` keyframes from section 8 (create in code if assets are not hand-authored). Use a Material Parameter Collection `MPC_Weather` (Wetness, PuddleAmount, SnowCover, DustAmount, WindDir/WindSpeed, SeasonTint, StormCell0/1 xy+radius+intensity) so road, terrain, foliage and cloud materials read the same state.
- Console / save: `time <hour>`, `weather <state>`, `season <name>`, `daylength <realMinutes>`, `freezeweather`; persist time, season, weather (prompt section on save games).
- Do not enable the `SunPosition` plugin just for the sun: it is not in `Sonnet55Forza.uproject` (plugins: Niagara, Metasound, PCG, Water, ...). The math is 10 lines (section 8.1). The plugin API for reference: `USunPositionFunctionLibrary::GetSunPosition(Latitude, Longitude, TimeZone, bIsDaylightSavingTime, Year, Month, Day, Hours, Minutes, Seconds, FSunPositionData&)` returning Elevation, CorrectedElevation, Azimuth [E].
- Project render settings already relevant [E, from `Config/DefaultEngine.ini`]: Lumen GI + Lumen reflections, Virtual Shadow Maps, Substrate, `r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange=True` (EV100 values are the extended range; do not toggle later, it invalidates all exposure settings), local exposure highlight/shadow scale 0.8.

---

## 4. Seasons spec

Own labels (original game): **Spring = Rainy, Summer = Hot, Autumn = Storm, Winter = Dry**. Rotation: manual (menu/console) with optional "Live season" = `(UTC week number) % 4`; default fixed Summer so recordings are reproducible.

Reference latitude for the sun: **36 N** [D] (temperate; gives visibly different sun heights per season). Declination `delta = 23.44 deg * sin(2*pi*(N-81)/365)`, N = day of year. Use fixed anchor days per season so the look is reproducible: Spring N=80 (equinox), Summer N=172 (solstice), Autumn N=266 (equinox), Winter N=355 (solstice); the table values below use exactly these anchors.

| Season | Sun noon elevation (36N, solstice/equinox) | Day length | Sunrise / sunset (solar time) | Base temp C (day mean) | Snow line (normalized altitude a=0..1) | Foliage/grass tint (sRGB) | Haze mult (Mie scale) | Cloud coverage bias |
|---|---|---|---|---|---|---|---|---|
| Spring (Rainy) | 54 deg (equinox) | 12.1 h | 06:00 / 18:00 | 14 | 0.90 | fresh green `#5E8F2E` | 1.2 | +0.10 |
| Summer (Hot) | 77 deg (solstice) | 14.5 h | 04:45 / 19:15 | 27 | none (1.2) | yellow-green `#8A9A3A` | 1.0 | -0.10 |
| Autumn (Storm) | 54 deg (equinox) | 12.1 h | 06:00 / 18:00 | 13 | 0.80 | orange-brown `#A07A2C` | 1.4 | +0.15 |
| Winter (Dry) | 31 deg (solstice) | 9.5 h | 07:15 / 16:45 | 3 | 0.60 | desaturated tan `#7C7A55` | 0.8 (dry, clear) | -0.05 |

Day length derivation (computed): `L = (2/15) * acos(-tan(phi) * tan(delta))` degrees to hours; at 36N: 14.45 h (+23.44 delta), 9.55 h (-23.44 delta), 12.0 h at equinox. Noon elevation `= 90 - |phi - delta|`: 77.4 / 54 / 30.6 deg [P].

Season effects checklist:
- Sun: use computed elevation/azimuth (section 8.1), so lighting differs per season for free.
- Foliage / grass tint via `MPC_Weather.SeasonTint` multiplied in landscape and foliage materials; autumn adds a slight yellow gain to trees only.
- Weather weights, event spawn rates and snow line (below).
- Winter: ground albedo up (SkyAtmosphere `GroundAlbedo` 0.4 default [E] -> 0.5 when snow cover is large), lower sun, longer shadows.
- Optional later: dry riverbed vs water level (FH5 does this) [SKIP for now].

Temperature model (for rain-vs-snow and HUD) [D]: `T(z, hour) = T_season_mean + 5*cos(2*pi*(hour-15)/24) - 18*a` where `a` = normalized terrain altitude (0 lowest road, 1 highest peak). Precip phase: `T < 1.5` snow, `T > 3.0` rain, linear mix between (this reproduces "rain turns to snow higher uphill").

Snow cover S (0..1): above the season's snow line the terrain/road materials show **persistent** snow with a fade band of 8% altitude; precipitation snow adds `dS/dt = +1/90 s` while it snows, melts at `-1/240 s` when T > 2 and sun is up. Below the line S only exists while snowing in cold hours.

---

## 5. Weather states, events and scheduling

### 5.1 States (enum `EWeatherState`) and base parameters [D]

`Cloud_GlobalCoverage`, `Cloud_GlobalDensity`, `Cloud_AlbedoColor`, `Storm_AlbedoColor`, `StormClouds`, `Storm_Lightning*`, `ManualLightningAnim`, `CloudWind`, `WindMultiplier`, `PhaseG`, `PhaseG2`, `PhaseBlend`, `MultiScatteringContribution/Occlusion/Eccentricity`, `AmbientOcclusion` are parameter names present in the engine cloud material `/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud` (found by scanning the .uasset strings [E]; confirm exact names/ranges in the editor before wiring). Create one `UMaterialInstanceDynamic` on it and drive these.

| State | Cloud cov. | Cloud dens. | Cloud layer bottom / height (km) | Direct sun scale* | Sky light scale | Rain 0..1 | Wind m/s | Lightning /min | Desat (saturation mult) | EV bias |
|---|---|---|---|---|---|---|---|---|---|---|
| Clear | 0.25 | 0.35 | 2.0 / 3.0 | 1.00 | 1.00 | 0 | 2 | 0 | 1.00 | 0 |
| Partly cloudy | 0.50 | 0.55 | 1.8 / 3.5 | 0.85 | 1.00 | 0 | 4 | 0 | 0.97 | 0 |
| Overcast | 0.80 | 0.70 | 1.2 / 4.0 | 0.45 | 0.90 | 0 | 5 | 0 | 0.88 | +0.3 |
| Light rain | 0.85 | 0.75 | 1.0 / 4.0 | 0.35 | 0.90 | 0.30 | 6 | 0 | 0.84 | +0.3 |
| Heavy rain | 0.92 | 0.90 | 0.8 / 5.0 | 0.22 | 0.85 | 0.75 | 9 | 0.5 | 0.80 | +0.5 |
| Thunderstorm | 1.00 | 1.00 | 0.7 / 8.0 | 0.15 | 0.80 | 1.00 | 14 | 4-8 | 0.78 | +0.6 |
| Fog (ground) | 0.65 | 0.60 | 0.6 / 2.0 | 0.30 | 1.10 | 0 | 1 | 0 | 0.80 | +0.4 |
| Dust storm (cell core) | 0.35 | 0.30 | 2.0 / 3.0 | 0.30 | 0.90 | 0 | 16 | 0 | 1.05 (orange) | +0.5 |
| Snow | 0.88 | 0.80 | 0.9 / 3.5 | 0.40 | 1.00 | 0 (snow 0.6) | 8 | 0 | 0.85 | +0.5 |
| Blizzard (mountain) | 1.00 | 0.90 | 0.6 / 3.0 | 0.20 | 1.00 | 0 (snow 1.0) | 18 | 0 | 0.80 | +0.7 |

\*"Direct sun scale" multiplies the Sun light intensity. If `bCastCloudShadows` is on and clouds are dense, the clouds already shade the ground; use only about the square root of the table value to avoid double dimming (e.g. Overcast 0.67) and check with the HDR visualization.

Cloud layer defaults [E, `VolumetricCloudComponent.cpp`]: `LayerBottomAltitude=5.0` km, `LayerHeight=10.0` km, `TracingStartMaxDistance=350` km, `TracingMaxDistance=50` km, `SkyLightCloudBottomOcclusion=0.5`, `ViewSampleCountScale=1.0`, `StopTracingTransmittanceThreshold=0.005`, `PlanetRadius=6360`. Lowering the layer to 0.7-2 km (table) gives clouds that read as close and dramatic from a car; keep `TracingMaxDistance` at about 40 km and raise `StopTracingTransmittanceThreshold` slightly (0.02) for cost. Setters are available at runtime: `SetLayerBottomAltitude`, `SetLayerHeight`, `SetMaterial` [E].

Drying states (FH5 "Post Rain") [S/D]: *Clear post rain* and *Cloudy post rain* are not selectable states; they are Clear/Cloudy with `Wetness > 0` and puddles present.

### 5.2 Wetness, puddles, dust, snow dynamics [D]

- Wetness `W` (0..1, road surface): rain gain `dW/dt = +Rain/45 s` (heavy rain wet in about 60 s, light rain in about 150 s). Loss `dW/dt = -(0.3 + 0.7*SunExposure)/300 s` with `SunExposure = saturate(sin(sunElev)) * (1 - cloudCoverage)`; at night drying uses 0.3 (so a wet night road stays wet ~5 min, a sunny noon road dries in ~5 min).
- Puddle amount `P` (0..1): rises when `Rain > 0.5`: `P -> W^2`, drains at `1/600 s`. Used by road/terrain materials (mask) and `GetPuddleDepth`.
- Dust `D` (0..1): rises to 1 inside a dust cell core, decays `1/180 s` outside. Material: lighter, desaturated sand tint on asphalt, slight grip loss (section 6.2).
- Snow cover `S`: section 4.
- All four live in `MPC_Weather`. Road material rule: albedo darkens by 0.55x at W=1 (multiply by `lerp(1,0.55,W)`), roughness `lerp(base, 0.12, saturate(W + P*1.0))`, normal intensity `lerp(1, 0.6, P)`, puddle mask from a tiling noise x vertex-painted lane-edge low spots, puddles set roughness 0.03 and add a depth-based normal flatten (plus Lumen reflections already on). Reduce metallic-like specular on dirt, keep rough.

### 5.3 Events ("weather cells") — localized, visible, growing storms [D]

Baseline weather is global and mild (Clear / Partly / Overcast). Strong weather arrives as **cells** that move with the wind, grow, peak, decay, and are visible from far away. At most **2 active cells**. Env params at the camera = baseline blended toward the cell's peak params by `influence = smoothstep(R, 0.55*R, dist) * envelope(t)`, with `envelope`: 25% grow, 50% plateau, 25% decay. Per-cell fields: type, center, radius R, velocity (from wind), lifetime, peak params (rain, fog density, cloud, lightning, dust).

| Cell | Allowed zones | Spawn rate per hour by season (Spr/Sum/Aut/Win) | Radius (m) | Speed (m/s) | Lifetime (min) | Peak look |
|---|---|---|---|---|---|---|
| Rain | any | 4 / 1 / 4 / 1 | 700-1400 | 4-8 | 4-8 | Heavy rain row; dark cloud base, rain curtain visible from afar |
| Thunderstorm | Coast, Valley | 1 / 3 / 2 / 0 | 600-1200 | 5-9 | 3-6 | Thunderstorm row; anvil cloud, lightning |
| Fog bank | Valley, Coast, Mountain | 2 / 0 / 2 / 2 (only when sun elev in [-6, +10] deg) | 900-1800 | 0.5 | 8-15 | Fog row; ground-hugging, thins above ~100 m |
| Dust storm | Dry Hills | 0.3 / 0.3 / 0.3 / 3 | 400-900 | 6-10 | 3-6 | Dust row; tall orange wall 150-300 m |
| Snow squall | Mountain above snow line | 0 / 0 / 0.5 / 3 | 500-1000 | 3-6 | 5-10 | Snow/blizzard row |

Baseline weights per season for the *global* state [D] (Clear / Partly / Overcast / Light rain / Heavy rain / Thunder / Fog / Dust / Snow):
Spring 25/25/15/18/8/3/6/0/0, Summer 45/25/6/4/3/13/2/2/0, Autumn 20/22/18/14/12/8/6/0/0, Winter 38/22/10/3/1/0/8/12/6. Min dwell 6-15 min for Clear/Partly, 4-10 for Overcast, 3-8 for rain; transitions ramp parameters over 45-90 s with smoothstep (sky changes are slow; only lightning and gusts are fast). Guarantee a non-Clear state at least once per 10 min (FH5 players complained about scarcity [C]).

Zone multipliers: Coast (thunder x2 in Summer, heavy rain x1.5 Autumn, sea fog x1.5 at dawn); Valley (fog x2 at dawn, rain x1.2 Spring); Dry Hills (dust x3 Winter, rain x0.4); Mountain (snow and overcast x2 Winter, cloud-in fog x1.5, thunder x0.8).

Distant storm readability: for the cloud, add a cell mask to the cloud material (world XY distance to `MPC_Weather.StormCell0/1`) that raises local coverage/density and darkens base; add a **rain curtain** (scrolling-streak mesh, translucent) at the cell edge, and on the minimap a colored disc. Check that Volume-domain cloud materials may read the MPC (should; verify).

---

## 6. Grip: surface x weather

### 6.1 Real-world anchors (source ranges, friction coefficient mu) [P]

| Surface | mu (peak) | Source note |
|---|---|---|
| Dry asphalt / concrete | 0.8-0.9 (0.75 sliding) | new tire; 0.9 at 0 km/h falls to 0.75 at 130 km/h |
| Wet asphalt | 0.5-0.7 (0.6 typical; sliding 0.45-0.6) | |
| Wet concrete | 0.6-0.8 | |
| Gravel, dry rolled | 0.6-0.7 | |
| Gravel, wet rolled | 0.3-0.5 | |
| Earth road dry / wet | 0.68 / 0.55 (sliding 0.65 / 0.40-0.50) | |
| Dry clay | 0.5-0.6 | |
| Loose sand | 0.3-0.4 | |
| Hard-packed snow | 0.2 (sliding 0.15) | |
| Ice | 0.1 (sliding 0.07) | |
| Mud, grass | not in sources | assume mud 0.3-0.4, wet grass 0.3-0.4 [D] |

Ratios to dry asphalt (0.9): wet asphalt 0.67 (range 0.55-0.80), earth 0.76/0.61, snow 0.22, ice 0.11, sand 0.33-0.44.

Rolling resistance (passenger car): concrete/asphalt 0.013-0.015, rolled gravel 0.02, unpaved 0.05, field 0.10-0.35, sand 0.30 [P].

### 6.2 Game values (relative to dry highway asphalt = 1.00), arcade compression [D]

`game = 1 - k*(1 - physicalRatio)` with `k ≈ 0.55` for rain, `0.7` for snow, `0.8` for ice, so cars stay controllable and match FH5's "rain is a grip debuff you can drive through" [C].

Condition columns: Dry (W=0), Damp (W≈0.35), Wet (W≈0.7, light rain), Soaked (W=1, heavy rain / storm), Snow-covered (S=1).

| Surface | Dry | Damp | Wet | Soaked | Snow-covered | Rolling-resistance mult (vs asphalt) |
|---|---|---|---|---|---|---|
| Asphalt, highway | 1.00 | 0.94 | 0.84 | 0.76 | 0.50 | 1.0 |
| Asphalt, rural / worn | 0.95 | 0.88 | 0.78 | 0.70 | 0.48 | 1.1 |
| Cobble / settlement | 0.90 | 0.80 | 0.68 | 0.62 | 0.45 | 1.3 |
| Dirt | 0.78 | 0.72 | 0.64 | 0.50 (mud forms) | 0.52 | 3.5 |
| Gravel | 0.80 | 0.74 | 0.66 | 0.58 | 0.52 | 2.0 |
| Grass / off-road | 0.62 | 0.52 | 0.44 | 0.38 | 0.45 | 7 |
| Sand (loose) | 0.55 | 0.62 | 0.66 | 0.58 | n/a | 10 (arcade cap; real 23) |
| Mud patch (fixed) | 0.40 | 0.40 | 0.40 | 0.38 | 0.40 | 8 |
| Ice patch (black ice, mountain nights in Winter) | 0.30 | 0.30 | 0.30 | 0.30 | 0.30 | 1.0 |

Blend: `grip = lerp over W knots {0, 0.35, 0.7, 1.0} -> {Dry, Damp, Wet, Soaked}`, then `grip = lerp(grip, SnowCovered, S)`. Dust on tarmac: `grip *= (1 - 0.06*D)`. Cold tires / temperature: none (keep simple).

Modifiers:
- Speed: `grip *= 1 - 0.17*saturate(v / 36 m/s)` (dry: 0.9 -> 0.75 at 130 km/h [P]).
- Puddle patches (local, from `GetPuddleDepth`, depth 0..1): `grip *= 1 - 0.55*depth*smoothstep(40, 110, v_kmh)`, and add drag `a = 0.8 m/s^2 * depth * (v/27.8)` (hydroplaning/aquaplaning feel). Clamp final multiplier to >= 0.25 so no softlock.
- Final per-wheel multiplier is smoothed (`FInterpTo`, 4/s) so surface transitions do not snap.

### 6.3 Tire compounds (relative to Street = 1.00; community-informed) [C/D]

| Compound | Dry asphalt | Wet asphalt | Dirt/gravel | Snow | Note |
|---|---|---|---|---|---|
| Street (stock) | 1.00 | 1.00 | 0.90 | 0.95 | predictable, safe in puddles |
| Sport | 1.06 | 0.98 | 0.85 | 0.92 | |
| Semi-slick / race | 1.14 | 0.88 | 0.78 | 0.85 | biggest wet penalty |
| Rally | 0.94 | 1.02 | 1.12 | 1.10 | best loose surface, a bit slidey on tarmac |
| Off-road | 0.85 | 0.95 | 1.18 | 1.15 | |

Applied as `Grip_total = CompoundMult[cond] * SurfaceWeatherGrip`. Keep the car's own per-surface grip curve (prompt: data-driven tire grip per surface) and use the table above only as a multiplier on it.

### 6.4 UE integration [E]

- Chaos wheel force limit (UE 5.8 `WheelSystem.cpp:84`): `AvailableGrip = ForceIntoSurface * SurfaceFriction * FrictionMultiplier`.
- `SurfaceFriction` is set **every tick from the hit `UPhysicalMaterial::Friction`** (`ChaosWheeledVehicleMovementComponent.cpp:519`); so one `UPhysicalMaterial` per surface with Friction = the Dry column (asphalt 1.0) works as the base. `FrictionMultiplier` comes from `UChaosVehicleWheel::FrictionForceMultiplier` (default **2.0**; `FSimpleWheelConfig` also defaults to 2.0) and can be changed at runtime with the BlueprintCallable `UChaosWheeledVehicleMovementComponent::SetWheelFrictionMultiplier(int WheelIndex, float Friction)`.
- Therefore: store `BaseFrictionMult` per wheel, and each frame set `SetWheelFrictionMultiplier(i, BaseFrictionMult * WeatherGrip(surfaceAtWheel))`. Never accumulate multiplicatively onto the current value. Other tuning knobs on the wheel: `SideSlipModifier` (lateral grip loss during skid), `SlipThreshold`, `SkidThreshold`, `LateralSlipGraph` — in wet, lower `SideSlipModifier` by about 10% and raise `SlipThreshold` slightly so the car breaks away earlier but more progressively.
- If the project uses a custom arcade tire model instead of Chaos wheels (prompt mentions data-driven tire curves), expose the same `GetGripMultiplier` from `UWeatherSubsystem` and multiply the lateral and longitudinal peak force limits.
- Wheel surface detection: line trace returns `PhysMaterial` per wheel; landscape layers need physical materials per layer (`LandscapeLayerInfoObject->PhysMaterial`); spline road meshes get PM via material. Water/puddle grip is applied by position query, not by physical material.

AI traffic: scale target speed by 0.9 (wet), 0.8 (heavy rain), 0.7 (fog < 300 m or blizzard); lights on per section 10.4.

---

## 7. Visibility and fog

### 7.1 Fog math from UE 5.8 source [E]

- `SceneCore.cpp:404-405`: `Density = FogDensity / 1000` and `HeightFalloff = FogHeightFalloff / 1000` per **centimeter**.
- `FogRendering.cpp:403`: collapsed observer-height density `= Density * 2^(-HeightFalloff * (CameraZ - FogActorZ))` (base-2 exponent).
- Transmittance over a path of L cm at roughly constant density d: `T = 2^(-d*L)`. Meteorological visibility is where contrast drops to 2%, `T = 0.02`, so `d*L = log2(50) = 5.64`.
- Result for a horizontal view at height `z` above the fog actor: `V_m ≈ 56.4 / FogDensity_eff`, with `FogDensity_eff = FogDensity * 2^(-0.001*FogHeightFalloff*(z_cm))`. At the default `FogDensity=0.02` this is 2.8 km (`T(1 km) = 0.25`).
- Inverse: `FogDensity = 56.4 / V_m` at the reference height. The density at height z falls by half every `1000/(FogHeightFalloff)` cm: falloff 0.2 (default) halves every 50 m; 0.05 every 200 m; 0.45 every 22 m.
- Defaults [E]: `FogDensity=0.02`, `FogHeightFalloff=0.2`, `FogMaxOpacity=1.0`, `StartDistance=0`, `FogCutoffDistance=0`, `VolumetricFogDistance=6000` (cm), `VolumetricFogScatteringDistribution=0.2`, `DirectionalInscatteringExponent=4`, `DirectionalInscatteringStartDistance=10000`, **`FogInscatteringLuminance` default black**. With a SkyAtmosphere in the level the fog color comes from the sky (`SkyAtmosphereAmbientContributionColorScale`, SkyAtmosphere `HeightFogContribution=1.0` [E]); do not set a fog color except for dust/snow.
- Runtime setters [E]: `SetFogDensity`, `SetFogHeightFalloff`, `SetFogMaxOpacity`, `SetSecondFogDensity/HeightOffset/HeightFalloff`, `SetStartDistance`, `SetFogCutoffDistance`, `SetVolumetricFog`, `SetVolumetricFogDistance/ScatteringDistribution/Albedo(FColor)/ExtinctionScale/Emissive`, `SetFogInscatteringColor`, `SetDirectionalInscatteringColor/Exponent/StartDistance`, `SetSkyAtmosphereAmbientContributionColorScale`. Density is clamped to 0..10 and falloff to 0..2 in `ValidateFogParams` [E].

### 7.2 Per-state fog table [D]

(`V` = visibility at the reference height at the fog actor, camera 0-5 m above it; place the ExponentialHeightFog actor at the lowest road altitude.)

| State | V (m) | FogDensity (=56.4/V) | HeightFalloff | FogMaxOpacity | Volumetric fog | Vol. albedo (sRGB) | Scatter distribution | Mie scale mult | Aerial persp. view dist scale |
|---|---|---|---|---|---|---|---|---|---|
| Clear | 20000 | 0.0028 | 0.12 | 0.90 | off (on at golden hour for shafts, optional) | white | 0.2 | 1.0 | 1.6 |
| Partly cloudy | 14000 | 0.0040 | 0.12 | 0.90 | off | white | 0.2 | 1.3 | 1.6 |
| Overcast | 9000 | 0.0063 | 0.10 | 0.92 | off | white | 0.2 | 1.8 | 1.5 |
| Light rain | 4000 | 0.014 | 0.08 | 0.95 | on, dist 8000 | (0.85,0.88,0.92) | 0.3 | 3.0 | 1.5 |
| Heavy rain | 1200 | 0.047 | 0.06 | 0.97 | on, dist 12000 | (0.70,0.74,0.78) | 0.35 | 4.5 | 1.4 |
| Thunderstorm | 700 | 0.081 | 0.05 | 0.98 | on, dist 12000 | (0.60,0.64,0.70) | 0.35 | 5.0 | 1.3 |
| Fog (ground) | 120 | 0.47 | 0.45 (thins above ~100 m, mountain passes rise above it) | 1.0 | on, dist 15000 | (0.90,0.92,0.95) | 0.45 | 8.0 | 1.0 |
| Dust storm (core) | 45 | 1.25 | 0.03 (tall wall) | 1.0 | on, dist 15000 | (0.78,0.62,0.42) dust slightly darker than haze | 0.30 | 6.0 | 1.0 |
| Dust (outside, hazy) | 3000 | 0.019 | 0.06 | 0.95 | off | n/a | 0.2 | 2.5 | 1.5 |
| Snow (light) | 1500 | 0.038 | 0.08 | 0.95 | on | (0.92,0.95,1.0) | 0.3 | 2.0 | 1.5 |
| Blizzard | 80 | 0.70 | 0.05 | 1.0 | on | (0.95,0.97,1.0) | 0.35 | 3.0 | 1.0 |

Notes:
- `FogDensity` for tall dust wall at z=100 m above the fog actor with falloff 0.03: factor `2^(-0.00003*10000)=0.81`, still V ~ 55 m; good.
- Valley fog (dawn): use the **second fog layer** (`SetSecondFogDensity ~0.5`, `SetSecondFogHeightFalloff ~1.0`, `SetSecondFogHeightOffset` = valley floor) so only the lowest ~20 m is dense; `Local Fog Volume` actors (sphere, `SetRadialFogExtinction`, `SetHeightFogExtinction`, `SetFogAlbedo`, phase g default 0.2) for dust-wall cores and fog banks over specific valleys [E, UE docs: no non-uniform scale, no shadows from local fog, cost scales with screen area and overlaps].
- `Mie scale mult`: multiply `SkyAtmosphere.MieScatteringScale` (default 0.003996 [E]); keep `MieAnisotropy` 0.8 default for clear days and 0.65 for rain/fog (softer halo). `AerialPespectiveViewDistanceScale` (typo is in the engine property name [E]) > 1 gives the pronounced blue-haze depth FH5 has on mountains.
- Same `V` feeds gameplay: headlights (V < 500 m), AI target speed, HUD low-visibility warning (V < 300 m), horn sound reverb, and the console debug overlay.

---

## 8. Time of day

### 8.1 Solar math (own implementation) [P]

```
delta = 23.44 deg * sin(2*pi*(N - 81)/365)            // N = day of year
H     = 15 deg * (solarHour - 12)                      // hour angle
sin(el) = sin(phi) sin(delta) + cos(phi) cos(delta) cos(H)
A_south_west = atan2( sin(H), cos(H) sin(phi) - tan(delta) cos(phi) )
az_from_north_clockwise = A_south_west + 180 deg
```

World convention: +X = North, +Y = East, +Z up (left-handed UE, so North->East is a clockwise turn viewed from above). Sun direction `s = (cos(el)cos(az), cos(el)sin(az), sin(el))`; the Directional Light shines along `-s`:
`Sun->SetWorldRotation((-s).Rotation())`. Apply an optional `NorthOffsetDeg` yaw so roads face the sun nicely at golden hour. Enable `bAtmosphereSunLight` with `AtmosphereSunLightIndex = 0` on the sun, `1` on the moon [E/UE docs]. Moon (cheap): `MoonAz = SunAz + 160 deg`, `MoonEl = clamp(-0.8*SunEl + 15, -90, 80)`; moon visible only if `MoonEl > 0`.

### 8.2 Time scale and night compression [D]

Base: 1 game hour = 2 real minutes at 1x. Speed multiplier by **sun elevation** (so it works in every season):

| Sun elevation | Time speed | Reason |
|---|---|---|
| e >= -6 deg | 1.0x | day, golden hour, civil twilight shown in full |
| -14 deg to -6 deg | lerp 1.0x -> 4.0x | smooth entry to dark |
| e < -14 deg | 4.0x | skip the dead dark hours (FH5's night is only ~10% of its cycle [C]) |

At 36N equinox this gives a full game day of about 32 real minutes with roughly 4-5 min of true night (derived estimate). `daylength` console command rescales the base. Photo-mode / console presets (FH5's 9 slots) map to elevations: Dawn -9 deg (rising), Sunrise 0 (rising), Morning +20 (rising), Early Afternoon +45 (descending), Late Afternoon +20 (descending), Sunset 0 (descending), Evening -6 deg (descending), Night -30 deg or solar midnight; Default = current. Convert to a solar hour by solving the equation above for the active season.

### 8.3 Keyframe table (keyed by sun elevation, interpolate in elevation; rising and falling use the same table) [P/D]

Twilight definitions [P]: civil -0 to -6 deg, nautical -6 to -12, astronomical -12 to -18; illumination from the sky is near zero at -18. Photographic golden hour is roughly the hour after sunrise / before sunset (sun about 10-12 deg up at mid-latitudes; the table uses +6 to 0 deg for the deepest gold); color temperature of the apparent sun ~2000 K just after sunrise/before sunset, ~3500 K golden hour, ~5500 K midday; horizon daylight ~5000 K, overcast sky ~6500 K, clear blue sky 15000+ K.

Illuminance anchors [P]: direct sun 32,000-100,000 lux, full daylight not direct 10,000-25,000, overcast 1,000, very dark overcast 100, sun at horizon on a clear day ~400, dark limit of civil twilight 3.4, full moon 0.05-0.3, moonless clear night 0.002.

**Important:** with `SkyAtmosphere` the sun is already reddened and dimmed by atmospheric transmittance according to elevation. So set the Directional Light to a **constant** physical sun (about 110,000-120,000 lux; Epic says a sun at zenith is about 120,000 lux and a white diffuse surface in perpendicular sun about 150,000 lux with sky about 20%) and a **near-neutral** `Temperature`. Setting both a warm temperature and relying on the atmosphere double-warms sunsets. The "Apparent CCT" column below is the look the atmosphere should produce (use it to judge), the "Light.Temperature" column is the only value to set.

| Sun elev | Phase name | Apparent sun CCT (result) | Sun intensity (lux) | Sun Light.Temperature (K) | Target ground illuminance (lux, interpolated) | SkyLight intensity scale | Auto-exposure EV100 min..max | Fog/haze mult (Mie) | Fog/sky mood color |
|---|---|---|---|---|---|---|---|---|---|
| +70 (summer noon) | High noon | 5500-5900 | 120000 | 6500 | ~100000 | 1.00 | 14.0..15.0 | 1.0 | pale blue `#BFD4F0` |
| +45 | Late morning / early afternoon | 5600 | 120000 | 6500 | ~80000 | 1.00 | 13.5..14.8 | 1.0 | `#C2D6F0` |
| +30 | Mid morning / afternoon | 5200 | 120000 | 6400 | ~55000 | 1.00 | 13.0..14.5 | 1.05 | `#C9D7EC` |
| +15 | Late afternoon / early morning | 4300 | 120000 | 6200 | ~25000 | 1.00 | 12.0..14.0 | 1.2 | `#E3D6C3` |
| +6 | Golden hour (upper) | 3500 | 120000 | 6000 | ~6000 | 1.00 | 11.0..13.0 | 1.4 | `#F0D2A6` |
| +2 | Golden hour (low) | 2500 | 120000 | 5800 | ~1500 | 0.90 | 10.0..12.0 | 1.8 | `#F2B27A` |
| 0 | Sunrise/sunset (disk on horizon) | 2000 | 120000 * smoothstep(-2,2,e) | 5800 | ~400 | 0.80 | 9.0..11.5 | 2.2 | `#E8996A` |
| -3 | Civil twilight (afterglow) | no direct sun | 0 | n/a | ~40 | 0.60 | 7.0..10.0 | 2.0 | purple-pink horizon `#A98AA8` |
| -6 | End of civil twilight / blue hour | sky only (~15000+) | 0 | n/a | ~3.4 | 0.45 | 5.5..9.0 | 1.6 | blue `#4C5E8F` |
| -12 | Nautical twilight | sky only | 0 (moon) | n/a | ~0.1 | 0.20 | 2.0..6.0 | 1.2 | deep blue `#1E2A4A` |
| -18 and below | Night | moonlight 7500 K | moon 0.5-1.0 (physical 0.26 at zenith, boosted for readability) | 7500 | ~0.3 with moon | 0.08 | -1.5..1.5 | 1.0 | `#0B1224` |

EV100 columns are **starting brackets**, not facts: Magnopus puts bright midday at about EV 13 for a 100,000 lux scene, sunny-16 rule says about 15, a sunset photo measured 10.9. Tune each row with the viewport HDR (Eye Adaptation) visualization. Rule: set `Min EV100` and `Max EV100` close together (about 1.5 EV apart) so exposure does not hunt, and make night brackets narrow and **not below about -2**: a very low Min EV100 makes UE brighten a dark scene into fake day (reported pitfall).

Moon: second Directional Light, `AtmosphereSunLightIndex = 1`, `Temperature 7500`, intensity 0.5-1.0 lux (note Epic: moon at zenith about 0.26 lux, 0.568 deg diameter; sun disk 0.545 deg) [E docs]. Second light has no multi-scattering contribution to the sky [E docs], so also keep SkyLight night scale ~0.08 and add a faint blue `SetLowerHemisphereColor`. Stars: SkyAtmosphere draws no stars; use `/Engine/EngineSky/SM_SkySphere` with `/Engine/EngineSky/T_Sky_Stars` in an unlit sky-flag material, opacity `saturate((-e - 6)/8)` [E asset names].

Weather modifies the table: multiply Mie scale by the state's haze mult, EV bias per state (section 5.1), SkyLight scale by state, saturation by state. At golden hour under overcast, drop the "disk on horizon" warmth (the cloud material's `Cloud_AlbedoColor` carries the warmth instead).

### 8.4 Dusk to dawn lights

- Vehicle lights: **on** when sun elevation < +4 deg (hysteresis off at +8), or `V < 500 m`, or heavy rain / thunderstorm / fog / dust, or inside a tunnel volume; fade 0.3 s. AI cars same. FH5 headlight behavior is not documented (tunnel auto-on was reported in FH3 [C]).
- Street lights only in settlements, junctions and tunnels (rural roads unlit): on at elevation < +3 deg (off > +7), ramp 20 s, color 3000 K. Cap real dynamic lights to the ~8 nearest to the player; the rest are emissive meshes with a fake light-pool decal.
- Lights shape the world at night, so night must feel safe but atmospheric: reduce scene darkness with moon 0.5-1 lux and exposure min not below -1.5.

### 8.5 Exposure behavior to avoid player complaints

- Auto-exposure metering mode: histogram (default); `Low/High percent` 70-80 / 85-95; adaptation Speed Up 3, Speed Down 1 (documented behavior: up = dark to bright) — make night-to-day slightly slower.
- Tunnel: a local post-process volume per tunnel mouth (blend radius ~30 m) with EV100 bracket ~7..10 so day to tunnel to day is smooth and the interior is lit by the headlights.
- Use local exposure (already highlight/shadow scale 0.8 in config) instead of exposure compensation to control contrast; avoid clamping min = max = 1 and using compensation to brighten (not physically scaled).

---

## 9. Sky component recipe (UE 5.8) [E]

SkyAtmosphere (defaults: bottom radius earth 6360 km, atmosphere height ~60 km, `GroundAlbedo` 170/255 = 0.4 linear, `RayleighExponentialDistribution` 8 km, `MieScatteringScale` 0.003996, `MieAbsorptionScale` 0.000444, `MieAnisotropy` 0.8, `MieExponentialDistribution` 1.2 km, `MultiScatteringFactor` 1.0, `AerialPespectiveViewDistanceScale` 1.0, `HeightFogContribution` 1.0):
- Transform mode: planet top at component transform, keep the actor at the lowest world Z.
- Drive per frame: `SetMieScatteringScale(0.004 * hazeMult)`, `SetMieAnisotropy`, `SetAerialPespectiveViewDistanceScale`, `SetGroundAlbedo`, `SetSkyLuminanceFactor` (slightly darker/desaturated in storms), `SetHeightFogContribution` (reduce to 0.5 inside fog cores so atmosphere does not double the fog tint).
- Keep multi-scattering on (docs: should be 1 for physically based sky lighting).

VolumetricCloud: `Material` = MID of `m_SimpleVolumetricCloud` (`bUsedWithVolumetricCloud`), `SetLayerBottomAltitude/Height` from section 5.1, `SetTracingMaxDistance(40)`, `SetViewSampleCountScale(0.8-1.0)`, `ReflectionViewSampleCountScale 0.25-0.5` (Lumen reflections see clouds), `SetSkyLightCloudBottomOcclusion(0.5)`. Epic notes: single multi-scattering octave for games, Beer shadow maps cheaper than ray-marched cloud shadows, gray-scale material cheaper. Console: `r.VolumetricRenderTarget.Mode=0` recommended for fast-paced gameplay (docs), raise Mode only for photo mode. Cloud shadows on sun: `bCastCloudShadows`, `CloudShadowStrength`, `CloudShadowExtent` (km, smaller = sharper) about 20-30, `CloudShadowMapResolutionScale` 0.5-1 [E].

Sun DirectionalLight: Mobility Movable, `bAtmosphereSunLight=true`, `AtmosphereSunLightIndex=0`, `bCastShadowsOnClouds`, `bCastShadowsOnAtmosphere` (shafts), `LightSourceAngle` 0.5357 default is fine, VSM on; `DynamicShadowDistanceMovableLight` ~ 20000 cm for non-VSM cascade fallback. `SetIntensity`, `SetTemperature`/`bUseTemperature`.

SkyLight: Movable, `bRealTimeCapture = true` (Epic: time-sliced capture over ~9 frames, so a very fast time warp will lag slightly — acceptable), `SourceType` captured scene, `bLowerHemisphereIsBlack=false` with `SetLowerHemisphereColor` about (0.14,0.12,0.10) day (ground bounce), `SetIntensity` from table. Enable `bCloudAmbientOcclusion` to darken ambient under dense storm decks.

ExponentialHeightFog: values from section 7.2, plus `SetVolumetricFog(true)` only for rain/fog/dust states (cost).

Post process (unbound, one component): `AutoExposureMethod=Histogram`, `AutoExposureMinBrightness/MaxBrightness` = the EV100 bracket (extended range), `AutoExposureBias` = state EV bias, `ColorSaturation`, `ColorContrast`, `WhiteTemp`.

---

## 10. Presentation

### 10.1 Color grading (FH-like, interpretation) [D]

Overall: punchy, saturated, clean highlights, slightly warm sun, cool shadows; atmosphere does the depth.

| Condition | Saturation | Contrast | WhiteTemp (K) | Other |
|---|---|---|---|---|
| Clear day | 1.10 | 1.04 | 6500 | bloom 0.6, vignette 0.25 |
| Golden hour | 1.15 | 1.06 | 5900 | bloom 0.9, slight teal shadow gain |
| Overcast / rain | 0.82 | 1.02 | 7000 | cooler, flatter, EV +0.3 |
| Fog | 0.78 | 0.92 | 6800 | lifted shadows (+0.01 offset) |
| Dust storm | 1.05 | 1.00 | 4800 | gain R 1.05, B 0.85, orange cast |
| Snow | 0.85 | 1.00 | 7500 | EV +0.3..+0.7 |
| Night | 0.90 | 1.08 | 7500 | cool blue shadows, bloom 1.0 on lights, vignette 0.35 |

Tonemapper is the project's default; do not fight it with film curve changes until the above is done. Blend all per-frame (no popping): keyframe by elevation + weather weights.

### 10.2 Rain / snow / dust VFX [D]

- Rain: camera-attached GPU Niagara, box about 30 x 30 x 20 m, spawn scaled by `Rain`, streak length scaled by car speed, slant `atan(wind/7)` clamped to 25 deg; splash/ripples via material (puddle ripples) not particles; wheel spray Niagara scaled by speed x wetness (also on dirt: dust; on snow: powder).
- Snow: same rig, slower fall (1-2 m/s), larger flakes; blizzard adds wind-driven streaks and fog density.
- Dust storm: wall = stack of large soft sprite sheets (Niagara) + Local Fog Volume core + dust tint fog; visible from 1.5-2 km as an orange wall; inside, particles near camera; lighting via volumetric fog scattering. Trail dust behind cars on dirt/sand scaled by speed.
- Lightning: random interval `Uniform(6, 25 s) / intensity`; flash = 2-4 sub-flashes 40-120 ms; SkyLight intensity x3 for 0.15 s, a high white `RectLight` or point light 10 km class not needed (use exposure-visible sky flash), cloud material `ManualLightningAnim`; thunder audio delay `distance_m / 343` s.
- Car-visible water: camera droplet overlay in cockpit/bumper cams only; windshield wipers if cabin view exists.

### 10.3 Wind

`WindDir`, `WindSpeed` in `MPC_Weather` drive cloud wind (`CloudWind` material param), foliage sway amplitude, rain slant, dust sprites; cells advect with it. Gale = Heavy rain with wind 14+ m/s.

### 10.4 Audio hooks

Rain loop intensity by `Rain` and surface; wet tire hiss by wheel-surface wetness; thunder with delay; wind loop by speed + WindSpeed. (Brief; separate audio topic.)

### 10.5 HUD / communication (our design, since FH5 has none confirmed)

- Minimap cluster: icon of local weather state, time `HH:MM`, season label ("Autumn - Storm Season"), optional temperature C.
- Road-condition indicator by `GripMultiplier`: >= 0.9 hidden; 0.7-0.9 amber droplet "WET ROAD"; < 0.7 red "SLIPPERY"; snow/ice icons; `Visibility < 300 m` fog icon "LOW VISIBILITY" and auto-lights.
- Minimap overlays: weather cells as colored discs (rain blue, thunder purple, dust orange, snow white, fog grey) with direction arrows; toast when a storm is within 600 m ("Storm ahead - 600 m").
- Pause/map: season banner + 3-step forecast from the deterministic schedule; photo mode/console lists use FH5-style 9 time slots and 10-state weather list.
- Diegetic first: storm walls visible from far, wet reflections, wipers/droplets, headlight beams in fog.

---

## 11. Pitfalls checklist

1. SkyAtmosphere requires the sun Directional Light to have `bAtmosphereSunLight` and the right index; moon is index 1 without multi-scattering. Without it the sky is black.
2. Double warming: constant sun temperature (~6500 K) + SkyAtmosphere, not a warm temperature too.
3. `ExtendDefaultLuminanceRange` is already True in `DefaultEngine.ini`: EV100 brackets in this doc are valid for that mode; switching later breaks all exposure settings.
4. Auto exposure at night with a very low Min EV100 brightens the scene to fake day; keep night brackets narrow and not below about -2.
5. SkyLight real-time capture needs a Movable (or Stationary) SkyLight and is time-sliced; set `SetCaptureIsDirty` after big sky changes (e.g. instant `time` command).
6. `Density` and `FogHeightFalloff` in the UI are 1000x larger than the engine values; visibility math is in section 7.1. FogMaxOpacity < 1 keeps skyline readable in clear weather.
7. Local Fog Volumes: no shadows, no non-uniform scale, overlap cost; keep at most 2 active cells x 1 volume each.
8. Cloud cost: lowering the layer and increasing coverage raises tracing cost; use `r.VolumetricRenderTarget.Mode=0` for driving and keep reflection sample scale low; clouds are not supported on mobile (irrelevant here).
9. Chaos friction: `SurfaceFriction` is overwritten from the physical material every tick; apply the weather multiplier through `SetWheelFrictionMultiplier` (store base). Default `UPhysicalMaterial` friction differs from the 1.0 asphalt assumption; set explicitly.
10. Landscape layers need physical materials per layer or all dirt/grass behaves like the default.
11. Puddle visuals and puddle physics must come from the same data (spatial hash of puddle centers); do not duplicate noise in material and C++.
12. Cloud material parameter names come from a binary scan; verify in the editor and wrap lookups in `if (Param exists)` style helpers.
13. Weather transitions must be time-based, not framerate-based; ramp 45-90 s; lightning excepted.
14. Time warp through dusk is fast; SkyLight capture lag can show in tunnels/valleys; clamp the warp to 1x when a photo-mode or cinematic is active.
15. Do not let weather lock the player in unplayable visibility (< 40 m): clamp min visibility to 40 m, always show road edge line brightness.
16. Rain scarcity in FH5 was a community complaint [C]: schedule deliberately.

## 12. Test checklist

- `time 6/12/18/21/0` in each season: sun elevation within +-1 deg of table, no black sky, no overexposure at noon (check HDR visualization).
- `weather <state>` for each state: fog distance matches V (place a marker at V and 2V; marker at V should read ~2% contrast).
- Drive 100 km/h on asphalt, then trigger Heavy rain: braking distance 100->0 should increase by about 1/0.76 ~ 1.3x (check against telemetry in `DEVELOPMENT.md` per prompt).
- Drive across Mountain zone in Winter: rain becomes snow with altitude; grip falls toward 0.50 on snow-covered asphalt.
- Dust cell: visibility inside ~45 m, visible orange wall from >= 1.5 km, fog and particles consistent; headlights on.
- Day/night full cycle recorded: no popping at elevation key boundaries; street lights toggle with hysteresis.

---

## 13. Sources actually used

FH5 (official or press):
- https://news.xbox.com/en-us/2021/07/26/exploring-the-biomes-and-seasons-of-forza-horizon-5/
- https://forza.net/news/exploring-forza-horizon-5-biomes-and-seasons
- https://forza.net/news/forza-horizon-5-road-to-mexico-june-update
- https://forza.net/news/forza-horizon-5-road-to-mexico-september-update
- https://forza.net/news/forza-horizon-5-explore-the-horizon (photo mode time/weather lists)
- https://forza.net/news/forza-photo-guide
- https://forza.net/news/forza-horizon-5-midnights
- https://news.xbox.com/en-us/2023/03/29/forza-horizon-5-rally-adventure-out-now/amp/
- https://www.videogameschronicle.com/news/forza-horizon-5s-art-team-explains-how-it-got-the-skies-to-look-so-realistic
- https://gamingbolt.com/forza-horizon-5-weather-conditions-detailed-eliminator-and-super-7-return
- https://www.gamepressure.com/S013-amp.asp?ID=13564
- https://en.wikipedia.org/wiki/Forza_Horizon_5
- https://traxion.gg/seasonal-conditions-and-unique-areas-explained-in-forza-horizon-5/
- https://racinggames.gg/forza/forza-horizon-5-complete-guide-to-scenery-and-seasons/
- https://www.gfinityesports.com/article/change-time-of-day-night
- https://www.analogstickgaming.com/game-reviews/2021/11/22/forza-horizon-5
- https://steamcommunity.com/app/1551360/discussions/0/3193611744850409699//1000 (community, tire advice)
- Search-result snippets only (not fetched): gfinityesports seasons-change page, racinggames.gg how-to-change-seasons, stevivor tourist-difficulty weather, PC Gamer "Seasons return" article, forums.forza.net rain/puddle/grip threads, gtplanet patch summary, primagames photo mode.

Unreal Engine:
- https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-atmosphere-component-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/exponential-height-fog-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/local-fog-volumes-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/auto-exposure-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/using-physical-lighting-units-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/geographically-accurate-sun-positioning-tool-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/sun-and-sky-actor-in-unreal-engine
- https://www.magnopus.com/blog/lighting-in-unreal-with-photography-principles
- Local UE 5.8 install (read-only): `Engine/Source/Runtime/Engine/Classes/Components/{SkyAtmosphere,VolumetricCloud,ExponentialHeightFog,SkyLight,DirectionalLight,LocalFogVolume}Component.h` and matching `.cpp`; `Engine/Source/Runtime/Renderer/Private/{SceneCore,FogRendering}.cpp`; `Engine/Plugins/Experimental/ChaosVehiclesPlugin/Source/ChaosVehicles/{Public,Private}/ChaosWheeledVehicleMovementComponent.*`, `ChaosVehicleWheel.*`; `Engine/Source/Runtime/Experimental/ChaosVehicles/ChaosVehiclesCore/{Public,Private}/WheelSystem.*`; `Engine/Plugins/Runtime/SunPosition/Source/SunPosition/Public/SunPosition.h`; `Engine/Content/EngineSky/**`.

Physics / photometry:
- https://www.engineeringtoolbox.com/amp/tractive-effort-d_1783.html (traction coefficients, speed dependence)
- https://hpwizard.com/tire-friction-coefficient.html (peak vs sliding, rolling resistance)
- https://en.wikipedia.org/wiki/Lux
- https://en.wikipedia.org/wiki/Color_temperature
- https://en.wikipedia.org/wiki/Golden_hour_(photography)
- https://en.wikipedia.org/wiki/Twilight
