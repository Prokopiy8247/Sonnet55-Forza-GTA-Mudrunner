# FEATURE_MATRIX.md - Roamline: Open Roads

Status vocabulary: **WORKING** (a functional in-game or automated path exists and was exercised), **PARTIAL** (implemented but limited or only partly verified), **NOT IMPLEMENTED**. "Verified" means a test, log or screenshot, named in the Notes column. QA addendum (real-world runs) is at the bottom.

| Feature | Status | Notes |
|---|---|---|
| C++ project builds (editor + game targets) | WORKING | both targets build; `Tools/build_editor.ps1`; own code warning-free |
| Automation tests | WORKING | `Automation RunTests Roam`: 55 tests pass (console, road network, time/weather, sky, traffic, activities, UI, menus, save, vehicle drive tests) |
| Blender MCP pipeline (Blender -> FBX -> Unreal) | WORKING | verified endpoint localhost:9889 + master file; 16 vehicles import with 952 validation checks, 0 failed |
| 10 distinct Blender-authored cars | WORKING | all 10 built, reviewed by an independent critic (PASS), imported with UCX hulls, materials and data assets; interiors/glass/lights/wheels as separate parts; art quality is "clean procedural", not hand-sculpted |
| Per-car data assets (handling, class, PI) | WORKING | `DA_Car_*` + `DA_CarCatalog`; PI by deterministic estimator; tuned numbers from drive tests |
| Vehicle physics (raycast/spring on Chaos body, tyres, drivetrains FWD/RWD/AWD, aero, assists) | WORKING | automated drive tests (0-100, top speed, braking, skidpad, 250 km/h stability, jump, surfaces, wet, drift, assists) pass; see QA addendum for real-mesh/real-map results |
| Surface + weather grip (asphalt/dirt/gravel/grass/sand, wet) | WORKING | per-surface tyre grip x weather multiplier; wet braking x1.45; physical materials on landscape layers and road chunks |
| Camera (chase, hood, cockpit, bumper, free look, collision, FOV/shake) | PARTIAL | implemented (`URoamCameraRig`); exercised in smoke runs, see QA addendum |
| Procedural engine/tyre/wind audio | PARTIAL | `URoamEngineSynth` (USynthComponent, RPM-driven harmonics); no listening test was possible in this environment |
| Vehicle visuals (wheel spin/steer, brake/head/tail lights, paint finishes gloss/matte/metallic + stripes) | WORKING | material parameter contract implemented; showroom screenshots of all cars |
| Vehicle FX (dust/smoke/skid marks) | PARTIAL | hooks and pooled FX component exist; limited effects |
| Damage / rewind / photo mode / full map / GPS route | NOT IMPLEMENTED | photo (`P`) and map (`M`) keys are mapped to stubs only |
| Large world 4 x 4 km, World Partition, Nanite landscape | WORKING | 4065 x 4065 landscape, 17 actors, 256 m cells, 124-130 fps average on RTX 5070 at 1920x1080 |
| >= 4 distinct regions + hub | WORKING | Greenvale, Highcrest, Sunbaked Plateau, Saltcliff Coast, Crossroads; blended soil layers/vegetation |
| Road network 40-60 km with a 20+ km loop | WORKING | 45.6 km, loop 23.1 km closed, 5.5 km highway, 22 bridges, 1 tunnel, 9 hairpins; grade/radius limits verified by independent recomputation |
| Road geometry (surface, lane markings via material, shoulders, bridges, tunnel, junction pads) | WORKING | 217 Nanite chunks with complex-as-simple collision; wheel probes hit road meshes (83 probes, 42 bridge-deck samples, 3 tunnel-floor samples, 0 missed) |
| Landscape holes for tunnel mouths | PARTIAL | visibility-layer holes work (mouths open); portal head-wall does not fully cover the hole (cosmetic) |
| Settlements, roadside furniture, nature props | WORKING | 87 buildings + 7 rotors, 60.6k trees, 106.7k ground-cover instances, 12.6k roadside pieces applied to L_Main; no per-prop visual review was done |
| Water / sea | PARTIAL | sea is a large water-material plane at z=0 (Water plugin ocean not used); no rivers rendered as water bodies |
| Day/night cycle | WORKING | `ARoamSkyManager`: sun/moon/atmosphere/clouds/fog/sky light/exposure; `time <hour>` |
| Weather (clear, cloudy, rain, fog, storm) with grip/visibility effect | WORKING | rain streak FX, lightning, fog, wetness MPC read by road/landscape materials; unit + screenshot verified on the test map, see QA addendum for L_Main |
| Street/vehicle lights at night | WORKING | `OnLightsSignal` + emissive light materials on cars |
| Civilian traffic (lane graph, IDM, junctions, pooling, rings, collision reaction) | WORKING | 6 vehicle types; automation tests + smoke runs (about 20 agents, 4 physics-ring actors); see QA addendum for the real network |
| Activities: speed traps, speed zones, drift zones, danger-sign jumps, checkpoint races, time trial | WORKING | gate-crossing logic with sub-frame interpolation, scoring, stars, personal bests, runtime placement on the real network; jumps need a crest, see QA addendum |
| Collectibles / photo spots | PARTIAL | markers and counters; no photo-mode integration |
| HUD (speedometer km/h or mph, tach, gear, surface, assist lamps, region popups, notifications, event bar, world strip) | WORKING | Slate; screenshots at 1920x1080 |
| Minimap | WORKING | heading-up, speed-dependent radius, road classes; drawn from the real DA_RoadNetwork (see QA addendum) |
| Console (`~`) with required commands | WORKING | Slate overlay with history + autocomplete; commands list in DEVELOPMENT.md; live keyboard input only partly tested |
| Garage / car select menu (F1/Tab) | WORKING | 10 cars, class badge + PI, six stat bars, paint tab; keyboard flow untested |
| Benchmark/debug menu (F2) | WORKING | teleports, spawn car, time/weather/traffic, assists, FPS/coords/speed overlays, repair/flip, telemetry; mouse-driven |
| Customization: paint + finish + stripes | WORKING | applied through material parameters |
| Customization: upgrades | PARTIAL | slots + stat preview + saved tiers; physics hook is a stub, no credits |
| Tuning sliders (gearing, alignment, springs, aero, brake bias) | NOT IMPLEMENTED | data fields exist in the car definition; no UI |
| Save / load profile (car, paint, tuning, position, time, weather, settings, personal bests) | WORKING | integrity-checked `USaveGame`; round-trip tests; see QA addendum for in-game restart test |
| Persistent settings (units, HUD toggles, volume) | PARTIAL | pause-menu settings stored in the profile |
| Seasons, wildlife, ambient life (balloons, planes) | NOT IMPLEMENTED | skipped for scope (see RESEARCH_NOTES.md) |
| HLOD / packaged build | NOT IMPLEMENTED | editor + `-game` only; landscape and roads are always loaded, props stream |

## QA addendum (real-world integration runs on L_Main, final pass)

| Check (on the real map) | Status | Evidence / limits |
|---|---|---|
| Player spawns in a car on the loop road, HUD + minimap with the real road network | WORKING | `ROAM_SPAWN_SOURCE WorldPoi`, region popup, minimap draws `DA_RoadNetwork`; spawn was moved off the 0.8 m highway median barrier (`SnapOffMedian`) |
| All 10 cars selectable and drivable (real meshes) | WORKING | `cartest` on L_Main: 10/10 sit on their wheels (hub height = tyre radius, 4 wheels loaded, left/right load within 2 %); sleeping-body and mass/inertia bugs fixed; wheel steer/spin/steering-wheel/brake lamps/paint verified by telemetry read-back |
| Cockpit camera | PARTIAL | no clipping on cars 1 and 6; roof lining close, interior texture coarse |
| Autopilot (`autodrive on/off [kmh]`) | PARTIAL | HWY_EAST 5.34 km at 150 km/h: avg 131 km/h, 0 stuck / 0 off-road / 0 fall, lateral error < 1.3 m; fails at some junctions / crest kinks |
| Scenic loop driven end to end | PARTIAL | NOT driven fully: one 24 km run finished only with 26 teleport recoveries; the junction-pad step that stopped cars at LOOP_COAST s~675 was removed afterwards (X-pads made visual-only) but the loop was not re-run to completion; sharp crests (12 m vertical radius on LOOP_PASS/LOOP_DESC) throw cars airborne at 60 km/h; guard rails and a rock mesa block cars that cut hairpins; autopilot turns into the dead end at Tidewick |
| 250+ km/h on the real highway | PARTIAL | Aether peaked at 221 km/h on HWY_EAST (road kinks / weaving of +-5-10 m); stable at 250 km/h on the flat test map |
| Frame rate | WORKING | 98-112 fps with 17-31 traffic agents at 1080p (Crossroads 107, Tidewick 98, summit 102, highway 112); 124-130 fps without traffic; 24 km autopilot run avg frame 9.4 ms, p99 18.7 ms, 18 hitches > 250 ms (max 853 ms, World Partition streaming) |
| Day/night + weather on L_Main | WORKING | `time 6/12/19/23`, `weather rain/storm/fog/clear` visible; sky manager replaces the level's plain lights (no double sun); wetness MPC shows puddles/reflections on roads; night/dusk exposure fixed; player headlights added |
| Traffic on the real network | WORKING | 22/22, 26/26, 19/19 agents on the correct side with none floating; six vehicle types with real meshes and wheels; a stopped pickup hit at 16.4 m/s reacted physically; about 1 in 22 agents had a ground hit 1.6-2.3 m high (probably under an overpass) |
| Activities on the real network | WORKING | 36 generated (12 traps, 5 zones, 4 drift, 6 races, 1 time trial, markers on the road); speed trap driven through at 158 km/h: 2 stars, NEW BEST, result card, personal best saved; speed-zone event bar verified |
| Menus on L_Main | WORKING | console, garage (10 cars, paint applied), debug teleports, pause screenshotted; real key presses to menus were not sent |
| Save / load across restart | WORKING | car, paint, 07:30, rain, last position and personal bests restored (`ROAM_SPAWN_SOURCE SavedTransform`); `resetprofile` returns defaults |
| Standalone game build (exe) | WORKING | `Tools/package_game.ps1` -> `Packaged/Windows/Sonnet55Forza.exe` (Development, 1.5 GB, git-ignored); test launch: L_Main loads in 6.9 s, car spawns, HUD visible; `Play_Roamline.bat` starts it |
