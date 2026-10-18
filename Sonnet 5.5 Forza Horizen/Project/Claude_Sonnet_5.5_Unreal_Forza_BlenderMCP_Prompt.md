# Claude Sonnet 5.5 — Unreal Engine 5.8 + Blender MCP Forza-Horizon-Style Open-World Racing Benchmark

## Mission

You are the sole lead developer, technical artist and QA engineer of the **existing Unreal Engine 5.8 project in the project folder currently opened in this Claude agent**.

Your task is to build the most complete and polished **open-world arcade-sim racing game in the spirit of Forza Horizon 5** that you can achieve during this autonomous development session.

The game must be an **original project**. Use Forza Horizon 5 only as a *mechanics, structure and feature-scope reference*. Do not copy its maps, names, logos, car models, textures, audio, UI artwork, code or any proprietary content, and do not use Forza/Playground Games/Microsoft branding anywhere. Choose your own original game title.

The game launches directly into free roam in a drivable car on a long scenic road. There is no story and no campaign.

### The defining design pillars

1. **Long, beautiful countryside roads.** The map is a large open world dominated by **long rural and inter-regional roads** — highways, sweeping valley roads, mountain passes with switchbacks, dirt and gravel tracks, coastal roads, bridges and tunnels. It is **not** a city game. Only **small settlements** (villages, hamlets, farms, gas stations, a few roadside points of interest) are placed on the map.
2. **Map scale.** Target a playable world of roughly **4 km × 4 km (about 16 km²)** with **40–60 km of drivable road** in total, including at least one continuous scenic loop of **20 km or more**. This is deliberately much smaller than the real Forza Horizon 5 map, but far larger than a 600 × 600 m test map. Do not spend the session expanding beyond this footprint; spend it on road quality, driving feel, visual quality and traffic.
3. **A 10-car garage.** Exactly **10 distinct, Blender-authored cars** with different classes, silhouettes and handling profiles, selectable through an in-game **console / garage menu** (see Section 8).
4. **Living roads.** There must be **civilian road traffic** (see Section 9).
5. **Forza-like feel.** Accessible, fast, satisfying arcade-sim handling; a sense of speed; beautiful lighting, weather and time of day; a festival-like, optimistic presentation; discoverable activities scattered along the roads.

---

# 0. Research first — go to the internet

Before designing anything substantial, **use the web search / web fetch tools available to this agent to research Forza Horizon 5**. If no web tool is available in this session, say so explicitly in `RESEARCH_NOTES.md` and continue from your own knowledge.

Research at least:

- the structure of the open world: biomes, region variety, road types and how roads are used for events;
- the weather and season system and how weather changes driving and visibility;
- time-of-day presentation and lighting;
- road events and activities (road/dirt/cross-country races, speed traps, speed zones, drift zones, danger signs/jumps, collectibles, photo opportunities, festival hubs);
- the car roster structure, car classes, customization, tuning and upgrade systems;
- traffic, wildlife and ambient world life;
- HUD, minimap, waypoint and navigation conventions;
- photo mode and other presentation features;
- how driving assists (traction control, stability, ABS, racing line) are presented.

Then research the Unreal Engine 5.8 side where needed: Landscape and World Partition for large worlds, Chaos Vehicles (and whether a custom raycast vehicle is more suitable), PCG/foliage, Nanite and Lumen limits, Water, Niagara, MetaSounds, Enhanced Input and the Python editor scripting API. Prefer official documentation.

Write the results to **`RESEARCH_NOTES.md`** in the project folder:

- a feature inventory of Forza Horizon 5 as you understand it;
- for each notable feature: **ADOPT / ADAPT / SKIP** for this project, with a one-line reason;
- source URLs;
- the final feature list you commit to, ranked by priority.

Re-use the research when making design decisions later. Do not copy text from sources; summarize in your own words.

---

# 1. Existing project and environment

Work directly in the current project folder, which contains `Sonnet55Forza.uproject`. **Do not create another nested Unreal project.**

Known environment (verify each item, do not blindly trust):

```text
Project folder:   the folder currently opened in this Claude agent
                  (W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza)
Project file:     Sonnet55Forza.uproject
Engine:           Unreal Engine 5.8 (EngineAssociation "5.8")
Engine install:   W:\Unreal Engine 5\UE_5.8
C++ module:       Sonnet55Forza (Runtime) - this is a C++ project
Enabled plugin:   ModelingToolsEditorMode (Editor only)
IDE / toolchain:  Visual Studio Community (W:\Visual Studio) - verify that the C++ workload
                  and Windows SDK required by UE 5.8 are present before the first build
Git:              W:\Git\Git\cmd\git.exe (on PATH)
```

Technical defaults:

- **C++** for core gameplay systems (vehicles, traffic, world managers, subsystems, console commands). Use **data-driven assets** (`UDataAsset`, `DataTable`) for cars, tuning, events and settings.
- Prefer code and Python editor scripting over hand-authored Blueprint graphs, because Blueprints are binary assets and difficult to review and repair. Small, generated or well-contained Blueprint assets are acceptable if the available tooling can create and validate them reliably.
- **World Partition** for the large world, with a sensible cell/HLOD strategy.
- **Landscape** for terrain; roads built from splines (Landscape splines or custom spline-mesh road actors) with project-generated meshes/materials.
- **Nanite** and **Lumen** where they work reliably on the target machine; keep the project recordable at stable frame rates.
- **Enhanced Input** for controls, **UMG** (or Slate) for HUD and menus.
- Use Unreal's built-in plugins where they help (for example Chaos Vehicles, Water, PCG, Niagara, MetaSounds). Check in the 5.8 install that a plugin actually exists before relying on it, and enable plugins through the `.uproject`.

Do not require a packaged build. A working editor session and a working `-game` run are the baseline; a packaged build is a stretch goal.

## 1.1 How to drive the engine (autonomy)

Use the best available automation path, in this order:

1. If this session exposes an **Unreal Editor MCP / toolset** (for example the official Epic Claude Code integration, which needs the editor running with the `ModelContextProtocol` and toolset plugins enabled), use it for actors, assets, materials and automation tests. Do not register new MCP servers or change global/user settings yourself; if something must be enabled outside the project, report it as a blocker with the exact minimal step.
2. Otherwise use the command line: `UnrealEditor-Cmd.exe` with `-ExecutePythonScript=...`, editor commandlets, `-ExecCmds=...` and automation tests; `Build.bat` / UnrealBuildTool for C++ builds; `-game` runs with log capture and `HighResShot` screenshots.
3. Keep every setup step reproducible as a script checked into the project (for example `Tools/*.py`, `Tools/*.ps1`).

You are responsible for build errors, missing includes, asset path errors, shader compile errors and import problems. Do not ask me to click anything in the editor.

---

# 2. Blender MCP — mandatory

The user created the master Blender file and started a dedicated Blender instance for this project.

```text
Blender host:        localhost
Blender port:        9889
Master Blender file: ./UnrealSonnet5.5Forza.blend   (in the project folder)
MCP server name:     expected to be `blender-forza-unreal` (declared in this project's .mcp.json)
                     - still discover and verify the actual enabled connection
```

The Blender scene is expected to be an **empty default scene** at the start (another agent already confirmed the connection and found only the default scene). Everything has to be created by you.

## 2.1 Routing rule

Choose the actual MCP connection exposed to this agent that is configured for **`localhost:9889`**. Determine its identity from the available tool descriptions. Do not reuse a server that points at another port, and do not invent names.

Before making any Blender changes:

1. Record the session start time (Section 16) and resolve the project directory.
2. Confirm that `UnrealSonnet5.5Forza.blend` exists in that directory.
3. Identify the MCP connection configured for `localhost:9889`.
4. Execute a real read-only Blender MCP call: inspect the open scene and obtain the full path of the current `.blend` file through an available permitted read-only operation.
5. Confirm that this path is the exact `UnrealSonnet5.5Forza.blend` in the project folder. A listening port or a matching basename alone is not confirmation.
6. Back up the master file before its first modification. Record the verified server/tool namespace, endpoint and full file path in `DEVELOPMENT.md` and the final report.

For every subsequent Blender operation: use only this verified connection; treat `UnrealSonnet5.5Forza.blend` as the canonical editable source; preserve unrelated content; organize generated assets in clearly named collections; save the master file regularly; keep exports and backups separate from the master file.

If the Blender MCP tools are unavailable, a call fails or the opened file does not match, report the exact blocker and the minimum correction. Do not write to another Blender instance, do not silently replace Blender-authored assets with engine primitives, and do not claim a successful verification you did not perform.

Respect the connector's permissions and Safe Mode. Do not patch the add-on or bypass validation. Do not ask me to model, UV, rig, export, import or wire assets manually.

## 2.2 Blender visual QA loop

For every important hero asset (cars first):

1. model it through the verified Blender MCP connection;
2. create UVs and materials;
3. inspect it visually using viewport/render feedback and revise anything that looks broken, lumpy or placeholder-quality;
4. save the Blender source;
5. export it (Section 2.4);
6. import it into Unreal;
7. configure materials, collision, physics and gameplay components;
8. test it in the running game.

An asset is not finished because a file exists. It must look reasonable and work inside Unreal.

## 2.3 No external asset shortcuts

Do not depend on Fab / Unreal Marketplace packs, Quixel Megascans, Sketchfab, Poly Haven, Poly Pizza, AI 3D-generation services, ripped game assets or any downloaded character/vehicle/prop model. Create the important project-specific 3D assets yourself with Blender MCP and project-owned code. Engine built-in content, built-in plugins and procedurally generated project-owned textures, materials, meshes and audio are allowed. Engine primitive shapes may be used only as temporary stand-ins during development.

## 2.4 Blender → Unreal export pipeline

Create a reproducible pipeline:

```text
UnrealSonnet5.5Forza.blend -> Blender MCP edits -> save -> export FBX (or glTF where it validates better)
 -> /Game/Forza/Imported/... -> import (Python/commandlet/Interchange) -> materials, collision, Nanite flags
 -> data assets / Blueprints / C++ classes -> gameplay integration
```

- FBX is the primary interchange format for vehicles and skeletal assets in Unreal; glTF/GLB is acceptable for static meshes where Interchange imports it correctly. Validate per asset.
- Author at real-world scale (1 Blender unit = 1 m); verify the scale, axis orientation and pivots after import (Unreal uses centimetres, Z-up).
- Cars: body, **four separate wheel meshes with the pivot at the axle centre**, separate steering wheel, brake discs, lights, windows with a separate glass material, interior suitable for cockpit camera. Name parts consistently (for example `Body`, `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`).
- Collision: use proper simple collision (Blender `UCX_*` convex hull objects or collision generated in code); do not rely on per-poly collision for vehicles.
- Provide lower-detail variants / LODs for cars and props, or rely on Nanite where it is appropriate.
- Do not rely on the GUI for exports; automate them through the MCP and scripts. The master `.blend` is never loaded at runtime.

Organize the Blender file into clear collections, for example `FORZA_UE / Cars / Traffic / Props / Settlements / Roadside / Nature / Collision`. Avoid unnamed `Cube.001` objects in final assets.

---

# 3. Autonomy and workflow

I am not an Unreal Engine expert. Do **not** expect me to create levels, assign Inspector references, configure project settings, import assets, fix compile errors, set up materials or wire UI manually. Take ownership.

Before substantial work:

1. read this entire prompt and any local `CLAUDE.md`/`AGENTS.md`;
2. record the start timestamp (Section 16);
3. inspect the project, `.uproject`, config files, installed engine and toolchain;
4. verify the Blender connection (Section 2.1);
5. do the research (Section 0);
6. write a concise technical plan;
7. create `.gitignore` for Unreal (`Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`, `.vs/`, build outputs) and initialize Git with a baseline commit if the folder is not already under version control;
8. create `DEVELOPMENT.md`, `FEATURE_MATRIX.md`, `RESEARCH_NOTES.md` and `SONNET_5.5_FINAL_REPORT.md`.

Then work autonomously. Do not stop to ask for confirmation after each subsystem. If a feature becomes a deep blocker, preserve the working game, document the limitation, move to the next high-value feature and return later. Never claim an unfinished feature works.

---

# 4. The world

## 4.1 Regions

Create **at least four clearly distinguishable regions**, connected by roads, with different terrain shapes, vegetation, soil colours and lighting moods. Suggested set (choose your own names and layout):

1. **Rolling farmland and forest valley** — gentle hills, fields, hedgerows, a river with bridges, a village.
2. **Mountain highlands** — a long climbing pass with hairpins, cliff edges, a tunnel, a viewpoint, snow or alpine vegetation at the top.
3. **Arid canyon / desert plateau** — wide fast roads, mesas, dust, dirt shortcuts, a gas station.
4. **Coastal cliffs and beach road** — sea, cliffs, a long bridge, a small harbour hamlet.
5. Optional: lake district, vineyard terraces, wetlands.

## 4.2 Roads

- A connected network, not isolated strips: highways (fast, wide), regional roads, winding mountain roads, dirt/gravel tracks and a few cross-country shortcuts.
- Proper road construction: lane markings, shoulders/curbs where appropriate, banked corners, bridges, tunnels, guard rails, signs, reflectors, posts, culverts. Roads must follow the terrain convincingly (cuttings and embankments rather than floating strips).
- Intersections that traffic can use.
- Several **long uninterrupted stretches** (5 km+) that are fun to drive at speed, with varied scenery and landmarks.
- Surface types with distinct physics and audio: asphalt, concrete, dirt, gravel, grass, sand, wet asphalt.

## 4.3 Settlements and points of interest

Only small settlements: villages, hamlets, farms, a harbour, a couple of gas stations, roadside diners, a ruined castle, a wind farm, a lighthouse, etc. Build reusable modular kits in Blender (houses, barns, fences, signs, poles, bridges, tunnels portals, guard rails). Do not build a large city.

## 4.4 Nature and dressing

Project-owned trees, bushes, rocks, grass, flowers, crops; roadside props and signs. Use instancing/foliage/PCG/Nanite appropriately. Cohesive silhouettes and sensible LODs matter more than quantity.

## 4.5 Sky, lighting, weather, time of day

- Full **day/night cycle** (sunrise, day, sunset, night) with street/vehicle lights.
- Weather states: **clear, cloudy, rain, fog, storm**; weather affects sky, lighting, visibility, particles, wet-looking surfaces and **tire grip**.
- Optional: seasons or a biome-dependent weather rule (for example dust in the desert, snow at altitude).

---

# 5. Vehicle physics and driving feel — the core of the game

This is the most important system. A beautiful world is worthless if the car does not feel good.

- Choose and justify the approach after prototyping: Unreal **Chaos Vehicles** (`ChaosVehicles` plugin) or a **project-owned raycast/spring vehicle** in C++. Test both quickly if unsure, keep the one that is stable and fun at 250+ km/h and in drifts.
- Required: steering with speed-sensitive reduction, throttle, brake/reverse, handbrake, engine with RPM/gear (automatic gearbox at minimum; manual optional), differential behaviour per drivetrain (FWD/RWD/AWD), suspension with weight transfer, tire grip model per surface, aerodynamic downforce/drag, anti-roll, body roll and pitch, wheel spin and wheel rotation visuals, brake lights, headlights, reverse lights, horn.
- Surface and weather response: grip changes on asphalt/dirt/gravel/grass/sand and when wet; dust and tire smoke particles; skid marks or decals where practical.
- Assists with in-game toggles/console commands: traction control, stability control, ABS, steering assist, braking line help (optional), auto/manual gearbox, rewind (stretch).
- Collisions: believable impact response, stability after landing from jumps, damage as a bonus (visual deformation or simple damage states); the car must be recoverable (reset-to-road command).
- Handling data must be **data-driven**: one data asset per car with mass, centre of mass, power/torque curve, gear ratios, drivetrain, tire grip curves per surface, suspension stiffness/damping, downforce, brake bias, steering lock, top speed, etc.
- Verify with automated drive tests (scripted inputs): 0–100 km/h time, top speed, braking distance, skidpad grip, stability at high speed, jump landings, off-road traction. Write the numbers in `DEVELOPMENT.md`.

Camera: chase camera with speed-dependent FOV and distance, hood camera, cockpit camera (interior), bumper camera, free look, smooth transitions, camera collision, subtle shake at speed and on impacts.

Audio: procedural/project-owned engine sound driven by RPM and load (MetaSounds or generated samples), turbo/blow-off, gear shifts, tire squeal per surface, wind at speed, suspension thumps, impacts, ambient sound per region. No copyrighted audio.

---

# 6. The garage — exactly 10 original cars

Create **10 distinct cars** with different silhouettes, proportions, drivetrains and handling. They must be original designs, not copies of real cars, and carry no real manufacturer names or logos.

Suggested class spread (adapt as you like):

1. compact hot hatch (FWD);
2. everyday sedan;
3. classic muscle car (RWD, powerful, tail-happy);
4. sports coupe (RWD);
5. grand tourer (front-engine, fast, stable);
6. mid-engine supercar (AWD or RWD);
7. rally car (AWD, great on gravel/dirt);
8. off-road SUV (tall suspension, rough-road capability);
9. pickup truck (heavy, body roll);
10. vintage roadster/classic (light, slow, charming).

Each car needs: a quality Blender-authored body (with visible detail and believable proportions), separate wheels, windows, lights, an interior for the cockpit view, a handling data asset, an engine sound profile, a performance-class label and a paint system (primary colour plus finish: gloss / matte / metallic).

Do **not** fake breadth: a car is listed only if it is drivable with its own model and handling. Never scale one mesh to pretend to be another car.

---

# 7. Customization, tuning and photo mode (high value, after driving is solid)

- **Paint**: primary colour, finish, optional stripes/livery variants; wheel/rim styles and colours.
- **Upgrades** with real gameplay effect (engine, tires, suspension, brakes, weight reduction, aero), shown as data-driven upgrade definitions and visible in a stat comparison.
- **Tuning**: gearing, tire pressure, alignment, spring/damper/anti-roll, aero, brake bias (a reduced set is fine).
- **Photo mode** (stretch): free camera, field of view, depth of field, time-of-day and weather freeze, hide HUD, screenshot key.

---

# 8. Console, garage menu and benchmark/debug menu — mandatory

The user wants to pick cars through a console. Implement both:

1. An **in-game developer console** (toggle with the backtick/tilde key, plus an on-screen hint) with commands at least such as:
   `cars` (list), `car <index|name>` (switch/spawn at current location), `respawn`, `tp <region|poi>`, `time <hour>`, `weather <state>`, `traffic <0..1>`, `speed`/`fps` toggles, `assist <name> on|off`, `paint <colour>`, `reset`, `help`.
2. A **graphical car-select / garage menu** (toggle key such as `F1` or `Tab`) listing all 10 cars with stats, so a viewer sees the roster in a video.
3. A **benchmark/debug menu** that makes the project easy to demo on YouTube: teleport to each region and to long-road start points, spawn any car, set time and weather, toggle traffic and density, toggle assists, show FPS/coordinates/speed, repair and flip-reset, and show telemetry (RPM, slip, surface).

These are testing tools; they must not break normal free-roam play.

---

# 9. Traffic — mandatory

Create believable **civilian road traffic** across the road network:

- a road/lane graph built from the road splines, with direction of travel, lanes, speed limits per road class and intersections/priorities;
- vehicles that follow lanes, keep safe following distance, brake for obstacles including the player, slow for corners, stop/give way at intersections, and optionally overtake on long roads;
- a mix of several **distinct traffic vehicle types** (for example small car, van, lorry, bus, tractor on farm roads, pickup), authored in Blender; they may be simpler than the player cars;
- density scaling by region/time of day and via the console;
- spawn/despawn around the player outside the camera view, pooling, simulation LOD (full physics near the player, simplified kinematic movement at distance, nothing far away);
- reaction to collisions (physics response when hit, then recover or become a stopped obstacle that despawns later), horn/flash feedback;
- parked cars and a few rest areas as stretch features.

Traffic must not tank performance and must not make the long scenic roads feel empty or crowded; tune density deliberately.

---

# 10. Activities on the roads (after driving and traffic work)

Forza-like discoverables, started simply by driving through them, with score/time and a HUD notification. Implement as many as are robust, in this order:

1. **Speed traps** — measure speed through a gate, show a score and a personal best.
2. **Speed zones** — keep average speed over a stretch.
3. **Drift zones** — a scored drift section.
4. **Danger signs / big jumps** — long jump or distance scoring.
5. **Checkpoint road races** along the long roads (start gate, checkpoints, timer, optional simple AI opponents as stretch).
6. **Time trials** on the scenic loop.
7. **Collectibles / photo spots / hidden cars** as stretch.

No story missions, no dialogue. Keep a simple persistent score/credits economy as a stretch goal only.

---

# 11. HUD, map and navigation

- Speedometer (km/h and mph option), tachometer, gear, current surface/assist indicators, region name popups, event notifications.
- **Minimap** with roads and your position/heading; **full map** (stretch) with regions, events and waypoint; **GPS route line** on the road (stretch).
- Clean, original, modern UI; responsive layout; readable at video resolution. Do not copy Forza UI artwork.

---

# 12. Performance and world streaming

- Target a stable **60 FPS** at reasonable recording settings on the user's machine, with 30 FPS as the floor; verify with `stat unit`/`stat fps` captures.
- World Partition with a streaming radius appropriate for high speed; HLOD/distance culling; Nanite for rock/foliage/building meshes where it helps; sensible Lumen settings; avoid per-actor tick spam; pool traffic and effects; avoid unbounded physics objects.
- Verify there is no visible hitching when driving the full loop at top speed, and no duplicate/leaked streamed actors.

---

# 13. Save/load and settings

Persist at least: current car and paint/upgrades, position, time of day, weather, settings, personal bests. Recover gracefully when dynamic objects are not persisted.

---

# 14. Priority order

This project is broad. Follow this order and **do not stop early**:

1. stable C++ project, builds and launches into a test map;
2. verified Blender MCP pipeline with one polished car imported and drivable;
3. driving model and chase camera that feel good;
4. large landscape with the first long road and the first region;
5. HUD basics and console/garage menu for switching cars;
6. traffic foundation on the first roads;
7. remaining regions and the connected road network (40–60 km);
8. all 10 cars with their handling profiles and sounds;
9. day/night cycle and weather with grip effects;
10. settlements, roadside dressing, tunnels, bridges, landmarks;
11. activities: speed traps, drift zones, jumps, races;
12. customization, tuning, photo mode;
13. minimap/map/GPS;
14. save/load;
15. polish pass: lighting, materials, VFX, audio, camera;
16. final QA, performance pass and documentation.

A strong first milestone: one polished car, a drivable stretch of landscape road, a good chase camera, HUD, the console switching between at least two cars, and basic traffic.

---

# 15. Quality, QA and documentation

## 15.1 Honest status

Use only `WORKING`, `PARTIAL` or `NOT IMPLEMENTED` in `FEATURE_MATRIX.md` (columns: Feature | Status | Notes). Only mark `WORKING` if there is a functional in-game path. Label decorative-only assets clearly. Do not populate menus with features that do not work.

## 15.2 Continuous QA

Continuously: build the C++ project, launch the editor/commandlet, read the log, fix errors/warnings that matter, run automation/drive tests, test gameplay in `-game`, capture screenshots of key views, verify imported assets (scale, orientation, wheel pivots, materials, collision), check missing references, and re-test traffic and streaming. Do not wait until the end to discover the project does not load.

## 15.3 Final validation

Before declaring completion verify at least: the project builds; the main map loads; the player spawns in a car on a road; all 10 cars are selectable and drivable; the console works; traffic runs; weather and day/night work; the long loop can be driven end to end without falling through the world; activities that are marked WORKING behave; Blender assets import and display correctly; no major missing materials; save/load works at a basic level; performance is acceptable for recording.

## 15.4 Asset-quality gate

Visually inspect the game and reject unintentional placeholder content. Prioritize authored, finished versions of: the player cars, road surfaces and road furniture, the main landmarks, traffic vehicles, vegetation, settlements. Document anything left unfinished.

## 15.5 Required documents

- **`DEVELOPMENT.md`** — engine version, plugins and toolchain, architecture, systems, controls, map layout, Blender workflow, build/run instructions, known limitations, drive-test numbers.
- **`FEATURE_MATRIX.md`** — status table described above.
- **`RESEARCH_NOTES.md`** — the Forza Horizon 5 research and adopt/adapt/skip decisions.
- **`SONNET_5.5_FINAL_REPORT.md`** — what was built, what works, what is partial, known bugs, controls, build result, Blender assets, car roster, map regions, traffic implementation, performance notes, and the metrics block from Section 16.

Make meaningful Git milestone commits (baseline, first car, driving model, landscape + road, traffic, regions, cars, weather, activities, final). Never commit `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/` or generated caches.

---

# 16. Session timing, token accounting and API-equivalent cost — mandatory

These metrics will be shown in a YouTube video about Claude Sonnet 5.5. Measure **only this Claude Sonnet 5.5 Unreal Forza project**. Do not include other sessions or projects, and **do not fabricate precision**.

## 16.1 Development time

At the very beginning, before substantial work:

1. read the current operating-system timestamp with its timezone;
2. create a unique run directory and save the start time to `.sonnet-5.5-forza-unreal-runs/<run-id>/start_time.txt`;
3. keep that run ID and start time unchanged for the whole task.

After the final validation and report preparation, read the timestamp again and save it to `end_time.txt` in the same directory. Compute the elapsed wall-clock time. If work is resumed, append identifiable segments instead of overwriting the original start; report known pauses separately; never sum overlapping tool/subagent durations.

## 16.2 Tokens

Obtain real usage from the runtime in which you are actually running (session usage metadata exposed by the agent or host, a usage record of this exact session, or the permitted local usage log identified reliably by session ID, working directory and timestamps). Read only relevant usage metadata; do not copy credentials or unrelated conversations into the repository.

Use mutually exclusive categories (uncached input, cache-read, cache-write, output; thinking/reasoning tokens only if separately exposed). Do not subtract cache usage from an already-uncached count and do not double count. Deduplicate events by request/message identity. A missing counter is **unknown**, not zero. Do not estimate tokens from code size, asset size, tool-call counts or elapsed time. Identify delegated subagent work separately and record the actual model of each part. If exact usage cannot be obtained, write exactly: `Exact token usage unavailable from the accessible runtime.`

## 16.3 API-equivalent price

Compute the **token-only API-equivalent cost in USD** from the verified usage using the **official Anthropic pricing for the model you actually ran as** (Claude Sonnet 5.5; verify the model identifier exposed by the session), at standard API pricing, from `https://platform.claude.com/docs/en/about-claude/pricing`. Record the source URL, verification date and the formula used. This is a benchmark equivalent, not the user's subscription payment or credits. If usage, model identity or pricing cannot be verified, say so and give a clearly labeled partial figure or "unavailable".

---

# 17. Start now

Begin immediately:

1. record the start timestamp and run ID;
2. inspect the Unreal project, engine and toolchain;
3. verify the Blender MCP connection on `localhost:9889` and the master file;
4. research Forza Horizon 5 and write `RESEARCH_NOTES.md`;
5. write the plan, then build the game autonomously.

Remember:

**This is an original open-world arcade-sim racing game in the spirit of Forza Horizon 5, built on Unreal Engine 5.8, with long countryside roads, a 10-car garage selectable via console, and civilian traffic.**

**Use only the verified Blender MCP connection on `localhost:9889` with `UnrealSonnet5.5Forza.blend` in the project folder, and use it actively for every important 3D asset.**

---

# 18. FINAL REQUEST — time, tokens and API-equivalent cost (do this last)

When the game, the documentation and all validation are finished, **calculate and report the following three numbers for this project**, following Section 16 exactly:

1. **Time spent on the project** — the wall-clock duration between the start timestamp you saved at the very beginning and a fresh end timestamp, as `HH:MM:SS` plus total minutes; report known pauses separately.
2. **Number of tokens** — real usage of this session (uncached input, cache-read, cache-write, output, thinking if separately exposed, and a deduplicated total), or the exact sentence `Exact token usage unavailable from the accessible runtime.`
3. **Price in API-equivalent US dollars** — the token-only cost from the verified usage at the official Claude Sonnet 5.5 API price, or an explicit statement that it is unavailable.

Put them into this block at the bottom of `SONNET_5.5_FINAL_REPORT.md` **and** state them in your final chat message, each marked as measured, estimated or unavailable:

```text
## Claude Sonnet 5.5 Unreal Forza Session Metrics

Project: Unreal Engine 5.8 Forza-style open-world racing game
Run/session identifier:
Working-directory full path:
Start timestamp and timezone:
End timestamp and timezone:
Elapsed wall-clock time (HH:MM:SS):
Elapsed minutes:
Known pauses / resumed segments:

Requested model: Claude Sonnet 5.5
Actual model identifier(s):
Input tokens (state whether uncached or inclusive):
Cache-read tokens:
Cache-write tokens:
Output tokens:
Thinking/reasoning tokens (included / separate / unavailable):
Deduplicated total tokens:
Usage source and observation cutoff:
Unmeasured work / limitations:

Token-only API-equivalent cost (USD):
Official pricing source, verification date and tier:
Rates and formula used:
Measured / estimated / unavailable, with reasons:

Blender MCP server/tool namespace actually used:
Blender host: localhost
Blender port: 9889
Blender master file: UnrealSonnet5.5Forza.blend
Verified full path of master file:
Approximate number of major Blender assets created:
```
