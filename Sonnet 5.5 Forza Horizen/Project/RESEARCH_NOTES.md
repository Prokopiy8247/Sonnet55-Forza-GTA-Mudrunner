# RESEARCH_NOTES.md - Roamline: Open Roads

## 1. Header

**Purpose.** Research record and decision log for *Roamline: Open Roads*, an ORIGINAL open-world arcade-sim racing game built in Unreal Engine 5.8.2 with Blender-authored cars. Forza Horizon 5 (FH5) is used only as a mechanics, structure and feature-scope reference. No FH5 map, name, logo, model, texture, audio, UI artwork or code is used. This file holds (2) the FH5 feature inventory with an ADOPT / ADAPT / SKIP verdict per feature, (3) the Unreal Engine 5.8 technical findings with verdicts, (4) source URLs, (5) the ranked feature list the project commits to, with the naming and branding rules for player-visible text (5.2), and (6) open risks.

**Date:** 2026-10-16. **Target:** 4 x 4 km world, 40-60 km of road, one scenic loop of 20 km or more, 10 original cars, civilian traffic, weather and day/night, road activities.

**Web tools.** WebSearch and WebFetch were both available and were used by eight research agents: five on FH5 design (world, weather and time, activities, cars and assists, traffic/HUD/photo) and three on the engine (world technology, vehicle and gameplay framework, automation and asset pipeline). Several publisher and forum pages (Forza Support, Forza forums, Windows Central, GamesRadar, TechRaptor, Prima, Twinfinite, Digital Trends) returned 403, redirects or truncated bodies, so some FH5 details rest on search snippets. The engine side was also checked against the LOCAL install (headers, .cpp, .ini, .uplugin files, the generated Python stub, and the Blender 5.2 FBX add-on). Nothing was compiled or launched during research.

**Evidence quality (read this before trusting a number).**

- FH5 publishes almost no numbers on traffic, minimap geometry, GPS colour, HUD timings, skill-chain math, drift scoring, grip, or day length. Every such value below is a **design value** chosen by this project, calibrated against fan data ratios.
- Fan guides disagree with each other (bonus board counts 200/250/255, barn finds 14 vs 15, skill-chain cap x5 vs x8, driving-line colours, tire pressure advice). Mechanics are trusted; counts are not.
- Engine facts marked "local" were read from the 5.8.2 source on disk and are authoritative over blog posts. Where blogs contradicted source (Pacejka tires in Chaos, a MassTraffic plugin, 5.7 changes), the source wins.
- Review pass on 2026-10-16: every URL in section 4 was requested again. All of them resolve to real pages whose titles match their topic (a few sites block scripted clients, so those were confirmed by a second fetch); none was invented. Three pages describe other titles and are labelled as such in section 4 (a Forza Motorsport 7 assist article, a Forza Horizon 3 class article, a Forza Horizon 6 tuning wiki). Key FH5 facts were re-read at the source: the 11 biome names, snow only on the volcano, fast-travel fee 10,000 with 200 off per board, bonus-board tiers 1k/3k/5k, 14 barn finds, 9 time and 10 weather photo-mode slots, driving-line modes and colours.

**Detailed technical notes** (exact API names, formulas, code skeletons) live in `Docs/Tech/`: `FH5_world.md`, `FH5_weather_time.md`, `FH5_activities.md`, `FH5_cars_assists.md`, `FH5_traffic_hud_photo.md`, `UE58_world.md`, `UE58_vehicle_gameplay.md`, `UE58_automation_pipeline.md`.

---

## 2. Feature inventory of Forza Horizon 5 as understood

Verdicts: **ADOPT** = build essentially as FH5 does it. **ADAPT** = keep the idea, change the form or scale. **SKIP** = out of scope.

### 2.1 World structure and biomes

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Fictionalised Mexico map | One large map, about 1.5x the previous game (absolute area is unofficial; fan estimates around 107 km2). A long diagonal highway links the south-west to the north-east. | ADAPT | Our map is 16 km2 (about 15 percent); use FH5 for ratios only, since fan distance claims contradict each other. |
| Altitude / moisture / coast-driven biome contrast | Strong regional contrast comes from elevation, moisture and distance to the sea; only the volcano summit has snow. | ADOPT | Cheap weightmap rules give instant regional identity on a small map. |
| 11 biomes | Canyon, tropical coast, farmland, arid hills, jungle, living desert, rocky coast, sand desert, swamp, urban town, volcano. | ADAPT | Collapse to 4 regions plus a crossroads hub; reuse a few props as sub-biomes. |
| Biome clustering | Several biomes sit within minutes of each other, so one drive crosses many looks. | ADOPT | Use 200-400 m blended transition bands. |
| Long diagonal highway spine | A very long fast road is the connective backbone; events cross over and under it. | ADOPT | Gives the 5 km+ high-speed stretch and a navigation reference. |
| Iconic landmark per region | Volcano cone, dam, bridge, ruins, canyon walls anchor navigation and event names. | ADOPT | Cheap navigation plus strong screenshots (lighthouse, castle, summit mast, mesa). |
| Mega events touring all biomes | Single runs of 17-37 miles (the longest around 55 km) crossing nearly every biome. | ADAPT | A 22-28 km grand-tour loop (scaling by the square root of area gives about 21 km); it doubles as the time trial. |
| Descent-from-high-to-low race geometry | Many sprints run from canyon, volcano or hills down to the coast. | ADOPT | Delivers speed, vistas and biome contrast cheaply. |
| Dense town with tunnels | The one fully urban biome with echoing tunnels and narrow streets. | SKIP | The brief is a countryside game; keep a mountain tunnel only. |
| Festival hub, outposts, expeditions | A main site plus five themed outposts, each unlocked by a long scripted drive; accolades gate progress. | ADAPT | One rest or hub area per region, no campaign, no gating. |
| Fast travel with fees, houses and boards | Fast travel costs credits (about 10,000), reduced 200 per smashed board; "go home" is free. | ADAPT | Free `tp` to named hubs from console or map; no economy. |
| Second map (Rally Adventure expansion) | A separate 6-biome map reached by fast travel. | SKIP | Single 4 x 4 km map. |
| Per-biome echo and reverb | Canyons and tunnels have audible reflections. | ADOPT | Reverb volumes cost little and add atmosphere. |
| Biome-tuned ambient density | Towns feel busier than jungle; wildlife is tied to biome. | ADAPT | Per-region traffic and ambient-life multipliers. |

### 2.2 Roads and surfaces

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Roads independent of events | The road network exists on its own; events are named waypoint chains laid on top and anchored to landmarks. | ADOPT | Events become data (road ID plus parameters), so the road graph can be regenerated without breaking them. |
| Road classes by character | A very long, nearly straight highway is the series' longest; the sand desert offers long top-speed stretches; the volcano has big switchback roads in both tarmac and dirt; the old town has tunnels; swamp waterways are drivable. | ADOPT | Five classes with distinct speed, width and surface rules: highway, regional, mountain, dirt, shortcut (village streets as a sub-class); each region gets one signature road type. |
| Event length classes | Fan data: circuits 1.2-2.5 mi per lap, road sprints 3.7-6.1 mi, dirt trails 3.8-5.4 mi, cross-country 3.2-4.8 mi, street 3.5-5.7 mi. | ADAPT | Sprints of 3-6 km; circuits only where a real loop exists. |
| Mixed-surface routes | Routes mix asphalt, dirt, sand, mud and fords. | ADOPT | Showcases the per-surface grip system. |
| Cross-country over open terrain | Routes across fields, dunes and rivers with jumps. | ADAPT | A few marked off-road shortcuts, no separate race class at first. |
| Surface set | Tarmac, dirt, gravel, grass, sand, mud, snow, water. | ADAPT | Asphalt, concrete, dirt, gravel, grass, sand, wet asphalt, plus snow and mud by climate. |
| Seasonal geography | A dry lake and seasonal river open shortcuts in some seasons. | SKIP | Out of scope for one session. |
| Roads drivable in both directions with oncoming flow | Two-way roads that events cross. | ADOPT | Needed for traffic and for the prompt's lane graph. |

### 2.3 Weather, seasons and time of day

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Weekly seasons | Four seasons rotate weekly, not player-selectable in free roam. | SKIP (rotation) | Weather plus time of day already cost enough; a static season preset may come as a stretch item. |
| Per-biome season effect | Each season hits biomes differently: spring is the rainy season for jungle and farmland, summer brings thunderstorms to the tropical coast, autumn is the storm season (tropical storms, wind), dust storms belong to the dry season (its calendar slot is not firmly sourced), and only the volcano gets snow while the coast stays warm. | ADAPT | Four climate zones plus an altitude snow line; dust only in the arid region. |
| Snow only at altitude; rain becomes snow uphill | Precipitation type follows elevation. | ADOPT | Fits the mountain pass; one temperature(altitude, hour) rule. |
| Localised, growing, visible storms | A storm sits over one area, starts small, swells and can be chased. | ADAPT | Staged: first a global weather state with per-region multipliers; later at most two moving weather cells. |
| Dust storm wall | Dust is volumetric particles the light passes through (not a screen tint) and scenery fades in and out as it drifts by, cutting visibility in the dry season; the exact distance is unpublished, our table uses tens of metres. | ADAPT | Stretch: a moving cell in the arid region using a Local Fog Volume, Niagara sheets and dense low-falloff fog. |
| Photo-mode weather list (10) and time list (9) | Default, clear, post-rain variants, cloudy, overcast, light and heavy precipitation, gale, fog; dawn to night slots. | ADAPT | Required states: clear, cloudy, rain, fog, storm; time slots map to fixed sun elevations. |
| Thousands of captured sky presets | Hundreds of hours of HDR sky capture drive the lighting. | SKIP | Use SkyAtmosphere plus VolumetricCloud plus about ten parameter rows. |
| Short night | The day cycle is long and night is only about a tenth of it (unofficial). | ADOPT | Elevation-based time warp gives about 4-5 real minutes of night. |
| Weather changes grip | Rain is a general grip debuff; big puddles can spin cars; no official numbers. | ADAPT | Surface x wetness tables derived from real friction data (section 5, item 9). |
| Visibility and fog | Dust and tropical storms cut visibility heavily. | ADAPT | Visibility table converted to fog density (FogDensity = 56.4 / visibility in metres). |
| Day/night lighting moods | Golden hour, sunset, blue hour, night. | ADAPT | Elevation-keyed lighting table (sun, sky light, exposure, haze). |
| Ray-traced GI and car-viewer ray tracing | FH5 uses new GI and ray tracing in the car viewer. | SKIP | Lumen is already configured. |
| Seasonal water level (lake dries up) | A large lake drains in winter. | SKIP | Out of scope. |
| Physics-driven dust trails | Rally expansion added dust plumes that obscure followers. | ADAPT | Speed-scaled dust and spray particles on loose and wet surfaces, no physics coupling. |
| Weather communicated in HUD | No confirmed weather widget; mostly diegetic. | ADAPT | Small weather/time chip plus grip and low-visibility warnings. |
| Rain scarcity in free roam | Players report rain is hard to find. | SKIP (avoid) | Schedule a non-clear state at least every 10 minutes. |
| Photo-style grading and exposure | Contrast, colour and exposure grading; auto-exposure criticised for hunting. | ADAPT | Per-condition grade table and narrow, slow exposure brackets. |

### 2.4 Events and activities

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Speed trap | Speed measured at the instant of crossing one gate, either direction; up to 3 stars. | ADOPT | Simplest robust activity; strong video payoff. |
| Speed zone | Average speed between two gates; must stay on road and drive the right way. | ADOPT | Reuses route speed profile and gate machinery. |
| Drift zone | Points from slip angle, speed and duration; one long drift beats several short ones; hitting objects resets the combo. | ADAPT | FH5's formula is unpublished; our own model needs drift-capable handling. |
| Danger sign (jump) | Ramp flight distance, clean landing required. | ADAPT | Needs hand-engineered ramps; scale distances to 40-250 m. |
| Trailblazer | Off-road sprint against a countdown; stars from seconds left. | ADAPT | Folded into the checkpoint-race system as the dirt variant. |
| Checkpoint race (road, dirt, cross-country) | Start arch, countdown, gates every 350-900 m, respawn at last gate. | ADAPT | Solo countdown race first; AI position racing is a stretch. |
| Street racing class | City street races. | SKIP | No city. |
| Time trial / Rivals ghost | Ghost time trials against recorded runs. | ADAPT | Flagship event on the scenic loop; local-only bests and ghost. |
| Bonus (XP) boards | Breakable boards paying 1k/3k/5k XP. | ADAPT | About 40 billboards in three tiers (200/500/1000). |
| Fast Travel boards | Each cuts the fast-travel fee by 200. | SKIP | Our teleport is free. |
| Barn finds | 14 hidden cars with a search circle and restoration. | ADAPT | 3 hidden barns with a cosmetic reward; all 10 cars stay selectable. |
| Treasure chests | Weekly search circle on the map. | ADAPT | Stretch: reuse the billboard system. |
| Photo challenges | A car plus a location, completed in photo mode; many also reward using a photo feature (portrait view, a saved preset, every time slot, a grid guide). | ADAPT | 8 overlook spots validated on capture (frustum, line trace, car in frame). |
| Pathfinder trail routes | Weekly exploration routes marked in free roam by coloured balloon markers (start/finish and along the route), pinned to the GPS, ending near a chest. | ADAPT | One permanent scenic discovery trail with floating markers, no weekly rotation; cheap wayfinding that doubles as a showcase drive. |
| Skill chain | Drift, air, near-miss and wreck skills build a multiplier; a collision breaks the chain. | ADAPT | Optional reduced chain, cap x5, 3 s timer, tunable (sources conflict). |
| Accolades, Festival Playlist, leaderboards, Showcase, Arcade, EventLab | Meta-progression, seasonal content, UGC, multiplayer. | SKIP | Not a solo 4 x 4 km game. |
| Harder AI pays more credits | Difficulty affects credits, not XP. | SKIP | No economy at first. |
| HUD notification system | Banners and result cards for each event. | ADAPT | Five channels (toast, banner, result card, live meter, countdown); activities emit events only. |

### 2.5 Cars and classes

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Roster of 500+ real cars | Alphabetical by maker, year and model. | ADAPT | Exactly 10 fictional cars. |
| Rarity tiers | Common to Legendary, mostly affecting wheelspin odds. | ADAPT | Display-only tag. |
| Performance classes D/C/B/A/S1/S2/X | Seven bands: D 100-500, C 501-600, B 601-700, A 701-800, S1 801-900, S2 901-998, X 999. | ADOPT | Familiar scale; thresholds in data. |
| Performance Index recomputed from resulting performance | Not a sum of part costs; a rear wing or heavy rims can lower it. | ADAPT | Analytic estimator in C++ instead of a hidden test lap. |
| Six sub-ratings | Speed, Handling, Acceleration, Launch, Braking, Offroad (0-10). | ADOPT | Direct garage stat bars that also feed PI. |
| Forza Editions, welcome packs, wheelspin collection, car mastery perks | Reward and collection systems. | SKIP | Meta-progression. |

### 2.6 Customisation, tuning and upgrades

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Six upgrade categories with tiers | Conversion, Engine, Platform and Handling, Tires and Rims, Aero and Appearance, Drivetrain; Stock/Street/Sport/Race. | ADAPT | About 14 slots and 38 options in a data table. |
| Parts gate tuning screens | Race suspension, brakes, transmission, differential and adjustable aero unlock the matching tuning rows. | ADOPT | Cheap with unlock tags; gives upgrades a purpose. |
| Auto Upgrade | One-click raise to the next class. | ADAPT | Greedy PI-per-cost solver on the estimator. |
| Nine tuning groups | Tires, gearing, alignment, anti-roll, springs/ride height, damping, aero, brakes, differential. | ADAPT | About 18 sliders; drop caster and per-gear editing. |
| Camber, toe, differential lock | Real parameters in FH. | ADAPT | Our own vehicle can model them as grip scalars, cosmetic wheel lean and a driveline split. |
| Paint finishes and vinyl editor | Paint families plus a layered vinyl editor. | ADAPT | Gloss, matte, metallic, stripes and rims; no vinyl editor. |
| Engine swaps, body kits, drift tier | Large part catalogues. | SKIP | Content cost. |
| Upgrade preview deltas | Stat bars show change before purchase. | ADOPT | Cheap and makes the garage readable on video. |

### 2.7 Driving assists

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Difficulty presets and options | Presented as a settings screen of separate selectors (not one slider): ABS on or off, steering from fully assisted to simulation, traction and stability control levels, automatic or manual shifting, driving line, damage level, rewind, plus AI skill; the game shows a credit multiplier that grows as assists are removed. Preset names were not readable in the sources. | ADAPT | Four presets (our own names) plus eight toggles in one settings struct, shown on one screen with a live summary. |
| ABS and traction control | Limit lock-up and wheelspin; ABS is a plain on/off menu switch, traction control is a graded level. No live on-screen indicator was found in the sources read. | ADOPT | Implement in our own tire model; add small ABS / TCS / STM lamps on the gauge cluster that flash when a controller intervenes (the project brief asks for assist indicators). |
| Stability control and steering assist | Hold slides, help counter-steer; steering assist is graded from auto-steer to simulation. | ADAPT | Yaw-rate controller with differential braking, plus counter-steer assist. |
| Driving line | Road overlay with full, braking-only and off modes; in full mode the colour is the message: green keep speed, yellow ease off for a coming turn, red brake hard. | ADAPT | Speed-profile line with cruise, lift and brake states; add chevron density or pulse as a second cue so state is never hue-only. |
| Rewind | Undo mistakes. | ADAPT | Stretch: ring buffer of vehicle state. |
| Credit bonus for fewer assists | Reported +25 percent to +50 percent (snippet-level evidence). | ADAPT | Additive reward multiplier; meaningful only if a score economy exists. |
| Drivatar difficulty, manual with clutch, tire wear | Further simulation options. | SKIP | Out of scope (manual gearbox without clutch stays optional). |

### 2.8 Traffic and ambient life

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Civilian traffic | Almost undocumented by sources; anecdotes say traffic is thin at night and in mountains. | ADAPT | Required by the brief; fully original design (see item 6). |
| Wildlife spread across regions | Pre-release coverage confirms goats, donkeys, bighorn sheep, flamingos and wild dogs scattered over the map; their exact biome mapping and flee behaviour are not documented (chickens and gulls were not confirmed in the pages read). | ADAPT | Fleeing livestock, bird flocks, a rare roadside crossing, assigned to regions by our own table. |
| Balloons and aircraft | Hot-air balloons over the festival. | ADAPT | 3-5 balloons and one light plane, cheap instanced life. |
| Spectators and crowds | Crowds at event sites. | SKIP | Animated people are costly; tents and flags suffice. |
| Deliberately sparse traffic | A 2026 press report says a successor title's low-traffic design was intentional. | ADOPT | Supports tuning for thin, fast roads. |

### 2.9 HUD, minimap and navigation

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Per-element HUD toggles and notification duration | Map, skills, notifications, wrong-way, lap time and more can be switched; duration adjustable. | ADOPT | Cheap, good for recording and accessibility. |
| Speedometer, tach, gear | Analogue or digital, metric or US units. | ADAPT | Bottom-right cluster, tabular digits, km/h and mph. |
| Circular minimap | Mini radar; undiscovered roads shown in orange; new roads reward XP. | ADAPT | Heading-up vector map; amber undiscovered segments. |
| Full map with filters | Pausable map, filter menu with an all-toggle; icons overlap; filters reportedly reset on boot. | ADOPT | Save filter state to fix the complaint. |
| Waypoint GPS line | Route trail on the road; a review said it was hard to see. | ADAPT | Cyan ribbon chosen for luminance contrast over asphalt. |
| GPS voice | Spoken directions with volume slider. | SKIP | Text card and ping give the same information. |
| Accessibility | Text scale to 150 percent, colour-blind and high-contrast modes. | ADAPT | Scale to 150 percent; never encode state by hue alone. |
| Region-name popup, toast stack | On-screen location and event messages. | ADAPT | Original timings (section 5, item 5). |
| Stunt result cards (FH5 calls these stunts PR stunts) | Per-stunt result with stars. | ADAPT | Per-activity star ratios (section 5, item 11); 60 / 80 / 100 percent of target only as a fallback. |

### 2.10 Photo mode and presentation

| Feature | What it is | Verdict | Reason |
|---|---|---|---|
| Photo mode core | Entry key pauses the world; free camera; zoom, aperture, shutter, exposure style sliders; time and weather. | ADAPT | Pause plus CineCamera pawn with real focal length and aperture. |
| Presets, composition guides, time and weather slots, wheel angle | Added in a 2023 update: composition guides (off, aspect ratios, grid, golden ratio) with a portrait toggle, 9 time and 10 weather slots, wheel angle (default, straight, left, right), saved and renamable effect presets, plus filters (contrast, saturation, brightness, vignette, temperature, bokeh). The aspect-ratio guides stand in for cropping. | ADOPT | Small, data-driven, valuable for video. |
| Capture and gallery | Saved with a watermark. | ADAPT | Same flow without watermark; wait 8-16 frames for Lumen/TSR to settle. |
| Live minimap via scene capture | Top-down render target. | SKIP | Re-renders the scene; vector map is cheaper and sharper. |
| Optimistic festival presentation | Bright colour, balloons, banners. | ADAPT | Warm hub areas, bunting and flags near rest stops. |
| Showroom / car viewer | Garage view of the car. | ADAPT | Showroom camera plus Slate overlay. |

---

## 3. Unreal Engine 5.8 technical findings

### 3.1 Landscape, World Partition and HLOD

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| Creating the landscape | `ALandscape::Import` is C++ only; Python, Blueprint and commandlets cannot create a landscape from data. | ADOPT | Wrap spawn + Import + layer infos + `ChangeGridSize` in a BlueprintCallable in `Sonnet55ForzaEditor` and call it from Python (pattern: Epic's PCG test and the New Landscape UI code). |
| Landscape size | Valid layouts use sections of 7/15/31/63/127/255 quads, one or 2x2 per component. 4033 verts (126-quad components, 1024 of them) is Epic's recommended size; 4065 verts (254-quad components, 16 x 16 = 256) gives 4064 m at 1 m. 4096 m is unreachable. | ADAPT | Primary 4065 / 256 components (lighter collision and Nanite cost); 4033 and a 2 m / 2033-vert layout stay as fallbacks. |
| Height encoding | 16-bit; local height = (u16 - 32768) / 128 x ZScale; ZScale = span_cm / 512 (a -60..+760 m span gives about 160). | ADOPT | Record the mapping in `world_meta.json`. |
| Road corridors | Landscape splines need a Spline edit layer and are barely scriptable. | ADOPT (pre-carve) | Author roads first, clamp grades, carve with falloff into the heightmap offline, then paint weightmaps; shared with traffic and events. |
| Weightmap layers | `FLandscapeImportLayerInfo` byte arrays; layer-info assets carry a physical material (dominant layer wins); Python cannot set `layer_name`. | ADAPT | 6-8 layers (physical-material index is 6-bit, max 63 per component). |
| Landscape material | Slope/height auto-blend in the shader plus scripted weightmaps. | ADOPT | No painting cost; scriptable. |
| Nanite landscape | About 2x landscape memory, async build; a 5.6 bug reportedly dropped components beyond 64. | ADOPT | Verify on 5.8.2 with the Nanite visualisation. |
| Runtime virtual texturing | Caches landscape shading. | SKIP | Roads are separate meshes; material is moderate. |
| Landscape Grass | Material-driven grass types with cull distances. | ADOPT | No scripting; keep meshes Nanite for Lumen. |
| Landscape splines | Edit-layer splines with spline meshes. | SKIP | Only `GetSplineMeshComponents` is scriptable. |
| Road meshes | One thick, opaque Nanite mesh per chunk (Blender or GeometryScript). Spline-mesh components would mean 2000+ components, an open Nanite spline bug (reported as UE-348635) and poor Lumen cards. | ADOPT chunks, SKIP spline mesh | Exact conformity; thickness stops Lumen leaking through thin walls. |
| World Partition map | `LevelEditorSubsystem.new_level(path, is_partitioned_world=True)` or `new_level_from_template` with the OpenWorld template; save to flush external actors. | ADOPT | Native Python path. |
| Streaming range | 5.8's default runtime hash is `WorldPartitionRuntimeHashSet` with 256 m range and 128 m cells (about 3.7 s at 250 km/h); Python cannot reach it. | ADAPT | Edit via C++ reflection (cell 256 m, range 768-1200 m) and add a velocity look-ahead streaming source. |
| Always-loaded terrain and roads | Landscape proxies and road chunks can be non-spatially-loaded; only vegetation, props and buildings stream. | ADOPT | A few hundred MB resident; landscape HLOD unnecessary. |
| HLOD | `UnrealEditor-Cmd ... -run=WorldPartitionBuilderCommandlet -Builder=WorldPartitionHLODsBuilder -AllowCommandletRendering -SetupHLODs -BuildHLODs`. | ADAPT | Optional; Instancing layer for distant settlements and trees only. |
| One File Per Actor, data layers | One actor per prop explodes file count; data layers are runtime toggles. | ADOPT (avoid) / SKIP | Use instanced meshes; no need for data layers yet. |

### 3.2 Vehicle physics: Chaos Vehicles vs a project-owned raycast vehicle

**Recommendation: ADOPT a project-owned raycast/spring vehicle driven from `UActorComponent::AsyncPhysicsTickComponent` on a Chaos rigid body. SKIP Chaos Vehicles** (time-boxed fallback spike only). Reasons from the local source:

- The plugin is in `Plugins/Experimental`, flagged experimental, disabled by default and absent from our `.uproject`; the 5.8 release notes only mention Modular Vehicles.
- It needs a skeletal mesh, physics asset and wheel bones (awkward to generate from Blender); a static mesh works only via a global debug CVar with no hard stops.
- Its tire model is a friction circle with one scalar friction from the physical material, and wheel speed snaps to ground speed. It has no stability control, camber, toe, tire pressure or temperature, per-axle downforce, bump/rebound split or limited-slip differential, and engine/gear/diff/steering configs are baked when physics state is created. Claims of a Pacejka model are contradicted by the source.
- A project-owned model gives full control of tires, driveline, assists, weather grip and tuning, is data-driven per car, and is stable at fixed steps at 250 km/h.

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| Per-step hook | `AddCustomPhysics` under Chaos calls the delegate once on the game thread; sync substepping does not call sim callbacks per substep. | SKIP | Not a per-substep hook. |
| Async physics tick | Runs per fixed solver step with the game thread frozen; forces go through the physics-thread body handle and are zeroed every step. | ADOPT | Fixed dt, no skeletal assets. |
| Settings | `bTickPhysicsAsync=True`, `AsyncFixedTimeStepSize` 1/60 (test 1/120), substepping off; read at scene creation, so ini only. | ADOPT | Constant step keeps springs and tires stable. |
| Wheel probes | `LineTraceSingleByObjectType` with `AllStaticObjects` and `bReturnPhysicalMaterial` (physics-thread data inside the async tick); read `Hit.PhysMaterial->SurfaceType`. Landscape layers use layer-info physical materials, roads a component override. | ADOPT | No channel setup needed. |
| Body setup | Mass override, centre-of-mass nudge, inertia scale, `SetInertiaConditioningEnabled(false)` (defaults true), CCD, wake bodies from the game thread. | ADOPT | Predictable handling; no tunnelling at 70 m/s. |
| Custom sim callback; Modular Vehicle | Callback avoids the thread sync but forbids UObject access; Modular Vehicle is experimental 0.1. | ADAPT / SKIP | Callback only if profiling demands it. |
| Units | cm, kg, s; 1 cm/s = 0.036 km/h; `GetForwardSpeed()` is signed cm/s. | ADOPT | Prevents unit bugs in triggers and HUD. |

### 3.3 PCG and foliage

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| PCG | Present, enabled by default, scriptable, but async and creates many partition actors. | SKIP (baseline) | Keep enabled; own placement is simpler. |
| PCG generation modes | Epic's docs describe four modes: non-partitioned (bound to its volume, default), partitioned (output split into grid cells that World Partition can stream), hierarchical (needs partitioning; coarse grids for trees and boulders, fine grids for grass, data flows large to small), and runtime (generates and cleans up around generation sources such as the player controller, best combined with hierarchical). Grid size lives on the PCG world actor; larger grids need larger radii, and passing large-grid data into small grids can duplicate points. | ADAPT | Stretch only: partitioned plus hierarchical runtime graphs for forests if the own scatter proves too uniform; not on the critical path. |
| Own scatter | `InstancedFoliageActor.add_instances` auto-partitions into WP foliage actors, or a C++ per-cell ISM actor. | ADOPT | Reproducible; ISM over HISM for Nanite meshes. |

### 3.4 Nanite, Lumen, Virtual Shadow Maps

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| Nanite | Opaque and masked only; WPO limited; foliage voxelisation experimental. | ADOPT | Gives Lumen surface-cache coverage and cheap shadows; keep a preserve-area fallback for trees. Tessellation and assemblies SKIP. |
| Lumen | Hardware tracing defaults on and the project has `r.RayTracing=True`. | ADAPT | Software Lumen: `r.Lumen.HardwareRayTracing=0`, `sg.GlobalIlluminationQuality=2`, reflections 2, shadows 2, TSR near 70 percent; profile on the RTX 5070; Lumen Lite (beta) as fallback. |
| Nanite limits | Epic's page: only opaque and masked blend modes (translucent materials and mesh decals are out, projected decals still work); no morph targets; no forward shading or MSAA; needs DirectX 12 with Shader Model 6 and an SSD-class disk; the scene is capped at about 16 million streamed-in instances; static, instanced, hierarchical-instanced, spline, foliage and landscape-grass components all work. | ADOPT | Fits: terrain, road chunks and opaque props are Nanite; glass, particles and any translucent decal stay non-Nanite; our instance counts are orders of magnitude below the cap. |
| Lumen limits | Epic's page: software tracing only sees static meshes, instanced meshes and landscape; foliage counts only if Nanite or if it affects distance-field lighting; WPO is unsupported; walls thinner than about 10 cm leak light; the Lumen scene reaches about 200 m around the camera (extendable to about 800 m with the Lumen Scene View Distance setting), beyond which only screen traces apply; static meshes get up to 12 surface-cache cards by default; hardware tracing needs RTX 2000 / RX 6000 class GPUs and its cost grows with overlapping meshes, with Far Field reaching about 1 km but needing HLOD; Lumen GI cannot be combined with baked lightmaps and does not support forward shading or VR; the High scalability level targets 60 FPS on current consoles and the Epic level 30 FPS with about 8 ms for GI and reflections at 1080p internal. | ADAPT | Thick road meshes (no thin walls), Nanite on every prop, cars are static-mesh parts so they get normal cards (split long shells if pink coverage appears), raise Lumen Scene View Distance for fast driving and check it against the RTX 5070 frame budget, keep the software path as the 60 FPS baseline. Values are from the docs; confirm in the 5.8.2 visualisation modes. |
| Virtual Shadow Maps | Moving the sun invalidates cached pages; non-Nanite casters and WPO are costly. | ADOPT | Quantise sun updates; page pool 2048 or more. |
| MegaLights | Many-light shadowing. | SKIP | Revisit for night street lights. |

### 3.5 Water, sky and weather stack

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| Water plugin | Experimental; a plain spawn skips factory defaults (materials, waves, fill zone); carving needs edit layers. | ADAPT | Ocean and lakes by hand with `affects_landscape=False`; plane-with-material fallback. Rivers SKIP (ribbon mesh). |
| Sky stack | SkyAtmosphere, two directional lights (atmosphere indices 0 and 1), real-time SkyLight, VolumetricCloud, ExponentialHeightFog, sea level at Z=0. | ADOPT | Official best practice. Engine cloud material `m_SimpleVolumetricCloud` exposes coverage, density, storm and wind parameters (names from an asset scan; confirm in editor). |
| Sun position | `SunPosition` plugin exists, not enabled. | SKIP | Ten lines of solar math. |
| Weather grip | Chaos reads friction from the physical material each tick. | ADAPT | Our model: grip = load x mu_surface x mu_weather x mu_tire, never accumulated. |

### 3.6 Niagara, MetaSounds and procedural audio

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| Niagara spawning | `UNiagaraFunctionLibrary::SpawnSystemAtLocation/Attached` plus `SetVariable*`. | ADOPT | Standard API. |
| Niagara authoring | No dust, smoke, rain or splash systems ship; templates expose no user parameters. The Beta `CascadeToNiagaraConverter` has a Python API that builds systems and emitters; exposing User parameters is unverified. | ADAPT | Try it; fallback is pooled ISM puff particles with a script-made material. |
| Engine and tire audio | `USynthComponent` + `ISoundGenerator` driven by atomic RPM, load, slip and wind (needs AudioMixer, SignalProcessing, AudioExtensions). | ADOPT | Asset-free, sample-accurate RPM response. |
| MetaSound Builder API | Works at runtime per the docs, but pin names are discovered by hand. | ADAPT | Later, for ambience. |
| MotoSynth, AudioMotorSim | Experimental, need recordings. | SKIP | No external audio. |

### 3.7 Enhanced Input, UMG/Slate, console, traffic framework, save

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| Enhanced Input | `NewObject` for `UInputAction`/`UInputMappingContext`; `MapKey` with negate and dead-zone modifiers; since 5.7 mappings sit under `DefaultKeyMappings.Mappings`; poll `GetBoundActionValue` (a bound reference can dangle). | ADOPT | No .uasset; photo mode needs `bTriggerWhenPaused`. |
| UI toolkit | Slate (`SLeafWidget::OnPaint`, `FSlateDrawElement`, `AddViewportWidgetContent`); `AHUD` canvas for debug text. | ADOPT | Robust without Blueprint widgets. UMG built in C++ SKIP. |
| Minimap drawing | `MakeLines` (in `DrawElementTypes.h`, copies arrays) over a baked underlay. | ADOPT | Reuse scratch buffers; flip with `map_y = -dot(d, forward)`. |
| Console | Engine console (tilde) with autocomplete from `IConsoleManager`; commands registered from a GameInstance subsystem. | ADOPT | Custom Slate console is optional and needs tilde removed from `ConsoleKeys`. |
| Mass / ZoneGraph | MassGameplay 0.4 experimental and pedestrian-oriented; ZoneGraph build is editor-only; no MassTraffic exists. | SKIP | Custom lane graph with IDM agents in a `UTickableWorldSubsystem` (needs a `GetStatId` override). |
| Subsystems and save | `UGameInstanceSubsystem` for save, console, settings; `USaveGame` with plain data and `AsyncSaveGameToSlot`. | ADOPT | Built in; object references serialise as strings. |

### 3.8 Python editor scripting and command-line automation

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| Headless Python | `UnrealEditor-Cmd.exe -ExecutePythonScript="file.py"` runs inside the full editor and quits unless `set_keep_python_script_alive(True)`; exit code is 0 even if the script raised, unless `-ScriptErrorsAreFatal`. `-run=PythonScript` is the commandlet (no level). | ADOPT / ADAPT | Only reliable driver for World Partition and asset work; commandlet for pure asset batches. |
| API reference | `Intermediate/PythonStub/unreal.py` is written when developer mode is on (already set) in a non-commandlet run. | ADOPT | Grep for exact 5.8 names. |
| Flags and tests | `-unattended -nosplash -nullrhi -stdout -FullStdOutLogOutput -culture=en -abslog=<abs>.log`; `-ExecCmds="Automation RunTests Roam; Quit"` exits 255 on failure (zero matched tests also fails); `-nullrhi` cannot screenshot. | ADOPT | CI-style loop. |
| Test world | `FTestWorldWrapper` gives a ticked game world without PIE; map-based functional tests need a plugin. | ADOPT / SKIP | Deterministic headless vehicle tests. |
| Game runs | `-game` with real RHI plus `HighResShot`. | ADAPT | Screenshots race with `Quit`; poll first. |
| GeometryScripting and materials | Creates Nanite-capable StaticMesh assets in one call (plugin must be added to the `.uproject`); `MaterialEditingLibrary` builds graphs. | ADOPT / ADAPT | With Substrate on, use a few verified parents plus instances. |
| Build | `Build.bat <Target> Win64 Development -Project=... -WaitMutex -Log=...` (baseline 63 s); exit 0 ok, 6 compile, 8 rules, 10 conflicting instance; real flag is `-NoHotReloadFromIDE` (the existing script's `-NoHotReload` is ignored). V7 settings make missing-return, dangling and unreachable-code warnings errors; Unreal5_8 include order removes transitive includes. | ADOPT | Reliable loop. Live Coding and distributed builds SKIP; `RunUAT BuildCookRun` ADAPT for a stretch package. |
| Windows launch | `FParse::QuotedString` values interpret backslash escapes; Git Bash rewrites `/Game/...` arguments; machine locale is Russian. | ADOPT | PowerShell launcher, forward slashes, `-culture=en`, parse stable log tokens. |

### 3.9 FBX / Interchange pipeline and Blender export recipe

| Topic | Finding | Verdict | Reason |
|---|---|---|---|
| FBX import path | In 5.8 an FBX import task goes to Interchange unless a legacy factory is set; legacy `FbxImportUI` options are converted in memory. Translator settings (convert scene, front-X axis, unit conversion) are not forwarded and come from `[Interchange_Translator_ClassName_InterchangeFbxTranslatorSettings]` in per-project editor settings. | ADOPT | Pin those settings; set every option explicitly and `automated_import_should_detect_type=False`; assert bounds, collision and Nanite after import. Legacy factory is a fallback (ADAPT). |
| Naming | `UCX_`, `UBX_`, `UCP_`, `USP_` collision prefixes and `SOCKET_` empties are honoured; one mesh per file takes the file name. | ADOPT | Props use hull collision; cars use code-made primitives. |
| Cars | Static meshes: body FBX with socket empties plus a shared wheel FBX, one part per file so pivots stay at the part origin. | ADOPT | No skeleton or physics asset. |
| Blender 5.2 recipe | `apply_unit_scale=True`, `global_scale=1`, scale option none, forward Y, up Z, smoothing off (normals only), triangulate, no tangents, no leaf bones, no animation bake, no space-transform bake. Default UE import maps Blender (x, y, z) to UE (x, -y, z) x 100, so cars face +X. | ADOPT | Project notes record a verified 4 m body to 400 uu, +X forward, left side to -Y; still run an asymmetric axis-test import in UE before the garage. |
| glTF; runtime meshes | glTF is meter and axis correct but has no collision or socket prefixes; procedural runtime meshes lack Nanite. | ADAPT | glTF for props only; runtime meshes only for geometry that changes (GPS ribbon). |

### 3.10 Verified facts about the LOCAL UE 5.8.2 install

- `W:\Unreal Engine 5\UE_5.8`: version 5.8.2, changelist 56702186, branch `++UE5+Release-5.8`.
- `ChaosVehiclesPlugin` is in `Plugins/Experimental`, `IsExperimentalVersion` true, `EnabledByDefault` false, and not in `Sonnet55Forza.uproject`. `ChaosModularVehicle` (0.1) and `Mover` are experimental; `Water` is experimental and disabled by default; `Landmass` is beta.
- `PCG` and `Interchange` are enabled by default (PCG not flagged beta). `GeometryScripting` is released (not experimental or beta) but not yet in the `.uproject`. `SunPosition` exists but is disabled by default. `Niagara`, `Metasound`, `Synthesis`, `EnhancedInput` are enabled by default; `CommonUI` is present but not default. `MassGameplay` (0.4) and `ZoneGraph` (0.5) are experimental; there is no MassTraffic. `PythonScriptPlugin` is flagged beta. `CascadeToNiagaraConverter` (FX) is beta.
- The `.uproject` lists modules `Sonnet55Forza` (Runtime) and `Sonnet55ForzaEditor` (Editor) and plugins ModelingToolsEditorMode (editor only), PythonScriptPlugin, EditorScriptingUtilities, Niagara, Metasound, PCG, Water.
- `DefaultEngine.ini` already sets Lumen GI and reflections, Virtual Shadow Maps, Substrate on, `r.RayTracing=True`, extended default luminance range and developer mode for the Python stub.
- Embedded editor Python is 3.11.8 without numpy; heavy heightmap work runs in Blender's bundled Python 3.13 (numpy 2.3) used as a plain interpreter.
- Machine: Ryzen 7 5700X3D, 64 GB RAM, RTX 5070, Windows 11, Russian locale; Blender 5.2.2 LTS on localhost:9889.

---

## 4. Source URLs (deduplicated, grouped by topic)

URLs are listed exactly as they appeared in the research output. Entries marked (snippet only) were not read in full (page blocked or truncated); claims that depend on them are treated as unverified. Local source paths are summarised at the end; they are not URLs.

**A. FH5 world, biomes, map, event routes**

- https://news.xbox.com/en-us/2021/07/26/exploring-the-biomes-and-seasons-of-forza-horizon-5/
- https://forza.net/news/exploring-forza-horizon-5-biomes-and-seasons
- https://forza.net/news/forza-horizon-5-rally-adventure-map-reveal
- https://forza.net/news/forza-horizon-5-road-to-mexico-september-update
- https://en.wikipedia.org/wiki/Forza_Horizon_5
- https://gtplanet.net/forza-horizon-5-map-revealed-20210809
- https://www.gtplanet.net/forza-horizon-5-snackable-20210907/
- https://gtplanet.net/here-are-the-11-biomes-featured-in-forza-horizon-5
- https://videogameschronicle.com/news/forza-horizon-5s-full-world-map-has-been-revealed
- https://press-start.com.au/news/xbox/2021/10/11/google-maps-played-a-big-role-in-forza-horizon-5s-mexico/
- https://www.thegamer.com/interview-playground-games-forza-horizon-5/
- https://racinggames.gg/article/forza-horizon-5-mexico-map-deep-dive
- https://www.ggrecon.com/guides/forza-horizon-5-map/
- https://guides4gamers.com/forza-horizon-5/maps/mexico/
- https://guides4gamers.com/forza-horizon-5/pois/road-racing-events/
- https://guides4gamers.com/forza-horizon-5/pois/cross-country-racing-events/
- https://guides4gamers.com/forza-horizon-5/pois/dirt-racing-events/
- https://guides4gamers.com/forza-horizon-5/pois/street-racing-events/
- https://www.gameshedge.com/forza-horizon-5-location-specific-barn-finds-localized-weather-diverse-animals/
- https://www.techradar.com/news/forza-horizon-5-has-the-longest-highway-in-the-series-and-i-cant-wait-to-tear-it-up (headline and search snippet only; the page body was truncated)

**B. FH5 weather, seasons, time of day, sky**

- https://forza.net/news/forza-horizon-5-road-to-mexico-june-update
- https://forza.net/news/forza-horizon-5-explore-the-horizon
- https://forza.net/news/forza-photo-guide
- https://forza.net/news/forza-horizon-5-midnights
- https://news.xbox.com/en-us/2023/03/29/forza-horizon-5-rally-adventure-out-now/amp/
- https://www.videogameschronicle.com/news/forza-horizon-5s-art-team-explains-how-it-got-the-skies-to-look-so-realistic
- https://gamingbolt.com/forza-horizon-5-weather-conditions-detailed-eliminator-and-super-7-return
- https://www.gamepressure.com/S013-amp.asp?ID=13564
- https://traxion.gg/seasonal-conditions-and-unique-areas-explained-in-forza-horizon-5/
- https://racinggames.gg/forza/forza-horizon-5-complete-guide-to-scenery-and-seasons/
- https://www.gfinityesports.com/article/change-time-of-day-night
- https://www.analogstickgaming.com/game-reviews/2021/11/22/forza-horizon-5
- https://steamcommunity.com/app/1551360/discussions/0/3193611744850409699//1000

**C. FH5 events, PR stunts, collectibles, skill chain**

- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Speed%20Trap
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Speed%20Zone
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Drift%20Zone
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Danger%20Sign
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Trailblazer
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/XP%20Board
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Fast%20Travel%20Board
- https://guides4gamers.com/forza-horizon-5/pois/speed-traps/
- https://guides4gamers.com/forza-horizon-5/pois/speed-zones/
- https://guides4gamers.com/forza-horizon-5/pois/drift-zones/
- https://guides4gamers.com/forza-horizon-5/pois/danger-signs/
- https://www.gtplanet.net/forza-horizon-5-season-change-20220310/
- https://forza.net/news/forza-horizon-5-first-drive
- https://forza.net/news/forza-horizon-5-high-performance
- https://forza.net/news/forza-horizon-5-Community-Choice
- https://insider-gaming.com/every-skill-in-forza-horizon-5-how-to-earn-an-ultimate-skill-chain/
- https://gamerant.com/forza-horizon-5-get-skill-points-how-car-mastery-perks/
- https://www.inverse.com/gaming/forza-horizon-5-best-skill-point-cars
- https://steamcommunity.com/app/1551360/discussions/0/3181237058698815348
- https://www.dexerto.com/gaming/forza-horizon-5-barn-finds-explained-everything-you-need-to-know-1680127/
- https://racinggames.gg/forza/forza-horizon-5-treasure-map-guide

**D. FH5 cars, classes, upgrades, tuning, assists**

- https://forza.net/news/forza-horizon-5-confirmed-car-list
- https://caniplaythat.com/2021/11/04/forza-horizon-5-accessibility-menu-deep-dive/
- https://hackernoon.com/forza-horizon-5-cars-guide-how-to-build-and-tune-for-optimal-road-race-performance
- https://gamepretty.com/forza-horizon-5-build-tuning-tips/
- https://diamondlobby.com/forza-horizon-5/best-tuning-setups-for-forza-horizon-5/
- https://forzahorizoncar.com/en/wiki/guides/tuning.html (the page is titled for Forza Horizon 6; used only as a cross-check of the tuning-group concepts)
- https://racinggames.gg/forza/forza-horizon-5-how-to-change-difficulty/
- https://support.forza.net/hc/en-us/articles/360005363194-Difficulty-Assists-and-Drivatars (a Forza Motorsport 7 article, used only for assist vocabulary; some clients get a 403)
- https://support.forza.net/hc/en-us/articles/360005372033-FH3-Performance-Index-and-Classes (a Forza Horizon 3 article, used only to cross-check the class bands; some clients get a 403)
- https://www.windowscentral.com/forza-horizon-5-upgrading-guide (snippet only)
- https://www.gamesradar.com/forza-horizon-5-tips (snippet only)
- https://www.pcgamer.com/forza-horizon-5-car-list (snippet only)
- https://racinggames.gg/forza/forza-horizon-5-how-many-cars-will-there-be/ (snippet only)

**E. FH5 HUD, minimap, navigation, traffic, photo mode**

- https://www.purexbox.com/news/2023/05/forza-horizon-5-update-21-is-huge-featuring-all-new-photo-mode-options-and-more
- https://kotaku.com/11-things-i-wish-i-knew-before-starting-forza-horizon-5-1848007497
- https://kotaku.com/before-you-start-five-settings-to-change-in-forza-hori-1848004522
- https://www.ludo.guide/guide/forza-horizon-5/racing-line
- https://www.thegamer.com/forza-horizon-beginners-guide-tips/
- https://www.shacknews.com/article/127554/fast-travel-and-xp-board-location-maps-forza-horizon-5
- https://www.gamespew.com/2021/11/how-to-use-photo-mode-in-forza-horizon-5/
- https://criticalhits.com.br/games/forza-horizon-5-como-filtrar-icones-do-mapa/
- https://www.purexbox.com/news/2026/03/forza-horizon-6s-low-traffic-gameplay-was-done-on-purpose-says-ign

**F. Unreal Engine: Landscape, World Partition, rendering, sky, water, PCG**

- https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5-8-release-notes
- https://tomlooman.com/unreal-engine-5-8-performance-highlights/
- https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-technical-guide-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-splines-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/importing-and-exporting-landscape-heightmaps-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/landscape-overview
- https://dev.epicgames.com/documentation/unreal-engine/creating-landscapes-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/using-nanite-with-landscapes-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/world-partition---hierarchical-level-of-detail-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/world-partition-builder-commandlet-reference
- https://dev.epicgames.com/documentation/unreal-engine/nanite-virtualized-geometry-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/lumen-technical-details-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/virtual-shadow-maps-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/procedural-content-generation-overview
- https://dev.epicgames.com/documentation/unreal-engine/using-pcg-generation-modes-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/water-system-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/water-body-actors-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-atmosphere-component-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/exponential-height-fog-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/local-fog-volumes-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/auto-exposure-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/using-physical-lighting-units-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/geographically-accurate-sun-positioning-tool-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/sun-and-sky-actor-in-unreal-engine

**G. Unreal Engine: vehicles, input, audio, UI, gameplay framework, camera**

- https://dev.epicgames.com/documentation/en-us/unreal-engine/how-to-set-up-vehicles-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/API/PluginIndex/ChaosVehiclesPlugin
- https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/ChaosVehicles/UChaosVehicleMovementComponent
- https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/ChaosVehicles/FVehicleState
- https://dev.epicgames.com/documentation/en-us/unreal-engine/chaos-modular-vehicles-overview
- https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UActorComponent/SetAsyncPhysicsTickEnabled
- https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UPhysicsSettings
- https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/programming-subsystems-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/saving-and-loading-your-game-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UGameplayStatics/SaveGameToSlot
- https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UWorldSubsystem
- https://dev.epicgames.com/documentation/en-us/unreal-engine/data-assets-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/metasounds-reference-guide-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/MetasoundEngine/UMetaSoundBuilderBase/AddNodeByClassName
- https://dev.epicgames.com/documentation/en-us/unreal-engine/BlueprintAPI/Audio/MetaSound/Builder/BuildNewMetaSound
- https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/NiagaraFunctionLibrary
- https://dev.epicgames.com/documentation/unreal-engine/depth-of-field-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/cinematic-cameras-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/overview-of-advanced-multiplatform-user-interfaces-with-common-ui-for-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/MassZoneGraphNavigation
- https://forums.unrealengine.com/t/tutorial-legacy-your-first-60-minutes-with-mass/794314?page=3
- https://forums.unrealengine.com/t/chaosvehicles/1333154
- https://forums.unrealengine.com/t/chaos-vehicles-c/2630018
- https://forums.unrealengine.com/t/chaos-mover/2733017
- https://www.strayspark.studio/blog/chaos-vehicles-masterclass-shipping-racing-game-2026
- https://www.strayspark.studio/blog/crowd-traffic-simulation-ue5-mass-ai
- https://dev.to/fgrenoville/taming-chaos-stable-vehicle-suspensions-with-async-physics-in-ue5-319l
- https://unrealcommunity.wiki/revisions/6100e80d9c9d1a89e0c2fe1a

**H. Unreal Engine and Blender tooling: Python, automation, import, export**

- https://dev.epicgames.com/documentation/en-us/unreal-engine/scripting-the-unreal-editor-using-python
- https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-command-line-arguments-reference
- https://dev.epicgames.com/documentation/en-us/unreal-engine/run-automation-tests-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/using-live-coding-to-recompile-unreal-engine-applications-at-runtime
- https://dev.epicgames.com/documentation/en-us/unreal-engine/fbx-static-mesh-pipeline-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/FbxImportUI
- https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/InterchangeGenericAssetsPipeline
- https://docs.blender.org/api/5.0/bpy.ops.export_scene.html
- https://app.cinevva.com/guides/blender-to-unreal-export-checklist
- https://raw.githubusercontent.com/EpicGamesExt/BlenderTools/main/send2ue/dependencies/unreal.py

**I. Physics and photography reference (for derived design values)**

- https://www.magnopus.com/blog/lighting-in-unreal-with-photography-principles
- https://www.engineeringtoolbox.com/amp/tractive-effort-d_1783.html
- https://hpwizard.com/tire-friction-coefficient.html
- https://en.wikipedia.org/wiki/Lux
- https://en.wikipedia.org/wiki/Color_temperature
<https://en.wikipedia.org/wiki/Golden_hour_(photography)>

- https://en.wikipedia.org/wiki/Twilight

**Local verification (not URLs).** `W:\Unreal Engine 5\UE_5.8\Engine`: Landscape, LandscapeEditor, WorldPartition, Renderer (Lumen, fog), Chaos Vehicles plugin and ChaosVehiclesCore, PhysScene_Chaos and SceneQuery, PCG tests, Water, CascadeToNiagaraConverter, ZoneGraph and MassGameplay, PythonScriptPlugin, AutomationController, UnrealBuildTool, Interchange; project files `Config/DefaultEngine.ini`, `Sonnet55Forza.uproject`, `Intermediate/PythonStub/unreal.py`; `W:\Blender\5.2\scripts\addons_core\io_scene_fbx` and `io_scene_gltf2`.

---

## 5. FINAL FEATURE LIST (ranked by priority)

### 5.0 Conflicts between research agents and how the plan resolves them

| Topic | Conflict | Commitment |
|---|---|---|
| Landscape size | 4033 verts / 1024 components (WORLD_SPEC) vs 4065 / 256. | 4065 / 256 is primary, 4033 stays valid. It is a one-constant change in the world definition; update WORLD_SPEC, `world_meta.json` and the ZScale formula. |
| Vehicle model | Weather, cars and assist notes assumed Chaos setters; vehicle research and ARCHITECTURE choose a project-owned model. | Project-owned model. Chaos-specific advice is translated into requirements for our tire and driveline code (grip = load x surface x weather x tire; ABS/TC/stability as our own controllers). |
| Road geometry | Spline-mesh actors vs chunked ribbon meshes. | Chunked Nanite ribbon meshes (spline mesh only for throwaway prototypes). |
| Streaming radius | 768 m vs 1200-1600 m. | Terrain and roads always loaded; props stream; start at 1000 m with a look-ahead source, then tune by full-loop drive at top speed. |
| Regional weather | Weather cells (adapt) vs one global state (skip). | Staged: global state plus per-region multipliers first; moving storm cells later as a stretch. |
| Seasons | Skip vs adapt. | No weekly rotation. Optional static 4-value preset (snow line, tint, weather weights) as a late stretch. |
| Skill chain | Cap x5 and 3 s window vs x8 and 4 s. | x5 cap and 3 s window as tunable CVars. |
| Region layout | Research ring A-B-D-C vs WORLD_SPEC regions. | WORLD_SPEC owns the layout (Greenvale, Highcrest, Sunbaked Plateau, Saltcliff Coast, Crossroads hub); research supplies rules, not coordinates. |
| Console | Engine console vs custom `SRoamConsole`. | Engine console first; custom console as polish. |
| Moon light | About 0.26 lux vs 0.5-1.0 lux. | Start at 0.5 lux and tune by eye. |
| Car PI | CAR_ROSTER targets (300-850) vs the estimator prototype (360-918, S1 empty). | The estimator is authoritative once built; roster numbers are design targets. |
| PCG | Enabled in the `.uproject` but verdict SKIP for baseline. | Keep enabled, off the critical path. |
| Star thresholds | HUD research used 60 / 80 / 100 percent of target; activity research derived per-activity ratios (speed trap 0.28 / 0.69 / 1.0, speed zone 0.38 / 0.74 / 1.0, drift about 0.08 / 0.53 / 1.0, danger sign about 0.20 / 0.55 / 1.0). | Per-activity ratios win; 60 / 80 / 100 is only the fallback for any new activity type. |

### 5.1 The ranked list

1. **Stable C++ build and headless harness.** UE 5.8.2 editor target builds via `Build.bat` (baseline 63 s) with V7 strict warnings and the Unreal5_8 include order; modules `Sonnet55Forza` plus `Sonnet55ForzaEditor`. Fix `-NoHotReload` to `-NoHotReloadFromIDE`. Add GeometryScripting to the `.uproject`; leave ChaosVehicles off. Ini: `bTickPhysicsAsync=True`, `AsyncFixedTimeStepSize=1/60`, defined PhysicalSurfaces, software Lumen with `r.RayTracing` off (profile both modes first). Headless runs through PowerShell with forward-slash paths, `-unattended -nosplash -nullrhi -abslog -culture=en`, a timeout with process-tree kill, and exit-code handling (UBT 0/6/8/10; automation 255).
2. **One polished car imported and drivable.** Blender parts `Body`, `Wheel_FL/FR/RL/RR`, steering wheel, glass, lights, interior, `SOCKET_` hub empties, `UCX_` hulls; FBX recipe above; axis-test import in UE confirms 100 uu per metre, +X forward, wheel pivots at axle centres; data asset per car; paint material with gloss/matte/metallic.
3. **Driving model and camera.** Project-owned raycast/spring vehicle at a fixed 60 Hz async step (test 120 Hz): suspension with anti-roll, friction-ellipse tires with per-surface grip, engine/gearbox/diff per drivetrain, aero, ABS/TCS/stability, handbrake, CCD. Relative grip on dry asphalt = 1.00: dirt 0.78, gravel 0.80, grass 0.62, sand 0.55 (rolling resistance x10), mud 0.40, snow on asphalt 0.50, ice 0.30; concrete treated as asphalt. Camera set: chase with speed-dependent FOV and distance, hood, cockpit, bumper, free look, collision, shake. Scripted drive tests for 0-100 km/h, top speed, braking, skidpad, 250+ km/h stability, jump landing and off-road traction, results recorded in `DEVELOPMENT.md`.
4. **Landscape and the first long road.** 4065 x 4065 vertex landscape at 1 m (4064 m), 256 components, Nanite landscape, Landscape Grass, per-layer physical materials, World Partition map from the OpenWorld template with terrain and road chunks always loaded. Roads are carved into the heightmap first: road corridors 2-4 cm below the mesh surface, grade limits highway 6 percent, regional 9, mountain 12, dirt 14; minimum radius from R = v squared / (g x (mu + e)): about 580 m at 250 km/h, 330 m at 190, 130 m at 120. Pass: 450-550 m climb at about 7 percent mean grade over 6.5-8 km, hairpin radius 18-25 m. Verify with a scripted top-speed drive for floating roads and falling-through points.
5. **HUD basics, console and garage.** Slate HUD: 5 percent safe area; speed cluster bottom-right 480 x 200 with 104 px tabular digits, gear box, 48-segment tach and a row of surface and assist lamps (ABS, TCS, STM flash on intervention); minimap slot bottom-left 264 px; event bar top-centre 640 x 84; region popup top-left 560 x 88 (350 ms in, 2.8 s hold, 400 ms out, 80 m hysteresis); toast stack of at most 3 at 440 x 72 with 4 s hold; per-element toggles; km/h and mph. Engine console (tilde) with `cars`, `car`, `respawn`, `tp`, `time`, `weather`, `traffic`, `speed`/`fps`, `assist`, `paint`, `reset`, `help`. Garage menu with 10 cars, six stat bars and a class/rating chip (the code name is PI; the player sees "Rating"). Debug menu with teleports, spawn, time/weather, assists, telemetry, repair and flip-reset.
6. **Traffic foundation.** Custom lane graph from the road network, IDM car following in a tickable world subsystem. Cruise speed km/h: highway 90-110, valley 60-80, coastal 55-70, mountain 35-50, dirt 25-40, village 20-30, tractor 25 or less. Headway 1.3-2.0 s, minimum gap 2.5-5 m. Density per km per direction: highway 3.5, valley 2.5, coastal 2.0, mountain 1.2, dirt 0.4; night x0.35; rush hours x1.15-1.2; console scale 0..1. Rings: physics body under 120 m, kinematic 120-450 m, data only 450-900 m; spawn 500-750 m ahead and outside the frustum, despawn beyond 900 m, 40 live agents maximum. Kinematic cars switch to physics on impact. Six vehicle types (compact, van, lorry, bus, tractor, pickup), near-miss events, horns, junction tokens. Ambient life: livestock, birds, a rare crossing, 3-5 balloons, one plane.
7. **Remaining regions and the connected road network (40-60 km).** Four regions plus the hub with 200-400 m blended transitions. Road budget about 50 km: highway about 7 km, scenic loop 23-24 km (coast 4.5, valley 4.0, canyon 4.5, pass 7.0, descent 3.5), valley roads 6, dirt and gravel 9, spurs 5; WORLD_SPEC route targets must sum to 60 km or less. Speed limits from the spec: highway 100-130, regional 80, mountain 60, dirt 50, shortcut 40, village 30. Bridges and tunnels on the profile rules, guard rails, junction pads, signs. At least four 5 km+ fast stretches and one 20 km+ loop verified end to end.
8. **All 10 cars with handling profiles and sounds.** One data asset per car; classes D/C/B/A/S1/S2/X; PI = round(100 + 899 x Score^0.72) with Score = 0.22 SPD + 0.26 HDL + 0.22 ACC + 0.07 LAU + 0.13 BRK + 0.10 OFF (ratings normalised 0-10). Procedural engine synth (phase accumulator tied to cylinder firing, harmonic bank, intake noise, turbo, crackle, limiter) plus tire squeal per surface and wind. Compare estimator output against measured 0-100 and top speed per car.
9. **Day/night and weather with grip effects.** Sun at a constant physical level of about 120,000 lux at neutral 6500 K (the atmosphere does the reddening); sky light 1.0 at noon falling to 0.08 at night; exposure about EV100 14-15 at noon down to about -1.5..1.5 at night, never below -2; moon on atmosphere light index 1; time warp 1x by day ramping to 4x below -14 degrees sun elevation, about 32 real minutes per game day with 4-5 minutes of night; quantised sun updates for shadow caches. States: clear, cloudy, rain, fog, storm (plus snow by altitude and dust as a stretch). Grip multipliers (dry asphalt 1.00): asphalt damp/wet/soaked/snow 0.94/0.84/0.76/0.50; dirt 0.72/0.64/0.50/0.52; gravel 0.74/0.66/0.58/0.52; grass 0.52/0.44/0.38/0.45; speed term -17 percent at 130 km/h; puddle patches up to -55 percent with hydroplaning above about 40-110 km/h; tire-compound multipliers. Visibility to fog: FogDensity = 56.4 / visibility in metres (clear 20 km: 0.0028; light rain 4 km: 0.014; heavy rain 1.2 km: 0.047; storm 700 m: 0.081; ground fog 120 m: 0.47; dust core 45 m: 1.25; blizzard 80 m: 0.70). Traffic slows in bad weather; a non-clear state at least every 10 minutes.
10. **Settlements, roadside dressing, landmarks.** Modular kit from Blender (houses, barns, fences, signs, poles, bridges, portals, rails); WORLD_SPEC settlements (Millbrook, Frostholm, Tidewick, farms, gas stations, diners, lighthouse, castle, wind farm, viewpoints). Scatter by own deterministic generator through the foliage API or per-cell ISM actors, never one actor per prop; Nanite on all opaque props; ocean and lake water with the Water plugin; per-region reverb volumes; one landmark per region.
11. **Activities.** Placement budget about 80 items for a 50 km network: speed traps 10-12, speed zones 5-6, drift zones 4-5, jumps 5-6, races 6-8, time trials 1-2, plus about 40 billboards, 3 barns, 8 photo spots. Gates use segment-versus-plane crossing with sub-frame interpolation (a car at 270 km/h moves 1.25 m per frame at 60 fps). Scoring: speed trap V3 = 0.96 x min(Vcap, sqrt(v0 squared + 2 x 4 x run-up length)) with stars at 0.28 / 0.69 / 1.0 of V3; speed zone average = length / time with stars at 0.38 / 0.74 / 1.0 of 0.92 x the route-profile average, zones 0.8-2.5 km; drift zone: entry at slip angle 12 degrees or more and 30 km/h or more held 0.35 s, rate = 0.5 x min(speed, 140) x min(slip, 60) points per second, multiplier x1 to x5 (+1 per 2 s), 0.8 s transition window, a crash loses only the live chain, 3-star score S3 = 0.6 x nominal rate x (5T - 20) with T the nominal zone time (a 700 m zone gives about 5k / 37.5k / 70k); danger sign: 3-star distance = 0.85 x ideal ballistic range, stars at about 0.20 / 0.55 / 1.0, jumps 40-250 m, clean landing required; dirt sprint allowance A = 1.25 x profile time, 3 stars at 0.12 x profile time left; road race countdown with checkpoint bonuses; time trial on the loop with 2 km sector splits, medals from a curvature speed profile (lateral acceleration 7.5 m/s2, forward and backward passes) times a class factor, worked example gold 13:13 / silver 14:57 / bronze 17:15 for a 23 km loop, optional ghost at 10 Hz (about 170 KB). Notification channels: toast 2.5 s, banner 3.5 s, result card 5.0 s with stars popping at 0.9 / 1.25 / 1.6 s. Optional "Flow chain" (our name for the FH5 skill-chain idea; cap x5, 3 s timer). All thresholds are tunable CVars. Activities read the car through an interface and use only pawn position and velocity.
12. **Customisation, tuning, photo mode.** Three paint finishes, stripes, rim styles and colours. Upgrades: about 14 slots and 38 options with stat-preview deltas, evaluated in the order conversion, aero, tires, drivetrain, platform, engine, then tuning. Tuning: about 18 sliders (tire pressure F/R, final drive, gear spacing, camber and toe F/R, anti-roll, springs, ride height, damping, aero F/R, brake balance and pressure, AWD split). Assists: four presets and eight toggles. Photo mode: P key, pause, CineCamera pawn with 36 mm full-frame filmback and focal length 12-200 mm (field of view = 2 x atan(18 / f), about 104 degrees at 14 mm and 10 degrees at 200 mm), aperture f/1.2-22 with 4-16 blades, look presets with 6 user slots, guides, crops, time and weather presets, hide HUD with H, capture after 8-16 frames to `Saved/Photos`. Widen the default lens ranges first and give the free camera a streaming source.
13. **Minimap, full map, GPS.** Heading-up vector minimap over a baked 1024 x 1024 underlay; view radius grows from 350 m to 900 m with speed; player 18 percent behind centre; undiscovered road segments amber and marked discovered at 60 percent driven (60-100 segments of about 600 m). Full map pauses the game with 1x/2x/4x zoom, an all-toggle filter panel (saved), dimmed completed icons, snapped waypoint pin, free teleport to hubs after streaming settles. GPS: A* on the road graph with turn penalties, re-route at 35 m or 1.5 s, a 1.4 m wide cyan ribbon 0.12 m above the road showing the next 450 m, destination beam, edge-clamped marker, driving-line modes off / braking-only / full. No GPS voice.
14. **Save and load.** One `USaveGame` profile slot with plain data: current car, paint, upgrades, tuning, last transform, game hour, weather, settings, HUD toggles, map filters, personal bests and stars, discovered road segments, collectibles. Async save, graceful fallback to a road start when the saved position or dynamic objects are invalid.
15. **Polish.** Lighting and grading per condition, wet-road look and puddles sharing one data source with puddle physics, dust and spray particles (Niagara if the user-parameter spike succeeds, otherwise pooled ISM puffs), skid marks, per-region ambience and reverb, camera shake, tunnel exposure volumes, rewind, dust-storm cell, optional static season preset.
16. **Final QA and performance.** Build clean; main map loads; player spawns on road; all 10 cars selectable and drivable; console works; traffic, weather and day/night run; the loop driven end to end at top speed without hitching, falling through or leaked streamed actors; marked-WORKING activities behave; save/load round-trips; 60 FPS target with a 30 FPS floor on the RTX 5070 (check `stat unit` and `stat fps`); HLOD build only if needed; documentation (`DEVELOPMENT.md`, `FEATURE_MATRIX.md`, final report) completed with honest WORKING / PARTIAL / NOT IMPLEMENTED status.

### 5.2 Naming and branding rules for player-visible text

The research vocabulary above uses FH5 names so that sources can be traced. None of the branded names below may reach a menu, HUD string, asset name shown to the player, file name in a shipped build or video title card. The project title is *Roamline: Open Roads*; the brief itself lists speed traps, speed zones, drift zones, danger signs / jumps, photo mode and hidden cars as generic activity words, so those stay allowed.

| FH5 vocabulary (research only) | Player-visible replacement |
|---|---|
| Forza, Horizon, Playground Games, Microsoft, Xbox, Hot Wheels, Mexico and its place names | Never shown. Regions and hubs use the WORLD_SPEC names (Greenvale, Highcrest, Sunbaked Plateau, Saltcliff Coast, Crossroads). |
| PR stunt, Trailblazer | "Stunts" as a group; the off-road countdown event is an "Off-road Sprint". |
| Skill chain, skills, Ultimate Skill Chain | "Flow chain". |
| Performance Index (PI) | "Rating" with a class letter. Class letters D, C, B, A, S1, S2, X are a genre convention and stay as data labels. |
| Forza Edition, Wheelspin, Car Mastery, Accolades, Festival Playlist, Rivals, EventLab, Drivatar | Not used. Ghost runs are "Ghost time trial"; AI cars are "traffic" or "racers". |
| Barn find | "Hidden car". |
| Bonus board, Fast Travel board | "Billboard" (breakable); teleport is simply "Travel". |

Rule of thumb: if a term only makes sense to someone who has played FH5, give it an original name; if it is a plain road or racing word (finish line, checkpoint, speed trap, drift zone, photo mode, garage), it can stay.

---

## 6. Open risks and pitfalls

**Evidence and scope**

- FH5 absolute area, event distances, traffic behaviour, HUD timings, drift and skill formulas, grip and day length are unpublished. Every such value here is a design value: keep it as tunable data and calibrate by playtest.
- Several publisher and forum pages were unreadable, so a few specifics (assist credit bonuses, preset names, unlock rules) rest on snippets and conflicting fan guides.
- Activity multipliers stay uncalibrated until a reference bot or AI lap exists; drift zones need drift-capable handling on at least some of the 10 cars.

**Physics and vehicle**

- Smoke-test first: does `AsyncPhysicsTickComponent` fire with `bTickPhysicsAsync` in a `-game` run, is the physics-thread pose consistent, and what does the per-step sync cost at 60 versus 120 Hz? Also confirm wheel probes return physical materials for landscape layers and road overrides, and that the traffic kinematic-to-physics handoff carries velocity.
- Forces are cleared every step and a sleeping body ignores them (wake from the game thread); the step size is ini-only.
- Fast cars can outrun streamed collision (give the vehicle a streaming source). Jump ramps are physics-fragile: validate each with teleport runs for the lightest and heaviest car. Crest and sag curvature, stacked hairpins and bridges can float roads or drop cars through: verify by scripted full-loop drives.
- The PI estimator can drift from live physics: add drive tests comparing both.

**World and streaming**

- The C++ landscape wrapper and the runtime-hash edit are derived from headers and untested (check whether the template partition is named MainGrid or MainPartition).
- Nanite landscape: build time for roughly 16.5 M vertices, completion detection and the old >64-component bug need confirming on 5.8.2; headless Nanite or HLOD builds may need a real RHI.
- At 1 m spacing a shoulder or ditch is one or two vertices wide, so the road mesh must hide the seam. Landscape holes for tunnels are unverified (fallback: carved trench plus a Blender tunnel shell).
- Level Blueprint references force always-loaded actors. Water, Landmass, ChaosVehicles and Mover are experimental. A free photo camera or fast travel needs a streaming source and a wait, or the car falls through unloaded ground.

**Rendering and lighting**

- Hardware Lumen and `r.RayTracing` are on in this project and unprofiled on the target GPU; measure both modes.
- Substrate is on: test the clear-coat paint and script-made materials early.
- A warm sun temperature on top of SkyAtmosphere double-warms sunsets (keep about 6500 K); a very low minimum EV100 auto-brightens night into fake day; exposure references disagree (about 13 versus 15 at midday), so tune with the HDR eye-adaptation view.
- Cloud material parameter names come from an asset scan, and whether a volume material can read a parameter collection for storm masks is untested. Screenshots before Lumen and TSR settle are blurry.

**Tooling and pipeline**

- The axis and scale mapping is derived from source plus a Blender-side check; the UE-side axis test is still required, and translator settings must be pinned in config.
- Launch UE from PowerShell with forward-slash paths; never run Build.bat during Live Coding, beside a headless editor start, or with two editors on one project. `-ExecutePythonScript` exits 0 on script errors, so read log tokens and a result file.
- Unverified: `HighResShot` output timing in `-game`, new-level creation under `-nullrhi`, the return shape of the GeometryScripting asset call, and whether Niagara Python authoring can expose User parameters headlessly.
- Strict build settings turn warnings into errors and remove transitive includes; 5.8 object-type query masks are 64-bit and several older members are deprecated.

**Gameplay systems**

- At 250 km/h, traffic must spawn 500 m or more ahead and outside the frustum, and kinematic bodies must move with teleport type none so impacts carry velocity.
- Triggers must depend only on pawn position and velocity (an FH5 trap objective reportedly failed on tuned or painted cars); overlap volumes tunnel at speed.
- Photo mode under pause needs tick-when-paused flags and `bTriggerWhenPaused`; default lens ranges clamp focal length and aperture until widened. The engine console key collides with any custom console, and Slate text boxes swallow the toggle key.
- If sand or gravel is absent from the final map, drop their tire-pressure and surface entries.
- Open design questions: a traffic-suppression hook while an activity is active; barn finds unlocking cosmetics only (recommended); right-hand-only traffic in version one.
